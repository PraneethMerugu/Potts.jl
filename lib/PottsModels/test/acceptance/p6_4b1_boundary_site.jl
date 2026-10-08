# P6.4b1 (ROADMAP Phase 6; D-177): `BoundarySiteCPM`, a sweep algorithm that draws only
# boundary sites and accounts the skipped interior (null) picks exactly, so that it is
# statistically identical to `SequentialCPM` and MCS time means the same thing. Frozen
# (AUTONOMY §7.3). Decisions: D-177 (the design), D-051 item 2 (whole-MCS paths cost
# nothing), D-052 (plain Metropolis on the model's proposal; no Hastings correction here),
# D-158 (our own code's recorded values are bitwise; same-session determinism is free),
# D-171 (the A/B decides speed; `gate.jl` checks warm allocations), D-048 (ordinary tests:
# independent oracles and negative controls, no parity harness).
#
# Definitions used throughout.
# - N is the number of mobile sites (`integrator.nmobile`), K the number of offsets of the
#   algorithm's proposal neighbourhood (the algorithm's `proposal`, else the problem's).
# - The boundary set B(σ) is the set of mobile sites t with at least one offset o of the
#   proposal neighbourhood such that the shifted site s = t + o lies on the lattice (wrapped
#   on periodic axes), s is mobile, and σ[s] ≠ σ[t]. Every SequentialCPM pick outside B is a
#   null move (`sequential_mcs!`: off-lattice, frozen source or like owner), so only picks
#   in B can change the state.
# - The reference chain is SequentialCPM's: one MCS is N attempts; an attempt draws a
#   target uniformly among the N mobile sites and a direction uniformly among all K offsets
#   (off-lattice and like-owner directions are null), then applies the constraint and the
#   acceptance law. BoundarySiteCPM must have the same law of the state after every whole
#   MCS, the same `stats.attempts` (N per MCS) and a `stats.accepted` that counts its
#   committed copies (the law of that count equals SequentialCPM's).
#
# What is pinned (one testset group per item of the P6.4b1 dispatch).
#  1. API. `BoundarySiteCPM(; acceptance = nothing, proposal = nothing)` is a
#     `CorePotts.CPMAlgorithm`, exported by CorePotts and Potts, with SequentialCPM's two
#     keywords and defaults (`nothing` = the model's law / the problem's proposal);
#     `BoundarySiteCPM(; proposal = Moore(1))` overrides as for SequentialCPM. It is
#     accepted wherever SequentialCPM is: `solve` (with `saveat`, callbacks), `init` +
#     `step!`, `reinit!`, `EnsembleProblem` (serial and threads), `checkpoint` continuation,
#     `Potts.anneal(…; alg)`, models with a lifecycle, a frozen kind, a tracked ΔH
#     (`track = (:ΔH,)`: `stats.accepted_ΔH` exact after every step, as under SequentialCPM).
#     SequentialCPM is unchanged: its fields, and two recorded bitwise results of our own
#     code (D-158) recorded on the freeze base (5f69e790): Graner–Glazier 72², 25 MCS, and
#     the OpenVT reference model on 60² with divisions, 1600 MCS. Its other pins stay where
#     they are and keep passing unchanged (they are frozen files): the exact transition
#     oracles `lib/CorePotts/test/oracle.jl` and `test/oracle.jl`, the fingerprints of
#     `p6_0ah_canonical_term_order.jl` and `p6_0af_lifecycle_followups.jl`, the bitwise rows
#     of `p6_0x_gather_ode_alloc.jl`, and the gate rows (`benchmark/gate.jl` `sequential`).
#  2. Exact law on an enumerable system (2×4 closed lattice, Moore(1) proposal and contacts,
#     two cells of kinds A and B plus medium, area and adhesion energy, `no_extinction`,
#     Metropolis at T = 3; 6050 states). An independent oracle (module `P64b1Oracle`, no
#     production code) re-derives SequentialCPM's one-attempt kernel from the definition
#     above and solves for its stationary law π exactly (sparse LU; residual < 1e-12, π > 0).
#     (a) Stationarity: R = 40 000 runs whose start states are drawn from π (StableRNG
#         177_401), K_STAT = 4 MCS each; the end states must follow π.
#     (b) Finite time: R = 40 000 runs from the fixed σ0 = column 1 cell 1, column 2 cell 2,
#         columns 3–4 medium (sites 7 and 8 are interior at t = 0); the states at MCS 1
#         and MCS 2 must follow the oracle's exact laws δ(σ0)·P^N and δ(σ0)·P^2N. This is the
#         exact form of "MCS time means the same thing".
#     SequentialCPM runs the same protocol as the positive control of the oracle–model
#     match (it passes on the freeze base).
#  3. Time equivalence on a mostly-medium lattice (60² closed, four 5×5 cells, 2.8 %
#     cover): per-run accepted copies in MCS 1 (mean and variance), accepted copies over
#     MCS 1–10 (mean), and the mean squared centroid displacement over 10 MCS (mean) of
#     BoundarySiteCPM against SequentialCPM, two-sample, 2000 runs each.
#  4. Incremental boundary set. Exposure (pinned): `Potts.CorePotts._boundary_sites(integ)`
#     returns the integrator's current boundary set as a collection of linear site indices
#     (any order, each index once); the storage is the implementer's choice. It must equal
#     the test's from-scratch B(σ) (computed here from σ, the kinds' frozen flags and the
#     proposal offsets; no production code) after `init`, after every `step!` (copies,
#     divisions, removals, a transition to a frozen kind, the removal of a frozen cell),
#     after `reinit!`, and after a direct write to `integ.state.σ` followed by
#     `u_modified!(integ, true)`. On a periodic lattice (Graner–Glazier 72²), on the
#     OpenVT reference model with divisions, and with a proposal that differs from the
#     contact neighbourhood (`BoundarySiteCPM(; proposal = VonNeumann(1))` on a Moore(1)
#     model).
#  5. Ensemble check on the published OpenVT model, case (a)/(b) growth (D-173 protocol:
#     `OpenVTReferenceMonolayer` at its Table S1 defaults, one disc cell). Growth curves
#     L(τ) = log₂ N at τ cycles (775 MCS per cycle) under BoundarySiteCPM and
#     SequentialCPM must agree (SMOKE always; FULL under POTTS_FULL_REPRODUCTION=true or
#     REPRO=full, offline on the PC, D-157).
#  6. Performance. Zero warm allocations per MCS (min over 5 `step!`, the gate's rule) on
#     Graner–Glazier 72², the gate's `openvt_reference_100` case and a 400² mostly-medium
#     lattice. The speed-up over SequentialCPM on 400² at 5.2 % cover (169 cells of 7×7) is
#     measured and reported (`@info`) on every run; the floor ≥ 1.5× is asserted only under
#     the benchmark harness convention: `POTTS_BENCH_PINNED=1` (a pinned, single-threaded
#     process on the NucBox, as `machine.jl` `pin_or_reexec` and `ab.jl` set it; run alone,
#     under `tools/exclusive.sh`). The SequentialCPM gate is unchanged: decided by
#     `ab.jl <base> <candidate> all cpu` (D-171), outside this file.
#  7. Determinism (D-158, the free kind). The same seed gives bitwise the same states and
#     statistics under BoundarySiteCPM: two `solve`s, `solve` against `init` + `step!`, and
#     `EnsembleSerial` against `EnsembleThreads`. Different seeds differ (control). It need
#     not equal SequentialCPM bitwise (D-177).
#
# Statistics and false-failure rates (each check ≤ 1e-3; derivations here, used below).
# - χ² (items 2a, 2b): Pearson's statistic of the R end states against the exact law, bins
#   with expected count < 5 pooled into one, as a Wilson–Hilferty z-score
#   z = ((X/k)^(1/3) − (1 − 2/(9k))) / √(2/(9k)), k = bins − 1, which is ≈ N(0, 1) when the
#   sampler follows the law (the oracle of `lib/CorePotts/test/oracle_core.jl`). Pass iff
#   z < Z_CHI = 3.72: one-sided P(N(0,1) > 3.72) = 1.0e-4 per check (k is 46–72 here, where
#   the WH approximation is accurate to well within a factor 2 at that tail).
#   Power, computed with the oracle on the freeze base (multinomial R = 40 000, StableRNG):
#   against the stationary law the wrong temperature T = 3.75 gives z ≈ 52; a variant that
#   draws N boundary picks per MCS with no skip accounting ("miscounts time", stationary law
#   ∝ π·|B|/N) gives z ≈ 27 after 4 MCS from π; a variant that draws the source among the
#   unlike neighbours of a boundary site gives z ≈ 43; at MCS 1 from σ0 the no-skip variant
#   gives z ≈ 46. These are pinned as negative controls of the statistic (samples drawn from
#   the wrong laws must give z > Z_CHI; samples from the right law must give z < Z_CHI), and
#   the production samples of both algorithms must also be rejected against the no-skip
#   variant's law (z > Z_CHI): the implementation is not that variant.
# - Two-sample z (item 3): Welch z = (x̄ − ȳ)/√(s²ₓ/n + s²ᵧ/m) for means (n = m = 2000;
#   CLT), pass iff |z| ≤ Z_MEAN = 3.29 (two-sided 1.0e-3). Variances: z = (s²ₓ − s²ᵧ)/
#   √(V̂ₓ + V̂ᵧ) with V̂ = (m₄ − s⁴)/n (the asymptotic variance of a sample variance, m₄ the
#   fourth central moment); pass iff |z| ≤ Z_VAR = 3.48 (two-sided 5e-4, half the budget, for
#   the slower convergence of the variance's normal limit). Negative control (no
#   BoundarySiteCPM involved): SequentialCPM at 10 MCS against SequentialCPM at 15 MCS
#   (other seeds), i.e. time miscounted by 1.5×, must give |z| > Z_MEAN for the 10-MCS
#   accepted count and for the MSD.
# - Growth curves, SMOKE (item 5): an exact two-sample permutation test (all C(16, 8) =
#   12 870 splits of 8 + 8 runs) of S = max over τ of |L̄₁(τ) − L̄₂(τ)| / sd(τ) (sd over all
#   16 runs, the same for every split; grid points with sd = 0 skipped). p = share of
#   splits with S ≥ S_obs; pass iff p ≥ P_PERM = 1e-3. Under equal laws the runs are
#   exchangeable, so P(p < 1e-3) ≤ 1e-3 exactly. Negative control: SequentialCPM against
#   SequentialCPM (other seeds) read at τ/1.25 (time miscounted by 1.25×) must give
#   p < P_PERM (the smallest attainable p is 2/12 870 = 1.6e-4).
# - Growth curves, FULL (item 5): 100 runs per algorithm; Welch z at each τ of
#   T_N = 0.5:1:8.5 and for the mean time to 1000 cells: 10 checks at |z| ≤ Z_FULL = 3.89
#   (two-sided 1.0e-4 each; ≤ 1e-3 together). Negative control: the same comparison with
#   BoundarySiteCPM's time scaled by 1.1 must fail at least one check.
#
# Tiers and cost (measured on the freeze base with a stub BoundarySiteCPM ≡ SequentialCPM,
# Apple M1 Pro, one thread; the real algorithm only makes its halves cheaper).
# - Always (the PottsModels suite): items 1–4, 6 (allocations, reported speed-up), 7, and
#   item 5 SMOKE: about 1.5 min of tests (SMOKE 52 s, the 2×4 samples 2 × 5 s, item 3 5 s)
#   plus the models' compilation, ~3–4 min in all.
# - POTTS_BENCH_PINNED=1: the ≥ 1.5× floor of item 6 (a few seconds of timing).
# - FULL: item 5 at 400² to 1000 cells, 100 + 100 runs (~1 h on the NucBox, threaded).
#
# Today (freeze base 5f69e790) this file fails because `BoundarySiteCPM` does not exist
# (`UndefVarError: BoundarySiteCPM not defined`, and `_boundary_sites` is missing) in every
# testset that names it. The SequentialCPM halves of items 2, 3 and 5, the oracle checks,
# every negative control of a statistic, the boundary-set recompute's own controls and the
# recorded SequentialCPM values pass on the base.
using Test, Potts, PottsModels
using Potts: CorePotts
using Statistics: mean, var
using StableRNGs: StableRNG
using SHA: sha256
using SparseArrays: sparse

const P64B1_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P64B1_BENCH = get(ENV, "POTTS_BENCH_PINNED", "") == "1"

const P64B1_Z_CHI = 3.72
const P64B1_Z_MEAN = 3.29
const P64B1_Z_VAR = 3.48
const P64B1_P_PERM = 1e-3
const P64B1_Z_FULL = 3.89
const P64B1_SPEEDUP = 1.5

# The algorithm under test, constructed only inside testsets (it does not exist on the base).
p64b1_bs(; kw...) = Potts.BoundarySiteCPM(; kw...)
const P64B1_MOORE = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
const P64B1_VN = [(1, 0), (-1, 0), (0, 1), (0, -1)]

# ---------------------------------------------------------------------------------------
# The independent oracle (item 2): SequentialCPM's chain from its definition, and the
# wrong variants used as negative controls. No production code.

module P64b1Oracle

using SparseArrays: sparse

struct Tiny
    dims::Tuple{Int, Int}
    offs::Vector{Tuple{Int, Int}}     # proposal = contact neighbourhood (Moore(1))
    kinds::Vector{Int}                # kind of cell c (medium = 0)
    J::Matrix{Float64}                # indexed by kind + 1
    λ::Float64
    V0::Float64
    T::Float64
end
with_T(m::Tiny, T) = Tiny(m.dims, m.offs, m.kinds, m.J, m.λ, m.V0, T)

nsite(m::Tiny) = prod(m.dims)
lin(m::Tiny, x, y) = x + (y - 1) * m.dims[1]
coords(m::Tiny, i) = (mod1(i, m.dims[1]), cld(i, m.dims[1]))
function nbr(m::Tiny, i, o)                       # closed lattice: 0 off the lattice
    x, y = coords(m, i)
    u, v = x + o[1], y + o[2]
    (1 <= u <= m.dims[1] && 1 <= v <= m.dims[2]) || return 0
    return lin(m, u, v)
end
kslot(m::Tiny, c) = c == 0 ? 1 : m.kinds[c] + 1
"""Total energy: J per unordered unlike neighbour pair, λ(V − V0)² per cell."""
function H(m::Tiny, σ)
    h = 0.0
    for i in 1:nsite(m), o in m.offs
        j = nbr(m, i, o)
        j == 0 && continue
        σ[i] != σ[j] && (h += m.J[kslot(m, σ[i]), kslot(m, σ[j])] / 2)
    end
    for c in eachindex(m.kinds)
        h += m.λ * (count(==(c), σ) - m.V0)^2
    end
    return h
end
pacc(m::Tiny, dH) = dH <= 0 ? 1.0 : exp(-dH / m.T)

"""Every σ ∈ {0, …, ncell}^N in which every cell owns at least one site (`no_extinction`)."""
function states(m::Tiny)
    N, C = nsite(m), length(m.kinds)
    out = Vector{Vector{Int8}}()
    for code in 0:((C + 1)^N - 1)
        σ = Vector{Int8}(undef, N)
        r = code
        for i in 1:N
            σ[i] = r % (C + 1)
            r ÷= (C + 1)
        end
        all(c -> any(==(c), σ), 1:C) && push!(out, σ)
    end
    return out
end

"""The boundary set: sites with a proposal neighbour on the lattice of another owner."""
boundary(m::Tiny, σ) = [t for t in 1:nsite(m) if any(o -> (s = nbr(m, t, o); s != 0 && σ[s] != σ[t]), m.offs)]

"""
One-attempt kernel as rows of (j, p), for `law`:
- `:sequential` — SequentialCPM: target uniform over all N sites, direction uniform over K;
- `:no_skip` (wrong) — target uniform over the boundary set B (no accounting for the
  skipped interior picks: N boundary picks per MCS), direction uniform over K;
- `:unlike` (wrong) — with probability |B|/N a target uniform in B, the source uniform over
  its unlike on-lattice neighbours.
A copy that removes a cell's last site is rejected (`no_extinction`).
"""
function kernel(m::Tiny, S, index; law::Symbol = :sequential)
    N, K = nsite(m), length(m.offs)
    rows = Vector{Vector{Tuple{Int, Float64}}}(undef, length(S))
    for (i, σ) in enumerate(S)
        acc = Dict{Int, Float64}()
        add!(j, w) = (acc[j] = get(acc, j, 0.0) + w)
        h = H(m, σ)
        B = boundary(m, σ)
        function attempt!(t, s, w)
            if s == 0 || σ[s] == σ[t]
                add!(i, w)
                return
            end
            a = σ[t]
            if a != 0 && count(==(a), σ) == 1
                add!(i, w)
                return
            end
            σ′ = copy(σ)
            σ′[t] = σ[s]
            p = pacc(m, H(m, σ′) - h)
            add!(index[σ′], w * p)
            add!(i, w * (1 - p))
        end
        if law === :sequential
            for t in 1:N, o in m.offs
                attempt!(t, nbr(m, t, o), 1 / (N * K))
            end
        elseif law === :no_skip
            isempty(B) && add!(i, 1.0)
            for t in B, o in m.offs
                attempt!(t, nbr(m, t, o), 1 / (length(B) * K))
            end
        elseif law === :unlike
            add!(i, 1 - length(B) / N)
            for t in B
                U = [s for s in (nbr(m, t, o) for o in m.offs) if s != 0 && σ[s] != σ[t]]
                for s in U
                    attempt!(t, s, 1 / (N * length(U)))
                end
            end
        else
            throw(ArgumentError("law $law"))
        end
        rows[i] = [(j, w) for (j, w) in acc]
    end
    return rows
end

function apply(rows, v)
    w = zeros(length(v))
    for i in eachindex(rows)
        vi = v[i]
        vi == 0 && continue
        for (j, p) in rows[i]
            w[j] += vi * p
        end
    end
    return w
end
"""The law after one MCS (N attempts)."""
mcs(m::Tiny, rows, v) = foldl((u, _) -> apply(rows, u), 1:nsite(m); init = v)

"""The stationary law of `rows`: πP = π, Σπ = 1, by a sparse LU solve."""
function stationary(rows)
    n = length(rows)
    I = Int[]; Jx = Int[]; V = Float64[]
    for i in 1:n, (j, p) in rows[i]
        j == 1 && continue                         # row 1 of (Pᵀ − I) is replaced by Σπ = 1
        push!(I, j); push!(Jx, i); push!(V, p)
    end
    for j in 2:n
        push!(I, j); push!(Jx, j); push!(V, -1.0)
    end
    for i in 1:n
        push!(I, 1); push!(Jx, i); push!(V, 1.0)
    end
    b = zeros(n)
    b[1] = 1.0
    return sparse(I, Jx, V, n, n) \ b
end

tv(p, q) = sum(abs, p .- q) / 2

"""
Pearson χ² of `counts` (length n + 1: the last entry counts states outside the space)
against the law `p` (length n), bins with expected count < 5 pooled, as a Wilson–Hilferty
z-score. Returns (z, k).
"""
function chi2_z(p, counts, R)
    X = 0.0; k = -1
    pe = 0.0; pc = counts[end]
    for i in eachindex(p)
        if R * p[i] >= 5
            X += (counts[i] - R * p[i])^2 / (R * p[i])
            k += 1
        else
            pe += p[i]; pc += counts[i]
        end
    end
    if pe > 0
        X += (pc - R * pe)^2 / (R * pe)
        k += 1
    elseif pc > 0
        return Inf, k
    end
    return ((X / k)^(1 / 3) - (1 - 2 / (9k))) / sqrt(2 / (9k)), k
end

"""Indices of R draws from the law `p` (inverse CDF; `rng` a StableRNG)."""
function draws(p, R, rng)
    c = cumsum(p)
    return [min(searchsortedfirst(c, rand(rng) * c[end]), length(p)) for _ in 1:R]
end
function multinomial(p, R, rng)
    cnt = zeros(Int, length(p) + 1)
    for i in draws(p, R, rng)
        cnt[i] += 1
    end
    return cnt
end

end # module P64b1Oracle

# ---------------------------------------------------------------------------------------
# Fixtures

# Item 2: the enumerable system (the oracle's `Tiny` with the same numbers).
@potts_model P64b1Tiny begin
    @structural_parameters begin
        lattice = (2, 4)
    end
    @kinds medium A B
    @parameters begin
        λ = 1.0
        V₀ = 2.0
        T = 3.0
        J[kind, kind] = [0.0 4.0 6.0; 4.0 2.0 5.0; 6.0 5.0 3.0]
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end
const P64B1_TINY = P64b1Oracle.Tiny((2, 4), P64B1_MOORE, [1, 2], [0.0 4.0 6.0; 4.0 2.0 5.0; 6.0 5.0 3.0], 1.0, 2.0, 3.0)
const P64B1_σ0 = Int8[1, 1, 2, 2, 0, 0, 0, 0]          # column-major 2×4
const P64B1_R = 40_000
const P64B1_K_STAT = 4
p64b1_tiny_op(σ) = [ownership => reshape(Int32.(σ), P64B1_TINY.dims), kind => [:A, :B]]
p64b1_tiny_problem(σ = P64B1_σ0, tspan = (0, 2)) = PottsProblem(P64b1Tiny(; name = :p64b1_tiny), p64b1_tiny_op(σ), tspan)

# Items 3, 6 (and the tracked-ΔH check of item 1): a mostly-medium lattice. Integer
# energies, so Σ accepted ΔH is exact in Float64.
@potts_model P64b1Free begin
    @structural_parameters begin
        lattice = (60, 60)
    end
    @kinds medium A
    @parameters begin
        λ = 1.0
        V₀ = 25.0
        T = 5.0
        J[kind, kind] = [0.0 8.0; 8.0 4.0]
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end
"""`side × side` cells with lower-left corners at `first:spacing:…` in both axes."""
function p64b1_grid(L, side, first, spacing)
    σ = zeros(Int32, L, L)
    k = 0
    for a in first:spacing:(L - side + 1), b in first:spacing:(L - side + 1)
        k += 1
        σ[a:(a + side - 1), b:(b + side - 1)] .= k
    end
    return σ, k
end
function p64b1_free_problem(; L = 60, side = 5, first = 15, spacing = 30, tspan = (0, 15), kw...)
    σ, n = p64b1_grid(L, side, first, spacing)
    return PottsProblem(P64b1Free(; name = Symbol(:p64b1_free, L), lattice = (L, L)),
        [ownership => σ, kind => fill(:A, n), :V₀ => Float64(side^2)], tspan; kw...)
end
"""Centroids (mean site index) of cells 1:n from σ (closed lattice, no wrap)."""
function p64b1_centroids(σ, n)
    s = zeros(n, 2); v = zeros(Int, n)
    for I in CartesianIndices(σ)
        c = σ[I]
        (1 <= c <= n) || continue
        s[c, 1] += I[1]; s[c, 2] += I[2]; v[c] += 1
    end
    return [(s[c, 1] / v[c], s[c, 2] / v[c]) for c in 1:n]
end

# Item 4: copies, divisions, removals, a transition to a frozen kind and the removal of a
# frozen cell, through CorePotts' public hand-written `Lifecycle` (Potts has no `@remove`;
# installed with `remake(prob; f = …)` as in P6.0v1). The model's `@divide` never fires; it
# gives the moments. Events (trigger MCS): 2 cell 1 divides; 3 cell 2 is removed; 4 cell 3
# becomes `wall` (frozen); 5 cell 4 divides (its daughter takes the lowest free slot, 2);
# 7 cell 3 (the wall) is removed, so its sites become mobile medium.
@potts_model P64b1Life begin
    @kinds medium A wall[frozen]
    @parameters begin
        λ = 2.0
        T = 2.0
        J[kind, kind] = [0.0 6.0 6.0; 6.0 3.0 6.0; 6.0 6.0 3.0]
    end
    @variables V_target(cell) = 16.0
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(A) => λ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @constraint no_extinction
    @divide cells(A) when = volume >= 10000
    @sweep Metropolis(; temperature = T)
end
struct P64b1Events end
function (::P64b1Events)(st, p, ctx, key, mcs, c)
    mcs == 2 && c == 1 && return EVENT_DIVIDE
    mcs == 3 && c == 2 && return EVENT_REMOVE
    mcs == 4 && c == 3 && return EVENT_TRANSITION
    mcs == 5 && c == 4 && return EVENT_DIVIDE
    mcs == 7 && c == 3 && return EVENT_REMOVE
    return EVENT_NONE
end
struct P64b1Normal end
(::P64b1Normal)(st, p, ctx, key, mcs, c) = (1.0f0, 0.0f0)
struct P64b1WallKind end
(::P64b1WallKind)(st, p, ctx, key, mcs, c) = Int32(2)
struct P64b1Halve end
function (::P64b1Halve)(st, p, ctx, key, mcs, parent, daughter)
    v = st.cell.V_target[parent] / 2
    st.cell.V_target[parent] = v
    st.cell.V_target[daughter] = v
    return nothing
end
function p64b1_life_problem(; tspan = (0, 10), seed = 4)
    σ = zeros(Int32, 24, 24)
    σ[3:6, 3:6] .= 1; σ[3:6, 15:18] .= 2; σ[15:18, 3:6] .= 3; σ[15:18, 15:18] .= 4
    prob = PottsProblem(P64b1Life(; name = :p64b1_life), [ownership => σ, kind => fill(:A, 4)], tspan;
        capacity = 8, seed)
    f = prob.f
    lc = Lifecycle(P64b1Events(); normal = P64b1Normal(), kind = P64b1WallKind(), divide! = P64b1Halve())
    g = CPMFunction(f.delta_H; f.commit!, f.constraint, f.claims, f.reads, f.temperature, f.bias, f.phases,
        lifecycle = lc, f.acceptance, f.footprint, f.fingerprint, f.sys)
    return remake(prob; f = g)
end

"""
The from-scratch boundary set (item 4): mobile sites with a mobile proposal neighbour (on
the lattice; wrapped when `periodic`) of another owner. `frozen_kinds` are the kind indices
whose cells are frozen (their sites are not mobile). Independent of production code.
"""
function p64b1_boundary(σ, kinds, offsets; periodic = false, frozen_kinds = ())
    dims = size(σ)
    mobile(I) = (c = σ[I]; c == 0 || !(Int(kinds[c]) in frozen_kinds))
    B = Int[]
    L = LinearIndices(σ)
    for I in CartesianIndices(σ)
        mobile(I) || continue
        for o in offsets
            J = Tuple(I) .+ o
            if periodic
                J = mod1.(J, dims)
            elseif !all(1 .<= J .<= dims)
                continue
            end
            K = CartesianIndex(J)
            (mobile(K) && σ[K] != σ[I]) || continue
            push!(B, L[I])
            break
        end
    end
    return B
end
"""The integrator's boundary set equals the recompute, with no duplicate index."""
function p64b1_boundary_ok(integ, offsets; kw...)
    got = collect(Int, CorePotts._boundary_sites(integ))
    want = p64b1_boundary(integ.state.σ, integ.state.cell.kind, offsets; kw...)
    return allunique(got) && Set(got) == Set(want)
end

# Item 6 and the recorded SequentialCPM values: the gate's cases.
p64b1_gg_problem(; tspan = (0, 10^6), seed = 1) =
    (gg = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :p64b1_gg), [ownership => gg[1], kind => gg[2]], tspan; seed))
function p64b1_openvt100_problem()
    σ = zeros(Int32, 100, 100)
    foreach(((k, (a, b)),) -> σ[29 + 7a .+ (1:7), 29 + 7b .+ (1:7)] .= k, enumerate(Iterators.product(0:5, 0:5)))
    return PottsProblem(OpenVTReferenceMonolayer(; name = :p64b1_r100, lattice = (100, 100)),
        [ownership => σ, kind => fill(:cell, 36), :σ_X => 0.0], (0, 10^6); capacity = 128)
end
p64b1_openvt_problem(L; tspan = (0, 10^6), seed = 1, capacity = 64) =
    PottsProblem(OpenVTReferenceMonolayer(; name = Symbol(:p64b1_ovt, L), lattice = (L, L)),
        openvt_reference_state(; lattice = (L, L)), tspan; capacity, seed)

p64b1_sha(σ) = bytes2hex(sha256(reinterpret(UInt8, vec(Array{Int32}(σ)))))
function p64b1_warm_allocs(integ)          # a function barrier, as in benchmark/gate.jl
    m = typemax(Int)
    for _ in 1:5
        m = min(m, @allocated step!(integ))
    end
    return m
end
function p64b1_warm_ns(prob, alg; samples = 30)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ); step!(integ)
    best = typemax(UInt64)
    for _ in 1:samples
        t0 = time_ns()
        step!(integ)
        best = min(best, time_ns() - t0)
    end
    return best / length(integ.state.σ)
end

# Two-sample statistics (item 3).
p64b1_welch(x, y) = (mean(x) - mean(y)) / sqrt(var(x) / length(x) + var(y) / length(y))
function p64b1_var_z(x, y)
    se2(v) = (m = mean(v); s2 = mean(abs2, v .- m); (mean(t -> (t - m)^4, v) - s2^2) / length(v))
    return (var(x) - var(y)) / sqrt(se2(x) + se2(y))
end

# ---------------------------------------------------------------------------------------
# 1. API

@testset "P6.4b1: BoundarySiteCPM is a public algorithm with SequentialCPM's keywords" begin
    @test isdefined(CorePotts, :BoundarySiteCPM) && Base.isexported(CorePotts, :BoundarySiteCPM)
    @test isdefined(Potts, :BoundarySiteCPM) && Base.isexported(Potts, :BoundarySiteCPM)
    @test Potts.BoundarySiteCPM === CorePotts.BoundarySiteCPM
    a = p64b1_bs()
    @test a isa CorePotts.CPMAlgorithm
    @test Potts.SciMLBase.isdiscrete(a)
    @test fieldnames(typeof(a)) == (:acceptance, :proposal)
    @test a.acceptance === nothing && a.proposal === nothing
    @test p64b1_bs(; proposal = Moore(1)).proposal == Moore(1)
    @test p64b1_bs(; acceptance = Barker()).acceptance == Barker()
    # SequentialCPM itself is unchanged
    @test fieldnames(SequentialCPM) == (:acceptance, :proposal)
    @test SequentialCPM().acceptance === nothing && SequentialCPM().proposal === nothing
    @test !(a isa SequentialCPM) && !(a isa CheckerboardCPM)
end

@testset "P6.4b1: BoundarySiteCPM is accepted wherever SequentialCPM is" begin
    prob = p64b1_free_problem(; tspan = (0, 6), seed = 11)
    N = 60 * 60
    # solve, saveat, callbacks
    hits = Ref(0)
    cb = DiscreteCallback((u, t, integ) -> true, integ -> (hits[] += 1); save_positions = (false, false))
    sol = solve(prob, p64b1_bs(); saveat = [2, 4], callback = cb)
    @test Symbol(sol.retcode) === :Success
    @test sol.t == [0, 2, 4, 6] && hits[] == 6
    @test sol.stats.mcs == 6 && sol.stats.attempts == 6N          # N attempts per MCS, over all sites
    @test sol.stats.accepted > 0                                    # counted (not −1, the checkerboard's)
    u = sol.u[end]
    @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
    # init + step! = solve, bitwise (free determinism, D-158)
    integ = init(prob, p64b1_bs(); save_start = false)
    for _ in 1:6
        step!(integ)
    end
    @test integ.state.σ == u.σ && integ.stats.accepted == sol.stats.accepted && integ.stats.attempts == 6N
    # the proposal keyword overrides the problem's, as for SequentialCPM
    @test Symbol(solve(prob, p64b1_bs(; proposal = VonNeumann(1))).retcode) === :Success
    @test Symbol(solve(prob, p64b1_bs(; acceptance = Barker())).retcode) === :Success
    # reinit! restarts the same trajectory
    reinit!(integ)
    for _ in 1:6
        step!(integ)
    end
    @test integ.state.σ == u.σ && integ.stats.accepted == sol.stats.accepted
    # EnsembleProblem
    ens = solve(EnsembleProblem(prob; prob_func = (q, ctx) -> q), p64b1_bs(), EnsembleSerial(); trajectories = 2)
    @test length(ens.u) == 2 && all(s -> Symbol(s.retcode) === :Success, ens.u)
    # checkpoint continuation runs (equal in law, not pinned bitwise; see D-177's notes)
    i2 = init(prob, p64b1_bs(); save_start = false)
    step!(i2); step!(i2)
    ck = checkpoint(i2)
    i3 = init(prob, p64b1_bs(); checkpoint = ck, save_start = false)
    @test i3.t == 2
    while i3.t < 6
        step!(i3)
    end
    @test i3.stats.attempts == 6N
    v = i3.u
    @test v.cell.volume == [count(==(c), v.σ) for c in eachindex(v.cell.volume)]
    # anneal
    w = Potts.anneal(prob; mcs = 3, alg = p64b1_bs())
    @test w.cell.volume == [count(==(c), w.σ) for c in eachindex(w.cell.volume)]
    @test total_energy(prob, w) <= total_energy(prob, prob.u0)      # T = 0: no uphill copy
    # a model with a lifecycle and a frozen kind
    lsol = solve(p64b1_life_problem(), p64b1_bs())
    @test Symbol(lsol.retcode) === :Success
    @test lsol.stats.lifecycle.divisions == 2 && lsol.stats.lifecycle.removals == 2
    # a published model with divisions (OpenVT reference, X ≡ 2: the first division by ~800 MCS)
    osol = solve(remake(p64b1_openvt_problem(60; tspan = (0, 1000)); p = [:σ_X => 0.0]), p64b1_bs())
    @test Symbol(osol.retcode) === :Success && osol.stats.lifecycle.divisions >= 1
end

@testset "P6.4b1: tracked ΔH is exact after every step under BoundarySiteCPM" begin
    # integer energies, no drive, `no_extinction` (no killing credit): Σ accepted ΔH = H(t) − H(0)
    prob = p64b1_free_problem(; tspan = (0, 8), seed = 12, track = (:ΔH,))
    integ = init(prob, p64b1_bs(); save_start = false)
    H0 = total_energy(prob, integ.u)
    ok = true
    for _ in 1:8
        step!(integ)
        ok &= integ.stats.accepted_ΔH == total_energy(prob, integ.u) - H0
    end
    @test ok
    @test integ.stats.accepted > 0
    # control: the same check holds on SequentialCPM (the base's semantics)
    is = init(prob, SequentialCPM(); save_start = false)
    for _ in 1:8
        step!(is)
    end
    @test is.stats.accepted_ΔH == total_energy(prob, is.u) - H0
end

# Recorded on the freeze base (5f69e790, this Mac) with SequentialCPM; our own code, so
# bitwise (D-158). The sha256 is of σ's Int32 bytes, column-major.
const P64B1_SEQ_GG = (; sha = "4c32e24553c6780481d0780f45310c7f12cdc045927987e4ebe7da33f0db4186", accepted = 7433)
const P64B1_SEQ_OPENVT = (; sha = "afecb651b63c0fbe43c6374a9e19bac82dfe5ecd39b70bbc9e07916e954e0c71", accepted = 25877, divisions = 1)

@testset "P6.4b1: SequentialCPM results are unchanged (recorded on the base)" begin
    s = solve(p64b1_gg_problem(; tspan = (0, 25), seed = 177), SequentialCPM(); save_start = false)
    @test p64b1_sha(s.u[end].σ) == P64B1_SEQ_GG.sha
    @test s.stats.accepted == P64B1_SEQ_GG.accepted
    o = solve(p64b1_openvt_problem(60; tspan = (0, 1600), seed = 177), SequentialCPM(); save_start = false)
    @test p64b1_sha(o.u[end].σ) == P64B1_SEQ_OPENVT.sha
    @test o.stats.accepted == P64B1_SEQ_OPENVT.accepted
    @test o.stats.lifecycle.divisions == P64B1_SEQ_OPENVT.divisions
    (p64b1_sha(s.u[end].σ) == P64B1_SEQ_GG.sha && p64b1_sha(o.u[end].σ) == P64B1_SEQ_OPENVT.sha) ||
        @info "P6.4b1 SequentialCPM values" gg = (p64b1_sha(s.u[end].σ), s.stats.accepted) openvt = (
            p64b1_sha(o.u[end].σ), o.stats.accepted, o.stats.lifecycle.divisions)
end

# ---------------------------------------------------------------------------------------
# 2. Exact law on the enumerable system

const P64B1_ORACLE = Dict{Symbol, Any}()
function p64b1_oracle()
    isempty(P64B1_ORACLE) || return P64B1_ORACLE
    O = P64b1Oracle
    m = P64B1_TINY
    S = O.states(m)
    index = Dict(σ => i for (i, σ) in enumerate(S))
    P = O.kernel(m, S, index)
    π = O.stationary(P)
    v0 = zeros(length(S)); v0[index[P64B1_σ0]] = 1.0
    seqk(rows, v, k) = foldl((u, _) -> O.mcs(m, rows, u), 1:k; init = v)
    Pn = O.kernel(m, S, index; law = :no_skip)
    Pu = O.kernel(m, S, index; law = :unlike)
    merge!(P64B1_ORACLE, Dict(:S => S, :index => index, :P => P, :π => π,
        :πT => O.stationary(O.kernel(O.with_T(m, 1.25 * m.T), S, index)),       # wrong temperature
        :π_no_skip => seqk(Pn, π, P64B1_K_STAT), :π_unlike => seqk(Pu, π, P64B1_K_STAT),
        :v1 => seqk(P, v0, 1), :v2 => seqk(P, v0, 2),
        :v1_no_skip => seqk(Pn, v0, 1), :v2_no_skip => seqk(Pn, v0, 2)))
    return P64B1_ORACLE
end
p64b1_bin(index, σ) = get(index, Vector{Int8}(vec(σ)), length(index) + 1)

@testset "P6.4b1: the oracle (exact stationary law and the statistic's controls)" begin
    O = P64b1Oracle
    o = p64b1_oracle()
    S, π = o[:S], o[:π]
    @test length(S) == 6050
    @test sum(π) ≈ 1 && all(>(0), π)                                  # unique, every state recurrent
    @test O.tv(O.mcs(P64B1_TINY, o[:P], π), π) < 1e-12                 # stationary
    @test sum(o[:v1]) ≈ 1 && sum(o[:v2]) ≈ 1
    # σ0 has interior sites (7, 8): the no-skip variant differs at MCS 1
    @test O.boundary(P64B1_TINY, P64B1_σ0) == 1:6
    # the statistic: calibrated on the right law, and powerful against every wrong one
    rng = StableRNG(177_301)
    R = P64B1_R
    z(p, q) = first(O.chi2_z(p, O.multinomial(q, R, rng), R))
    for (law, name) in ((π, "π"), (o[:v1], "MCS 1"), (o[:v2], "MCS 2"))
        @test z(law, law) < P64B1_Z_CHI
    end
    for (wrong, right, name) in ((o[:πT], π, "T = 3.75"), (o[:π_no_skip], π, "no skip, 4 MCS from π"),
            (o[:π_unlike], π, "unlike source, 4 MCS from π"), (o[:v1_no_skip], o[:v1], "no skip, MCS 1"),
            (o[:v2_no_skip], o[:v2], "no skip, MCS 2"))
        zw = z(right, wrong)
        @info "P6.4b1 oracle negative control" name zw tv = O.tv(right, wrong)
        @test zw > P64B1_Z_CHI
    end
end

"""Stationarity: R runs from start states drawn from π, K_STAT MCS each; end-state counts."""
function p64b1_stationary_counts(alg, seed0)
    o = p64b1_oracle()
    S, index = o[:S], o[:index]
    starts = P64b1Oracle.draws(o[:π], P64B1_R, StableRNG(177_401))
    mult = zeros(Int, length(S))
    foreach(i -> mult[i] += 1, starts)
    counts = zeros(Int, length(S) + 1)
    base = p64b1_tiny_problem(P64B1_σ0, (0, P64B1_K_STAT))
    j = 0
    for s in eachindex(S)
        mult[s] == 0 && continue
        ps = remake(base; u0 = p64b1_tiny_op(S[s]))
        for _ in 1:mult[s]
            j += 1
            sol = solve(remake(ps; seed = seed0 + j), alg; save_start = false)
            counts[p64b1_bin(index, sol.u[end].σ)] += 1
        end
    end
    return counts
end
"""Finite time: R runs from σ0; end-state counts at MCS 1 and MCS 2."""
function p64b1_finite_counts(alg, seed0)
    o = p64b1_oracle()
    index = o[:index]
    c1 = zeros(Int, length(index) + 1); c2 = zeros(Int, length(index) + 1)
    base = p64b1_tiny_problem(P64B1_σ0, (0, 2))
    for j in 1:P64B1_R
        sol = solve(remake(base; seed = seed0 + j), alg; saveat = [1, 2], save_start = false)
        @assert sol.t == [1, 2]
        c1[p64b1_bin(index, sol.u[1].σ)] += 1
        c2[p64b1_bin(index, sol.u[2].σ)] += 1
    end
    return c1, c2
end

@testset "P6.4b1: exact law on 2×4 ($name)" for (name, alg, seeds) in (
        ("SequentialCPM, oracle control", () -> SequentialCPM(), (1_770_000, 1_790_000)),
        ("BoundarySiteCPM", () -> p64b1_bs(), (1_780_000, 1_800_000)))
    O = P64b1Oracle
    o = p64b1_oracle()
    R = P64B1_R
    # (a) stationarity
    cs = p64b1_stationary_counts(alg(), seeds[1])
    zs, ks = O.chi2_z(o[:π], cs, R)
    zn, _ = O.chi2_z(o[:π_no_skip], cs, R)
    @info "P6.4b1 stationary law" name zs ks z_against_no_skip = zn
    @test cs[end] == 0                               # no state outside the space (no extinction)
    @test zs < P64B1_Z_CHI
    @test zn > P64B1_Z_CHI                           # not the no-skip variant
    # (b) the laws at MCS 1 and 2 from σ0
    c1, c2 = p64b1_finite_counts(alg(), seeds[2])
    z1, k1 = O.chi2_z(o[:v1], c1, R)
    z2, k2 = O.chi2_z(o[:v2], c2, R)
    z1n, _ = O.chi2_z(o[:v1_no_skip], c1, R)
    @info "P6.4b1 finite-time law" name z1 k1 z2 k2 z_mcs1_against_no_skip = z1n
    @test z1 < P64B1_Z_CHI
    @test z2 < P64B1_Z_CHI
    @test z1n > P64B1_Z_CHI
end

# ---------------------------------------------------------------------------------------
# 3. Time equivalence on a mostly-medium lattice

const P64B1_N_RUNS = 2000
"""Per run: accepted copies in MCS 1, accepted over MCS 1–k and the mean squared centroid
displacement of the four cells over k MCS, for k in `marks`."""
function p64b1_time_samples(alg, seed0; marks = (10,))
    prob = p64b1_free_problem(; tspan = (0, maximum(marks)))
    acc1 = Float64[]
    acc = Dict(k => Float64[] for k in marks)
    msd = Dict(k => Float64[] for k in marks)
    attempts_ok = true
    for j in 1:P64B1_N_RUNS
        integ = init(remake(prob; seed = seed0 + j), alg; save_start = false, save_end = false)
        c0 = p64b1_centroids(integ.state.σ, 4)
        for t in 1:maximum(marks)
            step!(integ)
            t == 1 && push!(acc1, integ.stats.accepted)
            if t in marks
                push!(acc[t], integ.stats.accepted)
                c = p64b1_centroids(integ.state.σ, 4)
                push!(msd[t], mean(sum(abs2, c[i] .- c0[i]) for i in 1:4))
            end
        end
        attempts_ok &= integ.stats.attempts == maximum(marks) * 60 * 60
    end
    return (; acc1, acc, msd, attempts_ok)
end

@testset "P6.4b1: time equivalence, two-sample (60², 2.8 % cover)" begin
    seqA = p64b1_time_samples(SequentialCPM(), 2_770_000; marks = (10, 15))
    seqB = p64b1_time_samples(SequentialCPM(), 2_780_000; marks = (10, 15))
    @test seqA.attempts_ok && seqB.attempts_ok
    # negative control (no BoundarySiteCPM): time miscounted by 1.5× is detected
    zc_acc = p64b1_welch(seqA.acc[10], seqB.acc[15])
    zc_msd = p64b1_welch(seqA.msd[10], seqB.msd[15])
    # null control: two SequentialCPM samples agree
    z0 = (p64b1_welch(seqA.acc1, seqB.acc1), p64b1_var_z(seqA.acc1, seqB.acc1),
        p64b1_welch(seqA.acc[10], seqB.acc[10]), p64b1_welch(seqA.msd[10], seqB.msd[10]))
    @info "P6.4b1 time equivalence controls" mean_acc1 = mean(seqA.acc1) var_acc1 = var(seqA.acc1) mean_acc10 = mean(seqA.acc[10]) mean_msd10 = mean(seqA.msd[10]) mean_msd15 = mean(seqB.msd[15]) zc_acc zc_msd z0
    @test abs(zc_acc) > P64B1_Z_MEAN
    @test abs(zc_msd) > P64B1_Z_MEAN
    @test abs(z0[1]) <= P64B1_Z_MEAN && abs(z0[2]) <= P64B1_Z_VAR && abs(z0[3]) <= P64B1_Z_MEAN && abs(z0[4]) <= P64B1_Z_MEAN
    # the claim: BoundarySiteCPM against SequentialCPM
    bs = p64b1_time_samples(p64b1_bs(), 2_790_000; marks = (10,))
    @test bs.attempts_ok                                               # N attempts per MCS
    z = (acc1 = p64b1_welch(bs.acc1, seqA.acc1), var_acc1 = p64b1_var_z(bs.acc1, seqA.acc1),
        acc10 = p64b1_welch(bs.acc[10], seqA.acc[10]), msd10 = p64b1_welch(bs.msd[10], seqA.msd[10]))
    @info "P6.4b1 time equivalence" z mean_acc1 = mean(bs.acc1) var_acc1 = var(bs.acc1) mean_msd10 = mean(bs.msd[10])
    @test abs(z.acc1) <= P64B1_Z_MEAN
    @test abs(z.var_acc1) <= P64B1_Z_VAR
    @test abs(z.acc10) <= P64B1_Z_MEAN
    @test abs(z.msd10) <= P64B1_Z_MEAN
end

# ---------------------------------------------------------------------------------------
# 4. The incremental boundary set

@testset "P6.4b1: the recompute's own controls (no BoundarySiteCPM)" begin
    # the fixture's events fire under SequentialCPM, and the recompute sees them
    integ = init(p64b1_life_problem(), SequentialCPM(); save_start = false)
    B0 = Set(p64b1_boundary(integ.state.σ, integ.state.cell.kind, P64B1_MOORE; frozen_kinds = (2,)))
    walls_seen = false
    while integ.t < 10
        step!(integ)
        if any(==(2), integ.state.cell.kind[c] for c in eachindex(integ.state.cell.volume) if integ.state.cell.volume[c] > 0)
            walls_seen = true
            # a frozen cell is present: ignoring the frozen flag gives another set
            @test Set(p64b1_boundary(integ.state.σ, integ.state.cell.kind, P64B1_MOORE; frozen_kinds = (2,))) !=
                  Set(p64b1_boundary(integ.state.σ, integ.state.cell.kind, P64B1_MOORE))
        end
    end
    l = integ.stats.lifecycle
    @test walls_seen
    @test l.divisions == 2 && l.removals == 2 && l.transitions == 1
    @test Set(p64b1_boundary(integ.state.σ, integ.state.cell.kind, P64B1_MOORE; frozen_kinds = (2,))) != B0  # a stale set fails
    # VonNeumann and Moore sets differ on the same state (the proposal matters)
    @test Set(p64b1_boundary(integ.state.σ, integ.state.cell.kind, P64B1_VN)) !=
          Set(p64b1_boundary(integ.state.σ, integ.state.cell.kind, P64B1_MOORE))
end

@testset "P6.4b1: the boundary set after copies, divisions, removals and frozen transitions" begin
    integ = init(p64b1_life_problem(), p64b1_bs(); save_start = false)
    ok = [p64b1_boundary_ok(integ, P64B1_MOORE; frozen_kinds = (2,))]
    while integ.t < 10
        step!(integ)
        push!(ok, p64b1_boundary_ok(integ, P64B1_MOORE; frozen_kinds = (2,)))
    end
    @test all(ok)
    l = integ.stats.lifecycle
    @test l.divisions == 2 && l.removals == 2 && l.transitions == 1
    # reinit! and a direct write followed by u_modified!
    reinit!(integ)
    @test p64b1_boundary_ok(integ, P64B1_MOORE; frozen_kinds = (2,))
    step!(integ)
    integ.state.σ[12, 12] = 1                    # an isolated site of cell 1 in the medium
    u_modified!(integ, true)
    @test p64b1_boundary_ok(integ, P64B1_MOORE; frozen_kinds = (2,))
end

@testset "P6.4b1: the boundary set on published models ($name)" for (name, make, alg, offsets, periodic, nmcs) in (
        ("Graner–Glazier 72², periodic", () -> p64b1_gg_problem(; seed = 3), () -> p64b1_bs(), P64B1_MOORE, true, 20),
        ("OpenVT reference 60², divisions", () -> remake(p64b1_openvt_problem(60; seed = 3); p = [:σ_X => 0.0]),
            () -> p64b1_bs(), P64B1_MOORE, false, 1700),
        ("OpenVT reference 60², VonNeumann(1) proposal on Moore(1) contacts",
            () -> remake(p64b1_openvt_problem(60; seed = 3); p = [:σ_X => 0.0]),
            () -> p64b1_bs(; proposal = VonNeumann(1)), P64B1_VN, false, 900))
    integ = init(make(), alg(); save_start = false, save_end = false)
    bad = Int[]
    p64b1_boundary_ok(integ, offsets; periodic) || push!(bad, 0)
    for t in 1:nmcs
        step!(integ)
        p64b1_boundary_ok(integ, offsets; periodic) || push!(bad, t)
    end
    @test isempty(bad)
    isempty(bad) || @info "P6.4b1 boundary set differs" name first_bad = first(bad)
    nmcs >= 1700 && @test integ.stats.lifecycle.divisions >= 1
end

# ---------------------------------------------------------------------------------------
# 5. Ensemble check: OpenVT growth curves

const P64B1_CYCLE = 775
const P64B1_SMOKE_L = 160
const P64B1_SMOKE_TMAX = 5040                    # ≥ 6.5 cycles
const P64B1_SMOKE_GRID = 0.5:1.0:6.5
const P64B1_SMOKE_RUNS = 8

"""N(t) for t = 0:tmax of one run (`OpenVTReferenceMonolayer`, Table S1 defaults)."""
function p64b1_growth(prob, alg, seed, tmax)
    integ = init(remake(prob; seed), alg; save_start = false, save_end = false)
    N = zeros(Int, tmax + 1)
    N[1] = count(>(0), integ.state.cell.volume)
    for t in 1:tmax
        step!(integ)
        N[t + 1] = count(>(0), integ.state.cell.volume)
    end
    σ = integ.state.σ
    clear = all(==(0), σ[1:5, :]) && all(==(0), σ[(end - 4):end, :]) && all(==(0), σ[:, 1:5]) && all(==(0), σ[:, (end - 4):end])
    return N, clear
end
"""L(τ) = log₂ N at MCS ⌊τ·775⌋ (scaled by `s`: the variant whose time runs `s` times slower)."""
p64b1_L(N, grid; s = 1.0) = [log2(N[floor(Int, τ * P64B1_CYCLE / s) + 1]) for τ in grid]

std0(x) = sqrt(var(x))
"""Exact two-sample permutation p-value of S = max_τ |ΔL̄(τ)|/sd(τ) over all splits."""
function p64b1_perm_p(A::Matrix, B::Matrix)          # rows: runs, columns: grid points
    X = vcat(A, B)
    n, nA = size(X, 1), size(A, 1)
    sd = [std0(X[:, j]) for j in axes(X, 2)]
    cols = findall(>(0), sd)
    stat(mask) = maximum((abs(mean(X[mask, j]) - mean(X[.!mask, j])) / sd[j] for j in cols); init = 0.0)
    obs = stat([trues(nA); falses(n - nA)])
    hits = 0; total = 0
    for code in 0:(2^n - 1)
        count_ones(code) == nA || continue
        mask = [((code >> (i - 1)) & 1) == 1 for i in 1:n]
        total += 1
        hits += stat(mask) >= obs - 1e-12
    end
    return hits / total, obs
end
@testset "P6.4b1: OpenVT growth curves, SMOKE (160², 6.5 cycles, 8 + 8 runs)" begin
    prob = p64b1_openvt_problem(P64B1_SMOKE_L; capacity = 400)
    runs(alg, seed0) = [p64b1_growth(prob, alg, seed0 + k, P64B1_SMOKE_TMAX) for k in 1:P64B1_SMOKE_RUNS]
    seqA = runs(SequentialCPM(), 177_100)
    seqB = runs(SequentialCPM(), 177_300)
    @test all(last, seqA) && all(last, seqB)                          # the colony stays off the edge
    LA = reduce(vcat, (p64b1_L(first(r), P64B1_SMOKE_GRID)' for r in seqA))
    LBs = reduce(vcat, (p64b1_L(first(r), P64B1_SMOKE_GRID; s = 1.25)' for r in seqB))
    pc, Sc = p64b1_perm_p(LA, LBs)
    @info "P6.4b1 SMOKE negative control (time × 1.25)" pc Sc LA = vec(mean(LA; dims = 1)) LBs = vec(mean(LBs; dims = 1))
    @test pc < P64B1_P_PERM
    bs = runs(p64b1_bs(), 177_200)
    @test all(last, bs)
    LS = reduce(vcat, (p64b1_L(first(r), P64B1_SMOKE_GRID)' for r in bs))
    p, S = p64b1_perm_p(LS, LA)
    @info "P6.4b1 SMOKE growth" p S BoundarySiteCPM = vec(mean(LS; dims = 1)) SequentialCPM = vec(mean(LA; dims = 1))
    @test p >= P64B1_P_PERM
end

const P64B1_FULL_L = 400
const P64B1_FULL_CELLS = 1000
const P64B1_FULL_RUNS = 100
const P64B1_FULL_GRID = 0.5:1.0:8.5

"""FULL: N(t) until the first MCS with ≥ 1000 cells (D-173 protocol; edge guard 5)."""
function p64b1_full_run(prob, alg, seed)
    N = Int[]
    rec = DiscreteCallback((u, t, integ) -> true, integ -> push!(N, count(>(0), integ.state.cell.volume));
        initialize = (cb, u, t, integ) -> push!(N, count(>(0), integ.state.cell.volume)), save_positions = (false, false))
    sol = solve(remake(prob; seed), alg; save_start = false, save_end = false,
        callback = CallbackSet(rec, PottsModels.stop_at_cells(P64B1_FULL_CELLS), PottsModels.edge_guard(5; terminate = true)))
    return (; N, retcode = Symbol(sol.retcode), ts = length(N) - 1)
end
"""L(τ) of a FULL run, reading the last value when the run stopped before ⌊τ·775/s⌋."""
p64b1_full_L(N, grid; s = 1.0) = [log2(N[min(floor(Int, τ * P64B1_CYCLE / s) + 1, length(N))]) for τ in grid]
function p64b1_full_z(A, B; s = 1.0)
    LA = [p64b1_full_L(r.N, P64B1_FULL_GRID; s) for r in A]
    LB = [p64b1_full_L(r.N, P64B1_FULL_GRID) for r in B]
    zs = Float64[]
    for j in eachindex(P64B1_FULL_GRID)
        a = [l[j] for l in LA]; b = [l[j] for l in LB]
        push!(zs, (var(a) + var(b)) == 0 ? (mean(a) == mean(b) ? 0.0 : Inf) : p64b1_welch(a, b))
    end
    push!(zs, p64b1_welch([r.ts * s for r in A], [r.ts for r in B]))
    return zs
end

@testset "P6.4b1: OpenVT growth curves, FULL (400², to 1000 cells, 100 + 100 runs)" begin
    if !P64B1_FULL
        @test_skip "FULL tier: set POTTS_FULL_REPRODUCTION=true (offline, on the PC)"
    else
        prob = p64b1_openvt_problem(P64B1_FULL_L; tspan = (0, 100_000), capacity = 1400)
        function runs(alg, seed)
            out = Vector{Any}(undef, P64B1_FULL_RUNS)
            Threads.@threads :dynamic for k in 1:P64B1_FULL_RUNS
                out[k] = p64b1_full_run(prob, alg, seed(k))
            end
            return out
        end
        seq = runs(SequentialCPM(), k -> 15_000 + k)                 # P6.15e/f case (b) seeds
        bs = runs(p64b1_bs(), k -> 177_000 + k)
        @test all(r -> r.retcode === :Terminated && r.N[end] >= P64B1_FULL_CELLS, seq)
        @test all(r -> r.retcode === :Terminated && r.N[end] >= P64B1_FULL_CELLS, bs)
        z = p64b1_full_z(bs, seq)
        zc = p64b1_full_z(bs, seq; s = 1.1)
        @info "P6.4b1 FULL growth" z zc
        @test all(x -> abs(x) <= P64B1_Z_FULL, z)
        @test any(x -> abs(x) > P64B1_Z_FULL, zc)                     # time × 1.1 is detected
    end
end

# ---------------------------------------------------------------------------------------
# 6. Performance

@testset "P6.4b1: zero warm allocations per MCS ($name)" for (name, make) in (
        ("Graner–Glazier 72²", () -> p64b1_gg_problem()),
        ("openvt_reference_100 (gate case, quiet lifecycle)", p64b1_openvt100_problem),
        ("400², 5.2 % cover", () -> p64b1_free_problem(; L = 400, side = 7, first = 15, spacing = 30, tspan = (0, 10^6))))
    integ = init(make(), p64b1_bs(); save_start = false, save_end = false)
    step!(integ); step!(integ)
    @test p64b1_warm_allocs(integ) == 0
end

@testset "P6.4b1: speed-up on a mostly-medium lattice (400², 169 cells of 7×7, 5.2 % cover)" begin
    prob = p64b1_free_problem(; L = 400, side = 7, first = 15, spacing = 30, tspan = (0, 10^6))
    @test count(!=(0), prob.u0.σ) == 169 * 49
    seq = p64b1_warm_ns(prob, SequentialCPM())
    bsn = p64b1_warm_ns(prob, p64b1_bs())
    ratio = seq / bsn
    @info "P6.4b1 speed-up (warm MCS, min of 30)" sequential_ns_per_site = seq boundary_site_ns_per_site = bsn ratio pinned = P64B1_BENCH
    @test isfinite(ratio)
    if P64B1_BENCH
        @test ratio >= P64B1_SPEEDUP
    else
        @test_skip "speed-up floor ≥ $(P64B1_SPEEDUP)×: asserted only with POTTS_BENCH_PINNED=1 (benchmark harness)"
    end
end

# ---------------------------------------------------------------------------------------
# 7. Determinism

@testset "P6.4b1: the same seed gives the same result" begin
    prob = p64b1_free_problem(; tspan = (0, 12), seed = 21)
    a = solve(prob, p64b1_bs(); save_start = false)
    b = solve(prob, p64b1_bs(); save_start = false)
    @test a.u[end].σ == b.u[end].σ && a.u[end].cell == b.u[end].cell
    @test a.stats.accepted == b.stats.accepted && a.stats.attempts == b.stats.attempts
    c = solve(remake(prob; seed = 22), p64b1_bs(); save_start = false)
    @test c.u[end].σ != a.u[end].σ                                    # control: seeds matter
    # EnsembleSerial = EnsembleThreads, trajectory by trajectory (no shared scratch)
    pf(q, ctx) = remake(q; seed = 300 + ctx.sim_id)
    es = solve(EnsembleProblem(prob; prob_func = pf), p64b1_bs(), EnsembleSerial(); trajectories = 4)
    et = solve(EnsembleProblem(prob; prob_func = pf), p64b1_bs(), EnsembleThreads(); trajectories = 4)
    @test all(i -> es.u[i].u[end].σ == et.u[i].u[end].σ, 1:4)
    @test es.u[1].u[end].σ != es.u[2].u[end].σ
    # with a lifecycle (division planes and removals)
    l1 = solve(p64b1_life_problem(), p64b1_bs(); save_start = false)
    l2 = solve(p64b1_life_problem(), p64b1_bs(); save_start = false)
    @test l1.u[end].σ == l2.u[end].σ && l1.u[end].cell == l2.u[end].cell
end
