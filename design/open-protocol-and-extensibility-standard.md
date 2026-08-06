# Open Protocol and Extensibility Standard

Status: Accepted engineering standard

Current disposition: compatible open-protocol principles survive. Exact public names, backend
inventories, capability promotion, and CorePotts API breadth are requalified by the
[G5H Hardening Contract](../spec/symbolic-potts-v1-hardening.md).

## Purpose

Potts.jl is intended to be both a high-performance Cellular Potts engine and an extensible Julia
scientific library. Extensibility therefore cannot mean accepting arbitrary runtime callbacks, and
GPU performance cannot mean hard-coding every supported scientific family into CorePotts.

This standard defines how CorePotts and PottsToolkit remain open to new scientific behavior while
retaining inference, compilation, device execution, reproducibility, validation, and semantic
provenance. It governs new protocols and revisions to existing protocols.

The accompanying [open-protocol audit](audits/open-protocol-audit.md) applies these rules to the
current specifications and implementation.

## Governing Principle

Scientific invariants and semantic taxonomies MAY be closed. Scientific families and execution
mechanisms MUST be open protocols with qualified built-in implementations unless a specification
explicitly declares a closed, versioned set.

A list of built-in implementations does not define the complete extension surface.

Examples:

- Exactly one owner per lattice site is a closed invariant.
- Hamiltonian, drive, hard-constraint, mechanical, tracker, and lifecycle classifications are a
  controlled scientific taxonomy.
- Random, major-axis, minor-axis, and vector-directed division are built-in division geometries,
  not the complete division protocol.
- CPU, Metal, and ROCm are the currently required qualified backends, not the only backend types
  that CorePotts may ever recognize.
- Level 1 portable DSL syntax is closed and versioned; Level 2 and Level 3 scientific construction
  use ordinary Julia extension protocols.

## What Open Means

A protocol is open when an independent package can add a conforming implementation by defining a
new type and methods on documented public functions, without:

- editing a central `Union`, enum, `isa` ladder, registry, or switch in CorePotts;
- depending on underscored functions or concrete cache fields;
- pirating methods on types owned entirely by other packages;
- changing the semantic meaning of existing implementations; or
- weakening validation, provenance, device compatibility, or conformance requirements.

Open does not mean that every extension is supported by every algorithm or backend. An extension
declares requirements, effects, and capabilities. Model compilation either produces a qualified
execution plan or reports the precise incompatibility before execution.

## What Closed Means

A closed set is appropriate when exhaustiveness is itself part of the contract. Examples include:

- finite state-machine outcomes local to one versioned algorithm;
- state invariants and transaction phases;
- versioned portable syntax and serialization tags;
- reproducibility-critical numeric encodings within one RNG contract version;
- semantic categories needed to distinguish equilibrium, kinetics, lifecycle, and diagnostics;
- currently supported and paper-qualified feature inventories.

Every closed public set MUST document:

1. Why exhaustiveness is necessary.
2. Whether the set is global or local to one protocol implementation.
3. How an incompatible new concept receives a new contract or semantic version.
4. Why ordinary multiple dispatch is insufficient or unsafe for the purpose.

An enum is a representation choice, not proof that a set should be scientifically closed.

## Julia-Native Protocol Shape

### Small required interface

Each protocol exposes the smallest set of essential generic functions. Rich behavior is derived
from those functions when a correct generic implementation exists. Essential operations have no
misleading fallback; optional traits have conservative typed defaults.

Conceptually:

```julia
function division_partition end
function division_requirements end
function division_capabilities end

division_capabilities(::Any) = UnsupportedDivisionCapabilities()
```

The final names are selected during the owning API phase. The important contract is that downstream
packages extend imported public functions rather than populate callback dictionaries.

### Semantic types, orthogonal traits

Abstract types communicate genuine scientific categories. Orthogonal facts such as device
compatibility, dimensionality, access scope, serialization, determinism, and workspace needs are
traits or typed capability values rather than deep inheritance.

Subtyping does not establish conformance. Public validators check required methods and return
values before compilation.

### Immutable parametric values

Scientific definitions and compiled policy descriptors use immutable parametric structs. Callable
values are stored by concrete type, not in `Function`-typed fields. Hot execution receives concrete
types through a function barrier.

Host authoring may use dynamic collections. Compilation canonicalizes and lowers them into concrete
tuples, homogeneous groups, structure-of-arrays storage, or other measured representations. The
input container is not the device execution layout.

### Dispatch instead of behavioral switching

Adding a behavioral family MUST NOT require appending another branch to a central `isa` chain or
another member to a method-signature `Union`. Dispatch on the policy value:

```julia
division_partition(policy::MyGeometry, context, site)
```

instead of switching in the engine:

```julia
if policy isa RandomGeometry
    # ...
elseif policy isa AxisGeometry
    # ...
end
```

Small unions such as `Union{T,Nothing}` and finite internal result tags remain valid when they are
not extension boundaries.

### No incidental registration

Direct CorePotts Level 3 use relies on Julia dispatch and does not require a global runtime plugin
registry. PottsToolkit registries are permitted at boundaries that genuinely need stable names:

- Level 1 DSL parsing and normalization;
- semantic serialization and reconstruction;
- compatibility import/export; and
- discoverable model-fragment naming.

Registration provides a spelling or durable identity. It MUST NOT be required merely to make an
ordinary CorePotts method executable.

### Package extensions for optional dependencies

Backend runtimes, storage formats, visualization systems, and other optional integrations use Julia
package extensions and weak dependencies. CorePotts owns the generic function; the extension adds
methods involving at least one type owned by CorePotts or the optional dependency. Type piracy is
prohibited.

## Two-Stage Extension Model

Potts.jl uses two deliberately different forms of openness:

1. **Host scientific openness** — ordinary Julia types and methods describe a model and may use
   flexible construction-time data.
2. **Compiled execution openness** — the compiler lowers accepted scientific values into concrete,
   bounded, device-valid descriptors and operations.

An extension may be valid for host reference execution without being valid on a requested GPU. That
limitation is explicit in its capabilities. A stable paper-facing component intended for the
hardware-agnostic API MUST provide the required CPU, Metal, and ROCm evidence.

The compiler boundary is a function barrier. Dynamic authoring work occurs before it; the MCS hot
path operates on concrete compiled values after it.

The host scientific object itself does not have to be a bitstype. Its GPU-qualified lowering MUST
produce immutable bitstype-compatible descriptors and device storage. Extension-owned lowering
preserves scientific identity and structure; centralized engine adaptation moves only the compiled
storage representation.

## Device-Executable Open Protocols

Open protocols used inside a GPU step MUST support static specialization without runtime device
dispatch. A GPU-valid implementation has:

- an immutable device-valid definition or compiled descriptor;
- concrete argument types at each kernel boundary;
- allocation-free, exception-free device methods;
- bounded loops or explicitly bounded workspaces;
- declared reads, writes, effects, RNG addresses, and atomic or reduction requirements;
- no strings, dictionaries, heap-backed vectors inside scalar policy objects, host closures,
  reflection, or hidden synchronization;
- a portable KernelAbstractions implementation before any optional backend specialization; and
- actual compile-and-run conformance on every claimed backend.

A lifecycle component is GPU-compatible only when its complete trigger, planning, conflict,
transformation, RNG, validation, and commit path is device-executable. Partial lowering with hidden
host evaluation is invalid.

An open protocol does not require dynamic dispatch in a kernel. Julia specializes a generic method
for the concrete policy types embedded in the compiled plan. When heterogeneous counts would cause
unbounded specialization or code size, compilation groups operations into a finite number of
homogeneous execution batches or lowers them to a versioned typed IR.

KernelAbstractions launch ordering is execution machinery, not biological event ordering. Atomics
resolve memory access only; they never define scientific priority or conflict semantics.

## Required Protocol Metadata

Every stable scientific extension declares, as applicable:

- stable semantic identity and contract version;
- scientific category and mathematical meaning;
- required properties, observables, relations, and fields;
- read, write, effect, conflict, and lifecycle scopes;
- dimensional, numerical, RNG, backend, and algorithm requirements;
- reference behavior and conformance evidence;
- workspace and synchronization behavior;
- provenance and semantic serialization support; and
- explicit unsupported combinations.

Capabilities are evidence-backed claims, not optimistic booleans. Unknown capability requirements
fail conservatively with an actionable construction-time report.

## Protocol Families Requiring Open Interfaces

The following families MUST be open even though the paper release supplies a finite built-in set:

- algorithms and proposal processes;
- acceptance laws and kinetic modifiers;
- energies, drives, hard constraints, trackers, observables, and mechanics;
- lifecycle schedules, triggers, conflict resolvers, effects, division geometries, inheritance,
  transition, death, retirement, and auxiliary lifecycle policies;
- initialization sources, rasterizers, placement policies, and overlap resolvers;
- topology, geometry, domains, spatial relations, metrics, queries, fields, interpolations, and
  responses;
- semantic RNG contracts and component-addressed stochastic namespaces;
- backend capability providers and execution specializations;
- snapshot/checkpoint stores and observation backends; and
- PottsToolkit Level 2 declarations, fragments, compiler IR nodes, and registered Level 1 spellings.

Some implementations may be experimental or supported only on a subset of backends. That maturity
does not change the openness of the protocol.

## Reproducible Extension Namespaces

The built-in RNG address encoding remains closed within its contract version. Extensibility is
provided above that encoding through stable component instance identity and compiler-assigned local
operation or draw identities.

An extension MUST NOT choose an undocumented raw numeric stream offset. The compiler derives a
collision-resistant semantic namespace from the component identity, instance identity, operation
label, entity identity, and versioned RNG contract. The resulting lowering must be injective over
the supported model domain and recorded in provenance.

If the current address width cannot represent that mapping, the project revises the RNG contract;
it does not let extensions silently share streams.

## Conformance as the Extension Contract

Documentation alone is insufficient. Every stable protocol ships public conformance helpers and at
least one test-only downstream extension package or module that defines a new implementation
without editing CorePotts.

The extension fixture MUST prove, where applicable:

- construction and validation through public methods only;
- scalar reference execution;
- lowering into a compiled plan;
- inference and bounded allocation behavior;
- CPU execution;
- Metal and ROCm compilation and execution for device-capable fixtures;
- semantic RNG and lifecycle behavior;
- snapshot/checkpoint round-trip when claimed;
- useful errors for an incomplete implementation; and
- no dependency on internal fields or underscored methods.

Conflict-sensitive fixtures MUST additionally permute declaration order, tuple layout, homogeneous
batch construction, and workgroup tuning. Results must remain invariant whenever the semantic
contract declares those choices non-observable.

The principal structural test is the **zero-core-edit test**:

> Can a downstream package add one scientifically meaningful family member, run the appropriate
> conformance suite, and use it through CorePotts without modifying CorePotts source?

PottsToolkit additionally applies a **zero-compiler-switch test**: adding a Level 2 object that
already conforms to a CorePotts protocol must not require another central `isa` branch in the model
compiler. Level 1 spelling and durable serialization may require explicit registration.

Lightweight runtime validators remain available from CorePotts. Heavy randomized, adversarial, and
multi-backend extension tests SHOULD live in a test-only conformance module or companion package so
downstream extensions can reuse them without adding testing machinery to the runtime dependency
surface.

## API and Performance Discipline

Extensibility MUST NOT create an unbounded public surface or specialization explosion.

- Export semantic types and documented extension functions, not cache structs and kernel helpers.
- Use explicit `public` declarations or documented exports according to the final Julia 1.12 API
  policy.
- Keep stable, experimental, and internal names mechanically distinguishable.
- Prefer instances over passing types when either design works.
- Avoid fields with abstract types and abstract-element containers in compiled execution values.
- Avoid value-parameterizing arbitrary model data; specialize only on information that changes
  generated control flow enough to justify compile cost.
- Measure compilation latency, native-code size, GPU register use, and steady-state performance for
  representative heterogeneous models.
- Provide generic correct implementations before isolated measured specializations.
- Do not use generated functions where ordinary dispatch, tuples, or function barriers suffice.

## Review Checklist

Before accepting or freezing a protocol, reviewers answer:

1. Is the set intentionally closed or accidentally equal to the first built-ins?
2. Can a downstream package add a member without a CorePotts edit?
3. Are required and optional methods documented separately?
4. Does the design use dispatch for behavior and finite tags only for exhaustive state?
5. Are capabilities orthogonal to the scientific type hierarchy?
6. Can construction remain flexible while compiled execution stays concrete?
7. Can a conforming implementation execute without a global runtime registry?
8. Are RNG, lifecycle, persistence, and provenance semantics defined for extensions?
9. Does an incomplete or incompatible implementation fail before kernel launch?
10. Is there a downstream conformance fixture and a device fixture where claimed?
11. Is specialization bounded and measured?
12. Are internal caches, kernels, and backend workarounds absent from the public contract?

Failure of questions 1 through 10 blocks protocol freeze. Questions 11 and 12 block paper API
qualification.

## Alignment with Julia and SciML

This standard follows the Julia model in which small informal interfaces enable derived behavior,
multiple dispatch separates algorithms from data types, concrete parametric fields preserve
specialization, and optional integrations use package extensions:

- [Julia interfaces](https://docs.julialang.org/en/v1/manual/interfaces/)
- [Julia methods and dispatch](https://docs.julialang.org/en/v1/manual/methods/)
- [Julia style guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- [Julia performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [Julia package extensions](https://docs.julialang.org/en/v1/manual/code-loading/#Package-Extensions)

It follows SciML's type-based `init`/`solve!`/`solve` composition and algorithm dispatch rather than
a central solver registry:

- [SciMLBase init and solve interface](https://docs.sciml.ai/SciMLBase/dev/interfaces/Init_Solve/)
- [SciML algorithm interface](https://docs.sciml.ai/SciMLBase/dev/interfaces/Algorithms/)

Its device constraints follow KernelAbstractions' backend-agnostic kernel model and asynchronous
launch semantics, with reusable parallel operations preferred where they preserve the contract:

- [KernelAbstractions](https://juliagpu.github.io/KernelAbstractions.jl/)
- [KernelAbstractions kernel interface](https://juliagpu.github.io/KernelAbstractions.jl/stable/kernels/)
- [AcceleratedKernels](https://juliagpu.github.io/AcceleratedKernels.jl/stable/)
