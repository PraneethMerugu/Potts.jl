isdefined(@__MODULE__, :_vector_parameter_units_and_imports_contract) || include("fixtures/vector_parameters.jl")
_vector_parameter_units_and_imports_contract((SequentialCPM(), CheckerboardSweepCPM()), CPUBackend())
