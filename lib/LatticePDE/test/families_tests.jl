# F4-01 (F4 design §3.2, rulings Q-B and Q1): `discretize` returns one SciML problem (an
# `ODEProblem` of rates, a `DiscreteProblem` of maps) that the field algorithms and
# OrdinaryDiffEq's solvers both take; `FieldAlgorithm <: SciMLBase.AbstractODEAlgorithm`; the
# compiled right side is built at its first call only; the `problem` keyword is deleted.
# Negative controls (the base 3ed05c3b): `ExplicitEuler <: AbstractDEAlgorithm` was false, and
# the right side was built at `discretize` (one build before any solve).
# This file at F4-00: 3 pass, 3 fail, 5 errors (every testset fails).

@testsetup module LP_families
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
include("shared/problems.jl")
include("shared/families.jl")
include("shared/export_all.jl")
end

@testitem "F4-01: one problem per family; the field algorithms equal the base's owned solves" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01: one problem per family; the field algorithms equal the base's owned solves" begin
    @test ExplicitEuler <: SciMLBase.AbstractODEAlgorithm && LFP.FieldAlgorithm <: SciMLBase.AbstractODEAlgorithm
    for (name, sys, alg) in FAM_CASES
        prob = discretize(sys, fam_disc())
        @test prob isa (name == "ExplicitMap" ? SciMLBase.DiscreteProblem : SciMLBase.ODEProblem)
        name == "ExplicitMap" || @test SciMLBase.problem_type(prob) isa LFP.LatticeMetadata
        s = solve(prob, alg)
        @test s.retcode == SciMLBase.ReturnCode.Success
        @test fam_digest(s.u[end]) == FAM_PINS[name] || (println("F4-01 pin ", name, " ", fam_digest(s.u[end])); false)
        # an owned solve never builds the right side of SciML's solvers
        @test LFP.lattice_metadata(prob).builds[] == 0
    end
end
end

@testitem "F4-01: OrdinaryDiffEq's solvers on the same problem" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01: OrdinaryDiffEq's solvers on the same problem" begin
    prob = discretize(fam_rate, fam_disc())
    m = LFP.lattice_metadata(prob)
    be = solve(prob, BackwardEuler(; dt = 1e-4, inner = FAM_INNER))
    @test m.builds[] == 0
    for alg in (Tsit5(), Rodas5P(), FBDF())
        s = solve(prob, alg; abstol = 1e-9, reltol = 1e-9)
        @test SciMLBase.successful_retcode(s) && s.t[end] == 0.2
        @test maximum(abs, s.u[end] .- be.u[end]) < 1e-3 || (println("F4-01 ", nameof(typeof(alg)), " vs BE ",
            maximum(abs, s.u[end] .- be.u[end])); false)
    end
    @test m.builds[] == 1                                      # built once, at the first call
    # an ensemble of the problem (R1: a `problem_type` other than `StandardODEProblem`)
    ks = [0.5, 1.0, 2.0]
    ep = SciMLBase.EnsembleProblem(prob; prob_func = (q, c) -> remake(q; p = [fk => ks[c.sim_id]]))
    es = solve(ep, Tsit5(), SciMLBase.EnsembleSerial(); trajectories = 3, abstol = 1e-9, reltol = 1e-9)
    for i in 1:3
        r = solve(remake(prob; p = [fk => ks[i]]), Tsit5(); abstol = 1e-9, reltol = 1e-9)
        @test es.u[i].u[end] == r.u[end]
    end
    @test es.u[1].u[end] != es.u[3].u[end]                     # control: the trajectories differ
    # the same problem, then a field algorithm again: the plans are the problem's
    @test solve(prob, BackwardEuler(; dt = 1e-4, inner = FAM_INNER)).u[end] == be.u[end]
end
end

@testitem "F4-01: the default algorithm (Q1), the map's function, the deleted keyword" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01: the default algorithm (Q1), the map's function, the deleted keyword" begin
    # rates: `ExplicitEuler()`, which needs `dt` without a clock
    prob = discretize(fam_rate, fam_disc())
    @test occursin("needs `dt`", fmsg(() -> solve(prob)))
    pc = discretize(fam_rate, LatticeDiscretization(Grid((8, 8)); T = Float64, clock = 0.01))
    @test solve(pc).u[end] == solve(pc, ExplicitEuler()).u[end]
    # maps: `ExplicitMap()`; the problem's function is one map step (`FunctionMap`'s call)
    pm = discretize(fam_map, fam_disc())
    sm = solve(pm)
    @test sm.u[end] == solve(pm, ExplicitMap()).u[end]
    un = similar(pm.u0)
    pm.f(un, pm.u0, pm.p, 0.0)
    @test un ≈ solve(remake(pm; tspan = (0.0, 1.0)), ExplicitMap()).u[end] atol = 1e-14
    @test un != pm.u0                                          # control: one step moves the state
    # `problem` is no keyword: a plain refusal of an unknown keyword (no shim)
    e = fmsg(() -> LatticeDiscretization(Grid((8, 8)); problem = :owned))
    @test occursin("got `problem`", e) && occursin("`clock`", e)
end
end

@testitem "F4-01: a state on another backend is refused, naming both (SX-12)" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01: a state on another backend is refused, naming both (SX-12)" begin
    prob = discretize(fam_rate, fam_disc())
    e = fmsg(() -> remake(prob; u0 = FamDevVec(zeros(64))))
    @test occursin("u0 is on the backend FamFakeGPU", e) && occursin("the problem's backend is CPU", e)
    @test remake(prob; u0 = zeros(64)).u0 == zeros(64)        # control: a host state
end
end
