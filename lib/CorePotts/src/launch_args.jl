# Kernel arguments converted once. KernelAbstractions converts every argument at every
# launch (on ROCm, `rocconvert`: a walk over every field, with one entry per device array in
# the launch's list of buffers), even when the argument is already in device form. A large
# `NamedTuple` of run-constant arguments then costs host time on every launch, about 2.3 µs
# per state array on ROCm. The run-constant part is converted once at setup; a launch
# converts only its few round values.

"""
Kernel arguments that a launch converts in part: `once`, converted once (`argconvert`),
and `round`, a few values converted at every launch. A kernel reads the fields of both
as those of `merge(once, round)`. KernelAbstractions converts every argument at every
launch, a walk over all of its fields; a large `NamedTuple` of arguments costs host time
per launch even when it is already in device form, and this type's conversion skips it.

The converted arrays are not kept alive by the result: the owner of the original arguments
keeps them while the result is used.
"""
struct _LaunchArgs{X, R <: NamedTuple}
    once::X
    round::R
end

"""`args` converted once for the kernel `k`'s backend, with no round values."""
_launch_args(k, args) = _LaunchArgs(KernelAbstractions.argconvert(k, args), (;))

"""The converted arguments `a` with the round values `round` (a `NamedTuple`)."""
_with_round(a::_LaunchArgs, round::NamedTuple) = _LaunchArgs(getfield(a, :once), round)

function Adapt.adapt_structure(to, a::_LaunchArgs)
    return _LaunchArgs(getfield(a, :once), Adapt.adapt(to, getfield(a, :round)))
end

@inline function Base.getproperty(a::_LaunchArgs, k::Symbol)
    r = getfield(a, :round)
    return isdefined(r, k) ? getfield(r, k) : getproperty(getfield(a, :once), k)
end
Base.propertynames(a::_LaunchArgs) =
    (propertynames(getfield(a, :once))..., propertynames(getfield(a, :round))...)
