# MakiePotts Visual Audit B

Status: accepted

Date: 2026-07-27

## Evidence

- Generator: `lib/MakiePotts/test/visual_audit_b.jl`
- Artifact: `makiepotts-visual-audit-b.png`
- Dimensions: 3200 × 1880 pixels
- File size: 351267 bytes
- SHA-256: `77afeca1d3ead38aefbca0f1109ae36580ddce6af3ee71e17fcdba89d593e67c`

The generator exits nonzero unless the unrelated downstream frame satisfies
the public conformance protocol, its downstream continuous encoding supplies
inspector-compatible label and unit semantics, all four categorical frames
share exact physical bounds, both representative recipes retain the three
atomic reactive children, and the PNG is nonempty.

## Composition audit

The accepted publication composition demonstrates:

1. the canonical categorical recipe with physical axes, semantic boundaries,
   medium and obstacle treatment, and a complete native Makie legend;
2. an unrelated `ColumnarFrame` rendered through the downstream-defined
   `RootSignalEncoding`, with a native Makie colorbar;
3. MCS 0, 50, and 100 frames with fixed geometry and stable category colors; and
4. a normal Makie line/scatter plot beside the Potts recipes, with a reactive
   current-MCS marker.

Manual inspection at original resolution found no clipped text, overlapping
labels, ambiguous legend or colorbar semantics, inconsistent category colors,
or redundant panel chrome. Physical axes align with the frame geometry and the
hierarchy remains legible from the figure title through panel titles and axes.

## Refinement round

The first render placed the current-MCS diamond directly on the time-series
axis limit. The final render adds modest horizontal margin so the current
marker is fully visible. The generator's atomic-child assertion was also
corrected to compare tuple-shaped results without weakening the expected
three-child invariant. The final artifact was rerendered and inspected again.

## Related gates

- Accepted tolerant reference:
  `lib/MakiePotts/test/reference/makiepotts-v02.png`
- Tolerant-reference SHA-256:
  `4c33bb9b296b211b021bd4edc5c5146e483e0c3db1744d0d7851ea3a95293afb`
- Audit A SHA-256:
  `87dd9fc74a0c82031f5b607ce785680859fb0a18846c6eb8150da30b7e9cf407`

Backend and full-suite results are recorded in
`design/makiepotts/qualification.md`.
