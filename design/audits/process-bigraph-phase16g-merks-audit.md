# ProcessBigraphs Phase 16.G Merks audit

Date: 2026-07-27

Status: qualified

## Claim boundary

Phase 16.G delivers a runnable, source-bounded reimplementation of the Merks et al. 2006
elongation/autocrine vasculogenesis model. It does not claim reproduction of Figure 5 ensembles,
the original random trajectory, lacuna or branch-point image analysis, or publication-level
quantitative agreement.

The primary paper is the scientific authority. Every source-unresolved choice needed to make the
model runnable is named in `bounded_reference_v1`: volume and length strengths, field boundary,
the effective hard-connectivity penalty, placement algorithm, and seed. The machine-readable
source/mechanism mapping is `spec/process-bigraph-phase16-merks-trace-v1.toml`.

## Compute ownership

ProcessBigraphs owns the two-second logical clock, the 15:1 field/CPM schedule, immutable input
projections, transaction boundaries, validation, publication, observation, and restart.
`ManagedFieldAdvanceProcess` invokes an injected `EngineDeclaration`; the adapter and its solver
retain control of numerical stepping and heavy field kernels. `Merks2006CPMStep` delegates one
MCS to the CorePotts sequential scientific kernel.

The same composite was exercised with:

- the CorePotts native field kernel;
- an explicit OrdinaryDiffEq Tsit5 algorithm through the SciML extension; and
- the independent external-style classical-RK4 conformance adapter.

No model-owned time loop, ProcessBigraphs-owned solver algorithm, or hidden fallback was added.

## Source mechanisms

The qualified assembly covers the 500 by 500 canonical domain, 282-cell central startup,
eight-neighbor proposals and contacts, the published contact values, area, inertia-based length,
the paper's cyclic local-connectivity collision test, cell-site secretion, ECM-only decay,
diffusion, extension chemotaxis, and the 15 field steps per 30-second MCS mapping.

Two algebraic translations are explicit:

- the source length is four times CorePotts' major-axis RMS, so the target is divided by four and
  the quadratic strength is multiplied by sixteen; and
- the source chemotactic energy divided by Metropolis temperature maps to a CorePotts log-bias
  coefficient of `1000 / 50 = 20`.

The reference split is `field_then_cpm_v1`. The paper fixes the 15:1 cadence but not the ordering,
so this is a named runnable profile rather than a source fact.

## Evidence

The rebased implementation commit is `e9ce80b8f4d1d7619dbe9efa0596d7629e86714e`, with tree
`d5523abe300e9cd74fe292631efe2a3b7e8c27f1`.

Qualification includes:

- 11 source-mechanism microfixture assertions;
- 21 canonical-startup/native schedule, invariant, observation, restart, and rollback assertions;
- 4 real-SciML assembly assertions;
- 4 independent external-adapter assembly assertions;
- the full ProcessBigraphs suite, 1,150 assertions;
- all 3,805 pre-existing CorePotts regression assertions in the package run; and
- a final 14-assertion CorePotts cross-adapter rerun after the shared field-mask change.

The canonical startup has shape 500 by 500, exactly 282 cell identities, and 27,354 occupied
lattice sites under the named deterministic placement profile. Read-only observations record cell
count, occupancy, eight-neighbor disconnected-cell count, and field mass/range at each MCS and
survive logical checkpoint/restart exactly.

## Open work

Phase 16.C still requires trusted exact-head Metal and ROCm evidence. Phase 16.H must qualify the
CNV scenario 38/simulation 902 assembly. Phase 16.I must reconcile the complete ledger and attest
internal beta. Phase 16.G does not widen public-release or full-analysis claims.
