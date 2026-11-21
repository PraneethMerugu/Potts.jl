# The tstops of an owned run for DiffEqBase's accessors: DiffEqCallbacks' periodic and
# iterative callbacks read them (`get_tstops_max`) to stop scheduling past the time span.
module LatticeFieldsDiffEqBaseExt

using DiffEqBase: DiffEqBase
using LatticeFields: Problems

DiffEqBase.get_tstops(i::Problems.FieldIntegrator) = getfield(i, :tstops)
DiffEqBase.get_tstops_array(i::Problems.FieldIntegrator) = getfield(i, :tstops)
function DiffEqBase.get_tstops_max(i::Problems.FieldIntegrator)
    return max(getfield(i, :tend), maximum(getfield(i, :tstops); init = -Inf))
end

end # module LatticeFieldsDiffEqBaseExt
