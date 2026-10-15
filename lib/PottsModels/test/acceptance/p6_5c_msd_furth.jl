# P6.5c (ROADMAP Phase 6, step 5; third step of Fortuna, reproduction 14), part C of 3: the
# mean squared displacement and the modified Fürth fits (R16) in `PottsModels.Analysis`.
# Frozen (AUTONOMY §7.3).
# Part A, `p6_5c_initial_state.jl`: the initial-state vocabulary. Part B,
# `p6_5c_predicate_source.jl`: the predicate-sourced PDE source.
#
# Spec: docs/design/research/p6-5c-brief.md §1.C, §3.C, §4.C, §4.D. Spec 14 §2.8
# (l.121–130); 14a-S1 §S1 (the fit procedure, steps i–vii) and §S3. Decisions: D-139 item 3
# (fits and MSD live in `PottsModels.Analysis`), D-200 / paper over code (the default fit is
# the paper's procedure), D-048 (oracles and negative controls).
#
# ROADMAP (P6.5c row): "R16 MSD / Fürth fits".
#
# =========================================================================================
# THE PUBLIC API THESE TESTS EXPECT (brief §3.C; exported from `PottsModels.Analysis`)
# =========================================================================================
#
# A point is an `NTuple{N, <:Real}` (what `centroids` returns) or an `AbstractVector` of
# length N. Floats are Float64.
#
# C1. `unwrap_track(points, dims; periodic) -> Vector{NTuple{N, Float64}}`.
#     out[1] = points[1]; out[k] = out[k−1] + w(points[k] − points[k−1]), w the identity on
#     non-periodic axes and, on a periodic axis d, the minimum image in [−dims[d]/2,
#     dims[d]/2) (ties to the lower image, D-141). `periodic`: one Bool per axis or one Bool
#     for all. Precondition (documented, not detected): true displacements between samples
#     are below half the period. `ArgumentError`s: an empty track, mixed point dimensions,
#     length(dims) or length(periodic) ≠ N, a non-positive period.
# C2. `msd(tracks; lags = 1:(n − 1)) -> Vector{Float64}`. `tracks` is one track (a vector of
#     points) or a vector of tracks of equal length n. MSD(ℓ) = the mean over tracks of
#     (1/(n − ℓ)) Σ_{i=1}^{n−ℓ} |x_{i+ℓ} − x_i|² (all components summed): OVERLAPPING windows,
#     replicas averaged with EQUAL weight (brief Q-4). `ArgumentError`s: ℓ < 1 or ℓ ≥ n,
#     unequal track lengths, no track, mixed dimensions.
# C3. `furth_msd(Δt; S, D, P)`, Eq. 1 elementwise:
#         MSD(Δt) = 2D(Δt − P(1 − e^{−Δt/P})) + (2DS/(1−S))Δt.
#     `ArgumentError` unless 0 ≤ S < 1, D ≥ 0, P > 0.
# C4. `natural_units(Δt, m, fit) -> (τ, ρ²)`: τ = Δt/P, ρ² = m/(2DP/(1−S)) (Eq. 2); `fit`
#     any object with fields S, D, P.
# C5. `furth_fit(Δt, m; method = :paper, range = nothing, short = nothing, offset = true)`
#     -> `(; S, D, P, D_fast, D_slow, v_eff, offset, method)`.
#     On all lags: an `ArgumentError` for length < 4, non-finite values, a non-increasing Δt.
#     - `method = :paper` (DEFAULT; 14a-S1 §S1): Δt uniformly spaced (relative 1e-9, else an
#       `ArgumentError`); second differences d_i = (m_{i+1} − 2m_i + m_{i−1})/h² at the
#       interior lags (`range` a (lo, hi) of Δt values, default all); keep d_i > 0; OLS of
#       log d_i = c₀ + c₁Δt_i gives P = −1/c₁, D = e^{c₀}P/2; fewer than 3 positive d_i or
#       c₁ ≥ 0 is the `ArgumentError` "furth_fit: no decaying second derivative (persistence
#       not resolved); try method = :lsq"; the residual r = m − furth_msd(Δt; S = 0, D, P)
#       over `short` (default Δt ≤ P with at least 2 points, else the first 2 lags); OLS
#       r = 2D_fast·Δt + c (c = 0 when `offset = false`), D_fast unclamped, `offset = c`;
#       S = D_fast/(D_fast + D), D_slow = D + D_fast, v_eff = √(D/P)/(1−S).
#     - `method = :lsq` (the cross-check): for fixed P, m ≈ a·g(Δt; P) + b·Δt (+ c), g = Δt −
#       P(1 − e^{−Δt/P}); min Σ((model − m)/m)² with a, b ≥ 0 (active sets; c free); P over
#       log P ∈ [log(Δt₁/10), log(100Δt_end)] on a 200-point grid, the best bracket refined
#       by golden section to a relative 1e-10, ties to the smaller P; D = a/2, D_fast = b/2,
#       D_slow = (a + b)/2 (DIRECTLY, not D/(1−S)), S = b/(a + b) (NaN if a + b = 0).
#       m ≤ 0 is an `ArgumentError` for `:lsq` (relative weights), allowed for `:paper`.
#     Both deterministic (no RNG). Unit-agnostic.
#
# Oracles. Hand-computed MSDs (section 2), the closed-form Eq. 1 (noise-free fits, section
# 4) and an Ornstein–Uhlenbeck + Brownian generator whose expected MSD is Eq. 1 up to O(δ/P)
# = 1 % (section 5). The generator is the test's own (StableRNG), independent of the code.
#
# Calibration of section 5 (the brief's provisional tolerances), by the test author on the
# freeze base with a stub that implements §3.C as written, 16 seeds (StableRNG(1:16)), 64
# tracks × 2·10⁴ samples, lags 1:400, S = 0.1, D = 0.5, P = 100:
#   `:lsq`   worst |ΔD/D| 5.9 %, |ΔP/P| 4.3 %, |ΔS| 0.0052  (targets ±10 %, ±10 %, ±0.02)
#   `:paper` worst |ΔD/D| 5.6 %, |ΔP/P| 16.4 %, |ΔS| 0.034  (targets ±20 %, ±20 %, ±0.04)
#   S = 0 data: `:lsq` S ≤ 2e-4 on every seed (`:paper` |S| up to 0.058, so the S = 0 control
#   is pinned for `:lsq`, and for `:paper` only relative to the S = 0.1 fit).
#   Shuffled samples: the MSD is flat (m(400)/m(1) within 0.3 % of 1, against > 100 for the
#   ordered data), and no seed's fit meets the `:lsq` targets; the brief's "fitted P < 2"
#   held on 9 of 16 seeds only (P went to 57, 37, 11 or the 4·10⁴ upper bound on the others),
#   so it is not pinned (reported for a ruling).
# The frozen seed is 14, chosen for margin under small interpretive differences in the
# `:paper` scheme (stub: `:lsq` +0.1 %, −0.6 %, −0.0006; `:paper` −1.3 %, −0.6 %, +0.0046);
# every one of the 16 seeds meets every target. Light tier: about 10 s.
#
# Sections: 1 names; 2 `unwrap_track`; 3 `msd` by hand; 4 Eq. 1/2 and the noise-free fits;
# 5 the stochastic oracle; 6 input validation; 7 the paper's Table 2 sanity; 8 docs.
using Test, Potts, PottsModels
using StableRNGs: StableRNG
using Random: shuffle

const P65CC_A = PottsModels.Analysis

# the five functions, looked up at run time (absent on the freeze base: each testset that
# needs them fails with the DEFECT CHECK below and errors at its first call)
p65cc_has(n) = isdefined(P65CC_A, n)
p65cc_unwrap_track(args...; kw...) = getfield(P65CC_A, :unwrap_track)(args...; kw...)
p65cc_msd(args...; kw...) = getfield(P65CC_A, :msd)(args...; kw...)
p65cc_furth_msd(args...; kw...) = getfield(P65CC_A, :furth_msd)(args...; kw...)
p65cc_furth_fit(args...; kw...) = getfield(P65CC_A, :furth_fit)(args...; kw...)
p65cc_natural_units(args...; kw...) = getfield(P65CC_A, :natural_units)(args...; kw...)

p65cc_msg(f) = try
    f()
    ""
catch e
    e isa ArgumentError ? e.msg : ""
end

# Eq. 1 written out (the test's own)
p65cc_eq1(t; S, D, P) = 2D * (t - P * (1 - exp(-t / P))) + 2D * S / (1 - S) * t

# The generator (brief §4.C5), 2D, time unit = one sample, δ = 1. Per axis: an
# Ornstein–Uhlenbeck velocity of variance D/(2P) and correlation time P (exact AR(1),
# coefficient e^{−1/P}); x ← x + v·δ plus independent Brownian increments of variance
# D_fast·δ, D_fast = DS/(1 − S). E[MSD] is Eq. 1 up to O(δ/P).
function p65cc_tracks(rng; S, D, P, n, ntracks)
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

const P65CC_KEYS = (:S, :D, :P, :D_fast, :D_slow, :v_eff, :offset, :method)

# ---------------------------------------------------------------------------------------
# 1. Names

@testset "P6.5c MSD/Fürth: the functions are exported from PottsModels.Analysis" begin
    for n in (:unwrap_track, :msd, :furth_fit, :furth_msd, :natural_units)
        @test Base.isexported(P65CC_A, n)                        # DEFECT CHECK
    end
    @test Base.isexported(P65CC_A, :centroids)                   # control
    @test !isdefined(Potts, :msd) && !isdefined(Potts, :furth_fit)   # analysis-only: nothing in Potts (control today)
end

# ---------------------------------------------------------------------------------------
# 2. `unwrap_track` (brief §4.C1)

@testset "P6.5c MSD/Fürth: unwrap_track by hand" begin
    @test p65cc_has(:unwrap_track)                               # DEFECT CHECK
    pts = [(8.0, 3.0), (9.0, 3.0), (10.0, 3.0), (1.0, 3.0), (2.0, 3.0)]
    out = p65cc_unwrap_track(pts, (10, 10); periodic = (true, false))
    @test out == [(8.0, 3.0), (9.0, 3.0), (10.0, 3.0), (11.0, 3.0), (12.0, 3.0)]
    @test out isa Vector{NTuple{2, Float64}}
    # the non-periodic axis is unchanged, even across a jump of more than half its width
    out2 = p65cc_unwrap_track([(8.0, 1.0), (9.0, 9.0), (10.0, 2.0)], (10, 10); periodic = (true, false))
    @test [p[2] for p in out2] == [1.0, 9.0, 2.0]
    # negative control: periodic = false leaves the wrap in
    @test p65cc_unwrap_track(pts, (10, 10); periodic = false) == pts
    # one Bool for all axes
    @test p65cc_unwrap_track(pts, (10, 10); periodic = true) == out
    # the [−L/2, L/2) convention: +5 on width 10 maps to −5; −5 stays −5
    @test p65cc_unwrap_track([(1.0, 0.0), (6.0, 0.0)], (10, 10); periodic = true) == [(1.0, 0.0), (-4.0, 0.0)]
    @test p65cc_unwrap_track([(6.0, 0.0), (1.0, 0.0)], (10, 10); periodic = true) == [(6.0, 0.0), (1.0, 0.0)]
    # a jump of 4.9 is kept, of 5.1 is wrapped
    @test p65cc_unwrap_track([(1.0, 0.0), (5.9, 0.0)], (10, 10); periodic = true)[2][1] ≈ 5.9
    @test p65cc_unwrap_track([(1.0, 0.0), (6.1, 0.0)], (10, 10); periodic = true)[2][1] ≈ -3.9
    # vector points, 3D, a non-integer period
    out3 = p65cc_unwrap_track([[0.5, 0.0, 0.0], [7.0, 0.0, 0.0], [7.5, 0.0, 0.0]], (7.5, 4, 4); periodic = (true, false, false))
    @test out3 isa Vector{NTuple{3, Float64}}
    @test [p[1] for p in out3] ≈ [0.5, -0.5, 0.0]
    # a single point
    @test p65cc_unwrap_track([(3, 4)], (10, 10); periodic = true) == [(3.0, 4.0)]
end

@testset "P6.5c MSD/Fürth: unwrap_track errors" begin
    @test p65cc_has(:unwrap_track)                               # DEFECT CHECK
    @test_throws ArgumentError p65cc_unwrap_track(NTuple{2, Float64}[], (10, 10); periodic = true)
    @test_throws ArgumentError p65cc_unwrap_track(Any[(1.0, 2.0), (1.0, 2.0, 3.0)], (10, 10); periodic = true)
    @test_throws ArgumentError p65cc_unwrap_track([(1.0, 2.0)], (10, 10, 10); periodic = true)
    @test_throws ArgumentError p65cc_unwrap_track([(1.0, 2.0)], (10, 10); periodic = (true, false, true))
    @test_throws ArgumentError p65cc_unwrap_track([(1.0, 2.0)], (10, 0); periodic = true)
    @test_throws ArgumentError p65cc_unwrap_track([(1.0, 2.0)], (-3, 10); periodic = (true, false))
end

@testset "P6.5c MSD/Fürth: unwrap_track after centroids (a box crossing a periodic edge)" begin
    # a 2×2 cell moving +1 in x per frame for 15 frames on a 10-wide periodic x axis
    σs = map(0:15) do t
        σ = zeros(Int32, 10, 6)
        for dx in 0:1, y in 3:4
            σ[mod1(2 + t + dx, 10), y] = 1
        end
        σ
    end
    cs = [only(P65CC_A.centroids(σ; periodic = (true, false))) for σ in σs]
    @test all(c -> 1 <= c[1] < 11, cs)                           # control: centroids wraps into [1, 11)
    @test cs[1] == (2.5, 3.5)                                    # control
    @test any(t -> cs[t + 1][1] < cs[t][1], 1:15)                # control: the raw track jumps back
    @test p65cc_has(:unwrap_track)                               # DEFECT CHECK
    u = p65cc_unwrap_track(cs, (10, 6); periodic = (true, false))
    @test u[end][1] - u[1][1] == 15.0
    @test all(t -> u[t + 1][1] - u[t][1] == 1.0, 1:15)
    @test all(p -> p[2] == 3.5, u)
end

# ---------------------------------------------------------------------------------------
# 3. `msd` by hand (brief §4.C2)

@testset "P6.5c MSD/Fürth: msd by hand (overlapping windows, equal-weight replicas)" begin
    @test p65cc_has(:msd)                                        # DEFECT CHECK
    tr = [(0.0, 0.0), (1.0, 0.0), (3.0, 0.0), (6.0, 0.0)]
    m = p65cc_msd(tr)
    @test m ≈ [14 / 3, 17.0, 36.0] rtol = 1e-14                  # (1 + 4 + 9)/3, (9 + 25)/2, 36
    @test m isa Vector{Float64}
    # negative control: non-overlapping windows would give MSD(2) = 9 (one window)
    @test !(m[2] ≈ 9.0)
    # its mirror: the same; the two together: the same (equal weights)
    mir = [(-p[1], p[2]) for p in tr]
    @test p65cc_msd(mir) ≈ m rtol = 1e-14
    @test p65cc_msd([tr, mir]) ≈ m rtol = 1e-14
    # ballistic x_k = (k, 0): ℓ² exactly
    bal = [(Float64(k), 0.0) for k in 0:9]
    @test p65cc_msd(bal) == [Float64(l^2) for l in 1:9]
    # two different tracks: the mean of the per-track MSDs
    @test p65cc_msd([tr, bal[1:4]]) ≈ ([14 / 3, 17.0, 36.0] .+ [1.0, 4.0, 9.0]) ./ 2 rtol = 1e-14
    # components are summed: a diagonal ballistic walk in 3D
    diag = [(Float64(k), Float64(k), Float64(k)) for k in 0:4]
    @test p65cc_msd(diag) == [3.0 * l^2 for l in 1:4]
    # `lags` and vector points
    @test p65cc_msd(tr; lags = [1, 3]) ≈ [14 / 3, 36.0] rtol = 1e-14
    @test p65cc_msd([[p...] for p in tr]; lags = 2:2) ≈ [17.0] rtol = 1e-14
end

@testset "P6.5c MSD/Fürth: msd errors" begin
    @test p65cc_has(:msd)                                        # DEFECT CHECK
    tr = [(0.0, 0.0), (1.0, 0.0), (3.0, 0.0), (6.0, 0.0)]
    @test_throws ArgumentError p65cc_msd(tr; lags = 0:2)              # ℓ = 0
    @test_throws ArgumentError p65cc_msd(tr; lags = [4])              # ℓ = n
    @test_throws ArgumentError p65cc_msd([tr, tr[1:3]])               # unequal lengths
    @test_throws ArgumentError p65cc_msd(Vector{NTuple{2, Float64}}[])   # no track
    @test_throws ArgumentError p65cc_msd(Any[(0.0, 0.0), (1.0, 0.0, 0.0)])   # mixed dimensions
end

# ---------------------------------------------------------------------------------------
# 4. Eq. 1/2 and the noise-free fits (brief §4.C3, C4)

@testset "P6.5c MSD/Fürth: furth_msd and natural_units (Eq. 1, Eq. 2)" begin
    @test p65cc_has(:furth_msd) && p65cc_has(:natural_units)     # DEFECT CHECK
    Δt = collect(1.0:2000.0)
    for (S, D, P) in ((0.1, 0.5, 100.0), (0.0, 2.0, 3.0), (0.9, 1e-3, 5000.0))
        m = p65cc_furth_msd(Δt; S, D, P)
        @test m ≈ p65cc_eq1.(Δt; S, D, P) rtol = 1e-12
        τ, ρ2 = p65cc_natural_units(Δt, m, (; S, D, P))
        @test τ ≈ Δt ./ P rtol = 1e-14
        @test ρ2 ≈ τ .- (1 - S) .* (1 .- exp.(-τ)) rtol = 1e-12  # Eq. 2
    end
    # the limits: ballistic for Δt ≪ P (MSD ≈ (D/P)Δt² + 2D_fast Δt), diffusive for Δt ≫ P
    @test p65cc_furth_msd([1e-3]; S = 0.0, D = 0.5, P = 100.0)[1] ≈ 0.5 / 100 * 1e-6 rtol = 1e-4
    @test p65cc_furth_msd([1e6]; S = 0.0, D = 0.5, P = 100.0)[1] ≈ 2 * 0.5 * (1e6 - 100) rtol = 1e-12
    for bad in ((; S = 1.0, D = 0.5, P = 100.0), (; S = -0.1, D = 0.5, P = 100.0), (; S = 0.1, D = -0.5, P = 100.0),
            (; S = 0.1, D = 0.5, P = 0.0))
        @test_throws ArgumentError p65cc_furth_msd(Δt; bad...)
    end
end

@testset "P6.5c MSD/Fürth: noise-free Eq. 1 is recovered (S = 0.1, D = 0.5, P = 100)" begin
    @test p65cc_has(:furth_fit)                                  # DEFECT CHECK
    Δt = collect(1.0:2000.0)
    m = p65cc_eq1.(Δt; S = 0.1, D = 0.5, P = 100.0)
    fp = p65cc_furth_fit(Δt, m)                                       # the default is the paper's procedure
    @test fp.method === :paper
    @test keys(fp) == P65CC_KEYS
    @test fp == p65cc_furth_fit(Δt, m; method = :paper)
    @test fp.S ≈ 0.1 rtol = 1e-3
    @test fp.D ≈ 0.5 rtol = 1e-3
    @test fp.P ≈ 100.0 rtol = 1e-3
    @test abs(fp.offset) < 1e-2
    fl = p65cc_furth_fit(Δt, m; method = :lsq)
    @test fl.method === :lsq && keys(fl) == P65CC_KEYS
    @test fl.S ≈ 0.1 rtol = 1e-6
    @test fl.D ≈ 0.5 rtol = 1e-6
    @test fl.P ≈ 100.0 rtol = 1e-6                               # the golden-section refinement is load-bearing
    # the derived fields (both methods)
    for f in (fp, fl)
        @test f.D_slow ≈ f.D + f.D_fast rtol = 1e-12
        @test f.S ≈ f.D_fast / (f.D_fast + f.D) rtol = 1e-12
        @test f.v_eff ≈ sqrt(f.D / f.P) / (1 - f.S) rtol = 1e-12
        @test f.D_fast ≈ 0.5 * 0.1 / 0.9 rtol = (f.method === :lsq ? 1e-6 : 1e-2)
    end
    # `offset = false` fits the residual line through the origin (the noise-free data has none)
    f0 = p65cc_furth_fit(Δt, m; offset = false)
    @test f0.offset == 0
    @test f0.S ≈ 0.1 rtol = 1e-2
    # natural units of the data with the fit: Eq. 2
    τ, ρ2 = p65cc_natural_units(Δt, m, fl)
    @test ρ2 ≈ τ .- (1 - 0.1) .* (1 .- exp.(-τ)) rtol = 1e-5
    # deterministic
    @test p65cc_furth_fit(Δt, m; method = :lsq) == fl
end

@testset "P6.5c MSD/Fürth: ballistic and pure-diffusion limits" begin
    @test p65cc_has(:furth_fit)                                  # DEFECT CHECK
    Δt = collect(1.0:2000.0)
    # ballistic m = (0.3Δt)²: no fast diffusion (a, b ≥ 0), P at the upper bound
    bal = (0.3 .* Δt) .^ 2
    fb = p65cc_furth_fit(Δt, bal; method = :lsq)
    @test 0 <= fb.S <= 1e-6
    @test fb.P >= 100 * 2000 * (1 - 1e-9)
    @test fb.v_eff ≈ 0.3 rtol = 5e-3
    # `:paper`: the second derivative is constant, so either P ≥ 10·Δt_end or the
    # "persistence not resolved" error (the sign of c₁ is rounding)
    pb = try
        p65cc_furth_fit(Δt, bal; method = :paper)
    catch e
        e
    end
    @test (pb isa NamedTuple && pb.P >= 10 * 2000) || (pb isa ArgumentError && occursin("persistence not resolved", pb.msg))
    # pure diffusion m = 1.4Δt: D_slow = 0.7 (S and P are not identifiable: not asserted)
    fd = p65cc_furth_fit(Δt, 1.4 .* Δt; method = :lsq)
    @test fd.D_slow ≈ 0.7 rtol = 1e-6
    # `:paper` cannot resolve a persistence: the error, naming the cross-check
    @test_throws ArgumentError p65cc_furth_fit(Δt, 1.4 .* Δt; method = :paper)
    msg = p65cc_msg(() -> p65cc_furth_fit(Δt, 1.4 .* Δt))
    @test occursin("persistence not resolved", msg) && occursin(":lsq", msg)
end

# ---------------------------------------------------------------------------------------
# 5. The stochastic oracle (brief §4.C5; calibration in the header)

const P65CC_SEED = 14

@testset "P6.5c MSD/Fürth: OU + Brownian tracks recover (S, D, P)" begin
    @test p65cc_has(:msd) && p65cc_has(:furth_fit)              # DEFECT CHECK
    lags = 1:400
    Δt = Float64.(lags)
    tracks = p65cc_tracks(StableRNG(P65CC_SEED); S = 0.1, D = 0.5, P = 100.0, n = 20_000, ntracks = 64)
    m = p65cc_msd(tracks; lags)
    # the estimator is the test's own sum on one lag (independent recomputation)
    l = 37
    @test m[l] ≈ sum(sum(sum(abs2, t[i + l] .- t[i]) for i in 1:(length(t) - l)) / (length(t) - l) for t in tracks) / 64 rtol = 1e-12
    # the expected MSD is Eq. 1 within the sampling error (a sanity check of the generator)
    @test maximum(abs.(m ./ p65cc_eq1.(Δt; S = 0.1, D = 0.5, P = 100.0) .- 1)) < 0.1
    fl = p65cc_furth_fit(Δt, m; method = :lsq)
    @test abs(fl.D / 0.5 - 1) <= 0.10
    @test abs(fl.P / 100 - 1) <= 0.10
    @test abs(fl.S - 0.1) <= 0.02
    fp = p65cc_furth_fit(Δt, m; method = :paper)
    @test abs(fp.D / 0.5 - 1) <= 0.20
    @test abs(fp.P / 100 - 1) <= 0.20
    @test abs(fp.S - 0.1) <= 0.04
    # negative control: S = 0 data (no Brownian part)
    t0 = p65cc_tracks(StableRNG(1000 + P65CC_SEED); S = 0.0, D = 0.5, P = 100.0, n = 20_000, ntracks = 64)
    m0 = p65cc_msd(t0; lags)
    f0 = p65cc_furth_fit(Δt, m0; method = :lsq)
    @test f0.S < 0.02
    @test p65cc_furth_fit(Δt, m0; method = :paper).S < fp.S           # `:paper`: below the S = 0.1 fit
    # negative control: shuffling the sample order destroys the persistence: a flat MSD and
    # a fit that misses the targets
    rng = StableRNG(2000 + P65CC_SEED)
    ms = p65cc_msd([shuffle(rng, t) for t in tracks]; lags)
    @test abs(ms[end] / ms[1] - 1) < 0.01 && m[end] / m[1] > 100
    fs = p65cc_furth_fit(Δt, ms; method = :lsq)
    @test !(abs(fs.D / 0.5 - 1) <= 0.10 && abs(fs.P / 100 - 1) <= 0.10 && abs(fs.S - 0.1) <= 0.02)
end

# ---------------------------------------------------------------------------------------
# 6. Input validation (brief §3.C5)

@testset "P6.5c MSD/Fürth: furth_fit input validation" begin
    @test p65cc_has(:furth_fit)                                  # DEFECT CHECK
    Δt = collect(1.0:10.0)
    m = p65cc_eq1.(Δt; S = 0.1, D = 0.5, P = 3.0)
    for method in (:paper, :lsq)
        @test_throws ArgumentError p65cc_furth_fit(Δt[1:3], m[1:3]; method)              # length < 4
        @test_throws ArgumentError p65cc_furth_fit(Δt, [m[1:9]; NaN]; method)            # non-finite
        @test_throws ArgumentError p65cc_furth_fit([Δt[1:9]; Inf], m; method)
        @test_throws ArgumentError p65cc_furth_fit([1.0, 2.0, 2.0, 3.0], m[1:4]; method)  # not increasing
        @test_throws ArgumentError p65cc_furth_fit(Δt[1:9], m; method)                   # lengths differ
    end
    # `:paper` needs a uniform spacing; `:lsq` does not
    tn = [1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 21.0, 34.0]
    mn = p65cc_eq1.(tn; S = 0.1, D = 0.5, P = 5.0)
    @test_throws ArgumentError p65cc_furth_fit(tn, mn; method = :paper)
    @test p65cc_furth_fit(tn, mn; method = :lsq).P ≈ 5.0 rtol = 1e-6
    # m ≤ 0: an error for `:lsq` (relative weights), allowed for `:paper`
    mz = copy(m)
    mz[1] = 0.0
    @test_throws ArgumentError p65cc_furth_fit(Δt, mz; method = :lsq)
    @test p65cc_furth_fit(Δt, mz; method = :paper) isa NamedTuple
    @test_throws ArgumentError p65cc_furth_fit(Δt, m; method = :fourier)                  # an unknown method
end

# ---------------------------------------------------------------------------------------
# 7. The paper's numbers, sanity only (brief §4.C6; guards the formula, not the table)

@testset "P6.5c MSD/Fürth: natural_units with Table 2's R = 15, φ = 0.10, λ = 150 row" begin
    fit = (; P = 6878.0, D = 2.83e-4, S = 9.68e-3)
    @test 2 * fit.D * fit.P / (1 - fit.S) ≈ 3.931 rtol = 1e-3     # control (arithmetic)
    @test p65cc_has(:natural_units)                              # DEFECT CHECK
    Δt = [6878.0, 2 * 6878.0]
    m = [1.0, 2.0]
    τ, ρ2 = p65cc_natural_units(Δt, m, fit)
    @test τ == [1.0, 2.0]
    @test round(m[1] / ρ2[1]; sigdigits = 4) == 3.931             # 2DP/(1 − S)
end

# ---------------------------------------------------------------------------------------
# 8. Docs (brief §4.D)

@testset "P6.5c MSD/Fürth: the analysis manual names msd and furth_fit" begin
    md = read(joinpath(@__DIR__, "..", "..", "..", "..", "docs", "src", "manual", "analysis.md"), String)
    @test occursin("centroids", md) || occursin("Analysis", md)   # control: the page exists
    @test occursin("msd", md) && occursin("furth_fit", md)        # DEFECT CHECK
end
