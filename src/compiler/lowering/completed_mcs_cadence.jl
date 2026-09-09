# One cadence conversion shared by sampled history and lifecycle processes.
function _completed_mcs_cadence(value)
    value isa EveryMCS && return (CorePotts.CompilerSPI.EveryMCSCadence, Int64(1))
    value isa AtMCS && return (CorePotts.CompilerSPI.AtMCSCadence, Int64(value.mcs))
    value isa Every && return (CorePotts.CompilerSPI.PeriodicMCSCadence, Int64(value.cadence))
    throw(ArgumentError("unsupported compiled completed-MCS cadence $(typeof(value))"))
end
