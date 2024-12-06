module emu.hw.dsp.dsp;

import util.bitop;
import util.number;

final class DSP {
    u16 mailbox_from_lo;

    u8 read_DSP_MAILBOX_FROM_LOW(int target_byte) {

        return mailbox_from_lo.get_byte(target_byte);
    }

    u16 mailbox_from_hi;

    u8 read_DSP_MAILBOX_FROM_HIGH(int target_byte) {
        // keep toggling the mailbox value
        if (target_byte == 1)
            mailbox_from_hi ^= 0x8000;

        return mailbox_from_hi.get_byte(target_byte);
    }

    u16 mailbox_to_lo;

    u8 read_DSP_MAILBOX_TO_LOW(int target_byte) {
        return mailbox_to_lo.get_byte(target_byte);
    }

    void write_DSP_MAILBOX_TO_LOW(int target_byte, u8 value) {
        mailbox_to_lo = 0;
    }

    u16 mailbox_to_hi;

    u8 read_DSP_MAILBOX_TO_HIGH(int target_byte) {
        return mailbox_to_hi.get_byte(target_byte);
    }

    void write_DSP_MAILBOX_TO_HIGH(int target_byte, u8 value) {
        mailbox_to_hi = 0;
    }

    u32 csr;

    u8 read_DSP_CSR(int target_byte) {
        return csr.get_byte(target_byte);
    }

    void write_DSP_CSR(int target_byte, u8 value) {
        csr = csr.set_byte(target_byte, value);
        csr &= ~1;
        csr &= ~(1 << 11);
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
