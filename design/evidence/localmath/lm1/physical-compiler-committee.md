# LM-1 physical compiler research committee

Date: 2026-08-22

Disposition: **approve a direct host-spine erasure and physical-ABI
simplification; reject a new physical-region IR for LM-1**.

This report records two adversarial research rounds covering the current
LocalWorksets implementation, Kaimon compiler evidence, Julia/GPU design,
scientific transaction semantics, and primary external implementations. No
production source edits were made during this committee gate.

## Converged diagnosis

LM-1 has two separate compilation failures:

1. planning specializes on the complete heterogeneous program shape before
   any KA kernel is compiled;
2. preparation qualifies many physical kernels whose arguments retain more
   Stage structure than each kernel uses.

The four-stage witness has a concrete 10,225-character lowering type and an
8,741-character prepared type, yet cold planning remains about 17.6 seconds
and preparation about 25.8 seconds. A new eight-stage program type took 45.9
seconds to plan in Kaimon. Large observed method-instance signatures include:

| Method | Signature size |
|---|---:|
| `_validate_bound_work` | up to 10,282 characters |
| `_stage_program_lowering` | up to 13,507 characters |
| `_stage_lowering_group` | 7,585 characters |
| `_prepare_stage_lowering_group` | 9,136 characters |
| `_qualify_stage_backend!` | 5,714 characters |
| `_execute_stage_groups!` | 5,629 characters |

By contrast, repeated Unique stages at different positions have identical
788-character admitted-stage types. Stage-level reuse is already available;
the complete-program and group tuples prevent Julia from realizing it.

Fusion can reduce the 33 physical launches in the four-stage witness, but it
cannot repair planning compilation. Both problems must be addressed at their
own boundaries.

## Rejected architecture

Do not add a physical-region IR, stored effect record, task graph, scheduler,
device interpreter, persistent kernel, or generated whole-program megakernel.

Existing admitted laws, relation views, controls, workspace layouts, and
dependency analysis already contain the facts required to select physical
work. A stored effect summary would duplicate authority and create another
invalidation and specialization surface. Physical facts should be derived by
ordinary multiple dispatch and recomputed for cold inspection.

The external comparison supports this restraint:

- ModelingToolkit recommends homogeneous symbolic containers to avoid
  combination-specific specialization, then generates coarse numerical
  functions rather than encoding the whole system in executable host types.
- Tullio lowers one bounded tensor expression to coarse loop/kernel work.
- Devito and Halide use dependence analysis and coarse code generation, but
  their general scheduling infrastructure is larger than LM-1 currently
  needs.
- Finch explicitly distinguishes structure-specializing and
  non-structure-specializing iteration protocols.
- Taichi caches by kernel-template signature; ordinary runtime values do not
  create new instantiations.
- KA provides asynchronous ordered enqueue and workgroup synchronization, not
  a portable grid-wide barrier or automatic launch fusion.

References:

- <https://docs.sciml.ai/ModelingToolkit/dev/basics/PrecompileComponents/>
- <https://github.com/mcabbott/Tullio.jl#how-it-works>
- <https://www.devitoproject.org/examples/compiler/00_index.html>
- <https://people.csail.mit.edu/jrk/halide12/>
- <https://finch-tensor.org/Finch.jl/stable/docs/language/iteration_protocols/>
- <https://docs.taichi-lang.org/docs/compilation>
- <https://github.com/JuliaGPU/KernelAbstractions.jl/blob/main/docs/src/quickstart.md>

## Approved architecture

```text
LocalWork semantic program
        ↓
nonspecializing host orchestration
        ↓
sealed host-erased vector of concrete Stage entries
        ↓
sealed host-erased vector of concrete prepared Stage launches
        ↓
the existing Candidate / Collect / OrderedFold executors
        ↓
narrow reusable KA kernels
```

The erased vector is not an interpreter. It contains no opcodes and performs
no semantic switch. One dynamic multiple-dispatch call occurs per Stage on the
host. The dispatched method sees the exact concrete Stage preparation; only
concrete values cross into KA kernels. Source order and the single backend
queue remain authoritative.

A representative internal envelope is:

```julia
abstract type _AbstractStageLaunch end

struct _StageLaunch{P,G} <: _AbstractStageLaunch
    prepared::P
    guard::G
    stage::Int32
end

struct _PreparedStageProgram{E}
    stages::Vector{_AbstractStageLaunch}
    execution_gate::E
end
```

Exact names are not frozen by this research gate. The essential constraints
are one sealed host-only envelope, no abstract device arguments, and no old
tuple representation retained in parallel.

This cut should delete:

- `_StageLoweringGroupInput`;
- `_StageLoweringGroup`;
- `_StagePreparationGroupInput`;
- `_PreparedStageGroup`;
- `_STAGE_COMPILER_GROUP_SIZE`;
- generated group lowering and preparation;
- tuple-recursive group execution;
- group-specific workspace and inspection assembly.

`plan` and `_validate_bound_work` must also decline to infer across the full
semantic Stage tuple. Each Stage is extracted through an inference barrier and
enters a concrete stage-local validation/admission function barrier. Merely
vectorizing the already-lowered groups is insufficient.

## Physical ABI rule

Every kernel receives only the values it consumes. Reset and control kernels
must not accept a complete evaluator/Stage execution object when they require
only workspace arrays, statuses, a lease, and an extent.

Permitted specialization axes are:

- backend and workgroup policy;
- physical kernel family;
- evaluator callable type where executed;
- field/record value types;
- packed relation-view family;
- conflict operator/law where executed;
- genuinely static bounded width.

Names, provenance, UUIDs, Stage position, evidence, proofs, runtime extents,
capacities, workspace paths, and complete-program tuple shape remain values.

## Direct fusion/deletion candidates

These are hypotheses to prove with focused failure witnesses before cutover:

1. Move emitted-destination bounds validation into candidate emission, or
   into the local-sort prologue where workgroup ordering is required. Dynamic
   whole-relation receipt validation remains separate.
2. Combine directory construction, semantic validation, and canonical private
   settlement where one destination workitem owns one ordered segment.
3. Fuse canonical Reduce/Resolve settlement with publication only after the
   whole-stage validation barrier. Relaxed atomic settlement remains separate.
4. Fold Collect projection clearing into publication.
5. Delete sorting for OrderedFold `_SourceOrder`; scan source positions and
   skip nonparticipants. Canonical ordering retains its sort.
6. Derive a direct identity-Unique form through the same Candidate executor
   only after a failure-aware witness. The defensible initial floor is four
   launches—reset, evaluate/validate, finalize, publish—not an unproven three.

Do not fuse reset with evaluation while a reset lane can erase another lane's
failure. Do not fuse finalization with publication when publication requires a
grid-visible final gate. Do not move dynamic relation receipt qualification
behind candidate evaluation.

## AcceleratedKernels decision

AcceleratedKernels is approved only for an isolated, preallocated sort/scan
replacement witness. It may own generic key/value sorting or scanning; it may
not own routing, conflict laws, coverage, diagnostics, transactionality, or
publication.

Adopt it by direct replacement only if exact composite keys preserve canonical
order and diagnostics, warm execution allocates no device storage, every
backend uses the same call, cold compilation and launch count improve, and the
custom LocalWorksets primitives are deleted. Otherwise delete the experiment.

## Direct cutover order

1. Prototype the sealed host-erased lowering/prepared spine outside production
   and measure repeated-identical and heterogeneous 1/4/8/32 programs.
2. If it wins, replace the tuple/group spine directly and delete the old group
   types and generated functions in the same cut.
3. Narrow reset/control/finalization kernel signatures and prove identical
   physical operations reuse the same kernel method instances.
4. Apply only transactionally proven launch fusions and delete their kernels
   and workspace leaves.
5. Delete `_SourceOrder` OrderedFold sorting.
6. Compare the current grouping implementation with one preallocated AK
   witness, then keep exactly one implementation.
7. Add exact backend qualification receipt reuse only after physical
   specialization identities stabilize.

Qualification receipts must derive from successful exact compilation or
execution and include backend/device identity, kernel family, exact argument
types, workgroup policy, evaluator/law identity where relevant, and method
world invalidation. Caching is amortization, not the primary fix.

## Gates and kill criteria

Reject or revert a cut if any of the following occurs:

- abstract values reach a kernel argument or GPU compilation sees dynamic
  dispatch;
- warm enqueue allocates or host dispatch becomes material;
- repeated identical stages compile stage-local methods by position;
- 1/4/8/32 cold scaling does not materially improve;
- a second production execution representation remains;
- semantic or inspection authority count increases;
- failed work can partially publish;
- deterministic first-failure, canonical ordering, or diagnostics change;
- CPU and GPU stop using the same packed-storage KA path;
- AK introduces a backend branch, hidden synchronization, warm allocation, or
  fails to delete custom machinery;
- production code grows more than the group/generated/kernel machinery it
  removes.

The committee's final priority is therefore: **stop compiling organizational
program structure, then make physical kernels reusable, then delete proven
launches**. This is smaller and more directly supported by evidence than a new
compiler framework.
