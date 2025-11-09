module emu.hw.broadway.jit.emission.emission_action;

import gallinule.x86;
import util.number;
import util.log;

enum EmissionActionType {
    Continue,
    DirectBranchTaken,
    IndirectBranchTaken,
    ConditionalDirectBranchTaken,
    ConditionalIndirectBranchTaken,
    ICacheInvalidation,
    CpuHalted,
    DecrementerChanged,
    VolatileStateChanged,
    RanHLEFunction,
    IdleLoopDetected
}

struct EmissionAction {
    public  EmissionActionType type;
    private u32                direct_branch_target;
    private R32                indirect_branch_target;
    private R32                condition_reg;
    private bool               with_link;

    static EmissionAction Continue() {
        EmissionAction action;
        action.type = EmissionActionType.Continue;
        return action;
    }

    static EmissionAction DirectBranchTaken(u32 branch_target, bool with_link) {
        EmissionAction action;
        action.type = EmissionActionType.DirectBranchTaken;
        action.direct_branch_target = branch_target;
        action.with_link = with_link;
        return action;
    }

    static EmissionAction IndirectBranchTaken(R32 reg, bool with_link) {
        EmissionAction action;
        action.type = EmissionActionType.IndirectBranchTaken;
        action.indirect_branch_target = reg;
        action.with_link = with_link;
        return action;
    }

    static EmissionAction ConditionalDirectBranchTaken(R32 condition_reg, u32 branch_target, bool with_link) {
        EmissionAction action;
        action.type = EmissionActionType.ConditionalDirectBranchTaken;
        action.condition_reg = condition_reg;
        action.direct_branch_target = branch_target;
        action.with_link = with_link;
        return action;
    }

    static EmissionAction ConditionalIndirectBranchTaken(R32 condition_reg, R32 branch_target, bool with_link) {
        EmissionAction action;
        action.type = EmissionActionType.ConditionalIndirectBranchTaken;
        action.condition_reg = condition_reg;
        action.indirect_branch_target = branch_target;
        action.with_link = with_link;
        return action;
    }

    static EmissionAction ICacheInvalidation() {
        EmissionAction action;
        action.type = EmissionActionType.ICacheInvalidation;
        return action;
    }

    static EmissionAction CpuHalted() {
        EmissionAction action;
        action.type = EmissionActionType.CpuHalted;
        return action;
    }

    static EmissionAction DecrementerChanged() {
        EmissionAction action;
        action.type = EmissionActionType.DecrementerChanged;
        return action;
    }

    static EmissionAction VolatileStateChanged() {
        EmissionAction action;
        action.type = EmissionActionType.VolatileStateChanged;
        return action;
    }

    static EmissionAction RanHLEFunction() {
        EmissionAction action;
        action.type = EmissionActionType.RanHLEFunction;
        return action;
    }

    static EmissionAction IdleLoopDetected() {
        EmissionAction action;
        action.type = EmissionActionType.IdleLoopDetected;
        return action;
    }

    u32 get_direct_branch_target() {
        if (type != EmissionActionType.DirectBranchTaken && type != EmissionActionType.ConditionalDirectBranchTaken) {
            error_jit("get_direct_branch_target is only valid for DirectBranchTaken and ConditionalDirectBranchTaken");
        }

        return direct_branch_target;
    }

    R32 get_indirect_branch_target() {
        if (type != EmissionActionType.IndirectBranchTaken && type != EmissionActionType.ConditionalIndirectBranchTaken) {
            error_jit("get_indirect_branch_target is only valid for IndirectBranchTaken and ConditionalIndirectBranchTaken");
        }

        return indirect_branch_target;
    }

    R32 get_condition_reg() {
        if (type != EmissionActionType.ConditionalDirectBranchTaken && type != EmissionActionType.ConditionalIndirectBranchTaken) {
            error_jit("get_condition_reg is only valid for ConditionalDirectBranchTaken and ConditionalIndirectBranchTaken");
        }

        return condition_reg;
    }

    bool is_with_link() {
        if (type != EmissionActionType.ConditionalDirectBranchTaken && 
            type != EmissionActionType.ConditionalIndirectBranchTaken &&
            type != EmissionActionType.DirectBranchTaken &&
            type != EmissionActionType.IndirectBranchTaken) {
            error_jit("is_with_link is only valid for ConditionalDirectBranchTaken and ConditionalIndirectBranchTaken");
        }

        return with_link;
    }
}