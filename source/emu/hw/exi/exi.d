module emu.hw.exi.exi;

import emu.hw.memory.strategy.memstrategy;
import util.bitop;
import util.log;
import util.number;

final class BigGuy : ExiChannel {
    enum Subdevice {
        MaskRom,
        RealTimeClock,
        SRAM,
        UART
    };

    Subdevice subdevice = Subdevice.MaskRom;
    u8[4] read_buffer;
    

    int num_reads = 0;
    override u8 read() {
        return 0;
    }

    override void read_complete() {
        num_reads = 0;
    }

    u8[4] write_buffer;

    int num_writes = 0;
    override void write(u8 value) {
        assert(num_writes < 4);
        log_exi("BigGuy write %02X", value);
        write_buffer[num_writes++] = value;
    }

    override void write_complete() {
        num_writes = 0;

        u32 command = write_buffer[0] << 24 | write_buffer[1] << 16 | write_buffer[2] << 8 | write_buffer[3];

        if (command == 0x00000000) {
            subdevice = Subdevice.MaskRom;
        } else if (command == 0x20000000) {
            subdevice = Subdevice.RealTimeClock;
        } else if (command == 0x20000100) {
            subdevice = Subdevice.SRAM;
        } else if (command == 0x20010000) {
            subdevice = Subdevice.UART;
        }

        log_exi("Selected subdevice: %s", subdevice);
    }
}

final class SerialPort : ExiChannel {
    u8[4] read_buffer;

    int num_reads = 0;
    override u8 read() {
        assert(num_reads < 4);
        return read_buffer[num_reads++];
    }

    override void read_complete() {
        num_reads = 0;
    }

    u8[4] write_buffer;

    int num_writes = 0;
    override void write(u8 value) {
        assert(num_writes < 4);
        write_buffer[num_writes++] = value;
    }

    override void write_complete() {
        num_writes = 0;

        u32 command = write_buffer[0] << 24 | write_buffer[1] << 16 | write_buffer[2] << 8 | write_buffer[3];
        log_exi("EXI command: %08X", command);

        if (command == 0x00000000) {
            log_exi("EXI command: ID");
            read_buffer[0] = 0x04;
            read_buffer[1] = 0x02;
            read_buffer[2] = 0x02;
            read_buffer[3] = 0x00;
        }
    }
}

abstract class ExiChannel {
    abstract u8 read();
    abstract void read_complete();
    abstract void write(u8 value);
    abstract void write_complete();
}

final class ExternalInterface {
    Mem mem;
    void connect_mem(Mem mem) {
        this.mem = mem;
    }

    auto exi_channels = [
        exi_channels_0,
        exi_channels_1,
        exi_channels_2
    ];
    
    const ExiChannel[3] exi_channels_0 = [
        null, new BigGuy(), new SerialPort()
    ];

    const ExiChannel[3] exi_channels_1 = [
        null, null, null
    ];

    const ExiChannel[3] exi_channels_2 = [
        null, null, null
    ];

    ExiChannel get_exi_channel(int x, int channel) {
        switch (channel) {
            case 0b001: return cast(ExiChannel) exi_channels[x][0];
            case 0b010: return cast(ExiChannel) exi_channels[x][1];
            case 0b100: return cast(ExiChannel) exi_channels[x][2];
            default: error_exi("Unknown EXI%d channel %d", x, channel);
        }

        assert(false);
    }

    u32[3] exi_csr;
    void write_EXI_CSR(int target_byte, u8 value, int x) {
        log_exi("EXI_CSR[%d][%d] = %02X", x, target_byte, value);
        exi_csr[x] = exi_csr[x].set_byte(target_byte, value);
    }

    u8 read_EXI_CSR(int target_byte, int x) {
        return exi_csr[x].get_byte(target_byte);
    }

    u32[3] exi_cr;
    void write_EXI_CR(T)(T value, int x) {
        assert(T.sizeof == 4);
        exi_cr[x] = cast(u32) value;

        bool start_transfer = exi_cr[x].bit(0);
        if (start_transfer) {
            log_hollywood("EXI%d transfer start", x);
            log_exi("EXI%d transfer start", x);

            bool is_dma = exi_cr[x].bit(1);

            bool is_write = exi_cr[x].bits(2, 3) != 0;
            bool is_read  = exi_cr[x].bits(2, 3) != 1;
            assert(exi_cr[x].bits(2, 3) != 3);

            if (is_dma) {
                if (is_read && is_write) {
                    error_exi("EXI%d DMA transfer cannot be both read and write", x);
                }
            }

            log_exi("is_write = %d, is_read = %d", is_write, is_read);
            int transfer_size = exi_cr[x].bits(4, 5) + 1;

            ExiChannel channel = get_exi_channel(x, exi_csr[x].bits(7, 9));
            if (channel is null) {
                error_exi("EXI%d channel %d not connected", x, exi_csr[x].bits(7, 9));
            }

            if (!is_dma) { 
                if (is_write) {
                    for (int i = 0; i < transfer_size; i++) {
                        channel.write(exi_data[x].get_byte(0)); 
                    }

                    channel.write_complete();
                }

                if (is_read) {
                    for (int i = 0; i < transfer_size; i++) {
                        exi_data[x] = exi_data[x].set_byte(i, channel.read());
                    }

                    channel.read_complete();
                }
            } else {
                u32 address = exi_mar[x];
                u32 length = exi_len[x];

                if (is_write) {
                    for (int i = 0; i < length; i++) {
                        u8 b = mem.paddr_read_u8(address + i);
                        channel.write(b);
                    }

                    channel.write_complete();
                }

                if (is_read) {
                    for (int i = 0; i < length; i++) {
                        u8 b = channel.read();
                        mem.paddr_write_u8(address + i, b);
                    }

                    channel.read_complete();
                }
            }
            
            exi_cr[x] &= ~1;
        }
    }

    T read_EXI_CR(T)(int x) {
        assert(T.sizeof == 4);
        return cast(T) exi_cr[x];
    }

    u32[3] exi_data;
    void write_EXI_DATA(int target_byte, u8 value, int x) {
        log_exi("EXI_DATA[%d][%d] = %02X", x, target_byte, value);
        exi_data[x] = exi_data[x].set_byte(target_byte, value);
    }

    u8 read_EXI_DATA(int target_byte, int x) {
        log_exi("READING EXI_DATA[%d][%d] = %02X", x, target_byte, exi_data[x].get_byte(target_byte));
        return exi_data[x].get_byte(target_byte);
    }

    u32[3] exi_mar;
    void write_EXI_MAR(int target_byte, u8 value, int x) {
        log_exi("EXI_MAR[%d][%d] = %02X", x, target_byte, value);
        exi_mar[x] = exi_mar[x].set_byte(target_byte, value);

        exi_mar[x] &= 0x03FFFFE0;
    }

    u8 read_EXI_MAR(int target_byte, int x) {
        return exi_mar[x].get_byte(target_byte);
    }

    u32[3] exi_len;
    void write_EXI_LEN(int target_byte, u8 value, int x) {
        log_exi("EXI_LEN[%d][%d] = %02X", x, target_byte, value);
        exi_len[x] = exi_len[x].set_byte(target_byte, value);
    }

    u8 read_EXI_LEN(int target_byte, int x) {
        return exi_len[x].get_byte(target_byte);
    }
}