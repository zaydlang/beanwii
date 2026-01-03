module emu.hw.hollywood.vertexdecoder.jit.code;

import core.bitop;
import emu.hw.hollywood.hollywood_types;
import emu.hw.hollywood.vertexdecoder.types;
import gallinule.x86;
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

    enum XMM BYTESWAP_U32_MASK = xmm14;
    enum XMM BYTESWAP_U16_MASK = xmm15;
    enum POSITION_LICM_REG = xmm4;
    enum TEXCOORD_LICM_REGS = [xmm5, xmm6, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12];
    enum COLOR_LICM_REGS = [xmm3, xmm13];

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

    void emit(VertexDecodeState state) {
        setup_licm_state(state);

        mov(rax, state.number_of_expected_vertices);
        label("vertex_decode_loop");

            process_vertex(state);
            add(DEST_REG64, cast(uint) Vertex.sizeof);

            dec(rax);
            jne("vertex_decode_loop");
        
        mov(rax, state.number_of_expected_vertices);
    }

    void setup_licm_state(VertexDecodeState state) {
        auto vcd = &state.vertex_descriptors[state.current_vat];

        setup_byteswap_masks();

        if (vcd.position_location != VertexAttributeLocation.NotPresent) {
            setup_position_parsing(state);
        }

        for (int i = 0; i < 2; i++) {
            if (vcd.color_location[i] != VertexAttributeLocation.NotPresent) {
                setup_color_parsing(state, i);
            }
        }

        for (int i = 0; i < 8; i++) {
            if (vcd.texcoord_location[i] != VertexAttributeLocation.NotPresent) {
                setup_texcoord_parsing(state, i);
            }
        }
    }

    void setup_byteswap_masks() {
        mov(rax, 0x0405_0607_0001_0203UL);
        movq(BYTESWAP_U32_MASK, rax);
        mov(rax, 0x0C0D_0E0F_0809_0A0BUL);
        movq(xmm0, rax);
        punpcklqdq(BYTESWAP_U32_MASK, xmm0);

        mov(rax, 0x0706_0504_0302_0100UL);
        movq(BYTESWAP_U16_MASK, rax);
        mov(rax, 0x0E0F_0C0D_0A0B_0809UL);
        movq(xmm0, rax);
        punpcklqdq(BYTESWAP_U16_MASK, xmm0);
    }

    void process_vertex(VertexDecodeState state) {
        auto vcd = &state.vertex_descriptors[state.current_vat];

        parse_position_matrix_index(state);
        parse_texcoord_matrix_indices(state);

        if (vcd.position_location != VertexAttributeLocation.NotPresent) {
            parse_position(state);
        }

        for (int i = 0; i < 2; i++) {
            if (vcd.color_location[i] != VertexAttributeLocation.NotPresent) {
                parse_colors(state, i);
            }
        }

        for (int i = 0; i < 8; i++) {
            if (vcd.texcoord_location[i] != VertexAttributeLocation.NotPresent) {
                parse_texcoord(state, i);
            }
        }
    }

    void parse_position_matrix_index(VertexDecodeState state) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        if (vcd.position_normal_matrix_location != VertexAttributeLocation.NotPresent) {
            movzx(eax, bytePtr(SOURCE_REG64));
            mov(dwordPtr(DEST_REG64, cast(uint) Vertex.position_matrix_index.offsetof), eax);
            add(SOURCE_REG64, 1);
        } else {
            mov(dwordPtr(DEST_REG64, cast(uint) Vertex.position_matrix_index.offsetof), -1);
        }
    }

    void parse_texcoord_matrix_indices(VertexDecodeState state) {
        auto vcd = &state.vertex_descriptors[state.current_vat];
        for (int i = 0; i < 8; i++) {
            if (vcd.texcoord_matrix_location[i] != VertexAttributeLocation.NotPresent) {
                add(SOURCE_REG64, 1);
            }
        }
    }

    void setup_position_parsing(VertexDecodeState state) {
        auto vat = &state.vats[state.current_vat];
        
        if (vat.position_shift != 0) {
            mov(eax, force_cast!u32(1.0f / (cast(float) (1u << vat.position_shift))));
            movd(POSITION_LICM_REG, eax);
            vbroadcastss(POSITION_LICM_REG, POSITION_LICM_REG);
        }
    }

    void parse_position(VertexDecodeState state) {
        auto vat = &state.vats[state.current_vat];

        movdqu(xmm1, xmmwordPtr(SOURCE_REG64));
        
        final switch (vat.position_format) {
            case CoordFormat.F32: pshufb(xmm1, BYTESWAP_U32_MASK); break;
            case CoordFormat.U16: 
            case CoordFormat.S16: pshufb(xmm1, BYTESWAP_U16_MASK); break;
            case CoordFormat.U8:
            case CoordFormat.S8: break;
        }
        
        final switch (vat.position_format) {
            case CoordFormat.F32: break;
            case CoordFormat.U16: pmovzxwd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
            case CoordFormat.S16: pmovsxwd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
            case CoordFormat.U8:  pmovzxbd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
            case CoordFormat.S8:  pmovsxbd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
        }

        if (vat.position_shift != 0) {
            mulps(xmm1, POSITION_LICM_REG);
        }

        movups(xmmwordPtr(DEST_REG64, cast(uint) Vertex.position.offsetof), xmm1);
        if (vat.position_count == 2) {
            mov(dwordPtr(DEST_REG64, cast(uint) (Vertex.position.offsetof + 8)), 0);
        }

        add(SOURCE_REG64, cast(uint) (vat.position_count * coord_format_to_bytes(vat.position_format)));
    }

    void setup_color_parsing(VertexDecodeState state, int index) {
        auto licm_reg = COLOR_LICM_REGS[index];
        auto vat = &state.vats[state.current_vat];

        if (vat.color_shift[index] != 0) {
            mov(eax, force_cast!u32(1.0f / (cast(float) (1u << vat.color_shift[index]))));
            movd(licm_reg, eax);
            vbroadcastss(licm_reg, licm_reg);
        }
    }

    void parse_colors(VertexDecodeState state, int index) {
        auto vat = &state.vats[state.current_vat];

        mov(eax, dwordPtr(SOURCE_REG64));

        final switch (vat.color_format[index]) {
        case ColorFormat.RGB565:
        case ColorFormat.RGBA4444:
            this.bswap(eax);
            break;

        case ColorFormat.RGBA8888:
        case ColorFormat.RGB888x:
            this.bswap(eax);
            break;

        case ColorFormat.RGBA6666:
        case ColorFormat.RGB888:
            this.bswap(eax);
            shr(eax, 8);
            break;
        }

        final switch (vat.color_format[index]) {
        case ColorFormat.RGB565:
            mov(ebx, 0x00_F8_FC_F8);
            pdep(eax, eax, ebx);
            break;
        
        case ColorFormat.RGBA4444:
            mov(ebx, 0xF0_F0_F0_F0);
            pdep(eax, eax, ebx);
            break;
        
        case ColorFormat.RGBA6666:
            mov(ebx, 0xFC_FC_FC_FC);
            pdep(eax, eax, ebx);
            break;
        
        case ColorFormat.RGB888x:
            break;
        
        case ColorFormat.RGBA8888:
            break;
        
        case ColorFormat.RGB888:
            break;
        }

        movd(xmm1, eax);
        pmovzxbd(xmm1, xmm1);
        cvtdq2ps(xmm1, xmm1);

        if (vat.color_shift[index] != 0) {
            mulps(xmm1, COLOR_LICM_REGS[index]);
        }

        movq(qwordPtr(DEST_REG64, cast(uint) (Vertex.color.offsetof + index * 16)), xmm1);
        add(SOURCE_REG64, cast(uint) color_format_to_bytes(vat.color_format[index]));
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

    void setup_texcoord_parsing(VertexDecodeState state, int index) {
        auto licm_reg = TEXCOORD_LICM_REGS[index];
        auto vat = &state.vats[state.current_vat];

        if (vat.texcoord_shift[index] != 0) {
            mov(eax, force_cast!u32(1.0f / (cast(float) (1u << vat.texcoord_shift[index]))));
            movd(licm_reg, eax);
            vbroadcastss(licm_reg, licm_reg);
        }
    }

    void parse_texcoord(VertexDecodeState state, int index) {
        auto licm_reg = TEXCOORD_LICM_REGS[index];
        auto vat = &state.vats[state.current_vat];

        movdqu(xmm1, xmmwordPtr(SOURCE_REG64));
        
        final switch (vat.position_format) {
            case CoordFormat.F32: pshufb(xmm1, BYTESWAP_U32_MASK); break;
            case CoordFormat.U16: 
            case CoordFormat.S16: pshufb(xmm1, BYTESWAP_U16_MASK); break;
            case CoordFormat.U8:
            case CoordFormat.S8: break;
        }
        
        final switch (vat.texcoord_format[index]) {
            case CoordFormat.F32: break;
            case CoordFormat.U16: pmovzxwd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
            case CoordFormat.S16: pmovsxwd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
            case CoordFormat.U8:  pmovzxbd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
            case CoordFormat.S8:  pmovsxbd(xmm1, xmm1); cvtdq2ps(xmm1, xmm1); break;
        }

        if (vat.texcoord_shift[index] != 0) {
           mulps(xmm1, licm_reg);
        }

        movq(qwordPtr(DEST_REG64, cast(uint) (Vertex.texcoord.offsetof + index * 4)), xmm1);
        if (vat.texcoord_count[index] == 1) {
            mov(dwordPtr(DEST_REG64, cast(uint) (Vertex.texcoord.offsetof + index * 4 + 4)), 0);
        }

        add(SOURCE_REG64, cast(uint) (vat.texcoord_count[index] * coord_format_to_bytes(vat.texcoord_format[index])));
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
