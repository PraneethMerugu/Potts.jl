# [Build a custom model](@id custom-model)

Potts models can combine ordinary Julia scalar mathematics, bounded spatial
gathers, maintained tracker projections, lattice fields, cell state,
relationships, and lifecycle operations without defining a new runtime type.
The complete executable program below combines those extension paths in one
small model.

```@example custom_model
using Potts
include(joinpath(dirname(dirname(dirname(@__DIR__))), "examples", "custom_model.jl"))
result = CustomModel.run_custom_model()

(
    is_scheduled(result.problem.system),
    last(result.solution).mcs,
    last(result.uninterrupted).ownership == last(result.resumed).ownership,
    failure_report(result.solution),
)
```

`scaled_neighbor_signal` is an ordinary typed Julia function declared with
`LocalMath.@localmath function`; it runs normally on concrete values and traces
when Potts constructs the symbolic drive. The two `gather` expressions request
the declared contact relation at the proposal target. One reads a lattice
`FieldState`; the other reads CorePotts's maintained `cell_volume` tracker.
`Statistics.mean` lowers through LocalMath's checked bounded-fold law. It
preserves relation-lane order and repeated endpoints; missing boundary lanes
and medium endpoints do not participate.

The intentionally false proposal constraint keeps stochastic copy dynamics
fixed in this compact tutorial. That isolates the authored gather from the
lifecycle and continuation behavior shown below; the independent gathered-fold
tests provide the numerical oracle for the reduction itself.

`PottsProblem` accepts the authored system and performs structural compilation
immediately. The explicit `mtkcompile(system)` spelling remains useful when a
compiler or extension author wants to inspect scheduling before creating a
problem, but it is not an ordinary setup requirement.

At MCS 1 the relationship lifecycle operation retunes the stored edge. At MCS
2 one cell transitions kind, updates its per-cell activity, and removes the now
incompatible relationship under the declared policy.

Custom gathered operations are functionally qualified, but their external
executable identities do not yet carry CorePotts's stronger exact-replay
qualification. The example therefore executes the complete custom model, then
uses the same state, relationship, and lifecycle model without the custom drive
to demonstrate the checkpoint boundary. Restored continuation reaches the same
MCS, ownership, generations, tracker values, field and cell state, observation,
relationship endpoints, relationship generations, payload, and incidence as
uninterrupted execution.

`failure_report(solution)` returns `nothing` for the successful custom run. For
a failed trajectory it returns the exact retained scientific or provider
failure without synchronizing or reconstructing execution internals.
