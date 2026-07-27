# MakiePotts v0.2 Hardening Through Visual Audit A

Status: execution specification

Date: 2026-07-27

## Scope

This pass hardens the already approved v0.2 product. It adds regression
resistance and qualification evidence without adding a new plotting surface or
promoting an experimental one.

The pass ends only after Visual Audit A has been rendered, inspected, corrected
where necessary, and recorded. Tolerant golden-image CI, allocation ceilings,
and final release qualification belong to the following pass.

## Baseline

The admitted implementation baseline is:

- MakiePotts: 166 assertions;
- PottsToolkit: 711 assertions;
- CorePotts: 3,676 assertions;
- CairoMakie 0.15.13 full test and render qualification;
- GLMakie 0.13.13 offscreen framebuffer qualification;
- WGLMakie 0.13.13 HTML serialization qualification; and
- accepted manual render SHA-256
  `260d5736f4768a1eff8da6a18835df3fd82c93f58945f71472d56a2e194e743b`.

These values establish provenance, not a promise that assertion totals or image
bytes remain constant.

## H1 — Contract truth and containment

Deliverables:

1. Describe `PottsRenderFrame` as a defensively owned, logically immutable
   snapshot. Julia callers can still reach and mutate concrete fields, so
   mechanical immutability is not claimed.
2. Record every exported name as stable, limited, or experimental in
   `public-api-v0.2.toml`.
3. Record both supported `cell_metadata` call forms in the frame protocol:
   generation-aware identity and semantic cell owner.
4. Enforce exhaustive export classification and reject known direct accesses
   to CorePotts and PottsToolkit storage fields.
5. Distinguish manual visual references from automated visual regression.

Gate:

- the contract checker passes;
- the frozen CorePotts API inventory still passes;
- documentation contains no mechanical-immutability claim for render frames.

## H2 — Independent protocol consumer

An in-test downstream module must define:

- an `AbstractPottsRenderFrame` subtype with a storage layout unrelated to
  `PottsRenderFrame`;
- every stable frame accessor;
- a custom channel request and `materialize_channel` extension; and
- a custom encoding.

The foreign implementation must pass conformance, categorical and custom
continuous encoding, native `plot`, `PlotSpec`, reactive replacement, standard
legend/colorbar construction, inspection, transformation, framebuffer
readback, and PNG saving.

Gate:

- the journey uses exported protocols only;
- no production recipe or encoding reads canonical frame fields.

## H3 — Adversarial correctness

Coverage must include:

- one-site and singleton-axis domains;
- all-medium, all-obstacle, and all-cell ownership;
- nonzero origins and anisotropic spacing;
- all three orthogonal slice axes and endpoint indices;
- maximum valid IDs/generations and generation mismatch rejection;
- missing site/cell/medium values and palette exhaustion;
- malformed geometry, metadata, requests, and channels;
- rapid reactive replacement without child-plot reconstruction; and
- empty, singleton, and incompatible recording inputs.

Seeded randomized conformance and encoding cases increase from 32 to 100.

Gate:

- valid edge cases preserve exact geometry and semantics;
- invalid cases fail before partial publication or output.

## H4 — Recurring backend qualification

Backend smoke programs live below `lib/MakiePotts/test/backends` and operate on
the same public recipe:

- CairoMakie: render, update, framebuffer, and PNG save;
- GLMakie: offscreen render, update, framebuffer, and screen cleanup under
  Xvfb; and
- WGLMakie: render, update, HTML serialization, and nonempty payload.

CI installs the declared backend qualification environment and runs all three.
The normal MakiePotts package job remains the complete Cairo suite.

Gate:

- each program fails nonzero on a missing child plot, failed reactive update,
  empty framebuffer/payload, or missing output.

## Visual Audit A

The audit composition must show, at publication scale:

1. categorical cell-type encoding with medium, cells, obstacle, boundaries,
   legend, physical units, nonzero origin, and anisotropic spacing;
2. continuous channel encoding with missing values, boundaries, obstacle,
   colorbar, and a different theme;
3. a nontrivial orthogonal 3D slice with preserved source-axis labels; and
4. a transformed copy proving that Makie transformations and plot bounds remain
   coherent.

The audit checks:

- cell-edge, boundary, obstacle, and physical-axis alignment;
- categorical mapping and complete semantic legend;
- continuous missing-value and colorbar behavior;
- readable labels and balanced layout;
- slice orientation and source-axis provenance; and
- absence of clipping, overlap, stale reactive content, or redundant chrome.

Evidence consists of the final PNG, its dimensions and SHA-256, the generating
script, the inspection record, and passing relevant automated tests.

## Explicit non-goals

- mechanically read-only lattice containers;
- support for additional Makie minor lines;
- browser-driven WGL automation;
- a multi-platform golden-image gallery;
- strict wall-clock CI thresholds;
- historical notebook rewrites; and
- graduation or expansion of `PottsVolume`, `PottsExplorer`, or
  `RerunController`.
