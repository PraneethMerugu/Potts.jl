"""Device-safe scientific state viewed at the MCS being evaluated."""
struct _LifecycleEvaluationState{S}
    state::S
    mcs::Int
end

@inline function Base.getproperty(view::_LifecycleEvaluationState, name::Symbol)
    name === :mcs && return getfield(view, :mcs)
    return getproperty(getfield(view, :state), name)
end

@inline _lifecycle_evaluation_state(state, mcs::Int64) =
    _LifecycleEvaluationState(state, Int(mcs))
