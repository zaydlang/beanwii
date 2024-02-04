module emu.hw.broadway.jit.ir.recipe;

import emu.hw.broadway.jit.common.guest_reg;
import emu.hw.broadway.jit.ir.instruction;
import emu.hw.broadway.jit.ir.types;
import std.container.dlist;
import std.format;
import std.sumtype;

alias RecipeAction = SumType!(
    RecipeActionInsertAfter,
    RecipeActionInsertBefore,
    RecipeActionRemove,
    RecipeActionReplace,
    RecipeActionDoNothing
);

struct RecipeActionInsertAfter {
    IRInstruction instr;
    IRInstruction[] new_instrs;
}

struct RecipeActionInsertBefore {
    IRInstruction instr;
    IRInstruction[] new_instrs;
}

struct RecipeActionRemove {
    IRInstruction instr;
}

struct RecipeActionReplace {
    IRInstruction instr;
    IRInstruction[] new_instrs;
}

struct RecipeActionDoNothing {
}

interface RecipeMap {
    RecipeAction func(IRInstruction instr);
}

final class IRInstructionLinkedListElement {
    public IRInstruction instr;
    public IRInstructionLinkedListElement next;
    public IRInstructionLinkedListElement prev;

    this(IRInstruction instr) {
        this.instr = instr;
    }
}

static IRInstructionLinkedListElement linked_list_element_from_instruction(IRInstruction* instr) {
    return cast(IRInstructionLinkedListElement) (instr + IRInstruction.sizeof);
}

final class IRInstructionLinkedList {
    private IRInstructionLinkedListElement head;
    private IRInstructionLinkedListElement tail;
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
        IRInstructionLinkedListElement new_element = new IRInstructionLinkedListElement(instr);
        if (head is null) {
            head = new_element;
            tail = new_element;
        } else {
            tail.next = new_element;
            new_element.prev = tail;
            tail = new_element;
        }

        this.length += 1;
    }

    public void insertAfter(IRInstruction instr, IRInstruction[] new_instrs) {
        IRInstructionLinkedListElement element = linked_list_element_from_instruction(&instr);
        IRInstructionLinkedListElement next = element.next;
        foreach (new_instr; new_instrs) {
            IRInstructionLinkedListElement new_element = new IRInstructionLinkedListElement(new_instr);
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

    public void insertBefore(IRInstruction instr, IRInstruction[] new_instrs) {
        IRInstructionLinkedListElement element = linked_list_element_from_instruction(&instr);
        IRInstructionLinkedListElement prev = element.prev;
        foreach (new_instr; new_instrs) {
            IRInstructionLinkedListElement new_element = new IRInstructionLinkedListElement(new_instr);
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

    public void remove(IRInstruction instr) {
        IRInstructionLinkedListElement element = linked_list_element_from_instruction(&instr);
        IRInstructionLinkedListElement prev = element.prev;
        IRInstructionLinkedListElement next = element.next;
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

    public void replace(IRInstruction instr, IRInstruction[] new_instrs) {
        insertAfter(instr, new_instrs);
        remove(instr);
    }
}

final class Recipe {
    private IRInstructionLinkedList instructions;

    this(IRInstruction[] instrs) {
        instructions = new IRInstructionLinkedList(instrs);
    }

    public void insert_after(IRInstruction instr, IRInstruction[] new_instrs) {
        instructions.insertAfter(instr, new_instrs);
    }

    public void insert_before(IRInstruction instr, IRInstruction[] new_instrs) {
        instructions.insertBefore(instr, new_instrs);
    }

    public void remove(IRInstruction instr) {
        instructions.remove(instr);
    }

    public void replace(IRInstruction instr, IRInstruction[] new_instrs) {
        instructions.insertAfter(instr, new_instrs);
        instructions.remove(instr);
    }

    public void map(RecipeMap recipe_map) {
        auto element = instructions.head;
        while (element !is null) {
            RecipeAction action = recipe_map.func(element.instr);
            action.match!(
                (RecipeActionInsertAfter action) {
                    insert_after(action.instr, action.new_instrs);
                },
                (RecipeActionInsertBefore action) {
                    insert_before(action.instr, action.new_instrs);
                },
                (RecipeActionRemove action) {
                    remove(action.instr);
                },
                (RecipeActionReplace action) {
                    replace(action.instr, action.new_instrs);
                },
                (RecipeActionDoNothing action) {
                }
            );

            element = element.next;
        }
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

        result ~= "\0";

        return result;
    }

    private string to_string(IRInstruction instruction) {
        return instruction.match!(
            (IRInstructionGetReg i) {
                return format("ld  v%d, %s", i.dest.get_id(), i.src.to_string());
            },

            (IRInstructionSetRegVar i) {
                return format("st  v%d, %s", i.src.get_id(), i.dest.to_string());
            },

            (IRInstructionSetRegImm i) {
                return format("st  #0x%x, %s", i.imm, i.dest.to_string());
            },

            (IRInstructionSetFPSCR i) {
                return format("st  v%d, FPSCR", i.src.get_id());
            },

            (IRInstructionBinaryDataOpImm i) {
                return format("%s v%d, v%d, 0x%x", i.op.to_string(), i.dest.get_id(), i.src1.get_id(), i.src2);
            },

            (IRInstructionBinaryDataOpVar i) {
                return format("%s v%d, v%d, v%d", i.op.to_string(), i.dest.get_id(), i.src1.get_id(), i.src2.get_id());
            },

            (IRInstructionUnaryDataOp i) {
                return format("%s v%d, v%d", i.op.to_string(), i.dest.get_id(), i.src.get_id());
            },

            (IRInstructionSetVarImmInt i) {
                return format("ld  v%d, 0x%x", i.dest.get_id(), i.imm);
            },

            (IRInstructionSetVarImmFloat i) {
                return format("ld  v%d, %f", i.dest.get_id(), i.imm);
            },

            (IRInstructionRead i) {
                string mnemonic;
                final switch (i.size) {
                    case 8: mnemonic = "ldd"; break;
                    case 4: mnemonic = "ldw"; break;
                    case 2: mnemonic = "ldh"; break;
                    case 1: mnemonic = "ldb"; break;
                }
                
                return format("%s  r%d, [v%d]", mnemonic, i.dest.get_id(), i.address.get_id());
            },

            (IRInstructionWrite i) {
                string mnemonic;
                final switch (i.size) {
                    case 8: mnemonic = "std"; break;
                    case 4: mnemonic = "stw"; break;
                    case 2: mnemonic = "sth"; break;
                    case 1: mnemonic = "stb"; break;
                }
                
                return format("%s  r%d, [v%d]", mnemonic, i.dest.get_id(), i.address.get_id());
            },

            (IRInstructionConditionalBranch i) {
                return format("bne v%d, #%d", i.cond.get_id(), i.after_true_label.instruction_index);
            },

            (IRInstructionBranch i) {
                return format("b   #%d", i.label.instruction_index);
            },

            (IRInstructionGetHostCarry i) {
                return format("getc v%d", i.dest.get_id());
            },

            (IRInstructionGetHostOverflow i) {
                return format("getv v%d", i.dest.get_id());
            },

            (IRInstructionHleFunc i) {
                return format("hle %d", i.function_id);
            },

            (IRInstructionPairedSingleMov i) {
                return format("mov ps%d:%d, ps%d", i.dest.get_id(), i.index, i.src.get_id());
            },

            (IRInstructionReadSized i) {
                return format("ld  v%d, [v%d] (size: %d)", i.dest.get_id(), i.address.get_id(), i.size.get_id());
            },

            (IRInstructionDebugAssert i) {
                return format("assert v%d", i.cond.get_id());
            },

            (IRInstructionSext i) {
                return format("sext v%d, v%d, %d", i.dest.get_id(), i.src.get_id(), i.bits);
            },

            (IRInstructionBreakpoint i) {
                return format("bkpt");
            },
        );
    }
}
