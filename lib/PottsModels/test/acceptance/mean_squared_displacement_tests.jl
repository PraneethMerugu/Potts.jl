# Initial state, part C of 3: the
# mean squared displacement and the modified Fürth fits (R16) in `PottsModels.Analysis`.
# Part A, `initial_state_tests.jl`: the initial-state vocabulary. Part B,
# `predicate_source_tests.jl`: the predicate-sourced PDE source.
#
# Spec: docs/design/research/p6-5c-brief.md §1.C, §3.C, §4.C, §4.D. Spec 14 §2.8
# (l.121–130); 14a-S1 §S1 (the fit procedure, steps i–vii) and §S3. Decisions: D-139 item 3
# (fits and MSD live in `PottsModels.Analysis`), D-200 / paper over code (the default fit is
# the paper's procedure), D-048 (oracles and negative controls).
#
#
# =========================================================================================
# THE PUBLIC API THESE TESTS EXPECT (brief §3.C; exported from `PottsModels.Analysis`)
# =========================================================================================
#
# A point is an `NTuple{N, <:Real}` (what `centroids` returns) or an `AbstractVector` of
# length N. Floats are Float64.
#
# C1. `unwrap_track(points, dims, periodic) -> Vector{NTuple{N, Float64}}`.
#     out[1] = points[1]; out[k] = out[k−1] + w(points[k] − points[k−1]), w the identity on
#     non-periodic axes and, on a periodic axis d, the minimum image in [−dims[d]/2,
#     dims[d]/2) (ties to the lower image, D-141). `periodic`: one Bool per axis or one Bool
#     for all. Precondition (documented, not detected): true displacements between samples
#     are below half the period. `ArgumentError`s: an empty track, mixed point dimensions,
#     length(dims) or length(periodic) ≠ N, a non-positive period.
# C2. `mean_squared_displacement(tracks; lags = 1:(n − 1)) -> Vector{Float64}`. `tracks` is
# one track (a vector of
#     points) or a vector of tracks of equal length n. MSD(ℓ) = the mean over tracks of
#     (1/(n − ℓ)) Σ_{i=1}^{n−ℓ} |x_{i+ℓ} − x_i|² (all components summed): OVERLAPPING
#     windows, replicas averaged with EQUAL weight (brief Q-4). `ArgumentError`s: ℓ < 1 or ℓ
#     ≥ n, unequal track lengths, no track, mixed dimensions.
# C3. `furth_mean_squared_displacement(Δt, S, D, P)`, Eq. 1 elementwise:
#         MSD(Δt) = 2D(Δt − P(1 − e^{−Δt/P})) + (2DS/(1−S))Δt.
#     `ArgumentError` unless 0 ≤ S < 1, D ≥ 0, P > 0.
# C4. `natural_units(Δt, m, fit) -> (τ, ρ²)`: τ = Δt/P, ρ² = m/(2DP/(1−S)) (Eq. 2); `fit`
#     any object with fields S, D, P.
# C5. `furth_fit(Δt, m; method = :paper, range = nothing, short = nothing, offset = true)`
#     -> `(; S, D, P, D_fast, D_slow, v_eff, offset, method)`.
#     On all lags: an `ArgumentError` for length < 4, non-finite values, a non-increasing
#     Δt.
#     - `method = :paper` (DEFAULT; 14a-S1 §S1): Δt uniformly spaced (relative 1e-9, else an
#       `ArgumentError`); second differences d_i = (m_{i+1} − 2m_i + m_{i−1})/h² at the
#       interior lags (`range` a (lo, hi) of Δt values, default all); keep d_i > 0; OLS of
#       log d_i = c₀ + c₁Δt_i gives P = −1/c₁, D = e^{c₀}P/2; fewer than 3 positive d_i or
#       c₁ ≥ 0 is the `ArgumentError` "furth_fit: no decaying second derivative (persistence
#       not resolved); try method = :lsq"; the residual r = m −
#       furth_mean_squared_displacement(Δt, 0, D, P) over `short` (default Δt ≤ P with at
#       least 2 points, else the first 2 lags); OLS r = 2D_fast·Δt + c (c = 0 when `offset =
#       false`), D_fast unclamped, `offset = c`; S = D_fast/(D_fast + D), D_slow = D +
#       D_fast, v_eff = √(D/P)/(1−S).
#     - `method = :lsq` (the cross-check): for fixed P, m ≈ a·g(Δt; P) + b·Δt (+ c), g = Δt
#       − P(1 − e^{−Δt/P}); min Σ((model − m)/m)² with a, b ≥ 0 (active sets; c free); P
#       over log P ∈ [log(Δt₁/10), log(100Δt_end)] on a 200-point grid, the best bracket
#       refined by golden section to a relative 1e-10, ties to the smaller P; D = a/2,
#       D_fast = b/2, D_slow = (a + b)/2 (DIRECTLY, not D/(1−S)), S = b/(a + b) (NaN if a +
#       b = 0). m ≤ 0 is an `ArgumentError` for `:lsq` (relative weights), allowed for
#       `:paper`.
#     Both deterministic (no RNG). Unit-agnostic.
#
# Oracles. Hand-computed MSDs (section 2), the closed-form Eq. 1 (noise-free fits, section
# 4) and an Ornstein–Uhlenbeck + Brownian generator whose expected MSD is Eq. 1 up to O(δ/P)
# = 1 % (section 5). The generator is the test's own (StableRNG), independent of the code.
#
# Calibration of section 5 (the brief's provisional tolerances), by the test author on the
# base commit with a stub that implements §3.C as written, 16 seeds (StableRNG(1:16)), 64
# tracks × 2·10⁴ samples, lags 1:400, S = 0.1, D = 0.5, P = 100:
#   `:lsq`   worst |ΔD/D| 5.9 %, |ΔP/P| 4.3 %, |ΔS| 0.0052  (targets ±10 %, ±10 %, ±0.02)
#   `:paper` worst |ΔD/D| 5.6 %, |ΔP/P| 16.4 %, |ΔS| 0.034  (targets ±20 %, ±20 %, ±0.04)
#   S = 0 data: `:lsq` S ≤ 2e-4 on every seed (`:paper` |S| up to 0.058, so the S = 0
#   control is pinned for `:lsq`, and for `:paper` only relative to the S = 0.1 fit).
#   Shuffled samples: the MSD is flat (m(400)/m(1) within 0.3 % of 1, against > 100 for the
#   ordered data), and no seed's fit meets the `:lsq` targets; the brief's "fitted P < 2"
#   held on 9 of 16 seeds only (P went to 57, 37, 11 or the 4·10⁴ upper bound on the
#   others), so it is not pinned (reported for a ruling).
# The seed is 14, chosen for margin under small interpretive differences in the
# `:paper` scheme (stub: `:lsq` +0.1 %, −0.6 %, −0.0006; `:paper` −1.3 %, −0.6 %, +0.0046);
# every one of the 16 seeds meets every target. Light tier: about 10 s.
#
# Sections: 1 names; 2 `unwrap_track`; 3 `mean_squared_displacement` by hand; 4 Eq. 1/2 and
# the noise-free fits; 5 the stochastic oracle; 6 input validation; 7 the paper's Table 2
# sanity; 8 docs.

@testsetup module MeanSquaredDisplacementSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using StableRNGs: StableRNG
using Random: shuffle
const DISPLACEMENT_A = PottsModels.Analysis
# the five functions, looked up at run time (absent on the base commit: each testset that
# needs them fails with the DEFECT CHECK below and errors at its first call)
has(n) = isdefined(DISPLACEMENT_A, n)
function displacement_unwrap_track(args...; kw...)
    return getfield(DISPLACEMENT_A, :unwrap_track)(
        args...;
        kw...
    )
end
msd(args...; kw...) = getfield(DISPLACEMENT_A, :mean_squared_displacement)(args...; kw...)
function furth_msd(args...; kw...)
    return getfield(
        DISPLACEMENT_A,
        :furth_mean_squared_displacement
    )(args...; kw...)
end
function displacement_furth_fit(args...; kw...)
    return getfield(DISPLACEMENT_A, :furth_fit)(
        args...;
        kw...
    )
end
function displacement_natural_units(args...; kw...)
    return getfield(
        DISPLACEMENT_A,
        :natural_units
    )(args...; kw...)
end
function displacement_msg(f)
    return try
        f()
        ""
    catch e
        e isa ArgumentError ? e.msg : ""
    end
end
# Eq. 1 written out (the test's own)
eq1(t; S, D, P) = 2D * (t - P * (1 - exp(-t / P))) + 2D * S / (1 - S) * t
# The generator (brief §4.C5), 2D, time unit = one sample, δ = 1. Per axis: an
# Ornstein–Uhlenbeck velocity of variance D/(2P) and correlation time P (exact AR(1),
# coefficient e^{−1/P}); x ← x + v·δ plus independent Brownian increments of variance
# D_fast·δ, D_fast = DS/(1 − S). E[MSD] is Eq. 1 up to O(δ/P).
function displacement_tracks(rng; S, D, P, n, ntracks)
    Df = D * S / (1 - S)
    a = exp(-1 / P)
    sv = sqrt(D / (2P))
    sb = sqrt(Df)
    tracks = Vector{Vector{NTuple{2, Float64}}}()
    for _ in 1:ntracks
        v = (sv * randn(rng), sv * randn(rng))
        x = (0.0, 0.0)
        tr = Vector{NTuple{2, Float64}}(undef, n)
        tr[1] = x
        for k in 2:n
            x = x .+ v .+ sb .* (randn(rng), randn(rng))
            v = a .* v .+ (sv * sqrt(1 - a^2)) .* (randn(rng), randn(rng))
            tr[k] = x
        end
        push!(tracks, tr)
    end
    return tracks
end
const KEYS = (:S, :D, :P, :D_fast, :D_slow, :v_eff, :offset, :method)
# ---------------------------------------------------------------------------------------
# 5. The stochastic oracle (brief §4.C5; calibration in the header)
const SEED = 14
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "initial state MSD/Fürth: the functions are exported from \
    PottsModels.Analysis" setup = [MeanSquaredDisplacementSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 1. Names
    @testset "initial state MSD/Fürth: the functions are exported from \
        PottsModels.Analysis" begin
        for n in (
                :unwrap_track, :mean_squared_displacement, :furth_fit,
                :furth_mean_squared_displacement, :natural_units,
            )
            @test Base.isexported(DISPLACEMENT_A, n)                        # DEFECT CHECK
        end
        @test Base.isexported(DISPLACEMENT_A, :centroids)                   # control
        # analysis-only: nothing in Potts (control today)
        @test !isdefined(Potts, :mean_squared_displacement) && !isdefined(Potts, :furth_fit)
    end
end

@testitem "initial state MSD/Fürth: unwrap_track by hand" setup = [
    MeanSquaredDisplacementSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 2. `unwrap_track` (brief §4.C1)
    @testset "initial state MSD/Fürth: unwrap_track by hand" begin
        @test has(:unwrap_track)                               # DEFECT CHECK
        pts = [(8.0, 3.0), (9.0, 3.0), (10.0, 3.0), (1.0, 3.0), (2.0, 3.0)]
        out = displacement_unwrap_track(pts, (10, 10), (true, false))
        @test out == [(8.0, 3.0), (9.0, 3.0), (10.0, 3.0), (11.0, 3.0), (12.0, 3.0)]
        @test out isa Vector{NTuple{2, Float64}}
        # the non-periodic axis is unchanged, even across a jump of more than half its width
        out2 = displacement_unwrap_track(
            [(8.0, 1.0), (9.0, 9.0), (10.0, 2.0)], (10, 10), (
                true, false,
            )
        )
        @test [p[2] for p in out2] == [1.0, 9.0, 2.0]
        # negative control: periodic = false leaves the wrap in
        @test displacement_unwrap_track(pts, (10, 10), false) == pts
        # one Bool for all axes
        @test displacement_unwrap_track(pts, (10, 10), true) == out
        # the [−L/2, L/2) convention: +5 on width 10 maps to −5; −5 stays −5
        @test displacement_unwrap_track([(1.0, 0.0), (6.0, 0.0)], (10, 10), true) ==
            [(1.0, 0.0), (-4.0, 0.0)]
        @test displacement_unwrap_track([(6.0, 0.0), (1.0, 0.0)], (10, 10), true) ==
            [(6.0, 0.0), (1.0, 0.0)]
        # a jump of 4.9 is kept, of 5.1 is wrapped
        @test displacement_unwrap_track([(1.0, 0.0), (5.9, 0.0)], (10, 10), true)[2][1] ≈
            5.9
        @test displacement_unwrap_track([(1.0, 0.0), (6.1, 0.0)], (10, 10), true)[2][1] ≈
            -3.9
        # vector points, 3D, a non-integer period
        out3 = displacement_unwrap_track(
            [[0.5, 0.0, 0.0], [7.0, 0.0, 0.0], [7.5, 0.0, 0.0]],
            (7.5, 4, 4), (true, false, false)
        )
        @test out3 isa Vector{NTuple{3, Float64}}
        @test [p[1] for p in out3] ≈ [0.5, -0.5, 0.0]
        # a single point
        @test displacement_unwrap_track([(3, 4)], (10, 10), true) == [(3.0, 4.0)]
    end
end

@testitem "initial state MSD/Fürth: unwrap_track errors" setup = [
    MeanSquaredDisplacementSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "initial state MSD/Fürth: unwrap_track errors" begin
        @test has(:unwrap_track)                               # DEFECT CHECK
        @test_throws ArgumentError displacement_unwrap_track(
            NTuple{2, Float64}[], (10, 10),
            true
        )
        @test_throws ArgumentError displacement_unwrap_track(
            Any[
                (1.0, 2.0), (
                    1.0, 2.0, 3.0,
                ),
            ], (10, 10), true
        )
        @test_throws ArgumentError displacement_unwrap_track(
            [(1.0, 2.0)], (10, 10, 10),
            true
        )
        @test_throws ArgumentError displacement_unwrap_track(
            [(1.0, 2.0)], (10, 10), (
                true, false, true,
            )
        )
        @test_throws ArgumentError displacement_unwrap_track([(1.0, 2.0)], (10, 0), true)
        @test_throws ArgumentError displacement_unwrap_track(
            [(1.0, 2.0)], (-3, 10), (
                true, false,
            )
        )
    end
end

@testitem "initial state MSD/Fürth: unwrap_track after centroids (a box crossing a \
    periodic edge)" setup = [MeanSquaredDisplacementSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "initial state MSD/Fürth: unwrap_track after centroids (a box crossing a \
        periodic edge)" begin
        # a 2×2 cell moving +1 in x per frame for 15 frames on a 10-wide periodic x axis
        σs = map(0:15) do t
            σ = zeros(Int32, 10, 6)
            for dx in 0:1, y in 3:4
                σ[mod1(2 + t + dx, 10), y] = 1
            end
            σ
        end
        cs = [only(DISPLACEMENT_A.centroids(σ; periodic = (true, false))) for σ in σs]
        # control: centroids wraps into [1, 11)
        @test all(c -> 1 <= c[1] < 11, cs)
        @test cs[1] == (2.5, 3.5)                                    # control
        # control: the raw track jumps back
        @test any(t -> cs[t + 1][1] < cs[t][1], 1:15)
        @test has(:unwrap_track)                               # DEFECT CHECK
        u = displacement_unwrap_track(cs, (10, 6), (true, false))
        @test u[end][1] - u[1][1] == 15.0
        @test all(t -> u[t + 1][1] - u[t][1] == 1.0, 1:15)
        @test all(p -> p[2] == 3.5, u)
    end
end

@testitem "initial state MSD/Fürth: mean_squared_displacement by hand (overlapping \
    windows, equal-weight replicas)" setup = [MeanSquaredDisplacementSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 3. `mean_squared_displacement` by hand (brief §4.C2)
    @testset "initial state MSD/Fürth: mean_squared_displacement by hand (overlapping \
        windows, equal-weight replicas)" begin
        # DEFECT CHECK
        @test has(:mean_squared_displacement)
        tr = [(0.0, 0.0), (1.0, 0.0), (3.0, 0.0), (6.0, 0.0)]
        m = msd(tr)
        # (1 + 4 + 9)/3, (9 + 25)/2, 36
        @test m ≈ [14 / 3, 17.0, 36.0] rtol = 1.0e-14
        @test m isa Vector{Float64}
        # negative control: non-overlapping windows would give MSD(2) = 9 (one window)
        @test !(m[2] ≈ 9.0)
        # its mirror: the same; the two together: the same (equal weights)
        mir = [(-p[1], p[2]) for p in tr]
        @test msd(mir) ≈ m rtol = 1.0e-14
        @test msd([tr, mir]) ≈ m rtol = 1.0e-14
        # ballistic x_k = (k, 0): ℓ² exactly
        bal = [(Float64(k), 0.0) for k in 0:9]
        @test msd(bal) == [Float64(l^2) for l in 1:9]
        # two different tracks: the mean of the per-track MSDs
        @test msd([tr, bal[1:4]]) ≈ ([14 / 3, 17.0, 36.0] .+ [1.0, 4.0, 9.0]) ./
            2 rtol = 1.0e-14
        # components are summed: a diagonal ballistic walk in 3D
        diag = [(Float64(k), Float64(k), Float64(k)) for k in 0:4]
        @test msd(diag) == [3.0 * l^2 for l in 1:4]
        # `lags` and vector points
        @test msd(tr; lags = [1, 3]) ≈ [14 / 3, 36.0] rtol = 1.0e-14
        @test msd([[p...] for p in tr]; lags = 2:2) ≈ [17.0] rtol = 1.0e-14
    end
end

@testitem "initial state MSD/Fürth: mean_squared_displacement errors" setup = [
    MeanSquaredDisplacementSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "initial state MSD/Fürth: mean_squared_displacement errors" begin
        # DEFECT CHECK
        @test has(:mean_squared_displacement)
        tr = [(0.0, 0.0), (1.0, 0.0), (3.0, 0.0), (6.0, 0.0)]
        @test_throws ArgumentError msd(tr; lags = 0:2)              # ℓ = 0
        @test_throws ArgumentError msd(tr; lags = [4])              # ℓ = n
        @test_throws ArgumentError msd([tr, tr[1:3]])               # unequal lengths
        @test_throws ArgumentError msd(Vector{NTuple{2, Float64}}[])   # no track
        # mixed dimensions
        @test_throws ArgumentError msd(Any[(0.0, 0.0), (1.0, 0.0, 0.0)])
    end
end

@testitem "initial state MSD/Fürth: furth_mean_squared_displacement and natural_units \
    (Eq. 1, Eq. 2)" setup = [MeanSquaredDisplacementSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 4. Eq. 1/2 and the noise-free fits (brief §4.C3, C4)
    @testset "initial state MSD/Fürth: furth_mean_squared_displacement and natural_units \
        (Eq. 1, Eq. 2)" begin
        # DEFECT CHECK
        @test has(:furth_mean_squared_displacement) && has(:natural_units)
        Δt = collect(1.0:2000.0)
        for (S, D, P) in ((0.1, 0.5, 100.0), (0.0, 2.0, 3.0), (0.9, 1.0e-3, 5000.0))
            m = furth_msd(Δt, S, D, P)
            @test m ≈ eq1.(Δt; S, D, P) rtol = 1.0e-12
            τ, ρ2 = displacement_natural_units(Δt, m, (; S, D, P))
            @test τ ≈ Δt ./ P rtol = 1.0e-14
            @test ρ2 ≈ τ .- (1 - S) .* (1 .- exp.(-τ)) rtol = 1.0e-12  # Eq. 2
        end
        # the limits: ballistic for Δt ≪ P (MSD ≈ (D/P)Δt² + 2D_fast Δt), diffusive for Δt ≫
        # P
        @test furth_msd([1.0e-3], 0.0, 0.5, 100.0)[1] ≈ 0.5 / 100 * 1.0e-6 rtol = 1.0e-4
        @test furth_msd([1.0e6], 0.0, 0.5, 100.0)[1] ≈ 2 * 0.5 *
            (1.0e6 - 100) rtol = 1.0e-12
        for bad in (
                (; S = 1.0, D = 0.5, P = 100.0), (; S = -0.1, D = 0.5, P = 100.0), (;
                    S = 0.1, D = -0.5, P = 100.0,
                ),
                (; S = 0.1, D = 0.5, P = 0.0),
            )
            @test_throws ArgumentError furth_msd(Δt, bad...)
        end
    end
end

@testitem "initial state MSD/Fürth: noise-free Eq. 1 is recovered (S = 0.1, D = 0.5, P = \
    100)" setup = [MeanSquaredDisplacementSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "initial state MSD/Fürth: noise-free Eq. 1 is recovered (S = 0.1, D = 0.5, P \
        = 100)" begin
        @test has(:furth_fit)                                  # DEFECT CHECK
        Δt = collect(1.0:2000.0)
        m = eq1.(Δt; S = 0.1, D = 0.5, P = 100.0)
        # the default is the paper's procedure
        fp = displacement_furth_fit(Δt, m)
        @test fp.method === :paper
        @test keys(fp) == KEYS
        @test fp == displacement_furth_fit(Δt, m; method = :paper)
        @test fp.S ≈ 0.1 rtol = 1.0e-3
        @test fp.D ≈ 0.5 rtol = 1.0e-3
        @test fp.P ≈ 100.0 rtol = 1.0e-3
        @test abs(fp.offset) < 1.0e-2
        fl = displacement_furth_fit(Δt, m; method = :lsq)
        @test fl.method === :lsq && keys(fl) == KEYS
        @test fl.S ≈ 0.1 rtol = 1.0e-6
        @test fl.D ≈ 0.5 rtol = 1.0e-6
        # the golden-section refinement is load-bearing
        @test fl.P ≈ 100.0 rtol = 1.0e-6
        # the derived fields (both methods)
        for f in (fp, fl)
            @test f.D_slow ≈ f.D + f.D_fast rtol = 1.0e-12
            @test f.S ≈ f.D_fast / (f.D_fast + f.D) rtol = 1.0e-12
            @test f.v_eff ≈ sqrt(f.D / f.P) / (1 - f.S) rtol = 1.0e-12
            @test f.D_fast ≈ 0.5 * 0.1 / 0.9 rtol = (f.method === :lsq ? 1.0e-6 : 1.0e-2)
        end
        # `offset = false` fits the residual line through the origin (the noise-free data
        # has none)
        f0 = displacement_furth_fit(Δt, m; offset = false)
        @test f0.offset == 0
        @test f0.S ≈ 0.1 rtol = 1.0e-2
        # natural units of the data with the fit: Eq. 2
        τ, ρ2 = displacement_natural_units(Δt, m, fl)
        @test ρ2 ≈ τ .- (1 - 0.1) .* (1 .- exp.(-τ)) rtol = 1.0e-5
        # deterministic
        @test displacement_furth_fit(Δt, m; method = :lsq) == fl
    end
end

@testitem "initial state MSD/Fürth: ballistic and pure-diffusion limits" setup = [
    MeanSquaredDisplacementSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "initial state MSD/Fürth: ballistic and pure-diffusion limits" begin
        @test has(:furth_fit)                                  # DEFECT CHECK
        Δt = collect(1.0:2000.0)
        # ballistic m = (0.3Δt)²: no fast diffusion (a, b ≥ 0), P at the upper bound
        bal = (0.3 .* Δt) .^ 2
        fb = displacement_furth_fit(Δt, bal; method = :lsq)
        @test 0 <= fb.S <= 1.0e-6
        @test fb.P >= 100 * 2000 * (1 - 1.0e-9)
        @test fb.v_eff ≈ 0.3 rtol = 5.0e-3
        # `:paper`: the second derivative is constant, so either P ≥ 10·Δt_end or the
        # "persistence not resolved" error (the sign of c₁ is rounding)
        pb = try
            displacement_furth_fit(Δt, bal; method = :paper)
        catch e
            e
        end
        @test (pb isa NamedTuple && pb.P >= 10 * 2000) || (pb isa ArgumentError)
        # pure diffusion m = 1.4Δt: D_slow = 0.7 (S and P are not identifiable: not
        # asserted)
        fd = displacement_furth_fit(Δt, 1.4 .* Δt; method = :lsq)
        @test fd.D_slow ≈ 0.7 rtol = 1.0e-6
        # `:paper` cannot resolve a persistence
        @test_throws ArgumentError displacement_furth_fit(Δt, 1.4 .* Δt; method = :paper)
        @test_throws ArgumentError displacement_furth_fit(Δt, 1.4 .* Δt)
    end
end

@testitem "initial state MSD/Fürth: OU + Brownian tracks recover (S, D, P)" setup = [
    MeanSquaredDisplacementSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "initial state MSD/Fürth: OU + Brownian tracks recover (S, D, P)" begin
        @test has(:mean_squared_displacement) && has(:furth_fit)              # DEFECT CHECK
        lags = 1:400
        Δt = Float64.(lags)
        tracks = displacement_tracks(
            StableRNG(SEED); S = 0.1, D = 0.5, P = 100.0, n = 20_000, ntracks = 64
        )
        m = msd(tracks; lags)
        # the estimator is the test's own sum on one lag (independent recomputation)
        l = 37
        @test m[l] ≈
            sum(
            sum(sum(abs2, t[i + l] .- t[i]) for i in 1:(length(t) - l)) /
                (length(t) - l) for t in tracks
        ) / 64 rtol = 1.0e-12
        # the expected MSD is Eq. 1 within the sampling error (a sanity check of the
        # generator)
        @test maximum(abs.(m ./ eq1.(Δt; S = 0.1, D = 0.5, P = 100.0) .- 1)) < 0.1
        fl = displacement_furth_fit(Δt, m; method = :lsq)
        @test abs(fl.D / 0.5 - 1) <= 0.1
        @test abs(fl.P / 100 - 1) <= 0.1
        @test abs(fl.S - 0.1) <= 0.02
        fp = displacement_furth_fit(Δt, m; method = :paper)
        @test abs(fp.D / 0.5 - 1) <= 0.2
        @test abs(fp.P / 100 - 1) <= 0.2
        @test abs(fp.S - 0.1) <= 0.04
        # negative control: S = 0 data (no Brownian part)
        t0 = displacement_tracks(
            StableRNG(1000 + SEED); S = 0.0, D = 0.5, P = 100.0, n = 20_000, ntracks = 64
        )
        m0 = msd(t0; lags)
        f0 = displacement_furth_fit(Δt, m0; method = :lsq)
        @test f0.S < 0.02
        # `:paper`: below the S = 0.1 fit
        @test displacement_furth_fit(Δt, m0; method = :paper).S < fp.S
        # negative control: shuffling the sample order destroys the persistence: a flat MSD
        # and a fit that misses the targets
        rng = StableRNG(2000 + SEED)
        ms = msd([shuffle(rng, t) for t in tracks]; lags)
        @test abs(ms[end] / ms[1] - 1) < 0.01 && m[end] / m[1] > 100
        fs = displacement_furth_fit(Δt, ms; method = :lsq)
        @test !(
            abs(fs.D / 0.5 - 1) <= 0.1 && abs(fs.P / 100 - 1) <= 0.1 &&
                abs(fs.S - 0.1) <= 0.02
        )
    end
end

@testitem "initial state MSD/Fürth: furth_fit input validation" setup = [
    MeanSquaredDisplacementSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 6. Input validation (brief §3.C5)
    @testset "initial state MSD/Fürth: furth_fit input validation" begin
        @test has(:furth_fit)                                  # DEFECT CHECK
        Δt = collect(1.0:10.0)
        m = eq1.(Δt; S = 0.1, D = 0.5, P = 3.0)
        for method in (:paper, :lsq)
            # length < 4
            @test_throws ArgumentError displacement_furth_fit(Δt[1:3], m[1:3]; method)
            # non-finite
            @test_throws ArgumentError displacement_furth_fit(Δt, [m[1:9]; NaN]; method)
            @test_throws ArgumentError displacement_furth_fit([Δt[1:9]; Inf], m; method)
            # not increasing
            @test_throws ArgumentError displacement_furth_fit(
                [1.0, 2.0, 2.0, 3.0], m[1:4];
                method
            )
            # lengths differ
            @test_throws ArgumentError displacement_furth_fit(Δt[1:9], m; method)
        end
        # `:paper` needs a uniform spacing; `:lsq` does not
        tn = [1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 21.0, 34.0]
        mn = eq1.(tn; S = 0.1, D = 0.5, P = 5.0)
        @test_throws ArgumentError displacement_furth_fit(tn, mn; method = :paper)
        @test displacement_furth_fit(tn, mn; method = :lsq).P ≈ 5.0 rtol = 1.0e-6
        # m ≤ 0: an error for `:lsq` (relative weights), allowed for `:paper`
        mz = copy(m)
        mz[1] = 0.0
        @test_throws ArgumentError displacement_furth_fit(Δt, mz; method = :lsq)
        @test displacement_furth_fit(Δt, mz; method = :paper) isa NamedTuple
        # an unknown method
        @test_throws ArgumentError displacement_furth_fit(Δt, m; method = :fourier)
    end
end

@testitem "initial state MSD/Fürth: natural_units with Table 2's R = 15, φ = 0.10, λ = \
    150 row" setup = [MeanSquaredDisplacementSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 7. The paper's numbers, sanity only (brief §4.C6; guards the formula, not the table)
    @testset "initial state MSD/Fürth: natural_units with Table 2's R = 15, φ = 0.10, λ = \
        150 row" begin
        fit = (; P = 6878.0, D = 2.83e-4, S = 9.68e-3)
        # control (arithmetic)
        @test 2 * fit.D * fit.P / (1 - fit.S) ≈ 3.931 rtol = 1.0e-3
        @test has(:natural_units)                              # DEFECT CHECK
        Δt = [6878.0, 2 * 6878.0]
        m = [1.0, 2.0]
        τ, ρ2 = displacement_natural_units(Δt, m, fit)
        @test τ == [1.0, 2.0]
        @test round(m[1] / ρ2[1]; sigdigits = 4) == 3.931             # 2DP/(1 − S)
    end
end

@testitem "initial state MSD/Fürth: the analysis manual names mean_squared_displacement \
    and furth_fit" setup = [MeanSquaredDisplacementSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 8. Docs (brief §4.D)
    @testset "initial state MSD/Fürth: the analysis manual names \
        mean_squared_displacement and furth_fit" begin
        md = read(
            joinpath(
                @__DIR__, "..", "..", "..", "..", "docs", "src", "manual", "analysis.md"
            ), String
        )
        # control: the page exists
        @test occursin("centroids", md) || occursin("Analysis", md)
        # DEFECT CHECK
        @test occursin("mean_squared_displacement", md) && occursin("furth_fit", md)
    end
end
