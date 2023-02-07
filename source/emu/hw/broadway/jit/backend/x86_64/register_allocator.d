module emu.hw.broadway.jit.backend.x86_64.register_allocator;

import emu.hw.broadway.jit.backend.x86_64.emitter;
import emu.hw.broadway.jit.backend.x86_64.host_reg;
import emu.hw.broadway.jit.ir.ir;
import std.traits;
import std.typecons;
import util.log;
import xbyak;

final class RegisterAllocator {
    struct BindingVariable {
        public HostReg_x86_64 host_reg;

        public int variable;
        public bool variable_bound;

        public bool guest_reg_bound;

        this(HostReg_x86_64 host_reg) {
            this.host_reg = host_reg;
            this.unbind_variable();
        }

        public void bind_variable(IRVariable new_variable) {
            if (variable_bound) error_jit("Tried to bind %s to %s when it was already bound to %s.", host_reg, new_variable, variable);

            variable_bound = true;
            this.variable = new_variable.get_id();
        }

        public void bind_variable(int new_variable_id) {
            if (variable_bound) error_jit("Tried to bind %s to id %d when it was already bound to %s.", host_reg, new_variable_id, variable);

            variable_bound = true;
            this.variable = new_variable_id;
        }

        public void unbind_variable() {
            variable_bound = false;
        }

        public bool unbound() {
            return !variable_bound;
        }
    }

    enum HOST_REGS      = EnumMembers!HostReg_x86_64;
    enum NUM_HOST_REGS  = HOST_REGS.length;

    // should be enough, but can be increased if needed
    enum NUM_VARIABLES = 1024;

    BindingVariable[NUM_HOST_REGS] bindings;

    this() {
        for (int i = 0; i < NUM_HOST_REGS; i++) {
            bindings[i] = BindingVariable(cast(HostReg_x86_64) i);
        }
        
        reset();
    }

    void reset() {
        unbind_all();
    }

    void unbind_all() {
        for(int i = 0; i < NUM_HOST_REGS; i++) {
            bindings[i].unbind_variable();
        }
    }

    // Reg get_scratch_reg(IRVariableType type) {
    //     BindingVariable* binding_variable = get_free_binding_variable(ir_variable.get_type());
    //     binding_variable.bind_as_scratch_reg();
    //     return binding_variable.host_reg;
    // }

    // void unbind_scratch_reg(Reg reg) {
    //     bindings[reg].unbind_variable();
    // }

    Reg get_bound_host_reg(IRVariable ir_variable) {
        BindingVariable* binding_variable;
        int binding_variable_index = get_binding_variable_from_variable(ir_variable);

        if (binding_variable_index == -1) {
            binding_variable = get_free_binding_variable(ir_variable.get_type());
            binding_variable.bind_variable(ir_variable);
        } else {
            binding_variable = &bindings[binding_variable_index];
        }

        return decipher_type(binding_variable.host_reg, ir_variable.get_type());
    }

    Reg decipher_type(HostReg_x86_64 host_reg, IRVariableType type) {
        final switch (type) {
            case IRVariableType.INTEGER:
                return host_reg.to_xbyak_reg32();
            
            case IRVariableType.FLOAT:
            case IRVariableType.PAIRED_SINGLE:
                return host_reg.to_xbyak_xmm();
        }
    }

    void bind_variable_to_host_reg(IRVariable ir_variable, HostReg_x86_64 host_reg) {
        bindings[host_reg].bind_variable(ir_variable);
    }

    int get_binding_variable_from_variable(IRVariable ir_variable) {
        for (int i = 0; i < NUM_HOST_REGS; i++) {
            BindingVariable binding_variable = bindings[i];
            if (!binding_variable.unbound() && binding_variable.variable == ir_variable.get_id()) {
                return i;
            }
        }

        return -1;
    }

    void maybe_unbind_variable(IRVariable ir_variable, int last_emitted_ir_instruction) {
        if (ir_variable.get_lifetime_end() < last_emitted_ir_instruction) {
            error_jit("Used an IRVariable v%d on IR Instruction #%d while its lifetime has already ended on IR Instruction #%d.", ir_variable.get_id(), last_emitted_ir_instruction, ir_variable.get_lifetime_end());
        }

        if (ir_variable.get_lifetime_end() == last_emitted_ir_instruction) {
            unbind_variable(ir_variable);
        }
    }

    void print_bindings() {
        for (int i = 0; i < NUM_HOST_REGS; i++) {
            log_jit("bindings[%s] = %s", 
                cast(HostReg_x86_64) i, 
                bindings[i].variable_bound ? bindings[i].variable : -1
            );
        }
    }

    void free_up_host_reg(Code code, HostReg_x86_64 host_reg) {
        if (is_host_reg_bound(host_reg)) {
            relocate_variable(code, host_reg);
        }

        bindings[host_reg].unbind_variable();
    }

    void relocate_variable(Code code, HostReg_x86_64 host_reg) {
        if (is_host_reg_bound(host_reg)) {
            IRVariableType type = get_type_from_host_reg(host_reg);
            BindingVariable* binding_variable = get_free_binding_variable(type);
            binding_variable.bind_variable(get_variable_id_from_host_reg(host_reg));
            
            code.mov(decipher_type(binding_variable.host_reg, type), decipher_type(host_reg, type));
            unbind_host_reg(host_reg);
        }
    }

    void sudo_assign_variable(Code code, IRVariable ir_variable, HostReg_x86_64 host_reg) {
        if (is_host_reg_bound(host_reg)) relocate_variable(code, host_reg);

        HostReg_x86_64 old_host_reg = get_host_reg_from_variable(ir_variable);
        unbind_host_reg(old_host_reg);

        bind_variable_to_host_reg(ir_variable, host_reg);
    }

    void assign_variable(Code code, IRVariable ir_variable, HostReg_x86_64 host_reg) {
        relocate_variable(code, host_reg);

        HostReg_x86_64 old_host_reg = get_host_reg_from_variable(ir_variable);
        unbind_host_reg(old_host_reg);
        bind_variable_to_host_reg(ir_variable, host_reg);

        code.mov(decipher_type(host_reg, ir_variable.get_type()), decipher_type(old_host_reg, ir_variable.get_type()));
    }


    int get_variable_id_from_host_reg(HostReg_x86_64 host_reg) {
        return bindings[host_reg].variable;
    }

    HostReg_x86_64 get_host_reg_from_variable(IRVariable ir_variable) {
        int binding_variable_index = get_binding_variable_from_variable(ir_variable);
        if (binding_variable_index == -1) error_jit("Tried to get host reg from %s when it was not bound.", ir_variable);
        return bindings[binding_variable_index].host_reg;
    }

    void unbind_variable(IRVariable ir_variable) {
        // log_jit("Unbinding %s", ir_variable);
        auto binding_variable_index = get_binding_variable_from_variable(ir_variable);
        if (binding_variable_index == -1) error_jit("Tried to unbind %s when it was not bound.", ir_variable);
        bindings[binding_variable_index].unbind_variable();
    }

    bool is_host_reg_bound(HostReg_x86_64 host_reg) {
        return !bindings[host_reg].unbound();
    }

    void unbind_host_reg(HostReg_x86_64 host_reg) {
        bindings[host_reg].unbind_variable();
    }

    bool will_variable_be_unbound(IRVariable ir_variable, int last_emitted_ir_instruction) {
        return ir_variable.get_lifetime_end() == last_emitted_ir_instruction;
    }

    private BindingVariable* get_free_binding_variable(IRVariableType type) {
        int start;
        int end;
        final switch (type) {
            case IRVariableType.INTEGER:
                start = HostReg_x86_64.RAX;
                end   = HostReg_x86_64.R15;
                break;
            
            case IRVariableType.FLOAT:
                start = HostReg_x86_64.XMM0;
                end   = HostReg_x86_64.XMM7;
                break;

            case IRVariableType.PAIRED_SINGLE:
                goto case IRVariableType.FLOAT;
        }

        for (int i = start; i <= end; i++) {
            // pls dont clobber the stack pointer
            static if (is(HostReg_x86_64 == HostReg_x86_64)) {
                if (bindings[i].host_reg == HostReg_x86_64.RSP || bindings[i].host_reg == HostReg_x86_64.RDI || bindings[i].host_reg == HostReg_x86_64.RCX) continue;
            }

            if (bindings[i].unbound()) {
                return &bindings[i];
            }
        }

        print_bindings();
        error_jit("No free binding variable found.");
        return &bindings[0]; // doesn't matter, error anyway
    }

    IRVariableType get_type_from_host_reg(HostReg_x86_64 host_reg) {
        final switch (host_reg) {
            case HostReg_x86_64.RAX:
            case HostReg_x86_64.RBX:
            case HostReg_x86_64.RCX:
            case HostReg_x86_64.RDX:
            case HostReg_x86_64.RSI:
            case HostReg_x86_64.RDI:
            case HostReg_x86_64.RBP:
            case HostReg_x86_64.RSP:
            case HostReg_x86_64.R8:
            case HostReg_x86_64.R9:
            case HostReg_x86_64.R10:
            case HostReg_x86_64.R11:
            case HostReg_x86_64.R12:
            case HostReg_x86_64.R13:
            case HostReg_x86_64.R14:
            case HostReg_x86_64.R15:
                return IRVariableType.INTEGER;

            case HostReg_x86_64.XMM0:
            case HostReg_x86_64.XMM1:
            case HostReg_x86_64.XMM2:
            case HostReg_x86_64.XMM3:
            case HostReg_x86_64.XMM4:
            case HostReg_x86_64.XMM5:
            case HostReg_x86_64.XMM6:
            case HostReg_x86_64.XMM7:
                return IRVariableType.FLOAT;
            
            case HostReg_x86_64.SPL:
            case HostReg_x86_64.BPL:
            case HostReg_x86_64.SIL:
            case HostReg_x86_64.DIL:
                error_jit("cry about it");
                assert(0);
        }
    }
}