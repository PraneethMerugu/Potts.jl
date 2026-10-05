# P6.15b (ROADMAP Step 3b): the OpenVT monolayer benchmark's mechanical calibration on 1D
# cell chains (M §2.2, Fig 2, Table S5). Frozen (AUTONOMY §7.3; D-148). The protocol is
# spec 15 §4.2.3 P1–P12 and the pre-registered targets are §4.1 V6–V8
# (docs/design/research/model-specs/15_openvt_monolayer.md v3); every reference value and
# pass band below is copied from there. The seeds, the SMOKE bands and the run lengths are
# the test author's (D-148). Gap G10 (spec §6).
#
# Surface fixed by the test author (implemented in P6.15b; open questions in D-148):
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
#     `contacts => J[kind, kind′]`; lattice periodic on both axes with Moore(1) (P1, P4);
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
using Potts, PottsModels, Test
using Statistics: mean

const P615B_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P615B_REPO = get(ENV, "OPENVT_MONOLAYER_REPO", "")
const P615B_A = PottsModels.Analysis

# ---------------------------------------------------------------------------------------------
# Constants, verbatim from spec 15
# ---------------------------------------------------------------------------------------------

const P615B_RATE = 18.2816647214633                 # k/η per T (§4.2.2, `relaxation_exact.m:4`)
# §4.2.2 / verification log: w(t) of the free 11-bead chain, 4 printed decimals
const P615B_REF_W = (0.1 => 6.0789, 0.5 => 7.9022, 1.0 => 9.0000, 2.0 => 9.7726, 5.0 => 9.9973)
const P615B_REF_PINNED = 7.17                       # §4.2.2: x₀ pinned, w(1)
const P615B_CD = 10                                 # C7: CD = 10 px
const P615B_BURNIN = 100                            # P5 (Morpheus, Artistoo)
const P615B_LEVEL = 9.0                             # P8: 90 % of 10 CD
const P615B_REF_T = collect(0:0.1:5)                # P9: the 51 points of relaxation_exact.csv
# V6 / Table S5 (M p.12): T(λ) in MCS and the MSE
const P615B_LAMBDAS = (1, 2, 3, 5)
const P615B_T_S5 = Dict(1 => 290, 2 => 155, 3 => 110, 5 => 75)
const P615B_MSE_S5 = Dict(1 => 7.570e-4, 2 => 2.664e-3, 3 => 4.433e-3, 5 => 1.378e-2)
const P615B_T_TOL = 0.15                            # V6: ±15 %
const P615B_MSE_FACTOR = 3                          # V7: ≤ 3 × Table S5
# V7: lattice spread of w₁₁ at 0.5 T and 2 T (TST, Morpheus-J10, Artistoo), ± 0.1 CD
const P615B_V7_SPREAD = (0.5 => (7.83, 7.87), 2.0 => (9.78, 9.80))
const P615B_V7_MARGIN = 0.1
# V8: lattice spread (CC3D, Morpheus-J10, TST, Artistoo) at 1 / 5 / 10 T, ± 0.15 CD
const P615B_V8_W21 = (1 => (15.90, 16.25), 5 => (19.20, 19.57), 10 => (19.90, 19.96))
const P615B_V8_INNER = (1 => (7.20, 7.51), 5 => (9.46, 9.71), 10 => (9.92, 9.96))
const P615B_V8_MARGIN = 0.15
const P615B_V8_PLATEAU = (0.15, 0.22)               # plateau end in T, data spread
const P615B_V8_PLATEAU_BAND = (0.1, 0.3)            # pass band
const P615B_PLATEAU_RISE = 0.05                     # plateau: w̄₂₁ < w̄₂₁(0) + 0.05
# P8/P9 applied to G's λ = 2 curves (§4.2.1, P9; T = 155): MSE as printed
const P615B_G_MSE = (TST = 1.26e-3, Morpheus = 1.59e-3, Artistoo = 7.4e-4)
const P615B_G_MSE_CC3D = 1.09e-2                    # CC3D (λ = 5, T = 84), P9

const P615B_N = P615B_FULL ? 100 : 4                # P7 (SMOKE: 4)
p615b_seed(λ::Integer, i::Integer) = 1000λ + i
p615b_seed21(i::Integer) = 21_000 + i
p615b_seed_smoke(i::Integer) = 90_000 + i
const P615B_ALG = SequentialCPM(; proposal = Moore(1))

# ---------------------------------------------------------------------------------------------
# Helpers (test-internal)
# ---------------------------------------------------------------------------------------------

# Linear interpolation of w (sampled at s, ascending) at r ∈ [s[1], s[end]]
function p615b_interp(s, w, r)
    s[1] <= r <= s[end] || throw(ArgumentError("p615b_interp: $r outside [$(s[1]), $(s[end])]"))
    j = searchsortedlast(s, r)
    j == length(s) && return float(w[j])
    return w[j] + (w[j + 1] - w[j]) * (r - s[j]) / (s[j + 1] - s[j])
end
p615b_within(x, (lo, hi), m) = lo - m <= x <= hi + m

# The expected initial chain (P2), painted by hand
function p615b_expected_chain(n)
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

p615b_state_σ(st) = Array(only(p.second for p in st if p.first === ownership))
p615b_state_kinds(st) = collect(only(p.second for p in st if p.first === kind))

# Runs of the n-chain at λ, one per seed, `tmax` MCS after the release; returns the spec
# time axis t = 0:tmax (MCS) and per-run w (and, for n = 21, the inner w₁₁) as matrices
# (time × run), plus the compressed cells' mean area at t = 0 and t = tmax.
function p615b_runs(n, λ, seeds; tmax, release = true)
    L = n == 11 ? 150 : 250
    sys = OpenVTChain(; name = Symbol(:p615b_chain, n), lattice = (L, 5), λ = Float64(λ))
    prob = PottsProblem(sys, openvt_chain(n), (0, P615B_BURNIN + tmax); seed = first(seeds))
    saves = P615B_BURNIN:(P615B_BURNIN + tmax)
    W = fill(NaN, length(saves), length(seeds))
    In = fill(NaN, length(saves), length(seeds))
    area = fill(NaN, 2, length(seeds))
    comp = n == 11 ? (1:11) : (6:16)
    Threads.@threads for j in eachindex(seeds)
        sol = solve(remake(prob; seed = seeds[j]), P615B_ALG; saveat = saves, save_start = false,
            callback = release ? openvt_release(P615B_BURNIN) : nothing)
        @assert collect(sol.t) == collect(saves)
        for (k, u) in enumerate(sol.u)
            xs = P615B_A.chain_centroids(u.σ)
            W[k, j] = (maximum(xs) - minimum(xs)) / P615B_CD
            n == 21 && (In[k, j] = (xs[16] - xs[6]) / P615B_CD)
        end
        for (r, u) in ((1, sol.u[1]), (2, sol.u[end]))
            area[r, j] = mean(count(==(c), u.σ) for c in comp)
        end
    end
    return (; t = collect(0:tmax), W, In, area)
end
p615b_mean(M) = vec(mean(M; dims = 2))

# ---------------------------------------------------------------------------------------------
# P11: the spring–dashpot reference (spec 15 §4.2.2)
# ---------------------------------------------------------------------------------------------

@testset "P6.15b P11: spring–dashpot reference (spec 15 §4.2.2)" begin
    @test abs(spring_dashpot_width(0.0; rate = P615B_RATE) - 5) <= 1e-12
    for (t, w) in P615B_REF_W
        @test abs(spring_dashpot_width(t; rate = P615B_RATE) - w) <= 5e-5
    end
    # k/η is the root of w(1) = 9 (`fzero`, `relaxation_exact.m:4`), and it is the default
    @test abs(spring_dashpot_width(1.0; rate = P615B_RATE) - 9) <= 1e-7
    @test spring_dashpot_width(1.0) == spring_dashpot_width(1.0; rate = P615B_RATE)
    @test spring_dashpot_width(1.0; rate = P615B_RATE, n = 11) == spring_dashpot_width(1.0; rate = P615B_RATE)
    # relaxed length n − 1 = 10 CD, approached monotonically from below
    ws = [spring_dashpot_width(t; rate = P615B_RATE) for t in 0:0.05:5]
    @test all(diff(ws) .> 0) && ws[end] < 10
    @test abs(spring_dashpot_width(20.0; rate = P615B_RATE) - 10) < 1e-6
    # negative control: one end pinned (the schema's "removal of one side constraint")
    wp = spring_dashpot_width(1.0; rate = P615B_RATE, pinned = true)
    @test abs(wp - P615B_REF_PINNED) <= 5e-3
    @test abs(wp - 9) > 1
end

@testset "P6.15b P11: relaxation_exact.csv (G)" begin
    path = joinpath(P615B_REPO, "results", "relaxation_exact.csv")
    if isempty(P615B_REPO) || !isfile(path)
        @test_skip isfile(path)
    else
        lines = filter(!isempty ∘ strip, readlines(path))
        @test lines[1] == "t,w"
        rows = [parse.(Float64, split(l, ',')) for l in lines[2:end]]
        @test length(rows) == 51
        @test all(isapprox(r[1], P615B_REF_T[k]; atol = 1e-12) for (k, r) in enumerate(rows))
        @test maximum(abs(spring_dashpot_width(r[1]; rate = P615B_RATE) - r[2]) for r in rows) <= 1e-6
    end
end

# ---------------------------------------------------------------------------------------------
# P1–P5: the model, the initial chains and the release
# ---------------------------------------------------------------------------------------------

@testset "P6.15b P1–P4: OpenVTChain (Table S1, periodic strip, Moore(1))" begin
    for (n, L) in ((11, 150), (21, 250))
        sys = OpenVTChain(; name = Symbol(:p615b_m, n), lattice = (L, 5))
        lat = Potts.lattice(sys)
        @test lat.dims == (L, 5)
        @test Potts.isperiodic(lat, 1) && Potts.isperiodic(lat, 2)
        prob = PottsProblem(sys, openvt_chain(n), (0, 1); seed = 1)
        par(x) = getp(prob, x)(prob)
        @test (par(:λ), par(:T), par(:A), par(:A_c)) == (2.0, 20.0, 50.0, 25.0)
        # kinds medium, compressed, relaxed: J_cc = 20, J_cm = 10 (Table S1)
        @test par(:J) == [0.0 10.0 10.0; 10.0 20.0 20.0; 10.0 20.0 20.0]
    end
    for λ in P615B_LAMBDAS
        sys = OpenVTChain(; name = Symbol(:p615b_l, λ), λ = Float64(λ))
        prob = PottsProblem(sys, openvt_chain(11), (0, 1); seed = 1)
        @test getp(prob, :λ)(prob) == λ
    end
    @test Potts.lattice(OpenVTChain(; name = :p615b_default)).dims == (150, 5)
end

@testset "P6.15b P2: initial chains (Morpheus placement and ids)" begin
    for n in (11, 21)
        st = openvt_chain(n)
        σ, kinds = p615b_state_σ(st), p615b_state_kinds(st)
        eσ, ek = p615b_expected_chain(n)
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
        @test P615B_A.chain_width(σ) == (n == 11 ? 5.0 : 14.5)
        xs = P615B_A.chain_centroids(σ)
        @test issorted(xs)
        n == 21 && @test (xs[16] - xs[6]) / P615B_CD == 5.0
        n == 21 && @test P615B_A.chain_width(σ, 6:16) == 5.0
    end
end

@testset "P6.15b P5: the release switches A_c at the end of MCS 100 (t = 0)" begin
    prob = PottsProblem(OpenVTChain(; name = :p615b_rel), openvt_chain(11), (0, 102); seed = 7)
    integ = init(prob, P615B_ALG; callback = openvt_release(P615B_BURNIN), saveat = [99, 100, 101],
        save_start = false)
    while integ.t < 99
        step!(integ)
    end
    @test integ.t == 99 && integ.ps[:A_c] == 25.0
    σ99 = copy(integ.u.σ)
    step!(integ)
    @test integ.t == 100 && integ.ps[:A_c] == 50.0 && integ.ps[:A] == 50.0
    # the callback changes the parameter only: the t = 0 state is the burn-in's end
    σ100 = copy(integ.u.σ)
    step!(integ)
    @test integ.ps[:A_c] == 50.0
    @test integ.saved_t == [99, 100, 101]
    @test integ.saved_u[1].σ == σ99 && integ.saved_u[2].σ == σ100
    # a different release time moves the switch
    integ2 = init(prob, P615B_ALG; callback = openvt_release(3))
    step!(integ2); step!(integ2)
    @test integ2.ps[:A_c] == 25.0
    step!(integ2)
    @test integ2.t == 3 && integ2.ps[:A_c] == 50.0
    # without the callback A_c stays 25
    integ3 = init(prob, P615B_ALG)
    for _ in 1:5
        step!(integ3)
    end
    @test integ3.ps[:A_c] == 25.0
end

# ---------------------------------------------------------------------------------------------
# P6: periodic centroids and chain widths on hand-built lattices
# ---------------------------------------------------------------------------------------------

@testset "P6.15b P6: Analysis.centroids with periodic axes" begin
    σ = zeros(Int, 10, 4)
    σ[[9, 10, 1, 2], 1:4] .= 1          # straddles the x seam
    σ[4:5, [4, 1]] .= 2                 # straddles the y seam
    σ[6:7, 2:3] .= 3                    # interior
    σ[3, 2] = 5                         # id 4 owns no site
    c = P615B_A.centroids(σ; periodic = (true, true))
    @test c[1][1] == 10.5               # sites 9, 10, 11, 12 ≡ 9, 10, 1, 2
    @test c[2] == (4.5, 4.5)            # rows 4, 5 ≡ 4, 1
    @test c[3] == (6.5, 2.5)
    @test all(isnan, c[4])
    @test c[5] == (3.0, 2.0)
    cx = P615B_A.centroids(σ; periodic = (true, false))
    @test cx[1] == (10.5, 2.5) && cx[2] == (4.5, 2.5) && cx[3] == (6.5, 2.5)
    # the default (and periodic = false) keep the plain mean of indices
    c0 = P615B_A.centroids(σ)
    @test c0[1] == (5.5, 2.5) && c0[2] == (4.5, 2.5)
    @test isequal(P615B_A.centroids(σ; periodic = (false, false)), c0)
    # wrapped into [1, n + 1): a cell at x ∈ {10, 1} is at 10.5, not 0.5
    τ = zeros(Int, 10, 1)
    τ[[10, 1]] .= 1
    @test P615B_A.centroids(τ; periodic = (true, false))[1] == (10.5, 1.0)
    # translation covariance on the periodic axis
    for s in 0:9
        cs = P615B_A.centroids(circshift(σ, (s, 0)); periodic = (true, true))
        @test all(mod(cs[k][1] - c[k][1] - s, 10) == 0 for k in (1, 2, 3, 5))
    end
end

@testset "P6.15b P6: chain_centroids and chain_width across the periodic seam" begin
    σA = zeros(Int, 30, 5)
    σA[5:9, :] .= 1
    σA[10:14, :] .= 2
    σA[15:24, :] .= 3
    xa = P615B_A.chain_centroids(σA)
    @test xa == [7.0, 12.0, 19.5]
    @test P615B_A.chain_width(σA) == 1.25
    @test P615B_A.chain_width(σA; CD = 1) == 12.5
    @test P615B_A.chain_width(σA, 1:2) == 0.5
    # the chain shifted by 20 crosses the seam: cell 2 straddles it, cell 3 is past it
    σB = circshift(σA, (20, 0))
    @test σB[30, 1] == 2 && σB[1, 1] == 2 && σB[10, 1] == 3
    @test P615B_A.chain_centroids(σB) == [27.0, 32.0, 39.5]
    @test P615B_A.chain_width(σB) == 1.25
    # negative control: the naive (wrapped) centroids get the width wrong here
    naive = [c[1] for c in P615B_A.centroids(σB; periodic = (true, true))]
    @test naive == [27.0, 2.0, 9.5]
    @test (maximum(naive) - minimum(naive)) / 10 == 2.5
    # every shift: same width, the leftmost cell in [1, 31), chain order kept
    for s in 0:29
        xs = P615B_A.chain_centroids(circshift(σA, (s, 0)))
        @test xs .- xs[1] == xa .- xa[1]
        @test 1 <= xs[1] < 31
        @test P615B_A.chain_width(circshift(σA, (s, 0))) == 1.25
    end
    # the published 11-chain anywhere on its strip
    σ11 = p615b_state_σ(openvt_chain(11))
    for s in (0, 50, 75, 100, 120, 149)
        @test P615B_A.chain_width(circshift(σ11, (s, 0))) == 5.0
    end
    # a stretched chain spanning most of the lattice: the largest gap still marks the ends
    σC = zeros(Int, 40, 2)
    for c in 1:6
        σC[mod1.((6c - 5 + 30):(6c - 2 + 30), 40), :] .= c   # 4 sites per cell, 2 medium between
    end
    @test P615B_A.chain_width(σC; CD = 1) == 30.0
end

# ---------------------------------------------------------------------------------------------
# P8 and P9 on synthetic curves with known answers
# ---------------------------------------------------------------------------------------------

@testset "P6.15b P8: crossing_time (first MCS with w ≥ 9)" begin
    t = collect(0:5)
    w = [5.0, 7.0, 8.99, 9.0, 8.5, 9.5]
    @test P615B_A.crossing_time(t, w) == 3                 # ≥, and the first crossing
    @test P615B_A.crossing_time(t, w, 8.0) == 2
    @test P615B_A.crossing_time(t .+ 100, w) == 103         # returns t, not the index
    @test P615B_A.crossing_time(t, fill(8.999, 6)) === nothing
    # on the reference sampled every MCS with T = 155 the crossing is MCS 155 (w = 9 there up
    # to rounding, so 156 is allowed)
    tt = collect(0:775)
    @test P615B_A.crossing_time(tt, [spring_dashpot_width(x / 155; rate = P615B_RATE) for x in tt]) in (155, 156)
end

@testset "P6.15b P9: relaxation_mse" begin
    rw = 5 .+ P615B_REF_T
    t = collect(0:775)
    w = 5 .+ t ./ 155
    @test P615B_A.relaxation_mse(t, w, 155, P615B_REF_T, rw) <= 1e-24
    @test abs(P615B_A.relaxation_mse(t, w .+ 0.1, 155, P615B_REF_T, rw) - 0.01) <= 1e-12
    # T scales time: w sampled at t = 0:1550 with T = 310 is the same curve
    t2 = collect(0:1550)
    @test P615B_A.relaxation_mse(t2, 5 .+ t2 ./ 310, 310, P615B_REF_T, rw) <= 1e-24
    # linear interpolation between coarse samples: s² on knots h = 0.3125 against s² at
    # the reference points; the interpolation error at s ∈ [a, a + h] is (s − a)(a + h − s)
    h = 0.3125
    tk = collect(0:50:800)                                  # T = 160, s = t / T = 0:h:5
    wk = (tk ./ 160) .^ 2
    expect = mean(((s - h * fld(s + 1e-12, h)) * (h * fld(s + 1e-12, h) + h - s))^2 for s in P615B_REF_T)
    @test abs(P615B_A.relaxation_mse(tk, wk, 160, P615B_REF_T, P615B_REF_T .^ 2) - expect) <= 1e-12
    @test expect > 1e-5                                     # the case is not trivial
    # the run must cover 0 … 5 T
    @test_throws ArgumentError P615B_A.relaxation_mse(collect(0:700), 5 .+ (0:700) ./ 155, 155, P615B_REF_T, rw)
    # the reference itself has MSE ≈ 0 against itself at T = 155
    wref = [spring_dashpot_width(x / 155; rate = P615B_RATE) for x in t]
    refw = [spring_dashpot_width(x; rate = P615B_RATE) for x in P615B_REF_T]
    @test P615B_A.relaxation_mse(t, wref, 155, P615B_REF_T, refw) < 1e-4
end

# ---------------------------------------------------------------------------------------------
# P8 / P9 and the V7 / V8 constants against the consortium's λ = 2 curves (G)
# ---------------------------------------------------------------------------------------------

# (s = t / T, w) columns of a G curve file
function p615b_gcurve(path, delim, tcol, wcol)
    lines = filter(!isempty ∘ strip, readlines(path))
    head = strip.(split(lines[1], delim), '"')
    it = tcol isa Integer ? tcol : findfirst(==(tcol), head)
    iw = wcol isa Integer ? wcol : findfirst(==(wcol), head)
    rows = [split(l, delim) for l in lines[2:end]]
    return [parse(Float64, r[it]) for r in rows], [parse(Float64, r[iw]) for r in rows]
end
# a G value matches the spec's printed value to half a unit of its last printed digit
p615b_printed(x, ref, digits) = abs(x - ref) <= 0.5 * 10.0^-digits * (1 + 1e-9)
p615b_in_spread(x, (lo, hi)) = lo <= round(x; digits = 2) <= hi

@testset "P6.15b P8/P9/V7/V8: the rules and constants on G's curves (G)" begin
    R = joinpath(P615B_REPO, "results")
    if isempty(P615B_REPO) || !isdir(R)
        @test_skip isdir(R)
    else
        rw = [spring_dashpot_width(x; rate = P615B_RATE) for x in P615B_REF_T]
        c11 = (TST = p615b_gcurve(joinpath(R, "TST", "Relaxation", "11cells", "width.csv"), ",",
                "Normalized time (T)", "Mean Tissue width (CD)"),
            Morpheus = p615b_gcurve(joinpath(R, "Morpheus", "Relaxation",
                    "Morpheus_1D_Relaxation_J10_11_cells_N100stats.csv"), ",", 1, 2),
            Artistoo = p615b_gcurve(joinpath(R, "Artistoo", "Relax", "average_sim1_11_cells.csv"), "\t", 1, 2))
        for name in keys(c11)
            s, w = c11[name]
            # P9 on s = t / T (T = 1) reproduces the spec's MSE (P9)
            @test p615b_printed(P615B_A.relaxation_mse(s, w, 1, P615B_REF_T, rw), P615B_G_MSE[name], 5)
            # P8 on whole MCS (t = round(155 s)) gives T within 1 % of 155 (V6 at λ = 2)
            k = findall(>=(0), s)
            tc = P615B_A.crossing_time(round.(Int, 155 .* s[k]), w[k])
            @test tc !== nothing && abs(tc / 155 - 1) <= 0.01
            # V7 spread
            for (r, spread) in P615B_V7_SPREAD
                @test p615b_in_spread(p615b_interp(s, w, r), spread)
            end
            # each is inside V7's MSE bound at λ = 2
            @test P615B_A.relaxation_mse(s, w, 1, P615B_REF_T, rw) <= P615B_MSE_FACTOR * P615B_MSE_S5[2]
        end
        # negative control: CC3D (λ = 5, T = 84) has the spec's MSE and fails the λ = 2 bound
        cc = p615b_gcurve(joinpath(R, "CompuCell3D", "Relaxation", "Tissue_Width_11_Cells.csv"), ",", "Time",
            "Tissue_Width(CD)")
        mcc = P615B_A.relaxation_mse(cc..., 1, P615B_REF_T, rw)
        @test p615b_printed(mcc, P615B_G_MSE_CC3D, 4)
        @test mcc > P615B_MSE_FACTOR * P615B_MSE_S5[2]
        # V8 spreads from the 21-chain curves (TST, Morpheus-J10, Artistoo)
        c21 = (TST = (p615b_gcurve(joinpath(R, "TST", "Relaxation", "11+10cells", "width.csv"), ",",
                    "Normalized time (T)", "Mean Tissue width (CD)"),
                p615b_gcurve(joinpath(R, "TST", "Relaxation", "11+10cells", "inner_width.csv"), ",",
                    "Normalized time (T)", "Mean inner width (CD)")),
            Morpheus = (p615b_gcurve(joinpath(R, "Morpheus", "Relaxation",
                        "Morpheus_1D_Relaxation_J10_11plus10_cells_tissue_N100stats.csv"), ",", 1, 2),
                p615b_gcurve(joinpath(R, "Morpheus", "Relaxation",
                        "Morpheus_1D_Relaxation_J10_11plus10_cells_core_N100stats.csv"), ",", 1, 2)),
            Artistoo = (p615b_gcurve(joinpath(R, "Artistoo", "Relax", "average_sim2_21_cells.csv"), "\t", 1, 2),
                p615b_gcurve(joinpath(R, "Artistoo", "Relax", "average_sim2_11_center_cells.csv"), "\t", 1, 2)))
        for name in keys(c21)
            (s, w), (si, wi) = c21[name]
            for (r, spread) in P615B_V8_W21
                @test p615b_in_spread(p615b_interp(s, w, r), spread)
            end
            for (r, spread) in P615B_V8_INNER
                @test p615b_in_spread(p615b_interp(si, wi, r), spread)
            end
            i0 = findfirst(>=(0), s)
            pe = s[i0 - 1 + findfirst(>=(w[i0] + P615B_PLATEAU_RISE), w[i0:end])]
            @test P615B_V8_PLATEAU[1] <= round(pe; digits = 2) <= P615B_V8_PLATEAU[2]
        end
    end
end

# ---------------------------------------------------------------------------------------------
# SMOKE: λ = 2, 4 seeds, 5 × 155 MCS after the release
# ---------------------------------------------------------------------------------------------

# mean of the replicate-mean curve over the MCS window `r` (spec time)
p615b_window(t, wbar, r) = mean(wbar[k] for k in eachindex(t) if t[k] in r)

if !P615B_FULL
    @testset "P6.15b SMOKE: the 11-chain relaxes (λ = 2, 4 seeds)" begin
        seeds = [p615b_seed_smoke(i) for i in 1:4]
        run = p615b_runs(11, 2, seeds; tmax = 5 * P615B_T_S5[2])
        wbar = p615b_mean(run.W)
        @test !any(isnan, run.W)
        # t = 0 is the compressed chain: w ≈ 5, area ≈ 25 (P5)
        @test 4.7 <= wbar[1] <= 5.3
        @test all(a -> 23 <= a <= 27, run.area[1, :])
        # the mean rises monotonically over windows from ≈ 5 toward ≈ 10
        windows = (0:4, 35:45, 75:85, 150:160, 300:320, 700:775)
        wv = [p615b_window(run.t, wbar, r) for r in windows]
        @test all(diff(wv) .> 0)
        @test 7.5 <= wv[4] <= 9.8
        @test 9.5 <= wv[end] <= 10.3
        # and the cells are relaxed at the end: area near A = 50
        @test all(a -> 45 <= a <= 53, run.area[2, :])
        # every run relaxes, not only the mean
        @test all(j -> run.W[end, j] > 8.5, eachindex(seeds))
        # negative control: no release, no relaxation
        ctl = p615b_runs(11, 2, seeds; tmax = P615B_T_S5[2], release = false)
        @test p615b_window(ctl.t, p615b_mean(ctl.W), 150:155) < 6.0
    end
end

# ---------------------------------------------------------------------------------------------
# FULL: V6, V7 (11-chain, λ ∈ {1, 2, 3, 5}) and V8 (21-chain, λ = 2), offline (D-146)
# ---------------------------------------------------------------------------------------------

if P615B_FULL
    @testset "P6.15b FULL: V6, V7, V8" begin
        rw = [spring_dashpot_width(x; rate = P615B_RATE) for x in P615B_REF_T]
        T = Dict{Int, Int}()
        for λ in P615B_LAMBDAS
            # 7 × T_S5 MCS covers 5 T for any T up to 1.4 × Table S5
            run = p615b_runs(11, λ, [p615b_seed(λ, i) for i in 1:P615B_N]; tmax = 7 * P615B_T_S5[λ])
            wbar = p615b_mean(run.W)
            tc = P615B_A.crossing_time(run.t, wbar, P615B_LEVEL)
            tc === nothing || (T[λ] = tc)
            @testset "V6 T(λ = $λ)" begin
                @test tc !== nothing && abs(tc / P615B_T_S5[λ] - 1) <= P615B_T_TOL
            end
            @testset "V7 shape (λ = $λ)" begin
                # the run covers 5 T (else V6 has already failed by more than 40 %)
                @test tc !== nothing && 5tc <= last(run.t)
                if tc !== nothing && 5tc <= last(run.t)
                    @test P615B_A.relaxation_mse(run.t, wbar, tc, P615B_REF_T, rw) <=
                          P615B_MSE_FACTOR * P615B_MSE_S5[λ]
                    if λ == 2
                        for (r, spread) in P615B_V7_SPREAD
                            @test p615b_within(p615b_interp(run.t ./ tc, wbar, r), spread, P615B_V7_MARGIN)
                        end
                    end
                end
            end
        end
        @testset "V6 monotone in λ" begin
            @test length(T) == length(P615B_LAMBDAS)
            length(T) == length(P615B_LAMBDAS) && @test all(diff([T[λ] for λ in P615B_LAMBDAS]) .< 0)
        end
        @testset "V8 21-chain with T from λ = 2 (no refit)" begin
            @test haskey(T, 2)
            if haskey(T, 2)
                T2 = T[2]
                run = p615b_runs(21, 2, [p615b_seed21(i) for i in 1:P615B_N]; tmax = 10T2)
                wbar, ibar = p615b_mean(run.W), p615b_mean(run.In)
                for (k, spread) in P615B_V8_W21
                    @test p615b_within(wbar[k * T2 + 1], spread, P615B_V8_MARGIN)
                end
                for (k, spread) in P615B_V8_INNER
                    @test p615b_within(ibar[k * T2 + 1], spread, P615B_V8_MARGIN)
                end
                pe = P615B_A.crossing_time(run.t, wbar, wbar[1] + P615B_PLATEAU_RISE)
                @test pe !== nothing && P615B_V8_PLATEAU_BAND[1] <= pe / T2 <= P615B_V8_PLATEAU_BAND[2]
            end
        end
    end
end
