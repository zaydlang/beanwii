import struct
from typing import List

class DspTestState:
    def __init__(self):
        self.reg = [0] * 32
    
    def prod_lo(self):
        return self.reg[20]

    def prod_m1(self):
        return self.reg[21]

    def prod_m2(self):
        return self.reg[23]

    def prod_hi(self):
        return self.reg[22] & 0xff

    def prod(self):
        return (self.prod_hi() << 32) + (self.prod_m2() << 16) + (self.prod_m1() << 16) + self.prod_lo()
    
    def ac_lo(self, index):
        return self.reg[28 + index]
    
    def ac_md(self, index):
        return self.reg[30 + index]
    
    def ac_hi(self, index):
        return self.reg[16 + index] & 0xff

    def ac_full(self, index):
        return (self.ac_hi(index) << 32) | (self.ac_md(index) << 16) | self.ac_lo(index)

    def ax_hi(self, index):
        return self.reg[26 + index]

    def ax_lo(self, index):
        return self.reg[24 + index]

    def sr(self):
        return self.reg[19]

class DspTestCase:
    def __init__(self, instructions, initial_state, expected_state):
        self.instructions = instructions
        self.initial_state = initial_state
        self.expected_state = expected_state

class DspTestFile:
    def __init__(self):
        self.instruction_length = 0
        self.test_cases = []

def parse_test_file(filepath: str) -> DspTestFile:
    test_file = DspTestFile()
    
    with open(filepath, 'rb') as f:
        file_data = f.read()
    
    offset = 0
    
    # Read instruction length (u16)
    test_file.instruction_length = struct.unpack('<H', file_data[offset:offset + 2])[0]
    offset += 2
    
    # Parse test cases
    while offset + test_file.instruction_length + (31 * 2 * 2) <= len(file_data):
        test_case = DspTestCase([], DspTestState(), DspTestState())
        
        # Read instructions
        instructions_bytes = file_data[offset:offset + test_file.instruction_length]
        test_case.instructions = list(struct.unpack(f'<{test_file.instruction_length // 2}H', instructions_bytes))
        offset += test_file.instruction_length
        
        # Read expected state (31 u16 values)
        for i in range(32):
            if i == 18:
                test_case.expected_state.reg[i] = 0
                continue

            test_case.expected_state.reg[i] = struct.unpack('<H', file_data[offset:offset + 2])[0]
            offset += 2
        
        # Read initial state (31 u16 values)  
        for i in range(32):
            if i == 18:
                test_case.expected_state.reg[i] = 0
                continue

            test_case.initial_state.reg[i] = struct.unpack('<H', file_data[offset:offset + 2])[0]
            offset += 2
        
        test_file.test_cases.append(test_case)
    
    return test_file