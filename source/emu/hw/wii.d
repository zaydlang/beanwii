module emu.hw.wii;

import emu.encryption.partition;
import emu.encryption.ticket;
import emu.hw.broadway.cpu;
import emu.hw.broadway.hle;
import emu.hw.broadway.interrupt;
import emu.hw.cp.cp;
import emu.hw.disk.apploader;
import emu.hw.disk.dol;
import emu.hw.disk.layout;
import emu.hw.disk.readers.filereader;
import emu.hw.disk.readers.wbfs;
import emu.hw.memory.spec;
import emu.hw.memory.strategy.memstrategy;
import emu.hw.hollywood.hollywood;
import emu.hw.ai.ai;
import emu.hw.dsp.dsp;
import emu.hw.exi.exi;
import emu.hw.ipc.ipc;
import emu.hw.si.si;
import emu.hw.vi.vi;
import emu.scheduler;
import ui.device;
import util.array;
import util.log;
import util.number;

final class Wii {
    public  Broadway         broadway;
    private Hollywood        hollywood;
    public  Mem              mem;

    private AudioInterface    audio_interface;
    private CommandProcessor  command_processor;
    private DSP               dsp;
    private ExternalInterface external_interface;
    private VideoInterface    video_interface;
    private SerialInterface   serial_interface;
    private IPC               ipc;

    private Scheduler        scheduler;

    this(size_t ringbuffer_size) {
        this.command_processor  = new CommandProcessor();
        this.video_interface    = new VideoInterface();
        this.serial_interface   = new SerialInterface();
        this.audio_interface    = new AudioInterface();
        this.ipc                = new IPC();
        this.external_interface = new ExternalInterface();
        this.dsp                = new DSP();
        this.mem                = new Mem();
        this.broadway           = new Broadway(ringbuffer_size);
        this.hollywood          = new Hollywood();
        this.scheduler          = new Scheduler();

        this.broadway.connect_mem(this.mem);
        this.broadway.connect_scheduler(this.scheduler);
        this.external_interface.connect_mem(this.mem);
        this.video_interface.connect_mem(this.mem);
        this.video_interface.connect_interrupt_controller(this.broadway.get_interrupt_controller());
        this.mem.connect_audio_interface(this.audio_interface);
        this.mem.connect_command_processor(this.command_processor);
        this.mem.connect_dsp(this.dsp);
        this.mem.connect_external_interface(this.external_interface);
        this.mem.connect_video_interface(this.video_interface);
        this.mem.connect_serial_interface(this.serial_interface);
        this.mem.connect_interrupt_controller(this.broadway.get_interrupt_controller());
        this.mem.connect_ipc(this.ipc);
        this.mem.connect_broadway(this.broadway);
        this.ipc.connect_mem(this.mem);
        this.ipc.connect_scheduler(this.scheduler);
        this.ipc.connect_interrupt_controller(this.broadway.get_interrupt_controller());

        g_logger_scheduler = &this.scheduler;

        this.broadway.reset();
    }

    public void cycle(int num_cycles) {
        this.broadway.cycle(num_cycles);
        this.video_interface.scanout();
    }

    public void single_step() {
        this.broadway.single_step();
    }

    public void load_disk(u8[] wii_disk_data) {
        this.setup_global_memory_value(wii_disk_data);

        WiiApploader* apploader = cast(WiiApploader*) &wii_disk_data[WII_APPLOADER_OFFSET];
        this.run_apploader(apploader, wii_disk_data);
    }

    public void load_dol(WiiDol* dol) {
        this.mem.map_dol(dol);
        this.broadway.set_pc(cast(u32) dol.header.entry_point);

        // this.broadway.set_gpr(1,  0x816ffff0); // ????
        // this.broadway.set_gpr(2,  0x81465cc0);
        // this.broadway.set_gpr(13, 0x81465320);
    }

    public void connect_multimedia_device(MultiMediaDevice device) {
        this.video_interface.set_present_videobuffer_callback(&device.present_videobuffer);
    }

    private void run_apploader(WiiApploader* apploader, u8[] wii_disk_data) {
        log_apploader("Apploader info:");
        log_apploader("  Size:         %x", cast(s32) apploader.header.size);
        log_apploader("  Trailer size: %x", cast(s32) apploader.header.trailer_size);
        log_apploader("  Entry point:  %x", cast(u32) apploader.header.entry_point);

        this.mem.map_buffer(apploader.data.ptr, cast(s32) apploader.header.size, WII_APPLOADER_LOAD_ADDRESS);

        // r1 is reserved for the stack, so let's just set the stack somewhere arbitrary that won't
        // conflict with the apploader code
        this.broadway.set_gpr(1, 0x8001_0000);

        // arguments
        this.broadway.set_gpr(3, 0x8060_0000);
        this.broadway.set_gpr(4, 0x8060_0004);
        this.broadway.set_gpr(5, 0x8060_0008);

        log_apploader("Running apploader...");
        this.broadway.set_pc(cast(u32) apploader.header.entry_point);
        this.broadway.run_until_return();

        u32 init_ptr  = cast(u32) this.mem.read_be_u32(0x8060_0000);
        u32 main_ptr  = cast(u32) this.mem.read_be_u32(0x8060_0004);
        u32 close_ptr = cast(u32) this.mem.read_be_u32(0x8060_0008);

        log_apploader("Apploader entry() returned.");
        log_apploader("Apploader init  ptr = %08x", init_ptr);
        log_apploader("Apploader main  ptr = %08x", main_ptr);
        log_apploader("Apploader close ptr = %08x", close_ptr);


        import util.dump;

        this.broadway.set_pc(init_ptr);
        u32 hle_func_addr = this.broadway.get_hle_context().add_hle_func(&hle_os_report, &this.mem);
        this.broadway.set_gpr(3, hle_func_addr);
        this.broadway.run_until_return();
        log_apploader("Apploader init() returned.");

        do {
            this.broadway.set_gpr(3, 0x8060_0000);
            this.broadway.set_gpr(4, 0x8060_0004);
            this.broadway.set_gpr(5, 0x8060_0008);
            this.broadway.set_pc(main_ptr);
            this.broadway.run_until_return();

            // the following behavior is literally documented nowhere
            // i only found out about this by looking at the source code for the dolphin emulator
            // in fact, there's wrong documentation about this on the wiibrew wiki, and yagc, and
            // i only found out that the documentation was wrong because i decompiled the apploader
            // and found something that contradicted the documentation
            // i'm not even kidding

            u32 disk_read_dest   = cast(u32) this.mem.read_be_u32(0x8060_0000);
            u32 disk_read_size   = cast(u32) this.mem.read_be_u32(0x8060_0004);
            u32 disk_read_offset = cast(u32) this.mem.read_be_u32(0x8060_0008) << 2;
            log_apploader("Apploader main() read request: dest = %08x, size = %08x, offset = %08x", disk_read_dest, disk_read_size, disk_read_offset);
            for (int i = 0; i < disk_read_size; i++) {
                this.mem.write_be_u8(disk_read_dest + i, wii_disk_data[disk_read_offset + i]);
            }
            
            log_apploader("Apploader main() returned.");
        } while (this.broadway.get_gpr(3) != 0);

        this.broadway.set_pc(close_ptr);
        this.broadway.run_until_return();
        log_apploader("Apploader close() returned. Obtained entrypoint: %x", this.broadway.get_gpr(3));

        broadway.should_log = true;
        dump(this.mem.mem1, "mem1.bin");

        u32 entrypoint = this.broadway.get_gpr(3);
        assert(entrypoint != 0);
        this.broadway.set_pc(entrypoint);
    }

    private void setup_global_memory_value(u8[] wii_disk_data) {
        WiiHeader* header = cast(WiiHeader*) wii_disk_data.ptr;

        // https://wiibrew.org/wiki/Memory_map

        this.mem.write_be_u32(0x8000_0000, cast(u32) wii_disk_data.read_be!u32(0));
        this.mem.write_be_u16(0x8000_0004, cast(u16) header.maker_code);
        this.mem.write_be_u8 (0x8000_0006, header.disk_number);
        this.mem.write_be_u8 (0x8000_0007, header.disk_version);
        this.mem.write_be_u8 (0x8000_0008, header.audio_streaming_enabled);
        this.mem.write_be_u8 (0x8000_0009, header.stream_buffer_size);
        this.mem.write_be_u32(0x8000_0018, WII_MAGIC_WORD);
        this.mem.write_be_u32(0x8000_0020, 0x0D15_EA5E); // Nintendo Standard Boot Code
        this.mem.write_be_u32(0x8000_0028, MEM1_SIZE); 
        this.mem.write_be_u32(0x8000_002C, 0x0000_0023); // Production Board Model
        this.mem.write_be_u32(0x8000_0030, 0x0000_0000); // Arena Low
        this.mem.write_be_u32(0x8000_0034, 0x817F_EC60); // Arena High
        this.mem.write_be_u32(0x8000_0038, cast(u32) wii_disk_data.read_be!u32(WII_FILE_SYSTEM_START_OFFSET));
        this.mem.write_be_u32(0x8000_003C, cast(u32) wii_disk_data.read_be!u32(WII_FILE_SYSTEM_MAX_SIZE_OFFSET));
        this.mem.write_be_u32(0x8000_0048, 0x8134_0000); // DB exception destination
        this.mem.write_be_u32(0x8000_00C4, 0xFFFF_FF00); // User interrupt mask
        this.mem.write_be_u32(0x8000_00C0, 0); // Revolution OS interrupt mask
        this.mem.write_be_u32(0x8000_00CC, 0); // NTSC TODO: is it okay to just keep this as NTSC?
        this.mem.write_be_u32(0x8000_00D8, 0); // OSContext to save FPRs to
        this.mem.write_be_u32(0x8000_00EC, 0); // Dev Debugger Monitor Address (Not present)
        this.mem.write_be_u32(0x8000_00F0, 0x0180_0000); // Simulated Memory Size
        this.mem.write_be_u32(0x8000_00F8, 0x0E7B_E2C0); // Console Bus Speed
        this.mem.write_be_u32(0x8000_00FC, 0x2B73_A840); // Console CPU Speed
        this.mem.write_be_u64(0x8000_30D8, 0x0054_98F0_5340_7000); // System Time
        this.mem.write_be_u32(0x8000_30F0, 0); // DOL Execute Parameters
        this.mem.write_be_u32(0x8000_3118, 0x0400_0000); // Physical MEM2 size
        this.mem.write_be_u32(0x8000_311C, 0x0400_0000); // Simulated MEM2 size
        this.mem.write_be_u32(0x8000_3120, 0x9340_0000); // End of MEM2 addressable to PPC
        this.mem.write_be_u32(0x8000_3124, 0x9000_0800); // Usable MEM2 Start
        this.mem.write_be_u32(0x8000_3128, 0x933E_0000); // Usable MEM2 End
        this.mem.write_be_u32(0x8000_3130, 0x933E_0000); // IOS IPC Buffer Start
        this.mem.write_be_u32(0x8000_3134, 0x9340_0000); // IOS IPC Buffer End
        this.mem.write_be_u32(0x8000_3138, 0x0000_0011); // Hollywood Version
        this.mem.write_be_u32(0x8000_3140, 0x0090_0204); // IOS Version (IOS9, v2.4)
        this.mem.write_be_u32(0x8000_3144, 0x0006_2507); // IOS Build Date (06/25/2007)
        this.mem.write_be_u32(0x8000_3148, 0x9360_0000); // IOS Reserved Heap Start
        this.mem.write_be_u32(0x8000_314C, 0x9362_0000); // IOS Reserved Heap End
        this.mem.write_be_u32(0x8000_3158, 0x0000_FF16); // GDPR Vendor Code
        this.mem.write_be_u8 (0x8000_315C, 0x80); // Some boot flag
        this.mem.write_be_u8 (0x8000_315D, 0x00); // Enable legacy DI mode (must be set if loading GC apploader)
        this.mem.write_be_u16(0x8000_315E, 0x0113); // Devkit boot program version (v1.13)
        this.mem.write_be_u32(0x8000_3160, 0x0000_0000); // Init sempahore
        this.mem.write_be_u32(0x8000_3164, 0x0000_0000); // GC MIOS mode flag
        this.mem.write_be_u32(0x8000_3180, cast(u32) wii_disk_data.read_be!u32(0)); // Game ID
        this.mem.write_be_u8 (0x8000_3184, 0x80); // Application Type - 0x80 for disk games, 0x81 for channels.
        this.mem.write_be_u8 (0x8000_3186, 0); // Application Type 2. Apparently set when a game loads a channel.
        this.mem.write_be_u32(0x8000_3188, 0x00351011); // Minimum IOS version
        this.mem.write_be_u32(0x8000_318C, 0); // Title Booted from NAND (Launch Code)
        this.mem.write_be_u32(0x8000_3190, 0); // Title Booted from NAND (Return Code)
        this.mem.write_be_u32(0x8000_3194, 0); // Data Partition Type

        // TODO: You silly address, you are going to need a refactor to implement cleanly. I'll just put an assert
        // in slowmem to make sure nobody reads from you.
        this.mem.write_be_u32(0x8000_3198, 0xDEADBEEF);

        this.mem.write_be_u8 (0x8000_319C, 0x80); // Single-layer 
    }

    public void on_error() {
        broadway.on_error();
    }

    public void load_sysconf(u8[] sysconf_data) {
        this.ipc.load_sysconf(sysconf_data);
    }
}