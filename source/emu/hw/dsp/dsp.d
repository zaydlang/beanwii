module emu.hw.dsp.dsp;

import util.bitop;
import util.number;

final class DSP {
    u32 mailbox_from = 0x8000_0000;
    
    u8 read_DSP_MAILBOX_FROM(int target_byte) {
        // keep toggling the mailbox value
        if (target_byte == 2)
            mailbox_from ^= 0x8000_0000;

        return mailbox_from.get_byte(target_byte ^ 2);
    }

    u32 mailbox_to;

    u8 read_DSP_MAILBOX_TO(int target_byte) {
        return mailbox_to.get_byte(target_byte ^ 2);
    }

    void write_DSP_MAILBOX_TO(int target_byte, u8 value) {
        mailbox_to = mailbox_to.set_byte(target_byte, value);
    }

    u32 csr;

    u8 read_DSP_CSR(int target_byte) {
        return csr.get_byte(target_byte);
    }

    void write_DSP_CSR(int target_byte, u8 value) {
        csr = csr.set_byte(target_byte, value);
        csr &= ~1;
    }

    u32 aram_mmaddr;

    u8 read_AR_ARAM_MMADDR(int target_byte) {
        return aram_mmaddr.get_byte(target_byte);
    }

    void write_AR_ARAM_MMADDR(int target_byte, u8 value) {
        aram_mmaddr = aram_mmaddr.set_byte(target_byte, value);
    }

    u32 aram_araddr;

    u8 read_AR_ARAM_ARADDR(int target_byte) {
        return aram_araddr.get_byte(target_byte);
    }

    void write_AR_ARAM_ARADDR(int target_byte, u8 value) {
        aram_araddr = aram_araddr.set_byte(target_byte, value);
    }

    u32 aram_size;

    u8 read_ARAM_SIZE(int target_byte) {
        return aram_size.get_byte(target_byte);
    }

    void write_ARAM_SIZE(int target_byte, u8 value) {
        aram_size = aram_size.set_byte(target_byte, value);
    }

    u32 ar_dma_cnt;

    u8 read_AR_DMA_CNT(int target_byte) {
        return ar_dma_cnt.get_byte(target_byte);
    }

    void write_AR_DMA_CNT(int target_byte, u8 value) {
        ar_dma_cnt = ar_dma_cnt.set_byte(target_byte, value);
    }
}
