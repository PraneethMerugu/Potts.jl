# `BoundarySiteCPM` is removed with no
# alias and becomes `SequentialCPM(; skip_interior = true)`. `CheckerboardCPM` has no
# `skip_interior` (D-271: it changed nothing there).
# Decisions: D-198 (the rename), D-177 (the
# semantics: draw only sites that can propose a non-null copy, count the skipped picks
# exactly, N attempts per MCS), D-158 (our own recorded values are bitwise), D-171 (the gate
# and the A/B decide speed), D-048 (ordinary tests, no parity harness).
#
# Ten short cases (`CASES`, < 1 s each, warm): Graner–Glazier 72² periodic (the
# problem's proposal, a Moore(1) override, Barker acceptance); the 04 foam configuration on 64²
# (periodic x, closed y, NeighborOrder(4) contacts and proposals, dry, at T = 3 and at the
# T → 0⁺ temperature 1e-6); cubes in medium on 16³ (VonNeumann(1) proposals, and a Moore(1)
# override); a frozen kind (the mobility mask) on 32² periodic; and the 15 configuration, the
# OpenVT reference model on 60² with Moore(1) proposals and a division (two seeds).
#
# What is checked.
#  1. API (D-198 items 1, 2). `SequentialCPM(; skip_interior = true)` is a `SequentialCPM` whose
#     `skip_interior` is `true`; the default is `false`; the keyword composes with `acceptance`
#     and `proposal`. `BoundarySiteCPM` is not defined in, nor exported by, CorePotts, Potts or
#     PottsModels (no alias, no deprecation binding).
#  2. The default is today's SequentialCPM (D-198 item 2, "the gate is unchanged"):
#     `SequentialCPM(; kw...)` and `SequentialCPM(; skip_interior = false, kw...)` give the
#     same trajectory, bitwise. The gate itself (`benchmark/gate.jl` `sequential`) and the A/B
#     (D-171) are run outside this file.
#  3. `SequentialCPM(; skip_interior = true, kw...)` attempts N times per MCS, as the default
#     does, in 2D and 3D, periodic and closed, with a frozen mask, with a lifecycle
#     (divisions), and with each proposal neighbourhood in use (the problem's, a Moore(1),
#     VonNeumann(1) or NeighborOrder(4) relation) and both acceptance laws.
#  4. The SMOKE verdicts of reproductions 04 and 15 (D-198 "the same verdicts"). They are the
#     files' own (`test/reproductions/04_foam_tests.jl` `ALG`,
#     `test/reproductions/15_openvt_sweeps_tests.jl` `INHIBITION_ALG`), which run in this suite; they are
#     not repeated here. This file checks only that both constants are the renamed algorithm.
#     On the base, with
#     `BoundarySiteCPM`, the files gave (Mac, default tier = always + SMOKE + FULL record):
#     04_foam_tests.jl 682 pass, 24 broken; 15_openvt_sweeps_tests.jl 1117 pass, 4 broken. After the
#     rename they must give the same counts.
#  5. CheckerboardCPM (D-271, replacing D-198 item 3): its `skip_interior` keyword is removed,
#     so `CheckerboardCPM(; skip_interior = true)` is a `MethodError`.
#  Not covered: D-198 item 4 for proposal laws. No `ProposalLaw` and no `UnlikeNeighbor` exists
#  on the base, so "the skip composes with any proposal law" is covered only for the
#  proposal neighbourhoods of item 3; the boundary-site law carries its own composition.
#
# Tiers and cost: always; ten short cases, ~1 min with the models' compilation on the Mac.
#

@testsetup module SkipInteriorSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: CorePotts
using SHA: SHA
# 2D foam, the 04 configuration on 64² (16 bricks of 16²): periodic x, closed y, NeighborOrder(4)
# contacts and proposals, J = 3, Γ(a − A)², dry (no medium site)
@potts_model Foam begin
    @structural_parameters begin
        lattice = (64, 64)
    end
    @kinds medium bubble
    @parameters begin
        J = 3.0
        Γ = 1.0
        T = 1.0e-6
    end
    @variables begin
        A(cell) = 256.0
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    @sweep Metropolis(; temperature = T)
end
# 3D: cubes in medium on 16³, closed, Moore(1) contacts, VonNeumann(1) proposals
@potts_model Cube begin
    @kinds medium A B
    @parameters begin
        λ = 1.0
        V₀ = 27.0
        T = 6.0
        J[kind, kind] = [0.0 8.0 8.0; 8.0 3.0 9.0; 8.0 9.0 3.0]
    end
    @lattice Lattice((16, 16, 16); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = VonNeumann(1)
    @energy begin
        cells => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
    end
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end
# A frozen kind (the mask) on 32² periodic, Moore(1) proposals
@potts_model Walled begin
    @kinds medium A wall[frozen]
    @parameters begin
        λ = 2.0
        T = 4.0
        J[kind, kind] = [0.0 6.0 4.0; 6.0 3.0 6.0; 4.0 6.0 0.0]
    end
    @lattice Lattice((32, 32); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(A) => λ * (volume - 16.0)^2
        contacts => J[kind, neighbor_kind]
    end
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end
function brick(L, b)
    return Int32[
        (r = (y - 1) ÷ b; r * (L[1] ÷ b) + mod(x - 1 - (isodd(r) ? b ÷ 2 : 0), L[1]) ÷ b + 1)
            for x in 1:L[1], y in 1:L[2]
    ]
end
function interior_foam(; tspan = (0, 30), T = 3.0, seed)
    σ = brick((64, 64), 16)
    return PottsProblem(
        Foam(; name = :interior_foam), [ownership => σ, kind => fill(:bubble, 16), :A => fill(256.0, 16), :T => T],
        tspan; seed
    )
end
function cube(; tspan = (0, 12), seed)
    σ = zeros(Int32, 16, 16, 16)
    k = 0
    for a in (3, 10), b in (3, 10), c in (3, 10)
        k += 1
        σ[a:(a + 2), b:(b + 2), c:(c + 2)] .= k
    end
    return PottsProblem(Cube(; name = :cube), [ownership => σ, kind => [isodd(i) ? :A : :B for i in 1:k]], tspan; seed)
end
function walled(; tspan = (0, 20), seed)
    σ = zeros(Int32, 32, 32)
    σ[1:32, 16] .= 1                                   # a frozen wall across the lattice
    k = 1
    for a in (4, 12, 20, 28), b in (5, 22)
        k += 1
        σ[a:(a + 3), b:(b + 3)] .= k
    end
    return PottsProblem(Walled(; name = :walled), [ownership => σ, kind => [:wall; fill(:A, k - 1)]], tspan; seed)
end
function interior_gg(; tspan = (0, 20), seed)
    gg = graner_glazier_state()
    return PottsProblem(GranerGlazier(; name = :interior_gg), [ownership => gg[1], kind => gg[2]], tspan; seed)
end
# the 15 configuration: OpenVT reference model with divisions (σ_X = 0: the first by ~800 MCS)
function openvt(; tspan = (0, 1000), seed)
    return remake(
        PottsProblem(
            OpenVTReferenceMonolayer(; name = :ovt, lattice = (60, 60)),
            openvt_reference_state(; lattice = (60, 60)), tspan; capacity = 64, seed
        ); p = [:σ_X => 0.0]
    )
end
# The cases: (label, problem, keywords of the algorithm). Short runs (< 1 s each, warm).
const CASES = [
    ("GG 72² periodic, problem's proposal, seed 1", () -> interior_gg(; seed = 1), (;)),
    ("GG 72² periodic, Moore(1), seed 2", () -> interior_gg(; seed = 2), (; proposal = Moore(1))),
    ("GG 72² periodic, Barker, seed 3", () -> interior_gg(; seed = 3), (; acceptance = Barker())),
    ("foam 64² NeighborOrder(4), T = 3, seed 1", () -> interior_foam(; seed = 1), (;)),
    ("foam 64² NeighborOrder(4), T = 1e-6, seed 2", () -> interior_foam(; T = 1.0e-6, seed = 2), (;)),
    ("cubes 16³, VonNeumann(1), seed 1", () -> cube(; seed = 1), (;)),
    ("cubes 16³, Moore(1) override, seed 2", () -> cube(; seed = 2), (; proposal = Moore(1))),
    ("frozen wall 32², seed 1", () -> walled(; seed = 1), (;)),
    ("OpenVT reference 60², Moore(1), divisions, seed 1", () -> openvt(; seed = 1), (; proposal = Moore(1))),
    ("OpenVT reference 60², Moore(1), divisions, seed 2", () -> openvt(; seed = 2), (; proposal = Moore(1))),
]
"""sha256 of σ after every MCS (and at t0), the accepted and attempted counts and the
division count: the whole trajectory of one run."""
function interior_trajectory(prob, alg)
    sol = solve(prob, alg; saveat = 1)
    ctx = SHA.SHA256_CTX()
    for u in sol.u
        SHA.update!(ctx, reinterpret(UInt8, vec(Array{Int32}(u.ownership))))
    end
    lc = sol.stats.lifecycle
    return (;
        ownership = bytes2hex(SHA.digest!(ctx)), accepted = sol.stats.accepted, attempts = sol.stats.attempts,
        divisions = lc === nothing ? 0 : lc.divisions, retcode = Symbol(sol.retcode),
    )
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "skip interior: SequentialCPM(; skip_interior) replaces BoundarySiteCPM, with no alias" setup = [SkipInteriorSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. API
    @testset "skip interior: SequentialCPM(; skip_interior) replaces BoundarySiteCPM, with no alias" begin
        a = SequentialCPM(; skip_interior = true)
        @test a isa SequentialCPM && a isa CorePotts.AbstractCPMAlgorithm
        @test a.skip_interior === true
        @test a.acceptance === nothing && a.proposal === nothing
        @test SequentialCPM().skip_interior === false
        @test SequentialCPM(; skip_interior = false).skip_interior === false
        b = SequentialCPM(; skip_interior = true, proposal = Moore(1), acceptance = Barker())
        @test b.skip_interior === true && b.proposal == Moore(1) && b.acceptance == Barker()
        for m in (CorePotts, Potts, PottsModels)
            @test !isdefined(m, :BoundarySiteCPM)
            @test !Base.isexported(m, :BoundarySiteCPM)
        end
        @test !isdefined(@__MODULE__, :BoundarySiteCPM)
    end
end

@testitem "skip interior: skip_interior = false is the default trajectory" setup = [SkipInteriorSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. The default is today's SequentialCPM
    @testset "skip interior: skip_interior = false is the default trajectory ($label)" for (label, mk, kw) in CASES
        prob = mk()
        @test interior_trajectory(prob, SequentialCPM(; skip_interior = false, kw...)) ==
            interior_trajectory(prob, SequentialCPM(; kw...))
    end
end

@testitem "skip interior: skip_interior = true attempts N times per MCS" setup = [SkipInteriorSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. The skip's attempt accounting
    @testset "skip interior: skip_interior = true attempts N times per MCS ($label)" for (label, mk, kw) in CASES
        prob = mk()
        alg = SequentialCPM(; skip_interior = true, kw...)
        got = interior_trajectory(prob, alg)
        @test got.retcode === :Success
        @test got.attempts == interior_trajectory(prob, SequentialCPM(; kw...)).attempts   # N attempts per MCS, as the default
        # init + step! is the same run (free determinism, D-158)
        integ = init(prob, alg; save_start = false)
        while integ.t < prob.tspan[2]
            step!(integ)
        end
        @test integ.stats.accepted == got.accepted && integ.stats.attempts == got.attempts
    end
end

@testitem "skip interior: reproductions 04 and 15 name SequentialCPM(; skip_interior = true)" setup = [SkipInteriorSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. The 04 and 15 SMOKE tiers run the renamed algorithm (their verdicts are their own)
    @testset "skip interior: reproductions 04 and 15 name SequentialCPM(; skip_interior = true)" begin
        dir = joinpath(@__DIR__, "..", "shared")
        s04 = read(joinpath(dir, "foam.jl"), String)
        s15 = read(joinpath(dir, "openvt_sweeps.jl"), String)
        @test occursin("\nconst ALG = SequentialCPM(; skip_interior = true)\n", s04)
        @test occursin("\nconst INHIBITION_ALG = SequentialCPM(; skip_interior = true, proposal = Moore(1))\n", s15)
    end
end

@testitem "skip interior: CheckerboardCPM runs the cases and has no skip_interior" setup = [SkipInteriorSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 5. CheckerboardCPM: the recorded trajectories; no skip_interior (D-271)
    @testset "skip interior: CheckerboardCPM runs the cases and has no skip_interior" begin
        @test_throws MethodError CheckerboardCPM(; skip_interior = true)
        for (label, mk, kw) in CASES
            @test interior_trajectory(mk(), CheckerboardCPM(; threads = false, kw...)).retcode === :Success
        end
    end
end
