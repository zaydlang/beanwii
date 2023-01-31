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
    IRInstructionSetVarImmInt,
    IRInstructionSetVarImmFloat,
    IRInstructionRead,
    IRInstructionWrite,
    IRInstructionReadSized,
    IRInstructionConditionalBranch,
    IRInstructionBranch,
    IRInstructionGetHostCarry,
    IRInstructionGetHostOverflow,
    IRInstructionHleFunc,
    IRInstructionPairedSingleMov,
    IRInstructionDebugAssert,
    IRInstructionSext
);

struct IR {
    struct PhiFunctionTransmuation {
        IRVariable from;
        IRVariable to;
    }

    enum MAX_IR_INSTRUCTIONS   = 0x10000;
    enum MAX_IR_VARIABLES      = 0x1000;
    enum MAX_IR_LABELS         = 0x1000;
    enum MAX_IR_TRANSMUTATIONS = 0x100;

    IRInstruction* instructions;
    size_t current_instruction_index;

    IRLabel* labels;
    size_t current_label_index;

    size_t current_transmutation_index;
    PhiFunctionTransmuation[MAX_IR_TRANSMUTATIONS] transmutations;

    // this has to be kept track of locally - not within an IRVariable. two reasons.
    // 1) i want IRVariables to be small and lightweight
    // 2) i want IRVariables to be able to be copied around without having to worry about
    //   updating the type of the variable
    IRVariableType[MAX_IR_VARIABLES] variable_types;

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
        current_transmutation_index = 0;
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
    
    IRVariable generate_new_variable(IRVariableType type) {
        int id = generate_new_variable_id();
        variable_types[id] = type;
        return IRVariable(&this, id);
    }

    void set_type(IRVariable variable, IRVariableType type) {
        variable_types[variable.variable_id] = type;
    }


    IRVariableType get_type(IRVariable variable) {
        return variable_types[variable.variable_id];
    }
    IRVariable constant(int constant) {
        IRVariable dest = generate_new_variable(IRVariableType.INTEGER);
        emit(IRInstructionSetVarImmInt(dest, constant));
        
        return dest;
    }

    IRVariable constant(float constant) {
        IRVariable dest = generate_new_variable(IRVariableType.FLOAT);
        emit(IRInstructionSetVarImmFloat(dest, constant));
        
        return dest;
    }

    IRVariable read_sized(IRVariable address, IRVariable size) {
        IRVariable value = generate_new_variable(IRVariableType.INTEGER);

        address.update_lifetime();
        size.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionReadSized(value, address, size));

        return value;
    }

    IRVariable read_u8(IRVariable address) {
        IRVariable value = generate_new_variable(IRVariableType.INTEGER);

        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value, address, u8.sizeof));

        return value;
    }

    IRVariable read_u16(IRVariable address) {
        IRVariable value = generate_new_variable(IRVariableType.INTEGER);

        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value, address, u16.sizeof));

        return value;
    }

    IRVariable read_u32(IRVariable address) {
        IRVariable value = generate_new_variable(IRVariableType.INTEGER);
        
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value, address, u32.sizeof));

        return value;
    }

    IRVariable read_u64(IRVariable address) {
        IRVariable value = generate_new_variable(IRVariableType.INTEGER);
        
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value, address, u64.sizeof));

        return value;
    }

    void write_u8(IRVariable address, IRVariable value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value, address, u8.sizeof));
    }

    void write_u16(IRVariable address, IRVariable value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value, address, u16.sizeof));
    }

    void write_u32(IRVariable address, IRVariable value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value, address, u32.sizeof));
    }

    void write_u64(IRVariable address, IRVariable value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value, address, u64.sizeof));
    }

    IRVariable get_reg(GuestReg reg) {
        IRVariableType type = get_variable_type_from_guest_reg(reg);
        IRVariable variable = generate_new_variable(type);
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

    IRLabel* generate_new_label() {
        IRLabel* label = &labels[current_label_index];
        label.id = cast(int) current_label_index;
        current_label_index++;

        return label;
    }
    

    void _if_no_phi(IRVariable cond, void delegate() true_case) {
        IRLabel* after_true_label = generate_new_label();

        this.emit(IRInstructionConditionalBranch(cond, after_true_label));

        this.update_lifetime(cond.variable_id);

        true_case();
        this.bind_label(after_true_label);
    }

    void _if(IRVariable cond, void delegate() true_case) {
        IRLabel* after_true_label   = generate_new_label();
        IRLabel* phi_function_label = generate_new_label();

        this.emit(IRInstructionConditionalBranch(cond, phi_function_label));

        this.update_lifetime(cond.variable_id);

        current_transmutation_index = 0;
        true_case();
        this.emit(IRInstructionBranch(after_true_label));

        this.bind_label(phi_function_label);

        // phi function
        for (int i = 0; i < current_transmutation_index; i++) {
            auto transmutation = transmutations[i];
            
            this.update_lifetime(transmutation.to.variable_id);
            this.update_lifetime(transmutation.from.variable_id);
            
            this.emit(IRInstructionUnaryDataOp(
                IRUnaryDataOp.MOV, 
                IRVariable(&this, transmutation.to.variable_id, ),
                IRVariable(&this, transmutation.from.variable_id)
            ));
        }

        this.bind_label(after_true_label);
    }

    void bind_label(IRLabel* label) {
        label.instruction_index = cast(int) this.current_instruction_index;
    }

    void run_hle_func(int function_id) {
        this.emit(IRInstructionHleFunc(function_id));
    }

    IRVariable get_carry() {
        IRVariable carry = generate_new_variable(IRVariableType.INTEGER);
        this.emit(IRInstructionGetHostCarry(carry));
        return carry;
    }

    IRVariable get_overflow() {
        IRVariable overflow = generate_new_variable(IRVariableType.INTEGER);
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

    void debug_assert(IRVariable condition) {
        condition.update_lifetime();
        emit(IRInstructionDebugAssert(condition));
    }

    // used to notify the IR that an IRVariable's ID has changed. necessary for implementing
    // phi functions for SSA (used for ir._if)
    void log_transmuation(IRVariable from, IRVariable to) {
        transmutations[current_transmutation_index].from.variable_id = from.variable_id;
        transmutations[current_transmutation_index].to.variable_id   = to.variable_id;
        variable_types[from.variable_id] = get_type(from);
        variable_types[to.variable_id]   = get_type(to);

        current_transmutation_index++;
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
                log_ir("%s v%d, v%d, 0x%x", i.op.to_string(), i.dest.get_id(), i.src1.get_id(), i.src2);
            },

            (IRInstructionBinaryDataOpVar i) {
                log_ir("%s v%d, v%d, v%d", i.op.to_string(), i.dest.get_id(), i.src1.get_id(), i.src2.get_id());
            },

            (IRInstructionUnaryDataOp i) {
                log_ir("%s v%d, v%d", i.op.to_string(), i.dest.get_id(), i.src.get_id());
            },

            (IRInstructionSetVarImmInt i) {
                log_ir("ld  v%d, 0x%x", i.dest.get_id(), i.imm);
            },

            (IRInstructionSetVarImmFloat i) {
                log_ir("ld  v%d, %f", i.dest.get_id(), i.imm);
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
                log_ir("bne v%d, #%d", i.cond.get_id(), i.after_true_label.instruction_index);
            },

            (IRInstructionBranch i) {
                log_ir("b   #%d", i.label.instruction_index);
            },

            (IRInstructionGetHostCarry i) {
                log_ir("getc v%d", i.dest.get_id());
            },

            (IRInstructionGetHostOverflow i) {
                log_ir("getv v%d", i.dest.get_id());
            },

            (IRInstructionHleFunc i) {
                log_ir("hle %d", i.function_id);
            },

            (IRInstructionPairedSingleMov i) {
                log_ir("mov ps%d:%d, ps%d", i.dest.get_id(), i.index, i.src.get_id());
            },

            (IRInstructionReadSized i) {
                log_ir("ld  v%d, [v%d] (size: %d)", i.dest.get_id(), i.address.get_id(), i.size.get_id());
            },

            (IRInstructionDebugAssert i) {
                log_ir("assert v%d", i.cond.get_id());
            },

            (IRInstructionSext i) {
                log_ir("sext v%d, v%d, %d", i.dest.get_id(), i.src.get_id(), i.bits);
            }
        );
    }
}

enum IRVariableType {
    INTEGER,
    FLOAT,
    PAIRED_SINGLE
}

private IRVariableType get_variable_type_from_guest_reg(GuestReg guest_reg) {
    switch (guest_reg) {
        case GuestReg.PS0: .. case GuestReg.PS31: return IRVariableType.PAIRED_SINGLE;
        case GuestReg.F0:  .. case GuestReg.F31:  return IRVariableType.FLOAT;

        default: 
            return IRVariableType.INTEGER;
    }
}

struct IRVariable {
    // Note that these are static single assignment variables, which means that
    // they can only be assigned to once. Any attempt to mutate an IRVariable
    // after it has been assigned to will result in a new variable being created
    // and returned. 

    private int variable_id;
    private IR* ir;

    this(IR* ir, int variable_id) {
        this.variable_id = variable_id;
        this.ir          = ir;
    }

    IRVariable opBinary(string s)(IRVariable other) {
        IRBinaryDataOp op = get_binary_data_op!s;

        IRVariableType type = IRVariableType.INTEGER;

        IRVariable dest = ir.generate_new_variable(type);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(op, dest, this, other));

        return dest;
    }

    IRVariable opBinary(string s)(int other) {
        IRBinaryDataOp op = get_binary_data_op!s;

        IRVariableType type = IRVariableType.INTEGER;
        if (op == IRBinaryDataOp.DIV) {
            type = IRVariableType.FLOAT;
        }

        IRVariable dest = ir.generate_new_variable(type);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpImm(op, dest, this, other));

        return dest;
    }

    void opIndexAssign(IRVariable other, size_t index) {
        assert(ir.get_type(this)  == IRVariableType.PAIRED_SINGLE);
        assert(ir.get_type(other) == IRVariableType.FLOAT);
        assert(index < 2);

        IRVariable old = this;
        this.variable_id = ir.generate_new_variable_id();
        ir.set_type(this, IRVariableType.PAIRED_SINGLE);
        ir.log_transmuation(old, this);

        this.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionPairedSingleMov(this, other, cast(int) index));
    }

    public IRVariable greater_unsigned(IRVariable other) {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.GTU, dest, this, other));

        return dest;
    }

    public IRVariable lesser_unsigned(IRVariable other) {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.LTU, dest, this, other));

        return dest;
    }

    public IRVariable greater_signed(IRVariable other) {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.GTS, dest, this, other));

        return dest;
    }

    public IRVariable lesser_signed(IRVariable other) {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.LTS, dest, this, other));

        return dest;
    }

    public IRVariable equals(IRVariable other) {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.EQ, dest, this, other));

        return dest;
    }

    public IRVariable notequals(IRVariable other) {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.NE, dest, this, other));

        return dest;
    }
    
    void opAssign(IRVariable rhs) {
        IRVariable old = this;
        this.variable_id = ir.generate_new_variable_id();
        ir.set_type(this, ir.get_type(rhs));
        ir.log_transmuation(old, this);

        this.update_lifetime();
        rhs.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, this, rhs));
    }

    IRVariable opUnary(string s)() {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        IRUnaryDataOp op = get_unary_data_op!s;

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(op, dest, this));

        return dest;
    }

    IRVariable rol(int amount) {
        assert(0 <= amount && amount <= 31);

        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpImm(IRBinaryDataOp.ROL, dest, this, amount));

        return dest;
    }

    IRVariable rol(IRVariable amount) {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        amount.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.ROL, dest, this, amount));

        return dest;
    }

    IRVariable clz() {
        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.CLZ, dest, this));

        return dest;
    }

    IRVariable to_float() {
        assert(ir.get_type(this) == IRVariableType.INTEGER);

        IRVariable dest = ir.generate_new_variable(IRVariableType.FLOAT);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.FLT_CAST, dest, this));

        return dest;
    }

    IRVariable to_int() {
        assert(ir.get_type(this) == IRVariableType.FLOAT);

        IRVariable dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.INT_CAST, dest, this));

        return dest;
    }

    IRVariable interpret_as_float() {
        assert(ir.get_type(this) == IRVariableType.INTEGER);

        IRVariable dest = ir.generate_new_variable(IRVariableType.FLOAT);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.FLT_INTERP, dest, this));

        return dest;
    }

    IRVariable sext(int bits) {
        assert(bits == 8 || bits == 16);

        IRVariable dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionSext(dest, this, bits));

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
            case "+":   return IRBinaryDataOp.ADD;
            case "-":   return IRBinaryDataOp.SUB;
            case "*":   return IRBinaryDataOp.MUL;
            case "/":   return IRBinaryDataOp.DIV;
            case "<<":  return IRBinaryDataOp.LSL;
            case ">>>": return IRBinaryDataOp.LSR;
            case ">>":  return IRBinaryDataOp.ASR;
            case "|":   return IRBinaryDataOp.ORR;
            case "&":   return IRBinaryDataOp.AND;
            case "^":   return IRBinaryDataOp.XOR;
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

    IRVariableType get_type() {
        return ir.get_type(this);
    }
}

struct IRLabel {
    int instruction_index;
    int id;
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

struct IRInstructionSetVarImmInt {
    IRVariable dest;
    u32 imm;
}

struct IRInstructionSetVarImmFloat {
    IRVariable dest;
    float imm;
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

struct IRInstructionReadSized {
    IRVariable dest;
    IRVariable address;
    IRVariable size;
}

struct IRInstructionConditionalBranch {
    IRVariable cond;
    IRLabel* after_true_label;
}

struct IRInstructionBranch {
    IRLabel* label;
}

struct IRInstructionGetHostCarry {
    IRVariable dest;
}

struct IRInstructionGetHostOverflow {
    IRVariable dest;
}

struct IRInstructionHleFunc {
    int function_id;
}

struct IRInstructionPairedSingleMov {
    IRVariable dest;
    IRVariable src;
    int index;
}

struct IRInstructionDebugAssert {
    IRVariable cond;
}

struct IRInstructionSext {
    IRVariable dest;
    IRVariable src;
    int bits;
}