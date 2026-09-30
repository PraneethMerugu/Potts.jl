# # Reproducing Graner & Glazier (1992): cell sorting by differential adhesion
#
# !!! note "Draft prose"
#     (prose: draft) The text on this page is a placeholder written with the code; a
#     separate pass will revise it. Every number below is computed on this page when the
#     docs are built, except values quoted from the papers, which carry a citation.
#
# !!! warning "Reduced run"
#     The docs build runs a reduced ensemble (`POTTS_FULL_REPRODUCTION` unset). The
#     full-size run (`POTTS_FULL_REPRODUCTION=true`) produces the published validation
#     table; its committed outputs (`lib/PottsModels/reproductions/data/09/`) are
#     **pending**: no full run has been made yet. The tables below are therefore a smoke
#     check, not the validation result.
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
#   PDF: `docs/references/09c_GranerGlazier1993_PRE_differential-adhesion-rearrangement.pdf`.
#   It gives the initial-condition recipe (§II D3) and the measurement protocol (§II D1).
# - Released code: none.
# - Spec: `docs/design/research/model-specs/09_cell_sorting.md` (§2.1, §3.1, §5.1, §7, §8).
#   The Osborne et al. (2017) Potts benchmark in the same spec is a separate model and is
#   not reproduced here.
# - Reproducibility grade: **B**. Energies, λ, T and the time unit are stated; lattice
#   size, boundary conditions and the type fraction are not (spec A-GG5).
#
# The papers show that differential adhesion alone sorts a random mixture of two cell
# types: with the sorting hierarchy of PRL Eq. (3), heterotypic boundary shrinks roughly
# logarithmically in time and the light cells end up enveloping the dark ones. This page
# reproduces that time course (PRL Fig. 2), the engulfment end state, and two contrasting
# regimes from the PRE (partial sorting, §III E; no sorting with symmetric contacts).

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

@named gg = GranerGlazier()
σ0, k0 = graner_glazier_state()
prob0 = PottsProblem(gg, [ownership => σ0, kind => k0], (0, 1); seed = 1)
J = getp(prob0, :J)(prob0)
par(name) = getp(prob0, name)(prob0)
Markdown.parse("""
| Symbol | Value | Meaning | Source | Status |
|---|---|---|---|---|
| J(d,d) | $(J[2, 2]) | dark–dark contact | PRL p.2015 | stated |
| J(d,l) | $(J[2, 3]) | dark–light contact | PRL p.2015 | stated |
| J(l,l) | $(J[3, 3]) | light–light contact | PRL p.2015 | stated |
| J(d,M) = J(l,M) | $(J[1, 2]) | cell–medium contact | PRL p.2015 | stated |
| λ | $(par(:λ)) | area-constraint strength | PRL p.2014 | stated |
| A(d) = A(l) | $(par(:V₀)) | target area (sites) | PRL p.2015; PRE p.2130, p.2151 | stated (PRE) |
| T | $(par(:T)) | temperature (k = 1) | PRL p.2014 | stated |
| lattice | $(join(size(σ0), " × ")), periodic | domain | — | our choice (unstated) |
| cells | $(length(k0)) ($(count(==(1), k0)) dark, $(count(==(2), k0)) light) | initial aggregate | PRE §II D3 recipe | derived |
""")

# **Units.** Lengths are lattice sites. One of our MCS is N copy attempts, N the number
# of lattice sites (medium included); the paper's MCS is 16N attempts (PRL p.2014), so
# one paper MCS is 16 of ours.

const PAPER_MCS = 16
nothing #hide

# ## 3. Deviations
#
# | Item | Paper | Released code | Our default | Variant keyword | Reason |
# |---|---|---|---|---|---|
# | Time unit | 1 MCS = 16N attempts (PRL p.2014) | — | 1 MCS = N attempts | — | INTERNALS F8; times are converted, paper t = our 16t |
# | Aggregate size | ≈ 1000 cells (PRE p.2129) | — | 64 cells on 72 × 72 | `graner_glazier_state(scale)` tiles aggregates | Cost. Boundary fractions scale with perimeter/area; sorting levels off after ≈ 500 paper MCS (spec §8.6 D1) |
# | Boundary conditions | unstated | — | periodic | `lattice` keyword | Aggregate never reaches its image; unsuitable for dispersal runs (D2) |
# | Type fraction | unstated (A-GG5) | — | probability ½ per cell (33/31) | — | Assumption, recorded in `data/graner/provenance.toml` |
# | Initial state | PRE §II D3: square aggregate of staggered bricks relaxed 400 paper MCS | — | the same recipe, 64 cells | — | D-049 F-2; `data/graner/generate.jl` |
# | T = 0 annealing | 2 paper MCS "before calculating the statistical properties" (PRL p.2014; PRE p.2134) | — | on a copy, 32 of our MCS | anneal the trajectory | README §4.6 S2: a measurement, not dynamics |
# | Target area per kind | one value except the cavity run (PRE Fig. 28) | — | one `V₀` | — | Per-kind targets not expressible yet (D14) |
# | Boundary length | mismatched bonds on the 8-neighbour lattice, medium included (PRE p.2133) | — | the same, each bond once | — | Once/twice counting cancels in fractions (D8) |

# ## 4. Build and run
#
# One replicate to 10³ paper MCS, sequential CPU solver:

alg = SequentialCPM(; proposal = Moore(1))
prob = remake(prob0; tspan = (0, PAPER_MCS * 1000))
t_one = @elapsed solve(prob, alg)
Markdown.parse("One replicate, 10³ paper MCS on the CPU: **$(round(t_one; digits = 1)) s**.")

# A variant is ordinary model code, here a parameter `remake`. The partial-sorting regime
# of PRE §III E swaps J(d,l) and J(l,l) and lowers T:

prob_partial = remake(prob; p = [:J => [0 16 16; 16 2 14; 16 14 11], :T => 5.0])
nothing #hide

# ### Measurement (PRE §II D1)
#
# Fractional boundary length: mismatched Moore bonds between two kinds divided by all
# mismatched bonds (medium included), measured on a copy annealed for 2 paper MCS at
# T = 0. These are the definitions of `lib/PottsModels/test/papers.jl`.
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

function annealed(σ, k; seed = 1)
    q = PottsProblem(GranerGlazier(; name = :anneal), [ownership => copy(σ), kind => k, :T => 0.0],
        (0, 2PAPER_MCS); seed)
    return ownership(solve(q, SequentialCPM(); saveat = 2PAPER_MCS).u[end])
end

function fractions(σ, k)
    n = bond_counts(annealed(σ, k), k)
    total = sum(values(n))
    return Dict(key => v / total for (key, v) in n)
end

function radius_ratio(σ, k)    # mean distance to the aggregate centroid, dark / light
    sites = findall(!=(0), σ)
    c = (mean(i[1] for i in sites), mean(i[2] for i in sites))
    r(kk) = mean(hypot(i[1] - c[1], i[2] - c[2]) for i in sites if k[σ[i]] == kk)
    return r(1) / r(2)
end

# engulfment as in `papers.jl`: dark–medium boundary below 0.003 and dark cells nearer the centre
engulfed(σ, k) = fractions(σ, k)[:dM] < 0.003 && radius_ratio(σ, k) < 0.75
nothing #hide

# ## 5. Validation
#
# ### Ensemble

n = FULL ? 10 : 4
ts = FULL ? [1, 2, 4, 8, 16, 32, 40, 64, 128, 256, 512, 1000, 2000, 4000, 10_000] :
     [1, 2, 4, 8, 16, 32, 40, 64, 128, 256, 512, 1000]
ens = solve(EnsembleProblem(remake(prob; tspan = (0, PAPER_MCS * last(ts)))), alg, EnsembleThreads();
    trajectories = n, saveat = PAPER_MCS .* ts)
keys5 = (:dl, :dd, :ll, :dM, :lM)
F = Dict(key => zeros(n, length(ts)) for key in keys5)
for (i, sol) in enumerate(ens.u), (j, t) in enumerate(ts)
    f = fractions(ownership(sol.u[findfirst(==(PAPER_MCS * t), sol.t)]), k0)
    for key in keys5
        F[key][i, j] = f[key]
    end
end
m(key) = vec(mean(F[key]; dims = 1))
s(key) = vec(std(F[key]; dims = 1))
fmt(x) = string(round(x; digits = 3))
Markdown.parse("""
n = $n replicates (`seed = 1`, replicas 1:$n), `SequentialCPM(; proposal = Moore(1))`, CPU,
$(Threads.nthreads()) thread(s). Fractions of all mismatched bonds, mean ± SD:

| paper MCS | heterotypic | dark–dark | light–light | dark–medium | light–medium |
|---|---|---|---|---|---|
""" * join(["| $t | " * join(["$(fmt(m(key)[j])) ± $(fmt(s(key)[j]))" for key in keys5], " | ") * " |"
            for (j, t) in enumerate(ts)], "\n"))

# Side by side with PRL Fig. 2(a): the markers are values read by eye from the figure (spec
# §5.1 V-GG1, uncertainty about ±0.03, drawn as bars); no digitised data file exists yet
# (`reproductions/data/09/paper/` is pending).

paper_t = [1, 40, 1000, 10_000]
paper_H = [0.40, 0.25, 0.12, 0.05]                           # PRL Fig. 2(a), read from plot
fig = Figure(size = (720, 420))
ax = Axis(fig[1, 1]; xscale = log10, xlabel = "time (paper MCS)", ylabel = "fraction of boundary")
for (key, label) in zip(keys5, ("heterotypic", "dark–dark", "light–light", "dark–medium", "light–medium"))
    band!(ax, ts, m(key) .- s(key), m(key) .+ s(key); alpha = 0.25)
    lines!(ax, ts, m(key); label)
end
errorbars!(ax, paper_t, paper_H, fill(0.03, 4); color = :black)
scatter!(ax, paper_t, paper_H; color = :black, label = "PRL Fig. 2(a), heterotypic")
Legend(fig[1, 2], ax; framevisible = false)
fig

# Snapshots of replicate 1 (dark kind blue, light kind green, medium black), for
# comparison with PRL Fig. 1:

snap = [1, 64, 1000]
fig = Figure(size = (900, 320))
sol1 = ens.u[1]
for (c, t) in enumerate(snap)
    ax = Axis(fig[1, c]; title = "$t paper MCS", aspect = DataAspect())
    hidedecorations!(ax)
    pottsplot!(ax, renderframe(sol1; index = findfirst(==(PAPER_MCS * t), sol1.t)); boundaries = true)
end
fig

# ### Contrasting regimes and negative control
#
# Engulfment (default J) against partial sorting (PRE §III E, J(d,l) = 14, J(l,l) = 11,
# T = 5), and against symmetric contacts, where sorting has no driving force.

t_end = 1000
last_states(ens) = [ownership(sol.u[end]) for sol in ens.u]
sorted_states = [ownership(sol.u[findfirst(==(PAPER_MCS * t_end), sol.t)]) for sol in ens.u]
partial_states = last_states(solve(EnsembleProblem(prob_partial), alg, EnsembleThreads(); trajectories = n,
    saveat = [PAPER_MCS * t_end]))
prob_sym = remake(prob; p = [:J => [0 16 16; 16 11 11; 16 11 11]])
sym_states = last_states(solve(EnsembleProblem(prob_sym), alg, EnsembleThreads(); trajectories = n,
    saveat = [PAPER_MCS * t_end]))
regime(states) = (count(σ -> engulfed(σ, k0), states),
    mean(σ -> fractions(σ, k0)[:dM], states), mean(σ -> fractions(σ, k0)[:dl], states))
rows = [("sorting (PRL defaults)", "engulfment", regime(sorted_states)),
    ("partial sorting (PRE §III E)", "no monolayer", regime(partial_states)),
    ("symmetric contacts (control)", "no sorting", regime(sym_states))]
Markdown.parse("""
At $t_end paper MCS, n = $n each:

| Run | Paper outcome | engulfed (of $n) | dark–medium | heterotypic |
|---|---|---|---|---|
""" * join(["| $r | $o | $(e) | $(fmt(dm)) | $(fmt(h)) |" for (r, o, (e, dm, h)) in rows], "\n"))

# ### Pass/fail table
#
# Targets and tolerances from spec §5.1. The pre-registration commit of this table is
# pending (it must precede the first full run).

row(j) = findfirst(==(j), ts)
H = m(:dl)
fit = (x = log.(ts[row(4):row(512)]); y = H[row(4):row(512)]; (cor(x, y)^2, cov(x, y) / var(x)))
cross = ts[findfirst(j -> m(:dd)[j] > m(:dl)[j], eachindex(ts))]
dark_area = mean(mean(count(==(c), σ) for c in eachindex(k0) if k0[c] == 1) for σ in sorted_states)
light_area = mean(mean(count(==(c), σ) for c in eachindex(k0) if k0[c] == 2) for σ in sorted_states)
pf(ok) = ok ? "PASS" : "FAIL"
within(x, target, tol) = pf(abs(x - target) <= tol)
targets = [
    ("V-GG1 heterotypic @ 1", "≈ 0.40 (Fig. 2a)", "$(fmt(H[row(1)])) ± $(fmt(s(:dl)[row(1)]))", "± 0.05",
        within(H[row(1)], 0.40, 0.05)),
    ("V-GG1 heterotypic @ 40", "≈ 0.25 (Fig. 2a)", "$(fmt(H[row(40)])) ± $(fmt(s(:dl)[row(40)]))", "± 0.05",
        within(H[row(40)], 0.25, 0.05)),
    ("V-GG1 heterotypic @ 10³", "≈ 0.12 (Fig. 2a)", "$(fmt(H[row(1000)])) ± $(fmt(s(:dl)[row(1000)]))",
        "± 0.05", within(H[row(1000)], 0.12, 0.05)),
    ("V-GG1 heterotypic @ 10⁴", "≈ 0.05 (Fig. 2a)",
        FULL ? "$(fmt(H[row(10_000)])) ± $(fmt(s(:dl)[row(10_000)]))" : "not run (reduced)", "± 0.05",
        FULL ? within(H[row(10_000)], 0.05, 0.05) : "—"),
    ("V-GG1 log law, 4–512", "linear in ln t (Fig. 2a)", "R² = $(fmt(fit[1])), slope $(fmt(fit[2]))",
        "R² > 0.95, slope < 0", pf(fit[1] > 0.95 && fit[2] < 0)),
    ("V-GG3 dark–dark overtakes heterotypic", "≈ 4 MCS (PRL p.2015)", "$cross paper MCS", "2–10",
        pf(2 <= cross <= 10)),
    ("V-GG4 dark–medium @ 512", "→ 0 by ≈ 300 (Fig. 2b)", "$(fmt(m(:dM)[row(512)]))", "< 0.005",
        pf(m(:dM)[row(512)] < 0.005)),
    ("V-GG4 light–medium @ 10³", "≈ 0.057 plateau (Fig. 2b)", "$(fmt(m(:lM)[row(1000)]))", "0.045–0.07",
        pf(0.045 <= m(:lM)[row(1000)] <= 0.07)),
    ("V-GG6 mean area light < dark", "\"slightly smaller\" (PRL p.2014)",
        "$(fmt(light_area)) vs $(fmt(dark_area))", "light < dark", pf(light_area < dark_area)),
]
Markdown.parse("""
| Target | Paper | Ours (mean ± SD, n = $n) | Tolerance | Result |
|---|---|---|---|---|
""" * join(["| " * join(r, " | ") * " |" for r in targets], "\n"))

# Where a row fails, the leading suspect is aggregate size: with 64 cells rather than
# ≈ 1000, the medium boundary is a larger share of all boundary and sorting stalls once
# the single dark cluster has formed (spec §8.6 D1, D9). A full run at paper size needs a
# single large aggregate, which `graner_glazier_state` does not yet generate.
#
# ## 6. Known limitations and open questions for the authors
#
# - (Glazier, Graner) The simulation set-up of PRE 47, 2128: lattice size, boundary
#   conditions and the dark/light fraction (spec A-GG5). An answer replaces rows 2–4 of the
#   deviations table and the initial-state generator.
# - (Glazier, Graner) Were the two T = 0 annealing steps applied to a copy or to the
#   trajectory (A-GG4)? The PRE (p.2134) reads as a copy, which is our default.
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
