# [Problems, solvers and solutions](@id manual-problems)

## `PottsProblem`

`PottsProblem(sys, op, (t0, t1); kwargs...)` compiles the model `sys` and builds the initial
state from the operating point `op`. Times are in MCS.

The operating point is a vector of pairs:

| Key | Value |
|---|---|
| `ownership` | integer array over the lattice: the cell number of each site (0 = medium) |
| `kind` | kind of each cell, by name (`:dark`) or number |
| `cluster` | compartment group of each cell (optional) |
| a variable, `:x` | initial value: a number, an array over the lattice (site, field), a vector over cells (cell) |
| a parameter, `:λ` | a value replacing the default |
| a relationship, `:bond` | initial links, `[(1, 2), …]` |

| Keyword | Meaning |
|---|---|
| `seed`, `replica`, `repeat` | the random stream (`seed` for a study, `replica` per ensemble trajectory) |
| `T` | number type of the state and code: `Float64` (default) or `Float32` (GPUs) |
| `capacity` | cell slots reserved for divisions |
| `field_solver`, `ode_solver`, `solvers` | integrators, see [Equations and solvers](@ref manual-equations) |

## Algorithms

| Algorithm | Where | Updates |
|---|---|---|
| `SequentialCPM(; proposal)` | CPU | one copy attempt at a time: the classic model |
| `BoundarySiteCPM(; proposal)` | CPU | `SequentialCPM`'s dynamics, drawing only sites at a cell boundary and skipping the others' null attempts exactly: equal in distribution, faster on mostly-medium lattices |
| `CheckerboardCPM(; proposal)` | CPU and GPU | all sites of one colour of a checkerboard at once |

`proposal` overrides the model's proposal neighbourhood for this solve.

Which one to use, and what `BoundarySiteCPM` does exactly, is on [Choosing an algorithm](@ref manual-algorithms).

## `solve`, `init` and the integrator

```@example problems
using Potts

@potts_model Simple begin
    @kinds medium cell
    @parameters T = 8.0
    @variables age(cell) = 0.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @after_mcs age += 1
    @sweep Metropolis(; temperature = T)
end
@named simple = Simple()
op = layout(Tiling((5, 5); region = (6:25, 6:25), spacing = 1, kinds = [:cell]), simple)
prob = PottsProblem(simple, op, (0, 100); seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 25)
```

`solve` keywords: `saveat` (a number: every so many MCS; or a list of times),
`save_start`, `save_end`, `callback`, and `backend` (GPU). The solution holds `sol.t`,
`sol.u` (the saved states), `sol.retcode`, `sol.stats` and `sol.prob`. `sol[i]` is the
`i`-th saved state, and `sol(t)` the state saved at MCS `t`:

```@example problems
sol(50) === sol.u[3]
```

`init` returns an **integrator** that you advance yourself, as in SciML:

```@example problems
integ = init(prob, SequentialCPM())
step!(integ)                    # one MCS
integ.t, integ[:age][1]
```

```@example problems
integ.ps[:T] = 2.0              # takes effect from the next MCS
integ[:age] = 0.0               # write state
sol2 = solve!(integ)            # run to the end
sol2.t
```

`integ.u` is a copy of the current state.

## A saved state

A state holds plain arrays: `u.σ` (cell numbers), `u.cell` (per-cell arrays: `kind`,
`volume`, declared cell variables, …), `u.site` (site and field variables, as arrays over
the lattice) and `u.model`. Prefer `sol[:name]` (see [Symbolic indexing](@ref
manual-indexing)), which works for every quantity, derived ones included.

## Checkpoints

A checkpoint saves an integrator, so a long run can be stopped and resumed exactly:

```@example problems
integ = init(prob, SequentialCPM())
foreach(_ -> step!(integ), 1:40)
ck = checkpoint(integ)
path = tempname() * ".jls"
save_checkpoint(path, ck)
resumed = init(prob, SequentialCPM(); checkpoint = load_checkpoint(path))
resumed.t
```

The resumed run continues with the same random stream, so it equals the uninterrupted run.
A checkpoint loads only into a problem built from the same model and solvers, with the same
schedule, acceptance law and neighbourhoods: the cadences of clocked components, `Every(n)`
rules, `mcs_duration`, the `@sweep` law (`Metropolis` or `Barker`) and its `offset`, and the
`@relations proposal` and `@relations contact` neighbourhoods (resolved on the lattice) are part
of the check. A neighbourhood that resolves to its default (`VonNeumann(1)` for the proposal,
the lattice's `neighborhood` for contact) checks like omitting it. Named relations
(`@relations far = Ball(2.0)`, read by `contacts(far)` or a fold `for n in far(site)`) and
inline relations (`Moore(1)(42)`) are part of the check too, each resolved on the lattice:
specs that resolve to the same offsets and weights (`Ball(1.5)` and `Moore(1)` on a square
lattice) check alike, and a relation nothing reads, or one read only by `@observed`
quantities, is not checked. The algorithm's `proposal` keyword (`SequentialCPM(; proposal)`)
is a run choice and is not checked.

A solver holding an anonymous function or closure, such as
`Adaptive(Rodas5P(); isoutofdomain = (u, p, t) -> any(<(0), u))`, has no name that survives
the Julia session, so its checkpoints are session-bound: they load in the session that
made them and are refused (an `ArgumentError`) in any other, even one running the same
script. To resume such a run in a new session, pass a named function defined at the top
level (`nonnegative(u, p, t) = any(<(0), u)`, then `isoutofdomain = nonnegative`) or an
instance of a callable struct.

## Changing a problem: `remake`

`remake(prob; p, u0, tspan, seed, replica)` returns a new problem without regenerating code;
`remake(prob; field_solver, ode_solver, solvers)` regenerates it. See
[Tutorial 7](@ref tutorial-scans) for scans and ensembles.
