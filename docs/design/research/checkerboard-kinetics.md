# Checkerboard kinetics: closing the gap to SequentialCPM (P6.0bl)

Status: plan and pre-registered criteria (2026-11-03). Nothing here is measured yet. Branch
`feat/cb-kinetics`.

## 1. Problem

`CheckerboardCPM` differs from `SequentialCPM` in its kinetics (D-220, P6.0bl). The causes, in
the order of their expected size:

- **E1 Drops.** An accepted copy that loses a cell claim is dropped (D-008). In the D-220
  monolayer about 73% of accepted copies are dropped. Drops fall most on cells with many
  active boundary sites, so they are not a uniform slow-down.
- **E2 Stale rejections.** Rejected proposals do not claim, so they read a cell volume that a
  winner of the same color then changes.
- **E3 Block order.** Copies of one color act at one instant, not in a random sequential order.
- **E4 Visiting law.** Each site is proposed exactly once per MCS (a random permutation of the
  colors). `SequentialCPM` draws sites with replacement: the visit count per site per MCS is
  about Poisson(1).

The aim is to make the checkerboard kinetically close to `SequentialCPM` with small changes to
the existing propose/claim/commit kernels. Exact equivalence (deterministic reservations in the
sequential pick order) is out of scope.

## 2. Variants

Each is a `CheckerboardCPM` keyword. The defaults stay at today's behavior until §5 decides.

| Variant | Change | Targets | Cost |
|---|---|---|---|
| `retries = R` | Losers re-propose against the updated state in up to R extra propose/commit passes per color; what is left after R is dropped and counted | E1 | 2 launches per color per retry, over a compacted loser list |
| `colors = :replacement` | C independent uniform color draws per MCS instead of a permutation; the sub-step index joins the draw keys | E4 | None |
| `stride = s` | The color stride, at least the footprint reach | E1–E3 | 2 s^d launches per MCS |

New stats (`counts = true`): accepted, committed and dropped copies.

**Dropped from the plan (2026-11-03): `cap = K`, bounded staleness.** A single pass that lets K
copies per cell commit must pick K claimants per cell. Atomics give a top-1 (the max claim) or
an arbitrary order (the first K increments). The arbitrary order is not deterministic on GPUs,
and keeping free determinism is a project rule. A deterministic top-K needs one more pass per
K, which costs as much as a retry that re-evaluates ΔH. `retries` therefore dominates `cap`.

**Retries decide each proposal once (2026-11-03).** The first build claimed only accepted copies
and retried the accepted losers. The harness measured a steady-state bias: on the foam, volume
and perimeter standard deviations fell by about 11% (r = 0.88–0.91, static FAIL), for every R.
A retried copy had to pass the acceptance test twice, and a proposal rejected against a stale
volume was never retried. Under retries every real proposal now claims, accepted or not. Its
decision stands only if it wins every claim, so no copy touching its cells acts before it in
that pass; otherwise it is undecided and proposed again. Losing then does not depend on the
proposal's own acceptance. The cost is more conflicts: about 8 retries recover sequential's
commit rate at stride 2, against 2–4 for the first build.

## 3. Closeness harness

`benchmark/kinetics.jl` compares an arm with `SequentialCPM` over many seeds. Every observable is
reported as the ratio r = mean(arm) / mean(sequential), with a 95% bootstrap interval over
seeds.

Cases (CPU first; the harness takes any case function):

- **K1 sorting.** Graner–Glazier, 144² (four tiles of the 72² baseline, 256 cells), T = 10,
  Moore(1). Kinetic: heterotypic boundary length H(t) at fixed MCS checkpoints.
- **K2 foam.** The same state with one cell kind (no driving). Static: mean and standard
  deviation of cell volume and perimeter. Kinetic: centroid diffusion coefficient (MSD slope)
  and the integrated autocorrelation time of cell volume.
- **K3 chain.** The OpenVT P1b chain relaxation time T (D-218 protocol). Phase 3.
- **K4 driven.** A reduced D-220 monolayer: cells lost and A*−V compression. Phase 3.

Committed copies per MCS are measured the same way for every arm, as sites whose owner changed
over one MCS (D-220's measure).

### Controls (the harness is not used until all three behave)

- **Positive.** `SequentialCPM` against itself with disjoint seeds passes every observable.
- **Clock.** `SequentialCPM` with its clock stretched by 1/0.3 (observed at 0.3 t) passes the
  static observables and fails the kinetic ones by about the factor 0.3. This shows the harness
  separates a pure time-scale difference from a steady-state difference.
- **Negative.** Today's 4-color checkerboard fails the kinetic observables (the known D-220
  gap).

### Control run (2026-11-03, CPU, 32 seeds per arm, `~/lpwork/cbk/controls-2026-11-03`)

| Case | Arm | committed | Kinetic (r) | Static (r) |
|---|---|---|---|---|
| foam | seq2 | 1.000 | D 1.012, τ_V 0.998: PASS | all within 0.3%: PASS |
| foam | clock | 0.302 | D 0.491, τ_V 1.724: FAIL | all within 1%: PASS |
| foam | cb | 0.670 | D 0.708, τ_V 1.222: FAIL | all within 0.6%: PASS |
| sort | seq2 | 0.999 | H(t) within 1.3%: PASS | — |
| sort | clock | 0.291 | H(1000) 1.182: FAIL | — |
| sort | cb | 0.337 | H(1000) 1.187: FAIL | — |

- Every positive-control interval is resolved (half-width at most half the margin).
- The clock control separates time from steady state on the foam: static passes, kinetic fails.
- On the sorting case the clock control failed the perimeter standard deviation (r = 0.959).
  Sorting has no steady state, so its volume and perimeter statistics track sorting progress.
  They are therefore not judged on that case; the static verdicts come from the foam only.
  This changes the case definition, not a margin.
- D and τ_V do not scale linearly with the clock (0.49 and 1.72 at a clock of 0.3): over these
  lags the centroid MSD mixes shape fluctuation with diffusion. They are ratios to compare
  between arms, not clock factors.
- Stock checkerboard: on the sorting case it commits 34% of sequential's copies and its H(t)
  curve lies on the clock control's. On the foam it commits 67%. The gap is larger in the
  denser, more active case, as D-220 found.

## 4. Pre-registered criteria

Fixed before any variant is measured.

- **Resolution.** For each observable, the positive control's interval half-width must be at
  most half the margin below. If not, add seeds until it is; an observable that cannot be
  resolved is reported as such, not judged.
- **Margins.** Kinetic observables (committed copies per MCS, H(t), diffusion coefficient,
  volume autocorrelation time, chain T): |r − 1| ≤ 0.05. Static observables (volume and
  perimeter mean and standard deviation): |r − 1| ≤ 0.02.
- **Pass.** An observable passes when the whole 95% interval of r lies inside the margin
  (an equivalence test, not a failure to find a difference).
- **Ranking.** Variants that pass every static observable are ranked by the largest kinetic
  |log r|. Within 0.01 of each other, the one with the lower wall time per
  sequential-equivalent MCS wins (MCS per second times the measured clock ratio).
- A variant that fails a static observable has a steady-state bias. It is reported and not
  made a default, whatever its kinetic score.

## 5. Decisions after measurement

The variant matrix (Phase 3) runs on the PC: stock; R ∈ {1, 2, 4, 8, 16}; with and without
`colors = :replacement`; s ∈ {2, 3, 4}, alone and with retries. The defaults are then set in a DECISIONS entry,
and the `CheckerboardCPM` docstring and the "Choosing an algorithm" page state the remaining
gap per variant. The D-220 ruling and the OpenVT checkerboard record are not changed.

## 6. Correctness tests (Phase 2)

| Step | Tests |
|---|---|
| Counters | Equal recounts from a logged run |
| `colors = :replacement` | Visit counts follow Binomial(C, 1/C) (chi-square); two visits of one color in one MCS get different draws (negative control: without the sub-step key the test fails) |
| `retries` | ΔH of every committed copy equals brute force at commit; volume trackers equal recounts; no cell changes twice in one pass; every loser ends committed, rejected or counted as dropped; negative control: a disabled claim fails these |
| `stride` | Coloring valid for every s (the seam tests extended) |
| All | Same seed, same state: run to run and across workgroup sizes |

## 7. Needs the maintainer

- Re-freezes: `colors = :replacement` changes draw keys only when selected, so stock seeded
  trajectories should not change. Any frozen file that does change is listed before it is
  touched.
- Default changes after §5.
