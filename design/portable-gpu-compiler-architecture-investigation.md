# Portable GPU compiler architecture investigation

This record owns the cross-package investigation of the portable execution
ladder:

```text
Potts authoring
→ semantic normalization
→ CorePotts operational recipes
→ LocalMath execution laws
→ portable KernelAbstractions kernels
→ selected backend
```

It is an engineering diagnostic, not a second compiler specification or a
qualification framework. Ordinary package tests and reproducible benchmarks
remain authoritative. Production scientific kernels remain portable
KernelAbstractions kernels; Metal is a hardware witness, not an authoring
target.

## Decision tuples

- Historical control: LocalMath `a26cbfe`, CorePotts `b4e5bda5`, Potts
  `2d317fc0`.
- Current decision tuple: LocalMath C15 content `b68952a`, CorePotts
  `b4e5bda5`, Potts `6c5344d6`.
- Compiler baseline: Julia 1.12.6, KernelAbstractions 0.9.42,
  GPUCompiler 1.23.0, Metal 1.10.0.

KaimonCompilerTools must be registered in a fresh Kaimon session before any
owner package is loaded. Compiler counts below are attribution evidence, not
brittle CI limits.

## Upstream executable-identity contract

Pinned source establishes this effective device-artifact identity:

```text
KA generated callable type
+ converted kernel argument tuple type
→ Julia MethodInstance
+ world age
+ GPUCompiler configuration
+ backend device/context
→ backend artifact
```

KernelAbstractions gives each `@kernel` definition a durable named callable.
GPUCompiler resolves the concrete callable and argument tuple to a
MethodInstance and keys compilation on that MethodInstance, world and compiler
configuration. Metal and CUDA both use this mechanism. Runtime values reuse an
artifact when their types are unchanged; source-site closure types, static
tuple shapes, `Val` values and broad nested payload types do not.

The ecosystem response is therefore compact named operation families and
runtime data—not a universal interpreter, device dispatch, a kernel registry,
or an ecosystem-owned compiler cache.

## Retained LocalMath boundaries

- C15 keeps extent, capacity and active count out of pointwise segmentation
  identity. Author rename, captured value changes and extent 16 → 24 reuse the
  exact prepared type and existing KA family.
- `_PreparedStageProgram` erases graph shape behind an explicit heterogeneous
  host barrier. Device launch re-specializes only at the prepared operation
  family.
- `_StageDraft` and `_StageEvaluation` exclude the authored stage, source
  origin and completed graph before device launch.
- Collection, keyed reduction, fold and relationship workgroups are bounded
  operation-family laws while `ndrange` remains runtime data.
- Arbitrary user closures remain a legitimate extension point. LocalMath
  cannot equate closures from different source sites; Potts and CorePotts must
  lower common semantics to durable named evaluator types.

The current four-member pointwise fusion law is retained until the real-Metal
fusion matrix demonstrates a portable alternative with a better cold/warm
tradeoff. Source inspection alone does not justify an alternate executor.

## Current specialization atlas

The current C15 pointwise canary produced 8,319 first-family inference records.
Subsequent runtime value, author-name and extent variants produced 6, 13 and 13
records respectively without adding LocalMath-owned MethodInstances. Repeated
8- and 16-stage programs reused the same four-member physical launch family;
their remaining growth was host planning for additional segments. Equivalent
closures from different source sites and deliberately different evaluator
types created new KA families, as required by Julia callable identity.

For a two-aggregate Potts model, late-lowering first-family attribution is:

| Boundary | Fresh inference records |
| --- | ---: |
| Site-aggregate lowering | 531 |
| Remaining tracker-plan lowering | 725 |
| Descriptor lowering | 2,074 |
| Stage lowering | 487 |
| Lifecycle lowering | 76 |
| Core program construction | 2,963 |

Author-only rename, declaration reorder and changed parameter value reuse the
same tracker, descriptor, stage, lifecycle and compiled-Core types. After the
first family, those variants add only the KCT root record at each isolated
boundary. The current late-lowering path therefore does not leak those facts
into execution identity.

## Corrected: runtime parameter names

The audited R50 baseline stored its author-facing `NamedTuple` keys in a type
parameter. Equivalent parameter renames therefore gave `PottsProblem` and
`PottsIntegrator` different concrete types even though lowering later erased
the name:

```text
PottsParameters{Any,Tuple{Float64},@NamedTuple{gain::Float64}}
PottsParameters{Any,Tuple{Float64},@NamedTuple{renamed_gain::Float64}}
```

After warming one model, initializing its renamed equivalent adds 43 inference
records. The qualified R50 correction stores names as tuple values while
retaining parameter count and value shapes in the type. The renamed model then
reuses the problem and integrator families and adds only the KCT root record.
`p[name]` and `propertynames(p)` are preserved; KCT AllocCheck reports no
possible allocation for symbolic lookup and JET reports no optimization error
for physical parameter-buffer construction.

R50 base commit `61745a52` now owns the correction. It places names in a
runtime `_RuntimeParameterSchema`, preserves the public named view, and removes
the schema contents from `PottsParameters` type identity. A separately prepared
duplicate was closed rather than merged after the base advance was discovered.

The focused ordinary parameter-contract test has passed with the correction.
On the functional current Metal stack, the existing whole/indexed vector
parameter witness passed all 132 CPU/Metal assertions with scalar indexing
disabled. Its cold run took 15 minutes 16 seconds, reinforcing that the wider
cold-compilation investigation remains necessary; the correction itself did
not add a backend-specific path. Complete behavioral validation produced 5,085
passing assertions. The only
initial package-quality failures observed during that run came from a temporary
local path inserted into the committed Metal manifest; after restoring
immutable repository revisions, package quality passed 48/48.

## Open CorePotts frontier

A small checkerboard model's complete execution-workspace type renders to more
than 129,000 characters. The nested type includes complete tracker and accepted
update plans, checkerboard/lifecycle plans and prepared law families. This is
not automatically a defect: expression and storage ABI differences can be
legitimate. It does make monolithic compiler diagnostics unusable and fresh
checkerboard initialization takes several minutes, so investigation must
continue at narrower semantic owners.

The first concrete suspect is compiler-generated tracker publication labels in
`_SiteSumOwnershipEvaluator`, `_CheckerboardOwnerValueEvaluator` and
`_CheckerboardMomentTrackerEvaluator`. Each label selects a single publication
field but currently participates in evaluator type identity. The candidate law
is a fixed internal `:value` port with diagnostic labels retained on the host.
It belongs to R49 only if tracker-index/count matrices show reduced
MethodInstances and KA families without moving work or changing behavior.

Future Core work must separately attribute:

1. host construction of `CheckerboardKernelProgram`;
2. adaptation of program/state storage;
3. scientific declaration construction;
4. accepted-update and tracker declarations;
5. LocalMath plan/prepare for each color bank;
6. per-step enqueue, settlement and inspection.

No completed model graph may become a kernel type identity merely to make
checkerboard conflict closure generic. R12/R13 continue to own that semantic
work, using runtime conflict data and reusable execution laws.

## Rejected hypothesis

Making two aggregate-lowering call sites consume `AnalyzedSiteAggregate`
directly reduced a partially warmed subcall from 531 to 329 inference records
and JET reports from 350 to 346. A clean matched-process measurement of the
complete tracker-plan boundary was exactly 1,028 inference records before and
after. The apparent improvement only moved work. The prototype is rejected and
does not enter production or the PR count.

## Backend availability and attribution

The historical Metal 1.10.0/GPUCompiler 1.23.0 tuple is unavailable after the
host moved to macOS 27: `Metal.functional()` is false and `versioninfo()`
reports no devices. Metal 1.11.1/GPUCompiler 2.8.1 sees the M1 Pro and is
functional. The current compatible stack is therefore the active hardware
validation target; the old tuple is retained only as audit provenance.

This is classified upstream/environmental. No project kernel or backend
shortcut may work around it. A normal dependency update is a separate decision
if the project chooses to support macOS 27 through the newer stack.

The supplemental current-backend run is complete. With KernelAbstractions
0.9.42, Metal 1.11.1 and GPUCompiler 2.8.1, the unmodified C15 LocalMath
production path passed all 592 real-Metal assertions with scalar indexing
disabled. The suite covered stage programs, receipt settlement, syntax and
authoring, tiny-domain oracles, pointwise/reduction/collection laws, keyed
reduction, both ordered-fold traversal laws, relationships, publication and
cross-domain scientific witnesses. This demonstrates portable behavior on the
functional current stack; it does not retroactively make the unavailable
Metal 1.10.0 stack a valid hardware result.

The dependency policy is now to support and validate the latest compatible
released package stack. Historical tuples remain audit provenance only, not
development or compatibility targets. Dependency upgrades must still preserve
the same portable KernelAbstractions scientific path and pass ordinary CPU and
real-hardware tests.

Potts PR #63 updates the reproducible Metal profile to current compatible
external releases, including Metal 1.11.1, GPUCompiler 2.8.1, DiffEqGPU 3.21.2,
ModelingToolkit 11.44.0, ModelingToolkitBase 1.74.0, SciMLBase 3.55.0,
LLVM 9.13.1 and Symbolics 7.40.0. The complete profile precompiled, package
quality passed 48/48, and the real-Metal vector-parameter witness passed
132/132 with scalar indexing disabled. A clean profile precompile took about
76 minutes and the focused witness 11 minutes 6 seconds; these are benchmark
evidence, not CI thresholds.

Internal source heads cannot yet be advanced independently. CorePotts `main`
contains the V2 RNG cutover but lacks later R49 SPI consumed by the active R50
lineage. The Metal profile therefore pins the current compatible LocalMath C15,
CorePotts R49 and Potts R50 commits while external dependencies are current.
Joining the internal heads requires the already-approved direct RNG/API
cutover on the later compatible lineage; no compatibility alias is permitted.

The active exact-replay environment has also been refreshed to the current
released SciML stack. The production replay row now targets
ModelingToolkit 11.44.0, ModelingToolkitBase 1.74.0, SciMLBase 3.55.0,
SymbolicIndexingInterface 0.3.55, Symbolics 7.40.0,
OrdinaryDiffEqTsit5 2.1.4 and MethodOfLines 1.5.1. An isolated direct-cutover
prototype passed all 249 existing checkpoint/restart and MethodOfLines replay
assertions before the row was changed. The docs and ordinary integration
environments admit MethodOfLines 1.x as well as the still-supported 0.11 line.

The latest Metal native stack is functionally current, but its exact-replay
row has not been advanced. On DiffEqGPU 3.21.2 the former bounded-failure
witness no longer induces a failed solve, even with the explicit one-iteration
bound used by the CPU witness. The success, deterministic replay and
checkpoint cases pass, but failure atomicity has not been re-demonstrated.
The older Metal exact-replay tuple therefore remains a closed evidence row;
latest Metal execution remains functional without claiming that stronger
guarantee. This is an upstream-behavior investigation, not permission to
weaken rollback tests.

## Remaining gates

- Resolve the latest compatible dependency stack across LocalMath, CorePotts,
  Potts and PottsModels, then repeat CPU and real-Metal validation. Potts'
  active Metal and exact CPU replay environments are current in PR #63; the
  remaining work is the sibling-package environment audit and the latest
  Metal-native failure-atomicity qualification.
- Finish 1/2/4/8/16/32 pointwise fusion and operation-family matrices.
- Attribute tracker-index labels and the broad checkerboard program/state
  boundary with fresh KCT processes.
- Decompose first-model and subsequent-model compilation into Julia inference,
  KA construction, GPUCompiler/LLVM, backend library creation and pipeline
  creation.
- Measure warm allocation, synchronization and transfer controls separately.
- Rerun after corrected R10/R11 and against the G09/R52–R54 model corpus.

The identified PR count remains 69. The demonstrated parameter-name correction
fits R50; no additional LocalMath or CorePotts companion has qualified.
