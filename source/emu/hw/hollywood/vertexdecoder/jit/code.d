module emu.hw.hollywood.vertexdecoder.jit.code;

import core.bitop;
import core.stdc.string;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.jit.passes.emit;
import emu.hw.hollywood.vertexdecoder.types;
import gallinule.x86;
import std.conv;
import util.log;
import util.number;
import util.force_cast;
import util.x86;

/// Skeleton vertex JIT code emitter.
final class Code {
    Block!true block;
    alias block this;

    enum SOURCE_REG64 = rdi;
    enum SOURCE_REG32 = edi;
    enum DEST_REG64   = rsi;
    enum DEST_REG32   = esi;

    enum MAX_LICM_VALUES = 4;
    static immutable YMM[MAX_LICM_VALUES] LICM_REGISTERS = [ymm8, ymm9, ymm10, ymm11];
    alias LicmValue = u8[32];
    LicmValue[MAX_LICM_VALUES] licm_values;
    int                        licm_value_count;

    u16 allocated_regs;

    this() {
        block = Block!true();
        free_all_registers();
    }

    void init() {
        block.reset();
        free_all_registers();
        emit_prologue();
    }

    DestFormat emit(VertexFormat state) {
        init_licm_state();
        int source_stride = size_of_incoming_vertex(
            state.vertex_descriptors[state.current_vat],
            state.vats[state.current_vat]);
        DestFormat dest_format;

        mov(rax, state.number_of_expected_vertices);
        jmp("licm");

        label("vertex_decode_loop");
            dest_format = emit_vertex(this, state);
            add(SOURCE_REG64, cast(uint) source_stride);
            add(DEST_REG64, cast(uint) dest_format.stride);

            dec(rax);
            jne("vertex_decode_loop");

        mov(rax, state.number_of_expected_vertices);
        jmp("done");

        // We only have the LICM data after emit_vertex runs.
        label("licm");
        emit_licm_block();

        jmp("vertex_decode_loop");
        label("done");

        return dest_format;
    }

    void init_licm_state() {
        licm_value_count = 0;
    }

    YMM register_licm_ymm(const(LicmValue) value) {
        licm_values[licm_value_count][] = value[];
        return LICM_REGISTERS[licm_value_count++];
    }

    void update_licm_ymm(YMM ymm, const(LicmValue) value) {
        int ymm_index = -1;
        foreach (i; 0 .. licm_value_count) {
            if (LICM_REGISTERS[i] == ymm) {
                ymm_index = i;
            }
        }

        assert_vertex_jit(ymm_index != -1, "vertex JIT LICM YMM not found");

        licm_values[ymm_index][] = value[];
    }

    LicmValue licm_value_for_entry(YMM ymm) {
        int ymm_index = -1;
        foreach (i; 0 .. licm_value_count) {
            if (LICM_REGISTERS[i] == ymm) {
                ymm_index = i;
            }
        }

        assert_vertex_jit(ymm_index != -1, "vertex JIT LICM YMM not found");

        return licm_values[ymm_index];
    }

    u8* licm_value_for_entry(int entry) {
        assert_vertex_jit(entry >= 0 && entry < licm_value_count,
            "vertex JIT LICM entry out of range");
        return &licm_values[entry][0];
    }

    void emit_licm_block() {
        foreach (entry; 0 .. licm_value_count) {
            auto label_name = licm_value_label(entry);
            writefln("Emitting LICM load for entry %d at label %s", entry, label_name);
            auto addr = Address!256.ripAnchor(label_name);
            vmovups(LICM_REGISTERS[entry], addr);
            registerRipReferenceFrom(addr);
        }

        auto addr = Address!256.ripAnchor("ymm_zero_data");
        vmovups(ymmzero(), addr);
        registerRipReferenceFrom(addr);
    }

    void emit_licm_value_data() {
        foreach (entry; 0 .. licm_value_count) {
            auto label_name = licm_value_label(entry);
            label(label_name);
            block.buffer ~= licm_values[entry][0 .. licm_values[entry].length];
        }

        label("ymm_zero_data");
        u8[32] zero_data;
        memset(&zero_data[0], 0, zero_data.length);
        block.buffer ~= zero_data[0 .. zero_data.length];
    }

    import std.stdio;
    u64 vpshufb_mask_map;
    void assign_vpshufb_mask_to_ymm(YMM ymm, YMM mask) {
        writefln("Assigning vpshufb mask %s to ymm %s", mask, ymm);
        vpshufb_mask_map &= ~(0xF << (ymm.index * 4));
        vpshufb_mask_map |= (mask.index & 0xF) << (ymm.index * 4);
    }

    YMM vpshufb_mask_for(YMM ymm) {
        writefln("Getting vpshufb mask for ymm %s", ymm);
        return YMM((vpshufb_mask_map >> (ymm.index * 4)) & 0xF);
    }

    private string licm_value_label(int entry) {
        return "licm_value_" ~ to!string(entry);
    }

    YMM ymmzero() {
        // Reserve the second last YMM as a 7f register.
        return YMM(14);
    }

    void process_vertex(VertexFormat state) {
        // First thing's first, lets extract the attributes into floats.

    //     auto vcd = &state.vertex_descriptors[state.current_vat];

    //     parse_position_matrix_index(state);
    //     parse_texcoord_matrix_indices(state);

    //     if (vcd.position_location != VertexAttributeLocation.NotPresent) {
    //         parse_position(state);
    //     }

    //     for (int i = 0; i < 2; i++) {
    //         if (vcd.color_location[i] != VertexAttributeLocation.NotPresent) {
    //             parse_colors(state, i);
    //         }
    //     }

    //     for (int i = 0; i < 8; i++) {
    //         if (vcd.texcoord_location[i] != VertexAttributeLocation.NotPresent) {
    //             parse_texcoord(state, i);
    //         }
    //     }
    }

    size_t color_format_to_bytes(ColorFormat format) {
        final switch (format) {
            case ColorFormat.RGB565:   return 2;
            case ColorFormat.RGB888:   return 3;
            case ColorFormat.RGB888x:  return 4;
            case ColorFormat.RGBA4444: return 2;
            case ColorFormat.RGBA6666: return 3;
            case ColorFormat.RGBA8888: return 4;
        }
    }

    void emit_prologue() {
        push(rbp);
        mov(rbp, rsp);

        foreach (reg; [rbx, r12, r13, r14, r15]) {
            push(reg);
        }
    }

    void emit_epilogue() {
        foreach (reg; [r15, r14, r13, r12, rbx]) {
            pop(reg);
        }

        pop(rbp);
        ret();
    }

    u8[] get() {
        emit_epilogue();
        emit_licm_value_data();
        return block.finalize();
    }

    R32 allocate_register() {
        if (allocated_regs == 0xFFFF) {
            assert_vertex_jit(false, "no free registers available");
        }

        int reg = core.bitop.bsf(~allocated_regs);
        allocated_regs |= 1 << reg;
        return u16_to_reg32(cast(u16) reg);
    }

    R32 allocate_register_prefer(R32 preferred) {
        int preferred_index = reg32_to_u16(preferred);

        if ((allocated_regs & (1 << preferred_index)) == 0) {
            allocated_regs |= 1 << preferred_index;
            return preferred;
        }

        return allocate_register();
    }

    void reserve_register(R32 reg) {
        allocated_regs |= 1 << reg32_to_u16(reg);
    }

    void free_register(R32 reg) {
        allocated_regs &= ~(1 << reg32_to_u16(reg));
    }

    void free_all_registers() {
        allocated_regs = 0;
        reserve_register(SOURCE_REG32);
    }
}
