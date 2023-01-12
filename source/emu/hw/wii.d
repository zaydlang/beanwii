module emu.hw.wii;

import emu.encryption.partition;
import emu.encryption.ticket;
import emu.hw.broadway.cpu;
import emu.hw.broadway.hle;
import emu.hw.cp.cp;
import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.layout;
import emu.hw.disk.readers.diskreader;
import emu.hw.disk.readers.wbfs;
import emu.hw.memory.strategy.memstrategy;
import emu.hw.hollywood.hollywood;
import emu.hw.vi.vi;
import ui.device;
import util.array;
import util.log;
import util.number;

final class Wii {
    private Broadway         broadway;
    private Hollywood        hollywood;
    private Mem              mem;

    private CommandProcessor command_processor;
    private VideoInterface   video_interface;

    this() {
        this.command_processor = new CommandProcessor();
        this.video_interface   = new VideoInterface();

        this.mem               = new Mem();
        this.broadway          = new Broadway();
        this.hollywood         = new Hollywood();

        this.broadway.connect_mem(this.mem);
        this.video_interface.connect_mem(this.mem);
        this.mem.connect_command_processor(this.command_processor);
        this.mem.connect_video_interface(this.video_interface);
    }

    public void cycle(int num_cycles) {
        int cycles_elapsed = 0;

        while (cycles_elapsed < num_cycles) {
            cycles_elapsed += this.broadway.run() * 2;
        }

        this.video_interface.scanout();
    }

    public void load_wii_disk(WiiApploader* apploader, WiiDol* dol) {
        if (apploader !is null) {
            this.run_apploader(apploader);
        }

        assert(dol !is null);

        this.mem.map_dol(dol);
        this.broadway.set_pc(cast(u32) dol.header.entry_point);

        this.broadway.set_gpr(1,  0x816ffff0); // ????
        this.broadway.set_gpr(2,  0x81465cc0);
        this.broadway.set_gpr(13, 0x81465320);
    }

    public void connect_multimedia_device(MultiMediaDevice device) {
        this.video_interface.set_present_videobuffer_callback(&device.present_videobuffer);
    }

    private void run_apploader(WiiApploader* apploader) {
        log_apploader("Apploader info:");
        log_apploader("  Size:         %x", cast(s32) apploader.header.size);
        log_apploader("  Trailer size: %x", cast(s32) apploader.header.trailer_size);
        log_apploader("  Entry point:  %x", cast(u32) apploader.header.entry_point);

        this.mem.map_buffer(apploader.data.ptr, cast(s32) apploader.header.size, WII_APPLOADER_LOAD_ADDRESS);

        // r1 is reserved for the stack, so let's just set the stack somewhere arbitrary that won't
        // conflict with the apploader code
        this.broadway.set_gpr(1, 0x8001_0000);

        // arguments
        this.broadway.set_gpr(3, 0x8000_0000);
        this.broadway.set_gpr(4, 0x8000_0004);
        this.broadway.set_gpr(5, 0x8000_0008);

        log_apploader("Running apploader entry...");
        this.broadway.set_pc(cast(u32) apploader.header.entry_point);
        this.broadway.run_until_return();

        u32 init_ptr  = cast(u32) this.mem.read_be_u32(0x8000_0000);
        u32 main_ptr  = cast(u32) this.mem.read_be_u32(0x8000_0004);
        u32 close_ptr = cast(u32) this.mem.read_be_u32(0x8000_0008);

        log_apploader("Apploader entry() returned.");
        log_apploader("Apploader init  ptr = %08x", init_ptr);
        log_apploader("Apploader main  ptr = %08x", main_ptr);
        log_apploader("Apploader close ptr = %08x", close_ptr);

        this.broadway.set_pc(init_ptr);
        u32 hle_func_addr = this.broadway.get_hle_context().add_hle_func(&hle_os_report, &this.mem);
        this.broadway.set_gpr(3, hle_func_addr);
        this.broadway.run_until_return();
        log_apploader("Apploader init() returned.");

        while (true) {}
    }
}
