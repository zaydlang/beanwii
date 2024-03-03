module emu.hw.broadway.jit.passes.code_emission.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.jit;
import emu.hw.broadway.jit.x86;
import emu.hw.broadway.state;
import std.sumtype;
import util.log;
import util.number;
import xbyak;

alias JitFunction = void function(BroadwayState* state);

final class CodeEmission : RecipePass {
    private Map map;

    this(JitConfig jit_config) {
        map = new Map(jit_config);
    }

    public JitFunction get_function() {
        return map.get_function();
    }

    public size_t get_function_size() {
        return map.code.getSize();
    }

    final class Map : RecipeMap {
        private CodeGenerator code;
        private JitConfig jit_config;

        this(JitConfig jit_config) {
            this.jit_config = jit_config;
            code = new CodeGenerator();
        }

        public void reset() {
            code.reset();
            code.mov(rbp, rsp);
            code.and(rsp, ~15);

            push_callee_saved_registers();
        }

        public JitFunction get_function() {
            pop_callee_saved_registers();

            code.mov(rsp, rbp);
            code.ret();

            assert(!code.hasUndefinedLabel());
            return cast(JitFunction) code.getCode();
        }

        public size_t get_function_size() {
            return code.getSize();
        }
 
        private string to_xbyak_label(IRLabel label) {
            import std.format;
            log_jit("label: %s", label.instruction_index);
            return format("L%d", label.instruction_index);
        }

        size_t label_counter = 0;
        private string generate_new_label() {
            import std.format;
            return format("L%d", label_counter++);
        }

        private void apply_binary_data_op(T)(Recipe recipe, IRInstructionBinaryDataOp instr, T src2) {
            auto dest_reg = recipe.get_register_assignment(instr.dest).to_xbyak_reg();
            auto src1_reg = recipe.get_register_assignment(instr.src1).to_xbyak_reg();
            code.mov(dest_reg.cvt32(), src1_reg.cvt32());

            final switch (instr.op) {
            case IRBinaryDataOp.AND: code.and(dest_reg.cvt32(), src2); break;
            case IRBinaryDataOp.ADD: code.add(dest_reg.cvt32(), src2); break;
            case IRBinaryDataOp.LSL: 
                static if (is(T == int))   code.shl(dest_reg.cvt32(), src2);
                static if (is(T == Reg64)) code.shl(dest_reg.cvt32(), cl);
                break;
            case IRBinaryDataOp.LSR:
                static if (is(T == int))   code.shr(dest_reg.cvt32(), src2);
                static if (is(T == Reg64)) code.shr(dest_reg.cvt32(), cl);
                break;
            case IRBinaryDataOp.ASR:
                static if (is(T == int))   code.sar(dest_reg.cvt32(), src2);
                static if (is(T == Reg64)) code.sar(dest_reg.cvt32(), cl);
                break;
            case IRBinaryDataOp.ORR: code.or(dest_reg.cvt32(), src2); break;
            case IRBinaryDataOp.SUB: code.sub(dest_reg.cvt32(), src2); break;
            case IRBinaryDataOp.MUL: code.mul(dest_reg.cvt32()); break;
            case IRBinaryDataOp.MULHI: break;
            case IRBinaryDataOp.MULHS: break;
            case IRBinaryDataOp.DIV: break;
            case IRBinaryDataOp.UDIV: break; // Todo absolute pain in the ass
            case IRBinaryDataOp.XOR: code.xor(dest_reg.cvt32(), src2); break;
            case IRBinaryDataOp.ROL: 
                static if (is(T == int))   code.rol(dest_reg.cvt32(), src2);
                static if (is(T == Reg64)) code.rol(dest_reg.cvt32(), cl);
                break;
            case IRBinaryDataOp.GTS: 
                code.cmp(dest_reg.cvt32(), src2); 
                code.setg(dest_reg.cvt8());
                break;
            case IRBinaryDataOp.LTS: 
                code.cmp(dest_reg.cvt32(), src2); 
                code.setl(dest_reg.cvt8());
                break;
            case IRBinaryDataOp.GTU: 
                code.cmp(dest_reg.cvt32(), src2); 
                code.seta(dest_reg.cvt8());
                break;
            case IRBinaryDataOp.LTU:
                code.cmp(dest_reg.cvt32(), src2); 
                code.setb(dest_reg.cvt8());
                break;
            case IRBinaryDataOp.EQ:
                code.cmp(dest_reg.cvt32(), src2); 
                code.sete(dest_reg.cvt8());
                break;
            case IRBinaryDataOp.NE:
                code.cmp(dest_reg.cvt32(), src2); 
                code.setne(dest_reg.cvt8());
                break;
            }
        }

        private void apply_unary_data_op(T)(Recipe recipe, IRInstructionUnaryDataOp instr, T src) {
            auto dest_reg = recipe.get_register_assignment(instr.dest).to_xbyak_reg();
            code.mov(dest_reg.cvt32(), src);

            final switch (instr.op) {
            case IRUnaryDataOp.NOT: code.not(dest_reg.cvt32()); break;
            case IRUnaryDataOp.NEG: code.neg(dest_reg.cvt32()); break;
            case IRUnaryDataOp.MOV: break;
            case IRUnaryDataOp.ABS: break;
            case IRUnaryDataOp.CTZ: break;
            case IRUnaryDataOp.CLZ: break;
            case IRUnaryDataOp.POPCNT: break;
            case IRUnaryDataOp.FLT_CAST: break;
            case IRUnaryDataOp.FLT_INTERP: break;
            case IRUnaryDataOp.INT_CAST: break;
            case IRUnaryDataOp.SATURATED_INT_CAST: break;
            }
        }

        private void push_callee_saved_registers() {
            code.push(rbx);
            code.push(rbp);
            code.push(r12);
            code.push(r13);
            code.push(r14);
            code.push(r15);
        }

        private void push_caller_saved_registers() {
            code.push(rax);
            code.push(rcx);
            code.push(rdx);
            code.push(rsi);
            code.push(rdi);
            code.push(r8);
            code.push(r9);
            code.push(r10);
            code.push(r11);
        }

        private void pop_callee_saved_registers() {
            code.pop(r15);
            code.pop(r14);
            code.pop(r13);
            code.pop(r12);
            code.pop(rbp);
            code.pop(rbx);
        }

        private void pop_caller_saved_registers() {
            code.pop(r11);
            code.pop(r10);
            code.pop(r9);
            code.pop(r8);
            code.pop(rdi);
            code.pop(rsi);
            code.pop(rdx);
            code.pop(rcx);
            code.pop(rax);
        }

        override public RecipeAction map(Recipe recipe, IRInstruction* instr) {
            (*instr).match!(
                (IRInstructionGetReg instr) {
                    auto dest_reg = recipe.get_register_assignment(instr.dest).to_xbyak_reg();
                    code.mov(dest_reg.cvt32(), dword [cpu_state_reg + cast(int) get_reg_offset(instr.src)]);
                },
                (IRInstructionSetReg instr) {
                    instr.src.match!(
                        (IRVariable var) {
                            auto src_reg = recipe.get_register_assignment(var).to_xbyak_reg();
                            code.mov(dword [cpu_state_reg + cast(int) get_reg_offset(instr.dest)], src_reg.cvt32());
                        },
                        (int imm) {
                            code.mov(dword [cpu_state_reg + cast(int) get_reg_offset(instr.dest)], imm);
                        },
                        _ => error_jit("not yet")
                    );
                },
                (IRInstructionSetFPSCR instr) {
                    error_jit("not yet");
                },
                (IRInstructionBinaryDataOp instr) {
                    instr.src2.match!(
                        (IRVariable var) => apply_binary_data_op(recipe, instr, recipe.get_register_assignment(var).to_xbyak_reg()),
                        (int imm) => apply_binary_data_op(recipe, instr, imm),
                        _ => error_jit("not yet")
                    );
                },
                (IRInstructionUnaryDataOp instr) { 
                    instr.src.match!(
                        (IRVariable var) => apply_unary_data_op(recipe, instr, recipe.get_register_assignment(var).to_xbyak_reg()),
                        (int imm) => apply_unary_data_op(recipe, instr, imm),
                        _ => error_jit("not yet")
                    );
                },
                (IRInstructionSetVarImmInt instr) {
                    auto dest_reg = recipe.get_register_assignment(instr.dest).to_xbyak_reg();
                    code.mov(dest_reg.cvt32(), instr.imm);
                },
                (IRInstructionSetVarImmFloat instr) {
                    error_jit("not yet");
                },
                (IRInstructionRead instr) {
                    push_caller_saved_registers();
                    
                    final switch (instr.size) {
                        case 1: code.mov(tmp_reg, cast(u64) jit_config.read_handler8); break;
                        case 2: code.mov(tmp_reg, cast(u64) jit_config.read_handler16); break;
                        case 4: code.mov(tmp_reg, cast(u64) jit_config.read_handler32); break;
                        case 8: code.mov(tmp_reg, cast(u64) jit_config.read_handler64); break;
                    }

                    code.push(rdi);
                    code.mov(rdi, cast(u64) jit_config.mem_handler_context);
                    code.call(tmp_reg);
                    code.mov(tmp_reg, rax);
                    code.pop(rdi);

                    pop_caller_saved_registers();
                    code.mov(rax, tmp_reg);
                },
                (IRInstructionWrite instr) {
                    push_caller_saved_registers();
                    
                    final switch (instr.size) {
                        case 1: code.mov(tmp_reg, cast(u64) jit_config.write_handler8); break;
                        case 2: code.mov(tmp_reg, cast(u64) jit_config.write_handler16); break;
                        case 4: code.mov(tmp_reg, cast(u64) jit_config.write_handler32); break;
                        case 8: code.mov(tmp_reg, cast(u64) jit_config.write_handler64); break;
                    }

                    code.push(rdi);
                    code.mov(rdi, cast(u64) jit_config.mem_handler_context);
                    code.call(tmp_reg);
                    code.pop(rdi);
                    
                    pop_caller_saved_registers();
                },
                (IRInstructionReadSized instr) {
                    error_jit("not yet");
                },
                (IRInstructionConditionalBranch instr) {
                    auto cond_reg = recipe.get_register_assignment(instr.cond).to_xbyak_reg();
                    auto true_address_reg = recipe.get_register_assignment(instr.address_if_true).to_xbyak_reg();
                    auto false_address_reg = recipe.get_register_assignment(instr.address_if_false).to_xbyak_reg();
                    code.test(cond_reg.cvt32(), cond_reg.cvt32());
                    
                    auto label1 = generate_new_label();
                    auto label2 = generate_new_label();

                    code.jz(label1);
                    code.mov(dword [rdi + cast(int) BroadwayState.pc.offsetof], true_address_reg.cvt32());
                    code.jmp(label2);
                    code.L(label1);
                    code.mov(dword [rdi + cast(int) BroadwayState.pc.offsetof], false_address_reg.cvt32());
                    code.L(label2);
                },
                (IRInstructionConditionalBranchWithLink instr) {
                    auto cond_reg = recipe.get_register_assignment(instr.cond).to_xbyak_reg();
                    auto true_address_reg = recipe.get_register_assignment(instr.address_if_true).to_xbyak_reg();
                    auto false_address_reg = recipe.get_register_assignment(instr.address_if_false).to_xbyak_reg();
                    code.test(cond_reg.cvt32(), cond_reg.cvt32());

                    auto label1 = generate_new_label();
                    auto label2 = generate_new_label();

                    code.jz(label1);
                    code.mov(dword [rdi + cast(int) BroadwayState.pc.offsetof], true_address_reg.cvt32());
                    code.jmp(label2);
                    code.L(label1);
                    code.mov(dword [rdi + cast(int) BroadwayState.pc.offsetof], false_address_reg.cvt32());
                    code.L(label2);
                    code.mov(dword [rdi + cast(int) BroadwayState.lr.offsetof], cast(int) instr.link);
                },
                (IRInstructionBranch instr) {
                    // code.jmp(to_xbyak_label(*instr.label));
                },
                (IRInstructionGetHostCarry instr) {
                    auto dest_reg = recipe.get_register_assignment(instr.dest).to_xbyak_reg();
                    code.setc(dest_reg.cvt8());
                },
                (IRInstructionGetHostOverflow instr) {
                    auto dest_reg = recipe.get_register_assignment(instr.dest).to_xbyak_reg();
                    code.seto(dest_reg.cvt8());
                },
                // (IRInstructionHleFunc instr) => [],
                // (IRInstructionPairedSingleMov instr) => [instr.dest, instr.src],
                // (IRInstructionDebugAssert instr) => [instr.cond],
                // (IRInstructionSext instr) => [instr.dest, instr.src],
                // (IRInstructionBreakpoint instr) => [],
                (IRInstructionHaltCpu instr) {
                    code.mov(dword [cpu_state_reg + cast(int) BroadwayState.halted.offsetof], 1);
                },
                
                _ => error_jit("not yet")
            );

            return RecipeAction.DoNothing();
        }
    }

    public void reset() {
        map.reset();
    }

    override public void pass(Recipe recipe) {
        recipe.map(map);
    }
}
