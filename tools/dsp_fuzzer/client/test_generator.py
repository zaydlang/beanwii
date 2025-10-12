import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + "/dsp_codegen")

import assembler
import fuzz
import random

def r(low, high):
    return random.randint(low, high)

def i(low, high):
    return random.randint(low, high)

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
    assembler.cmpi(r(0, 1), i(0, 0xffff))

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
    long_form = True
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
    xorr
]

test_cases = [tc for tc in test_cases if sys.argv[2] in tc.__name__ or len(sys.argv) == 2]

if len(test_cases) == 0:
    print("No test cases matched the filter.")
    exit(0)

# check for compilation first
for test_case in test_cases:
    test_case()

for test_case in test_cases:
    print("Generating test case:", test_case.__name__)
    fuzz.send_to_wii(sys.argv[1], f"source/test/dsp/tests/{test_case.__name__}.bin", *fuzz.do_tests(test_case, 1000))

print("All done!")