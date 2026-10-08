# [Models](@id models)

Each page in this section builds one published cellular Potts model from scratch, as a
tutorial, and ends with the constructor that PottsModels ships for it.

**What you will learn**

- how a published model becomes a `@potts_model`, one section at a time: the lattice and
  cell kinds, each energy term, drives, field equations, constraints, growth and division
  rules, and the sweep;
- which equation of the paper each line implements;
- how to build a starting state with layouts, solve, record the run as a movie and
  measure what the model is about;
- where each model differs from its paper, and why.

## How each page is organised

1. **The paper run.** A video of the finished model run at the paper's size, with the
   paper's starting state, parameters and run length, computed outside the docs build.
   Its caption gives the lattice, run length and seed.
2. **Construction tutorial.** The model is written section by section, each explained
   against the paper's equations, and then assembled into one `@potts_model`. The page
   runs it at a size that takes seconds: starting state, solve, a movie of the run, one
   measurement.
3. **Differences from the paper.** A short table of everything that differs from the
   paper (and, where the paper's text and the authors' code disagree, which one the
   model follows). Everything not listed is the paper's.
4. **Constructor docs.** The finished model is the one PottsModels exports. The page
   closes with "This model ships as `X`" and the docstrings of the constructor and its
   state or layout helpers. The test suite checks that the tutorial's model compiles to
   the same code, with the same defaults, as the shipped constructor, so the two cannot
   drift apart.
5. **Paper run.** Each page shows a video of the shipped constructor run at the paper's
   size and length. Full reproduction pages, which compare the model with the paper's
   figures, are in preparation.

## The models

| Page | Constructor | What it shows | New ingredients |
|:-----|:------------|:--------------|:----------------|
| [Cell sorting](@ref model-graner-glazier) | `GranerGlazier` | differential adhesion sorts two cell kinds (Graner & Glazier 1992) | lattice, kinds, area and contact energies, Metropolis sweep |
| [Vasculogenesis](@ref model-merks) | `MerksVasculogenesis`; the papers' parameter sets `Merks2006`, `Merks2008` | elongated cells following their own chemoattractant form vascular networks (Merks et al. 2006); contact-inhibited chemotaxis makes networks and sprouts (Merks et al. 2008) | a diffusing field and its equation, a chemotaxis drive, a shape energy, connectivity |
| [Leader–follower invasion](@ref model-akeeb) | `AkeebInvasion` | leader cells climbing a cue pull a proliferating tumour slab into fingers (Akeeb, Marcus & Jiang 2026) | per-cell variables, growth after each MCS, division with random timing |
| [Actin-driven migration](@ref model-wortel-act) | `WortelAct` | a site-level actin memory makes cells crawl persistently (Niculescu et al. 2015) | site variables, copy-time updates, a neighbourhood drive |
| [Growing monolayer](@ref model-openvt) | `OpenVTGrowingMonolayer`, `OpenVTReferenceMonolayer` | one cell grows and divides into a colony (OpenVT benchmark; the 2024 Artistoo set and the manuscript's Table S1 set) | a growing target area, size-triggered division, contact counts, thresholds drawn per daughter |

The pages build on one another: the first explains the parts every model shares, and
each later page explains only what is new.
