module emu.hw.dsp.jit.emission.helpers;

import emu.hw.dsp.jit.emission.code;
import gallinule.x86;

void emit_wrapping_register_add(DspCode code, R16 ar, R16 wr, R16 ix, R16 sum) {
    R16 n    = code.allocate_register().cvt16();
    R16 mask = code.allocate_register().cvt16();
    R16 tmp  = code.allocate_register().cvt16();

    code.movzx(ix.cvt32(), ix);
    code.movzx(wr.cvt32(), wr);
    code.movzx(ar.cvt32(), ar);

    // source for this algorithm, the legendary duo:
    //    https://github.com/hrydgard for coming up with the initial algorithm     
    //    https://github.com/calc84maniac for refining it to this form

    // let N be the number of significant bits in WR, with a minimum of 1
    code.mov(n, wr);
    code.or(n, 1);
    code.bsr(n, n);
    code.add(n, 1);

    // create a mask out of N
    code.mov(mask, 1);
    code.mov(cl, n.cvt8());
    code.shl(mask.cvt32());
    code.sub(mask.cvt32(), 1);

    // let SUM be REG + IX...
    code.mov(sum.cvt32(), ar.cvt32());
    code.add(sum.cvt32(), ix.cvt32());

    // and let CARRY be the carry out of the low N bits of that addition
    R16 carry = ar;
    code.and(ar, mask);
    code.movzx(tmp.cvt32(), ix);
    code.and(tmp, mask);
    code.add(carry.cvt32(), tmp.cvt32());
    code.shr(carry.cvt32());
    code.and(carry, 1);

    // if IX >= 0 ...
    auto ix_negative = code.fresh_label();
    auto done = code.fresh_label();

    code.cmp(ix, 0);
    code.jl(ix_negative);

    // if CARRY == 1:
    code.cmp(carry, 0);
    code.je(done);

    // let SUM be SUM - WR - 1
    code.add(wr, 1);
    code.sub(sum, wr);
    code.jmp(done);

code.label(ix_negative);
    // if CARRY == 0 or the low N bits of SUM is less than the low N bits of ~WR:
    auto underflow = code.fresh_label();
    code.cmp(carry, 0);
    code.je(underflow);
    code.mov(tmp, wr);
    code.not(tmp);

    // reuse ix since it's no longer needed
    code.mov(ix, sum);
    code.and(ix, mask);
    code.and(tmp, mask);
    code.cmp(ix, tmp);
    code.jb(underflow);
    code.jmp(done);

code.label(underflow);
    // let SUM be SUM + (WR + 1)
    code.add(wr, 1);
    code.add(sum, wr);

code.label(done);

}