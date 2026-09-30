# Questions for Roeland Merks: Merks et al. 2006 (Dev Biol) and 2008 (PLoS Comput Biol)

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file. **Q1 is on HOLD** only for the 2006
"Supplementary methods" file, which could not be located by script (see the pre-send checklist in
README.md). If the maintainer finds it on ScienceDirect and it settles L, E₀ or the seeding,
narrow Q1 and revise the intro sentence again. Q2 is no longer on HOLD.

---

Dear Prof. Merks,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing your vasculogenesis models (Dev Biol 289 (2006) 44 and PLoS
Comput Biol 4 (2008) e1000163) with full provenance: every equation and parameter is traced to
a page, figure or code line, and every choice we make will be listed in a tutorial that we will
publish and share with you.

Thanks to Dataset S1 and the Tissue Simulation Toolkit 0.1.3 released with the 2008 paper, the
2008 model is almost fully determined. The 2006 model is less so: the paper, its supplementary
movie and your Tissue Simulation Toolkit chapter (Methods Mol Biol 1214, 2015) leave the target
length, the connectivity penalty and the initial set-up open, and we could not find the 2006
supplementary methods online. Questions 1–2 block an exact reproduction; 3–5 are quick. We would
like to reach a perfect reproduction together with you, and we would welcome any corrections.

## Blocking questions

### Q1 [B] [HOLD] 2006: target length, connectivity penalty and the Fig 4 set-up

- **Context.** The 2006 text gives a target length of "about 100 µm" (p.50), i.e. 50 px at
  2 µm per pixel, but every TST file labelled "Cf. Fig. 4 of Merks et al. 2006" uses L = 60 px
  (`longcells.par:8`), and the 2015 chapter suggests starting from `target_length = 60`
  ("L = 120 µm"). The connectivity penalty is "E0 > 2000" (p.49); the files use 2000
  (`default.par`) or 5000 (`longcells.par`). The Fig 4 caption (p.48) describes 282 cells in a
  333 × 333 area within a 500 × 500 lattice, while the 2006-labelled files are a 100-cell,
  200 × 200 demonstration. The first frame of the supplementary movie already shows compact
  multi-pixel cells, so we cannot tell how they were made.
- **Question.** Could you share the 2006 supplementary methods, or tell us (a) L, (b) E₀, and
  (c) how the 282 cells were seeded (single pixels grown by Eden growth, as `GrowInCells` does,
  or blobs placed at the target area), and whether any relaxation ran before the first frame?
- **Our assumption.** L = 50 px (the paper text), with L = 60 as a variant; E₀ = 5000 as a soft
  penalty (from the file labelled for Fig 4); the paper's 282-cell geometry.
- **What changes.** The 2006 defaults. Cell length and the connectivity penalty drive network
  formation and the lacuna statistics we compare against.

### Q2 [B] 2008: are the 100 relaxation MCS counted?

- **Context.** Every Dataset S1 file runs 100 MCS with no secretion or diffusion before the main
  run (`relaxation = 100`; `vessel.cpp:86`). The paper does not mention it.
- **Question.** Do the MCS counts in the 2008 figures (for example 10,000 MCS in Figs 2, 4 and
  5) include those 100 MCS?
- **Our assumption.** We include the relaxation and report time both from MCS 0 of the code and
  from the end of relaxation.
- **What changes.** The time axis of every 2008 comparison.

## Quick questions (non-blocking)

**Q3. Analysis code.** Could you share the scripts behind the compactness plots and the Fig 13
"H − H₀" curve? The released `Compactness()` uses all cell sites and the convex hull of pixel
centres, but `vessel.cpp` never calls it, and the release accumulates accepted ΔH including the
chemotaxis term. Is there a morphometry code? `overview.dat` lists `morphometry.cpp`, which is
not in the release. *Meanwhile we use the released `Compactness()` and state our H − H₀
bookkeeping explicitly.*

**Q4. Missing parameter files.** Dataset S1's 12 files share one parameter set on 200 × 200
(sprout files: 128 cells; de novo files: 360 seeds) and differ only in T, extension-only, the
VE-cadherin switch and the initial condition. Could you share the files for the parameter
sweeps of Figs 3, 5 and 7–10, the 1024-cell Fig 10 runs, the 256-cell Figs 12–13 runs on
500 × 500, and the code for the continuous χ(c,c)/χ(c,M) sweep of Fig 5? TST 0.1.3 only
supports χ(c,c) ∈ {0, χ(c,M)}. *We expose χ(c,c) as a real parameter, a superset of the
released code.*

**Q5. Enclosing lattice of Fig 2.** The size of the lattice enclosing the 2008 Fig 2 seed region
is printed as "1,00 µm × 1,00 µm" (p.4, also in the online version). Is it 1,000 µm, i.e.
500 × 500 px, as for Fig 12? *We assume 500 × 500.*

Once the reproduction is published, we will send you the tutorial, with separate 2006 and 2008
parameter sets. Each of your answers will be recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 01 §1 (01a-mov, 01a-PMC, 01c), §2.9, §7.6, §7.8, §7.9 D-12, D-13, D-16, §8 A-1, A-3, A-15; specs README §4 M2, M3; README §5 Merks item 1. Checked 2026-09-30: PMC manuscript (same text), supplementary movie (first frame), TST chapter 01c pp.11, 12, 14 (L = 60 ↔ 120 µm; GrowInCells; relaxation option); none settles L, E₀ or the 2006 seeding. HOLD remains only for the 2006 "Supplementary methods" file (not served by the publisher CDN; ScienceDirect page 403 to scripts)
Q2: spec 01 §7.1 (relaxation :40), §7.9 D-5, §8 A-19; specs README §4 M6; README §5 Merks item 2. HOLD lifted 2026-09-30: 01c pp.12, 15–16 describe relaxation but not the 01b time axis; the 2006 supplementary is not relevant to 2008
Q3: spec 01 §7.9 D-17, D-18, §8 A-14, A-18; README §5 Merks item 3
Q4: spec 01 §3.3, §7.1, §7.9 D-2, D-3, §8 A-20; README §5 Merks item 4
Q5: spec 01 §2.9, §8 A-9; specs README §4 M10; README §5 Merks item 5 (Fig 12 dropped in review round 1; former Q5(b) on the Fig 10 1024-cell lattice dropped in review round 2, answered by 01b p.9, see spec 01 §3.3 row 10 and §8 A-10)
Tutorial (planned): 01_merks.jl, step 3
-->
