module emu.hw.broadway.jit.passes.insert_push_pop.pass;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.recipe;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.x86;

import std.algorithm;
import std.array;
import std.sumtype;

final class InsertPushPop : RecipePass {
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

    final class InsertPushPopMap : RecipeMap {
        int[IRVariable] variable_birth;
        int[IRVariable] variable_death;
        int index = 0;

        private RecipeAction insert_push_pop_around(Recipe recipe, IRInstruction instr, int index) {
            IRInstruction[] instructions = [ instr];

            foreach (variable; recipe.get_variables()) {
                auto birth = variable_birth[variable];
                auto death = variable_death[variable];

                if (birth < index && index < death) {
                    auto var = recipe.get_register_assignment(variable);
                    if (var.is_caller_save) {
                        instructions = [
                            Instruction.Push(var)
                        ] ~ instructions ~ [
                            Instruction.Pop(var)
                        ];
                    }
                }
            }

            return RecipeAction.Replace(instructions);
        }

        override public RecipeAction map(Recipe recipe, IRInstruction* instr) {
            auto action = (*instr).match!(
                (IRInstructionRead r) => insert_push_pop_around(recipe, cast(IRInstruction) r, index),
                (IRInstructionWrite w) => insert_push_pop_around(recipe, cast(IRInstruction) w, index),
                (IRInstructionReadSized r) => insert_push_pop_around(recipe, cast(IRInstruction) r, index),
                (_) => RecipeAction.DoNothing()
            );

            index++;
            return action;
        }

        public void init(int[IRVariable] variable_birth, int[IRVariable] variable_death) {
            this.variable_birth = variable_birth;
            this.variable_death = variable_death;
        }

        public void reset() {
            this.index = 0;
        }
    }

    CollectLifetimes lifetimes;
    InsertPushPopMap insert_push_pop_map;

    this() {
        this.lifetimes = new CollectLifetimes();
        this.insert_push_pop_map = new InsertPushPopMap();
    }

    public void reset() {
        this.lifetimes.reset();
        this.insert_push_pop_map.reset();
    }

    override public void pass(Recipe recipe) {
        recipe.map(this.lifetimes);
        
        insert_push_pop_map.init(
            lifetimes.variable_birth, 
            lifetimes.variable_death,
        );
        recipe.map(insert_push_pop_map);

        HostReg[] callee_save_registers = recipe.get_variables()
            .map!(v => recipe.get_register_assignment(v))
            .filter!(r => r.is_callee_save)
            .array();
        
        foreach (reg; callee_save_registers) {
            recipe.prepend(Instruction.Push(reg));
            recipe.append(Instruction.Pop(reg));
        }
    }
}
