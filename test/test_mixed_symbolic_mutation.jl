include("fixtures/mixed_symbolic_mutation.jl")
_mixed_symbolic_mutation_contract((SequentialCPM(), CheckerboardSweepCPM()), CPUBackend())
