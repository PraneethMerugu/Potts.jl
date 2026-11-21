# The pending tstops of a Potts run for DiffEqBase's accessors: DiffEqCallbacks' periodic
# and iterative callbacks read them (`get_tstops_max`) to stop scheduling past the time
# span.
module CorePottsDiffEqBaseExt

using CorePotts: PottsIntegrator
using DiffEqBase: DiffEqBase

DiffEqBase.get_tstops(i::PottsIntegrator) = i.opts.tstops
DiffEqBase.get_tstops_array(i::PottsIntegrator) = i.opts.tstops
function DiffEqBase.get_tstops_max(i::PottsIntegrator)
    return max(i.tstop, maximum(i.opts.tstops; init = typemin(Int)))
end

end # module CorePottsDiffEqBaseExt
