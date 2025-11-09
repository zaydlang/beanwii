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
    prod_hi = test_case.initial_state.prod_hi()
    prod_m1 = test_case.initial_state.prod_m1()
    prod_m2 = test_case.initial_state.prod_m2()
    prod_lo = test_case.initial_state.prod_lo()

    prod = (prod_hi << 32) + (prod_m1 << 16) + (prod_m2 << 16) + (prod_lo)
    
    if prod & 0x10000:
        prod = prod + 0x8000
    else:
        prod = prod + 0x7fff

    prod &= ~0xffff
    asshole = prod
    menezes = asshole >> 40

    expected_ac = test_case.expected_state.ac_full((test_case.instructions[0] >> 8) & 1)
    expected_carry = (test_case.expected_state.sr() >> 0) & 1

    prod &= (1 << 40) - 1
    expected_ac &= (1 << 40) - 1

    actual_carry = 1 if unsigned_24bit_to_signed(prod) > unsigned_24bit_to_signed(expected_ac) else 0
    actual_carry = (not menezes) if prod > expected_ac else menezes
    if expected_carry != actual_carry:
        num_failures += 1
        print("  Failure!")
        print(f"    Prod Hi: {test_case.initial_state.prod_hi():04x}")
        print(f"    Prod M1: {test_case.initial_state.prod_m1():04x}")
        print(f"    Prod M2: {test_case.initial_state.prod_m2():04x}")
        print(f"    Prod Lo: {test_case.initial_state.prod_lo():04x}")
        print(f"    ASSHOLE:    {asshole:010x}")
        print(f"    Prod:    {prod:010x}")
        print(f"    Expected Acc: { test_case.expected_state.ac_full((test_case.instructions[0] >> 8) & 1):010x} (C={expected_carry})")
        print(f"    Expected Carry: {expected_carry}")
        print(f"    Actual Carry: {actual_carry}")

print(f"Total Failures: {num_failures} / {len(test_file.test_cases)}")
