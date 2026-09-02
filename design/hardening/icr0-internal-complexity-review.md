# IC-R0 internal-complexity and Julian-design review

Status: passed; exact product qualified and review sealed

Date: 2026-08-13

Baseline commit: `b73dd89ca3f8ff79c145a00b0bdbaac8f139b3c7`

Baseline tree: `11debc5eb7dc56bfbc50dbdfc4c7e9d0a6d5d9b0`

Qualified product commit: `8b710692a84f79b1411a1443a27a9ee099327bcf`

Qualified product tree: `b360f2b06b404b34d448c75f3bdd5b012d839dc7`

Scope: the production and active verification surfaces of LocalWorksets,
CorePotts, and PottsToolkit. This is a bounded behavior-preserving hold before
LW-5 adoption, not a feature phase, public redesign, or performance campaign.

## Decision rule

IC succeeds only when the code becomes easier to understand, extend, and
verify without weakening a scientific, admission, determinism, lifetime,
checkpoint, or backend guarantee. Line reduction is evidence of clearer
ownership, not a target.

Every changed abstraction must answer four questions:

1. Which distinct behaviors or external consumers require it?
2. What safety, dispatch, inference, or performance property does it enforce?
3. Is ordinary Julia dispatch or a small shared function sufficient instead?
4. Which focused and complete tests prove that consolidation preserved meaning?

The pass follows Julia's documented preference for generic functions,
ordinary interfaces, minimally constrained arguments, and restrained use of
type parameters and metaprogramming:

- [Julia style guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- [Julia interfaces](https://docs.julialang.org/en/v1/manual/interfaces/)
- [Julia performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [KernelAbstractions quick start](https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/)
- [KernelAbstractions backend implementation contract](https://juliagpu.github.io/KernelAbstractions.jl/stable/implementations/)

KernelAbstractions continues to own portable asynchronous kernel execution and
implicit ordering. This pass introduces no stream, scheduler, event graph,
backend branch, hidden synchronization, or execution family.

## Audit result

The three packages are large because they implement substantial semantics, not
because one removable framework dominates them. The audit did find small,
confirmed instances of accidental hierarchy, structural reconstruction,
validation, finalization, and verification duplication. Those are corrected
below. It did not find a responsible basis for flattening public protocol
hierarchies, merging qualified execution lowerings, splitting large files by
line count, deleting reference implementations, or pruning a public SPI in a
contract-preserving phase.

### Abstraction disposition

| Candidate | Finding | Disposition |
| --- | --- | --- |
| LocalWorksets `_AbstractCombinationLaw` | Private hierarchy with one concrete child; no dispatch or extension contract used the parent. | Remove the abstract parent. Generic constructor rejection still rejects counterfeit laws. |
| PottsToolkit `AbstractSolverPolicy` | Private hierarchy with one singleton child; the parent carried no field, method, or extension contract. | Remove the abstract parent while preserving `DiscreteFieldEuler`. |
| LocalWorksets `_AbstractProviderLane` | One package implementation, but hostile fake-lane tests and inspection/admission dispatch use the boundary. | Retain: it is a security and inspection protocol, not an enum modeled as types. |
| CorePotts evaluator, footprint, lifecycle, tracker, and backend abstract types | Multiple concrete behaviors or named public SPI extension dimensions. | Retain. Public contract reduction requires a separate compatibility decision and real external-consumer inventory. |
| LocalWorksets generic, combined, resolved, and conjunctive lowerings | Similar validation vocabulary but distinct qualified launch, workspace, conflict, and determinism obligations. LW-4C already consolidated their shared safe machinery. | Retain measured specializations; no false unification. Revisit only with replacement parity and performance evidence. |
| Large checkerboard, sequential, MTK extension, native, and compiler files | Cohesive but broad responsibility regions; no safe split independently reduced ownership or invalidation cost in this pass. | Preserve the ED-R0 waivers through the first LW-5 pilot. Split only around a material change with an explicit include boundary and affected evidence. |

The production census changes from 694 declared types, including 99 abstract
types, to 692 and 97. The 13 generated functions and 24 `eval`/`@eval`
occurrences are unchanged; this pass does not replace established statement or
device-specialization generation with a new metaprogramming layer.

### Confirmed consolidation

| ID | Change | Preserved contract |
| --- | --- | --- |
| IC-01 | Replace two decorative private one-child hierarchies with plain concrete types. | Public names, constructors, fingerprints, operation semantics, and counterfeit-declaration rejection remain unchanged. |
| IC-02 | Make one `_rebuild_program_runtime` helper the authority for structural `ProgramRuntime` reconstruction. | Adapted and LocalWorksets-candidate runtimes preserve every field and specialize on the new capability/workspace types. |
| IC-03 | Share positive bank/slot validation between `StateHandle` and `WorkspaceHandle`. | Exact state/workspace diagnostics and `Int32` representation remain unchanged. |
| IC-04 | Share identical lifecycle finalizers over two small closed unions instead of five method bodies. | Create/transition/divide remain no-ops; remove/retire still clear the staged kind and report one finalized anchor. |
| IC-05 | Remove the stale `test/fast/runtests.jl` shadow inventory, give the package runner domain names, perform the private MTK scheduling scan in the existing active-file quality walk, and consolidate three irreversible CorePotts adapter processes into two honest method-world profiles. | The complete root suite remains the sole package inventory; no assertion, attack, or active test file is omitted. |
| IC-06 | Make both CorePotts SPI modules explicit pure facades; move the lone `rng_contract_identity` wrapper to CorePotts authority and re-import it. | The public BackendSPI spelling and value are unchanged. Tests require disjoint SPI names and exact binding identity with CorePotts. |
| IC-07 | Document role-based SPI selection and verification tiers. | No new registry, nested namespace, wrapper API, test framework, or release ceremony is created. |
| IC-08 | Make the ordinary real-Metal runner semantic by default; run its existing 1,000-pair cross-domain and 50-batch LW-3 performance profiles only when `LW4_PERF_SAMPLES` is explicitly selected, and print compact summaries while retaining serialized raw evidence. | Semantic/lifetime/direct-parity/admission checks remain unchanged. The historical qualification driver already sets the reviewed performance profile, so performance evidence remains available and fail closed. |
| IC-09 | Run the bounded [Symbolics evaluator feasibility sub-gate](ic-symbolics-feasibility.md) against the existing analyzed graph and frozen evaluator. | Adoption is vetoed: ordinary symbolic construction changes `OrderedFold` floating order, while opaque folds or complete generated accessors retain/recreate the existing evaluator and expand complexity. No production code, API, dependency, fingerprint, checkpoint, or LocalWorksets change results. |

## SPI organization and admission

The repository has four distinct extension-facing surfaces:

- PottsToolkit has 76 unexported public bindings, grouped into scientific
  compiler transfer, native MTK/SciML component integration, and stable
  diagnostics/inspection;
- `CorePotts.CompilerSPI` has 245 public bindings;
- `CorePotts.BackendSPI` has 136 public bindings; and
- LocalWorksets has 22 exports plus intentionally unexported `inspect`, with
  its extension rules expressed through the same ordinary lifecycle.

The CorePotts SPI name sets are disjoint. Their breadth is substantial, but
raw count is not enough to safely prune a pre-1.0 compiler/runtime protocol
used by package extensions. The maintainable organization is explicit flat
surfaces selected by role:

| Author | Surface | Responsibility |
| --- | --- | --- |
| Scientific model author | exported PottsToolkit API | biology and model composition; no SPI |
| Scientific term or operation package | PottsToolkit transfer API plus the minimum `CompilerSPI` bindings | validated compiler IR construction and inspection |
| Runtime or backend package | minimum `BackendSPI` bindings | capability admission, adaptation, transactions, enqueue/settlement, and checkpoint validation |
| Local-work extension | LocalWorksets public extension protocol | declarative local connectivity/output semantics lowered centrally |
| MTK/SciML integration | Julia package extension and upstream public interfaces | symbolic/system integration, not a CorePotts SPI role by default |

The source intentionally groups PottsToolkit and LocalWorksets declarations
with comments and repeats explicit `import` and `public` lists in the CorePotts
facades. Replacing them with an export macro or runtime registry would save
lines while hiding ownership from Julia tooling and making accidental surface
growth easier. Nested role modules would add qualification ceremony without
creating a new dispatch or dependency boundary. LocalWorksets is small enough
that a second `ExtensionSPI` namespace would duplicate its documented Level-2
and extension lifecycle rather than clarify it.

Every future SPI addition must identify:

1. the owning package and role;
2. a concrete external consumer that cannot use an existing generic;
3. the minimum methods and semantic laws required;
4. a positive contract test and a negative boundary/admission test;
5. whether the binding aliases CorePotts authority or why an SPI-owned
   implementation is unavoidable; and
6. for backend behavior, the exact qualification identity that admits it.

External code cannot self-authorize compiler or backend capability. IC-R0 does
not remove existing public SPI bindings; that would require a separate public
compatibility audit and external-consumer evidence.

The Symbolics sub-gate also rejects using generated callables as a new SPI.
Arithmetic islands would require a second callable/reconstruction contract,
while complete evaluator generation would either call hostile public dispatch
or expose CorePotts private context access. Neither improves the role boundary.

## Verification ownership and cost

The root had two competing inventories: the complete package runner and an
unreferenced `test/fast/runtests.jl` that duplicated 19 of 21 package tests,
omitted package-quality and statement coverage, and was not used by CI,
documentation, scripts, or contributor instructions. It is deleted rather
than maintained as a misleading second authority.

The remaining workflow has four ordinary levels:

1. a self-contained focused test during the edit loop;
2. the complete suite for every changed package before handoff;
3. behavioral integration and strict docs when those boundaries change; and
4. qualified hardware evidence only when device execution, adaptation,
   admission, lifetime, or evidence changes.

CorePotts also launched three fresh Julia processes for three hostile method-
world attacks. Broad `run!` and broad `wait` replacements can honestly share
one irreversible world. The more-specific cached-executor attack cannot share
that world because the broad replacement must make a later uncached submission
reject. The suite now uses two final fresh processes while retaining broad
`run!`, broad `wait`, more-specific `run!`/`wait`, cached-executor,
unsubmitted-rejection, drain, lease, and poison assertions.

Historical frozen bundles are evidence for their exact commits, not another
active suite. A changed contract explicitly invalidates its relevant evidence;
elapsed wall time alone never does. The complete package suite remains required
at IC-R0, so targeted success cannot be mistaken for gate success.

The ordinary real-Metal runner also used to execute two 1,000-pair cross-domain
campaigns and a 50-batch LW-3 noninferiority comparison unconditionally, then
print their raw sample vectors. That contradicted the documented rule that
benchmarks are manually dispatched. The runner now performs semantic,
lifetime, direct-parity, and admission qualification by default. The existing
reviewed `LW4_PERF_SAMPLES=1000` or `2000` profile opts into all unchanged
campaigns; the historical qualification driver already supplies that profile
and serialized results still retain every raw sample. Console output is a
compact ratio/upper-bound summary. IC-R0 does not require a fresh performance
campaign because no measured execution path changed.

## Descriptive before/after metrics

| Boundary | Baseline production | Candidate production | Delta | Baseline tests | Candidate tests | Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| PottsToolkit `src` | 24,089 | 24,093 | +4 | 12,058 | 12,004 | -54 |
| PottsToolkit extensions | 2,196 | 2,196 | 0 | - | - | - |
| Integration | - | - | - | 2,213 | 2,213 | 0 |
| CorePotts | 23,224 | 23,202 | -22 | 5,152 | 5,210 | +58 |
| LocalWorksets | 9,150 | 9,152 | +2 | 4,731 | 4,729 | -2 |
| Total | 58,659 | 58,643 | -16 | 24,154 | 24,156 | +2 |

The net production reduction includes five new comments that make extension
roles visible. Test lines are essentially flat: 33 deleted lines were a stale
shadow runner, while CorePotts gains direct shared-validation and SPI-facade
invariants. The real-Metal harness grows from 281 to 326 lines to make three
costly benchmark campaigns explicit and preserve compact/manual evidence; its
ordinary path executes none of those campaigns. Public surfaces and package
dependencies are unchanged.

## IC-R0 qualification matrix

IC-R0 does not pass from focused tests alone. The exact candidate requires:

| Boundary | Required result |
| --- | --- |
| LocalWorksets complete CPU suite | API, mechanisms, lifetime, admission, package quality, and removed-hierarchy regression pass. |
| CorePotts complete CPU suite | direct/LocalWorksets execution, RNG, lifecycle, checkpoint, capability, handle validation, SPI identity, package quality, and hostile-world tests pass. |
| PottsToolkit complete CPU suite | all active package tests pass from the sole test inventory. |
| Cross-domain witnesses | LBM, springs, matrix-free FEM, z-buffer, launch/allocation, and inspection evidence pass. |
| Behavioral integration | MTK/MTSL, Catalyst, MethodOfLines, native serial/batched execution, Unitful, extension loading, and load order pass in the qualified environment. |
| Strict documentation | doctests, executable examples, references, and HTML build pass. |
| Qualified real Metal | relevant LocalWorksets and CorePotts execution/lifetime evidence passes without source or qualification weakening. |
| Static gates | Runic on touched Julia files, `git diff --check`, parse/load, public-surface counts, zero owned ambiguities, ExplicitImports, include/test inventory, and no empty active directories pass. |

No throughput rerun is required because no kernel, launch sequence, workspace,
wait, or measured execution path changes. Existing direct/reference and
cross-domain performance witnesses remain the baseline; any unexpected
regression during the complete suites blocks and triggers investigation.

### Candidate qualification state

| Boundary | Current result |
| --- | --- |
| LocalWorksets complete CPU suite | Pass on the candidate source: API, all bounded mechanisms, lifetime/admission attacks, and package quality completed with exit 0. |
| CorePotts complete CPU suite | Pass on the candidate source, including the two fresh method-world profiles and the new handle/SPI invariants. |
| PottsToolkit complete CPU suite | Pass: 2,633/2,633 in 20m17.2s. The elapsed time is descriptive, not an admission property. |
| Cross-domain CPU witnesses | Pass with LBM, deterministic/fast springs, matrix-free FEM, z-buffer, launch/wait/allocation, rejection, and inspection evidence. |
| Behavioral integration | Pass with exit 0 on Julia 1.12.1 across MTK/MTSL, Catalyst, MethodOfLines, native serial/batched execution, Unitful, distribution, and extension/load-order cases. |
| Strict documentation | Pass with doctests, checks, cross-references, and HTML rendering. |
| Symbolics feasibility | Pass with adoption veto; see [IC-SYM](ic-symbolics-feasibility.md). No production change results. |
| Qualified real Metal | Pass with exit 0 on the exact product commit using one real Apple M1 Pro device: fresh extension orders 2/2, cross-domain witnesses 8/8, native components 37/37, LocalWorksets/CorePotts semantic, lifetime, implicit-order, one-final-wait, queued-settlement, boundary/workgroup, lifecycle-policy, direct-parity, poisoning, and fail-closed admission evidence all passed. The three opt-in throughput campaigns were absent from this semantic run as designed. |
| Static gates | Pass: Runic made no changes; 297 Julia, 170 TOML, and four workflow YAML files parse; `git diff --check`, public-surface/SPI identity, ambiguity/ExplicitImports, active test inventory, and empty-directory checks pass. |

An initial post-edit Metal attempt reported no devices inside the filesystem
sandbox while IOKit still showed the active GPU. Repeating the exact command
with real-device access exposed one functional M1 Pro and completed the full
runner. No waiver or inherited pass was used. The disposable Symbolics Expr and
dropped-RGF probes also compiled and executed on that device; their separate
ordered-arithmetic failure still vetoes adoption.

## Review questions

The final exact-tree review answers separately:

1. Did every edit remove confirmed complexity rather than move or rename it?
2. Did any public name, semantic identity, backend claim, or scientific result change?
3. Are all retained abstractions justified by multiple behaviors, external
   extensibility, security, or measured specialization?
4. Are the two SPIs role-separated, pure facades, inspectable, and protected
   from unreviewed growth without inventing a plugin framework?
5. Is there one authoritative active test inventory and a proportional,
   documented invalidation rule?
6. Does anything make LW-5 adoption or eventual maintenance harder?

### Final exact-tree ballot

1. **Confirmed complexity was removed rather than renamed.** The only removed
   types had no dispatch or extension role; shared reconstruction, validation,
   finalization, and verification now have one owner.
2. **No public or scientific contract changed.** Public counts, exact SPI
   binding identity, fingerprints, RNG/checkpoint behavior, deterministic
   folding, execution results, and backend admission remain qualified.
3. **Retained abstractions earn their cost.** They represent multiple concrete
   behaviors, hostile-boundary security, external extensibility, or
   performance-qualified lowerings; speculative flattening was vetoed.
4. **The SPIs are maintainable flat facades.** Compiler and backend names are
   disjoint, alias CorePotts authority exactly, are selected by author role,
   and gain no registry or self-authorization path.
5. **Verification has one active inventory and proportional invalidation.** The
   stale shadow runner is deleted, hostile worlds are consolidated without
   losing attacks, and expensive Metal performance campaigns are explicit.
6. **LW-5 is easier, not harder, to begin.** The authoring and ownership seams
   are clearer, while direct/reference oracles and all LocalWorksets safeguards
   remain available for the first evidence-bearing adoption pilot.

Final review: **PASS**, P0=0, P1=0, P2=0, with no carried finding. The Symbolics
question is a concluded adoption veto, not deferred remediation.

Passing IC-R0 authorizes only the already specified
LW-5 representability inventory and first evidence-bearing pilot. It does not
authorize a new execution family, broad adapter framework, public API redesign,
direct-oracle deletion, or G6.

The deferred MethodOfLines input-field integration remains deferred exactly as
currently documented.
