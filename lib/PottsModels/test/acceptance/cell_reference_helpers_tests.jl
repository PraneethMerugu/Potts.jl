# E2 named pairs and the
# E7 geometry helpers `centroid(c, k)`, `minimum_image`, `separation` and
# `integral(x; over = cluster)` (D-243 amendment; planned as `cluster_integral`).
# Decisions and sources: D-231 "Scope" (`centroid(c, k)`, `separation`, `minimum_image` get
# their own tests, here), D-075 / api-synthesis §2.6–2.7 and §6.4 (the reference
# vocabulary and the geometry helpers), D-066 item 5 (a dead referent reads as the medium),
# D-032 / D-075 (`centroid` has no ΔH, so it is not read in energies until R7), D-188 (axes
# are literal lattice axes), D-048 (hand oracles, independent oracles, negative controls),
# the ergonomics review `research/ergonomics-review-fortuna.md` (E2, E6, E7) and spec 14
# (Π_CN−N, 14b Eq 10: r_CN − r_N = V_C (r_C − r_N) / (V_C + V_N), xy-projected; the
# lamellipodium–nucleus distance, 14a Fig 12; 14c's base statistics over a cluster).
#
# Scope (D-231 follow-ups): E2 named pairs; E6 docs for cell references; E7 helpers
# `centroid(c, k)`, `minimum_image`, `cluster_integral` (api-synthesis §6.4), with their own tests.
#
# =========================================================================================
# THE PUBLIC API THESE TESTS EXPECT (names, signatures, semantics)
# =========================================================================================
#
# A. Named pairs (E2). Inside `@parameters`, a kind-indexed parameter may be written
#        J[kind, kind] = Pairs(default = d, (k₁, k₂) => v, …)
#        μ[kind, kind] = Pairs((k₁, k₂) => v, …; default = d, symmetric = false)
#    - `Pairs` is bound inside model bodies (a new `Potts.DSL` name). `k₁`, `k₂` are kind
#      names of the model's `@kinds`; `v` is a number or an expression of scalar parameters
#      (as the matrix form allows, `api_defects_tests.jl`).
#    - Symmetric fill (the default, `symmetric = true`): entry (k₁, k₂) and (k₂, k₁) both get
#      v; every unlisted entry gets `default`. With `symmetric = false` only (k₁, k₂) is set.
#    - It lowers to the same matrix: the parameter object equals the hand-written matrix
#      form's (`prob.p == prob_matrix.p`, same type), so there is zero runtime cost, and a
#      parameter entry follows `remake` on both sides of the diagonal.
#    - Errors (at `@potts_model` expansion, at the constructor or at `PottsProblem`, any of
#      them, as an `ArgumentError`):
#      * an unknown kind name (a misspelling) names it;
#      * a name that is bound but is not a kind (a parameter) names it;
#      * a pair given twice is an error; with symmetric fill (k₂, k₁) after (k₁, k₂) counts
#        as given twice (asymmetric input is only allowed with `symmetric = false`).
#    - The matrix form stays (the matrix twins below are the controls).
#    - Not pinned: kind classes inside `Pairs` and api-synthesis §2.2's `KindTable(a => b
#      => v, …)` spelling; `Pairs` without `default`; a `Pairs` value for a non-kind-table
#      parameter.
# B. `centroid(c, k)` (E7; api-synthesis §2.7, "cell-first, mirrors `displacement(c, k)`").
#    Coordinate `k` (a literal axis) of the centroid of the cell that reference `c` names,
#    in the same units and convention as `centroid(k)` for the current cell: lattice units,
#    embedded on a hexagonal lattice, periodic axes wrapped into [1, L + 1) (the circular
#    mean, so a cell across the seam has its centroid there). `c` is any reference source
#    (`sibling(k)`, `sibling(c, k)`, a `CellRef` variable, `root(cluster)`, a population-
#    fold element). A dead referent or ref 0 reads 0.0 (the medium, as `centroid(k)` of
#    an empty slot reads today, `_centroid_axis`). Cell scope: updates (`@after_mcs`),
#    `@observed`, population folds (`sum(centroid(c, 1) for c in cells(nucleus))`).
#    Refused in `@energy` (`PottsCompileError` naming `centroid`: it has no ΔH).
#    `centroid(c, k)` with k not an axis of the lattice is a `PottsCompileError` naming
#    `centroid`.
# C. `minimum_image(d, axis)` (E7; the scalar wrap). On a periodic axis of length L, the
#    representative of `d` modulo L nearest 0; on a closed axis `d` itself. `axis` is a
#    literal axis (1 … N); anything else (3 on a 2D lattice, a parameter) is an
#    ArgumentError naming `minimum_image`. A pure function of `d` and the lattice:
#    usable in cell scope, in a `@drive` (copy scope, e.g. of `position[target][1]`) and
#    in an `@energy` cell term of static values (a cell variable), on the CPU and the
#    device. Pinned exactly for |d| < L with |d| ≠ L/2; at |d| = ±L/2 the sign is free but
#    the magnitude is exactly L/2 (O2). Inputs are assumed within one period (O3).
#    Lattice units only (O7).
# D. `separation(a, b)`: the minimum-image vector centroid(a) − centroid(b) (13 F3), a
#    vector of N components (`separation(a, b)[k]`, `norm(separation(a, b))`). On a
#    square lattice component k is `minimum_image(centroid(a, k) − centroid(b, k), k)`. On a
#    periodic hexagonal lattice it is the embedded nearest image on the rhombic torus
#    (the one `CorePotts.centroid_distance` measures), not the per-axis wrap of embedded
#    coordinates. Pinned for two alive referents only.
# E. `integral(x; over = cluster)` (D-243 amendment; was `cluster_integral(x)`): the sum of
#    the site expression `x` over every site of every
#    alive member of the current cell's cluster (each site weight 1; divide by the
#    cluster's volume for the mean). The same value for every member. For a cell that is
#    its own cluster it equals plain `integral(x)`, which stays the cell sum. Cell scope like `integral` (updates,
#    `@observed`); refused in `@energy` with a `PottsCompileError` (as `integral` is: no ΔH).
#    The integrand is in site scope (spec-owner ruling, 2026-10-14): `kind` and `volume`
#    inside `x` bind to the site's owner, the member cell the site belongs to, so
#    `integral(volume; over = cluster)` = Σ_members V_m², not (Σ V_m)·V_current. An unknown
#    `over =` value, and `over = cluster` outside a cell or cluster context, are refused.
# F. Cost. The checkerboard claims nothing (D-271), so the test that these helpers add no
#    reads or claims (old section 9) is removed.
#
# E6 (docs for cell references) is prose and is not in this file: no test asserts
# documentation text. The `kind[old] == medium` form that E6 asks the docs to use already
# compiles (the OpenVT model uses `neighbor_kind == medium`) and is not re-pinned here.
#
# Open choices (the test author's conservative readings, flagged for the spec owner):
#   O1 (ruled; superseded 2026-10-14 by the maintainer) the spelling is `integral(x; over =
#      cluster)`, a scope argument on the existing `integral`, not a new name. The fold
#      `sum(x for s in sites(cluster))` of api-synthesis §2.1/§6.3 comes later as an
#      equivalent spelling; it is not pinned here.
#   O2 (ruled) Ties: at d = ±L/2 the sign of `minimum_image` is free, the magnitude is
#      exactly L/2. (CorePotts's integer `min_image` resolves ties to +; its float
#      `_min_image` and copy-scope `direction` keep `d`.)
#   O3 (ruled) |d| ≥ L is open: inputs are assumed within one period (centroid
#      differences lie in (−L, L)).
#   O4 (ruled) A dead referent's centroid reads 0.0 (today's `centroid(k)` convention for
#      an empty slot), not NaN. `separation` with a dead referent is open: guard it with
#      `alive(ref)`.
#   O5 (ruled) `centroid(c, k)` is refused in energies (D-032) and is not pinned in drives
#      (api-synthesis lists it for cell scope only). The energy refusal is amended at R7.
#   O6 `minimum_image` is pinned in a `@drive` and an `@energy` cell term (pure arithmetic,
#      no state read); `minimum_image` on a hexagonal lattice is not pinned (a scalar wrap
#      of an embedded coordinate is not well defined there; `separation` is).
#   O7 (ruled) Lattice units only: spacing ≠ 1 is not pinned (`centroid` is in lattice
#      units while `position` is scaled by the spacing).
#   O8 `centroid(c)` (one argument, a vector) is not pinned: it would clash with
#      `centroid(k)`, the current cell's axis k.
#   O9 `Pairs` value types: a mixed Int/Float/parameter list is pinned; class keys are not.
#   R1 (ruling) The binding inside `integral(x; over = cluster)`: site scope, the owner's `kind` and
#      `volume` (section 3, "integral(x; over = cluster) sums over the cluster's sites").
#
# Sections: 1 the fixtures build; 2 named pairs (E2); 3 centroid(c, k), minimum_image,
# separation and integral(x; over = cluster) by hand (square, periodic × closed); 4 dead referents;
# 5 after-MCS writes against `@observed` and an independent oracle after a short run; 6
# minimum_image in a drive and an energy, bitwise against an explicit-wrap twin; 7 the
# hexagonal torus; 8 refusals and axis errors (negative controls); 9 device.
#
# Today (base commit 588ad407) every assertion that reads a new name fails (marked DEFECT
# CHECK): `Pairs`, `minimum_image` and `separation` are undefined, `integral` has no `over` keyword, and
# `centroid` has no two-argument method, so the fixtures that use them do not build. The
# explicit-wrap twins, the matrix twins, the hand oracles' own checks and the existing
# refusals pass (marked CONTROL). On the base commit (Apple M-series): 22 pass, 16 fail,
# 11 errors (fixtures that do not build), 1 broken (the device testset's skip); ~15 s after
# precompilation. The hand values were checked on the base commit with today's
# primitives (`centroid(k)`, `integral`, `CorePotts.centroid`, `centroid_distance`) on the
# same states. Runtime: a few model compilations and ~10 MCS on small lattices; no FULL
# tier.

@testsetup module CellReferenceHelpersSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# 0. Helpers
const DEFINE_ERRORS = Dict{Symbol, Any}()
function define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
    catch e
        DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
model(name::Symbol) = isdefined(@__MODULE__, name) ? getfield(@__MODULE__, name) :
    error("cell reference helpers fixture $name did not build: $(get(DEFINE_ERRORS, name, "unknown"))")
system(name::Symbol; sysname = :m) = Base.invokelatest(model(name); name = sysname)
vol(u) = Array(u.cell.volume)
col(u, n) = Array(getfield(u.cell, n))
ctx(prob) = Potts._host_ctx(prob)
# The error a model raises anywhere from its definition to `PottsProblem` (nothing if none).
# `op(sys)` gives the operating point.
function build_error(name::Symbol, ex::Expr, op)
    try
        Core.eval(@__MODULE__, ex)
        sys = Base.invokelatest(getfield(@__MODULE__, name); name = :bad)
        Base.invokelatest(PottsProblem, sys, op(sys), (0, 1))
        return nothing
    catch e
        return e isa LoadError ? e.error : e
    end
end
msg(e) = e === nothing ? "" : sprint(showerror, e)
# every Moore(1) copy (target t takes source s's owner)
function helper_props(prob, u)
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    σ = Array(u.ownership)
    out = CorePotts.Proposal{2}[]
    for t in eachindex(σ)
        x = CorePotts.coordinates(lat, t)
        for kk in 1:length(moore)
            ins, y = CorePotts.shift(lat, x, moore.offsets[kk])
            ins || continue
            s = CorePotts.linear_index(lat, y)
            σ[t] == σ[s] && continue
            push!(out, CorePotts.Proposal(t, s, x, 1, σ[t], σ[s]))
        end
    end
    return out
end
helper_prop(prob, u, old, new) = first(filter(p -> p.old == old && p.new == new, helper_props(prob, u)))
function apply(prob, u, prop)
    a = deepcopy(u)
    a.ownership[prop.target] = prop.new
    prob.f.commit!(a, prob.p, prop, ctx(prob))
    return a
end
# Independent oracles (from σ alone; D-048). Periodic axes: circular mean, each site
# unwrapped to the image nearest it, the mean wrapped into [1, L + 1).
function oracle_centroid(σ, c, dims, periodic)
    idx = [Tuple(I) for I in CartesianIndices(σ) if σ[I] == c]
    isempty(idx) && return ntuple(_ -> 0.0, length(dims))
    return ntuple(length(dims)) do d
        xs = Float64[i[d] for i in idx]
        periodic[d] || return sum(xs) / length(xs)
        L = dims[d]
        θ = atan(sum(sin.(2π .* xs ./ L)), sum(cos.(2π .* xs ./ L)))
        ref = mod(θ * L / (2π), L)                      # in [0, L)
        un = [x + L * round((ref - x) / L) for x in xs]
        m = sum(un) / length(un)
        return mod(m - 1, L) + 1
    end
end
oracle_wrap(d, L, periodic) = periodic ? d - L * round(d / L) : d
function oracle_sibling(u, c, k)
    v = vol(u); kd = col(u, :kind); cl = col(u, :cluster)
    ms = [m for m in eachindex(v) if v[m] > 0 && cl[m] == cl[c] && kd[m] == k]
    @assert length(ms) <= 1
    return isempty(ms) ? 0 : ms[1]
end
function oracle_cluster_sum(u, F, c)
    σ = Array(u.ownership); cl = col(u, :cluster)
    return sum((F[I] for I in CartesianIndices(σ) if σ[I] != 0 && cl[σ[I]] == cl[c]); init = 0.0)
end
# ---------------------------------------------------------------------------------------
# Fixtures

# F1. Named pairs (section 2). Kinds: medium 1, substrate 2, cytoplasm 3, nucleus 4 (rows).
const PAIRS_BODY = quote
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 9.0)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = T)
end
pairs_expr(name::Symbol, Jline::Expr, μline::Expr) = :(
    @potts_model $name begin
        @kinds medium substrate cytoplasm nucleus
        @parameters begin
            Jcn = 7.0
            T = 4.0
            $Jline
            $μline
        end
        $(PAIRS_BODY.args...)
    end
)
const J_PAIRS = :(
    J[kind, kind] = Pairs(
        default = 0.0, (medium, substrate) => 20, (medium, cytoplasm) => 16,
        (substrate, cytoplasm) => 3.5, (cytoplasm, nucleus) => Jcn, (nucleus, nucleus) => 2.5
    )
)
const μ_PAIRS = :(
    μ[kind, kind] = Pairs(
        (cytoplasm, nucleus) => 4.0, (nucleus, cytoplasm) => 9.0; default = 1.0,
        symmetric = false
    )
)
const J_MATRIX = :(J[kind, kind] = [0 20 16 0; 20 0 3.5 0; 16 3.5 0 Jcn; 0 0 Jcn 2.5])
const μ_MATRIX = :(μ[kind, kind] = [1.0 1.0 1.0 1.0; 1.0 1.0 1.0 1.0; 1.0 1.0 1.0 4.0; 1.0 1.0 9.0 1.0])
define(:HelperPairs, pairs_expr(:HelperPairs, J_PAIRS, μ_PAIRS))
define(:PairsMatrix, pairs_expr(:PairsMatrix, J_MATRIX, μ_MATRIX))
# the twin

# hand matrices (Jcn = 7)
J_hand(Jcn = 7.0) = [0.0 20.0 16.0 0.0; 20.0 0.0 3.5 0.0; 16.0 3.5 0.0 Jcn; 0.0 0.0 Jcn 2.5]
const μ_HAND = [1.0 1.0 1.0 1.0; 1.0 1.0 1.0 1.0; 1.0 1.0 1.0 4.0; 1.0 1.0 9.0 1.0]
function pairs_sigma()
    σ = zeros(Int32, 12, 12)
    σ[1:12, 1] .= 1                      # substrate row
    σ[4:6, 2:4] .= 2                     # cytoplasm on it
    σ[7:8, 2:3] .= 3                     # nucleus beside the cytoplasm, on the substrate
    return σ
end
const PAIRS_OP = [ownership => pairs_sigma(), kind => [:substrate, :cytoplasm, :nucleus]]
pairs_problem(name; seed = 1) = PottsProblem(system(name; sysname = :pr), PAIRS_OP, (0, 3); seed)
# F2. Geometry fixture (sections 3–5, 10). 20 × 12, axis 1 periodic, axis 2 closed.
# Kinds: medium 0, cytoplasm 1, nucleus 2, lamellipodium 3. References appear only in
# updates and observables.
define(
    :Refs, quote
        @potts_model Refs begin
            @kinds medium cytoplasm nucleus lamellipodium
            @parameters begin
                λ = 2.0
                T = 2.0
            end
            @variables begin
                Vt(cell) = 0.0
                dd(cell) = 0.0
                F(site) = 0.0
                G(site) = 0.0
                wcx(cell) = 0.0
                wmi(cell) = 0.0
                wsn(cell) = 0.0
                wci(cell) = 0.0
            end
            @lattice Lattice((20, 12); boundary = (Periodic(), Closed()), neighborhood = Moore(1))
            @energy begin
                cells => λ * (volume - Vt)^2
                contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 0.5, 1.0)
            end
            @after_mcs begin
                wcx ~ centroid(sibling(nucleus), 1)
                wmi ~ minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1)
                wsn ~ norm(separation(sibling(cytoplasm), sibling(nucleus)))
                wci ~ integral(F; over = cluster)
            end
            @observed begin
                own1(cell) ~ centroid(1)
                cnx(cell) ~ centroid(sibling(nucleus), 1)
                cny(cell) ~ centroid(sibling(nucleus), 2)
                clx(cell) ~ centroid(sibling(lamellipodium), 1)
                cly(cell) ~ centroid(sibling(lamellipodium), 2)
                ccx(cell) ~ centroid(sibling(cytoplasm), 1)
                raw(cell) ~ centroid(1) - centroid(sibling(nucleus), 1)
                mi(cell) ~ minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1)
                mj(cell) ~ minimum_image(centroid(2) - centroid(sibling(nucleus), 2), 2)
                mdd(cell) ~ minimum_image(dd, 1)
                mdd2(cell) ~ minimum_image(dd, 2)
                sepx(cell) ~ separation(sibling(lamellipodium), sibling(nucleus))[1]
                sepy(cell) ~ separation(sibling(lamellipodium), sibling(nucleus))[2]
                sepn(cell) ~ norm(separation(sibling(lamellipodium), sibling(nucleus)))
                scx(cell) ~ separation(sibling(cytoplasm), sibling(nucleus))[1]
                scy(cell) ~ separation(sibling(cytoplasm), sibling(nucleus))[2]
                sncx(cell) ~ separation(sibling(nucleus), sibling(cytoplasm))[1]
                scn(cell) ~ norm(separation(sibling(cytoplasm), sibling(nucleus)))
                ci(cell) ~ integral(F; over = cluster)
                civ(cell) ~ integral(G; over = cluster)
                cvol(cell) ~ integral(volume; over = cluster)
                own_int(cell) ~ integral(F)
                Πx(cell) ~ volume * minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1) /
                    (volume + volume[sibling(nucleus)])
                tot ~ sum(centroid(c, 1) for c in cells(nucleus))
            end
            @sweep Metropolis(; temperature = T)
        end
    end
)
# Cluster A (root 1): cytoplasm 1 across the x seam (x ∈ {19, 20, 1, 2}, y 3:5, 12 sites),
# nucleus 2 (x 3:4, y 3:4), one-site lamellipodium 3 at (17, 11). Cluster B (root 4):
# cytoplasm 4 (x 8:10, y 8:10), nucleus 5 (x 11, y 8:9), no lamellipodium. Cell 6: a lone
# cytoplasm (x 14:15, y 1:2), its own cluster. F = x + 100y, G = 1.
const DIMS = (20, 12)
const PER = (true, false)
function refs_sigma()
    σ = zeros(Int32, 20, 12)
    σ[[19, 20, 1, 2], 3:5] .= 1
    σ[3:4, 3:4] .= 2
    σ[17, 11] = 3
    σ[8:10, 8:10] .= 4
    σ[11, 8:9] .= 5
    σ[14:15, 1:2] .= 6
    return σ
end
const HELPER_F = [Float64(x + 100y) for x in 1:20, y in 1:12]
const HELPER_DD = [15.0, -15.0, 3.0, -10.25, 10.0, -10.0]
function refs_problem(; tspan = (0, 3), seed = 1, T = Float64)
    sys = system(:Refs; sysname = :rf)
    return PottsProblem(
        sys, [
            ownership => refs_sigma(),
            kind => [:cytoplasm, :nucleus, :lamellipodium, :cytoplasm, :nucleus, :cytoplasm],
            cluster => [1, 1, 1, 4, 4, 6], :Vt => [12.0, 4.0, 1.0, 9.0, 2.0, 4.0], :dd => HELPER_DD,
            :F => HELPER_F, :G => ones(20, 12),
        ], tspan; seed, T, capacity = 8
    )
end
# F3. minimum_image in a drive and a cell energy (section 6), and its explicit-wrap twin.
# The twin reads the period from the parameter Lw (20 = the lattice's x length); Lw = 1e6
# removes the wrap (the negative control).
define(
    :Wrap, quote
        @potts_model Wrap begin
            @kinds medium cell
            @parameters begin
                κ = 0.375
                x0 = 3.5
                μ = 0.25
                λ = 1.0
                T = 3.0
            end
            @variables begin
                q(cell) = 0.0
            end
            @lattice Lattice((20, 12); boundary = (Periodic(), Closed()), neighborhood = Moore(1))
            @energy begin
                cells => λ * (volume - 9.0)^2 + μ * minimum_image(q - x0, 1)^2
                contacts => 2.0
            end
            @drive copy => κ * minimum_image(position[target][1] - x0, 1)
            @sweep Metropolis(; temperature = T)
        end
    end
)
@potts_model WrapRef begin
    @kinds medium cell
    @parameters begin
        κ = 0.375
        x0 = 3.5
        μ = 0.25
        λ = 1.0
        T = 3.0
        Lw = 20.0
    end
    @variables begin
        q(cell) = 0.0
    end
    @lattice Lattice((20, 12); boundary = (Periodic(), Closed()), neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - 9.0)^2 +
            μ * ifelse(2 * (q - x0) > Lw, q - x0 - Lw, ifelse(2 * (q - x0) < -Lw, q - x0 + Lw, q - x0))^2
        contacts => 2.0
    end
    @drive copy => κ * ifelse(
        2 * (position[target][1] - x0) > Lw, position[target][1] - x0 - Lw,
        ifelse(2 * (position[target][1] - x0) < -Lw, position[target][1] - x0 + Lw, position[target][1] - x0)
    )
    @sweep Metropolis(; temperature = T)
end
# three 3×3 cells, cell 1 across the x seam. q − x0 = 13.75, −16, 0.5 → wrapped −6.25, 4, 0.5.
function wrap_sigma()
    σ = zeros(Int32, 20, 12)
    σ[[19, 20, 1], 2:4] .= 1
    σ[8:10, 5:7] .= 2
    σ[13:15, 8:10] .= 3
    return σ
end
const WRAP_OP = [ownership => wrap_sigma(), kind => fill(:cell, 3), :q => [17.25, -12.5, 4.0]]
wrap_problem(; seed = 1, T = Float64, tspan = (0, 5)) =
    PottsProblem(system(:Wrap; sysname = :wr), WRAP_OP, tspan; seed, T)
wrapref_problem(; seed = 1, T = Float64, tspan = (0, 5), Lw = 20.0) =
    PottsProblem(WrapRef(; name = :wf, Lw), WRAP_OP, tspan; seed, T)
const WRAP_CELL_TERM = 0.25 * (6.25^2 + 4.0^2 + 0.5^2)
# μ Σ minimum_image(q − x0)² = 13.828125

# F4. The hexagonal torus (section 7). 10 × 10 periodic hex. Two one-site cells at lattice
# coordinates a = (6, 5) and b = (2, 2): a − b = (4, 3). Images (4 + 10i, 3 + 10j), squared
# embedded norm q² + qr + r²: (4, 3) → 37, (−6, 3) → 27, (4, −7) → 37, (−6, −7) → 127; the
# nearest is (−6, 3), embedded (−6 + 3/2, 3√3/2) = (−4.5, 2.598…), norm √27. The per-axis
# wrap of embedded centroids would give (5.5, 3√3/2), norm √37.
define(
    :HelperHex, quote
        @potts_model HelperHex begin
            @kinds medium blob
            @variables begin
                me(cell)::CellRef
                partner(cell)::CellRef
            end
            @lattice Lattice((10, 10); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1))
            @energy cells => (volume - 1.0)^2
            @observed begin
                hx(cell) ~ separation(me, partner)[1]
                hy(cell) ~ separation(me, partner)[2]
                hn(cell) ~ norm(separation(me, partner))
                hpx(cell) ~ centroid(partner, 1)
                hpy(cell) ~ centroid(partner, 2)
            end
            @sweep Metropolis(; temperature = 1.0)
        end
    end
)
function hex_problem()
    σ = zeros(Int32, 10, 10)
    σ[6, 5] = 1
    σ[2, 2] = 2
    return PottsProblem(
        system(:HelperHex; sysname = :hx), [
            ownership => σ, kind => [:blob, :blob],
            :me => [1, 2], :partner => [2, 1],
        ], (0, 1)
    )
end
# F5. Refusal templates (section 8): one model per refused form, on F2's lattice.
bad_expr(name::Symbol; energy = :((volume - 9.0)^2), update = :(w ~ 0.0)) = :(
    @potts_model $name begin
        @kinds medium cytoplasm nucleus
        @parameters begin
            ax = 1.0
        end
        @variables begin
            dd(cell) = 0.0
            w(cell) = 0.0
            F(site) = 0.0
        end
        @lattice Lattice((20, 12); boundary = (Periodic(), Closed()), neighborhood = Moore(1))
        @energy begin
            cells => $energy
            contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 0.5, 1.0)
        end
        @after_mcs $update
        @sweep Metropolis(; temperature = 1.0)
    end
)
function bad_op(sys)
    σ = zeros(Int32, 20, 12)
    σ[3:5, 3:5] .= 1
    σ[6, 3] = 2
    return [ownership => σ, kind => [:cytoplasm, :nucleus], cluster => [1, 1]]
end
# ---------------------------------------------------------------------------------------
# 5. After-MCS writes: the same values as `@observed`, and an independent oracle
function check_writes(prob, u; atol)
    σ = Array(u.ownership)
    v = vol(u)
    alive = [c for c in 1:6 if v[c] > 0]
    # the writes (after the last sweep) equal the observed values on the saved state
    @test isapprox(col(u, :wcx)[alive], observe(prob, :cnx, u)[alive]; atol)
    @test isapprox(col(u, :wmi)[alive], observe(prob, :mi, u)[alive]; atol)
    @test isapprox(col(u, :wsn)[alive], observe(prob, :scn, u)[alive]; atol)
    @test isapprox(col(u, :wci)[alive], observe(prob, :ci, u)[alive]; atol)
    # the observed values equal the independent oracle (σ alone)
    for c in alive
        n = oracle_sibling(u, c, 2)
        cn = oracle_centroid(σ, n, DIMS, PER)
        cc = oracle_centroid(σ, c, DIMS, PER)
        @test isapprox(observe(prob, :cnx, u)[c], n == 0 ? 0.0 : cn[1]; atol)
        n == 0 && continue
        w = oracle_wrap(cc[1] - cn[1], 20, true)
        m = observe(prob, :mi, u)[c]
        abs(abs(w) - 10) < 1.0e-6 ? (@test isapprox(abs(m), 10.0; atol)) : (@test isapprox(m, w; atol))   # a tie: up to sign (O2)
        @test isapprox(observe(prob, :ci, u)[c], oracle_cluster_sum(u, HELPER_F, c); atol)
    end
    return nothing
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "cell reference helpers: the fixtures build" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. The fixtures build
    @testset "cell reference helpers: the fixtures build" begin
        # (the constructor runs the model body, where the new names are resolved)
        builds(name) = try
            system(name)
            true
        catch
            false
        end
        for name in (:HelperPairs, :Refs, :Wrap, :HelperHex)
            @test builds(name)                                       # DEFECT CHECK: `Pairs`, `minimum_image`, … unknown today
        end
        @test builds(:PairsMatrix)                              # CONTROL: the matrix twin
        @test builds(:WrapRef)                                  # CONTROL: the explicit-wrap twin
    end
end

@testitem "cell reference helpers: Pairs lowers to the hand-written matrix (E2)" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Named pairs (E2)
    @testset "cell reference helpers: Pairs lowers to the hand-written matrix (E2)" begin
        pm = pairs_problem(:PairsMatrix)
        # CONTROL: the matrix twin carries the hand matrices
        @test getp(pm, :J)(pm) == J_hand()
        @test getp(pm, :μ)(pm) == μ_HAND
        pp = pairs_problem(:HelperPairs)                        # DEFECT CHECK (the whole testset below)
        @test getp(pp, :J)(pp) == J_hand()                     # symmetric fill, default 0, a parameter entry
        @test getp(pp, :μ)(pp) == μ_HAND                       # symmetric = false: only the listed order
        @test typeof(pp.p) == typeof(pm.p)                           # the same parameter object type …
        @test pp.p == pm.p                                           # … and values: zero runtime cost
        @test total_energy(pp, pp.u0) == total_energy(pm, pm.u0)
        # a parameter entry follows remake on both sides of the diagonal
        pr = remake(pp; p = [:Jcn => 11.0])
        @test getp(pr, :J)(pr) == J_hand(11.0)
        @test getp(pr, :J)(pr)[3, 4] == 11.0 && getp(pr, :J)(pr)[4, 3] == 11.0
        # and the same trajectory as the matrix form
        sp, sm = solve(pp, SequentialCPM(); saveat = 1), solve(pm, SequentialCPM(); saveat = 1)
        @test all(i -> Array(sp.u[i].ownership) == Array(sm.u[i].ownership), eachindex(sm.u))
    end
end

@testitem "cell reference helpers: Pairs refuses unknown names, non-kinds and pairs given twice (E2)" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: Pairs refuses unknown names, non-kinds and pairs given twice (E2)" begin
        op = sys -> PAIRS_OP
        good_μ = μ_PAIRS
        bad(name, J) = build_error(name, pairs_expr(name, J, good_μ), op)
        # a misspelled kind
        e1 = bad(:PairsTypo, :(J[kind, kind] = Pairs(default = 0.0, (medium, cytoplsm) => 1.0)))
        @test e1 isa ArgumentError                                   # DEFECT CHECK (today: `Pairs` undefined)
        @test occursin("cytoplsm", msg(e1))
        # a bound name that is not a kind (a parameter)
        e2 = bad(:PairsParam, :(J[kind, kind] = Pairs(default = 0.0, (medium, Jcn) => 1.0)))
        @test e2 isa ArgumentError                                   # DEFECT CHECK
        @test occursin("Jcn", msg(e2))
        # the same pair twice
        e3 = bad(
            :PairsTwice, :(
                J[kind, kind] = Pairs(
                    default = 0.0, (medium, substrate) => 1.0,
                    (medium, substrate) => 2.0
                )
            )
        )
        @test e3 isa ArgumentError                                   # DEFECT CHECK
        # the reversed pair under symmetric fill (even with the same value)
        e4 = bad(
            :PairsRev, :(
                J[kind, kind] = Pairs(
                    default = 0.0, (medium, substrate) => 1.0,
                    (substrate, medium) => 1.0
                )
            )
        )
        @test e4 isa ArgumentError                                   # DEFECT CHECK
        # control: the same reversed pair is accepted with symmetric = false (given to μ, which
        # the energy does not read, so the contact table J stays symmetric)
        e5 = build_error(
            :PairsAsym, pairs_expr(
                :PairsAsym, J_PAIRS,
                :(
                    μ[kind, kind] = Pairs(
                        (medium, substrate) => 1.0, (substrate, medium) => 2.0; default = 0.0,
                        symmetric = false
                    )
                )
            ), op
        )
        @test e5 === nothing                                         # DEFECT CHECK (positive control of the rule)
    end
end

@testitem "cell reference helpers: the hand oracles' own checks" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. centroid(c, k), minimum_image, separation, integral(x; over = cluster): hand values
    @testset "cell reference helpers: the hand oracles' own checks" begin
        # CONTROL (passes today): the independent oracles reproduce the hand values
        σ = refs_sigma()
        C = c -> oracle_centroid(σ, c, DIMS, PER)
        @test C(1) == (20.5, 4.0)                                    # across the seam: 19, 20, 21, 22 → 20.5
        @test C(2) == (3.5, 3.5) && C(3) == (17.0, 11.0) && C(4) == (9.0, 9.0) && C(5) == (11.0, 8.5)
        @test C(6) == (14.5, 1.5)
        @test oracle_wrap(17.0, 20, true) == -3.0 && oracle_wrap(13.5, 20, true) == -6.5
        @test oracle_wrap(7.5, 12, false) == 7.5
        @test sum(HELPER_F[I] for I in CartesianIndices(σ) if σ[I] in (1, 2, 3)) == 7457
        @test sum(HELPER_F[I] for I in CartesianIndices(σ) if σ[I] in (4, 5)) == 9903
        @test sum(HELPER_F[I] for I in CartesianIndices(σ) if σ[I] == 6) == 658
    end
end

@testitem "cell reference helpers: centroid(c, k) reads another cell's centroid (hand values)" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: centroid(c, k) reads another cell's centroid (hand values)" begin
        prob = refs_problem()                                  # DEFECT CHECK (the whole testset)
        u = prob.u0
        @test vol(u)[1:6] == [12, 4, 1, 9, 2, 4]
        @test observe(prob, :own1, u)[1:6] == [20.5, 3.5, 17.0, 9.0, 11.0, 14.5]   # centroid(k): today's convention
        @test observe(prob, :cnx, u)[1:6] == [3.5, 3.5, 3.5, 11.0, 11.0, 0.0]      # no nucleus in cell 6's cluster → 0
        @test observe(prob, :cny, u)[1:6] == [3.5, 3.5, 3.5, 8.5, 8.5, 0.0]
        @test observe(prob, :clx, u)[1:6] == [17.0, 17.0, 17.0, 0.0, 0.0, 0.0]
        @test observe(prob, :cly, u)[1:6] == [11.0, 11.0, 11.0, 0.0, 0.0, 0.0]
        @test observe(prob, :ccx, u)[1:6] == [20.5, 20.5, 20.5, 9.0, 9.0, 14.5]   # the seam cell, wrapped into [1, 21)
        @test observe(prob, :tot, u) == 3.5 + 11.0                   # centroid(c, 1) over cells(nucleus)
    end
end

@testitem "cell reference helpers: minimum_image (periodic and closed axes)" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: minimum_image (periodic and closed axes)" begin
        prob = refs_problem()                                  # DEFECT CHECK (the whole testset)
        u = prob.u0
        # centroid differences: the raw difference (negative control: not wrapped) …
        @test observe(prob, :raw, u)[1:5] == [17.0, 0.0, 13.5, -2.0, 0.0]
        # … and its minimum image on the periodic axis 1 (L = 20)
        @test observe(prob, :mi, u)[1:5] == [-3.0, 0.0, -6.5, -2.0, 0.0]
        # the closed axis 2 is not wrapped, even beyond L/2 = 6
        @test observe(prob, :mj, u)[1:5] == [0.5, 0.0, 7.5, 0.5, 0.0]
        # scalar values (dd = 15, −15, 3, −10.25, ±10)
        m1 = observe(prob, :mdd, u)
        @test m1[1:4] == [-5.0, 5.0, 3.0, 9.75]
        # the tie d = ±L/2: the sign is free, the magnitude is exactly L/2 = 10 (O2, ruled)
        @test abs(m1[5]) == 10.0 && abs(m1[6]) == 10.0
        @test observe(prob, :mdd2, u)[1:6] == HELPER_DD              # closed axis: identity
    end
end

@testitem "cell reference helpers: separation is the minimum-image centroid difference" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: separation is the minimum-image centroid difference" begin
        prob = refs_problem()                                  # DEFECT CHECK (the whole testset)
        u = prob.u0
        # lamellipodium (17, 11) − nucleus (3.5, 3.5): x 13.5 → −6.5 (periodic), y 7.5 (closed)
        @test observe(prob, :sepx, u)[1:3] == [-6.5, -6.5, -6.5]
        @test observe(prob, :sepy, u)[1:3] == [7.5, 7.5, 7.5]
        @test observe(prob, :sepn, u)[1:3] ≈ fill(sqrt(6.5^2 + 7.5^2), 3) atol = 1.0e-12
        # cytoplasm − nucleus: A (20.5, 4) − (3.5, 3.5) → (−3, 0.5); B (9, 9) − (11, 8.5) → (−2, 0.5)
        @test observe(prob, :scx, u)[1:5] == [-3.0, -3.0, -3.0, -2.0, -2.0]
        @test observe(prob, :scy, u)[1:5] == [0.5, 0.5, 0.5, 0.5, 0.5]
        @test observe(prob, :sncx, u)[1:5] == [3.0, 3.0, 3.0, 2.0, 2.0]   # antisymmetric (no tie)
        @test observe(prob, :scn, u)[[1, 4]] ≈ [sqrt(9.25), sqrt(4.25)] atol = 1.0e-12
    end
end

@testitem "cell reference helpers: integral(x; over = cluster) sums over the cluster's sites" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: integral(x; over = cluster) sums over the cluster's sites" begin
        prob = refs_problem()                                  # DEFECT CHECK (the whole testset)
        u = prob.u0
        @test observe(prob, :ci, u)[1:6] == [7457.0, 7457.0, 7457.0, 9903.0, 9903.0, 658.0]
        @test observe(prob, :civ, u)[1:6] == [17.0, 17.0, 17.0, 11.0, 11.0, 4.0]   # Σ 1 = the cluster's volume
        # the integrand is in site scope (ruling R1): `volume` is the site owner's, so the
        # two-member cluster B (V₄ = 9, V₅ = 2) gives 9² + 2² = 85 for both members. Negative
        # control (the other reading, the current cell's volume): (9 + 2)·9 = 99 for cell 4 and
        # (9 + 2)·2 = 22 for cell 5. Cluster A: 12² + 4² + 1² = 161; lone cell 6: 4² = 16.
        cv = observe(prob, :cvol, u)
        @test cv[4:5] == [85.0, 85.0]
        @test cv[4] != 99.0 && cv[5] != 22.0
        @test cv[1:3] == [161.0, 161.0, 161.0] && cv[6] == 16.0
        oi = observe(prob, :own_int, u)
        @test oi[1:6] == [4926.0, 1414.0, 1117.0, 8181.0, 1722.0, 658.0]           # integral(F), per cell
        @test observe(prob, :ci, u)[6] == oi[6]                      # a lone cell: the cluster sum = integral
        @test observe(prob, :ci, u)[1] == oi[1] + oi[2] + oi[3]      # the members' integrals add up
        # plain `integral(x)` stays the cell sum (D-243 amendment): cell 1's own sites only,
        # not the cluster's (7457)
        @test oi[1] == 4926.0 && oi[1] != 7457.0
    end
end

@testitem "cell reference helpers: integral(x; over = …) refusals" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: integral(x; over = …) refusals" begin
        op = bad_op
        # an unknown `over =` value
        eo = build_error(:BadOver, bad_expr(:BadOver; update = :(w ~ integral(F; over = lattice))), op)
        @test eo isa ArgumentError                                   # DEFECT CHECK
        @test occursin("over", msg(eo))
        # `over = cluster` outside a cell or cluster context (a site-scope update)
        es = build_error(:BadOverSite, bad_expr(:BadOverSite; update = :(F ~ integral(F; over = cluster))), op)
        @test es isa Potts.PottsCompileError                                   # DEFECT CHECK
        @test occursin("integral", msg(es))
        # CONTROL (DEFECT CHECK today): `over = cluster` in a cell-scope update builds
        eok = build_error(:OkOver, bad_expr(:OkOver; update = :(w ~ integral(F; over = cluster))), op)
        @test eok === nothing                                        # DEFECT CHECK
    end
end

@testitem "cell reference helpers: the Π_CN−N polarization of 14b Eq 10 from the helpers" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: the Π_CN−N polarization of 14b Eq 10 from the helpers" begin
        prob = refs_problem()                                  # DEFECT CHECK
        u = prob.u0
        Π = observe(prob, :Πx, u)
        # V_C (r_C − r_N) / (V_C + V_N), x: A 12 · (−3) / 16, B 9 · (−2) / 11
        @test Π[1] ≈ -2.25 atol = 1.0e-12
        @test Π[4] ≈ -18 / 11 atol = 1.0e-12
    end
end

@testitem "cell reference helpers: a dead referent's centroid reads 0; the integral drops its sites" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. Dead referents
    @testset "cell reference helpers: a dead referent's centroid reads 0; the integral drops its sites" begin
        prob = refs_problem()                                  # DEFECT CHECK (the whole testset)
        u = prob.u0
        a = apply(prob, u, helper_prop(prob, u, 3, 0))          # the medium takes the lamellipodium's only site
        @test vol(a)[3] == 0
        @test observe(prob, :clx, a)[1:2] == [0.0, 0.0]              # dead referent → 0.0 (open, O4)
        @test observe(prob, :cly, a)[1:2] == [0.0, 0.0]
        @test observe(prob, :ci, a)[1:2] == [7457.0 - 1117.0, 7457.0 - 1117.0]
        @test observe(prob, :civ, a)[1:2] == [16.0, 16.0]
        @test observe(prob, :cnx, a)[1:2] == [3.5, 3.5]              # an alive referent is unaffected
    end
end

@testitem "cell reference helpers: after-MCS writes match @observed and the oracle (sequential and checkerboard)" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cell reference helpers: after-MCS writes match @observed and the oracle (sequential and checkerboard)" begin
        for alg in (SequentialCPM(), CheckerboardCPM())              # DEFECT CHECK (the whole testset)
            prob = refs_problem(; tspan = (0, 4), seed = 3)
            sol = solve(prob, alg; saveat = 1)
            @test Symbol(sol.retcode) === :Success
            check_writes(prob, sol.u[end]; atol = 1.0e-9)
        end
    end
end

@testitem "cell reference helpers: minimum_image in a drive and an energy equals the explicit wrap (bitwise)" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 6. minimum_image in a drive and an energy, against the explicit-wrap twin
    @testset "cell reference helpers: minimum_image in a drive and an energy equals the explicit wrap (bitwise)" begin
        pr = wrapref_problem()
        # CONTROL: the twin's cell term is the hand value μ Σ wrap(q − x0)²
        p0 = remake(pr; p = [:μ => 0.0])
        @test total_energy(pr, pr.u0) - total_energy(p0, p0.u0) == WRAP_CELL_TERM
        # CONTROL (negative): without the wrap the twin's trajectory changes, so equality pins it
        rr = solve(pr, SequentialCPM(); saveat = 1)
        rn = solve(wrapref_problem(; Lw = 1.0e6), SequentialCPM(); saveat = 1)
        @test any(i -> Array(rr.u[i].ownership) != Array(rn.u[i].ownership), eachindex(rr.u))
        pw = wrap_problem()                                    # DEFECT CHECK (the rest)
        @test total_energy(pw, pw.u0) == total_energy(pr, pr.u0)
        ctxw, ctxr = ctx(pw), ctx(pr)
        props = helper_props(pw, pw.u0)
        @test all(p -> pw.f.bias(pw.u0, pw.p, p, ctxw) == pr.f.bias(pr.u0, pr.p, p, ctxr), props)
        @test all(p -> energy_change(pw, pw.u0, p) == energy_change(pr, pr.u0, p), props)
        for alg in (SequentialCPM(), CheckerboardCPM())
            sw = solve(pw, alg; saveat = 1)
            sr = solve(pr, alg; saveat = 1)
            @test all(i -> Array(sw.u[i].ownership) == Array(sr.u[i].ownership), eachindex(sr.u))
        end
    end
end

@testitem "cell reference helpers: separation on the periodic hexagonal lattice is the embedded nearest image" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 7. The hexagonal torus
    @testset "cell reference helpers: separation on the periodic hexagonal lattice is the embedded nearest image" begin
        prob = hex_problem()                                   # DEFECT CHECK (the whole testset)
        u = prob.u0
        s3 = sqrt(3.0) / 2
        @test observe(prob, :hx, u)[1:2] ≈ [-4.5, 4.5] atol = 1.0e-12  # a − b → image (−6, 3), embedded
        @test observe(prob, :hy, u)[1:2] ≈ [3s3, -3s3] atol = 1.0e-12
        @test observe(prob, :hn, u)[1:2] ≈ fill(sqrt(27.0), 2) atol = 1.0e-12        # not √37 (per-axis wrap)
        # the same distance as CorePotts's centroid distance (the link-energy measure)
        @test CorePotts.centroid_distance(Float64, u.cell, prob.lattice, 1, 2) ≈ sqrt(27.0) atol = 1.0e-12  # CONTROL
        # centroid(c, k) is embedded, as centroid(k): b = (2, 2) → (3, √3), a = (6, 5) → (8.5, 5√3/2)
        @test observe(prob, :hpx, u)[1:2] ≈ [3.0, 8.5] atol = 1.0e-12
        @test observe(prob, :hpy, u)[1:2] ≈ [2s3, 5s3] atol = 1.0e-12
    end
end

@testitem "cell reference helpers: refusals in energies and axis errors" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 8. Refusals and axis errors (negative controls)
    @testset "cell reference helpers: refusals in energies and axis errors" begin
        op = bad_op
        # CONTROL (passes today): the harness sees today's refusals
        e0 = build_error(:BadOld, bad_expr(:BadOld; energy = :((volume - 9.0)^2 + centroid(1))), op)
        @test e0 isa Potts.PottsCompileError && occursin("centroid", msg(e0))
        e00 = build_error(:BadOldAxis, bad_expr(:BadOldAxis; update = :(w ~ centroid(3))), op)
        @test e00 isa Potts.PottsCompileError && occursin("centroid", msg(e00))
        # CONTROL (DEFECT CHECK today): the template itself builds with the helpers in an update
        eok = build_error(
            :BadNone, bad_expr(
                :BadNone;
                update = :(w ~ centroid(sibling(nucleus), 1) + minimum_image(dd, 1) + integral(F; over = cluster))
            ), op
        )
        @test eok === nothing                                        # DEFECT CHECK
        # centroid(c, k) in an energy (no ΔH; D-032 until R7, open O5)
        e1 = build_error(
            :BadCE, bad_expr(
                :BadCE;
                energy = :((volume - 9.0)^2 + centroid(sibling(nucleus), 1))
            ), op
        )
        @test e1 isa Potts.PottsCompileError                                   # DEFECT CHECK
        @test occursin("centroid", msg(e1))
        # integral(x; over = cluster) in an energy (refreshed once per MCS: no ΔH, as integral)
        e2 = build_error(:BadCI, bad_expr(:BadCI; energy = :((volume - 9.0)^2 + integral(F; over = cluster))), op)
        @test e2 isa Potts.PottsCompileError                                   # DEFECT CHECK
        @test occursin("integral", msg(e2))
        # axes: not an axis of the 2D lattice, and not a literal
        e3 = build_error(:BadCA, bad_expr(:BadCA; update = :(w ~ centroid(sibling(nucleus), 3))), op)
        @test e3 isa Potts.PottsCompileError                                   # DEFECT CHECK
        @test occursin("centroid", msg(e3))
        e4 = build_error(:BadMA, bad_expr(:BadMA; update = :(w ~ minimum_image(dd, 3))), op)
        @test e4 isa Potts.PottsCompileError                                   # DEFECT CHECK
        @test occursin("minimum_image", msg(e4))
        e5 = build_error(:BadML, bad_expr(:BadML; update = :(w ~ minimum_image(dd, ax))), op)
        @test e5 isa Potts.PottsCompileError                                   # DEFECT CHECK
        @test occursin("minimum_image", msg(e5))
    end
end

@testitem "cell reference helpers: the helpers on the device" setup = [CellReferenceHelpersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 9. Device
    @testset "cell reference helpers: the helpers on the device" begin
        if PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM(; proposal = Moore(1))
            # after-MCS writes of centroid(c, k), minimum_image, separation, integral(x; over = cluster)
            prob = refs_problem(; tspan = (0, 4), seed = 3, T = Float32)
            sol = solve(prob, alg; backend, saveat = 1)
            @test Symbol(sol.retcode) === :Success
            check_writes(prob, sol.u[end]; atol = 1.0e-3)
            # minimum_image in a drive and an energy: bitwise equal to the explicit wrap on the
            # device (every value is dyadic, so Float32 is exact)
            sw = solve(wrap_problem(; T = Float32), alg; backend, saveat = 1)
            sr = solve(wrapref_problem(; T = Float32), alg; backend, saveat = 1)
            @test Symbol(sw.retcode) === :Success
            @test all(i -> Array(sw.u[i].ownership) == Array(sr.u[i].ownership), eachindex(sr.u))
            # named pairs on the device: the same trajectory as the matrix form
            pp = PottsProblem(system(:HelperPairs; sysname = :pr), PAIRS_OP, (0, 3); seed = 1, T = Float32)
            pm = PottsProblem(system(:PairsMatrix; sysname = :pr), PAIRS_OP, (0, 3); seed = 1, T = Float32)
            sp, sm = solve(pp, alg; backend, saveat = 1), solve(pm, alg; backend, saveat = 1)
            @test all(i -> Array(sp.u[i].ownership) == Array(sm.u[i].ownership), eachindex(sm.u))
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end
