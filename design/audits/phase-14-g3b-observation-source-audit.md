# Phase 14.1 G3-B Observation Source Audit

Status: exact Wang record schema and schedule accepted; generic runtime primitive remains
paper-independent

Date: 2026-07-25

## Authority

The observation authority is Wang Git commit
`60ebcf013aafefdff39ebe566114ee79f2a6e54d`, file
`s4_figures/Figure3/Radial/Simulation/fpp_polarity_force_Steppables.py`, SHA-256
`2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30`.

The pinned source sets `relax_step = 120` at line 7. The relevant steppable executes only under
`if mcs > relax_step` at lines 245–246. It opens one record for that source MCS at lines 308–310,
writes the exact header at line 312, and writes one row for each `CELL` at lines 313–331.

The exact source header is:

```text
cell_id,x,y,x_self_polarity,y_self_polarity,a,s,rac,f,f_x,f_y,fpp,f_coef,p_frac
```

Under the accepted normalized mapping, source MCS `k` is target MCS `k+1`. The source condition
`mcs > 120` over source `0:499` therefore becomes target `122:500`, carrying exactly derived source
labels `121:499`.

## Generic versus paper-specific authority

The source freezes only the Wang declaration:

- the two coordinate labels `x` and `y`;
- the eleven named property projections following those coordinates;
- the target/source schedule;
- and the source-shaped fourteen-column publication.

It does not justify a Wang-named runtime type, a fixed two-dimensional generic table, or a
paper-specific execution branch. CorePotts therefore implements a dimension-matched bounded
cell-table primitive with arbitrary typed named property bindings. The Wang assembly supplies this
exact two-dimensional schema and schedule as configuration.

The target 91/source 90 and target 271/source 270 lossless ownership publications are Phase 14
evidence requirements for later geometric analysis. They preserve the complete lattice ownership
and cell identity envelope; Phase 14.3, not G3-B, owns derived features and classifier/UMAP
execution.

## Claim boundary

This audit proves source labels, source timing, and the generic/paper boundary. It does not prove
the assembled Wang process order, paper-scale output agreement, real Metal or ROCm execution, or
Phase 14.3 classification.
