# The precompile workload runs on the current API (owned
# ExplicitEuler and BackwardEuler in Float64 and Float32, one ODE right-side call, the
# solution read by name, `field_report`) without a warning.

@testsetup module LP_precompile
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/export_all.jl")
end

@testitem "the precompile workload runs" setup = [LP_precompile] tags = [:latticepde, :precompile] begin
@testset "the precompile workload runs" begin
    @test (@test_logs min_level = Base.CoreLogging.Warn LatticePDE._precompile_workload()) === nothing
end
end
