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

        high_index = 31
        prev_char = ''
        representation = ''.join(line.split('*')[1].strip().split())
        assert len(representation) == 16 or len(representation) == 32

        for i in range(len(representation)):
            char = representation[i]

            if char == ' ':
                continue
            
            if char == '0' or char == '1':
                self.fixed_repr |= (int(char) << (len(representation) - 1 - i))
                continue
                
            if char != prev_char:
                if prev_char != '':
                    self.operands.append(Operand(len(representation) - i, high_index - 1, prev_char))
                high_index = len(representation) - i
                prev_char = char
        
        if prev_char != '':
            self.operands.append(Operand(0, high_index - 1, prev_char))
        
        self.operands.reverse()  # Reverse to have the lowest index first

    def __repr__(self):
        return f'Instruction(opcode={self.opcode}, operands={self.operands})'

def get_instructions(file_name):
    return [Instruction(line) for line in open(file_name, 'r')]