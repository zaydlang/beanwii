module emu.hw.memory.strategy.hardware_accelerated_mem.mmio_gen;

import util.bitop;
import util.number;
import util.log;

enum {
    READ,
    WRITE,
    READ_WRITE
}

struct MmioRegister {
    this(string component, string name, uint address, int size, int access_type) {
        this.component      = component;
        this.name           = name;
        this.address        = address;
        this.size           = size;
        this.readable       = access_type != WRITE;
        this.writeable      = access_type != READ;

        this.stride         = -1;
        this.cnt            = -1;
        this.all_at_once    = false;
        this.filter_enabled = false;
        this.implemented    = true;
    }

    MmioRegister repeat(int cnt, int stride) {
        this.cnt    = cnt;
        this.stride = stride;

        return this;
    } 

    MmioRegister dont_decompose_into_bytes() {
        this.all_at_once = true;
        return this;
    }

    MmioRegister filter(bool function(int i) new_f)() {
        this.filter_enabled = true;
        this.f = new_f;
        return this;
    }

    MmioRegister unimplemented() {
        this.implemented = false;
        this.all_at_once = true;
        return this;
    }
    
    string component;
    string name;
    u32   address;
    int    size;

    int    cnt;
    int    stride;

    bool   all_at_once;

    bool   readable;
    bool   writeable;

    bool   filter_enabled;
    bool function(int i) f;

    bool   implemented;
}

final class MmioGen(MmioRegister[] mmio_registers, T) {
    T context;

    this(T context) {
        this.context = context;
    }

    // static foreach (MmioRegister mr; mmio_registers) {
    //     mixin("enum %s = %d;".format(mr.name, mr.address));
    // }

    string get_mmio_reg_from_address(u32 address, out int offset) {
        import std.array;
        import std.conv;

        static foreach (MmioRegister mr; mmio_registers) {
            static if (mr.stride == -1) {
                if (address >= mr.address && address < mr.address + mr.size) {
                    offset = address - mr.address;
                    return mr.name;
                }
            } else {
                static foreach (int i; 0..mr.cnt) {
                    if (address >= mr.address + i * mr.stride && address < mr.address + i * mr.stride + mr.size) {
                        offset = address - (mr.address + i * mr.stride);
                        return mr.name.replace("x", to!string(i));
                    }
                }
            }
        }

        return "???";
    }

    private void log_read(T)(u32 address, T value) {
        int offset;
        string reg = get_mmio_reg_from_address(address, offset);

        // if (context.ipc.file_manager.usb_dev_57e305.usb_manager.bluetooth.wiimote.button_state & 4) {
            log_mmio("MMIO: Reading from %s (offset = %d) (size = %d) (value = %x) from 0x%08x / 0x%08x", reg, offset, T.sizeof, value, context.interrupt_controller.broadway.state.pc, context.interrupt_controller.broadway.state.lr);
        // }
    }

    private void log_write(T)(u32 address, T value) {
        int offset;
        string reg = get_mmio_reg_from_address(address, offset);

        // if (context.ipc.file_manager.usb_dev_57e305.usb_manager.bluetooth.wiimote.button_state & 4) {
            log_mmio("MMIO: Writing to %s (offset = %d) (size = %d) (value = %x) from 0x%08x / 0x%08x", reg, offset, T.sizeof, value, context.interrupt_controller.broadway.state.pc, context.interrupt_controller.broadway.state.lr);
        // }
    }

    T read(T)(u32 address) {
        import std.format;

        // log_memory("VERBOSE MMIO: Reading from %x (size = %d) (%X %X)", address, T.sizeof, arm9.regs[pc], arm7.regs[pc]);
        T value = T(0);

        static foreach (MmioRegister mr; mmio_registers) {
            static if (mr.readable && mr.all_at_once) {
                if (address + T.sizeof > mr.address && address < mr.address + mr.size) {
                    static if (mr.implemented) {
                        mixin("value |= context.%s.read_%s!T(address %% %d) << (8 * (address - mr.address));".format(mr.component, mr.name, mr.size));
                        this.log_read!T(address, value);
                        return value;
                    } else {
                        log_memory("Unimplemented read: %s (size = %d)", mr.name, T.sizeof);
                        return T(0);
                    }
                }
            }
        }

        static if (is(T == u32)) {
            value = (
                read_byte(address + 3) <<  0 |
                read_byte(address + 2) <<  8 |
                read_byte(address + 1) << 16 |
                read_byte(address + 0) << 24
            );
        } else

        static if (is(T == u16)) {
            value = (
                read_byte(address + 1) <<  0 |
                read_byte(address + 0) <<  8
            );
        } else

        static if (is(T == u8)) {
            value = read_byte(address);
        }

        else assert(0);

        this.log_read!T(address, value);
        return value;
    }

    private u8 read_byte(u32 address) {
        switch (address & 0xff00f000) {
            case 0xcc000000: return read_byte_block!(0xcc000000)(address);
            case 0xcc001000: return read_byte_block!(0xcc001000)(address);
            case 0xcc002000: return read_byte_block!(0xcc002000)(address);
            case 0xcc003000: return read_byte_block!(0xcc003000)(address);
            case 0xcc004000: return read_byte_block!(0xcc004000)(address);
            case 0xcc005000: return read_byte_block!(0xcc005000)(address);
            case 0xcc008000: return read_byte_block!(0xcc008000)(address);
            case 0xcd000000: return read_byte_block!(0xcd000000)(address);
            case 0xcd006000: return read_byte_block!(0xcd006000)(address);
            default: error_memory("Unimplemented read: [%x]", address);
        }

        return u8(0);
    }

    private u8 read_byte_block(u32 block_mask)(u32 address) {
        import std.format;
        
        mmio_switch: switch (address) {
            static foreach (MmioRegister mr; mmio_registers) {
                static if (mr.readable && (mr.address & 0xff00f000) == block_mask) {
                    static if (mr.stride == -1) {
                        static foreach(int offset; 0..mr.size) {
                            static if (!mr.filter_enabled || mr.f(offset)) {
                                case mr.address + offset:
                                    static if (!mr.all_at_once) {
                                        mixin("return context.%s.read_%s(%d ^ %d);".format(mr.component, mr.name, offset, mr.size - 1));
                                    } else {
                                        mixin("break mmio_switch;");
                                    }
                            }
                        }
                    } else {
                        static foreach(int stride_offset; 0..mr.cnt) {
                            static foreach(int offset; 0..mr.size) {
                                static if (!mr.filter_enabled || mr.f(offset)) {
                                    case mr.address + stride_offset * mr.stride + offset:
                                        static if (!mr.all_at_once) {
                                            mixin("return context.%s.read_%s(%d ^ %d, %d);".format(mr.component, mr.name, offset, mr.size - 1, stride_offset));
                                        } else {
                                            mixin("break mmio_switch;");
                                        }
                                }
                            }
                        }
                    }
                }
            }
            default: error_memory("Unimplemented read: [%x]", address);
        }
        return u8(0);
    }

    void write(T)(u32 address, T value) {
        this.log_write!T(address, value);
        // log_memory("VERBOSE MMIO: Writing %x to %x (size = %d) (%X %X)", value, address, T.sizeof,  arm9.regs[pc], arm7.regs[pc]);

        import std.format;
        static foreach (MmioRegister mr; mmio_registers) {
            static if (mr.writeable && mr.all_at_once) {
                if (address + T.sizeof > mr.address && address < mr.address + mr.size) {
                    static if (mr.implemented) {
                        mixin("context.%s.write_%s!T(cast(T) (value >> (8 * (address - mr.address))), address %% %d);".format(mr.component, mr.name, mr.size));
                        return;
                    } else {
                        log_memory("Unimplemented write: [%s] = %08x (size = %d)", mr.name, value, T.sizeof);
                        return;
                    }
                }
            }
        }

        static if (is(T == u32)) {
            write_byte(address + 3, value.get_byte(0));
            write_byte(address + 2, value.get_byte(1));
            write_byte(address + 1, value.get_byte(2));
            write_byte(address + 0, value.get_byte(3));
        } else

        static if (is(T == u16)) {
            write_byte(address + 1, value.get_byte(0));
            write_byte(address + 0, value.get_byte(1));
        } else

        static if (is(T == u8)) {
            write_byte(address, value);
        }
        
        else assert(0);
    }

    private void write_byte(u32 address, u8 value) {
        switch (address & 0xff00f000) {
            case 0xcc000000: write_byte_block!(0xcc000000)(address, value); break;
            case 0xcc001000: write_byte_block!(0xcc001000)(address, value); break;
            case 0xcc002000: write_byte_block!(0xcc002000)(address, value); break;
            case 0xcc003000: write_byte_block!(0xcc003000)(address, value); break;
            case 0xcc004000: write_byte_block!(0xcc004000)(address, value); break;
            case 0xcc005000: write_byte_block!(0xcc005000)(address, value); break;
            case 0xcc008000: write_byte_block!(0xcc008000)(address, value); break;
            case 0xcd000000: write_byte_block!(0xcd000000)(address, value); break;
            case 0xcd006000: write_byte_block!(0xcd006000)(address, value); break;
            default: error_memory("Unimplemented write: [%x] = %x", address, value);
        }
    }

    private void write_byte_block(u32 block_mask)(u32 address, u8 value) {
        import std.format;

        mmio_switch: switch (address) {
            static foreach (MmioRegister mr; mmio_registers) {
                static if (mr.writeable && (mr.address & 0xff00f000) == block_mask) {
                    static if (mr.stride == -1) {
                        static foreach(int offset; 0..mr.size) {
                            static if (!mr.filter_enabled || mr.f(offset)) {
                                case mr.address + offset:
                                    static if (!mr.all_at_once) {
                                        mixin("context.%s.write_%s(%d, value); break mmio_switch;".format(mr.component, mr.name, offset ^ (mr.size - 1)));
                                    } else {
                                        mixin("break mmio_switch;");
                                    }
                            }
                        }
                    } else {
                        static foreach(int stride_offset; 0..mr.cnt) {
                            static foreach(int offset; 0..mr.size) {
                                static if (!mr.filter_enabled || mr.f(offset)) {
                                    case mr.address + stride_offset * mr.stride + offset:
                                        static if (!mr.all_at_once) {
                                            mixin("context.%s.write_%s(%d, value, %d); break mmio_switch;".format(mr.component, mr.name, offset ^ (mr.size - 1), stride_offset));
                                        } else {
                                            mixin("break mmio_switch;");
                                        }
                                }
                            }
                        }
                    }
                }
            }
            default: error_memory("Unimplemented write: [%x] = %x", address, value);
        }
    }
}