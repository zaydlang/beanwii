module emu.hw.cp.cp;

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

    u8 read_CP_FIFO_WP(int target_byte) {
        return 0;
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

    void write_CP_FIFO_WP(int target_byte, u8 value) {

    }
}