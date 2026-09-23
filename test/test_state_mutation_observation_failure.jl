include("fixtures/symbolic_mutation_observation_failure.jl")
_symbolic_mutation_refresh_failure_contract((SequentialCPM(), CheckerboardSweepCPM()), CPUBackend())
