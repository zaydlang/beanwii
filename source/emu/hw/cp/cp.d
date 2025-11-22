module emu.hw.cp.cp;

import util.bitop;
import util.log;
import util.number;

final class CommandProcessor {
    bool fifos_linked = false;

    u8 read_CP_FIFO_STATUS(int target_byte) {
        log_cp("read CP_FIFO_STATUS[%d] = 0x00", target_byte);
        return 0;
    }

    u8 read_CP_CONTROL(int target_byte) {
        u8 result = 0;
        log_cp("read CP_CONTROL[%d] = 0x%02x", target_byte, result);
        return result;
    }

    u8 read_CP_CLEAR(int target_byte) {
        u8 result = 0;
        log_cp("read CP_CLEAR[%d] = 0x%02x", target_byte, result);
        return result;
    }

    u8 read_CP_TOKEN(int target_byte) {
        u8 result = 0;
        log_cp("read CP_TOKEN[%d] = 0x%02x", target_byte, result);
        return result;
    }

    u8 read_CP_FIFO_START(int target_byte) {
        u8 result = 0;
        log_cp("read CP_FIFO_START[%d] = 0x%02x", target_byte, result);
        return result;
    }

    u8 read_CP_FIFO_END(int target_byte) {
        u8 result = 0;
        log_cp("read CP_FIFO_END[%d] = 0x%02x", target_byte, result);
        return result;
    }

    u8 read_CP_FIFO_WP_HI(int target_byte) {
        u8 result = 0;
        log_cp("read CP_FIFO_WP_HI[%d] = 0x%02x", target_byte, result);
        return result;
    }

    u8 read_CP_FIFO_WP_LO(int target_byte) {
        u8 result = 0;
        log_cp("read CP_FIFO_WP_LO[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_STATUS(int target_byte, u8 value) {
    }

    void write_CP_CONTROL(int target_byte, u8 value) {
        if (target_byte == 0) {
            log_cp("fifos_linked set to %s", value.bit(4) ? "true" : "false");
            fifos_linked = value.bit(4);
        }
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
        u8 result = cp_fifo_distance_lo.get_byte(target_byte);
        log_cp("read CP_FIFO_DISTANCE_LO[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_DISTANCE_LO(int target_byte, u8 value) {
        cp_fifo_distance_lo = cp_fifo_distance_lo.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_DISTANCE_HI(int target_byte) {
        u8 result = cp_fifo_distance_hi.get_byte(target_byte);
        log_cp("read CP_FIFO_DISTANCE_HI[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_DISTANCE_HI(int target_byte, u8 value) {
        cp_fifo_distance_hi = cp_fifo_distance_hi.set_byte(target_byte, value);
    }

    u32 cp_fifo_read_ptr_lo;
    u32 cp_fifo_read_ptr_hi;

    u8 read_CP_FIFO_RP_LO(int target_byte) {
        u8 result = cp_fifo_read_ptr_lo.get_byte(target_byte);
        log_cp("read CP_FIFO_RP_LO[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_RP_LO(int target_byte, u8 value) {
        cp_fifo_read_ptr_lo = cp_fifo_read_ptr_lo.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_RP_HI(int target_byte) {
        u8 result = cp_fifo_read_ptr_hi.get_byte(target_byte);
        log_cp("read CP_FIFO_RP_HI[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_RP_HI(int target_byte, u8 value) {
        cp_fifo_read_ptr_hi = cp_fifo_read_ptr_hi.set_byte(target_byte, value);
    }

    u32 cp_fifo_hi_watermark_hi;
    u32 cp_fifo_hi_watermark_lo;
    u32 cp_fifo_lo_watermark_hi;
    u32 cp_fifo_lo_watermark_lo;

    u8 read_CP_FIFO_HI_WM_HI(int target_byte) {
        u8 result = cp_fifo_hi_watermark_hi.get_byte(target_byte);
        log_cp("read CP_FIFO_HI_WM_HI[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_HI_WM_HI(int target_byte, u8 value) {
        cp_fifo_hi_watermark_hi = cp_fifo_hi_watermark_hi.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_HI_WM_LO(int target_byte) {
        u8 result = cp_fifo_hi_watermark_lo.get_byte(target_byte);
        log_cp("read CP_FIFO_HI_WM_LO[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_HI_WM_LO(int target_byte, u8 value) {
        cp_fifo_hi_watermark_lo = cp_fifo_hi_watermark_lo.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_LO_WM_HI(int target_byte) {
        u8 result = cp_fifo_lo_watermark_hi.get_byte(target_byte);
        log_cp("read CP_FIFO_LO_WM_HI[%d] = 0x%02x", target_byte, result);
        return result;
    }

    void write_CP_FIFO_LO_WM_HI(int target_byte, u8 value) {
        cp_fifo_lo_watermark_hi = cp_fifo_lo_watermark_hi.set_byte(target_byte, value);
    }

    u8 read_CP_FIFO_LO_WM_LO(int target_byte) {
        u8 result = cp_fifo_lo_watermark_lo.get_byte(target_byte);
        log_cp("read CP_FIFO_LO_WM_LO[%d] = 0x%02x", target_byte, result);
        return result;
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