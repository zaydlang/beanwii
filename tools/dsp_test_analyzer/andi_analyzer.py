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
    expected_ac = test_case.expected_state.ac_full((test_case.instructions[0] >> 8) & 1)
    expected_ac_md = test_case.expected_state.ac_md((test_case.instructions[0] >> 8) & 1)
    original_s32 = (test_case.initial_state.sr() >> 4) & 1
    exepcted_s32 = (test_case.expected_state.sr() >> 4) & 1

    actual_s32 = (expected_ac >> 31) != 0 and (expected_ac >> 31) != 0x1ff

    if actual_s32 != exepcted_s32:
        num_failures += 1
        print("  Failure!")
        print(f"    Original S32: {original_s32}")
        print(f"    Expected S32: {exepcted_s32}")
        print(f"    Actual S32:   {actual_s32}")
        print(f"    Expected Acc: {expected_ac:010x}")
        print(f"    Expected Acc MD: {expected_ac_md:010x}")
        print(f"    shift by 31: {expected_ac >> 31:010x}")


    # if exepcted_s32:
        # print("yes: " + hex(expected_ac) + " md: " + hex(expected_ac_md))
    # else:
        # print("no:  " + hex(expected_ac) + " md: " + hex(expected_ac_md))

print(f"Total Failures: {num_failures} / {len(test_file.test_cases)}")
