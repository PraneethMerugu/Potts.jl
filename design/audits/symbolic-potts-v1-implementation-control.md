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
| G1 host compiler facts | `passed` | conservative Hamiltonian taxonomy, closed domains, compiler-proven finite affected anchors, adversarial rejection suite | `eb8a37a` | included in fresh R1 scope |
| G2 descriptor/group/evaluator/state/workspace | `candidate_pending_R1` | immutable before/after views, typed domain/affected plans, local/global equivalence, allocation/inference/growth/Metal qualification | pending | fresh R1 required |
| G3 sequential reference/finite transitions | `pending` | pending | pending | none |
| G4 checkerboard/first GPU witness | `pending` | pending | pending | none |
| G5 trackers/relationships/lifecycle/checkpoint | `pending` | pending | pending | R2 |
| G6 public integration spine | `pending` | pending | pending | none |
| G7 proof-model reconstruction | `pending` | pending | pending | R3 |
| G8 clean break/full integration | `pending` | pending | pending | none |
| G9 terminal qualification | `pending` | pending | pending | R4 |

## Reviewer state

| Review | State | Blocking findings | Nonblocking findings |
|---|---|---|---|
| R1 compiler | `reopened` | four `598493b` P1 findings repaired; exact-tree rereview pending | dead alternate-evaluator P2 repaired by removal |
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

## Prohibited record contents

This record intentionally contains no freshness deadline, renewed attestation, copied CI log,
expected-output archive, hardware ledger, manually renewed hash, duplicated vendor suite, or
second semantic definition.
