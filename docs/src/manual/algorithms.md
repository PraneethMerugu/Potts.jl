# [Choosing an algorithm](@id manual-algorithms)

`solve(prob, alg)` takes one of three sweep algorithms. All three sample the same model:
the same energy, constraints, acceptance law and proposal neighbourhood. They differ in
the order in which copy attempts are made, in where they run, and in what that order does
to the kinetics.

| Algorithm | Backends | Dynamics | Use it for |
|---|---|---|---|
| `SequentialCPM()` | CPU | one copy attempt at a time, each at a uniformly drawn site: the classic CPM | the reference dynamics, against which the reproductions are defined |
| `BoundarySiteCPM()` | CPU | `SequentialCPM`'s dynamics, drawing only boundary sites; equal in distribution to `SequentialCPM` | the same runs, faster, when most of the lattice is medium or cell interior |
| `CheckerboardCPM()` | CPU and GPU | all sites of one colour of a checkerboard at once | GPUs and large lattices; its kinetics differ from `SequentialCPM`'s |

All three take `acceptance` and `proposal` keywords, which default to the model's
acceptance law and the problem's proposal neighbourhood (see [Problems, solvers and
solutions](@ref manual-problems)).

## `BoundarySiteCPM`

### What it does

`SequentialCPM` makes `N` copy attempts per MCS, where `N` is the number of mobile sites.
Each attempt picks a target site uniformly and one of its proposal neighbours. When every
proposal neighbour of the picked site belongs to the same owner as the site (the inside of
a cell, or open medium), the attempt can only copy that owner onto itself: a null move,
which changes nothing. On a lattice that is mostly medium, almost every attempt is null.

`BoundarySiteCPM` keeps the set of **boundary sites**: mobile sites with at least one
mobile proposal neighbour of another owner (frozen and off-lattice neighbours do not count).
It draws only from that set. The interior picks it does not make are accounted exactly:
between two boundary picks, the number of skipped picks is drawn at once from its exact
law, a geometric run length in the boundary fraction ``|B|/N``. So

- an MCS is still `N` attempts over all mobile sites, and `sol.stats.attempts` reports `N`
  per MCS, as under `SequentialCPM`;
- a run of skipped picks never crosses the end of an MCS, so the state after every MCS
  has the same law as under `SequentialCPM`, and **MCS time means the same thing**: drives,
  equations, `@after_mcs` updates and lifecycle rules see the same clock.

The boundary set is updated incrementally after each copy, division and removal, and
rebuilt after lifecycle events, `reinit!`, `u_modified!` and a checkpoint restore.

### Equal in distribution, not bitwise

The sequence of non-null attempts has the same law as `SequentialCPM`'s, but it is drawn
from a different random stream: `SequentialCPM` spends one draw on each null pick, and
`BoundarySiteCPM` does not make those draws. With the same `seed`, the two algorithms give
different trajectories with the same statistics. Each algorithm is still deterministic on
its own: the same problem, seed and algorithm give the same run (D-158). Continuing from a
checkpoint is equal in law to an uninterrupted run, not bitwise identical (D-177).

### When to use it

Use it wherever you would use `SequentialCPM` and much of the lattice is medium or cell
interior: a colony growing from one cell, such as the OpenVT monolayer, a few cells
migrating on a large lattice, or a dilute aggregate. The fewer boundary sites, the larger
the speed-up. A frozen reproduction defined on `SequentialCPM` can switch to it without
changing its targets, since the two are equal in law; the OpenVT threshold sweeps did so
before their full run (D-174).

### Limits

- **CPU only.** `solve` or `init` with a non-CPU `backend` raises an `ArgumentError`; use
  `CheckerboardCPM` on a GPU.
- **One O(N) pass per MCS.** At the start of each MCS the state and the frozen mask are
  compared with a shadow copy, to catch writes made outside the sweep. On a nearly empty
  lattice this pass is a visible part of the cost: about 0.25 ms per MCS on 1400² (Mac, Apple
  Silicon, CPU; measured in the P6.4b1 review).
- **Not a change to `CheckerboardCPM`.** `CheckerboardCPM` updates sites in parallel by
  colour, which is a different dynamics. Whether its kinetics are statistically equivalent
  to `SequentialCPM`'s is open (ROADMAP P6.0bl): on the Merks models they differ
  measurably (eight seeds at 400 MCS: compactness of the 2008 sprout 0.821 sequential
  against 0.869 checkerboard). `BoundarySiteCPM` is equivalent to `SequentialCPM` by
  construction, so it does not share that question.
- General proposal laws with a Hastings correction, and a GPU form, are later work
  (ROADMAP P6.4b).

### Example

A few cells on a mostly-medium lattice, run under both algorithms. The attempt counts
agree exactly; the accepted counts are random, with the same expected value.

```@example boundary
using Potts

@potts_model Dilute begin
    @kinds medium cell
    @lattice Lattice((60, 60); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @sweep Metropolis(; temperature = 8.0)
end
@named dilute = Dilute()
op = layout(Tiling((5, 5); region = (21:40, 21:40), spacing = 5, kinds = [:cell]), dilute)
prob = PottsProblem(dilute, op, (0, 20); seed = 1)

seq = solve(prob, SequentialCPM())
bnd = solve(prob, BoundarySiteCPM())
(; sequential = (seq.stats.attempts, seq.stats.accepted),
   boundary = (bnd.stats.attempts, bnd.stats.accepted))
```

### Measured evidence

The acceptance test is `lib/PottsModels/test/acceptance/p6_4b1_boundary_site.jl` (frozen,
D-177). It passes at both tiers (SMOKE: 369 checks; FULL on the PC: 106 checks, every
``|z| \le 2.4``). Each check is held to a false-failure probability of at most 10⁻³ and
has a negative control.

- **Exact law.** On a 2 × 4 lattice with two cells (6050 states), an independent oracle
  computes `SequentialCPM`'s exact stationary law and its exact laws after one and two
  MCS. `BoundarySiteCPM`'s states follow all three (χ² z-scores below 3.72), with
  `SequentialCPM` as the positive control of the oracle.
- **Time equivalence.** On 60² with four cells (2.8 % cover), accepted copies in MCS 1
  (mean and variance), accepted copies over MCS 1–10 and the mean squared centroid
  displacement over 10 MCS agree with `SequentialCPM` (Welch tests, 2000 runs each).
- **Growth curves.** On the OpenVT reference model, the growth curves log₂ N against time
  agree with `SequentialCPM`'s (SMOKE: an exact permutation test, p ≥ 10⁻³; FULL:
  ``|z| \le 3.89``).
- **Boundary set.** It equals a from-scratch recompute after every step, division,
  removal, `reinit!` and direct state write.
- **`SequentialCPM` unchanged.** Two bitwise records of `SequentialCPM` runs still match,
  and its performance A/B passes (worst candidate/base 1.010 against a margin of 1.032).

Speed-ups over `SequentialCPM` (D-177):

| Case | Speed-up | Machine and backend |
|---|---|---|
| 400², 169 cells of 7 × 7 (5 % cover) | 4.40× | PC (AMD Ryzen AI Max+ 395), CPU, single thread, pinned |
| OpenVT case (a), 1400², one cell to 10⁴ cells | 2.83× (178 s against 504 s) | PC (AMD Ryzen AI Max+ 395), CPU, one run each |

The docstring: [`BoundarySiteCPM`](@ref).
