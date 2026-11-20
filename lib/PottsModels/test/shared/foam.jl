using Potts, PottsModels, Test
using Statistics: mean, median, std
const FOAM_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const DATA = joinpath(pkgdir(PottsModels), "reproductions", "data", "04")
const RECORD_OUT = get(ENV, "RECORD_OUT", "")
const FOAM_AN = PottsModels.Analysis
# ---------------------------------------------------------------------------------------------
# Constants (pre-registered)
# ---------------------------------------------------------------------------------------------
const FOAM_L = (256, 256)
const L_LOW = (320, 320)
# DV4: d095, d107
const BRICK = 16
const FOAM_J = 3.0
const FOAM_Γ = 1.0
const FOAM_T0 = 1.0e-6
# T → 0⁺ (A-6, DV2)
const FOAM_TA, FOAM_NA, FOAM_NR = 3.0, 10, 1000
# anneal T, MCS; relax MCS (A-8)
const FOAM_TC, CHECK, CMAX = 3.0, 10, 20_000
# coarsening T, μ2 read cadence, cap (A-8)
const PREP_TOL, TRIES = 0.3, 5
const PERIOD, CYCLES, NBIN = 4000, 10, 40
# paper MCS per period
const TSPEC, T14, T16 = 2^17, 2^15, 10_000
const TV2, TV9 = 10_000, 5000
const REPS = 5
const MID = 32.0
const FOAMS = (
    ordered = (target = 0.0, L = FOAM_L, code = 0), d081 = (target = 0.81, L = FOAM_L, code = 1),
    d095 = (target = 0.95, L = L_LOW, code = 2), d107 = (target = 1.07, L = L_LOW, code = 3),
    d165 = (target = 1.65, L = FOAM_L, code = 4), d172 = (target = 1.72, L = FOAM_L, code = 5),
    d202 = (target = 2.02, L = FOAM_L, code = 6),
)
const SCAN_J = [1.0, 3.0, 5.0, 10.0]
const CAL_R = 2.0 .^ (-2:0.25:6)
# κ stage: model γ0/J at J = 3 (0.25 … 64)
const SCAN_R = collect(0.25:0.25:6.0)
# V5 stage: paper γ0/J, model γ0 = κ·J·r
const BETAS = [0.001, 0.005, 0.01, 0.02, 0.05]
const BETAS14 = [1.0e-4, 1.0e-3, 5.0e-3, 1.0e-2, 5.0e-2]
const V6_T = [FOAM_T0, 5.0, 10.0, 15.0]
const BIN_EDGES = 10 .^ (-5.2:0.05:-0.3)
const C_YIELD = 0.023
# spec §3.2 c (info only)

# seeds: foam k of kind f, try t; run (block, index, replicate)
prep_seed(f::Symbol, k, t = 0) = 4_000_000 + 100_000 * FOAMS[f].code + 100k + t
run_seed(block, idx, k) = 5_000_000 + 1_000_000block + 10idx + k
smoke_seed(k) = 9_400_000 + k
const BLOCK = (scan = 1, v3 = 2, v4 = 3, v6 = 4, v2 = 5, v9 = 6, v9c = 7, spec = 8, v14 = 9, v16 = 10, v16c = 11, cal = 12)
# ---------------------------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------------------------
@potts_model ReferenceUnshearedFoam begin
    @structural_parameters begin
        lattice = (256, 256)
    end
    @kinds medium bubble
    @parameters begin
        J = 3.0
        Γ = 1.0
        T = 1.0e-6
    end
    @variables begin
        A(cell) = 256.0
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    @sweep Metropolis(; temperature = T)
end
# Eq. 1 + Eq. 2 in the displacement form (A-1). ytop = L_y and ymid = (L_y + 1)/2 are set
# per lattice by foam_problem. bulk = 1: Eq. 7; else Eq. 6. periodic = 1: G = sin(ω mcs).
const SHEAR_EXPR = :(
    @potts_model ReferenceShearedFoam begin
        @structural_parameters begin
            lattice = (256, 256)
        end
        @kinds medium bubble
        @parameters begin
            J = 3.0
            Γ = 1.0
            T = 1.0e-6
            γ0 = 0.0
            β = 0.0
            bulk = 0.0
            periodic = 0.0
            ω = 2π / 4000
            ytop = 256.0
            ymid = 128.5
        end
        @variables begin
            A(cell) = 256.0
        end
        @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
        @relations proposal = NeighborOrder(4)
        @energy begin
            contacts => J
            cells(bubble) => Γ * (volume - A)^2
        end
        @drive copy => ifelse(periodic > 0.5, sin(ω * mcs), 1.0) *
            ifelse(
            bulk > 0.5, -β * (position[target][2] - ymid),
            γ0 * (ifelse(position[target][2] < 1.5, 1.0, 0.0) - ifelse(position[target][2] > ytop - 0.5, 1.0, 0.0))
        ) *
            direction[1]
        @sweep Metropolis(; temperature = T)
    end
)
Core.eval(@__MODULE__, SHEAR_EXPR)
const ALG = SequentialCPM(; skip_interior = true)
const TEMPLATES = Dict{Tuple{Bool, Tuple{Int, Int}}, Any}()
function brick(L)
    return Int32[
            (r = (y - 1) ÷ BRICK; r * (L[1] ÷ BRICK) + mod(x - 1 - (isodd(r) ? BRICK ÷ 2 : 0), L[1]) ÷ BRICK + 1)
                for x in 1:L[1], y in 1:L[2]
        ]
end
foam_lat(L) = Lattice(L; boundary = (Periodic(), Closed()))
"""The template problem of (shear?, L); built once, outside any threaded loop."""
function foam_template(shear::Bool, L)
    return get!(TEMPLATES, (shear, L)) do
        σ = brick(L)
        n = Int(maximum(σ))
        op = Pair[ownership => σ, kind => fill(:bubble, n), :A => fill(256.0, n)]
        if shear
            M = Base.invokelatest(getfield, @__MODULE__, :ReferenceShearedFoam)
            sys = Base.invokelatest(() -> M(; name = :foam_shear, lattice = L))
            append!(op, [:ytop => Float64(L[2]), :ymid => (L[2] + 1) / 2])
        else
            sys = ReferenceUnshearedFoam(; name = :foam, lattice = L)
        end
        PottsProblem(sys, op, (0, 1); seed = 1)
    end
end
"""A problem from a state (; ownership = σ, A) for `tend` MCS. Every parameter is set explicitly."""
function foam_problem(
        st, tend; shear = false, J = FOAM_J, Γ = FOAM_Γ, T = FOAM_T0, γ0 = 0.0, β = 0.0,
        bulk = false, periodic = false, ω = 2π / PERIOD, seed
    )
    L = size(st.ownership)
    n = length(st.A)
    n == maximum(st.ownership) || throw(ArgumentError("foam_problem: A has $n entries, the largest id is $(maximum(st.ownership))"))
    p = Pair{Symbol, Float64}[:J => J, :Γ => Γ, :T => T]
    shear && append!(
        p, [
            :γ0 => γ0, :β => β, :bulk => Float64(bulk), :periodic => Float64(periodic), :ω => ω,
            :ytop => Float64(L[2]), :ymid => (L[2] + 1) / 2,
        ]
    )
    return remake(
        TEMPLATES[(shear, L)]; u0 = Pair[ownership => st.ownership, kind => fill(:bubble, n), :A => st.A], p,
        tspan = (0, tend), seed
    )
end
# ---------------------------------------------------------------------------------------------
# Observables on a state
# ---------------------------------------------------------------------------------------------
"""Per-bubble site count, centroid y and edge flag; ids 1:n."""
function foam_cells(σ, n)
    Y = size(σ, 2)
    cnt = zeros(Int, n)
    sy = zeros(n)
    edge = falses(n)
    for y in 1:Y, x in 1:size(σ, 1)
        c = σ[x, y]
        cnt[c] += 1
        sy[c] += y
        (y == 1 || y == Y) && (edge[c] = true)
    end
    return (; cnt, cy = sy ./ max.(cnt, 1), edge)
end
"""n per id 1:n (0 for ids above maximum(σ))."""
sides(σ, lat, n) = (s = FOAM_AN.side_counts(σ, lat); [c <= length(s) ? s[c] : 0 for c in 1:n])
"""Interior hexagons, interior bubbles, and the non-hexagonal interior bubbles mid / away."""
function frame(σ, lat, n)
    c = foam_cells(σ, n)
    s = sides(σ, lat, n)
    ymid = (size(σ, 2) + 1) / 2
    hex = tot = mid = away = 0
    for b in 1:n
        (c.cnt[b] > 0 && !c.edge[b]) || continue
        tot += 1
        if s[b] == 6
            hex += 1
        elseif abs(c.cy[b] - ymid) <= MID
            mid += 1
        else
            away += 1
        end
    end
    return (; hex, tot, mid, away)
end
hexfrac(σ, n) = (f = frame(σ, foam_lat(size(σ)), n); f.hex / f.tot)
foam_mu2n(σ) = FOAM_AN.topology_moments(σ, foam_lat(size(σ))).mu2_n
"""V19: E_a / (E_a + J φ)."""
function foam_area_frac(σ, vol, A; J = FOAM_J)
    Ea = FOAM_Γ * sum((vol[c] - A[c])^2 for c in eachindex(A) if vol[c] > 0; init = 0.0)
    return Ea / (Ea + J * FOAM_AN.stored_energy(σ, foam_lat(size(σ))))
end
foam_vol(u, n) = Float64.(u.cell.volume[1:n])
const FOAM_N4 = [(a, b) for a in -2:2 for b in -2:2 if 0 < a^2 + b^2 <= 5]
# NeighborOrder(4): 20 offsets
"""ū: the mean over boundary sites (≥ 1 unlike site among the 20 offsets, on the lattice:
periodic x, closed y) of the unlike share, unlike / 20. τ = 1/ū (A-5)."""
function foam_ubar(σ)
    X, Y = size(σ)
    s = 0.0
    nb = 0
    for x in 1:X, y in 1:Y
        u = 0
        for (a, b) in FOAM_N4
            q = y + b
            1 <= q <= Y || continue
            u += σ[x, y] != σ[mod1(x + a, X), q]
        end
        u > 0 && (s += u / 20; nb += 1)
    end
    return s / nb
end
# ---------------------------------------------------------------------------------------------
# Foams
# ---------------------------------------------------------------------------------------------
function foam_ordered(seed; L = FOAM_L)
    σ0 = brick(L)
    n = Int(maximum(σ0))
    A = fill(Float64(BRICK^2), n)
    u = solve(foam_problem((; ownership = σ0, A), FOAM_NA; T = FOAM_TA, seed), ALG).u[end]
    u = solve(foam_problem((; ownership = Array(u.ownership), A), FOAM_NR; seed), ALG).u[end]
    return (; ownership = Array(u.ownership), A, stop = 0)
end
function disordered(target, seed; L = FOAM_L)
    o = foam_ordered(seed; L)
    n = length(o.A)
    integ = init(foam_problem(o, CMAX; T = FOAM_TC, Γ = 0.0, seed), ALG)
    m = 0
    while m < CMAX
        for _ in 1:CHECK
            step!(integ)
        end
        m += CHECK
        foam_mu2n(Array(current_state(integ).ownership)) >= target && break
    end
    σc = Array(current_state(integ).ownership)
    A = foam_vol(current_state(integ), n)[1:Int(maximum(σc))]                # ids above the largest survivor are dropped
    u = solve(foam_problem((; ownership = σc, A), FOAM_NR; seed), ALG).u[end]
    return (; ownership = Array(u.ownership), A, stop = m)
end
"""Foam k of kind f with its PREP row (tries until accepted, at most TRIES)."""
function make_foam(f::Symbol, k; seedf = t -> prep_seed(f, k, t))
    spec = FOAMS[f]
    local st, mu, t
    for outer t in 0:(TRIES - 1)
        st = f === :ordered ? foam_ordered(seedf(t); spec.L) : disordered(spec.target, seedf(t); spec.L)
        mu = foam_mu2n(st.ownership)
        (f === :ordered || abs(mu - spec.target) <= PREP_TOL) && break
    end
    m = FOAM_AN.topology_moments(st.ownership, foam_lat(size(st.ownership)))
    n = length(st.A)
    row = Dict{String, Any}(
        "foam" => string(f), "k" => k, "seed" => seedf(t), "try" => t, "ly" => size(st.ownership, 2),
        "target" => spec.target, "mu2n" => m.mu2_n, "mu2a" => m.mu2_a, "nbub" => count(>(0), foam_cells(st.ownership, n).cnt),
        "hex" => hexfrac(st.ownership, n), "area_frac" => foam_area_frac(st.ownership, Float64.(foam_cells(st.ownership, n).cnt), st.A),
        "stop" => st.stop, "ok" => f === :ordered || abs(m.mu2_n - spec.target) <= PREP_TOL,
        "ubar" => foam_ubar(st.ownership)
    )
    return (; ownership = st.ownership, A = st.A), row
end
# ---------------------------------------------------------------------------------------------
# Rules (pure functions of series; checked on synthetic input below)
# ---------------------------------------------------------------------------------------------
"""Zigzag extrema with threshold h: confirmed peaks and their troughs (index vectors)."""
function zigzag(x, h)
    peaks, troughs = Int[], Int[]
    isempty(x) && return peaks, troughs
    up = true
    imax = imin = 1
    for i in 2:length(x)
        if up
            x[i] > x[imax] && (imax = i)
            if x[imax] - x[i] >= h
                push!(peaks, imax)
                up = false
                imin = i
            end
        else
            x[i] < x[imin] && (imin = i)
            if x[i] - x[imin] >= h
                push!(troughs, imin)
                up = true
                imax = i
            end
        end
    end
    up || push!(troughs, imin)
    return peaks, troughs
end
drops(x, h) = ((p, t) = zigzag(x, h); [x[p[i]] - x[t[i]] for i in eachindex(p)])
"""Bursts of non-zero bins (single empty bins bridged) and the share of empty bins."""
function foam_bursts(c)
    n = length(c)
    bursts = 0
    i = 1
    while i <= n
        if c[i] > 0
            bursts += 1
            j = i
            while true
                if j + 1 <= n && c[j + 1] > 0
                    j += 1
                elseif j + 2 <= n && c[j + 1] == 0 && c[j + 2] > 0
                    j += 2
                else
                    break
                end
            end
            i = j + 1
        else
            i += 1
        end
    end
    return (; bursts, quiet = n == 0 ? 0.0 : count(==(0), c) / n)
end
"""The first crossing of v ≥ thr along r, linearly interpolated; nothing if v never reaches
thr or already does at r[1] (the boundary is not resolved by the grid)."""
function foam_crossing(r, v, thr)
    i = findfirst(>=(thr), v)
    (i === nothing || i == 1) && return nothing
    return r[i - 1] + (thr - v[i - 1]) / (v[i] - v[i - 1]) * (r[i] - r[i - 1])
end
function ranks(x)
    p = sortperm(x)
    r = similar(x, Float64)
    for (j, i) in enumerate(p)
            r[i] = j
        end
    return [mean(r[findall(==(x[i]), x)]) for i in eachindex(x)]
end
function spearman(x, y)
    a, b = ranks(x), ranks(y)
    return sum((a .- mean(a)) .* (b .- mean(b))) / sqrt(sum(abs2, a .- mean(a)) * sum(abs2, b .- mean(b)))
end
ols(x, y) = (xm = mean(x); ym = mean(y); s = sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm); (a = ym - s * xm, s = s))
"""Log-binned spectrum (20 bins per decade)."""
function foam_bin(f, S)
    E = BIN_EDGES
    fb, Sb = Float64[], Float64[]
    for i in 1:(length(E) - 1)
        idx = findall(x -> E[i] <= x < E[i + 1], f)
        isempty(idx) && continue
        push!(fb, 10^mean(log10.(f[idx])))
        push!(Sb, mean(S[idx]))
    end
    return fb, Sb
end
"""α over [lo, hi] on positive bins; NaN if fewer than 2."""
function alpha(fb, Sb, lo, hi)
    k = findall(i -> lo <= fb[i] <= hi && Sb[i] > 0, eachindex(fb))
    length(k) < 2 && return NaN
    return FOAM_AN.spectral_exponent(fb[k], Sb[k], (lo, hi))
end
"""Largest α over the 1-decade windows [f_b, 10 f_b], lo ≤ f_b ≤ hi (and 10 f_b ≤ 0.5); NaN
if any window has no α (an empty spectrum cannot pass a "no power law" row)."""
function window_alpha(fb, Sb, lo, hi)
    a = [alpha(fb, Sb, f, 10f) for f in fb if lo <= f <= hi && 10f <= 0.5]
    return isempty(a) || any(isnan, a) ? NaN : maximum(a)
end
"""V7 (iii) peak on a raw periodogram."""
function foam_peak(f, S)
    sm = [mean(S[max(1, i - 2):min(end, i + 2)]) for i in eachindex(S)]
    k = findall(x -> 2.0e-4 <= x <= 5.0e-3, f)
    i = k[argmax(sm[k])]
    return (; f = f[i], prom = sm[i] / median(S[k]))
end
bincentre_strain(b) = sinpi(2(b - 0.5) / NBIN)
# ---------------------------------------------------------------------------------------------
# Runs. Durations are in paper MCS; our MCS m is paper time m/τ (A-5).
# ---------------------------------------------------------------------------------------------
"""Paper bin of width w (paper MCS) that our MCS m (1-based) falls in, at time scale τ."""
pbin(m, w, τ) = floor(Int, (m - 1) / (w * τ)) + 1
"""Our MCS that cover `tp` paper MCS."""
ours(tp, τ) = ceil(Int, tp * τ)
"""Periodic boundary shear, 10 periods of 4000 paper MCS (V3–V6, the calibration and the scan)."""
function foam_loop(st, J, γ0m, T, seed, τ)
    lat = foam_lat(size(st.ownership))
    P = ours(PERIOD, τ)                                # one period in our MCS
    integ = init(
        foam_problem(st, CYCLES * P; shear = true, J, T, γ0 = γ0m, periodic = true, ω = 2π / P, seed),
        ALG
    )
    φ0 = FOAM_AN.stored_energy(st.ownership, lat)
    g = FOAM_AN.cell_graph(st.ownership, lat)
    t1 = zeros(CYCLES)
    acc = zeros(CYCLES, NBIN)
    cnt = zeros(Int, CYCLES, NBIN)
    all = Float64[]
    for m in 1:(CYCLES * P)
        step!(integ)
        σ = current_state(integ).ownership
        g2 = FOAM_AN.cell_graph(σ, lat)
        c = (m - 1) ÷ P + 1
        t1[c] += FOAM_AN.t1_events(g, g2; unit = :t1)
        g = g2
        if m % 10 == 0
            v = FOAM_AN.stored_energy(σ, lat) / φ0
            b = floor(Int, NBIN * mod(m, P) / P) + 1
            acc[c, b] += v
            cnt[c, b] += 1
            push!(all, v)
        end
    end
    per = acc ./ max.(cnt, 1)                                   # per-period bin means
    return Dict{String, Any}(
        "J" => J, "gamma0" => γ0m, "T" => T, "seed" => seed, "t1_cycles" => t1,
        "phi_bins" => vec(mean(per; dims = 1)), "phi_noise" => mean(std(per[:, b]) for b in 1:NBIN),
        "phi_mean" => mean(all)
    )
end
"""Steady boundary shear for `tp` paper MCS (V2, V9): 50-MCS bins of T1s, φ̂ and frames."""
function foam_steady(st, γ0m, tp, seed, τ)
    n = length(st.A)
    lat = foam_lat(size(st.ownership))
    T = ours(tp, τ)
    nb = tp ÷ 50
    integ = init(foam_problem(st, T; shear = true, γ0 = γ0m, seed), ALG)
    φ0 = FOAM_AN.stored_energy(st.ownership, lat)
    g = FOAM_AN.cell_graph(st.ownership, lat)
    N = zeros(T)
    t1 = zeros(nb)
    phi = fill(NaN, nb)
    hexp = hext = 0
    changed = Set{Int}()
    cmax = 0.0
    for m in 1:T
        step!(integ)
        σ = current_state(integ).ownership
        g2 = FOAM_AN.cell_graph(σ, lat)
        N[m] = FOAM_AN.t1_events(g, g2; unit = :t1)
        cc = FOAM_AN.contact_changes(g, g2)
        for (a, b) in Iterators.flatten((cc.lost, cc.gained))
            push!(changed, a, b)
        end
        g = g2
        i = min(pbin(m, 50, τ), nb)
        t1[i] += N[m]
        if m == T || pbin(m + 1, 50, τ) > i                     # the last MCS of a 50-MCS bin
            phi[i] = FOAM_AN.stored_energy(σ, lat) / φ0
            fr = frame(σ, lat, n)
            hexp += fr.hex
            hext += fr.tot
        end
        if m == T || pbin(m + 1, 100, τ) > pbin(m, 100, τ)     # the last MCS of a 100-MCS window
            cmax = max(cmax, length(changed) / count(>(0), foam_cells(σ, n).cnt))
            empty!(changed)
        end
    end
    tf = FOAM_AN.yield_strain(collect(1:T) ./ τ, N; threshold = 1, window = round(Int, 100τ))
    return Dict{String, Any}(
        "gamma0" => γ0m, "seed" => seed, "t1_50" => t1, "phi_50" => phi, "hex_pairs" => hexp,
        "hex_total" => hext, "t_first" => tf === nothing ? -1 : round(Int, tf), "changed_max" => cmax
    )
end
"""Steady bulk shear at paper β (model κβ) for `tp` paper MCS: run row, 100-MCS windows and
(spectral runs) the binned spectra in cycles per paper MCS."""
function foam_bulk(st, βp, κ, tp, seed, τ; spectra = false)
    n = length(st.A)
    lat = foam_lat(size(st.ownership))
    T = ours(tp, τ)
    nw = tp ÷ 100
    integ = init(foam_problem(st, T; shear = true, β = κ * βp, bulk = true, seed), ALG)
    φ0 = FOAM_AN.stored_energy(st.ownership, lat)
    g = FOAM_AN.cell_graph(st.ownership, lat)
    nb0 = count(>(0), foam_cells(st.ownership, n).cnt)
    N = zeros(T)
    Φ = spectra ? zeros(T) : Float64[]
    W = Dict{String, Any}[]
    changed = Set{Int}()
    tw = 0.0
    for m in 1:T
        step!(integ)
        σ = current_state(integ).ownership
        g2 = FOAM_AN.cell_graph(σ, lat)
        N[m] = FOAM_AN.t1_events(g, g2; unit = :t1)
        cc = FOAM_AN.contact_changes(g, g2)
        for (a, b) in Iterators.flatten((cc.lost, cc.gained))
            push!(changed, a, b)
        end
        g = g2
        tw += N[m]
        spectra && (Φ[m] = FOAM_AN.stored_energy(σ, lat) / φ0)
        w = pbin(m, 100, τ)
        if w <= nw && (m == T || pbin(m + 1, 100, τ) > w)
            fr = frame(σ, lat, n)
            vol = foam_vol(current_state(integ), n)
            push!(
                W, Dict{String, Any}(
                    "w" => w, "t1" => tw,
                    "phi" => spectra ? Φ[m] : FOAM_AN.stored_energy(σ, lat) / φ0, "mu2n" => foam_mu2n(σ),
                    "nonhex_mid" => fr.mid, "nonhex_away" => fr.away,
                    "changed_frac" => length(changed) / count(>(0), vol), "area_frac" => foam_area_frac(σ, vol, st.A)
                )
            )
            empty!(changed)
            tw = 0.0
        end
    end
    tf = FOAM_AN.yield_strain(collect(1:T) ./ τ, N; threshold = 1, window = round(Int, 100τ))
    run = Dict{String, Any}(
        "beta" => βp, "beta_model" => κ * βp, "seed" => seed, "mcs" => tp, "nbub" => nb0,
        "mu2n0" => foam_mu2n(st.ownership), "t1_total" => sum(N), "t_first" => tf === nothing ? -1 : round(Int, tf),
        "peak_f" => NaN, "peak_prom" => NaN
    )
    spec = Dict{String, Any}[]
    if spectra
        for (name, x) in (("t1", N), ("phi", Φ))
            P = FOAM_AN.power_spectrum(x; dt = 1 / τ)                  # f in cycles per paper MCS
            name == "t1" && ((pk = foam_peak(P.f, P.S)); run["peak_f"] = pk.f; run["peak_prom"] = pk.prom)
            fb, Sb = foam_bin(P.f, P.S)
            append!(spec, [Dict{String, Any}("series" => name, "f" => fb[i], "S" => Sb[i]) for i in eachindex(fb)])
        end
    end
    return run, W, spec
end
# ---------------------------------------------------------------------------------------------
# Record schema, reader, writer
# ---------------------------------------------------------------------------------------------
const SCHEMA = Dict(
    "foams" => [
        "foam" => String, "k" => Int, "seed" => Int, "try" => Int, "ly" => Int, "target" => Float64,
        "mu2n" => Float64, "mu2a" => Float64, "nbub" => Int, "hex" => Float64, "area_frac" => Float64, "stop" => Int,
        "ok" => Bool, "ubar" => Float64,
    ],
    "loops" => [
        "set" => String, "J" => Float64, "r" => Float64, "gp" => Float64, "gamma0" => Float64, "T" => Float64,
        "k" => Int, "seed" => Int, "t1_cycles" => Vector{Float64}, "phi_bins" => Vector{Float64},
        "phi_noise" => Float64, "phi_mean" => Float64,
    ],
    "steady" => [
        "set" => String, "foam" => String, "k" => Int, "seed" => Int, "gamma0" => Float64,
        "t1_50" => Vector{Float64}, "phi_50" => Vector{Float64}, "hex_pairs" => Int, "hex_total" => Int,
        "t_first" => Int, "changed_max" => Float64,
    ],
    "bulk" => [
        "set" => String, "foam" => String, "beta" => Float64, "beta_model" => Float64, "k" => Int,
        "seed" => Int, "mcs" => Int, "nbub" => Int, "mu2n0" => Float64, "t1_total" => Float64, "t_first" => Int,
        "peak_f" => Float64, "peak_prom" => Float64,
    ],
    "windows" => [
        "set" => String, "foam" => String, "beta" => Float64, "k" => Int, "w" => Int, "t1" => Float64,
        "phi" => Float64, "mu2n" => Float64, "nonhex_mid" => Int, "nonhex_away" => Int, "changed_frac" => Float64,
        "area_frac" => Float64,
    ],
    "spectra" => ["foam" => String, "beta" => Float64, "k" => Int, "series" => String, "f" => Float64, "S" => Float64],
    "calibration" => ["kappa" => Float64, "r_star" => Float64, "tau" => Float64]
)
fmt(x::AbstractVector) = join(map(fmt, x), ',')
fmt(x::AbstractFloat) = isnan(x) ? "NaN" : string(Float64(x))
fmt(x) = string(x)
foam_parse(::Type{String}, s) = String(s)
foam_parse(::Type{Bool}, s) = parse(Bool, s)
foam_parse(::Type{T}, s) where {T <: Real} = parse(T, s)
foam_parse(::Type{Vector{Float64}}, s) = isempty(s) ? Float64[] : parse.(Float64, split(s, ','))
function foam_write(dir, R)
    mkpath(dir)
    for (name, cols) in SCHEMA
        open(joinpath(dir, "$name.tsv"), "w") do io
            println(io, join(first.(cols), '\t'))
            for r in R[name]
                println(io, join((fmt(r[c]) for c in first.(cols)), '\t'))
            end
        end
    end
    return
end
function foam_read(dir)
    R = Dict{String, Vector{Dict{String, Any}}}()
    for (name, cols) in SCHEMA
        l = split.(readlines(joinpath(dir, "$name.tsv")), '\t'; keepempty = true)
        @assert l[1] == first.(cols) "04 record: $name.tsv header $(l[1]) is not the schema's"
        R[name] = [Dict{String, Any}(c => foam_parse(T, v) for ((c, T), v) in zip(cols, r)) for r in l[2:end]]
    end
    return R
end
sel(tab; kw...) = filter(r -> all(r[string(k)] == v for (k, v) in kw), tab)
# ---------------------------------------------------------------------------------------------
# Verdicts from the tables (shared by the record tier and FULL)
# ---------------------------------------------------------------------------------------------
"""τ = 1/ū over ordered foams 1:5 (the foams the shear runs start from)."""
foam_tau(R) = 1 / mean(r["ubar"] for r in R["foams"] if r["foam"] == "ordered" && r["k"] <= REPS)
"""κ and r* from the calibration stage (J = 3, model r grid)."""
function foam_kappa(R)
    lp = sel(R["loops"]; set = "cal", J = 3.0)
    rs = sort(unique(r["r"] for r in lp))
    m = [median(mean(x["t1_cycles"]) for x in lp if x["r"] == r) for r in rs]
    rstar = foam_crossing(rs, m, 0.5)
    return rstar === nothing ? (kappa = NaN, r_star = NaN) : (kappa = 3rstar / 5.8, r_star = rstar)
end
t1c(rows) = median(mean(r["t1_cycles"]) for r in rows)
curve(rows) = mean(r["phi_bins"] for r in rows)
foam_height(rows) = (c = curve(rows); maximum(c) - minimum(c))
foam_in(x, lo, hi) = lo <= x <= hi
med(x) = isempty(x) ? NaN : median(x)
function ens_spec(R, foam, β, series)
    rows = sel(R["spectra"]; foam, beta = β, series)
    fs = sort(unique(r["f"] for r in rows))
    return (fs, [mean(r["S"] for r in rows if r["f"] == f) for f in fs])
end
"""V7 (i) / V8: the mid share of non-hexagonal interior bubble-frames after t_first, pooled."""
function mid_share(R, foam, β)
    m = a = 0
    for b in sel(R["bulk"]; set = "spec", foam, beta = β)
        b["t_first"] >= 0 || continue
        for w in sel(R["windows"]; set = "spec", foam, beta = β, k = b["k"])
            100w["w"] > b["t_first"] || continue
            m += w["nonhex_mid"]
            a += w["nonhex_away"]
        end
    end
    return m + a == 0 ? NaN : m / (m + a)
end
wseries(R, set, foam, β, k, col) = [w[col] for w in sort(sel(R["windows"]; set, foam, beta = β, k); by = w -> w["w"])]
function foam_verdicts(R)
    V = NamedTuple[]
    add!(id, kind, value, band, ok) = push!(V, (; id, kind, value, band, ok = ok === true))
    κ = foam_kappa(R)
    add!("kappa", :info, κ.kappa, "γ_model / γ_paper", true)
    add!("r_star", :info, κ.r_star, "J = 3 first-T1 r (model)", true)
    add!("tau", :info, foam_tau(R), "our MCS per paper MCS (1/ū)", true)
    # V1, V1b, V19 (relaxed), PREP
    ord = sel(R["foams"]; foam = "ordered")
    add!("V1", :row, minimum(r["hex"] for r in ord), "≥ 0.95 every foam", length(ord) == 10 && all(r -> r["hex"] >= 0.95, ord))
    add!("V1b", :row, extrema(r["mu2n"] for r in ord), "[0.3, 0.6] every foam", all(r -> foam_in(r["mu2n"], 0.3, 0.6), ord))
    add!("V19a", :row, maximum(r["area_frac"] for r in ord), "< 5e-3", all(r -> r["area_frac"] < 5.0e-3, ord))
    dis = filter(r -> r["foam"] != "ordered", R["foams"])
    add!("PREP", :row, count(r -> r["ok"], dis), "all $(length(dis)) accepted", length(dis) == 30 && all(r -> r["ok"], dis))
    μa(f) = mean(r["mu2a"] for r in sel(R["foams"]; foam = f))
    add!(
        "PREPa", :row, (μa("d165") + μa("d172"), μa("d095") + μa("d107")) ./ 2, "high > low",
        μa("d165") + μa("d172") > μa("d095") + μa("d107")
    )
    d081 = sel(R["foams"]; foam = "d081")
    add!("C-V1", :control, maximum(r["hex"] for r in d081), "< 0.95 (d081)", all(r -> r["hex"] < 0.95, d081))
    # V3, V4, V6
    v3(gp) = sel(R["loops"]; set = "v3", gp)
    add!(
        "V3a", :row, (foam_height(v3(1.0)), t1c(v3(1.0))), "height < 0.002, T1 < 0.5",
        foam_height(v3(1.0)) < 0.002 && t1c(v3(1.0)) < 0.5
    )
    add!(
        "V3b", :row, (foam_height(v3(3.5)), t1c(v3(3.5))), "height ∈ [0.01, 0.03], T1 < 0.5",
        foam_in(foam_height(v3(3.5)), 0.01, 0.03) && t1c(v3(3.5)) < 0.5
    )
    c7 = curve(v3(7.0))
    sx = abs(bincentre_strain(argmax(c7)))
    add!("V3c", :row, (t1c(v3(7.0)), sx), "T1 ≥ 0.5, |strain| at max > 0.8γ0", t1c(v3(7.0)) >= 0.5 && sx > 0.8)
    add!("V3t", :info, 5.8, "transition = calibration (κ)", true)
    m4 = Dict(J => t1c(J == 3.0 ? v3(7.0) : sel(R["loops"]; set = "v4", J)) for J in (1.0, 3.0, 5.0, 10.0))
    add!(
        "V4", :row, m4, "J10, J5 < 0.5; J3 ∈ [0.5, 2.5); J1 ≥ 1.5; non-increasing",
        m4[10.0] < 0.5 && m4[5.0] < 0.5 && 0.5 <= m4[3.0] < 2.5 && m4[1.0] >= 1.5 && m4[1.0] >= m4[3.0] >= m4[5.0] >= m4[10.0]
    )
    v6 = [sel(R["loops"]; set = "v6", T) for T in V6_T]
    mφ = [median(r["phi_mean"] for r in rows) for rows in v6]
    hn = [foam_height(rows) / mean(r["phi_noise"] for r in rows) for rows in v6]
    add!("V6a", :row, mφ, "strictly increasing in T", issorted(mφ) && allunique(mφ))
    add!("V6b", :row, (hn[1], hn[4]), "height/noise > 3 at T = 0, < 1 at T = 15", hn[1] > 3 && hn[4] < 1)
    add!("V6c", :info, ols([0.0, 5, 10, 15], mφ).s, "≈ 0.014 ± 50 %", true)
    # V5
    bnd = Dict{Tuple{Symbol, Float64}, Any}()
    for J in SCAN_J
        lp = sel(R["loops"]; set = "scan", J)
        rs = sort(unique(r["r"] for r in lp))
        h = [foam_height(filter(x -> x["r"] == r, lp)) for r in rs]
        t = [t1c(filter(x -> x["r"] == r, lp)) for r in rs]
        bnd[(:e, J)] = foam_crossing(rs, h, 0.002)
        bnd[(:b1, J)] = foam_crossing(rs, t, 0.5)
        bnd[(:b2, J)] = foam_crossing(rs, t, 1.5)
        bnd[(:b3, J)] = foam_crossing(rs, t, 2.5)
    end
    for (b, id, lo, hi) in ((:e, "V5a", 0.7, 1.4), (:b1, "V5b", 1.4, 2.5))
        rb = [bnd[(b, J)] for J in SCAN_J]
        if any(isnothing, rb) || isnan(κ.kappa)
            add!(id, :row, rb, "s ∈ [$lo, $hi], |a| ≤ 1.6", false)
        else
            fit = ols(SCAN_J, SCAN_J .* rb)                # paper γ0 = J·r_b (r in paper units)
            add!(id, :row, (fit.s, fit.a), "s ∈ [$lo, $hi], |a| ≤ 1.6", foam_in(fit.s, lo, hi) && abs(fit.a) <= 1.6)
        end
    end
    ordok = all(SCAN_J) do J
        e, b1, b2, b3 = (bnd[(b, J)] for b in (:e, :b1, :b2, :b3))
        (e !== nothing && b1 !== nothing && e < b1) && (b2 === nothing || b1 <= b2) && (b3 === nothing || (b2 !== nothing && b2 <= b3))
    end
    add!("V5c", :row, Dict(string(k) => v for (k, v) in bnd), "r_e < r_1 ≤ r_2 ≤ r_3", ordok)
    # V2, V9, V20 inputs
    v2 = sel(R["steady"]; set = "v2")
    add!(
        "V2i", :row, sum(r["hex_pairs"] for r in v2) / sum(r["hex_total"] for r in v2), "> 0.95",
        sum(r["hex_pairs"] for r in v2) / sum(r["hex_total"] for r in v2) > 0.95
    )
    v2ii = map(v2) do r
        p, _ = zigzag(r["phi_50"], 0.002)
        d = drops(r["phi_50"], 0.002)
        sp = diff(p)
        length(d) >= 3 && foam_in(median(d), 0.005, 0.02) && length(sp) >= 2 && std(sp) / mean(sp) <= 0.3
    end
    add!("V2ii", :row, count(v2ii), "≥ 4/5 replicates", count(v2ii) >= 4)
    v2iii = [(b = foam_bursts(r["t1_50"]); b.bursts >= 3 && b.quiet >= 0.3) for r in v2]
    add!("V2iii", :row, count(v2iii), "≥ 4/5 replicates", count(v2iii) >= 4)
    early(set) = count(r -> 0 <= r["t_first"] < 100, sel(R["steady"]; set))
    add!("V9", :row, early("v9"), "t_first < 100 in ≥ 4/5", early("v9") >= 4)
    add!("C-V9", :control, early("v9c"), "ordered: t_first < 100 in ≤ 1/5", early("v9c") <= 1)
    # V7, V8, V17, V19b, V20
    dropb = median(med(drops(wseries(R, "spec", "ordered", 0.01, k, "phi"), 0.001)) for k in 1:REPS)
    drops2 = median(med(drops(r["phi_50"][2:2:end], 0.001)) for r in v2)
    l01, l05 = mid_share(R, "ordered", 0.01), mid_share(R, "ordered", 0.05)
    add!("V7i", :row, l01, "≥ 0.9", l01 >= 0.9)
    add!("V7ii", :row, dropb / drops2, "≤ 0.6", dropb / drops2 <= 0.6)
    pk = sel(R["bulk"]; set = "spec", foam = "ordered", beta = 0.01)
    npk = count(r -> 5.0e-4 < r["peak_f"] < 1.5e-3 && r["peak_prom"] >= 3, pk)
    add!("V7iii", :row, [r["peak_f"] for r in pk], "f* ∈ (5e-4, 1.5e-3), prominence ≥ 3 in ≥ 4/5", npk >= 4)
    add!("V8", :row, l05, "< 0.5", l05 < 0.5)
    add!("V20", :row, dropb / drops2, "∈ [0.2, 0.6]", foam_in(dropb / drops2, 0.2, 0.6))
    af = mean(w["area_frac"] for w in sel(R["windows"]; set = "spec", foam = "ordered", beta = 0.01))
    add!("V19b", :row, af, "< 5e-3", af < 5.0e-3)
    exc = tot = 0
    for k in 1:REPS
        μ = wseries(R, "spec", "ordered", 0.01, k, "mu2n")
        φ = wseries(R, "spec", "ordered", 0.01, k, "phi")
        p, t = zigzag(φ, 0.001)
        falls = [p[i]:t[i] for i in eachindex(p)]
        b = median(μ)
        i = 1
        while i <= length(μ)
            if μ[i] > b + 0.01
                j = i
                while j + 1 <= length(μ) && μ[j + 1] > b + 0.01
                    j += 1
                end
                tot += 1
                exc += any(r -> !isempty(intersect(i:j, r)), falls)
                i = j + 1
            else
                i += 1
            end
        end
    end
    add!("V17", :row, (exc, tot), "≥ 80 % of ≥ 3 excursions", tot >= 3 && exc / tot >= 0.8)
    # spectra: V10–V13
    α(foam, β, s; lo = 1.0e-4, hi = 1.0e-2) = (S = ens_spec(R, foam, β, s); alpha(S[1], S[2], lo, hi))
    wα(foam, β, s, lo, hi) = (S = ens_spec(R, foam, β, s); window_alpha(S[1], S[2], lo, hi))
    a05, a02 = α("ordered", 0.05, "t1"), α("ordered", 0.02, "t1")
    add!("V10a", :row, a05, "∈ [0.7, 1.3]", foam_in(a05, 0.7, 1.3))
    add!("V10b", :row, a02, "|α| < 0.3", abs(a02) < 0.3)
    a81 = [α("d081", β, "t1") for β in BETAS]
    ρ = any(isnan, a81) ? NaN : spearman(BETAS, a81)
    add!("V11a", :row, ρ, "Spearman ≥ 0.8", ρ >= 0.8)
    add!("V11b", :row, a81[end], "∈ [0.7, 1.2]", foam_in(a81[end], 0.7, 1.2))
    add!("V11c", :row, a81[1], "< 0.4", a81[1] < 0.4)
    w12 = [wα("d165", β, "t1", 1.0e-4, 1.0e-2) for β in (0.001, 0.01, 0.05)]
    add!("V12", :row, w12, "every window α ≤ 0.5", all(<=(0.5), w12))
    c12 = wα("ordered", 0.05, "t1", 1.0e-4, 1.0e-2)
    add!("C-V12", :control, c12, "ordered β = 0.05: > 0.5", c12 > 0.5)
    φok = [
        (foam, β) => (α(foam, β, "phi"), wα(foam, β, "phi", 1.0e-5, 0.05)) for foam in ("ordered", "d081", "d165")
            for β in BETAS
    ]
    add!(
        "V13a", :row, Dict(φok), "α_φ ∈ [0.5, 1.2], every window < 1.5",
        all(((_, (a, w)),) -> foam_in(a, 0.5, 1.2) && w < 1.5, φok)
    )
    h1, h2 = α("d165", 0.005, "phi"; hi = 1.0e-3), α("d165", 0.005, "phi"; lo = 1.0e-3)
    add!("V13b", :row, (h1, h2), "both ∈ [0.5, 1.2]", foam_in(h1, 0.5, 1.2) && foam_in(h2, 0.5, 1.2))
    # V14
    function nbar(foam, β)
        return mean(
                FOAM_AN.mean_t1([r["t1_total"]], r["nbub"], β * r["mcs"])
                    for r in sel(R["bulk"]; set = "v14", foam, beta = β)
            )
    end
    N14 = Dict((f, β) => nbar(f, β) for f in ("d165", "d172", "d107", "d095") for β in BETAS14)
    r1 = [N14[(f, 1.0e-4)] / N14[(f, 1.0e-3)] for f in ("d165", "d172", "d107", "d095")]
    r2 = [N14[(f, 1.0e-3)] / N14[(f, 5.0e-2)] for f in ("d165", "d172", "d107", "d095")]
    sep = [(N14[("d165", β)] + N14[("d172", β)]) / (N14[("d107", β)] + N14[("d095", β)]) for β in (5.0e-3, 1.0e-2, 5.0e-2)]
    add!("V14a", :row, r1, "∈ [4, 25] each foam", all(x -> foam_in(x, 4, 25), r1))
    add!("V14b", :row, r2, "≥ 10 each foam (finite)", all(x -> isfinite(x) && x >= 10, r2))
    add!("V14c", :row, sep, "≥ 5 at β ≥ 5e-3 (finite)", all(x -> isfinite(x) && x >= 5, sep))
    # V15
    function εy(foam, β)
        rs = sel(R["bulk"]; set = "spec", foam, beta = β)
        return median(r["t_first"] < 0 ? Inf : β * r["t_first"] for r in rs)
    end
    eo = [εy("ordered", β) for β in BETAS]
    plateau = median(eo[1:3])
    add!(
        "V15a", :row, (maximum(eo[1:3]) - minimum(eo[1:3])) / mean(eo[1:3]), "≤ 0.10",
        (maximum(eo[1:3]) - minimum(eo[1:3])) / mean(eo[1:3]) <= 0.1
    )
    add!("V15b", :row, eo[5] / eo[3], "∈ [0.25, 0.6]", foam_in(eo[5] / eo[3], 0.25, 0.6))
    allo = sel(R["bulk"]; set = "spec", foam = "ordered")
    add!(
        "V15c", :row, minimum(r["t_first"] for r in allo), "every ordered run yields, t_first ≥ 100",
        all(r -> r["t_first"] >= 100, allo)
    )
    ed = [εy(f, β) for f in ("d081", "d165") for β in (0.01, 0.02, 0.05)]
    add!("V15d", :row, ed ./ plateau, "≤ 0.045 (all yield)", isfinite(plateau) && all(x -> isfinite(x) && x <= 0.045 * plateau, ed))
    add!("V15e", :info, C_YIELD .* eo, "ε_y with c = 0.023 (paper 1.13, 1.10, 1.11, 0.80, 0.43)", true)
    # V16
    function rise(set, foam, β)
        return map(sel(R["bulk"]; set, foam, beta = β)) do r
                ws = filter(w -> 2000 <= 100w["w"] <= 10_000, sel(R["windows"]; set, foam, beta = β, k = r["k"]))
                mean(w["mu2n"] for w in ws) - r["mu2n0"]
            end
    end
    v16 = Dict(f => rise("v16", f, 0.01) for f in ("d081", "d165", "d172", "d202"))
    add!("V16", :row, v16, "rise ≥ 0.1 in ≥ 4/5, each foam", all(x -> count(>=(0.1), x) >= 4, values(v16)))
    c16 = rise("v16c", "d165", 0.0)
    add!("C-V16", :control, c16, "β = 0: rise < 0.1 in ≥ 4/5", count(<(0.1), c16) >= 4)
    # V18
    m18 = max(maximum(w["changed_frac"] for w in R["windows"]), maximum(r["changed_max"] for r in R["steady"]))
    add!("V18", :row, m18, "< 0.5", m18 < 0.5)
    return V
end
# ---------------------------------------------------------------------------------------------
# always: the rules on synthetic series and hand-built states
# ---------------------------------------------------------------------------------------------
"""Brute-force φ: unordered NeighborOrder(4) pairs, periodic x, closed y (no production code)."""
function phi_oracle(σ)
    X, Y = size(σ)
    offs = [(a, b) for a in -2:2 for b in -2:2 if 0 < a^2 + b^2 <= 5 && (a > 0 || (a == 0 && b > 0))]
    φ = 0
    for x in 1:X, y in 1:Y, (a, b) in offs
        q = y + b
        1 <= q <= Y || continue
        φ += σ[x, y] != σ[mod1(x + a, X), q]
    end
    return φ
end
"""Brute-force n: distinct other ids among VonNeumann(1) neighbours, periodic x, closed y."""
function sides_oracle(σ, n)
    X, Y = size(σ)
    S = [Set{Int}() for _ in 1:n]
    for x in 1:X, y in 1:Y, (a, b) in ((1, 0), (-1, 0), (0, 1), (0, -1))
        q = y + b
        1 <= q <= Y || continue
        c, d = σ[x, y], σ[mod1(x + a, X), q]
        c != d && push!(S[c], d)
    end
    return length.(S)
end
# ---------------------------------------------------------------------------------------------
# SMOKE: the no-shear rows at full size (binding once the foam analysis lands)
# ---------------------------------------------------------------------------------------------
const FOAM_SMOKE = Dict{Symbol, Any}()
# the two ordered smoke foams, built once per process: the ordered-foam item checks them, and
# the shear item starts from the first
function smoke_ordered_foams()
    return get!(FOAM_SMOKE, :ordered) do
            foam_template(false, FOAM_L)
            [make_foam(:ordered, k; seedf = _ -> smoke_seed(k)) for k in 1:2]
        end
end
# ---------------------------------------------------------------------------------------------
# SMOKE: shear (κ-free checks)
# ---------------------------------------------------------------------------------------------
"""Per-bubble circular centroid x (sites) of ids 1:n."""
function foam_cx(σ, n)
    X = size(σ, 1)
    s, c = zeros(n), zeros(n)
    for I in CartesianIndices(σ)
        b = σ[I]
        s[b] += sinpi(2I[1] / X)
        c[b] += cospi(2I[1] / X)
    end
    return [atan(s[b], c[b]) * X / 2π for b in 1:n]
end
"""Mean x drift (sites; minimum-image increments of circular centroids every 10 MCS) of the
top (start centroid y ≥ 192) and bottom (≤ 64) bubbles over `mcs` MCS of bulk shear at
model β; the T1 events; the final area fraction."""
function foam_drift(st, βm, mcs, seed)
    n = length(st.A)
    X = size(st.ownership, 1)
    lat = foam_lat(size(st.ownership))
    integ = init(foam_problem(st, mcs; shear = true, β = βm, bulk = true, seed), ALG)
    cy = foam_cells(st.ownership, n).cy
    x0 = foam_cx(st.ownership, n)
    d = zeros(n)
    g = FOAM_AN.cell_graph(st.ownership, lat)
    t1 = 0.0
    for m in 1:mcs
        step!(integ)
        g2 = FOAM_AN.cell_graph(current_state(integ).ownership, lat)
        t1 += FOAM_AN.t1_events(g, g2; unit = :t1)
        g = g2
        if m % 10 == 0
            x1 = foam_cx(current_state(integ).ownership, n)
            d .+= mod.(x1 .- x0 .+ X / 2, X) .- X / 2
            x0 = x1
        end
    end
    return (;
        top = mean(d[cy .>= 192]), bottom = mean(d[cy .<= 64]), t1,
        area = foam_area_frac(current_state(integ).ownership, foam_vol(current_state(integ), n), st.A),
    )
end
# ---------------------------------------------------------------------------------------------
# FULL record (D-146): recompute every row from the committed record
# ---------------------------------------------------------------------------------------------
function check(V, devs; broken_ok)
    for v in V
        if v.kind === :info
            @info "04 info $(v.id)" v.value v.band
        elseif v.kind === :control
            @test v.ok                                                         # controls must behave as pre-registered
        elseif v.ok
            @test v.ok
        elseif broken_ok && any(d -> d["id"] == v.id, devs)
            @test_broken v.ok                                                  # a D-154 deviation
        else
            @error "04 row failed" v.id v.value v.band
            @test v.ok
        end
    end
    return @test count(v -> v.kind === :row, V) == 42 && count(v -> v.kind === :control, V) == 4
end
# ---------------------------------------------------------------------------------------------
# FULL: rerun everything (offline on the PC; D-146, D-157)
# ---------------------------------------------------------------------------------------------
function tmap(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads :dynamic for i in eachindex(xs)
        out[i] = f(xs[i])
    end
    return out
end
function foam_full()
    R = Dict{String, Vector{Dict{String, Any}}}(k => Dict{String, Any}[] for k in keys(SCHEMA))
    for L in (FOAM_L, L_LOW), s in (false, true)
        foam_template(s, L)
    end
    function tag!(d; kw...)
        for (k, v) in kw
                d[string(k)] = v
            end
        return d
    end
    # foams, then τ (A-5)
    jobs = [[(:ordered, k) for k in 1:10]; [(f, k) for f in keys(FOAMS) if f !== :ordered for k in 1:REPS]]
    res = tmap(((f, k),) -> (f, k, make_foam(f, k)), jobs)
    F = Dict((f, k) => st for (f, k, (st, _)) in res)
    append!(R["foams"], [row for (_, _, (_, row)) in res])
    τ = foam_tau(R)
    # κ stage (J = 3, model r grid), then κ
    cj = [(i, r, k) for (i, r) in enumerate(CAL_R) for k in 1:REPS]
    append!(
        R["loops"], tmap(cj) do (i, r, k)
            tag!(
                foam_loop(F[(:ordered, k)], 3.0, 3.0 * r, FOAM_T0, run_seed(BLOCK.cal, i, k), τ);
                set = "cal", r, gp = NaN, k
            )
        end
    )
    κ = foam_kappa(R)
    push!(R["calibration"], Dict{String, Any}("kappa" => κ.kappa, "r_star" => κ.r_star, "tau" => τ))
    isnan(κ.kappa) && error("04 FULL: no first-T1 crossing at J = 3 on the calibration grid; κ cannot be calibrated")
    # V5 scan (paper r grid), V3, V4, V6: every γ0 = κ × paper γ0
    lj = [
        [("scan", J, J * r, FOAM_T0, 100j + i) for (j, J) in enumerate(SCAN_J) for (i, r) in enumerate(SCAN_R)];
        [("v3", 3.0, gp, FOAM_T0, i) for (i, gp) in enumerate((1.0, 3.5, 7.0))];
        [("v4", J, 7.0, FOAM_T0, i) for (i, J) in enumerate((1.0, 5.0, 10.0))];
        [("v6", 3.0, 4.0, T, i) for (i, T) in enumerate(V6_T)]
    ]
    lj = [(j..., k) for j in lj for k in 1:REPS]
    append!(
        R["loops"], tmap(lj) do (set, J, gp, T, i, k)
            tag!(
                foam_loop(F[(:ordered, k)], J, κ.kappa * gp, T, run_seed(getfield(BLOCK, Symbol(set)), i, k), τ);
                set, r = gp / J, gp, k
            )
        end
    )
    # V2, V9 (steady boundary, paper γ0 = 7)
    sj = [[("v2", :ordered, TV2)]; [("v9", :d165, TV9)]; [("v9c", :ordered, TV9)]]
    sj = [(j..., k) for j in sj for k in 1:REPS]
    append!(
        R["steady"], tmap(sj) do (set, f, T, k)
            tag!(
                foam_steady(F[(f, k)], κ.kappa * 7.0, T, run_seed(getfield(BLOCK, Symbol(set)), 0, k), τ);
                set, foam = string(f), k
            )
        end
    )
    # bulk: spectral set, V14, V16 (+ control)
    bj = [
        [("spec", f, β, TSPEC) for f in (:ordered, :d081, :d165) for β in BETAS];
        [("v14", f, β, T14) for f in (:d165, :d172, :d107, :d095) for β in BETAS14];
        [("v16", f, 0.01, T16) for f in (:d081, :d165, :d172, :d202)]; [("v16c", :d165, 0.0, T16)]
    ]
    bj = [(j..., i, k) for (i, j) in enumerate(bj) for k in 1:REPS]
    out = tmap(bj) do (set, f, β, T, i, k)
        run, W, S = foam_bulk(
            F[(f, k)], β, κ.kappa, T, run_seed(getfield(BLOCK, Symbol(set)), i, k), τ;
            spectra = set == "spec"
        )
        (
            tag!(run; set, foam = string(f), k), [tag!(w; set, foam = string(f), beta = β, k) for w in W],
            [tag!(s; foam = string(f), beta = β, k) for s in S],
        )
    end
    for (run, W, S) in out
        push!(R["bulk"], run)
        run["set"] == "v14" || append!(R["windows"], W)
        append!(R["spectra"], S)
    end
    return R
end
