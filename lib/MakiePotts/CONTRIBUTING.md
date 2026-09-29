# Contributing

MakiePotts.jl follows the ordinary Julia package workflow. Julia 1.12 or a later
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
the changed behavior. The package tests use CairoMakie and include frame,
encoding, recording, downstream-protocol, allocation, and adversarial coverage:

```sh
julia --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
```

Focused commands shorten the edit loop; they are not a second test inventory
or release gate. Before handoff, run the complete suite of every changed
package. Add the integration suite when a package boundary, extension, SciML
lifecycle, or persistence behavior changed; add the strict documentation build
when a public name, docstring, example, or manual page changed. Applicable
real-GPU tests are required when device execution, adaptation, admission, or
lifetime changed.

Run the package suite from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Build documentation with:

```sh
julia --project=docs docs/make.jl
```

The package suite includes Aqua and Cairo-based recipe coverage. The separate
rendering environments exercise CairoMakie, GLMakie, WGLMakie, clean-install
rendering, and tolerant visual regression. In a sibling checkout, develop the
audited LocalMath, CorePotts, Potts, and MakiePotts repositories into that
environment before running these commands:

```sh
julia --project=test/backends --startup-file=no test/backends/cairo.jl
julia --project=test/backends --startup-file=no test/backends/wgl.jl
xvfb-run -a julia --project=test/backends --startup-file=no test/backends/gl.jl
julia --project=test/backends --startup-file=no test/visual_regression.jl
julia --project=test/backends --startup-file=no test/clean_install_smoke.jl
```

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

The manual executes its own bounded examples and API references. Backend and
visual-reference behavior remains owned by the package's separate rendering
tests rather than by documentation prose.

## Continuous integration

Every pull request runs the standalone package suite and strict documentation
build on Julia 1.12.6. Cairo/GL/WGL backend smokes, clean-install rendering,
visual regression, the native recipe and macOS rendering run unless the whole
PR diff consists only of explicitly listed non-executable prose/metadata paths.
Executable docs, source, tests, examples, dependency/workflow changes and unknown
paths retain those checks. Main and manual runs exercise the full workflow.

The workflow uses explicit LocalMath, CorePotts and Potts revision defaults;
manual dispatch can select candidate siblings and every testing job logs the
actual checkout tuple. Production projects contain no sibling paths and retain
broad compatibility ranges. An ordinary candidate run is not an exact dependency
replay claim. MakiePotts has no device execution path or independent GPU
capability claim. Benchmarks remain diagnostic and run when their measured
rendering path changes.

The package job's explicit `AMD` 0.5.3 installation is a CI resolver workaround,
not a MakiePotts dependency: no package, documentation, example, or test code
imports it, and it was removed from every declared project. The workflow retains
the installation until a hosted comparison demonstrates that the complete
unregistered sibling checkout resolves and tests without it. Phase telemetry
records the cost while preserving the current qualified dependency selection.
