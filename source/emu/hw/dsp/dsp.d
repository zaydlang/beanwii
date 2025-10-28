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
    Thread dsp_thread;
    Mutex dsp_mutex;
    bool dsp_should_stop;

    this() {
        jit = new DspJit();
        dsp_state = DspState();
        dsp_mutex = new Mutex();
        dsp_should_stop = false;
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
        log_dsp("Read DSP_MAILBOX_FROM_LOW[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    u8 read_DSP_MAILBOX_FROM_HIGH(int target_byte) {
        if (dsp_state.phase == DspPhase.Bootstrap || dsp_state.phase == DspPhase.AcceptingMicrocode) {
            u8 result = cast(u8) ((dsp_state.bootstrap_mailbox >> (target_byte * 8)) & 0xFF);
            if (target_byte == 1) {
                dsp_state.bootstrap_mailbox ^= 0x8000;
            }
            log_dsp("Read DSP_MAILBOX_FROM_HIGH[%d] -> 0x%02x (%s) (PC=0x%08x LR=0x%08x)", target_byte, result, 
                   dsp_state.phase == DspPhase.Bootstrap ? "Bootstrap" : "AcceptingMicrocode",
                   interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
            return result;
        }
        log_dsp("Read DSP_MAILBOX_FROM_HIGH[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    u8 read_DSP_MAILBOX_TO_LOW(int target_byte) {
        log_dsp("Read DSP_MAILBOX_TO_LOW[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    void write_DSP_MAILBOX_TO_LOW(int target_byte, u8 value) {
        log_dsp("Write DSP_MAILBOX_TO_LOW[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        
        u32 mask = 0xFF << (target_byte * 8);
        dsp_state.mailbox_to_low = (dsp_state.mailbox_to_low & ~mask) | ((cast(u32) value) << (target_byte * 8));
        
        if (target_byte == 1 && dsp_state.phase == DspPhase.AcceptingMicrocode && dsp_state.microcode_count < 10) {
            u32 microcode_config = (dsp_state.mailbox_to_high << 16) | (dsp_state.mailbox_to_low & 0xFFFF);
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
                
                start_dsp_thread();
            }
        }
    }

    u8 read_DSP_MAILBOX_TO_HIGH(int target_byte) {
        log_dsp("Read DSP_MAILBOX_TO_HIGH[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    void write_DSP_MAILBOX_TO_HIGH(int target_byte, u8 value) {
        log_dsp("Write DSP_MAILBOX_TO_HIGH[%d] = 0x%02x (PC=0x%08x LR=0x%08x)", target_byte, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        
        u32 mask = 0xFF << (target_byte * 8);
        dsp_state.mailbox_to_high = (dsp_state.mailbox_to_high & ~mask) | ((cast(u32) value) << (target_byte * 8));
    }

    T read_DSP_CSR(T)(int offset) {
        log_dsp("Read DSP_CSR<%s>[%d] -> 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, dsp_state.csr, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return cast(T) dsp_state.csr;
    }

    void write_DSP_CSR(T)(T value, int offset) {
        log_dsp("Write DSP_CSR<%s>[%d] = 0x%x (PC=0x%08x LR=0x%08x)", T.stringof, offset, value, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        
        if (cast(u16) value & 0x20) {
            dsp_state.csr &= ~0x20;
            log_dsp("DSP CSR: Clearing bit 5 due to write");
        }
        
        if (cast(u16) value & 1) {
            if (dsp_state.phase == DspPhase.Halted) {
                dsp_state.phase = DspPhase.Bootstrap;
                log_dsp("DSP transitioning from Halted to Bootstrap phase");
            } else if (dsp_state.phase == DspPhase.Bootstrap) {
                dsp_state.phase = DspPhase.AcceptingMicrocode;
                log_dsp("DSP transitioning from Bootstrap to AcceptingMicrocode phase");
            }
        }
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
    }

    u8 read_DSP_DMA_BYTES_LEFT(int target_byte) {
        log_dsp("Read DSP_DMA_BYTES_LEFT[%d] -> 0x00 (PC=0x%08x LR=0x%08x)", target_byte, interrupt_controller.broadway.state.pc, interrupt_controller.broadway.state.lr);
        return 0;
    }

    private void start_dsp_thread() {
        if (dsp_thread !is null && dsp_thread.isRunning()) {
            return;
        }
        
        dsp_should_stop = false;
        dsp_thread = new Thread(&dsp_execution_thread);
        dsp_thread.start();
        log_dsp("DSP execution thread started");
    }

    private void stop_dsp_thread() {
        if (dsp_thread is null || !dsp_thread.isRunning()) {
            return;
        }
        
        dsp_should_stop = true;
        dsp_thread.join();
        log_dsp("DSP execution thread stopped");
    }

    private void dsp_execution_thread() {
        while (!dsp_should_stop) {
            dsp_mutex.lock();
            scope(exit) dsp_mutex.unlock();
            
            if (dsp_state.phase != DspPhase.Running) {
                break;
            }
            
            JitExitReason reason = jit.run_cycles(&dsp_state, 1000);
            
            if (reason == JitExitReason.DspHalted) {
                dsp_state.phase = DspPhase.Halted;
                log_dsp("DSP halted");
                break;
            }
        }
    }
}