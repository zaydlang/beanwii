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
    condition = (test_case.instructions[0] >> 0) & 0xf
    original_ac0 = test_case.initial_state.ac_full((test_case.instructions[0] >> 8) & 1) & 0xffffffff
    expected_ac0 = test_case.expected_state.ac_full((test_case.instructions[0] >> 8) & 1) & 0xffffffff
    sr = test_case.initial_state.sr()
    
    o = (sr >> 1) & 1
    s = (sr >> 3) & 1
    z = (sr >> 2) & 1

    if condition == 3:
        print(f" result: {1 if original_ac0 == expected_ac0 else 0}     o: {o} s: {s} z: {z}")

print(f"Total Failures: {num_failures} / {len(test_file.test_cases)}")
