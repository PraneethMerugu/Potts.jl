# MakiePotts v0.2 Hardening Visual Audit A

Status: accepted

Date: 2026-07-27

Generator: `lib/MakiePotts/test/visual_audit_a.jl`

Artifact:
`/Users/praneethmerugu/.codex/visualizations/2026/07/27/019fa170-487e-7120-89f2-a7574f5092b1/makiepotts-visual-audit-a.png`

Dimensions: 3,080 × 1,840 pixels

File size: 315,263 bytes

SHA-256:
`87dd9fc74a0c82031f5b607ce785680859fb0a18846c6eb8150da30b7e9cf407`

## Composition

The audit renders four publication-scale panels:

1. cell-type categories with medium, cells, obstacle, boundaries, physical
   coordinates, nonzero origin, anisotropic spacing, and native legend;
2. a continuous cell channel with an ordinary Makie colorbar and explicit
   medium, missing, and obstacle semantics;
3. a true axis-2 projection of a three-dimensional CorePotts state, labeled
   with preserved source axes `(1, 3)` and generation-aware identities; and
4. the categorical recipe translated through Makie's transformation system.

## Defect found and corrected

The first render showed that a cell-scoped continuous channel used `nan_color`
for both sites outside the cell scope and genuinely missing cell values. Medium
and missing were therefore visually indistinguishable.

The recipe's existing semantic image child now overlays:

- medium sites for cell-scoped channel encodings with `medium_color`;
- obstacle sites with `obstacle_color`; and
- neither site-scoped numeric values nor genuinely missing cell values.

This retains the three-child reactive plot structure and keeps site-scoped and
medium-scoped numeric channels unobscured. Automated semantic-overlay assertions
cover the distinction.

## Final inspection

Accepted:

- physical cell edges align with heatmap cells, obstacle masks, and boundary
  segments in all panels;
- nonzero origins and anisotropic spacing are reflected correctly by axes;
- categorical colors are deterministic and every visible semantic ownership
  category appears in the legend;
- continuous medium, missing, and obstacle regions are visibly distinct;
- the continuous panel inherits its light medium, dark obstacle, and white
  boundary styling from a separate `potts_theme`;
- the colorbar describes only the continuous numeric scale;
- the projected slice is nontrivial, correctly oriented, and labeled with
  source axes `(1, 3)`;
- the translated recipe moves its heatmap, semantic overlay, and boundaries as
  one unit and reports the asserted transformed bounding box;
- titles, axes, legends, and colorbar are legible without clipping or overlap;
  and
- no stale reactive content or redundant plot-owned layout chrome is visible.
