module emu.hw.ipc.usb.extensions.extension;

import emu.hw.ipc.usb.extensions.nunchuk;
import util.number;

enum WiimoteExtensionType {
    Nunchuk,
}

interface WiimoteExtension {
    u8[6] get_report_data();
    u8[6] get_id();
}

WiimoteExtension create_extension(WiimoteExtensionType type) {
    final switch (type) {
        case WiimoteExtensionType.Nunchuk:
            return new NunchukExtension();
    }
}
