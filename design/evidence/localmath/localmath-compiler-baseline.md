# LocalMath LM-0 compiler and execution baseline

Status: frozen LM-0 evidence, validated against the final LM-0 source.

This document fixes the compiler-health ceiling used by later LocalMath gates.
It is a regression bound, not a claim that the present cold latency is good
enough for release. Later gates must meet or improve these numbers without
refitting them, boxing executable meaning, splitting a scientific sequence, or
adding another execution path.

The machine-readable authority is
[`compiler-gate.toml`](../design/evidence/localmath/lm0/compiler-gate.toml),
validated by:

```sh
julia --startup-file=no scripts/check_localmath_lm0_compiler_gate.jl
```

## Measurement contract

Every CPU observation is a fresh Julia 1.12.6 process on the Apple M1, one
Julia thread, ordinary `--compile=yes --optimize=2`, and existing package
compiled modules. The harness separately records package load, construction,
planning, storage allocation, preparation, first completed execution, and
seven warm executions. Complete child elapsed time is retained because Julia's
nested `@timed` compiler counters do not include every caller/report-emission
specialization.

The synthetic family cycles through all five physical law families: unique
publication, deterministic reduction, resolution with evidence, stable bounded
collection, and bounded heterogeneous ordered recurrence. The flagship is the
real CorePotts 13-stage lifecycle selection graph, including its request index,
two physical banks, packed relationship recurrence, and production planning,
preparation, and execution.

The reproducible commands and timing definitions are in
[`benchmark/lm0/README.md`](../benchmark/lm0/README.md). The final CPU
manifests are:

- [`cpu-synthetic-final/manifest.toml`](../design/evidence/localmath/lm0/cpu-synthetic-final/manifest.toml), 15 fresh processes;
- [`cpu-flagship-final/manifest.toml`](../design/evidence/localmath/lm0/cpu-flagship-final/manifest.toml), 3 fresh processes.

## Frozen numeric bounds

For `n` logical stages, the ordinary host-compilation ceiling is:

```text
T_host(n) <= -1.21441894395 + 4.06540554900 n seconds
```

The complete fresh-child ceiling is:

```text
T_process(n) <= 7.97618399935 + 7.10845248622 n seconds
```

The one-stage guarded ceilings are 2.85098660505 seconds host compilation and
15.0846364856 seconds complete-child elapsed. Both affine envelopes use the
observed maxima plus one 15% noise margin; the 32-stage point is therefore an
honest upper envelope, not a claim that the observed scaling is intrinsically
affine.

| stages | fresh reports | raw maximum host compile (s) | raw maximum child elapsed (s) |
|---:|---:|---:|---:|
| 1 | 3 | 2.4791 | 13.1171 |
| 4 | 3 | 13.0845 | 26.7956 |
| 8 | 3 | 20.3677 | 37.6504 |
| 13 | 3 | 31.0853 | 54.0880 |
| 32 | 3 | 93.5380 | 204.7362 |

For the authentic 13-stage CorePotts flagship, planning through first completed
selection must remain at or below 135.829952876 seconds and complete fresh
child elapsed at or below 214.376347351 seconds. Every qualifying observation
must also preserve exactly 39 physical launches, two agreeing physical banks,
15 operation facts, current method/world identities, and successful selection.

## Final-source regression observations

The numeric bounds were frozen before the final demand-closure and typed
workspace fixes. They were not refit afterward. Two additional fresh-process
observations prove the final LM-0 source remains below the already-frozen
ceilings:

| witness | measured host/plan-to-first (s) | frozen ceiling (s) | child elapsed (s) | frozen child ceiling (s) |
|---|---:|---:|---:|---:|
| synthetic 32-stage, 74 launches | 81.3765 host | 128.8786 | 149.2764 | 235.4467 |
| CorePotts 13-stage, 39 launches | 117.9980 plan-to-first | 135.8300 | 173.2766 | 214.3763 |

The reports are
[`post-qualification-current-synthetic`](../design/evidence/localmath/lm0/post-qualification-current-synthetic/stages-32-run-1.toml)
and
[`post-qualification-current-flagship`](../design/evidence/localmath/lm0/post-qualification-current-flagship/flagship-run-1.toml).

The final source also completed a real Apple-GPU 8-stage observation through
`Metal.MetalKernels.MetalBackend`: all five law families, 15 physical KA
launches, three warm executions, and a first-execution provider-compilation
upper bound of 0.7603 seconds. See
[`metal-current/stages-08-run-1.toml`](../design/evidence/localmath/lm0/metal-current/stages-08-run-1.toml).

## Specialization matrix

The executable representation may specialize on facts that change layout,
scalar code generation, or physical law selection:

| May be a type fact | Reason |
|---|---|
| scalar and fixed-tensor types | device layout and arithmetic code |
| spatial dimension | bounded index and relation code |
| relation representation and small static degree | physical traversal shape |
| publication/numerical law | distinct conflict and accumulation algorithms |
| evaluator and ordered-transition callable types | concrete Julia/GPU scalar code |
| physical phase type | one typed KA launch unit |
| finite heterogeneous semantic sequence | exact stage order and scientific composition |

The intended LocalMath policy is that extents, ordinary capacities, runtime
identifiers, epochs, origins, and provenance remain values or cold evidence.
Public field names are not scientific type parameters. The live LM-0
LocalWorksets representation does not yet fully satisfy that policy, so the
baseline inventories its existing declaration/physical-ABI exceptions rather
than pretending they do not exist:

| Existing LM-0 type fact | Current justification | Required disposition |
|---|---|---|
| NamedTuple binding keys and `_BindingRead{Name}` / `_PointwiseRead{Name}` | concrete Julia storage lookup | replaced by structural `Field` identity in LM-1/LM-3 |
| `_BoundedRead{Binding,Route,K}`, output/port names, route names, active-prefix names, and work-gate names | compile-time declaration wiring and bounded read shape | names lower through `Field`/`Relation`/`Control`; only a genuinely small static degree may remain typed |
| compacted demand, consumer, and producer-port names | stage-local producer/consumer closure | replaced by structural relation/publication identity in LM-1/LM-2 |
| physical phase/output names | typed launch selection and cold inspection label | physical phase *kind* may remain typed; source/user spelling becomes cold provenance |
| bounded emission count or small fixed relation degree | changes a statically bounded kernel ABI | remains typed only when it is demonstrably small and code-generating |
| `Capacity`/`Groups` in the current compacted result/view ABI | concrete persistent device view layout | ordinary runtime capacity moves to prepared values/device views in LM-1/LM-2 unless measurements prove a small-static specialization is required |

Stage-local binding projection already prevents one phase from carrying the
full program binding-name set, but it does not erase these legacy type facts.
They are measured LM-1/LM-2 deletion targets, not approved precedent for
encoding arbitrary user names or capacities in the final LocalMath IR.

## Compiler-health cuts retained by LM-0

LM-0 made four direct architectural cuts while preserving one semantic and KA
execution path:

1. Prepared sequence phases are grouped by semantic stage. The flat lowering
   phase schedule remains the sole planning and inspection authority; groups
   only bound executable compiler specialization.
2. Every stage receives a projection of the bindings it can actually use,
   including compacted producer storage demanded indirectly by source-position,
   bounded-group, or record-count consumers.
3. Cold inspection and operation-fact synthesis cross explicit type-erasure
   barriers, while executable phases, workspaces, callables, and stage order
   remain concrete.
4. Warm workspace validation traverses the typed workspace template, not the
   erased inspection leaf list. The focused compacted-consumer witness is zero
   allocation across `run!` plus `wait` after warm-up.

The broad 32-stage and flagship harnesses still report warm host allocations
from their orchestration surfaces. LM-0 records that fact. LM-7 requires zero
warm device and algorithmic-workspace allocation, relationship packing,
symbolic interpretation, Julia recompilation, and hidden synchronization;
host receipt/submission bookkeeping instead receives measured, bounded frozen
ceilings. Cold cost also remains steep, especially in preparation and
CorePotts lifecycle initialization. These remain measured deletion and
simplification targets.

## Gate interpretation

LM-0 passes compiler health only when all of the following remain true:

- the 15-run synthetic and 3-run flagship matrices satisfy the frozen bounds;
- the final-source 32-stage and flagship regression reports satisfy those same
  bounds without refitting;
- the real-GPU witness executes all five law families on a named physical
  device through KernelAbstractions;
- the exact launch, bank, operation-fact, method/world, and selection identities
  remain valid; and
- the 19-row authority ledger validates independently.

Later LM review gates rerun the same checker and add their own current-source
observations. A faster implementation may pass; a slower one cannot change the
baseline to approve itself.
