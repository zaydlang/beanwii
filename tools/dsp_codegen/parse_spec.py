class Operand:
    def __init__(self, low_index, high_index, char):
        self.low_index = low_index
        self.high_index = high_index
        self.char = char
    
    def __repr__(self):
        return f'Operand({self.low_index}, {self.high_index}, {self.char})'

class Instruction:
    def __init__(self, line):
        self.opcode = '_'.join(line.split('*')[0].split()).strip()
        self.operands = []
        self.fixed_repr = 0
        self.fixed_mask = 0

        high_index = 31
        prev_char = ''
        representation = ''.join(line.split('*')[1].strip().split())
        assert len(representation) == 16 or len(representation) == 32

        self.size = len(representation)

        ass = self.opcode == 'ABS'

        for i in range(len(representation)):
            char = representation[i]
            
            if char == '0' or char == '1':
                self.fixed_repr |= (int(char) << (len(representation) - 1 - i))
                self.fixed_mask |= (1 << (len(representation) - 1 - i))
            
            if char != prev_char:
                if prev_char != '0' and prev_char != '1' and prev_char != '':
                    self.operands.append(Operand(len(representation) - i, high_index - 1, prev_char))
                high_index = len(representation) - i


            prev_char = char
        
        if prev_char != '' and prev_char != '0' and prev_char != '1':
            self.operands.append(Operand(0, high_index - 1, prev_char))

            if ass:
                print(prev_char)
        
        self.operands.reverse()  # Reverse to have the lowest index first

    def __repr__(self):
        return f'Instruction(opcode={self.opcode}, operands={self.operands})'

class ExtensionInstruction:
    def __init__(self, line):
        # Parse extension instruction like "'MV * xxxx xxxx 0001 ddss"
        parts = line.split('*')
        self.opcode = parts[0].strip().lstrip("'")  # Remove the ' prefix
        
        pattern_parts = parts[1].strip().split()
        # Skip the "xxxx xxxx" main mask, take the extension pattern
        extension_pattern = ''.join(pattern_parts[2:])  # Join remaining parts
        assert len(extension_pattern) == 8, f"Extension pattern must be 8 bits, got {len(extension_pattern)}: {extension_pattern}"
        
        self.operands = []
        self.fixed_repr = 0
        self.fixed_mask = 0
        self.size = 8  # Extension opcodes are always 8 bits
        
        # Parse the 8-bit extension pattern
        high_index = 7
        prev_char = ''
        
        for i in range(8):
            char = extension_pattern[i]
            
            if char == '0' or char == '1':
                self.fixed_repr |= (int(char) << (7 - i))
                self.fixed_mask |= (1 << (7 - i))
            
            if char != prev_char:
                if prev_char != '0' and prev_char != '1' and prev_char != '':
                    self.operands.append(Operand(8 - i, high_index - 1, prev_char))
                high_index = 8 - i
            
            prev_char = char
        
        if prev_char != '' and prev_char != '0' and prev_char != '1':
            self.operands.append(Operand(0, high_index - 1, prev_char))
        
        self.operands.reverse()  # Reverse to have the lowest index first
    
    def __repr__(self):
        return f'ExtensionInstruction(opcode={self.opcode}, operands={self.operands})'

def get_instructions(file_name):
    instructions = []
    extension_instructions = []
    
    for line in open(file_name, 'r'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        
        if line.startswith("'"):
            extension_instructions.append(ExtensionInstruction(line))
        else:
            instructions.append(Instruction(line))
    
    return instructions, extension_instructions