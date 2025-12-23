module test.broadway.achurch.pretty_printer;

import consolecolors;
import std.format;
import std.stdio;
import util.number;

struct FailureRecord {
    u32 instruction_word;
    u32 instruction_address;
    u32 aux_data0;  // Result/Data0
    u32 aux_data1;  // Data1
    u32 aux_data2;  // CR/FPSCR
    u32 aux_data3;  // XER (ALU only)
    u32 unused0;
    u32 unused1;
}

static assert(FailureRecord.sizeof == 32);

string get_opcode_name(u32 instr) {
    u32 primary = (instr >> 26) & 0x3F;
    u32 extended = (instr >> 1) & 0x3FF;
    
    switch (primary) {
        case 3: return "twi";
        case 7: return "mulli";
        case 8: return "subfic";
        case 10: return "cmpli";
        case 11: return "cmpi";
        case 12: return "addic";
        case 13: return "addic.";
        case 14: return "addi";
        case 15: return "addis";
        case 16: return "bc";
        case 17: return "sc";
        case 18: return "b";
        case 19:
            switch (extended) {
                case 16: return "bclr";
                case 528: return "bcctr";
                default: return "branch_ext";
            }
        case 20: return "rlwimi";
        case 21: return "rlwinm";
        case 23: return "rlwnm";
        case 24: return "ori";
        case 25: return "oris";
        case 26: return "xori";
        case 27: return "xoris";
        case 28: return "andi.";
        case 29: return "andis.";
        case 31:
            switch (extended) {
                case 266: return "add";
                case 10: return "addc";
                case 138: return "adde";
                case 234: return "addme";
                case 202: return "addze";
                case 491: return "divw";
                case 459: return "divwu";
                case 75: return "mulhw";
                case 11: return "mulhwu";
                case 235: return "mullw";
                case 104: return "neg";
                case 40: return "subf";
                case 8: return "subfc";
                case 136: return "subfe";
                case 232: return "subfme";
                case 200: return "subfze";
                case 28: return "and";
                case 60: return "andc";
                case 954: return "extsb";
                case 922: return "extsh";
                case 122: return "nand";
                case 124: return "nor";
                case 444: return "or";
                case 412: return "orc";
                case 316: return "xor";
                default: return "fixed_ext";
            }
        case 59: return "fps";
        case 63: return "fpd";
        default: return "unknown";
    }
}

string decode_cr_field(u32 cr, int field) {
    u32 bits = (cr >> (28 - field * 4)) & 0xF;
    switch (bits & 0xE) {
        case 0x8: return "LT";
        case 0x4: return "GT"; 
        case 0x2: return "EQ";
        default: return "??";
    }
}

void print_fpscr_flags(u32 fpscr) {
    cwritef("FPSCR: <lcyan>0x%08X</lcyan> [", fpscr);
    if (fpscr & (1 << 31)) cwritef("<lred>FX</lred> ");
    if (fpscr & (1 << 30)) cwritef("<lred>FEX</lred> ");
    if (fpscr & (1 << 29)) cwritef("<lred>VX</lred> ");
    if (fpscr & (1 << 28)) cwritef("<lred>OX</lred> ");
    if (fpscr & (1 << 27)) cwritef("<lred>UX</lred> ");
    if (fpscr & (1 << 26)) cwritef("<lred>ZX</lred> ");
    if (fpscr & (1 << 25)) cwritef("<lred>XX</lred> ");
    if (fpscr & (1 << 24)) cwritef("<lred>VXSNAN</lred> ");
    if (fpscr & (1 << 23)) cwritef("<lred>VXISI</lred> ");
    if (fpscr & (1 << 22)) cwritef("<lred>VXIDI</lred> ");
    if (fpscr & (1 << 21)) cwritef("<lred>VXZDZ</lred> ");
    if (fpscr & (1 << 20)) cwritef("<lred>VXIMZ</lred> ");
    if (fpscr & (1 << 19)) cwritef("<lred>VXVC</lred> ");
    if (fpscr & (1 << 18)) cwritef("<lyellow>FR</lyellow> ");
    if (fpscr & (1 << 17)) cwritef("<lyellow>FI</lyellow> ");
    if (fpscr & (1 << 16)) cwritef("<lcyan>FPRF</lcyan> ");
    cwriteln("]");
}

void print_xer_flags(u32 xer) {
    cwritef("XER: <lcyan>0x%08X</lcyan> [", xer);
    if (xer & (1 << 31)) cwritef("<lred>SO</lred> ");
    if (xer & (1 << 30)) cwritef("<lred>OV</lred> ");
    if (xer & (1 << 29)) cwritef("<lred>CA</lred> ");
    cwriteln("]");
}

void print_failure_record(int record_num, FailureRecord record) {
    cwriteln("=======================================================================");
    cwritefln("                      <lred>FAILURE RECORD #%d</lred>", record_num);
    cwriteln("=======================================================================");
    
    string opcode_name = get_opcode_name(record.instruction_word);
    cwritefln("Instruction: <lcyan>0x%08X</lcyan> (<lgreen>%s</lgreen>) at address <lyellow>0x%08X</lyellow>", 
              record.instruction_word, opcode_name, record.instruction_address);
    
    u32 rt = (record.instruction_word >> 21) & 0x1F;
    u32 ra = (record.instruction_word >> 16) & 0x1F;
    u32 rb = (record.instruction_word >> 11) & 0x1F;
    cwritefln("  Fields: RT/RS=%d RA=%d RB/SH=%d", rt, ra, rb);
    
    cwriteln("\nAuxiliary Data:");
    cwritefln("  Word 2 (Result/Data0): <lcyan>0x%08X</lcyan> (%d)", record.aux_data0, cast(int)record.aux_data0);
    cwritefln("  Word 3 (Data1):       <lcyan>0x%08X</lcyan> (%d)", record.aux_data1, cast(int)record.aux_data1);
    
    u64 double_val = (cast(u64)record.aux_data0 << 32) | record.aux_data1;
    cwritefln("  Words 2-3 (as double): <lgreen>%f</lgreen> (0x%016X)", 
              *(cast(double*)&double_val), double_val);
    
    if (opcode_name[0] == 'f') {
        cwriteln();
        print_fpscr_flags(record.aux_data2);
        
        if (record.aux_data3 != 0) {
            cwritefln("  Word 5 (Extra): <lcyan>0x%08X</lcyan>", record.aux_data3);
        }
    } else {
        cwritef("\n  CR: <lcyan>0x%08X</lcyan> [CR0=%s", record.aux_data2, decode_cr_field(record.aux_data2, 0));
        for (int i = 1; i < 8; i++) {
            cwritef(" CR%d=%s", i, decode_cr_field(record.aux_data2, i));
        }
        cwriteln("]");
        
        if (record.aux_data3 != 0) {
            cwritef("  ");
            print_xer_flags(record.aux_data3);
        }
    }
    
    cwriteln();
}

void print_achurch_failures(u32 failure_count, FailureRecord[] records) {
    cwriteln("ACHURCH PowerPC Test Suite - Failure Report");
    cwriteln("=======================================================================");
    cwritefln("Total failures: <lred>%u</lred>\n", failure_count);
    
    if (failure_count == 0) {
        cwriteln("<lgreen>✓ All tests passed!</lgreen>");
        return;
    }
    
    for (uint i = 0; i < failure_count && i < records.length; i++) {
        print_failure_record(cast(int)(i + 1), records[i]);
    }
}