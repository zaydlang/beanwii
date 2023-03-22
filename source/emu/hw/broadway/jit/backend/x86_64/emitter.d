module emu.hw.broadway.jit.backend.x86_64.emitter;

import emu.hw.broadway.jit.backend.x86_64.host_reg;
import emu.hw.broadway.jit.backend.x86_64.label;
import emu.hw.broadway.jit.backend.x86_64.register_allocator;
import emu.hw.broadway.jit.frontend.guest_reg;
import emu.hw.broadway.jit.ir.ir;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.jit;
import emu.hw.broadway.state;
import std.sumtype;
import util.log;
import util.number;
import xbyak;

__gshared bool g_START_LOGGING = false;

final class Code : CodeGenerator {
    JitConfig         config;
    RegisterAllocator register_allocator;

    int rsp_misalignment;

    this(JitConfig config) {
        this.config             = config;
        this.register_allocator = new RegisterAllocator();
    }

    void disambiguate_second_operand_and_emit(string op)(Reg reg, IROperand operand) {
        // static if (T == operand)

        // ir_operand.match!(
        //     (_IRVariable ir_variable) => ir_variable,

        //     (_IRConstant ir_constant) {
        //         error_jit("Tried to get variable from constant");
        //         return _IRVariable(-1);
        //     },

        //     (_IRGuestReg ir_guest_reg) {
        //         error_jit("Tried to get variable from guest register");
        //         return _IRVariable(-1);
        //     }
        // );
    }

    private size_t get_operand_size(Operand op) {
        if (op.isBit(8))   return 1;
        if (op.isBit(16))  return 2;
        if (op.isBit(32))  return 4;
        if (op.isBit(64))  return 8;
        if (op.isBit(128)) return 16;
        if (op.isBit(256)) return 32;
        assert(0);
    }

    private size_t get_stack_operand_size(Operand op) {
        size_t size = get_operand_size(op);
        if (size == 4) size = 8; // xbyak automatically turns 4-byte reg pushes into 8-byte reg pushes

        return size;
    }

    override void reset() {
        super.reset();
        
        if (register_allocator) register_allocator.reset();

        rsp_misalignment = 0;
    }

    override void push(Operand op) {
        rsp_misalignment -= get_stack_operand_size(op);
        rsp_misalignment &= 0xF;

        super.push(op);
    }

    override void pop(Operand op) {
        rsp_misalignment -= get_stack_operand_size(op);
        rsp_misalignment &= 0xF;

        super.pop(op);
    }

    override void call(Operand op) {
        if (rsp_misalignment != 0) sub(rsp, rsp_misalignment);
        super.call(op);
        if (rsp_misalignment != 0) add(rsp, rsp_misalignment);
    }
    
    void general_mov(IRVariableType type1, IRVariableType type2, Reg reg1, Reg reg2) {
        final switch (type1) {
            case IRVariableType.INTEGER:
                mov(reg1, reg2);
                break;
            
            case IRVariableType.FLOAT:
            case IRVariableType.PAIRED_SINGLE:
                final switch (type2) {
                    case IRVariableType.INTEGER:
                        movq(cast(Xmm) reg1, reg2.cvt64());
                        break;
                    
                    case IRVariableType.FLOAT:
                    case IRVariableType.PAIRED_SINGLE:
                        movq(cast(Xmm) reg1, cast(Xmm) reg2);
                        break;
                }
                break;

        }
    }

    struct LabeledData {
        u8[] data;
        Label label;
    }

    LabeledData[0x100] labeled_datas;
    size_t labeled_data_ptr;

    void put_data(Label label, u8[] new_data) {
        labeled_datas[labeled_data_ptr] = LabeledData(new_data, label);
        labeled_data_ptr++;
    }

    void emit(IR* ir) {
        emit_prologue();

        ir.pretty_print();

        for (int i = 0; i < ir.num_instructions(); i++) {
            for (int j = 0; j < ir.num_labels(); j++) {
                if (ir.labels[j].instruction_index == i) {
                    L(ir.labels[j].to_xbyak_label());
                }
            }
            emit(ir.instructions[i], i);
        }

        for (int j = 0; j < ir.num_labels(); j++) {
            if (ir.labels[j].instruction_index == ir.num_instructions()) {
                L(ir.labels[j].to_xbyak_label());
            }
        }

        emit_epilogue();

        for (int i = 0; i < labeled_data_ptr; i++) {
            L(labeled_datas[i].label);
            
            for (int j = 0; j < labeled_datas[i].data.length; j++) {
                db(labeled_datas[i].data[j]);
            }
        }

        assert(!this.hasUndefinedLabel()); // xbyak function

        // if (g_START_LOGGING) { 
            pretty_print(); 
        // }
        //   error_jit("jit"); }
    }

    void emit_prologue() {
        push(rbp);

        mov(rbp, rsp);
        and(rsp, ~15);
        this.rsp_misalignment = 0;
        
        // align stack

        push(rbp);
        push(rbx);
        push(rsi);
        push(rdi);
        push(r8);
        push(r9);
        push(r10);
        push(r11);
        push(r12);
        push(r13);
        push(r14);
        push(r15);
    }

    void emit_epilogue() {
        pop(r15);
        pop(r14);
        pop(r13);
        pop(r12);
        pop(r11);
        pop(r10);
        pop(r9);
        pop(r8);
        pop(rdi);
        pop(rsi);
        pop(rbx);
        pop(rbp);

        mov(rsp, rbp);
        pop(rbp);

        ret();
    }

    void emit_push_caller_save_regs() {
        push(rax);
        push(rcx);
        push(rdx);
        push(r8);
        push(r9);
        push(r10);
        push(r11);
    }

    void emit_pop_caller_save_regs() {
        pop(r11);
        pop(r10);
        pop(r9);
        pop(r8);
        pop(rdx);
        pop(rcx);
        pop(rax);
    }

    void emit_GET_REG(IRInstructionGetReg ir_instruction, int current_instruction_index) {
        GuestReg guest_reg = ir_instruction.src;
        Reg host_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);

        int offset = cast(int) guest_reg.get_reg_offset();

        // if (guest_reg.is_time_base()) {
        //     mov(host_reg.cvt64(), cast(size_t) config.timestamp);
        //     mov(host_reg.cvt64(), qword [host_reg.cvt64()]);

        //     Reg scratch = register_allocator.get_scratch_reg(IRVariableType.INTEGER).cvt64();
        //     mov(scratch, cast(size_t) &this.last_tb_update_timestamp);
        //     mov(scratch, qword [scratch]);

        //     // host_reg == the amount of cycles since the last TB update
        //     sub(host_reg.cvt64(), scratch);
        //     mov(scratch, qword [rdi + GuestReg.TBL.get_reg_offset()]);
        //     add(host_reg.cvt64(), scratch);
        //     if (guest_reg == GuestReg.TBU) {
        //         shr(host_reg.cvt64(), 32);
        //     }
        // } else {
            final switch (ir_instruction.dest.get_type()) {
                case IRVariableType.INTEGER:
                    mov(host_reg, dword [rdi + offset]);
                    break;
                
                case IRVariableType.FLOAT:
                case IRVariableType.PAIRED_SINGLE:
                    movq(cast(Xmm) host_reg, qword [rdi + offset]);
                    break;
            }
        // }
    }

    void emit_SET_REG_VAR(IRInstructionSetRegVar ir_instruction, int current_instruction_index) {
        GuestReg dest_reg = ir_instruction.dest;
        Reg src_reg = register_allocator.get_bound_host_reg(ir_instruction.src);
        
        int offset = cast(int) dest_reg.get_reg_offset();

        final switch (ir_instruction.src.get_type()) {
            case IRVariableType.INTEGER:
                mov(dword [rdi + offset], src_reg);
                break;
            
            case IRVariableType.FLOAT:
            case IRVariableType.PAIRED_SINGLE:
                movq(qword [rdi + offset], cast(Xmm) src_reg);
                break;
        }

        register_allocator.maybe_unbind_variable(ir_instruction.src, current_instruction_index);
    }

    void emit_SET_REG_IMM(IRInstructionSetRegImm ir_instruction, int current_instruction_index) {
        GuestReg dest_reg = ir_instruction.dest;
        
        int offset = cast(int) dest_reg.get_reg_offset();
        mov(dword [rdi + offset], ir_instruction.imm);
    }

    void emit_SET_FPSCR(IRInstructionSetFPSCR ir_instruction, int current_instruction_index) {
        Xmm src_reg = cast(Xmm) register_allocator.get_bound_host_reg(ir_instruction.src);
        Xmm scratch_xmm1 = cast(Xmm) register_allocator.get_scratch_reg(IRVariableType.FLOAT);
        Xmm scratch_xmm2 = cast(Xmm) register_allocator.get_scratch_reg(IRVariableType.FLOAT);

        Reg scratch_int = register_allocator.get_scratch_reg(IRVariableType.INTEGER);

        Label done_label = new Label();
        Label eq_label   = new Label();

        movapd(scratch_xmm2, src_reg);
        pxor(scratch_xmm1, scratch_xmm1);
        xor(scratch_int, scratch_int);
        comisd(scratch_xmm1, scratch_xmm2);
        seta(scratch_int.cvt8());
        sal(scratch_int.cvt32(), 15);
        comisd(scratch_xmm2, scratch_xmm1);
        jbe(eq_label);
        or(scratch_int, 1 << 14);
        jmp(done_label);
        L(eq_label);
        ucomisd(scratch_xmm2, scratch_xmm1);
        jp(done_label);
        jne(done_label);
        or(scratch_int, 1 << 13);
        L(done_label);
        mov(dword [rdi + cast(int) GuestReg.FPSCR.get_reg_offset()], scratch_int);

        register_allocator.unbind_scratch_reg(scratch_xmm1, IRVariableType.FLOAT);
        register_allocator.unbind_scratch_reg(scratch_xmm2, IRVariableType.FLOAT);
        register_allocator.unbind_scratch_reg(scratch_int, IRVariableType.INTEGER);
    }

    void emit_BINARY_DATA_OP_IMM(IRInstructionBinaryDataOpImm ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        Reg src1     = register_allocator.get_bound_host_reg(ir_instruction.src1);
        int src2     = ir_instruction.src2;
        
        switch (ir_instruction.op) {
            case IRBinaryDataOp.AND:
                mov(dest_reg, src1);
                and(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.ORR:
                mov(dest_reg, src1);
                or (dest_reg, src2);
                break;
            
            case IRBinaryDataOp.LSL:
                mov(dest_reg, src1);
                shl(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.LSR:
                mov(dest_reg, src1);
                shr(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.ASR:
                mov(dest_reg, src1);
                sar(dest_reg, src2);
                break;

            case IRBinaryDataOp.ADD:
                mov(dest_reg, src1);
                add(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.SUB:
                mov(dest_reg, src1);
                sub(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.XOR:
                mov(dest_reg, src1);
                xor(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.ROL:
                mov(dest_reg, src1);
                rol(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.MUL:
                imul(dest_reg, src1, src2);
                break;
            
            default: assert(0);
        }
        
        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.src1, current_instruction_index);
    }

    void emit_BINARY_DATA_OP_VAR(IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        Reg src1     = register_allocator.get_bound_host_reg(ir_instruction.src1);
        Reg src2     = register_allocator.get_bound_host_reg(ir_instruction.src2);
        
        switch (ir_instruction.op) {
            case IRBinaryDataOp.AND:
                mov(dest_reg, src1);
                and(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.ORR:
                mov(dest_reg, src1);
                or (dest_reg, src2);
                break;
            
            case IRBinaryDataOp.LSL:
                mov(dest_reg, src1);
                mov(ecx, src2.cvt8());
                shl(dest_reg, cl);
                break;
            
            case IRBinaryDataOp.LSR:
                mov(dest_reg, src1);
                mov(ecx, src2.cvt8());
                shr(dest_reg, cl);
                break;
            
            case IRBinaryDataOp.ASR:
                mov(dest_reg, src1);
                mov(ecx, src2.cvt8());
                sar(dest_reg, cl);
                break;
            
            case IRBinaryDataOp.ADD:
                emit_binary_data_op_var_add(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.SUB:
                emit_binary_data_op_var_sub(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.XOR:
                mov(dest_reg, src1);
                xor(dest_reg, src2);
                break;
            
            case IRBinaryDataOp.ROL:
                mov(dest_reg, src1);
                mov(ecx, src2.cvt8());
                rol(dest_reg, cl);
                break;
            
            case IRBinaryDataOp.GTU:
                emit_binary_data_op_var_gtu(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.LTU:
                emit_binary_data_op_var_ltu(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.GTS:
                emit_binary_data_op_var_gts(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.LTS:
                emit_binary_data_op_var_lts(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.EQ:
                emit_binary_data_op_var_eq(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.NE:
                emit_binary_data_op_var_ne(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.DIV:
                final switch (ir_instruction.src1.get_type()) {
                    case IRVariableType.PAIRED_SINGLE:
                        movq(cast(Xmm) dest_reg, cast(Xmm) src1);

                        if (ir_instruction.src2.get_type() == IRVariableType.INTEGER) {
                            pxor(cast(Xmm) src1, cast(Xmm) src1);
                            cvtsi2ss(cast(Xmm) src1, src2.cvt32());
                        }

                        divss(cast(Xmm) dest_reg, cast(Xmm) src1);
                        break;
                    
                    case IRVariableType.FLOAT:
                        assert(0);
                    
                    case IRVariableType.INTEGER:
                        register_allocator.assign_variable(this, ir_instruction.src1, HostReg_x86_64.RAX);
                        register_allocator.assign_variable(this, ir_instruction.src2, HostReg_x86_64.R15);
                        register_allocator.free_up_host_reg(this, HostReg_x86_64.RDX);

                        src1 = register_allocator.get_bound_host_reg(ir_instruction.src1);
                        src2 = register_allocator.get_bound_host_reg(ir_instruction.src2);

                        push(rdx);
                        movsxd(src1.cvt64(), src1.cvt32());
                        movsxd(src2.cvt64(), src2.cvt32());
                        cqo();
                        idiv(r15.cvt64());
                        register_allocator.sudo_assign_variable(this, ir_instruction.dest, HostReg_x86_64.RAX);
                        register_allocator.free_up_host_reg(this, HostReg_x86_64.RDX);

                        pop(rdx);
                }
                break;
            
            case IRBinaryDataOp.UDIV:
                register_allocator.assign_variable(this, ir_instruction.src1, HostReg_x86_64.RAX);
                register_allocator.assign_variable(this, ir_instruction.src2, HostReg_x86_64.R15);
                register_allocator.free_up_host_reg(this, HostReg_x86_64.RDX);

                push(rdx);
                xor(rdx, rdx);
                mov(eax, eax);
                div(r15);
                register_allocator.sudo_assign_variable(this, ir_instruction.dest, HostReg_x86_64.RAX);
                register_allocator.free_up_host_reg(this, HostReg_x86_64.RDX);

                pop(rdx);
                break;
            
            case IRBinaryDataOp.MUL:
                emit_binary_data_op_var_mul(this, ir_instruction, current_instruction_index);
                break;
            
            case IRBinaryDataOp.MULHI:
                mov(dest_reg.cvt32(), src1.cvt32());
                imul(dest_reg.cvt64(), src2.cvt64());
                shr(dest_reg.cvt64(), 32);
                break;
            
            case IRBinaryDataOp.MULHS:
                movsxd(src2.cvt64(), src2.cvt32());
                movsxd(src1.cvt64(), src1.cvt32());
                movsxd(dest_reg.cvt64(), src1.cvt32());
                imul(dest_reg.cvt64(), src2.cvt64());
                sar(dest_reg.cvt64(), 32);
                break;
                
            default: assert(0);
        }

        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.src1, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.src2, current_instruction_index);
    }

    alias BinaryDataOpHandler = void delegate(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index);
    alias UnaryDataOpHandler  = void delegate(Code code, Reg dest_reg, Reg src, int current_instruction_index);

    private void emit_binary_data_op_var_sub(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_sub_int,
            &emit_binary_data_op_var_sub_float,
            &emit_binary_data_op_var_sub_paired_single
        );
    }

    private void emit_binary_data_op_var_sub_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.mov(dest_reg, src1);
        code.sub(dest_reg, src2);
    }

    private void emit_binary_data_op_var_sub_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.movsd(cast(Xmm) dest_reg, cast(Xmm) src1);
        code.subsd(cast(Xmm) dest_reg, cast(Xmm) src2);
    }

    private void emit_binary_data_op_var_sub_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.movss(cast(Xmm) dest_reg, cast(Xmm) src1);
        code.subps(cast(Xmm) dest_reg, cast(Xmm) src2);
    }

    private void emit_binary_data_op_var_mul(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_mul_int,
            &emit_binary_data_op_var_mul_float,
            &emit_binary_data_op_var_mul_paired_single
        );
    }

    private void emit_binary_data_op_var_mul_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.mov(dest_reg, src1);
        code.imul(dest_reg, src2);
    }

    private void emit_binary_data_op_var_mul_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.movsd(cast(Xmm) dest_reg, cast(Xmm) src1);
        code.mulsd(cast(Xmm) dest_reg, cast(Xmm) src2);
    }

    private void emit_binary_data_op_var_mul_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.movss(cast(Xmm) dest_reg, cast(Xmm) src1);
        code.mulps(cast(Xmm) dest_reg, cast(Xmm) src2);
    }

    private void emit_binary_data_op_var_add(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_mul_int,
            &emit_binary_data_op_var_mul_float,
            &emit_binary_data_op_var_mul_paired_single
        );
    }

    private void emit_binary_data_op_var_add_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.add(dest_reg, src1);
        code.imul(dest_reg, src2);
    }

    private void emit_binary_data_op_var_add_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.movss(cast(Xmm) dest_reg, cast(Xmm) src1);
        code.addss(cast(Xmm) dest_reg, cast(Xmm) src2);
    }

    private void emit_binary_data_op_var_add_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.movss(cast(Xmm) dest_reg, cast(Xmm) src1);
        code.addps(cast(Xmm) dest_reg, cast(Xmm) src2);
    }

    private void emit_binary_data_op_var_gtu(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_gtu_int,
            &emit_binary_data_op_var_gtu_float,
            &emit_binary_data_op_var_gtu_paired_single
        );
    }

    private void emit_binary_data_op_var_gtu_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmp(src1, src2);
        code.seta(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_gtu_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmpss(cast(Xmm) src1, cast(Xmm) src2, 0);
        code.seta(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_gtu_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        assert(0);
    }

    public void emit_binary_data_op_var_ltu(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_ltu_int,
            &emit_binary_data_op_var_ltu_float,
            &emit_binary_data_op_var_ltu_paired_single
        );
    }

    private void emit_binary_data_op_var_ltu_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmp(src1, src2);
        code.setb(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_ltu_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmpss(cast(Xmm) src1, cast(Xmm) src2, 0);
        code.setb(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_ltu_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        assert(0);
    }

    private void emit_binary_data_op_var_gts(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_gts_int,
            &emit_binary_data_op_var_gts_float,
            &emit_binary_data_op_var_gts_paired_single
        );
    }

    private void emit_binary_data_op_var_gts_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmp(src1, src2);
        code.setg(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_gts_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmpss(cast(Xmm) src1, cast(Xmm) src2, 0);
        code.setg(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_gts_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        assert(0);
    }

    private void emit_binary_data_op_var_lts(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_lts_int,
            &emit_binary_data_op_var_lts_float,
            &emit_binary_data_op_var_lts_paired_single
        );
    }

    private void emit_binary_data_op_var_lts_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmp(src1, src2);
        code.setl(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_lts_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmpss(cast(Xmm) src1, cast(Xmm) src2, 0);
        log_ir("%s %s %s", src1, src2, dest_reg);
        code.setl(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_lts_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        assert(0);
    }

    private void emit_binary_data_op_var_eq(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_eq_int,
            &emit_binary_data_op_var_eq_float,
            &emit_binary_data_op_var_eq_paired_single
        );
    }

    private void emit_binary_data_op_var_eq_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmp(src1, src2);
        code.sete(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_eq_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmpss(cast(Xmm) src1, cast(Xmm) src2, 0);
        code.sete(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_eq_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        assert(0);
    }

    private void emit_binary_data_op_var_ne(Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        emit_binary_data_op_var_generic(
            code, ir_instruction, current_instruction_index,
            &emit_binary_data_op_var_ne_int,
            &emit_binary_data_op_var_ne_float,
            &emit_binary_data_op_var_ne_paired_single
        );
    }

    private void emit_binary_data_op_var_ne_int(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmp(src1, src2);
        code.setne(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_ne_float(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        code.cmpss(cast(Xmm) src1, cast(Xmm) src2, 0);
        code.setne(dest_reg.cvt8());
        code.movzx(dest_reg.cvt64(), dest_reg.cvt8());
    }

    private void emit_binary_data_op_var_ne_paired_single(Code code, Reg dest_reg, Reg src1, Reg src2, int current_instruction_index) {
        assert(0);
    }

    private void emit_unary_data_op_abs(Code code, IRInstructionUnaryDataOp ir_instruction, int current_instruction_index) {
        emit_unary_data_op_generic(
            code, ir_instruction, current_instruction_index,
            &emit_unary_data_op_neg_int,
            &emit_unary_data_op_neg_float,
            &emit_unary_data_op_neg_paired_single
        );
    }

    private void emit_unary_data_op_abs_int(Code code, Reg dest_reg, Reg src, int current_instruction_index) {
        assert(0);
    }

    private void emit_unary_data_op_abs_float(Code code, Reg dest_reg, Reg src, int current_instruction_index) {
        assert(0);
    }

    private void emit_unary_data_op_abs_paired_single(Code code, Reg dest_reg, Reg src, int current_instruction_index) {
        Label label = L();
        put_data(label, [0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00]);

        code.movss(cast(Xmm) dest_reg, cast(Xmm) src);
        code.vorpd(cast(Xmm) dest_reg, word [rip + label]);
    }

    private void emit_unary_data_op_neg(Code code, IRInstructionUnaryDataOp ir_instruction, int current_instruction_index) {
        emit_unary_data_op_generic(
            code, ir_instruction, current_instruction_index,
            &emit_unary_data_op_neg_int,
            &emit_unary_data_op_neg_float,
            &emit_unary_data_op_neg_paired_single
        );
    }

    private void emit_unary_data_op_neg_int(Code code, Reg dest_reg, Reg src, int current_instruction_index) {
        code.mov(dest_reg, src);
        code.neg(dest_reg);
    }

    private void emit_unary_data_op_neg_float(Code code, Reg dest_reg, Reg src, int current_instruction_index) {
        Label label = L();
        put_data(label, [0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00]);

        code.movss(cast(Xmm) dest_reg, cast(Xmm) src);
        code.xorps(cast(Xmm) dest_reg, xword [rip]);
    }

    private void emit_unary_data_op_neg_paired_single(Code code, Reg dest_reg, Reg src, int current_instruction_index) {
        Label label = L();
        put_data(label, [0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00]);

        code.movss(cast(Xmm) dest_reg, cast(Xmm) src);
        code.vxorpd(cast(Xmm) dest_reg, word [rip + label]);
    }

    private void emit_binary_data_op_var_generic(
        Code code, IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index,
        BinaryDataOpHandler int_handler, BinaryDataOpHandler float_handler, BinaryDataOpHandler paired_single_handler
    ) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        Reg src1     = register_allocator.get_bound_host_reg(ir_instruction.src1);
        Reg src2     = register_allocator.get_bound_host_reg(ir_instruction.src2);
        IRVariableType type = ir_instruction.src2.get_type();
            
        final switch (type) {
            case IRVariableType.INTEGER:
                int_handler(code, dest_reg, src1, src2, current_instruction_index);
                break;
            case IRVariableType.FLOAT:
                float_handler(code, dest_reg, src1, src2, current_instruction_index);
                break;
            case IRVariableType.PAIRED_SINGLE:
                paired_single_handler(code, dest_reg, src1, src2, current_instruction_index);
                break;
        }
    }

    private void emit_unary_data_op_generic(
        Code code, IRInstructionUnaryDataOp ir_instruction, int current_instruction_index,
        UnaryDataOpHandler int_handler, UnaryDataOpHandler float_handler, UnaryDataOpHandler paired_single_handler
    ) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        Reg src      = register_allocator.get_bound_host_reg(ir_instruction.src);
        IRVariableType type = ir_instruction.src.get_type();
            
        final switch (type) {
            case IRVariableType.INTEGER:
                int_handler(code, dest_reg, src, current_instruction_index);
                break;
            case IRVariableType.FLOAT:
                float_handler(code, dest_reg, src, current_instruction_index);
                break;
            case IRVariableType.PAIRED_SINGLE:
                paired_single_handler(code, dest_reg, src, current_instruction_index);
                break;
        }
    }

    void emit_UNARY_DATA_OP(IRInstructionUnaryDataOp ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        Reg src_reg  = register_allocator.get_bound_host_reg(ir_instruction.src);

        switch (ir_instruction.op) {
            case IRUnaryDataOp.NOT:
                mov(dest_reg, src_reg);
                not(dest_reg);
                break;

            case IRUnaryDataOp.NEG:
                emit_unary_data_op_neg(this, ir_instruction, current_instruction_index);
                break;
            
            case IRUnaryDataOp.MOV:
                general_mov(ir_instruction.dest.get_type(), ir_instruction.src.get_type(), dest_reg, src_reg);
                break;
            
            case IRUnaryDataOp.CTZ:
                mov(dest_reg, src_reg);
                rep();
                bsf(dest_reg, dest_reg);
                break;
            
            case IRUnaryDataOp.CLZ:
                mov(dest_reg, src_reg);
                rep();
                bsr(dest_reg, dest_reg);
                break;
            
            case IRUnaryDataOp.POPCNT:
                mov(dest_reg, src_reg);
                popcnt(dest_reg, dest_reg);
                break;
            
            case IRUnaryDataOp.FLT_INTERP:
                movq(cast(Xmm) dest_reg, src_reg.cvt64());
                break;
            
            case IRUnaryDataOp.FLT_CAST:
                Xmm dest_xmm = cast(Xmm) dest_reg;
                pxor(dest_xmm, dest_xmm);
                cvtsi2ss(dest_xmm, src_reg);
                break;
            
            case IRUnaryDataOp.INT_CAST:
                cvttss2si(dest_reg, cast(Xmm) src_reg);
                break;
            
            case IRUnaryDataOp.ABS:
                emit_unary_data_op_abs(this, ir_instruction, current_instruction_index);
                break;
            
            default: assert(0);
        }

        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.src,  current_instruction_index);
    }

    void emit_SET_VAR_IMM_INT(IRInstructionSetVarImmInt ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        mov(dest_reg, ir_instruction.imm);
        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
    }

    void emit_SET_VAR_IMM_FLOAT(IRInstructionSetVarImmFloat ir_instruction, int current_instruction_index) {
        Xmm dest_reg = cast(Xmm) register_allocator.get_bound_host_reg(ir_instruction.dest);

        // cry about it
        push(r10);
        mov(r10, *cast(size_t*)&ir_instruction.imm);
        movd(dest_reg, r10d);
        pop(r10);

        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
    }

    void emit_READ(IRInstructionRead ir_instruction, int current_instruction_index) {
        // TODO: optimize this instead of just spilling all registers    
        emit_push_caller_save_regs();

        Reg address_reg = register_allocator.get_bound_host_reg(ir_instruction.address);
        Reg value_reg   = register_allocator.get_bound_host_reg(ir_instruction.dest);

        push(rsi);
        push(rdi);

        // TODO: if any of value_reg / address_reg are bound to rdi / rsi, then we need to... tbh i don't
        // know exactly how to fix that but it's obviously a massive problem.

        mov(rsi, address_reg);
        mov(rdi, cast(size_t) config.mem_handler_context);

        final switch (ir_instruction.size) {
            case 8: mov(r10.cvt64(), cast(size_t) config.read_handler64); break;
            case 4: mov(r10.cvt64(), cast(size_t) config.read_handler32); break;
            case 2: mov(r10.cvt64(), cast(size_t) config.read_handler16); break;
            case 1: mov(r10.cvt64(), cast(size_t) config.read_handler8);  break;
        }

        call(r10);
        mov(value_reg, rax.cvt64());

        foreach (Reg reg; [rdi, rsi, r11, r10, r9, r8, rdx, rcx, rax]) {
            if (reg.getIdx() == value_reg.getIdx()) {
                add(sp, 8);
            } else {
                pop(reg);
            }
        }

        register_allocator.maybe_unbind_variable(ir_instruction.address, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.dest,    current_instruction_index);
    }

    void emit_WRITE(IRInstructionWrite ir_instruction, int current_instruction_index) {
        // TODO: optimize this instead of just spilling all registers    
        emit_push_caller_save_regs();

        Reg address_reg = register_allocator.get_bound_host_reg(ir_instruction.address);
        Reg value_reg   = register_allocator.get_bound_host_reg(ir_instruction.dest);

        push(rsi);
        push(rdi);
        push(rdx);

        // i hate this.
        push(value_reg);
        push(address_reg);
        pop(rsi);
        pop(rdx);

        mov(rdi, cast(size_t) config.mem_handler_context);

        final switch (ir_instruction.size) {
            case 8: mov(r10.cvt64(), cast(size_t) config.write_handler64); break;
            case 4: mov(r10.cvt64(), cast(size_t) config.write_handler32); break;
            case 2: mov(r10.cvt64(), cast(size_t) config.write_handler16); break;
            case 1: mov(r10.cvt64(), cast(size_t) config.write_handler8);  break;
        }

        call(r10);

        pop(rdx);
        pop(rdi);
        pop(rsi);

        emit_pop_caller_save_regs();

        register_allocator.maybe_unbind_variable(ir_instruction.address, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.dest,    current_instruction_index);
    }

    void emit_READ_SIZED(IRInstructionReadSized ir_instruction, int current_instruction_index) {
        // TODO: optimize this instead of just spilling all registers    
        emit_push_caller_save_regs();

        Reg address_reg = register_allocator.get_bound_host_reg(ir_instruction.address);
        Reg value_reg   = register_allocator.get_bound_host_reg(ir_instruction.dest);
        Reg size_reg    = register_allocator.get_bound_host_reg(ir_instruction.size);

        push(rsi);
        push(rdi);

        // we need three scratch registers that are not address_reg, value_reg, or size_reg
        Reg[3] scratch;
        int scratch_idx = 0;
        foreach (Reg reg; [rcx, rdx, r8, r9, r10, r11]) {
            if (reg.getIdx() == address_reg.getIdx() || reg.getIdx() == value_reg.getIdx() || reg.getIdx() == size_reg.getIdx()) {
                continue;
            }
            scratch[scratch_idx++] = reg;
            if (scratch_idx == 3) {
                break;
            }
        }

        assert(scratch_idx == 3);

        // i hate this function
        mov(scratch[0], address_reg);
        mov(scratch[1].cvt64(), cast(size_t) &config);
        push(scratch[2]);

        shr(scratch[2], 1);
        shl(scratch[2], 3);

        mov(rsi, scratch[0]);
        mov(rdi, qword [scratch[1].cvt64() + cast(int) JitConfig.mem_handler_context.offsetof]);
        mov(scratch[2], qword [scratch[1].cvt64() + scratch[2].cvt64()]);

        call(scratch[2]);
        pop(scratch[2]);

        // based on the size, we need to zero out the upper bits of the value register
        mov(value_reg, 0xFFFF_FFFF);
        mov(rcx, 4);
        sub(rcx, scratch[2]);
        shl(rcx, 3);
        shr(value_reg, cl);
        and(value_reg, rax);

        foreach (Reg reg; [rdi, rsi, r11, r10, r9, r8, rdx, rcx, rax]) {
            if (reg.getIdx() == value_reg.getIdx()) {
                add(sp, 8);
            } else {
                pop(reg);
            }
        }

        register_allocator.maybe_unbind_variable(ir_instruction.address, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.dest,    current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.size,    current_instruction_index);
    }

    void emit_CONDITIONAL_BRANCH(IRInstructionConditionalBranch ir_instruction, int current_instruction_index) {
        Reg cond_reg = register_allocator.get_bound_host_reg(ir_instruction.cond);

        cmp(cond_reg, 0);
        je((*ir_instruction.after_true_label).to_xbyak_label(), T_NEAR);

        register_allocator.maybe_unbind_variable(ir_instruction.cond, current_instruction_index);
    }

    void emit_BRANCH(IRInstructionBranch ir_instruction, int current_instruction_index) {
        jmp((*ir_instruction.label).to_xbyak_label(), T_NEAR);
    }

    void emit_GET_HOST_CARRY(IRInstructionGetHostCarry ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        setc(dest_reg.cvt8());
        movzx(dest_reg.cvt32(), dest_reg.cvt8());
    }

    void emit_GET_HOST_OVERFLOW(IRInstructionGetHostOverflow ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        seto(dest_reg.cvt8());
        movzx(dest_reg.cvt32(), dest_reg.cvt8());
    }

    void emit_HLE_FUNC(IRInstructionHleFunc ir_instruction, int current_instruction_index) {
        emit_push_caller_save_regs();

        // it is safe to clobber these registers, because if an HLE opcode gets emitted, it will
        // be the only IR opcode.
        mov(rdi, cast(size_t) config.hle_handler_context);
        mov(rsi, ir_instruction.function_id);
        mov(r10, cast(size_t) config.hle_handler);
        call(r10);

        emit_pop_caller_save_regs();
    }

    void emit_PAIRED_SINGLE_MOV(IRInstructionPairedSingleMov ir_instruction, int current_instruction_index) {
        Xmm dest_reg = cast(Xmm) register_allocator.get_bound_host_reg(ir_instruction.dest);
        Xmm src_reg  = cast(Xmm) register_allocator.get_bound_host_reg(ir_instruction.src);

        unpcklps(dest_reg, src_reg);
        if (ir_instruction.index == 1) {
            pshufd(dest_reg, dest_reg, 0b00_01);
        }
    }

    void emit_DEBUG_ASSERT(IRInstructionDebugAssert ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.cond);
        string after_assert_label = generate_unique_label();

        cmp(dest_reg, 0);
        je(after_assert_label);
        mov(rax.cvt64(), cast(size_t) (&this.jit_assert).funcptr);
        call(rax);
        L(after_assert_label);

        register_allocator.maybe_unbind_variable(ir_instruction.cond, current_instruction_index);
    }

    void emit_SEXT(IRInstructionSext ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        Reg src_reg  = register_allocator.get_bound_host_reg(ir_instruction.src);

        if (ir_instruction.bits == 8) {
            movsx(dest_reg.cvt32(), src_reg.cvt8());
        } else if (ir_instruction.bits == 16) {
            movsx(dest_reg.cvt32(), src_reg.cvt16());
        } else {
            assert(0);
        }
    }

    void emit_BREAKPOINT(IRInstructionBreakpoint ir_instruction, int current_instruction_index) {
        int3();
    }

    void emit(IRInstruction ir_instruction, int current_instruction_index) {
        ir_instruction.match!(
            (IRInstructionGetReg i)            => emit_GET_REG(i, current_instruction_index),
            (IRInstructionSetRegVar i)         => emit_SET_REG_VAR(i, current_instruction_index),
            (IRInstructionSetRegImm i)         => emit_SET_REG_IMM(i, current_instruction_index),
            (IRInstructionSetFPSCR i)          => emit_SET_FPSCR(i, current_instruction_index),
            (IRInstructionBinaryDataOpImm i)   => emit_BINARY_DATA_OP_IMM(i, current_instruction_index),
            (IRInstructionBinaryDataOpVar i)   => emit_BINARY_DATA_OP_VAR(i, current_instruction_index),
            (IRInstructionUnaryDataOp i)       => emit_UNARY_DATA_OP(i, current_instruction_index),
            (IRInstructionSetVarImmInt i)      => emit_SET_VAR_IMM_INT(i, current_instruction_index),
            (IRInstructionSetVarImmFloat i)    => emit_SET_VAR_IMM_FLOAT(i, current_instruction_index),
            (IRInstructionRead i)              => emit_READ(i, current_instruction_index),
            (IRInstructionWrite i)             => emit_WRITE(i, current_instruction_index),
            (IRInstructionReadSized i)         => emit_READ_SIZED(i, current_instruction_index),
            (IRInstructionConditionalBranch i) => emit_CONDITIONAL_BRANCH(i, current_instruction_index),
            (IRInstructionBranch i)            => emit_BRANCH(i, current_instruction_index),
            (IRInstructionGetHostCarry i)      => emit_GET_HOST_CARRY(i, current_instruction_index),
            (IRInstructionGetHostOverflow i)   => emit_GET_HOST_OVERFLOW(i, current_instruction_index),
            (IRInstructionHleFunc i)           => emit_HLE_FUNC(i, current_instruction_index),
            (IRInstructionPairedSingleMov i)   => emit_PAIRED_SINGLE_MOV(i, current_instruction_index),
            (IRInstructionDebugAssert i)       => emit_DEBUG_ASSERT(i, current_instruction_index),
            (IRInstructionSext i)              => emit_SEXT(i, current_instruction_index),
            (IRInstructionBreakpoint i)        => emit_BREAKPOINT(i, current_instruction_index),
        );
    }

    void pretty_print() {
        import capstone;

        auto disassembler = create(Arch.x86, ModeFlags(Mode.bit64 | Mode.littleEndian));
        auto instructions = disassembler.disasm(this.getCode()[0..this.getSize()], this.getSize());
        foreach (instruction; instructions) {
            log_xbyak("0x%x:\t%s\t\t%s", instruction.address, instruction.mnemonic, instruction.opStr);
        }
    }

    void jit_assert() {
        error_jit("Jit asserted 0");
    }
}