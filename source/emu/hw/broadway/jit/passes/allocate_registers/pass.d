module emu.hw.broadway.jit.passes.allocate_registers.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.x86;
import std.algorithm;
import std.range;
import std.sumtype;
import util.log;

final class AllocateRegisters : RecipePass {
    final class CollectLifetimes : RecipeMap {
        int[IRVariable] variable_birth;
        int[IRVariable] variable_death;
        int index = 0;

        override public RecipeAction map(Recipe recipe, IRInstruction* instr) {
            foreach (variable; (*instr).get_variables()) {
                if (variable !in variable_birth) {
                    variable_birth[variable] = index;
                }

                variable_death[variable] = index;
            }

            index++;

            return RecipeAction.DoNothing();
        }

        public void reset() {
            variable_birth.clear();
            variable_death.clear();
            index = 0;
        }
    }

    final class ColorGraph : RecipeMap {
        int[IRVariable] variable_birth;
        int[IRVariable] variable_death;

        int index = 0;

        HostReg[] free_registers = [
            HostReg.RAX,
            HostReg.RCX,
            HostReg.RDX,
            HostReg.RBX,
            HostReg.RSP,
            HostReg.RBP,
            HostReg.RSI,
            HostReg.RDI,
            HostReg.R8,
            HostReg.R9,
            HostReg.R10,
            HostReg.R11,
            HostReg.R12,
            HostReg.R13,
            HostReg.R14,
            HostReg.R15
        ];

        HostReg[] assigned_registers;

        IRVariable[] assigned_variables;

        override public RecipeAction map(Recipe recipe, IRInstruction* instr) {
            foreach (variable; (*instr).get_variables()) {
                if (variable_birth[variable] == index && !recipe.has_register_assignment(variable)) {
                    if (free_registers.empty()) {
                        error_jit("fuck.");
                    }

                    HostReg assigned_reg = free_registers[0];
                    free_registers = free_registers[1..$];
                    recipe.assign_register(variable, assigned_reg);

                }

                if (variable_death[variable] == index) {
                    free_registers ~= recipe.get_register_assignment(variable);

                    foreach (reg; assigned_registers) {
                        free_registers = free_registers.filter!(x => x != reg).array;
                    }
                    log_jit("remaining registers: %s %s", free_registers, variable);
                    
                }
            }

            index++;

            return RecipeAction.DoNothing();
        }
        
        public void enforce_invariant(Recipe recipe) {
            foreach (variable1; recipe.get_variables()) {
            foreach (variable2; recipe.get_variables()) {
                if (variable1 == variable2) continue;

                if (variable_birth[variable1] < variable_death[variable2] && variable_birth[variable2] < variable_death[variable1]) {
                    auto reg1 = recipe.get_register_assignment(variable1);
                    auto reg2 = recipe.get_register_assignment(variable2);

                    if (reg1 == reg2) {
                        import std.conv;

                        log_jit(recipe.to_string());
                        log_jit("lifetimes: " ~ to!string(variable_birth[variable1]) ~ " " ~ to!string(variable_death[variable1]) ~ " " ~ to!string(variable_birth[variable2]) ~ " " ~ to!string(variable_death[variable2]));
                        error_jit("Invalid register allocation: " ~ variable1.to_string() ~ " and " ~ variable2.to_string() ~ " are both assigned to " ~ to!string(reg1) ~ " but their lifetimes overlap.");
                    }
                }
            }
            }
        }

        public void init(int[IRVariable] variable_birth, int[IRVariable] variable_death, HostReg[] restricted_registers, HostReg[] assigned_registers) {
            this.variable_birth = variable_birth;
            this.variable_death = variable_death;

            foreach (reg; restricted_registers) {
                free_registers = free_registers.filter!(x => x != reg).array;
            }

            foreach (reg; assigned_registers) {
                free_registers = free_registers.filter!(x => x != reg).array;
            }

            foreach (reg; free_registers) {
                import std.conv;
                log_jit("Free register: " ~ to!string(reg));
            }

            // TODO: fix this shit
            this.assigned_registers = assigned_registers;
        }

        public void reset() {
            this.index = 0;
        }
    }

    CollectLifetimes lifetimes;
    ColorGraph graph_colorer;

    this() {
        this.lifetimes = new CollectLifetimes();
        this.graph_colorer = new ColorGraph();
    }

    public void reset() {
        this.lifetimes.reset();
        this.graph_colorer.reset();
    }

    override public void pass(Recipe recipe) {
        recipe.map(this.lifetimes);
        graph_colorer.init(
            lifetimes.variable_birth, 
            lifetimes.variable_death,
            [HostReg.RSP, HostReg.RBP, HostReg.RDI, HostReg.R14, HostReg.R15],
            recipe.get_all_assigned_registers()
        );

        recipe.map(graph_colorer);

        graph_colorer.enforce_invariant(recipe);
    }
}
