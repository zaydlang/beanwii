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
    private u8 tex_copy_format;

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

    private u8 alpha_comp0;
    private u8 alpha_comp1;
    private u8 alpha_aop;
    private u8 alpha_ref0;
    private u8 alpha_ref1;

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

    void write_tex_copy_format(u8 value) {
        tex_copy_format = value;
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

    void write_alpha_compare(u32 value) {
        alpha_comp0 = cast(u8) value.bits(16, 18);
        alpha_comp1 = cast(u8) value.bits(19, 21);
        alpha_aop = cast(u8) value.bits(22, 23);
        alpha_ref0 = cast(u8) value.bits(0, 7);
        alpha_ref1 = cast(u8) value.bits(8, 15);
    }
    
    u16 get_efb_boxcoord_x() { return efb_boxcoord_x; }
    u16 get_efb_boxcoord_y() { return efb_boxcoord_y; }
    u16 get_efb_boxcoord_size_x() { return efb_boxcoord_size_x; }
    u16 get_efb_boxcoord_size_y() { return efb_boxcoord_size_y; }
    u32 get_xfb_addr() { return xfb_addr; }
    u8 get_tex_copy_format() { return tex_copy_format; }
    
    u8 get_copy_clear_color_red() { return copy_clear_color_red; }
    u8 get_copy_clear_color_green() { return copy_clear_color_green; }
    u8 get_copy_clear_color_blue() { return copy_clear_color_blue; }
    u8 get_copy_clear_color_alpha() { return copy_clear_color_alpha; }
    u32 get_copy_clear_depth() { return copy_clear_depth; }

    u8 get_alpha_comp0() { return alpha_comp0; }
    u8 get_alpha_comp1() { return alpha_comp1; }
    u8 get_alpha_aop() { return alpha_aop; }
    u8 get_alpha_ref0() { return alpha_ref0; }
    u8 get_alpha_ref1() { return alpha_ref1; }
}