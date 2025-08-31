import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + "/dsp_codegen")

import assembler
import fuzz

def sanity():
    assembler.nop()

test_cases = [
    sanity
]

for test_case in test_cases:
    fuzz.send_to_wii(sys.argv[1], f"source/test/dsp/tests/{test_case.__name__}.bin", *fuzz.do_tests(test_case, 1000))
