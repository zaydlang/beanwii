module emu.hw.broadway.jit.ir.recipe;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.types;
import emu.hw.broadway.jit.x86;
import std.container.dlist;
import std.format;
import std.sumtype;
import util.log;

struct RecipeAction {
    alias Inner = SumType!(
        RecipeActioninsert_after,
        RecipeActioninsert_before,
        RecipeActionRemove,
        RecipeActionReplace,
        RecipeActionDoNothing
    );

    Inner inner;
    alias inner this;

    static RecipeAction insert_after(IRInstruction[] new_instrs) {
        return RecipeAction(Inner(RecipeActioninsert_after(new_instrs)));
    }

    static RecipeAction insert_before(IRInstruction[] new_instrs) {
        return RecipeAction(Inner(RecipeActioninsert_before(new_instrs)));
    }

    static RecipeAction Remove() {
        return RecipeAction(Inner(RecipeActionRemove()));
    }

    static RecipeAction Replace(IRInstruction[] new_instrs) {
        return RecipeAction(Inner(RecipeActionReplace(new_instrs)));
    }

    static RecipeAction DoNothing() {
        return RecipeAction(Inner(RecipeActionDoNothing()));
    }
}

struct RecipeActioninsert_after {
    IRInstruction[] new_instrs;
}

struct RecipeActioninsert_before {
    IRInstruction[] new_instrs;
}

struct RecipeActionRemove {
}

struct RecipeActionReplace {
    IRInstruction[] new_instrs;
}

struct RecipeActionDoNothing {
}

interface RecipePass {
    void pass(Recipe recipe);
}

interface RecipeMap {
    RecipeAction map(Recipe recipe, IRInstruction* instr);
}

struct IRInstructionLinkedListElement {
    public IRInstruction instr;
    public IRInstructionLinkedListElement* next;
    public IRInstructionLinkedListElement* prev;

    this(IRInstruction instr) {
        this.instr = instr;
        this.next  = null;
        this.prev  = null;
    }
}

static IRInstructionLinkedListElement* linked_list_element_from_instruction(IRInstruction* instr) {
    return cast(IRInstructionLinkedListElement*) (cast(void*) instr - IRInstructionLinkedListElement.instr.offsetof);
}

final class IRInstructionLinkedList {
    private IRInstructionLinkedListElement* head;
    private IRInstructionLinkedListElement* tail;
    private size_t length;

    this(IRInstruction[] instrs) {
        this.head = null;
        this.tail = null;
        this.length = 0;

        foreach (instr; instrs) {
            this.append(instr);
        }
    }

    public void append(IRInstruction instr) {
        IRInstructionLinkedListElement* element = new IRInstructionLinkedListElement(instr);
        if (head is null) {
            head = element;
            tail = element;
        } else {
            tail.next = element;
            element.prev = tail;
            tail = element;
        }
    }

    public void prepend(IRInstruction instr) {
        IRInstructionLinkedListElement* element = new IRInstructionLinkedListElement(instr);
        if (head is null) {
            head = element;
            tail = element;
        } else {
            head.prev = element;
            element.next = head;
            head = element;
        }
    }

    public void insert_after(IRInstruction* instr, IRInstruction[] new_instrs) {
        IRInstructionLinkedListElement* element = linked_list_element_from_instruction(instr);
        IRInstructionLinkedListElement* next = element.next;
        foreach (new_instr; new_instrs) {
            IRInstructionLinkedListElement* new_element = new IRInstructionLinkedListElement(new_instr);
            new_element.prev = element;
            new_element.next = next;
            element.next = new_element;
            if (next !is null) {
                next.prev = new_element;
            }
            if (tail == element) {
                tail = new_element;
            }
            element = new_element;
        }

        this.length += new_instrs.length;
    }

    public void insert_before(IRInstruction* instr, IRInstruction[] new_instrs) {
        IRInstructionLinkedListElement* element = linked_list_element_from_instruction(instr);
        IRInstructionLinkedListElement* prev = element.prev;
        foreach (new_instr; new_instrs) {
            IRInstructionLinkedListElement* new_element = new IRInstructionLinkedListElement(new_instr);
            new_element.prev = prev;
            new_element.next = element;
            element.prev = new_element;
            if (prev !is null) {
                prev.next = new_element;
            }
            if (head == element) {
                head = new_element;
            }
            element = new_element;
        }

        this.length += new_instrs.length;
    }

    public void remove(IRInstruction* instr) {
        IRInstructionLinkedListElement* element = linked_list_element_from_instruction(instr);
        IRInstructionLinkedListElement* prev = element.prev;
        IRInstructionLinkedListElement* next = element.next;
        
        if (prev !is null) {
            prev.next = next;
        }

        if (next !is null) {
            next.prev = prev;
        }
        
        if (head == element) {
            head = next;
        }
        
        if (tail == element) {
            tail = prev;
        }

        this.length -= 1;
    }

    public void replace(IRInstruction* instr, IRInstruction[] new_instrs) {
        IRInstructionLinkedListElement* element = linked_list_element_from_instruction(instr);
        IRInstructionLinkedListElement* prev = element.prev;
        IRInstructionLinkedListElement* next = element.next;

        foreach (new_instr; new_instrs) {
            IRInstructionLinkedListElement* new_element = new IRInstructionLinkedListElement(new_instr);
            new_element.prev = prev;
            new_element.next = next;
            
            if (prev !is null) {
                prev.next = new_element;
            }

            if (next !is null) {
                next.prev = new_element;
            }

            if (head == element) {
                head = new_element;
            }

            if (tail == element) {
                tail = new_element;
            }

            prev = new_element;
        }

        this.length += new_instrs.length - 1;
    }
}

final class Recipe {
    private IRInstructionLinkedList instructions;
    private HostReg[IRVariable] reg_allocations;
    private int internal_variable_id;

    this(IRInstruction[] instrs) {
        instructions = new IRInstructionLinkedList(instrs);

        // maybe this shoudl be an assert to make sure there are no conflicts
        // but if theres already 10k internal variables, then we have bigger problems
        internal_variable_id = 10000;
    }

    public IRInstruction* opIndex(size_t index) {
        auto element = instructions.head;
        for (size_t i = 0; i < index; i++) {
            element = element.next;
        }

        return &element.instr;
    }

    public void insert_after(IRInstruction* instr, IRInstruction[] new_instrs) {
        instructions.insert_after(instr, new_instrs);
    }

    public void insert_before(IRInstruction* instr, IRInstruction[] new_instrs) {
        instructions.insert_before(instr, new_instrs);
    }

    public void remove(IRInstruction* instr) {
        instructions.remove(instr);
    }

    public void replace(IRInstruction* instr, IRInstruction[] new_instrs) {
        instructions.replace(instr, new_instrs);
    }

    public void prepend(IRInstruction instr) {
        instructions.prepend(instr);
    }

    public void append(IRInstruction instr) {
        instructions.append(instr);
    }

    public IRVariable[] get_variables() {
        IRVariable[] result;

        auto element = instructions.head;
        while (element !is null) {
            result ~= element.instr.get_variables();
            element = element.next;
        }

        return result;
    }

    public void pass(RecipePass pass) {
        pass.pass(this);
    }

    public void reverse_map(RecipeMap recipe_map) {
        auto element = instructions.tail;

        while (element !is null) {
            RecipeAction action = recipe_map.map(this, &element.instr);

            action.match!(
                (RecipeActioninsert_after action) {
                    insert_after(&element.instr, action.new_instrs);
                },
                (RecipeActioninsert_before action) {
                    insert_before(&element.instr, action.new_instrs);
                },
                (RecipeActionRemove action) {
                    auto prev = element.prev;
                    remove(&element.instr);
                    element = prev;
                },
                (RecipeActionReplace action) {
                    auto prev = element.prev;
                    replace(&element.instr, action.new_instrs);
                    element = element.prev;
                },
                (RecipeActionDoNothing action) {
                    element = element.prev;
                }
            );
        }
    }

    public void map(RecipeMap recipe_map) {
        auto element = instructions.head;

        while (element !is null) {
            RecipeAction action = recipe_map.map(this, &element.instr);

            action.match!(
                (RecipeActioninsert_after action) {
                    insert_after(&element.instr, action.new_instrs);
                },
                (RecipeActioninsert_before action) {
                    insert_before(&element.instr, action.new_instrs);
                },
                (RecipeActionRemove action) {
                    auto next = element.next;
                    remove(&element.instr);
                    element = next;
                },
                (RecipeActionReplace action) {
                    auto next = element.next;
                    replace(&element.instr, action.new_instrs);
                    element = next;
                },
                (RecipeActionDoNothing action) {
                    element = element.next;
                }
            );
        }
    }

    public void assign_register(IRVariable variable, HostReg reg) {
        reg_allocations[variable] = reg;
    }

    public HostReg get_register_assignment(IRVariable variable) {
        return reg_allocations[variable];
    }

    public HostReg[] get_all_assigned_registers() {
        HostReg[] result;

        foreach (key, value; reg_allocations) {
            result ~= value;
        }

        return result;
    }

    public bool has_register_assignment(IRVariable variable) {
        return (variable in reg_allocations) != null;
    }

    public size_t length() {
        return instructions.length;
    }

    public string to_string() {
        string result = "";

        auto element = instructions.head;
        while (element !is null) {
            result ~= format("%s\n", this.to_string(element.instr));
            element = element.next;
        }

        foreach (key, value; reg_allocations) {
            result ~= format("%s -> %s\n", key.to_string(), value);
        }

        result ~= "\0";

        return result;
    }

    public IRVariable fresh_variable() {
        return IRVariable(internal_variable_id++);
    }

    private string to_string(IRInstruction instruction) {
        return instruction.match!(
            (IRInstructionGetReg i) {
                return format("ld  %s, %s", i.dest.to_string(), i.src.to_string());
            },

            (IRInstructionSetReg i) {
                return format("st  %s, %s", i.src.to_string(), i.dest.to_string());
            },

            (IRInstructionSetFPSCR i) {
                return format("st  %s, FPSCR", i.src.to_string());
            },

            (IRInstructionBinaryDataOp i) {
                return format("%s %s, %s, %s", i.op.to_string(), i.dest.to_string(), i.src1.to_string(), i.src2.to_string());
            },

            (IRInstructionUnaryDataOp i) {
                return format("%s %s, %s", i.op.to_string(), i.dest.to_string(), i.src.to_string());
            },

            (IRInstructionSetVarImmInt i) {
                return format("ld  %s, 0x%x", i.dest.to_string(), i.imm);
            },

            (IRInstructionSetVarImmFloat i) {
                return format("ld  %s, %f", i.dest.to_string(), i.imm);
            },

            (IRInstructionRead i) {
                string mnemonic;
                final switch (i.size) {
                    case 8: mnemonic = "ldd"; break;
                    case 4: mnemonic = "ldw"; break;
                    case 2: mnemonic = "ldh"; break;
                    case 1: mnemonic = "ldb"; break;
                }
                
                return format("%s  r%d, [v%d]", mnemonic, i.dest.id, i.address.id);
            },

            (IRInstructionWrite i) {
                string mnemonic;
                final switch (i.size) {
                    case 8: mnemonic = "std"; break;
                    case 4: mnemonic = "stw"; break;
                    case 2: mnemonic = "sth"; break;
                    case 1: mnemonic = "stb"; break;
                }
                
                return format("%s  r%d, [v%d]", mnemonic, i.dest.id, i.address.id);
            },

            (IRInstructionConditionalBranch i) {
                return format("b v%d if v%d else v%d", i.address_if_true.id, i.cond.id, i.address_if_false.id);
            },

            (IRInstructionConditionalBranchWithLink i) {
                return format("bl v%d if v%d else v%d", i.address_if_true.id, i.cond.id, i.address_if_false.id);
            },

            (IRInstructionBranch i) {
                return format("b   #%d", i.label.instruction_index);
            },

            (IRInstructionGetHostCarry i) {
                return format("getc v%d", i.dest.id);
            },

            (IRInstructionGetHostOverflow i) {
                return format("getv v%d", i.dest.id);
            },

            (IRInstructionHleFunc i) {
                return format("hle %d", i.function_id);
            },

            (IRInstructionPairedSingleMov i) {
                return format("mov ps%d:%d, ps%d", i.dest.id, i.index, i.src.id);
            },

            (IRInstructionReadSized i) {
                return format("ld  v%d, [v%d] (size: %d)", i.dest.id, i.address.id, i.size.id);
            },

            (IRInstructionDebugAssert i) {
                return format("assert v%d", i.cond.id);
            },

            (IRInstructionSext i) {
                return format("sext v%d, v%d, %d", i.dest.id, i.src.id, i.bits);
            },

            (IRInstructionBreakpoint i) {
                return format("bkpt");
            },

            (IRInstructionHaltCpu i) {
                return format("halt");
            },

            (IRInstructionPush i) {
                return format("push %s", i.src);
            },

            (IRInstructionPop i) {
                return format("pop %s", i.dest);
            },
        );
    }

    override public bool opEquals(Object other) {
        Recipe other_recipe = cast(Recipe) other;

        if (other_recipe.length() != this.length()) {
            return false;
        }

        auto element = instructions.head;
        auto other_element = other_recipe.instructions.head;
        while (element !is null) {
            if (element.instr != other_element.instr) {
                return false;
            }

            element = element.next;
            other_element = other_element.next;
        }

        foreach (key, value; reg_allocations) {
            if (!other_recipe.has_register_assignment(key)) {
                return false;
            }
            
            if (value != other_recipe.reg_allocations[key]) {
                return false;
            }
        }

        return true;
    }
}
