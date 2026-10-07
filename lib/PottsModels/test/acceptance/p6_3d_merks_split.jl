# P6.3d (ROADMAP Phase 6, step 3) + P6.3e: Merks split into `Merks2006` and `Merks2008`
# per D-050 M1–M11 (model-spec 01, README §4.1), the `merks_state` port onto `Scattered`
# (D-087), the 2008 20-neighbour contacts and copies with a 2-thick frame (P6.3e), and the
# D-141 follow-up: a `Splits` cell repaired into one piece by a later layer is not warned
# about. Adopts D-145's `@boundary … sites(kind == border) => Dirichlet(0.0)` and
# `@schedule fields, sweep` (D-145 ruling 10). Decision: D-153. Frozen (AUTONOMY §7.3).
#
# Surface pinned here (PottsModels, exported; nothing in Potts or CorePotts is model-named):
#
#   Merks2006(; name, lattice = (500, 500), rule = :soft, <parameters>)   Variant E (01a)
#   Merks2008(; name, lattice = (202, 202), mode = :extension_retraction, <parameters>)
#                                                                          Variant CI (01b)
#     Kinds `medium`, `endothelial`, `border[frozen]` (in that order).
#     Parameters, lattice units (Δx = 2 µm, 1 MCS = 30 s = 15 × Δt = 2 s; spec 01 §3):
#       both: T, λ, A, J[kind, kind] (3 × 3, medium/endothelial/border), χcM, χcc, s,
#             Dc (D·30 s/Δx²), α (secretion per MCS), ε (decay per MCS)
#       2006: T 50, λ 50, A 100, λ_L 5, L 50 (M2; 60 is the `L = 60.0` variant), E₀ 5000
#             (M3), χcM = χcc = 1000 (chemotaxis at every copy, spec A-7), s 0, Dc 0.75,
#             α = ε = 5.4e-3 (1.8e-4 s⁻¹ · 30 s) — spec 01 §3.1, §7.8
#       2008: T 50, λ 25, A 50, χcM 500, χcc 0 (contact inhibition), s 0, Dc 0.75,
#             α = ε = 0.03 (1e-3 s⁻¹ · 30 s), t_relax 100 (M6) — spec 01 §3.2, §7.1
#       J = [0 20 0; 20 40 100; 0 100 0] (J(c,M) 20, J(c,c) 40, J(c,B) 100, J(M,B) 0; M4)
#     Contacts and copies: 2006 the 8 Moore neighbours; 2008 the 20 neighbours of
#     NeighborOrder(4) (P6.3e, `neighbours = 3` in Dataset S1).
#     H (exact Float ΔH, M9): Σ_pairs J(1 − δ) + Σ_endothelial λ(a − A)² [+ λ_L(l − L)² in
#       2006, l = 4√(largest eigenvalue of the site-coordinate covariance), 01a Eq. 5].
#     Chemotaxis drive (01b Eq. 3; 01a Eq. 2 with s = 0): −χ (sat(c[target]) − sat(c[source])),
#       sat(c) = c / (1 + s c), χ = χcM when the target's or the source's owner is the
#       medium, χcc otherwise (spec 01 §8 A-13). 2008 `mode = :extension_only` (01b Eq. 4):
#       0 when the source is medium (a retraction). Any other `mode` is an ArgumentError.
#     2006 connectivity (M3, D-140): `rule = :soft` adds the drive E₀ · breaks, where breaks
#       is TST's ConnectivityPreservedP failing for a losing endothelial cell (ca.cpp:1166-1226);
#       `rule = :hard` instead vetoes exactly those copies (and has no E₀ drive). Any other
#       `rule` is an ArgumentError.
#     Field (M5): D(c) = Dc Δc + α [endothelial] − ε c [medium], 5-point Δ, per MCS;
#       absorbing ring: `@boundary c begin sites(kind == border) => Dirichlet(0.0) end`;
#       `@schedule fields, sweep` (the field step of MCS k sees σ(k), vessel.cpp:86-94). The
#       docstrings give the paper's solver `ExplicitEuler(substeps = 15)` (Δt = 2 s).
#       2008: no field before MCS t_relax (0-based MCS index; the first t_relax MCS leave
#       c = 0 everywhere: TST's `relaxation`, M6); 2006 has no relaxation.
#
#   merks_layout(; lattice = (500, 500), region = <(333, 333) on 500², else lattice>, n = 282,
#       side = 10, seed = 1) -> Scattered        the D-087 port: n endothelial side² boxes,
#       gap 1, at uniformly random corners in (off + 2):(off + R − 1) per axis, off = (lattice
#       − region) ÷ 2 — draw-for-draw the former hand loop of `merks_state` under a StableRNG
#   merks_state(; lattice = (500, 500), kw...) == layout(merks_layout(; lattice, kw...), lattice)
#   merks2006_layout(; lattice = (500, 500), kw...) =
#       overlay(Frame(:border; width = 1), merks_layout(; lattice, kw...))
#   merks2008_sprout(; rounds = 50, divisions = 7, seed = 1) =
#       overlay(Frame(:border; width = 2), Splits(Eden(Center(); rounds, kinds = [:endothelial],
#               seed, neighborhood = Moore(1)), divisions; splits = :allow))       (D-141, M11)
#   merks2008_denovo(; lattice = (202, 202), n = 360, rounds = 10,
#       region = (3:(lattice[1] − 2), 3:(lattice[2] − 2)), seed = 1) =
#       overlay(Frame(:border; width = 2), Eden(RandomPoints(n; region, replace = true, seed);
#               rounds, kinds = [:endothelial], seed, neighborhood = Moore(1), shortfall = :allow))
#     (TST grows with 8 neighbours whatever the CPM neighbourhood, D-141; P6.3e)
#
#   Potts.layout: a cell a `Splits` left in pieces is warned about only if it is still not
#   one piece in the final σ (a later layer may remove or fill pieces; D-141 review).
#
# Oracles: the parameter values are the spec's, with the unit conversions computed here; ΔH
# against a brute-force total energy written here (all pairs of the stated neighbourhood,
# area, the covariance length) plus a chemotaxis formula and TST's ConnectivityPreservedP
# written here from ca.cpp; the field against a plain explicit Euler written here (15
# substeps, ring clamped after each); `merks_state` against the former loop, copied here
# with StableRNG; the frame against a hand-written 20-offset stencil. Negative controls:
# the other phase order, no clamp, 14 substeps and a 9-point Laplacian each miss the field
# oracle; the 2006 and 2008 sets differ; retractions and cell–cell copies are non-vacuous
# in every mode test; breaking copies exist in the E₀ fixture; a 1-thick frame cuts the
# 20-site stencil; t_relax = 0 starts the field at once; the MersenneTwister loop differs
# from the port; a still-broken Splits cell is warned about.
#
# Today this fails with `UndefVarError: Merks2006` / `Merks2008` / `merks_layout` /
# `merks2006_layout` / `merks2008_sprout` / `merks2008_denovo` (each testset), the
# `merks_state` port test fails (it still draws from a MersenneTwister), and the repaired
# Splits cell is still warned about. `@boundary`/`@schedule` come from P6.3b (D-145).
using Potts: CorePotts
using StableRNGs: StableRNG
using Random: MersenneTwister

const P63D_J = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]
const P63D_SOLVER = ExplicitEuler(substeps = 15)
# NeighborOrder(4) in 2D written out: 1 ≤ dx² + dy² ≤ 5 (4 + 4 + 4 + 8 = 20 sites)
const P63D_N20 = [(dx, dy) for dx in -2:2 for dy in -2:2 if 1 <= dx^2 + dy^2 <= 5]
const P63D_N8 = [(dx, dy) for dx in -1:1 for dy in -1:1 if (dx, dy) != (0, 0)]
# TST's fixed 8-ring, cyclic, starting at (−1, 0) (ca.cpp:1170-1173)
const P63D_RING = ((-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1))

p63d_c(u) = Float64.(Array(u.site.c))
p63d_σ(op) = op[1].second
p63d_kinds(op) = op[2].second
p63d_quiet(f) = @test_logs min_level = Base.CoreLogging.Warn f()

"""A σ with a frame cell 1 of the given width on `dims`, and the given blocks as cells 2, 3, …"""
function p63d_framed(dims, width, blocks...)
    σ = zeros(Int32, dims)
    for I in CartesianIndices(σ)
        any(d -> I[d] <= width || I[d] > dims[d] - width, 1:2) && (σ[I] = 1)
    end
    for (k, b) in enumerate(blocks)
        for x in b
            σ[x...] = k + 1
        end
    end
    return σ
end
p63d_op(σ) = [ownership => σ, kind => [:border; fill(:endothelial, maximum(σ) - 1)]]

# ---------------------------------------------------------------------------------------
# Brute-force energy (spec 01 §2.2, §7.2): unordered pairs of the neighbourhood, area and
# (2006) the length l = 4√λ_max(covariance of the site coordinates) (01a Eq. 5; cell.h:397-421).
# kinds: 0 medium, 1 endothelial, 2 border (index into J is kind + 1).
# ---------------------------------------------------------------------------------------
function p63d_length(sites)
    n = length(sites)
    mx, my = sum(first, sites) / n, sum(last, sites) / n
    sxx = sum(s -> (s[1] - mx)^2, sites) / n
    syy = sum(s -> (s[2] - my)^2, sites) / n
    sxy = sum(s -> (s[1] - mx) * (s[2] - my), sites) / n
    λmax = (sxx + syy) / 2 + sqrt(((sxx - syy) / 2)^2 + sxy^2)
    return 4 * sqrt(λmax)
end
function p63d_energy(σ, kindof, p, offs; length_term = false)
    X, Y = size(σ)
    H = 0.0
    for x in 1:X, y in 1:Y, (dx, dy) in offs
        u, v = x + dx, y + dy
        (1 <= u <= X && 1 <= v <= Y) || continue
        a, b = σ[x, y], σ[u, v]
        a == b && continue
        H += p.J[kindof(a) + 1, kindof(b) + 1] / 2          # each unordered pair is visited twice
    end
    for c in 1:maximum(σ)
        kindof(c) == 1 || continue
        sites = [(I[1], I[2]) for I in findall(==(c), σ)]
        isempty(sites) && continue
        H += p.λ * (length(sites) - p.A)^2
        length_term && (H += p.λ_L * (p63d_length(sites) - p.L)^2)
    end
    return H
end

# TST ConnectivityPreservedP (ca.cpp:1166-1226) for the target's current owner `own`:
# n_borders = ring-adjacent pairs (cyclic) with exactly one member owned by `own`; broken iff
# n_borders > 2 and (more than 2 distinct non-zero owners on the ring counting `own`, or a
# medium site on the ring). Off-lattice ring sites are border (−1) as in TST.
function p63d_breaks(σ, x, own)
    X, Y = size(σ)
    r = map(P63D_RING) do (dx, dy)
        u, v = x[1] + dx, x[2] + dy
        (1 <= u <= X && 1 <= v <= Y) ? Int(σ[u, v]) : -1
    end
    nb = count(k -> (r[k] == own) != (r[mod1(k + 1, 8)] == own), 1:8)
    nb > 2 || return false
    return length(unique(filter(!=(0), [r...; own]))) > 2 || any(==(0), r)
end

"""Every interface proposal (target owner ≠ source owner, neither the frame cell 1) of the
state `u` under the offsets `offs`: a vector of (prop, ctx)."""
function p63d_proposals(prob, u, offs)
    lat = prob.lattice
    ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
    σ = Array(u.σ)
    X, Y = size(σ)
    out = []
    for x in 1:X, y in 1:Y, (dx, dy) in offs
        sx, sy = x + dx, y + dy
        (1 <= sx <= X && 1 <= sy <= Y) || continue
        old, new = σ[x, y], σ[sx, sy]
        (old == new || old == 1 || new == 1) && continue
        t, s = LinearIndices(σ)[x, y], LinearIndices(σ)[sx, sy]
        push!(out, (CorePotts.Proposal(t, s, (x, y), 1, Int32(old), Int32(new)), ctx))
    end
    return out
end
p63d_first(prob) = solve(remake(prob; tspan = (0, 1)), SequentialCPM(); saveat = [0]).u[1]

p63d_sat(c, s) = c / (1 + s * c)
function p63d_chemo(prop, c, p; mode = :extension_retraction)
    mode === :extension_only && prop.new == 0 && return 0.0
    χ = (prop.old == 0 || prop.new == 0) ? p.χcM : p.χcc
    return -χ * (p63d_sat(c[prop.target], p.s) - p63d_sat(c[prop.source], p.s))
end

# ---------------------------------------------------------------------------------------
# The field oracle (spec 01 §2.7, §7.4): explicit Euler, h = 1/n per substep, 5-point
# Laplacian with zero flux at the lattice edge (the frame clamps anyway), c set to 0 on the
# frame after every substep. `stencil = :nine` is a negative-control 9-point Laplacian;
# `clamp = false` drops the clamp. (TST splits each substep into secrete/decay, then diffuse;
# the model takes the unsplit step — a deviations-table row of the reproduction page.)
# ---------------------------------------------------------------------------------------
function p63d_field(c0, σ, kindof, p; n = 15, clamp = true, stencil = :five)
    c = copy(c0)
    X, Y = size(c)
    h = 1 / n
    isEC = [kindof(σ[x, y]) == 1 for x in 1:X, y in 1:Y]
    isM = [σ[x, y] == 0 for x in 1:X, y in 1:Y]
    ring = [kindof(σ[x, y]) == 2 for x in 1:X, y in 1:Y]
    offs = stencil === :five ? [(1, 0), (-1, 0), (0, 1), (0, -1)] : P63D_N8
    wts = stencil === :five ? ones(4) : [abs(a) + abs(b) == 1 ? 0.5 : 0.25 for (a, b) in P63D_N8]
    lap(c, x, y) = sum(k -> wts[k] * ((1 <= x + offs[k][1] <= X && 1 <= y + offs[k][2] <= Y) ?
                                      c[x + offs[k][1], y + offs[k][2]] - c[x, y] : 0.0), eachindex(offs))
    for _ in 1:n
        c = [c[x, y] + h * (p.Dc * lap(c, x, y) + p.α * isEC[x, y] - p.ε * c[x, y] * isM[x, y]) for x in 1:X, y in 1:Y]
        clamp && (c[ring] .= 0.0)
    end
    return c
end

# =======================================================================================
# M1, M2, M4 (values), P6.3e (neighbourhoods): the two parameter sets
# =======================================================================================
@testset "P6.3d M1: two parameter sets, not mixed (spec 01 §3.1, §3.2, §7.1, §7.8)" begin
    τ, Δx = 30.0, 2.0e-6                                   # s per MCS, m per site
    D = 1.0e-13 * τ / Δx^2                                 # 0.75 sites²/MCS (both papers)
    σ6 = p63d_framed((12, 12), 1, [(x, y) for x in 4:6 for y in 4:6])
    σ8 = p63d_framed((12, 12), 2, [(x, y) for x in 5:7 for y in 5:7])
    p6 = PottsProblem(Merks2006(; name = :m6, lattice = (12, 12)), p63d_op(σ6), (0, 1); field_solver = P63D_SOLVER)
    p8 = PottsProblem(Merks2008(; name = :m8, lattice = (12, 12)), p63d_op(σ8), (0, 1); field_solver = P63D_SOLVER)
    a, b = p6.p, p8.p
    @test (a.T, a.λ, a.A, a.λ_L, a.L, a.E₀) == (50.0, 50.0, 100.0, 5.0, 50.0, 5000.0)
    @test (a.χcM, a.χcc, a.s) == (1000.0, 1000.0, 0.0)
    @test a.Dc ≈ D && a.α ≈ 1.8e-4 * τ && a.ε ≈ 1.8e-4 * τ
    @test Matrix(a.J) == P63D_J
    @test (b.T, b.λ, b.A, b.t_relax) == (50.0, 25.0, 50.0, 100.0)
    @test (b.χcM, b.χcc, b.s) == (500.0, 0.0, 0.0)
    @test b.Dc ≈ D && b.α ≈ 1.0e-3 * τ && b.ε ≈ 1.0e-3 * τ
    @test Matrix(b.J) == P63D_J
    # 2008 has no length constraint and no E₀ (Dataset S1: lambda2 = 0, conn_diss = 0)
    @test !hasproperty(b, :λ_L) && !hasproperty(b, :L) && !hasproperty(b, :E₀)
    # negative control: the sets are distinct (spec 01 §8 A-17)
    @test (a.λ, a.A, a.α, a.χcM) != (b.λ, b.A, b.α, b.χcM)
    # M2: L = 50 px default ("about 100 µm"); the released files' 60 px is a keyword
    @test PottsProblem(Merks2006(; name = :m6, lattice = (12, 12), L = 60.0), p63d_op(σ6), (0, 1);
        field_solver = P63D_SOLVER).p.L == 60.0
    # default lattices: 500² with a 1-site frame (01a Fig. 4); TST 200² plus the off-lattice
    # ring its 20-site stencil reaches, as a 2-site frame on 202² (P6.3e)
    @test Potts.lattice(Merks2006(; name = :m6)).dims == (500, 500)
    @test Potts.lattice(Merks2008(; name = :m8)).dims == (202, 202)
    # contacts and copies: 8 (2006) and 20 (2008, P6.3e) neighbours
    nb(prob, spec) = Set(Tuple.(Int.(o) for o in CorePotts.relation(spec, prob.lattice).offsets))
    @test nb(p6, p6.contact) == nb(p6, p6.proposal) == Set(P63D_N8)
    @test nb(p8, p8.contact) == nb(p8, p8.proposal) == Set(P63D_N20)
    # the published field solver is named in each docstring (D-050 M5)
    @test occursin("ExplicitEuler(substeps = 15)", string(@doc Merks2006))
    @test occursin("ExplicitEuler(substeps = 15)", string(@doc Merks2008))
end

@testset "P6.3d M3, M7: invalid variants are errors; `contact_inhibited` is gone from 2008" begin
    @test_throws ArgumentError Merks2006(; name = :m, lattice = (12, 12), rule = :other)
    @test_throws ArgumentError Merks2008(; name = :m, lattice = (12, 12), mode = :other)
    @test_throws Exception Merks2008(; name = :m, lattice = (12, 12), contact_inhibited = true)
    @test Merks2006(; name = :m, lattice = (12, 12), rule = :hard) isa PottsSystem
    @test Merks2008(; name = :m, lattice = (12, 12), mode = :extension_only) isa PottsSystem
end

# =======================================================================================
# M4 + P6.3e: the frozen frame
# =======================================================================================
@testset "P6.3d M4 / P6.3e: the frame is frozen, J(c,B) = 100, 2 sites thick for 2008" begin
    # P6.3e geometry: with a width-2 frame on 202², every NeighborOrder(4) neighbour of every
    # mobile site (3:200) is on the lattice — TST's off-lattice border ring is the outer frame
    # layer; negative control: a width-1 frame leaves mobile sites (2) whose stencil leaves
    # the lattice (their border contacts would be lost)
    inside(x, w, n) = all(o -> all(d -> 1 <= x[d] + o[d] <= n, 1:2), P63D_N20)
    @test all(x -> inside(x, 2, 202), ((i, j) for i in 3:200 for j in 3:200))
    @test !all(x -> inside(x, 1, 202), ((i, j) for i in 2:201 for j in 2:201))

    # 2008 sprout: frame cell 1 owns exactly the sites within 2 of the edge
    op = p63d_quiet(() -> layout(merks2008_sprout(; seed = 3), (202, 202)))
    σ = p63d_σ(op)
    ring2 = [min(i, j, 203 - i, 203 - j) <= 2 for i in 1:202, j in 1:202]
    @test (σ .== 1) == ring2 && p63d_kinds(op)[1] === :border
    @test all(==(:endothelial), p63d_kinds(op)[2:end])
    # 2006: frame width 1
    op6 = layout(merks2006_layout(; lattice = (40, 40), n = 4, side = 5, seed = 2), (40, 40))
    σ6 = p63d_σ(op6)
    @test (σ6 .== 1) == [min(i, j, 41 - i, 41 - j) == 1 for i in 1:40, j in 1:40]
    @test p63d_kinds(op6) == [:border; fill(:endothelial, 4)]

    # the frame never moves; c = 0 on it after every MCS (cells next to the frame, T high)
    for (M, w) in ((Merks2006, 1), (Merks2008, 2))
        σ0 = p63d_framed((16, 16), w, [(x, y) for x in (w + 1):(w + 4) for y in (w + 1):(w + 4)],
            [(x, y) for x in 9:12 for y in 6:9])
        extra = M === Merks2008 ? [:t_relax => 0.0] : []
        prob = PottsProblem(M(; name = :m, lattice = (16, 16)), [p63d_op(σ0); :T => 500.0; extra...], (0, 6);
            field_solver = P63D_SOLVER, seed = 4)
        sol = solve(prob, SequentialCPM(); saveat = 1)
        frame = σ0 .== 1
        @test all(u -> Array(u.σ)[frame] == σ0[frame] && !any(==(1), Array(u.σ)[.!frame]), sol.u)
        @test all(u -> all(==(0.0), p63d_c(u)[frame]), sol.u[2:end])
        @test any(u -> Array(u.σ) != σ0, sol.u)                                     # control: cells moved
    end
end

# =======================================================================================
# M1/M4/M9 + P6.3e: ΔH = brute-force energy difference + chemotaxis (+ E₀) — exact Float
# =======================================================================================
@testset "P6.3d: ΔH against the brute-force energy, both models (spec 01 §2.2, §7.2)" begin
    # 2008: 20-neighbour adhesion, border contacts within the 2-site frame, area
    σ8 = p63d_framed((16, 16), 2, [(x, y) for x in 3:6 for y in 3:7], [(x, y) for x in 7:9 for y in 4:8],
        [(x, y) for x in 10:13 for y in 10:12])
    c8 = [0.001 * ((3x + 7y) % 11) for x in 1:16, y in 1:16]
    prob8 = PottsProblem(Merks2008(; name = :m8, lattice = (16, 16)), [p63d_op(σ8); :c => c8; :t_relax => 0.0], (0, 1);
        field_solver = P63D_SOLVER)
    u8 = p63d_first(prob8)
    kind8(c) = c == 0 ? 0 : c == 1 ? 2 : 1
    props8 = p63d_proposals(prob8, u8, P63D_N20)
    @test length(props8) > 300
    H8 = p63d_energy(Array(u8.σ), kind8, prob8.p, P63D_N20)
    worst8 = 0.0
    for (prop, ctx) in props8
        a = Array(u8.σ); a[prop.target] = prop.new
        dE = p63d_energy(a, kind8, prob8.p, P63D_N20) - H8
        worst8 = max(worst8, abs(energy_change(prob8, u8, prop) - dE),
            abs(prob8.f.delta_H(u8, prob8.p, prop, ctx) - (dE + p63d_chemo(prop, p63d_c(u8), prob8.p))))
    end
    @test worst8 < 1e-9
    # M9: Float ΔH — chemotactic terms below 1 are kept (TST truncates them, D-7)
    small = [p63d_chemo(prop, p63d_c(u8), prob8.p) for (prop, _) in props8]
    @test any(x -> 0 < abs(x) < 1 && !isinteger(x), small)

    # 2006: Moore adhesion, area and the covariance length, plus chemotaxis and E₀
    σ6 = p63d_framed((14, 14), 1, [(x, y) for x in 3:4 for y in 3:10], [(x, y) for x in 5:8 for y in 6:9],
        [(x, y) for x in 9:12 for y in 3:4])
    c6 = [0.002 * ((5x + 3y) % 13) for x in 1:14, y in 1:14]
    prob6 = PottsProblem(Merks2006(; name = :m6, lattice = (14, 14)), [p63d_op(σ6); :c => c6], (0, 1);
        field_solver = P63D_SOLVER)
    u6 = p63d_first(prob6)
    σu = Array(u6.σ)
    props6 = p63d_proposals(prob6, u6, P63D_N8)
    @test length(props6) > 150
    H6 = p63d_energy(σu, kind8, prob6.p, P63D_N8; length_term = true)
    worst6 = 0.0
    for (prop, ctx) in props6
        a = copy(σu); a[prop.target] = prop.new
        dE = p63d_energy(a, kind8, prob6.p, P63D_N8; length_term = true) - H6
        br = prop.old != 0 && p63d_breaks(σu, prop.x, prop.old)
        worst6 = max(worst6, abs(energy_change(prob6, u6, prop) - dE) / max(1.0, abs(dE)),
            abs(prob6.f.delta_H(u6, prob6.p, prop, ctx) - (dE + p63d_chemo(prop, p63d_c(u6), prob6.p) + prob6.p.E₀ * br)) /
            max(1.0, abs(dE)))
    end
    @test worst6 < 1e-9
end

# =======================================================================================
# M3: soft E₀ on TST's connectivity-breaking copies (2006); the hard variant
# =======================================================================================
@testset "P6.3d M3: E₀ = 5000 on ring-breaking copies of the losing cell; `rule = :hard` vetoes them" begin
    # cell 2: a column i ∈ 3:11 at j = 7; cell 3: the block 5:9 × 5:9 around it; cell 4: a
    # block touching cell 3. Targets of every class: preserved (one arc), preserved by TST's
    # exception (two arcs, two cells, no medium: (7, 7)), broken with medium on the ring
    # ((4, 7)), broken with three cells.
    blk3 = [(i, j) for i in 5:9 for j in 5:9 if j != 7]
    σ = p63d_framed((14, 14), 1, [(i, 7) for i in 3:11], blk3, [(i, j) for i in 5:9 for j in 10:11])
    soft = PottsProblem(Merks2006(; name = :m6, lattice = (14, 14)), p63d_op(σ), (0, 1); field_solver = P63D_SOLVER)
    hard = PottsProblem(Merks2006(; name = :m6, lattice = (14, 14), rule = :hard), p63d_op(σ), (0, 1);
        field_solver = P63D_SOLVER)
    u = p63d_first(soft)
    props = p63d_proposals(soft, u, P63D_N8)
    nbreak, npass, nexception = 0, 0, 0
    for (prop, ctx) in props
        br = prop.old != 0 && p63d_breaks(σ, prop.x, prop.old)       # c = 0: no chemotaxis yet
        drive = soft.f.delta_H(u, soft.p, prop, ctx) - energy_change(soft, u, prop)
        @test drive ≈ 5000.0 * br atol = 1e-9
        @test hard.f.constraint(u, hard.p, prop, ctx) == !br
        @test hard.f.delta_H(u, hard.p, prop, ctx) - energy_change(hard, u, prop) ≈ 0.0 atol = 1e-9
        nbreak += br; npass += !br
        prop.x == (7, 7) && prop.old == 2 && (nexception += !br)
    end
    @test nbreak >= 10 && npass >= 10                     # control: both classes are sampled
    @test nexception > 0                                  # TST's two-cell exception is exercised
    @test p63d_breaks(σ, (4, 7), 2) && !p63d_breaks(σ, (7, 7), 2)
    # D-13 variant: E₀ is a parameter
    e2 = remake(soft; p = [:E₀ => 2000.0])
    prop, ctx = first(filter(q -> q[1].x == (4, 7) && q[1].new == 0, props))
    @test e2.f.delta_H(u, e2.p, prop, ctx) - energy_change(e2, u, prop) ≈ 2000.0
end

# =======================================================================================
# M7, M8: the chemotaxis drive (2008): χ(c,M) and χ(c,c), both modes, saturation
# =======================================================================================
@testset "P6.3d M7/M8: chemotaxis χ(c,M)/χ(c,c), extension/retraction vs extension only, c/(1 + s c)" begin
    σ = p63d_framed((16, 16), 2, [(x, y) for x in 4:7 for y in 4:8], [(x, y) for x in 8:10 for y in 5:9],
        [(x, y) for x in 11:13 for y in 11:13])
    c0 = [0.05 + 0.01 * ((x * 7 + y * 3) % 9) for x in 1:16, y in 1:16]
    for mode in (:extension_retraction, :extension_only), (χcc, s) in ((0.0, 0.0), (250.0, 0.0), (250.0, 0.3))
        prob = PottsProblem(Merks2008(; name = :m8, lattice = (16, 16), mode),
            [p63d_op(σ); :c => c0; :χcc => χcc; :s => s; :t_relax => 0.0], (0, 1); field_solver = P63D_SOLVER)
        u = p63d_first(prob)
        props = p63d_proposals(prob, u, P63D_N20)
        drives = [prob.f.delta_H(u, prob.p, prop, ctx) - energy_change(prob, u, prop) for (prop, ctx) in props]
        want = [p63d_chemo(prop, p63d_c(u), prob.p; mode) for (prop, _) in props]
        @test maximum(abs, drives .- want) < 1e-9
        # controls: every copy class is sampled and non-vacuous
        retract = [prop.new == 0 for (prop, _) in props]
        cellcell = [prop.old != 0 && prop.new != 0 for (prop, _) in props]
        extend = [prop.old == 0 for (prop, _) in props]
        @test count(retract) > 20 && count(cellcell) > 20 && count(extend) > 20
        @test any(!=(0.0), drives[extend])
        if mode === :extension_only
            @test all(==(0.0), drives[retract])                                  # 01b Eq. 4
        else
            @test any(!=(0.0), drives[retract])                                  # retractions count
        end
        χcc == 0 ? @test(all(==(0.0), drives[cellcell])) : @test(any(!=(0.0), drives[cellcell]))
    end
end

# =======================================================================================
# M5 (+ D-145 ruling 10): 15 substeps, absorbing frame, fields before the sweep
# =======================================================================================
@testset "P6.3d M5: the field is 15 explicit substeps on σ(k), clamped on the frame ($nm)" for nm in (:Merks2006, :Merks2008)
    M = getglobal(PottsModels, nm)                        # resolved inside the testset (absent on the base)
    w = M === Merks2006 ? 1 : 2
    σ0 = p63d_framed((20, 20), w, [(x, y) for x in 4:7 for y in 4:9], [(x, y) for x in 11:14 for y in 8:12],
        [(x, y) for x in 6:9 for y in 13:16])
    extra = M === Merks2008 ? [:t_relax => 0.0] : []
    prob = PottsProblem(M(; name = :m, lattice = (20, 20)), [p63d_op(σ0); :T => 200.0; extra...], (0, 5);
        field_solver = P63D_SOLVER, seed = 7)
    kd(c) = c == 0 ? 0 : c == 1 ? 2 : 1
    p = prob.p
    sol = solve(prob, SequentialCPM(); saveat = 1)
    frame = σ0 .== 1
    right = wrong = noclamp = fewer = nine = 0.0
    for k in 1:5
        u, u′ = sol.u[k], sol.u[k + 1]
        c, c′ = p63d_c(u), p63d_c(u′)
        @test all(==(0.0), c′[frame])
        right = max(right, maximum(abs, c′ .- p63d_field(c, Array(u.σ), kd, p)))
        wrong = max(wrong, maximum(abs, c′ .- p63d_field(c, Array(u′.σ), kd, p)))      # sweep first
        noclamp = max(noclamp, maximum(abs, c′ .- p63d_field(c, Array(u.σ), kd, p; clamp = false)))
        fewer = max(fewer, maximum(abs, c′ .- p63d_field(c, Array(u.σ), kd, p; n = 14)))
        nine = max(nine, maximum(abs, c′ .- p63d_field(c, Array(u.σ), kd, p; stencil = :nine)))
    end
    @test right < 1e-12
    @test wrong > 1e-4 && noclamp > 1e-6 && fewer > 1e-9 && nine > 1e-6          # negative controls
    @test any(k -> Array(sol.u[k].σ) != Array(sol.u[k + 1].σ), 1:5)               # control: cells moved
end

# =======================================================================================
# M6: the 2008 relaxation (100 MCS without the field); none in 2006
# =======================================================================================
@testset "P6.3d M6: 2008 relaxes for t_relax MCS without the field; 2006 does not" begin
    σ0 = p63d_framed((16, 16), 2, [(x, y) for x in 5:8 for y in 5:9])
    prob = PottsProblem(Merks2008(; name = :m8, lattice = (16, 16)), p63d_op(σ0), (0, 101);
        field_solver = P63D_SOLVER, seed = 2)
    @test prob.p.t_relax == 100
    sol = solve(prob, SequentialCPM(); saveat = 1)
    @test sol.t[101] == 100 && sol.t[102] == 101
    kd(c) = c == 0 ? 0 : c == 1 ? 2 : 1
    @test all(u -> all(==(0.0), p63d_c(u)), sol.u[1:101])                          # MCS 0–99: no field
    c100, σ100, c101 = p63d_c(sol.u[101]), Array(sol.u[101].σ), p63d_c(sol.u[102])
    @test maximum(abs, c101 .- p63d_field(c100, σ100, kd, prob.p)) < 1e-12         # MCS 100: the field
    @test minimum(c101[σ100 .>= 2]) > 0
    # negative control: t_relax = 0 starts the field in MCS 0
    s0 = solve(remake(prob; p = [:t_relax => 0.0], tspan = (0, 1)), SequentialCPM(); saveat = 1)
    @test maximum(p63d_c(s0.u[end])) > 0
    # 2006: the field runs from MCS 0 (the 2006-labelled files have relaxation = 0)
    σ6 = p63d_framed((16, 16), 1, [(x, y) for x in 5:8 for y in 5:9])
    s6 = solve(PottsProblem(Merks2006(; name = :m6, lattice = (16, 16)), p63d_op(σ6), (0, 1);
        field_solver = P63D_SOLVER, seed = 2), SequentialCPM(); saveat = 1)
    @test minimum(p63d_c(s6.u[end])[σ6 .>= 2]) > 0
end

# =======================================================================================
# D-087: `merks_state` on `Scattered`, draw-for-draw the former loop under a StableRNG
# =======================================================================================
"""The former `merks_state` loop (PottsModels 04ed45b5, src/merks.jl:87-103), with the RNG
passed in."""
function p63d_old_merks(rng; lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice, n = 282,
        side = 10)
    σ = zeros(Int32, lattice)
    off = (lattice .- region) .÷ 2
    placed = 0
    for _ in 1:(1000n)
        placed == n && break
        lo = off .+ (rand(rng, 2:(region[1] - side)), rand(rng, 2:(region[2] - side)))
        box = (lo[1] - 1):(lo[1] + side), (lo[2] - 1):(lo[2] + side)
        all(iszero, view(σ, box...)) || continue
        placed += 1
        σ[lo[1]:(lo[1] + side - 1), lo[2]:(lo[2] + side - 1)] .= placed
    end
    placed == n || error("oracle: only $placed of $n placed")
    return σ
end

@testset "P6.3d D-087: merks_state is Scattered, draw-for-draw the former loop under StableRNG" begin
    geoms = [(;), (; lattice = (100, 100), n = 25), (; lattice = (140, 140), n = 49),
        (; lattice = (32, 32), n = 6, side = 7), (; lattice = (200, 200), n = 100), (; lattice = (100, 100), n = 50, side = 7)]
    for g in geoms, seed in 1:6
        op = merks_state(; g..., seed)
        @test p63d_σ(op) == p63d_old_merks(StableRNG(seed); g...)
        @test p63d_kinds(op) == fill(:endothelial, get(g, :n, 282))
        lat = get(g, :lattice, (500, 500))
        l = merks_layout(; g..., seed)
        @test l isa Scattered
        @test p63d_σ(layout(l, lat)) == p63d_σ(op)
        # 2006 layout: the same cells inside a 1-site frame (ids shifted by the frame cell)
        f = p63d_σ(layout(merks2006_layout(; g..., seed), lat))
        @test f == ifelse.(p63d_σ(op) .> 0, p63d_σ(op) .+ Int32(1), Int32.([min(i, j, lat[1] + 1 - i, lat[2] + 1 - j) == 1
                                                                            for i in 1:lat[1], j in 1:lat[2]]))
    end
    # the frozen merks_2006_defaults geometry still holds: 282 squares of 10² in the central 333²
    σ = p63d_σ(merks_state())
    @test all(c -> count(==(c), σ) == 100, 1:282)
    @test all(I -> 84 <= I[1] <= 417 && 84 <= I[2] <= 417, findall(!=(0), σ))
    # negative control: the stream moved from MersenneTwister to StableRNG (D-087)
    @test p63d_σ(merks_state(; lattice = (100, 100), n = 25, seed = 1)) !=
          p63d_old_merks(MersenneTwister(1); lattice = (100, 100), n = 25)
end

# =======================================================================================
# M10, M11 + D-141: the 2008 starts (TST GrowInCells / DivideCells)
# =======================================================================================
@testset "P6.3d M11: the 2008 sprout is one Eden blob split 7 times (128 cells)" begin
    for seed in 1:4
        l = merks2008_sprout(; seed)
        op = p63d_quiet(() -> layout(l, (202, 202)))
        ref = overlay(Frame(:border; width = 2),
            Splits(Eden(Center(); rounds = 50, kinds = [:endothelial], seed, neighborhood = Moore(1)), 7; splits = :allow))
        @test p63d_σ(op) == p63d_σ(layout(ref, (202, 202))) && p63d_kinds(op) == [:border; fill(:endothelial, 128)]
        σ = p63d_σ(op)
        @test all(I -> 3 <= I[1] <= 200 && 3 <= I[2] <= 200, findall(>(1), σ))
        @test 1816 <= count(>(1), σ) <= 2439                                  # D-141 band (spec 01 §7.6)
        # painted on the Merks2008 system (NeighborOrder(4)) the blob still grows with 8 neighbours
        @test p63d_σ(p63d_quiet(() -> layout(l, Merks2008(; name = :m8)))) == σ
    end
    # the keywords reach the layers: Fig. 12's 256 cells are 8 divisions
    @test maximum(p63d_σ(p63d_quiet(() -> layout(merks2008_sprout(; divisions = 8, seed = 1), (202, 202))))) == 257
end

@testset "P6.3d M10: the 2008 de novo starts (files: 360 seeds on 202²; paper: 1000 in 333² of 502²)" begin
    for seed in 1:3
        op, rep = layout(merks2008_denovo(; seed), (202, 202); report = true)
        ref = overlay(Frame(:border; width = 2),
            Eden(RandomPoints(360; region = (3:200, 3:200), replace = true, seed); rounds = 10, kinds = [:endothelial],
                seed, neighborhood = Moore(1), shortfall = :allow))
        @test p63d_σ(op) == p63d_σ(layout(ref, (202, 202)))
        n = length(p63d_kinds(op)) - 1
        @test 357 <= n <= 360                                                  # D-141 band
        @test 40 <= count(>(1), p63d_σ(op)) / n <= 55                          # ≈ 47 sites per cell (spec 01 §7.6)
        # the paper geometry (D-050 M10): 1000 seeds over the central 333² of 502²
        σp = p63d_σ(layout(merks2008_denovo(; lattice = (502, 502), n = 1000, region = (85:417, 85:417), seed), (502, 502)))
        np = maximum(σp) - 1
        @test 985 <= np <= 1000
        @test all(I -> 75 <= I[1] <= 427 && 75 <= I[2] <= 427, findall(>(1), σp))     # 10 rounds of growth
    end
end

# =======================================================================================
# D-141 follow-up: re-check a Splits cell against the final σ before warning
# =======================================================================================
struct P63dSites <: AbstractLayout          # one cell per site list, kind :a
    cells::Vector{Vector{NTuple{2, Int}}}
end
function Potts.paint!(op::Potts.LayoutState, l::P63dSites, lat)
    for s in l.cells
        id = Potts.new_cell!(op, :a)
        foreach(x -> Potts.assign!(op, x, id), s)
    end
    return nothing
end
struct P63dJoin <: AbstractLayout           # assigns the sites to an existing cell id
    id::Int
    sites::Vector{NTuple{2, Int}}
end
function Potts.paint!(op::Potts.LayoutState, l::P63dJoin, lat)
    foreach(x -> Potts.assign!(op, x, l.id), l.sites)
    return nothing
end

@testset "P6.3d: a Splits cell repaired by a later layer is not warned about (D-141 follow-up)" begin
    # the D-141 U: columns x = 1 and x = 3 at y ∈ 1:6 joined by (2, 1); one division puts
    # y ∈ 4:6 of both columns in the daughter (cell 2): two pieces under Moore(1)
    U = P63dSites([vcat([(1, y) for y in 1:6], [(3, y) for y in 1:6], [(2, 1)])])
    daughter = Set(vcat([(1, y) for y in 4:6], [(3, y) for y in 4:6]))
    sites(σ, c) = Set((I[1], I[2]) for I in findall(==(c), σ))
    # control (unchanged behaviour): alone, the daughter is warned about
    op = @test_logs (:warn, r"cell 2 \(kind a\)") layout(Splits(U, 1), (5, 8))
    @test sites(p63d_σ(op), 2) == daughter
    # (a) a later Tiling covers one piece: the daughter is one piece in the final σ — no warning
    cover = Tiling((1, 3); region = (3:3, 4:6), kinds = [:t])
    op = p63d_quiet(() -> layout(overlay(Splits(U, 1), cover), (5, 8)))
    @test sites(p63d_σ(op), 2) == Set((1, y) for y in 4:6)
    # (b) a later layer fills the gap with the daughter's own id: one piece — no warning
    op = p63d_quiet(() -> layout(overlay(Splits(U, 1), P63dJoin(2, [(2, y) for y in 4:6])), (5, 8)))
    @test sites(p63d_σ(op), 2) == union(daughter, Set((2, y) for y in 4:6))
    # negative controls: a later layer that leaves the daughter in pieces still warns
    partial = Tiling((1, 1); region = (3:3, 6:6), kinds = [:t])
    @test_logs (:warn, r"cell 2 \(kind a\)") layout(overlay(Splits(U, 1), partial), (5, 8))
    @test_logs (:warn, r"cell 2 \(kind a\)") layout(overlay(Splits(U, 1), P63dJoin(2, [(4, 6)])), (5, 8))
end
