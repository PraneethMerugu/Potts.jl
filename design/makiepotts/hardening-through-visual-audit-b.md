# MakiePotts v0.2 Hardening Through Visual Audit B

Status: execution specification

Date: 2026-07-27

## Scope

This pass begins from the accepted Visual Audit A state and completes the
remaining bounded release hardening. It ends only after tolerant visual
regression, lifecycle and failure cleanup, allocation guards, clean-install and
release checks, Visual Audit B, and the complete qualification matrix have
passed.

The pass does not expand or graduate `PottsVolume`, `PottsExplorer`, or
`RerunController`.

## B1 — Tolerant visual regression

One deterministic CairoMakie reference composition covers categorical and
continuous recipes, physical geometry, boundaries, semantic overlays, legend,
colorbar, and text layout.

Comparison is performed on decoded RGBA pixels:

- dimensions must match exactly;
- a pixel is materially changed when any channel differs by more than `8/255`;
- materially changed pixels must not exceed 3.5%;
- mean absolute channel error must not exceed 0.006; and
- failures retain expected, actual, and amplified-difference PNGs.

The deliberately small single-reference set avoids a brittle gallery. CI
uploads failure evidence and never updates the accepted reference.

Gate:

- an unchanged render passes;
- an intentionally perturbed render fails in a self-test;
- the reference is generated only through an explicit acceptance mode.

## B2 — Lifecycle, errors, and performance guards

Deliverables:

1. `PottsExplorer` retains and releases its slider subscription and optional
   `DataInspector`; `close` is idempotent.
2. Closing a `RerunController` prevents in-flight or future work from
   publishing.
3. Recording validates frames and frame rate before rendering, writes to a
   temporary sibling artifact, and replaces the destination only after success.
4. Public failure text reports the requested key, available channels, expected
   geometry, and remediation where applicable.
5. Warmed common operations have generous deterministic allocation ceilings.
   Wall-clock medians remain non-gating evidence.
6. The benchmark entry point can emit a machine-readable TOML report containing
   median time, memory, and allocation counts.

Gate:

- repeated construction, update, close, and failure paths do not retain owned
  subscriptions or replace a previously valid result/output;
- allocation ceilings catch order-of-magnitude regressions, not machine noise.

## B3 — User and release journey

Deliverables:

- the clean temporary-project exercise installs CairoMakie and completes
  construct → plot → legend → framebuffer → PNG;
- the native example runs from its declared environment;
- strict documentation, doctests, API classification, architecture, workspace,
  manifest, metadata, and whitespace checks pass;
- the backend qualification manifest pins the tested Makie backend line; and
- generated benchmark output and visual failure artifacts remain outside the
  package source.

Gate:

- no success claim depends on the developer workspace already having loaded
  MakiePotts;
- the release checker fails on missing metadata, reference evidence, or an
  undeclared backend dependency.

## Visual Audit B

The final publication composition shows:

1. the canonical categorical recipe with physical axes and complete legend;
2. an unrelated downstream frame rendered by a downstream continuous encoding
   with a standard Makie colorbar and inspector-compatible semantics;
3. a three-frame MCS sequence demonstrating stable categorical identity and
   geometry; and
4. an ordinary Makie time-series panel composed beside the Potts recipes with a
   linked current-MCS marker.

The audit checks visual hierarchy, compact publication layout, categorical
stability, downstream interoperability, semantic legend/colorbar correctness,
physical alignment, typography, and absence of clipping or redundant chrome.

Evidence consists of the final PNG, dimensions, SHA-256, generator, inspection
record, tolerant-reference result, all backend smokes, and complete
qualification commands.

## Explicit non-goals

- mechanically read-only lattice storage;
- additional Makie compatibility lines;
- browser-driven WGL interaction automation;
- hard cross-machine timing budgets;
- a multi-platform visual gallery;
- a separate published conformance package;
- historical notebook rewrites; and
- new dashboard, selection, volume, or rerun product features.
