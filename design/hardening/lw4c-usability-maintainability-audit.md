# LW-4C usability and maintainability audit

> The usability findings remain historical input. Qualification mechanics and
> final-review procedure are superseded by
> `design/hardening/lw4q-qualification.md` and are not normative here.

Status: pre-freeze lens complete; exact qualification bundle and fresh LW-R2
ballots remain required

Date: 2026-08-11

This audit evaluates the remediated LW-4 candidate without reopening the
accepted architecture, lifecycle, names, output-family algebra,
KernelAbstractions ordering model, or domain boundaries. KernelAbstractions
owns portable launch and implicit ordering. LocalWorksets owns validated
topology, conflict semantics, bounded workspace, lifetime, and inspection.
Domain packages retain physics, clocks, RNG, transactions, solvers, and
checkpoints.

The package is not rated 10/10 in LW-4. That rating requires LW-5 evidence that
real CorePotts and PottsToolkit operations reduce to scientific operation,
explicit output semantics, explicit topology, and ordinary storage binding
with materially less glue.

## Five author perspectives

### Scientific user reading an example

The single-output example now reads as `localwork -> topology -> plan ->
prepare -> run! -> wait`. Automatic workspace is the default, compiler terms
are absent, and independent/combined/resolved semantics are visible. The user
still has to understand routes and destination counts; that is necessary
scientific information, not removable ceremony. The package cannot yet prove
that a real domain example remains this small after all model-specific state is
included, so final usability is an LW-5 question.

### Domain-package author defining heterogeneous work

Named ports permit independent edge state, combined vertex forces, and
resolved fracture candidates in one concrete callable. Numerical mode,
identity, empty behavior, bounded emissions, routes, and semantic identities
are explicit. Automatic workspace removes lowering-specific buffers from the
normal path. The retained legacy resolved adapter is confusing if presented
beside generic `resolved`/`candidate`; it is therefore compatibility-only,
closed to new consumers, and governed by removal criteria below.

### Unrelated external operation author

An external package adds a concrete isbits callable with
`(item::Int32, reads, values)` and uses public declarations. It changes zero
LocalWorksets source files. External methods cannot authorize a capability,
provider, lowering, synchronization, allocation, or fallback. The remaining
friction is learning the concrete device-call contract and interpreting a
rejection; README examples and structured diagnostics now make both explicit.

### JuliaGPU/backend qualification maintainer

Execution source is vendor-neutral, while admission remains qualified only for
CPU and the reviewed Apple-M1/Metal environment. Inspection distinguishes
operation-structure validation, reviewed provider environment, host runtime
compilation, GPU compilation deferred to first run, absence of a provider
compile-validation protocol, and forbidden host fallback. KernelAbstractions
0.9 has no portable compile-only GPU entry point, so LocalWorksets correctly
does not add vendor hooks or probe launches. The exact qualification bundle is
a freeze blocker.

### LocalWorksets contributor

The current source is about 9,000 physical lines after structured diagnostics
and derived inspection groups. Size is debt evidence, not a verdict. Common
validation, topology, workspace, evidence, arbitration, and provider ownership
have one private authority, while family schedules remain separate. The legacy
four-launch path is the largest unearned compatibility surface. Any further
internal representation must demonstrate lower change amplification without
weakening static specialization or central admission.

## Decision table

| Concern | Current evidence | User impact | Developer impact | Freeze blocker? | Disposition | Required tests |
|---|---|---|---|---|---|---|
| One public resolved language | Generic `resolved(...)` plus `candidate(rank, value[, condition])` executes CPU/Metal witnesses. | One mental model for new code. | Generic declaration is the semantic authority. | Yes, as a documentation/admission rule; legacy removal is not. | **Required before LW-4 freeze:** document one new-code language and reject new legacy consumers. | Generic empty, mask/no-candidate, total rank, canonical tie, CPU/Metal, external operation. |
| `masked` compatibility | Used only by the legacy descriptor/fixtures. | Visible extra vocabulary can confuse discovery. | Keeps eager-mask handling and duplicate tests alive. | No, if clearly isolated. | **Bounded post-freeze hardening:** deprecate only after the complete generic parity gate. | No-new-adoption source test; warned-release migration test before removal. |
| Named-family resolved descriptor, flat topology, legacy workspace, four-launch lowering | Retained together; no CorePotts authority and no demonstrated performance advantage. | Expert users could mistake it for an alternative authoring surface. | Duplicates validation, evidence, workspace, and kernels. | No, while compatibility is isolated and qualified. | **Bounded post-freeze hardening:** migrate and remove as one unit after explicit criteria below. | Semantic/lifetime/inspection parity, exact launches/allocations, CPU/Metal direct performance, zero remaining consumers. |
| Conjunctive CorePotts resolution | Exact old-owner/new-owner claim with Core-owned proposal/commit semantics. | Not exposed as public convenience. | A bounded domain adapter remains separate from destination publication. | No. | **Required before LW-4 freeze:** preserve as private/domain adapter; do not generalize its language. | Core continuation, RNG mismatch, settlement, queued MCS, CPU/Metal direct parity. |
| Structured diagnostic schema | `LocalWorkValidationError` publicly exposes stage, contract, port, binding, workspace leaf, expected, actual, hint. | Programmatic and interactive failures become actionable. | Stable field tests replace brittle prose matching. | Yes for schema and high-value public paths. | **Required before LW-4 freeze:** retain schema and field coverage for declaration validation, routes/counts, results, bindings, aliases, submissions, workspace, backend capability, topology, and poison. | Field assertions plus concise `showerror`; prelaunch rejection remains unpoisoned. |
| Remaining message-only internal errors | Many method-ownership/invariant errors do not yet populate every field. | Rare internal-admission faults have less structured context. | Mechanical conversion risks assigning misleading stages. | No after public paths are covered. | **Bounded post-freeze hardening:** enrich by subsystem when a stable contract name is meaningful; do not churn prose-only internals blindly. | One field-stability table per converted subsystem. |
| Declaration-constructor misuse | Julia-style `ArgumentError` remains for malformed constructor arguments. | Familiar Julia behavior before any lifecycle object exists. | Avoids pretending an unconstructed declaration reached plan validation. | No. | **Bounded post-freeze hardening:** reconsider only with real discoverability evidence; validated lifecycle faults use the structured type now. | Constructor error-type and docstring tests. |
| Author-oriented inspection | `summary`, `outputs`, `execution`, `memory`, and `qualification` are derived from the same flat facts. | Common questions are discoverable without losing detail. | No second evidence graph or launch authority. | Yes for additive organization and derivation tests. | **Required before LW-4 freeze.** | Equality/identity with authoritative flat fields at plan, prepare, and event stages. |
| Inspection completeness | Existing facts include empty behavior, phases, launches, determinism, transfers, workspace identity/bytes, provider scope, poison, and qualification. | Users can explain what will run and what failed. | Evidence builders remain the only semantic source. | Yes. | **Required before LW-4 freeze.** | Cross-family inspection snapshots and machine-readable witness results. |
| GPU compilation state | KA 0.9 lacks portable compile-only GPU validation; non-CPU selected-device compile is reported as deferred to first run. | No false promise that `prepare` compiled the GPU kernel. | Avoids Metal/CUDA/AMDGPU/GPUCompiler hooks and hidden probes. | Yes. | **Required before LW-4 freeze:** document and inspect all current states honestly. | CPU and real-Metal inspection; first-run failure poisons cumulative scope; source vendor-neutrality. |
| Future provider compile-validation | No protocol exists. | Could improve first-run feedback later. | A bad protocol could introduce hidden launches or vendor coupling. | No. | **Bounded post-freeze hardening:** admit only a separately reviewed compile-only, no-launch, fail-closed, centrally qualified provider protocol. | Provider conformance, zero launch, external self-authorization rejection. |
| Automatic workspace normal path | Direct, buffered, single-resolved, legacy, conjunctive, and sequence preparations have package-owned bounded construction evidence. | Normal examples contain no record buffers or lease arrays. | One workspace spec drives allocation, validation, identity, and bytes. | Yes. | **Required before LW-4 freeze.** | Every retained mechanism, exact bytes/identities, warm no-growth, zero topology transfer on run. |
| Explicit workspace stability | Expert caller ownership remains available; lowering leaf layouts are inspectable. | Enables controlled memory ownership but exposes mechanism detail. | Freezing record layouts would obstruct consolidation. | No. | **Required before LW-4 freeze:** state that the keyword is public but lowering-specific leaf layout is not a second stable authoring API. | Caller workspace validation, alias/shape fields, package-vs-caller inspection. |
| Public allocator/pool | No multiple-consumer evidence. | Would add lifecycle and memory vocabulary. | Risks scheduler/pool ownership and record-layout exposure. | No. | **Rejected.** | Reconsider only with multiple real consumers and no hidden semantics. |
| Ordinary external operation change amplification | External module test adds callable and declaration with zero LocalWorksets edits. | Strong extension experience. | Static dispatch and central validation preserved. | Yes. | **Required before LW-4 freeze.** | External module CPU/Metal execution and hostile late-method replacement. |
| New output value type change amplification | Requires a reviewed backend x type x operation x address-space row, family validation if the profile is narrowed there, and qualification tests/evidence. | Unsupported types fail closed rather than silently falling back. | Roughly two mechanism/evidence authorities plus tests, not a new public type. | No. | **Bounded post-freeze hardening:** derive reusable queries from declarations where this removes duplicated profile lists. | Rejection fields, capability piracy, CPU/Metal numerical and performance qualification. |
| New qualified backend profile | Generic provider code remains unchanged; reviewed environment evidence and backend conformance/manifest rows change. | Portability claim stays narrower than source portability. | Qualification metadata is isolated from execution. | No for LW-4. | **Bounded post-freeze hardening** when real hardware exists; CUDA/ROCm remain unclaimed. | Full provider, failure, allocation, ordering, cross-domain, and performance suite on exact hardware. |
| Change to an existing output family | Declaration query, family validation/lowering, evidence/workspace if affected, kernels if schedule changes, and tests must agree. | Semantic changes remain explicit. | Four to six components is justified only when the semantic contract actually changes. | No. | **Bounded post-freeze hardening:** first use existing declarations as authoritative reusable queries; add no new public contract type automatically. | Semantic, inspection, capability, lifetime, CPU/Metal, launch/allocation tests. |
| New execution mechanism | Requires two unrelated consumers, central admission/lowering, workspace/evidence, kernels/provider compatibility, and complete qualification. | Prevents package becoming a hidden solver/framework. | High change cost is an intentional admission barrier. | No. | **Rejected without two unrelated consumers.** | Both consumers plus all semantic/provider/performance gates. |
| New normalized IR/PortContract/policy hierarchy | Current declarations already carry value/rank type, route, emissions, coverage/empty, law, and determinism inputs. | Adds compiler terminology and adapter burden. | Could duplicate state and explode specialization. | No. | **Rejected absent measured reduction in duplicated state/change amplification.** | Static specialization and full parity proof would be mandatory before reconsideration. |
| Qualification driver and immutable bundle | `benchmark/lw4_qualification.jl` hashes the candidate, records environments/commands/exact exits/logs/results, verifies no source drift, and seals only after ballots. | Claims become reproducible rather than narrative. | One command replaces manual ledger assembly. | Yes; the driver existing is insufficient until its exact run passes. | **Required before LW-4 freeze.** | Driver self-test; all suites; raw CPU/Metal samples/counters; candidate unchanged; five ballots plus chair; final bundle manifest. |
| Qualification workflow after freeze | Current driver is local and sequential. | Requalification is clear but potentially expensive. | CI/artifact publication can be added without API changes. | No. | **Bounded post-freeze hardening:** package the driver workflow only after this exact bundle proves it. | Fresh-machine replay and corrupted/missing-result rejection. |
| LW-5 domain adoption metrics | No completed multi-operation CorePotts/PottsToolkit migration yet. | Determines whether the package is genuinely concise in practice. | Reveals adapter/glue cost the isolated API cannot measure. | No for LW-4; yes for a 10/10 claim and further mechanism expansion. | **Deferred to LW-5 evidence.** | Per-operation before/glue/topology/binding/workspace sizes, internal types, inspection, CPU/Metal parity. |
| Macro DSL, second lifecycle, inferred destination counts, hidden identities, public policy hierarchy, scheduler/streams, probe launches, public compiler nodes, generic fusion, arbitrary line target, second topology language | No evidence overturns prior vetoes. | Shorter demos would conceal necessary semantics or add mental models. | Each creates hidden authority, portability, or maintenance risk. | No. | **Rejected.** | Reopen only with explicit contradictory evidence and a separately approved gate. |

## Legacy removal criteria

The compatibility resolved path may be removed only when all of these are
simultaneously true:

1. generic `resolved` plus conditional `candidate` reproduces eager mask,
   active-prefix, explicit empty result, total rank, canonical semantic tie,
   topology freshness, cumulative lifetime, poison, and inspection behavior;
2. CPU and real-Metal tests pass on the exact candidate;
3. launch, allocation, workspace, transfer, and controlled direct-performance
   gates are no worse than the accepted qualification threshold;
4. no production, test, witness, or documentation consumer still constructs
   the named-family descriptor, flat topology, or legacy workspace; and
5. one warned compatibility release precedes deletion if the surface has been
   published.

The descriptor, flat topology, workspace, and four-launch lowering migrate as
one unit. Removing only a constructor while retaining its hidden machinery is
not consolidation.

## Contributor change-amplification summary

| Change | LocalWorksets source components expected to change | Admission judgment |
|---|---:|---|
| Ordinary external operation | 0 | Target achieved. |
| Another instance using an already qualified value type/family | 0 | Target achieved; declaration/topology/storage live downstream. |
| New qualified value/operation profile | 1–2 mechanism/evidence authorities, plus qualification tests | Acceptable because this expands executable claims. |
| New backend qualification row | isolated environment/capability evidence; generic provider should remain unchanged | Acceptable only with real hardware evidence. |
| Semantic change to one family | 4–6 declaration/query, validation/lowering, evidence/workspace/kernel components depending on actual scope | Debt signal; consolidate only if one declaration query can remove repeated state. |
| New execution mechanism | 5+ central lowering/evidence/workspace/kernel/include components plus two consumer suites | Deliberately expensive and normally vetoed. |

This table is a review budget, not permission to add abstractions. In
particular, a new private normalized representation is acceptable only if a
prototype proves fewer synchronized edit sites while retaining concrete types,
GPU compilation, central admission, and performance.

## Scores and provisional ballots

Scores describe the pre-freeze candidate, not the eventual package promise.
Ten means demonstrated real-domain excellence, so no category receives ten in
LW-4.

| Surface | Score / 10 | Freeze ballot | Reason and remaining ceiling |
|---|---:|---|---|
| Common Level-1 authoring | 8.5 | Pass | Concise ordinary Julia and automatic workspace; LW-5 must prove realistic state does not inflate glue. |
| Heterogeneous Level-2 authoring | 8.5 | Pass | Named ports express all three semantics cohesively; explicit topology remains appropriately visible. |
| External operation authoring | 9.0 | Pass | Zero source edits, concrete callable, hostile extension boundary tested; more unrelated packages must validate discoverability. |
| Diagnostics | 8.0 | Pass with bounded follow-up | Stable public fields cover high-value lifecycle paths; constructor `ArgumentError` and rare internal message-only faults prevent a higher score. |
| Inspection | 8.5 | Pass | Author groups derive from complete facts; real downstream readers must judge whether the detail is well prioritized. |
| GPU expectation clarity | 9.0 | Pass | Deferred first-run compilation and forbidden fallback are honest; no portable preflight exists. |
| Backend qualification workflow | 8.0 pending exact run | Block until bundle passes | Driver design meets the record contract, but an unexecuted driver is not evidence. |
| Internal maintainability | 7.5 | Pass with explicit debt | Shared authorities and closed mechanisms are sound; roughly 9,000 lines and the legacy adapter still impose substantial change cost. |

Perspective ballots before exact qualification:

- scientific example reader: **pass for freeze, 10/10 deferred to LW-5**;
- heterogeneous domain author: **pass, with legacy vocabulary closed**;
- unrelated external author: **pass, contingent on structured diagnostic and
  Metal extension evidence**;
- JuliaGPU qualification maintainer: **block until the exact CPU/Metal bundle
  passes; no architectural objection**;
- LocalWorksets contributor: **pass with legacy/consolidation debt preserved;
  reject new mechanisms before LW-5**.

These are lens ballots, not the fresh LW-R2 committee freeze ballots. The
committee must review the exact sealed candidate bundle independently, preserve
substantive dissent, and ballot again.

## Freeze conclusion

The bounded usability work required before freeze is: structured public
diagnostics on high-value paths, derived author inspection, honest GPU states,
automatic workspace across every retained mechanism, an explicit legacy
migration rule, and one exact qualification bundle. These changes improve
cohesion without another lifecycle, public policy system, scheduler, compiler
surface, or topology language.

LW-5 remains the decisive value test. If several real operations still need
large LocalWorksets-specific adapters, manual scratch, or internal descriptor
knowledge, the authoring surface must be simplified before admitting further
mechanisms.
