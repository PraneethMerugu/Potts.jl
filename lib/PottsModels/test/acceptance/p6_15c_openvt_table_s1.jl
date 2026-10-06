# P6.15c (ROADMAP Step 3b; spec research/model-specs/15_openvt_monolayer.md v3 §2, §5, §6
# G1, G2, G5, G6, G7, G11, §1.1 C3, C9, C13, C14; D-147, D-048): the OpenVT monolayer model
# updated to M's Table S1, as a NEW published model beside the 2024 Artistoo set, which is
# kept unchanged as a documented variant (`OpenVTGrowingMonolayer`, pinned bit for bit
# below). Decision: D-150. Frozen (AUTONOMY §7.3).
#
# ── Surface fixed here ─────────────────────────────────────────────────────────────────────
#
# G1 (Potts DSL, general; not model-named): a CELL-SCOPE CONTACT FOLD.
#   In cell scope (`@before_mcs`/`@after_mcs` cell updates, division `when`, cell
#   `@observed`), `count(pred for _ in contacts)` is the number of contact pairs (s, s′) of
#   the cell: s a site of the cell, s′ ∈ R(s) inside the lattice (wrapping on periodic
#   axes, dropped across a closed edge), owner(s′) ≠ owner(s), for which `pred` holds.
#   R is the contact relation (the lattice neighbourhood unless declared otherwise);
#   `contacts(rel)` folds over a relation declared in `@relations`. `pred` may read the
#   partner's `kind′` (`kind′ == medium`, `kind′ == B`; `medium` is the kind of owner 0)
#   and constants; `true` counts every unlike pair, so `count(true for _ in contacts)` ==
#   `surface` when the surface relation is the contact relation (cross-checked below).
#   The value is EXACT after every accepted copy and every lifecycle event (it is read
#   fresh at `@before_mcs`, i.e. after the previous MCS's lifecycle, and at `@after_mcs`,
#   after the sweep), and it is maintained INCREMENTALLY: a model reading it pays per
#   accepted copy, not per site per MCS (cost backstop below: ≤ 1.5× the same model reading
#   the existing `surface` tracker; a whole-lattice recomputation, the only form today,
#   measures ≈ 2.7×). M's free-surface fraction (Fig 4, spec §2.4, TST "method 3") is
#   f = count(kind′ == medium for _ in contacts) / count(true for _ in contacts) on Moore(1).
#
# G2 (Potts DSL, general):
#   `randn()`: a standard normal draw with `rand()`'s contract (vocabulary.jl:299): its
#   own counter-based stream per occurrence, fresh per MCS and per cell, available in
#   updates, equations, division conditions and rules; a draw depends only on (seed, MCS,
#   cell id, occurrence), so it is the same on every algorithm and thread count.
#   Division state rules that draw (`x => randn()`, `x => rand()`, any expression with a
#   draw) are evaluated SEPARATELY for the parent and for the daughter: each daughter
#   draws its own value (today one value goes to both, vocabulary.jl:710). Rules without
#   a draw are unchanged (both get the value), and models without drawing rules keep
#   their streams and fingerprints.
#   The truncation "redraw while X ≤ 0" (C3) is pinned through the model's behaviour only
#   (every X > 0 at every save, in a regime where 5.5 % of raw draws are ≤ 0); its DSL
#   form is the implementer's (open question in D-150).
#
# The model (PottsModels, exported):
#   OpenVTReferenceMonolayer(; name, lattice = (1400, 1400), …)
#     kinds `medium, cell`; lattice Closed() on both axes, neighbourhood Moore(1);
#     proposals Moore(1); Metropolis at T. Parameters, Table S1 (M p.11) and M §2.1:
#       A₀ = 50.0 (A*(0), px), λ = 2.0, T = 20.0, α = 50/775 (px/MCS; 6.452e-2, cycle
#       5T = A₀/α = 775 MCS, C1, C16), μ_X = 2.0, σ_X = 0.4 (X ~ N(μ_X, σ_X); μ_Amax =
#       μ_X A₀ = 100), β = 0.0, γ = 0.0, J[kind, kind] = [0 10; 10 20] (J_cm = 10,
#       J_cc = 20).
#     Cell variables: A_star (A*_i; starts at A₀), X (X_i), f (the free-surface fraction
#     the growth rule read at the last MCS, after the sweep, G1 on Moore(1)).
#     Energy λ (volume − A_star)² + contacts J[kind, kind′].
#     Growth, once per MCS after the sweep (spec §2.1): A_star += α iff
#       (volume / A_star ≥ β) && (f ≥ γ)       (C9: ≥; a_i = A_i / A*_i, the current A*)
#     else unchanged.
#     Division (C13: actual area): at the MCS boundary, a cell divides iff
#       volume ≥ X · A₀, along RandomPlane(); A_star => Split() (C14); BOTH daughters draw
#       a fresh X ~ N(μ_X, σ_X) redrawn while ≤ 0 (C3), at birth. The first cell's X is
#       drawn the same way (from the run's seed) before the first division check.
#       σ_X = 0 is the deterministic mode X ≡ μ_X = 2 (case (f)).
#   openvt_reference_state(; lattice = (1400, 1400), A₀ = 50) -> [ownership => σ, kind => [:cell]]
#     (exported; G5) one disc: the sites whose centres lie within R = √(A₀/π) of the
#     lattice centre point ((size .+ 1) ./ 2, the layouts' `Center()`), id 1 — Morpheus'
#     `Sphere radius="R"` at the centre. 52 sites on even lattices, 45 on odd ones (A₀ = 50).
#   openvt_snapshot(u; A₀ = 50.0, center = (size(u.σ) .+ 1) ./ 2) -> (; x, y, r, f, a)
#     (PottsModels; G11's O2 row data, spec §3.1) live cells (volume > 0) in id order;
#     x, y = (centroid − center) / R in R units (centroid = mean site index, closed
#     lattice); r = √(A_star/π) / R; f = medium pairs / unlike pairs over Moore(1)
#     computed from σ (exact at the saved state); a = volume / A_star; R = √(A₀/π).
#     Written with P6.15d's `write_openvt(path, :O2, snapshot)` (feat/p6-15d surface).
#   stop_at_cells(n) -> DiscreteCallback   (PottsModels, G7/G11) terminate! at the end of
#     the first MCS whose live-cell count (volume > 0, after the lifecycle) is ≥ n;
#     retcode Terminated. Used at n = 1000 (F3/F5) and 10⁴ (M's termination, C15).
#   PottsModels.Analysis.near_edge(σ, margin)::Bool   (G6, general) true iff some site
#     with σ ≠ 0 has an index i_d ≤ margin or i_d ≥ size(σ, d) − margin + 1 on some axis d.
#   edge_guard(margin; terminate = false) -> DiscreteCallback   (PottsModels, G6) checked
#     after every MCS; when `near_edge(σ, margin)`: throws a `DomainError` (default), or with
#     `terminate = true` calls terminate!(integ, ReturnCode.Failure).
#
# ── Oracles and controls (D-048) ──────────────────────────────────────────────────────────
#   - F4: M's Fig 4 lattice panel (G:results/free_surface.tex:48-110, transcribed below as a
#     7 × 7 σ) draws 13 medium pairs and 25 cell pairs for cell i: f_i = 13/38. The other
#     three cells' counts are the brute-force ones on the closed 7 × 7 crop.
#   - G1: a brute-force pair count from σ (written here), after EVERY MCS of random runs
#     with divisions, kinds A/B, a periodic and a closed axis, Moore(1) and VonNeumann(1);
#     `surface` as a second oracle. Controls: the before-values disagree with the same
#     MCS's σ (the timing is real), consecutive states differ (a stale count would fail).
#   - G2: moments and tails against N(0, 1) at 4 SE; parent/daughter independence; equality
#     across SequentialCPM and CheckerboardCPM (stream keyed by cell and MCS; `rand()` is the
#     positive control, it does this today); a constant rule still copies.
#   - Model: Table S1 values; the growth law against σ after every MCS on an inhibited
#     colony (both inhibitions exercised, and the alternative a = A/A₀ shown to differ);
#     C9 at exact equality (β = 1 and γ = 1 grow; nextfloat does not); the division law
#     (no cell above threshold survives an MCS; Split halves; both daughters redraw);
#     X statistics; truncation in a regime where 5.5 % of raw draws are ≤ 0.
#   - Deterministic mode: X ≡ 2 and synchronous doublings (N = 1, 2, 4, 8 in windows at
#     t ≈ 1, 2, 3 cycles); control: the stochastic mode fails the same windows.
#     Windows from a stub of this model on today's primitives, 16/16 deterministic seeds
#     inside (first division 698–755, second 1457–1521, third 2193–2294 MCS), 0/16 stochastic.
#   - The 2024 set: fingerprint and 60-MCS trajectory digests of `OpenVTGrowingMonolayer`
#     recorded at 30c39601 (1 and 4 threads alike).
#   - G6/G11: hand-built σ for `near_edge`; a run that reaches the edge (guard fires; without
#     the guard it runs on); tilings of 999/1000 and 9999/10⁴ cells; the first crossing in a
#     growing run against an unstopped run of the same seed; O2 rows against brute force.
#
# Seeds are the test author's: 151_001… (G1), 152_001… (G2 fixture), 153_001… (model runs),
# 15_001… (doubling windows, as measured), 1:200 (initial X).
#
# Metal (POTTS_GPU=metal with Metal loaded): G1 exactness and the per-daughter draws on
# CheckerboardCPM with Float32, and the model's division-free f on the device.

using Test, Potts, PottsModels
using Potts: CorePotts
using Statistics: mean, var, std, cor
using Potts: SciMLBase
const ReturnCode = SciMLBase.ReturnCode

const P615C_ON_DEVICE = isdefined(Main, :PottsDevices) \&\& Main.PottsDevices.on_device()
const P615C_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM())
const P615C_R = sqrt(50 / π)                       # 1 R in px (spec §2.3), A₀ = 50
const P615C_MOORE = [(dx, dy) for dx in -1:1 for dy in -1:1 if (dx, dy) != (0, 0)]
const P615C_VN = [(1, 0), (-1, 0), (0, 1), (0, -1)]

# ---------------------------------------------------------------------------------------------
# Models defined with syntax that does not exist yet are defined inside `try`, so that a
# failure is recorded per testset (the right reason: the DSL lacks the fold or `randn()`)
# and the rest of the file still runs.
# ---------------------------------------------------------------------------------------------

const P615C_DEFINED = Dict{Symbol, Any}()
function p615c_define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
        P615C_DEFINED[name] = true
    catch e
        P615C_DEFINED[name] = e
        @error "P6.15c: defining $name failed" exception = (e, catch_backtrace())
    end
    return nothing
end
p615c_ok(name::Symbol) = get(P615C_DEFINED, name, nothing) === true

# G1 fixture: kinds A, B; a periodic axis 1 and a closed axis 2; growth and division
p615c_define(:P615cFold, :(@potts_model P615cFold begin
    @kinds medium A B
    @parameters begin
        T = 6.0
        g = 0.4
        J[kind, kind] = [0.0 6.0 6.0; 6.0 4.0 8.0; 6.0 8.0 4.0]
    end
    @variables begin
        A_t(cell) = 20.0
        mb(cell) = -1.0
        ub(cell) = -1.0
        bb(cell) = -1.0
        vb(cell) = -1.0
        sb(cell) = -1.0
        ma(cell) = -1.0
        ua(cell) = -1.0
    end
    @lattice Lattice((36, 30); boundary = (Periodic(), Closed()), neighborhood = Moore(1))
    @relations begin
        proposal = Moore(1)
        vn = VonNeumann(1)
    end
    @energy begin
        cells(A, B) => 1.0 * (volume - A_t)^2
        contacts => J[kind, kind′]
    end
    @before_mcs begin
        mb ~ count(kind′ == medium for _ in contacts)
        ub ~ count(true for _ in contacts)
        bb ~ count(kind′ == B for _ in contacts)
        vb ~ count(kind′ == medium for _ in contacts(vn))
        sb ~ surface
    end
    @after_mcs begin
        A_t ~ Pre(A_t) + g
        ma ~ count(kind′ == medium for _ in contacts)
        ua ~ count(true for _ in contacts)
    end
    @divide cells(A, B) when = volume >= 40, along = RandomPlane(), A_t => 20.0
    @sweep Metropolis(; temperature = T)
end))

# G1 on M's Fig 4 lattice panel (7 × 7 crop, closed)
p615c_define(:P615cFig4, :(@potts_model P615cFig4 begin
    @kinds medium cell
    @parameters T = 1.0
    @variables begin
        m(cell) = -1.0
        u(cell) = -1.0
    end
    @lattice Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy cells(cell) => 1.0 * (volume - 10)^2
    @before_mcs begin
        m ~ count(kind′ == medium for _ in contacts)
        u ~ count(true for _ in contacts)
    end
    @sweep Metropolis(; temperature = T)
end))

# G1 cost: the same model reading the fold (CostFold) or the existing `surface` (CostSurf)
for (name, rhs) in ((:P615cCostFold, :(count(kind′ == medium for _ in contacts) / count(true for _ in contacts))),
                    (:P615cCostSurf, :(surface / (surface + 1.0))))
    p615c_define(name, :(@potts_model $name begin
        @kinds medium cell
        @parameters begin
            T = 20.0
            γ = 0.0
            J[kind, kind] = [0.0 10.0; 10.0 20.0]
        end
        @variables begin
            A_star(cell) = 25.0
            f(cell) = 0.0
        end
        @lattice Lattice((200, 200); boundary = Closed(), neighborhood = Moore(1))
        @relations proposal = Moore(1)
        @energy begin
            cells(cell) => 2.0 * (volume - A_star)^2
            contacts => J[kind, kind′]
        end
        @after_mcs begin
            f ~ $rhs
            A_star ~ ifelse(f >= γ, Pre(A_star) + 1e-9, Pre(A_star))
        end
        @sweep Metropolis(; temperature = T)
    end))
end

# G2 fixture: per-MCS draws and per-daughter rule draws; every cell divides at MCS 0
p615c_define(:P615cDraws, :(@potts_model P615cDraws begin
    @kinds medium A
    @parameters begin
        T = 4.0
        J[kind, kind] = [0.0 4.0; 4.0 4.0]
    end
    @variables begin
        z(cell) = 0.0
        w(cell) = 0.0
        d(cell) = 0.0
        h(cell) = 0.0
        e(cell) = 0.0
        tag(cell) = 0.0
    end
    @lattice Lattice((80, 80); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(A) => 1.0 * (volume - 16)^2
        contacts => J[kind, kind′]
    end
    @before_mcs begin
        z ~ randn()
        w ~ rand()
    end
    @divide cells(A) when = mcs == 0, along = RandomPlane(), d => randn(), h => rand(), e => 7.0, tag => Split()
    @sweep Metropolis(; temperature = T)
end))

# G11: a non-dividing tiling model for the cell-count stop at 1000 and 10⁴
@potts_model P615cTiles begin
    @kinds medium cell
    @parameters T = 2.0
    @lattice Lattice((400, 400); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy cells(cell) => 1.0 * (volume - 16)^2
    @sweep Metropolis(; temperature = T)
end

# ---------------------------------------------------------------------------------------------
# Helpers (test-internal)
# ---------------------------------------------------------------------------------------------

"""Brute-force contact pairs per cell id 1:maximum(σ): unlike pairs, medium pairs and pairs
whose partner cell has kind index `toward` (kindof[id]), over `offs`, wrapping on periodic axes."""
function p615c_contacts(σ, offs; periodic = (false, false), kindof = nothing, toward = 0, n = maximum(σ; init = 0))
    unlike = zeros(Int, n); med = zeros(Int, n); tow = zeros(Int, n)
    L = size(σ)
    for I in CartesianIndices(σ)
        c = σ[I]
        c == 0 && continue
        for o in offs
            J = ntuple(d -> periodic[d] ? mod1(I[d] + o[d], L[d]) : I[d] + o[d], 2)
            all(d -> 1 <= J[d] <= L[d], 1:2) || continue
            s = σ[J...]
            s == c && continue
            unlike[c] += 1
            s == 0 && (med[c] += 1)
            kindof !== nothing && s != 0 && kindof[s] == toward && (tow[c] += 1)
        end
    end
    return (; unlike, med, tow)
end
p615c_live(u) = findall(>(0), Array(u.cell.volume))
"""A host copy of a saved state (σ and every cell column), so device states index alike."""
p615c_host(u) = (; σ = Array(u.σ), cell = map(Array, u.cell))
p615c_hosts(sol) = [p615c_host(u) for u in sol.u]
p615c_state_σ(st) = Array(only(p.second for p in st if p.first === ownership))
p615c_state_kinds(st) = collect(only(p.second for p in st if p.first === kind))
"""FNV-1a (64 bit) of σ's bytes then V_target's (no dependency beyond Base)."""
function p615c_fnv(bytes)
    h = 0xcbf29ce484222325
    for b in bytes
        h = (h ⊻ b) * 0x00000100000001b3
    end
    return h
end
p615c_digest(u) = p615c_fnv(vcat(reinterpret(UInt8, vec(Array(u.σ))), reinterpret(UInt8, Array(u.cell.V_target))))
p615c_par(prob, x) = getp(prob, x)(prob)

# The F4 lattice: σ[x + 1, y + 1] is the tikz pixel (x, y); cell i = 1, i−1 = 2, i+1 = 3, i+2 = 4
function p615c_fig4()
    σ = zeros(Int32, 7, 7)
    cells = (
        [(3, 1), (2, 2), (3, 2), (4, 2), (2, 3), (3, 3), (4, 3), (5, 3), (2, 4), (3, 4), (4, 4), (3, 5)],   # i (ca)
        [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (2, 1)],                                           # i−1 (cb)
        [(4, 0), (5, 0), (6, 0), (4, 1), (5, 1), (6, 1), (5, 2), (6, 2), (6, 3)],                           # i+1 (cc)
        [(4, 6), (5, 6), (6, 6), (4, 5), (5, 5), (6, 5), (5, 4), (6, 4)],                                   # i+2 (cd)
    )
    for (c, px) in enumerate(cells), (x, y) in px
        σ[x + 1, y + 1] = c
    end
    return σ
end

# The OpenVT model on the 60 × 60 test lattice (built once; `nothing` if it does not exist)
const P615C_L = (60, 60)
const P615C_SYS = Ref{Any}(nothing)
function p615c_sys()
    P615C_SYS[] === nothing && isdefined(PottsModels, :OpenVTReferenceMonolayer) &&
        (P615C_SYS[] = PottsModels.OpenVTReferenceMonolayer(; name = :p615c_m, lattice = P615C_L))
    return P615C_SYS[]
end
function p615c_prob(; tspan = (0, 300), seed = 153_001, p = Pair{Symbol, Any}[], op = nothing, kw...)
    sys = p615c_sys()
    sys === nothing && error("OpenVTReferenceMonolayer is not defined")
    st = op === nothing ? PottsModels.openvt_reference_state(; lattice = P615C_L) : op
    return PottsProblem(sys, [st; p...], tspan; capacity = 512, seed, kw...)
end

"""Division-free MCS k (host states `us`, save index i = k + 1): the same live ids and no
A_star decrease (A_star only grows, except at a division's Split)."""
function p615c_quiet(us, i)
    a, b = us[i - 1], us[i]
    p615c_live(a) == p615c_live(b) || return false
    return all(c -> b.cell.A_star[c] >= a.cell.A_star[c], p615c_live(b))
end

"""The division of MCS k (host states `us`, save i) as (parent, daughter), or `nothing`
unless exactly one happened: parent = live before with A_star decreased, daughter = new id."""
function p615c_division(us, i)
    a, b = us[i - 1], us[i]
    la, lb = p615c_live(a), p615c_live(b)
    born = setdiff(lb, la)
    parents = [c for c in intersect(la, lb) if b.cell.A_star[c] < a.cell.A_star[c] - 1e-12]
    (length(born) == 1 && length(parents) == 1) || return nothing
    return (only(parents), only(born))
end

# ---------------------------------------------------------------------------------------------
# G1: the contact fold
# ---------------------------------------------------------------------------------------------

@testset "P6.15c G1 F4: the fold equals M's Fig 4 lattice count (f_i = 13/38)" begin
    σ = p615c_fig4()
    @test [count(==(c), σ) for c in 0:4] == [13, 12, 7, 9, 8]
    # the oracle on the picture: magenta (medium) and orange (cell) dashes of cell i
    bf = p615c_contacts(σ, P615C_MOORE)
    @test bf.med == [13, 5, 0, 2] && bf.unlike == [38, 13, 14, 13]
    @test bf.med[1] == 13 && bf.unlike[1] - bf.med[1] == 25          # the drawn counts
    @test p615c_ok(:P615cFig4)
    if p615c_ok(:P615cFig4)
        prob = PottsProblem(P615cFig4(; name = :p615c_f4), [ownership => σ, kind => fill(:cell, 4)], (0, 1); seed = 1)
        u = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = 1).u[end]
        @test u.cell.m[1:4] == [13, 5, 0, 2]
        @test u.cell.u[1:4] == [38, 13, 14, 13]
        @test u.cell.m[1] / u.cell.u[1] == 13 / 38
        # negative control: von Neumann pairs on the same picture give another fraction
        bv = p615c_contacts(σ, P615C_VN)
        @test bv.med[1] / bv.unlike[1] != 13 / 38
    end
end

const P615C_FOLD_SEEDS = (151_001, 151_002)
const P615C_FOLD_MCS = 150

function p615c_fold_state()
    σ = zeros(Int32, 36, 30)
    blocks = ((vcat(35:36, 1:2), 1:5), (8:11, 1:5), (12:15, 1:5), (20:23, 10:14), (24:27, 10:14), (5:8, 25:29))
    for (c, (xs, ys)) in enumerate(blocks)
        σ[xs, ys] .= c
    end
    return [ownership => σ, kind => [:A, :B, :A, :B, :A, :B]]
end

"""Check every saved MCS of a P615cFold run against the brute-force oracle; returns counters."""
function p615c_check_fold(sol)
    out = Dict(k => 0 for k in (:before_bad, :before_n, :after_bad, :after_n, :divisions, :ab, :vn_differs,
        :stale_differs, :timing_differs))
    us = p615c_hosts(sol)
    for i in 2:length(us)
        prev, cur = us[i - 1], us[i]
        σp, σc = prev.σ, cur.σ
        kp = prev.cell.kind
        n = length(prev.cell.volume)
        bp = p615c_contacts(σp, P615C_MOORE; periodic = (true, false), kindof = kp, toward = 2, n)
        vp = p615c_contacts(σp, P615C_VN; periodic = (true, false), n)
        bc = p615c_contacts(σc, P615C_MOORE; periodic = (true, false), n)
        both = intersect(p615c_live(prev), p615c_live(cur))
        for c in both
            out[:before_n] += 1
            ok = cur.cell.mb[c] == bp.med[c] && cur.cell.ub[c] == bp.unlike[c] && cur.cell.bb[c] == bp.tow[c] &&
                 cur.cell.vb[c] == vp.med[c] && cur.cell.sb[c] == bp.unlike[c]
            out[:before_bad] += !ok
            out[:ab] += bp.tow[c] > 0
            out[:vn_differs] += vp.med[c] != bp.med[c]
            out[:timing_differs] += cur.cell.mb[c] != bc.med[c]
        end
        divided = any(c -> cur.cell.A_t[c] == 20, p615c_live(cur))
        out[:divisions] += divided
        if !divided
            for c in p615c_live(cur)
                out[:after_n] += 1
                out[:after_bad] += !(cur.cell.ma[c] == bc.med[c] && cur.cell.ua[c] == bc.unlike[c])
            end
        end
        out[:stale_differs] += bp.med != bc.med[1:length(bp.med)]
    end
    return out
end

@testset "P6.15c G1: the contact fold is exact after every MCS (random runs, both algorithms)" begin
    @test p615c_ok(:P615cFold)
    if p615c_ok(:P615cFold)
        prob = PottsProblem(P615cFold(; name = :p615c_fold), p615c_fold_state(), (0, P615C_FOLD_MCS); capacity = 64,
            seed = first(P615C_FOLD_SEEDS))
        for alg in P615C_ALGS, seed in P615C_FOLD_SEEDS
            sol = solve(remake(prob; seed), alg; saveat = 1)
            @test Symbol(sol.retcode) === :Success
            r = p615c_check_fold(sol)
            @test r[:before_bad] == 0                 # fresh after the lifecycle: equals σ of the previous MCS
            @test r[:after_bad] == 0                  # fresh after the sweep (division-free MCS)
            # non-vacuous
            @test r[:before_n] >= 6 * P615C_FOLD_MCS && r[:after_n] >= 4 * P615C_FOLD_MCS
            @test r[:divisions] >= 3                  # lifecycle events happened and were followed
            @test r[:ab] > 0 && r[:vn_differs] > 0    # A–B contacts present; VonNeumann ≠ Moore
            @test r[:stale_differs] >= P615C_FOLD_MCS ÷ 2   # a count one MCS stale would fail
            @test r[:timing_differs] > 0              # before-values are not the after-sweep state
        end
    end
end

"""Minimum per-MCS seconds of `n` warm steps over `reps` repetitions."""
function p615c_time(integ; n = 10, reps = 3)
    return minimum(1:reps) do _
        t = time_ns()
        for _ in 1:n
            step!(integ)
        end
        (time_ns() - t) / n / 1e9
    end
end

@testset "P6.15c G1: the fold is incremental (cost ≤ 1.5× the `surface` tracker)" begin
    @test p615c_ok(:P615cCostFold) && p615c_ok(:P615cCostSurf)
    if p615c_ok(:P615cCostFold) && p615c_ok(:P615cCostSurf)
        σ = zeros(Int32, 200, 200)
        k = 0
        for a in 0:35, b in 0:35
            k += 1
            σ[20 + 5a .+ (1:5), 20 + 5b .+ (1:5)] .= k
        end
        op = [ownership => σ, kind => fill(:cell, k)]
        for alg in P615C_ALGS
            a = init(PottsProblem(P615cCostFold(; name = :p615c_cf), op, (0, 10^6)), alg; save_start = false, save_end = false)
            b = init(PottsProblem(P615cCostSurf(; name = :p615c_cs), op, (0, 10^6)), alg; save_start = false, save_end = false)
            foreach(_ -> (step!(a); step!(b)), 1:5)
            # the fold model computes the true fraction (control: not a constant)
            fs = Array(a.u.cell.f)[1:k]
            @test minimum(fs) == 0 && any(x -> 0 < x < 1, fs)       # interior cells 0, rim cells in between
            rs = map(1:10) do r
                ta, tb = isodd(r) ? (p615c_time(a), p615c_time(b)) : reverse((p615c_time(b), p615c_time(a)))
                ta / tb
            end
            @info "P6.15c G1 cost ($(nameof(typeof(alg)))): fold / surface per MCS, min $(round(minimum(rs); digits = 3)), median $(round(sort(rs)[5]; digits = 3))"
            @test minimum(rs) <= 1.5          # a whole-lattice recomputation measures ≈ 2.7×
        end
    end
end

# ---------------------------------------------------------------------------------------------
# G2: randn() and per-daughter draws
# ---------------------------------------------------------------------------------------------

const P615C_DRAW_SEEDS = (152_001, 152_002)
function p615c_draws_state()
    σ = zeros(Int32, 80, 80)
    k = 0
    for a in 0:19, b in 0:19
        k += 1
        σ[4a .+ (1:4), 4b .+ (1:4)] .= k
    end
    return [ownership => σ, kind => fill(:A, k), :tag => [2.0c for c in 1:k]]
end

@testset "P6.15c G2: randn() and per-daughter draws in division rules" begin
    @test p615c_ok(:P615cDraws)
    if p615c_ok(:P615cDraws)
        prob = PottsProblem(P615cDraws(; name = :p615c_dr), p615c_draws_state(), (0, 6); capacity = 1024,
            seed = first(P615C_DRAW_SEEDS))
        sols = Dict((nameof(typeof(alg)), s) => solve(remake(prob; seed = s), alg; saveat = 1)
                    for alg in P615C_ALGS, s in P615C_DRAW_SEEDS)
        sol = sols[(:SequentialCPM, first(P615C_DRAW_SEEDS))]
        u1 = sol.u[2]                                     # after MCS 0: every cell divided once
        live = p615c_live(u1)
        @test length(live) == 800
        # pairs by the split tag: parent and daughter both carry c
        tags = Array(u1.cell.tag)
        pairs_ = [findall(==(Float64(c)), tags[1:length(tags)]) for c in 1:400]
        @test all(p -> length(p) == 2, pairs_)
        dp = [u1.cell.d[p[1]] for p in pairs_]; dd = [u1.cell.d[p[2]] for p in pairs_]
        hp = [u1.cell.h[p[1]] for p in pairs_]; hd = [u1.cell.h[p[2]] for p in pairs_]
        # each daughter draws: the two values differ, independently
        @test all(dp .!= dd) && all(hp .!= hd)
        @test abs(cor(dp, dd)) <= 0.2 && abs(cor(hp, hd)) <= 0.2       # 4/√400
        ds = vcat(dp, dd)
        @test abs(mean(ds)) <= 4 / sqrt(800) && abs(var(ds) - 1) <= 4 * sqrt(2 / 800)
        @test all(x -> 0 < x < 1, vcat(hp, hd)) && abs(mean(vcat(hp, hd)) - 0.5) <= 4 * sqrt(1 / 12 / 800)
        # a rule without a draw still copies (control)
        @test all(==(7.0), u1.cell.e[live])
        # randn() per MCS and per cell: N(0, 1)
        Z = reduce(vcat, [Array(u.cell.z)[p615c_live(u)] for u in sol.u[3:end]])      # MCS 1..5, 800 cells
        W = reduce(vcat, [Array(u.cell.w)[p615c_live(u)] for u in sol.u[3:end]])
        n = length(Z)
        @test n == 4000
        @test abs(mean(Z)) <= 4 / sqrt(n)
        @test abs(var(Z) - 1) <= 4 * sqrt(2 / n)
        @test abs(mean(abs.(Z) .> 1.959964) - 0.05) <= 4 * sqrt(0.05 * 0.95 / n)
        @test abs(mean(Z .> 0) - 0.5) <= 4 * sqrt(0.25 / n)
        @test abs(cor(Z, W)) <= 4 / sqrt(n)                              # distinct streams
        # fresh per MCS: lag-1 correlation of each cell's draws
        z2 = [Array(sol.u[i].cell.z)[1:800] for i in 3:7]
        lag = reduce(vcat, [z2[i] for i in 1:4]); lead = reduce(vcat, [z2[i] for i in 2:5])
        @test abs(cor(lag, lead)) <= 4 / sqrt(3200)
        @test length(unique(Z)) == n
        # stable stream: keyed by (seed, MCS, cell), so equal on both algorithms
        for s in P615C_DRAW_SEEDS
            a, b = sols[(:SequentialCPM, s)], sols[(:CheckerboardCPM, s)]
            @test all(i -> Array(a.u[i].cell.w)[1:800] == Array(b.u[i].cell.w)[1:800], 3:7)   # rand(): positive control (today)
            @test all(i -> Array(a.u[i].cell.z)[1:800] == Array(b.u[i].cell.z)[1:800], 3:7)
            @test Array(a.u[2].cell.d)[1:800] == Array(b.u[2].cell.d)[1:800]
            @test Array(a.u[2].σ) != Array(b.u[2].σ)                     # control: the sweeps differ
        end
        # reproducible under the seed; another seed draws otherwise
        again = solve(prob, first(P615C_ALGS); saveat = 1)
        @test all(i -> Array(again.u[i].cell.z) == Array(sol.u[i].cell.z) && Array(again.u[i].cell.d) == Array(sol.u[i].cell.d), 1:7)
        other = sols[(:SequentialCPM, last(P615C_DRAW_SEEDS))]
        @test Array(other.u[3].cell.z)[1:800] != Array(sol.u[3].cell.z)[1:800]
    end
end

# ---------------------------------------------------------------------------------------------
# The Table S1 model
# ---------------------------------------------------------------------------------------------

@testset "P6.15c model: OpenVTReferenceMonolayer has Table S1's parameters (M p.11, §2.1)" begin
    @test isdefined(PottsModels, :OpenVTReferenceMonolayer) && :OpenVTReferenceMonolayer in names(PottsModels)
    @test isdefined(PottsModels, :openvt_reference_state) && :openvt_reference_state in names(PottsModels)
    if p615c_sys() !== nothing
        sys = PottsModels.OpenVTReferenceMonolayer(; name = :p615c_default)
        lat = Potts.lattice(sys)
        @test lat.dims == (1400, 1400)
        @test !Potts.isperiodic(lat, 1) && !Potts.isperiodic(lat, 2)
        prob = p615c_prob(; tspan = (0, 1))
        @test (p615c_par(prob, :A₀), p615c_par(prob, :λ), p615c_par(prob, :T)) == (50.0, 2.0, 20.0)
        @test p615c_par(prob, :α) == 50 / 775 && abs(p615c_par(prob, :α) - 6.452e-2) < 5e-6   # Table S1, C16
        @test isapprox(p615c_par(prob, :A₀) / p615c_par(prob, :α), 775; rtol = 1e-12)           # 5T = 775 MCS (C1)
        @test (p615c_par(prob, :μ_X), p615c_par(prob, :σ_X)) == (2.0, 0.4)
        @test p615c_par(prob, :μ_X) * p615c_par(prob, :A₀) == 100.0                              # μ_Amax
        @test (p615c_par(prob, :β), p615c_par(prob, :γ)) == (0.0, 0.0)
        @test p615c_par(prob, :J) == [0.0 10.0; 10.0 20.0]                                       # J_cm = 10, J_cc = 20
        @test prob.u0.cell.A_star[1] == 50.0                                                     # A*(0)
        @test prob.f.lifecycle !== nothing
    end
end

@testset "P6.15c G5: the disc start" begin
    @test isdefined(PottsModels, :openvt_reference_state)
    if isdefined(PottsModels, :openvt_reference_state)
        for (L, n) in (((100, 100), 52), ((101, 101), 45), ((1400, 1400), 52), ((60, 60), 52))
            st = PottsModels.openvt_reference_state(; lattice = L)
            σ = p615c_state_σ(st)
            @test size(σ) == L && p615c_state_kinds(st) == [:cell]
            c = (L .+ 1) ./ 2
            disc = [I for I in CartesianIndices(σ) if hypot(I[1] - c[1], I[2] - c[2]) <= P615C_R]
            @test count(==(1), σ) == n == length(disc)
            @test all(I -> σ[I] == 1, disc) && count(!=(0), σ) == n && maximum(σ) == 1
            idx = findall(==(1), σ)
            @test (mean(i[1] for i in idx), mean(i[2] for i in idx)) == c                      # centred
        end
        @test p615c_state_σ(PottsModels.openvt_reference_state()) ==
              p615c_state_σ(PottsModels.openvt_reference_state(; lattice = (1400, 1400)))
        # the radius follows A₀
        σ = p615c_state_σ(PottsModels.openvt_reference_state(; lattice = (100, 100), A₀ = 100))
        @test count(==(1), σ) == count(I -> hypot(I[1] - 50.5, I[2] - 50.5) <= sqrt(100 / π), CartesianIndices(σ))
        @test abs(count(==(1), σ) - 100) <= 10
        # negative control: the 2024 state is a 5 × 5 square, not a disc
        @test count(!=(0), first(openvt_monolayer_state(; lattice = (100, 100))).second) == 25
    end
end

@testset "P6.15c model: runs on both algorithms; f is G1's; uninhibited growth by α" begin
    @test p615c_sys() !== nothing
    if p615c_sys() !== nothing
        for alg in P615C_ALGS, seed in (153_001, 153_002)
            sol = solve(p615c_prob(; tspan = (0, 400), seed, p = [:α => 0.5]), alg; saveat = 1)
            @test Symbol(sol.retcode) === :Success
            α = 0.5
            bad_f = 0; bad_g = 0; quiet = 0; divs = 0; badX = 0; bad_v = 0
            us = p615c_hosts(sol)
            for i in 2:length(us)
                u = us[i]
                live = p615c_live(u)
                bad_v += u.cell.volume[live] != [count(==(c), u.σ) for c in live]
                badX += count(c -> !(u.cell.X[c] > 0), live)
                if p615c_quiet(us, i)
                    quiet += 1
                    bf = p615c_contacts(u.σ, P615C_MOORE; n = length(u.cell.volume))
                    bad_f += count(c -> u.cell.f[c] != bf.med[c] / bf.unlike[c], live)
                    bad_g += count(c -> abs(u.cell.A_star[c] - us[i - 1].cell.A_star[c] - α) > 1e-9, live)
                else
                    divs += 1
                end
            end
            @test bad_v == 0
            @test badX == 0
            @test bad_f == 0 && bad_g == 0
            @test quiet >= 300 && divs >= 3
        end
    end
end

@testset "P6.15c model: the growth law with β and γ (after every MCS of an inhibited colony)" begin
    @test p615c_sys() !== nothing
    if p615c_sys() !== nothing
        # a 5 × 5 block of 7 × 7 cells (interior cells have f = 0); X ≡ 2 and slow growth: no division
        σ = zeros(Int32, P615C_L)
        k = 0
        for a in 0:4, b in 0:4
            k += 1
            σ[13 + 7a .+ (1:7), 13 + 7b .+ (1:7)] .= k
        end
        β, γ = 0.97, 0.1037
        op = [ownership => σ, kind => fill(:cell, k)]
        n_grow = n_β = n_γ = n_both = n_alt = bad = lost = 0
        for alg in P615C_ALGS, seed in (153_011, 153_012)
            sol = solve(p615c_prob(; tspan = (0, 250), seed, op, p = [:β => β, :γ => γ, :σ_X => 0.0]), alg; saveat = 1)
            @test Symbol(sol.retcode) === :Success
            us = p615c_hosts(sol)
            for i in 2:length(us)
                prev, u = us[i - 1], us[i]
                lost += p615c_live(u) != 1:k                                 # no division, no loss
                bf = p615c_contacts(u.σ, P615C_MOORE; n = length(u.cell.volume))
                for c in 1:k
                    A0, A1, v = prev.cell.A_star[c], u.cell.A_star[c], u.cell.volume[c]
                    f = bf.med[c] / bf.unlike[c]
                    grew = abs(A1 - A0 - 50 / 775) <= 1e-9
                    same = abs(A1 - A0) <= 1e-12
                    okβ, okγ = v / A0 >= β, f >= γ
                    bad += !(grew || same) || (grew != (okβ && okγ)) || u.cell.f[c] != f
                    n_grow += okβ && okγ
                    n_β += !okβ && okγ
                    n_γ += okβ && !okγ
                    n_both += !okβ && !okγ
                    n_alt += (v / A0 >= β) != (v / 50 >= β)                  # CC3D's a = A/A₀ differs
                end
            end
        end
        @test bad == 0 && lost == 0
        # non-vacuous: every branch of the law was taken
        @test n_grow >= 200 && n_β >= 50 && n_γ >= 50 && n_both >= 20 && n_alt >= 20
    end
end

@testset "P6.15c model: C9 at equality (≥ grows, nextfloat does not)" begin
    @test p615c_sys() !== nothing
    if p615c_sys() !== nothing
        st = PottsModels.openvt_reference_state(; lattice = P615C_L)
        σ0 = p615c_state_σ(st)
        v = count(==(1), σ0)                      # 52: frozen in place by λ = 1e6 at T = 1e-3
        for (β, γ, grows) in ((1.0, 0.0, true), (nextfloat(1.0), 0.0, false), (0.0, 1.0, true), (0.0, nextfloat(1.0), false))
            p = [:λ => 1e6, :T => 1e-3, :A₀ => Float64(v), :β => β, :γ => γ, :σ_X => 0.0]
            sol = solve(p615c_prob(; tspan = (0, 1), op = [st; :A_star => [Float64(v)]], p), first(P615C_ALGS); saveat = 1)
            u = sol.u[end]
            @test Array(u.σ) == σ0                                   # a = 1 and f = 1 exactly
            @test u.cell.f[1] == 1.0
            @test u.cell.A_star[1] == (grows ? v + 50 / 775 : Float64(v))
        end
    end
end

@testset "P6.15c model: division at X·A₀, Split, both daughters redraw X (M §2.1, C13, C14)" begin
    @test p615c_sys() !== nothing
    if p615c_sys() !== nothing
        births = Float64[]; pairsX = Tuple{Float64, Float64}[]
        bad_thresh = bad_split = bad_redraw = n_single = n_div = 0
        for seed in 153_021:153_024
            sol = solve(p615c_prob(; tspan = (0, 300), seed, p = [:α => 1.0]), first(P615C_ALGS); saveat = 1)
            us = p615c_hosts(sol)
            for i in 2:length(us)
                prev, u = us[i - 1], us[i]
                A₀ = 50.0
                ev = p615c_division(us, i)
                born = setdiff(p615c_live(u), p615c_live(prev))
                n_div += length(born)
                # no surviving non-dividing cell is at or above its threshold (checked after the sweep)
                parents = [c for c in intersect(p615c_live(prev), p615c_live(u)) if u.cell.A_star[c] < prev.cell.A_star[c] - 1e-12]
                for c in setdiff(p615c_live(u), born, parents)
                    bad_thresh += !(u.cell.volume[c] < u.cell.X[c] * A₀)
                end
                ev === nothing && continue
                p, d = ev
                n_single += 1
                bad_thresh += !(u.cell.volume[p] + u.cell.volume[d] >= prev.cell.X[p] * A₀)
                bad_split += !(u.cell.A_star[p] == u.cell.A_star[d] &&
                               abs(u.cell.A_star[p] + u.cell.A_star[d] - (prev.cell.A_star[p] + 1.0)) <= 1e-9)
                bad_redraw += !(u.cell.X[p] != prev.cell.X[p] && u.cell.X[d] != u.cell.X[p])
                append!(births, (u.cell.X[p], u.cell.X[d]))
                push!(pairsX, (u.cell.X[p], u.cell.X[d]))
            end
        end
        @test bad_thresh == 0
        @test bad_split == 0
        @test bad_redraw == 0
        @test n_div >= 100 && n_single >= 80
        n = length(births)
        @test all(>(0), births)
        @test abs(mean(births) - 2) <= 4 * 0.4 / sqrt(n)
        @test abs(std(births) - 0.4) <= 4 * 0.4 / sqrt(2n)
        @test abs(cor(first.(pairsX), last.(pairsX))) <= 4 / sqrt(length(pairsX))
    end
end

@testset "P6.15c model: X is redrawn while ≤ 0 (C3), at birth" begin
    @test p615c_sys() !== nothing
    if p615c_sys() !== nothing
        # σ_X = 1.25: P(X ≤ 0) = Φ(−1.6) ≈ 5.5 % per raw draw, so an untruncated draw shows up
        # (≥ 100 draws: missed with P < 0.4 %)
        draws = Float64[]
        nonpos = 0
        for seed in 153_031:153_034
            sol = solve(p615c_prob(; tspan = (0, 300), seed, p = [:α => 1.0, :σ_X => 1.25]), first(P615C_ALGS); saveat = 1)
            @test Symbol(sol.retcode) === :Success
            for i in 2:length(sol.u)
                u = sol.u[i]
                live = p615c_live(u)
                nonpos += count(c -> !(u.cell.X[c] > 0), live)
                born = setdiff(live, p615c_live(sol.u[i - 1]))
                append!(draws, [u.cell.X[c] for c in born])
            end
        end
        @test nonpos == 0
        n = length(draws)
        @test n >= 100
        # N(2, 1.25²) truncated at 0: mean 2 + 1.25 φ(1.6)/Φ(1.6) = 2.1467
        @test abs(mean(draws) - 2.1467) <= 4 * 1.25 / sqrt(n)
    end
end

@testset "P6.15c model: the first cell's X (drawn per seed, keyed like every draw)" begin
    @test p615c_sys() !== nothing
    if p615c_sys() !== nothing
        prob = p615c_prob(; tspan = (0, 1))
        X1 = Float64[]
        for seed in 1:200
            u = solve(remake(prob; seed), first(P615C_ALGS); saveat = 1).u[end]
            p615c_live(u) == [1] && push!(X1, u.cell.X[1])
        end
        n = length(X1)
        @test n >= 190                                 # X·A₀ ≤ 52 has P ≈ 0.8 %
        @test all(>(0), X1) && length(unique(X1)) == n
        @test abs(mean(X1) - 2) <= 4 * 0.4 / sqrt(n) && abs(std(X1) - 0.4) <= 4 * 0.4 / sqrt(2n)
        # reproducible, and the same on both algorithms (the sweep does not touch the stream)
        for seed in 1:10
            a = solve(remake(prob; seed), P615C_ALGS[1]; saveat = 1).u[end]
            b = solve(remake(prob; seed), P615C_ALGS[2]; saveat = 1).u[end]
            c = solve(remake(prob; seed), P615C_ALGS[1]; saveat = 1).u[end]
            @test a.cell.X[1] == c.cell.X[1] && Array(a.σ) == Array(c.σ)
            p615c_live(a) == p615c_live(b) == [1] && @test a.cell.X[1] == b.cell.X[1]
        end
    end
end

const P615C_DET_SEEDS = 15_001:15_004
const P615C_STO_SEEDS = 15_001:15_006
"""N(MCS) in the case-(f) windows: 1 on 0:650, 2 on 800:1400, 4 on 1600:2100, 8 at 2400."""
p615c_windows(N) = all(N[m + 1] == 1 for m in 0:650) && all(N[m + 1] == 2 for m in 800:1400) &&
                   all(N[m + 1] == 4 for m in 1600:2100) && N[2401] == 8

@testset "P6.15c G2: deterministic mode X ≡ 2 gives synchronous doublings (case (f))" begin
    @test p615c_sys() !== nothing
    if p615c_sys() !== nothing
        prob = p615c_prob(; tspan = (0, 2400), p = [:σ_X => 0.0])
        for seed in P615C_DET_SEEDS
            sol = solve(remake(prob; seed), first(P615C_ALGS); saveat = 1)
            N = [length(p615c_live(u)) for u in sol.u]
            @test all(u -> all(c -> u.cell.X[c] == 2.0, p615c_live(u)), sol.u[2:end])
            @test p615c_windows(N)
            # the steps fall near t = 1, 2, 3 cycles (775 MCS each)
            steps = [k - 1 for k in 2:length(N) if N[k] != N[k - 1]]
            @test all(s -> any(j -> j - 0.2 <= s / 775 <= j + 0.02, 1:3), steps)
        end
        # negative control: the stochastic mode (σ_X = 0.4) misses the windows
        hits = count(seed -> p615c_windows([length(p615c_live(u)) for u in
                                            solve(remake(prob; seed, p = [:σ_X => 0.4]), first(P615C_ALGS); saveat = 1).u]),
                     P615C_STO_SEEDS)
        @test hits <= 2
    end
end

# ---------------------------------------------------------------------------------------------
# The 2024 set is kept, bit for bit
# ---------------------------------------------------------------------------------------------

@testset "P6.15c: OpenVTGrowingMonolayer (the 2024 Artistoo set) is unchanged" begin
    prob = PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)), openvt_monolayer_state(; lattice = (24, 24)),
        (0, 10); capacity = 64)
    @test prob.f.fingerprint == 0xfcecc4612f387b5e
    p = PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (40, 40), τ = 10.0), openvt_monolayer_state(; lattice = (40, 40)),
        (0, 60); capacity = 256, seed = 3)
    @test (p615c_par(p, :A₀), p615c_par(p, :λ), p615c_par(p, :τ), p615c_par(p, :J)) == (25.0, 20.0, 10.0, [0.0 20.0; 20.0 20.0])
    for (alg, n, h) in ((SequentialCPM(), 32, 0xbc48e2769f4e0859), (CheckerboardCPM(), 16, 0xf0c391e15b30e661))
        u = solve(p, alg).u[end]
        @test count(>(0), u.cell.volume) == n
        @test p615c_digest(u) == h
    end
end

# ---------------------------------------------------------------------------------------------
# G6: the domain guard
# ---------------------------------------------------------------------------------------------

@testset "P6.15c G6: near_edge and edge_guard" begin
    @test isdefined(PottsModels.Analysis, :near_edge) && isdefined(PottsModels, :edge_guard)
    if isdefined(PottsModels.Analysis, :near_edge)
        ne = PottsModels.Analysis.near_edge
        one_at(i, j) = (σ = zeros(Int32, 20, 16); σ[i, j] = 7; σ)
        @test !ne(zeros(Int32, 20, 16), 3)
        @test !ne(one_at(4, 8), 3) && ne(one_at(3, 8), 3)
        @test !ne(one_at(17, 8), 3) && ne(one_at(18, 8), 3)
        @test !ne(one_at(10, 4), 3) && ne(one_at(10, 3), 3)
        @test !ne(one_at(10, 13), 3) && ne(one_at(10, 14), 3)
        @test !ne(one_at(1, 1), 0) && ne(one_at(1, 1), 1)
    end
    if isdefined(PottsModels, :edge_guard) && p615c_sys() !== nothing
        ne = PottsModels.Analysis.near_edge
        # a fast colony on 60 × 60 reaches the 12-site margin within 400 MCS
        prob = p615c_prob(; tspan = (0, 400), seed = 153_041, p = [:α => 2.0])
        free = solve(prob, first(P615C_ALGS); saveat = 1)
        @test Symbol(free.retcode) === :Success                         # control: no guard, it runs on
        hit = findfirst(u -> ne(Array(u.σ), 12), free.u)
        @test hit !== nothing && hit > 2
        @test_throws DomainError solve(prob, first(P615C_ALGS); callback = PottsModels.edge_guard(12))
        sol = solve(prob, first(P615C_ALGS); saveat = 1, callback = PottsModels.edge_guard(12; terminate = true))
        @test sol.retcode == ReturnCode.Failure
        @test sol.t[end] == free.t[hit] && Array(sol.u[end].σ) == Array(free.u[hit].σ)
        @test !ne(Array(sol.u[end - 1].σ), 12)
        # control: a margin the run never reaches
        quiet = solve(remake(prob; tspan = (0, 100)), first(P615C_ALGS); callback = PottsModels.edge_guard(3))
        @test Symbol(quiet.retcode) === :Success
    end
end

# ---------------------------------------------------------------------------------------------
# G11: stop at N cells, and the O2 snapshot
# ---------------------------------------------------------------------------------------------

"""The first `n` 4 × 4 tiles (column-major) of the 100 × 100 tiling of 400 × 400."""
function p615c_tiles(n)
    σ = zeros(Int32, 400, 400)
    k = 0
    for b in 0:99, a in 0:99
        k == n && break
        k += 1
        σ[4a .+ (1:4), 4b .+ (1:4)] .= k
    end
    return [ownership => σ, kind => fill(:cell, n)]
end

@testset "P6.15c G11: stop_at_cells at 1000 and 10⁴ cells, and at the first crossing" begin
    @test isdefined(PottsModels, :stop_at_cells)
    if isdefined(PottsModels, :stop_at_cells)
        for n in (1000, 10_000)
            cb = PottsModels.stop_at_cells(n)
            @test cb isa DiscreteCallback
            at = solve(PottsProblem(P615cTiles(; name = :p615c_t), p615c_tiles(n), (0, 3); capacity = 10_100),
                first(P615C_ALGS); callback = cb)
            @test at.retcode == ReturnCode.Terminated && at.t[end] == 1
            below = solve(PottsProblem(P615cTiles(; name = :p615c_t), p615c_tiles(n - 1), (0, 3); capacity = 10_100),
                first(P615C_ALGS); callback = cb)
            @test Symbol(below.retcode) === :Success && below.t[end] == 3     # control
        end
        if p615c_sys() !== nothing
            prob = p615c_prob(; tspan = (0, 600), seed = 153_051, p = [:α => 1.0])
            ref = solve(prob, first(P615C_ALGS); saveat = 1)
            N = [length(p615c_live(u)) for u in ref.u]
            first8 = findfirst(>=(8), N)
            @test first8 !== nothing && N[first8 - 1] < 8
            sol = solve(prob, first(P615C_ALGS); saveat = 1, callback = PottsModels.stop_at_cells(8))
            @test sol.retcode == ReturnCode.Terminated
            @test sol.t[end] == ref.t[first8] && Array(sol.u[end].σ) == Array(ref.u[first8].σ)
        end
    end
end

@testset "P6.15c G11: the O2 snapshot (x, y, r, f, a in R; r = √(A*/π)/R)" begin
    @test isdefined(PottsModels, :openvt_snapshot)
    if isdefined(PottsModels, :openvt_snapshot) && p615c_sys() !== nothing
        snap = PottsModels.openvt_snapshot
        # the initial disc: at the origin, r = 1 R, f = 1, a = 52/50
        u0 = p615c_prob(; tspan = (0, 1)).u0
        s0 = snap(u0)
        @test keys(s0) == (:x, :y, :r, :f, :a)
        @test s0.x == [0.0] && s0.y == [0.0] && abs(s0.r[1] - 1) <= 1e-12 && s0.f == [1.0] && s0.a == [52 / 50]
        # a grown colony against brute force
        sol = solve(p615c_prob(; tspan = (0, 300), seed = 153_061, p = [:α => 1.0]), first(P615C_ALGS))
        u = sol.u[end]
        s = snap(u)
        live = p615c_live(u)
        σ = Array(u.σ)
        bf = p615c_contacts(σ, P615C_MOORE; n = length(u.cell.volume))
        cx = [mean(I[1] for I in findall(==(c), σ)) for c in live]
        cy = [mean(I[2] for I in findall(==(c), σ)) for c in live]
        @test length(live) >= 8 && length(s.x) == length(live)
        @test maximum(abs.(s.x .- (cx .- 30.5) ./ P615C_R)) <= 1e-12
        @test maximum(abs.(s.y .- (cy .- 30.5) ./ P615C_R)) <= 1e-12
        @test maximum(abs.(s.r .- sqrt.(Array(u.cell.A_star)[live] ./ π) ./ P615C_R)) <= 1e-12
        @test s.f == [bf.med[c] / bf.unlike[c] for c in live]
        @test maximum(abs.(s.a .- Array(u.cell.volume)[live] ./ Array(u.cell.A_star)[live])) <= 1e-12
        @test any(<(1.0), s.f)                                           # non-vacuous: contacts between cells
        # the centre and A₀ keywords
        s2 = snap(u; A₀ = 100.0, center = (1.0, 1.0))
        @test maximum(abs.(s2.x .- (cx .- 1) ./ sqrt(100 / π))) <= 1e-12
        # written with P6.15d's writer (feat/p6-15d surface) when it is merged
        if isdefined(PottsModels, :write_openvt) && isdefined(PottsModels, :read_openvt)
            dir = mktempdir()
            path = joinpath(dir, PottsModels.openvt_filename(:O2; k = 1))
            mkpath(dirname(path))
            PottsModels.write_openvt(path, :O2, s)
            @test isequal(PottsModels.read_openvt(path, :O2), s)
            @test readline(path) == "x,y,r,f,a"
        else
            @test_broken isdefined(PottsModels, :write_openvt)              # P6.15d not merged yet
        end
    end
end

# ---------------------------------------------------------------------------------------------
# Metal
# ---------------------------------------------------------------------------------------------

@testset "P6.15c device: G1 exact, per-daughter draws, the model's f (CheckerboardCPM, Float32)" begin
    if P615C_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        if p615c_ok(:P615cFold)
            prob = PottsProblem(P615cFold(; name = :p615c_fold32), p615c_fold_state(), (0, P615C_FOLD_MCS); capacity = 64,
                seed = first(P615C_FOLD_SEEDS), T = Float32)
            r = p615c_check_fold(solve(prob, CheckerboardCPM(); backend, saveat = 1))
            @test r[:before_bad] == 0 && r[:after_bad] == 0 && r[:divisions] >= 3
        else
            @test p615c_ok(:P615cFold)
        end
        if p615c_ok(:P615cDraws)
            prob = PottsProblem(P615cDraws(; name = :p615c_dr32), p615c_draws_state(), (0, 2); capacity = 1024,
                seed = first(P615C_DRAW_SEEDS), T = Float32)
            u1 = solve(prob, CheckerboardCPM(); backend, saveat = 1).u[2]
            tags = Array(u1.cell.tag); d = Array(u1.cell.d)
            prs = [findall(==(Float32(c)), tags) for c in 1:400]
            @test all(p -> length(p) == 2 && d[p[1]] != d[p[2]], prs)
            @test abs(mean(d[1:800])) <= 4 / sqrt(800)
        else
            @test p615c_ok(:P615cDraws)
        end
        if p615c_sys() !== nothing
            sol = solve(p615c_prob(; tspan = (0, 300), seed = 153_071, p = [:α => 1.0], T = Float32), CheckerboardCPM();
                backend, saveat = 1)
            bad = 0; quiet = 0; badX = 0
            us = p615c_hosts(sol)
            for i in 2:length(us)
                u = us[i]
                badX += count(c -> !(u.cell.X[c] > 0), p615c_live(u))
                p615c_quiet(us, i) || continue
                quiet += 1
                bf = p615c_contacts(u.σ, P615C_MOORE; n = length(u.cell.volume))
                bad += count(c -> abs(u.cell.f[c] - bf.med[c] / bf.unlike[c]) > eps(Float32), p615c_live(u))
            end
            @test bad == 0 && badX == 0 && quiet >= 200
        else
            @test p615c_sys() !== nothing
        end
    else
        @test_skip P615C_ON_DEVICE
    end
end
