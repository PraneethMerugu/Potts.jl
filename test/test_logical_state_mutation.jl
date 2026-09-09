include(joinpath(@__DIR__, "fixtures", "logical_state_mutation.jl"))

_logical_state_mutation_contract((SequentialCPM(), CheckerboardSweepCPM()), CPUBackend())
