import sys
import test_analyzer

def unsigned_24bit_to_signed(val):
    if val & 0x800000:
        val -= 0x1000000
    return val

print(unsigned_24bit_to_signed(0xffffff))

test_file = test_analyzer.parse_test_file(sys.argv[1])

num_failures = 0

for test_case in test_file.test_cases:
    original_ac0 = test_case.initial_state.ac_full((test_case.instructions[0] >> 8) & 1) & 0xffffffff
    expected_ac0 = test_case.expected_state.ac_full((test_case.instructions[0] >> 8) & 1) & 0xffffffff
    sr = test_case.initial_state.sr()

    if expected_ac0 == original_ac0:
        print(f"    SR: {sr:04x}")

print(f"Total Failures: {num_failures} / {len(test_file.test_cases)}")
