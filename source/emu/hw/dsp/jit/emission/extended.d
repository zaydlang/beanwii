module emu.hw.dsp.jit.emission.extended;

import emu.hw.dsp.dsp;
import emu.hw.dsp.jit.emission.code;
import emu.hw.dsp.jit.emission.decoder;
import emu.hw.dsp.jit.emission.helpers;
import gallinule.x86;
import util.log;
import util.number;
import util.x86;

void emit_ext_nop(DspCode code, EXT_NOP ext, DSP dsp_instance) {

}

void emit_ext_dr(DspCode code, EXT_DR ext, DSP dsp_instance) {
    R16 ar = code.allocate_register().cvt16();
    R16 wr = code.allocate_register().cvt16();
    R16 sum = code.allocate_register().cvt16();

    code.movzx(ar.cvt32(), code.ar_address(ext.r));
    code.movzx(wr.cvt32(), code.wr_address(ext.r));

    R32 tmp1 = code.allocate_register().cvt32();
    R32 tmp2 = code.allocate_register().cvt32();
    R32 tmp3 = code.allocate_register().cvt32();
    emit_wrapping_register_sub_one(code, ar, wr, sum, tmp1, tmp2, tmp3);
    code.mov(code.ar_address(ext.r), sum);

    code.deallocate_register(ar.cvt64());
    code.deallocate_register(wr.cvt64());
    code.deallocate_register(sum.cvt64());
    code.deallocate_register(tmp1.cvt64());
    code.deallocate_register(tmp2.cvt64());
    code.deallocate_register(tmp3.cvt64());
}

void emit_ext_ir(DspCode code, EXT_IR ext, DSP dsp_instance) {
    R16 ar = code.allocate_register().cvt16();
    R16 wr = code.allocate_register().cvt16();
    R16 sum = code.allocate_register().cvt16();

    code.movzx(ar.cvt32(), code.ar_address(ext.r));
    code.movzx(wr.cvt32(), code.wr_address(ext.r));

    R32 tmp1 = code.allocate_register().cvt32();
    R32 tmp2 = code.allocate_register().cvt32();
    R32 tmp3 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar, wr, sum, tmp1, tmp2, tmp3);
    code.mov(code.ar_address(ext.r), sum);

    code.deallocate_register(ar.cvt64());
    code.deallocate_register(wr.cvt64());
    code.deallocate_register(sum.cvt64());
    code.deallocate_register(tmp1.cvt64());
    code.deallocate_register(tmp2.cvt64());
    code.deallocate_register(tmp3.cvt64());
}

void emit_ext_nr(DspCode code, EXT_NR ext, DSP dsp_instance) {
    code.reserve_register(rcx);

    R16 ar = code.allocate_register().cvt16();
    R16 wr = code.allocate_register().cvt16();
    R16 ix = code.allocate_register().cvt16();

    code.mov(ar, code.ar_address(ext.r));
    code.mov(wr, code.wr_address(ext.r));
    code.mov(ix, code.ix_address(ext.r));

    R16 sum = code.allocate_register().cvt16();
    R16 tmp1 = code.allocate_register().cvt16();
    R16 tmp2 = code.allocate_register().cvt16();
    emit_wrapping_register_add(code, ar, wr, ix, sum, tmp1, tmp2);
    code.mov(code.ar_address(ext.r), sum);

    code.deallocate_register(ar.cvt64());
    code.deallocate_register(wr.cvt64());
    code.deallocate_register(ix.cvt64());
    code.deallocate_register(sum.cvt64());
    code.deallocate_register(tmp1.cvt64());
    code.deallocate_register(tmp2.cvt64());
}

void emit_ext_mv(DspCode code, EXT_MV ext, DSP dsp_instance) {
    R64 value = code.allocate_register();
    
    read_arbitrary_reg(code, value, 0x1c + ext.s);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    code.deallocate_register(value);
}

void emit_ext_s(DspCode code, EXT_S ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, value, 0x1c + ext.s);
    read_arbitrary_reg(code, address, ext.d);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar = tmp1.cvt16();
    R16 wr = tmp2.cvt16();
    R16 sum = value.cvt16();
    
    code.movzx(ar.cvt32(), code.ar_address(ext.d));
    code.movzx(wr.cvt32(), code.wr_address(ext.d));
    
    R32 tmp3 = address.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar, wr, sum, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(ext.d), sum);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_sn(DspCode code, EXT_SN ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, value, 0x1c + ext.s);
    read_arbitrary_reg(code, address, ext.d);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar = tmp1.cvt16();
    R16 wr = tmp2.cvt16();
    R16 ix = value.cvt16();
    
    code.mov(ar, code.ar_address(ext.d));
    code.mov(wr, code.wr_address(ext.d));
    code.mov(ix, code.ix_address(ext.d));
    
    R16 sum = address.cvt16();
    R16 tmp3 = code.allocate_register().cvt16();
    R16 tmp4 = code.allocate_register().cvt16();
    emit_wrapping_register_add(code, ar, wr, ix, sum, tmp3, tmp4);
    code.mov(code.ar_address(ext.d), sum);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
}

void emit_ext_l(DspCode code, EXT_L ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 address = code.allocate_register();
    R64 value = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, ext.s);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar = tmp1.cvt16();
    R16 wr = tmp2.cvt16();
    R16 sum = value.cvt16();
    
    code.movzx(ar.cvt32(), code.ar_address(ext.s));
    code.movzx(wr.cvt32(), code.wr_address(ext.s));
    
    R32 tmp3 = address.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar, wr, sum, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(ext.s), sum);
    
    code.deallocate_register(address);
    code.deallocate_register(value);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_ln(DspCode code, EXT_LN ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 address = code.allocate_register();
    R64 value = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, ext.s);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar = tmp1.cvt16();
    R16 wr = tmp2.cvt16();
    R16 ix = value.cvt16();
    
    code.mov(ar, code.ar_address(ext.s));
    code.mov(wr, code.wr_address(ext.s));
    code.mov(ix, code.ix_address(ext.s));
    
    R16 sum = address.cvt16();
    R16 tmp3 = code.allocate_register().cvt16();
    R16 tmp4 = code.allocate_register().cvt16();
    emit_wrapping_register_add(code, ar, wr, ix, sum, tmp3, tmp4);
    code.mov(code.ar_address(ext.s), sum);
    
    code.deallocate_register(address);
    code.deallocate_register(value);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
}

void emit_ext_ls(DspCode code, EXT_LS ext, DSP dsp_instance) {
    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, 0);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar = address.cvt16();
    R16 wr = tmp1.cvt16();
    R16 sum = value.cvt16();
    
    code.movzx(ar.cvt32(), code.ar_address(0));
    code.movzx(wr.cvt32(), code.wr_address(0));
    
    R32 tmp3 = tmp2.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar, wr, sum, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(0), sum);
    
    read_arbitrary_reg(code, address, 3);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    code.movzx(ar.cvt32(), code.ar_address(3));
    code.movzx(wr.cvt32(), code.wr_address(3));
    
    emit_wrapping_register_add_one(code, ar, wr, sum, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_sl(DspCode code, EXT_SL ext, DSP dsp_instance) {
    R64 address0 = code.allocate_register();
    R64 address3 = code.allocate_register();
    R64 value = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address0, 0);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address0, tmp1, tmp2, dsp_instance);
    
    read_arbitrary_reg(code, address3, 3);
    emit_read_data_memory(code, value, address3, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar0 = address0.cvt16();
    R16 wr0 = address3.cvt16();
    R16 sum0 = value.cvt16();
    
    code.movzx(ar0.cvt32(), code.ar_address(0));
    code.movzx(wr0.cvt32(), code.wr_address(0));
    
    R32 tmp3 = tmp1.cvt32();
    R32 tmp4 = tmp2.cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar0, wr0, sum0, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(0), sum0);
    
    R16 ar3 = address0.cvt16();
    R16 wr3 = address3.cvt16();
    R16 sum3 = value.cvt16();
    
    code.movzx(ar3.cvt32(), code.ar_address(3));
    code.movzx(wr3.cvt32(), code.wr_address(3));
    
    emit_wrapping_register_add_one(code, ar3, wr3, sum3, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(address0);
    code.deallocate_register(address3);
    code.deallocate_register(value);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_lsn(DspCode code, EXT_LSN ext, DSP dsp_instance) {
    code.reserve_register(rcx);

    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, 0);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar0 = address.cvt16();
    R16 wr0 = tmp1.cvt16();
    R16 ix0 = value.cvt16();
    
    code.mov(ar0, code.ar_address(0));
    code.mov(wr0, code.wr_address(0));
    code.mov(ix0, code.ix_address(0));
    
    R16 sum0 = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, ar0, wr0, ix0, sum0, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(0), sum0);
    
    read_arbitrary_reg(code, address, 3);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar3 = address.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 sum3 = value.cvt16();
    
    code.movzx(ar3.cvt32(), code.ar_address(3));
    code.movzx(wr3.cvt32(), code.wr_address(3));
    
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar3, wr3, sum3, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_sln(DspCode code, EXT_SLN ext, DSP dsp_instance) {
    code.reserve_register(rcx);

    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, 3);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    read_arbitrary_reg(code, address, 0);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar0 = address.cvt16();
    R16 wr0 = tmp1.cvt16();
    R16 ix0 = value.cvt16();
    
    code.mov(ar0, code.ar_address(0));
    code.mov(wr0, code.wr_address(0));
    code.mov(ix0, code.ix_address(0));
    
    R16 sum0 = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, ar0, wr0, ix0, sum0, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(0), sum0);
    
    R16 ar3 = address.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 sum3 = value.cvt16();
    
    code.movzx(ar3.cvt32(), code.ar_address(3));
    code.movzx(wr3.cvt32(), code.wr_address(3));
    
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar3, wr3, sum3, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_lsm(DspCode code, EXT_LSM ext, DSP dsp_instance) {
    code.reserve_register(rcx);

    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, 0);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar0 = address.cvt16();
    R16 wr0 = tmp1.cvt16();
    R16 sum0 = value.cvt16();
    
    code.movzx(ar0.cvt32(), code.ar_address(0));
    code.movzx(wr0.cvt32(), code.wr_address(0));
    
    R32 tmp3 = tmp2.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar0, wr0, sum0, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(0), sum0);
    
    read_arbitrary_reg(code, address, 3);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar3 = address.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp5.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_slm(DspCode code, EXT_SLM ext, DSP dsp_instance) {
    code.reserve_register(rcx);

    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, 0);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar0 = address.cvt16();
    R16 wr0 = tmp1.cvt16();
    R16 sum0 = value.cvt16();
    
    code.movzx(ar0.cvt32(), code.ar_address(0));
    code.movzx(wr0.cvt32(), code.wr_address(0));
    
    R32 tmp3 = tmp2.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar0, wr0, sum0, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(0), sum0);
    
    read_arbitrary_reg(code, address, 3);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar3 = address.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp5.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_lsnm(DspCode code, EXT_LSNM ext, DSP dsp_instance) {
    code.reserve_register(rcx);

    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, 0);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    R16 ar0 = address.cvt16();
    R16 wr0 = tmp1.cvt16();
    R16 ix0 = value.cvt16();
    
    code.mov(ar0, code.ar_address(0));
    code.mov(wr0, code.wr_address(0));
    code.mov(ix0, code.ix_address(0));
    
    R16 sum0 = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, ar0, wr0, ix0, sum0, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(0), sum0);
    
    read_arbitrary_reg(code, address, 3);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar3 = address.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
}

void emit_ext_slnm(DspCode code, EXT_SLNM ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address, 3);
    emit_read_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d);
    
    read_arbitrary_reg(code, address, 0);
    read_arbitrary_reg(code, value, 0x1e + ext.s);
    emit_write_data_memory(code, value, address, tmp1, tmp2, dsp_instance);
    
    R16 ar0 = address.cvt16();
    R16 wr0 = tmp1.cvt16();
    R16 ix0 = value.cvt16();
    
    code.mov(ar0, code.ar_address(0));
    code.mov(wr0, code.wr_address(0));
    code.mov(ix0, code.ix_address(0));
    
    R16 sum0 = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, ar0, wr0, ix0, sum0, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(0), sum0);
    
    R16 ar3 = address.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
}

void emit_ext_ld(DspCode code, EXT_LD ext, DSP dsp_instance) {
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d * 2);
    
    R16 page1 = address1.cvt16();
    code.mov(tmp2, address2);
    code.shr(page1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    
    code.cmp(page1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    
    code.label(same_page_label);
    
    write_arbitrary_reg(code, value, 0x19 + ext.r * 2);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 sumS = value.cvt16();
    
    code.movzx(arS.cvt32(), code.ar_address(ext.s));
    code.movzx(wrS.cvt32(), code.wr_address(ext.s));
    
    R32 tmp3 = tmp2.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, arS, wrS, sumS, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 sum3 = value.cvt16();
    
    code.movzx(ar3.cvt32(), code.ar_address(3));
    code.movzx(wr3.cvt32(), code.wr_address(3));
    
    emit_wrapping_register_add_one(code, ar3, wr3, sum3, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_ldax(DspCode code, EXT_LDAX ext, DSP dsp_instance) {
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x1a + ext.r);
    
    code.mov(tmp1.cvt32(), address1.cvt32());
    code.mov(tmp2.cvt32(), address2.cvt32());
    code.shr(tmp1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    auto different_page_label = code.fresh_label();
    
    code.cmp(tmp1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    code.jmp(different_page_label);
    
    code.label(same_page_label);
    
    code.label(different_page_label);
    write_arbitrary_reg(code, value, 0x18 + ext.r);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 sumS = value.cvt16();
    
    code.movzx(arS.cvt32(), code.ar_address(ext.s));
    code.movzx(wrS.cvt32(), code.wr_address(ext.s));
    
    R32 tmp3 = tmp2.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, arS, wrS, sumS, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 sum3 = value.cvt16();
    
    code.movzx(ar3.cvt32(), code.ar_address(3));
    code.movzx(wr3.cvt32(), code.wr_address(3));
    
    emit_wrapping_register_add_one(code, ar3, wr3, sum3, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_ldn(DspCode code, EXT_LDN ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d * 2);
    
    code.mov(tmp1.cvt32(), address1.cvt32());
    code.mov(tmp2.cvt32(), address2.cvt32());
    code.shr(tmp1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    auto different_page_label = code.fresh_label();
    
    code.cmp(tmp1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    code.jmp(different_page_label);
    
    code.label(same_page_label);
    
    code.label(different_page_label);
    write_arbitrary_reg(code, value, 0x19 + ext.r * 2);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 ixS = value.cvt16();
    
    code.mov(arS, code.ar_address(ext.s));
    code.mov(wrS, code.wr_address(ext.s));
    code.mov(ixS, code.ix_address(ext.s));
    
    R16 sumS = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, arS, wrS, ixS, sumS, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 sum3 = value.cvt16();
    
    code.movzx(ar3.cvt32(), code.ar_address(3));
    code.movzx(wr3.cvt32(), code.wr_address(3));
    
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar3, wr3, sum3, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_ldaxn(DspCode code, EXT_LDAXN ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x1a + ext.r);
    
    code.mov(tmp1.cvt32(), address1.cvt32());
    code.mov(tmp2.cvt32(), address2.cvt32());
    code.shr(tmp1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    auto different_page_label = code.fresh_label();
    
    code.cmp(tmp1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    code.jmp(different_page_label);
    
    code.label(same_page_label);
    
    code.label(different_page_label);
    write_arbitrary_reg(code, value, 0x18 + ext.r);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 ixS = value.cvt16();
    
    code.mov(arS, code.ar_address(ext.s));
    code.mov(wrS, code.wr_address(ext.s));
    code.mov(ixS, code.ix_address(ext.s));
    
    R16 sumS = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, arS, wrS, ixS, sumS, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 sum3 = value.cvt16();
    
    code.movzx(ar3.cvt32(), code.ar_address(3));
    code.movzx(wr3.cvt32(), code.wr_address(3));
    
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, ar3, wr3, sum3, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_ldm(DspCode code, EXT_LDM ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d * 2);
    
    code.mov(tmp1.cvt32(), address1.cvt32());
    code.mov(tmp2.cvt32(), address2.cvt32());
    code.shr(tmp1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    auto different_page_label = code.fresh_label();
    
    code.cmp(tmp1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    code.jmp(different_page_label);
    
    code.label(same_page_label);
    
    code.label(different_page_label);
    write_arbitrary_reg(code, value, 0x19 + ext.r * 2);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 sumS = value.cvt16();
    
    code.movzx(arS.cvt32(), code.ar_address(ext.s));
    code.movzx(wrS.cvt32(), code.wr_address(ext.s));
    
    R32 tmp3 = tmp2.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, arS, wrS, sumS, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp5.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_ldaxm(DspCode code, EXT_LDAXM ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x1a + ext.r);
    
    code.mov(tmp1.cvt32(), address1.cvt32());
    code.mov(tmp2.cvt32(), address2.cvt32());
    code.shr(tmp1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    auto different_page_label = code.fresh_label();
    
    code.cmp(tmp1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    code.jmp(different_page_label);
    
    code.label(same_page_label);
    
    code.label(different_page_label);
    write_arbitrary_reg(code, value, 0x18 + ext.r);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 sumS = value.cvt16();
    
    code.movzx(arS.cvt32(), code.ar_address(ext.s));
    code.movzx(wrS.cvt32(), code.wr_address(ext.s));
    
    R32 tmp3 = tmp2.cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    R32 tmp5 = code.allocate_register().cvt32();
    emit_wrapping_register_add_one(code, arS, wrS, sumS, tmp3, tmp4, tmp5);
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp5.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp4.cvt64());
    code.deallocate_register(tmp5.cvt64());
}

void emit_ext_ldnm(DspCode code, EXT_LDNM ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x18 + ext.d * 2);
    
    code.mov(tmp1.cvt32(), address1.cvt32());
    code.mov(tmp2.cvt32(), address2.cvt32());
    code.shr(tmp1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    auto different_page_label = code.fresh_label();
    
    code.cmp(tmp1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    code.jmp(different_page_label);
    
    code.label(same_page_label);
    
    code.label(different_page_label);
    write_arbitrary_reg(code, value, 0x19 + ext.r * 2);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 ixS = value.cvt16();
    
    code.mov(arS, code.ar_address(ext.s));
    code.mov(wrS, code.wr_address(ext.s));
    code.mov(ixS, code.ix_address(ext.s));
    
    R16 sumS = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, arS, wrS, ixS, sumS, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
}

void emit_ext_ldaxnm(DspCode code, EXT_LDAXNM ext, DSP dsp_instance) {
    code.reserve_register(rcx);
    
    R64 value = code.allocate_register();
    R64 address1 = code.allocate_register();
    R64 address2 = code.allocate_register();
    R64 tmp1 = code.allocate_register();
    R64 tmp2 = code.allocate_register();
    
    read_arbitrary_reg(code, address1, ext.s);
    read_arbitrary_reg(code, address2, 3);
    
    emit_read_data_memory(code, value, address1, tmp1, tmp2, dsp_instance);
    write_arbitrary_reg(code, value, 0x1a + ext.r);
    
    code.mov(tmp1.cvt32(), address1.cvt32());
    code.mov(tmp2.cvt32(), address2.cvt32());
    code.shr(tmp1.cvt32(), 10);
    code.shr(tmp2.cvt32(), 10);
    
    auto same_page_label = code.fresh_label();
    auto different_page_label = code.fresh_label();
    
    code.cmp(tmp1.cvt32(), tmp2.cvt32());
    code.je(same_page_label);
    
    emit_read_data_memory(code, value, address2, tmp1, tmp2, dsp_instance);
    code.jmp(different_page_label);
    
    code.label(same_page_label);
    
    code.label(different_page_label);
    write_arbitrary_reg(code, value, 0x18 + ext.r);
    
    R16 arS = address1.cvt16();
    R16 wrS = tmp1.cvt16();
    R16 ixS = value.cvt16();
    
    code.mov(arS, code.ar_address(ext.s));
    code.mov(wrS, code.wr_address(ext.s));
    code.mov(ixS, code.ix_address(ext.s));
    
    R16 sumS = tmp2.cvt16();
    R32 tmp3 = code.allocate_register().cvt32();
    R32 tmp4 = code.allocate_register().cvt32();
    emit_wrapping_register_add(code, arS, wrS, ixS, sumS, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(ext.s), sumS);
    
    R16 ar3 = address2.cvt16();
    R16 wr3 = tmp1.cvt16();
    R16 ix3 = value.cvt16();
    
    code.mov(ar3, code.ar_address(3));
    code.mov(wr3, code.wr_address(3));
    code.mov(ix3, code.ix_address(3));
    
    R16 sum3 = tmp2.cvt16();
    emit_wrapping_register_add(code, ar3, wr3, ix3, sum3, tmp3.cvt16(), tmp4.cvt16());
    code.mov(code.ar_address(3), sum3);
    
    code.deallocate_register(value);
    code.deallocate_register(address1);
    code.deallocate_register(address2);
    code.deallocate_register(tmp1);
    code.deallocate_register(tmp2);
    code.deallocate_register(tmp3.cvt64());
    code.deallocate_register(tmp4.cvt64());
}

void handle_extension_instruction(DspCode code, DecodedInstruction decoded, DSP dsp_instance) {
    u16 saved_allocated_regs = code.allocated_regs;
    u16 rdi_mask = cast(u16) (1 << reg64_to_u16(rdi));
    u16 rsi_mask = cast(u16) (1 << reg64_to_u16(rsi));
    u16 active_regs = code.allocated_regs & ~(rdi_mask | rsi_mask);
    
    for (int reg_index = 0; reg_index < 16; reg_index++) {
        if (active_regs & (1 << reg_index)) {
            R64 reg = u16_to_reg64(cast(u16) reg_index);
            code.push(reg);
        }
    }
    
    code.allocated_regs = rdi_mask | rsi_mask;
    
    final switch (decoded.extension.opcode) {
        case ExtensionOpcode.EXT_NOP: emit_ext_nop(code, decoded.extension.nop, dsp_instance); break;
        case ExtensionOpcode.EXT_DR: emit_ext_dr(code, decoded.extension.dr, dsp_instance); break;
        case ExtensionOpcode.EXT_IR: emit_ext_ir(code, decoded.extension.ir, dsp_instance); break;
        case ExtensionOpcode.EXT_NR: emit_ext_nr(code, decoded.extension.nr, dsp_instance); break;
        case ExtensionOpcode.EXT_MV: emit_ext_mv(code, decoded.extension.mv, dsp_instance); break;
        case ExtensionOpcode.EXT_S: emit_ext_s(code, decoded.extension.s, dsp_instance); break;
        case ExtensionOpcode.EXT_SN: emit_ext_sn(code, decoded.extension.sn, dsp_instance); break;
        case ExtensionOpcode.EXT_L: emit_ext_l(code, decoded.extension.l, dsp_instance); break;
        case ExtensionOpcode.EXT_LN: emit_ext_ln(code, decoded.extension.ln, dsp_instance); break;
        case ExtensionOpcode.EXT_LS: emit_ext_ls(code, decoded.extension.ls, dsp_instance); break;
        case ExtensionOpcode.EXT_SL: emit_ext_sl(code, decoded.extension.sl, dsp_instance); break;
        case ExtensionOpcode.EXT_LSN: emit_ext_lsn(code, decoded.extension.lsn, dsp_instance); break;
        case ExtensionOpcode.EXT_SLN: emit_ext_sln(code, decoded.extension.sln, dsp_instance); break;
        case ExtensionOpcode.EXT_LSM: emit_ext_lsm(code, decoded.extension.lsm, dsp_instance); break;
        case ExtensionOpcode.EXT_SLM: emit_ext_slm(code, decoded.extension.slm, dsp_instance); break;
        case ExtensionOpcode.EXT_LSNM: emit_ext_lsnm(code, decoded.extension.lsnm, dsp_instance); break;
        case ExtensionOpcode.EXT_SLNM: emit_ext_slnm(code, decoded.extension.slnm, dsp_instance); break;
        case ExtensionOpcode.EXT_LD: emit_ext_ld(code, decoded.extension.ld, dsp_instance); break;
        case ExtensionOpcode.EXT_LDAX: emit_ext_ldax(code, decoded.extension.ldax, dsp_instance); break;
        case ExtensionOpcode.EXT_LDN: emit_ext_ldn(code, decoded.extension.ldn, dsp_instance); break;
        case ExtensionOpcode.EXT_LDAXN: emit_ext_ldaxn(code, decoded.extension.ldaxn, dsp_instance); break;
        case ExtensionOpcode.EXT_LDM: emit_ext_ldm(code, decoded.extension.ldm, dsp_instance); break;
        case ExtensionOpcode.EXT_LDAXM: emit_ext_ldaxm(code, decoded.extension.ldaxm, dsp_instance); break;
        case ExtensionOpcode.EXT_LDNM: emit_ext_ldnm(code, decoded.extension.ldnm, dsp_instance); break;
        case ExtensionOpcode.EXT_LDAXNM: emit_ext_ldaxnm(code, decoded.extension.ldaxnm, dsp_instance); break;
    }
    
    for (int reg_index = 15; reg_index >= 0; reg_index--) {
        if (active_regs & (1 << reg_index)) {
            R64 reg = u16_to_reg64(cast(u16) reg_index);
            code.pop(reg);
        }
    }
    
    code.allocated_regs = saved_allocated_regs;
    code.extension_handled = true;
}

void handle_extension_opcode(DspCode code, DecodedInstruction decoded_instruction, DSP dsp_instance) {
    if (decoded_instruction.has_extension) {
        handle_extension_instruction(code, decoded_instruction, dsp_instance);
    }

    if (decoded_instruction.main.opcode == DspOpcode.MULCAC) {
        log_dsp("Handling MULCAC opcode %s", decoded_instruction);
    }
}