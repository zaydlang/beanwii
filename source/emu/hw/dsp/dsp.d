module emu.hw.dsp.dsp;

import emu.hw.ai.ai;
import emu.hw.broadway.interrupt;
import emu.hw.dsp.accelerator;
import emu.hw.dsp.jit.jit;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import ui.device;
import util.bitop;
import util.number;
import util.log;
import core.thread;
import core.sync.mutex;

final class DSP {
    Scheduler scheduler;
    InterruptController interrupt_controller;
    Mem mem;
    AudioInterface audio_interface;

    DspJit jit;
    DspState dsp_state;
    DSPAccelerator accelerator;
    
    private EventID aid_interrupt_event_id;
    private EventID update_event_id;
    
    // DSP DMA registers
    private u16 dma_control_reg = 0;    // DSCR (0xFFC9)
    private u16 dma_block_length = 0;   // DSBL (0xFFCB)
    private u16 dma_dsp_address = 0;    // DSPA (0xFFCD)
    private u16 dma_mm_addr_high = 0;   // DSMAH (0xFFCE)
    private u16 dma_mm_addr_low = 0;    // DSMAL (0xFFCF)

    this() {
        jit = new DspJit();
        jit.set_dsp_instance(this);
        dsp_state = DspState();
        accelerator = new DSPAccelerator();

        dsp_state.wr[0] = 0xffff;
        dsp_state.wr[1] = 0xffff;
        dsp_state.wr[2] = 0xffff;
        dsp_state.wr[3] = 0xffff;
    }

    void connect_scheduler(Scheduler scheduler) {
        this.scheduler = scheduler;
    }

    void connect_interrupt_controller(InterruptController interrupt_controller) {
        this.interrupt_controller = interrupt_controller;
    }

    void connect_mem(Mem mem) {
        this.mem = mem;
        accelerator.connect_mem(mem);
    }

    void connect_audio_interface(AudioInterface audio_interface) {
        this.audio_interface = audio_interface;
    }

    u8 read_DSP_MAILBOX_FROM_LOW(int target_byte) {
        if (dsp_state.phase == DspPhase.Running) {
            u8 result = cast(u8) ((dsp_state.dsp_mailbox_lo >> (target_byte * 8)) & 0xFF);
            
            if (target_byte == 1) {
                dsp_state.dsp_mailbox_hi &= ~0x8000;
                resume_from_idle_loop();
            }

            log_dsp("Read DSP_MAILBOX_FROM_LOW[%d] -> 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, result, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return result;
        } else {
            log_dsp("Read DSP_MAILBOX_FROM_LOW[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return 0;
        }
    }

    u8 read_DSP_MAILBOX_FROM_HIGH(int target_byte) {
        if (dsp_state.phase == DspPhase.Bootstrap || dsp_state.phase == DspPhase.AcceptingMicrocode) {
            u8 result = dsp_state.dsp_mailbox_hi.get_byte(target_byte);
            if (target_byte == 1) {
                dsp_state.dsp_mailbox_hi ^= 0x8000;
            }
            log_dsp("Read DSP_MAILBOX_FROM_HIGH[%d] -> 0x%02x (%s) (PC=0x%08x LR=0x%08x)", target_byte, result, 
                   dsp_state.phase == DspPhase.Bootstrap ? "Bootstrap" : "AcceptingMicrocode",
                   interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return result;
        } else if (dsp_state.phase == DspPhase.Running) {
            u8 result = dsp_state.dsp_mailbox_hi.get_byte(target_byte);
            log_dsp("Read DSP_MAILBOX_FROM_HIGH[%d] -> 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, result, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return result;
        } else {
            log_dsp("Read DSP_MAILBOX_FROM_HIGH[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return 0;
        }
    }

    u8 read_DSP_MAILBOX_TO_LOW(int target_byte) {
        if (dsp_state.phase == DspPhase.Running) {
            u8 result = dsp_state.cpu_mailbox_lo.get_byte(target_byte);
            log_dsp("Read DSP_MAILBOX_TO_LOW[%d] -> 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, result, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return result;
        } else {
            log_dsp("Read DSP_MAILBOX_TO_LOW[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return 0;
        }
    }

    void write_DSP_MAILBOX_TO_LOW(int target_byte, u8 value) {
        import std.stdio;
        log_dsp("Write DSP_MAILBOX_TO_LOW[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        dsp_state.cpu_mailbox_lo = cast(u16) dsp_state.cpu_mailbox_lo.set_byte(target_byte, value);
        
        if (target_byte == 1 && dsp_state.phase == DspPhase.AcceptingMicrocode && dsp_state.microcode_count < 10) {
            u32 microcode_config = (cast(u32) dsp_state.cpu_mailbox_hi << 16) | dsp_state.cpu_mailbox_lo;
            dsp_state.microcode_words[dsp_state.microcode_count] = microcode_config;
            dsp_state.microcode_count++;
            log_dsp("DSP captured microcode config %d: 0x%08x", dsp_state.microcode_count, microcode_config);
            
            if (dsp_state.microcode_count == 10) {
                log_dsp("DSP task parameters:");
                log_dsp("  iram_maddr: 0x%08x", dsp_state.microcode_words[1]);
                log_dsp("  iram_addr: 0x%08x", dsp_state.microcode_words[3]);
                log_dsp("  iram_len: 0x%08x", dsp_state.microcode_words[5]);
                log_dsp("  dram_len: 0x%08x", dsp_state.microcode_words[7]);
                log_dsp("  init_vec: 0x%08x", dsp_state.microcode_words[9]);
                
                // Upload IRAM code from main memory
                u32 iram_maddr = dsp_state.microcode_words[1] & 0x7FFFFFFF;
                u32 iram_len = dsp_state.microcode_words[5];
                u16 init_vec = cast(u16) dsp_state.microcode_words[9];
                
                if (iram_len > 0) {
                    u32 iram_words = iram_len / 2;
                    u16[] iram_data = new u16[iram_words];

                    for (u32 i = 0; i < iram_words; i++) {
                        iram_data[i] = mem.physical_read_u16(iram_maddr + i * 2);
                    }

                    jit.dsp_memory.upload_iram(iram_data);
                    dsp_state.dsp_mailbox_hi &= ~0x8000;
                }
                
                dsp_state.pc = init_vec;
                dsp_state.phase = DspPhase.Running;
                log_dsp("DSP started: PC=0x%04x, state=Running", init_vec);
                
                schedule_next_aid_interrupt();
                schedule_next_update();
            }
        } else {
            if (target_byte == 1) {
                dsp_state.cpu_mailbox_hi |= 0x8000;
            }
            
            // Resume DSP if it was idle waiting for mailbox
            resume_from_idle_loop();
        }
    }

    u8 read_DSP_MAILBOX_TO_HIGH(int target_byte) {
        if (dsp_state.phase == DspPhase.Running) {
            u8 result = dsp_state.cpu_mailbox_hi.get_byte(target_byte);
            log_dsp("Read DSP_MAILBOX_TO_HIGH[%d] -> 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, result, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return result;
        } else {
            log_dsp("Read DSP_MAILBOX_TO_HIGH[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return 0;
        }
    }

    void write_DSP_MAILBOX_TO_HIGH(int target_byte, u8 value) {
        log_dsp("Write DSP_MAILBOX_TO_HIGH[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);

        dsp_state.cpu_mailbox_hi = cast(u16) dsp_state.cpu_mailbox_hi.set_byte(target_byte, value);
        
        // Resume DSP if it was idle waiting for mailbox
        resume_from_idle_loop();
    }

    T read_DSP_CSR(T)(int offset) {
        log_dsp("Read DSP_CSR<%s>[%d] -> 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, dsp_state.csr, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return cast(T) dsp_state.csr;
    }

    void write_DSP_CSR(T)(T value, int offset) {
        log_dsp("Write DSP_CSR<%s>[%d] = 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        
        if (value.bit(0)) {
            if (dsp_state.phase == DspPhase.Halted) {
                dsp_state.phase = DspPhase.Bootstrap;
                log_dsp("DSP transitioning from Halted to Bootstrap phase");
            } else if (dsp_state.phase == DspPhase.Bootstrap) {
                dsp_state.phase = DspPhase.AcceptingMicrocode;
                log_dsp("DSP transitioning from Bootstrap to AcceptingMicrocode phase");
            }
        }
        
        if (value.bit(1)) {
            if (dsp_state.phase == DspPhase.Running) {
                dsp_state.raise_interrupt();
            }
        }
        
        if (value.bit(2)) {
            if (dsp_state.phase == DspPhase.Running) {
                error_dsp("DSP halt requested while running");
            }
        }
        
        if (value.bit(3)) {
            dsp_state.csr &= ~(1 << 3);
        }
        
        dsp_state.csr &= ~(1 << 4);
        dsp_state.csr |= value.bit(4) << 4;
        
        if (value.bit(5)) {
            dsp_state.csr &= ~(1 << 5);
        }
        
        if (value.bit(7)) {
            dsp_state.csr &= ~(1 << 7);
        }

        dsp_state.csr &= ~(1 << 8);
        dsp_state.csr |= value.bit(8) << 8;
    }

    u8 read_AR_ARAM_MMADDR(int target_byte) {
        log_dsp("Read AR_ARAM_MMADDR[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    void write_AR_ARAM_MMADDR(int target_byte, u8 value) {
        log_dsp("Write AR_ARAM_MMADDR[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
    }

    u8 read_AR_ARAM_ARADDR(int target_byte) {
        log_dsp("Read AR_ARAM_ARADDR[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    void write_AR_ARAM_ARADDR(int target_byte, u8 value) {
        log_dsp("Write AR_ARAM_ARADDR[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
    }

    u8 read_ARAM_SIZE(int target_byte) {
        log_dsp("Read ARAM_SIZE[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    void write_ARAM_SIZE(int target_byte, u8 value) {
        log_dsp("Write ARAM_SIZE[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
    }

    T read_ARAM_SIZE(T)(int offset) {
        log_dsp("Read ARAM_SIZE<%s>[%d] -> 0x0 (PC=0x%08x LR=0x%08x)", T.stringof, offset, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return cast(T) 0;
    }

    T read_AR_DMA_SIZE(T)(int offset) {
        log_dsp("Read AR_DMA_SIZE<%s>[%d] -> 0x0 (PC=0x%08x LR=0x%08x)", T.stringof, offset, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return cast(T) 0;
    }

    void write_AR_DMA_SIZE(T)(T value, int offset) {
        log_dsp("Write AR_DMA_SIZE<%s>[%d] = 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        
        if (dsp_state.phase == DspPhase.Bootstrap && value != 0) {
            dsp_state.csr |= (1 << 5);
            log_dsp("DSP Bootstrap: Setting CSR bit 5 due to nonzero AR_DMA_SIZE write");
        }
    }

    u8 read_AR_DMA_START_HIGH(int target_byte) {
        u8 result = ar_dma_start_high.get_byte(target_byte);
        log_cp("Read AR_DMA_START_HIGH[%d] -> 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, result, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return result;
    }

    void write_AR_DMA_START_HIGH(int target_byte, u8 value) {
        log_cp("Write AR_DMA_START_HIGH[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        ar_dma_start_high = cast(u16) ar_dma_start_high.set_byte(target_byte, value);
    }

    u8 read_AR_DMA_START_LOW(int target_byte) {
        u8 result = ar_dma_start_low.get_byte(target_byte);
        log_cp("Read AR_DMA_START_LOW[%d] -> 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, result, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return result;
    }

    void write_AR_DMA_START_LOW(int target_byte, u8 value) {
        log_cp("Write AR_DMA_START_LOW[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        ar_dma_start_low = cast(u16) ar_dma_start_low.set_byte(target_byte, value);
    }

    T read_AR_DMA_CNT(T)(int offset) {
        log_cp("Read AR_DMA_CNT<%s>[%d] -> 0x0 (PC=0x%08x LR=0x%08x)", T.stringof, offset, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return cast(T) ar_dma_cnt;
    }

    bool play_to_ai;
    u32 ai_sample_length;
    u16 ar_dma_cnt;
    u16 ar_dma_start_high;
    u16 ar_dma_start_low;
    
    u32 current_audio_address;
    u32 samples_remaining;
    ulong audio_stream_event_id;
    bool audio_streaming_active;
    void write_AR_DMA_CNT(T)(T value, int offset) {
        log_dsp("Write AR_DMA_CNT<%s>[%d] = 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        assert_dsp(offset == 0, "AR_DMA_CNT write with unsupported offset %d", offset);
        assert_dsp(T.sizeof == 2, "AR_DMA_CNT write with unsupported size %d", T.sizeof);
        ar_dma_cnt = cast(u16) value;

        log_cp("Write AR_DMA_CNT<%s>[%d] = 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);

        this.play_to_ai = value.bit(15);
        this.ai_sample_length = cast(u32) value.bits(0, 14) * 32;

        if (this.play_to_ai && !audio_streaming_active) {
            start_audio_streaming();
        }
    }

    u8 read_DSP_DMA_BYTES_LEFT(int target_byte) {
        log_cp("Read DSP_DMA_BYTES_LEFT[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    u16 dsp_read_mailbox_register(u16 address) {
        final switch (address) {
        case 0xFFFC:
            return dsp_state.dsp_mailbox_hi;
        case 0xFFFD:
            return dsp_state.dsp_mailbox_lo;
        case 0xFFFE:
            return dsp_state.cpu_mailbox_hi;
        case 0xFFFF:
            u16 value = dsp_state.cpu_mailbox_lo;
            dsp_state.cpu_mailbox_hi &= ~0x8000;
            return value;
        }
    }

    void dsp_write_mailbox_register(u16 address, u16 value) {
        final switch (address) {
        case 0xFFFC:
            dsp_state.dsp_mailbox_hi = value & 0x7FFF;
            break;
        case 0xFFFD:
            dsp_state.dsp_mailbox_lo = value;
            dsp_state.dsp_mailbox_hi |= 0x8000;
            break;
        case 0xFFFE:

            break;
        case 0xFFFF:
            break;
        }
    }

    u16 dsp_io_read(u16 address) {
        switch (address) {
        case 0xFFC9:
            return dma_control_reg;
        case 0xFFCB:
            return dma_block_length;
        case 0xFFCD:
            return dma_dsp_address;
        case 0xFFCE:
            return dma_mm_addr_high;
        case 0xFFCF:
            return dma_mm_addr_low;
        case 0xFFA0: .. case 0xFFAF:
        case 0xFFD1:
        case 0xFFD2:
        case 0xFFD3:
        case 0xFFD4:
        case 0xFFD5:
        case 0xFFD6:
        case 0xFFD7:
        case 0xFFD8:
        case 0xFFD9:
        case 0xFFDA:
        case 0xFFDB:
        case 0xFFDC:
        case 0xFFDD:
        case 0xFFDE:
        case 0xFFDF:
            return accelerator.read_register(address);
        case 0xFFFC:
            log_dsp("DSP IO read to DSP_MAILBOX_FROM_HIGH: 0x%04X", dsp_state.dsp_mailbox_hi);
            return dsp_state.dsp_mailbox_hi;
        case 0xFFFD:
            log_dsp("DSP IO read to DSP_MAILBOX_FROM_HIGH: 0x%04X", dsp_state.dsp_mailbox_lo);
            return dsp_state.dsp_mailbox_lo;
        case 0xFFFE:

            import std.stdio;
            // writefln("DSP IO read to CPU_MAILBOX_HIGH: 0x%04X", dsp_state.cpu_mailbox_hi);
            return dsp_state.cpu_mailbox_hi;
        case 0xFFFF:
            import std.stdio;
            // writefln("DSP IO read to CPU_MAILBOX_LOW: 0x%04X", dsp_state.cpu_mailbox_lo);
            u16 value = dsp_state.cpu_mailbox_lo;
            dsp_state.cpu_mailbox_hi &= ~0x8000;
            return value;
        default:
            error_dsp("DSP IO read from unhandled address 0x%04X", address);
            return 0;
        }
    }

    void dsp_io_write(u16 address, u16 value) {
        switch (address) {
        case 0xFFC9:
            dma_control_reg = value;
            break;
        case 0xFFCB:
            dma_block_length = value;
            if (value == 0) {
                error_dsp("DSP DMA: Cannot transfer 0 bytes");
            } else {
                execute_dsp_dma_transfer();
            }
            break;
        case 0xFFCD:
            dma_dsp_address = value;
            break;
        case 0xFFCE:
            dma_mm_addr_high = value;
            break;
        case 0xFFCF:
            dma_mm_addr_low = value;
            break;
        case 0xFFA0: .. case 0xFFAF:
        case 0xFFD1:
        case 0xFFD2:
        case 0xFFD3:
        case 0xFFD4:
        case 0xFFD5:
        case 0xFFD6:
        case 0xFFD7:
        case 0xFFD8:
        case 0xFFD9:
        case 0xFFDA:
        case 0xFFDB:
        case 0xFFDC:
        case 0xFFDE:
        case 0xFFDF:
            accelerator.write_register(address, value);
            break;
        case 0xFFFB:
            if (value != 1 && value != 0) {
                error_dsp("DSP DIRQ: Invalid value 0x%04X, only 0 or 1 is allowed", value);
                return;
            }
            
            if (value == 1 && dsp_state.csr.bit(8)) {
                dsp_state.csr |= 1 << 7;
                log_dsp("DSP DIRQ: Processing interrupt request, raising CPU interrupt");
                interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
            }
            break;
        case 0xFFFC:
            log_dsp("DSP IO write to DSP_MAILBOX_FROM_HIGH: 0x%04X", value);
            dsp_state.dsp_mailbox_hi = value & 0x7FFF;
            break;
        case 0xFFFD:
            log_dsp("DSP IO write to DSP_MAILBOX_FROM_LOW: 0x%04X", value);
            dsp_state.dsp_mailbox_lo = value;
            dsp_state.dsp_mailbox_hi |= 0x8000;
            break;
        case 0xFFFE:
        case 0xFFFF:
            break;
        default:
            error_dsp("DSP IO write to unhandled address 0x%04X (value 0x%04X)", address, value);
            break;
        }
    }

    private void schedule_next_aid_interrupt() {
        aid_interrupt_event_id = scheduler.add_event_relative_to_clock(&trigger_aid_interrupt, 100_000);
    }

    private void trigger_aid_interrupt() {
        if (dsp_state.csr.bit(4)) {
            // dsp_state.csr |= 1 << 3;
        }

        // interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
        
        schedule_next_aid_interrupt();
    }

    private void schedule_next_update() {
        update_event_id = scheduler.add_event_relative_to_clock(&update, 1000);
    }

    private void resume_from_idle_loop() {
        if (is_in_idle_loop) {
            is_in_idle_loop = false;
            log_dsp("DSP waking up (mailbox written, resuming from idle loop)");
            schedule_next_update();
        }
    }

    private bool is_in_idle_loop = false;

    private void update() {
        if (dsp_state.phase != DspPhase.Running) {
            return;
        }
        
        u16 wr3_before = dsp_state.wr[3];
        JitExitReason reason = jit.run_cycles(&dsp_state, 100);
        u16 wr3_after = dsp_state.wr[3];
        
        if (reason == JitExitReason.DspHalted) {
            dsp_state.phase = DspPhase.Halted;
            error_dsp("DSP halted");
        } else if (reason == JitExitReason.IdleLoopDetected) {
            is_in_idle_loop = true;
            log_dsp("DSP going to sleep (idle loop detected at PC=0x%04X)", dsp_state.pc);
            return; // Don't reschedule
        }
        
        schedule_next_update();
    }

    private void trigger_dsp_dma() {
        log_cp("Triggering DSP DMA transfer");
        scheduler.add_event_relative_to_clock(&this.complete_dsp_dma, 1000);
    }

    private void complete_dsp_dma() {
        log_dsp("DSP DMA completed");

        if (dsp_state.csr.bit(4)) {
            dsp_state.csr |= 1 << 3;
            interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
        }
    }

    private void execute_dsp_dma_transfer() {
        u32 main_memory_address = ((cast(u32) dma_mm_addr_high << 16) | dma_mm_addr_low) & 0x7FFFFFFF;
        u16 dsp_address = dma_dsp_address;
        u16 transfer_bytes = dma_block_length / 2;
        
        bool cpu_to_dsp = !(dma_control_reg & (1 << 0));
        bool use_imem = (dma_control_reg & (1 << 1)) != 0;
        
        log_dsp("DSP DMA: %s %d bytes between DSP 0x%04X (%s) and main memory 0x%08X at pc %x", 
                cpu_to_dsp ? "CPU->DSP" : "DSP->CPU", transfer_bytes,
                dsp_address, use_imem ? "IMEM" : "DMEM", main_memory_address, dsp_state.pc);
        
        u16 transfer_words = transfer_bytes;
        
        for (u16 i = 0; i < transfer_words; i++) {
            u16 data;
            if (cpu_to_dsp) {
                data = mem.physical_read_u16(main_memory_address + i * 2);
                if (use_imem) {
                    jit.dsp_memory.write_instruction(cast(u16)(dsp_address + i), data);
                } else {
                    jit.dsp_memory.write_data(cast(u16)(dsp_address + i), data);
                }
            } else {
                if (use_imem) {
                    data = jit.dsp_memory.read_instruction(cast(u16)(dsp_address + i));
                } else {
                    data = jit.dsp_memory.read_data(cast(u16)(dsp_address + i));
                }
                mem.physical_write_u16(main_memory_address + i * 2, data);
            }
        }
        
        dma_block_length = 0;
        scheduler.add_event_relative_to_clock(&complete_dsp_dma, 100);
    }

    private void start_audio_streaming() {
        current_audio_address = ((cast(u32) ar_dma_start_high << 16) | ar_dma_start_low) & 0x7FFFFFFF;
        samples_remaining = ai_sample_length / 4;
        audio_streaming_active = true;
        
        log_dsp("Starting 32kHz audio stream: address=0x%08X, samples=%d", current_audio_address, samples_remaining);
        
        auto audio_cycles = 729_000_000 / 32000;
        audio_stream_event_id = scheduler.add_event_relative_to_clock(&this.stream_next_sample, audio_cycles / 2);
    }

    private void stream_next_sample() {
        log_dsp("Streaming next audio sample: address=0x%08X, samples_remaining=%d", current_audio_address, samples_remaining);
        
        if (samples_remaining == 0) {
            current_audio_address = ((cast(u32) ar_dma_start_high << 16) | ar_dma_start_low) & 0x7FFFFFFF;
            samples_remaining = ai_sample_length / 2;
            audio_streaming_active = false;
            log_dsp("Audio stream exhausted: address=0x%08X, samples=%d, streaming_active=%s", current_audio_address, samples_remaining, audio_streaming_active ? "true" : "false");

            // ?????
            trigger_dsp_dma();
            return;
        }
        
        if (samples_remaining > 0 && audio_interface) {
            short left = cast(short) mem.physical_read_u16(current_audio_address);
            short right = cast(short) mem.physical_read_u16(current_audio_address + 2);

            if ((left & 0x7fff) != 0 || (right & 0x7fff) != 0) {
                import std.stdio;
                // writefln("Audio sample: address=0x%08X left=0x%04X right=0x%04X", current_audio_address, cast(u16) left, cast(u16) right);
            }
            
            audio_interface.push_sample(left, right);
            
            current_audio_address += 4;
            samples_remaining--;
        }
        
        auto audio_cycles = 729_000_000 / 32000;
        audio_stream_event_id = scheduler.add_event_relative_to_self(&this.stream_next_sample, audio_cycles / 2);
    }

    void dump_dsp_registers() {
        import std.stdio;
        writefln("=== DSP REGISTER DUMP ===");
        writefln("PC=0x%04x loop_counter=%d", dsp_state.pc, dsp_state.loop_counter);
        writefln("AR=[0x%04x,0x%04x,0x%04x,0x%04x] IX=[0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.ar[0], dsp_state.ar[1], dsp_state.ar[2], dsp_state.ar[3],
                dsp_state.ix[0], dsp_state.ix[1], dsp_state.ix[2], dsp_state.ix[3]);
        writefln("WR=[0x%04x,0x%04x,0x%04x,0x%04x] AC=[0x%016x,0x%016x]", 
                dsp_state.wr[0], dsp_state.wr[1], dsp_state.wr[2], dsp_state.wr[3],
                dsp_state.ac[0].full, dsp_state.ac[1].full);
                // size : 32
        writefln("Call Stack1: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.call_stack.sp,
                dsp_state.call_stack.data[0], dsp_state.call_stack.data[1], 
                dsp_state.call_stack.data[2], dsp_state.call_stack.data[3],
                dsp_state.call_stack.data[4], dsp_state.call_stack.data[5],
                dsp_state.call_stack.data[6], dsp_state.call_stack.data[7]);
        writefln("Call Stack2: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.call_stack.sp,
                dsp_state.call_stack.data[8], dsp_state.call_stack.data[9],
                dsp_state.call_stack.data[10], dsp_state.call_stack.data[11],
                dsp_state.call_stack.data[12], dsp_state.call_stack.data[13],
                dsp_state.call_stack.data[14], dsp_state.call_stack.data[15]);
        writefln("Call Stack3: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.call_stack.sp,
                dsp_state.call_stack.data[16], dsp_state.call_stack.data[17],
                dsp_state.call_stack.data[18], dsp_state.call_stack.data[19],
                dsp_state.call_stack.data[20], dsp_state.call_stack.data[21],
                dsp_state.call_stack.data[22], dsp_state.call_stack.data[23]);
        writefln("Call Stack4: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.call_stack.sp,
                dsp_state.call_stack.data[24], dsp_state.call_stack.data[25],
                dsp_state.call_stack.data[26], dsp_state.call_stack.data[27],
                dsp_state.call_stack.data[28], dsp_state.call_stack.data[29],
                dsp_state.call_stack.data[30], dsp_state.call_stack.data[31]);

        writefln("Data Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.data_stack.sp,
                dsp_state.data_stack.data[0], dsp_state.data_stack.data[1], 
                dsp_state.data_stack.data[2], dsp_state.data_stack.data[3],
                dsp_state.data_stack.data[4], dsp_state.data_stack.data[5],
                dsp_state.data_stack.data[6], dsp_state.data_stack.data[7]);
        
        writefln("========================");
    }
}

void dsp_stack_overflow_error(u32 stack_type) {
    switch (stack_type) {
    case 0: error_dsp("DSP call stack overflow (ST0)"); break;
    case 1: error_dsp("DSP data stack overflow (ST1)"); break;
    case 2: error_dsp("DSP loop address stack overflow"); break;
    case 3: error_dsp("DSP loop counter stack overflow"); break;
    default: error_dsp("DSP stack overflow (unknown type %d)", stack_type); break;
    }
}

void dsp_stack_underflow_error(u32 stack_type) {
    switch (stack_type) {
    case 0: error_dsp("DSP call stack underflow (ST0)"); break;
    case 1: error_dsp("DSP data stack underflow (ST1)"); break;
    case 2: error_dsp("DSP loop address stack underflow"); break;
    case 3: error_dsp("DSP loop counter stack underflow"); break;
    default: error_dsp("DSP stack underflow (unknown type %d)", stack_type); break;
    }
}

void dsp_invalid_instruction_memory_error(u16 address) {
    error_dsp("DSP invalid instruction memory access at address 0x%04X", address);
}

void dsp_invalid_data_memory_read_error(u16 address) {
    error_dsp("DSP invalid data memory read at address 0x%04X", address);
}

void dsp_invalid_data_memory_write_error(u16 address) {
    error_dsp("DSP invalid data memory write at address 0x%04X", address);
}

void dsp_coef_memory_write_error(u16 address) {
    error_dsp("DSP attempted write to read-only COEF memory at address 0x%04X", address);
}