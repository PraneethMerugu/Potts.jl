# P6.0bk2 (ROADMAP Phase 6; D-198, amending D-177): `BoundarySiteCPM` is removed with no
# alias and becomes `SequentialCPM(; skip_interior = true)`; `CheckerboardCPM(; skip_interior =
# true)` is the same option on the checkerboard (P6.0bk, folded in by D-198 item 3). Frozen
# (AUTONOMY §7.3). Decisions: D-198 (the rename and its code-identity check), D-177 (the
# semantics: draw only sites that can propose a non-null copy, count the skipped picks
# exactly, N attempts per MCS), D-158 (our own recorded values are bitwise), D-171 (the gate
# and the A/B decide speed), D-048 (ordinary tests, no parity harness).
#
# Recorded on the freeze base (cfdf8477, Apple M-series, Julia 1.12.6) with the code as it was
# then: `BoundarySiteCPM(; kw...)`, `SequentialCPM(; kw...)` and `CheckerboardCPM(; kw...)` on
# the ten short cases of `P60BK2_CASES` (< 1 s each, warm): Graner–Glazier 72² periodic (the
# problem's proposal, a Moore(1) override, Barker acceptance); the 04 foam configuration on 64²
# (periodic x, closed y, NeighborOrder(4) contacts and proposals, dry, at T = 3 and at the
# T → 0⁺ temperature 1e-6); cubes in medium on 16³ (VonNeumann(1) proposals, and a Moore(1)
# override); a frozen kind (the mobility mask) on 32² periodic; and the 15 configuration, the
# OpenVT reference model on 60² with Moore(1) proposals and a division (two seeds). Each value
# is the sha256 of σ at t0 and after every MCS, with `stats.accepted`, `stats.attempts`, the
# division count and the return code.
#
# What is pinned.
#  1. API (D-198 items 1, 2). `SequentialCPM(; skip_interior = true)` is a `SequentialCPM` whose
#     `skip_interior` is `true`; the default is `false`; the keyword composes with `acceptance`
#     and `proposal`. `BoundarySiteCPM` is not defined in, nor exported by, CorePotts, Potts or
#     PottsModels (no alias, no deprecation binding).
#  2. The default is today's SequentialCPM (D-198 item 2, "the gate is unchanged").
#     (a) `SequentialCPM(; kw...)` and `SequentialCPM(; skip_interior = false, kw...)` give,
#         bitwise, the trajectories recorded on the base.
#     (b) Code identity of the default loop: the optimized, typed IR of
#         `CorePotts.sequential_mcs!` (debuginfo stripped), for the integrator `init` builds
#         from `SequentialCPM()` on GG 72² and on the 16³ cubes, has the sha256 recorded on the
#         base. The skip lives outside that function (as `boundary_site_mcs!` does today), so
#         the default compiles to the same loop. The IR's printed form depends on the Julia
#         version: the row binds on Julia 1.12.6 only and is `@test_skip` on any other.
#     The gate itself (`benchmark/gate.jl` `sequential`) and the A/B (D-171) are run outside
#     this file.
#  3. Code identity of the rename (D-198 "Code-identity check"). `SequentialCPM(; skip_interior =
#     true, kw...)` gives, bitwise, the trajectories `BoundarySiteCPM(; kw...)` gave on the base:
#     the same RNG draws (stream, counters), the same σ after every MCS, the same accepted and
#     attempted counts, in 2D and 3D, periodic and closed, with a frozen mask, with a lifecycle
#     (divisions), and with each proposal neighbourhood in use (the problem's, a Moore(1),
#     VonNeumann(1) or NeighborOrder(4) relation) and both acceptance laws.
#  4. The SMOKE verdicts of reproductions 04 and 15 (D-198 "the same verdicts"). They are the
#     re-frozen files' own (`test/reproductions/04_foam.jl` `P64R_ALG`,
#     `test/reproductions/15_openvt_sweeps.jl` `P615G_ALG`), which run in this suite; they are
#     not repeated here. This file pins only that both constants are the renamed algorithm,
#     so that item 3's identity carries the base verdicts over. On the base, with
#     `BoundarySiteCPM`, the files gave (Mac, default tier = always + SMOKE + FULL record):
#     04_foam.jl 682 pass, 24 broken; 15_openvt_sweeps.jl 1117 pass, 4 broken. After the
#     rename they must give the same counts.
#  5. `CheckerboardCPM(; skip_interior = true)` (D-198 item 3, P6.0bk). P6.0bk's own statement is
#     an exact null-region skip "without changing the trajectory": the checkerboard draws per
#     (MCS, site), so skipping sites that can only propose a null copy leaves every other draw
#     as it was. Pinned as a disjunction, since P6.0bk may land after the rename:
#     - either the keyword is accepted and raises an informative `ArgumentError` (its message
#       names `skip_interior` and says "not yet implemented") at construction or at `solve`;
#     - or it runs, and on the CPU it gives, bitwise, `CheckerboardCPM(; kw...)`'s trajectory
#       on every case, which is in turn the one recorded on the base, with
#       `CheckerboardCPM().skip_interior === false`.
#     A `MethodError` (the keyword unknown, as on the base) fails.
#  Not pinned: D-198 item 4 for proposal laws. No `ProposalLaw` and no `UnlikeNeighbor` exists
#  on the base (P6.4b), so "the skip composes with any proposal law" is covered only for the
#  proposal neighbourhoods of item 3; the law that P6.4b adds pins its own composition.
#
# Tiers and cost: always; ten short cases × four algorithms plus the IR, ~1 min with the
# models' compilation on the Mac.
#
# Today (freeze base cfdf8477) this file fails only because the keyword does not exist:
# `SequentialCPM(; skip_interior = …)` and `CheckerboardCPM(; skip_interior = …)` raise
# `MethodError` (items 1, 3, 5 and the `skip_interior = false` half of 2a), and
# `BoundarySiteCPM` is still defined (item 1). Item 2a's `SequentialCPM(; kw...)` half, item 2b
# and item 4 pass on the base.
using Test, Potts, PottsModels
using Potts: CorePotts
using SHA: SHA, sha256

# 2D foam, the 04 configuration on 64² (16 bricks of 16²): periodic x, closed y, NeighborOrder(4)
# contacts and proposals, J = 3, Γ(a − A)², dry (no medium site)
@potts_model P60bk2Foam begin
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
@potts_model P60bk2Cube begin
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
        contacts => J[kind, kind′]
    end
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end

# A frozen kind (the mask) on 32² periodic, Moore(1) proposals
@potts_model P60bk2Walled begin
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
        contacts => J[kind, kind′]
    end
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end

p60bk2_brick(L, b) = Int32[(r = (y - 1) ÷ b; r * (L[1] ÷ b) + mod(x - 1 - (isodd(r) ? b ÷ 2 : 0), L[1]) ÷ b + 1)
                           for x in 1:L[1], y in 1:L[2]]
function p60bk2_foam(; tspan = (0, 30), T = 3.0, seed)
    σ = p60bk2_brick((64, 64), 16)
    return PottsProblem(P60bk2Foam(; name = :p60bk2_foam), [ownership => σ, kind => fill(:bubble, 16), :A => fill(256.0, 16), :T => T],
        tspan; seed)
end
function p60bk2_cube(; tspan = (0, 12), seed)
    σ = zeros(Int32, 16, 16, 16)
    k = 0
    for a in (3, 10), b in (3, 10), c in (3, 10)
        k += 1
        σ[a:(a + 2), b:(b + 2), c:(c + 2)] .= k
    end
    return PottsProblem(P60bk2Cube(; name = :p60bk2_cube), [ownership => σ, kind => [isodd(i) ? :A : :B for i in 1:k]], tspan; seed)
end
function p60bk2_walled(; tspan = (0, 20), seed)
    σ = zeros(Int32, 32, 32)
    σ[1:32, 16] .= 1                                   # a frozen wall across the lattice
    k = 1
    for a in (4, 12, 20, 28), b in (5, 22)
        k += 1
        σ[a:(a + 3), b:(b + 3)] .= k
    end
    return PottsProblem(P60bk2Walled(; name = :p60bk2_walled), [ownership => σ, kind => [:wall; fill(:A, k - 1)]], tspan; seed)
end
p60bk2_gg(; tspan = (0, 20), seed) =
    (gg = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :p60bk2_gg), [ownership => gg[1], kind => gg[2]], tspan; seed))
# the 15 configuration: OpenVT reference model with divisions (σ_X = 0: the first by ~800 MCS)
p60bk2_openvt(; tspan = (0, 1000), seed) =
    remake(PottsProblem(OpenVTReferenceMonolayer(; name = :p60bk2_ovt, lattice = (60, 60)),
            openvt_reference_state(; lattice = (60, 60)), tspan; capacity = 64, seed); p = [:σ_X => 0.0])

# The cases: (label, problem, keywords of the algorithm). Short runs (< 1 s each, warm).
const P60BK2_CASES = [
    ("GG 72² periodic, problem's proposal, seed 1", () -> p60bk2_gg(; seed = 1), (;)),
    ("GG 72² periodic, Moore(1), seed 2", () -> p60bk2_gg(; seed = 2), (; proposal = Moore(1))),
    ("GG 72² periodic, Barker, seed 3", () -> p60bk2_gg(; seed = 3), (; acceptance = Barker())),
    ("foam 64² NeighborOrder(4), T = 3, seed 1", () -> p60bk2_foam(; seed = 1), (;)),
    ("foam 64² NeighborOrder(4), T = 1e-6, seed 2", () -> p60bk2_foam(; T = 1.0e-6, seed = 2), (;)),
    ("cubes 16³, VonNeumann(1), seed 1", () -> p60bk2_cube(; seed = 1), (;)),
    ("cubes 16³, Moore(1) override, seed 2", () -> p60bk2_cube(; seed = 2), (; proposal = Moore(1))),
    ("frozen wall 32², seed 1", () -> p60bk2_walled(; seed = 1), (;)),
    ("OpenVT reference 60², Moore(1), divisions, seed 1", () -> p60bk2_openvt(; seed = 1), (; proposal = Moore(1))),
    ("OpenVT reference 60², Moore(1), divisions, seed 2", () -> p60bk2_openvt(; seed = 2), (; proposal = Moore(1))),
]

"""sha256 of σ after every MCS (and at t0), the accepted and attempted counts and the
division count: the whole trajectory of one run."""
function p60bk2_trajectory(prob, alg)
    sol = solve(prob, alg; saveat = 1)
    ctx = SHA.SHA256_CTX()
    for u in sol.u
        SHA.update!(ctx, reinterpret(UInt8, vec(Array{Int32}(u.σ))))
    end
    lc = sol.stats.lifecycle
    return (; σ = bytes2hex(SHA.digest!(ctx)), accepted = sol.stats.accepted, attempts = sol.stats.attempts,
        divisions = lc === nothing ? 0 : lc.divisions, retcode = Symbol(sol.retcode))
end

p60bk2_rec(σ, accepted, attempts, divisions) = (; σ, accepted, attempts, divisions, retcode = :Success)

# Item 3: `BoundarySiteCPM(; kw...)` on the base.
const P60BK2_SKIP = Dict(
    "GG 72² periodic, problem's proposal, seed 1" => p60bk2_rec("f702cd7e9e8b40eb0602b48354999cbc5d5cca716eb0a9f44b74ba929227212a", 5884, 103680, 0),
    "GG 72² periodic, Moore(1), seed 2" => p60bk2_rec("839735a49c4b4c0f522d5320149d1a5f127ca91d46d2b097a08e3d25a0b16794", 5913, 103680, 0),
    "GG 72² periodic, Barker, seed 3" => p60bk2_rec("7c7f06add58fb53c27cea2a9fbcae1f89e827fe58b23cd50934f01ba46571aba", 3976, 103680, 0),
    "foam 64² NeighborOrder(4), T = 3, seed 1" => p60bk2_rec("6649f6f7b23f31c1ec1ca304ef84b4f1b8d135297d31b89afe0635790d5c1ded", 1146, 122880, 0),
    "foam 64² NeighborOrder(4), T = 1e-6, seed 2" => p60bk2_rec("e0c07c4e94fef6ea3f59847462dfe2485ccd78dc757b7aef57d4b229219113cd", 260, 122880, 0),
    "cubes 16³, VonNeumann(1), seed 1" => p60bk2_rec("3b937851110aa9ccb024150214c87b5acc1a47b58e25875a80f1db6cca0eba40", 210, 49152, 0),
    "cubes 16³, Moore(1) override, seed 2" => p60bk2_rec("6462fe366bf4abb06cb35e960adf2ee8e070b2eaf54a3a8805e29da8be223d95", 208, 49152, 0),
    "frozen wall 32², seed 1" => p60bk2_rec("387813f7b546cf91429f4605c40d67a79e6d0583fa005bf29bf4b4e335f6d980", 338, 19840, 0),
    "OpenVT reference 60², Moore(1), divisions, seed 1" => p60bk2_rec("638e4826057a1719c310bc3f0c7ad5d3af22296ed3ad0c64ec4a2590ba96ab88", 14780, 3600000, 1),
    "OpenVT reference 60², Moore(1), divisions, seed 2" => p60bk2_rec("5b627a85e70ffa29fceba9d09143fb7eb5d2c5a30dd922e8426004522107c494", 15238, 3600000, 1),
)

# Item 2a: `SequentialCPM(; kw...)` on the base.
const P60BK2_SEQ = Dict(
    "GG 72² periodic, problem's proposal, seed 1" => p60bk2_rec("35b3f7ce4db3b9835e6a341c34fea9137dc15cb5119f07dbddbf599d786578ed", 5995, 103680, 0),
    "GG 72² periodic, Moore(1), seed 2" => p60bk2_rec("916aa9b36e567d25606f993f2829d02eda055df59292be52ff30200f667a7a0b", 6018, 103680, 0),
    "GG 72² periodic, Barker, seed 3" => p60bk2_rec("e48381ae12a7e6e219e8cc9dbe0e2183d7a43c6930db8745086e15ea06864d75", 3951, 103680, 0),
    "foam 64² NeighborOrder(4), T = 3, seed 1" => p60bk2_rec("4206decbe17416d940879390379426c4515189e3821ba76cb346362096f9c673", 1392, 122880, 0),
    "foam 64² NeighborOrder(4), T = 1e-6, seed 2" => p60bk2_rec("715c52316ba0c8b8f39605564fbfa33e24066b0a67c35287c7e30aca4bb83fd8", 298, 122880, 0),
    "cubes 16³, VonNeumann(1), seed 1" => p60bk2_rec("295dfc7bcb57592f399baace2c42b9b8c861f698dc345102d325fc360b936f37", 210, 49152, 0),
    "cubes 16³, Moore(1) override, seed 2" => p60bk2_rec("4f1b776e7d89074fa498963db687ca718e4c45879eb90a0788153defc1ccee5f", 210, 49152, 0),
    "frozen wall 32², seed 1" => p60bk2_rec("85ea133bf97fc5a91152614e4f7e2db890d0d390e41cec3be19c10065376f121", 356, 19840, 0),
    "OpenVT reference 60², Moore(1), divisions, seed 1" => p60bk2_rec("9a01b19c96a30c331c4c5271c230d36b26f17544b74b5343f5ddfd21983fc7a2", 15119, 3600000, 1),
    "OpenVT reference 60², Moore(1), divisions, seed 2" => p60bk2_rec("7f37a021eee48013bd0a90e4e4ad04ca36430954a8995fa852e878d0d5da69fb", 14935, 3600000, 1),
)

# Item 5: `CheckerboardCPM(; kw...)` on the base, CPU (`accepted` is −1: not counted).
const P60BK2_CB = Dict(
    "GG 72² periodic, problem's proposal, seed 1" => p60bk2_rec("8a303df5c4efc024dc79f05011a1c96b97f71ccb65cac16bc9d1f0ec34b23de7", -1, 103680, 0),
    "GG 72² periodic, Moore(1), seed 2" => p60bk2_rec("139b0d3d2ce36aa3e6af34d8c8e395a4a1d039e708d0824e37dfa7e1145aa775", -1, 103680, 0),
    "GG 72² periodic, Barker, seed 3" => p60bk2_rec("150c612f7e2302ac9b0e2a626379b857a0be944bed86cf312d524669cc9b2253", -1, 103680, 0),
    "foam 64² NeighborOrder(4), T = 3, seed 1" => p60bk2_rec("306f1c79e8b5f0869dfa2d71df2b5d55cb150b424bf1a4b8b9eb7e9966276180", -1, 122880, 0),
    "foam 64² NeighborOrder(4), T = 1e-6, seed 2" => p60bk2_rec("a407c2fd8aeb166e7bc5302183b94e7fc2d66c8cd013aee3f4d5321a90d9ed1e", -1, 122880, 0),
    "cubes 16³, VonNeumann(1), seed 1" => p60bk2_rec("7d8296459b096d907d55bf82bd430b997a1eee09394e6260b6cb1626b55afed6", -1, 49152, 0),
    "cubes 16³, Moore(1) override, seed 2" => p60bk2_rec("459f28a412f1184494afd2307140aff9307940dc3eb66755f3d30b85cd157f27", -1, 49152, 0),
    "frozen wall 32², seed 1" => p60bk2_rec("3d8f15799de8e75f899c9d0d015f03e13ee80546ac92d50f450255c4056f53b3", -1, 19840, 0),
    "OpenVT reference 60², Moore(1), divisions, seed 1" => p60bk2_rec("0663dde26392f900705509cd1462514bbcd6592fcf62d76d7f27583d07d4e505", -1, 3600000, 1),
    "OpenVT reference 60², Moore(1), divisions, seed 2" => p60bk2_rec("797146400d423494e56cc5d9479fddd6ff99c9edadebe36ef036632b45ff778e", -1, 3600000, 1),
)

# Item 2b: sha256 of the printed optimized typed IR of `sequential_mcs!` (Julia 1.12.6).
const P60BK2_IR_VERSION = v"1.12.6"
const P60BK2_IR = Dict(
    "GG 72²" => "eb450f913161074f87bb22f49df9ee2eefd2aa3272a918b870f0928b47b281df",
    "cubes 16³" => "ae79283679dc26748025cac9044d4f02df298b64062a0cbd887fe0a4e2b04a74",
)
function p60bk2_ir_hash(prob)
    integ = init(prob, SequentialCPM(); save_start = false)
    args = (integ.state, integ.kf, integ.p, CorePotts.sweep_ctx(integ.ctx, 0), integ.law, integ.key, 0, integ.f.track)
    ci = only(code_typed(CorePotts.sequential_mcs!, typeof.(args); optimize = true, debuginfo = :none))
    io = IOBuffer()
    show(io, ci.first)
    return bytes2hex(sha256(take!(io)))
end

# ---------------------------------------------------------------------------------------
# 1. API

@testset "P6.0bk2: SequentialCPM(; skip_interior) replaces BoundarySiteCPM, with no alias" begin
    a = SequentialCPM(; skip_interior = true)
    @test a isa SequentialCPM && a isa CorePotts.CPMAlgorithm
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

# ---------------------------------------------------------------------------------------
# 2. The default is today's SequentialCPM

@testset "P6.0bk2: SequentialCPM() keeps the base trajectory ($label)" for (label, mk, kw) in P60BK2_CASES
    prob = mk()
    @test p60bk2_trajectory(prob, SequentialCPM(; kw...)) == P60BK2_SEQ[label]
    @test p60bk2_trajectory(prob, SequentialCPM(; skip_interior = false, kw...)) == P60BK2_SEQ[label]
end

const P60BK2_IR_CASES = [("GG 72²", () -> p60bk2_gg(; seed = 1)), ("cubes 16³", () -> p60bk2_cube(; seed = 1))]
@testset "P6.0bk2: SequentialCPM()'s loop compiles to the base code ($label)" for (label, mk) in P60BK2_IR_CASES
    if VERSION == P60BK2_IR_VERSION
        @test p60bk2_ir_hash(mk()) == P60BK2_IR[label]
    else
        @test_skip p60bk2_ir_hash(mk()) == P60BK2_IR[label]
    end
end

# ---------------------------------------------------------------------------------------
# 3. Code identity of the rename

@testset "P6.0bk2: skip_interior = true is BoundarySiteCPM's code path ($label)" for (label, mk, kw) in P60BK2_CASES
    prob = mk()
    alg = SequentialCPM(; skip_interior = true, kw...)
    got = p60bk2_trajectory(prob, alg)
    @test got == P60BK2_SKIP[label]
    @test got.attempts == P60BK2_SEQ[label].attempts                 # N attempts per MCS, as the default
    # init + step! is the same run (free determinism, D-158)
    integ = init(prob, alg; save_start = false)
    while integ.t < prob.tspan[2]
        step!(integ)
    end
    @test integ.stats.accepted == got.accepted && integ.stats.attempts == got.attempts
end

# ---------------------------------------------------------------------------------------
# 4. The 04 and 15 SMOKE tiers run the renamed algorithm (their verdicts are their own)

@testset "P6.0bk2: reproductions 04 and 15 name SequentialCPM(; skip_interior = true)" begin
    dir = joinpath(@__DIR__, "..", "reproductions")
    s04 = read(joinpath(dir, "04_foam.jl"), String)
    s15 = read(joinpath(dir, "15_openvt_sweeps.jl"), String)
    @test occursin("\nconst P64R_ALG = SequentialCPM(; skip_interior = true)\n", s04)
    @test occursin("\nconst P615G_ALG = SequentialCPM(; skip_interior = true, proposal = Moore(1))\n", s15)
end

# ---------------------------------------------------------------------------------------
# 5. CheckerboardCPM(; skip_interior = true) (P6.0bk)

"""`:pending` if `f()` raises the informative not-yet-implemented `ArgumentError`, else `f()`'s
value (any other exception propagates)."""
function p60bk2_pending(f)
    try
        return f()
    catch e
        (e isa ArgumentError && occursin("skip_interior", e.msg) && occursin(r"not yet implemented"i, e.msg)) &&
            return :pending
        rethrow()
    end
end

@testset "P6.0bk2: CheckerboardCPM(; skip_interior = true) is exact, or pending P6.0bk" begin
    for (label, mk, kw) in P60BK2_CASES
        prob = mk()
        got = p60bk2_pending(() -> p60bk2_trajectory(prob, CheckerboardCPM(; skip_interior = true, kw...)))
        if got === :pending
            @test got === :pending
            @info "P6.0bk2: CheckerboardCPM(; skip_interior = true) is not yet implemented (P6.0bk)"
            break
        end
        @test CheckerboardCPM().skip_interior === false
        @test CheckerboardCPM(; skip_interior = true).skip_interior === true
        @test p60bk2_trajectory(prob, CheckerboardCPM(; kw...)) == P60BK2_CB[label]
        @test got == P60BK2_CB[label]                                 # the trajectory is unchanged
    end
end
