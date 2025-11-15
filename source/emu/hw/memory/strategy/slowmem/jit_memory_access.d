module emu.hw.memory.strategy.slowmem.jit_memory_access;

import emu.hw.broadway.jit.emission.code;
import emu.hw.broadway.jit.emission.guest_reg;
import gallinule.x86;
import util.number;

enum MemorySize {
    Byte = 0,
    HalfWord = 1, 
    Word = 2,
    DoubleWord = 3
}

enum Extension {
    Zero,
    Sign
}

enum Update {
    No,
    Yes
}

enum ByteOrder {
    BigEndian,
    LittleEndian
}

R32 calculate_effective_address_indexed(Code code, GuestReg ra, GuestReg rb) {
    R32 ra_reg = code.get_reg(ra);
    R32 rb_reg = code.get_reg(rb);
    
    code.mov(esi, ra_reg);
    if (ra == GuestReg.R0) {
        code.xor(esi, esi);
    }
    code.add(esi, rb_reg);
    
    return esi;
}

R32 calculate_effective_address_displacement(Code code, GuestReg ra, int offset) {
    R32 ra_reg = code.get_reg(ra);
    
    code.mov(esi, ra_reg);
    if (ra == GuestReg.R0) {
        code.xor(esi, esi);
    }
    
    if (offset != 0) {
        code.add(esi, offset);
    }
    
    return esi;
}

R32 calculate_indexed_address(Code code, GuestReg ra, GuestReg rb) {
    return calculate_effective_address_indexed(code, ra, rb);
}

void emit_memory_read(Code code, R32 result_reg, R32 address_reg, MemorySize size, Extension extension, ByteOrder byte_order) {
    code.mov(esi, address_reg);
    
    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        
        final switch (size) {
            case MemorySize.Byte:
                code.mov(rax, cast(u64) code.config.read_handler8);
                break;
            case MemorySize.HalfWord:
                code.mov(rax, cast(u64) code.config.read_handler16);
                break;
            case MemorySize.Word:
                code.mov(rax, cast(u64) code.config.read_handler32);
                break;
            case MemorySize.DoubleWord:
                code.mov(rax, cast(u64) code.config.read_handler64);
                break;
        }
        
        code.call(rax);
        
        final switch (extension) {
            case Extension.Zero:
                final switch (size) {
                    case MemorySize.Byte:
                        code.movzx(eax, al);
                        break;
                    case MemorySize.HalfWord:
                        code.movzx(eax, ax);
                        break;
                    case MemorySize.Word:
                    case MemorySize.DoubleWord:
                        break;
                }
                break;
            case Extension.Sign:
                final switch (size) {
                    case MemorySize.Byte:
                        code.movsx(eax, al);
                        break;
                    case MemorySize.HalfWord:
                        code.movsx(eax, ax);
                        break;
                    case MemorySize.Word:
                    case MemorySize.DoubleWord:
                        break;
                }
                break;
        }
        
        if (byte_order == ByteOrder.LittleEndian) {
            final switch (size) {
                case MemorySize.Byte:
                    break;
                case MemorySize.HalfWord:
                    code.bswap(eax);
                    code.shr(eax, 16);
                    break;
                case MemorySize.Word:
                    code.bswap(eax);
                    break;
                case MemorySize.DoubleWord:
                    code.bswap(rax);
                    break;
            }
        }
    code.exit_stack_alignment_context();
    code.pop(rdi);
    
    code.mov(result_reg.cvt64(), rax);
}

void emit_memory_write(Code code, R32 address_reg, R64 value_reg, MemorySize size, ByteOrder byte_order) {
    code.mov(esi, address_reg);
    
    R64 converted_value = value_reg;
    if (byte_order == ByteOrder.LittleEndian) {
        converted_value = code.allocate_register().cvt64();
        code.mov(converted_value, value_reg);
        
        final switch (size) {
            case MemorySize.Byte:
                break;
            case MemorySize.HalfWord:
                code.bswap(converted_value.cvt32());
                code.shr(converted_value.cvt32(), 16);
                break;
            case MemorySize.Word:
                code.bswap(converted_value.cvt32());
                break;
            case MemorySize.DoubleWord:
                code.bswap(converted_value);
                break;
        }
    }
    
    final switch (size) {
        case MemorySize.Byte:
            code.movzx(edx, converted_value.cvt8());
            break;
        case MemorySize.HalfWord:
            code.movzx(edx, converted_value.cvt16());
            break;
        case MemorySize.Word:
            code.mov(edx, converted_value.cvt32());
            break;
        case MemorySize.DoubleWord:
            code.mov(rdx, converted_value);
            break;
    }
    
    code.push(rdi);
    code.enter_stack_alignment_context();
        code.mov(rdi, cast(u64) code.config.mem_handler_context);
        
        final switch (size) {
            case MemorySize.Byte:
                code.mov(rax, cast(u64) code.config.write_handler8);
                break;
            case MemorySize.HalfWord:
                code.mov(rax, cast(u64) code.config.write_handler16);
                break;
            case MemorySize.Word:
                code.mov(rax, cast(u64) code.config.write_handler32);
                break;
            case MemorySize.DoubleWord:
                code.mov(rax, cast(u64) code.config.write_handler64);
                break;
        }
        
        code.call(rax);
    code.exit_stack_alignment_context();
    code.pop(rdi);
}



void emit_load_displacement(Code code, GuestReg dest, GuestReg base, int displacement, MemorySize size, Extension extension, Update update, ByteOrder byte_order) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto address = calculate_effective_address_displacement(code, base, displacement);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    auto result = code.allocate_register();
    emit_memory_read(code, result, address, size, extension, byte_order);
    code.set_reg(dest, result);
}

void emit_store_displacement(Code code, GuestReg source, GuestReg base, int displacement, MemorySize size, ByteOrder byte_order, Update update) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto address = calculate_effective_address_displacement(code, base, displacement);
    auto value = code.get_reg(source);
    
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    emit_memory_write(code, address, value.cvt64(), size, byte_order);
}

void emit_load_indexed(Code code, GuestReg dest, GuestReg base, GuestReg index, MemorySize size, Extension extension, Update update, ByteOrder byte_order) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto address = calculate_indexed_address(code, base, index);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    auto result = code.allocate_register();
    emit_memory_read(code, result, address, size, extension, byte_order);
    code.set_reg(dest, result);
}

void emit_store_indexed(Code code, GuestReg source, GuestReg base, GuestReg index, MemorySize size, ByteOrder byte_order, Update update) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto address = calculate_indexed_address(code, base, index);
    auto value = code.get_reg(source);
    
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    emit_memory_write(code, address, value.cvt64(), size, byte_order);
}

void emit_load_fpr_displacement(Code code, GuestReg dest_fpr, GuestReg base, int displacement, Update update) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto address = calculate_effective_address_displacement(code, base, displacement);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    auto result = code.allocate_register();
    emit_memory_read(code, result, address, MemorySize.DoubleWord, Extension.Zero, ByteOrder.BigEndian);
    code.set_fpr(dest_fpr, result.cvt64());
}

void emit_load_fpr_indexed(Code code, GuestReg dest_fpr, GuestReg base, GuestReg index, Update update) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto address = calculate_indexed_address(code, base, index);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    auto result = code.allocate_register();
    emit_memory_read(code, result, address, MemorySize.DoubleWord, Extension.Zero, ByteOrder.BigEndian);
    code.set_fpr(dest_fpr, result.cvt64());
}

void emit_store_fpr_displacement(Code code, GuestReg source_fpr, GuestReg base, int displacement, Update update) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto address = calculate_effective_address_displacement(code, base, displacement);
    auto value = code.get_fpr(source_fpr);
    
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    emit_memory_write(code, address, value, MemorySize.DoubleWord, ByteOrder.BigEndian);
}

void emit_store_fpr_indexed(Code code, GuestReg source_fpr, GuestReg base, GuestReg index, Update update) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto address = calculate_indexed_address(code, base, index);
    auto value = code.get_fpr(source_fpr);
    
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    emit_memory_write(code, address, value, MemorySize.DoubleWord, ByteOrder.BigEndian);
}

void emit_load_ps_displacement(Code code, GuestReg dest_ps, GuestReg base, int displacement, Update update) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto address = calculate_effective_address_displacement(code, base, displacement);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    auto result = code.allocate_register();
    emit_memory_read(code, result, address, MemorySize.Word, Extension.Zero, ByteOrder.BigEndian);
    
    code.movq(xmm0, result.cvt64());
    code.cvtss2sd(xmm0, xmm0);
    
    auto end = code.fresh_label();
    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);
    code.vpbroadcastq(xmm0, xmm0);
    code.label(end);
    
    code.set_ps(dest_ps, xmm0);
}

void emit_store_ps_displacement(Code code, GuestReg source_ps, GuestReg base, int displacement, Update update) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto address = calculate_effective_address_displacement(code, base, displacement);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    code.get_ps(source_ps, xmm0);
    code.cvtsd2ss(xmm0, xmm0);
    code.movd(edx, xmm0);
    
    emit_memory_write(code, address, edx.cvt64(), MemorySize.Word, ByteOrder.BigEndian);
}

void emit_load_ps_indexed(Code code, GuestReg dest_ps, GuestReg base, GuestReg index, Update update) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    
    auto address = calculate_indexed_address(code, base, index);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    auto result = code.allocate_register();
    emit_memory_read(code, result, address, MemorySize.Word, Extension.Zero, ByteOrder.BigEndian);
    
    code.movq(xmm0, result.cvt64());
    code.cvtss2sd(xmm0, xmm0);
    
    auto end = code.fresh_label();
    auto hid2 = code.get_reg(GuestReg.HID2);
    code.test(hid2, 1 << 29);
    code.jz(end);
    code.vpbroadcastq(xmm0, xmm0);
    code.label(end);
    
    code.set_ps(dest_ps, xmm0);
}

void emit_store_ps_indexed(Code code, GuestReg source_ps, GuestReg base, GuestReg index, Update update) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto address = calculate_indexed_address(code, base, index);
    if (update == Update.Yes) {
        code.set_reg(base, address);
    }
    
    code.get_ps(source_ps, xmm0);
    code.cvtsd2ss(xmm0, xmm0);
    code.movd(edx, xmm0);
    
    emit_memory_write(code, address, edx.cvt64(), MemorySize.Word, ByteOrder.BigEndian);
}

void emit_store_fpr_as_integer_indexed(Code code, GuestReg source_fpr, GuestReg base, GuestReg index) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    
    auto address = calculate_indexed_address(code, base, index);
    auto value = code.get_fpr(source_fpr);
    
    emit_memory_write(code, address, value.cvt32().cvt64(), MemorySize.Word, ByteOrder.BigEndian);
}

void raw_read8(Code code, R32 address, R32 dest) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_read(code, dest, address, MemorySize.Byte, Extension.Zero, ByteOrder.BigEndian);
    code.pop_caller_saved_registers_except(dest.cvt64());
}

void raw_read16(Code code, R32 address, R32 dest) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_read(code, dest, address, MemorySize.HalfWord, Extension.Zero, ByteOrder.BigEndian);
    code.pop_caller_saved_registers_except(dest.cvt64());
}

void raw_read32(Code code, R32 address, R32 dest) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_read(code, dest, address, MemorySize.Word, Extension.Zero, ByteOrder.BigEndian);
    code.pop_caller_saved_registers_except(dest.cvt64());
}

void raw_read64(Code code, R32 address, R64 dest) {
    code.reserve_register(esi);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_read(code, dest.cvt32(), address, MemorySize.DoubleWord, Extension.Zero, ByteOrder.BigEndian);
    code.pop_caller_saved_registers_except(dest);
}

void raw_write8(Code code, R32 address, R32 value) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_write(code, address, value.cvt64(), MemorySize.Byte, ByteOrder.BigEndian);
    code.pop_caller_saved_registers();
}

void raw_write16(Code code, R32 address, R32 value) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_write(code, address, value.cvt64(), MemorySize.HalfWord, ByteOrder.BigEndian);
    code.pop_caller_saved_registers();
}

void raw_write32(Code code, R32 address, R32 value) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_write(code, address, value.cvt64(), MemorySize.Word, ByteOrder.BigEndian);
    code.pop_caller_saved_registers();
}

void raw_write64(Code code, R32 address, R64 value) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);
    code.push_caller_saved_registers();
    emit_memory_write(code, address, value, MemorySize.DoubleWord, ByteOrder.BigEndian);
    code.pop_caller_saved_registers();
}

void data_cache_block_zero(Code code, GuestReg base, GuestReg index) {
    R32 ra;
    if (base == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(base);
    }

    auto rb = code.get_reg(index);

    code.mov(r12d, ra);
    code.add(r12d, rb);
    code.and(r12d, ~31);

    code.mov(rb, 0);

    code.push(rdi);
    code.enter_stack_alignment_context();
        for (int i = 0; i < 32 / 4; i++) {
            code.mov(rdi, cast(u64) code.config.mem_handler_context);
            code.mov(esi, r12d);
            code.mov(edx, 0);
            code.mov(rax, cast(u64) code.config.write_handler32);
            code.call(rax);
            code.add(r12d, 4);
        }
    code.exit_stack_alignment_context();
    code.pop(rdi);
}

void load_multiple_words(Code code, GuestReg start_reg, GuestReg base, int displacement) {
    code.reserve_register(esi);
    code.reserve_register(eax);

    R32 ra = code.allocate_register();
    if (base == GuestReg.R0) {
        ra = code.allocate_register();
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(base);
    }

    code.push(rdi);
        for (int i = cast(int)start_reg; i < 32; i++) {
            code.push(ra);
            code.mov(esi, ra);
            code.add(esi, displacement);

            code.enter_stack_alignment_context();
            code.mov(rdi, cast(u64) code.config.mem_handler_context);
            code.mov(rax, cast(u64) code.config.read_handler32);
            code.call(rax);
            code.exit_stack_alignment_context();

            code.pop(ra);
            code.add(ra, 4);

            code.pop(rdi);
            code.set_reg(cast(GuestReg)i, eax);
            code.push(rdi);

        }
    code.pop(rdi);
}

void store_multiple_words(Code code, GuestReg start_reg, GuestReg base, int offset) {
    code.reserve_register(edi);
    code.reserve_register(esi);
    code.reserve_register(edx);
    code.reserve_register(eax);

    R32 ra = code.allocate_register();
    if (base == GuestReg.R0) {
        code.xor(ra, ra);
    } else {
        ra = code.get_reg(base);
    }

    int loop_ofs = 0;
    for (int i = cast(int)start_reg; i < 32; i++) {
        auto rs = code.get_reg(cast(GuestReg)i);
        code.push(ra);
        code.push(rdi);
        code.enter_stack_alignment_context();

            code.mov(esi, ra);
            code.add(esi, offset + loop_ofs);
            code.mov(edx, rs);
            code.mov(rdi, cast(u64) code.config.mem_handler_context);
            code.mov(rax, cast(u64) code.config.write_handler32);
            code.call(rax);

        code.exit_stack_alignment_context();
        code.pop(rdi);
        code.pop(ra);
        code.free_register(rs);

        loop_ofs += 4;
    }
}