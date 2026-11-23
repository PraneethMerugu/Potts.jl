# Parallel-first design for the remaining model mechanisms

Status: design record, 2026-11-22, revised the same day after the design review
(`~/lpwork/d332-review/review.md`). No code yet. Decision: D-332. User rulings of 2026-11-22.

## 1. Scope and rule

Six paper models (Bauer 2009, Jiang 2005, Bauer 2007, FBCA, Jafari Nivlouei, Zajac) and the
Dal-Castel variant of Fortuna still need general mechanisms. The gap audit
(`~/lpwork/models-gap/audit.md`) lists them. This note fixes how each mechanism runs in
parallel before it is built.

The rule (user, 2026-11-22):
- **One model path.** Every model has one generated code path, and that path runs under every
  algorithm. No mechanism is refused on any algorithm.
- Every mechanism runs on `SequentialCPM` (CPU only, as today) and on `CheckerboardCPM`, on
  the CPU and on a device.
- How a copy reads other cells' state is a policy of the algorithm, not of the model
  (section 5.3). Only one policy, `:exact`, is called exact (section 8).
- Lifecycle rules and per-cell operators run on the device.

This reverses the earlier rulings of 2026-11-22 that allowed sequential-only forms for the
Zajac tensor energy, the FBCA neighbor-site writes and the Starruß angle terms. D-329's
refusal of non-sequential algorithms for angle terms is lifted when the read layer of
section 5 lands.

## 2. What exists today

| Mechanism | Where | What it gives |
|---|---|---|
| Lifecycle planner | `lib/CorePotts/src/lifecycle_planner.jl`, D-089, D-332 | one KernelAbstractions planner for every backend and algorithm. CPU: staged form; a quiet MCS runs only the trigger kernel; statistics fold at each event round. Device: fused or staged form; a quiet MCS has 0 syncs and 0 transfers. `PLAN_WG` is fitted to the backend by halving. Host hooks run as a stage after the planner |
| Footprint spacing | `lib/CorePotts/src/checkerboard.jl`, `docs/src/manual/algorithms.md` | the spacing between active sub-regions covers every copy-time read; a wider read widens `region` |
| Cell stamps (CPU) | `_phase_conflict!` in `checkerboard.jl` | one stamp per cell over a lattice box of radius `need` around each work item's sub-region; a phase whose work items share a cell runs inline in block order, which is exact; other phases run threaded. It is a serial host loop. On a device it returns false |
| Serial list | `_push_serial!`, `serial_kernel!` in `checkerboard.jl` | a copy that needs a whole-cell connectivity decision is deferred and decided after the phase, on the CPU and on a device (one work item). It is allocated only for models with whole-cell connectivity |
| Lockless device cells | `checkerboard.jl` header, D-271 | on a device, cell totals change by atomic adds and copies read them live; no cell guarantee |
| Paired 32-bit sums | `_paired` in `lib/CorePotts/src/spatial.jl` | a 64-bit integer sum as two 32-bit words where the backend has no 64-bit atomics (Metal) |
| Reference and link reads | D-271 (claim machinery removed), D-065 Q7, D-330 | nothing protects cells reached through references or links. On the CPU only the box stamps above help; on a device nothing does. The D-330 drive reads (centroids of referenced cells) on `CheckerboardCPM` are live and unprotected on both backends |
| Exact finite-time oracle | `lib/CorePotts/test/oracle_core.jl` | the exact distribution of states after m MCS of each algorithm on a tiny lattice, compared by total-variation distance; it models in-order block execution |
| Kinetics harness | `benchmark/kinetics.jl`, `research/checkerboard-kinetics.md` §3–§4 | ratio to `SequentialCPM` with bootstrap intervals; equivalence margins 5 % (kinetic) and 2 % (static); positive, clock and negative controls |

## 3. One lifecycle planner

One KernelAbstractions planner replaces the two planners. It runs on the CPU backend and on
a device, for every algorithm, `SequentialCPM` included. `@transition`, `@retire`,
`@create`, `@convert`, `@discrete_events` and `@terminate` are built once, in this planner.

- **New device work.**
  - **Retire into a collective.** A partition kernel moves the cell's sites to the
    collective. An atomic add updates the collective's volume (an integer), and the rule's
    own update statement updates its target (see "Collective and target" below).
  - **Create at a site set.** The planner allocates the id (the same prefix scan as for
    daughters). The partition kernel assigns the sites. `@create` and `@convert` (D-066,
    `convert.jl`, today a host routine plus kernels) move into the planner.
  - **State across a transition.** Cell variables and per-cell component state stay at the
    cell's index; only the kind column changes. Kind-indexed parameters are read through
    the new kind from the next copy.
  - **Discrete events.** The trigger kernel sets device flags. The update kernel applies
    them.
- `@terminate` needs a host decision. The device writes a flag. The host reads it at the
  existing sync points (save, end of `solve!`, checkpoint). See open question Q1.
- Lifecycle rules run between sweeps, so they do not change what a copy reads. They need no
  checkerboard work.

**Event precedence in one lifecycle round (user ruling, 2026-11-22).** Every trigger
reads the state before the round. The events then apply in the order retire and remove,
convert, transition, divide, create, then model-scope discrete events, then the terminate
check. Reason: it extends the existing priority list (remove > convert > transition > divide
> create, `research/feature-roadmap-review.md`) and keeps A-17, and no outcome depends on
cell index.

| A cell or site set has, in one round | Outcome |
|---|---|
| retire (or remove) and divide | the cell retires; the division is dropped |
| retire (or remove) and transition | the cell retires; the transition is dropped |
| transition and divide | the transition applies first; both halves carry the new kind (A-17, as today) |
| retire `sites => ref`, and `ref` also retires | the sites go with `ref` to `ref`'s destination |
| retire `sites => ref`, and `ref` divides | the sites join `ref` first; `ref` then divides |
| `@create` at sites that a retiring cell owns | the create applies after the retire; it takes the sites that are medium after the retire |
| `@create` at sites that a dividing cell owns | those sites belong to a daughter, so the create skips them; skipped sites are counted, and a create with no site left is dropped and counted |
| a discrete event and any cell event | cell triggers read the state before the round; model-scope affects apply after the cell events |
| `@terminate` | checked after the whole round; the round's events stay applied, then the run stops |

**Retirement chains and cycles.** A retire `sites => ref` whose `ref` also retires forms a
chain; a retires into b while b retires into a forms a cycle. The planner resolves every
destination by pointer doubling: each step sets dest[c] = dest[dest[c]] for every cell whose
destination also retires, reading the previous step's array (double buffered). Four steps
resolve every chain of up to 16 links. A cell whose destination still retires after the
four steps is in a cycle or in a chain longer than 16 links. Its sites go to the medium, and
the event is counted in the lifecycle statistics. The resolution takes a fixed number of
steps, is deterministic and does not depend on cell index or launch order.

**Collective and target (user ruling, 2026-11-22).** A collective is an ordinary
cell: one id, its own kind, declared `collective = true` so that it may have several pieces
without a split warning (api-synthesis §2). Its target is a cell variable of that cell (for
example `V_target`), not a parameter. A retire into the collective always adds the retired
volume to the collective's volume tracker. The target changes only through the rule's own
update statement (`V_target[core] += volume`). Reason: this is the Jiang 2005 sketch of
api-synthesis §5.2, and no hidden rule changes a target.
- **Order-independent target updates.** The planner applies the rule's target updates in
  cell order (increasing id of the retiring cell), not by float atomic add. Generic number
  types (Duals, mixed precision) then work, and results are deterministic. An integer target
  may use atomic adds, because integer addition does not depend on order.

**Acceptance.** The host planner is deleted only after all of the following hold.

**Status (2026-11-22).** Items 1 to 3 hold; the host planner is deleted (commit
5f3b82b2). Item 4, the CPU A/B, is pending.

1. **Five host behaviors.**
   - Host hooks (`Lifecycle.rebuild!`, a custom `remake_frozen`, cell-scope `pieces` with a
     lifecycle) run as an explicit host stage after the planner, not as a second planner.
   - No silent handover. **User ruling, 2026-11-22:** a staged form that always
     launches, with `PLAN_WG` adapted to the backend's workgroup limit (more stages where
     needed), and no host fallback. Reason: it keeps one planner, as ruled, and the limits
     are known at `init`, so a test can cover the smallest workgroup.
   - The `SequentialCPM` mobile-site list is rebuilt when the event flag is set. On the CPU
     the flag is in host memory, so the read is free.
   - Moment scratch is Int64 where `_atomic64(backend)` holds, as `mcnt` already is, so large
     cells do not hit the Int32 deferral of `_scratch_ok`. The Int32 form stays only where a
     backend lacks 64-bit atomics.
   - A CPU quiet MCS exits after the trigger kernel, without the fixed kernel sequence.
2. **Transfer counters.** A quiet device MCS stays at 0 syncs and 0 transfers. The CPU counts
   of D-035 (1 sync and 4 B per checked MCS) change; the tests that check them are updated
   with the measured values.
3. **Statistics.** Device and CPU statistics match (D-029). CPU code that reads
   `stats.lifecycle` mid-run goes through the fold of the Int32 counters (D-089).
4. **CPU A/B.** Quiet and event MCS on Akeeb, Merks and OpenVT, the unified planner against
   the host planner, on the quiet PC.

## 4. Per-cell operators on the device

- **Layout.** One work item (small cells) or one workgroup (large cells) per cell. An
  owner-sorted site index, rebuilt once per MCS by a segmented compaction (O(N)), gives
  each cell its site list.
- **Conservative uptake and secretion.** Each cell sums its demand over its sites. An
  atomic per-cell total caps it. A second pass spreads the result over the sites. A
  conservation test runs on both backends.
- **Random-order operators with write-back** (FBCA impermeable case): see section 6,
  "Random-order operators".
- **FBA solves stay on the host.** The LP solver (JuMP with a COBREXA model) runs on the
  CPU. On a device run this costs one read of the per-cell bounds and one write of the
  per-cell fluxes per MCS. A batched GPU LP solver is not planned. Whether a maintained
  one supports ROCm is not checked. See open question Q2.

## 5. Copy-time terms: one path, one read layer

### 5.1 State: running sums that commits only add to

Every copy-time term (energy, drive, constraint, `@on_copy` update) gives an exact ΔH from
reads within the footprint or from cell state kept as running sums.

- **Running sums.** Every shared cell quantity that a copy-time term reads is a running sum
  that a commit only adds to: N, Σx, Σy, Σz, Σx², Σy², Σz², Σxy, Σxz, Σyz, perimeter,
  contact counts, and the per-pair contact store (section 5.7) where a term needs it.
- **One source.** The adds are plain on `SequentialCPM` and atomic on parallel backends,
  from one KernelAbstractions and Atomix source.
- **Integers.** Position sums are integers over the unwrapped coordinates that the centroid
  trackers use, so they are exact and independent of order. They are relative to the cell's
  anchor and re-centered between sweeps, as today (`geometry.jl`). They are Int64 where
  `_atomic64(backend)` holds, and paired 32-bit words elsewhere (`_paired`).
- **Covariance in integers.** The covariance is formed in integers (for example
  N·Σxy − Σx·Σy) before the conversion to float, so the axis keeps Float32 precision.
- **Derived values.** Centroid, axis, angle and curvature are computed on read from the sums.
  Nothing derived is stored.
- **No threading inside one ΔH.** A ΔH reads about 8 to 100 sites, so threads cost more than
  they save on the CPU, and one launch per copy costs too much on a device. The one candidate
  is the Zajac re-evaluation over the contacts of two large cells. It is added only if a
  measurement shows a gain.

### 5.2 Read sets: emitted by the compiler, complete

The compiler emits the read set of every copy-time term from its expression. A model whose
terms read only the copy's two cells has no extra read set. The read set contains:
- the two cells of the copy;
- their contact neighbors, for terms that read neighbor cell state;
- the link partners of every relationship whose terms read partner state, ordered and
  unordered (`link_delta` reads the centroid of every link partner of `old` and `new`), up
  to the depth the expression uses (two links for angle terms);
- the cluster roots, for terms that read cluster aggregates (`cluster_volume`,
  `cluster_surface`); roots are cell ids and share the cell stamps, which is conservative;
- the cells reached through references (`CellRef` fields), the D-330 drive reads included.

Rules that keep the sets sound:
- **Scope.** A read set covers only state that copies change: the running sums and the cell
  columns that `@on_copy` writes. Link topology and `rank` are constant inside a sweep
  (links change only in lifecycle and `@link` phases, D-329), so they need no protection,
  although `rank` walks without bound.
- **Reference-write rule.** In a model with extra read sets, a copy-time write to a reference
  may target only `old`, `new`, `id` or 0. Those targets are already in the write set.
  Any other value is a typed `PottsCompileError` that names the rule. No model uses such
  writes today.
- **Model-level state.** A copy-time term may read model-level state only if no copy writes
  it. The compiler checks this and refuses the model with a typed error. No such path exists
  in CorePotts today.

### 5.3 One read accessor, read policy chosen by the algorithm

Generated code reads other cells' state through one accessor. The read policy is a type
parameter that the algorithm chooses. A model without extra read sets compiles to the same
generated code as today under every policy; an A/B against the parent commit shows it.

| Algorithm | Policy | What a read of another cell returns |
|---|---|---|
| `SequentialCPM` | always exact | the live state; nothing else is in flight |
| `CheckerboardCPM(reads = :exact)` | priority rounds (5.4) | the live state; no conflicting item is in flight |
| `CheckerboardCPM(reads = :snapshot)` | per-phase copy (5.5) | the state at the start of the phase |
| `CheckerboardCPM(reads = :live)` | version counters (5.6) | a consistent live value of each cell |

- **Models without extra read sets.** Their generated code never changes. `:snapshot` and
  `:live` run today's path for them: the CPU same-cell test and the lockless device scheme.
  `:exact` applies to all models: for these models it runs priority rounds over same-cell
  conflicts only (5.4), which changes the scheduler, not the model code. It therefore also
  makes device runs exact for cells wider than the spacing. It costs something only when
  `:exact` is chosen.
- **Defaults.** On the CPU the default is `reads = :exact`, for every model. On a device the
  default is chosen after a measurement of the round counts, the launch cost and tier 2.
- **A/B.** The default path is A/B-tested against today's path before it becomes the
  default: on the CPU, `:exact` against today's same-cell scheme for models without extra
  read sets (the generated code is equal, so the A/B measures the scheduler).

### 5.4 `reads = :exact`: priority rounds

Under `:exact` a phase equals a sequential run of all its work items in a random order.
The order is pseudo-random (a keyed bijection of the block indices), not uniform over all
n! orders. Every committed ΔH is then exact. `:exact` applies to every model.

- **Sets per item.** Claims are per work item, because one item makes all the attempts of its
  sub-region. Its write set W is the cells in its box of radius `need`, as `_phase_conflict!`
  computes, plus the third cells whose per-pair aggregates a commit changes (the target's
  neighbor cells, as with `commit_contact_count!`). Its read set R is the union of the read
  sets (5.2) of the cells in W. For a model without extra read sets, R adds nothing to W:
  W is the cells in the item's box, and conflicts are same-cell conflicts only.
- **Conflict.** Two items conflict if W of one meets W ∪ R of the other. Read-read overlap is
  not a conflict.
- **Keys.** Each item gets a unique random key per phase: a bijective keyed mix of its block
  index (a small Feistel network, with cycle-walking to the block count). The mix key comes
  from the counter RNG on its own stream, keyed by MCS and phase. Bijectivity rules out ties.
- **Rounds.** Repeat until no item remains:
  1. **Mark** (one launch). Each remaining item rebuilds W and R from the current state and
     writes its key by atomic min into two per-cell words: `amin` for every cell of W ∪ R,
     and `wmin` for every cell of W.
  2. **Check and run** (one launch). An item runs if `amin` equals its key on every cell of W,
     and `wmin` is its key or larger on every cell of R. That is, no remaining conflicting
     item has a smaller key. The item then makes its attempts.

  Items of one round are pairwise free of conflicts, and every conflicting pair runs in key
  order. The remaining item with the smallest key always runs, so every round makes
  progress. W and R must be rebuilt each round: an earlier item can give a later item's cell
  a new contact neighbor that a third item writes in the same round.
- **Why check and run can share one launch.** While item j checks, other items of the same
  launch may already run. Item j's check is still sound:
  - W_j comes from σ in j's box. A running item i writes only its own sub-region, which lies
    outside j's box because the spacing is at least `need` + 1.
  - R_j comes from the contact store and the references of the cells of W_j. A running item
    changes those only for cells in W_i, and a cell in W_i ∩ W_j is already a conflict, so j
    does not run this round.
  - A cell that j enumerates at check time but did not mark fails the check. That is
    conservative: j waits for a later round.
- **Marks and token.** A mark is the round token in the high bits and the key in the low
  bits. The token is one global counter that decreases by one every round, across phases
  and MCS. Fresh marks are therefore always smaller than every stale mark, so the atomic min
  needs no reset launch. When the counter reaches 0, one `fill!` resets both arrays and the
  counter restarts at its maximum. A token that restarted each phase would be unsound: the
  small tokens of the last phase would beat this phase's fresh marks, so `amin` would never
  equal a key on cells marked late in the last phase, and those items would never run.
- **Mark width and limits.**
  - On backends with 64-bit atomics (CPU, ROCm, CUDA) the marks are 64-bit: a 32-bit token
    and a 32-bit key. Up to 2^32 items per phase; the token wraps after 2^32 rounds. Memory:
    2 × cell capacity × 8 B.
  - Elsewhere (Metal) the marks are 32-bit. The token width is chosen per run:
    t = 32 − ceil(log2(items per phase)), and `fill!` runs every 2^t − 1 rounds. For example,
    a 1024³ lattice with `parts = 4` and b = 1 has (1024/4)³ = 2^24 items per phase, so
    t = 8 and `fill!` runs every 255 rounds. Memory: 2 × cell capacity × 4 B.
  - `init` throws a typed error only when neither fits: more than 2^32 items per phase with
    64-bit marks, or more than 2^31 (t < 1) with 32-bit marks.
- **Marking cost.** The check launch rescans the box and expands R again, about twice the
  marking cost. No per-item lists are stored: a duplicate atomic min with the same key is
  harmless, so no deduplication buffer is needed. On the CPU the marking is a KA launch, not
  a serial host loop like `_phase_conflict!`.
- **Launches.** Two per round, plus a 4-B read of the remaining-item count every r rounds,
  with r chosen by measurement; launches with no remaining items return at once. At 64 phases
  and 3 rounds that is about 400 launches per MCS. On a device the read-back is a sync, so
  there are at least 64 syncs per MCS at 64 phases. The device-default measurement (Q3)
  counts them. An alternative is a fixed round budget per phase, gated on the device, with
  one read-back per MCS to adapt the budget.
- **CPU: rounds or inline per phase.** On the CPU, running a phase inline in key order gives
  the same result, path by path, as running it in rounds. So the scheduler may choose rounds
  or inline for each phase by cost (for example, inline when the expected round count
  exceeds a threshold) without changing any result. This protects the CPU A/B of the
  `:exact` default.
- **Inline paths.** Every phase with a conflict uses the key order, also when it runs inline:
  `cache.inline` (at most 512 blocks, `threads = false`, threaded ensembles), small block
  counts, and phases that run inline because of a conflict. Because `:exact` is the CPU
  default for every model, this changes CPU results for all models (no pins, D-275) and the
  tier 1 oracle (section 7).
- **Draws.** Attempts draw by (block, lid), never by round or position. An item runs exactly
  once per phase, so no draw is used twice. Tier 0 tests this invariant.
- **Exception.** Copy-level connectivity deferrals (`_push_serial!` from `block_attempt!`)
  are decided after the phase, as today. They commute with other items' work, but they are
  not part of "a sequential run of items". The exactness statement names them.
- **Reproducibility.** The classification does not depend on the order of the atomic mins,
  so a host brute-force classification and the device agree exactly, and an `:exact` device
  run is reproducible apart from float atomics.
- **Region policy.** The probe of the review (2D Voronoi, 256², `need = 2`) needed 13 to 46
  rounds at b ≤ 2 and 2.4 to 3.3 rounds at b = 4 to 8. Region changes the checkerboard
  kinetics. So each model with extra read sets gets its region from a measured sweep of
  rounds × launch cost against kinetics. Tier 2 runs at the chosen region, which the model's
  docs record. Models without extra read sets keep today's default region under every
  policy.

### 5.5 `reads = :snapshot`: per-phase copy

At the start of each phase, a copy is taken of the cell state that the read sets read. Reads
of other cells return the copy; reads of the copy's own two cells stay live.

- The lag is one phase: 1/(k^d · switches) MCS, which is 1/64 MCS only at the default parts
  with one switch. It is not the per-MCS lagged director that the Zajac spec rejects as a
  model change.
- The error is confined to neighbor and linked state that changed earlier in the same phase.
- It is a documented deviation. It is allowed in a model only after tier 2 passes, with its
  measured ratios in the model's deviation table.

### 5.6 `reads = :live`: version counters

Reads of other cells are live, and a per-cell version word makes each read consistent: a
reader never sees half of one commit's adds.

- **Generic.** Codegen and CorePotts build the counters for every model with extra read sets.
  Nothing is model-specific.
- **Writer.** A commit brackets its adds to a cell with two atomic adds on the cell's version
  word. On a device several items can commit to one cell at the same time (lockless scheme),
  so a single odd or even version is not enough: two concurrent writers leave it even. The
  word therefore packs an epoch (high bits) and an in-flight writer count (low bits). Begin
  adds one to the count. End subtracts one from the count and adds one to the epoch, in one
  atomic add. With the epoch in the high bits, its carry leaves the word harmlessly when it
  wraps; in the low bits it would raise the count for the rest of the run.
- **Field widths.** The count has at least ceil(log2(items per phase + 1)) bits, because at
  most one commit per item is in flight. The epoch has at least 16 bits, which makes ABA
  (the word returning to the same value during one read) negligible. The word is 64-bit
  where the backend has 64-bit atomics. On Metal it is 32-bit, which allows at most
  2^16 − 1 items per phase under `:live`; `init` throws a typed error above that.
- **Protocol.**
  - Writer: begin (atomic add of one, relaxed); a release fence; the adds to the sums
    (relaxed atomics); end (the atomic add of the end step, with release ordering).
  - Reader: load the word with acquire ordering (v1); retry if its count is not 0; load the
    sums (relaxed atomics); an acquire fence; load the word again (v2); retry if v2 ≠ v1.
  - The release fence after begin keeps the adds from becoming visible before the count.
    The acquire fence before the second load keeps the sum loads before it. Without these
    fences torn reads go undetected and the counter undercounts.
- **Precondition.** `:live` is built on a backend only if Atomix or KernelAbstractions gives a
  device-wide fence there (ROCm, CUDA, Metal). The builder checks this first. Without the
  fence, `:live` is not built on that backend.
- **Retry cap.** Retries are bounded by a stated cap, because a GPU wavefront without
  independent forward progress can spin on a writer in its own wavefront. At the cap the
  reader takes the value as read and counts a torn read. Torn reads are counted per block,
  as `cnt` is, not in one global atomic, and are folded into the solve statistics at read
  points, so the rate is measured and reported. Two consequences:
  - A reader lane that waits on a writer lane of its own wavefront always reaches the cap.
    So the count includes these lockstep waits, which do not tear a value, and overstates
    real tears.
  - A large hot cell with many concurrent writers (Zajac) rarely shows a count of 0, so most
    of its reads will be torn. `:live` is expected to fail tier 2 for such models.
- **Data races.** CPU reads and writes of shared sums use relaxed atomic access, so threaded
  runs have no data races.
- `:live` is not exact. It is a documented deviation under the same tier 2 rule as
  `:snapshot`.

### 5.7 Per-pair contact store

Contact read sets, `neighbors(c)` and `contact(c, n)` need each cell's neighbor list. Today
only per-cell counts by kind mask exist (`lib/CorePotts/src/contact_counts.jl`).

- Each cell has a fixed maximum degree of (neighbor id, contact count) slots. Overflow sets
  the status word, which raises a typed error at the next sync.
- A commit adds the count changes for the target's neighbor cells, which are in W. Counts
  change by atomic add.
- A slot is found or inserted in a fixed probe order. The writer scans for its neighbor's id
  and, at an empty slot, tries a compare-and-swap of the id. After a failed compare-and-swap
  it compares the winner's id with its own: if equal it uses that slot, else it probes on.
  Without this check two lockless writers would insert duplicate slots for one neighbor.
- A slot whose count reaches 0 keeps its id until a compaction between sweeps, so slot reuse
  never races with an insert.
- The store is allocated only for models whose terms read contact neighbors.

## 6. Per-mechanism parallel forms

All forms below run on the one model path. "Exact" means exact under `SequentialCPM` and
under `reads = :exact`.

| Mechanism | Models | Parallel form | Exact? |
|---|---|---|---|
| Lifecycle rules | Bauer 2007 and 2009, Jiang 2005, FBCA, Jafari Nivlouei, Dal-Castel | between sweeps, the one planner (section 3) | exact |
| Per-cell operators, uptake | FBCA; Bauer per-cell uptake if chosen | between sweeps, one item or workgroup per cell (section 4) | exact |
| Proposal laws: `UnlikeNeighbor`, Hastings acceptance, `attempts = k` | Bauer 2007, FBCA | local reads; the Hastings ratio below | exact |
| Neighbor loops `neighbors(c)`, `contact(c, n)` | Jafari Nivlouei | the per-pair contact store (5.7); read sets over contact neighbors if the loops run at copy time | exact |
| Lags and windowed means on cell variables | Dal-Castel | between sweeps | exact |
| Small folds (`argmax`, `var`), division plane by draw | Bauer 2007, FBCA, Dal-Castel | between sweeps | exact |
| Ordered chains: angle terms and propulsion | Starruß | read sets over `prev`, `next` and their `prev` and `next` (two links from each changed cell, from the six pivots of D-329) | exact under `:exact` |
| Moment tensor in energies, contact geometry per pair | Zajac | moments from running sums; contact energy re-evaluated over the boundary links of both cells (see below); read sets over both cells and their contact neighbors | exact under `:exact` |
| Copy-time writes to neighbor sites | FBCA 08b | `region` widened by the write radius, so writes of two items never overlap and need no atomics | exact; conservation exact |
| Random-order operators with write-back | FBCA 08b | see below | exact |
| Layouts, analysis helpers | Bauer 2007 and 2009, Starruß, FBCA | setup and post-processing | not affected |

**Hastings ratio.** The site-then-unlike-neighbor law picks the target t uniformly over all
sites and the source uniformly over the unlike neighbors of t. Let t belong to a, the copy
give t to b, u(t) and u′(t) be the unlike-neighbor counts before and after, and n_a(t) and
n_b(t) the numbers of neighbors of t that a and b own. The forward probability is
∝ n_b(t)/u(t), the reverse ∝ n_a(t)/u′(t), and the ratio is (n_a/u′)/(n_b/u). Everything
lies within the footprint. A target with u(t) = 0 is rejected. Targets uniform over boundary
sites (`skip_interior`) would add a global normalizer; see Q5, settled when the model is built.

**Random-order operators.** The paper solves each cell's FBA in a random order and writes
the result back to the field before the next solve. Cells i and j conflict if the write site
set of one meets the read or write site set of the other. Read-read overlap is not a
conflict. The schedule is the priority rule of 5.4 applied to cells:
1. draw a random priority per cell (the permutation);
2. in each round, run every remaining cell with no remaining conflicting cell of smaller
   priority;
3. repeat until no cell remains.

Every cell sees the field it would see in the sequential order, so the result equals the
sequential result for the same permutation, path by path. The site sets come from the
owner-sorted site index (section 4). On the host the rounds are threaded LP solves.
Preconditions:
- site sets, retirements and divisions do not change during the pass;
- per-cell draws are keyed by cell, not by position in the permutation;
- each LP is cold-started or warm-started from its own cell's previous solution, never from
  a per-thread state, which would make the result depend on the schedule.

O(number of cells) rounds is the worst case. On a conflict graph of bounded degree with
random priorities the count should grow slowly; this is checked before any number is quoted,
and tier 2 reports the round count.

**Zajac contact cost.** The spec's working inference (12 spec, P-Z9) averages r sin θ over
the links of each cell pair. Because of the absolute value in r sin θ, that average must
be recomputed link by link when a cell's axis turns. The default exact ΔH therefore costs
O(boundary links of the two cells), which needs a boundary list kept on every copy or a
whole-cell traversal. An alternative takes r sin θ at the mean contact point of each pair.
Per-pair link counts and summed positions then give O(1) per pair, and the ΔH costs
O(contact neighbors of the two cells). That alternative changes the model, so it is used
only if the authors confirm it (question Q-Z6). Both costs are exact. The builder defines
the axis of a near-isotropic cell and checks the Float32 conditioning of the eigenvectors
(D-065 Q10).

## 7. Kinetic checks in tiers

| Tier | Check | Cost | When |
|---|---|---|---|
| 0 | per-copy exactness on both algorithms: brute-force ΔH at commit on `SequentialCPM` and on inline checkerboard phases, trackers equal recounts, conservation. Order invariance (below) is the negative control of `:exact`. One threaded run with many blocks and one device run | seconds | every gate |
| 1 | the exact finite-time oracle extended to each new copy-time term, for both algorithms, on a tiny lattice; it follows the random key order of conflicting items | seconds to minutes | every gate |
| 2 | the kinetics harness on a minimal case per mechanism (the smallest lattice where the term matters), at the region the model uses; seeds start at 8 and are added until the positive control resolves (half-width at most half the margin), up to a cap; the margins below | about 1 core-hour per mechanism | once per parallel policy, when it lands, with an A/B |
| 3 | full-model kinetics | full-run cost | only for checkerboard claims in the paper |

- **Tier 0 order invariance.** A test hook runs the items of each round (or the cleared items
  of each phase) inline on the CPU in block order, in reverse, and in K random orders. The
  states and the ΔH sums must be identical; `:exact` makes them so, because draws are keyed
  by block. The fixture lays a chain or a contact pair across a block seam, so two items read
  each other's cells. With the read sets disabled the states differ deterministically. A
  threaded race test alone can pass by luck, because conflicting neighbors mostly sit in one
  thread's slab.
- **Tier 0 classification.** A host brute-force computation of W, R and the per-round
  selection must equal the kernel's, exactly, on the CPU and on a device.
- **Tier 1.** The oracle models the random order of conflicting items, which is cheap on
  tiny lattices (a few blocks give a few permutations). It then tests the order law. It is
  weak for terms over several cells: angle terms need at least 3 cells, the state space is
  (cells + 1)^sites, and moments of 2- and 3-site cells are degenerate. Tier 0 and tier 2
  carry those terms.
- **Tier 2 margins.** A 5 % margin on a whole observable can hide half of a term's effect
  when the term moves the observable by 10 %. So each mechanism also measures the term's own
  effect: `SequentialCPM` with and without the term. The parallel form passes only if
  |parallel − sequential| ≤ 20 % of that effect, as well as the margins of
  `checkerboard-kinetics.md` §4. A negative control with a known bias (the term read many
  phases stale) must fail.
- Tiny lattices cannot show cell-scale effects, such as a Zajac axis turning over a large
  cell. Tier 2 covers those.
- The oracle re-derives every term from its specification and does not call production code
  except `solve`. Each new term therefore needs an independent oracle implementation.

## 8. Scope of "exact"

- Only `SequentialCPM` and `CheckerboardCPM(reads = :exact)` are called exact.
  `:exact` is called exact in docs and in the paper only after its tier 2 passes on a minimal
  case.
- The scope is every model run under `:exact`, with or without extra read sets, apart from
  the copy-level connectivity deferrals (5.4). "Exact" means every committed ΔH is exact and
  the phase equals a sequential run of its items in a pseudo-random order; the checkerboard
  kinetics still differ from `SequentialCPM` and are measured by tier 2.
- `:exact` makes device runs exact also for cells wider than the spacing. Under `:snapshot`
  and `:live` the base lockless device path stays inexact for such cells (D-271), for every
  model.
- The D-330 drive reads on `CheckerboardCPM` are live and unprotected today on both backends.
  Under this design they are read sets (references) and follow the chosen policy.

## 9. Build order

1. The one lifecycle planner (section 3). Layouts and analysis helpers alongside.
2. Lags and small folds, when a model needs them.
3. The 14c chemotaxis variant.
4. The one-path read layer: running sums, read sets, the accessor, the three policies, the
   per-pair contact store. D-329's refusal is lifted when it lands.

## 10. Open questions

- **Q1.** May the device check `@terminate` every k MCS (a stated keyword), or must the
  stop be exact to the MCS? Exact means one read-back per MCS on a device.
- **Q2.** Is FBA on the host acceptable for device FBCA runs (one read and one write per
  MCS)?
- **Q3.** The device default read policy follows a measurement of rounds, launch cost,
  read-back syncs and tier 2. (Settled: the CPU default is `:exact`; the `:live` retry cap
  behavior is in 5.6.)

Settled by the user on 2026-11-22 (section 3):
- **P1.** The event precedence table, with bounded resolution of retirement chains and
  cycles.
- **P2.** What a collective and its target are, with target updates in cell order.
- **P3.** A staged planner form that always launches, with no host fallback.

Settled when the model is built, from its paper:
- **Q4.** Do Jafari Nivlouei's neighbor loops run at copy time (read sets over contact
  neighbors) or between sweeps (no read sets; the gap audit G6 suggests lagged coefficients
  for an ODE)?
- **Q5.** Hastings acceptance with `skip_interior`: the boundary-site count is global, and on
  the checkerboard only a per-sub-region count is local. How the model that needs it
  normalizes.
