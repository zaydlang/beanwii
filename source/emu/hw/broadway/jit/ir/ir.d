module emu.hw.broadway.jit.ir.ir;

import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.broadway.jit.ir.types;
import std.sumtype;
import util.log;
import util.number;

alias IRInstruction = SumType!(
    IRInstructionGetReg,
    IRInstructionSetRegVar,
    IRInstructionSetRegImm,
    IRInstructionBinaryDataOpImm,
    IRInstructionBinaryDataOpVar,
    IRInstructionUnaryDataOp,
    IRInstructionSetFlags
);

struct IR {
    enum MAX_IR_INSTRUCTIONS = 0x10000;
    enum MAX_IR_VARIABLES    = 0x1000;

    IRInstruction* instructions;
    size_t current_instruction_index;

    // keeps track of a variables lifetime. this corresponds to an IR instruction. when this IR instruction
    // is executed, the variable is deleted (in other words, it gets unbound from the host register)
    size_t[MAX_IR_VARIABLES] variable_lifetimes;

    private void emit(I)(I ir_opcode) {
        instructions[current_instruction_index++] = ir_opcode;
    }

    void setup() {
        // yes this looks stupid but IRInstruction is a sumtype which disables the default constructor
        // so we have to do this silly workaround

        instructions = cast(IRInstruction*) new ubyte[IRInstruction.sizeof * MAX_IR_INSTRUCTIONS];
    }

    void reset() {
        current_variable_id = 0;
        current_instruction_index = 0;
    }

    size_t length() {
        return current_instruction_index;
    }

    int current_variable_id;
    int generate_new_variable_id() {
        if (current_variable_id >= MAX_IR_VARIABLES) {
            error_ir("Tried to create too many IR variables.");
        }

        return current_variable_id++;
    }
    
    IRVariable generate_new_variable() {
        return IRVariable(&this, this.generate_new_variable_id());
    }

    IRVariable get_reg(GuestReg reg) {
        IRVariable variable = generate_new_variable();
        emit(IRInstructionGetReg(variable, reg));

        return variable;
    }

    void set_reg(GuestReg reg, IRVariable variable) {
        variable.update_lifetime();
        emit(IRInstructionSetRegVar(reg, variable));
    }

    void set_reg(GuestReg reg, u32 imm) {
        emit(IRInstructionSetRegImm(reg, imm));
    }

    void set_flags(int flags, IRVariable variable) {
        emit(IRInstructionSetFlags(variable, flags));
    }

    void pretty_print() {
        for (int i = 0; i < this.length(); i++) {
            pretty_print_instruction(instructions[i]);
        }
    }

    void update_lifetime(int variable_id) {
        variable_lifetimes[variable_id] = current_instruction_index;
    }

    size_t get_lifetime_end(int variable_id) {
        return variable_lifetimes[variable_id];
    }

    void pretty_print_instruction(IRInstruction instruction) {
        instruction.match!(
            (IRInstructionGetReg i) {
                log_ir("ld  v%d, %s", i.dest.get_id(), i.src.to_string());
            },

            (IRInstructionSetRegVar i) {
                log_ir("st  v%d, %s", i.src.get_id(), i.dest.to_string());
            },

            (IRInstructionSetRegImm i) {
                log_ir("st  #0x%x, %s", i.imm, i.dest.to_string());
            },

            (IRInstructionBinaryDataOpImm i) {
                log_ir("%s v%d, v%d, %d", i.op.to_string(), i.dest.get_id(), i.src1.get_id(), i.src2);
            },

            (IRInstructionBinaryDataOpVar i) {
                log_ir("%s v%d, v%d, v%d", i.op.to_string(), i.dest.get_id(), i.src1.get_id(), i.src2.get_id());
            },

            (IRInstructionUnaryDataOp i) {
                log_ir("%s v%d, v%d", i.op.to_string(), i.dest.get_id(), i.src.get_id());
            },

            (IRInstructionSetFlags i) {
                log_ir("setf v%d, %d", i.src.get_id(), i.flags);
            }
        );
    }
}

struct IRVariable {
    // Note that these are static single assignment variables, which means that
    // they can only be assigned to once. Any attempt to mutate an IRVariable
    // after it has been assigned to will result in a new variable being created
    // and returned. 

    private int variable_id;
    private IR* ir;

    @disable this();

    this(IR* ir, int variable_id) {
        this.variable_id = variable_id;
        this.ir          = ir;
    }

    IRVariable opBinary(string s)(IRVariable other) {
        IRVariable dest = ir.generate_new_variable();

        IRBinaryDataOp op = get_binary_data_op!s;

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(op, dest, this, other));

        return dest;
    }

    IRVariable opBinary(string s)(int other) {
        IRVariable dest = ir.generate_new_variable();

        IRBinaryDataOp op = get_binary_data_op!s;

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpImm(op, dest, this, other));

        return dest;
    }

    // TODO: figure out how to make this work
    // @disable IRVariable opBinaryRight(string s)(IRVariable other);
    // @disable IRVariable opBinaryRight(string s)(int other);
    
    // IRVariable opBinaryRight(string s)(IRVariable other) {
    //     return other.opBinary!s(this);
    // }

    // IRVariable opBinaryRight(string s)(int other) {
    //     return this.opBinary!s(other);
    // }

    // void opOpAssign(string s)(IRVariable other) {

    // }

    // void opOpAssign(string s)(int other) {
    //     this.variable_id = ir.generate_new_variable_id();
    //     ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, this, rhs));
    // }
    
    void opAssign(IRVariable rhs) {
        this.variable_id = ir.generate_new_variable_id();

        this.update_lifetime();
        rhs.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, this, rhs));
    }

    IRVariable opUnary(string s)() {
        IRVariable dest = ir.generate_new_variable();

        IRUnaryDataOp op = get_unary_data_op!s;

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(op, dest, this));

        return dest;
    }

    void update_lifetime() {
        ir.update_lifetime(this.variable_id);
    }

    size_t get_lifetime_end() {
        return ir.get_lifetime_end(this.variable_id);
    }

    IRBinaryDataOp get_binary_data_op(string s)() {
        final switch (s) {
            case "+":  return IRBinaryDataOp.ADD;
            case "-":  return IRBinaryDataOp.SUB;
            case "<<": return IRBinaryDataOp.LSL;
            case "|":  return IRBinaryDataOp.ORR;
            case "&":  return IRBinaryDataOp.AND;
            case "^":  return IRBinaryDataOp.XOR;
        }
    }

    IRUnaryDataOp get_unary_data_op(string s)() {
        final switch (s) {
            case "-": return IRUnaryDataOp.NEG;
            case "~": return IRUnaryDataOp.NOT;
        }
    }

    int get_id() {
        return variable_id;
    }
}

struct IRConstant {
    int value;
}

struct IRGuestReg {
    GuestReg guest_reg;
}

struct IRInstructionBinaryDataOpImm {
    IRBinaryDataOp op;

    IRVariable dest;
    IRVariable src1;
    uint src2;
}

struct IRInstructionBinaryDataOpVar {
    IRBinaryDataOp op;

    IRVariable dest;
    IRVariable src1;
    IRVariable src2;
}

struct IRInstructionUnaryDataOp {
    IRUnaryDataOp op;

    IRVariable dest;
    IRVariable src;
}

struct IRInstructionGetReg {
    IRVariable dest;
    GuestReg src;
}

struct IRInstructionSetRegVar {
    GuestReg dest;
    IRVariable src;
}

struct IRInstructionSetRegImm {
    GuestReg dest;
    u32 imm;
}

struct IRInstructionSetFlags {
    IRVariable src;
    int flags;
}