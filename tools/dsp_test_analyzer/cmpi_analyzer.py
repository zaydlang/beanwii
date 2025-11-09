import sys
import test_analyzer

def unsigned_16bit_to_signed(val):
    if val & 0x8000:
        val -= 0x10000
    return val


test_file = test_analyzer.parse_test_file(sys.argv[1])

num_failures = 0

for test_case in test_file.test_cases:
    original_ac = test_case.initial_state.ac_full((test_case.instructions[0] >> 8) & 1) & ((1 << 40) - 1)
    expected_ac = test_case.expected_state.ac_full((test_case.instructions[0] >> 8) & 1) & ((1 << 40) - 1)
    exepcted_zero = (test_case.expected_state.sr() >> 2) & 1
    i = test_case.instructions[1]

    i = unsigned_16bit_to_signed(i)
    i <<= 16
    i &= ((1 << 40) - 1)
    print("go")
    print(hex(i))
    print(hex(original_ac))
    print(hex(test_case.expected_state.sr()))

    if exepcted_zero != (1 if ((i) == expected_ac) else 0):
        num_failures += 1
        print("Failure!")
        print(f"    Original AC: {original_ac:010x}")
        print(f"    Expected Zero Flag: {exepcted_zero}")
        print(f"    Expected AC: {expected_ac:010x}")
        print(f"    Instr Value: {i:010x}")


        # if exepcted_zero:
        #     print("yes: " + hex(expected_ac) + " instr: " + hex(i) + " orig: " + hex(original_ac))
        # else:
        #     print("no:  " + hex(expected_ac) + " instr: " + hex(i) + " orig: " + hex(original_ac))

print(f"Total Failures: {num_failures} / {len(test_file.test_cases)}")
