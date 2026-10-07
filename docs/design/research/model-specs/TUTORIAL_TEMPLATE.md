# Template: "Reproducing ⟨paper⟩" tutorials

Every published model in `lib/PottsModels` ships one reproduction tutorial. The tutorials
are meant to be shown to the original authors, so they are built around three things:
provenance, an honest account of every deviation, and side-by-side validation. The user
wants each one to be an invitation to reach a perfect reproduction together.

## Where the files live and how they render

- **Source.** A Literate.jl script at `lib/PottsModels/reproductions/<nn>_<model>.jl`.
  - `<nn>` is the spec number in `docs/design/research/model-specs/` (for example
    `09_cell_sorting.jl`).
  - Prose lines start with `# `. Code is plain Julia.
  - `#md`, `#nb` and `#src` line filters are allowed.
- **Rendering.** Documenter renders each script into the **"Published models"** section of
  the docs site (ROADMAP M5.2).
- **Build size.** The docs build runs a reduced ensemble. Each tutorial reads its size from
  one line: `const FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true"`.
  - The full-size ensemble produces the published validation table and figures.
  - Its outputs (CSV + PNG) are committed under
    `lib/PottsModels/reproductions/data/<nn>/` with the git commit, date and hardware that
    produced them.
  - The docs build compares against these committed numbers. It never presents a reduced
    run as the validation result.
- **Build gate.** Every number in the prose is computed or loaded in the script. Nothing is
  typed by hand except values quoted from the paper, and each of those carries a citation.
- **Spec link.** The spec is the evidence base, and the tutorial is its public face. Every
  claim about the paper cites the paper (page, equation, figure, table). Every claim about
  released code cites `file:line` at a pinned commit.

## API rules for the code cells

- **Public API only** (ROADMAP rules). The tutorial builds everything from the published
  constructor and ordinary SciML calls:
  - `Model(; params…)`, `model_state(...)` and `model_observables(sol)`;
  - `PottsProblem`, `solve`, `remake`, `EnsembleProblem`.
- The tutorial never calls internals, and the model never gets a hook named after it
  (AUDIT P-15).
- If a step needs a capability that does not exist yet, show the planned syntax in a block
  tagged `# planned:` and do not execute it. Link the feature id (README §2) and say what
  the tutorial does instead. Syntax must follow `docs/design/AUTHORING.md`.
- **Composability.** At least one cell shows the model built by `@extend`, or changed by
  `remake` or keyword overrides, to switch a variant on. This shows that variants are
  ordinary model code, not flags hidden in the engine.

---

## Required sections

### 1. Paper and sources

- Full citation(s) with DOI(s).
- The exact PDFs used, by filename in `docs/references/`. Record the version (for example
  "arXiv v1, not the version of record") and the erratum status.
- Released code: repository URL, **commit hash**, and the local path under
  `docs/references/codebases/`. Also the supplementary files used.
- The spec file and its sections.
- A **reproducibility grade** (A/B/C, README §1) with a one-line reason.
- One paragraph: what the paper claims and which results this tutorial reproduces.

### 2. The model, term by term

- Each term of H, each drive, field equation, lifecycle rule and component appears as a
  **pair**:
  - the source equation, quoted with its citation (for example "Eq. (2), p.2014");
  - the `@potts_model` statement that implements it.
- Terms taken from released code rather than the paper carry `file:line`.
- A **parameter table** with the columns: symbol | value | units | meaning | source
  (per-row citation) | stated / derived / code-only / calibrated.
  - A calibrated value names its calibration target and procedure.
  - A value from an external, not-on-disk source says so.
- A units paragraph: lattice spacing, time per MCS, and the attempts-per-MCS convention
  (1 MCS = N attempts; INTERNALS F8).

### 3. Deviations table

Every failed, parked or provisional target is listed (D-154), and so is every difference
from the paper or the released code, including those the maintainer approved (README §4).
The table has four columns after the row label (D-154):

| Item | Ours | Paper | Suspected cause | Author question |
|---|---|---|---|---|

Rules:
- **Ours** is our value or default, with the variant keyword that switches to the
  alternative. A value about our runs is computed on the page or loaded from the committed
  full-run record (`reproductions/data/<nn>/`).
- **Paper** is the paper's value with its citation. Where the released code or files
  differ, give their value too ("files: …"). "—" means the source is silent.
- **Suspected cause** says why we differ: a convention, a provisional default (D-155), an
  unstated value, a paper-internal conflict, or, for a failed target, the candidate causes
  tested and excluded.
- **Author question** is one of: "not an author question"; "not asked (on our open question
  list, README §5)" with the item number; "asked on ⟨date⟩"; "answered → ⟨D-entry⟩". Pages
  are public: they cite README §5 and the page's §6, never the internal PI sheet (Dr Jiang
  sends the letters, D-155).
- Failed targets come first. The main text of the paper names only the rows that matter.
- Performance-over-exactness choices (D-029) are rows too, for example Float vs integer ΔH
  or checkerboard vs sequential. Each one names the statistical test that shows it is
  harmless.
- Paper-internal inconsistencies are rows, with the reading we chose.

### 4. Build and run: public API only

- Load, build, seed, solve. Show the variant switch (`remake`, keyword or `@extend`).
- Show one snapshot plot (MakiePotts) next to the paper's snapshot description. Cells are
  never drawn with outlines: no `boundaries = true` and no `pottsboundaries` overlay in
  plots, videos or figures (D-156). Runs are shown as videos.
- State the cost: wall time for one replicate at paper size. Every timing names the machine
  (CPU or GPU model) and the backend (CPU or device, solver, thread count) that produced it.

### 5. Validation

- **Pre-registered tolerances.**
  - Copy the target table from the spec's validation section: target | source (figure,
    table, CSV) | type | acceptance.
  - Commit it **before** the first full run. The commit hash of the table is printed in
    the tutorial.
  - A tolerance may be changed later only as a new row that gives the reason. The original
    row stays.
- **Ensemble.**
  - State n (at least the paper's replicate count), the seeds (`seed = 1:n`), the solver,
    and the backend.
  - Use `solve(EnsembleProblem(prob; prob_func), alg, EnsembleThreads(); trajectories = n)`.
- **Pass/fail table:** target | paper value | our mean ± SD (n) | tolerance | PASS/FAIL.
  FAIL rows stay visible with a short diagnosis.
- **Side-by-side plots.**
  - The paper's digitised curve (with a digitisation-uncertainty band) against the
    ensemble mean ± SD, on the paper's axes and units.
  - Digitised data files live in `reproductions/data/<nn>/paper/` with the figure, the
    method (for example "by eye from 300 dpi render") and the uncertainty.
- **Negative controls** (D-048): switching the paper's mechanism off must remove the
  effect.
- **Variant runs** for each deviation whose harmlessness is claimed in §3.

### 6. Known limitations and open questions for the authors

- The model's question list from README §5, blocking questions first. Each question says
  what changes in the tutorial once it is answered.
- An explicit invitation: "We would welcome corrections, the original input files, or a
  joint check of these results."
- A contact line (maintainer) and how the authors' answers will be recorded: a new
  deviations-table row and a dated changelog entry.

### 7. How to cite

- Cite the original paper(s) first, then this package (CITATION entry, version and
  commit).
- Say plainly that this is an independent reimplementation. Unless the authors have
  reviewed it, it is **not** endorsed by them.
- Changelog: date | change | reason (for example an author answer).

---

## Example skeleton: `09_cell_sorting.jl`

This is a prose skeleton only. Every result is a placeholder (`⟨…⟩`). Nothing here is a
real run. Syntax is the current public surface. `# planned:` blocks are not executed.

```julia
# # Reproducing Graner & Glazier (1992): cell sorting by differential adhesion
#
# ## 1. Paper and sources
#
# - F. Graner, J.A. Glazier, "Simulation of Biological Cell Sorting Using a Two-Dimensional
#   Extended Potts Model", Phys. Rev. Lett. 69, 2013 (1992). doi:10.1103/PhysRevLett.69.2013.
#   PDF: `docs/references/09a_GranerGlazier1992_PRL_cell-sorting.pdf`.
# - Spec: `docs/design/research/model-specs/09_cell_sorting.md`. (The Osborne et al. 2017
#   rows of the spec are retired: cell sorting is Graner–Glazier only, D-156.)
# - Grade: B (energies stated; set-up in PRE 47, 2128 (1993)).
#
# ## 2. The model, term by term
#
# Graner–Glazier Eq. (2), p.2014:
#   H = Σ J(τ,τ′)(1 − δ) + λ Σ (a − A_τ)² θ(A_τ)
# is, in the published constructor,

using Potts, PottsModels
@named gg = GranerGlazier()        # energies: `cells(dark, light) => λ*(volume - V₀)^2`,
                                   #           `contacts => J[kind, kind′]`
                                   # proposal: `@relations proposal = Moore(1)` (D-049 F-1)

# Parameter table: J(d,d) = 2, J(d,l) = 11, J(l,l) = 14, J(·,M) = 16 (p.2015); λ = 1, T = 10
# (p.2014); A = 40 (p.2015, "(A=40)", read as the target: spec A-GG1). One paper MCS = 16
# of ours (p.2014).
#
# ## 3. Deviations
#
# | Item | Ours | Paper | Suspected cause | Author question |
# |---|---|---|---|---|
# | ⟨failed target⟩ (**FAIL**) | ⟨mean ± SE, n⟩ | ⟨value, figure⟩ | ⟨candidates tested and excluded⟩ | not asked (on our open question list, README §5 ⟨item⟩) |
# | Initial state | PRE 1993 §II D3 recipe | "square aggregate … (A=40)", 400 MCS relax (p.2015) | — | not an author question |
# | T = 0 annealing | measured on a copy | "two T=0 annealing steps" | none: matches PRE p.2134 (spec A-GG4) | not an author question |
# | ⟨…⟩ | | | | |
#
# ## 4. Build and run

σ0, kinds = graner_glazier_state()
prob = PottsProblem(gg, [ownership => σ0, kind => kinds], (0, 16 * 10_000); seed = 1)
t = @elapsed sol = solve(prob, SequentialCPM())
# "⟨t⟩ s on ⟨CPU model⟩, CPU backend, one thread" (every timing names machine and backend)
record_potts("09_replicate1.mp4", sol)       # no `boundaries = true` (D-156)

# A variant is ordinary model code: symmetric contacts as the negative control.
prob_ctrl = remake(prob; p = [:J => [0 16 16; 16 11 11; 16 11 11]])

# ## 5. Validation
#
# Pre-registered targets (committed in ⟨hash⟩ before the first full run): V-GG1 … V-GG6 and
# V-PRE1 … V-PRE17 from spec §9.

n = FULL ? 10 : 2
ens = solve(EnsembleProblem(prob), SequentialCPM(), EnsembleThreads(); trajectories = n)
# planned: graner_glazier_observables(ens) -> boundary-length fractions after 2 T=0 steps (G12)

# | Target | Paper | Ours (mean ± SD, n) | Tolerance | Result |
# |---|---|---|---|---|
# | V-GG1 heterotypic fraction @ 10³ paper MCS | ≈ 0.12 (Fig. 2a, digitised ± 0.03) | ⟨…⟩ | ± 0.05 | ⟨…⟩ |
#
# Side-by-side: Fig. 2(a) digitised (with band) vs ensemble mean ± SD, log time axis.
#
# ## 6. Open questions for the authors
#
# - (Glazier) PRE 1993 set-up: lattice size, boundary conditions, type fraction (spec
#   A-GG5). The answer replaces the boundary-conditions and type-fraction rows of §3.
# We would welcome corrections, the original input files, or a joint check of these results.
#
# ## 7. How to cite
#
# Cite Graner & Glazier (1992) and Glazier & Graner (1993), then PottsModels ⟨version, commit⟩.
# This is an independent reimplementation, not reviewed by the authors.
```
