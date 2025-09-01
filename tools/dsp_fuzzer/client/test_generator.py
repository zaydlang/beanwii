import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + "/dsp_codegen")

import assembler
import fuzz
import random

def r(low, high):
    return random.randint(low, high)

def sanity():
    assembler.nop()

def abs():
    assembler.abs(r(0, 1), 0)

def add():
    assembler.add(r(0, 1), 0)

test_cases = [
    sanity,
    abs,
    add
]

test_cases = [tc for tc in test_cases if tc.__name__ in sys.argv[2] or len(sys.argv) == 2]

if len(test_cases) == 0:
    print("No test cases matched the filter.")
    exit(0)

for test_case in test_cases:
    print("Generating test case:", test_case.__name__)
    fuzz.send_to_wii(sys.argv[1], f"source/test/dsp/tests/{test_case.__name__}.bin", *fuzz.do_tests(test_case, 1000))

print("All done!")