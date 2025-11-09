import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + "/dsp_codegen")

import assembler
import fuzz
import random

def r(low, high):
    return random.randint(low, high)

def i(low, high):
    while True:
        value = fuzz.generate_pseudo_values(1)[0]
        if low <= value <= high:
            return value

def c(low, high):
    return random.randint(low, high)

def sanity():
    assembler.nop()

def abs():
    assembler.abs(r(0, 1), 0)

def add():
    assembler.add(r(0, 1), 0)

def addarn():
    assembler.addarn(r(0, 3), r(0, 3))

def addax():
    assembler.addax(r(0, 1), r(0, 1), 0)

def addaxl():
    assembler.addaxl(r(0, 1), r(0, 1), 0)

def addi():
    assembler.addi(r(0, 1), i(0, 0xffff))

def addis():
    assembler.addis(r(0, 1), i(0, 0xff))

def addp():
    assembler.addp(r(0, 1), 0)

def addpaxz():
    assembler.addpaxz(r(0, 1), r(0, 1), 0)

def addr():
    assembler.addr(r(0, 3), r(0, 1), 0)

def andc():
    assembler.andc(r(0, 1), 0)

def andcf():
    assembler.andcf(r(0, 1), i(0, 0xffff))

def andf():
    assembler.andf(r(0, 1), i(0, 0xffff))

def andi():
    assembler.andi(r(0, 1), i(0, 0xffff))

def andr():
    assembler.andr(r(0, 1), r(0, 1), 0)

def asl():
    assembler.asl(r(0, 1), i(0, 63))

def asr():
    assembler.asr(r(0, 1), i(0, 63))

def asrn():
    assembler.asrn()

def asrnr():
    assembler.asrnr(r(0, 1), 0)

def asrnrx():
    assembler.asrnrx(r(0, 1), r(0, 1), 0)

def asr16():
    assembler.asr16(r(0, 1), 0)

def clr15():
    assembler.clr15(0)

def clr():
    assembler.clr(r(0, 1), 0)

def clrl():
    assembler.clrl(r(0, 1), 0)

def clrp():
    assembler.clrp(0)

def cmp():
    assembler.cmp(0)

def cmpaxh():
    assembler.cmpaxh(r(0, 1), r(0, 1), 0)

def cmpi():
    assembler.lri(16, 0xffff)
    assembler.lri(30, 0xfd34)
    assembler.lri(28, 0x00ff)
    assembler.cmpi(r(0, 1), 0x8000)

def cmpis():
    assembler.cmpis(r(0, 1), i(0, 0xff))

def dar():
    assembler.dar(r(0, 3))

def dec():
    assembler.dec(r(0, 1), 0)

def decm():
    assembler.decm(r(0, 1), 0)

def iar():
    assembler.iar(r(0, 3))

def if_cc():
    long_form = random.choice([True, False])
    if long_form:
        assembler.if_cc(c(0, 15))
        assembler.andi(0, 0x8c00) # 0x8c00 is clr15
    else:
        assembler.if_cc(c(0, 15))
        assembler.clr15(0)
        assembler.nop()

def inc():
    assembler.inc(r(0, 1), 0)

def incm():
    assembler.incm(r(0, 1), 0)

def lsl():
    assembler.lsl(r(0, 1), i(0, 63))

def lsl16():
    assembler.lsl16(r(0, 1), 0)

def lsr():
    assembler.lsr(r(0, 1), i(0, 63))

def lsrn():
    assembler.lsrn()

def lsrnr():
    assembler.lsrnr(r(0, 1), 0)

def lsrnrx():
    assembler.lsrnrx(r(0, 1), r(0, 1), 0)

def lsr16():
    assembler.lsr16(r(0, 1), 0)

def lri():
    rand = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    assembler.lri(rand(), i(0, 0xffff))

def lris():
    assembler.lri(r(0, 7), i(0, 0xff))

def m0():
    assembler.m0(0)

def m2():
    assembler.m2(0)

def madd():
    assembler.madd(r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def maddc():
    assembler.maddc(r(0, 1), r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def maddx():
    assembler.maddx(r(0, 1), r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mov():
    assembler.mov(r(0, 1), 0)

def movax():
    assembler.movax(r(0, 1), r(0, 1), 0)

def movnp():
    assembler.movnp(r(0, 1), 0)

def movp():
    assembler.movp(r(0, 1), 0)

def movpz():
    assembler.movpz(r(0, 1), 0)

def movr():
    assembler.movr(r(0, 1), r(0, 1), 0)

def mrr():
    rand = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    assembler.mrr(rand(), rand())

def msub():
    assembler.msub(r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def msubc():
    assembler.msubc(r(0, 1), r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def msubx():
    assembler.msubx(r(0, 1), r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mul():
    assembler.mul(r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulac():
    assembler.mulac(r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulaxh():
    assembler.mulaxh(0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulc():
    assembler.mulc(r(0, 1), r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulcac():
    assembler.mulcac(r(0, 1), r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulcmv():
    assembler.mulcmv(r(0, 1), r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulcmvz():
    assembler.mulcmvz(r(0, 1), r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulmv():
    assembler.mulmv(r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulmvz():
    assembler.mulmvz(r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulx():
    assembler.mulx(r(0, 1), r(0, 1), 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulxac():
    assembler.mulxac(r(0, 1), r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulxmv():
    assembler.mulxmv(r(0, 1), r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def mulxmvz():
    assembler.mulxmvz(r(0, 1), r(0, 1), 1, 0)
    assembler.clr(0, 0)
    assembler.addp(0, 0)
    assembler.clrp(0)

def neg():
    assembler.neg(r(0, 1), 0)

def _not():
    assembler._not(r(0, 1), 0)

def orc():
    assembler.orc(r(0, 1), 0)

def ori():
    assembler.ori(r(0, 1), i(0, 0xffff))

def orr():
    assembler.orr(r(0, 1), r(0, 1), 0)

def sbclr():
    assembler.sbclr(i(0, 7))

def sbset():
    assembler.sbset(i(0, 7))

def set15():
    assembler.set15(0)

def set16():
    assembler.set16(0)

def set40():
    assembler.set40(0)

def sub():
    assembler.sub(r(0, 1), 0)

def subarn():
    assembler.subarn(r(0, 3))

def subax():
    assembler.subax(r(0, 1), r(0, 1), 0)

def subp():
    assembler.subp(r(0, 1), 0)

def subr():
    assembler.subr(r(0, 3), r(0, 1), 0)

def tst():
    assembler.tst(r(0, 1), 0)

def tstaxh():
    assembler.tstaxh(r(0, 1), 0)

def tstprod():
    assembler.tstprod(0)

def xorc():
    assembler.xorc(r(0, 1), 0)

def xori():
    assembler.xori(r(0, 1), i(0, 0xffff))

def xorr():
    assembler.xorr(r(0, 1), r(0, 1), 0)

def bloop():
    assembler.clr(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)

    label = assembler.get_label()
    end_label = label + 3 + 62
    assembler.bloop(1, end_label)
    assembler.addi(0, 0x100)

    assembler.clr(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)
    assembler.inc(1, 0)

    label = assembler.get_label()
    end_label = label + 3 + 62
    assembler.bloop(1, end_label)
    assembler.addi(0, 0x1000)

bloop.count = 1

def bloopi():
    label = assembler.get_label()
    end_label = label + 3 + 62
    print(end_label)

    assembler.bloopi(3, end_label)
    assembler.addi(0, 0x100)

    label = assembler.get_label()
    end_label = label + 3 + 62

    assembler.bloopi(10, end_label)
    assembler.addi(0, 0x1000)

    label = assembler.get_label()
    end_label_outer = label + 3 + 62
    end_label_inner = label + 7 + 62

    assembler.bloopi(3, end_label_outer)
    assembler.addi(0, 0x200)
    assembler.bloopi(4, end_label_inner)
    assembler.addi(0, 0x2)

bloopi.count = 1

def jmp_cc():
    target = 4 + 62
    assembler.jmp_cc(c(0, 15), target)
    assembler.addi(0, 0x888)
    assembler.addi(1, 0x888)
    assembler.addi(1, 0x2345)

def jmpr_cc():
    target = 7 + 62
    rand = r(4, 7)
    assembler.lri(rand, target)
    assembler.jmpr_cc(rand, c(0, 15))
    assembler.addi(0, 0x666)
    assembler.addi(1, 0x666)
    assembler.addi(1, 0x6789)

jmpr_cc.count = 1

def call_cc():
    target = 5 + 62
    assembler.call_cc(c(0, 15), target)
    assembler.addi(0, 0x888)
    assembler.addi(1, 0x888)
    assembler.addi(1, 0x2345)

def callr_cc():
    target = 6 + 62
    assembler.lri(r(4, 7), target)
    assembler.callrcc(r(4, 7), c(0, 15))
    assembler.addi(0, 0x666)
    assembler.addi(1, 0x666)
    assembler.addi(1, 0x6789)

def ret_cc():
    assembler.call_cc(15, 66)
    assembler.jmp_cc(15, 71)  # always jump to skip ret on second pass
    assembler.addi(0, 0x888)
    assembler.addi(1, 0x888)
    assembler.ret_cc(c(0, 15))
    assembler.addi(0, 0x999)
    assembler.addi(1, 0x999)

def lr_sr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    reg1 = rand_reg()
    reg2 = rand_reg()
    
    assembler.lri(reg1, test_value)
    assembler.sr(reg1, test_addr)
    assembler.lr(reg2, test_addr)

def lrr_sr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)  # AR0-AR3 for addressing
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.sr(value_reg, test_addr)
    assembler.lrr(addr_reg, dest_reg)

def lrrd_sr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.sr(value_reg, test_addr)
    assembler.lrrd(addr_reg, dest_reg)

def lrri_sr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.sr(value_reg, test_addr)
    assembler.lrri(addr_reg, dest_reg)

def lrrn_sr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.sr(value_reg, test_addr)
    assembler.lrrn(addr_reg, dest_reg)

def lrs_sr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_cr = i(0x01, 0x0F)
    test_offset = i(0x00, 0xFF)
    
    value_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(18, test_cr)
    test_addr = (test_cr << 8) | test_offset
    assembler.sr(value_reg, test_addr)
    assembler.lrs(r(0, 7), test_offset)

def srr_lr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.srr(addr_reg, value_reg)
    assembler.lr(dest_reg, test_addr)

def srrd_lr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.srrd(addr_reg, value_reg)
    assembler.lr(dest_reg, test_addr)

def srri_lr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.srri(addr_reg, value_reg)
    assembler.lr(dest_reg, test_addr) 

def srrn_lr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    test_ix = i(0x01, 0x0F)
    
    value_reg = rand_reg()
    addr_reg = r(0, 3)
    dest_reg = rand_reg()
    
    assembler.lri(value_reg, test_value)
    assembler.lri(addr_reg, test_addr)
    assembler.lri(addr_reg + 4, test_ix)
    assembler.srrn(addr_reg, value_reg)
    assembler.lr(dest_reg, test_addr)

def srsh_lr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_cr = i(0x01, 0x0F)
    test_offset = i(0x00, 0xFF)
    
    ac_reg = r(0, 1)
    dest_reg = rand_reg()
    
    assembler.lri(16 + ac_reg, test_value)
    assembler.lri(18, test_cr)
    assembler.srsh(ac_reg, test_offset)
    test_addr = (test_cr << 8) | test_offset
    assembler.lr(dest_reg, test_addr)

def srs_lr():
    rand_reg = lambda : random.sample([x for x in list(range(32)) if not x in [12, 13, 14, 15, 18]], 1)[0]
    test_value = i(0x1000, 0xFFFF)
    test_cr = i(0x01, 0x0F)
    test_offset = i(0x00, 0xFF)
    test_s = r(0, 3) 
    
    dest_reg = rand_reg()
    
    assembler.lri(0x1C + test_s, test_value) 
    assembler.lri(18, test_cr) 
    test_addr = (test_cr << 8) | test_offset
    assembler.srs(test_s, test_offset)
    assembler.lr(dest_reg, test_addr)

def rti_cc():
    assembler.call_cc(15, 66)
    assembler.jmp_cc(15, 71)
    assembler.addi(0, 0x888)
    assembler.addi(1, 0x888)
    assembler.rti_cc(c(0, 15))
    assembler.addi(0, 0x999)
    assembler.addi(1, 0x999)

def ext_nop():
    assembler.nx(0, 0)
    assembler.ext_nop(0)

def ext_dr():
    assembler.nx(0, 0)
    assembler.ext_dr(r(0, 3))

def ext_ir():
    assembler.nx(0, 0)
    assembler.ext_ir(r(0, 3))

def ext_nr():
    assembler.nx(0, 0)
    assembler.ext_nr(r(0, 3))

def ext_mv():
    assembler.nx(0, 0)
    assembler.ext_mv(r(0, 3), r(0, 3))

def ext_s():
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    address_reg = r(0, 3)
    
    assembler.lri(28, test_value)
    assembler.lri(address_reg, test_addr)
    assembler.nx(0, 0)
    assembler.ext_s(r(0, 3), address_reg)

def ext_sn():
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    address_reg = r(0, 3)
    
    assembler.lri(28, test_value)
    assembler.lri(address_reg, test_addr)
    assembler.nx(0, 0)
    assembler.ext_sn(r(0, 3), address_reg)

def ext_l():
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    address_reg = r(0, 3)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr)
    assembler.lri(address_reg, test_addr)
    assembler.nx(0, 0)
    assembler.ext_l(r(0, 3), address_reg)

def ext_ln():
    test_value = i(0x1000, 0xFFFF)
    test_addr = i(0x100, 0xFFF)
    address_reg = r(0, 3)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr)
    assembler.lri(address_reg, test_addr)
    assembler.nx(0, 0)
    assembler.ext_ln(r(0, 7), address_reg)

def ext_ls():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr0)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_ls(r(0, 3), r(0, 1))

def ext_sl():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr3)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_sl(r(0, 3), r(0, 1))

def ext_lsn():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr0)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_lsn(r(0, 3), r(0, 1))

def ext_sln():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    source_reg = r(0, 1)
    dest_reg = r(0, 3)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr3)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_sln(dest_reg, source_reg)

def ext_lsm():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr0)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_lsm(r(0, 3), r(0, 1))

def ext_slm():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    source_reg = r(0, 1)
    dest_reg = r(0, 3)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr3)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_slm(dest_reg, source_reg)

def ext_lsnm():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr0)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_lsnm(r(0, 3), r(0, 1))

def ext_slnm():
    test_value = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    source_reg = r(0, 1)
    dest_reg = r(0, 3)
    
    assembler.lri(24, test_value)
    assembler.sr(24, test_addr3)
    assembler.lri(30, test_value)
    assembler.lri(0, test_addr0)
    assembler.lri(3, test_addr3)
    assembler.nx(0, 0)
    assembler.ext_slnm(dest_reg, source_reg)

def ext_ld():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 2)
    dest_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ld(dest_reg, r_reg, source_reg)

def ext_ldax():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ldax(source_reg, r_reg)

def ext_ldn():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 2)
    dest_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ldn(dest_reg, r_reg, source_reg)

def ext_ldaxn():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ldaxn(source_reg, r_reg)

def ext_ldm():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 2)
    dest_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ldm(dest_reg, r_reg, source_reg)

def ext_ldaxm():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ldaxm(source_reg, r_reg)

def ext_ldnm():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 2)
    dest_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ldnm(dest_reg, r_reg, source_reg)

def ext_ldaxnm():
    test_value0 = i(0x1000, 0xFFFF)
    test_value3 = i(0x1000, 0xFFFF)
    test_addr0 = i(0x100, 0xFFF)
    test_addr3 = i(0x100, 0xFFF)
    
    source_reg = r(0, 1)
    r_reg = r(0, 1)
    
    assembler.lri(28, test_value0)
    assembler.lri(source_reg, test_addr0)
    assembler.sr(28, test_addr0)
    
    assembler.lri(29, test_value3)
    assembler.lri(3, test_addr3)
    assembler.sr(29, test_addr3)
    
    assembler.nx(0, 0)
    assembler.ext_ldaxnm(source_reg, r_reg)

test_cases = [
    sanity,
    abs,
    addarn,
    addax,
    addaxl,
    addi,
    addis,
    addp,
    addpaxz,
    addr,
    andc,
    andcf,
    andf,
    andi,
    andr,
    asl,
    asr,
    asrn,
    asrnr,
    asrnrx,
    asr16,
    clr15,
    clr,
    clrl,
    clrp,
    cmp,
    cmpaxh,
    cmpi,
    cmpis,
    dar,
    dec,
    decm,
    iar,
    if_cc,
    inc,
    incm,
    lsl,
    lsl16,
    lsr,
    lsrn,
    lsrnr,
    lsrnrx,
    lsr16,
    lri,
    lris,
    lr_sr,
    lrr_sr,
    lrrd_sr,
    lrri_sr,
    lrrn_sr,
    lrs_sr,
    srr_lr,
    srrd_lr,
    srri_lr,
    srrn_lr,
    srs_lr,
    srsh_lr,
    m0,
    m2,
    madd,
    maddc,
    maddx,
    mov,
    movax,
    movnp,
    movp,
    movpz,
    movr,
    mrr,
    msub,
    msubc,
    msubx,
    mul,
    mulac,
    mulaxh,
    mulc,
    mulcac,
    mulcmv,
    mulcmvz,
    mulmv,
    mulmvz,
    mulx,
    mulxac,
    mulxmv,
    mulxmvz,
    neg,
    _not,
    orc,
    ori,
    orr,
    sbclr,
    sbset,
    set15,
    set16,
    set40,
    sub,
    subarn,
    subax,
    subp,
    subr,
    tst,
    tstaxh,
    tstprod,
    xorc,
    xori,
    xorr,

    bloop,
    bloopi,
    
    jmp_cc,
    jmpr_cc,
    call_cc,
    callr_cc,
    ret_cc,
    rti_cc,
    
    ext_nop,
    ext_dr,
    ext_ir,
    ext_nr,
    ext_mv,
    ext_s,
    ext_sn,
    ext_l,
    ext_ln,
    ext_ls,
    ext_sl,
    ext_lsn,
    ext_sln,
    ext_lsm,
    ext_slm,
    ext_lsnm,
    ext_slnm,
    ext_ld,
    ext_ldax,
    ext_ldn,
    ext_ldaxn,
    ext_ldm,
    ext_ldaxm,
    ext_ldnm,
    ext_ldaxnm,
]

# if len(sys.argv) < 2:
test_cases = [tc for tc in test_cases if tc.__name__.startswith(sys.argv[2]) or len(sys.argv) == 2]

if len(test_cases) == 0:
    print("No test cases matched the filter.")
    exit(0)

# check for compilation first
for test_case in test_cases:
    test_case()

for test_case in test_cases:
    count = getattr(test_case, 'count', 100)
    print(f"Generating test case: {test_case.__name__} ({count} iterations)")
    fuzz.send_to_wii(sys.argv[1], f"source/test/dsp/tests/{test_case.__name__}.bin", *fuzz.do_tests(test_case, count))

print("All done!")