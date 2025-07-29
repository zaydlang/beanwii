module emu.hw.cp.cp;

import util.bitop;
import util.log;
import util.number;

final class CommandProcessor {
    u8 read_CP_FIFO_STATUS(int target_byte) {
        return 0;
    }

    u8 read_CP_CONTROL(int target_byte) {
        return 0;
    }

    u8 read_CP_CLEAR(int target_byte) {
        return 0;
    }

    u8 read_CP_TOKEN(int target_byte) {
        return 0;
    }

    u8 read_CP_FIFO_START(int target_byte) {
        return 0;
    }

    u8 read_CP_FIFO_END(int target_byte) {
        return 0;
    }

    u8 read_CP_FIFO_WP_HI(int target_byte) {
        u8 result = 0;
        return result;
    }

    u8 read_CP_FIFO_WP_LO(int target_byte) {
        u8 result = 0;
        return result;
    }

    void write_CP_FIFO_STATUS(int target_byte, u8 value) {
    }

    void write_CP_CONTROL(int target_byte, u8 value) {
    }

    void write_CP_CLEAR(int target_byte, u8 value) {
    }

    void write_CP_TOKEN(int target_byte, u8 value) {
    }

    void write_CP_FIFO_START(int target_byte, u8 value) {
    }

    void write_CP_FIFO_END(int target_byte, u8 value) {
    }

    void write_CP_FIFO_WP_HI(int target_byte, u8 value) {
    }
    
    void write_CP_FIFO_WP_LO(int target_byte, u8 value) {
    }

    u32 cp_fifo_distance_lo;
    u32 cp_fifo_distance_hi;

    u8 read_CP_FIFO_DISTANCE_LO(int target_byte) {
        return cp_fifo_distance_lo.get_byte(target_byte);
    }

    void write_CP_FIFO_DISTANCE_LO(int target_byte, u8 value) {
        cp_fifo_distance_lo = cp_fifo_distance_lo.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_DISTANCE_HI(int target_byte) {
        return cp_fifo_distance_hi.get_byte(target_byte);
    }

    void write_CP_FIFO_DISTANCE_HI(int target_byte, u8 value) {
        cp_fifo_distance_hi = cp_fifo_distance_hi.set_byte(target_byte, value);
    }

    u32 cp_fifo_read_ptr_lo;
    u32 cp_fifo_read_ptr_hi;

    u8 read_CP_FIFO_RP_LO(int target_byte) {
        return cp_fifo_read_ptr_lo.get_byte(target_byte);
    }

    void write_CP_FIFO_RP_LO(int target_byte, u8 value) {
        cp_fifo_read_ptr_lo = cp_fifo_read_ptr_lo.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_RP_HI(int target_byte) {
        return cp_fifo_read_ptr_hi.get_byte(target_byte);
    }

    void write_CP_FIFO_RP_HI(int target_byte, u8 value) {
        cp_fifo_read_ptr_hi = cp_fifo_read_ptr_hi.set_byte(target_byte, value);
    }

    u32 cp_fifo_hi_watermark_hi;
    u32 cp_fifo_hi_watermark_lo;
    u32 cp_fifo_lo_watermark_hi;
    u32 cp_fifo_lo_watermark_lo;

    u8 read_CP_FIFO_HI_WM_HI(int target_byte) {
        return cp_fifo_hi_watermark_hi.get_byte(target_byte);
    }

    void write_CP_FIFO_HI_WM_HI(int target_byte, u8 value) {
        cp_fifo_hi_watermark_hi = cp_fifo_hi_watermark_hi.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_HI_WM_LO(int target_byte) {
        return cp_fifo_hi_watermark_lo.get_byte(target_byte);
    }

    void write_CP_FIFO_HI_WM_LO(int target_byte, u8 value) {
        cp_fifo_hi_watermark_lo = cp_fifo_hi_watermark_lo.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_LO_WM_HI(int target_byte) {
        return cp_fifo_lo_watermark_hi.get_byte(target_byte);
    }

    void write_CP_FIFO_LO_WM_HI(int target_byte, u8 value) {
        cp_fifo_lo_watermark_hi = cp_fifo_lo_watermark_hi.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_LO_WM_LO(int target_byte) {
        return cp_fifo_lo_watermark_lo.get_byte(target_byte);
    }

    void write_CP_FIFO_LO_WM_LO(int target_byte, u8 value) {
        cp_fifo_lo_watermark_lo = cp_fifo_lo_watermark_lo.set_byte(target_byte, value);
    }

    u32 unknown_CC000006;
    u8 read_UNKNOWN_CC000006(int target_byte) {
        return unknown_CC000006.get_byte(target_byte);
    }

    void write_UNKNOWN_CC000006(int target_byte, u8 value) {
        unknown_CC000006 = unknown_CC000006.set_byte(target_byte, value);
    }
}