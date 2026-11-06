# F4-01 (F4 design §3.2, rulings Q-B and Q1): `discretize` returns one SciML problem (an
# `ODEProblem` of rates, a `DiscreteProblem` of maps) that the field algorithms and
# OrdinaryDiffEq's solvers both take; `FieldAlgorithm <: SciMLBase.AbstractODEAlgorithm`; the
# compiled right side is built at its first call only; the `problem` keyword is deleted.
# Negative controls (the base 3ed05c3b): `ExplicitEuler <: AbstractDEAlgorithm` was false, and
# the right side was built at `discretize` (one build before any solve).
# This file at F4-00: 3 pass, 3 fail, 5 errors (every testset fails).
using SciMLBase: SciMLBase, remake
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqRosenbrock: Rodas5P
using OrdinaryDiffEqBDF: FBDF
using KernelAbstractions: KernelAbstractions as KA

@parameters fDc = 0.2 fk = 1.0
@parameters fdx [lattice_spacing = 1]
@variables fu(..) fv(..) fN(..)
fam_u, fam_v, fam_N = fu(t, x, y), fv(t, x, y), fN(t, x, y)
fam_dom = [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
fam_faces = [fu(t, 0, y) ~ 1.0, fu(t, x, 0) ~ fu(t, x, 1)]
fam_rate = PDESystem([D(fam_u) ~ fDc * Δ(fam_u) - fk * fam_u + x * y], [fu(0, x, y) ~ x; fam_faces], fam_dom, [t, x, y],
    [fam_u], [fDc, fk]; name = :famr)
fam_steady = PDESystem([D(fam_u) ~ fDc * Δ(fam_u) - fk * fam_u + fam_v, 0 ~ 0.1 * Δ(fam_v) - fam_v + fam_u],
    [fu(0, x, y) ~ x; fam_faces; fv(t, x, 0) ~ fv(t, x, 1)], fam_dom, [t, x, y], [fam_u, fam_v], [fDc, fk]; name = :fams)
fam_chain = PDESystem([D(fam_u) ~ fDc * Δ(fam_u) - fk * fam_u, D(fam_v) ~ 0.5 * Δ(fam_v) - fam_v + fam_u],
    [fu(0, x, y) ~ x; fv(0, x, y) ~ y; fam_faces; fv(t, x, 0) ~ fv(t, x, 1)], fam_dom, [t, x, y], [fam_u, fam_v], [fDc, fk]; name = :famc)
fam_map = PDESystem([Shift(t, 1)(fam_N) ~ (fN(t, x + fdx, y) + fN(t, x - fdx, y)) / 2], [fN(0, x, y) ~ x],
    [t ∈ Interval(0.0, 3.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [fam_N], [fdx]; name = :famm)
const FAM_INNER = DevicePCG(; rtol = 1e-12, budget = 64)
const FAM_CASES = [("ExplicitEuler", fam_rate, ExplicitEuler(; dt = 0.01)),
    ("BackwardEuler", fam_rate, BackwardEuler(; dt = 0.05, inner = FAM_INNER)),
    ("CrankNicolson", fam_rate, CrankNicolson(; dt = 0.05, inner = FAM_INNER)),
    ("BDF2", fam_rate, BDF2(; dt = 0.05, inner = FAM_INNER)),
    ("QuasiSteady", fam_steady, BackwardEuler(; dt = 0.05, inner = FAM_INNER)),
    ("FieldGroups", fam_chain, FieldGroups(fam_u => ExplicitEuler(; dt = 0.05, substeps = 2),
        fam_v => BackwardEuler(; dt = 0.05, inner = FAM_INNER))),
    ("ExplicitMap", fam_map, ExplicitMap())]
fam_digest(u) = (repr(sum(u)), repr(u[1]), repr(u[end]))
# the base's owned solves (`problem = :owned` at 3ed05c3b, ~/lpwork/f4b1/pins.jl on the PC):
# `(sum, first, last)` of the final state, printed exactly
const FAM_PINS = Dict{String, NTuple{3, String}}(
    "ExplicitEuler" => ("40.083782220091095", "0.8464843838279211", "0.7229504422497087"),
    "BackwardEuler" => ("39.58397959572821", "0.8208813249422733", "0.7369070815165802"),
    "CrankNicolson" => ("39.98320671764459", "0.8429541456996491", "0.7266335083499864"),
    "BDF2" => ("39.98795542318008", "0.8509726321471082", "0.7289081501820648"),
    "QuasiSteady" => ("83.97825902430269", "0.8510960053524306", "0.6964964497644828"),
    "FieldGroups" => ("70.23816581681162", "0.8442336499283419", "0.5305929833215783"),
    "ExplicitMap" => ("24.0", "0.1015625", "0.2734375"))
fam_disc() = LatticeDiscretization(Grid((8, 8)); T = Float64)
fmsg(f) = try
    f(); ""
catch e
    sprint(showerror, e)
end

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

# a backend that is not the problem's (SX-12): an array type whose backend is a stand-in GPU
struct FamFakeGPU <: KA.GPU end
struct FamDevVec <: AbstractVector{Float64}
    v::Vector{Float64}
end
Base.size(a::FamDevVec) = size(a.v)
Base.getindex(a::FamDevVec, i::Int) = a.v[i]
KA.get_backend(::FamDevVec) = FamFakeGPU()

@testset "F4-01: a state on another backend is refused, naming both (SX-12)" begin
    prob = discretize(fam_rate, fam_disc())
    e = fmsg(() -> remake(prob; u0 = FamDevVec(zeros(64))))
    @test occursin("u0 is on the backend FamFakeGPU", e) && occursin("the problem's backend is CPU", e)
    @test remake(prob; u0 = zeros(64)).u0 == zeros(64)        # control: a host state
end
