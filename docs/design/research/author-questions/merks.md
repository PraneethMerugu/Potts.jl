# Questions for Roeland Merks: Merks et al. 2006 (Dev Biol) and 2008 (PLoS Comput Biol)

Batch 1 — **draft, not sent.** The maintainer sends this personally. Citations point to
`docs/design/research/model-specs/01_merks.md` ("spec 01 §x") and the specs README
("specs README §4 M<n>").

---

Dear Prof. Merks,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing your vasculogenesis models (Dev Biol 289:44, 2006, and PLoS
Comput Biol 4:e1000163, 2008) with full provenance: every equation and parameter is traced to a
page, figure or code line, and every choice we make is listed in a public tutorial.

Thanks to Dataset S1 and the Tissue Simulation Toolkit 0.1.3 released with the 2008 paper, the
2008 model is almost fully determined. The 2006 model is not, because its supplementary methods
are not available to us. Questions 1–2 block an exact reproduction; 3–5 are quick. We would
like to reach a perfect reproduction together with you, and we would welcome any corrections.

With thanks,
[Maintainer name]

---

## Blocking questions

### Q1 [B] 2006: target length, connectivity penalty and the Fig 4 set-up

- **Context.** The 2006 text gives a target length of "about 100 µm" (01a p.50), i.e. 50 px at
  2 µm/px, but every TST file labelled "Cf. Fig. 4 of Merks et al. 2006" uses L = 60 px
  (`longcells.par:8`) (spec 01 §7.9 D-12). The connectivity penalty is "E0 > 2000" (01a p.49);
  the files use 2000 (`default.par`) or 5000 (`longcells.par`) (D-13). The published Fig 4 run
  has 282 cells in 333² of a 500² lattice (01a p.50), while the 2006-labelled files are a
  100-cell, 200² demo (D-16).
- **Question.** Could you share the 2006 supplementary methods, or tell us (a) L, (b) E₀, and
  (c) the lattice, cell count and seeding used for Fig 4?
- **Our assumption.** L = 50 px (paper text) with L = 60 as a variant; soft E₀ = 5000 (from the
  file labelled for Fig 4); the paper's 282-cell geometry (specs README §4 M2, M3; spec 01 §2.9).
- **What changes.** The 2006 defaults. Cell length and the connectivity penalty drive network
  formation and the lacuna statistics we validate against.

### Q2 [B] 2008: are the 100 relaxation MCS counted?

- **Context.** Every Dataset S1 file runs 100 MCS with no secretion or diffusion before the main
  run (`vessel.cpp:86`); the paper does not mention it (spec 01 §7.9 D-5, §8 A-19).
- **Question.** Do the MCS counts in the 2008 figures (for example 10,000 MCS in Figs 2, 4, 5)
  include those 100 MCS?
- **Our assumption.** We include the relaxation and report time both from code MCS 0 and from
  the end of relaxation (specs README §4 M6).
- **What changes.** The time axis of every 2008 comparison.

## Quick questions (non-blocking)

**Q3. Analysis code.** Could you share the scripts behind the compactness plots and the Fig 13
"H − H₀" curve? The released `Compactness()` uses all cell sites and the convex hull of pixel
centres, but it is never called in `vessel.cpp`, and the release accumulates accepted ΔH
including the chemotaxis term (spec 01 §7.9 D-17, D-18; §8 A-14). Is there a morphometry code
(`overview.dat` lists `morphometry.cpp`, which is not in the release; A-18)? *Meanwhile we use
the released `Compactness()` and state our H − H₀ bookkeeping explicitly.*

**Q4. Missing parameter files.** Dataset S1's 12 files share one parameter set (128 cells on
200²) and differ only in T, extension-only, the CI switch and the initial condition (spec 01
§7.1). Could you share the files for the parameter sweeps of Figs 3, 5 and 7–10, the 1024-cell
Fig 10 runs, the 256-cell Figs 12–13 runs on 500², and the code for the continuous
χ(c,c)/χ(c,M) sweep of Fig 5? TST 0.1.3 only supports χ(c,c) ∈ {0, χ(c,M)} (spec 01 §7.9 D-2,
D-3; §8 A-20). *We expose χ(c,c)
as a real parameter, a superset of the released code.*

**Q5. Lattice sizes.** (a) The enclosing lattice of 2008 Fig 2 is garbled in the PDF
("1,00 µm × 1,00 µm"; A-9). Is it 500 × 500? (b) What lattices were used for Figs 10 and 12
(A-10)? *We assume 500 × 500 for Fig 2 (specs README §4 M10).*

## Tutorial to share once public

`lib/PottsModels/reproductions/01_merks.jl` (planned, build step 3, following
TUTORIAL_TEMPLATE), with separate 2006 and 2008 parameter sets. Each answer becomes a dated
changelog entry and a row of its deviations table.
