# Shared aliases only. Final Stage witnesses own their fixtures locally.
const LM = LocalMath
const KA = LocalMath.KernelAbstractions

"""Return a Stage admission through the sole production planning entrance."""
function _test_stage_admission(bound; backend, index::Integer = 1)
    plan = LocalMath.plan(bound; backend)
    entries = LocalMath._logical_lowering_entries(plan.lowering)
    1 <= index <= length(entries) || throw(BoundsError(entries, index))
    return entries[index].admission
end
