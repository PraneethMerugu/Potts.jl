# P6.0v2b (ROADMAP Phase 6, step 0; from the P6.0v2 review): a custom-rule
# `refresh_frozen!` copies only the state leaves its `remake_frozen` reads. Frozen
# (AUTONOMY §7.3). Decisions: D-081 (the mask follows the state), D-085 (counters), D-089,
# D-092 (column-only copies, `HostPhase` `reads`); audit
# `docs/design/research/gpu-host-transfer-audit.md` R4. Rule: D-128.
#
# Accept (ROADMAP): per-refresh bytes independent of unused cell quantities on Metal.
#
# API (proposed surface; D-128). A custom rule cannot be scanned for what it reads (it is
# host code), so it declares it:
#     CorePotts.frozen_reads(sys)   # default `nothing`
# A tuple of Symbols naming the state leaves `remake_frozen(sys, prob, u)` reads at a
# refresh: `:σ` (the labels) or a cell column name, as `HostPhase(...; reads)` (D-092).
# `nothing` (the default) keeps today's behaviour: the whole state is copied to the host
# at every custom-rule refresh. With a declaration, what the rule sees in undeclared leaves
# is unspecified. A name that is neither `:σ` nor a cell column of the state is an
# `ArgumentError` by the first refresh (at `init` or at `refresh_frozen!`), on every
# backend, so a typo never reads a stale or device leaf silently. Public, not exported,
# beside `frozen_varies`/`frozen_kinds`. The standard rule (`frozen_kinds`) ignores it.
#
# What is pinned. CorePotts-level fixtures (32 cell slots, so every Float32/Int32 column is
# 128 B; 16 × 16 Closed lattice; cells 1, 2, 3 are fixed 4 × 4 squares: T = 0 and a volume
# constraint at V0 = 16 reject every copy, so σ never changes and every mask is
# hand-checkable). The custom rule freezes the sites of cells whose `stiff` column is
# > 1/2; it reads σ and `stiff` only. Each fixture comes as a twin pair that differs ONLY
# by quantities the rule does not read: extra cell columns z1 (Float), z2 (Int32), z3 (a
# 3 × 32 matrix), a model quantity q and a site field h. Systems:
#   P60v2bDeclared    custom rule, `frozen_reads = (:σ, :stiff)`
#   P60v2bUndeclared  the same rule, no declaration (the whole-state fallback)
#   P60v2bBad         the same rule, declares a column that does not exist
#   P60v2bStandard    the standard rule, `frozen_kinds = (2,)` (cell 2 has kind 2)
# On Metal (POTTS_GPU=metal with Metal loaded; Float32, CheckerboardCPM), the counter
# triple (syncs, transfers, transfer_bytes) of each direct `refresh_frozen!(integ)` (after
# one warm MCS; three refreshes: unchanged state, `stiff` rewritten on the device, unchanged
# again):
#  1. Twin invariance (the Accept line). Declared: the triple is the same at every refresh
#     and identical between the twins. Standard: the same (a regression guard).
#  2. Bound. Declared: per-refresh bytes ≤ sizeof(σ) + sizeof(stiff) (down) + nsites
#     (the Bool mask, up) + P60V2B_SLACK. Standard: ≤ P60V2B_SLACK (it runs on the device;
#     a direct call reads back its three Int32 counts, 12 B). P60V2B_SLACK = 16 B covers up
#     to four 4-byte scalar read-backs, as in D-092; every unused column is ≥ 128 B, so no
#     unused column fits in it. A device implementation (0 B down) satisfies every bound.
#  3. Results. Every refresh's mask (`integ.ctx.mobility.frozen`) and `integ.nmobile` equal
#     the hand-built expectation, the undeclared fallback's and `frozen_sites`; the
#     Declared rule actually ran (the rewrite of `stiff` moves the mask from cell 2 to cells
#     1 and 3).
#  4. Negative control: the undeclared fallback twins differ in bytes (the measurement
#     sees unused quantities; the fallback is the whole state, as today), and give the
#     same masks.
# On the CPU (always): the masks are exactly today's snapshot-path masks, hand-checked
# (cell 2's 16 sites, then cells 1 and 3's 32 sites), for both algorithms and both twins;
# declared and undeclared agree; nothing is counted (every counter stays 0); the hook's
# default is `nothing`; a bad declaration is an `ArgumentError`.
#
# Today: the CPU mask testset passes except the hook checks (`frozen_reads` is not
# defined, so the declared system silently uses the fallback and the bad declaration does
# not throw); on Metal the Declared twins differ (the snapshot copies σ, every cell column,
# the model and site leaves) and exceed the bound. The Standard and fallback testsets pass.
using Potts: CorePotts

const P60V2B_ON_METAL = get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal)
const P60V2B_SLACK = 16
const P60V2B_NCELL = 32
const P60V2B_DIMS = (16, 16)
p60v2b_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)

# the three fixed cells (rows, cols) and the expected masks, by hand
const P60V2B_SQUARES = ((3:6, 3:6), (10:13, 3:6), (3:6, 10:13))
function p60v2b_expected(cells)
    m = falses(P60V2B_DIMS)
    for c in cells
        r, q = P60V2B_SQUARES[c]
        m[r, q] .= true
    end
    return Array{Bool}(m)
end
const P60V2B_STIFF0 = (2,)            # stiff[2] = 1: cell 2 frozen (16 sites)
const P60V2B_STIFF1 = (1, 3)          # after the rewrite: cells 1 and 3 (32 sites)
p60v2b_stiff(T, cells) = (s = zeros(T, P60V2B_NCELL); foreach(c -> s[c] = T(1), cells); s)

# the custom rule: sites of cells whose `stiff` > 1/2; reads σ and `stiff` only
function p60v2b_rule(u)
    σ = Array(u.σ)
    stiff = Array(u.cell.stiff)
    return map(c -> c != 0 && stiff[c] > 0.5, σ)
end

struct P60v2bDeclared end
struct P60v2bUndeclared end
struct P60v2bBad end
struct P60v2bStandard end
for S in (P60v2bDeclared, P60v2bUndeclared, P60v2bBad)
    @eval CorePotts.frozen_varies(::$S) = true
    @eval CorePotts.remake_frozen(::$S, prob, u) = p60v2b_rule(u)
end
CorePotts.frozen_kinds(::P60v2bStandard) = (Int32(2),)
const P60V2B_HOOK = isdefined(CorePotts, :frozen_reads)
if P60V2B_HOOK          # today the hook does not exist: the declared systems use the fallback
    @eval CorePotts.frozen_reads(::P60v2bDeclared) = (:σ, :stiff)
    @eval CorePotts.frozen_reads(::P60v2bBad) = (:σ, :stiff, :nonexistent)
end

function p60v2b_problem(sys; wide = false, T = Float64)
    σ = zeros(Int32, P60V2B_DIMS)
    for (c, (r, q)) in enumerate(P60V2B_SQUARES)
        σ[r, q] .= Int32(c)
    end
    n = P60V2B_NCELL
    kinds = ones(Int32, n)
    kinds[2] = 2                                    # the standard rule freezes kind 2
    cell = (; stiff = p60v2b_stiff(T, P60V2B_STIFF0))
    model = (;)
    site = (;)
    if wide
        cell = merge(cell, (; z1 = fill(T(2), n), z2 = fill(Int32(7), n), z3 = ones(T, 3, n)))
        model = (; q = T[5])
        site = (; h = fill(T(0.5), P60V2B_DIMS))
    end
    u0 = CorePotts.initial_state(σ, kinds; cell, model, site)
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T, sys)
    p = (; λ = T(100), V0 = T(16), T = T(0))
    lat = CorePotts.Lattice(P60V2B_DIMS; boundary = CorePotts.Closed())
    frozen = sys isa P60v2bStandard ? nothing : p60v2b_rule(u0)
    return CorePotts.PottsProblem(f, u0, lat, (0, 4), p; frozen)
end

"""Per-refresh counter triples and masks: one warm MCS, then three direct refreshes
(unchanged; `stiff` rewritten to P60V2B_STIFF1 in the live state; unchanged again)."""
function p60v2b_refreshes(sys, alg; backend = CPU(), wide = false, T = Float64)
    prob = p60v2b_problem(sys; wide, T)
    integ = init(prob, alg; backend, save_start = false, save_end = false)
    step!(integ)
    deltas = NTuple{3, Int}[]
    masks = Matrix{Bool}[]
    nmobile = Int[]
    for i in 1:3
        if i == 2       # a user write to the live state (not an integrator transfer)
            sys isa P60v2bStandard ? copyto!(integ.state.cell.kind, Int32[1, 1, 2, ones(Int32, P60V2B_NCELL - 3)...]) :
                copyto!(integ.state.cell.stiff, p60v2b_stiff(T, P60V2B_STIFF1))
        end
        c0 = p60v2b_counts(integ.stats)
        r = refresh_frozen!(integ)
        push!(deltas, p60v2b_counts(integ.stats) .- c0)
        @assert r === integ
        push!(masks, Array{Bool}(Array(integ.ctx.mobility.frozen)))
        push!(nmobile, integ.nmobile)
    end
    return (; deltas, masks, nmobile, integ, prob)
end
p60v2b_bound(prob) = sizeof(prob.u0.σ) + sizeof(prob.u0.cell.stiff) + prod(P60V2B_DIMS) + P60V2B_SLACK

# ---------------------------------------------------------------------------------------

@testset "P6.0v2b: fixtures differ only by quantities the rule does not read" begin
    a, b = p60v2b_problem(P60v2bDeclared()), p60v2b_problem(P60v2bDeclared(); wide = true)
    @test issubset(keys(a.u0.cell), keys(b.u0.cell)) && length(keys(b.u0.cell)) == length(keys(a.u0.cell)) + 3
    @test haskey(b.u0.model, :q) && haskey(b.u0.site, :h) && !haskey(a.u0.site, :h)
    @test all(c -> sizeof(getfield(b.u0.cell, c)) >= 8 * P60V2B_SLACK, keys(b.u0.cell))   # slack < any column
    @test a.u0.σ == b.u0.σ && a.u0.cell.stiff == b.u0.cell.stiff
    @test a.frozen == b.frozen == p60v2b_expected(P60V2B_STIFF0)
    @test count(a.frozen) == 16
    @test p60v2b_problem(P60v2bStandard()).frozen == p60v2b_expected(P60V2B_STIFF0)
    @test p60v2b_bound(a) == 1024 + 256 + 256 + 16                         # σ, stiff, mask up, slack
end

@testset "P6.0v2b: the `frozen_reads` hook" begin
    @test P60V2B_HOOK
    if P60V2B_HOOK
        @test CorePotts.frozen_reads(P60v2bUndeclared()) === nothing         # the default
        @test CorePotts.frozen_reads(P60v2bStandard()) === nothing
        @test CorePotts.frozen_reads(P60v2bDeclared()) == (:σ, :stiff)
        @test Base.ispublic(CorePotts, :frozen_reads)
    end
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test_throws ArgumentError begin
            integ = init(p60v2b_problem(P60v2bBad()), alg)
            refresh_frozen!(integ)
        end
    end
end

@testset "P6.0v2b: custom-rule masks on the CPU (today's snapshot path, hand-checked)" begin
    m0, m1 = p60v2b_expected(P60V2B_STIFF0), p60v2b_expected(P60V2B_STIFF1)
    @test count(m0) == 16 && count(m1) == 32
    N = prod(P60V2B_DIMS)
    for alg in (SequentialCPM(), CheckerboardCPM()), wide in (false, true)
        ref = p60v2b_refreshes(P60v2bUndeclared(), alg; wide)
        dec = p60v2b_refreshes(P60v2bDeclared(), alg; wide)
        for r in (ref, dec)
            @test r.masks == [m0, m1, m1]
            @test r.nmobile == [N - 16, N - 32, N - 32]
            @test r.masks[end] == frozen_sites(r.prob, r.integ.state)
            @test all(==((0, 0, 0)), r.deltas)                              # nothing counted on the CPU
            @test r.integ.state.σ == r.prob.u0.σ                            # σ fixed (T = 0)
            @test r.integ.stats.refreshes == 3
        end
        std = p60v2b_refreshes(P60v2bStandard(), alg; wide)
        @test std.masks == [m0, p60v2b_expected((3,)), p60v2b_expected((3,))]
        @test all(==((0, 0, 0)), std.deltas)
    end
    # reinit! refreshes the mask of the new state by the declared rule
    for alg in (SequentialCPM(), CheckerboardCPM())
        integ = init(p60v2b_problem(P60v2bDeclared(); wide = true), alg)
        u = deepcopy(integ.prob.u0)
        u.cell.stiff .= p60v2b_stiff(Float64, P60V2B_STIFF1)
        reinit!(integ, u)
        @test Array(integ.ctx.mobility.frozen) == m1
    end
end

@testset "P6.0v2b: custom-rule refresh copies only the declared leaves on Metal" begin
    if P60V2B_ON_METAL
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        T = Float32
        m0, m1 = p60v2b_expected(P60V2B_STIFF0), p60v2b_expected(P60V2B_STIFF1)
        N = prod(P60V2B_DIMS)
        nar = p60v2b_refreshes(P60v2bDeclared(), alg; backend, T)
        wid = p60v2b_refreshes(P60v2bDeclared(), alg; backend, T, wide = true)
        bound = p60v2b_bound(nar.prob)
        @info "P6.0v2b declared refresh (syncs, transfers, bytes)" narrow = nar.deltas wide = wid.deltas bound
        @test all(==(first(nar.deltas)), nar.deltas)                        # steady
        @test wid.deltas == nar.deltas                                      # unused quantities: not moved
        @test all(d -> d[3] <= bound, nar.deltas)
        for r in (nar, wid)
            @test r.masks == [m0, m1, m1]                                   # the rule ran on the new stiff
            @test r.nmobile == [N - 16, N - 32, N - 32]
            @test r.integ.stats.refreshes == 3
            @test Array(r.integ.state.σ) == r.prob.u0.σ
        end
        # negative control: the undeclared fallback (whole state) sees the unused quantities
        fn = p60v2b_refreshes(P60v2bUndeclared(), alg; backend, T)
        fw = p60v2b_refreshes(P60v2bUndeclared(), alg; backend, T, wide = true)
        @info "P6.0v2b fallback refresh (syncs, transfers, bytes)" narrow = fn.deltas wide = fw.deltas
        @test all(i -> fw.deltas[i][3] > fn.deltas[i][3], 1:3)
        @test fn.masks == fw.masks == nar.masks
        @test fn.nmobile == nar.nmobile
        # the same rule on the CPU (Float32) gives the same masks
        cpu = p60v2b_refreshes(P60v2bDeclared(), alg; T, wide = true)
        @test cpu.masks == nar.masks
        # a bad declaration fails on the device too
        @test_throws ArgumentError begin
            integ = init(p60v2b_problem(P60v2bBad(); T), alg; backend)
            refresh_frozen!(integ)
        end
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end

@testset "P6.0v2b: standard-rule refresh on Metal (device, twin-invariant)" begin
    if P60V2B_ON_METAL
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        nar = p60v2b_refreshes(P60v2bStandard(), alg; backend, T = Float32)
        wid = p60v2b_refreshes(P60v2bStandard(), alg; backend, T = Float32, wide = true)
        @info "P6.0v2b standard refresh (syncs, transfers, bytes)" narrow = nar.deltas wide = wid.deltas
        @test all(==(first(nar.deltas)), nar.deltas)
        @test wid.deltas == nar.deltas
        @test all(d -> d[3] <= P60V2B_SLACK, nar.deltas)                    # the counts only (12 B)
        @test nar.masks == wid.masks == [p60v2b_expected((2,)), p60v2b_expected((3,)), p60v2b_expected((3,))]
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end
