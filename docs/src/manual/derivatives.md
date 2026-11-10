# [Derivatives with ForwardDiff](@id manual-derivatives)

```julia
using Potts, ForwardDiff

# ∂(total chemical)/∂k of a run, at a fixed seed
f(k) = sum(solve(PottsProblem(sys, [op; :k => k], (0, 100); seed = 1), SequentialCPM()).u[end].site.c)
ForwardDiff.derivative(f, 0.1)

# or seed by hand: a Dual in the operating point or in `remake`
prob = remake(PottsProblem(sys, op, (0, 100)); p = [:k => ForwardDiff.Dual(0.1, 1.0)])
sol = solve(prob, SequentialCPM())
ForwardDiff.partials.(sol.u[end].site.c, 1)      # ∂c/∂k at every site
```

## What is differentiated

The derivative is pathwise, at the run's CPM path. The seed fixes every copy attempt and every
draw. The derivative holds that path fixed: σ, the cells, cell and model variables and their
ODEs. It differentiates only the fields' response to the parameters along the path.

- The CPM runs on the primal values. A Dual run's σ and field values equal the primal run's, bit
  for bit.
- The CPM's response to a parameter is not in the derivative. With chemotaxis, or any field read
  in the energy, the cells would move differently at another parameter value. That response is
  missing, so the derivative is not the derivative of the expected outcome.
- A parameter that only the CPM or an ODE reads has derivative 0, and a warning says so. The
  acceptance of a copy is piecewise constant in it: use likelihood-free inference for it.
- An implicit field solver gives the derivative of each converged stage. For a nonlinear term,
  give `newton = k` (k ≥ 2), so that the run converges too; a warning names the case.
- Central differences of the run agree with it at the same seed, as long as the ± runs keep the
  same path. Check that `sol.u[i].σ` is equal across them.

## Seeding and reading

| Where | Seed | Read |
|---|---|---|
| a Potts model | a Dual for a parameter, or a Dual initial value of a field, in the operating point; `remake(prob; p = [k => Dual])` | `sol.u[i].site.c`, `integ[c]`, `integ.u` (Dual arrays) |
| a LatticePDE problem (`discretize`) | `remake(prob; p = [k => Dual])`, or a Dual `u0` | `sol.u[i]` (Dual arrays) |

- In a Potts model, the live state `integ.state` stays primal. Only the field arrays are Duals.
- A field whose initial value reads a seeded parameter (`c(0, x, y) ~ c0` in its `PDESystem`)
  carries `∂c₀/∂c0`.
- `integ[c] = v` sets the field's derivative parts from `v` (0 for plain values).
- `integ.ps[k] = v` mid-run is allowed. The written value is plain from then on, and the other
  parameters keep their derivative parts.
- One run takes one Dual type: use one `ForwardDiff` call per run (a `gradient` seeds all its
  parameters at once).

## Cost

A Dual run of a Potts model is the primal run plus the derivative parts of the fields:

- an explicit group: one Dual step per window (about 1.2 to 1.4 times the primal field cost);
- an implicit group: the primal solve once per stage, then one linear solve per derivative part
  with the converged operator. A 128² `BackwardEuler` run takes about 2.0 times the primal run's
  time per MCS with one derivative part and 3.8 times with three.

The CPM's cost does not change.

## Refused, with routes

| Input | Route |
|---|---|
| a Dual in a kind table | a scalar parameter in the direction of the derivative (Dual kind tables are a later feature) |
| a Dual initial value of a cell, model or site variable | the CPM's state is held fixed; finite differences |
| a seeded parameter inside a CPM read that the CPM fills whole (an `ifelse` of CPM reads) | move the parameter out of the branches |
| a model with no fields | finite differences |
| seeds of different Dual types | one `ForwardDiff` call per run |
| a Dual in an integrator write (`integ.ps[k] = Dual`) | `remake(prob; p = [k => Dual])` |
| a Dual in `remake(prob; u0 = …)` | give it to `PottsProblem` |
| `checkpoint` of a Dual run | run from the start, or checkpoint the primal run |
