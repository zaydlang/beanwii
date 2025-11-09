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
    ax_hi = test_case.expected_state.ax_hi((test_case.instructions[0] >> 8) & 1)
    ax_lo = test_case.expected_state.ax_lo((test_case.instructions[0] >> 8) & 1)

    # sign extend the 8 bit values to 64
    if ax_hi & 0x8000:
        ax_hi |= 0xffffffffffff0000
    if ax_lo & 0x8000:
        ax_lo |= 0xffffffffffff0000
    
    product = ax_hi * ax_lo
    if not test_case.initial_state.sr() & 0x2000:
        product *= 2
    
    original_prod = test_case.initial_state.prod()
    expected_prod = (original_prod + product) & 0xffffffffff
    actual_prod = test_case.expected_state.ac_full(0)

    expected_carry = (test_case.expected_state.sr() >> 0) & 1
    actual_carry = (actual_prod >> 40) & 1

    if actual_prod != expected_prod or actual_carry != expected_carry:
        num_failures += 1
        print("  Failure!")
        print(f"    Original Prod: {original_prod:010x}")
        print(f"    Ax Hi: {test_case.expected_state.ax_hi((test_case.instructions[0] >> 8) & 1):02x}")
        print(f"    Ax Lo: {test_case.expected_state.ax_lo((test_case.instructions[0] >> 8) & 1):02x}")
        print(f"    Product: {product:010x}")
        print(f"    Expected Prod:   {actual_prod:010x}")
        print(f"    Actual Prod: {expected_prod:010x}")
        print(f"    Expected Carry: {expected_carry}")
        print(f"    Actual Carry: {actual_carry}")


    # if exepcted_s32:
        # print("yes: " + hex(expected_ac) + " md: " + hex(expected_ac_md))
    # else:
        # print("no:  " + hex(expected_ac) + " md: " + hex(expected_ac_md))

print(f"Total Failures: {num_failures} / {len(test_file.test_cases)}")
