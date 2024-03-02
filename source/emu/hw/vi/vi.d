module emu.hw.vi.vi;

import emu.hw.memory.strategy.memstrategy;
import emu.hw.vi.vi;
import ui.device;
import util.bitop;
import util.log;
import util.number;

final class VideoInterface {
    enum XBFR_WIDTH  = 640;
    enum XBFR_HEIGHT = 480;

    enum VideoFormat {
        NTSC  = 0,
        PAL   = 1,
        MPAL  = 2,
        DEBUG = 3
    }

    enum DisplayLatchSetting {
        OFF           = 0,
        ON_ONE_FIELD  = 1,
        ON_TWO_FIELDS = 2,
        ALWAYS_ON     = 3
    }

    enum ClockSelect {
        MHZ_27 = 0,
        MHZ_54 = 1
    }

    VideoFormat video_format;
    DisplayLatchSetting display_latch_0;
    DisplayLatchSetting display_latch_1;
    bool display_mode_3;
    bool non_interlaced;
    
    int hsync_start_to_color_burst_start;
    int hsync_start_to_color_burst_end;
    int halfline_width;

    int halfline_to_hblank_start;
    int hsync_start_to_hblank_end;
    int hsync_width;

    int active_video;
    int equalization_pulse;

    int post_blanking_halflines_interval_odd;
    int pre_blanking_halflines_interval_odd;
    int post_blanking_halflines_interval_even;
    int pre_blanking_halflines_interval_even;

    int field3_start_to_burst_blanking_end;
    int field3_start_to_burst_blanking_start;
    int field1_start_to_burst_blanking_end;
    int field1_start_to_burst_blanking_start;

    int field4_start_to_burst_blanking_end;
    int field4_start_to_burst_blanking_start;
    int field2_start_to_burst_blanking_end;
    int field2_start_to_burst_blanking_start;

    int top_field_page_offset;
    int horizontal_offset_of_left_pixel;
    int top_field_fbb_address;

    int bottom_field_page_offset;
    int bottom_field_fbb_address;

    int horizontal_scaling_enable;
    int horizontal_scaling_step_size; // u1.8
    
    int[24] tap;

    ClockSelect clock_select;

    private VideoBuffer video_buffer;
    private Mem mem;
    private PresentVideoBufferCallback present_videobuffer_callback;

    public u8 read_DCR(int target_byte) {
        error_vi("Unimplemented: DCR Read");
        return 0; // TODO
    }

    public void write_DCR(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                if (value.bit(0)) {
                    log_vi("Unimplemented: DCR Enable");
                }

                if (value.bit(1)) {
                    log_vi("Unimplemented: DCR Reset");
                }

                non_interlaced = value.bit(2);
                display_mode_3 = value.bit(3);
                display_latch_0 = cast(DisplayLatchSetting) value.bits(4, 5);
                display_latch_1 = cast(DisplayLatchSetting) value.bits(6, 7);
                break;
            
            case 1:
                video_format = cast(VideoFormat) value.bits(0, 1);
                assert(value.bits(2, 7) == 0);
                break;
        }
    }

    public u8 read_HTR0(int target_byte) {
        error_vi("Unimplemented: HTR0 Read");
        return 0; // TODO
    }

    public void write_HTR0(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                halfline_width &= 0x100;
                halfline_width |= value;
                break;
            
            case 1:
                assert(value.bits(1, 7) == 0);
                halfline_width &= 0xFF;
                halfline_width |= value.bit(0) << 8;
                break;

            case 2:
                assert(value.bit(7) == 0);
                hsync_start_to_color_burst_end = value;
                break;
            
            case 3:
                assert(value.bit(7) == 0);
                hsync_start_to_color_burst_start = value;
                break;
        }
    }

    public u8 read_HTR1(int target_byte) {
        error_vi("Unimplemented: HTR1 Read");
        return 0; // TODO
    }

    public void write_HTR1(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                halfline_to_hblank_start = value.bits(0, 6);
                hsync_start_to_hblank_end &= 0x3FE;
                hsync_start_to_hblank_end |= value.bit(7);
                break;
            
            case 1:
                hsync_start_to_hblank_end &= 0x201;
                hsync_start_to_hblank_end |= value << 1;
                break;

            case 2:
                hsync_start_to_hblank_end &= 0x1FF;
                hsync_start_to_hblank_end |= value.bit(0) << 9;
                hsync_width &= 0x380;
                hsync_width |= value.bits(1, 7);
                break;
            
            case 3:
                assert(value.bits(3, 7) == 0);
                hsync_width &= 0x7F;
                hsync_width |= value.bits(0, 2) << 7;
                break;
        }
    }

    public u8 read_VTR(int target_byte) {
        error_vi("Unimplemented: VTR Read");
        return 0; // TODO
    }

    public void write_VTR(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                equalization_pulse = value.bits(0, 3);
                active_video &= 0x3F0;
                active_video |= value.bits(4, 7);
                break;
            
            case 1:
                active_video &= 0xF;
                active_video |= value << 4;
                break;
        }
    }

    public u8 read_VTO(int target_byte) {
        error_vi("Unimplemented: VTO Read");
        return 0; // TODO
    }

    public void write_VTO(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                post_blanking_halflines_interval_odd &= 0x300;
                post_blanking_halflines_interval_odd |= value;
                break;
            
            case 1:
                post_blanking_halflines_interval_odd &= 0xFF;
                post_blanking_halflines_interval_odd |= value.bits(0, 1) << 8;
                break;
            
            case 2:
                pre_blanking_halflines_interval_odd &= 0x300;
                pre_blanking_halflines_interval_odd |= value;
                break;
            
            case 3:
                pre_blanking_halflines_interval_odd &= 0xFF;
                pre_blanking_halflines_interval_odd |= value.bits(0, 1) << 8;
                break;
        }
    }

    public u8 read_VTE(int target_byte) {
        error_vi("Unimplemented: VTE Read");
        return 0; // TODO
    }

    public void write_VTE(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                post_blanking_halflines_interval_even &= 0x300;
                post_blanking_halflines_interval_even |= value;
                break;
            
            case 1:
                post_blanking_halflines_interval_even &= 0xFF;
                post_blanking_halflines_interval_even |= value.bits(0, 1) << 8;
                break;
            
            case 2:
                pre_blanking_halflines_interval_even &= 0x300;
                pre_blanking_halflines_interval_even |= value;
                break;
            
            case 3:
                pre_blanking_halflines_interval_even &= 0xFF;
                pre_blanking_halflines_interval_even |= value.bits(0, 1) << 8;
                break;
        }
    }

    public u8 read_BBEI(int target_byte) {
        error_vi("Unimplemented: BBEI Read");
        return 0; // TODO
    }

    public void write_BBEI(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                field1_start_to_burst_blanking_start = value.bits(0, 4);
                field1_start_to_burst_blanking_end &= 0x7E0;
                field1_start_to_burst_blanking_end |= value.bits(5, 7);
                break;

            case 1:
                field1_start_to_burst_blanking_end &= 0x7;
                field1_start_to_burst_blanking_end |= value << 3;
                break;
            
            case 2:
                field3_start_to_burst_blanking_start = value.bits(0, 4);
                field3_start_to_burst_blanking_end &= 0x7E0;
                field3_start_to_burst_blanking_end |= value.bits(5, 7);
                break;
            
            case 3:
                field3_start_to_burst_blanking_end &= 0x7;
                field3_start_to_burst_blanking_end |= value << 3;
                break;
        }
    }

    public u8 read_BBOI(int target_byte) {
        error_vi("Unimplemented: BBOI Read");
        return 0; // TODO
    }

    public void write_BBOI(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                field2_start_to_burst_blanking_end = value.bits(0, 4);
                field2_start_to_burst_blanking_start &= 0x7E0;
                field2_start_to_burst_blanking_start |= value.bits(5, 7);
                break;
            
            case 1:
                field2_start_to_burst_blanking_start &= 0x7;
                field2_start_to_burst_blanking_start |= value << 3;
                break;
            
            case 2:
                field4_start_to_burst_blanking_end = value.bits(0, 4);
                field4_start_to_burst_blanking_start &= 0x7E0;
                field4_start_to_burst_blanking_start |= value.bits(5, 7);
                break;
            
            case 3:
                field4_start_to_burst_blanking_start &= 0x7;
                field4_start_to_burst_blanking_start |= value << 3;
                break;
        }
    }

    public u8 read_TFBL(int target_byte) {
        error_vi("Unimplemented: TFBL Read");
        return 0; // TODO
    }

    public void write_TFBL(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0: break;

            case 1:
                top_field_fbb_address &= 0x7F80;
                top_field_fbb_address |= value.bits(1, 7);
                break;
            
            case 2:
                top_field_fbb_address &= 0x7F;
                top_field_fbb_address |= value << 7;
                break;
            
            case 3:
                horizontal_offset_of_left_pixel = value.bits(0, 3);
                top_field_page_offset = value.bit(4);
                break;
        }
    }

    public u8 read_BFBL(int target_byte) {
        error_vi("Unimplemented: BFBL Read");
        return 0; // TODO
    }

    public void write_BFBL(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0: break;

            case 1:
                bottom_field_fbb_address &= 0x7F80;
                bottom_field_fbb_address |= value.bits(1, 7);
                break;
            
            case 2:
                bottom_field_fbb_address &= 0x7F;
                bottom_field_fbb_address |= value << 7;
                break;
            
            case 3:
                bottom_field_page_offset = value.bit(4);
                break;
        }
    }

    public u8 read_HSR(int target_byte) {
        error_vi("Unimplemented: HSR Read");
        return 0; // TODO
    }

    public void write_HSR(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                horizontal_scaling_step_size &= 0x100;
                horizontal_scaling_step_size |= value;
                break;
            
            case 1:
                horizontal_scaling_step_size &= 0xFF;
                horizontal_scaling_step_size |= value.bit(0) << 8;
                horizontal_scaling_enable = value.bit(4);
                break;
        }
    }

    public u8 read_FCTx(int target_byte, int x) {
        error_vi("Unimplemented: FCT%d Read", x);
        return 0; // TODO
    }

    public void write_FCTx(int target_byte, u8 value, int x) {
        if (x < 3) {
            int tap_offset = x * 3;
            final switch (target_byte) {
                case 0:
                    tap[tap_offset + 0] &= 0x300;
                    tap[tap_offset + 0] |= value;
                    break;
                
                case 1:
                    tap[tap_offset + 0] &= 0xFF;
                    tap[tap_offset + 0] |= value.bits(0, 1) << 8;
                    tap[tap_offset + 1] &= 0x3C0;
                    tap[tap_offset + 1] |= value.bits(2, 7);
                    break;
                
                case 2:
                    tap[tap_offset + 1] &= 0x3F;
                    tap[tap_offset + 1] |= value.bits(0, 3) << 6;
                    tap[tap_offset + 2] &= 0x1F0;
                    tap[tap_offset + 2] |= value.bits(4, 7);
                    break;
                
                case 3:
                    tap[tap_offset + 2] &= 0xF;
                    tap[tap_offset + 2] |= value.bits(0, 5) << 4;
                    break;
            }
        } else {
            int tap_offset = 9 + (x - 3) * 4;
            int tap_index = tap_offset + target_byte;

            if (tap_index == 24) {
                return; // tap[24] is all zeros apparently
            } else {
                tap[tap_offset + target_byte] = value;
            }
        }
    }

    public u8 read_VICLK(int target_byte) {
        error_vi("Unimplemented: VICLK Read");
        return 0; // TODO
    }

    public void write_VICLK(int target_byte, u8 value) {
        final switch (target_byte) {
            case 0:
                clock_select = cast(ClockSelect) value.bit(0);
                break;
            
            case 1:
                break;
        }
    }

    public u8 read_UNKNOWN(int target_byte) {
        log_vi("Unimplemented: UNKNOWN Read");
        return 0; // TODO
    }

    public void write_UNKNOWN(int target_byte, u8 value) {
        log_vi("Unimplemented: UNKNOWN Write (%08x)", value);
    }

    public void scanout() {
        for (int field = 0; field < 2; field++) {
            u32 base_address = (this.top_field_fbb_address << 9) + 0x8000_0000 + (field * XBFR_WIDTH * 2);
            for (int y = field; y < XBFR_HEIGHT; y += 2) {
            for (int x = 0;     x < XBFR_WIDTH;  x += 2) {
                u32 ycbycr = mem.read_be_u32(base_address + x * 2 + y * XBFR_WIDTH * 2);

                float cr = ycbycr.get_byte(0);
                float y2 = ycbycr.get_byte(1);
                float cb = ycbycr.get_byte(2);
                float y1 = ycbycr.get_byte(3);

                video_buffer[x + 0][y] = ycbycr_to_rgb(y1, cr, cb);
                video_buffer[x + 1][y] = ycbycr_to_rgb(y2, cr, cb);
            }
            }
        }

        log_vi("Presenting VideoBuffer");

        this.present_videobuffer_callback(video_buffer);
    }

    private Pixel ycbycr_to_rgb(float y, float cr, float cb) {
        import std.algorithm.comparison;

        return Pixel(
            cast(u8) clamp((y + 1.371f * (cr - 128)), 0, 255),
            cast(u8) clamp((y - 0.698f * (cr - 128) - 0.336f * (cb - 128)), 0, 255),
            cast(u8) clamp((y + 1.732f * (cb - 128)), 0, 255)
        );
    }

    public void set_present_videobuffer_callback(PresentVideoBufferCallback callback) {
        this.present_videobuffer_callback = callback;
    }

    public void connect_mem(Mem mem) {
        this.mem = mem;
    }
}