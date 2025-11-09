import sys
import test_analyzer

test_file = test_analyzer.parse_test_file(sys.argv[1])

num_failures = 0

def overflow_from(a, b, sum, bits):
    a   &= (1 << bits) - 1
    b   &= (1 << bits) - 1
    sum &= (1 << bits) - 1

    return ((a ^ sum) & (b ^ sum) & (1 << (bits - 1))) >> (bits - 1)

for test_case in test_file.test_cases:
    prod_hi = test_case.initial_state.prod_hi()
    prod_m1 = test_case.initial_state.prod_m1()
    prod_m2 = test_case.initial_state.prod_m2()
    prod_lo = test_case.initial_state.prod_lo()

    prod = (prod_hi << 32) + (prod_m1 << 16) + (prod_m2 << 16) + (prod_lo)

    initial_acc = test_case.initial_state.ac_full((test_case.instructions[0] >> 8) & 1)
    expected_acc = test_case.expected_state.ac_full((test_case.instructions[0] >> 8) & 1)

    prod_carry = prod >> 40
    prod_overflow = overflow_from(prod_lo | (prod_m1 << 16), (prod_m2 << 16) | (prod_hi << 32), prod, 40)
    # prod_overflow = overflow_from(prod_m1, prod_m2, prod_m1 + prod_m2, 16)
    # prod_overflow = (prod_m1 + prod_m2) >> 16

    prod         &= (1 << 40) - 1
    initial_acc  &= (1 << 40) - 1
    expected_acc &= (1 << 40) - 1

    actual_acc = initial_acc + prod

    expected_carry    = (test_case.expected_state.sr() >> 0) & 1
    expected_overflow = (test_case.expected_state.sr() >> 1) & 1

    actual_carry = (actual_acc >> 40) | prod_carry
    actual_overflow = overflow_from(initial_acc, prod, actual_acc, 40) ^ prod_overflow

    actual_acc &= (1 << 40) - 1

    failure = \
        actual_acc != expected_acc or \
        actual_carry != expected_carry or \
        actual_overflow != expected_overflow
    
    
    if failure:
        print("  Failure!")
        print(f"    Prod Hi: {test_case.initial_state.prod_hi():04x}")
        print(f"    Prod M1: {test_case.initial_state.prod_m1():04x}")
        print(f"    Prod M2: {test_case.initial_state.prod_m2():04x}")
        print(f"    Prod Lo: {test_case.initial_state.prod_lo():04x}")
        print(f"    Prod:    {prod:010x}")
        print(f"    Prod carry: {prod_carry}")
        print(f"    Initial Acc:  {initial_acc:010x}")
        print(f"    Expected Acc: {expected_acc:010x} (C={expected_carry} V={expected_overflow})")
        print(f"    Actual Acc:   {actual_acc:010x} (C={actual_carry} V={actual_overflow})")

        num_failures += 1

print(f"Total Failures: {num_failures} / {len(test_file.test_cases)}")

