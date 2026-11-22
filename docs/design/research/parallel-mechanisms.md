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
| Cell stamps (CPU) | `_phase_conflict!` in `checkerboard.jl` | one stamp per cell over a lattice box of radius `need` around each work item's sub-region; a phase whose work items share a cell runs inline, one item after another, which is exact; other phases run threaded. On a device `_phase_conflict!` returns false |
| Serial list | `_push_serial!`, `serial_kernel!` in `checkerboard.jl` | a copy that needs a whole-cell decision is deferred and decided after the phase, with nothing in flight, on the CPU and on a device. It is allocated only for models with whole-cell connectivity |
| Lockless device cells | `checkerboard.jl` header, D-271 | on a device, cell totals change by atomic adds and copies read them live; no cell guarantee |
| Reference and link reads | D-271 (claim machinery removed), D-065 Q7 | nothing claims the cells reached through references or links today. A copy reads them live: on the CPU only the box stamps above protect them, and on a device nothing does. The Starruß propulsion drive (D-330) runs on `CheckerboardCPM` this way |
| Exact finite-time oracle | `lib/CorePotts/test/oracle_core.jl` | the exact distribution of states after m MCS of each algorithm on a tiny lattice, compared by total-variation distance |
| Kinetics harness | `benchmark/kinetics.jl`, `research/checkerboard-kinetics.md` §3–§4 | ratio to `SequentialCPM` with bootstrap intervals; equivalence margins 5 % (kinetic) and 2 % (static); positive, clock and negative controls |

## 3. Lifecycle rules on the device

- `@transition`, `@retire`, `@create`, `@discrete_events` and `@terminate` lower onto the
  existing lifecycle events. Today there are two planners: the CPU runs the D-035 host
  planner (`_step_lifecycle!` in `lib/CorePotts/src/problem.jl`), and a device runs the
  D-089 planner. `SequentialCPM` never runs the device planner. Each new rule therefore
  needs a host form and a device form, with one test that runs both. Merging the two
  planners is a separate choice, not part of this record.
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
- **Sets per work item.** Claims are per work item, not per copy, because one item makes
  all the attempts of its sub-region. Its write set W is the set of cells in its box of
  radius `need`, as `_phase_conflict!` already computes. W also includes the third cells
  whose per-pair aggregates a commit changes (the target's neighbor cells, as with
  `commit_contact_count!`). Its read set R is the declared read set of every cell in W.
- **Conflict test (symmetric).** Two items conflict if W of one meets R ∪ W of the other.
  Read-read overlap is not a conflict.
- **Protocol (CPU and device).**
  1. A marking pass, one launch: each item marks every cell of W with a writer stamp
     (compare-and-swap; a second writer sets the cell to "contested") and every cell of R
     with a reader stamp (its block id, or "many" if another reader came first).
  2. The kernel boundary orders all marks before all checks.
  3. A check pass: an item is clear if every cell of its W has itself as the only writer
     and no reader other than itself, and every cell of its R has no writer other than
     itself.

  Clear items run in parallel. Items that are not clear run after the phase, one after
  another, in block order. This is the serial pass, applied to whole items; it needs the
  serial list allocated whenever a model declares extra read sets. A clear item neither
  reads nor writes anything that another item writes, so its attempts commute with every
  other item's. The phase is therefore equal to a sequential run of its items, and every
  committed ΔH is exact.
- **On the CPU** this replaces the same-cell test of `_phase_conflict!` for models with
  extra read sets. A phase with a conflict can still run inline as a whole, as today.
- **Preconditions.** Read sets come from the state at the start of the phase. That is
  sound because ordered links change only between sweeps, and a contact that appears
  inside a phase lies inside the writer's box, so the box already conflicts. Contact
  read sets need the box radius to cover the contact relation, as `need` already does.
- **Cost.** The marking pass costs about (sites in the box) × (read-set size) per item per
  phase. Tier 2 reports it with the fraction of items deferred.
- This restores claims for these models only. It amends D-065 Q7 (exact again under claims,
  for terms with declared read sets) and D-271 (claims return as an option on the
  lockless checkerboard).
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
| Proposal laws: `UnlikeNeighbor`, Hastings acceptance, `attempts = k` | Bauer 2007, FBCA | local reads; the Hastings ratio needs the forward and reverse proposal probabilities (for a site-then-unlike-neighbor law, the unlike-neighbor count at the target before and after the copy), both within the footprint | exact |
| Neighbor loops `neighbors(c)`, `contact(c, n)` | Jafari Nivlouei | per-pair contact aggregates kept on every copy | exact |
| Lags and windowed means on cell variables | Dal-Castel | between sweeps | exact |
| Small folds (`argmax`, `var`), division plane by draw | Bauer 2007, FBCA, Dal-Castel | between sweeps | exact |
| Ordered chains: angle terms and propulsion | Starruß | read-set claims over `prev`, `next` and their `prev` and `next` (two links from each changed cell, from the six pivots of D-329) | exact; fallback 5.3 |
| Moment tensor in energies, contact geometry per pair | Zajac | moments from running sums (Σx, Σy, Σx², Σy², Σxy, N); contact energy re-evaluated over the boundary links of both cells (see below); read-set claims over both cells and their contact neighbors | exact; fallback 5.3 |
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
solves. Preconditions:
- site sets, retirements and divisions do not change during the pass;
- per-cell draws are keyed by cell, not by position in the permutation;
- overlap between two read sets alone is not a conflict.

In compact tissue, where every cell overlaps its neighbors, the number of rounds can grow
to O(number of cells). Tier 2 reports the round count.

**Zajac contact cost.** The spec's working inference (12 spec, P-Z9) averages r sin θ over
the links of each cell pair. Because of the absolute value in r sin θ, that average must
be recomputed link by link when a cell's axis turns. The default exact ΔH therefore costs
O(boundary links of the two cells). An alternative takes r sin θ at the mean contact point
of each pair. Per-pair link counts and summed positions then give O(1) per pair, and the
ΔH costs O(contact neighbors of the two cells). That alternative changes the model, so it
is used only if the authors confirm it (question Q-Z6). Both costs are exact.

## 7. Kinetic checks in tiers

| Tier | Check | Cost | When |
|---|---|---|---|
| 0 | per-copy exactness on both algorithms: brute-force ΔH at commit, trackers equal recounts, conservation; each with a negative control (for example, with read-set claims disabled the test must fail). The checkerboard runs use `threads = true` with enough blocks that phases really run threaded, plus one device run | seconds | every gate |
| 1 | the exact finite-time oracle extended to each new copy-time term, for both algorithms, on a tiny lattice | seconds to minutes | every gate |
| 2 | the kinetics harness on a minimal case per mechanism (the smallest lattice where the term matters); seeds start at 8 and are added until the positive control resolves (half-width at most half the margin), up to a cap; positive, clock and negative controls; the margins of `checkerboard-kinetics.md` §4 | about 1 core-hour per mechanism | once, when the parallel form lands, with an A/B |
| 3 | full-model kinetics | full-run cost | only for checkerboard claims in the paper |

- Tier 1 checks a term's law exactly: it compares with an exact distribution, so no
  tolerance can hide a bias, and it is cheap. It does not test claims: on a tiny lattice
  every phase runs inline (the oracle models in-order block execution). Tier 0 tests the
  claims.
- Tiny lattices cannot show cell-scale effects, such as a Zajac axis turning over a large
  cell. Tier 2 covers those.
- A close-to-exact form (5.3) passes only if tier 2 passes. Its measured ratios go into the
  model's deviation table.
- The oracle re-derives every term from its specification and does not call production code
  except `solve`. Each new term therefore needs an independent oracle implementation.

## 8. Open questions

- **Q1.** May the device check `@terminate` every k MCS (a stated keyword), or must the
  stop be exact to the MCS? Exact means one read-back per MCS on a device.
- **Q2.** Is FBA on the host acceptable for device FBCA runs (one read and one write per
  MCS)?
