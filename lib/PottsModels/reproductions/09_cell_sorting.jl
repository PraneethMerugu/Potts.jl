# # Reproducing Graner & Glazier (1992): cell sorting by differential adhesion
#
# !!! note "Draft prose"
#     (prose: draft) The text on this page is a placeholder written with the code; a
#     separate pass will revise it. Every number about our runs is computed on this page
#     when the docs are built. Values quoted from the papers carry a citation.
#
# !!! warning "Reduced run"
#     The docs build runs a reduced ensemble (`POTTS_FULL_REPRODUCTION` unset), so the
#     tables below are a smoke check, not validation. The full run
#     (`POTTS_FULL_REPRODUCTION=true`) raises the replicate count and the run length, and
#     replaces the small aggregate of `graner_glazier_state` with a paper-size one of 1000
#     cells (`graner_glazier_aggregate`), so the differences that come from aggregate size
#     (deviations table) can be tested there. The committed full-run outputs
#     (`lib/PottsModels/reproductions/data/09/`) are **pending**: no full run has been made
#     yet.
#
# ## 1. Paper and sources
#
# - F. Graner, J.A. Glazier, "Simulation of Biological Cell Sorting Using a Two-Dimensional
#   Extended Potts Model", *Phys. Rev. Lett.* **69**, 2013 (1992).
#   doi:[10.1103/PhysRevLett.69.2013](https://doi.org/10.1103/PhysRevLett.69.2013).
#   PDF: `docs/references/09a_GranerGlazier1992_PRL_cell-sorting.pdf` (version of record,
#   OCR text layer; equations read from the page images).
# - J.A. Glazier, F. Graner, "Simulation of the differential adhesion driven rearrangement
#   of biological cells", *Phys. Rev. E* **47**, 2128 (1993).
#   doi:[10.1103/PhysRevE.47.2128](https://doi.org/10.1103/PhysRevE.47.2128).
#   PDF: `docs/references/09c_GranerGlazier1993_PRE_differential-adhesion-rearrangement.pdf`
#   (version of record). It gives the initial-condition recipe (§II D3), the measurement
#   protocol (§II D1) and the full sorting run (§III B, Fig. 13).
# - Erratum status: the spec records no erratum for either paper. We have not checked the
#   APS erratum listings.
# - Released code: none.
# - Spec: `docs/design/research/model-specs/09_cell_sorting.md` (§2.1, §3.1, §8.4, §8.5).
#   The Osborne et al. (2017) Potts benchmark in the same spec is a separate model and is
#   not reproduced here.
# - Reproducibility grade: **B**. Energies, λ, T, the time unit and the initial-state
#   recipe are stated. Lattice size, boundary conditions and the type fraction are not
#   (spec §8.4).
#
# The papers show that differential adhesion alone sorts a random mixture of two cell
# types. With the sorting hierarchy of PRL Eq. (3), heterotypic boundary shrinks roughly
# logarithmically in time, and the light cells end up enveloping the dark ones. This page
# reproduces that time course (PRL Fig. 2; PRE Fig. 13), the engulfment end state, and two
# contrasting runs: partial sorting (PRE §III E) and symmetric contacts (no sorting).

using Potts, PottsModels
using MakiePotts, CairoMakie
using Statistics: mean, std, var, cov, cor
using Markdown
CairoMakie.activate!(type = "png")

const FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true"

# ## 2. The model, term by term
#
# PRL Eq. (2), p.2014 (also PRE Eq. (2), p.2129):
#
# ```math
# H = \sum_{\langle i, j\rangle} J(\tau(\sigma_i), \tau(\sigma_j))\,(1 - \delta_{\sigma_i\sigma_j})
#   + \lambda \sum_\sigma (a_\sigma - A_{\tau(\sigma)})^2\,\theta(A_{\tau(\sigma)})
# ```
#
# | Paper | `GranerGlazier` statement |
# |---|---|
# | contact term over the next-nearest-neighbour (8) set (PRL p.2014; PRE p.2129) | `contacts => J[kind, kind′]` on `Lattice(...; neighborhood = Moore(1))` |
# | area term, medium exempt through ``\theta(A_M < 0)`` (PRE p.2130) | `cells(dark, light) => λ * (volume - V₀)^2` |
# | copy from "one of the eight neighboring sites" (PRE p.2130) | `@relations proposal = Moore(1)` |
# | Metropolis at temperature T, Eq. (3) (PRE p.2130) | `@sweep Metropolis(; temperature = T)` |
#
# The published constructor carries all of it:

σ0, k0 = FULL ? graner_glazier_aggregate(1000; seed = 1) : graner_glazier_state()
gg = GranerGlazier(; name = :gg, lattice = size(σ0))
prob0 = PottsProblem(gg, [ownership => σ0, kind => k0], (0, 1); seed = 1)
J = getp(prob0, :J)(prob0)
par(name) = getp(prob0, name)(prob0)
ncells, ndark, nlight = length(k0), count(==(1), k0), count(==(2), k0)
Markdown.parse("""
| Symbol | Value | Units | Meaning | Source | Status |
|---|---|---|---|---|---|
| J(d,d) | $(J[2, 2]) | energy | dark–dark contact | PRL p.2015 | stated |
| J(d,l) | $(J[2, 3]) | energy | dark–light contact | PRL p.2015 | stated |
| J(l,l) | $(J[3, 3]) | energy | light–light contact | PRL p.2015 | stated |
| J(d,M) = J(l,M) | $(J[1, 2]) | energy | cell–medium contact | PRL p.2015 | stated |
| λ | $(par(:λ)) | energy / site² | area-constraint strength | PRL p.2014 | stated |
| A(d) = A(l) | $(par(:V₀)) | sites | target area | PRL p.2015; PRE p.2130, p.2151 | stated (PRE) |
| T | $(par(:T)) | energy (k = 1) | temperature | PRL p.2014 | stated |
| lattice | $(join(size(σ0), " × ")), periodic | sites | domain | — | our choice (unstated) |
| cells | $ncells ($ndark dark, $nlight light) | — | initial aggregate | PRE §II D3 recipe | derived |
""")

# **Units.** Lengths are lattice sites. One of our MCS is N copy attempts, N the number
# of lattice sites (medium included). The paper's MCS is 16N attempts (PRL p.2014), so
# one paper MCS is 16 of ours. All times on this page are paper MCS.

const PAPER_MCS = 16
nothing #hide

# ## 3. Deviations

Markdown.parse("""
| Item | Paper | Released code | Our default | Variant keyword | Reason |
|---|---|---|---|---|---|
| Time unit | 1 MCS = 16N attempts (PRL p.2014) | — | 1 MCS = N attempts | — | INTERNALS F8; times are converted, paper t = our $(PAPER_MCS)t |
| Aggregate size | ≈ 1000 cells (PRE p.2129) | — | $ncells cells on $(join(size(σ0), " × ")) | `graner_glazier_aggregate(n)`: one round aggregate of n cells (the full run uses n = 1000) | Cost. Boundary fractions scale with perimeter/area, and sorting levels off long before 10⁴ paper MCS (`GranerGlazier` docstring; `test/papers.jl`) |
| Log-law window | 5–4000 paper MCS (spec §8.5 V-PRE1) | — | also reported over 4–512 | — | The window of `test/papers.jl`, which ends before our small aggregate levels off. Extra row, not a replacement |
| Boundary conditions | unstated | — | periodic | `lattice` keyword | The aggregate stays clear of its image; unsuitable for dispersal runs (spec §8.6 D2) |
| Type fraction | unstated (spec §8.4) | — | $(FULL ? "equal numbers, randomly placed" : "probability ½ per cell") ($ndark dark / $nlight light) | — | $(FULL ? "Assumption; `graner_glazier_aggregate`, one draw per replicate" : "Assumption, recorded in `data/graner/provenance.toml`") |
| Initial state | square aggregate of staggered bricks relaxed 400 paper MCS (PRE §II D3) | — | $(FULL ? "a round aggregate of $ncells centroidal Voronoi cells, not Potts-relaxed (`graner_glazier_aggregate`)" : "the same recipe with $ncells cells") | — | $(FULL ? "Paper size. Areas are more spread than after a Potts relaxation (SD 7.6 against 1.6), but heterotypic fractions from either start agree within 0.005 at 1, 10 and 100 paper MCS (measured in the P6.1b2 review, 6 seeds)" : "D-049 F-2; `data/graner/generate.jl`") |
| T = 0 annealing | 2 paper MCS on a copy: "We anneal the displayed data only" (PRE p.2134) | — | on a copy, $(2PAPER_MCS) of our MCS, run's J | — | Matches the paper (spec §8.4 A-GG4, resolved) |
| Target area per kind | one value except the cavity run (PRE Fig. 28) | — | one `V₀` | — | Per-kind targets not expressible yet (spec §8.6 D14) |
| Boundary length | mismatched bonds on the 8-neighbour lattice, medium included (PRE p.2133) | — | the same, each bond once | — | Once/twice counting cancels in fractions (spec §8.6 D8) |
""")

# ## 4. Build and run
#
# One replicate to 10³ paper MCS, sequential CPU solver, timed after a warm-up solve. In
# the reduced build this is our small aggregate, not paper size.

alg = SequentialCPM(; proposal = Moore(1))
prob = remake(prob0; tspan = (0, PAPER_MCS * 1000))
solve(remake(prob; tspan = (0, PAPER_MCS)), alg)            # warm-up (compilation)
t_one = @elapsed solve(prob, alg)
Markdown.parse("One replicate ($ncells cells), 10³ paper MCS on the CPU, compiled: " *
               "**$(round(t_one; digits = 1)) s**.")

# A variant is ordinary model code, here a parameter `remake`. The partial-sorting regime
# of PRE §III E swaps J(d,l) and J(l,l) and lowers T:

prob_partial = remake(prob; p = [:J => [0 16 16; 16 2 14; 16 14 11], :T => 5.0])
nothing #hide

# ### Measurement (PRE §II D1)
#
# Fractional boundary length is the number of mismatched Moore bonds between two kinds,
# divided by all mismatched bonds (medium included). It is measured on a copy annealed for
# 2 paper MCS at T = 0 with the run's own contact energies. The definitions follow
# `lib/PottsModels/test/papers.jl`.
#
# planned: a `graner_glazier_observables(sol)` (feature G12, observables library) will
# replace these helpers.

function bond_counts(σ, k)
    n = Dict(:dd => 0, :ll => 0, :dl => 0, :dM => 0, :lM => 0)
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]
        b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        a == b && continue
        a == 0 && ((a, b) = (b, a))
        key = b == 0 ? (k[a] == 1 ? :dM : :lM) : k[a] == k[b] ? (k[a] == 1 ? :dd : :ll) : :dl
        n[key] += 1
    end
    return n
end

## anneal a copy at T = 0 with the energies of the run `run` (a PottsProblem)
function annealed(σ, k, run; seed = 1)
    q = PottsProblem(GranerGlazier(; name = :anneal, lattice = size(σ)),
        [ownership => copy(σ), kind => k, :J => getp(run, :J)(run), :λ => getp(run, :λ)(run),
            :V₀ => getp(run, :V₀)(run), :T => 0.0], (0, 2PAPER_MCS); seed)
    return ownership(solve(q, SequentialCPM(); saveat = 2PAPER_MCS).u[end])
end

function fractions(σ, k, run)
    n = bond_counts(annealed(σ, k, run), k)
    total = sum(values(n))
    return Dict(key => v / total for (key, v) in n)
end

function radius_ratio(σ, k)    # mean distance to the aggregate centroid, dark / light
    sites = findall(!=(0), σ)
    c = (mean(i[1] for i in sites), mean(i[2] for i in sites))
    r(kk) = mean(hypot(i[1] - c[1], i[2] - c[2]) for i in sites if k[σ[i]] == kk)
    return r(1) / r(2)
end

## engulfment as in `papers.jl`: dark–medium boundary below 0.003, dark cells nearer the centre
engulfed(σ, k, run) = fractions(σ, k, run)[:dM] < 0.003 && radius_ratio(σ, k) < 0.75
nothing #hide

# ## 5. Validation
#
# ### Ensemble

n = FULL ? 10 : 4
## FULL: replicate i starts from its own aggregate, `graner_glazier_aggregate(1000; seed = i)`,
## so the kind assignments are independent (spec §8.5); the reduced run shares the 64-cell state
starts = [FULL ? graner_glazier_aggregate(1000; seed = i) : (σ0, k0) for i in 1:n]
kinds_of(i) = starts[i][2]
from_start(q, ctx) = FULL ? remake(q; u0 = [ownership => starts[ctx.sim_id][1], kind => starts[ctx.sim_id][2]]) : q
ts = [1, 2, 3, 4, 5, 6, 8, 10, 13, 16, 20, 25, 32, 40, 50, 64, 80, 100, 128, 160, 200, 256, 320,
    400, 500, 640, 800, 1000, 1280, 1600, 2000]
FULL && append!(ts, [2560, 3200, 4000, 5000, 6400, 8000, 10_000, 12_800, 16_000, 20_000])
ens = solve(EnsembleProblem(remake(prob; tspan = (0, PAPER_MCS * last(ts))); prob_func = from_start), alg,
    EnsembleThreads();
    trajectories = n, saveat = PAPER_MCS .* ts)
keys5 = (:dl, :dd, :ll, :dM, :lM)
F = Dict(key => zeros(n, length(ts)) for key in keys5)
for (i, sol) in enumerate(ens.u), (j, t) in enumerate(ts)
    f = fractions(ownership(sol.u[findfirst(==(PAPER_MCS * t), sol.t)]), kinds_of(i), prob)
    for key in keys5
        F[key][i, j] = f[key]
    end
end
m(key) = vec(mean(F[key]; dims = 1))
s(key) = vec(std(F[key]; dims = 1))
fmt(x) = string(round(x; digits = 3))
shown = filter(t -> t in (1, 10, 100, 1000, 2000, 4000, 10_000, 20_000), ts)
Markdown.parse("""
n = $n replicates (`seed = 1`, replicas 1:$n), `SequentialCPM(; proposal = Moore(1))`, CPU,
$(Threads.nthreads()) thread(s). Fractions of all mismatched bonds, mean ± SD (selected
times; the plot shows all $(length(ts))):

| paper MCS | heterotypic | dark–dark | light–light | dark–medium | light–medium |
|---|---|---|---|---|---|
""" * join(["| $t | " * join(["$(fmt(m(key)[j])) ± $(fmt(s(key)[j]))" for key in keys5], " | ") * " |"
            for (j, t) in enumerate(ts) if t in shown], "\n"))

# Side by side with PRE Fig. 13(c): the markers are values read by eye from the figure
# (spec §8.5 V-PRE1; digitisation uncertainty ±0.02 above 0.1 and ±0.01 below, drawn as bars). No digitised data
# file exists yet (`reproductions/data/09/paper/` is pending).

paper_t = [1, 10, 100, 1000, 10_000]
paper = Dict(:dl => [0.43, 0.37, 0.25, 0.14, 0.05],        # PRE Fig. 13(c), read from plot
    :dd => [0.28, 0.32, 0.39, 0.44, 0.485], :ll => [0.23, 0.255, 0.31, 0.35, 0.40])
colors = Makie.wong_colors()
fig = Figure(size = (760, 420))
ax = Axis(fig[1, 1]; xscale = log10, xlabel = "time (paper MCS)", ylabel = "fraction of boundary")
for (c, key, label) in zip(1:5, keys5, ("heterotypic", "dark–dark", "light–light", "dark–medium", "light–medium"))
    band!(ax, ts, m(key) .- s(key), m(key) .+ s(key); color = (colors[c], 0.25))
    lines!(ax, ts, m(key); color = colors[c], label)
    if haskey(paper, key)
        errorbars!(ax, paper_t, paper[key], [v > 0.1 ? 0.02 : 0.01 for v in paper[key]]; color = colors[c])
        scatter!(ax, paper_t, paper[key]; color = colors[c], marker = :diamond, label = "$label, PRE Fig. 13(c)")
    end
end
Legend(fig[1, 2], ax; framevisible = false)
fig

# Snapshots of replicate 1 (dark kind blue, light kind green, medium black). PRL Fig. 1
# shows small same-type clusters after the first steps, merging clusters by 100 MCS,
# partial sorting with trapped light cells at 1000, and a single rounding dark cluster at
# 4000–10000 (spec §5.1 V-GG5).

snap = FULL ? [1, 100, 1000, 10_000] : [1, 100, 1000]
fig = Figure(size = (300 * length(snap), 320))
sol1 = ens.u[1]
for (c, t) in enumerate(snap)
    ax = Axis(fig[1, c]; title = "$t paper MCS", aspect = DataAspect())
    hidedecorations!(ax)
    pottsplot!(ax, renderframe(sol1; index = findfirst(==(PAPER_MCS * t), sol1.t)); boundaries = true)
end
fig

# ### Contrasting regimes and negative control
#
# Engulfment (default J) against partial sorting (PRE §III E: J(d,l) = 14, J(l,l) = 11,
# T = 5) and against symmetric contacts, where sorting has no driving force.

t_end = 1000
last_states(ens) = [ownership(sol.u[end]) for sol in ens.u]
sorted_states = [ownership(sol.u[findfirst(==(PAPER_MCS * t_end), sol.t)]) for sol in ens.u]
partial_states = last_states(solve(EnsembleProblem(prob_partial; prob_func = from_start), alg, EnsembleThreads(); trajectories = n,
    saveat = [PAPER_MCS * t_end]))
prob_sym = remake(prob; p = [:J => [0 16 16; 16 11 11; 16 11 11]])
sym_states = last_states(solve(EnsembleProblem(prob_sym; prob_func = from_start), alg, EnsembleThreads(); trajectories = n,
    saveat = [PAPER_MCS * t_end]))
regime(states, run) = (count(i -> engulfed(states[i], kinds_of(i), run), eachindex(states)),
    mean(i -> fractions(states[i], kinds_of(i), run)[:dM], eachindex(states)),
    mean(i -> fractions(states[i], kinds_of(i), run)[:dl], eachindex(states)))
rows = [("sorting (PRL defaults)", "engulfment", regime(sorted_states, prob)),
    ("partial sorting (PRE §III E)", "no monolayer", regime(partial_states, prob_partial)),
    ("symmetric contacts (control)", "no sorting", regime(sym_states, prob_sym))]
Markdown.parse("""
At $t_end paper MCS, n = $n each:

| Run | Paper outcome | engulfed (of $n) | dark–medium | heterotypic |
|---|---|---|---|---|
""" * join(["| $r | $o | $(e) | $(fmt(dm)) | $(fmt(h)) |" for (r, o, (e, dm, h)) in rows], "\n"))

# ### Pass/fail table
#
# The targets are copied from spec §8.5 (V-PRE1–V-PRE3 supersede V-GG1, V-GG3 and V-GG4
# of §5.1). V-GG6 has no PRE counterpart and stays. Every verdict in the Result column is
# taken at the paper's nominal times. The one extra row that is not in the spec is
# labelled as such. The pre-registration commit of this table is pending; it must precede
# the first full run.
#
# The last column is informational only. Spec §8.5 allows a ±2× time tolerance, but the
# premise behind it is under revision. Instead of widening each row, we look for one global
# time scale s ∈ [½, 2]. Every timed row is read at s × its nominal time, and we pick the s
# that makes the most timed rows pass.

pf(ok) = ok ? "PASS" : "FAIL"
## ensemble mean of `key` at paper time τ, linear in log t between saves; `nothing` outside the run
function at(key, τ)
    (τ < first(ts) || τ > last(ts)) && return nothing
    j = searchsortedlast(ts, τ)
    j == length(ts) && return m(key)[j]
    w = (log(τ) - log(ts[j])) / (log(ts[j + 1]) - log(ts[j]))
    return (1 - w) * m(key)[j] + w * m(key)[j + 1]
end
medium(t) = at(:dM, t) + at(:lM, t)                  # our medium share of all boundary
const PAPER_MEDIUM = 0.027 + 0.037                   # PRE Fig. 13(b) at t = 1 (spec §8.5 V-PRE3)
## caveat: this is the paper's t = 1 value, applied at all times; read off the figure; our own read-off uncertainty estimate is ≈ ±0.014
function logfit(lo, hi)
    js = findall(t -> lo <= t <= hi, ts)
    x = log10.(ts[js])
    y = m(:dl)[js]
    return cor(x, y)^2, cov(x, y) / var(x), ts[js[end]]
end
## first saved time at which curve `a` exceeds curve `b`; `nothing` if never
crossing(a, b) = (j = findfirst(j -> a[j] > b[j], eachindex(ts)); j === nothing ? nothing : ts[j])
show_t(t) = t === nothing ? "none by $(last(ts))" : t == first(ts) ? "≤ $t (already at the first save)" : "$t"

## a row: text columns, the nominal verdict, and `timed(s)` (nothing if the row has no time)
targets = []
addrow!(target, paper, ours, tol, result; timed = nothing, info = (;)) =
    push!(targets, (; target, paper, ours, tol, result, timed, info))

for (key, name) in ((:dl, "heterotypic"), (:dd, "dark–dark"), (:ll, "light–light")),
        (t, v) in zip(paper_t[2:end], paper[key][2:end])
    if t > last(ts)
        addrow!("V-PRE1 $name @ $t", "≈ $v (Fig. 13c)", "not run", "± 0.05", "pending full run")
        continue
    end
    ok(s) = (x = at(key, s * t); x !== nothing && abs(x - v) <= 0.05)
    addrow!("V-PRE1 $name @ $t", "≈ $v (Fig. 13c)", "$(fmt(at(key, t))) ± $(fmt(s(key)[findfirst(==(t), ts)]))",
        "± 0.05", pf(ok(1)); timed = ok, info = (; key, t, v))
end
r2, slope, t_hi = logfit(5, 4000)
addrow!("V-PRE1 log law, 5–4000", "linear in log₁₀ t (Fig. 13c)",
    "R² = $(fmt(r2)), slope $(fmt(slope))" * (t_hi < 4000 ? " (run ends at $t_hi)" : ""),
    "R² > 0.95, slope < 0", pf(r2 > 0.95 && slope < 0))
r2b, slopeb, _ = logfit(4, 512)
addrow!("extra (not in spec): log law, 4–512", "`test/papers.jl` window",
    "R² = $(fmt(r2b)), slope $(fmt(slopeb))", "R² > 0.95, slope < 0", pf(r2b > 0.95 && slopeb < 0))
c_homo, c_dd, c_ll = crossing(m(:dd) .+ m(:ll), m(:dl)), crossing(m(:dd), m(:dl)), crossing(m(:ll), m(:dl))
ok_homo(s) = c_homo !== nothing && c_homo <= 10s
ok_dd(s) = c_dd !== nothing && 5s <= c_dd <= 100s
ok_ll(s) = c_ll !== nothing && c_dd !== nothing && 5s <= c_ll <= 100s && c_dd <= c_ll
addrow!("V-PRE2 summed homotypic > heterotypic", "within ≈ 4 MCS (p.2140)", show_t(c_homo), "by t ≤ 10",
    pf(ok_homo(1)); timed = ok_homo)
addrow!("V-PRE2 dark–dark crosses heterotypic", "≈ 20 (Fig. 13c)", show_t(c_dd), "[5, 100]", pf(ok_dd(1));
    timed = ok_dd)
gap = c_dd === nothing || c_ll === nothing ? "" : "; ll/dd crossing ratio $(fmt(c_ll / c_dd)) (paper ≈ $(fmt(45 / 20)))"
addrow!("V-PRE2 light–light crosses heterotypic, after dark–dark", "≈ 45 (Fig. 13c)", show_t(c_ll) * gap,
    "[5, 100]; dd first", pf(ok_ll(1)); timed = ok_ll)
c_dM = (j = findfirst(<(0.003), m(:dM)); j === nothing ? nothing : ts[j])
ok_dM(s) = c_dM !== nothing && c_dM <= 1000s
addrow!("V-PRE3 dark–medium < 0.003", "≈ 0 by 300–600 (Fig. 13b)", show_t(c_dM), "by 10³", pf(ok_dM(1));
    timed = ok_dM)
## plateau: first save after which light–medium stays within 5% of its last value, and the
## curve is flat over the last decade: its least-squares slope in log₁₀ t, over the saves in
## [t_end / 10, t_end], changes it by at most 5% of its last value per decade
lM_end = m(:lM)[end]
j_plat = findfirst(j -> all(abs.(m(:lM)[j:end] .- lM_end) .<= 0.05lM_end), eachindex(ts))
t_plat = ts[j_plat]
js_last = findall(t -> t >= last(ts) / 10, ts)
lM_slope = length(js_last) < 2 ? NaN :
           let x = log10.(ts[js_last])
               cov(x, m(:lM)[js_last]) / var(x)
           end
flat = abs(lM_slope) <= 0.05lM_end
ok_plat(s) = t_plat <= 1000s && flat
addrow!("V-PRE3 light–medium plateau reached", "from ≈ 200 (Fig. 13b)",
    "$t_plat (within 5% of the value at $(last(ts))); last-decade slope $(fmt(lM_slope)) per decade",
    "before 10³; last-decade slope within ± 5% of the last value ($(fmt(0.05lM_end))) per decade",
    pf(ok_plat(1)); timed = ok_plat)
## plateau level: raw against the spec band, and relative to the medium share at t = 1
lM_1000 = at(:lM, 1000)
ratio, paper_ratio = lM_1000 / medium(1), 0.0625 / PAPER_MEDIUM
lo_r, hi_r = 0.050 / PAPER_MEDIUM, 0.075 / PAPER_MEDIUM
addrow!("V-PRE3 light–medium plateau level @ 10³", "0.062–0.063 (Fig. 13b); plateau / medium share at t = 1 ≈ $(fmt(paper_ratio))",
    "raw $(fmt(lM_1000)); plateau / medium share at t = 1 = $(fmt(ratio))",
    "raw in [0.050, 0.075]; size-corrected ratio in [$(fmt(lo_r)), $(fmt(hi_r))]",
    "raw $(pf(0.050 <= lM_1000 <= 0.075)); size-corrected $(pf(lo_r <= ratio <= hi_r))")
area(kk) = mean(mean(count(==(c), σ) for c in eachindex(kinds_of(i)) if kinds_of(i)[c] == kk)
                for (i, σ) in enumerate(sorted_states))
addrow!("V-GG6 mean area light < dark (at 10³)", "\"slightly smaller\" (PRL p.2014)",
    "$(fmt(area(2))) vs $(fmt(area(1)))", "light < dark", pf(area(2) < area(1)))

## informational: one global time scale for all timed rows
timed_rows = filter(r -> r.timed !== nothing, targets)
npass(s) = count(r -> r.timed(s), timed_rows)
scales = 2.0 .^ range(-1, 1; length = 41)
best = argmax(s -> (npass(s), -abs(log(s))), scales)
at_s(r) = r.timed === nothing ? "—" : pf(r.timed(best))

heading = FULL ? "Validation (n = $n)" :
          "**Smoke check (reduced, n = $n) — not validation.** Results below say whether this reduced run meets each target; the validation result is the pending full run."
Markdown.parse("""
$heading

| Target | Paper | Ours (mean ± SD, n = $n) | Tolerance | Result (nominal time) | at s = $(fmt(best)) (informational) |
|---|---|---|---|---|---|
""" * join(["| $(r.target) | $(r.paper) | $(r.ours) | $(r.tol) | $(r.result) | $(at_s(r)) |" for r in targets], "\n") * """


Informational: spec §8.5 ±2× (premise under revision). The single time scale
s = $(fmt(best)) ∈ [½, 2], applied to all $(length(timed_rows)) timed rows at once, makes
$(npass(best)) of them pass; $(npass(1.0)) pass at s = 1.
""")

# Diagnosis of the failing rows, generated from the table:

function light_on_surface(σ, k)      # share of light cells with a Moore neighbour in the medium #hide
    nx, ny = size(σ) #hide
    surf = falses(length(k)) #hide
    for y in 1:ny, x in 1:nx, dx in -1:1, dy in -1:1 #hide
        c = σ[x, y] #hide
        c != 0 && σ[mod1(x + dx, nx), mod1(y + dy, ny)] == 0 && (surf[c] = true) #hide
    end #hide
    return count(c -> surf[c] && k[c] == 2, eachindex(k)) / count(==(2), k) #hide
end #hide
## a cell–cell fraction rescaled to the paper's medium share #hide
corrected(r) = at(r.info.key, r.info.t) / (1 - medium(r.info.t)) * (1 - PAPER_MEDIUM) #hide
failing = filter(r -> occursin("FAIL", r.result), targets) #hide
lines = String[] #hide
for r in failing #hide
    if haskey(r.info, :key) #hide
        x = corrected(r) #hide
        ok = abs(x - r.info.v) <= 0.05 #hide
        push!(lines, "$(r.target): rescaled from our medium share ($(fmt(medium(r.info.t)))) to the " * #hide
            "paper's ($(fmt(PAPER_MEDIUM))), $(fmt(at(r.info.key, r.info.t))) becomes $(fmt(x)) against " * #hide
            "$(r.info.v), $(ok ? "which is within tolerance: consistent with the medium share of a small aggregate" : #hide
                                  "which still fails")." #hide
        ) #hide
    end #hide
end #hide
any(r -> haskey(r.info, :key), failing) && #hide
    push!(lines, "Caveat: the paper's medium share ($(fmt(PAPER_MEDIUM))) is its t = 1 value, applied at all " * #hide
        "times, and is read off Fig. 13(b) (our estimate of the read-off uncertainty: ≈ ±0.014).") #hide
if any(r -> startswith(r.target, "V-PRE1 light–light") && occursin("FAIL", r.result), failing) #hide
    push!(lines, "Light–light: at 10³, $(round(Int, 100mean(i -> light_on_surface(sorted_states[i], kinds_of(i)), eachindex(sorted_states))))% " * #hide
        "of light cells touch the medium. In a $ncells-cell aggregate nearly every light cell sits in the " * #hide
        "outer monolayer, so light–light bonds are scarce. The medium-share rescaling leaves " * #hide
        "$(count(r -> startswith(r.target, "V-PRE1 light–light") && haskey(r.info, :key) && #hide
                      abs(corrected(r) - r.info.v) > 0.05, failing)) of the failing light–light rows failing; " * #hide
        "a larger aggregate is needed to test them.") #hide
end #hide
any(r -> startswith(r.target, "V-PRE2 light–light") && occursin("FAIL", r.result), failing) && gap != "" && #hide
    push!(lines, "Crossings: shape, not only timing. Our dark–dark and light–light crossings are " * #hide
        "$(fmt(c_ll / c_dd))× apart in time; the paper's are ≈ $(fmt(45 / 20))× apart.") #hide
any(r -> startswith(r.target, "V-PRE1 log law"), failing) && #hide
    push!(lines, "Log law: the 5–4000 fit spans the plateau our small aggregate reaches; compare the extra 4–512 row.") #hide
any(r -> startswith(r.target, "V-PRE3 light–medium plateau level"), failing) && #hide
    push!(lines, "Plateau level: the raw value is set by aggregate size (perimeter/area); see the size-corrected ratio in the same row.") #hide
Markdown.parse(isempty(failing) ? "No row fails in this run." : #hide
               "Failing rows: $(join([r.target for r in failing], "; ")).\n\n" * join(["- " * l for l in lines], "\n")) #hide

# ## 6. Known limitations and open questions for the authors
#
# Questions for J.A. Glazier and F. Graner (spec §8.4, still open):
#
# - The lattice size of the PRE runs. With the boundary conditions it fixes the medium gap
#   around the aggregate, which matters for runs in which cells detach. The answer
#   replaces the lattice entry of the aggregate-size row.
# - The boundary conditions. The answer replaces the boundary-conditions row.
# - The dark/light fraction and how it was drawn. The answer replaces the type-fraction
#   row and the initial-state generator.
# - The definition of the "type-type correlation" plotted in PRE Figs. 13(d) and 21(b).
#   The answer adds it to the validation table.
#
# We would welcome corrections, the original input files, or a joint check of these
# results. Contact: the PottsModels maintainer. Answers are recorded as a new row in the
# deviations table and a dated changelog entry below.
#
# ## 7. How to cite
#
# Cite Graner & Glazier (1992) and Glazier & Graner (1993) first, then PottsModels
# (version and commit of this build). This is an independent reimplementation; it has not
# been reviewed or endorsed by the authors.
#
# | Date | Change | Reason |
# |---|---|---|
# | 2026-09-30 | First version (pilot tutorial, reduced run) | ROADMAP P6.0h |
# | 2026-09-30 | The full run uses a 1000-cell aggregate (`graner_glazier_aggregate`) | ROADMAP P6.1b2 |
