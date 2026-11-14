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
# imports an earlier file made in the old single Main
using SciMLBase: ReturnCode
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/families.jl")
include("shared/export_all.jl")
end

@testitem "F4-01: one problem per family; an owned solve builds no right side" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01: one problem per family; an owned solve builds no right side" begin
    @test ExplicitEuler <: SciMLBase.AbstractODEAlgorithm && LFP.FieldAlgorithm <: SciMLBase.AbstractODEAlgorithm
    for (name, sys, alg) in FAM_CASES
        prob = discretize(sys, fam_disc())
        @test prob isa (name == "ExplicitMap" ? SciMLBase.DiscreteProblem : SciMLBase.ODEProblem)
        name == "ExplicitMap" || @test SciMLBase.problem_type(prob) isa LFP.LatticeMetadata
        s = solve(prob, alg)
        @test s.retcode == SciMLBase.ReturnCode.Success
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

# F4-01 (TS2): `FieldGroups`, one of the three cases whose recorded triple was its only value
# check, against an oracle instead. The group cut does not touch a field it does not feed: `u` reads
# nothing but the coordinates, so its trajectory inside the grouped solve is the one it has alone,
# at every save, bitwise.
@testitem "F4-01 (TS2): the group cut leaves a field it does not feed bitwise unchanged" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01 (TS2): the group cut leaves a field it does not feed bitwise unchanged" begin
    fg = FieldGroups(fam_u => ExplicitEuler(; dt = 0.05, substeps = 2),
        fam_v => BackwardEuler(; dt = 0.05, inner = FAM_INNER))
    sg = solve(discretize(fam_chain, fam_disc()), fg)
    uonly = PDESystem([D(fam_u) ~ fDc * Δ(fam_u) - fk * fam_u], [fu(0, x, y) ~ x; fam_faces], fam_dom, [t, x, y],
        [fam_u], [fDc, fk]; name = :famu)
    su = solve(discretize(uonly, fam_disc()), ExplicitEuler(; dt = 0.05, substeps = 2))
    @test length(su.t) == length(sg.t) && su.t == sg.t
    bad = [k for k in eachindex(su.t) if !(Array(sg[fam_u, k]) == Array(su[fam_u, k]))]
    @test isempty(bad) || (println("F4-01 TS2 grouped u differs at ", bad); false)
    @test Array(sg[fam_u, end]) != Array(sg[fam_v, end])          # control: the two fields differ
end
end

# F4-01 (TS2): `ExplicitMap`, the second case whose recorded triple was its only value check. The
# map is `(N(x + h) + N(x - h)) / 2`; `fam_map` gives no boundary rule, so a read beyond a face takes
# 0 (measured at `9adc2be7`: the first and last cell of a column average with 0, the interior cells
# average their two neighbours). Every value the map produces is dyadic, so the hand formula is
# compared exactly, once against one map step of the problem and once over the whole span.
@testitem "F4-01 (TS2): the map equals its analytic shift formula" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01 (TS2): the map equals its analytic shift formula" begin
    handshift(c) = [(i == 1 ? 0.0 : c[i - 1, j]) + (i == 8 ? 0.0 : c[i + 1, j]) for i in 1:8, j in 1:8] ./ 2
    pm = discretize(fam_map, fam_disc())
    u0 = reshape(collect(Float64.(pm.u0)), 8, 8)
    @test all(j -> u0[:, j] == u0[:, 1], axes(u0, 2))            # the initial condition is x, every column alike
    un = similar(pm.u0)
    pm.f(un, pm.u0, pm.p, 0.0)
    @test reshape(collect(Float64.(un)), 8, 8) == handshift(u0)  # one step, exactly
    got = reshape(collect(Float64.(solve(pm, ExplicitMap()).u[end])), 8, 8)
    @test got == handshift(handshift(handshift(u0)))             # three steps of the span (0, 3), exactly
    @test got != u0                                              # control: the map moves the state
end
end

# F4-01 (TS2): the `QuasiSteady` case, the third whose recorded triple was its only value check. The
# case is `BackwardEuler` on the two-field steady system `fam_steady`, and that system has an analytic
# steady state: eliminating `v` (`v = (1 - 0.1Δ)⁻¹u`) from `0 = Dc Δu - k u + v` gives
# `Δu (Dc + 0.1 k) - 0.1 Dc Δ²u + (1 - k) u = 0`, where `k = 1.0` cancels the last term and leaves
# `Δu (Dc + 0.1 - 0.1 Dc Δ) = 0`, that is `Δu = 0`. So `u` is constant, `u = v`, and the face
# `u(t, 0, y) = 1.0` fixes `u = v = 1`. The transient has no closed form, so the case is checked
# where it has one: the same run continued must sit on that state. The bound is derived, not chosen.
# A mode with `Δ` eigenvalue `-μ` decays at `-0.3μ` for small `μ`; the smallest nonzero `μ` of an 8²
# lattice is at least 0.03, so over t = 2000 every mode is damped by at least e^-18; the initial
# profile lies in [0, 1], so its mode amplitudes are at most 1; and the inner solve runs at rtol 1e-12
# (`FAM_INNER`), three orders below the deviation. The 1e-6 asserted is one order above the derived
# e^-18 = 1.5e-8 and six above the inner solve's accuracy.
@testitem "F4-01 (TS2): the coupled steady system converges to its analytic solution u = v = 1" setup = [LP_families] tags = [:latticepde, :families] begin
@testset "F4-01 (TS2): the coupled steady system converges to its analytic solution u = v = 1" begin
    prob = discretize(fam_steady, fam_disc())
    @test SciMLBase.successful_retcode(solve(prob, BackwardEuler(; dt = 0.05, inner = FAM_INNER)))
    long = solve(remake(prob; tspan = (0.0, 2000.0)), BackwardEuler(; dt = 1.0, inner = FAM_INNER))
    ue = collect(Float64.(long.u[end]))
    @test length(ue) == 128
    @test maximum(abs, ue .- 1.0) < 1e-6 || (println("F4-01 TS2 steady max dev ", maximum(abs, ue .- 1.0)); false)
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
