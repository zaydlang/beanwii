module emu.hw.ipc.usb.extensions.nunchuk;

import emu.hw.ipc.usb.extensions.extension;
import util.number;

final class NunchukExtension : WiimoteExtension {
    override u8[6] get_report_data() {
        return [0, 0, 0, 0, 0, 0];
    }

    override u8[6] get_id() {
        return [0x00, 0x00, 0xA4, 0x20, 0x00, 0x00];
    }
}
