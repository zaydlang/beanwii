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
    IRInstructionSetFlags,
    IRInstructionSetVarImm,
    IRInstructionRead,
    IRInstructionWrite,
    IRInstructionConditionalBranch,
    IRInstructionGetHostCarry,
    IRInstructionGetHostOverflow,
);

struct IR {
    enum MAX_IR_INSTRUCTIONS = 0x10000;
    enum MAX_IR_VARIABLES    = 0x1000;
    enum MAX_IR_LABELS       = 0x1000;

    IRInstruction* instructions;
    size_t current_instruction_index;

    IRLabel* labels;
    size_t current_label_index;

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
        labels       = cast(IRLabel*)       new ubyte[IRLabel.sizeof * MAX_IR_LABELS];
    }

    void reset() {
        current_variable_id = 0;
        current_instruction_index = 0;
        current_label_index = 0;
    }

    size_t num_instructions() {
        return current_instruction_index;
    }

    size_t num_labels() {
        return current_label_index;
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

    IRVariable constant(int constant) {
        IRVariable dest = generate_new_variable();
        emit(IRInstructionSetVarImm(dest, constant));
        
        return dest;
    }

    void read_u8(IRVariable address, IRVariable value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value, address, u8.sizeof));
    }

    void read_u16(IRVariable address, IRVariable value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value, address, u16.sizeof));
    }

    void read_u32(IRVariable address, IRVariable value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value, address, u32.sizeof));
    }

    void write_u8(IRVariable address, IRVariable value) {
        emit(IRInstructionWrite(value, address, u8.sizeof));
        address.update_lifetime();
    }

    void write_u16(IRVariable address, IRVariable value) {
        emit(IRInstructionWrite(value, address, u16.sizeof));
        address.update_lifetime();
    }

    void write_u32(IRVariable address, IRVariable value) {
        emit(IRInstructionWrite(value, address, u32.sizeof));
        address.update_lifetime();
    }

    IRVariable get_reg(GuestReg reg) {
        IRVariable variable = generate_new_variable();
        emit(IRInstructionGetReg(variable, reg));

        if (reg == GuestReg.PC) {
            variable = variable - 4;
        }

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

    void _if(IRVariable cond, void delegate() true_case) {
        IRLabel after_true_label;
        this.emit(IRInstructionConditionalBranch(cond, &after_true_label));

        true_case();
        this.bind_label(after_true_label);
    }

    void bind_label(IRLabel label) {
        label.instruction_index = cast(int) this.current_instruction_index;
        this.labels[this.current_label_index++] = label;
    }

    IRVariable get_carry() {
        IRVariable carry = generate_new_variable();
        this.emit(IRInstructionGetHostCarry(carry));
        return carry;
    }

    IRVariable get_overflow() {
        IRVariable overflow = generate_new_variable();
        this.emit(IRInstructionGetHostOverflow(overflow));
        return overflow;
    }

    void pretty_print() {
        for (int i = 0; i < this.num_instructions(); i++) {
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
            },

            (IRInstructionSetVarImm i) {
                log_ir("ld   v%d, %x", i.dest.get_id(), i.imm);
            },

            (IRInstructionRead i) {
                string mnemonic;
                final switch (i.size) {
                    case 4: mnemonic = "ldw"; break;
                    case 2: mnemonic = "ldh"; break;
                    case 1: mnemonic = "ldb"; break;
                }
                
                log_ir("%s  r%d, [v%d]", mnemonic, i.dest.get_id(), i.address.get_id());
            },

            (IRInstructionWrite i) {
                string mnemonic;
                final switch (i.size) {
                    case 4: mnemonic = "stw"; break;
                    case 2: mnemonic = "sth"; break;
                    case 1: mnemonic = "stb"; break;
                }
                
                log_ir("%s  r%d, [v%d]", mnemonic, i.dest.get_id(), i.address.get_id());
            },

            (IRInstructionConditionalBranch i) {
                log_ir("bne  v%d, #%d", i.cond.get_id(), i.after_true_label.instruction_index);
            },

            (IRInstructionGetHostCarry i) {
                log_ir("getc v%d", i.dest.get_id());
            },

            (IRInstructionGetHostOverflow i) {
                log_ir("getv v%d", i.dest.get_id());
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

    public IRVariable greater(IRVariable other) {
        IRVariable dest = ir.generate_new_variable();

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.GT, dest, this, other));

        return dest;
    }

    public IRVariable lesser(IRVariable other) {
        IRVariable dest = ir.generate_new_variable();

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.LT, dest, this, other));

        return dest;
    }

    public IRVariable equals(IRVariable other) {
        IRVariable dest = ir.generate_new_variable();

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.EQ, dest, this, other));

        return dest;
    }

    public IRVariable notequals(IRVariable other) {
        IRVariable dest = ir.generate_new_variable();

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.NE, dest, this, other));

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

    IRVariable rol(int amount) {
        assert(0 <= amount && amount <= 31);

        IRVariable dest = ir.generate_new_variable();
        
        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpImm(IRBinaryDataOp.ROL, dest, this, amount));

        return dest;
    }

    // void _if(IRVariable cond, void delegate(void) true_case, void delegate(void) false_case) {
    // }

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
            case ">>": return IRBinaryDataOp.LSR;
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

struct IRLabel {
    int instruction_index;
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

struct IRInstructionSetVarImm {
    IRVariable dest;
    u32 imm;
}

struct IRInstructionSetFlags {
    IRVariable src;
    int flags;
}

struct IRInstructionRead {
    IRVariable dest;
    IRVariable address;
    int size;
}

struct IRInstructionWrite {
    IRVariable dest;
    IRVariable address;
    int size;
}

struct IRInstructionConditionalBranch {
    IRVariable cond;
    IRLabel* after_true_label;
}

struct IRInstructionGetHostCarry {
    IRVariable dest;
}

struct IRInstructionGetHostOverflow {
    IRVariable dest;
}
