# Symbolic Potts V1 Implementation Control

Date started: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: active; explicit owner implementation send-off received

## Authority

The owner gave explicit implementation send-off on 2026-07-30 with: “u may start”.

Implementation is governed by:

1. [`spec/symbolic-potts-v1-compiler-construction.md`](../../spec/symbolic-potts-v1-compiler-construction.md);
2. [`spec/symbolic-potts-v1-architecture-redirection.md`](../../spec/symbolic-potts-v1-architecture-redirection.md);
3. [`spec/symbolic-potts-v1-consolidation.md`](../../spec/symbolic-potts-v1-consolidation.md);
4. [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md); and
5. compatible scientific specifications and accepted decisions.

G0 through G9 in CCV1-022 are the sole execution order. This record tracks implementation state
only. It does not redefine semantics or create CI/evidence authority.

## Baseline ownership

The pre-G0 Git parent is `ac23160` (`Build Symbolic Potts V1 runtime slice`).

At send-off, the worktree contained 360 entries:

- 278 tracked deletions;
- 61 tracked modifications; and
- 21 untracked files.

These paths are the accumulated Symbolic Potts V1 prototype, consolidation, architecture
redirection, compiler specification, test fixtures, package integrations, and removal of obsolete
benchmark/oracle/engine/authoring surfaces from this branch. No unrelated path cluster was found.
All are preserved in the G0 checkpoint rather than discarded, reset, or reconstructed from memory.

The deleted parent sources remain recoverable from Git history. A temporary clone of `main` may be
used read-only for algorithm and test-intent inspection only.

## Surviving implementation and test authority

The baseline prototype currently concentrates execution in:

- `src/completion`;
- `src/compiler`;
- `src/runtime`;
- `src/statements`;
- `src/symbolics`;
- `src/systems.jl`;
- `lib/CorePotts/src/program/v1.jl`; and
- `lib/CorePotts/src/rng/semantic.jl`.

The prototype is test and semantic evidence, not the accepted final architecture. In particular,
its named activity, field, history, elongation, relationship, and observation plans are replacement
targets under CCV1-006, CCV1-012, CCV1-017, and CCV1-018.

Current reusable test authority is concentrated in:

- `test/test_system_contract.jl`;
- `test/test_statements_and_traversal.jl`;
- `test/test_completion_and_diagnostics.jl`;
- `test/test_compilation_and_inspection.jl`;
- `test/test_units_and_parameters.jl`;
- `test/test_initial_problem_remake.jl`;
- `test/test_runtime_solution_sii.jl`;
- `test/test_checkpoint.jl`;
- `test/test_wortel_fixture.jl`;
- `test/test_merks_fixture.jl`;
- `test/test_focal_fixture.jl`;
- `test/test_package_quality.jl`;
- `lib/CorePotts/test/test_program_v1.jl`; and
- the five current integration fixtures.

Deleted parent tests may be mined for independently useful semantic intent. They must not be
restored as a legacy oracle, expected-output archive, or competing runtime authority.

## Pre-checkpoint baseline execution

The root package baseline was executed before the G0 checkpoint with:

```text
/Users/praneethmerugu/.julia/juliaup/julia-1.12.6+0.aarch64.apple.darwin14/bin/julia \
    --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
```

It completed in 5 minutes 16.4 seconds with 272 passes, no assertion failures, and one error.
`initial_problem` reaches `CorePotts.initialization_bounded`, which calls the keyword-only
`RNGAddress` constructor with an obsolete positional `Int64` at
`lib/CorePotts/src/program/v1.jl:1056`. This is an inherited prototype defect, not a moved
baseline. It was corrected after the G0 checkpoint by naming the final `draw` keyword and adding
a direct semantic-RNG initialization regression.

## G1 evidence

G1 introduced:

- a frozen, indexed, host-only source graph with hierarchy, source order, registry snapshot,
  qualified references, provenance, and a stable structural key;
- an ordered normalized term DAG whose pure-node interning is record-local;
- versioned operation transfer methods with validation;
- explicit analyzed fact tables and descriptor candidates;
- normalization and analysis verifiers with qualified diagnostics; and
- downstream `ExternalWeightedSiteTerm` and `ExternalBoundedPairTerm` fixtures authored in a
  separate test module through public registration and lowering protocols.

Qualification:

- G1 focused compiler tests: 33 passed;
- CorePotts focused program tests: 43 passed;
- initial-state/problem/remake tests: 24 passed;
- Wortel fixture: 14 passed;
- Merks fixture: 8 passed; and
- complete ordinary root package suite: 313 passed in 6 minutes 15.2 seconds.

The full-suite probe initially exposed state variables represented as symbolic calls. The host
normalizer now resolves declared variables and parameters before operation lookup, preserving
state identity without treating `activity(t)` or a field variable as an extension operation.

## Gate state

| Gate | State | Establishing evidence | Checkpoint | Review |
|---|---|---|---|---|
| G0 authority and recovery baseline | `passed` | branch/worktree inventory; specification validation; baseline execution | `0cc013ae8086` | none |
| G1 host compiler facts | `reopened` | R1.5 proved declared connectivity semantics are absent from lowering and explicit draw identities are occurrence-set ordinals | `eb8a37a` | R1.5 returned G1 |
| G2 descriptor/group/evaluator/state/workspace | `reopened` | prior boundary passed; must requalify repaired connectivity and draw-identity representations | `3e131d97e352` | R1.5 returned through G2 |
| G3 sequential reference/finite transitions | `reopened` | candidate passed 305/305 focused tests but R1.5 found descriptor-authority, oracle, allocation, accounting, and seam defects | `d8f00c352230` | R1.5 returned G3 |
| G4 checkerboard/first GPU witness | `pending` | blocked until R1.5 clears G3 | pending | none |
| G5 trackers/relationships/lifecycle/checkpoint | `pending` | pending | pending | R2 |
| G6 public integration spine | `pending` | pending | pending | none |
| G7 proof-model reconstruction | `pending` | pending | pending | R3 |
| G8 clean break/full integration | `pending` | pending | pending | none |
| G9 terminal qualification | `pending` | pending | pending | R4 |

## Reviewer state

| Review | State | Blocking findings | Nonblocking findings |
|---|---|---|---|
| R1 compiler | `passed` | none | none |
| R1.5 sequential authority | `returned` | 1 P0; 2 P1 | 4 P2 |
| R2 execution/concurrency/GPU | `pending` | none | none |
| R3 science | `pending` | none | none |
| R4 terminal | `pending` | none | none |

## Resolved R1 decision questions

R1 must resolve the operation-execution boundary recorded in
[`symbolic-potts-v1-operation-execution-decision.md`](symbolic-potts-v1-operation-execution-decision.md).
The corrected evaluator experiment compared the strongest concrete-callable design against the
CorePotts-owned ordinary-operation-tag alternative. The restrained callable hybrid was selected:
ordinary Julia mathematics remains ordinary Julia callables, ordered folds are explicit, and
context/resource-sensitive CPM operations are concrete callable structs. Independent R1
confirmation remains checkpoint-blocking.

## R1 handoff questions

R1 must answer these owner-raised questions explicitly:

1. Is there exactly one production path from a symbolic expression to a concrete callable
   evaluator?
2. Can any alternate evaluator constructor, legacy interpreter, descriptor shortcut, or runtime
   path bypass the frozen host IR, normalized term DAG, versioned `OperationTransfer`,
   `operation_callable`, bounded lowering, and `StaticEvaluator` boundary?
3. Does the current folder organization clearly encode the compiler stages and the CorePotts
   execution boundary?
4. Which folder/file moves are required before G2 can be considered maintainable, given the
   combined responsibilities in the host IR, descriptor lowering, CorePotts descriptor runtime,
   and legacy `program/v1.jl`?
5. Is registered, versioned operation-schema lowering the sole authority by which a function or
   callable can enter an evaluator? The `Base.issingletontype`/`nameof` closure check in
   `storage.jl` may remain only as defense-in-depth; R1 must not treat compiler-generated name
   spelling as certification of device legality.
6. Do the final callable, context, descriptor, state, workspace, and launch arguments compile on
   each claimed backend, with backend capability declared before lowering and no host fallback?
7. Are `StateHandle{Bank}` and `WorkspaceHandle{Bank}` type parameters bounded by a small set of
   true storage representations, rather than resource identity, declaration count, or declaration
   order?
8. Do permanent tests prove that 1, 32, and 1,024 resources sharing a storage class reuse the same
   handle type; resource names never enter handle types; declaration reordering does not create
   kernel specializations; and a new shape changes a type only when its storage representation
   truly differs?

R1 should affirm the intended specialization policy explicitly:

- named singleton Julia functions for ordinary mathematics are appropriate;
- empty singleton structs for finite contextual/resource CPM semantics are appropriate;
- `OrderedFold(+)` and `OrderedFold(*)` are justified by explicit ordered arithmetic;
- arbitrary functions and capturing closures cannot enter through model data;
- operation schema, concrete/isbits lowering, declared backend capability, and real backend
  compilation together establish legality; and
- structural facts may control specialization, while user/model names must not.

Folder organization is a review deliverable, not a request to perform speculative moves before
verification. R1 should distinguish:

- G2 files that must be split or moved now to make the single production path obvious;
- legacy `program/v1.jl` organization that is intentionally removed or replaced at G8; and
- cosmetic moves that can wait without weakening compiler ownership.

The organization repair groups compiler sources under `host/`, `lowering/`, and `execution/`,
leaves only orchestration in `compiler/compile.jl`, and splits the mechanism-free CorePotts
boundary under `execution/`. Package-local READMEs record exact include order, stage ownership,
and the single lowering path. Legacy `program/v1.jl` removal remains G8 work.

## G0 checks

Required:

- [x] explicit owner implementation send-off;
- [x] authoritative branch confirmed;
- [x] dirty-worktree ownership inventoried;
- [x] unrelated changes preserved;
- [x] specification links, Markdown fences, clause count, gates, reviews, and send-off boundary
      validated;
- [x] surviving prototype/test authority inventoried;
- [x] complete baseline checkpoint commit (`0cc013ae8086`);
- [x] verify the checkpoint worktree is clean; and
- [x] mark G0 `passed` and G1 `in_progress`.

Commands used:

```text
git branch --show-current
git status --short
git status --porcelain=v1
git diff --stat
git diff --check
git log -5 --oneline --decorate
```

## Reopen history

R1 first review returned G2 on 2026-07-30 with six P1 findings:

1. dual proposal authority caused executable specialization to grow with occurrence count;
2. external operation and descriptor construction did not work end to end;
3. state and workspace were metadata shells;
4. adaptation tested a descriptor rather than the production group-launch boundary;
5. evaluator qualification omitted required depth, occurrence, group, generated-code, and
   stochastic dimensions; and
6. analyzed totality facts were not enforced before launch.

The same review reported one P2 concerning lowering diagnostics and inspection detail. G3 remained
stopped. The repair:

- made `core_program.descriptor_plan` the sole proposal descriptor authority and removed the four
  occurrence-shaped proposal tuples from `CompiledPottsProgram`;
- added public, versioned external operation, descriptor, and workspace construction protocols and
  made the neutral site fixture use all three;
- resolved qualified state/workspace identities to compact handles, attached those requirements to
  group launches, and demonstrated shared workspace reuse;
- separated host schemas from the adaptable `DescriptorLaunch`, tested a transforming synthetic
  adaptor, and executed a 32-instance production descriptor buffer on Metal;
- ran and recorded the complete recursive-tree/bounded-n-ary/static-SSA matrix across independent
  shape depth, 8/32/64 nodes, 1/32/1,024 occurrences, and 1/4/8 distinct groups on CPU and Metal;
- lowered `log`, `sqrt`, Bernoulli, Uniform, and Normal domains into init/remake parameter
  constraints and rejected runtime-state-dependent partial domains; and
- added qualified typed diagnostics plus group splits, kernel families, state/workspace counts,
  validation groups, and evaluator-node counts to inspection.

Repair qualification:

- G1/G2 focused tests: 33 and 64 passes respectively;
- ordinary root `Pkg.test()`: 378 passes in a fresh resolved environment, including Aqua and
  ExplicitImports;
- CorePotts `Pkg.test()`: all 56 assertions passed, including package quality;
- evaluator experiment: complete CPU and functional Metal matrices passed with exact fixed
  stochastic vectors and zero warmed evaluator allocation;
- production Metal witness: 32 adapted external descriptors executed from a concrete homogeneous
  `MtlVector` with compact state/workspace handles and returned 32 correct `17.5f0` values; and
- `git diff --check`: clean.

The second R1 review confirmed that the six first-review findings were materially repaired, including
independent direct built-in `N=1/32/1,024` and parameter-only fixed-`G` reproduction. It nevertheless
returned G2 with four narrower P1 findings:

1. central reporting still accessed a descriptor's undocumented `evaluator` field instead of a
   complete opaque descriptor protocol;
2. state/workspace schemas and handles lacked real typed runtime storage, allocation, adaptation,
   settled export, and logical codec behavior;
3. the evaluator experiment did not use identical tags/context/occurrence data or genuine semantic
   RNG vectors and did not compile real `G=1/4/8` aggregates; and
4. the production proposal loop began generic sequential descriptor execution before R1 cleared.

It also retained a P2 for downstream-qualified inspection and permanent direct built-in
`N=1/32/1,024` plus parameter-only coverage. This is a bounded G2 gate failure, not an architecture
invalidation. G3 remains stopped and no R1 checkpoint exists.

## Second-review repair

The four second-review findings and its P2 were repaired without advancing G3:

- central planning/reporting now uses a complete opaque descriptor protocol, including adaptation,
  evaluator node count, source handle, inspection, checkpoint policy, codec, and reconstruction;
- state and workspace layouts now contain typed bank/slot handles, schema-owned allocation,
  validation, adaptation, reset, settled export, inspection, and logical checkpoint codecs;
  workspaces are structurally absent from checkpoint state;
- the evaluator experiment now starts from one shared semantic IR, uses identical concrete
  occurrence/context data, genuine semantic RNG addresses and Philox words, real homogeneous
  buffers at `N=1/32/1,024`, and real heterogeneous launch tuples at `G=1/4/8`;
- the premature generic descriptor execution path was removed from the production proposal loop,
  keeping all G3 runtime integration stopped;
- downstream-qualified inspection works through an opaque descriptor that has no `evaluator`
  field; and
- direct built-in `N=1/32/1,024` and parameter-only fixed-specialization tests are permanent
  ordinary tests.

The newly raised operation-execution question was resolved from the corrected experiment. The
production evaluator now stores named singleton Julia functions or concrete contextual callable
structs, plus `OrderedFold` for explicit ordered variadic evaluation. The boundary rejects closures.

Repair qualification:

- G2 focused compiler boundary: 87/87 passed;
- ordinary root `Pkg.test()`: 401/401 passed in 8 minutes 48.2 seconds;
- CorePotts package suite: passed, including the external callable extension and package-quality
  checks;
- corrected evaluator CPU matrix: exact semantic RNG words and no candidate failures;
- corrected evaluator Metal matrix: exact semantic RNG words; recursive and bounded-nary tag and
  callable candidates passed, while the recorded wide static-SSA failures support its rejection;
- production Metal boundary: 32 descriptors plus adapted descriptor/state/workspace/parameter
  buffers returned 32 exact `17.5f0` values; and
- `git diff --check`: clean.

G3 remains stopped until independent R1 rereview passes.

## Final R1 return and repair

The final R1 audit answered the owner's single-path question with “no” and returned two P1s:

1. `registered_descriptor` could ignore the compiler-supplied evaluator and define arbitrary
   proposal execution; and
2. state/workspace bank numbers were assigned by first encounter, allowing resource renaming or
   reordering across storage classes to alter handle types.

The repair:

- replaces downstream descriptor construction with `registered_descriptor_payload`;
- makes `CorePotts.ProposalDescriptor` the universal symbolic proposal descriptor and sole owner of
  `evaluate_static`;
- supplies registered hooks no evaluator and accepts only inert isbits payload metadata;
- rejects functions, static expressions/evaluators, and contextual operations in payloads with a
  qualified diagnostic;
- adds an adversarial registered extension that attempts evaluator injection and must fail;
- derives bank numbers from a stable sort of storage-class representations before assigning
  value-level slots;
- adds 1,024-state and 1,024-workspace same-class growth checks plus mixed-class rename/reorder and
  public compile checks; and
- replaces the repeated 1,024-term full symbolic compile in ordinary tests with real 32/1,024
  descriptor grouping/launch-plan checks, leaving the full CPU/Metal evaluator matrix as explicit
  qualification.

The focused G2 suite passed 99/99 after this repair. A subsequent independent rereview confirmed
that the symbolic-to-evaluator path is singular and unbypassable through the supported descriptor
extension contract, but returned two further adversarial P1s:

1. a nested operation with `gpu = false` was hidden by an admitted `+` root because backend
   admission was not propagated through the expression DAG; and
2. sorted ordinal bank numbers were stable only for a fixed representation set, so adding a class
   that sorted earlier changed an existing representation's handle type.

The bounded follow-up repair:

- folds CPU/GPU admission transitively from every operand and preserves descendant rejection
  reasons at enclosing nodes and descriptors;
- adds a registered external CPU-only operation nested below an admitted root and proves the
  compiled descriptor rejects GPU execution;
- replaces ordinal handle type parameters with canonical `StateStorageRepresentation` and
  `WorkspaceStorageRepresentation` marker types;
- stores the physical bank ordinal and slot as values, and uses a generated representation lookup
  to retain inferred, allocation-free access to heterogeneous bank tuples;
- preserves representation markers explicitly through `Adapt`, after the first Metal attempt
  exposed and localized a generic reconstruction failure;
- proves exact 1/32/1,024 same-representation handle and kernel-strategy stability, rename/reorder
  stability, same-representation shape stability, and add/remove-class stability;
- moves the full 1/32/1,024 symbolic compilation matrix to
  `scripts/qualify_g2_specialization_growth.jl`, while ordinary tests retain cheap structural
  fixed-`G` coverage; and
- keeps the backend contract shared and vendor-neutral, using Metal only as the selected witness.

Requalification evidence:

- focused G2: 120/120 in 37.0 seconds;
- explicit full specialization-growth qualification: 5/5 in 2m41.6s;
- CorePotts package suite: passed, including package quality;
- Metal shared boundary: 32 device descriptors with device state/workspace buffers and exact
  `17.5f0` output; and
- root `Pkg.test`: 434/434 in 5m52.7s.

The large private stage files remain a nonblocking organization P2. Directory ownership and the
single entry path are already explicit; the files will be mechanically decomposed before
substantial G3 growth without adding another compiler entry point. G3 remains stopped pending the
next independent R1 verdict.

## Payload specialization return and repair

The next independent R1 challenge confirmed the prior backend and bank repairs, the singular
symbolic-to-evaluator path, device legality, test tiering, and legacy quarantine. It found one new
supported-path P1: `registered_descriptor_payload` could return an isbits type parameterized by
`context.source.identity.local_id`. Because the universal proposal descriptor contains the payload
type and grouping includes descriptor type, two otherwise identical occurrences could become two
kernel groups.

The repair freezes `descriptor_payload_type` in every registered statement schema version,
requires it to be one concrete isbits type, propagates it through registered provenance, and
requires exact equality with `typeof(payload)` before constructing or grouping the descriptor.
Occurrence metadata remains in fields. The neutral fixture now attempts a
`NameParameterizedPayload{term_name}` and receives the qualified
`descriptor_payload_type_mismatch` diagnostic.

Focused evidence after this repair:

- descriptor/compiler boundary: 124/124 in 42.9 seconds; and
- statement-registry plus completion/provenance: 66/66 in 22.5 seconds.

Exact-tree requalification after the payload repair:

- root `Pkg.test`: 441/441 in 4m32.3s;
- explicit full specialization-growth qualification: 5/5 in 2m45.8s; and
- shared Metal boundary: 32 device descriptors with device state/workspace buffers and exact
  `17.5f0` output.

CorePotts had no source change after its passing package suite. G3 remains stopped pending the
independent rereview verdict.

The final payload-contract rereview confirmed the documented registration path was closed, then
found two adjacent authority defects:

1. ordinary public statement kwargs could inject `__registered_origin`, and completion trusted the
   marker without authenticating it against the supplied registry; and
2. canonical `DataType` encoding retained only module and outer name, so structurally different
   parameterized payload types could collide in completed fingerprints.

The bounded repair rejects all double-underscore internal option names in public statement
constructors, authenticates every internal origin against the exact frozen registry definition,
and rejects missing or field-mismatched origins with `unauthenticated_registered_origin`.
Canonical concrete-type encoding now recursively includes type parameters. Permanent tests cover
public origin injection, a private-marker/empty-registry attempt, a matching-schema but mismatched
payload-type attempt, direct canonical inequality, and distinct end-to-end completed fingerprints.

Focused evidence currently passes:

- statement/registry/completion provenance and fingerprint checks: 71/71; and
- G2 descriptor authority: 124/124.

Exact-tree requalification after these repairs:

- statement/registry/completion provenance and fingerprint checks: 73/73;
- G2 descriptor authority: 124/124;
- root `Pkg.test`: 448/448 in 4m35.2s;
- explicit full specialization-growth qualification: 5/5 in 2m39.5s; and
- shared Metal boundary: 32 device descriptors with device state/workspace buffers and exact
  `17.5f0` output.

G3 remained stopped pending the independent rereview verdict.

## R1 pass and isolated-suite repair

Independent R1 returned `PASS` with zero P0 and zero P1 findings. It confirmed exactly one
supported production path from a frozen symbolic source graph through the normalized/analyzed DAG,
versioned operation resolution, bounded immutable expression, `StaticEvaluator`, universal
`ProposalDescriptor`, and descriptor launch. It also confirmed that no supported extension hook,
legacy interpreter, alternate evaluator constructor, or runtime shortcut bypasses that path.

The review retained two P2 findings. First, the G2 test selected the first operand of a
commutative multiplication when replacing a parameter default. That was a positional test bug,
not a production evaluator defect. The test now locates and replaces `ParameterExpression` nodes
structurally, and the truly standalone G2 suite passes 124/124 in 42.1 seconds. Second, the large
private stage files must be mechanically split by ownership before substantial G3 growth, without
adding an entry point.

The organization P2 is closed. `host/ir.jl` is now four ordered files for source freezing,
operation authority, normalization, and analysis. `lowering/descriptors.jl` is now four ordered
files for static evaluators, storage layouts, proposal descriptors, and constraints. CorePotts'
`descriptor_runtime.jl` is now five ordered files for static evaluation, storage schemas, storage
runtime, descriptor protocol, and descriptor plans. The split introduced no public or complete
pipeline entry point. Its largest reviewed unit is 510 lines.

Post-split qualification passed:

- package load and all extension precompilation;
- standalone G2 descriptor/compiler boundary: 124/124 in 45.3 seconds;
- complete CorePotts package suite, including package quality; and
- root `Pkg.test`: 448/448 in 4m37.9s.

R1 cleared the G2 checkpoint, both R1 P2 findings are repaired, and G3 may begin.

## G3 preflight return to G1/G2

Before runtime integration, an independent read-only G3 preflight challenged the scientific meaning
of the descriptor evaluator against controlling ARV1-003 and CCV1-003/021/024. It found a P0 that
the earlier R1 evaluator-boundary review did not cover:

- the stored and analyzed taxonomy still uses proposal-delta-first `ProposalEnergy` rather than
  conservative `HamiltonianTerm`;
- high-level constructors currently author local deltas directly;
- `affected_region` is only a generic locality record, not a compiler-proven energy-region plan;
  and
- the universal descriptor contains one evaluator and no typed before/after Hamiltonian evaluation
  policy.

The sequential proposal loop must not consume those evaluator values as Hamiltonian deltas. G3 is
therefore stopped, G1 and G2 are reopened, and R1 must be repeated after the taxonomy,
affected-region analysis, typed Hamiltonian plan, neutral external delta, algebra, and backend
evidence are repaired. The earlier checkpoints remain recovery points for the valid expression,
storage, grouping, provenance, and device-boundary work; they are not complete gate evidence.

## Repaired G1 checkpoint

The reopened G1 boundary now stores conservative `HamiltonianTerm` statements as an energy
domain, a bound anchor, and one energy expression. The removed `ProposalEnergy` name has no alias
or wrapper. The closed domain vocabulary is limited to sites, cells, canonical contacts, and
bounded relationship edges. Volume and elongation are cell energies, contact adhesion is a
canonical-contact energy, eligible relationship elasticity is a relationship energy, chemotaxis
and Act are drives, and local connectivity remains a constraint.

Host analysis independently derives a finite affected-anchor fact from the domain, the expression's
actual anchor reads, operation-locality transfer facts, and resolved structural bounds. It proves
target-site, source/target-cell, incident-contact, or incident-relationship plans; a registered
extension may declare the expected class, but a false declaration is rejected after the compiler's
proof. Contact bounds resolve the declared finite lattice relation and relationship bounds resolve
the declared maximum degree. Anchor names and resource identities are retained only as host values;
the new candidate structural contribution contains only domain/anchor classes and the proven
affected-plan class/bound.

Permanent rejection tests cover proposal-context reads, stochastic draws, a foreign bound anchor,
finite-spatial reads without a closed affected rule, domain/anchor mismatch, a forged mutating
Hamiltonian payload, and a false registered affected-region assertion. Focused checkpoint evidence
passes:

- public statement/traversal tests: 24/24;
- system contract tests: 40/40;
- completion, provenance, and diagnostics tests: 49/49; and
- expanded G1 host compiler facts and rejection suite: 62/62.

G2 remains reopened. This G1 result does not authorize G3: the executor still needs immutable
before/after views, structural domain and affected plans, local/global energy equivalence, and fresh
inference, allocation, specialization-growth, Metal, and independent R1 clearance.

## Repaired G2 candidate

The repaired G2 boundary preserves the previously cleared normalized DAG, versioned operation
resolution, bounded callable evaluator, universal descriptor, grouping, representation-canonical
state/workspace handles, adaptation, diagnostics, payload contract, capability analysis, and
backend launch work. It adds no second evaluator and does not connect descriptors to the G3
proposal loop.

`HamiltonianRole` now carries a structural energy-domain plan and a structural affected-anchor
plan. Kind, relation, relationship, source, and occurrence identities remain compact values.
Lowering resolves bound energy anchors to contextual callable objects and resolves kind and
relationship-payload selectors to compact values. Every Hamiltonian proposal evaluation constructs
immutable before and after views over the unchanged runtime, enumerates only the compiler-proven
finite affected anchors, evaluates the same stored energy expression in each view, and subtracts
before from after.

The closed V1 plans are:

- one target-site anchor for site energies;
- at most the distinct source and target cells for cell energies;
- canonical incident contacts, bounded by the resolved spatial relation; and
- unique active incident relationship edges, bounded by the resolved maximum degree.

Contact anchors are canonicalized and deduplicated without a collection. Relationship edges are
visited once. Runtime bounds defend the host proof. Descriptor contributions are written into
source-indexed caller-owned storage, then folded in frozen source order, so heterogeneous group
execution order cannot change floating-point contribution order. Descriptor source handles are
required to be unique in V1, preventing occurrence overwrite.

Permanent scientific tests use independently written full-energy implementations only as test
oracles. They establish local descriptor delta equality with `H(after) - H(before)` for site,
volume, contact, elongation, and eligible focal-point relationship elasticity; constant-offset
cancellation; affected-anchor completeness over all differing cardinal proposals in the neutral
fixture; unchanged runtime ownership and volumes; group-order-independent source contributions;
and canonical source-order folding. Act and chemotaxis remain drives, connectivity remains a
constraint, and relationship topology changes remain processes.

Qualification on the candidate tree:

- preserved standalone G2 descriptor/compiler boundary: 124/124;
- repaired local Hamiltonian equivalence and structural-specialization suite: 59/59;
- Merks elongation fixture: 11/11, including independent global energy and zero warmed allocation;
- focal-point-plasticity fixture: 19/19, including independent global energy and zero warmed
  allocation;
- full symbolic specialization growth at 1/32/1,024 occurrences: 5/5 in 2m57.7s;
- selected bounded callable evaluator on CPU: inferred `Float32`, zero `Any` slots, zero ordinary
  warm allocation, exact semantic RNG words, fixed occurrence specialization, and deliberate
  `G=1/4/8` group growth;
- shared Metal boundary: 32 adapted external Hamiltonian descriptors with device parameter,
  state, and workspace buffers returned exact `17.5f0` values;
- full evaluator experiment on functional Metal: exact semantic RNG words, concrete inference,
  selected bounded callable compilation over all tested shapes, fixed specialization through
  1,024 occurrences, and measured device-code growth only with heterogeneous group count;
- complete CorePotts package suite: passed, including Aqua; and
- complete root package suite: 542/542 in 5m19.0s, including Aqua and ExplicitImports.

The wide static-SSA comparison still fails selected Metal shapes and remains rejected; that is
comparison evidence rather than a candidate failure. The Metal environment was read from the
`main` branch into a temporary directory and used only to supply the vendor package. The code under
qualification came from this branch.

G3 remains stopped. This candidate requires a fresh independent R1 clearance of the exact
checkpoint before any proposal-loop integration or Wortel/Merks migration.

## First repaired-G2 R1 return

Independent R1 review of checkpoint `598493b` returned the repaired G2 boundary with four P1
findings and one P2 finding:

1. payload-specialized external methods could replace descriptor evaluation on a supported
   `ProposalDescriptor` subtype;
2. contact-relation and relationship-state resource handles were lowered but the Hamiltonian
   runtime ignored them;
3. Hamiltonian state reads selected a legacy value by slot while ignoring the handle's canonical
   storage representation; and
4. relationship Hamiltonians were partial when a proposal extinguished an endpoint and found
   affected edges by scanning full relationship capacity rather than the proven incident bound.

The P2 identified a dead `ProgramExpression` lowering/evaluation vocabulary that looked like a
plausible alternate production path. These findings were localized boundary failures. They did
not invalidate the normalized DAG, callable evaluator, universal descriptor, grouping, storage
schema, payload, capability, adaptation, diagnostic, or backend designs. G3 remained stopped.

## Current repaired-G2 candidate

The bounded repair keeps the cleared G2 machinery and closes the returned defects:

- production plans accept only compiler-owned universal `ProposalDescriptor` values and invoke
  their stored evaluators through non-extensible CorePotts implementation paths; public metadata
  and checkpoint protocol calls cannot replace execution;
- the compiler materializes one validated, adaptable, value-level domain-resource table, and
  contact and relationship Hamiltonians resolve the exact frozen resource handle from that table;
- Hamiltonian state reads use canonical representation-typed banks and value-level slots in the
  runtime auxiliary state;
- immutable after views make extinct cell and relationship anchors absent from their energy
  domains, so their after energy is exactly zero;
- relationship runtime state maintains a bounded, sorted incident-edge index; affected-edge
  enumeration merges the old/new endpoint lists in canonical order without warm-path allocation;
- descriptor contributions remain source-indexed and are folded in canonical frozen source order;
  and
- the dead `ProgramExpression`/`ProgramCall` evaluator and lowering vocabulary has been removed.

Permanent adversarial tests cover bound relation selection, representation-bank selection,
payload-method execution bypass, extinct cell and relationship anchors, bounded canonical
incident-edge union, warm allocation, and absence of the dead evaluator vocabulary.

Exact-tree qualification after the repair:

- repaired R1 adversarial boundary: 20/20;
- descriptor/compiler boundary: 126/126;
- local Hamiltonian equivalence and structural specialization: 59/59;
- focal-point-plasticity and Merks fixtures: 19/19 and 11/11;
- complete CorePotts package suite: passed, including Aqua;
- ordinary root `Pkg.test()`: 564/564 in 5m45.0s, including Aqua and ExplicitImports;
- full symbolic specialization growth: 5/5 in 2m40.7s;
- shared Metal boundary: 32 adapted production Hamiltonian descriptors with device parameter,
  state, and workspace buffers returned exact `17.5f0`; and
- the fail-closed CPU and Metal evaluator matrix passed the selected concrete-callable bounded-nary
  design across all tested shapes, semantic RNG words, 1/32/1,024 occurrences, and 1/4/8 groups.

The evaluator qualification's private comparison descriptors now adapt through their own test
path rather than the production `ProposalDescriptor` adapter. The script exits nonzero if the
selected design fails; rejected comparison candidates may still report nonblocking failures.

Fresh independent R1 review of the exact checkpoint is still required before this section may
record G2 as passed. No G3 integration or Wortel/Merks migration is authorized meanwhile.

## Evaluator-dispatch R1 return and repair

Fresh independent R1 review of exact checkpoint `d9ffab1` confirmed the four preceding P1 repairs,
the removal of the dead alternate evaluator, the production specialization policy, and the
backend-agnostic Metal witness. It returned G2 for one adjacent P1: production still called the
public `evaluate_static` generic, so an external module could specialize that method for the exact
lowered evaluator type and replace the compiled result. The reviewer reproduced `17.5f0` becoming
`12345.0f0` without changing lowering or the descriptor.

The bounded repair adds a private CorePotts expression walker used by descriptor launches,
constraint validation, descriptor probes, and Hamiltonian anchor evaluation. It invokes built-in
context and resource semantics through compiler-owned paths and invokes registered concrete
callables directly as the deliberate semantic extension point. Public `evaluate_static`,
`evaluate_expression`, and `execute_operation` remain probe conveniences but are not production
dispatch points. A permanent adversarial test specializes all three public functions, observes
their forged values, and proves the same production Hamiltonian delta remains unchanged.

The review's three P2s were also closed without expanding the gate:

- `compile.jl` is now 176 lines of orchestration; compilation coverage moved to
  `host/coverage.jl`, while manifests, external I/O, initial values, and time contracts moved to
  `execution/manifests.jl`;
- public state/workspace layout constructors now assign value-level bank ordinals from the same
  canonical representation ordering as production lowering; and
- the expensive evaluator qualification now fails on selected-design inference, `Any` slots,
  warm allocation, and bounded host/device generated-code growth, while remaining outside
  ordinary `Pkg.test()`.

Qualification currently completed on this repair:

- repaired R1 adversarial boundary: 24/24;
- complete CorePotts suite: passed, including the internal evaluator inference assertion,
  canonical public layout tests, and Aqua; and
- ordinary root `Pkg.test()`: 568/568 in 6m42.8s, including Aqua and ExplicitImports;
- full specialization growth: 5/5 in 2m56.0s;
- the fail-closed CPU evaluator matrix passed all selected-design inference, allocation,
  occurrence, group, and generated-code bounds;
- the shared Metal boundary executed 32 adapted production descriptors with device parameter,
  state, and workspace buffers and returned exact `17.5f0`; and
- the fail-closed Metal evaluator matrix passed all selected-design checks over the tested
  expression shapes, semantic RNG words, 1/32/1,024 occurrences, and 1/4/8 groups.

Exact-checkpoint R1 rereview remains required. G3 remains stopped.

## Parameter-access R1 return and repair

Fresh independent R1 review of exact checkpoint `5b708bc` reproduced the preceding public
evaluator attacks as sealed, then returned G2 for one adjacent P1: the private production
expression walker still obtained `ParameterExpression` storage through the public
`evaluator_parameters` generic. An external module could therefore specialize that public method
for an exact Hamiltonian evaluation context and forge production delta energy without replacing
the evaluator itself.

The bounded repair leaves the evaluator, normalized DAG, descriptor, grouping, storage, payload,
capability, adaptation, diagnostic, and backend designs intact. Production parameter reads now use
a CorePotts-owned accessor whose built-in contexts read their concrete parameter fields directly;
the public accessor remains a probe convenience only. Permanent adversarial tests override the
public parameter accessor for an exact Hamiltonian context and for the parameter-validation probe.
They demonstrate forged public results while proving that production descriptor delta energy and
production constraint validation remain unchanged. The review's include-order P2 was corrected in
the compiler ownership README without moving code.

Exact-tree qualification after this repair:

- repaired R1 adversarial boundary: 28/28;
- complete CorePotts suite: passed, including Aqua;
- ordinary root `Pkg.test()`: 572/572 in 6m18.1s, including Aqua and ExplicitImports;
- full specialization growth: 5/5 in 2m55.9s; and
- the shared Metal boundary executed 32 adapted production descriptors with device parameter,
  state, and workspace buffers and returned exact `17.5f0`.

The next R1 brief also includes the owner's 177-line candidate critique as untrusted review input.
The reviewer is required to challenge its claims rather than adopt them, including claims about
the singular production path, extension authority, payload specialization, generated-code growth,
backend legality, host/device separation, legacy quarantine, diagnostics, and external-module
openness. At this repair checkpoint, fresh exact-tree R1 clearance was still required and G3
remained stopped; the verdict is recorded below.

## Repaired G2 R1 clearance

Independent R1 returned `PASS` on clean exact checkpoint
`3e131d97e352a9bc8080aa3f6d582299c9281fb5` with zero P0, P1, or P2 findings. It answered the
owner's defining question affirmatively: there is exactly one supported production route from
symbolic source through frozen and normalized compiler facts, registered operation transfer,
concrete static expression, `StaticEvaluator`, compiler-owned `ProposalDescriptor`, homogeneous
`DescriptorLaunch`, and the private compiled evaluator walker.

The reviewer challenged rather than adopted the supplied candidate critique. It found no supported
adjacent evaluator bypass, confirmed canonical representation-derived storage banks, accepted the
current stage/ownership split, verified bounded specialization growth, and found the external
registered fixture crosses the same concrete, inferred, launch, and Metal boundary. It classified
additional GPU vendors as a later backend-agnostic release-matrix concern, final checkerboard GPU
simulation as G4, and legacy runtime removal as G8 rather than G2 blockers.

Independent evidence on the exact checkpoint:

- ordinary root suite: 572/572 in 6m26s;
- complete CorePotts suite: passed, including Aqua;
- full specialization-growth qualification: 5/5 in 2m44s;
- production Metal launch: 32 descriptors over real `MtlArray` parameter, state, and workspace
  buffers returned exact `17.5f0`;
- adversarial exact public overrides altered their public probes but not production delta energy or
  parameter validation; and
- clean worktree and `git diff --check`, with no reviewer edits.

G2 is cleared. G3 may begin without redesigning the cleared evaluator, descriptor, grouping,
storage, capability, adaptation, diagnostic, or backend boundary. Any G3 need to redesign those
facts returns work to G2.

## G3 sequential reference candidate

The G3 implementation candidate passed local qualification at exact implementation checkpoint
`d8f00c352230a3ce3a208312eee82444a93eef55`. The sequential proposal loop now consumes the
compiler-owned descriptor plan: every group writes a structured, source-indexed
`ProposalEvaluation` into caller-owned scratch storage, and the runtime folds Hamiltonian energy,
drive log bias, kinetic modification, and hard constraints in frozen source order. Hamiltonian
values still use the cleared local before/after machinery. Drives, modifiers, and constraints use
the same private compiled evaluator walker. The proposal loop no longer calls named volume,
contact, activity, chemotaxis, relationship, or elongation delta helpers.

The conventional V1 acceptance law is one pure production function shared by runtime and tests. It
rejects nonfinite inputs, treats constraints as hard vetoes, handles favorable, neutral,
unfavorable, underflow, strict-threshold, and zero-temperature seams explicitly, and keeps
Hamiltonian, drive, and modifier roles semantically distinct. Runtime proposal scratch is
nonlogical and reconstructed from the executable rather than checkpointed.

Permanent G3 evidence includes:

- complete finite one-attempt transition matrices over all eight configurations of a periodic
  three-site fixture, every ordered proposal choice, null mass, constraints, source/target
  multiplicities, and independently enumerated two-step composition;
- compiled scripted attempts immediately below, at, and above the acceptance threshold;
- translation symmetry plus Gibbs stationarity and pairwise flux equality on an explicitly closed,
  proven-reversible subspace;
- exact rejection atomicity and incremental-volume comparison with recomputation after every
  admitted compiled attempt;
- fixed raw Philox known-answer vectors, evaluation-order invariance, and a small exhaustive
  semantic-address isolation check;
- a counting-array sentinel proving the neutral external Hamiltonian performs exactly two state
  reads on both 4×4 and 64×64 lattices;
- inferred `ProposalEvaluation{Float64}` and `Bool` return types with zero warmed proposal
  evaluation and scripted-rejection allocation;
- the neutral external registered term through public `PottsProblem`, `init`, `step!`, `solve!`,
  symbolic state indexing, checkpoint, and exact continuation; and
- scale/temperature invariance, energy and temperature monotonicity, finite-input rejection, and
  drive/modifier/constraint acceptance semantics.

Qualification on the exact checkpoint:

- focused G3 suite: 305/305;
- complete CorePotts package suite: passed, including Aqua;
- ordinary root `Pkg.test()`: 877/877 in 6m49.0s, including Wortel, Merks, focal, SciML/SII,
  checkpoint, Aqua, and ExplicitImports; and
- preserved G2 specialization growth: 5/5 in 2m56.9s.

The named legacy helper definitions remain quarantined until their scheduled G8 clean-break
removal; they are not reachable from the production proposal loop.

## R1.5 sequential-authority review gate

R1.5 is a fresh-context, read-only review of the exact G3 implementation checkpoint above. It
must challenge the descriptor-only production path, separation of Hamiltonian/drive/modifier/
constraint roles, acceptance seams, finite transition oracle, RNG identities and address
consumption, null/rejection atomicity, tracker invariants, checkpoint continuation and scratch
exclusion, warm inference/allocation, and the public external fixture. It must also determine
whether G3 changed any cleared G2 compiler boundary without returning that boundary to review.

R1.5 must perform a mechanism-leakage inventory across CorePotts program fields, descriptor roles,
callable and resource-operation identities, capability bits, evaluator dispatch, proposal loops,
checkpoint code, and engine branches. A named scientific mechanism moved behind a descriptor or
singleton operation tag remains a blocking leak. The reviewer must require the same behavior to be
expressible by a PottsToolkit or external callable composed over public structural primitives with
no CorePotts edit. This check is repeated at R4 for the completed tree.

The inventory is semantic, not a name-only search. For every mechanism-shaped branch or datum, the
reviewer records its owner, the invariant that allegedly makes it structural, and the public
primitive that an external implementation would use. The review must challenge at least:

- proposal vetoes or mutations performed before or after the canonical descriptor/request path;
- program fields, checkpoint fields, or capability flags that exist for one scientific mechanism;
- operation tags and callable types whose parameters name biology rather than bounded execution;
- neighborhood traversal whose relation, radius, dimensionality, or boundary rule is selected by
  the engine instead of a compiled resource or affected-anchor plan;
- relationship lifecycle, connectivity, motility, adhesion, volume, elongation, and focal-point
  behavior embedded in engine control flow rather than expressed from primitives;
- backend-specialized branches that reproduce scientific meaning instead of specializing a
  structural primitive; and
- default values or sentinel encodings that silently select a named mechanism.

The decisive negative probe is an external test-only mechanism with comparable resource access,
bounded traversal, proposal inspection, and rejection or contribution behavior. It must compile,
execute, qualify, and checkpoint through the ordinary public path without editing CorePotts. A
CorePotts edit needed only to add a genuinely reusable structural primitive is permitted during
repair, but the reviewer must reject an operation whose API or semantics merely spell the new
mechanism. Search results are evidence leads; absence of a biological name is not clearance.

### Engine-hardcoding audit protocol

Engine hardcoding is a recurring architectural failure mode and MUST be audited independently of
the mechanism-leakage name search. The question is not whether CorePotts mentions `Act`,
`chemotaxis`, or another familiar mechanism. The question is whether engine control flow or engine
state assumes a scientific policy that should instead be compiled from reusable structural
primitives.

CorePotts may own only bounded execution facts such as immutable proposal views, resource handles,
typed structural domains, bounded traversal, descriptor evaluation, canonical folding,
transactional request arbitration, generic state effects, scheduling, adaptation, and backend
launch. PottsToolkit or an external module must own the scientific composition of those facts.
Renaming a mechanism to a generic-looking tag, capability bit, plan, callback, or singleton does
not change its ownership.

This division applies equally to constraints. CorePotts may own the closed execution result of a
constraint evaluation, the canonical rule for combining compiled results, and the bounded
primitives needed to inspect a proposal. It MUST NOT own connectivity preservation, fragmentation
policy, a privileged constraint neighborhood, or any other scientific admissibility rule. Those
belong in PottsToolkit or an external module as ordinary compiled descriptors composed from the
same public proposal, state, relation, and bounded-traversal primitives available to every other
constraint.

For every reachable branch, field, tag, callable, mutation, or checkpoint datum under the engine,
the reviewer MUST record:

1. the exact source location and production call path;
2. the invariant that makes it structural rather than scientific;
3. the smallest public primitive or closed structural algebra that exposes that invariant;
4. whether an external module can express an equally demanding but scientifically unrelated use;
5. whether adding that external use changes CorePotts, `CompiledPottsProgram`, the proposal loop,
   stage executors, checkpoint machinery, or backend kernels; and
6. the disposition: retain as primitive, generalize, move to PottsToolkit, quarantine as
   unreachable legacy, or remove.

The audit MUST challenge these common disguises of hardcoding:

- a closed `isa`, symbol, enum, or trait ladder that dispatches scientific behavior;
- one program/runtime/checkpoint field or capability boolean per mechanism;
- a named constraint, drive, Hamiltonian term, process, or observation with a privileged engine
  descriptor, executor branch, proposal veto, affected-region algorithm, or backend kernel;
- an engine-selected neighborhood, owner, cell kind, field, history depth, reduction, decay law,
  interpolation rule, or lifecycle condition;
- accepted-copy or after-MCS branches that mutate a named resource directly instead of executing a
  compiled typed effect;
- observation code that knows particular biological state layouts instead of consuming compiled
  observation descriptors;
- relationship creation, retirement, or force policy embedded beside generic topology storage and
  transaction primitives;
- a compiler special case that recognizes a built-in mechanism where a registered operation,
  domain, effect, or capability rule should suffice;
- a generic-looking constraint or effect tag whose implementation still fixes the scientific
  predicate, traversal, or mutation rather than only its bounded execution contract;
- a backend-specific implementation that restates scientific semantics instead of implementing
  the same structural primitive; and
- defaults, zero values, empty plans, sentinels, or skipped descriptor categories that silently
  disable or select a mechanism.

#### Primitive-legitimacy test

Calling something a primitive is not sufficient. Every operation reachable from an engine loop
MUST be classified as exactly one of:

1. a **structural kernel primitive** owned by CorePotts;
2. a **compiled policy object** whose concrete behavior is supplied by PottsToolkit or an external
   module; or
3. a **scientific composition** owned entirely outside CorePotts.

A CorePotts operation qualifies as a structural primitive only when all of the following hold:

- its inputs and result describe execution structure, topology, geometry, proposal views, resource
  access, bounded traversal, scheduling, or transactional state change—not a named biological or
  biophysical rule;
- it does not choose a scientific predicate, coefficient meaning, endpoint-kind policy,
  neighborhood, lifecycle condition, or payload schema;
- its bounds, aliasing, mutation, allocation, inference, and backend behavior have an explicit
  compiler contract;
- at least two scientifically unrelated compositions can use the same implementation without a
  CorePotts edit or a new engine branch;
- every backend already admitted by the current gate executes the same semantics through that
  primitive; a primitive reserved for a later device gate must already adapt, report capability,
  and fail closed, then receive its real-device execution proof at that gate; and
- removing any one built-in mechanism leaves the primitive and its tests coherent.

If an operation fails any item, the default disposition is to move its policy into a compiled
callable/effect outside CorePotts and retain only the smallest structural operation it needs. A
new symbol, trait, singleton type, descriptor role, capability flag, or `isa` case is not an
acceptable repair unless the item itself passes this test. Conversely, the audit MUST NOT force a
useful structural primitive out of CorePotts merely because one built-in model currently happens
to be its only user; the independent negative probe decides that boundary.

For each candidate primitive, the reviewer records its exact semantic contract and constructs a
counterexample: a scientifically unrelated external use that stresses the same access, traversal,
mutation, and backend behavior. Failure of the counterexample is a P1 even when all bundled models
pass.

#### Dependency-inversion and zero-engine-edit probes

R1.5 MUST also audit the direction of dependency, not only the apparent generality of individual
types. Scientific modules may depend on CorePotts primitives; CorePotts execution MUST NOT depend
on the presence, names, registration order, payload vocabulary, or policy choices of bundled
scientific modules.

For every admitted extension category—Hamiltonian, drive, constraint, accepted-copy effect,
after-MCS process, observation, and bounded relationship operation—the reviewer performs both of
these probes:

1. **Additive probe:** add a scientifically unrelated test-only implementation using only public
   registration, lowering, descriptor, resource, and effect interfaces. The diff required under
   `lib/CorePotts`, the proposal loop, stage executors, checkpoint machinery, and backend kernels
   MUST be empty.
2. **Subtractive probe:** omit the corresponding bundled mechanism and its registrations while
   retaining the structural primitive and external fixture. Core compilation, execution,
   checkpoint continuation, inference, and selected backend qualification MUST remain coherent.

Any engine edit demanded by the additive probe is presumed to expose a missing primitive or a
hard-coded policy. The reviewer must identify the smallest reusable structural contract before an
edit is accepted. Any failure of the subtractive probe shows that the alleged primitive still
derives meaning, defaults, layout, dispatch, or lifecycle behavior from a privileged built-in.

The source audit therefore starts from production entry points and works inward. It traces every
reachable `isa`/trait/symbol branch, tuple-position assumption, program or checkpoint field,
resource slot convention, default/sentinel, and backend dispatch case to its declaring compiler
fact. A branch is not cleared because several current models happen to share it. It is cleared only
when the branch selects a bounded execution representation and all scientific choices arrive in a
compiled value or callable owned outside CorePotts.

The reviewer records the result in a compact table with: source location, reachable caller,
suspected embedded policy, proposed structural primitive, additive-probe result,
subtractive-probe result, backend result, and disposition. This table is a bounded review artifact,
not a permanent evidence subsystem.

#### Current candidate hardcoding inventory

The following are evidence leads and repair claims in the current candidate, not predetermined
verdicts. R1.5 MUST trace and either clear or dispose of every item against the
primitive-legitimacy test:

- the former `CompiledRelationshipPlan` mixed structural capacity/degree bounds with endpoint
  kinds, focal-point payload defaults, accepted-copy creation, breakage, and endpoint-removal
  policy. The repaired candidate replaces it with `RelationshipStoreSchema`; the audit must prove
  that this replacement owns only bounded storage structure and that endpoint eligibility,
  creation conditions, lifecycle predicates, and scientific payload meaning now arrive through
  compiled policy outside CorePotts;
- the former relationship request, initialization, checkpoint, and energy path spelled the focal
  payload fields `strength`, `target`, and `maximum`. The repaired candidate uses positional tuple
  payload storage plus compiler-owned value-level field resolution. The audit must prove no payload
  name, declaration order, or bundled schema controls a CorePotts type, branch, slot convention, or
  checkpoint interpretation;
- the former `_accepted_copy_relationship_state` chose contact traversal, relationship creation,
  payload defaults, and timing inside the proposal executor. The repaired candidate claims a
  generic `RelationshipCreateEffect` over compiled evaluators and the public relationship
  transaction primitive. The audit must trace the full emit/validate/commit path, prove warm
  allocation and rejection atomicity, and exercise it with an unrelated external topology update;
- the former `_after_mcs!` owned focal-link breakage and endpoint-removal decisions. The repaired
  candidate claims a generic `RelationshipRemoveEffect` whose compiled predicate is evaluated from
  an immutable relationship-stage view before canonical mutation. The audit must prove the engine
  neither interprets payload meaning nor selects lifecycle policy and that multiple descriptors
  obey the declared snapshot and conflict semantics;
- relationship evaluation and observation currently contain a one-store/slot-one assumption. The
  audit must decide whether this is an explicit closed V1 structural bound or an accidental
  privileged resource, and must reject any path in which the first declared relationship gains
  semantics unavailable to another declaration.
- named resource operations such as cell volume/elongation, field/history access, relationship
  degree, contact access, and owner-kind access require individual review. Geometry and generic
  resource reads may be legitimate primitives; a hidden choice of model state, reduction,
  neighborhood, or biological interpretation is not. They are not cleared merely because their
  operation structs are concrete and allocation-free.
- canonical cell-volume tracking and cell-retirement cleanup require an ownership audit: the
  engine may maintain structural ownership invariants and generically retire cell-domain storage,
  but it must not select mechanism-specific state, relationship policy, or observation behavior
  during retirement.
- every `ResourceOperation`, `ContextOperation`, stage-effect type, descriptor role, capability
  field, and backend dispatch case must have a public structural contract and an unrelated external
  probe. Any entry whose only coherent explanation is a bundled Wortel, Merks, Act, connectivity,
  elongation, chemotaxis, or focal-point feature is a mechanism leak even if its name is generic.

This inventory is updated during repair: a removed item is marked with the replacing primitive and
its negative-probe test; a retained item is marked with the structural invariant that justifies it.
Passing the bundled fixtures alone cannot clear any item.

Clearance requires external, test-only negative probes for every production phase admitted by V1,
not one token extension that exercises only proposal energy. At minimum the probes cover:

- a proposal contribution and a hard constraint using declared state and bounded neighborhood
  access;
- an accepted-copy state update expressed as a compiled request/effect;
- an after-MCS state transformation expressed through the same generic stage executor;
- a compiled observation over externally declared state;
- a bounded relationship request and lifecycle operation when the relationship surface is in
  scope; and
- checkpoint/restore plus the selected CPU qualification boundary for the resulting generic
  resources and effects, with adaptation and fail-closed capability evidence for device paths not
  yet admitted by the current gate. The same probe must execute on the selected real device at the
  first gate that admits that stage; R1.5 must not circularly require G4 execution before allowing
  G4 to begin.

Each probe must use names and scientific meaning absent from CorePotts, run through the ordinary
public compile and execution path, and require no engine edit. A test that merely subclasses a
CorePotts mechanism-specific plan does not qualify. If one external probe cannot be expressed, the
finding returns to the earliest missing primitive or executor boundary; it is not repaired by
adding another named engine branch.

The hard-constraint probe MUST use a predicate unrelated to connectivity and MUST prove that it
uses the identical descriptor lowering, proposal-view access, canonical decision combination,
checkpoint path, inference boundary, and selected backend launch as built-in PottsToolkit
constraints. Conversely, the connectivity implementation MUST be removable from PottsToolkit
without changing CorePotts or weakening that external probe. This bidirectional check distinguishes
a real constraint primitive from a connectivity engine with an extension-shaped API.

#### Semantic DRYness and single-source audit

R1.5 MUST audit code DRYness wherever duplication can create a second source of execution or
scientific truth. This is not a line-count or abstraction-maximization exercise: small repeated
plumbing is preferable to an opaque framework when it cannot drift semantically. A finding is
blocking when two reachable implementations can disagree about the same contract, or when adding
an extension requires copying and editing a built-in path instead of composing public primitives.

The reviewer MUST trace and challenge duplication across:

- symbolic-expression normalization, versioned operation resolution, evaluator construction, and
  invocation. Compiler-synthesized expressions and stage effects must not create an alternate
  lowering path;
- request emission, canonical ordering, conflict arbitration, validation, and atomic commit.
  Per-descriptor convenience paths must not duplicate or bypass the batch transaction;
- sequential and backend-specific execution. Backends may specialize structural launch and memory
  behavior but must not restate scientific semantics;
- runtime initialization, snapshots, checkpoint reconstruction, saved-state projection, and
  symbolic indexing. These must consume the same declared resource schema rather than maintain
  parallel mechanism-shaped layouts;
- Hamiltonian, drive, constraint, observation, and stage-effect traversal, grouping, capability,
  and diagnostics. A new category member must extend one owned algebra rather than add mirrored
  switch ladders across compiler and engine files;
- neighborhood, ownership, topology, geometry, and relationship primitives. Built-ins and external
  mechanisms must share the exact implementation rather than carry near-copies; and
- CPU/GPU implementations, test oracles, and generated-code paths. An independent oracle may
  deliberately duplicate mathematics for testing, but it must never be reachable production code.

For each suspected duplicate, the reviewer records both call paths, identifies the authoritative
owner, and applies a divergence probe using an edge case or external extension. The preferred
repair removes the second semantic implementation or derives both representations from one frozen
compiler fact. Clearance does not require deduplicating independent test oracles, backend launch
plumbing, or short local code whose unification would obscure ownership or worsen inference.

Severity follows consequence: P0 when reachable duplicates execute different declared science or
break atomicity; P1 when duplication creates a bypass, inconsistent extension contract, or backend
semantic fork; P2 for nonblocking organization or repeated plumbing with a bounded cleanup.

Severity is assigned by reachability and consequence:

- P0 when hardcoding makes an accepted model scientifically inert or executes different science
  from its declaration;
- P1 when an external mechanism of an admitted V1 category requires an engine edit, bypass, host
  fallback, or new specialization category; and
- P2 only for unreachable legacy or organization that cannot affect production behavior and has a
  bounded removal checkpoint.

This protocol is applied at R1.5, repeated over concurrency and device paths at R2, exercised by
Wortel, Merks, focal-point plasticity, and at least one unrelated external mechanism at R3, and
repeated over the complete reachable tree at R4. It is intentionally a source-and-negative-probe
review, not a new evidence framework or a permanent slow test tier.

G4 remains stopped until R1.5 reports zero P0 and zero P1 findings. A compiler-boundary finding
returns work to G1 or G2; an acceptance, RNG, atomicity, tracker, lifecycle, or sequential-runtime
finding returns work to G3. P2 findings remain nonblocking under the existing autonomous repair
rule.

### First R1.5 result — returned

The read-only review of `d8f00c352230a3ce3a208312eee82444a93eef55` returned G1 through G3
with one P0, two P1, four P2, and no P3 findings. It independently reproduced that:

- `LocalConnectivity` lowers to a literal-true expression and the runtime instead traverses
  proposal offsets, so declared connectivity relations do not control connectivity semantics;
- connectivity and relationship-extinction vetoes can determine a proposal outside the compiled
  descriptor plan;
- adding an unrelated lexically earlier `DrawKey` renumbers an existing explicit draw identity;
- the two-step transition check reuses the one-step oracle rather than independently enumerating
  two proposals and their branches;
- an admitted warmed connectivity rejection allocates 1,088 bytes;
- required attempt-accounting categories are absent; and
- underflow and proposal-level RNG-role evidence is incomplete.

The reviewer also confirmed the single structural sequential call path, absence of reachable named
energy-delta helpers, role separation, ordinary rejection atomicity, checkpoint scratch exclusion,
and the public external fixture. Its focused G3 run passed 305/305 in 42.7 seconds. G4 remains
blocked; repairs start at G1, requalify G2, complete G3 evidence, and receive a fresh R1.5 review.

During the first repair attempt, moving connectivity and endpoint-retirement semantics into named
CorePotts resource operations was rejected before checkpointing. That shape made the executor look
descriptor-driven while retaining scientific mechanism knowledge in CorePotts. The repair must
instead add only public structural proposal/resource primitives to CorePotts and keep scientific
callables and compositions in PottsToolkit or external modules.

### Repaired R1.5 candidate

The repaired implementation checkpoint is
`2fce3b470eaa5d36a3cc5ad675967d69c5ffd038`. It replaces the two out-of-plan vetoes with ordinary
compiled constraints. Merks connectivity is a PottsToolkit-owned concrete callable composed from
public proposal-owner, kind, declared-relation, bounded-neighbor, and relation-count primitives.
Endpoint retirement is a PottsToolkit completion rule expressed through the ordinary symbolic
constraint and bounded relationship-degree path. Neither behavior adds a named CorePotts
mechanism operation.

Additional repaired evidence on that checkpoint includes:

- declared radius-one Moore/Von Neumann connectivity resources, exact compiled footprints, a
  diagonal-disconnection truth table, the two-cell Merks exception, conservative boundary
  behavior, zero warmed evaluator allocation, and rejection of invalid relation declarations;
- qualified, stable explicit-draw identities that do not renumber after an unrelated earlier draw,
  with explicit compile-time collision rejection;
- an independently enumerated two-attempt oracle that does not call the one-step row oracle;
- null, constraint-rejection, energy-rejection, accepted-copy, and retired-cell counters whose
  terminal outcomes partition candidate attempts and survive checkpoints;
- subnormal and deep-underflow acceptance seams proving the proposal path compares in log space;
  and
- branch-invariant later RNG addresses across null, hard-rejection, energy-rejection, and accepted
  first attempts.

Qualification on the implementation checkpoint:

- focused repaired G3 suite: 558/558;
- focused G1 host facts: 62/62;
- focused G2 descriptor and local-energy suites: 131/131 and 59/59;
- CorePotts package suite: passed, including Aqua; and
- ordinary root `Pkg.test()`: 1,152/1,152 in 6m52.7s, including the visible Wortel, Merks, and
  focal-point-plasticity fixtures, SciML/SII, checkpoints, Aqua, and ExplicitImports.

The following are mandatory semantic audit leads, not accepted dispositions. CorePotts still
defines activity, field, history, elongation, relationship, and observation plan/state names;
`CompiledPottsProgram`, `ProgramInitialState`, `ProgramRuntime`, snapshots, and checkpoints still
carry some corresponding fields; `_commit_copy!` and `_after_mcs!` still contain conditional
activity, history, field, and relationship behavior; and old named delta helpers remain defined
although the proposal loop no longer calls them. R1.5 must determine which, if any, are genuinely
reusable structural primitives, which are unreachable staged legacy, and which are blocking
mechanism leakage. It must not infer clearance merely from descriptor-driven proposal energy.

### Second R1.5 result — returned

The fresh read-only review of exact audit-record checkpoint
`4a6ec9959b44f7578ada388fe4abe62680b68901` returned G2/G3 with two P0 findings, one P1 finding,
and no P2 findings:

- `ActEnergy` lowers to a literal-zero drive, leaving its kind, activity, maximum, strength, and
  reduction scientifically inert in proposal acceptance;
- `Chemotaxis` lowers an unconditional field difference, leaving its declared cell kind,
  responding-owner mode, and interpolation policy as metadata rather than executable semantics;
  and
- reachable CorePotts activity, field, history, relationship, observation, accepted-copy, and
  after-MCS policy remains closed, while the declared generic request/stage hooks have no
  production executor call sites. An external staged mechanism therefore still requires a
  CorePotts edit.

The reviewer independently passed the G2 descriptor suite 131/131, local Hamiltonian equivalence
59/59, G2 adversarial boundaries 28/28, and repaired G3 sequential suite 558/558. It cleared the
connectivity, endpoint-retirement, stable-draw, two-step-oracle, accounting, underflow, canonical
evaluator, representation-bank, specialization-growth, folder-ownership, and fast/expensive-test
repair questions. G4 remains stopped. The earliest repair boundary is G2/G3: make generic
request/stage execution real, express Act and chemotaxis through that generic path, and remove or
quarantine reachable named CorePotts policy before requesting another R1.5 review.

### Third repaired R1.5 candidate — awaiting independent review

The repaired implementation checkpoint is
`27964c6e9ce0a6af82bbc1baa1021f1804f2cd4b`. This checkpoint is a candidate, not a clearance. G4
remains stopped until a fresh independent review reports zero P0 and zero P1 findings.

The candidate makes the following claims for the reviewer to challenge:

- `ActEnergy` now lowers to a concrete PottsToolkit-owned callable and participates in the
  canonical drive evaluator. Chemotaxis has one exact admitted V1 profile; unsupported responding
  modes and interpolation policies fail closed during compilation instead of becoming inert
  metadata.
- accepted-copy and after-MCS policies now execute through the production `CompiledStagePlan`.
  Generic relationship create and remove effects emit requests whose validation, arbitration,
  and commit are owned by structural CorePotts transaction primitives.
- relationship storage has generic positional payload tuples. Payload names, endpoint-kind
  eligibility, creation predicates, lifecycle predicates, and scientific payload meaning are
  supplied outside CorePotts. The unrelated external fixture uses `score`, `cutoff`, and `marker`
  payloads through the same production stages.
- the public saved-state layer now indexes declared state and topology by value-level declaration
  names rather than carrying dedicated activity, field, history, focal, or relationship aliases.
- relationship stage execution is warm allocation-free in its admitted focused probes and returns
  inferred concrete result types.

The review MUST NOT accept those claims from passing bundled fixtures. It must apply the engine-
hardcoding protocol, primitive-legitimacy test, additive/subtractive dependency-inversion probes,
and semantic DRYness/single-source audit above. In particular, it must trace every reachable `isa`,
trait, symbol branch, resource operation, tuple position, slot convention, default, sentinel,
descriptor role, capability field, checkpoint field, duplicated semantic implementation, and
backend branch from the sequential production entry point back to an explicit compiler fact or
public structural contract.

The following are mandatory unresolved leads:

- relationship evaluation, snapshots, and saved topology still expose a one-runtime-store and
  slot-one bound. The reviewer must decide whether this is a coherent closed V1 structural limit
  that treats every declaration equivalently or an accidental privileged resource that blocks
  external extension. No clearance is implied by documenting the limit.
- CorePotts resource operations for geometry, fields, histories, contacts, owner kinds, and
  relationships must each pass the primitive-legitimacy test. Concrete singleton representation
  and zero allocation are insufficient if the operation fixes scientific interpretation.
- the finite stage-effect algebra must be checked for dependency inversion. Adding an unrelated
  accepted-copy effect, after-MCS process, observation, and relationship operation must require
  zero changes to CorePotts, the proposal loop, stage executors, checkpoint machinery, and backend
  kernels; removing each bundled mechanism must leave those paths coherent.
- inspection roles such as activity, field, and history must remain value-level reporting facts.
  They must not select runtime storage, evaluation, mutation, observation, checkpoint, or backend
  behavior.
- every retained CorePotts relationship, retirement, and ownership mutation must be justified by
  a generic bounded-topology or ownership invariant and exercised by a scientifically unrelated
  external use.

Qualification on the implementation checkpoint:

- CorePotts package suite: passed, including Aqua;
- focused G1 host facts: 62/62;
- focused G2 descriptor, local Hamiltonian equivalence, and adversarial-boundary suites: 131/131,
  59/59, and 28/28;
- focused repaired G3 sequential suite: 602/602, including the unrelated relationship payload and
  stage-effect fixture;
- specialization-growth qualification: 5/5;
- real Metal G2 descriptor boundary: passed with descriptor, state, and workspace buffers adapted
  to `MtlArray` and the expected value `17.5f0`; and
- ordinary root `Pkg.test()`: 1,205/1,205 in 8m40.6s, including Wortel, Merks,
  focal-point-plasticity, SciML/SII, checkpoint, Aqua, and ExplicitImports coverage.

The Metal evidence qualifies the already admitted G2 descriptor boundary only. It is not evidence
that later relationship or stage effects execute on every GPU backend. Those paths must adapt,
declare capability, fail closed where not admitted, and receive real backend-agnostic device
qualification at the gate that first admits them.

### Third R1.5 result — returned

The fresh read-only review of audit-record checkpoint `cfcd1dc` returned the candidate with two P0,
four P1, and one P2 findings. G4 remains stopped.

The reviewer independently reproduced:

- an advertised `cell_surface` Hamiltonian that completes and compiles but throws a `MethodError`
  in production evaluation, with additional registered resource operations lacking context
  implementations or fail-closed admission;
- two accepted-copy relationship-create descriptors for the same endpoints being validated and
  directly committed independently, producing duplicate edges instead of passing through the
  canonical batch transaction;
- the one-store/slot-one topology bound rejecting coexistence of bundled-style and unrelated
  relationship declarations;
- compiler-synthesized stage evaluators directly embedding callable objects rather than traversing
  the sole versioned operation-transfer and callable-resolution path;
- external declared `SiteState` observation lowering being rejected despite a structurally
  reusable export evaluator; and
- the specified public `Retune` relationship effect lacking a compiled stage descriptor and
  executor path despite generic transaction support.

The reviewer cleared role separation, executable Act energy, fail-closed unsupported chemotaxis,
RNG identities, representation-bank canonicalization, normalized singleton callables,
specialization-growth placement, generic ordinary saved-state naming, ownership/retirement within
the representable topology bound, current checkpoint reconstruction, and backend-qualification
placement. The focused G3 suite passed 602/602, but bundled-suite success did not override the
negative probes.

The nonblocking P2 identifies `lib/CorePotts/src/program/v1.jl` as a roughly 2,500-line ownership
mixture that obscured the transaction bypass and retains a dead duplicated `contact_offsets`
field. Repair returns to G1/G2 for operation admission, the sole evaluator route, and generic
observation lowering; to G2/G3 for canonical batched topology transactions, multiple stores, and
the complete create/remove/retune algebra; and then performs the semantic DRYness audit before a
fresh R1.5 review.

### Fourth repaired R1.5 candidate — awaiting independent review

The exact implementation checkpoint is
`52856077f2ae7ab678d644320b91323b9680121d`. This checkpoint is a candidate, not a clearance. G4
remains stopped until a fresh independent R1.5 review reports zero P0 and zero P1 findings.

The candidate makes the following claims for the reviewer to challenge rather than accept:

- every compiler-produced executable expression reaches `CorePotts.StaticEvaluator` through one
  `_static_evaluator` construction site after versioned operation transfer, concrete callable
  resolution, context admission, and device-representation checks; unsupported `cell_surface`
  use now fails compilation instead of reaching a runtime `MethodError`;
- all accepted-copy relationship Creates enter one preallocated batched transaction per store,
  canonical arbitration occurs before any publication, duplicate Creates are idempotent, and
  after-MCS Remove and Retune use the same transaction and publication machinery;
- relationship declarations are canonically ordered once by qualified identity, multiple stores
  remain independently addressable across initialization, queries, Hamiltonians, staged effects,
  observations, saved state, reports, and checkpoints, and value-level slots select heterogeneous
  stores through one generated relationship-slot call primitive without warm-path allocation;
- direct observations lower generically for declared site, cell, medium, model, field, and history
  state; Retune is a production symbolic effect rather than test-only transaction machinery;
- CorePotts contains no Wortel, Merks, focal-point-plasticity, Act, chemotaxis, or connectivity
  mechanism identity; the remaining PottsToolkit qualification branches are front-end policy and
  not engine semantics; and
- the former `program/v1.jl` ownership mixture is now a ten-line include manifest over files owned
  by program types, relationship storage, runtime state, RNG, proposal context, staged execution,
  and sequential execution. The dead duplicated `contact_offsets` program field is removed.

Qualification on the exact implementation checkpoint:

- ordinary root `Pkg.test()`: 1,233/1,233 in 9m23.7s;
- focused G3 sequential suite: 628/628, including two independently addressable relationship
  stores, allocation-free multi-store query/Create/Retune execution, and checkpoint restoration;
- focused descriptor, local/global Hamiltonian, and adversarial G2 suites: 131/131, 59/59, and
  28/28;
- complete CorePotts package suite: passed, including Aqua;
- full specialization-growth qualification at 1, 32, and 1,024 repeated terms: 5/5; and
- real Metal G2 descriptor boundary: 32 descriptors with descriptor, state, and workspace buffers
  adapted to `MtlArray`, returning `17.5f0`.

The reviewer MUST apply the engine-hardcoding, primitive-legitimacy, semantic-DRYness, and
single-source protocols above. In addition, it MUST independently debate the following supplied
review leads; none is a pre-accepted fact or mandated implementation:

- Is there exactly one production path from a symbolic expression to a concrete callable
  evaluator, including registered external descriptors and every contextual operation, or can an
  extension bypass canonical normalization, transfer, callable resolution, or context admission?
- Are named singleton Base functions, finite parametric semantic operations, and `OrderedFold(+)`
  used only where structural meaning warrants specialization? Is the name-string closure check
  merely defense-in-depth, with registered schema provenance, `isbits`, declared capability, and
  real backend compilation remaining authoritative?
- Are storage-bank and handle types derived canonically from representation rather than encounter
  order or declaration identity? Do 1, 32, and 1,024 same-representation blocks reuse handle types,
  and do relationship-store tuple structure or generated slot branches introduce unacceptable
  specialization or generated-code growth as store count increases?
- Does each accepted Hamiltonian still store an energy domain, bound anchor, and normalized energy
  expression while the compiler proves a finite affected-anchor plan and derives local
  after-minus-before contributions? Are proposal-context reads, random draws, mutation, unbounded
  domains, user names in types, and source-order folding drift still rejected?
- Can a scientifically unrelated external module add a Hamiltonian term, constraint, drive,
  accepted-copy effect, after-MCS process, observation, and relationship operation without editing
  CorePotts, the proposal loop, stage executors, checkpoint machinery, or backend kernels? Must it
  pass the same CPU, inference, allocation, specialization, and admitted-backend gates?
- Are Act, chemotaxis, and Merks local-connectivity branches in PottsToolkit honest finite V1
  qualification adapters, or do any hard-code biological mechanisms where a compiler fact or
  reusable primitive should control lowering? Conversely, would abstracting them further create a
  speculative general query or mechanism framework outside the closed V1 scope?
- Does folder ownership now make compiler stages and runtime authority legible, and has relocation
  actually removed semantic duplication? Search specifically for duplicate evaluator factories,
  relationship ordering, slot mapping, payload validation, transaction arbitration, observation
  export, before/after energy evaluation, checkpoint reconstruction, and backend adaptation.
- Are expensive Metal and specialization qualifications properly outside the everyday test loop
  while the ordinary Julia suite retains fast negative admission, scientific equivalence,
  inference, and allocation proofs? No renewed evidence ledger or second production oracle may be
  introduced to answer this question.

R1.5 must report findings with exact production call paths and the earliest repair boundary. A
bundled fixture passing, a concrete type, or a zero-allocation microprobe is not by itself evidence
of extensibility, scientific correctness, device legality, or semantic DRYness.

## Prohibited record contents

This record intentionally contains no freshness deadline, renewed attestation, copied CI log,
expected-output archive, hardware ledger, manually renewed hash, duplicated vendor suite, or
second semantic definition.
