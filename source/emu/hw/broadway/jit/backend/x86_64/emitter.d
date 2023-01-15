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

final class Code : CodeGenerator {
    JitConfig         config;
    RegisterAllocator register_allocator;

    bool rsp_aligned;

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

    override void reset() {
        super.reset();
        
        if (register_allocator) register_allocator.reset();

        rsp_aligned = true;
    }

    override void push(Operand op) {
        rsp_aligned = !rsp_aligned;
        super.push(op);
    }

    override void pop(Operand op) {
        rsp_aligned = !rsp_aligned;
        super.pop(op);
    }

    override void call(Operand op) {
        if (!rsp_aligned) sub(rsp, 8);
        super.call(op);
        if (!rsp_aligned) add(rsp, 8);
    }
    
    void emit(IR* ir) {
        emit_prologue();

        // ir.pretty_print();

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

        assert(!this.hasUndefinedLabel()); // xbyak function

        emit_epilogue();
    }

    void emit_prologue() {
        push(rbp);

        mov(rbp, rsp);
        and(rsp, ~15);
        this.rsp_aligned = true;
        
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
        pop(rax);
        pop(rcx);
        pop(rdx);
        pop(r8);
        pop(r9);
        pop(r10);
        pop(r11);
    }

    void emit_GET_REG(IRInstructionGetReg ir_instruction, int current_instruction_index) {
        GuestReg guest_reg = ir_instruction.src;
        Reg host_reg = register_allocator.get_bound_host_reg(ir_instruction.dest).to_xbyak_reg64();

        int offset = cast(int) BroadwayState.gprs.offsetof + 4 * guest_reg;
        mov(host_reg.cvt32(), dword [rdi + offset]);
    }

    void emit_SET_REG_VAR(IRInstructionSetRegVar ir_instruction, int current_instruction_index) {
        GuestReg dest_reg = ir_instruction.dest;
        Reg src_reg = register_allocator.get_bound_host_reg(ir_instruction.src).to_xbyak_reg64();
        
        int offset = cast(int) BroadwayState.gprs.offsetof + 4 * dest_reg;
        mov(dword [rdi + offset], src_reg.cvt32());

        register_allocator.maybe_unbind_variable(ir_instruction.src, current_instruction_index);
    }

    void emit_SET_REG_IMM(IRInstructionSetRegImm ir_instruction, int current_instruction_index) {
        GuestReg dest_reg = ir_instruction.dest;
        
        int offset = cast(int) BroadwayState.gprs.offsetof + 4 * dest_reg;
        mov(dword [rdi + offset], ir_instruction.imm);
    }

    void emit_BINARY_DATA_OP_IMM(IRInstructionBinaryDataOpImm ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest).to_xbyak_reg64();
        Reg src1     = register_allocator.get_bound_host_reg(ir_instruction.src1).to_xbyak_reg64();
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
            
            default: assert(0);
        }
        
        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.src1, current_instruction_index);
    }

    void emit_BINARY_DATA_OP_VAR(IRInstructionBinaryDataOpVar ir_instruction, int current_instruction_index) {
        HostReg_x86_64 dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        HostReg_x86_64 src1     = register_allocator.get_bound_host_reg(ir_instruction.src1);
        HostReg_x86_64 src2     = register_allocator.get_bound_host_reg(ir_instruction.src2);
        
        switch (ir_instruction.op) {
            case IRBinaryDataOp.AND:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                and(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg64());
                break;
            
            case IRBinaryDataOp.ORR:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                or (dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg64());
                break;
            
            case IRBinaryDataOp.LSL:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                shl(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.LSR:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                shr(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.ASR:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                sar(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.ADD:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                add(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg64());
                break;
            
            case IRBinaryDataOp.SUB:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                sub(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg64());
                break;
            
            case IRBinaryDataOp.XOR:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                xor(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg64());
                break;
            
            case IRBinaryDataOp.ROL:
                mov(dest_reg.to_xbyak_reg64(), src1.to_xbyak_reg64());
                rol(dest_reg.to_xbyak_reg64(), src2.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.GTU:
                cmp(src1.to_xbyak_reg64(), src2.to_xbyak_reg64());
                seta(dest_reg.to_xbyak_reg8());
                movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.LTU:
                cmp(src1.to_xbyak_reg64(), src2.to_xbyak_reg64());
                setb(dest_reg.to_xbyak_reg8());
                movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.GTS:
                cmp(src1.to_xbyak_reg64(), src2.to_xbyak_reg64());
                setg(dest_reg.to_xbyak_reg8());
                movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.LTS:
                cmp(src1.to_xbyak_reg64(), src2.to_xbyak_reg64());
                setl(dest_reg.to_xbyak_reg8());
                movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.EQ:
                cmp(src1.to_xbyak_reg64(), src2.to_xbyak_reg64());
                sete(dest_reg.to_xbyak_reg8());
                movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
                break;
            
            case IRBinaryDataOp.NE:
                cmp(src1.to_xbyak_reg64(), src2.to_xbyak_reg64());
                setne(dest_reg.to_xbyak_reg8());
                movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
                break;
            
            default: assert(0);
        }

        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.src1, current_instruction_index);
        register_allocator.maybe_unbind_variable(ir_instruction.src2, current_instruction_index);
    }

    void emit_UNARY_DATA_OP(IRInstructionUnaryDataOp ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest).to_xbyak_reg64();
        Reg src_reg  = register_allocator.get_bound_host_reg(ir_instruction.src).to_xbyak_reg64();

        bool unbound_src = false;

        switch (ir_instruction.op) {
            case IRUnaryDataOp.NOT:
                mov(dest_reg, src_reg);
                not(dest_reg);
                break;

            case IRUnaryDataOp.NEG:
                mov(dest_reg, src_reg);
                neg(dest_reg);
                break;
            
            case IRUnaryDataOp.MOV:
                mov(dest_reg, src_reg);
                break;
            
            case IRUnaryDataOp.CLZ:
                mov(dest_reg, src_reg);
                bsf(dest_reg, dest_reg);
                break;

            default: break;
        }

        register_allocator.maybe_unbind_variable(ir_instruction.dest, current_instruction_index);
        
        if (!unbound_src) {
            register_allocator.maybe_unbind_variable(ir_instruction.src,  current_instruction_index);
        }
    }

    void emit_SET_VAR_IMM(IRInstructionSetVarImm ir_instruction, int current_instruction_index) {
        Reg dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest).to_xbyak_reg64();
        mov(dest_reg, ir_instruction.imm);
    }

    void emit_READ(IRInstructionRead ir_instruction, int current_instruction_index) {
        // TODO: optimize this instead of just spilling all registers    
        emit_push_caller_save_regs();

        Reg address_reg = register_allocator.get_bound_host_reg(ir_instruction.address).to_xbyak_reg64();
        Reg value_reg   = register_allocator.get_bound_host_reg(ir_instruction.dest).to_xbyak_reg64();

        push(rsi);
        push(rdi);

        // TODO: if any of value_reg / address_reg are bound to rdi / rsi, then we need to... tbh i don't
        // know exactly how to fix that but it's obviously a massive problem.

        mov(rsi, address_reg);
        mov(rdi, cast(u64) config.mem_handler_context);

        final switch (ir_instruction.size) {
            case 4: mov(r10, cast(u64) config.read_handler32); break;
            case 2: mov(r10, cast(u64) config.read_handler16); break;
            case 1: mov(r10, cast(u64) config.read_handler8);  break;
        }

        call(r10);
        mov(value_reg, rax);

        foreach (Reg reg; [rdi, rsi, r11, r10, r9, r8, rdx, rcx, rax]) {
            if (reg.getIdx() == value_reg.getIdx()) {
                add(sp, 8);
            } else {
                pop(reg);
            }
        }
    }

    void emit_WRITE(IRInstructionWrite ir_instruction, int current_instruction_index) {
        // TODO: optimize this instead of just spilling all registers    
        emit_push_caller_save_regs();

        Reg address_reg = register_allocator.get_bound_host_reg(ir_instruction.address).to_xbyak_reg64();
        Reg value_reg   = register_allocator.get_bound_host_reg(ir_instruction.dest).to_xbyak_reg64();

        push(rsi);
        push(rdi);
        push(rdx);

        // TODO: if any of value_reg / address_reg are bound to rdi / rsi, then we need to... tbh i don't
        // know exactly how to fix that but it's obviously a massive problem.

        mov(rdx, value_reg);
        mov(rsi, address_reg);
        mov(rdi, cast(u64) config.mem_handler_context);

        final switch (ir_instruction.size) {
            case 4: mov(r10, cast(u64) config.write_handler32); break;
            case 2: mov(r10, cast(u64) config.write_handler16); break;
            case 1: mov(r10, cast(u64) config.write_handler8);  break;
        }

        call(r10);

        pop(rdx);
        pop(rdi);
        pop(rsi);

        emit_pop_caller_save_regs();
    }

    void emit_CONDITIONAL_BRANCH(IRInstructionConditionalBranch ir_instruction, int current_instruction_index) {
        Reg cond_reg = register_allocator.get_bound_host_reg(ir_instruction.cond).to_xbyak_reg64();

        cmp(cond_reg, 0);
        je((*ir_instruction.after_true_label).to_xbyak_label());
    }

    void emit_GET_HOST_CARRY(IRInstructionGetHostCarry ir_instruction, int current_instruction_index) {
        HostReg_x86_64 dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        setc(dest_reg.to_xbyak_reg8());
        movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
    }

    void emit_GET_HOST_OVERFLOW(IRInstructionGetHostOverflow ir_instruction, int current_instruction_index) {
        HostReg_x86_64 dest_reg = register_allocator.get_bound_host_reg(ir_instruction.dest);
        seto(dest_reg.to_xbyak_reg8());
        movzx(dest_reg.to_xbyak_reg64(), dest_reg.to_xbyak_reg8());
    }

    void emit_HLE_FUNC(IRInstructionHleFunc ir_instruction, int current_instruction_index) {
        emit_push_caller_save_regs();

        // it is safe to clobber these registers, because if an HLE opcode gets emitted, it will
        // be the only IR opcode.
        mov(rdi, cast(u64) config.hle_handler_context);
        mov(rsi, ir_instruction.function_id);
        mov(r10, cast(u64) config.hle_handler);
        call(r10);

        emit_pop_caller_save_regs();
    }

    void emit(IRInstruction ir_instruction, int current_instruction_index) {
        ir_instruction.match!(
            (IRInstructionGetReg i)            => emit_GET_REG(i, current_instruction_index),
            (IRInstructionSetRegVar i)         => emit_SET_REG_VAR(i, current_instruction_index),
            (IRInstructionSetRegImm i)         => emit_SET_REG_IMM(i, current_instruction_index),
            (IRInstructionBinaryDataOpImm i)   => emit_BINARY_DATA_OP_IMM(i, current_instruction_index),
            (IRInstructionBinaryDataOpVar i)   => emit_BINARY_DATA_OP_VAR(i, current_instruction_index),
            (IRInstructionUnaryDataOp i)       => emit_UNARY_DATA_OP(i, current_instruction_index),
            (IRInstructionSetVarImm i)         => emit_SET_VAR_IMM(i, current_instruction_index),
            (IRInstructionRead i)              => emit_READ(i, current_instruction_index),
            (IRInstructionWrite i)             => emit_WRITE(i, current_instruction_index),
            (IRInstructionConditionalBranch i) => emit_CONDITIONAL_BRANCH(i, current_instruction_index),
            (IRInstructionGetHostCarry i)      => emit_GET_HOST_CARRY(i, current_instruction_index),
            (IRInstructionGetHostOverflow i)   => emit_GET_HOST_OVERFLOW(i, current_instruction_index),
            (IRInstructionHleFunc i)           => emit_HLE_FUNC(i, current_instruction_index)
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
}