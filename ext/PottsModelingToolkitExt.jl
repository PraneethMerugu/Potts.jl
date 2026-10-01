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
if isdefined(ModelingToolkit, :discrete_compile_pass)      # else `check_compatible` reports it
    ModelingToolkit.discrete_compile_pass(::PottsDiscretePass) = true
end

# Called by MTK for a system whose clock partitions are all discrete.
function (pass::PottsDiscretePass)(_, tss, clocked_inputs, ci, id_to_clock)
    sys = ModelingToolkitBase.with_reversible_transformation(
        pass.sys, ModelingToolkitBase.UnhackSystemTransformation)
    return invoke(ModelingToolkitBase.__mtkcompile, Tuple{ModelingToolkitBase.AbstractSystem}, sys)
end
# Every additional pass also runs on the compiled system; systems MTK compiled itself
# (`ShiftIndex(t, 0)`: no clock partitioning needed) pass through unchanged.
(pass::PottsDiscretePass)(sys) = sys

# The MTK internals this extension relies on, checked once (not by relabelling errors).
const _HOOKS = (isdefined(ModelingToolkit, :discrete_compile_pass) &&
                isdefined(ModelingToolkitBase, :with_reversible_transformation) &&
                isdefined(ModelingToolkitBase, :UnhackSystemTransformation) &&
                isdefined(ModelingToolkitBase, :__mtkcompile) &&
                hasmethod(ModelingToolkitBase.__mtkcompile, Tuple{ModelingToolkitBase.AbstractSystem}))

"""Throw if the loaded ModelingToolkit lacks the discrete-compilation hook this extension uses."""
function check_compatible()
    _HOOKS || throw(ErrorException("PottsModelingToolkitExt is incompatible with ModelingToolkit " *
                                   "v$(pkgversion(ModelingToolkit)): its discrete-compilation hook " *
                                   "(`discrete_compile_pass`, MTKBase `__mtkcompile`) is missing or changed"))
    return nothing
end

"""
`mtkcompile` of a discrete component with full ModelingToolkit loaded.
"""
function compile_discrete(sys)
    ModelingToolkitBase.mtkcompile(sys; additional_passes = Any[PottsDiscretePass(sys)])
end

end
