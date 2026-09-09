# [Architecture](@id architecture)

Potts.jl separates symbolic model authority, numerical execution, and presentation:

```text
PottsModels scientific factories + initializers + tutorials
          │ ordinary public declarations (no executor)
          v
Potts
  PottsSystem + native MTK component islands
          │ complete / structural mtkcompile
          v
  scheduled PottsSystem + coupling schemas
          │ PottsProblem / init / solve
          v
CorePotts CPM runtime <-> native SciML component integrators
     │ uses                    │ publishes settled observations
     v                         v
LocalMath              MakiePotts / analysis
     │ portable launches
     v
KernelAbstractions
```

## Potts

The explicit-constructor form of `@statements` in
`statements/statement_set.jl` captures source locations and results of the actual
symbolic declaration macros. Its temporary collections are immediately consumed
by `_assemble_declared_system` in `systems.jl`, which calls the same positional
constructor. No builder survives in the source model. Macro binding identity,
single evaluation, whole-array inventories, imported ownership and explicit-entry
duplicate rejection are defended by `test_lexical_enrollment.jl`.
Both macro forms use `_capture_statement_block` for executed declaration leaves
inside Julia blocks, branches and loops. It preserves ordinary control flow and
captures each leaf's source, without retaining a control-flow representation in
the model. `test_declaration_control_flow.jl` defends evaluation order, helper
splicing, empty/terminated loops, conditional symbolic inventories and numerical
execution on both CPU engines.

The positional `PottsSystem(::StatementSet; ...)` constructor in `systems.jl`
normalizes declaration-derived symbolic inventories into the ordinary keyword
constructor. State enrollment and expression discovery reuse
`completion/inference.jl`; imported aliases remain references. Completion,
execution and inspection consume the resulting ordinary source object, without
a retained construction graph. `test_declaration_assembly.jl` defends ownership,
default dependency closure and equivalence to explicit inventories.

Potts owns the public symbolic and SciML-facing product:

- typed Potts statements, names, hierarchy, units, parameters, and observations;
- composition, completion, validation, source-located diagnostics, and inspection;
- structural `mtkcompile` and explicit component IO, time, scope, and coupling schedules;
- `PottsProblem`, late private lowering, integrator/solution integration, and symbolic indexing.

Source component bindings follow one chain: `PottsSystem(imports=...)` and
`ComponentReference` declarations in `systems.jl` → the existing source inventory
and `completion/component_imports.jl` → ordinary MTK-scoped symbols and qualified
statement records → the unchanged evaluator/state execution path. Imports do not
create a runtime registry or additional state. `component_replacement.jl` rebuilds
source and asks completion to validate it; it does not modify compiled plans.
Synchronous writer uniqueness is checked after qualification in
`completion/qualification.jl`, so aliases cannot conceal multiple writers.
The validator examines individual effects, including repeated targets inside
one process. `compiler/host/coverage.jl` validates their common iteration domain;
`compiler/lowering/stage_plan.jl` assigns each effect its own descriptor and
scratch slot, using its indexed normalized expression root. CorePotts owns
boundary-entry evaluation and publication; Potts does not execute assignments.
Read scope is independent of writer scope: `compiler/host/normalized_payloads.jl`
resolves each state leaf to its qualified declaration. Operation closure and
`compiler/lowering/evaluator_nodes.jl` reuse that owner to select a model-bound
read for `ModelState`, including inside site and cell assignments. Core validates the
declared storage domain and supplies the execution gather; Potts does not
broadcast or duplicate model storage. `test_model_state_proposal_reads.jl`
contains the public proposal and mixed model/site numerical witnesses.
`test/test_model_cell_transactions.jl` checks changing model values read by
unequal-area selected cells, fixed-vector updates, inactive slots, and checkpoint
continuation. Its shared numerical fixture also belongs to the ordinary Metal
cell-process witness; backend support is established by running that witness.

For `Synchronous(...; domain=cells(kind))`, the same lowering resolves the
qualified kind through `evaluator_resources.jl` and emits CorePotts'
`CellAssignmentEffect`. The existing operation closure supplies the cell-bound
state read, and CorePotts owns finite-cell eligibility and the cell-domain
execution. Cell processes do not borrow a lattice traversal.
`operation_library/numerics.jl` owns `DiscreteFieldEuler`: either its existing
finite-stencil rate or a normalized explicit `FieldState(rhs=...)` expression
feeds one clipped Euler update. Completion records the RHS as a process root;
ordinary unit analysis, operation admission, and state-read lowering apply.
CorePotts' existing iterated-site effect owns substep entry state and addressed
draw execution. No separate numerical scheduler or random generator is added.
`test/test_cell_process_authoring.jl` checks per-cell frequency, kind selection,
inactive slots, simultaneous scalar/vector writes, and domain rejection.
State-policy literals reuse the compiled state manifest's logical type and
reference units. `compiler/lowering/lifecycle_plan.jl` resolves the target's
existing handle; `_static_literal` delegates numerical conversion to the same
recursive owner in `compiler/execution/manifests.jl` used by initialization.
No additional lifecycle state schema is retained. The actual retirement and
invalid literal tests live in `test/test_structured_lifecycle_literals.jl`.
`compiler/lowering/evaluator_nodes.jl` normalizes dimensional arithmetic using
the analyzed node units and the existing reference manifest in
`compiler/lowering/parameters.jl`. It inserts ordinary scalar multiplication
only when operand and result reference scales require conversion. The same
lowering applies to process and lifecycle expressions; no runtime unit table
or second reference inventory exists. `test/test_expression_reference_scales.jl`
checks independent reference scales, SI intermediate dimensions, and lifecycle
creation numerically.
`test/test_compound_effects.jl` exercises this path through public models.
`completion/inference.jl` retains actual effect RHS reads even when the same
process writes those states. `compiler/host/footprints.jl` gives direct site-state
reads their iteration-site or proposal-target footprint; both inspection and
descriptor lowering consume this analyzed fact. Model-state reads do not acquire
a lattice footprint merely because the model also contains a lattice.
`test/test_component_replacement.jl` checks shared-input/state trajectories,
replacement, and binding failures through public constructors.

Native port imports follow the same source mapping through
`native/components.jl`'s endpoint rebuild. Original native systems and symbols
are retained. `completion/native_completion.jl` resolves endpoints against the
ephemeral enclosing source inventory, so an imported owner is not copied into a
child's state inventory. `ExternalIO` derives bindings from completed or scheduled
native declarations. Scheduling rejects a child that lacks an external endpoint
owner and directs the caller to compile its containing model.
`integration/test_native_component_replacement.jl` checks CPU shared-input and
replacement trajectories, sampled publication, native symbol identity, and failed
port reconnections. Native solver execution remains owned by the existing coupling
and native runtime path.

`completion/symbolic_interface.jl` projects completed equations, observations,
unknowns, parameters, IO roles, and initial conditions from qualified frozen source
references. It does not recursively namespace completed children or cache a second
symbol table. Incomplete source retains the ordinary MTK source query behavior;
the low-level `get_*` accessors still expose local source fields.

An external ModelingToolkit system remains native through structural compilation. Potts
does not recreate that system by copying equations, unknowns, parameters, defaults, events, or
hierarchy into a parallel Potts representation.

## PottsModels

PottsModels owns complete scientific model construction, initializers, analysis
of explicit saved observations, executable modeling tutorials and model-level
tests. Its plain factories return the authored system, initial conditions and
symbolic references; the caller owns numerical execution choices. The library
does not wrap private engine storage or duplicate lowering and execution.

The behavioral chain is factory → public Potts declarations → Potts validation
and lowering → CorePotts/LocalMath execution → public saved observations →
Models scientific tests. Minimal operation and engine-contract fixtures stay in
their owning upstream package; complete model implementations do not.

See the [model library](@ref model-library) for the initial bounded tutorials
and their explicitly limited scientific scope.

## CorePotts

Authored randomness follows `draw(..., DrawKey(...))` and lifecycle declarations
→ `completion/inference.jl`'s qualified random-operation inventory and
`completion/semantic_ordering.jl`'s duplicate validation →
`compiler/lowering/evaluator_resources.jl`'s one public CorePotts key-derivation
batch → concrete evaluator/lifecycle descriptors → CorePotts addressed draws.

The same operation catalog admits `:draw` in scheduled assignments. No separate
scheduled key registry is built: qualified process identity and `DrawKey` enter
the same complete batch. Core owns model/site/cell identity, cell generation,
MCS, and scientific substep addressing. `test_scheduled_process_draws.jl` and
its shared fixture exercise public model/cell/site updates, declaration-order
noninterference, and checkpoint continuation; the ordinary Metal witness
reuses that fixture.
`RandomOperations` and lifecycle inspection derive from that same source
inventory. Procedural initialization uses the same public key derivation with
its explicitly named placement identity in `runtime/initial_state.jl`.
`test/test_addressed_randomness.jl` checks scoped identities, source-order
stability, lifecycle validation, CPU execution, and same-profile continuation.

CorePotts is the independently testable numerical kernel. It owns CPM state and invariants,
proposal and acceptance semantics, trackers, relationships, generation-safe lifecycle,
counter-based randomness, checkpoints, and backend execution. It has no ModelingToolkit dependency
and does not execute an external numerical solver.

CorePotts publishes settled coupling arrays and lifecycle receipts. Potts uses those public
boundaries to coordinate native component integrators.

## LocalMath

LocalMath is an independently testable execution substrate beneath
CorePotts. It owns validated local topology, declared reads and destinations,
bounded workspace, independent/combined/resolved output mechanisms, lifetime,
inspection, and central lowering to KernelAbstractions kernels. It relies on
KernelAbstractions implicit ordering and does not implement a scheduler.
Every package-owned spatial kernel uses that same KernelAbstractions path;
backend extensions adapt storage and report concrete device support but do not own raw
vendor kernel, launch, or synchronization implementations.

LocalMath does not own CPM physics, clocks, randomness, acceptance,
Hamiltonian folding, lifecycle transactions, checkpoints, or solver behavior.
Those remain domain responsibilities. Hardware-neutral kernel source is also
distinct from runtime support: the currently tested execution paths
are CPU and real Metal, not untested CUDA or ROCm claims.

## Logical state values and storage axes

An array-valued symbolic state describes one logical value, not extra lattice
axes. Completion retains Symbolics' declared value type, including Boolean and
integer meaning. `completion/symbolic_interface.jl` owns declaration/system
initial-value selection, and `compiler/execution/manifests.jl` owns numerical
conversion. `compiler/lowering/storage_layouts.jl`
uses that conversion to derive a fixed array's element type for the canonical
CorePotts state layout. The runtime initializer separates logical value shape
from model, site, and cell storage shape; saved values and checkpoints consume
the resulting Core-owned storage. The owning behavioral tests are in
`test/test_structured_state_authoring.jl`.

History sampling follows the qualified `of` declaration, not an inferred
storage-domain tag. `_state_sample_record` in `compiler/host/source_graph.jl`
also supplies that source identity to lifecycle lowering: cell-owned histories
need explicit cell-state policies, SiteState histories need ownership-change
laws, and Eulerian FieldState histories preserve fixed-site meaning unless an
ownership law is explicitly declared. No parallel classification is retained
in runtime manifests. `test/test_history_lifecycle.jl` and
`test/test_history_ownership_change.jl` exercise the corresponding public
creation, retirement, sampling order, and site-lifetime behavior.
`test/fixtures/history_structured_samples.jl` supplies the same numerical
vector, tensor, product, dimensional-reference, and checkpoint oracle to the
ordinary CPU test and the Metal runner; invalid symbolic projections remain
in the ordinary compiler test.

Public `SymbolicIndexingInterface.setu` and `setp` belong to
`runtime/symbolic_indexing.jl`: one tagged setter resolves canonical state and
parameter targets and stages the complete batch. Its commit owner also serves
the parameter finalization hook, records parameter history once, and restores
published values, pending parameters and the detached current value after an
ordinary host refresh failure. Initialization and mutation share
`runtime/initial_state.jl`'s supplied-value normalization and descriptor packing,
which delegate logical type/unit conversion to the manifest owner above.
CorePotts' public `update_program_descriptor_state!` validates and publishes the
candidate through its existing host/device storage boundary. Potts then refreshes
the detached current saved value, without mutating earlier snapshots.
`runtime/integrator.jl` owns rollback of state and parameters across an ordinary
callback boundary. `test/test_logical_state_mutation.jl` defends conversion
atomicity, canonical slot/history shapes, snapshots and continuation;
`test/test_mixed_symbolic_mutation.jl` covers mixed batches and provider-independent
pending-parameter policy, while `test/test_state_mutation_observation_failure.jl`
exercises the shared refresh rollback boundary;
`test/test_history_initialization.jl` covers callback-before-capture ordering.
The mixed-publication and host-observation fault fixtures are shared with
`benchmark/backends/metal/mixed_symbolic_mutation.jl`. The latter exercises host
refresh errors after device publication; it does not simulate or promise
recovery from failed device copies or execution.

Named products use the same conversion owner recursively: declared field names,
types, and fixed-array shapes determine the stored value, including omitted
defaults. Completion's reference-anchor traversal visits nested quantity leaves;
it does not create independent field state owners. Runtime supplied values reuse
the compiled conversion contract. Product initialization and checkpoint witnesses
live in `test/test_product_state_authoring.jl`, recursive defaults in
`test/test_product_state_defaults.jl`, and dimensional conversion in
`test/test_state_reference_inference.jl`.

Fixed-vector construction and indexing use the existing operation catalog and
normalized expression graph. `compiler/host/term_analysis.jl` derives logical
shape and proves literal index bounds; unit analysis checks component dimensions.
Assignment lowering compares the expression's shape to the declared target.
CorePotts supplies the corresponding static callables through its public compiler
interface, and its existing stage transaction executes the expression. The
analysis contracts live in `test/test_fixed_vector_operations.jl`; the shared
`test/fixtures/vector_rotation.jl` supplies the ordinary and Metal execution
witness without adding another evaluator.

Scalar `sin` and `cos` use canonical `:sine` and `:cosine` entries in the same
catalog. Operation admission requires real scalar inputs, unit analysis requires
dimensionless arguments, and CorePotts supplies the ordinary Julia callables.
`test/test_trigonometric_operations.jl` defends shape and unit rejection;
`examples/cell_polarity_dynamics.jl` is the real held-turn consumer, reused by
ordinary CPU and Metal tests through `test/fixtures/cell_polarity_dynamics.jl`.

Named-product field syntax belongs to the existing state declaration in
`statements/semantics.jl`. Its owned symbolic callable uses SymbolicUtils' public
type and shape promotion hooks, so same-declared-type substitution retains the
original state owner and projected type. Structural type changes are rejected
before captured shape or ordinal information can become stale; the owning
regression is `test/test_product_field_substitution.jl`.
Normalization consumes the field spelling and source
type into the sole `product_field` operation plus a literal declared ordinal;
the frozen operation catalog does not grow one schema per field. Existing
analysis derives the selected type, shape, and field units, and CorePotts consumes
the literal selection before execution. `test/test_product_field_authoring.jl`
owns composition, unit, and scalar/vector consumer tests. No product wrapper or
independent symbolic field owner participates in completion.

`completion/symbolic_interface.jl` selects each effective state initial from the
qualified source references, using the same parent-first precedence as MTK's
completed initial-condition query. Scheduling, storage conversion, host unit
analysis, and component reconnection contracts consume that selection directly.
A declaration/system disagreement remains an error; a parent's explicit value
for a qualified child overrides the child's system default. The ordinary
`test/test_state_initial_selection.jl` defends these distinctions and their
dimensional execution consequences.

`compiler/lowering/storage_layouts.jl` resolves indexed symbolic reads back to
their declared logical array owner when inventorying state handles. Completion
retains the indexed expression, but execution reads the existing owner's whole
stored value before projecting a component. An indexed read does not create
another state handle or expand a vector into scalar states.

The shared `test/fixtures/cell_processes.jl` checks selected-cell updates and
structured retirement values through the public workflow. Ordinary CPU tests
and `benchmark/backends/metal/cell_processes.jl` use these same independent
numerical expectations; malformed declaration and literal checks remain in the
ordinary owning tests.

## Time

The completed integer Monte Carlo step is the master CPM clock and lifecycle boundary. Each native
time-dependent component declares a physical duration per MCS and a named split policy. MTK clock
objects are not the master scheduler.

## MakiePotts

MakiePotts consumes explicit public observations and solutions. It cannot mutate simulation state,
advance time, trigger synchronization implicitly, or redefine scientific semantics.

See [Capability status](@ref capability-status) for the exact admitted
conjunctions. Architecture does not broaden a backend or solver claim.
