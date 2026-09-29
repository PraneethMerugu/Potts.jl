# Contributing

LocalMath.jl follows the ordinary Julia package workflow. Julia 1.12 or a later
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
julia --project=. --startup-file=no -e 'using Test; import LocalMath; include("test/support.jl"); include("test/test_public_api.jl")'
```

Ordered-fold participation and publication are owned by
`src/execution/ordered_fold_stage.jl`. The shared behavioral fixture
`test/fixtures/ordered_fold_control_contracts.jl` exercises closed/open gates,
retained destinations, and unchanged duplicate-order rejection through the
ordinary CPU and Metal inventories.

Field-derived control dependencies are owned by `src/stage_planning.jl`.
Its publication-totality predicate recognizes `Unique` with `TotalCoverage`
and `Reduce` with `IdentitySeed`, and rejects whole-stage-gated producers.
Prefix, mask, and subset controls filter contributions rather than bypassing
successful publication. An identity-seeded reduction initializes every
destination even when no source contributes; `ExistingSeed` cannot establish
a freshly produced control value. `test/fixtures/reduction_control_contracts.jl`
checks open, closed, and no-contribution gate production plus rejection of
existing-value seeds through the ordinary CPU and Metal inventories.

Pointwise traversal and its control checks are owned by
`src/execution/candidate_stage.jl`. The shared fixture
`test/fixtures/empty_pointwise_contracts.jl` checks empty-domain preparation,
untouched backing storage, nonempty publication, and runtime-prefix diagnostics
through the ordinary CPU and Metal inventories.

Canonical collection ordering is owned by
`src/execution/collect_physical_support.jl`. The shared
`test/fixtures/collect_canonical_order_contracts.jl` checks reverse tuple-key
ordering across workgroup boundaries, partial participation, empty gated
collections, and duplicate-identity failure atomicity on CPU and real Metal.
Run these checks with `--check-bounds=yes` when changing shared-memory sorting;
disabled bounds checks must not substitute for correct padded-lane behavior.

Closed callable admission is owned by
`src/execution/stage_program_kernelabstractions.jl`. Its narrowly enumerated
pure unary floating-point calls use public method reflection to require the same
Base-owned native math module as the Float64 method, a concrete `AbstractFloat`
argument and the same return type. Extensions undergo
ordinary recursive effect analysis; this does not admit arbitrary foreign calls.
`test/fixtures/trigonometric_stage_contracts.jl` exercises real sine/cosine
publication through ordinary CPU and Metal stages, while
`test/test_stage_preparation.jl` retains unsafe-capture/access rejection tests.

Focused commands shorten the edit loop; they are not a second test inventory
or release gate. Before handoff, run the complete suite of every changed
package. Add the integration suite when a package boundary, extension, SciML
lifecycle, or persistence behavior changed; add the strict documentation build
when a public name, docstring, example, or manual page changed. Applicable
real-GPU tests are required when device execution, adaptation, admission, or
lifetime changed.

Run the package suite and its scientific witnesses from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=test/scientific_witnesses test/scientific_witnesses/runtests.jl
```

Build documentation with:

```sh
julia --project=docs docs/make.jl
```

The package suite includes Aqua and ExplicitImports checks. Real-Metal
qualification lives in `test/metal` and uses Julia 1.12.6.

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

The manual executes LocalMath examples for relations, storage, scientific
recipes and domain compilers. Complete CPM models belong to PottsModels;
visualization belongs to MakiePotts.

## Continuous integration

Every pull request runs the complete owning package suite and strict manual
build. Scientific and real-Metal checks run unless the whole PR diff contains
only the explicitly listed non-executable prose/metadata paths. Unknown paths,
executable documentation, source, tests, examples and dependency/workflow changes
retain the broader checks. Manual dispatch and main pushes run those checks too.
The workflow records the selected checkout revision; dispatch can select a
candidate branch without changing main. Ordinary dependency compatibility stays
broad rather than becoming an exact-replay claim.

Hosted `macos-15` runners execute the Metal suite, which rejects unavailable
hardware. PRs run the macOS API smoke; main and manual runs use the complete
macOS suite instead of duplicating that smoke. Benchmarks remain diagnostic
and run when their measured path changes.

Run real-Metal semantic tests independently from performance measurements:

```sh
julia --project=test/metal --startup-file=no -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate(); include("test/metal/runtests.jl")'
```

The runner includes LocalMath stage, publication, correctness and scientific
recipe witnesses; performance campaigns remain separate. Use Julia 1.12.6 for
this Metal profile. The runner owns the test inventory; do not duplicate it in
a separate orchestration script.

Current specifications and decisions live under `spec/`. Historical interviews and evidence under
`design/audits/`, and retired qualification scripts under `scripts/archive/`, document earlier
repository states but are not active development gates.
