# Parallel-first design for the remaining model mechanisms

Status: design record, 2026-11-22. No code yet. Decision: D-332. User rulings of 2026-11-22.

## 1. Scope and rule

Six paper models (Bauer 2009, Jiang 2005, Bauer 2007, FBCA, Jafari Nivlouei, Zajac) and the
Dal-Castel variant of Fortuna still need general mechanisms. The gap audit
(`~/lpwork/models-gap/audit.md`) lists them. This note fixes how each mechanism runs in
parallel before it is built.

The rule (user, 2026-11-22):
- Every mechanism runs on `SequentialCPM` and on `CheckerboardCPM`, on the CPU and on a
  device.
- There are no sequential-only mechanisms. Each mechanism has an exact parallel form. Where
  an exact form costs too much, it has a close-to-exact form. A close-to-exact form is a
  documented deviation with a measured bound (section 5).
- Lifecycle rules and per-cell operators run on the device.

This reverses the earlier rulings of 2026-11-22 that allowed sequential-only forms for the
Zajac tensor energy, the FBCA neighbor-site writes and the Starruß angle terms (D-329,
"Solvers").

## 2. What exists today

| Mechanism | Where | What it gives |
|---|---|---|
| Device lifecycle | `lib/CorePotts/src/lifecycle_device.jl`, D-089 | trigger, plan, partition and update kernels; division, removal and kind change planned on the device; a quiet MCS has 0 syncs and 0 transfers |
| Footprint spacing | `lib/CorePotts/src/checkerboard.jl`, `docs/src/manual/algorithms.md` | the spacing between active sub-regions covers every copy-time read; a wider read widens `region` |
| Cell claims (CPU) | `_phase_conflict!` in `checkerboard.jl` | one stamp per cell; a phase whose work items share a cell runs inline, one item after another, which is exact; other phases run threaded |
| Serial list | `_push_serial!`, `serial_kernel!` in `checkerboard.jl` | a copy that needs a whole-cell decision is deferred and decided after the phase, with nothing in flight, on the CPU and on a device |
| Lockless device cells | `checkerboard.jl` header, D-271 | on a device, cell totals change by atomic adds and copies read them live; no cell guarantee |
| Exact finite-time oracle | `lib/CorePotts/test/oracle_core.jl` | the exact distribution of states after m MCS of each algorithm on a tiny lattice, compared by total-variation distance |
| Kinetics harness | `benchmark/kinetics.jl`, `research/checkerboard-kinetics.md` §3–§4 | ratio to `SequentialCPM` with bootstrap intervals; equivalence margins 5 % (kinetic) and 2 % (static); positive, clock and negative controls |

## 3. Lifecycle rules on the device

- `@transition`, `@retire`, `@create`, `@discrete_events` and `@terminate` lower onto the
  D-089 planner. There is one path: the CPU runs the same plan and update functions.
- New device work:
  - **Retire into a collective.** A partition kernel moves the cell's sites to the
    collective. An atomic add updates the collective's volume and target.
  - **Create at a site set.** The planner allocates the id (the same prefix scan as for
    daughters). The partition kernel assigns the sites.
  - **State across a transition.** Cell variables and per-cell component state stay at the
    cell's index; only the kind column changes. Kind-indexed parameters are read through
    the new kind from the next copy.
  - **Discrete events.** The trigger kernel sets device flags. The update kernel applies
    them.
- `@terminate` needs a host decision. The device writes a flag. The host reads it at the
  existing sync points (save, end of `solve!`, checkpoint). See open question Q1.
- Acceptance: the transfer counters test (0 syncs and 0 transfers on a quiet MCS) covers
  every new rule, and device statistics match the CPU (D-029).
- Lifecycle rules run between sweeps, so they do not change what a copy reads. They need no
  checkerboard work.

## 4. Per-cell operators on the device

- **Layout.** One work item (small cells) or one workgroup (large cells) per cell. An
  owner-sorted site index, rebuilt once per MCS by a segmented compaction (O(N)), gives
  each cell its site list.
- **Conservative uptake and secretion.** Each cell sums its demand over its sites. An
  atomic per-cell total caps it. A second pass spreads the result over the sites. A
  conservation test runs on both backends.
- **Random-order operators with write-back** (FBCA impermeable case): see section 6,
  "Random-order operators". They are exact in parallel.
- **FBA solves stay on the host.** The LP solver (JuMP with a COBREXA model) runs on the
  CPU. On a device run this costs one read of the per-cell bounds and one write of the
  per-cell fluxes per MCS. A batched GPU LP solver is not planned. Whether a maintained
  one supports ROCm is not checked. See open question Q2.

## 5. Parallelism rules for copy-time terms

### 5.1 Local reads or kept aggregates

Every copy-time term (energy, drive, constraint, `@on_copy` update) must give an exact ΔH
from either
- reads within a bounded lattice distance of the target (the footprint), or
- per-cell or per-pair aggregates that every copy keeps exact, read for the two cells of
  the copy and their contact or linked neighbors.

This rule makes sequential copies cheap, and it makes the read set of a copy known before
it runs. A known read set is what the checkerboard needs. Threading inside one ΔH is not
planned: a ΔH reads about 8 to 100 sites, so threads cost more than they save on the CPU,
and one kernel launch per copy costs too much on a device. The one candidate is the Zajac
re-evaluation over the contacts of two large cells. It is added only if a measurement shows
a gain.

### 5.2 Read-set claims

Today a CPU phase is exact when its work items share no cell. A term that reads other
cells' live state (contact neighbors' moments, linked cells' centroids) needs more: no
other copy in flight may change a cell that the term reads.

- **Declared read set.** The compiler derives the read set of every copy-time term from its
  expression:
  - always the two cells of the copy;
  - their contact neighbors, for terms over contacts that read neighbor cell state;
  - the cells reached through references and ordered links (`prev`, `next`, up to the
    depth the expression uses, two for angle terms).
- **CPU.** `_phase_conflict!` stamps the written cells of each work item and checks the
  read sets of the other items against them. A phase with a conflict runs inline, which is
  exact. This extends D-053 item 7 (references widen claims) to contacts and links.
- **Device.** Each work item claims its written cells with an atomic stamp and checks its
  read set. A copy with a conflict goes to the serial list and is decided after the phase.
  This is exact. If the serial list grows so long that the device gains nothing, the
  close-to-exact form of 5.3 applies.
- Models without such terms have empty extra read sets. They pay nothing (the same
  criterion as D-051 item 2), and their generated code does not change.

**Limit.** The parallel width falls as cells grow. A phase of a model with few large cells
(Zajac) conflicts often and runs mostly inline. Expect modest speed-ups there. The tier 2
check (section 7) reports the inline fraction and the wall time per sequential-equivalent
MCS.

### 5.3 Close-to-exact form: phase snapshots

The fallback when claims cost too much: snapshot the cell state that other copies read
(moments, centroids, axes) at the start of each phase, and read the snapshot in the phase.

- The lag is one phase, about 1/64 MCS with the default parts. It is not the per-MCS
  lagged director that the Zajac spec rejects as a model change.
- ΔH is exact for the copy's own two cells. The error is confined to neighbor and linked
  state that changed earlier in the same phase.
- The form is a documented deviation. Tiers 1 and 2 measure it against the exact
  sequential form, and its bound goes into the model's deviation table.

## 6. Per-mechanism parallel forms

| Mechanism | Models | Parallel form | Exact? |
|---|---|---|---|
| Lifecycle rules | Bauer 2007 and 2009, Jiang 2005, FBCA, Jafari Nivlouei, Dal-Castel | between sweeps, device planner (section 3) | exact |
| Per-cell operators, uptake | FBCA; Bauer per-cell uptake if chosen | between sweeps, one item or workgroup per cell (section 4) | exact |
| Proposal laws: `UnlikeNeighbor`, Hastings acceptance, `attempts = k` | Bauer 2007, FBCA | local reads; the Hastings ratio counts unlike neighbors at the target and at the source, both within the footprint | exact |
| Neighbor loops `neighbors(c)`, `contact(c, n)` | Jafari Nivlouei | per-pair contact aggregates kept on every copy | exact |
| Lags and windowed means on cell variables | Dal-Castel | between sweeps | exact |
| Small folds (`argmax`, `var`), division plane by draw | Bauer 2007, FBCA, Dal-Castel | between sweeps | exact |
| Ordered chains: angle terms and propulsion | Starruß | read-set claims over `prev`, `next` and their neighbors (two links from each changed cell) | exact; fallback 5.3 |
| Moment tensor in energies, contact geometry per pair | Zajac | moments from running sums (Σx, Σy, Σx², Σy², Σxy, N); per-pair contact aggregates (link count, summed contact-point positions); read-set claims over both cells and their contact neighbors | exact; fallback 5.3 |
| Copy-time writes to neighbor sites | FBCA 08b | `region` widened by the write radius, so writes of two items never overlap; conserved quantities by atomic adds on a device | exact; conservation exact |
| Random-order operators with write-back | FBCA 08b | see below | exact |
| Layouts, analysis helpers | Bauer 2007 and 2009, Starruß, FBCA | setup and post-processing | not affected |

**Random-order operators.** The paper solves each cell's FBA in a random order and writes
the result back to the field before the next solve. Two cells interact only if one's read
or write site set overlaps the other's. So:
1. draw the permutation;
2. give each cell the round 1 + max(round of every earlier cell in the permutation whose
   site sets overlap its own);
3. run the cells of a round at the same time, rounds in order.

Every cell sees exactly the field it would see in the sequential order, so the result
equals the sequential result for the same permutation, not only in distribution. The
rounds come from the owner-sorted site index (section 4). On the host they are threaded LP
solves.

**Zajac aggregates.** The paper averages over each contact segment (12 spec, P-Z9: one
segment per cell pair). With per-pair link counts and summed contact-point positions, the
segment's mean point gives r sin θ for each cell from the cell's centroid and axis in O(1)
per pair. The cost of an exact ΔH is then O(contact neighbors of the two cells). If the
screens rule that r sin θ is averaged per link and not taken at the mean point, the
absolute value prevents an O(1) update when the axis turns. The cost is then
O(boundary links of the two cells). Both are exact. The choice follows the spec's A-Z4
screen, not this note.

## 7. Kinetic checks in tiers

| Tier | Check | Cost | When |
|---|---|---|---|
| 0 | per-copy exactness on both algorithms: brute-force ΔH at commit, trackers equal recounts, conservation; each with a negative control (for example, with read-set claims disabled the test must fail) | seconds | every gate |
| 1 | the exact finite-time oracle extended to each new copy-time term, for both algorithms, on a tiny lattice | seconds to minutes | every gate |
| 2 | the kinetics harness on a minimal case per mechanism (the smallest lattice where the term matters); seeds start at 8 and are added until the positive control resolves (half-width at most half the margin), up to a cap; positive, clock and negative controls; the margins of `checkerboard-kinetics.md` §4 | about 1 core-hour per mechanism | once, when the parallel form lands, with an A/B |
| 3 | full-model kinetics | full-run cost | only for checkerboard claims in the paper |

- Tier 1 is the conclusive check: it compares with an exact distribution, so no tolerance
  can hide a bias, and it is cheap. Tiny lattices cannot show cell-scale effects, such as a
  Zajac axis turning over a large cell. Tier 2 covers those.
- A close-to-exact form (5.3) passes only if tier 2 passes. Its measured ratios go into the
  model's deviation table.
- The oracle re-derives every term from its specification and does not call production code
  except `solve`. Each new term therefore needs an independent oracle implementation.

## 8. Open questions

- **Q1.** May the device check `@terminate` every k MCS (a stated keyword), or must the
  stop be exact to the MCS? Exact means one read-back per MCS on a device.
- **Q2.** Is FBA on the host acceptable for device FBCA runs (one read and one write per
  MCS)?
