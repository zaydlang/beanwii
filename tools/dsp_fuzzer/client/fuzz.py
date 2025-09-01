import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + "/dsp_codegen")

import assembler
import socket
import random
import struct

def generate_pseudo_values(count):
    values = []
    for i in range(count):
        match random.randint(0, 20):
            case 0:
                values.append(0)
            case 1:
                values.append(1)
            case 2:
                values.append(0xfe)
            case 3:
                values.append(0xff)
            case 4:
                values.append(0x100)
            case 4:
                values.append(0x101)
            case 5:
                values.append(0x7f)
            case 6:
                values.append(0x80)
            case 7:
                values.append(0x81)
            case 8:
                values.append(0xfffe)
            case 9:
                values.append(0xffff)
            case 10:
                values.append(0x7f00)
            case 11:
                values.append(0x7fff)
            case 12:
                values.append(0)
            case 13:
                values.append(0)
            case _:
                values.append(random.randint(0, 0xffff))
    
    return values

def load_accumulators():
    labels = []

    accumulator_values = generate_pseudo_values(32)
    # load ACM0 and ACM1 first
    for i in reversed(range(32)):
        if i == 18:
            # assembler.lri(18, 0)
            continue
        labels.append(assembler.get_num_bytes() + 2)
        assembler.lri(i, accumulator_values[i])
    
    return reversed(labels)

def store_accumulators():
    for i in range(32):
        if i == 18:
            continue

        if i == 30:
            assembler.lri(16, 0)
            assembler.lri(17, 0)
            assembler.lri(19, 0)
    
        assembler.lri(18, 0)
        assembler.sr(i, i)

    for i in range(32):
        if i == 18:
            continue

        # assembler.lri(18, 0x69)
        assembler.lri(18, 0)
        assembler.lrs(0, i)
        assembler.lri(18, 0xff)

        assembler.si(0xfc, i)
        # assembler.si(0xfd, i)
        assembler.sr(0x18, 0xfffd)

        label = assembler.get_label()
        assembler.lrs(6, 0xfc)
        assembler.andf(0, 0x8000)
        assembler.jmp_cc(0b1101, label)

def do_tests(instruction_generator, num_tests):
    assembler.reset()
    [instruction_generator() for _ in range(num_tests)]
    tests_bytes = assembler.assemble()[0]
    test_size = assembler.get_num_bytes() // assembler.get_num_instructions()

    assembler.reset()
    # assembler.si(0xfd, 0x42)
    # assembler.si(0xfc, 0x42)
    # assembler.jmp_cc(0b1111, 0)
    accumulator_indices = load_accumulators()
    test_case_index = assembler.get_num_bytes()
    instruction_generator()
    store_accumulators()

    label = assembler.get_label()
    assembler.lrs(6, 0xfc)
    assembler.jmp_cc(0b1111, label)

    bytes_data, length = assembler.assemble()

    test_cases_accumulators = generate_pseudo_values(31 * num_tests)

    return bytes_data, length, test_size, test_case_index, list(accumulator_indices), test_cases_accumulators, tests_bytes, num_tests

def send_to_wii(ip, filename, iram_code_bytes, iram_code_length, test_case_length, test_case_index, accumulator_indices, test_cases_accumulators, test_cases_data, num_tests):
    # print("Original Accumulators:", [hex(x) for x in test_cases_accumulators])
    # print([hex(x) for x in iram_code_bytes])
    port = 1234

    # test_cases_accumulators = [
    #     0xfffe, 0x007f, 0x22b5, 0x0001, 0x0000, 0x0001, 0x3afe, 0x0000,
    #     0xc41b, 0x00fe, 0x7f00, 0x490d, 0x1e03, 0xe1c0, 0x00ff, 0x7f00,
    #     0x00ff, 0x00fe, 0x9834, 0x0100, 0x0100, 0x0080, 0x0000,
    #     0x6baa, 0x5dc9, 0xfffe, 0x00ff, 0xfffe, 0x7fff, 0x9216, 0x007f,
    # ]

    # test_cases_data = [ 0x4d, 0x64 ]

    packet = bytearray()
    packet.extend(struct.pack('>H', 0xBEEF))  # magic
    packet.extend(struct.pack('>H', test_case_length))  # test_case_length
    packet.extend(struct.pack('>H', test_case_index))  # test_case_index
    packet.extend(struct.pack('>H', num_tests))  # num_test_cases
    packet.extend(struct.pack('>H', iram_code_length))  # iram_code_length
    packet.extend(iram_code_bytes)  # iram_code
    for val in test_cases_accumulators:
        packet.extend(struct.pack('>H', val))  # test_cases_accumulators
    for val in accumulator_indices:
        packet.extend(struct.pack('>H', val))  # test_cases_accumulator_indices
    packet.extend(test_cases_data)  # test_cases_data

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((ip, port))
    s.sendall(packet)

    # wait to receive 31 * num_tests * 2 bytes
    expected_bytes = 31 * num_tests * 2
    data = bytearray()
    while len(data) < expected_bytes:
        chunk = s.recv(expected_bytes - len(data))
        if not chunk:
            print("Connection closed prematurely")
            return
        data.extend(chunk)

    results = struct.unpack(f'>{len(data)//2}H', data)
    # print("Result Accumulators:  ", [hex(x) for x in results])

    s.close()

    expected = results

    with open(f"{filename}", "wb+") as f:
        f.write(test_case_length.to_bytes(2, 'little'))
        for i in range(num_tests):
            for j in range(0, test_case_length, 2):
                f.write((test_cases_data[i * test_case_length + j + 1] + (test_cases_data[i * test_case_length + j] << 8)).to_bytes(2, 'little'))

            for j in range(31):
                f.write(expected[i * 31 + j].to_bytes(2, 'little'))
            
            for j in range(31):
                f.write(test_cases_accumulators[i * 31 + j].to_bytes(2, 'little'))