import parse_spec
import sys

class Table:
    def __init__(self, size, mask):
        self.size  = size
        self.table = [[] for _ in range(size)]
        self.mask  = mask

    def __getitem__(self, key):
        return self.table[key]

    def __setitem__(self, key, item):
        self.table[key] = item
      
    def __repr__(self):
        return f'Table(size={self.size}, mask={self.mask:x}, table={self.table})'
    
instructions, extension_instructions = parse_spec.get_instructions('tools/dsp_codegen/spec')

def check_for_overlapping_encodings(instructions):
    """Check if any two instructions have overlapping encodings and error out if found."""
    for i, inst1 in enumerate(instructions):
        for j, inst2 in enumerate(instructions[i+1:], i+1):
            # Two instructions overlap if they have the same size and their fixed bits conflict
            if inst1.size == inst2.size:
                # Check if the fixed bits of both instructions can coexist
                # They overlap if for any bit position, both have fixed values that differ
                common_fixed_bits = inst1.fixed_mask & inst2.fixed_mask
                if common_fixed_bits != 0:
                    # Check if the fixed representations differ in the common fixed bit positions
                    if (inst1.fixed_repr & common_fixed_bits) != (inst2.fixed_repr & common_fixed_bits):
                        continue  # No overlap - they have different fixed values
                    else:
                        # They have the same fixed values in all common positions - this is an overlap!
                        print(f"ERROR: Instructions '{inst1.opcode}' and '{inst2.opcode}' have overlapping encodings!")
                        print(f"  {inst1.opcode}: fixed_mask=0x{inst1.fixed_mask:0{inst1.size//4}x}, fixed_repr=0x{inst1.fixed_repr:0{inst1.size//4}x}")
                        print(f"  {inst2.opcode}: fixed_mask=0x{inst2.fixed_mask:0{inst2.size//4}x}, fixed_repr=0x{inst2.fixed_repr:0{inst2.size//4}x}")
                        print(f"  Common fixed bits: 0x{common_fixed_bits:0{inst1.size//4}x}")
                        sys.exit(1)

check_for_overlapping_encodings(instructions)

def pext(value, mask):
    result = 0

    j = 0
    for i in range(mask.bit_length()):
        if (mask & (1 << i)) != 0:
            if (value & (1 << i)) != 0:
                result |= (1 << j)
            j += 1

    return result

def popcount(value):
    count = 0
    while value:
        count += value & 1
        value >>= 1
    return count

def generate_table_for(instructions, bits_looked_at_so_far = 0):
    if len(instructions) == 1:
        return instructions[0]

    discrimination_mask = 0xffff_ffff_ffff_ffff
    discrimination_mask &= ~bits_looked_at_so_far

    for instruction in instructions:
        fixed_mask = instruction.fixed_mask
        if instruction.size != 16:
            fixed_mask >>= 16

        discrimination_mask &= fixed_mask
    
    bitsize = popcount(discrimination_mask)

    if bitsize == 0:
        return []

    table = Table(1 << bitsize, discrimination_mask)
    tmp_table = [[] for _ in range(1 << bitsize)]

    for instruction in instructions:
        fixed_repr = instruction.fixed_repr
        if instruction.size != 16:
            fixed_repr >>= 16

        index = pext(fixed_repr, discrimination_mask)
        tmp_table[index].append(instruction)
    
    for i in range(1 << bitsize):
        entry = tmp_table[i]

        if len(entry) > 0:
            table[i] = generate_table_for(entry, bits_looked_at_so_far | discrimination_mask)
        else:
            table[i] = None

    return table


def fresh_table_function_name():
    fresh_table_function_name_counter = 0
    while True:
        fresh_table_function_name_counter += 1
        yield f'generated_table_{fresh_table_function_name_counter}'
fresh_table_function_name = fresh_table_function_name()

def write_out_instruction_structs(f, instructions, extension_instructions):
    f.write(
f'''struct DspInstruction {{
    DspOpcode opcode;
    size_t size;

    union {{
        {'\n\t\t'.join([f"{i.opcode.upper()} {i.opcode.lower()};" for i in reversed(instructions)])}
    }}
}}\n\n''')
    
    f.write(
f'''struct ExtensionInstruction {{
    ExtensionOpcode opcode;

    union {{
        {'\n\t\t'.join([f"EXT_{i.opcode.upper()} {i.opcode.lower()};" for i in reversed(extension_instructions)])}
    }}
}}\n\n''')
    
    f.write(
f'''struct DecodedInstruction {{
    DspInstruction main;
    bool has_extension;
    ExtensionInstruction extension;
}}\n\n''')
    
    f.write(
f'''enum DspOpcode {{
    {'\n\t'.join([f"{i.opcode.upper()}," for i in instructions])}
}}\n\n''') 
    
    f.write(
f'''enum ExtensionOpcode {{
    {'\n\t'.join([f"EXT_{i.opcode.upper()}," for i in extension_instructions])}
}}\n\n''')

    for i in instructions:
        f.write(
f'''struct {i.opcode.upper()} {{
    {'\n\t'.join([f'u16 {op.char.lower()};' for op in reversed(i.operands)])}
}}\n\n''')
        
    for i in extension_instructions:
        f.write(
f'''struct EXT_{i.opcode.upper()} {{
    {'\n\t'.join([f'u16 {op.char.lower()};' for op in reversed(i.operands)])}
}}\n\n''')

def get_operand_decoding_string(operand, instruction_size):
    if instruction_size == 16:
        if operand.low_index == operand.high_index:
            return f'instruction.bit({operand.low_index})'
        else:
            return f'instruction.bits({operand.low_index}, {operand.high_index})'
    else:
        if operand.low_index == operand.high_index:
            if operand.low_index < 16:
                return f'next_instruction.bit({operand.low_index})'
            else:
                return f'instruction.bit({operand.low_index - 16})'
        elif operand.low_index == 0 and operand.high_index == 15:
            return 'next_instruction'
        else:
            assert operand.low_index >= 16 and operand.high_index >= 16, f'Invalid operand indices: {operand.low_index}, {operand.high_index}'
            return f'instruction.bits({operand.low_index - 16}, {operand.high_index - 16})'

def get_extension_operand_decoding_string(operand):
    # Extension operands are always 8-bit from the lower bits of instruction
    if operand.low_index == operand.high_index:
        return f'cast(u16) (instruction & 0xFF).bit({operand.low_index})'
    else:
        return f'cast(u16) (instruction & 0xFF).bits({operand.low_index}, {operand.high_index})'

def generate_extension_table_for(extension_instructions):
    # Create a simple lookup table for 8-bit extension opcodes
    table = [None] * 256
    
    for ext_inst in extension_instructions:
        # Calculate all possible values that match this instruction
        for i in range(256):
            if (i & ext_inst.fixed_mask) == ext_inst.fixed_repr:
                if table[i] is not None:
                    print(f"WARNING: Extension opcode conflict at 0x{i:02x} between {table[i].opcode} and {ext_inst.opcode}")
                table[i] = ext_inst
    
    return table

def write_extension_decoder(f, extension_instructions):
    f.write('ExtensionInstruction decode_extension(u16 instruction) {\n')
    f.write('\tu8 ext_opcode = instruction & 0xFF;\n')
    f.write('\tswitch (ext_opcode) {\n')
    
    table = generate_extension_table_for(extension_instructions)
    
    for i in range(256):
        if table[i] is not None:
            ext_inst = table[i]
            operand_strings = [get_extension_operand_decoding_string(op) for op in reversed(ext_inst.operands)]
            f.write(f'\t\tcase 0x{i:02x}: return ExtensionInstruction(ExtensionOpcode.EXT_{ext_inst.opcode.upper()}, {ext_inst.opcode.lower()} : EXT_{ext_inst.opcode.upper()}({", ".join(operand_strings)}));\n')
        else:
            # Generate NOP for unmatched cases
            f.write(f'\t\tcase 0x{i:02x}: return ExtensionInstruction(ExtensionOpcode.EXT_NOP, nop : EXT_NOP());\n')
    
    f.write('\t\tdefault:\n')
    f.write('\t\t\tlog_dsp("Unknown extension opcode: 0x%02x", ext_opcode);\n')
    f.write('\t\t\treturn ExtensionInstruction(ExtensionOpcode.EXT_NOP, nop : EXT_NOP());\n')
    f.write('\t}\n')
    f.write('}\n\n')

def can_instruction_have_extension(instruction):
    # Check if instruction can have extension based on first nybble rules
    # First nybble 0, 1, 2 cannot be extended
    # First nybble 4+ can be extended with 8-bit extension
    # First nybble 3 can be extended with 7-bit extension (not implemented yet)
    first_nybble = (instruction >> 12) & 0xF
    return first_nybble >= 4

def write_main_decoder_function(f):
    f.write('DecodedInstruction decode_instruction_with_extension(u16 instruction, u16 next_instruction) {\n')
    f.write('\tDspInstruction main_inst = decode_instruction(instruction, next_instruction);\n')
    f.write('\tbool has_ext = false;\n')
    f.write('\tExtensionInstruction ext_inst;\n')
    f.write('\n')
    f.write('\t// Check if main instruction can have extension (first nybble >= 4)\n')
    f.write('\tif ((instruction >> 12) >= 4) {\n')
    f.write('\t\t// Extension is always present if instruction can have one\n')
    f.write('\t\text_inst = decode_extension(instruction);\n')
    f.write('\t\thas_ext = true;\n')
    f.write('\t}\n')
    f.write('\n')
    f.write('\treturn DecodedInstruction(main_inst, has_ext, ext_inst);\n')
    f.write('}\n\n')

def write_out_table(f, function_name, table):
    children = []

    f.write(f'DspInstruction {function_name}(u16 instruction, u16 next_instruction) {{\n')
    
    f.write(f'\tu16 index = 0;\n');
    j = 0
    for i in range(table.mask.bit_length()):
        if (table.mask & (1 << i)) != 0:
            f.write(f'\tindex |= ((instruction & {1 << i:#x}) >> {i}) << {j};\n')
            j += 1
                                            
    f.write(f'\n\tswitch (index) {{\n')
    for case_number in range(table.size):
        if isinstance(table[case_number], parse_spec.Instruction):
            instruction = table[case_number]
            f.write(f'\t\tcase {case_number}: return DspInstruction(DspOpcode.{instruction.opcode.upper()}, {instruction.size}, {instruction.opcode.lower()} : {instruction.opcode.upper()}({", ".join([get_operand_decoding_string(op, instruction.size) for op in reversed(instruction.operands)])}));\n')
        elif table[case_number] is None:
            pass
        else:
            child_function_name = next(fresh_table_function_name)
            f.write(f'\t\tcase {case_number}: return {child_function_name}(instruction, next_instruction);\n')
            children.append((child_function_name, table[case_number]))

    f.write('\t\tdefault:\n')
    f.write('\t\t\tlog_dsp("Unknown instruction opcode: 0x%04x (index: %d)", instruction, index);\n')
    f.write('\t\t\treturn DspInstruction(DspOpcode.NOP, 16, nop : NOP());\n')
    f.write('\t}\n')
    f.write('}\n\n')

    for child in children:
        write_out_table(f, child[0], child[1])

table = generate_table_for(instructions)
with open(sys.argv[1], 'w+') as f:
    f.write('// This file is automatically generated by generate_decoder.py.\n// Do not edit it manually.\n\n')

    f.write('module emu.hw.dsp.jit.emission.decoder;\n\n')
    f.write('import util.bitop;\n')
    f.write('import util.number;\n')
    f.write('import util.log;\n')

    f.write('\n')

    write_out_instruction_structs(f, instructions, extension_instructions)
    write_extension_decoder(f, extension_instructions)
    write_out_table(f, 'decode_instruction', table)
    write_main_decoder_function(f)