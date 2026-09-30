# Gap G1 of discrete components (P6.0k, D-065 Q9): loading full ModelingToolkit replaces
# ModelingToolkitBase's structural simplification (`__mtkcompile`) with its own, which rejects
# clocked discrete systems ("Discrete systems with multiple clocks are not supported with the
# standard MTK compiler") unless a pass declares `ModelingToolkit.discrete_compile_pass`. This
# extension supplies that pass: it compiles the system as ModelingToolkitBase does (lag
# unknowns, `Shift(t, 1)(xₜ₋₁) ~ x`, observed rules), so a discrete component lowers the same
# with or without ModelingToolkit loaded. The hook and the MTKBase method it re-enters are MTK
# internals (pinned by `test/mtk_extension.jl`).
module PottsModelingToolkitExt

using ModelingToolkit: ModelingToolkit
using ModelingToolkitBase: ModelingToolkitBase

"""
MTK's discrete-compilation hook: compile the (whole, single-clock) system with MTKBase's rules.
"""
struct PottsDiscretePass
    sys::Any
end
ModelingToolkit.discrete_compile_pass(::PottsDiscretePass) = true

# Called by MTK for a system whose clock partitions are all discrete.
function (pass::PottsDiscretePass)(_, tss, clocked_inputs, ci, id_to_clock)
    sys = ModelingToolkitBase.with_reversible_transformation(
        pass.sys, ModelingToolkitBase.UnhackSystemTransformation)
    return invoke(ModelingToolkitBase.__mtkcompile, Tuple{ModelingToolkitBase.AbstractSystem}, sys)
end
# Every additional pass also runs on the compiled system; systems MTK compiled itself
# (`ShiftIndex(t, 0)`: no clock partitioning needed) pass through unchanged.
(pass::PottsDiscretePass)(sys) = sys

"""
`mtkcompile` of a discrete component with full ModelingToolkit loaded.
"""
function compile_discrete(sys)
    ModelingToolkitBase.mtkcompile(sys; additional_passes = Any[PottsDiscretePass(sys)])
end

end
