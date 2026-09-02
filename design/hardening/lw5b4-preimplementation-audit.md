# LW-5B4 pre-implementation committee audit

Date: 2026-08-13

Status: **PASS TO IMPLEMENT**; K02 is opened only as a private,
non-promoted adapter-reuse witness

Authority:

- [LW-5A adoption-and-consolidation amendment](lw5a-adoption-consolidation-amendment.md)
- [LW-5B3 proposal-only review](lw5b3-proposal-adoption-review.md)
- [LW-5B3 remediation review](lw5b3-proposal-adoption-remediation-review.md)
- [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md)

## Question

Before implementation, the committee reviewed whether checkerboard candidate
generation (`K02`) can be constructed through the existing CorePotts adapter
as a materially smaller second use without adding LocalWorksets behavior,
moving scientific ownership, or weakening the B3 baseline.

The audit inspected the preserved dirty-tree B3 candidate. It ran no tests or
benchmarks and changed no source. The pre-implementation identities include:

```text
e7aef6c16ce8a95fcea27f31f404d19395b414e0c6974ced642ea3767adc0df5  lib/CorePotts/src/execution/checkerboard_program.jl
a84a877ec8b279fb2e4050bda596858b82495a7dd4a5896e2906315f77545a90  lib/CorePotts/src/execution/descriptor_plan.jl
659ef2ac9db272e0ed3814503738555ca7518278e18481984d9b5c9903f795dc  lib/CorePotts/src/execution/localworksets_adapter.jl
554d73a622e35f52595d61f7edfcab9b457a4fb8260bae76590338f0c4205b32  lib/CorePotts/src/execution/localworksets_proposal_bridge.jl
```

## Independent ballots

| Reviewer | Ballot | P0 | P1 | P2 |
|---|---|---:|---:|---:|
| CorePotts science, RNG and checkpoint preservation | **PASS TO IMPLEMENT** | 0 | 0 | 3 |
| JuliaGPU, KernelAbstractions and lowering | **PASS TO IMPLEMENT** | 0 | 0 | 4 |
| Nonvoting chair reconciliation | **PASS TO IMPLEMENT** | 0 | 0 | 4 carried classes |

The reviewers independently reached the same architectural result. The
existing direct-independent LocalWorksets lowering can represent K02 as seven
named partial independent ports in one launch. No LocalWorksets change is
necessary or permitted.

## Frozen implementation contract

### Exact operation

The prepared item capacity is the compiled checkerboard maximum color size.
`active_count` supplies the realized color size. One concrete isbits CorePotts
operation returns these named conditional emissions:

| Port | Type | Meaning |
|---|---|---|
| `target_sites` | `Int32` | canonical site for color/local item |
| `source_sites` | `Int32` | neighbor site, or zero outside a nonperiodic boundary |
| `old_owners` | `Int32` | target owner |
| `new_owners` | `Int32` | source owner, or old owner for an invalid neighbor |
| `priorities` | `UInt32` | semantic priority for actionable proposals, otherwise zero |
| `semantic_ids` | `Int32` | attempt-round/site identity |
| `dispositions` | `UInt8` | pending for actionable proposals, otherwise null |

All ports use the same topology-proved identity route, partial coverage, one
launch and zero algorithmic workspace. A closed CorePotts program/lifecycle
gate emits nothing and preserves every destination. Null proposals still
publish all seven values when the gate is open.

Submission values are immutable `color::Int32`, `attempt_round::Int32`,
`mcs::Int64` and `active_count::Int32`. The operation may not derive identity
or randomness from launch order, lanes or LocalWork item numbering beyond the
direct kernel's canonical local-index mapping.

### Scientific ownership

CorePotts retains:

- the attempt/color loop and preallocated unbiased color permutation;
- semantic identity `(attempt_round - 1) * length(ownership) + target`;
- `ProposalDirectionStream`, operation 2, semantic MCS, site identity and
  color subround;
- `CheckerboardPriorityStream`, operation 4, the same MCS/site/color address;
- seed/replica/repeat trajectory identity;
- periodic wrapping and nonperiodic invalid-neighbor behavior;
- pending/null meaning, gates and output values; and
- clocks, transactions, capability identity, checkpoints and settlement.

B4 adds no executable `ProgramRuntime`, checkpoint block, restoration method
or mechanism identity. Production candidate generation remains the unchanged
direct kernel.

### Adapter-reuse condition

B4 must factor the broad B3 proposal view into one smaller checkerboard
projection shared by K02 and K03. The shared layer may own only checkerboard
program topology, ownership, gate/lifecycle state and semantic RNG identity.
Descriptor, tracker, relationship, parameter and Hamiltonian data remain a
proposal-only layer.

B4 fails if it adds a second execution-view hierarchy, copies K03's complete
binding block, parameterizes K02 on descriptor/model schedules, or leaves K02
using an unjustified Hamiltonian-wide read view. Preparation, trusted
submission, topology/binding validation, inspection, bank selection and
backend validation must reuse the existing CorePotts adapter authority.

## Required evidence

Before the post-implementation review, B4 must prove:

1. concrete inferred seven-port return and an isbits callable;
2. exact direct-array parity for every color on CPU and real Metal;
3. actionable, same-owner, nonperiodic-null and periodic-wrap cases;
4. independent direction and priority RNG-address/word oracles across varied
   seed, replica, repeat, MCS and color;
5. gate-closed, active-zero and inactive-tail preservation;
6. K02 followed immediately by the unchanged direct proposal evaluator with
   KernelAbstractions implicit ordering and one final synchronization;
7. exact inspection of ports, types, routes, access, launch count, workspace,
   transfers, leases and provider scope;
8. fail-closed wrong-bank/backend/type/shape/alias/topology/submission
   rejection before launch;
9. CPU and real-Metal device compilation without scalar fallback or vendor
   branches;
10. bounded native-text/method and Metal compiler-cache growth;
11. a paired direct/K02 `upper95 <= 1.05` noninferiority result; and
12. complete LocalWorksets, CorePotts CPU and qualified real-Metal regression,
    including the unchanged B3 parity/performance protocol because its shared
    view changes.

## Carried P2 findings

1. Seven logical ports may copy the same route seven times. Record exact
   topology bytes; do not modify LocalWorksets during B4.
2. Generated seven-port publication and two bank-local preparations may grow
   code and transfer footprint. Record native text, compiler cache, topology
   bytes and lease costs.
3. B3's proposal view is broad. The shared checkerboard/proposal-only split is
   an implementation admission condition, not optional cleanup.
4. The current general RNG suite lacks an explicit
   `CheckerboardPriorityStream` address witness. B4 must add one.

## Vetoes and opening decision

Any LocalWorksets source change, new execution family, new wait/event rule,
extra launch or intermediate wait, hidden output mutation, vendor branch,
host fallback, new runtime/checkpoint identity, copied proposal framework, or
failure to demonstrate materially smaller second-use integration blocks B4.

The committee returns P0=0 and P1=0. The P2 findings are owned by B4 evidence
and its post-implementation review. The pre-gate therefore passes and bounded
implementation may begin. Production/default selection, later families,
LW-R3 and G6 remain closed.
