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
#     cells per replicate (`graner_glazier_aggregate(1000; seed = replicate)`), so the
#     differences that come from aggregate size (deviations table) can be tested there. The
#     committed full-run outputs (`lib/PottsModels/reproductions/data/09/`) are **pending**:
#     no full run has been made yet.
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
# - Spec: `docs/design/research/model-specs/09_cell_sorting.md` (§2.1, §3.1, §8.4, §8.5,
#   and the pre-registration audit §9). The Osborne et al. (2017) Potts benchmark in the
#   same spec is a separate model and is not reproduced here.
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
const SEED = 1                          # base seed of every ensemble on this page

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
# The starts: the reduced build shares the 64-cell `graner_glazier_state` between its
# replicates; the full build gives replicate i its own paper-size aggregate
# `graner_glazier_aggregate(1000; seed = i, margin = MARGIN)`, so the kind assignments are independent (spec
# §9.0). The published constructor carries the rest:

n = FULL ? 10 : 4                       # replicates (spec §9.0: 4 smoke, 10 full)
σ_state, k_state = graner_glazier_state()
n_state, dims_state = length(k_state), join(size(σ_state), " × ")
const MARGIN = 10                       # medium margin of the full-run aggregates (periodic check in §5)
starts = [FULL ? graner_glazier_aggregate(1000; seed = i, margin = MARGIN) : (σ_state, k_state) for i in 1:n]
σ0, k0 = starts[1]
gg = GranerGlazier(; name = :gg, lattice = size(σ0))
prob0 = PottsProblem(gg, [ownership => σ0, kind => k0], (0, 1); seed = SEED)
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
| cells | $ncells ($ndark dark, $nlight light) | — | initial aggregate | $(FULL ? "`graner_glazier_aggregate`; PRE p.2129 ≈ 1000" : "PRE §II D3 recipe") | derived |
""")

# **Units.** Lengths are lattice sites. One of our MCS is N copy attempts, N the number
# of lattice sites (medium included). The paper's MCS is 16N attempts (PRL p.2014), so
# one paper MCS is 16 of ours. All times on this page are paper MCS. The full build runs
# to 2×10⁴ paper MCS (spec §9.0).

const PAPER_MCS = 16
const T_FULL = 20_000
nothing #hide

# Cell areas of the starts, for the initial-state row below: the paper-size aggregate is
# not Potts-relaxed, `graner_glazier_state` is.

function cell_areas(σ, k)                 # site count of every cell; 0 for a vanished cell
    a = zeros(Int, length(k))
    for c in σ
        c > 0 && (a[c] += 1)
    end
    return a
end
big_start = FULL ? starts[1] : graner_glazier_aggregate(1000; seed = 1)     # a paper-size start
voronoi_starts = FULL ? starts : [big_start]
sd_voronoi = mean(std(cell_areas(s...)) for s in voronoi_starts)
sd_relaxed = std(cell_areas(σ_state, k_state))
nothing #hide

# ## 3. Deviations

## the same start embedded in a lattice twice as wide (the periodic-boundary variant run of §5)
function padded(σ)
    P = zeros(eltype(σ), 2 .* size(σ))
    o = size(σ) .÷ 2
    P[o[1] .+ (1:size(σ, 1)), o[2] .+ (1:size(σ, 2))] .= σ
    return P
end
dims_pad = join(2 .* size(σ0), " × ")
Markdown.parse("""
| Item | Paper | Released code | Our default | Variant keyword | Reason |
|---|---|---|---|---|---|
| Time unit | 1 MCS = 16N attempts (PRL p.2014) | — | 1 MCS = N attempts | — | INTERNALS F8; times are converted, paper t = our $(PAPER_MCS)t. Both samplers pick target sites uniformly over the whole lattice, so verdicts are read at the paper's nominal times (spec §8.5) |
| Aggregate size | ≈ 1000 cells (PRE p.2129) | — | $(n_state) cells on $(dims_state) (`graner_glazier_state`)$(FULL ? "; this run uses the variant" : "") | `graner_glazier_aggregate(n)`: one round aggregate of n cells on a lattice sized to fit (the full run: n = 1000, one per replicate) | Cost of the docs build. With the small aggregate, boundary fractions scale with perimeter/area and sorting levels off long before 10⁴ paper MCS; the full run tests this deviation |
| Log-law window | 5–4000 paper MCS (spec §9.1 V-PRE1) | — | also reported over 4–512 | — | The window of `test/papers.jl`, which ends before our small aggregate levels off. Extra row, not a replacement |
| Boundary conditions | unstated | — | periodic | `lattice` keyword | The aggregate stays clear of its image: the same starts embedded in a $(dims_pad) lattice give the same bond counts (variant run in §5)$(FULL ? "; the aggregates have a medium margin of $MARGIN sites" : ""). The full run's margin of $MARGIN was chosen by a separate check with 120-cell aggregates on lattices twice as wide (spec §9.1 ruling 3); the gap to the periodic image is twice the margin whatever the cell count. Unsuitable for dispersal runs, which need a margin of at least 60 sites (`graner_glazier_aggregate(n; margin)`; spec §8.6 D2, §9.1 V-PRE14/15) |
| Type fraction | unstated (spec §8.4) | — | $(FULL ? "equal numbers, randomly placed" : "probability ½ per cell") ($ndark dark / $nlight light) | — | $(FULL ? "Assumption; `graner_glazier_aggregate`, one draw per replicate" : "Assumption, recorded in `data/graner/provenance.toml`") |
| Initial state | square aggregate of staggered bricks relaxed 400 paper MCS (PRE §II D3) | — | $(FULL ? "a round aggregate of $ncells centroidal Voronoi cells, not Potts-relaxed (`graner_glazier_aggregate`)" : "the same recipe with $ncells cells") | $(FULL ? "—" : "`graner_glazier_aggregate(n)`") | $(FULL ? "Paper size. " : "D-049 F-2; `data/graner/generate.jl`. ")The paper-size aggregate is not relaxed: its cell-area SD is $(round(sd_voronoi; digits = 1)) sites (mean over the $(length(voronoi_starts)) paper-size start(s) built on this page), against $(round(sd_relaxed; digits = 1)) for the Potts-relaxed `graner_glazier_state`. Heterotypic fractions from a Voronoi and from a relaxed start agree at 1, 10 and 100 paper MCS (D-063; P6.1b2 review), and so does the V-PRE4 boundary drop (spec §9.1 V-PRE4) |
| T = 0 annealing | 2 paper MCS on a copy: "We anneal the displayed data only" (PRE p.2134) | — | on a copy, $(2PAPER_MCS) of our MCS, run's J | — | Matches the paper (spec §8.4 A-GG4, resolved) |
| Target area per kind | one value except the cavity run (PRE Fig. 28) | — | one `V₀` | — | Per-kind targets not expressible yet (spec §8.6 D14) |
| Boundary length | mismatched bonds on the 8-neighbour lattice, medium included (PRE p.2133) | — | the same, each bond once | — | Once/twice counting cancels in fractions (spec §8.6 D8) |
| Two published runs (paper-internal) | PRL Fig. 2 and PRE Fig. 13 use the same parameters but differ: dark–dark at 10 MCS, dd crossing time, light–medium plateau (spec §9.2) | — | the sorting targets use the envelope of both runs, widened by 0.03 (spec §9.1) | — | Spec §8.5 "Supersession": a single paper curve ± 0.05 would fail a model that reproduces the other run. Which run PRL Fig. 2 is: question in §6 |
| Monolayer time (paper-internal) | light monolayer "after 300 MCS" (PRL p.2015) against "After 600 MCS" (PRE p.2140) | — | read as the two runs; the target is dark–medium < 0.003 by 10³ (V-PRE3 (a)), which both runs meet | — | Spec §8.4, §9.1 V-PRE3 (a) |
| Annealing temperature in PRE Fig. 23 (paper-internal) | caption: "two MCS of T = 10 annealing"; the protocol is T = 0 (PRE p.2134) | — | T = 0 for the partial-sorting copy too | — | Read as a typo (spec §8.2; §9.1 V-PRE13) |
""")

# ## 4. Build and run
#
# One replicate to 10³ paper MCS, sequential CPU solver, timed after a warm-up solve.

alg = SequentialCPM(; proposal = Moore(1))
prob = remake(prob0; tspan = (0, PAPER_MCS * 1000))
solve(remake(prob; tspan = (0, PAPER_MCS)), alg)            # warm-up (compilation)
t_one = @elapsed solve(prob, alg)
Markdown.parse("One replicate ($ncells cells), 10³ paper MCS on the CPU, compiled: " *
               "**$(round(t_one; digits = 1)) s**." *
               (FULL ? "" : " In the reduced build this is the $ncells-cell aggregate, so this is not the " *
                            "paper-size cost; the full build times the 1000-cell aggregate."))

# The paper-size cost. The reduced build times about 10 paper MCS of
# `graner_glazier_aggregate(1000)`; the full build reads it off the run above.

t_per_mcs = if FULL
    t_one / 1000
else
    prob_big = PottsProblem(GranerGlazier(; name = :gg1000, lattice = size(big_start[1])),
        [ownership => big_start[1], kind => big_start[2]], (0, PAPER_MCS); seed = 1)
    solve(prob_big, alg)                                     # warm-up (compilation)
    (@elapsed solve(remake(prob_big; tspan = (0, 10PAPER_MCS)), alg)) / 10
end
Markdown.parse("Paper size ($(length(big_start[2])) cells on $(join(size(big_start[1]), " × "))): " *
               "**$(round(t_per_mcs; digits = 3)) s per paper MCS**, so one full-run replicate " *
               "($T_FULL paper MCS) takes about $(round(t_per_mcs * T_FULL / 3600; digits = 1)) h on one CPU thread.")

# A variant is ordinary model code, here a parameter `remake`. The partial-sorting regime
# of PRE §III E swaps J(d,l) and J(l,l) and lowers T:

prob_partial = remake(prob; p = [:J => [0 16 16; 16 2 14; 16 14 11], :T => 5.0])
nothing #hide

# ### Measurement (PRE §II D1)
#
# Fractional boundary length is the number of mismatched Moore bonds between two kinds,
# divided by all mismatched bonds (medium included). It is measured on a copy annealed for
# 2 paper MCS at T = 0 with the run's own contact energies. The definitions follow
# `lib/PottsModels/test/papers.jl` and spec §9.0.
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

## dark clusters (spec §9.0): connected components of the dark cells, two cells adjacent
## when they share a Moore bond; returns the count and the largest one's share of dark cells
function root!(parent, c)
    while parent[c] != c
        parent[c] = parent[parent[c]]
        c = parent[c]
    end
    return c
end
function dark_clusters(σ, k)
    parent = collect(eachindex(k))
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a, b = σ[x, y], σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        (a == b || a == 0 || b == 0 || k[a] != 1 || k[b] != 1) && continue
        parent[root!(parent, a)] = root!(parent, b)
    end
    a = cell_areas(σ, k)
    size_of = Dict{Int, Int}()
    for c in eachindex(k)
        (k[c] == 1 && a[c] > 0) || continue
        r = root!(parent, c)
        size_of[r] = get(size_of, r, 0) + 1
    end
    return length(size_of), maximum(values(size_of)) / sum(values(size_of))
end
nothing #hide

# ## 5. Validation
#
# ### Pre-registered targets
#
# The targets are copied from spec §9.1, which folds V-GG1–V-GG4 into V-PRE1–V-PRE3 as a
# second paper run. Verdict classes (spec §9.0): **SMOKE+FULL** rows are size-free and
# binding in both builds; **FULL** rows are paper comparisons with a verdict only in the full
# run, reported as information here. Times are paper MCS; fractions are of all mismatched
# bonds on the annealed copy. NC1 is the symmetric-contact control, J = [0 16 16; 16 11 11;
# 16 11 11]. Rules marked "verbatim" are copied from §9.1; the others are abridged, and for
# every row §9.1 is the binding text.
#
# | Target | Source | Pass rule (spec §9.1) | Class | Status (spec §9.1) | On this page |
# |---|---|---|---|---|---|
# | V-GG1–V-GG4 | PRL Fig. 2, p.2015–2016 | — (enter V-PRE1–V-PRE3 as the second run) | — | superseded | as PRL markers and envelope |
# | V-GG5 | PRL Fig. 1 | — (covered by V-PRE5) | — | superseded | — |
# | V-GG6 | PRL p.2014 | per replicate Δa = `⟨a_l⟩ − ⟨a_d⟩` on the raw state at 10³; mean Δa < 0 and \|mean Δa\| > 2 SE; NC1 \|mean Δa\| < ½ \|mean Δa\| | SMOKE+FULL | fix applied | computed |
# | V-PRE1 dl, dd, ll | PRE Fig. 13(c); PRL Fig. 2(a) | mean at 10, 100, 10³, 10⁴ inside the two-run envelope ± 0.03 | FULL | fix applied | computed (10⁴ in the full run) |
# | V-PRE1 log law | PRL Fig. 2 caption; PRE Fig. 13(c) | fit of mean `F_dl` on log₁₀ t over [5, 4000]: R² > 0.95, slope in [−0.15, −0.07] per decade | FULL | fix applied | computed |
# | V-PRE2 | PRE Fig. 13(c); PRL Fig. 2(a); PRE p.2140 | dd crossing in [2.5, 40]; ll crossing in [19, 100]; dd first; dd + ll > dl at every save; NC1: no dd or ll crossing by 10³ | FULL | fix applied | computed |
# | V-PRE3 (a) | PRE Fig. 13(b); PRL Fig. 2(b) | FULL: first save with mean `F_dM` < 0.003 is ≤ 10³. Size-free form (ruling of 2026-09-30), reported only: first save with mean `F_dM`(t) / mean `F_dM`(1) < 0.1; it was to bind the reduced build if 20 calibration seeds reached it by the 500 save, and they did not (P6.1c), so (a) is FULL-only. Both builds, NC1: mean `F_dM`(10³) ≥ 0.01 | FULL; NC1 clause SMOKE+FULL | ready | computed |
# | V-PRE3 (b) | same | plateau `t_p` ≤ 10³ and last-decade log-slope of `F_lM` within ± 5% of its last value | FULL | ready | computed |
# | V-PRE3 (c) | same; spec §8.5 | R = `F_lM`(10³) / [`F_dM`(1) + `F_lM`(1)] in [0.85, 1.10] | FULL | fix applied | computed |
# | V-PRE3 (d) | same | raw `F_lM`(10³) in [0.050, 0.075] | FULL | ready | computed |
# | V-PRE4 | PRE Fig. 13(a) | D = [`N_mm`(1) − mean `N_mm` over [100, 10³]] / `N_mm`(1) in [0.005, 0.03]; \|log-slope of `N_mm` over [10³, 10⁴]\| ≤ 0.005 `N_mm`(10³) per decade | FULL | fix applied | computed; start check in the full run |
# | V-PRE5 | PRE Fig. 12 | mean dark-cluster count non-increasing over 10, 100, 10³, 10⁴; largest dark cluster ≥ 90% of dark cells at 10⁴; mean `F_dM`(10⁴) < 0.001 | FULL | fix applied | computed (10⁴ in the full run) |
# | V-PRE6 | PRE Table II | bulk ⟨n⟩, μ₂ against T | — | **parked** (neighbour rule for n undefined) | — |
# | V-PRE7 | PRE Fig. 15 | T = 0: \|`F_dl`(2000) − `F_dl`(100)\| < 0.02. Order at 10³: `F_dl`(T=2) > `F_dl`(T=5) > `F_dl`(T=10). T = 40: `F_dl` > 0.07 at every save in [10³, 10⁴]. T = 80: > 50% of cells gone (volume 0) by 500 (verbatim) | FULL + T scan | ready | not yet on this page |
# | V-PRE8 | PRE Fig. 16, Table III | λ = 0.1: 0 cells alive. λ = 0.2: 0 light, ≥ 90% dark alive. λ = 0.5: ≥ 90% light alive. λ ≥ 1: all alive. `t*(λ = 10) / t*(λ = 0.5)` ∈ [3, 30] (verbatim) | FULL + λ scan | fix applied | not yet on this page |
# | V-PRE9 | PRE Figs. 7–8 | checkerboard: mean `F_dl`(10³) ≥ 0.72 and log-slope of `F_dl` over [10, 2000] > 0; `F_ll`(10³), `F_dd`(10³) ≤ 0.12 (verbatim) | FULL | ready | not yet on this page |
# | V-PRE10 | PRE Fig. 9, Table I | T = 0: \|`F_dl`(2000) − `F_dl`(100)\| < 0.02; `F_dl`(2000) at T = 15 and T = 40 < `F_dl`(2000) at T = 10 (verbatim) | FULL + T scan | fix applied | not yet on this page |
# | V-PRE11 | PRE Figs. 18–19 | mean `F_dM`(10³) > 0.005 and decreasing across saves 10², 10³, 10⁴; log-slope of `F_dM` over [10³, 10⁴] < log-slope over [10², 10³] (accelerating on log axes); a linear-in-t fit of `F_dM` over [2000, 10⁴] reaches 0 at t ∈ [5×10³, 3×10⁴] (verbatim) | FULL | fix applied | not yet on this page |
# | V-PRE12 | PRE Figs. 20–21 | `J_lM` = 30: `F_lM` < 0.005 from 200; `F_dl` within ± 0.05 of 0.38, 0.25, 0.13 at 10, 100, 10³ | FULL | fix applied | not yet on this page |
# | V-PRE13 (a) | PRE Fig. 23(b), replotted in Fig. 24(b) | partial sorting: mean `F_dM`(10³) > 0.01 | SMOKE+FULL | fix applied | computed |
# | V-PRE13 (b) | PRE Fig. 23(a) | partial sorting: mean `F_dl` within ± 0.05 of 0.325, 0.245, 0.17 at 10, 100, 10³ | FULL | fix applied | computed |
# | V-PRE14 | PRE Fig. 25 | dispersal (`J_lM` = 2, `J_dd` = 4, T = 5), unannealed: > 20% of light cells outside the largest component at 480 | FULL, margin ≥ 60 (`graner_glazier_aggregate(n; margin)`) | ready | not yet on this page |
# | V-PRE15 | PRE Figs. 26–27 | `J_ld` = 35: ≥ 2 components of ≥ 10% of cells; `J_ld` = 29: largest ≥ 95%, at 2000 | FULL, larger margin | fix applied | not yet on this page |
# | V-PRE16 | PRE Figs. 4–5 | generator plateau: \|mean of the last 4 saves − mean of the first 4\| ≤ 2% of the window mean, over the last 100 of 400 MCS, for `F_lM` and `N_mm` on a 10-MCS T = 0 annealed copy (ruling of 2026-09-30; ⟨n⟩ part parked) | generator | ready (plateau) / **parked** (⟨n⟩) | generator: checked when `data/graner/generate.jl` regenerates the start, not in CI |
# | V-PRE17 | PRE Fig. 2 | bulk ⟨n⟩ after 2 annealing MCS | — | **parked** | — |
# | V-OS1–V-OS5 | Osborne et al. (2017) | CP benchmark (OS3, OS4 parked) | OS | waits for an OS port | — (separate model) |
# | NC1 | D-048 | at 10³: mean of `F_dl` / (1 − `F_dM` − `F_lM`) ≥ 0.40 (size-free heterotypic share of cell–cell bonds; ruling of 2026-09-30, calibrated on seeds 7001–7024 in P6.1c); mean `F_dM` ≥ 0.01; 0 of n engulfed. The old raw `F_dl` ≥ 0.35 is reported only | SMOKE+FULL | fix applied | computed |

## pre-registration status of this page, read from git and the frozen-test list
page = joinpath(pkgdir(PottsModels), "reproductions", "09_cell_sorting.jl")
git(args...) = try
    readchomp(Cmd(`git $args`; dir = dirname(page)))
catch
    ""
end
page_commit = git("log", "-1", "--format=%h %cs", "--", basename(page))
page_dirty = !isempty(git("status", "--porcelain", "--", basename(page)))
frozen_list = joinpath(pkgdir(PottsModels), "test", "frozen.toml")
page_frozen = isfile(frozen_list) && occursin("reproductions/" * basename(page), read(frozen_list, String))
Markdown.parse("This table was last changed in commit " *
               (isempty(page_commit) ? "(git unavailable)" : "`$page_commit`") *
               (page_dirty ? ", with uncommitted edits in this build" : "") * ". " *
               (page_frozen ? "It is frozen (`lib/PottsModels/test/frozen.toml`)." :
                "It is not frozen yet: the pre-registration commit is pending and must precede the first full run."))

# ### Ensemble

## replicate i starts from `starts[i]` (§2); the reduced run's starts are all the same state
kinds_of(i) = starts[i][2]
from_start(q, ctx) = FULL ? remake(q; u0 = [ownership => starts[ctx.sim_id][1], kind => starts[ctx.sim_id][2]]) : q
ts = [1, 2, 3, 4, 5, 6, 8, 10, 13, 16, 20, 25, 32, 40, 50, 64, 80, 100, 128, 160, 200, 256, 320,
    400, 500, 640, 800, 1000, 1280, 1600, 2000]
FULL && append!(ts, [2560, 3200, 4000, 5000, 6400, 8000, 10_000, 12_800, 16_000, T_FULL])
ens = solve(EnsembleProblem(remake(prob; tspan = (0, PAPER_MCS * last(ts))); prob_func = from_start), alg,
    EnsembleThreads();
    trajectories = n, saveat = PAPER_MCS .* ts)
state_at(sol, t) = ownership(sol.u[findfirst(==(PAPER_MCS * t), sol.t)])
keys5 = (:dl, :dd, :ll, :dM, :lM)
Cb = Dict(key => zeros(n, length(ts)) for key in keys5)      # bond counts on the annealed copy
Nmm = zeros(n, length(ts))                                   # total length: all mismatched bonds
cluster_t = filter(t -> t in (10, 100, 1000, 10_000), ts)
ncluster, largest = zeros(n, length(cluster_t)), zeros(n, length(cluster_t))
for (i, sol) in enumerate(ens.u), (j, t) in enumerate(ts)
    σa = annealed(state_at(sol, t), kinds_of(i), prob)
    b = bond_counts(σa, kinds_of(i))
    Nmm[i, j] = sum(values(b))
    for key in keys5
        Cb[key][i, j] = b[key]
    end
    c = findfirst(==(t), cluster_t)
    c === nothing || ((ncluster[i, c], largest[i, c]) = dark_clusters(σa, kinds_of(i)))
end
F = Dict(key => Cb[key] ./ Nmm for key in keys5)
m(key) = vec(mean(F[key]; dims = 1))
s(key) = vec(std(F[key]; dims = 1))
fmt(x) = string(round(x; digits = 3))
shown = filter(t -> t in (1, 10, 100, 1000, 2000, 4000, 10_000, T_FULL), ts)
Markdown.parse("""
n = $n replicates (`seed = $SEED`, replicas 1:$n), `SequentialCPM(; proposal = Moore(1))`, CPU,
$(Threads.nthreads()) thread(s). Fractions of all mismatched bonds, mean ± SD (selected
times; the plot shows all $(length(ts))):

| paper MCS | heterotypic | dark–dark | light–light | dark–medium | light–medium |
|---|---|---|---|---|---|
""" * join(["| $t | " * join(["$(fmt(m(key)[j])) ± $(fmt(s(key)[j]))" for key in keys5], " | ") * " |"
            for (j, t) in enumerate(ts) if t in shown], "\n"))

# Side by side with the two published runs: PRE Fig. 13(c) (diamonds) and PRL Fig. 2(a)
# (triangles), read from 400-dpi renders (spec §8.5 V-PRE1, §9.0: ±0.005, drawn as bars).
# The grey ranges are the V-PRE1 pass bands: the envelope of the two runs widened by 0.03
# (spec §9.1). No digitised data file exists yet (`reproductions/data/09/paper/` is
# pending).

paper_t = [1, 10, 100, 1000, 10_000]
## PRE Fig. 13(c) and PRL Fig. 2(a), 400-dpi reads (spec §8.5 V-PRE1); NaN: off-scale (> 0.5)
paper_pre = Dict(:dl => [0.43, 0.36, 0.245, 0.136, 0.05], :dd => [0.28, 0.30, 0.39, 0.44, 0.485],
    :ll => [0.23, 0.255, 0.31, 0.36, 0.40])
paper_prl = Dict(:dl => [0.40, 0.333, 0.206, 0.122, 0.04], :dd => [0.33, 0.375, 0.416, 0.489, NaN],
    :ll => [0.22, 0.238, 0.289, 0.328, 0.362])
const READ_ERR = 0.005             # 400-dpi read-off (spec §9.0)
const ENVELOPE_MARGIN = 0.03       # spec §9.1 V-PRE1
const DD_OFFSCALE_HI = 0.55        # spec §9.1: dd at 10⁴ widened to 0.55, the PRL value being off-scale
function envelope(key, j)
    a, b = paper_pre[key][j], paper_prl[key][j]
    isnan(b) && return (a - ENVELOPE_MARGIN, DD_OFFSCALE_HI)
    return (min(a, b) - ENVELOPE_MARGIN, max(a, b) + ENVELOPE_MARGIN)
end
colors = Makie.wong_colors()
names5 = ("heterotypic", "dark–dark", "light–light", "dark–medium", "light–medium")
fig = Figure(size = (820, 440))
ax = Axis(fig[1, 1]; xscale = log10, xlabel = "time (paper MCS)", ylabel = "fraction of boundary")
for (c, key) in zip(1:5, keys5)
    band!(ax, ts, m(key) .- s(key), m(key) .+ s(key); color = (colors[c], 0.25))
    lines!(ax, ts, m(key); color = colors[c])
    haskey(paper_pre, key) || continue
    js = 2:length(paper_t)
    rangebars!(ax, paper_t[js] .* 1.08, first.(envelope.(key, js)), last.(envelope.(key, js));
        color = (:gray, 0.6), whiskerwidth = 6)
    for (vals, marker) in ((paper_pre[key], :diamond), (paper_prl[key], :utriangle))
        ok = .!isnan.(vals)
        errorbars!(ax, paper_t[ok], vals[ok], fill(READ_ERR, count(ok)); color = colors[c])
        scatter!(ax, paper_t[ok], vals[ok]; color = colors[c], marker)
    end
end
Legend(fig[1, 2],
    [[LineElement(; color = colors[c]) for c in 1:5]; MarkerElement(; marker = :diamond, color = :black);
     MarkerElement(; marker = :utriangle, color = :black); LineElement(; color = :gray)],
    [collect("ours, " .* names5); "PRE Fig. 13(c)"; "PRL Fig. 2(a)"; "V-PRE1 pass band"]; framevisible = false)
fig

# Snapshots of replicate 1 (dark kind blue, light kind green, medium black). PRL Fig. 1
# shows small same-type clusters after the first steps, merging clusters by 100 MCS,
# partial sorting with trapped light cells at 1000, and a single rounding dark cluster at
# 4000–10000 (spec §5.1 V-GG5).

snap = FULL ? [1, 100, 1000, 10_000] : [1, 100, 1000]
fig = Figure(size = (300 * length(snap), 320))
sol1 = ens.u[1]
for (c, t) in enumerate(snap)
    ax_t = Axis(fig[1, c]; title = "$t paper MCS", aspect = DataAspect())
    hidedecorations!(ax_t)
    pottsplot!(ax_t, renderframe(sol1; index = findfirst(==(PAPER_MCS * t), sol1.t)); boundaries = true)
end
fig

# ### Contrasting regimes and negative control
#
# Engulfment (default J) against partial sorting (PRE §III E: J(d,l) = 14, J(l,l) = 11,
# T = 5) and against symmetric contacts (NC1), where sorting has no driving force. The
# control is saved at every save up to 10³, for the NC1 clause of V-PRE2.

t_end = 1000
ts_ctrl = filter(<=(t_end), ts)
t_partial = [10, 100, t_end]
last_states(ens) = [ownership(sol.u[end]) for sol in ens.u]
sorted_states = [state_at(sol, t_end) for sol in ens.u]
ens_partial = solve(EnsembleProblem(prob_partial; prob_func = from_start), alg, EnsembleThreads(); trajectories = n,
    saveat = PAPER_MCS .* t_partial)
partial_states = last_states(ens_partial)
prob_sym = remake(prob; p = [:J => [0 16 16; 16 11 11; 16 11 11]])
ens_sym = solve(EnsembleProblem(prob_sym; prob_func = from_start), alg, EnsembleThreads(); trajectories = n,
    saveat = PAPER_MCS .* ts_ctrl)
sym_states = last_states(ens_sym)
regime(states, run) = (count(i -> engulfed(states[i], kinds_of(i), run), eachindex(states)),
    mean(i -> fractions(states[i], kinds_of(i), run)[:dM], eachindex(states)),
    mean(i -> fractions(states[i], kinds_of(i), run)[:dl], eachindex(states)))
rows = [("sorting (PRL defaults)", "engulfment", regime(sorted_states, prob)),
    ("partial sorting (PRE §III E)", "no monolayer", regime(partial_states, prob_partial)),
    ("symmetric contacts (NC1)", "no sorting", regime(sym_states, prob_sym))]
Markdown.parse("""
At $t_end paper MCS, n = $n each:

| Run | Paper outcome | engulfed (of $n) | dark–medium | heterotypic |
|---|---|---|---|---|
""" * join(["| $r | $o | $(e) | $(fmt(dm)) | $(fmt(h)) |" for (r, o, (e, dm, h)) in rows], "\n"))

# ### Variant run: periodic boundaries
#
# The boundary-conditions row of §3 claims that the aggregate does not feel its periodic
# image. The same starts, embedded in the middle of a lattice twice as wide, are run to 10³
# paper MCS and their annealed bond counts compared with the main ensemble (spec §8.5 made
# this check for the 64-cell start). The test is a two-sample t test on each of the 9
# comparisons (3 times × 3 bond counts), Bonferroni-corrected to a family-wise level of 5%:
# every difference of the means must lie within q standard errors, q the two-sided
# t-quantile at 5%/9 with 2n − 2 degrees of freedom. It is class FULL: a verdict in the full
# build, information here. The full run's margin was chosen by a separate check at n = 6
# (spec §9.1, ruling 3).

pf(ok) = ok ? "PASS" : "FAIL"
binding(class) = class == "SMOKE+FULL" || (class == "FULL" && FULL)
result(ok, class) = binding(class) ? pf(ok) : "info: $(ok ? "in band" : "out of band")"
## Student-t CDF for ν degrees of freedom: with x = √ν tan θ the density is ∝ cos^(ν−1) θ;
## integrated by Simpson's rule. The quantile is found by bisection.
function simpson(f, a, b; m = 2000)
    h = (b - a) / m
    return h / 3 * (f(a) + f(b) + sum((isodd(i) ? 4 : 2) * f(a + i * h) for i in 1:(m - 1)))
end
tcdf(x, ν) = 0.5 + 0.5sign(x) * simpson(θ -> cos(θ)^(ν - 1), 0, atan(abs(x) / sqrt(ν))) /
                              simpson(θ -> cos(θ)^(ν - 1), 0, π / 2)
function tquantile(p, ν)
    lo, hi = 0.0, 1000.0
    for _ in 1:200
        mid = (lo + hi) / 2
        tcdf(mid, ν) < p ? (lo = mid) : (hi = mid)
    end
    return (lo + hi) / 2
end

t_pad = [10, 100, t_end]
σp = padded(σ0)
prob_pad = PottsProblem(GranerGlazier(; name = :gg_padded, lattice = size(σp)),
    [ownership => σp, kind => k0], (0, PAPER_MCS * t_end); seed = SEED)
pad_start(q, ctx) = FULL ? remake(q; u0 = [ownership => padded(starts[ctx.sim_id][1]), kind => starts[ctx.sim_id][2]]) : q
ens_pad = solve(EnsembleProblem(prob_pad; prob_func = pad_start), alg, EnsembleThreads(); trajectories = n,
    saveat = PAPER_MCS .* t_pad)
pad_counts = [bond_counts(annealed(state_at(sol, t), kinds_of(i), prob_pad), kinds_of(i))
              for (i, sol) in enumerate(ens_pad.u), t in t_pad]
pad_rows = String[]
pad_oks = Bool[]
n_cmp = length(t_pad) * 3
q_pad = tquantile(1 - 0.05 / (2n_cmp), 2n - 2)
for (j, t) in enumerate(t_pad), key in (:dl, :dM, :total)
    base = key === :total ? Nmm[:, findfirst(==(t), ts)] : Cb[key][:, findfirst(==(t), ts)]
    wide = [key === :total ? sum(values(pad_counts[i, j])) : pad_counts[i, j][key] for i in 1:n]
    Δ, se = mean(wide) - mean(base), sqrt(var(base) / n + var(wide) / n)
    ok = abs(Δ) <= q_pad * se
    push!(pad_oks, ok)
    push!(pad_rows, "| $t | $key | $(fmt(mean(base))) ± $(fmt(std(base))) | $(fmt(mean(wide))) ± $(fmt(std(wide))) | " *
                    "$(fmt(Δ)) | $(fmt(q_pad * se)) | $(ok ? "yes" : "no") |")
end
Markdown.parse("""
Bond counts (mean ± SD, n = $n each), $(join(size(σ0), " × ")) against $dims_pad:

| paper MCS | bonds | $(join(size(σ0), " × ")) | $dims_pad | difference | q SE (q = $(fmt(q_pad))) | within |
|---|---|---|---|---|---|---|
""" * join(pad_rows, "\n") * """


Periodic boundaries harmless for sorting at this size (class FULL): **$(result(all(pad_oks), "FULL"))**.
""")

# ### Pass/fail table
#
# Verdicts are taken at the paper's nominal times: our sampler and the paper's spend the
# same attempts per site per paper MCS (spec §8.5), so there is no time tolerance. To show
# whether a mismatch looks like a uniform change of pace (for example from aggregate size),
# we also report the one global time scale s ∈ [½, 2] that makes the most timed rows pass;
# s never changes a verdict.
#
# The Class column is the verdict class of §9.0. In the reduced build, FULL rows are
# reported as "in band" or "out of band" and carry no verdict. Rows of class "reported"
# never carry one. The one extra row that is not
# in the spec is labelled as such.

## ensemble mean of `key` at paper time τ, linear in log t between saves; `nothing` outside the run
function at(key, τ)
    (τ < first(ts) || τ > last(ts)) && return nothing
    j = searchsortedlast(ts, τ)
    j == length(ts) && return m(key)[j]
    w = (log(τ) - log(ts[j])) / (log(ts[j + 1]) - log(ts[j]))
    return (1 - w) * m(key)[j] + w * m(key)[j + 1]
end
medium(t) = at(:dM, t) + at(:lM, t)                  # our medium share of all boundary
const PAPER_MEDIUM = 0.0268 + 0.0367                 # PRE Fig. 13(b) at t = 1, 400 dpi (spec §8.5 V-PRE3)
## caveat: the paper's t = 1 value; its medium share stays 0.063–0.064 at every time (spec §8.5)
function logfit(y, lo, hi)
    js = findall(t -> lo <= t <= hi, ts)
    x = log10.(ts[js])
    return cor(x, y[js])^2, cov(x, y[js]) / var(x), ts[js[end]]
end
## first saved time at which curve `a` exceeds curve `b`; `nothing` if never
crossing(a, b, times = ts) = (j = findfirst(j -> a[j] > b[j], eachindex(times)); j === nothing ? nothing : times[j])
show_t(t) = t === nothing ? "none by $(last(ts))" : t == first(ts) ? "≤ $t (already at the first save)" : "$t"

## a row: text columns, the class, `ok` at the nominal time (nothing if not run), and
## `timed(s)` (nothing if the row has no time)
targets = []
addrow!(target, paper, ours, tol, class, ok; timed = nothing, info = (;)) =
    push!(targets, (; target, paper, ours, tol, class, ok, timed, info,
        result = ok === nothing ? "pending full run" : result(ok, class)))

## V-PRE1: two-run envelope ± 0.03 at 10, 100, 10³, 10⁴
for (key, name) in ((:dl, "heterotypic"), (:dd, "dark–dark"), (:ll, "light–light")), j in 2:length(paper_t)
    t = paper_t[j]
    lo, hi = envelope(key, j)
    paper = "PRE $(paper_pre[key][j]), PRL $(isnan(paper_prl[key][j]) ? "off-scale (> 0.5)" : paper_prl[key][j])"
    tol = "[$(fmt(lo)), $(fmt(hi))]"
    if t > last(ts)
        addrow!("V-PRE1 $name @ $t", paper, "not run", tol, "FULL", nothing)
        continue
    end
    ok(s) = (x = at(key, s * t); x !== nothing && lo <= x <= hi)
    addrow!("V-PRE1 $name @ $t", paper, "$(fmt(at(key, t))) ± $(fmt(s(key)[findfirst(==(t), ts)]))",
        tol, "FULL", ok(1); timed = ok, info = (; key, t, lo, hi))
end
r2, slope, t_hi = logfit(m(:dl), 5, 4000)
addrow!("V-PRE1 log law, 5–4000", "linear in log₁₀ t; slope ≈ −0.11 (PRE), ≈ −0.105 (PRL) per decade (spec §9.1)",
    "R² = $(fmt(r2)), slope $(fmt(slope))" * (t_hi < 4000 ? " (run ends at $t_hi)" : ""),
    "R² > 0.95, slope in [−0.15, −0.07]", "FULL", r2 > 0.95 && -0.15 <= slope <= -0.07)
r2b, slopeb, _ = logfit(m(:dl), 4, 512)
addrow!("extra (not in spec): log law, 4–512", "`test/papers.jl` window",
    "R² = $(fmt(r2b)), slope $(fmt(slopeb))", "R² > 0.95, slope < 0", "extra", r2b > 0.95 && slopeb < 0)

## V-PRE2: crossing windows; paper crossings from spec §8.5 V-PRE2 (PRE Fig. 13(c), PRL Fig. 2(a))
paper_cross = (pre = (dd = 18, ll = 49), prl = (dd = 5, ll = 38))
c_dd, c_ll = crossing(m(:dd), m(:dl)), crossing(m(:ll), m(:dl))
homo_all = all(m(:dd) .+ m(:ll) .> m(:dl))
addrow!("V-PRE2 summed homotypic > heterotypic at every save",
    "already at t = 1 in both paper runs, so a sanity row that cannot discriminate (spec §9.1)",
    homo_all ? "at every save" : "not at every save", "every save", "FULL", homo_all)
ok_dd(s) = c_dd !== nothing && 2.5s <= c_dd <= 40s
addrow!("V-PRE2 dark–dark crosses heterotypic", "≈ $(paper_cross.pre.dd) (PRE), ≈ $(paper_cross.prl.dd) (PRL)",
    show_t(c_dd), "[2.5, 40]", "FULL", ok_dd(1); timed = ok_dd)
gap = c_dd === nothing || c_ll === nothing ? "" : "; ll/dd crossing ratio $(fmt(c_ll / c_dd))"
ok_ll(s) = c_ll !== nothing && c_dd !== nothing && 19s <= c_ll <= 100s && c_dd < c_ll
addrow!("V-PRE2 light–light crosses heterotypic, after dark–dark",
    "≈ $(paper_cross.pre.ll) (PRE), ≈ $(paper_cross.prl.ll) (PRL)", show_t(c_ll) * gap,
    "[19, 100]; dd first", "FULL", ok_ll(1); timed = ok_ll)
## NC1 clause of V-PRE2: the control's fractions at every save up to 10³
Fsym = Dict(key => [begin
                        b = bond_counts(annealed(state_at(sol, t), kinds_of(i), prob_sym), kinds_of(i))
                        b[key] / sum(values(b))
                    end for (i, sol) in enumerate(ens_sym.u), t in ts_ctrl] for key in (:dl, :dd, :ll))
msym(key) = vec(mean(Fsym[key]; dims = 1))
c_sym = (crossing(msym(:dd), msym(:dl), ts_ctrl), crossing(msym(:ll), msym(:dl), ts_ctrl))
addrow!("V-PRE2 NC1: no crossing by 10³", "— (control)",
    "dd: $(something(c_sym[1], "none")), ll: $(something(c_sym[2], "none"))", "no dd or ll crossing",
    "FULL", all(isnothing, c_sym))

## V-PRE3
c_dM = (j = findfirst(<(0.003), m(:dM)); j === nothing ? nothing : ts[j])
ok_dM(s) = c_dM !== nothing && c_dM <= 1000s
addrow!("V-PRE3 (a) dark–medium < 0.003", "0.0026 at 200 (PRE); 0 by 300 (PRL)", show_t(c_dM), "by 10³",
    "FULL", ok_dM(1); timed = ok_dM)
## size-free form (ruling of 2026-09-30, spec §9.1), reported only: it did not reach its
## calibration bar (20 seeds by the 500 save), so it binds neither build
paper_rel = 0.0026 / 0.0268                           # PRE Fig. 13(b) at 200 and at 1, 400 dpi (spec §8.5)
rel_dM = m(:dM) ./ m(:dM)[1]
c_rel = (j = findfirst(<(0.1), rel_dM); j === nothing ? nothing : ts[j])
ok_rel(s) = c_rel !== nothing && c_rel <= 1000s
addrow!("V-PRE3 (a) size-free: dark–medium below 0.1 × its t = 1 value", "$(fmt(paper_rel)) at 200 (PRE Fig. 13(b))",
    show_t(c_rel), "by 10³", "reported", ok_rel(1); timed = ok_rel)
sym_dM = mean(i -> fractions(sym_states[i], kinds_of(i), prob_sym)[:dM], 1:n)
addrow!("V-PRE3 (a) NC1: dark–medium @ 10³", "— (control)", fmt(sym_dM), "≥ 0.01", "SMOKE+FULL", sym_dM >= 0.01)
## plateau: first save after which light–medium stays within 5% of its last value, and the
## curve is flat over the last decade: its least-squares slope in log₁₀ t, over the saves in
## [t_end / 10, t_end], changes it by at most 5% of its last value per decade
lM_end = m(:lM)[end]
j_plat = findfirst(j -> all(abs.(m(:lM)[j:end] .- lM_end) .<= 0.05lM_end), eachindex(ts))
t_plat = ts[j_plat]
_, lM_slope, _ = logfit(m(:lM), last(ts) / 10, last(ts))
flat = abs(lM_slope) <= 0.05lM_end
ok_plat(s) = t_plat <= 1000s && flat
addrow!("V-PRE3 (b) light–medium plateau reached", "from ≈ 200 (PRE), ≈ 300 (PRL)",
    "$t_plat (within 5% of the value at $(last(ts))); last-decade slope $(fmt(lM_slope)) per decade",
    "before 10³; last-decade slope within ± 5% of the last value ($(fmt(0.05lM_end))) per decade",
    "FULL", ok_plat(1); timed = ok_plat)
## plateau level: size-free ratio R, and the raw value
lM_1000 = at(:lM, 1000)
ratio, paper_ratio = lM_1000 / medium(1), 0.0628 / PAPER_MEDIUM
addrow!("V-PRE3 (c) plateau level, size-free R", "0.0628 / $(round(PAPER_MEDIUM; digits = 4)) = $(fmt(paper_ratio)) (PRE Fig. 13(b)); ≈ 0.99 (PRL)",
    "R = $(fmt(lM_1000)) / $(fmt(medium(1))) = $(fmt(ratio))", "[0.85, 1.10]", "FULL", 0.85 <= ratio <= 1.10)
addrow!("V-PRE3 (d) plateau level, raw @ 10³", "0.0628 (PRE), 0.057 (PRL)", fmt(lM_1000), "[0.050, 0.075]",
    "FULL", 0.050 <= lM_1000 <= 0.075)

## V-PRE4: relative drop of the total length, and flatness after 10³
j100 = findall(t -> 100 <= t <= 1000, ts)
Dmm = [(Nmm[i, 1] - mean(Nmm[i, j100])) / Nmm[i, 1] for i in 1:n]
paper_D = (66_850 - 65_900) / 66_850                  # PRE Fig. 13(a) (spec §9.1 V-PRE4)
addrow!("V-PRE4 total length drop D", "$(fmt(paper_D)) (PRE Fig. 13(a))", "$(fmt(mean(Dmm))) ± $(fmt(std(Dmm)))",
    "[0.005, 0.03]", "FULL", 0.005 <= mean(Dmm) <= 0.03)
_, N_slope, N_hi = logfit(vec(mean(Nmm; dims = 1)), 1000, 10_000)
N_1000 = mean(Nmm[:, findfirst(==(1000), ts)])
addrow!("V-PRE4 total length flat over [10³, 10⁴]", "flat after ≈ 20–100 (PRE Fig. 13(a))",
    "log-slope $(fmt(N_slope)) bonds per decade" * (N_hi < 10_000 ? " (run ends at $N_hi)" : ""),
    "≤ 0.005 N_mm(10³) = $(fmt(0.005N_1000)) per decade", "FULL", abs(N_slope) <= 0.005N_1000)

## V-PRE5: dark clusters on the annealed copy
mc = vec(mean(ncluster; dims = 1))
addrow!("V-PRE5 dark-cluster count non-increasing", "clusters merge (PRE Fig. 12)",
    join(["$(fmt(v)) @ $t" for (t, v) in zip(cluster_t, mc)], ", "), "non-increasing over 10, 100, 10³, 10⁴",
    "FULL", issorted(mc; rev = true))
if 10_000 in cluster_t
    big_share, dM_end = mean(largest[:, end]), at(:dM, 10_000)
    addrow!("V-PRE5 one dark cluster @ 10⁴", "a single dark cluster at 13 500 (PRE Fig. 12(h))",
        "largest $(fmt(big_share)); dark–medium $(fmt(dM_end))", "largest ≥ 0.90; dark–medium < 0.001", "FULL",
        big_share >= 0.90 && dM_end < 0.001)
else
    addrow!("V-PRE5 one dark cluster @ 10⁴", "a single dark cluster at 13 500 (PRE Fig. 12(h))",
        "not run (largest $(fmt(mean(largest[:, end]))) @ $(last(cluster_t)))", "largest ≥ 0.90; dark–medium < 0.001",
        "FULL", nothing)
end

## V-PRE13: partial sorting
part = [fractions(state_at(sol, t), kinds_of(i), prob_partial) for (i, sol) in enumerate(ens_partial.u), t in t_partial]
mpart(key, j) = mean(part[i, j][key] for i in 1:n)
addrow!("V-PRE13 (a) partial sorting: dark–medium @ 10³", "0.019 (PRE Fig. 23(b), dark–medium bullets; replotted in Fig. 24(b))", fmt(mpart(:dM, 3)), "> 0.01",
    "SMOKE+FULL", mpart(:dM, 3) > 0.01)
for (j, (t, v)) in enumerate(zip(t_partial, (0.325, 0.245, 0.17)))   # PRE Fig. 23(a), 300 dpi (spec §9.1)
    addrow!("V-PRE13 (b) partial sorting: heterotypic @ $t", "≈ $v (PRE Fig. 23(a))", fmt(mpart(:dl, j)),
        "± 0.05", "FULL", abs(mpart(:dl, j) - v) <= 0.05)
end

## V-GG6: light cells smaller than dark, raw state at 10³, with the NC1 control
function Δarea(states)
    return [begin
                a, k = cell_areas(σ, kinds_of(i)), kinds_of(i)
                mean(a[c] for c in eachindex(k) if k[c] == 2 && a[c] > 0) -
                mean(a[c] for c in eachindex(k) if k[c] == 1 && a[c] > 0)
            end for (i, σ) in enumerate(states)]
end
Δa, Δa_sym = Δarea(sorted_states), Δarea(sym_states)
se_Δa = std(Δa) / sqrt(n)
addrow!("V-GG6 light cells smaller than dark @ 10³", "\"slightly smaller\" (PRL p.2014)",
    "Δa = $(fmt(mean(Δa))) ± $(fmt(se_Δa)) (SE); NC1 $(fmt(mean(Δa_sym)))",
    "Δa < 0, \\|Δa\\| > 2 SE; \\|NC1\\| < ½ \\|Δa\\|", "SMOKE+FULL",
    mean(Δa) < 0 && abs(mean(Δa)) > 2se_Δa && abs(mean(Δa_sym)) < abs(mean(Δa)) / 2)

## NC1: symmetric contacts do not sort
## the heterotypic clause is size-free: the heterotypic share of cell–cell bonds only, which
## random mixing puts near ½ at any aggregate size (spec §9.1 NC1)
sym_f = [fractions(sym_states[i], kinds_of(i), prob_sym) for i in 1:n]
sym_share = mean(f[:dl] / (1 - f[:dM] - f[:lM]) for f in sym_f)
sym_dl = mean(f[:dl] for f in sym_f)
sym_eng = count(i -> engulfed(sym_states[i], kinds_of(i), prob_sym), 1:n)
addrow!("NC1 symmetric contacts @ 10³", "— (control; random mixing gives a cell–cell heterotypic share ≈ ½, spec §9.1)",
    "cell–cell heterotypic share $(fmt(sym_share)); dark–medium $(fmt(sym_dM)); engulfed $sym_eng of $n",
    "share ≥ 0.40; dark–medium ≥ 0.01; 0 engulfed", "SMOKE+FULL",
    sym_share >= 0.40 && sym_dM >= 0.01 && sym_eng == 0)
addrow!("NC1 raw heterotypic @ 10³ (the old clause)", "— (assumed the paper-size medium share)", fmt(sym_dl), "≥ 0.35",
    "reported", sym_dl >= 0.35)

## informational: one global time scale for all timed rows
timed_rows = filter(r -> r.timed !== nothing, targets)
npass(s) = count(r -> r.timed(s), timed_rows)
scales = 2.0 .^ range(-1, 1; length = 41)
best = argmax(s -> (npass(s), -abs(log(s))), scales)
at_s(r) = r.timed === nothing ? "—" : pf(r.timed(best))

heading = FULL ? "Validation (n = $n)" :
          "**Smoke check (reduced, n = $n) — not validation.** Only the SMOKE+FULL rows carry a verdict here; the validation result is the pending full run."
Markdown.parse("""
$heading

| Target | Paper | Ours (mean ± SD, n = $n) | Tolerance | Class | Result (nominal time) | at s = $(fmt(best)) (informational) |
|---|---|---|---|---|---|---|
""" * join(["| $(r.target) | $(r.paper) | $(r.ours) | $(r.tol) | $(r.class) | $(r.result) | $(at_s(r)) |" for r in targets],
               "\n") * """


Informational only, not a tolerance (spec §8.5). The single time scale
s = $(fmt(best)) ∈ [½, 2], applied to all $(length(timed_rows)) timed rows at once, makes
$(npass(best)) of them pass; $(npass(1.0)) pass at s = 1.
""")

# V-PRE4 depends on the start: an unrelaxed Voronoi start may shed more boundary in its
# first MCS than the paper's relaxed one did (spec §9.1 V-PRE4 note). The full build
# measures D from relaxed copies of its first starts: each is relaxed as one type for 400
# paper MCS with the PRE §II D3 energies (`data/graner/generate.jl`) and then sorted with
# its own kinds.

if FULL
    relax_ids = 1:min(3, n)
    D_relaxed = map(relax_ids) do i
        σi, ki = starts[i]
        relax = remake(prob; u0 = [ownership => σi, kind => fill(2, length(ki))], tspan = (0, 400PAPER_MCS),
            p = [:J => [0 8 8; 8 2 2; 8 2 2], :T => 5.0])
        σr = ownership(solve(relax, alg; saveat = 400PAPER_MCS).u[end])
        run = remake(prob; u0 = [ownership => σr, kind => ki], tspan = (0, PAPER_MCS * 1000))
        sol = solve(run, alg; saveat = PAPER_MCS .* ts[1:findfirst(==(1000), ts)])
        N = [sum(values(bond_counts(annealed(state_at(sol, t), ki, prob), ki))) for t in ts if t <= 1000]
        (N[1] - mean(N[j100])) / N[1]
    end
    Markdown.parse("V-PRE4 start check, replicates $(relax_ids): D = $(fmt(mean(Dmm[relax_ids]))) from the Voronoi " *
                   "starts against $(fmt(mean(D_relaxed))) from their relaxed copies.")
else
    Markdown.parse("The start check runs in the full build; the reduced build's start is already relaxed. " *
                   "The pre-freeze check (1000 cells, 6 seeds, Voronoi against relaxed starts) found no start " *
                   "effect on D; its values are recorded in spec §9.1 V-PRE4.")
end

# Diagnosis of the rows that fail or fall out of band, generated from the table:

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
in_band(r, x) = r.info.lo <= x <= r.info.hi #hide
failing = filter(r -> r.ok === false, targets) #hide
diag_lines = String[] #hide
for r in failing #hide
    if haskey(r.info, :key) #hide
        x = corrected(r) #hide
        push!(diag_lines, "$(r.target): rescaled from our medium share ($(fmt(medium(r.info.t)))) to the " * #hide
            "paper's ($(fmt(PAPER_MEDIUM))), $(fmt(at(r.info.key, r.info.t))) becomes $(fmt(x)) against " * #hide
            "the band [$(fmt(r.info.lo)), $(fmt(r.info.hi))], $(in_band(r, x) ? "which is inside it: consistent with the larger medium share of our small aggregate" : #hide
                                  "which is still outside it")." #hide
        ) #hide
    end #hide
end #hide
any(r -> haskey(r.info, :key), failing) && #hide
    push!(diag_lines, "Caveat: the paper's medium share ($(fmt(PAPER_MEDIUM))) is its t = 1 value (0.0268 dark + 0.0367 light, " * #hide
        "PRE Fig. 13(b)); the paper's medium share stays at 0.063–0.064 at every time shown (t = 1…1000), so one " * #hide
        "value serves all times. Read-off uncertainty ≈ ±0.001 per medium fraction (spec §9.0).") #hide
if any(r -> startswith(r.target, "V-PRE1 light–light"), failing) #hide
    push!(diag_lines, "Light–light: at 10³, $(round(Int, 100mean(i -> light_on_surface(sorted_states[i], kinds_of(i)), eachindex(sorted_states))))% " * #hide
        "of light cells touch the medium. In a $ncells-cell aggregate nearly every light cell sits in the " * #hide
        "outer monolayer, so light–light bonds are scarce. The medium-share rescaling leaves " * #hide
        "$(count(r -> startswith(r.target, "V-PRE1 light–light") && haskey(r.info, :key) && #hide
                      !in_band(r, corrected(r)), failing)) of the out-of-band light–light rows outside their band; " * #hide
        "a larger aggregate is needed to test them.") #hide
end #hide
any(r -> startswith(r.target, "V-PRE2 light–light"), failing) && gap != "" && #hide
    push!(diag_lines, "Crossings: shape, not only timing. Our dark–dark and light–light crossings are " * #hide
        "$(fmt(c_ll / c_dd))× apart in time; the paper's are ≈ $(fmt(paper_cross.pre.ll / paper_cross.pre.dd))× (PRE) " * #hide
        "and ≈ $(fmt(paper_cross.prl.ll / paper_cross.prl.dd))× (PRL) apart.") #hide
any(r -> startswith(r.target, "V-PRE1 log law"), failing) && #hide
    push!(diag_lines, "Log law: the 5–4000 fit spans the plateau our small aggregate reaches; compare the extra 4–512 row.") #hide
any(r -> startswith(r.target, "V-PRE3 (d)"), failing) && #hide
    push!(diag_lines, "Plateau level: the raw value is set by aggregate size (perimeter/area); see the size-free ratio R, row (c).") #hide
Markdown.parse(isempty(failing) ? "No row fails or falls out of band in this run." : #hide
               "Rows that fail or fall out of band: $(join([r.target for r in failing], "; ")).\n\n" * #hide
               join(["- " * l for l in diag_lines], "\n")) #hide

# ## 6. Known limitations and open questions for the authors
#
# Questions for J.A. Glazier and F. Graner (spec §8.4, §9; model-specs README §5):
#
# - Are PRL Fig. 2 and PRE Fig. 13 two different runs of the sorting parameter set, and if
#   so, how do they differ (start, seed, protocol)? They disagree by more than a
#   1000-cell run-to-run spread would explain (spec §9.2). The answer decides whether the
#   V-PRE1 and V-PRE2 bands stay the two-run envelope or narrow to one run, and replaces
#   the "two published runs" row of §3.
# - The lattice size of the PRE runs. With the boundary conditions it fixes the medium gap
#   around the aggregate, which matters for runs in which cells detach. The answer
#   replaces the lattice entry of the aggregate-size row.
# - The boundary conditions. The answer replaces the boundary-conditions row.
# - The dark/light fraction and how it was drawn. The answer replaces the type-fraction
#   row and the initial-state generator.
# - The rule that makes two cells neighbours when counting n (Tables I–III). The answer
#   unparks V-PRE6, V-PRE17 and the ⟨n⟩ parts of V-PRE10 and V-PRE16.
# - The definition of the "type-type correlation" plotted in PRE Figs. 13(d) and 21(b).
#   The answer adds it to the validation table.
# - How the total boundary length of PRE Fig. 13(a) is counted (bond pairs once or twice,
#   which neighbour range). Our count of the paper-size aggregate is below the paper's by a
#   factor that is not 2 (spec §9.1 V-PRE4). The V-PRE4 drop D is a ratio and does not
#   depend on it; the answer lets the page compare absolute lengths.
#
# We would welcome corrections, the original input files, or a joint check of these
# results. Contact: the PottsModels maintainer. Answers are recorded as a new row in the
# deviations table and a dated changelog entry below.
#
# ## 7. How to cite
#
# Cite Graner & Glazier (1992) and Glazier & Graner (1993) first, then PottsModels at the
# version and commit of this build:

build_commit = git("rev-parse", "--short", "HEAD")
build_dirty = !isempty(git("status", "--porcelain"))
Markdown.parse("PottsModels $(pkgversion(PottsModels)), commit " *
               (isempty(build_commit) ? "(git unavailable)" : "`$build_commit`") *
               (build_dirty ? " with uncommitted changes" : "") * ".")

# This is an independent reimplementation; it has not been reviewed or endorsed by the
# authors.
#
# | Date | Change | Reason |
# |---|---|---|
# | 2026-09-30 | First version (pilot tutorial, reduced run) | ROADMAP P6.0h |
# | 2026-09-30 | The full run uses a 1000-cell aggregate (`graner_glazier_aggregate`) | ROADMAP P6.1b2; D-063 |
# | 2026-09-30 | Targets revised before freezing: nominal-time verdicts, two-run envelope, size-free plateau ratio | spec 09 §9 |
