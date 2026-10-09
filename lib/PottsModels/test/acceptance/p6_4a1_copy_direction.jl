# P6.4a1 (ROADMAP Phase 6, step 4; D-186 foam stream 1): the copy-scope `direction`, the
# source→target lattice offset of the attempted copy, readable wherever ΔH is written in the
# copy scope, so that the foam shear term of Jiang et al. (1999), spec 04 §2.2 and A-1,
#     ΔH_shear = γ(y_i, t)·(x_i − x_j)      (i = target, j = source, minimum image in x),
# can be written. Frozen (AUTONOMY §7.3). Decisions: D-186 (the item), D-048 (ordinary tests:
# independent oracles and negative controls), D-158 (our own code's recorded values are
# bitwise; same-seed determinism is free), D-171 (`gate.jl` checks warm allocations, the
# A/B decides speed), D-157 (POTTS_GPU device selection).
#
# Names and forms pinned (the DSL surface; the reviewer checks DSL_NAMES, AUTONOMY §7.3).
# - `direction[k]`, k = 1..N: component k of x_target − x_source, a scalar of the model's
#   type `T`. Why this form: it mirrors `position[k]`, the one vector builtin of the DSL,
#   which is already indexed by axis with `[k]` and is in the same Cartesian units. A tuple
#   value would be a new kind of value in the expression language (every builtin today is a
#   scalar or an axis-indexed vector), and a call form `direction(k)` would read as a
#   function of the copy like `displacement(c, k)`, which takes a cell. The name says what
#   it is in the paper's words ("(1,0) … the direction of the strain", 04b p.5821).
# - Units: the same as `position` (the embedded coordinates times the lattice `spacing`), so
#   that on a closed axis `direction[k] == position[target][k] − position[source][k]`
#   exactly. On a square lattice with unit spacing it is the integer lattice offset.
# - Periodic axes: the minimum image, d − L·round(d/L) for the coordinate difference d along
#   an axis of L sites (then times the spacing). Closed axes: the plain difference, also for
#   a scripted source far from the target. The fixtures never use |d| = L/2 on a periodic
#   axis (the tie is not pinned); every proposal neighbourhood has reach < L/2 here.
# - It is a function of (source, target) alone, not of `prop.dir` (the host hook below
#   builds proposals with `dir = 1` as every frozen ΔH oracle does, and the host context has
#   no proposal relation), and it does not read the state.
# - Copy scope: drives (`@drive copy => …`) and constraints (`@constraint …`) read it; both
#   are pinned. (On-copy updates and a copy-scope temperature share the copy scope's
#   environment and are expected to follow; they are not pinned here.) It is not an
#   `@energy` name: an energy is a state function and x_i − x_j is a property of the copy, so
#   the shear term is a drive, and ΔH (`prob.f.delta_H`, the Metropolis argument) includes
#   it. `energy_change` (ΔH without drives) does not.
# - Also in the copy scope, both today rejected in a drive ("`mcs` is not available in a
#   drive", "`position` is not available in a drive"; spec 04 §8 assumed both were there):
#   `mcs`, the number of completed MCS, i.e. n − 1 during the n-th MCS (as in `@before_mcs`
#   and the ODEs, P6.0q); and `position[target][k]`, `position[source][k]`, the site's
#   `position` component k. The copy scope indexes every site quantity explicitly
#   (`kind[target]`, `c[source]`), so `position[s]` is the site's vector and `[k]` its
#   component; the site-scope `position[k]` is unchanged. `time` (ROADMAP P6.4a) is not
#   needed by the foam (t is in MCS) and is left to P6.4a.
#
# The foam form that must be writable (spec 04 Eq. 7 with G(t) = sin(ωt), y from the
# mid-plane y0):
#     @drive copy => γ0 * sin(ω * mcs) * (position[target][2] - y0) * direction[1]
# (Eq. 6, the boundary rows, is the same with an indicator of position[target][2].)
#
# What is pinned.
#  1. Exact values on the host hook. Tiny lattices with random labels (three owners): 7×6
#     periodic × closed; 7×6 periodic × periodic; 7×6 closed × periodic with spacing
#     (0.5, 2.0); 5×6×5 periodic × closed × periodic. Every unlike (target, source) pair
#     with source = target + o, o in Moore(1) ∪ VonNeumann(1) ∪ reach-2 offsets (as in
#     NeighborOrder(4), the foam's 20-neighbour shell), wrapped across periodic axes
#     (seam pairs included), plus far pairs (|o| up to 5) on every axis. The drive part of
#     ΔH, `prob.f.delta_H(u, p, prop, ctx) − energy_change(prob, u, prop)`, of the probe
#     drive `a1·direction[1] + a2·direction[2] (+ a3·direction[3]) + bt·position[target][2]·
#     direction[1] + cs·position[source][1]·direction[2]` with one coefficient at a time set
#     to 1 equals the hand value from the coordinates (no production code), exactly: every
#     value is dyadic. The same with `dir = 2`.
#     Hexagonal (optional, pinned either way): a closed 7×6 hexagonal model with the probe
#     drive either fails to build with an `ArgumentError` that names `direction`, or gives
#     the embedded offset (q + r/2, r·√3/2) of the axial difference, to 1e-12. A periodic
#     hexagonal lattice is not pinned.
#  2. The kernel path, bitwise. A model with the shear drive written with `direction`,
#     `position` and `mcs` (`P64a1Dir`) and a reference that writes the same numbers with
#     features that exist today (`P64a1Ref`: site variables px, py holding the coordinates,
#     the minimum image by `ifelse` with the period L, and a model variable G set from `mcs`
#     in `@before_mcs`) give bitwise the same trajectory (σ at every MCS and
#     `stats.accepted`) from the same seed. 24×16, periodic x, closed y, one cell across the
#     x seam. Algorithms: SequentialCPM with Moore(1), VonNeumann(1) and NeighborOrder(4)
#     proposals, CheckerboardCPM(Moore(1)), BoundarySiteCPM(Moore(1)). Drives: (a) γ0·G·(y −
#     y0)·dx with G = 1 for mcs < K = 3 and −½ after (a reversal at a pinned MCS: pins the
#     `mcs` convention), (b) the literal foam form with sin(ω·mcs), (c) η·dy + u·dx. A
#     copy-scope constraint `direction[1]² + direction[2]² ≤ R2` is in both, always true at
#     R2 = 100; at R2 = 1.5 (diagonal copies forbidden) the two still agree. Every value of
#     (a) and (c) is dyadic, so the comparison is exact; (b) multiplies sin values whose
#     rounding could in principle differ with the factor order, so a flip needs a uniform
#     draw within an ulp of the threshold (probability ~1e-13 over the run).
#     Negative controls (reference only, so they pass today): the reference without the
#     minimum image (L = 1e6), with γ0 → −γ0, with K = 4, and with R2 = 1.5 each give a
#     different trajectory from the reference, so equality with the reference pins the
#     wrap, the sign, the MCS convention and the constraint read.
#     Float32 (CPU) the same. On the device (POTTS_GPU = metal | rocm, T = Float32,
#     CheckerboardCPM(Moore(1))): `P64a1Dir` equals `P64a1Ref` on the device, bitwise.
#  3. Statistics. A uniform shear field (drive u·direction[1], ΔH = u·dx) moves a single
#     cell toward −x for u > 0 (spec 04 §2.2: γ > 0 biases reassignment toward decreasing
#     x). One 25-site cell across the x seam of the 24×16 lattice, R = 400 runs of M = 40
#     MCS, SequentialCPM(Moore(1)), T = 3; D = the net x drift of the centroid (circular
#     mean on the periodic axis, minimum-image increments per MCS).
#     (a) sign: z = D̄/(s/√R) < −Z1 at u = +1, > +Z1 at u = −1 (the negative control with
#         the opposite sign), Z1 = 3.09 (one-sided 1.0e-3);
#     (b) rough magnitude: D̄ ∈ [−2.0, −0.5] at u = +1 and ∈ [0.5, 2.0] at u = −1;
#     (c) null: |z| ≤ Z2 = 3.29 at u = 0 (two-sided 1.0e-3);
#     (d) the same law as the reference: Welch |z| ≤ Z2 between `P64a1Dir` (seeds 1:400) and
#         `P64a1Ref` (seeds 1001:1400) at u = 1; control: `P64a1Dir` at u = 1 against
#         `P64a1Ref` at u = ½ gives |z| > Z2.
#     Calibrated on the freeze base with the reference (400 runs, 40 MCS): D̄ = −0.994,
#     s = 0.973 at u = 1 (z = −20.4); −0.499 at u = ½; +0.012 at u = 0 (z = 0.25). False
#     failure: (a) and (b) sit ≥ 10 standard errors inside their limits (< 1e-20); (c) and
#     (d) are 1.0e-3 each under the hypothesis; the (d) control expects |z| ≈ 7.
#  4. Performance. Zero warm allocations (the gate's rule: the minimum over five warm
#     `step!`s after two, `benchmark/gate.jl`) for `P64a1Dir` with the sin drive under the
#     four algorithms of item 2 and for the 3D probe under SequentialCPM(Moore(1)).
#     Models that do not read `direction` are unchanged bitwise (D-158) and are pinned
#     elsewhere, not duplicated here: the SequentialCPM records of
#     `p6_4b1_boundary_site.jl` (Graner–Glazier 72², OpenVT 60²), the bitwise rows of
#     `p6_0x_gather_ode_alloc.jl`, the fingerprints of `p6_0ah_canonical_term_order.jl`,
#     `p6_0aq_acceptance_fingerprint.jl` and `p6_0ar_neighbourhood_fingerprint.jl`, the
#     transition oracles (`lib/CorePotts/test/oracle.jl`, `test/oracle.jl`) and the gate
#     rows. One new record: `P64a1Ref`, a model with a copy-scope drive and constraint that
#     do not read `direction` (the code path this item touches), keeps its fingerprint and
#     its SequentialCPM result (sha256 of σ and the accepted count) recorded on the freeze
#     base. Speed is the D-171 A/B, outside this file.
#  5. `Metropolis(tie)` is deferred (not needed for the foam). Spec 04 A-6 recommends the
#     T → 0⁺ limit: ties (ΔH′ = 0) accepted with P = 1, uphill moves rejected. Today's
#     `Metropolis` at T = ε > 0 does exactly that for ties (`x ≤ 0` accepts) and accepts
#     ΔH > 0 with exp(−ΔH/ε), which is 0 in Float64 and Float32 for ΔH ≥ 1e-3 at ε = 1e-6;
#     the foam's integer contact and area terms make |ΔH| ≥ 1 apart from the shear term, so
#     the only difference from the T → 0⁺ limit is the band 0 < ΔH < ~1e-4, crossed by the
#     continuous γ(t)·dx for a fraction ~1e-5 of a sin(ωt) cycle: far below the paper's
#     own "few percent of a Monte Carlo step" timing uncertainty (04b p.5821). T ≤ 0 keeps
#     the CompuCell3D ½ tie rule, which is why the foam uses ε and not 0. The premise is
#     pinned (it passes today): `CorePotts.accept` at ε = 1e-6 accepts ties for every
#     uniform draw and rejects ΔH = 1e-3 for every draw, in Float64 and Float32.
#
# Tiers and cost (Apple M-series, one thread): always on, about 1 min with a stub, mostly the
# compilation of the eight models; item 3 is ~1 s of sampling per arm. No FULL tier.
#
# Today (freeze base d7fc5793) this file fails because `direction` is not defined
# (`UndefVarError: direction not defined` when any model that names it is constructed: 40
# errors, in every testset of items 1–4 that uses `direction`); with `direction` alone added,
# `mcs` and `position` would still be rejected in a drive. The reference halves pass: the
# hand oracle's own checks, the controls of item 2, the reference arms of item 3, the
# record of item 4 and item 5. Checked before the freeze against a stub (the probes and
# `P64a1Dir` rewritten with today's site-variable workaround): every testset passes.
using Test, Potts, PottsModels
using Potts: CorePotts
using Statistics: mean, std, var
using StableRNGs: StableRNG
using SHA: sha256

const P64A1_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()
const P64A1_Z1 = 3.09
const P64A1_Z2 = 3.29
const P64A1_R = 400
const P64A1_M = 40

# ---------------------------------------------------------------------------------------
# Fixtures are defined through `p64a1_define`, so that a build failure (today: `direction`
# is undefined, `mcs` and `position` are rejected in a drive) fails the testsets that use
# the fixture instead of aborting the file.

const P64A1_DEFINE_ERRORS = Dict{Symbol, Any}()
function p64a1_define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
    catch e
        P64A1_DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
p64a1_model(name::Symbol) = isdefined(@__MODULE__, name) ? getfield(@__MODULE__, name) :
                            error("P6.4a1 fixture $name did not build: $(get(P64A1_DEFINE_ERRORS, name, "unknown"))")

# ---------------------------------------------------------------------------------------
# 1. Probe models for the host oracle.

function p64a1_probe_expr(name::Symbol, lattice::Expr, nd::Int)
    drive = nd == 3 ?
            :(a1 * direction[1] + a2 * direction[2] + a3 * direction[3] + bt * position[target][2] * direction[1] +
              cs * position[source][1] * direction[2]) :
            :(a1 * direction[1] + a2 * direction[2] + bt * position[target][2] * direction[1] +
              cs * position[source][1] * direction[2])
    return :(@potts_model $name begin
        @kinds medium A B
        @parameters begin
            a1 = 0.0
            a2 = 0.0
            a3 = 0.0
            bt = 0.0
            cs = 0.0
        end
        @lattice $lattice
        @energy begin
            cells => (volume - 4.0)^2
            contacts => 2.0 * (kind != kind′)
        end
        @drive copy => $drive
        @sweep Metropolis(; temperature = 1.0)
    end)
end

# (name, lattice expression, dims, periodic axes, spacing)
const P64A1_GEOMS = [
    (:P64a1ProbePC, :(Lattice((7, 6); boundary = (Periodic(), Closed()))), (7, 6), (true, false), (1.0, 1.0)),
    (:P64a1ProbePP, :(Lattice((7, 6); boundary = (Periodic(), Periodic()))), (7, 6), (true, true), (1.0, 1.0)),
    (:P64a1ProbeSP, :(Lattice((7, 6); boundary = (Closed(), Periodic()), spacing = (0.5, 2.0))), (7, 6), (false, true),
        (0.5, 2.0)),
    (:P64a1Probe3D, :(Lattice((5, 6, 5); boundary = (Periodic(), Closed(), Periodic()))), (5, 6, 5),
        (true, false, true), (1.0, 1.0, 1.0)),
]
for (name, lat, dims, _, _) in P64A1_GEOMS
    p64a1_define(name, p64a1_probe_expr(name, lat, length(dims)))
end
p64a1_define(:P64a1ProbeHex, p64a1_probe_expr(:P64a1ProbeHex,
    :(Lattice((7, 6); boundary = Closed(), geometry = CorePotts.Hexagonal())), 2))

"""Random labels 0..2 on `dims` (each label present), from a StableRNG."""
function p64a1_labels(dims, seed)
    rng = StableRNG(seed)
    while true
        σ = Int32.(rand(rng, 0:2, dims...))
        all(c -> any(==(c), σ), 0:2) && return σ
    end
end

p64a1_probe_problem(M, dims; seed = 1) =
    PottsProblem(M(; name = :probe), [ownership => p64a1_labels(dims, 640 + seed), kind => [:A, :B]], (0, 1))

# the offsets tried from every target: Moore(1) (which contains VonNeumann(1)), the reach-2
# shell of NeighborOrder(4), and far pairs along every axis
function p64a1_offsets(nd)
    near = vec([Tuple(o) for o in Iterators.product(ntuple(_ -> -1:1, nd)...) if any(!=(0), Tuple(o))])
    reach2 = nd == 2 ? [(2, 0), (-2, 0), (0, 2), (0, -2), (2, 1), (-1, 2), (-2, -1), (1, -2)] :
             [(2, 0, 0), (0, -2, 0), (0, 0, 2), (2, 1, 0), (0, -1, 2), (-2, 0, -1)]
    far = [ntuple(j -> j == k ? s : 0, nd) for k in 1:nd for s in (-5, -4, 4, 5)]
    return unique(vcat(near, reach2, far))
end

"""Minimum image of a coordinate difference `d` on a periodic axis of `L` sites."""
p64a1_mi(d, L) = d - L * round(Int, d / L)

"""
Hand value of `direction` for a copy from `xs` into `xt` (coordinates): the coordinate
difference xt − xs, the minimum image on periodic axes, times the spacing. `nothing` when a
periodic axis is at the tie |d| = L/2 (not pinned).
"""
function p64a1_direction(xt, xs, dims, periodic, spacing)
    d = map((a, b, L, per) -> per ? p64a1_mi(a - b, L) : a - b, xt, xs, dims, periodic)
    any(k -> periodic[k] && 2 * abs(d[k]) == dims[k], eachindex(d)) && return nothing
    return map((x, h) -> x * h, d, spacing)
end

"""The shifted site x + o (wrapping on periodic axes), or `nothing` off a closed axis."""
function p64a1_shift(x, o, dims, periodic)
    y = map((a, b, L, per) -> per ? mod1(a + b, L) : a + b, x, o, dims, periodic)
    all(k -> 1 <= y[k] <= dims[k], eachindex(y)) || return nothing
    return y
end

# the drive part of ΔH (ΔH − ΔE) of one scripted copy, through the host hook
p64a1_drive(prob, u, prop) = prob.f.delta_H(u, prob.p, prop, Potts._host_ctx(prob)) - energy_change(prob, u, prop)

"""
Every unlike scripted copy on the probe problem, as (target coords, source coords, wrapped?):
`wrapped` when the source was reached across a periodic seam.
"""
function p64a1_pairs(prob, dims, periodic)
    σ = prob.u0.σ
    out = Tuple{NTuple{length(dims), Int}, NTuple{length(dims), Int}, Bool}[]
    for I in CartesianIndices(σ), o in p64a1_offsets(length(dims))
        xt = Tuple(I)
        xs = p64a1_shift(xt, o, dims, periodic)
        xs === nothing && continue
        σ[xt...] == σ[xs...] && continue
        push!(out, (xt, xs, any(k -> xs[k] != xt[k] + o[k], eachindex(o))))
    end
    return out
end

p64a1_prop(prob, xt, xs; dir = 1) = (lat = prob.lattice; σ = prob.u0.σ;
    CorePotts.Proposal(CorePotts.linear_index(lat, xt), CorePotts.linear_index(lat, xs), xt, dir, σ[xt...], σ[xs...]))

@testset "P6.4a1: the hand oracle (no production code)" begin
    # the oracle's minimum image and the near offsets: −o on every axis
    for (dims, periodic) in (((7, 6), (true, false)), ((5, 6, 5), (true, false, true)))
        for I in CartesianIndices(dims), o in p64a1_offsets(length(dims))
            maximum(abs, o) <= 2 || continue
            xt = Tuple(I)
            xs = p64a1_shift(xt, o, dims, periodic)
            xs === nothing && continue
            @test p64a1_direction(xt, xs, dims, periodic, map(_ -> 1.0, dims)) == map(x -> -Float64(x), o)
        end
    end
    @test p64a1_mi(-6, 7) == 1 && p64a1_mi(5, 7) == -2 && p64a1_mi(4, 6) == -2 && p64a1_mi(-3, 7) == -3
    @test p64a1_direction((1, 1), (6, 1), (7, 6), (true, false), (1.0, 1.0)) == (2.0, 0.0)     # across the seam
    @test p64a1_direction((1, 1), (1, 6), (7, 6), (true, false), (1.0, 1.0)) == (0.0, -5.0)    # closed: plain
    @test p64a1_direction((1, 1), (1, 4), (7, 6), (true, true), (1.0, 1.0)) === nothing        # the tie
end

@testset "P6.4a1: exact direction on the host hook ($name)" for (name, _, dims, periodic, spacing) in P64A1_GEOMS
    M = p64a1_model(name)
    nd = length(dims)
    coefs = nd == 3 ? (:a1, :a2, :a3, :bt, :cs) : (:a1, :a2, :bt, :cs)
    nbad = nchecked = nwrap = nfar_closed = nfar_periodic = 0
    for seed in 1:2
        base = p64a1_probe_problem(M, dims; seed)
        probs = Dict(k => remake(base; p = [k => 1.0]) for k in coefs)
        u = base.u0
        for (xt, xs, wrapped) in p64a1_pairs(base, dims, periodic)
            d = p64a1_direction(xt, xs, dims, periodic, spacing)
            d === nothing && continue
            yt = xt[2] * spacing[2]                       # position[target][2]
            xs1 = xs[1] * spacing[1]                      # position[source][1]
            want = Dict(:a1 => d[1], :a2 => d[2], :bt => yt * d[1], :cs => xs1 * d[2])
            nd == 3 && (want[:a3] = d[3])
            for dir in (1, 2), k in coefs
                got = p64a1_drive(probs[k], u, p64a1_prop(base, xt, xs; dir))
                nbad += got != want[k]
                nchecked += 1
            end
            nwrap += wrapped
            raw = map(-, xt, xs)
            nfar_closed += any(k -> !periodic[k] && abs(raw[k]) >= 4, 1:nd)
            nfar_periodic += any(k -> periodic[k] && abs(raw[k]) >= 4 && !wrapped, 1:nd)
        end
    end
    @test nbad == 0
    # coverage of the fixture itself
    @test nchecked > 1000
    @test nwrap > 50
    any(!, periodic) && @test nfar_closed > 20
    @test nfar_periodic > 20
end

@testset "P6.4a1: hexagonal (either an ArgumentError naming `direction`, or the embedded offset)" begin
    if haskey(P64A1_DEFINE_ERRORS, :P64a1ProbeHex) && P64A1_DEFINE_ERRORS[:P64a1ProbeHex] isa ArgumentError
        @test occursin("direction", sprint(showerror, P64A1_DEFINE_ERRORS[:P64a1ProbeHex]))
    else
        M = p64a1_model(:P64a1ProbeHex)
        built = try
            p64a1_probe_problem(M, (7, 6))
        catch e
            e
        end
        if built isa ArgumentError
            @test occursin("direction", sprint(showerror, built))
        else
            base = built
            probs = Dict(k => remake(base; p = [k => 1.0]) for k in (:a1, :a2, :bt, :cs))
            emb(v) = (v[1] + v[2] / 2, v[2] * sqrt(3) / 2)
            worst = 0.0
            n = 0
            for (xt, xs, _) in p64a1_pairs(base, (7, 6), (false, false))
                d = emb(map(-, xt, xs))
                want = Dict(:a1 => d[1], :a2 => d[2], :bt => emb(xt)[2] * d[1], :cs => emb(xs)[1] * d[2])
                for k in (:a1, :a2, :bt, :cs)
                    worst = max(worst, abs(p64a1_drive(probs[k], base.u0, p64a1_prop(base, xt, xs)) - want[k]))
                end
                n += 1
            end
            @test n > 300
            @test worst < 1e-12
        end
    end
end

# ---------------------------------------------------------------------------------------
# 2. The kernel path: the shear drive written with `direction`, `position` and `mcs`, and a
# reference written with features that exist today.

const P64A1_LAT = (24, 16)

p64a1_define(:P64a1Dir, :(@potts_model P64a1Dir begin
    @kinds medium A
    @parameters begin
        γ0 = 1.0
        y0 = 8.5
        K = 3.0
        mode = 0.0
        ω = 0.3
        η = 0.0
        u = 0.0
        R2 = 100.0
    end
    @lattice Lattice((24, 16); boundary = (Periodic(), Closed()))
    @energy begin
        cells => (volume - 25.0)^2
        contacts => 4.0 * (kind != kind′)
    end
    @drive copy => γ0 * ifelse(mode > 0.5, sin(ω * mcs), ifelse(mcs < K, 1.0, -0.5)) * (position[target][2] - y0) *
                   direction[1] + η * direction[2] + u * direction[1]
    @constraint direction[1]^2 + direction[2]^2 <= R2
    @sweep Metropolis(; temperature = 3.0)
end))

@potts_model P64a1Ref begin
    @kinds medium A
    @parameters begin
        γ0 = 1.0
        y0 = 8.5
        K = 3.0
        mode = 0.0
        ω = 0.3
        η = 0.0
        u = 0.0
        R2 = 100.0
        L = 24.0
    end
    @variables begin
        px(site) = 0.0
        py(site) = 0.0
        G(model) = 0.0
    end
    @lattice Lattice((24, 16); boundary = (Periodic(), Closed()))
    @energy begin
        cells => (volume - 25.0)^2
        contacts => 4.0 * (kind != kind′)
    end
    @before_mcs G ~ ifelse(mode > 0.5, sin(ω * mcs), ifelse(mcs < K, 1.0, -0.5))
    @drive copy => γ0 * G * (py[target] - y0) *
                   ifelse(px[target] - px[source] > L / 2, px[target] - px[source] - L,
        ifelse(px[target] - px[source] < -L / 2, px[target] - px[source] + L, px[target] - px[source])) +
                   η * (py[target] - py[source]) +
                   u * ifelse(px[target] - px[source] > L / 2, px[target] - px[source] - L,
        ifelse(px[target] - px[source] < -L / 2, px[target] - px[source] + L, px[target] - px[source]))
    @constraint ifelse(px[target] - px[source] > L / 2, px[target] - px[source] - L,
        ifelse(px[target] - px[source] < -L / 2, px[target] - px[source] + L, px[target] - px[source]))^2 +
                (py[target] - py[source])^2 <= R2
    @sweep Metropolis(; temperature = 3.0)
end

const P64A1_PX = [Float64(x) for x in 1:24, y in 1:16]
const P64A1_PY = [Float64(y) for x in 1:24, y in 1:16]

"""Two 5×5 cells: one across the x seam (x 22:24 ∪ 1:2) in the lower half, one in the upper."""
p64a1_two() = (σ = zeros(Int32, P64A1_LAT); σ[22:24, 3:7] .= 1; σ[1:2, 3:7] .= 1; σ[10:14, 10:14] .= 2; σ)
"""One 5×5 cell across the x seam at mid-height."""
p64a1_one() = (σ = zeros(Int32, P64A1_LAT); σ[22:24, 7:11] .= 1; σ[1:2, 7:11] .= 1; σ)

function p64a1_problem(which::Symbol, σ; T = Float64, p = Pair{Symbol, Float64}[], seed = 11, tspan = (0, 8))
    nc = maximum(σ)
    op = which === :dir ? [ownership => σ, kind => fill(:A, nc)] :
         [ownership => σ, kind => fill(:A, nc), :px => P64A1_PX, :py => P64A1_PY]
    M = which === :dir ? p64a1_model(:P64a1Dir) : P64a1Ref
    prob = PottsProblem(M(; name = which), op, tspan; T, seed)
    return isempty(p) ? prob : remake(prob; p)
end

"""σ at every MCS and the accepted count."""
function p64a1_traj(prob, alg; kw...)
    sol = solve(prob, alg; saveat = 1, kw...)
    return ([Array(u.σ) for u in sol.u], sol.stats.accepted)
end

const P64A1_ALGS = [
    ("SequentialCPM(Moore(1))", SequentialCPM(; proposal = Moore(1))),
    ("SequentialCPM(VonNeumann(1))", SequentialCPM(; proposal = VonNeumann(1))),
    ("SequentialCPM(NeighborOrder(4))", SequentialCPM(; proposal = NeighborOrder(4))),
    ("CheckerboardCPM(Moore(1))", CheckerboardCPM(; proposal = Moore(1))),
    ("BoundarySiteCPM(Moore(1))", SequentialCPM(; skip_interior = true, proposal = Moore(1))),
]
const P64A1_DRIVES = [
    ("(a) reversal at mcs = K", Pair{Symbol, Float64}[]),
    ("(b) foam sin(ω·mcs)", [:mode => 1.0, :γ0 => 0.75]),
    ("(c) η·dy + u·dx", [:γ0 => 0.0, :η => 0.5, :u => -0.75]),
    ("(a) with diagonal copies forbidden", [:R2 => 1.5]),
]

@testset "P6.4a1: the reference's controls discriminate (no `direction`)" begin
    alg = SequentialCPM(; proposal = Moore(1))
    ref = p64a1_traj(p64a1_problem(:ref, p64a1_two()), alg)
    @test ref == p64a1_traj(p64a1_problem(:ref, p64a1_two()), alg)                       # determinism
    for (label, p) in (("no minimum image", [:L => 1.0e6]), ("opposite sign", [:γ0 => -1.0]),
        ("reversal one MCS later", [:K => 4.0]), ("diagonals forbidden", [:R2 => 1.5]))
        alt = p64a1_traj(p64a1_problem(:ref, p64a1_two(); p), alg)
        @test alt[1] != ref[1]
    end
    # the foam form and drive (c) move cells (the comparisons below are not of frozen states)
    for (_, p) in P64A1_DRIVES
        tr = p64a1_traj(p64a1_problem(:ref, p64a1_two(); p), alg)
        @test tr[2] > 10 && tr[1][end] != tr[1][1]
    end
end

@testset "P6.4a1: kernel path equals the reference, bitwise ($alabel; $dlabel)" for (alabel, alg) in P64A1_ALGS,
    (dlabel, p) in P64A1_DRIVES

    @test p64a1_traj(p64a1_problem(:dir, p64a1_two(); p), alg) == p64a1_traj(p64a1_problem(:ref, p64a1_two(); p), alg)
end

@testset "P6.4a1: kernel path equals the reference, bitwise (Float32, $dlabel)" for (dlabel, p) in P64A1_DRIVES
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        @test p64a1_traj(p64a1_problem(:dir, p64a1_two(); T = Float32, p), alg) ==
              p64a1_traj(p64a1_problem(:ref, p64a1_two(); T = Float32, p), alg)
    end
end

@testset "P6.4a1: on the device (Float32, CheckerboardCPM), $dlabel" for (dlabel, p) in P64A1_DRIVES
    if P64A1_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM(; proposal = Moore(1))
        a = p64a1_traj(p64a1_problem(:dir, p64a1_two(); T = Float32, p), alg; backend)
        b = p64a1_traj(p64a1_problem(:ref, p64a1_two(); T = Float32, p), alg; backend)
        @test a == b
        @test a[1][end] != a[1][1]
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end

# ---------------------------------------------------------------------------------------
# 3. Statistics: a uniform shear field drifts a single cell.

"""Centroid x of cell 1 on the periodic x axis (circular mean)."""
function p64a1_cx(σ)
    L = size(σ, 1)
    z = sum(cis(2π * (x - 1) / L) for x in axes(σ, 1), y in axes(σ, 2) if σ[x, y] == 1)
    return L * angle(z) / 2π
end

"""Net x drift of the cell over M MCS: the sum of minimum-image centroid increments."""
function p64a1_drift(prob, M)
    integ = init(prob, SequentialCPM(; proposal = Moore(1)); save_start = false, save_end = false)
    c = p64a1_cx(integ.u.σ)
    D = 0.0
    for _ in 1:M
        step!(integ)
        c2 = p64a1_cx(integ.u.σ)
        D += c2 - c - P64A1_LAT[1] * round((c2 - c) / P64A1_LAT[1])
        c = c2
    end
    return D
end

function p64a1_drifts(which, u, seeds)
    base = p64a1_problem(which, p64a1_one(); p = [:γ0 => 0.0, :u => u], tspan = (0, P64A1_M))
    return [p64a1_drift(remake(base; seed = s), P64A1_M) for s in seeds]
end
p64a1_z(D) = mean(D) / (std(D) / sqrt(length(D)))
p64a1_welch(a, b) = (mean(a) - mean(b)) / sqrt(var(a) / length(a) + var(b) / length(b))

@testset "P6.4a1: drift statistics, reference arms (no `direction`)" begin
    ref1 = p64a1_drifts(:ref, 1.0, 1001:1400)
    ref1b = p64a1_drifts(:ref, 1.0, 2001:2400)
    refh = p64a1_drifts(:ref, 0.5, 1001:1400)
    @info "P6.4a1 reference drift" u1 = (mean(ref1), std(ref1), p64a1_z(ref1)) u½ = (mean(refh), p64a1_z(refh))
    @test p64a1_z(ref1) < -P64A1_Z1 && -2.0 <= mean(ref1) <= -0.5
    @test abs(p64a1_welch(ref1, ref1b)) <= P64A1_Z2              # the two-sample test's null
    @test abs(p64a1_welch(ref1, refh)) > P64A1_Z2                # and its power at u = ½
end

@testset "P6.4a1: drift statistics (`direction`)" begin
    pos = p64a1_drifts(:dir, 1.0, 1:P64A1_R)
    neg = p64a1_drifts(:dir, -1.0, 1:P64A1_R)
    nul = p64a1_drifts(:dir, 0.0, 1:P64A1_R)
    ref1 = p64a1_drifts(:ref, 1.0, 1001:1400)
    refh = p64a1_drifts(:ref, 0.5, 1001:1400)
    @info "P6.4a1 drift" u1 = (mean(pos), p64a1_z(pos)) u_minus1 = (mean(neg), p64a1_z(neg)) u0 = (mean(nul), p64a1_z(nul)) welch =
        p64a1_welch(pos, ref1)
    @test p64a1_z(pos) < -P64A1_Z1                               # (a) sign
    @test p64a1_z(neg) > P64A1_Z1                                # (a) the opposite sign
    @test -2.0 <= mean(pos) <= -0.5                              # (b) rough magnitude
    @test 0.5 <= mean(neg) <= 2.0
    @test abs(p64a1_z(nul)) <= P64A1_Z2                          # (c) null
    @test abs(p64a1_welch(pos, ref1)) <= P64A1_Z2                # (d) the reference's law
    @test abs(p64a1_welch(pos, refh)) > P64A1_Z2                 # (d) control
end

# ---------------------------------------------------------------------------------------
# 4. Performance and the reference's records.

"""The gate's rule: the minimum allocation over five warm `step!`s, after two."""
function p64a1_warm_alloc(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    m = typemax(Int)
    for _ in 1:5
        m = min(m, @allocated step!(integ))
    end
    return m
end

@testset "P6.4a1: zero warm allocations ($alabel)" for (alabel, alg) in P64A1_ALGS
    prob = p64a1_problem(:dir, p64a1_two(); p = [:mode => 1.0], tspan = (0, 100))
    @test p64a1_warm_alloc(prob, alg) == 0
    @test p64a1_warm_alloc(p64a1_problem(:ref, p64a1_two(); p = [:mode => 1.0], tspan = (0, 100)), alg) == 0   # control
end

@testset "P6.4a1: zero warm allocations (3D probe)" begin
    base = p64a1_probe_problem(p64a1_model(:P64a1Probe3D), (5, 6, 5))
    prob = remake(base; p = [:a1 => 1.0, :a3 => -0.5, :bt => 0.25, :cs => 0.125], tspan = (0, 100))
    @test p64a1_warm_alloc(prob, SequentialCPM(; proposal = Moore(1))) == 0
end

# Recorded on the freeze base d7fc5793 (Apple M-series, Julia 1.12.6): `P64a1Ref`, drive (a),
# SequentialCPM(Moore(1)), seed 11, 8 MCS.
const P64A1_REF_FINGERPRINT = 0x07162920e1884e03
const P64A1_REF_SHA = "303638e662289649e5f884b16fa537d0c70ea7b0182d13040158d694442b7755"
const P64A1_REF_ACCEPTED = 55

@testset "P6.4a1: a model without `direction` is unchanged (recorded)" begin
    prob = p64a1_problem(:ref, p64a1_two())
    sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
    @test prob.f.fingerprint == P64A1_REF_FINGERPRINT
    @test bytes2hex(sha256(reinterpret(UInt8, vec(Array(sol.u[end].σ))))) == P64A1_REF_SHA
    @test sol.stats.accepted == P64A1_REF_ACCEPTED
end

# ---------------------------------------------------------------------------------------
# 5. The premise of deferring `Metropolis(tie)`: T = ε gives the T → 0⁺ limit.

@testset "P6.4a1: T = ε is the T → 0⁺ limit (Metropolis(tie) deferred)" begin
    law = CorePotts.Metropolis()
    for T in (Float64, Float32)
        ε = T(1.0e-6)
        draws = T[0, 1.0e-7, 0.25, 0.5, 0.75, prevfloat(one(T))]
        @test all(r -> CorePotts.accept(law, zero(T), ε, r), draws)            # ties: P = 1
        @test all(r -> CorePotts.accept(law, T(-1.0e-3), ε, r), draws)         # downhill
        @test !any(r -> CorePotts.accept(law, T(1.0e-3), ε, r), draws[2:end])  # uphill: P = 0
        @test !any(r -> CorePotts.accept(law, T(1), ε, r), draws)
        # control: T = 0 keeps the ½ tie rule, which is why the foam uses ε
        @test CorePotts.accept(law, zero(T), zero(T), T(0.25)) && !CorePotts.accept(law, zero(T), zero(T), T(0.75))
    end
end
