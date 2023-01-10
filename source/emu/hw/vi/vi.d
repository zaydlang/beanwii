module emu.hw.vi.vi;

import util.bitop;
import util.log;
import util.number;

final class VideoInterface {
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

    VideoFormat video_format;
    DisplayLatchSetting display_latch_0;
    DisplayLatchSetting display_latch_1;
    bool display_mode_3;
    bool non_interlaced;

    u8 read_DCR(int target_byte) {
        error_vi("Unimplementd: DCR Read");
        return 0; // TODO
    }

    void write_DCR(int target_byte, u8 value) {
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
}