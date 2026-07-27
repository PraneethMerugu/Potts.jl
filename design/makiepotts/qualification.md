# MakiePotts v0.2 Qualification

Status: local implementation qualification passed through Visual Audit B

Date: 2026-07-27

## Contract and architecture

- The owner-approved product, API, visual, and acceptance contracts are recorded
  beside this report.
- CorePotts exposes saved-state and domain metadata only through additive frozen
  API accessors.
- PottsToolkit owns explicit, visualization-neutral lattice observation.
- MakiePotts never reads internal simulation fields, starts a solve, synchronizes
  a device, or transfers backend storage while plotting.
- The render-frame conformance suite exercises only the stable accessor
  protocol, so downstream frame implementations do not inherit the canonical
  frame's physical layout.

## Automated qualification

`Pkg.test()` for MakiePotts passed 505 assertions:

- validated semantic frames and invalid-state rejection;
- 100 seeded randomized frame cases;
- full-domain and orthogonal-slice requests;
- retained Toolkit observations;
- typed site and cell channels, missing values, categorical and continuous
  encodings;
- reactive child-plot identity;
- exact physical data limits and transformed bounding boxes;
- Makie `PlotSpec`, `Legend`, `Colorbar`, `DataInspector`, PNG save, and Cairo
  framebuffer behavior;
- GIF recording and explorer lifecycle;
- atomic latest-request-wins reruns;
- downstream open-protocol conformance and custom encodings;
- adversarial invalid geometry, channels, requests, slices, and recordings;
- deterministic warmed allocation ceilings; and
- Aqua, ambiguity detection, and complete exported-name documentation.

Additional checks passed:

- PottsToolkit full suite: 711 assertions;
- CorePotts full suite: 3,676 assertions;
- Phase 13 frozen-API inventory;
- Phase 14 architecture closure;
- repository structure and workspace policy;
- strict Documenter build with doctests and cross-reference validation;
- clean current example execution.

The exact clean temporary-project journey separately developed MakiePotts,
installed CairoMakie 0.15, and completed frame construction, native
`plot(frame)`, legend construction, framebuffer readback, and PNG save. It did
not inherit the developer workspace's loaded packages.

## Backends and visual audit

- CairoMakie 0.15.13: complete test suite, PNG rendering, save, and recording.
- GLMakie 0.13.13: offscreen recipe render and framebuffer readback.
- WGLMakie 0.13.13: browser-render payload serialization.
- Metal and ROCm do not enter the render recipe. Their state reaches MakiePotts
  only after CorePotts publishes an explicit host snapshot or PottsToolkit
  publishes a declared ownership observation.

The original render audit at `lib/MakiePotts/test/render_audit.jl` produced a
2480×960 categorical/continuous comparison. The accepted tolerant Cairo
reference now also covers categorical and continuous recipes, physical
geometry, boundaries, semantic overlays, legend, colorbar, and text layout.
The final comparison matched exactly:

- materially changed pixels: 0.0%;
- mean absolute channel error: 0.0;
- accepted limits: 3.5% and 0.006 respectively; and
- the deliberate perturbation self-check was rejected.

Visual Audit A confirmed:

- exact alignment of cell edges, boundaries, obstacles, and physical axes;
- deterministic categorical mapping with medium and obstacle legend entries;
- continuous missing-value treatment and standard Makie colorbar behavior;
- readable publication layout at the requested output scale.

Audit SHA-256:
`260d5736f4768a1eff8da6a18835df3fd82c93f58945f71472d56a2e194e743b`.

Visual Audit B is the final 3200×1880 publication composition. It demonstrates
the canonical categorical recipe, an unrelated downstream frame and downstream
continuous encoding, a stable three-frame MCS sequence, and an ordinary Makie
time series with a reactive current-frame marker. The first visual round found
the current marker on the axis edge; the accepted rerender adds margin and was
re-inspected at original resolution.

Visual Audit B SHA-256:
`77afeca1d3ead38aefbca0f1109ae36580ddce6af3ee71e17fcdba89d593e67c`.

## Performance smoke

Machine-readable benchmark evidence on a 512×512 frame:

| Operation | Median | Memory | Allocations |
|---|---:|---:|---:|
| Cell-type encoding | 5.728 ms | 4,933,984 B | 83 |
| Cell-identity encoding | 8.096 ms | 14,073,680 B | 14,401 |
| Boundary extraction | 711.708 μs | 1,845,104 B | 21 |
| Full frame conformance | 6.711 ms | 144 B | 3 |

These are recorded as a smoke baseline, not a cross-machine performance
guarantee. The reproducible benchmark entry point is
`lib/MakiePotts/benchmark/benchmarks.jl`.

The normal test suite also enforces deliberately generous, warmed 256×256
allocation ceilings: 8 MiB for cell type, 20 MiB for identity, 4 MiB for
boundaries, and 1 MiB for conformance. These are regression tripwires rather
than optimization targets.

## Hardening through Visual Audit A

The bounded hardening pass on 2026-07-27 adds:

- exhaustive stable, limited, and experimental export classification;
- a static accessor-boundary sentinel;
- an unrelated downstream frame layout, custom channel request/materializer,
  and custom continuous encoding exercised through the public Makie journey;
- 100 seeded randomized frames and adversarial geometry, slicing, channel,
  reactive, and recording cases;
- declared CairoMakie, GLMakie, and WGLMakie qualification
  programs; and
- the accepted four-panel Visual Audit A recorded in
  `visual-audit-a.md`.

Visual Audit A found one defect: medium sites and genuinely missing cells were
indistinguishable for cell-scoped continuous encodings. The corrected recipe
uses its existing semantic overlay child to distinguish medium, missing, and
obstacle sites without reconstructing reactive child plots or hiding
site-scoped numeric values.

## Hardening through Visual Audit B

The final bounded pass adds:

- tolerant visual regression with expected, actual, and amplified-difference
  failure artifacts during explicit pre-release qualification;
- actionable missing-channel and geometry diagnostics;
- owned subscription and inspector cleanup with idempotent `close`;
- close-safe latest-request-wins reruns;
- complete preflight validation and atomic destination replacement for
  recordings;
- deterministic allocation guards and optional TOML benchmark output;
- a clean install-to-PNG script;
- release metadata, backend manifest, reference digest, and artifact-hygiene
  enforcement; and
- the accepted Visual Audit B record in `visual-audit-b.md`.

Local qualification passed the three package suites, CairoMakie, GLMakie, and
WGLMakie programs, tolerant visual regression, strict documentation and
doctests, native example, frozen-API inventory, architecture closure, repository
structure, metadata and artifact hygiene, TOML/YAML parsing, notebook JSON
parsing, and whitespace validation. Pull-request CI keeps the complete
CairoMakie package suite and release gates; the standalone GLMakie, WGLMakie,
native-example, and tolerant visual-regression programs are retained for
explicit pre-release qualification.
