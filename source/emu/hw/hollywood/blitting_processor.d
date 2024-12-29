module emu.hw.hollywood.blitting_processor;

import util.bitop;
import util.number;

final class BlittingProcessor {
    private u16 efb_boxcoord_x;
    private u16 efb_boxcoord_y;
    private u16 efb_boxcoord_size_x;
    private u16 efb_boxcoord_size_y;

    private u32 xfb_addr;
    private u32 xfb_stride;

    private u8 copy_clear_color_alpha;
    private u8 copy_clear_color_red;
    private u8 copy_clear_color_green;
    private u8 copy_clear_color_blue;
    private u32 copy_clear_depth;

    private u32[4] bp_filter;
    private u8[7] bp_vfilter_0f;

    private u16 mem_scissor_top;
    private u16 mem_scissor_left;
    private u16 mem_scissor_bottom;
    private u16 mem_scissor_right;

    private u16 mem_scissor_offset_x;
    private u16 mem_scissor_offset_y;

    void write_efb_boxcoord_x(u16 value) {
        efb_boxcoord_x = value;
    }

    void write_efb_boxcoord_y(u16 value) {
        efb_boxcoord_y = value;
    }

    void write_efb_boxcoord_size_x(u16 value) {
        efb_boxcoord_size_x = value;
    }

    void write_efb_boxcoord_size_y(u16 value) {
        efb_boxcoord_size_y = value;
    }

    void write_xfb_addr(u32 value) {
        xfb_addr = value;
    }

    void write_xfb_stride(u32 value) {
        xfb_stride = value;
    }

    void write_copy_clear_color_alpha(u8 value) {
        copy_clear_color_alpha = value;
    }

    void write_copy_clear_color_red(u8 value) {
        copy_clear_color_red = value;
    }

    void write_copy_clear_color_green(u8 value) {
        copy_clear_color_green = value;
    }

    void write_copy_clear_color_blue(u8 value) {
        copy_clear_color_blue = value;
    }

    void write_copy_clear_depth(u32 value) {
        copy_clear_depth = value;
    }

    void write_bp_filter(u32 value, u8 index) {
        bp_filter[index] = value;
    }

    void write_bp_vfilter_0f(u8 value, u8 index) {
        bp_vfilter_0f[index] = value;
    }

    void write_mem_scissor_top(u16 value) {
        mem_scissor_top = value;
    }

    void write_mem_scissor_left(u16 value) {
        mem_scissor_left = value;
    }

    void write_mem_scissor_bottom(u16 value) {
        mem_scissor_bottom = value;
    }

    void write_mem_scissor_right(u16 value) {
        mem_scissor_right = value;
    }

    void write_mem_scissor_offset_x(u16 value) {
        mem_scissor_offset_x = value;
    }

    void write_mem_scissor_offset_y(u16 value) {
        mem_scissor_offset_y = value;
    }
}