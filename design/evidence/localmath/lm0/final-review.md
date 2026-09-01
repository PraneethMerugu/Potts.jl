# LocalMath LM-0 final review

Date: 2026-08-20

Disposition: **PASS**. LM-0 is closed and LM-1 is authorized to begin. This is
an implementation dependency gate, not a compatibility or migration boundary.

All four required reviewers inspected the live source and evidence after the
last correction. Each returned `PASS` with zero remaining P0/P1 findings.

## Julia/compiler and public API — PASS

The frozen gate now recomputes both affine envelopes and the two flagship
ceilings from the retained 15 synthetic plus 3 flagship reports and the fixed
15% margin. It compares the candidate raw maxima/environment, exact synthetic
law order and launch counts, and the complete flagship logical-stage,
lowering, physical-phase, qualified-fact, per-stage, and per-purpose identities
for both the baseline and final source.

The specialization matrix explicitly inventories every live LM-0 declaration
name, route, gate, active selector, output/port, compacted demand, phase, and
`Capacity`/`Groups` type-ABI exception and assigns its LM-1/LM-2 disposition.
It no longer mistakes the desired final policy for the current representation.

Executable phases, stage workspaces, projected bindings, callables, and device
views remain concrete. Type erasure is confined to cold schema/inspection
evidence. Grouped sequence traversal feeds the same `_execute_phases!` ->
`_execute_one_phase!` -> `_execute_phase!` route.

## GPU/provider and performance engineering — PASS

Production scans contain no raw Metal launch or provider path. LocalWorksets
and CorePotts use KernelAbstractions as the sole kernel boundary; the only
provider synchronization is the explicit cumulative tail settlement.

The real Apple-GPU evidence covers an 8-stage heterogeneous program with all
five law families and 15 KA launches. Cross-domain evidence covers D2Q9,
deterministic/relaxed lattice spring, matrix-free FEM, z-buffer resolution,
ordered recurrence, atomic publication gating, and shared failure scope.

The corrected CorePotts adversarial witness now distinguishes:

- `ProposalAcceptanceFailure`: scientific failure, no commit, provider scope
  remains healthy; and
- a real Metal device bounds fault: `LifecycleBackendFailure(1, 1)`, proposal
  and claims share one poisoned lane, both retain `submitted=1, drained=0`, and
  exactly one scope synchronization occurs.

The focused compacted-consumer warm `run!` plus `wait` is zero-allocation after
typed workspace-template validation. Broad harness allocations and steep cold
compilation remain recorded debt for later gates; LM-0 does not relabel them as
release-ready performance.

## Scientific meaning and cross-domain modeling — PASS

The semantic closure ledger preserves exact unique participation versus
coverage, identity/existing-seeded reductions, resolved tie/empty behavior,
collection empty/overflow/order laws, deterministic versus relaxed numerics,
heterogeneous ordered current-prefix recurrence, success-gated emergent
transaction behavior, and provider-failure non-rollback semantics.

Stage-local demand projection includes indirect compacted dependencies through
source position, bounded grouped access, and record count. The authentic
CorePotts flagship remains exactly 13 logical stages, 39 ordered physical
phases, two agreeing banks, 15 operation facts, two qualified facts, current
methods/world, and successful selection.

## Simplification, deletion, and maintainability — PASS

The 19-row authority ledger inventories the exact public export surface and all
26 package-owned KA kernels. There is no LocalMath-named peer stack,
compatibility shim, deprecated constructor, migration selector, forwarding
module, or alternate executor.

Prepared work no longer owns duplicate binding-name/access, trusted-method,
execution-method, or locking authorities. Prepared sequences no longer retain
a redundant flat executable phase tuple: the flat lowering schedule remains
the sole planning/inspection authority, and preparation derives stage groups
from it. Cold evidence cannot expand executable type identity.

LM-1 therefore starts from one waist:

```text
LocalWork -> _LoweredWork -> WorkPlan -> _PreparedPipeline
```

## Corrected review findings

The committee blocked intermediate drafts until these findings were corrected:

1. cold evidence synthesis still specialized on heterogeneous phase tuples;
2. stage projections omitted compacted producer storage demanded indirectly by
   downstream consumers;
3. erased workspace leaf traversal allocated on the warm path;
4. the Metal harness loaded optional providers from the wrong Julia world;
5. the CorePotts provider-failure fixture had become an exact publication
   validation witness and therefore could not prove shared provider poisoning;
6. two qualification consumers still read a superseded failure-result key;
7. the specialization matrix understated live name/capacity ABI exceptions;
8. the compiler checker did not independently derive its ceiling or pin the
   complete flagship identity.

Every finding was fixed by direct edits to the sole implementation or its
evidence. No compatibility or migration machinery was added.

## Reproducible gate

```sh
julia --startup-file=no scripts/check_localmath_lm0_compiler_gate.jl
julia --startup-file=no scripts/check_localmath_cutover_authority_ledger.jl
```

Final output:

```text
LocalMath LM-0 compiler gate passed: synthetic=15, flagship=3, current-source=2, real-gpu=1
LocalMath authority ledger valid: gate=LM-0, status=baseline, rows=19
```

Supporting evidence:

- [`compiler baseline`](../../../../spec/localmath-lm0-compiler-baseline.md)
- [`semantic closure`](../../../../spec/localmath-lm0-semantic-closure-evidence.md)
- [`compiler gate`](compiler-gate.toml)
- [`real-Metal semantic evidence`](metal-semantic-final.toml)
- [`authority ledger`](../../../audits/localmath-cutover-authority-ledger.toml)
