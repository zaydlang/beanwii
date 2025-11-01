module emu.hw.dsp.dsp;

import emu.hw.broadway.interrupt;
import emu.hw.dsp.jit.jit;
import emu.hw.dsp.jit.memory;
import emu.hw.dsp.state;
import emu.hw.memory.strategy.memstrategy;
import emu.scheduler;
import util.bitop;
import util.number;
import util.log;
import core.thread;
import core.sync.mutex;

final class DSP {
    Scheduler scheduler;
    InterruptController interrupt_controller;
    Mem mem;

    DspJit jit;
    DspState dsp_state;
    
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
    }

    u8 read_DSP_MAILBOX_FROM_LOW(int target_byte) {
        if (dsp_state.phase == DspPhase.Running) {
            u8 result = cast(u8) ((dsp_state.dsp_mailbox_lo >> (target_byte * 8)) & 0xFF);
            
            if (target_byte == 1) {
                dsp_state.dsp_mailbox_hi &= ~0x8000;
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
        log_dsp("Write DSP_MAILBOX_TO_LOW[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        
        if (dsp_state.phase == DspPhase.Running) {
            dsp_state.cpu_mailbox_lo = cast(u16) dsp_state.cpu_mailbox_lo.set_byte(target_byte, value);
        } else {
            dsp_state.cpu_mailbox_lo = cast(u16) dsp_state.cpu_mailbox_lo.set_byte(target_byte, value);
        }
        
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
                u32 iram_maddr = dsp_state.microcode_words[1];
                u32 iram_len = dsp_state.microcode_words[5];
                u16 init_vec = cast(u16) dsp_state.microcode_words[9];
                
                if (iram_len > 0) {
                    u32 iram_words = iram_len / 2;
                    u16[] iram_data = new u16[iram_words];
                    for (u32 i = 0; i < iram_words; i++) {
                        iram_data[i] = mem.read_be_u16(iram_maddr + i * 2);
                    }
                    jit.dsp_memory.upload_iram(iram_data);
                }
                
                dsp_state.pc = init_vec;
                dsp_state.phase = DspPhase.Running;
                log_dsp("DSP started: PC=0x%04x, state=Running", init_vec);
                
                schedule_next_aid_interrupt();
                schedule_next_update();
            }
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
                dsp_state.phase = DspPhase.Halted;
                log_dsp("DSP halted due to CSR bit 1 write");
            }
        }
        
        if (value.bit(2)) {
            if (dsp_state.phase == DspPhase.Running) {
                dsp_state.trigger_interrupt();
                log_dsp("DSP interrupt triggered due to CSR bit 2 write");
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
        log_dsp("Read AR_DMA_START_HIGH[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    void write_AR_DMA_START_HIGH(int target_byte, u8 value) {
        log_dsp("Write AR_DMA_START_HIGH[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
    }

    u8 read_AR_DMA_START_LOW(int target_byte) {
        log_dsp("Read AR_DMA_START_LOW[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    void write_AR_DMA_START_LOW(int target_byte, u8 value) {
        log_dsp("Write AR_DMA_START_LOW[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
    }

    T read_AR_DMA_CNT(T)(int offset) {
        log_dsp("Read AR_DMA_CNT<%s>[%d] -> 0x0 (PC=0x%08x LR=0x%08x)", T.stringof, offset, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return cast(T) 0;
    }

    void write_AR_DMA_CNT(T)(T value, int offset) {
        log_dsp("Write AR_DMA_CNT<%s>[%d] = 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        
        if (value.bit(15)) {
            this.trigger_dsp_dma();
        }
    }

    u8 read_DSP_DMA_BYTES_LEFT(int target_byte) {
        log_dsp("Read DSP_DMA_BYTES_LEFT[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
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
        case 0xFFFB:
            if (value != 1) {
                error_dsp("DSP DIRQ: Invalid value 0x%04X, only 1 is allowed", value);
                return;
            }
            
            if (dsp_state.csr.bit(8)) {
                dsp_state.csr |= 1 << 7;
                log_dsp("DSP DIRQ: Processing interrupt request, raising CPU interrupt");
                interrupt_controller.raise_processor_interface_interrupt(ProcessorInterfaceInterruptCause.DSP);
            }
            break;
        case 0xFFFC:
            dsp_state.dsp_mailbox_hi = value & 0x7FFF;
            break;
        case 0xFFFD:
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

    private void update() {
        if (dsp_state.phase != DspPhase.Running) {
            return;
        }
        
        JitExitReason reason = jit.run_cycles(&dsp_state, 100);
        
        if (reason == JitExitReason.DspHalted) {
            dsp_state.phase = DspPhase.Halted;
            error_dsp("DSP halted");
        }
        
        schedule_next_update();
    }

    private void trigger_dsp_dma() {
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
        u16 transfer_bytes = dma_block_length;
        
        bool cpu_to_dsp = !(dma_control_reg & (1 << 0));
        bool use_imem = (dma_control_reg & (1 << 1)) != 0;
        
        log_dsp("DSP DMA: %s %d bytes between DSP 0x%04X (%s) and main memory 0x%08X", 
                cpu_to_dsp ? "CPU->DSP" : "DSP->CPU", transfer_bytes,
                dsp_address, use_imem ? "IMEM" : "DMEM", main_memory_address);
        
        u16 transfer_words = transfer_bytes / 2;
        
        for (u16 i = 0; i < transfer_words; i++) {
            if (cpu_to_dsp) {
                u16 data = mem.paddr_read_u16(main_memory_address + i * 2);
                if (use_imem) {
                    jit.dsp_memory.write_instruction(cast(u16)(dsp_address + i), data);
                } else {
                    jit.dsp_memory.write_data(cast(u16)(dsp_address + i), data);
                }
            } else {
                u16 data;
                if (use_imem) {
                    data = jit.dsp_memory.read_instruction(cast(u16)(dsp_address + i));
                } else {
                    data = jit.dsp_memory.read_data(cast(u16)(dsp_address + i));
                }
                mem.paddr_write_u16(main_memory_address + i * 2, data);
            }
        }
        
        dma_block_length = 0;
        scheduler.add_event_relative_to_clock(&complete_dsp_dma, 100);
    }

    void dump_dsp_registers() {
        log_dsp("=== DSP REGISTER DUMP ===");
        log_dsp("PC=0x%04x loop_counter=%d", dsp_state.pc, dsp_state.loop_counter);
        log_dsp("AR=[0x%04x,0x%04x,0x%04x,0x%04x] IX=[0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.ar[0], dsp_state.ar[1], dsp_state.ar[2], dsp_state.ar[3],
                dsp_state.ix[0], dsp_state.ix[1], dsp_state.ix[2], dsp_state.ix[3]);
        log_dsp("WR=[0x%04x,0x%04x,0x%04x,0x%04x] AC=[0x%016x,0x%016x]", 
                dsp_state.wr[0], dsp_state.wr[1], dsp_state.wr[2], dsp_state.wr[3],
                dsp_state.ac[0].full, dsp_state.ac[1].full);
        log_dsp("Call Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.call_stack.sp,
                dsp_state.call_stack.data[0], dsp_state.call_stack.data[1], 
                dsp_state.call_stack.data[2], dsp_state.call_stack.data[3]);
        log_dsp("Data Stack: sp=%d [0x%04x,0x%04x,0x%04x,0x%04x]", 
                dsp_state.data_stack.sp,
                dsp_state.data_stack.data[0], dsp_state.data_stack.data[1], 
                dsp_state.data_stack.data[2], dsp_state.data_stack.data[3]);
        log_dsp("========================");
    }
}