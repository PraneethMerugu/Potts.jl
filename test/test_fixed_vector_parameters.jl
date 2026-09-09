isdefined(@__MODULE__, :_fixed_vector_parameters_contract) || include("fixtures/vector_parameters.jl")
_fixed_vector_parameters_contract((SequentialCPM(), CheckerboardSweepCPM()), CPUBackend())
