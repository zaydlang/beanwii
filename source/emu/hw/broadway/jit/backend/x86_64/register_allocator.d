module emu.hw.broadway.jit.backend.x86_64.register_allocator;

import emu.hw.broadway.jit.backend.x86_64.host_reg;
import emu.hw.broadway.jit.ir.ir;
import std.traits;
import std.typecons;
import util.log;

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

            log_jit("Binding %s to %s.", host_reg, new_variable);
            variable_bound = true;
            this.variable = new_variable.get_id();
            log_jit("%s is %s", host_reg, this.variable);
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
        log_jit("Initializing register allocator.");
        
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

    HostReg_x86_64 get_bound_host_reg(IRVariable ir_variable) {
        BindingVariable* binding_variable;
        int binding_variable_index = get_binding_variable_from_variable(ir_variable);

        if (binding_variable_index == -1) {
            binding_variable = get_free_binding_variable();
            log_jit("wtf1 %d",bindings[1].variable);
            binding_variable.bind_variable(ir_variable);
            log_jit("wtf1 %d",bindings[1].variable);
        } else {
            binding_variable = &bindings[binding_variable_index];
        }

            log_jit("wtf1 %d",bindings[1].variable);
        return binding_variable.host_reg;
    }

    void bind_variable_to_host_reg(IRVariable ir_variable, HostReg_x86_64 host_reg) {
        bindings[host_reg].bind_variable(ir_variable);
    }

    int get_binding_variable_from_variable(IRVariable ir_variable) {
        for (int i = 0; i < NUM_HOST_REGS; i++) {
            BindingVariable binding_variable = bindings[i];
            log_jit("Comparing %d [%s] to %s. [%d]", binding_variable.variable, binding_variable.host_reg, ir_variable, !binding_variable.unbound());
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

    void unbind_variable(IRVariable ir_variable) {
        log_jit("Unbinding v%d.", ir_variable.get_id());
        auto binding_variable_index = get_binding_variable_from_variable(ir_variable);
        if (binding_variable_index == -1) error_jit("Tried to unbind %s when it was not bound.", ir_variable);
        bindings[binding_variable_index].unbind_variable();
    }

    void unbind_host_reg(HostReg_x86_64 host_reg) {
        bindings[host_reg].unbind_variable();
    }

    bool will_variable_be_unbound(IRVariable ir_variable, int last_emitted_ir_instruction) {
        return ir_variable.get_lifetime_end() == last_emitted_ir_instruction;
    }

    private BindingVariable* get_free_binding_variable() {
        log_jit("Getting free binding variable.");
        for (int i = 0; i < NUM_HOST_REGS; i++) {
            // pls dont clobber the stack pointer
            static if (is(HostReg_x86_64 == HostReg_x86_64)) {
                if (bindings[i].host_reg == HostReg_x86_64.ESP || bindings[i].host_reg == HostReg_x86_64.EDI) continue;
            }

            if (bindings[i].unbound()) {
                return &bindings[i];
            }
        }

        error_jit("No free binding variable found.");
        return &bindings[0]; // doesn't matter, error anyway
    }
}