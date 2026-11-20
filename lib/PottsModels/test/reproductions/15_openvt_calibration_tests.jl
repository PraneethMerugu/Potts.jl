# the OpenVT monolayer benchmark's mechanical calibration on 1D
# cell chains (M §2.2, Fig 2, Table S5). The protocol is
# spec 15 §4.2.3 P1–P12 and the pre-registered targets are §4.1 V6–V8
# (docs/design/research/model-specs/15_openvt_monolayer.md v3); every reference value and
# pass band below is copied from there. The seeds, the SMOKE bands and the run lengths are
# the test author's (D-148). Gap G10 (spec §6).
#
# Surface fixed by the test author (implemented in `15_openvt_calibration_tests.jl`; open questions in D-148):
#
#   PottsModels.Analysis.centroids(σ; periodic = (false, …)) -> Vector{NTuple{N, Float64}}
#     (general; the existing method gains the keyword). On an axis d with periodic[d], each
#     cell's sites are taken at the minimum image nearest the cell's first site in
#     column-major order, and the mean is wrapped into [1, size(σ, d) + 1) (CorePotts
#     `centroid`'s convention). Non-periodic axes, the default and the NaN of an id that
#     owns no site are unchanged.
#
#   PottsModels.Analysis.chain_centroids(σ) -> Vector{Float64}
#     The x (axis 1) centroid of every cell 1:maximum(σ), axis 1 periodic (`centroids` with
#     periodic axis 1), then unwrapped along the chain: sort the centroids, cut the circle
#     at the largest gap between cyclically consecutive centroids, and add size(σ, 1) to
#     every centroid left of the cut, so the chain's leftmost cell lies in
#     [1, size(σ, 1) + 1) and the chain is contiguous (spec P6 "centroids unwrapped across
#     the periodic x boundary"). Valid while the chain is shorter than the lattice minus
#     its largest gap.
#   PottsModels.Analysis.chain_width(σ, cells = 1:maximum(σ); CD = 10) -> Float64
#     (max − min of chain_centroids(σ)[cells]) / CD: w₁₁, w₂₁ of spec P6 (CD = 10 px, C7).
#     The inner w₁₁ of the 21-chain is (x_c(16) − x_c(6)) / CD from chain_centroids.
#   PottsModels.Analysis.crossing_time(t, w, level = 9.0)
#     t[i] for the first i with w[i] ≥ level, `nothing` if none (spec P8: the first MCS at
#     which the replicate-mean w₁₁ ≥ 9 CD).
#   PottsModels.Analysis.relaxation_mse(t, w, T, ref_t, ref_w) -> Float64
#     mean over j of (ŵ(ref_t[j]) − ref_w[j])², ŵ the linear interpolant of w against
#     t ./ T (spec P9); an ArgumentError if some ref_t[j] lies outside [t[1], t[end]] / T.
#
#   spring_dashpot_width(t; n = 11, rate = 18.2816647214633, pinned = false) -> Float64
#     (PottsModels, exported) The spring–dashpot reference of spec §4.2.2 / P11: n beads at
#     x_i(0) = 0.5 i CD (i = 0 … n−1), rest length 1 CD, overdamped
#     ẋ_i = rate·[(x_{i+1} − x_i − 1) − (x_i − x_{i−1} − 1)] with both ends free (or x_0
#     held fixed with `pinned = true`), t in units of T; returns x_{n−1}(t) − x_0(t) in CD.
#   OpenVTChain(; name, lattice = (150, 5), λ = 2.0, …)   (PottsModels, exported)
#     kinds `medium, compressed, relaxed`; parameters λ = 2, T = 20, A = 50, A_c = 25 and
#     J[kind, kind] with cell–cell 20, cell–medium 10 (Table S1, P3); energies
#     `cells(compressed) => λ (volume − A_c)²`, `cells(relaxed) => λ (volume − A)²` and
#     `contacts => J[kind, neighbor_kind]`; lattice periodic on both axes with Moore(1) (P1, P4);
#     proposals Moore(1); Metropolis at T; no growth and no division.
#   openvt_chain(n) -> [ownership => σ, kind => kinds]   (PottsModels, exported)
#     n = 11: 11 compressed 5 × 5 cells packed edge to edge on 150 × 5 at x ∈ 49:103;
#     n = 21: on 250 × 5, 5 relaxed 10 × 5 cells at x ∈ 49:98, 11 compressed at 99:153 and
#     5 relaxed at 154:203, flush. Ids left to right (Morpheus: uncompressed 1–5,
#     compressed 6–16, uncompressed 17–21). The x positions are Morpheus's
#     (`Relaxation_11cells_Morpheus_V5.xml`, `…11+10…`: box origin size.x/2 − 5CD/2 − 2,
#     0-based), i.e. the chain centred within one site (P2).
#   openvt_release(at = 100) -> DiscreteCallback   (PottsModels, exported)
#     Sets A_c := A at the end of MCS `at` (condition t == at; P5). The burn-in is the
#     first 100 MCS; the state saved at MCS `at` is the chain's t = 0, and the first
#     relaxing MCS is at + 1. Spec time t (MCS) is our MCS − 100.
#
# Runs: `SequentialCPM(; proposal = Moore(1))`, `PottsProblem(OpenVTChain(; lattice, λ),
# openvt_chain(n), (0, 100 + tmax); seed)`, `callback = openvt_release(100)`, saved every
# MCS from 100 on.
#
# Tiers. The fixture rows and SMOKE run in the PottsModels suite (seconds plus one model
# compilation). FULL runs with POTTS_FULL_REPRODUCTION=true (or REPRO=full), offline (D-146);
# it is cheap (500 runs on 150 × 5 and 250 × 5, about 20 s on 4 threads for a minimal
# implementation), but its outputs follow the D-146 export rule.
# Rows marked "G" also run when OPENVT_MONOLAYER_REPO points at the consortium repo G
# (gitlab.com/rvet/monolayergrowth at 54f375f; read only, never copied into git) and are
# skipped otherwise.
#
# | Row | Target (spec 15) | Rule / tolerance | Tier |
# |---|---|---|---|
# | P11 | §4.2.2 reference: w(0.1) = 6.0789, w(0.5) = 7.9022, w(1) = 9.0000, w(2) = 9.7726, w(5) = 9.9973; w(1) = 9 defines k/η | 5e-5 (4 printed decimals); 1e-7 | always |
# | P11 control | pinned end: w(1) = 7.17 | 5e-3 | always |
# | P11 data | `relaxation_exact.csv`, 51 rows, t = 0:0.1:5 | 1e-6 | G |
# | P1–P4 | lattice, kinds, Table S1 parameters, Moore(1) | exact | always |
# | P2 | initial 11- and 21-chains, ids, w₁₁(0) = 5, w₂₁(0) = 14.5, inner 5 | exact | always |
# | P5 | A_c = 25 through MCS 99, A_c = 50 from the end of MCS 100; state at 100 unchanged | exact | always |
# | P6 | periodic centroids and unwrapped chain widths on hand-built σ | exact (1e-12) | always |
# | P8, P9 | crossing and MSE on synthetic curves with known answers | exact (1e-12) | always |
# | P8, P9, V7, V8 data | the rules on G's TST, Morpheus-J10, Artistoo curves give the spec's MSEs, crossings (T = 155) and V7/V8 spreads | printed digits | G |
# | SMOKE | λ = 2, 4 seeds: w̄ ≈ 5 at t = 0, rises monotonically toward 10 by 5 × 155; compressed area ≈ 25 at t = 0; no release ⇒ no relaxation | bands below | always |
# | V6 | T(λ), λ ∈ {1, 2, 3, 5}: 290, 155, 110, 75 MCS (Table S5) | ±15 % each; strictly decreasing in λ | FULL |
# | V7 | MSE vs the reference ≤ 3 × Table S5 (7.570e-4, 2.664e-3, 4.433e-3, 1.378e-2); at λ = 2 w₁₁(0.5T) ∈ 7.83–7.87, w₁₁(2T) ∈ 9.78–9.80 | ≤ 3×; spread ± 0.1 CD | FULL |
# | V8 | 21-chain, λ = 2, T from V6 (no refit): w₂₁ at 1/5/10 T 15.90–16.25 / 19.20–19.57 / 19.90–19.96; inner w₁₁ 7.20–7.51 / 9.46–9.71 / 9.92–9.96; plateau (w̄₂₁ < w̄₂₁(0) + 0.05) ends at 0.15–0.22 T | spread ± 0.15 CD; plateau end in 0.1–0.3 T | FULL |
#
# Replicates (P7): 100 seeds per λ for the 11-chain and 100 for the 21-chain. Seeds:
# 11-chain at λ, run i → 1000λ + i; 21-chain run i → 21_000 + i; SMOKE run i → 90_000 + i.
#
# Negative controls (D-048): the pinned-end reference misses w(1) = 9 (free ends matter);
# without `openvt_release` the chain stays compressed; the unwrapped width differs from the
# naive one across the seam; P8 picks the first crossing, not the last, on a non-monotone
# curve; an offset curve has a known nonzero MSE; G's CC3D curve (λ = 5, T = 84) fails
# V7's λ = 2 MSE bound.

@testsetup module OpenVTCalibrationSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts, PottsModels, Test
using Statistics: mean
const CALIBRATION_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const REPO = get(ENV, "OPENVT_MONOLAYER_REPO", "")
const CALIBRATION_A = PottsModels.Analysis
# ---------------------------------------------------------------------------------------------
# Constants, verbatim from spec 15
# ---------------------------------------------------------------------------------------------
const RATE = 18.2816647214633
# k/η per T (§4.2.2, `relaxation_exact.m:4`)
# §4.2.2 / verification log: w(t) of the free 11-bead chain, 4 printed decimals
const REF_W = (0.1 => 6.0789, 0.5 => 7.9022, 1.0 => 9.0, 2.0 => 9.7726, 5.0 => 9.9973)
const REF_PINNED = 7.17
# §4.2.2: x₀ pinned, w(1)
const CALIBRATION_CD = 10
# C7: CD = 10 px
const BURNIN = 100
# P5 (Morpheus, Artistoo)
const LEVEL = 9.0
# P8: 90 % of 10 CD
const REF_T = collect(0:0.1:5)
# P9: the 51 points of relaxation_exact.csv
# V6 / Table S5 (M p.12): T(λ) in MCS and the MSE
const LAMBDAS = (1, 2, 3, 5)
const T_S5 = Dict(1 => 290, 2 => 155, 3 => 110, 5 => 75)
const MSE_S5 = Dict(1 => 7.57e-4, 2 => 2.664e-3, 3 => 4.433e-3, 5 => 1.378e-2)
const T_TOL = 0.15
# V6: ±15 %
const MSE_FACTOR = 3
# V7: ≤ 3 × Table S5
# V7: lattice spread of w₁₁ at 0.5 T and 2 T (TST, Morpheus-J10, Artistoo), ± 0.1 CD
const V7_SPREAD = (0.5 => (7.83, 7.87), 2.0 => (9.78, 9.8))
const V7_MARGIN = 0.1
# V8: lattice spread (CC3D, Morpheus-J10, TST, Artistoo) at 1 / 5 / 10 T, ± 0.15 CD
const V8_W21 = (1 => (15.9, 16.25), 5 => (19.2, 19.57), 10 => (19.9, 19.96))
const V8_INNER = (1 => (7.2, 7.51), 5 => (9.46, 9.71), 10 => (9.92, 9.96))
const V8_MARGIN = 0.15
const V8_PLATEAU = (0.15, 0.22)
# plateau end in T, data spread
const V8_PLATEAU_BAND = (0.1, 0.3)
# pass band
const PLATEAU_RISE = 0.05
# plateau: w̄₂₁ < w̄₂₁(0) + 0.05
# P8/P9 applied to G's λ = 2 curves (§4.2.1, P9; T = 155): MSE as printed
const G_MSE = (TST = 1.26e-3, Morpheus = 1.59e-3, Artistoo = 7.4e-4)
const G_MSE_CC3D = 1.09e-2
# CC3D (λ = 5, T = 84), P9
const CALIBRATION_N = CALIBRATION_FULL ? 100 : 4
# P7 (SMOKE: 4)
calibration_seed(λ::Integer, i::Integer) = 1000λ + i
seed21(i::Integer) = 21_000 + i
seed_smoke(i::Integer) = 90_000 + i
const ALG = SequentialCPM(; proposal = Moore(1))
# ---------------------------------------------------------------------------------------------
# Helpers (test-internal)
# ---------------------------------------------------------------------------------------------

# Linear interpolation of w (sampled at s, ascending) at r ∈ [s[1], s[end]]
function interp(s, w, r)
    s[1] <= r <= s[end] || throw(ArgumentError("interp: $r outside [$(s[1]), $(s[end])]"))
    j = searchsortedlast(s, r)
    j == length(s) && return float(w[j])
    return w[j] + (w[j + 1] - w[j]) * (r - s[j]) / (s[j + 1] - s[j])
end
within(x, (lo, hi), m) = lo - m <= x <= hi + m
# The expected initial chain (P2), painted by hand
function expected_chain(n)
    L = n == 11 ? 150 : 250
    σ = zeros(Int32, L, 5)
    kinds = Symbol[]
    x0 = n == 11 ? 49 : 99                          # first compressed column
    if n == 21
        for i in 1:5
            σ[(x0 - 50 + 10(i - 1)) .+ (0:9), :] .= length(kinds) + 1
            push!(kinds, :relaxed)
        end
    end
    for i in 1:11
        σ[(x0 + 5(i - 1)) .+ (0:4), :] .= length(kinds) + 1
        push!(kinds, :compressed)
    end
    if n == 21
        for i in 1:5
            σ[(x0 + 55 + 10(i - 1)) .+ (0:9), :] .= length(kinds) + 1
            push!(kinds, :relaxed)
        end
    end
    return σ, kinds
end
state_σ(st) = Array(only(p.second for p in st if p.first === ownership))
state_kinds(st) = collect(only(p.second for p in st if p.first === kind))
# Runs of the n-chain at λ, one per seed, `tmax` MCS after the release; returns the spec
# time axis t = 0:tmax (MCS) and per-run w (and, for n = 21, the inner w₁₁) as matrices
# (time × run), plus the compressed cells' mean area at t = 0 and t = tmax.
function runs(n, λ, seeds; tmax, release = true)
    L = n == 11 ? 150 : 250
    sys = OpenVTChain(; name = Symbol(:calibration_chain, n), lattice = (L, 5), λ = Float64(λ))
    prob = PottsProblem(sys, openvt_chain(n), (0, BURNIN + tmax); seed = first(seeds))
    saves = BURNIN:(BURNIN + tmax)
    W = fill(NaN, length(saves), length(seeds))
    In = fill(NaN, length(saves), length(seeds))
    area = fill(NaN, 2, length(seeds))
    comp = n == 11 ? (1:11) : (6:16)
    Threads.@threads for j in eachindex(seeds)
        sol = solve(
            remake(prob; seed = seeds[j]), ALG; saveat = saves, save_start = false,
            callback = release ? openvt_release(BURNIN) : nothing
        )
        @assert collect(sol.t) == collect(saves)
        for (k, u) in enumerate(sol.u)
            xs = CALIBRATION_A.chain_centroids(u.ownership)
            W[k, j] = (maximum(xs) - minimum(xs)) / CALIBRATION_CD
            n == 21 && (In[k, j] = (xs[16] - xs[6]) / CALIBRATION_CD)
        end
        for (r, u) in ((1, sol.u[1]), (2, sol.u[end]))
            area[r, j] = mean(count(==(c), u.ownership) for c in comp)
        end
    end
    return (; t = collect(0:tmax), W, In, area)
end
calibration_mean(M) = vec(mean(M; dims = 2))
# ---------------------------------------------------------------------------------------------
# P8 / P9 and the V7 / V8 constants against the consortium's λ = 2 curves (G)
# ---------------------------------------------------------------------------------------------

# (s = t / T, w) columns of a G curve file
function gcurve(path, delim, tcol, wcol)
    lines = filter(!isempty ∘ strip, readlines(path))
    head = strip.(split(lines[1], delim), '"')
    it = tcol isa Integer ? tcol : findfirst(==(tcol), head)
    iw = wcol isa Integer ? wcol : findfirst(==(wcol), head)
    rows = [split(l, delim) for l in lines[2:end]]
    return [parse(Float64, r[it]) for r in rows], [parse(Float64, r[iw]) for r in rows]
end
# a G value matches the spec's printed value to half a unit of its last printed digit
printed(x, ref, digits) = abs(x - ref) <= 0.5 * 10.0^-digits * (1 + 1.0e-9)
in_spread(x, (lo, hi)) = lo <= round(x; digits = 2) <= hi
# ---------------------------------------------------------------------------------------------
# SMOKE: λ = 2, 4 seeds, 5 × 155 MCS after the release
# ---------------------------------------------------------------------------------------------

# mean of the replicate-mean curve over the MCS window `r` (spec time)
window(t, wbar, r) = mean(wbar[k] for k in eachindex(t) if t[k] in r)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "15 openvt calibration P11: spring–dashpot reference (spec 15 §4.2.2)" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # P11: the spring–dashpot reference (spec 15 §4.2.2)
    # ---------------------------------------------------------------------------------------------
    @testset "15 openvt calibration P11: spring–dashpot reference (spec 15 §4.2.2)" begin
        @test abs(spring_dashpot_width(0.0; rate = RATE) - 5) <= 1.0e-12
        for (t, w) in REF_W
            @test abs(spring_dashpot_width(t; rate = RATE) - w) <= 5.0e-5
        end
        # k/η is the root of w(1) = 9 (`fzero`, `relaxation_exact.m:4`), and it is the default
        @test abs(spring_dashpot_width(1.0; rate = RATE) - 9) <= 1.0e-7
        @test spring_dashpot_width(1.0) == spring_dashpot_width(1.0; rate = RATE)
        @test spring_dashpot_width(1.0; rate = RATE, n = 11) == spring_dashpot_width(1.0; rate = RATE)
        # relaxed length n − 1 = 10 CD, approached monotonically from below
        ws = [spring_dashpot_width(t; rate = RATE) for t in 0:0.05:5]
        @test all(diff(ws) .> 0) && ws[end] < 10
        @test abs(spring_dashpot_width(20.0; rate = RATE) - 10) < 1.0e-6
        # negative control: one end pinned (the schema's "removal of one side constraint")
        wp = spring_dashpot_width(1.0; rate = RATE, pinned = true)
        @test abs(wp - REF_PINNED) <= 5.0e-3
        @test abs(wp - 9) > 1
    end
end

@testitem "15 openvt calibration P11: relaxation_exact.csv (G)" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt calibration P11: relaxation_exact.csv (G)" begin
        path = joinpath(REPO, "results", "relaxation_exact.csv")
        if isempty(REPO) || !isfile(path)
            @test_skip isfile(path)
        else
            lines = filter(!isempty ∘ strip, readlines(path))
            @test lines[1] == "t,w"
            rows = [parse.(Float64, split(l, ',')) for l in lines[2:end]]
            @test length(rows) == 51
            @test all(isapprox(r[1], REF_T[k]; atol = 1.0e-12) for (k, r) in enumerate(rows))
            @test maximum(abs(spring_dashpot_width(r[1]; rate = RATE) - r[2]) for r in rows) <= 1.0e-6
        end
    end
end

@testitem "15 openvt calibration P1–P4: OpenVTChain (Table S1, periodic strip, Moore(1))" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # P1–P5: the model, the initial chains and the release
    # ---------------------------------------------------------------------------------------------
    @testset "15 openvt calibration P1–P4: OpenVTChain (Table S1, periodic strip, Moore(1))" begin
        for (n, L) in ((11, 150), (21, 250))
            sys = OpenVTChain(; name = Symbol(:calibration_m, n), lattice = (L, 5))
            lat = Potts.lattice(sys)
            @test lat.dims == (L, 5)
            @test Potts.isperiodic(lat, 1) && Potts.isperiodic(lat, 2)
            prob = PottsProblem(sys, openvt_chain(n), (0, 1); seed = 1)
            par(x) = getp(prob, x)(prob)
            @test (par(:λ), par(:T), par(:A), par(:A_c)) == (2.0, 20.0, 50.0, 25.0)
            # kinds medium, compressed, relaxed: J_cc = 20, J_cm = 10 (Table S1)
            @test par(:J) == [0.0 10.0 10.0; 10.0 20.0 20.0; 10.0 20.0 20.0]
        end
        for λ in LAMBDAS
            sys = OpenVTChain(; name = Symbol(:calibration_l, λ), λ = Float64(λ))
            prob = PottsProblem(sys, openvt_chain(11), (0, 1); seed = 1)
            @test getp(prob, :λ)(prob) == λ
        end
        @test Potts.lattice(OpenVTChain(; name = :default)).dims == (150, 5)
    end
end

@testitem "15 openvt calibration P2: initial chains (Morpheus placement and ids)" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt calibration P2: initial chains (Morpheus placement and ids)" begin
        for n in (11, 21)
            st = openvt_chain(n)
            σ, kinds = state_σ(st), state_kinds(st)
            eσ, ek = expected_chain(n)
            @test size(σ) == size(eσ)
            @test σ == eσ
            @test kinds == ek
            # independent statement of the columns (1-based)
            cols(c) = unique(i[1] for i in findall(==(c), σ))
            if n == 11
                @test cols(1) == 49:53 && cols(11) == 99:103
            else
                @test cols(1) == 49:58 && cols(5) == 89:98 && cols(6) == 99:103 && cols(16) == 149:153 &&
                    cols(17) == 154:163 && cols(21) == 194:203
            end
            # every cell spans the strip; compressed 25 sites, relaxed 50
            @test all(c -> all(any(==(c), view(σ, :, y)) for y in 1:5), 1:n)
            @test all(c -> count(==(c), σ) == (kinds[c] === :compressed ? 25 : 50), 1:n)
            # observables at the start (P6)
            @test CALIBRATION_A.chain_width(σ) == (n == 11 ? 5.0 : 14.5)
            xs = CALIBRATION_A.chain_centroids(σ)
            @test issorted(xs)
            n == 21 && @test (xs[16] - xs[6]) / CALIBRATION_CD == 5.0
            n == 21 && @test CALIBRATION_A.chain_width(σ, 6:16) == 5.0
        end
    end
end

@testitem "15 openvt calibration P5: the release switches A_c at the end of MCS 100 (t = 0)" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt calibration P5: the release switches A_c at the end of MCS 100 (t = 0)" begin
        prob = PottsProblem(OpenVTChain(; name = :rel), openvt_chain(11), (0, 102); seed = 7)
        integ = init(
            prob, ALG; callback = openvt_release(BURNIN), saveat = [99, 100, 101],
            save_start = false
        )
        while integ.t < 99
            step!(integ)
        end
        @test integ.t == 99 && integ.ps[:A_c] == 25.0
        σ99 = copy(current_state(integ).ownership)
        step!(integ)
        @test integ.t == 100 && integ.ps[:A_c] == 50.0 && integ.ps[:A] == 50.0
        # the callback changes the parameter only: the t = 0 state is the burn-in's end
        σ100 = copy(current_state(integ).ownership)
        step!(integ)
        @test integ.ps[:A_c] == 50.0
        @test integ.saved_t == [99, 100, 101]
        @test integ.saved_u[1].ownership == σ99 && integ.saved_u[2].ownership == σ100
        # a different release time moves the switch
        integ2 = init(prob, ALG; callback = openvt_release(3))
        step!(integ2); step!(integ2)
        @test integ2.ps[:A_c] == 25.0
        step!(integ2)
        @test integ2.t == 3 && integ2.ps[:A_c] == 50.0
        # without the callback A_c stays 25
        integ3 = init(prob, ALG)
        for _ in 1:5
            step!(integ3)
        end
        @test integ3.ps[:A_c] == 25.0
    end
end

@testitem "15 openvt calibration P6: Analysis.centroids with periodic axes" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # P6: periodic centroids and chain widths on hand-built lattices
    # ---------------------------------------------------------------------------------------------
    @testset "15 openvt calibration P6: Analysis.centroids with periodic axes" begin
        σ = zeros(Int, 10, 4)
        σ[[9, 10, 1, 2], 1:4] .= 1          # straddles the x seam
        σ[4:5, [4, 1]] .= 2                 # straddles the y seam
        σ[6:7, 2:3] .= 3                    # interior
        σ[3, 2] = 5                         # id 4 owns no site
        c = CALIBRATION_A.centroids(σ; periodic = (true, true))
        @test c[1][1] == 10.5               # sites 9, 10, 11, 12 ≡ 9, 10, 1, 2
        @test c[2] == (4.5, 4.5)            # rows 4, 5 ≡ 4, 1
        @test c[3] == (6.5, 2.5)
        @test all(isnan, c[4])
        @test c[5] == (3.0, 2.0)
        cx = CALIBRATION_A.centroids(σ; periodic = (true, false))
        @test cx[1] == (10.5, 2.5) && cx[2] == (4.5, 2.5) && cx[3] == (6.5, 2.5)
        # the default (and periodic = false) keep the plain mean of indices
        c0 = CALIBRATION_A.centroids(σ)
        @test c0[1] == (5.5, 2.5) && c0[2] == (4.5, 2.5)
        @test isequal(CALIBRATION_A.centroids(σ; periodic = (false, false)), c0)
        # wrapped into [1, n + 1): a cell at x ∈ {10, 1} is at 10.5, not 0.5
        τ = zeros(Int, 10, 1)
        τ[[10, 1]] .= 1
        @test CALIBRATION_A.centroids(τ; periodic = (true, false))[1] == (10.5, 1.0)
        # translation covariance on the periodic axis
        for s in 0:9
            cs = CALIBRATION_A.centroids(circshift(σ, (s, 0)); periodic = (true, true))
            @test all(mod(cs[k][1] - c[k][1] - s, 10) == 0 for k in (1, 2, 3, 5))
        end
    end
end

@testitem "15 openvt calibration P6: chain_centroids and chain_width across the periodic seam" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt calibration P6: chain_centroids and chain_width across the periodic seam" begin
        σA = zeros(Int, 30, 5)
        σA[5:9, :] .= 1
        σA[10:14, :] .= 2
        σA[15:24, :] .= 3
        xa = CALIBRATION_A.chain_centroids(σA)
        @test xa == [7.0, 12.0, 19.5]
        @test CALIBRATION_A.chain_width(σA) == 1.25
        @test CALIBRATION_A.chain_width(σA; CD = 1) == 12.5
        @test CALIBRATION_A.chain_width(σA, 1:2) == 0.5
        # the chain shifted by 20 crosses the seam: cell 2 straddles it, cell 3 is past it
        σB = circshift(σA, (20, 0))
        @test σB[30, 1] == 2 && σB[1, 1] == 2 && σB[10, 1] == 3
        @test CALIBRATION_A.chain_centroids(σB) == [27.0, 32.0, 39.5]
        @test CALIBRATION_A.chain_width(σB) == 1.25
        # negative control: the naive (wrapped) centroids get the width wrong here
        naive = [c[1] for c in CALIBRATION_A.centroids(σB; periodic = (true, true))]
        @test naive == [27.0, 2.0, 9.5]
        @test (maximum(naive) - minimum(naive)) / 10 == 2.5
        # every shift: same width, the leftmost cell in [1, 31), chain order kept
        for s in 0:29
            xs = CALIBRATION_A.chain_centroids(circshift(σA, (s, 0)))
            @test xs .- xs[1] == xa .- xa[1]
            @test 1 <= xs[1] < 31
            @test CALIBRATION_A.chain_width(circshift(σA, (s, 0))) == 1.25
        end
        # the published 11-chain anywhere on its strip
        σ11 = state_σ(openvt_chain(11))
        for s in (0, 50, 75, 100, 120, 149)
            @test CALIBRATION_A.chain_width(circshift(σ11, (s, 0))) == 5.0
        end
        # a stretched chain spanning most of the lattice: the largest gap still marks the ends
        σC = zeros(Int, 40, 2)
        for c in 1:6
            σC[mod1.((6c - 5 + 30):(6c - 2 + 30), 40), :] .= c   # 4 sites per cell, 2 medium between
        end
        @test CALIBRATION_A.chain_width(σC; CD = 1) == 30.0
    end
end

@testitem "15 openvt calibration P8: crossing_time (first MCS with w ≥ 9)" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # P8 and P9 on synthetic curves with known answers
    # ---------------------------------------------------------------------------------------------
    @testset "15 openvt calibration P8: crossing_time (first MCS with w ≥ 9)" begin
        t = collect(0:5)
        w = [5.0, 7.0, 8.99, 9.0, 8.5, 9.5]
        @test CALIBRATION_A.crossing_time(t, w) == 3                 # ≥, and the first crossing
        @test CALIBRATION_A.crossing_time(t, w, 8.0) == 2
        @test CALIBRATION_A.crossing_time(t .+ 100, w) == 103         # returns t, not the index
        @test CALIBRATION_A.crossing_time(t, fill(8.999, 6)) === nothing
        # on the reference sampled every MCS with T = 155 the crossing is MCS 155 (w = 9 there up
        # to rounding, so 156 is allowed)
        tt = collect(0:775)
        @test CALIBRATION_A.crossing_time(tt, [spring_dashpot_width(x / 155; rate = RATE) for x in tt]) in (155, 156)
    end
end

@testitem "15 openvt calibration P9: relaxation_mse" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt calibration P9: relaxation_mse" begin
        rw = 5 .+ REF_T
        t = collect(0:775)
        w = 5 .+ t ./ 155
        @test CALIBRATION_A.relaxation_mse(t, w, 155, REF_T, rw) <= 1.0e-24
        @test abs(CALIBRATION_A.relaxation_mse(t, w .+ 0.1, 155, REF_T, rw) - 0.01) <= 1.0e-12
        # T scales time: w sampled at t = 0:1550 with T = 310 is the same curve
        t2 = collect(0:1550)
        @test CALIBRATION_A.relaxation_mse(t2, 5 .+ t2 ./ 310, 310, REF_T, rw) <= 1.0e-24
        # linear interpolation between coarse samples: s² on knots h = 0.3125 against s² at
        # the reference points; the interpolation error at s ∈ [a, a + h] is (s − a)(a + h − s)
        h = 0.3125
        tk = collect(0:50:800)                                  # T = 160, s = t / T = 0:h:5
        wk = (tk ./ 160) .^ 2
        expect = mean(((s - h * fld(s + 1.0e-12, h)) * (h * fld(s + 1.0e-12, h) + h - s))^2 for s in REF_T)
        @test abs(CALIBRATION_A.relaxation_mse(tk, wk, 160, REF_T, REF_T .^ 2) - expect) <= 1.0e-12
        @test expect > 1.0e-5                                     # the case is not trivial
        # the run must cover 0 … 5 T
        @test_throws ArgumentError CALIBRATION_A.relaxation_mse(collect(0:700), 5 .+ (0:700) ./ 155, 155, REF_T, rw)
        # the reference itself has MSE ≈ 0 against itself at T = 155
        wref = [spring_dashpot_width(x / 155; rate = RATE) for x in t]
        refw = [spring_dashpot_width(x; rate = RATE) for x in REF_T]
        @test CALIBRATION_A.relaxation_mse(t, wref, 155, REF_T, refw) < 1.0e-4
    end
end

@testitem "15 openvt calibration P8/P9/V7/V8: the rules and constants on G's curves (G)" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt calibration P8/P9/V7/V8: the rules and constants on G's curves (G)" begin
        R = joinpath(REPO, "results")
        if isempty(REPO) || !isdir(R)
            @test_skip isdir(R)
        else
            rw = [spring_dashpot_width(x; rate = RATE) for x in REF_T]
            c11 = (
                TST = gcurve(
                    joinpath(R, "TST", "Relaxation", "11cells", "width.csv"), ",",
                    "Normalized time (T)", "Mean Tissue width (CD)"
                ),
                Morpheus = gcurve(
                    joinpath(
                        R, "Morpheus", "Relaxation",
                        "Morpheus_1D_Relaxation_J10_11_cells_N100stats.csv"
                    ), ",", 1, 2
                ),
                Artistoo = gcurve(joinpath(R, "Artistoo", "Relax", "average_sim1_11_cells.csv"), "\t", 1, 2),
            )
            for name in keys(c11)
                s, w = c11[name]
                # P9 on s = t / T (T = 1) reproduces the spec's MSE (P9)
                @test printed(CALIBRATION_A.relaxation_mse(s, w, 1, REF_T, rw), G_MSE[name], 5)
                # P8 on whole MCS (t = round(155 s)) gives T within 1 % of 155 (V6 at λ = 2)
                k = findall(>=(0), s)
                tc = CALIBRATION_A.crossing_time(round.(Int, 155 .* s[k]), w[k])
                @test tc !== nothing && abs(tc / 155 - 1) <= 0.01
                # V7 spread
                for (r, spread) in V7_SPREAD
                    @test in_spread(interp(s, w, r), spread)
                end
                # each is inside V7's MSE bound at λ = 2
                @test CALIBRATION_A.relaxation_mse(s, w, 1, REF_T, rw) <= MSE_FACTOR * MSE_S5[2]
            end
            # negative control: CC3D (λ = 5, T = 84) has the spec's MSE and fails the λ = 2 bound
            cc = gcurve(
                joinpath(R, "CompuCell3D", "Relaxation", "Tissue_Width_11_Cells.csv"), ",", "Time",
                "Tissue_Width(CD)"
            )
            mcc = CALIBRATION_A.relaxation_mse(cc..., 1, REF_T, rw)
            @test printed(mcc, G_MSE_CC3D, 4)
            @test mcc > MSE_FACTOR * MSE_S5[2]
            # V8 spreads from the 21-chain curves (TST, Morpheus-J10, Artistoo)
            c21 = (
                TST = (
                    gcurve(
                        joinpath(R, "TST", "Relaxation", "11+10cells", "width.csv"), ",",
                        "Normalized time (T)", "Mean Tissue width (CD)"
                    ),
                    gcurve(
                        joinpath(R, "TST", "Relaxation", "11+10cells", "inner_width.csv"), ",",
                        "Normalized time (T)", "Mean inner width (CD)"
                    ),
                ),
                Morpheus = (
                    gcurve(
                        joinpath(
                            R, "Morpheus", "Relaxation",
                            "Morpheus_1D_Relaxation_J10_11plus10_cells_tissue_N100stats.csv"
                        ), ",", 1, 2
                    ),
                    gcurve(
                        joinpath(
                            R, "Morpheus", "Relaxation",
                            "Morpheus_1D_Relaxation_J10_11plus10_cells_core_N100stats.csv"
                        ), ",", 1, 2
                    ),
                ),
                Artistoo = (
                    gcurve(joinpath(R, "Artistoo", "Relax", "average_sim2_21_cells.csv"), "\t", 1, 2),
                    gcurve(joinpath(R, "Artistoo", "Relax", "average_sim2_11_center_cells.csv"), "\t", 1, 2),
                ),
            )
            for name in keys(c21)
                (s, w), (si, wi) = c21[name]
                for (r, spread) in V8_W21
                    @test in_spread(interp(s, w, r), spread)
                end
                for (r, spread) in V8_INNER
                    @test in_spread(interp(si, wi, r), spread)
                end
                i0 = findfirst(>=(0), s)
                pe = s[i0 - 1 + findfirst(>=(w[i0] + PLATEAU_RISE), w[i0:end])]
                @test V8_PLATEAU[1] <= round(pe; digits = 2) <= V8_PLATEAU[2]
            end
        end
    end
end

@testitem "15 openvt calibration SMOKE: the 11-chain relaxes (λ = 2, 4 seeds)" setup = [OpenVTCalibrationSetup] tags = [:pottsmodels, :reproductions] begin
    if !CALIBRATION_FULL
        @testset "15 openvt calibration SMOKE: the 11-chain relaxes (λ = 2, 4 seeds)" begin
            seeds = [seed_smoke(i) for i in 1:4]
            run = runs(11, 2, seeds; tmax = 5 * T_S5[2])
            wbar = calibration_mean(run.W)
            @test !any(isnan, run.W)
            # t = 0 is the compressed chain: w ≈ 5, area ≈ 25 (P5)
            @test 4.7 <= wbar[1] <= 5.3
            @test all(a -> 23 <= a <= 27, run.area[1, :])
            # the mean rises monotonically over windows from ≈ 5 toward ≈ 10
            windows = (0:4, 35:45, 75:85, 150:160, 300:320, 700:775)
            wv = [window(run.t, wbar, r) for r in windows]
            @test all(diff(wv) .> 0)
            @test 7.5 <= wv[4] <= 9.8
            @test 9.5 <= wv[end] <= 10.3
            # and the cells are relaxed at the end: area near A = 50
            @test all(a -> 45 <= a <= 53, run.area[2, :])
            # every run relaxes, not only the mean
            @test all(j -> run.W[end, j] > 8.5, eachindex(seeds))
            # negative control: no release, no relaxation
            ctl = runs(11, 2, seeds; tmax = T_S5[2], release = false)
            @test window(ctl.t, calibration_mean(ctl.W), 150:155) < 6.0
        end
    end
    # ---------------------------------------------------------------------------------------------
    # FULL: V6, V7 (11-chain, λ ∈ {1, 2, 3, 5}) and V8 (21-chain, λ = 2), offline (D-146)
    # ---------------------------------------------------------------------------------------------
    if CALIBRATION_FULL
        @testset "15 openvt calibration FULL: V6, V7, V8" begin
            rw = [spring_dashpot_width(x; rate = RATE) for x in REF_T]
            T = Dict{Int, Int}()
            for λ in LAMBDAS
                # 7 × T_S5 MCS covers 5 T for any T up to 1.4 × Table S5
                run = runs(11, λ, [calibration_seed(λ, i) for i in 1:CALIBRATION_N]; tmax = 7 * T_S5[λ])
                wbar = calibration_mean(run.W)
                tc = CALIBRATION_A.crossing_time(run.t, wbar, LEVEL)
                tc === nothing || (T[λ] = tc)
                @testset "V6 T(λ = $λ)" begin
                    @test tc !== nothing && abs(tc / T_S5[λ] - 1) <= T_TOL
                end
                @testset "V7 shape (λ = $λ)" begin
                    # the run covers 5 T (else V6 has already failed by more than 40 %)
                    @test tc !== nothing && 5tc <= last(run.t)
                    if tc !== nothing && 5tc <= last(run.t)
                        @test CALIBRATION_A.relaxation_mse(run.t, wbar, tc, REF_T, rw) <=
                            MSE_FACTOR * MSE_S5[λ]
                        if λ == 2
                            for (r, spread) in V7_SPREAD
                                @test within(interp(run.t ./ tc, wbar, r), spread, V7_MARGIN)
                            end
                        end
                    end
                end
            end
            @testset "V6 monotone in λ" begin
                @test length(T) == length(LAMBDAS)
                length(T) == length(LAMBDAS) && @test all(diff([T[λ] for λ in LAMBDAS]) .< 0)
            end
            @testset "V8 21-chain with T from λ = 2 (no refit)" begin
                @test haskey(T, 2)
                if haskey(T, 2)
                    T2 = T[2]
                    run = runs(21, 2, [seed21(i) for i in 1:CALIBRATION_N]; tmax = 10T2)
                    wbar, ibar = calibration_mean(run.W), calibration_mean(run.In)
                    for (k, spread) in V8_W21
                        @test within(wbar[k * T2 + 1], spread, V8_MARGIN)
                    end
                    for (k, spread) in V8_INNER
                        @test within(ibar[k * T2 + 1], spread, V8_MARGIN)
                    end
                    pe = CALIBRATION_A.crossing_time(run.t, wbar, wbar[1] + PLATEAU_RISE)
                    @test pe !== nothing && V8_PLATEAU_BAND[1] <= pe / T2 <= V8_PLATEAU_BAND[2]
                end
            end
        end
    end
end
