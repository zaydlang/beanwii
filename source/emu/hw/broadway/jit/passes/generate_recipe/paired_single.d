module emu.hw.broadway.jit.passes.generate_recipe.paired_single;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.jit;
import emu.hw.broadway.jit.passes.generate_recipe.helpers;
import emu.hw.broadway.jit.passes.generate_recipe.pass;
import util.bitop;
import util.log;
import util.number;

public GenerateRecipeAction emit_psq_l(IR* ir, u32 opcode, JitContext ctx) {
    // GuestReg rd  = to_ps (opcode.bits(21, 25));
    // GuestReg ra  = to_gpr(opcode.bits(16, 20));
    // GuestReg gqr = to_gqr(opcode.bits(12, 14));

    // bool w = opcode.bit(15);
    // int d = opcode.bits(0, 11);

    // IRVariable address = ra == 0 ? ir.constant(0) : ir.get_reg(ra);
    // address = address + sext_32(d, 12);

    // IRVariable gqr_value = ir.get_reg(gqr);
    // IRVariable gqr_type  = get_gqr_dequantization_type(ir, gqr_value);
    // IRVariable gqr_scale = get_gqr_dequantization_scale(ir, gqr_value);

    // IRVariable access_size = get_gqr_type_size(ir, gqr_type);

    // IRVariable paired_single = ir.get_reg(rd);
    // if (w) {
    //     paired_single[0] = dequantize(ir, ir.read_sized(address, access_size), gqr_type, gqr_scale);
    //     paired_single[1] = ir.constant(1.0f);
    // } else {
    //     paired_single[0] = dequantize(ir, ir.read_sized(address, access_size), gqr_type, gqr_scale);
    //     paired_single[1] = dequantize(ir, ir.read_sized(address + access_size, access_size), gqr_type, gqr_scale);
    // }

    // ir.set_reg(rd, paired_single);

    return GenerateRecipeAction.CONTINUE;
}

public GenerateRecipeAction emit_ps_mr(IR* ir, u32 opcode, JitContext ctx) {
    GuestReg frd = to_ps(opcode.bits(21, 25));
    GuestReg frb = to_ps(opcode.bits(11, 15));

    assert(opcode.bits(16, 20) == 0b00000);
    assert(opcode.bit(0) == 0);

    ir.set_reg(frd, ir.get_reg(frb));

    return GenerateRecipeAction.CONTINUE;
}

private IRVariable dequantize(IR* ir, IRVariable value, IRVariable gqr_type, IRVariable gqr_scale) {
    IRVariable result = ir.constant(0.0f);

    ir._if(is_gqr_type_u16(ir, gqr_type), () {
        IRVariable masked_value = value & 0xFFFF;

        // nested ifs are not supported...
        // ir._if(is_gqr_type_signed(ir, gqr_type), () {
        //     value = (value << 16) >> 16;
        // });

        result = masked_value.to_float() / (ir.constant(1) << gqr_scale);
    });

    ir._if(is_gqr_type_u8(ir, gqr_type), () {
        IRVariable masked_value = value & 0xFF;

        // nested ifs are not supported...
        // ir._if(is_gqr_type_signed(ir, gqr_type), () {
        //     value = (value << 24) >> 24;
        // });

        result = masked_value.to_float() / (ir.constant(1) << gqr_scale);
    });

    ir._if(is_gqr_type_float(ir, gqr_type), () {
        result = value.interpret_as_float();
    });

    return result;
}

private IRVariable get_gqr_dequantization_type(IR* ir, IRVariable gqr) {
    return (gqr >> 16) & 7;
}

private IRVariable get_gqr_dequantization_scale(IR* ir, IRVariable gqr) {
    IRVariable scale = (gqr >> 24) & 63;

    // ensure the type is not 1, 2, or 3 (invalid types)
    ir.debug_assert(is_valid_gqr_scale(ir, scale));
    return scale;
}

private IRVariable is_gqr_type_float(IR* ir, IRVariable type) {
    return type.equals(ir.constant(0));
}

private IRVariable is_gqr_type_u16(IR* ir, IRVariable type) {
    return (type & 0b101).equals(ir.constant(0b101));
}

private IRVariable is_gqr_type_u8(IR* ir, IRVariable type) {
    return (type & 0b101).equals(ir.constant(0b100));
}

private IRVariable is_gqr_type_signed(IR* ir, IRVariable type) {
    return (type & 0b110).equals(ir.constant(0b101));
}

private IRVariable get_gqr_type_size(IR* ir, IRVariable type) {
    // 4 <- ~a
    // 2 <- a ^  c
    // 1 <- a ^ ~c
    // ~a * 4 + c * 2;

    // abc
    // 000 4 111 1 1 101 2 010
    // 001 4 110 1 0 100 2 011
    // 010 4 101 1 1 101 2 010
    // 011 4 100 1 0 100 2 011

    // 100 1 011 0 1 001 1 110 0
    // 101 2 010 0 0 000 0 111 1
    // 110 1 001 0 1 001 1 110 0
    // 111 2 000 0 0 000 0 111 1

    IRVariable c = ir.constant(4);

    ir._if(is_gqr_type_u8(ir, type), () {
        c = ir.constant(1);
    });

    ir._if(is_gqr_type_u16(ir, type), () {
        c = ir.constant(2);
    });

    return c;
}

private IRVariable is_valid_gqr_scale(IR* ir, IRVariable scale) {
    return scale.greater_signed(ir.constant(3)) | scale.notequals(ir.constant(0));
}
