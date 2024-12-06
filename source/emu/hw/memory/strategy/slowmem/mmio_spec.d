module emu.hw.memory.strategy.slowmem.mmio_spec;

import emu.hw.broadway.interrupt;
import emu.hw.cp.cp;
import emu.hw.memory.strategy.slowmem.mmio_gen;
import emu.hw.memory.strategy.memstrategy;
import emu.hw.ai.ai;
import emu.hw.di.di;
import emu.hw.dsp.dsp;
import emu.hw.exi.exi;
import emu.hw.hollywood.hollywood;
import emu.hw.pe.pe;
import emu.hw.si.si;
import emu.hw.vi.vi;
import emu.hw.ipc.ipc;
import util.number;

final class Mmio {
    private MmioGen!(mmio_spec, Mmio) gen;

    public AudioInterface      audio_interface;
    public CommandProcessor    command_processor;
    public DSP                 dsp;
    public DVDInterface        dvd_interface;
    public ExternalInterface   external_interface;
    public VideoInterface      video_interface;
    public PixelEngine         pixel_engine;
    public SerialInterface     serial_interface;
    public InterruptController interrupt_controller;
    public IPC                 ipc;
    public Hollywood           hollywood;
    public Mem                 memory;

    static const mmio_spec = [
        MmioRegister("command_processor",    "CP_FIFO_STATUS",        0xCC00_0000, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_CONTROL",            0xCC00_0002, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_CLEAR",              0xCC00_0004, 2, READ_WRITE),
        MmioRegister("command_processor",    "UNKNOWN_CC000006",      0xCC00_0006, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_TOKEN",              0xCC00_000E, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_START",         0xCC00_0020, 4, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_END",           0xCC00_0024, 4, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_HI_WM_LO",      0xCC00_0028, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_HI_WM_HI",      0xCC00_002A, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_LO_WM_LO",      0xCC00_002C, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_LO_WM_HI",      0xCC00_002E, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_DISTANCE_LO",   0xCC00_0030, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_DISTANCE_HI",   0xCC00_0032, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_WP",            0xCC00_0034, 4, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_RP_LO",         0xCC00_0038, 2, READ_WRITE),
        MmioRegister("command_processor",    "CP_FIFO_RP_HI",         0xCC00_003A, 2, READ_WRITE),
        MmioRegister("pixel_engine",         "Z_CONFIG",              0xCC00_1000, 2, READ_WRITE),
        MmioRegister("pixel_engine",         "ALPHA_CONFIG",          0xCC00_1002, 2, READ_WRITE),
        MmioRegister("pixel_engine",         "DESTINATION_ALPHA",     0xCC00_1004, 2, READ_WRITE),
        MmioRegister("pixel_engine",         "ALPHA_MODE",            0xCC00_1006, 2, READ_WRITE),
        MmioRegister("pixel_engine",         "ALPHA_READ",            0xCC00_1008, 2, READ_WRITE),
        MmioRegister("pixel_engine",         "PE_IRQ",                0xCC00_100A, 2, READ_WRITE),
        MmioRegister("pixel_engine",         "PE_TOKEN",              0xCC00_100E, 2, READ_WRITE),
        MmioRegister("video_interface",      "VTR",                   0xCC00_2000, 2, READ_WRITE),
        MmioRegister("video_interface",      "DCR",                   0xCC00_2002, 2, READ_WRITE),
        MmioRegister("video_interface",      "HTR0",                  0xCC00_2004, 4, READ_WRITE),
        MmioRegister("video_interface",      "HTR1",                  0xCC00_2008, 4, READ_WRITE),
        MmioRegister("video_interface",      "VTO",                   0xCC00_200C, 4, READ_WRITE),
        MmioRegister("video_interface",      "VTE",                   0xCC00_2010, 4, READ_WRITE),
        MmioRegister("video_interface",      "BBEI",                  0xCC00_2014, 4, READ_WRITE),
        MmioRegister("video_interface",      "BBOI",                  0xCC00_2018, 4, READ_WRITE),
        MmioRegister("video_interface",      "TFBL",                  0xCC00_201C, 4, READ_WRITE),
        MmioRegister("video_interface",      "BFBL",                  0xCC00_2024, 4, READ_WRITE),
        MmioRegister("video_interface",      "DIx",                   0xCC00_2030, 4, READ_WRITE).repeat(4, 4),
        MmioRegister("video_interface",      "HSW",                   0xCC00_2048, 2, READ_WRITE),
        MmioRegister("video_interface",      "HSR",                   0xCC00_204A, 2, READ_WRITE),
        MmioRegister("video_interface",      "FCTx",                  0xCC00_204C, 4, READ_WRITE).repeat(7, 4),
        MmioRegister("video_interface",      "VICLK",                 0xCC00_206C, 2, READ_WRITE),
        MmioRegister("video_interface",      "VISEL",                 0xCC00_206E, 2, READ_WRITE),
        MmioRegister("video_interface",      "UNKNOWN",               0xCC00_2070, 2, READ_WRITE),
        MmioRegister("video_interface",      "HBE",                   0xCC00_2072, 2, READ_WRITE),
        MmioRegister("video_interface",      "HBS",                   0xCC00_2074, 2, READ_WRITE),
        MmioRegister("interrupt_controller", "UNKNOWN_CC003024",      0xCC00_3024, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "UNKNOWN_CC00302C",      0xCC00_302C, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "INTERRUPT_CAUSE",       0xCC00_3000, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "INTERRUPT_MASK",        0xCC00_3004, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "FIFO_BASE_START",       0xCC00_300C, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "FIFO_BASE_END",         0xCC00_3010, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "FIFO_WRITE_PTR",        0xCC00_3014, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "UNKNOWN_CC003018",      0xCC00_3018, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "UNKNOWN_CC00301C",      0xCC00_301C, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "UNKNOWN_CC003020",      0xCC00_3020, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "HW_PPCIRQFLAG",         0xCD00_0030, 4, READ_WRITE),
        MmioRegister("interrupt_controller", "HW_PPCIRQMASK",         0xCD00_0034, 4, READ_WRITE),
        MmioRegister("memory",               "MI_PROT_TYPE",          0xCC00_4010, 2, READ_WRITE),
        MmioRegister("memory",               "MI_INTERRUPT_MASK",     0xCC00_401C, 4, READ_WRITE),
        MmioRegister("memory",               "UNKNOWN_CC004020",      0xCC00_4020, 2, READ_WRITE),
        MmioRegister("audio_interface",      "AI_CONTROL",            0xCD00_6C00, 4, READ_WRITE),
        MmioRegister("audio_interface",      "AIVR",                  0xCD00_6C04, 4, READ_WRITE),
        MmioRegister("audio_interface",      "AISCNT",                0xCD00_6C08, 4, READ_WRITE),
        MmioRegister("audio_interface",      "AIIT",                  0xCD00_6C0C, 4, READ_WRITE),
        MmioRegister("audio_interface",      "HW_PLLAI",              0xCD00_01CC, 4, READ_WRITE),
        MmioRegister("audio_interface",      "HW_PLLAIEXT",           0xCD00_01D0, 4, READ_WRITE),
        MmioRegister("dsp",                  "DSP_MAILBOX_TO_HIGH",   0xCC00_5000, 2, READ_WRITE),
        MmioRegister("dsp",                  "DSP_MAILBOX_TO_LOW",    0xCC00_5002, 2, READ_WRITE),
        MmioRegister("dsp",                  "DSP_MAILBOX_FROM_HIGH", 0xCC00_5004, 2, READ),
        MmioRegister("dsp",                  "DSP_MAILBOX_FROM_LOW",  0xCC00_5006, 2, READ),
        MmioRegister("dsp",                  "DSP_CSR",               0xCC00_500A, 2, READ_WRITE),
        MmioRegister("dsp",                  "ARAM_SIZE",             0xCC00_5012, 2, READ_WRITE),
        MmioRegister("dsp",                  "AR_ARAM_MMADDR",        0xCC00_5020, 4, READ_WRITE),
        MmioRegister("dsp",                  "AR_ARAM_ARADDR",        0xCC00_5024, 4, READ_WRITE),
        MmioRegister("dsp",                  "AR_DMA_CNT",            0xCC00_5028, 4, READ_WRITE),
        MmioRegister("external_interface",   "EXI_CSR",               0xCD00_6800, 4, READ_WRITE).repeat(3, 0x14),
        MmioRegister("external_interface",   "EXI_MAR",               0xCD00_6804, 4, READ_WRITE).repeat(3, 0x14),
        MmioRegister("external_interface",   "EXI_LEN",               0xCD00_6808, 4, READ_WRITE).repeat(3, 0x14),
        MmioRegister("external_interface",   "EXI_CR",                0xCD00_680C, 4, READ_WRITE).repeat(3, 0x14).dont_decompose_into_bytes(),
        MmioRegister("external_interface",   "EXI_DATA",              0xCD00_6810, 4, READ_WRITE).repeat(3, 0x14),
        MmioRegister("hollywood",            "GX_FIFO",               0xCC00_8000, 8,      WRITE).dont_decompose_into_bytes(),
        MmioRegister("ipc",                  "HW_IPC_PPCMSG",         0xCD00_0000, 4, READ_WRITE),
        MmioRegister("ipc",                  "HW_IPC_PPCCTRL",        0xCD00_0004, 4, READ_WRITE).dont_decompose_into_bytes(),
        MmioRegister("ipc",                  "HW_IPC_ARMMSG",         0xCD00_0008, 4, READ),
        MmioRegister("dvd_interface",        "DICFG",                 0xCD00_6024, 4, READ),
        MmioRegister("dvd_interface",        "HW_COMPAT",             0xCD00_0180, 4, READ_WRITE),
        MmioRegister("serial_interface",     "SICxOUTBUF",            0xCD00_6400, 4, READ_WRITE).repeat(4, 0xC),
        MmioRegister("serial_interface",     "SIPOLL",                0xCD00_6430, 4, READ_WRITE),
        MmioRegister("serial_interface",     "SICOMCSR",              0xCD00_6434, 4, READ_WRITE),
        MmioRegister("serial_interface",     "SISR",                  0xCD00_6438, 4, READ_WRITE),
        MmioRegister("serial_interface",     "SIEXILK",               0xCD00_643C, 4, READ_WRITE),
        MmioRegister("serial_interface",     "SIOBUF",                0xCD00_6480, 4, READ_WRITE),
        MmioRegister("video_interface",      "GPIOB_STUB",            0xCD00_00C0, 4, READ_WRITE).repeat(7, 4),
    ];

    this() {
        this.gen = new MmioGen!(mmio_spec, Mmio)(this);
    }

    u32 get_effective_address(u32 address) {
        if (address >= 0xCD000030 && address < 0xCD80021C) {
            return 0xCD000000 | (address & 0x000F_FFFF);
        } else {
            return address;
        }
    }

    public T read(T)(u32 address) {
        return this.gen.read!(T)(get_effective_address(address));
    }

    public void write(T)(u32 address, T value) {
        this.gen.write!(T)(get_effective_address(address), value);
    }

    public void connect_audio_interface(AudioInterface audio_interface) {
        this.audio_interface = audio_interface;
    }

    public void connect_command_processor(CommandProcessor command_processor) {
        this.command_processor = command_processor;
    }

    public void connect_dsp(DSP dsp) {
        this.dsp = dsp;
    }

    public void connect_external_interface(ExternalInterface external_interface) {
        this.external_interface = external_interface;
    }

    public void connect_video_interface(VideoInterface video_interface) {
        this.video_interface = video_interface;
    }

    public void connect_dvd_interface(DVDInterface dvd_interface) {
        this.dvd_interface = dvd_interface;
    }

    public void connect_serial_interface(SerialInterface serial_interface) {
        this.serial_interface = serial_interface;
    }

    public void connect_interrupt_controller(InterruptController interrupt_controller) {
        this.interrupt_controller = interrupt_controller;
    }

    public void connect_ipc(IPC ipc) {
        this.ipc = ipc;
    }

    public void connect_memory(Mem memory) {
        this.memory = memory;
    }

    public void connect_pixel_engine(PixelEngine pe) {
        this.pixel_engine = pe;
    }

    public void connect_hollywood(Hollywood hollywood) {
        this.hollywood = hollywood;
    }
}