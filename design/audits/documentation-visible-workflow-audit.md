# Documentation visible-workflow audit

> **Historical evidence.** This audit binds the pre-G5H manual and is not current qualification or
> construction authority. Its useful teaching observations feed G5H F19; Decision 0044 and the G5H
> hardening contract govern the replacement documentation product.

Date: 2026-07-27

Scope: the released documentation redesign on `main`, excluding Phase 16 material.

Status: remediated and re-audited on `codex/docs-visible-workflows`

## 2026-07-28 verification result

The failure described below has been corrected. This section records the shipped
state; the original finding remains in the audit as the reason for the stronger
contract.

- All required reader-facing Learn and Example pages show their canonical program
  in evaluated blocks. The checker accepts a program taught across consecutive
  blocks, so prose can explain each conceptual step without hiding setup.
- Reader-facing `include(...)` and `ReferenceModels.*` shortcuts are absent.
- Every gallery program imports MakiePotts and converts saved engine state with
  `renderframe` or `renderframes`.
- Every gallery result uses CairoMakie and the MakiePotts recipe. The four dynamic
  studies call `record_potts` and embed the generated MP4.
- Each example plots its contract-relevant measurement: volume error, unlike
  interfaces, directed displacement, lifecycle counts, morphology, fluctuation
  distribution, ownership, dimensional reuse, exact restoration, or ensemble
  variability.
- The strict Documenter build passes with `warnonly = false`. The documentation
  checker now rejects hidden canonical programs, missing explanatory comments,
  missing teaching sections, reference-model shortcuts, decorative custom
  images, and plots that omit the declared scientific evidence.
- Rendered inspection confirms a clean outcome-first home page, readable visual
  gallery, copyable code, no large intermediate object dumps, and working local
  routes.
- The generated H.264 animations are short inspection loops rather than long
  simulations: sorting is 11 frames at 3 fps, chemotaxis is 9 frames at 3 fps,
  growth/division is 9 frames at 2 fps, and elongation is 11 frames at 3 fps.
  Contact-sheet inspection confirms that both spatial state and quantitative
  trace change across each animation.

The corrected documentation satisfies the accepted non-Phase-16 9/10 contract.
This remains an auditor-led assessment, not a substitute for observing new users
work through the manual.

## Verdict

The documentation is not yet at the accepted 9/10 bar for executable teaching.
Its information architecture, strict build, API inventories, scientific caveats,
and generated media are strong. Its code presentation is not.

Every required Learn tutorial and gallery example delegates its primary evaluated
block to an `include(...)` call. A reader therefore sees the result of a program
without seeing the program that constructed it. The gallery also avoids the
MakiePotts workflow in all ten example sources, even though every example is
presented with a figure, animation, or diagram.

The previous 91/100 assessment did not test this property and is superseded until
the remediation and acceptance checks below pass.

## Inventory

### Rendered pages that hide the primary program

All 24 required executable pages contain `include(...)` in their primary
Documenter `@example` block:

- 14/14 Learn pages:
  `install-and-verify`, `cellular-potts-concepts`, `first-simulation`,
  `build-model`, `domains-and-initialization`, `adhesion-and-mechanics`,
  `fields-and-chemotaxis`, `rules-and-lifecycle`,
  `algorithms-and-guarantees`, `observe-and-analyze`,
  `checkpoint-and-reproduce`, `visualize-and-export`,
  `backends-and-performance`, and `research-workflow`.
- 10/10 gallery pages:
  `relaxing-cell`, `differential-adhesion`, `chemotaxis`,
  `growth-and-division`, `elongated-network`, `fluctuating-droplet`,
  `boundaries-and-obstacles`, `same-model-2d-3d`, `stop-and-resume`,
  and `reproducible-ensemble`.

The includes are not isolated snippets or setup-only helpers. They are the sole
visible execution path for the model construction, algorithm selection,
simulation, observation, assertions, and result assembly.

### MakiePotts exposure

- Only 2/14 tutorial sources import MakiePotts:
  `first_simulation.jl` and `visualize_and_export.jl`.
- 0/10 gallery example sources import MakiePotts.
- Only two rendered pages contain hand-written MakiePotts plotting snippets.
  Those snippets are not evaluated and refer to objects produced by the hidden
  include.
- The gallery asset generator obtains logical snapshots through CorePotts and
  constructs its lattice SVGs directly. It does not consume MakiePotts render
  frames or encodings. This custom image pipeline is removed by the remediation.

### Quality-gate gap

`scripts/check_documentation_quality.jl` verifies that each required tutorial or
example has a canonical source file. It does not verify that:

- the source is visible on the rendered page;
- the visible code is the code that Documenter executes;
- `include(...)` is absent from reader-facing examples;
- a visual example demonstrates the MakiePotts conversion and plotting path; or
- the gallery renderer consumes the supported visualization boundary.

The result is a false-positive quality score: source existence was treated as
equivalent to source visibility.

## Why this fails the teaching contract

A runnable source link is useful supplementary material, but it is not a
replacement for a complete workflow on the page. Readers need to see, in order:

1. imports;
2. model or problem construction;
3. algorithm selection;
4. `solve`, `init`/`step!`, or ensemble execution;
5. observation or analysis;
6. MakiePotts frame conversion for spatial results;
7. backend plotting or export when a visual result is claimed; and
8. the concrete value or figure produced by that code.

Hiding steps 1–7 behind `include(...)` prevents scanning, copying, adapting, and
debugging. It also makes the prose impossible to review against the actual API
without leaving the page.

## Remediation design

Use explicit Documenter `@example` blocks containing the complete canonical
program. Keep the small `.jl` files as standalone sources for tests and direct
execution, but enforce byte-normalized containment: the canonical source must
appear inside the page's evaluated block. This deliberately accepts a small
amount of duplication because:

- the programs are short (roughly 15–66 lines);
- the rendered Markdown remains obvious to contributors;
- no source-generation layer is needed; and
- CI can make drift impossible.

Literate.jl remains a reasonable future option if examples grow into substantial
narrative programs. It is unnecessary for this correction.

For visual workflows:

- canonical spatial examples import MakiePotts;
- they retain explicit host snapshots;
- they call `renderframe` or `renderframes`;
- reader-facing plotting blocks show a real Makie backend, the MakiePotts recipe,
  legends where relevant, and `save` or `record_potts` when export is taught;
- Documenter renders the visible MakiePotts/CairoMakie result directly; the
  parallel custom SVG renderer and its checked-in outputs are deleted.

The checkpoint-only example may use a before/after render frame to make exact
continuation spatially inspectable. The ensemble example may render a
representative trajectory while keeping ensemble statistics as its primary
result.

## Executable acceptance criteria

The documentation quality checker must reject the repository when any of these
conditions is true:

1. A required target Learn or example page contains a reader-facing
   `include(...)`.
2. Its canonical source is absent from an evaluated `@example` block.
3. A required example with a figure or animation has no visible
   `using MakiePotts` and `renderframe`/`renderframes` workflow.
4. A page claims backend plotting or export but only presents an unevaluated
   fenced snippet.
5. A gallery page references a parallel custom image instead of displaying the
   result of its evaluated MakiePotts block.
6. The strict Documenter build emits an error or warning.
7. Canonical examples or the quality-checker tests fail.

`Base.include` remains allowed inside internal test harnesses. It is forbidden as
a reader-facing documentation surface.

## Target quality reassessment

Before remediation, the released documentation should be treated as approximately
7.5/10 overall: strong structure and governance, but a material failure in the
central tutorial experience.

After remediation:

- all 24 canonical programs are visible in evaluated blocks;
- all 10 gallery programs import MakiePotts and materialize render frames;
- all 10 gallery pages execute a native CairoMakie/MakiePotts recipe;
- the custom SVG generator, manifest, review record, and checked-in SVG outputs
  are removed;
- the quality gate rejects reader includes, canonical-source drift, missing
  MakiePotts/backend calls, and custom example images;
- the strict Documenter build completes without warnings; and
- desktop and 390 px rendered-site inspection shows no page-level overflow,
  copyable code, and responsive native figures.

These results support a corrected 92/100 assessment for the non-Phase-16
documentation.
