# Contributing

Potts.jl follows the ordinary Julia package workflow. Julia 1.12 or a later
Julia 1.x release is required.

## Semantic names and direct cutovers

Internal phases, gates, and review checkpoints may organize development, but
they are not supported product states. Live identifiers, errors, configuration,
serialized fields, extensions, and current documentation must name durable
scientific, mathematical, numerical, hardware, protocol, ownership, or
execution meaning rather than when an implementation was developed.

Replace temporary names and representations directly across source, tests,
documentation, examples, and downstream packages. Delete the replaced name in
the same edit; do not add forwarding aliases, deprecated spellings, old/new
selectors, feature flags, or parallel migration implementations. Breaking
renames use ordinary package versioning.

Classify names by meaning, not by a word blacklist. Scientific phases,
mathematical/compiler candidates, genuine algorithm and backend choices,
checkpoint/import behavior, independent test oracles, and durable protocol or
schema versions are valid product concepts. Historical milestone terminology
may remain in specifications, design records, audits, and archived evidence.

Use ordinary package tests, integration tests, documentation builds, Aqua,
ExplicitImports, and relevant GPU witnesses to validate a cutover. Do not add a
custom policy gate script; review establishes that the surviving name has
durable meaning and normal tests establish behavioral preservation.

No evidence hashes, milestone scripts, frozen pass/fail timing gates, or
committee paperwork are part of development. Reviews are ordinary technical
reviews. Focused benchmarks remain valuable for investigation and reproducible
performance claims, but machine-dependent timing observations do not become
brittle acceptance thresholds. Historical specifications, audits, and evidence
may record earlier processes without making them current contributor workflow.

## Prevent development debt

Keep one production authority for each fact. Scientific meaning belongs to its
domain package, spatial and publication meaning belongs to LocalMath, and
physical execution belongs to the shared KernelAbstractions path. Inspection
and diagnostics project those authorities rather than storing parallel evidence.

New abstractions must delete an existing authority or demonstrate reuse by real
consumers. Keep exploratory runtimes and compiler prototypes outside production
source. Once an approach qualifies, move it into the sole production path and
delete the prototype in the same edit. Downstream packages must use public APIs;
private structures are contracts only inside their owning package.

Tests should assert observable behavior: scientific results, deterministic and
ordered semantics, failure atomicity, checkpoint continuation, ownership,
allocation, compilation behavior, and CPU/GPU parity where applicable. Avoid
assertions about milestone labels, arbitrary device ordinals, evidence metadata,
implementation slogans, or incidental struct layout. When an independent
scientific oracle is useful, keep one oracle and one production implementation;
the oracle must not become another executor.

Treat functional support and stronger guarantees independently. Exact replay,
checkpoint portability, deterministic conflict resolution, and performance each
need evidence that directly exercises that claim. Ordinary compatibility
environments remain broad; pin a complete dependency environment only for a
guarantee that genuinely depends on exact dependency replay.

Before handing off a change, check:

1. Did it create another semantic authority or execution path?
2. Did development chronology enter a live identifier or schema?
3. Does a test assert an incidental implementation detail?
4. Does a downstream package reach through another package's private API?
5. Did a replaced name, representation, or implementation remain active?
6. Do CPU and GPU still use the same semantic KernelAbstractions path?
7. Is every claimed guarantee exercised by the appropriate ordinary test or
   reproducible benchmark?

Resolve any affirmative answer as part of the same change.

## Test

During development, start with the smallest self-contained test file that owns
the changed behavior. For example, a focused root check can load the shared
setup explicitly:

```sh
julia --project=. --startup-file=no -e 'include("test/setup.jl"); include("test/test_public_api.jl")'
```

Focused commands shorten the edit loop; they are not a second test inventory
or release gate. Before handoff, run the complete suite of every changed
package. Add the integration suite when a package boundary, extension, SciML
lifecycle, or persistence behavior changed; add the strict documentation build
when a public name, docstring, example, or manual page changed. Applicable
real-GPU tests are required when device execution, adaptation, admission, or
lifetime changed.

Run the Potts package suite from this repository:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

LocalMath, CorePotts, and MakiePotts are independent repositories with their
own test, documentation, and backend qualification. For sibling development,
place their checkouts beside Potts in a plain `PottsEcosystem` directory and
use `Pkg.develop(path=...)` from a temporary or task-specific environment.

Run Potts-owned cross-package behavior with:

```sh
julia --project=integration -e 'using Pkg; Pkg.instantiate()'
julia --project=integration integration/runtests.jl
```

The normal integration environment exercises functional behavior across its
declared compatibility ranges. Exact native checkpoint replay is tested
separately in `integration/replay`; its pinned Julia, dependency graph, and
ARM macOS platform are part of that stronger replay claim and do not restrict
ordinary functional execution. Use the qualified platform documented in
`integration/replay/README.md` for that suite.

The package suites include Aqua checks. Published stochastic models test both
exact fixed-seed replay and seed-sensitive, bounded behavior. A random seed is
part of a reproducible run identity, not a claim that different seeds produce
the same trajectory.

## Format Julia changes

This repository adopts [Runic](https://github.com/fredrikekre/Runic.jl) for
new and modified Julia code. During incremental adoption, check only the files
you touched; do not mechanically reformat the repository as part of an
unrelated change. With Runic 1 installed as a Julia app, check explicit files
without modifying them:

```sh
runic --check --diff path/to/file.jl another/file.jl
```

Use `runic --inplace` on those same explicit paths to apply formatting. A
future dedicated baseline commit may extend the check to all tracked Julia
files.

## Build the documentation

The manual uses a strict Documenter build: doctest, executable-example, and
cross-reference failures fail the command.

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The manual executes bounded authoring and integration examples, including the
custom-model workflow. PottsModels owns complete scientific model factories and
tutorials; MakiePotts and backend suites own rendering and device behavior.

## Continuous integration

Every PR runs the complete Potts CPU package suite, a macOS public-trajectory
smoke, and the strict documentation build. Integration, closed-profile replay,
and Metal tests also run unless the **whole PR diff** changes only top-level
prose/metadata or Markdown under `spec/` and `design/`. Renames are considered
as deletion plus addition. Executable documentation, examples, tests, dependency
files, workflows, and unknown paths select those execution jobs. An unavailable
diff selects all jobs; a failed or malformed selector fails the selected jobs
instead of allowing a silent skip. Main and manual runs select all execution
jobs and the complete macOS package suite. The weekly sibling-main run is a
separate diagnostic of floating upstream branches.

Ordinary CI and documentation use the same default LocalMath and CorePotts
commit selection. Their manual inputs accept only full lowercase commit SHAs;
supply the same pair when testing a cross-package change, and inspect the
printed source revisions. These source selections make a reviewed candidate
reproducible without narrowing ordinary package compatibility or claiming an
exact replay guarantee for every resolved dependency environment.

The separate `exact-replay` and `metal` jobs retain their committed upstream
manifest selections; candidate inputs do not silently replace those profiles.
Run the real-Metal semantic tests independently from performance measurements:

```sh
julia --project=benchmark/backends/metal --startup-file=no -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate(; julia_version_strict=true)'
julia --project=benchmark/backends/metal --startup-file=no benchmark/backends/metal/runtests.jl
```

Use Julia 1.12.6. Hosted `macos-15` runs require functional Metal and fail when it
is unavailable. The runner includes Potts-owned extension loading, symbolic
relationship authoring, lifecycle authoring, and native-component tests in its
Julia process. CorePotts and LocalMath own their runtime and mathematical tests.
Local real-GPU runs remain useful for hardware-specific investigation;
performance campaigns are separate diagnostic measurements.

Dispatch `Ecosystem integration` with full commit SHAs for LocalMath, CorePotts,
Potts, and MakiePotts to test a cross-repository candidate together. To include
PottsModels, also supply its actual `owner/repository` and full commit SHA;
neither has an invented default. Both Models inputs must be supplied together.
A run without them covers only the four selected repositories and does not
validate the model library. Include Models for model-library changes and
upstream changes affecting its public consumer contracts.

The combined workflow runs ordinary package, scientific, integration,
documentation/tutorial, rendering, and applicable Metal tests. Its macOS
candidate-tuple tests intentionally develop the selected upstream revisions,
including native continuation tests; they do **not** establish the separately
published closed-profile replay guarantee. Changes to any selected revision
require rechecking the affected owner and consumers together before handoff.
Use these ordinary results to coordinate dependent repository merges; this
workflow does not merge repositories or make a multi-repository change atomic.
It does not impose release-version inventories, spelling scans, or additional
qualification paperwork.

## Investigating compound-model compilation

Run `benchmark/compound_compilation.jl` in an environment that develops the
checkout being measured. Run each combination in a fresh Julia process:

```sh
julia --project=ENV --startup-file=no benchmark/compound_compilation.jl model sequential
julia --project=ENV --startup-file=no benchmark/compound_compilation.jl model checkerboard
julia --project=ENV --startup-file=no benchmark/compound_compilation.jl site sequential
julia --project=ENV --startup-file=no benchmark/compound_compilation.jl site checkerboard
```

Replace `ENV` with the actual package environment. The diagnostic separates
authoring, structural compilation, scheduled problem construction,
initialization, first and subsequent steps, and repeated initialization. Julia's
`@time` reports compilation time and cumulative allocations; allocations are
not peak memory. Package loading occurs before the measured sections. Numerical
swap, ownership, and clock checks run outside the timed sections.

Record Julia/package versions and machine load with the output. Use an idle
machine and repeated fresh processes for comparisons; concurrent test runs can
distort timings. These measurements guide profiling, not pass/fail thresholds.

Current specifications and decisions live under `spec/`. Historical interviews
and evidence under `design/audits/`, and retired scripts under
`scripts/archive/`, describe earlier states, not active development gates.
