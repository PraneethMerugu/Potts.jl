@testsetup module LP_qa
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
using JET: JET, @test_opt
using AllocCheck: check_allocs
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "qa_common.jl"))
include("shared/export_all.jl")
end

@testitem "QA" setup = [LP_qa] tags = [:latticepde, :qa] begin
    @testset "QA" begin
        qa_aqua(LatticePDE)
        qa_api_docs(
            LatticePDE;
            docs_dir = joinpath(@__DIR__, "..", "..", "..", "docs"),
            doc_module_names = ["Potts.LatticePDE"]
        )
        # `VarDomainPairing` (what `x ∈ (a, b)` builds) is not declared public by Symbolics.
        # `get_unit` (MTK unit inference, which registered operators extend) is not declared
        # public by ModelingToolkitBase.
        qa_explicit_imports(
            LatticePDE;
            nonpublic_explicit = (:VarDomainPairing,),
            nonpublic_qualified = (:get_unit,)
        )
        qa_source_rules(joinpath(@__DIR__, ".."); exclude_files = [@__FILE__])
    end
end

@testitem "QA: JET and AllocCheck (LatticePDE steppers)" setup = [LP_qa] tags = [:latticepde, :qa] begin
    @testset "QA: JET and AllocCheck (LatticePDE steppers)" begin
        @parameters x y D = 0.01
        @variables u(..)
        sys = PDESystem(
            [Differential(t)(u(t, x, y)) ~ D * Δ(u(t, x, y))],
            [u(0, x, y) ~ 1.0],
            [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
            [t, x, y],
            [u(t, x, y)],
            [D];
            name = :qa_diff,
        )
        grid = Grid((16, 16))
        prob = discretize(sys, LatticeDiscretization(grid; T = Float64))
        for alg in (ExplicitEuler(dt = 0.05, substeps = 2), BackwardEuler(dt = 0.05))
            integ = init(prob, alg; save_start = false, save_everystep = false, save_end = false)
            step!(integ)
            @test_opt target_modules = (LatticePDE,) step!(integ)
            if alg isa ExplicitEuler
                @test minimum((@allocated step!(integ)) for _ in 1:5) == 0
                @test isempty(check_allocs(LatticePDE._symkey, (Symbol,)))
            end
        end
    end
end
