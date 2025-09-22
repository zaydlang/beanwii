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
    andi
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