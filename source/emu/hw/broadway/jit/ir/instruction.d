module emu.hw.broadway.jit.ir.instruction;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.types;
import std.format;
import std.sumtype;
import util.log;
import util.number;

alias IRInstruction = SumType!(
    IRInstructionGetReg,
    IRInstructionSetRegVar,
    IRInstructionSetRegImm,
    IRInstructionSetFPSCR,
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
    IRInstructionSext,
    IRInstructionBreakpoint
);

final class Instruction {
    static IRInstruction GetReg(IRVariable variable, GuestReg guest_reg) {
        return cast(IRInstruction) IRInstructionGetReg(variable, guest_reg);
    }

    static IRInstruction SetRegVar(GuestReg guest_reg, IRVariable variable) {
        return cast(IRInstruction) IRInstructionSetRegVar(guest_reg, variable);
    }

    static IRInstruction SetRegImm(GuestReg guest_reg, int imm) {
        return cast(IRInstruction) IRInstructionSetRegImm(guest_reg, imm);
    }

    static IRInstruction SetFPSCR(IRVariable variable) {
        return cast(IRInstruction) IRInstructionSetFPSCR(variable);
    }

    static IRInstruction BinaryDataOpImm(IRBinaryDataOp op, IRVariable dest, IRVariable src, int imm) {
        return cast(IRInstruction) IRInstructionBinaryDataOpImm(op, dest, src, imm);
    }

    static IRInstruction BinaryDataOpVar(IRBinaryDataOp op, IRVariable dest, IRVariable src1, IRVariable src2) {
        return cast(IRInstruction) IRInstructionBinaryDataOpVar(op, dest, src1, src2);
    }

    static IRInstruction UnaryDataOp(IRUnaryDataOp op, IRVariable dest, IRVariable src) {
        return cast(IRInstruction) IRInstructionUnaryDataOp(op, dest, src);
    }

    static IRInstruction SetVarImmInt(IRVariable dest, int imm) {
        return cast(IRInstruction) IRInstructionSetVarImmInt(dest, imm);
    }

    static IRInstruction SetVarImmFloat(IRVariable dest, float imm) {
        return cast(IRInstruction) IRInstructionSetVarImmFloat(dest, imm);
    }

    static IRInstruction Read(IRVariable dest, IRVariable src, int size) {
        return cast(IRInstruction) IRInstructionRead(dest, src, size);
    }

    static IRInstruction Write(IRVariable dest, IRVariable src, int size) {
        return cast(IRInstruction) IRInstructionWrite(dest, src, size);
    }

    static IRInstruction ReadSized(IRVariable dest, IRVariable src, IRVariable size) {
        return cast(IRInstruction) IRInstructionReadSized(dest, src, size);
    }

    static IRInstruction ConditionalBranch(IRVariable cond, IRLabel* after_true_label) {
        return cast(IRInstruction) IRInstructionConditionalBranch(cond, after_true_label);
    }

    static IRInstruction Branch(IRLabel* label) {
        return cast(IRInstruction) IRInstructionBranch(label);
    }

    static IRInstruction GetHostCarry(IRVariable dest) {
        return cast(IRInstruction) IRInstructionGetHostCarry(dest);
    }

    static IRInstruction GetHostOverflow(IRVariable dest) {
        return cast(IRInstruction) IRInstructionGetHostOverflow(dest);
    }

    static IRInstruction HleFunc(int function_id) {
        return cast(IRInstruction) IRInstructionHleFunc(function_id);
    }

    static IRInstruction PairedSingleMov(IRVariable dest, IRVariable src) {
        return cast(IRInstruction) IRInstructionPairedSingleMov(dest, src);
    }

    static IRInstruction DebugAssert(IRVariable cond) {
        return cast(IRInstruction) IRInstructionDebugAssert(cond);
    }

    static IRInstruction Sext(IRVariable dest, IRVariable src, int size) {
        return cast(IRInstruction) IRInstructionSext(dest, src, size);
    }

    static IRInstruction Breakpoint() {
        return cast(IRInstruction) IRInstructionBreakpoint();
    }
}

struct IR {
    struct PhiFunctionTransmuation {
        IRVariableGenerator from;
        IRVariableGenerator to;
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

    // this has to be kept track of locally - not within an IRVariableGenerator. two reasons.
    // 1) i want IRVariableGenerators to be small and lightweight
    // 2) i want IRVariableGenerators to be able to be copied around without having to worry about
    //   updating the type of the variable
    IRVariableType[MAX_IR_VARIABLES] variable_types;

    // keeps track of a variables lifetime. this corresponds to an IR instruction. when this IR instruction
    // is executed, the variable is deleted (in other words, it gets unbound from the host register)
    size_t[MAX_IR_VARIABLES] variable_lifetimes;

    public IRInstruction[] get_instructions() {
        IRInstruction[] result;
        for (size_t i = 0; i < current_instruction_index; i++) {
            result ~= instructions[i];
        }
        return result;
    }

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
    
    IRVariableGenerator generate_new_variable(IRVariableType type) {
        int id = generate_new_variable_id();
        variable_types[id] = type;
        return IRVariableGenerator(&this, id);
    }

    void set_type(IRVariableGenerator variable, IRVariableType type) {
        variable_types[variable.variable_id] = type;
    }


    IRVariableType get_type(IRVariableGenerator variable) {
        return variable_types[variable.variable_id];
    }

    IRVariableGenerator constant(int constant) {
        IRVariableGenerator dest = generate_new_variable(IRVariableType.INTEGER);
        emit(IRInstructionSetVarImmInt(dest.get_variable(), constant));
        
        return dest;
    }

    IRVariableGenerator constant(float constant) {
        IRVariableGenerator dest = generate_new_variable(IRVariableType.FLOAT);
        emit(IRInstructionSetVarImmFloat(dest.get_variable(), constant));
        
        return dest;
    }

    IRVariableGenerator constant(double constant) {
        IRVariableGenerator dest = generate_new_variable(IRVariableType.DOUBLE);
        emit(IRInstructionSetVarImmFloat(dest.get_variable(), constant));
        
        return dest;
    }

    IRVariableGenerator read_sized(IRVariableGenerator address, IRVariableGenerator size) {
        IRVariableGenerator value = generate_new_variable(IRVariableType.INTEGER);

        address.update_lifetime();
        size.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionReadSized(value.get_variable(), address.get_variable(), size.get_variable()));

        return value;
    }

    IRVariableGenerator read_u8(IRVariableGenerator address) {
        IRVariableGenerator value = generate_new_variable(IRVariableType.INTEGER);

        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value.get_variable(), address.get_variable(), u8.sizeof));

        return value;
    }

    IRVariableGenerator read_u16(IRVariableGenerator address) {
        IRVariableGenerator value = generate_new_variable(IRVariableType.INTEGER);

        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value.get_variable(), address.get_variable(), u16.sizeof));

        return value;
    }

    IRVariableGenerator read_u32(IRVariableGenerator address) {
        IRVariableGenerator value = generate_new_variable(IRVariableType.INTEGER);
        
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value.get_variable(), address.get_variable(), u32.sizeof));

        return value;
    }

    IRVariableGenerator read_u64(IRVariableGenerator address) {
        IRVariableGenerator value = generate_new_variable(IRVariableType.INTEGER);
        
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionRead(value.get_variable(), address.get_variable(), u64.sizeof));

        return value;
    }

    void write_u8(IRVariableGenerator address, IRVariableGenerator value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value.get_variable(), address.get_variable(), u8.sizeof));
    }

    void write_u16(IRVariableGenerator address, IRVariableGenerator value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value.get_variable(), address.get_variable(), u16.sizeof));
    }

    void write_u32(IRVariableGenerator address, IRVariableGenerator value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value.get_variable(), address.get_variable(), u32.sizeof));
    }

    void write_u64(IRVariableGenerator address, IRVariableGenerator value) {
        address.update_lifetime();
        value.update_lifetime();
        emit(IRInstructionWrite(value.get_variable(), address.get_variable(), u64.sizeof));
    }

    IRVariableGenerator get_reg(GuestReg reg) {
        IRVariableType type = get_variable_type_from_guest_reg(reg);
        IRVariableGenerator variable = generate_new_variable(type);
        emit(IRInstructionGetReg(variable.get_variable(), reg));

        if (reg == GuestReg.PC) {
            variable = variable - 4;
        }

        return variable;
    }

    void set_reg(GuestReg reg, IRVariableGenerator variable) {
        variable.update_lifetime();
        emit(IRInstructionSetRegVar(reg, variable.get_variable()));
    }

    void set_reg(GuestReg reg, u32 imm) {
        emit(IRInstructionSetRegImm(reg, imm));
    }

    void set_fpscr(IRVariableGenerator dest) {
        dest.update_lifetime();
        emit(IRInstructionSetFPSCR(dest.get_variable()));
    }

    IRLabel* generate_new_label() {
        IRLabel* label = &labels[current_label_index];
        label.id = cast(int) current_label_index;
        current_label_index++;

        return label;
    }

    void _if_no_phi(IRVariableGenerator cond, void delegate() true_case) {
        IRLabel* after_true_label = generate_new_label();

        this.emit(IRInstructionConditionalBranch(cond.get_variable(), after_true_label));

        this.update_lifetime(cond.variable_id);

        true_case();
        this.bind_label(after_true_label);
    }
    

    void _if_no_phi(IRVariableGenerator cond, void delegate() true_case, void delegate() false_case) {
        IRLabel* after_true_label = generate_new_label();
        IRLabel* after_false_label = generate_new_label();

        this.emit(IRInstructionConditionalBranch(cond.get_variable(), after_true_label));

        this.update_lifetime(cond.variable_id);

        true_case();
        this.emit(IRInstructionBranch(after_false_label));
        this.bind_label(after_true_label);
        false_case();
        this.bind_label(after_false_label); 
    }

    void _if(IRVariableGenerator cond, void delegate() true_case) {
        IRLabel* after_true_label   = generate_new_label();
        IRLabel* phi_function_label = generate_new_label();

        this.emit(IRInstructionConditionalBranch(cond.get_variable(), phi_function_label));

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
                IRVariableGenerator(&this, transmutation.to.variable_id, ).get_variable(),
                IRVariableGenerator(&this, transmutation.from.variable_id).get_variable()
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

    IRVariableGenerator get_carry() {
        IRVariableGenerator carry = generate_new_variable(IRVariableType.INTEGER);
        this.emit(IRInstructionGetHostCarry(carry.get_variable()));
        return carry;
    }

    IRVariableGenerator get_overflow() {
        IRVariableGenerator overflow = generate_new_variable(IRVariableType.INTEGER);
        this.emit(IRInstructionGetHostOverflow(overflow.get_variable()));
        return overflow;
    }

    void update_lifetime(int variable_id) {
        variable_lifetimes[variable_id] = current_instruction_index;
    }

    size_t get_lifetime_end(int variable_id) {
        return variable_lifetimes[variable_id];
    }

    void debug_assert(IRVariableGenerator condition) {
        condition.update_lifetime();
        emit(IRInstructionDebugAssert(condition.get_variable()));
    }

    // used to notify the IR that an IRVariableGenerator's ID has changed. necessary for implementing
    // phi functions for SSA (used for ir._if)
    void log_transmuation(IRVariableGenerator from, IRVariableGenerator to) {
        transmutations[current_transmutation_index].from.variable_id = from.variable_id;
        transmutations[current_transmutation_index].to.variable_id   = to.variable_id;
        variable_types[from.variable_id] = get_type(from);
        variable_types[to.variable_id]   = get_type(to);

        current_transmutation_index++;
    }

    void breakpoint() {
        emit(IRInstructionBreakpoint());
    }
}

enum IRVariableType {
    INTEGER,
    FLOAT,
    DOUBLE,
    PAIRED_SINGLE
}

private IRVariableType get_variable_type_from_guest_reg(GuestReg guest_reg) {
    switch (guest_reg) {
        case GuestReg.PS0_0: .. case GuestReg.PS31_1: return IRVariableType.FLOAT;
        case GuestReg.F0:    .. case GuestReg.F31:    return IRVariableType.DOUBLE;

        default: 
            return IRVariableType.INTEGER;
    }
}

struct IRVariable {
    public int id;
}

struct IRVariableGenerator {
    // Note that these are static single assignment variables, which means that
    // they can only be assigned to once. Any attempt to mutate an IRVariableGenerator
    // after it has been assigned to will result in a new variable being created
    // and returned. 

    private int variable_id;
    private IR* ir;

    this(IR* ir, int variable_id) {
        this.variable_id = variable_id;
        this.ir          = ir;
    }

    IRVariableGenerator opBinary(string s)(IRVariableGenerator other) {
        IRBinaryDataOp op = get_binary_data_op!s;

        // assert(this.get_type() == other.get_type());
        IRVariableType type = this.get_type();

        IRVariableGenerator dest = ir.generate_new_variable(type);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(op, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }

    IRVariableGenerator opBinary(string s)(int other) {
        IRBinaryDataOp op = get_binary_data_op!s;

        IRVariableType type = IRVariableType.INTEGER;
        if (op == IRBinaryDataOp.DIV) {
            type = IRVariableType.DOUBLE;
        }

        IRVariableGenerator dest = ir.generate_new_variable(type);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpImm(op, dest.get_variable(), this.get_variable(), other));

        return dest;
    }

    void opIndexAssign(IRVariableGenerator other, size_t index) {
        assert(ir.get_type(this)  == IRVariableType.PAIRED_SINGLE);
        assert(ir.get_type(other) == IRVariableType.DOUBLE);
        assert(index < 2);

        IRVariableGenerator old = this;
        this.variable_id = ir.generate_new_variable_id();
        ir.set_type(this, IRVariableType.PAIRED_SINGLE);
        ir.log_transmuation(old, this);

        this.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionPairedSingleMov(this.get_variable(), other.get_variable(), cast(int) index));
    }

    // TODO: refactor to clean up
    // as it stands i don't care enough to do it

    public IRVariableGenerator greater_unsigned(IRVariableGenerator other) {
        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.GTU, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }

    public IRVariableGenerator lesser_unsigned(IRVariableGenerator other) {
        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.LTU, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }

    public IRVariableGenerator greater_signed(IRVariableGenerator other) {
        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.GTS, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }

    public IRVariableGenerator lesser_signed(IRVariableGenerator other) {
        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.LTS, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }

    public IRVariableGenerator equals(IRVariableGenerator other) {
        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.EQ, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }

    public IRVariableGenerator notequals(IRVariableGenerator other) {
        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.NE, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }
    
    void opAssign(IRVariableGenerator rhs) {
        IRVariableGenerator old = this;
        this.variable_id = ir.generate_new_variable_id();
        ir.set_type(this, ir.get_type(rhs));
        ir.log_transmuation(old, this);

        this.update_lifetime();
        rhs.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.MOV, this.get_variable(), rhs.get_variable()));
    }

    IRVariableGenerator opUnary(string s)() {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        IRUnaryDataOp op = get_unary_data_op!s;

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(op, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator rol(int amount) {
        assert(0 <= amount && amount <= 31);

        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpImm(IRBinaryDataOp.ROL, dest.get_variable(), this.get_variable(), amount));

        return dest;
    }

    IRVariableGenerator rol(IRVariableGenerator amount) {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        amount.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.ROL, dest.get_variable(), this.get_variable(), amount.get_variable()));

        return dest;
    }

    IRVariableGenerator multiply_high(IRVariableGenerator amount) {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        amount.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.MULHI, dest.get_variable(), this.get_variable(), amount.get_variable()));

        return dest;
    }

    IRVariableGenerator abs() {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.ABS, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator multiply_high_signed(IRVariableGenerator amount) {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        amount.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.MULHS, dest.get_variable(), this.get_variable(), amount.get_variable()));

        return dest;
    }

    IRVariableGenerator ctz() {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.CTZ, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator clz() {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.CLZ, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator popcnt() {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.POPCNT, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator unsigned_div(IRVariableGenerator other) {
        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();
        other.update_lifetime();

        ir.emit(IRInstructionBinaryDataOpVar(IRBinaryDataOp.UDIV, dest.get_variable(), this.get_variable(), other.get_variable()));

        return dest;
    }

    IRVariableGenerator to_float() {
        assert(ir.get_type(this) == IRVariableType.INTEGER);

        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.DOUBLE);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.FLT_CAST, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator to_int() {
        assert(ir.get_type(this) == IRVariableType.DOUBLE);

        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.INT_CAST, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator to_saturated_int() {
        assert(ir.get_type(this) == IRVariableType.DOUBLE);

        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.INTEGER);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.SATURATED_INT_CAST, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator interpret_as_float() {
        assert(ir.get_type(this) == IRVariableType.INTEGER);

        IRVariableGenerator dest = ir.generate_new_variable(IRVariableType.DOUBLE);
        ir.log_transmuation(this, dest);

        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionUnaryDataOp(IRUnaryDataOp.FLT_INTERP, dest.get_variable(), this.get_variable()));

        return dest;
    }

    IRVariableGenerator sext(int bits) {
        assert(bits == 8 || bits == 16);

        IRVariableGenerator dest = ir.generate_new_variable(ir.get_type(this));
        ir.log_transmuation(this, dest);
        
        this.update_lifetime();
        dest.update_lifetime();

        ir.emit(IRInstructionSext(dest.get_variable(), this.get_variable(), bits));

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

    IRVariable get_variable() {
        return IRVariable(this.get_id());
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

struct IRInstructionSetFPSCR {
    IRVariable src;
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

struct IRInstructionBreakpoint {
    
}

struct IRInstructionSext {
    IRVariable dest;
    IRVariable src;
    int bits;
}
