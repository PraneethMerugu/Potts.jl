# Repository development rules

These instructions apply to the complete repository.

## Semantic naming

- Development chronology is never product semantics. Do not introduce live
  product names, runtime modes, configuration, serialized fields, or execution
  paths whose identity is a phase, gate, migration, provisional generation, or
  old/new development state.
- Name live code after durable scientific, mathematical, numerical, hardware,
  protocol, ownership, or execution meaning.
- Classify meaning rather than spelling. Scientific phases, mathematical or
  compiler candidates, real algorithm/backend choices, checkpoint and importer
  semantics, test-only independent oracles, package versions, and durable
  schema/protocol versions are allowed.

## Direct cutovers

- Replace temporary names and representations atomically across implementation,
  tests, current documentation, examples, configuration, extensions,
  serialization boundaries, and downstream consumers.
- Delete the replaced name or representation in the same change. Do not add
  compatibility aliases, deprecations, feature flags, old/new selectors, or
  parallel migration implementations.
- Preserve genuine features and observable scientific behavior unless an
  accepted decision explicitly changes them.
- Validate changes with the ordinary Julia package, integration,
  documentation, quality, and applicable GPU tests. Do not create custom gate
  scripts for naming or cutover policy.

## Ordinary development workflow

- No evidence hashes, milestone scripts, frozen pass/fail timing gates, or
  committee paperwork.
- Use ordinary Julia tests, integration tests, documentation builds, relevant
  GPU tests, and focused reproducible benchmarks. Benchmarks guide engineering
  decisions and support performance claims; machine-dependent wall time is not
  a brittle development acceptance threshold.
- Reviews are normal technical review, not a parallel qualification system.
  Historical specifications, audits, and evidence may describe earlier
  milestone processes, but they do not impose active development ceremony.

## Prevent architectural and test debt

- Every scientific or execution fact has one production owner. Domain packages
  own scientific meaning, LocalMath owns spatial and publication meaning, and
  the KernelAbstractions path owns physical execution. Inspection derives from
  those authorities; it must not store a second copy for reporting or testing.
- A new abstraction must remove an existing authority or enable demonstrated
  reuse across real consumers. Do not add speculative IRs, adapter hierarchies,
  registries, schedulers, capability taxonomies, or report objects.
- Keep prototypes outside production source. When a prototype qualifies,
  transplant its result into the sole production path and delete the prototype
  in the same change.
- Downstream packages use public interfaces. Private implementation details are
  tested within their owning package and are not made into cross-package
  contracts.
- Separate functional support from stronger guarantees such as exact replay,
  checkpoint portability, deterministic conflict resolution, and performance.
  Claim each guarantee only where an ordinary test or reproducible benchmark
  directly demonstrates it.
- Tests assert observable scientific and operational contracts: numerical
  results, ordering, failure atomicity, deterministic behavior, continuation,
  ownership, allocation, compilation behavior, and CPU/GPU parity as relevant.
  Do not assert milestone metadata, implementation slogans, arbitrary device
  identifiers, duplicated evidence fields, or incidental struct layout.
- Maintain one production implementation plus an independent scientific oracle
  where an oracle is needed. An oracle must not become a second executor.
- Keep ordinary compatibility environments broad. Pin a complete environment
  only when the stronger claim itself requires exact dependency replay.
- Before completing a change, ask: did it create another authority or path; did
  chronology enter a live name; does a test depend on an incidental detail; is
  a downstream package using private API; did a replaced implementation remain;
  do CPU and GPU still share the same semantic KernelAbstractions path; and is
  every claimed guarantee directly exercised? Resolve any yes before handoff.

The normative project authority is `spec/project-charter.md`; human workflow
guidance is in `CONTRIBUTING.md`. Historical milestone terminology may remain
in specifications, design records, audits, and archived development evidence.
