# [SciML field adapter](@id sciml-field-adapter-example)

> **Support level:** qualified SciML extension on CPU/Float64/host.

**Outcome.** Advance a constant reaction-diffusion field with a real Tsit5
solver and compare the bounded result with its analytic decay.

**Prerequisites.** [Integrate adapters and solvers](@ref adapters-and-solvers).

## Complete executed source

```@example sciml-field-adapter
using ProcessBigraphs
using OrdinaryDiffEqTsit5: Tsit5

scale = TimeScale(1, 20, :second)
initial = fill(2.0, 5, 5)
field_problem = BoundedCartesianFieldProblem(
    "decaying-constant-field",
    initial;
    diffusion=0.1,
    decay=0.2,
    tick_duration=0.05,
    time_scale=scale,
)
declaration = sciml_field_declaration(
    field_problem,
    Tsit5();
    algorithm_id="ordinarydiffeq-tsit5",
    solver_options=(abstol=1.0e-10, reltol=1.0e-10),
)
process = managed_field_process(
    declaration;
    resource_authorization=(
        backend=:cpu,
        precision=:float64,
        residency=:host,
    ),
)

model = compose(:DecayingField; scale) do system
    field = store!(system, :field, LeafSchema(
        Float64; shape=size(initial), default=initial, update_law=:replace))
    forcing = store!(system, :forcing, LeafSchema(
        Float64; shape=size(initial), default=zeros(size(initial)),
        update_law=:replace))
    weights = store!(system, :weights, LeafSchema(
        Float64; shape=size(initial), default=ones(size(initial)),
        update_law=:replace))
    published = store!(system, :published, LeafSchema(
        Float64; shape=size(initial), default=initial, update_law=:replace))
    solver = mount!(system, :solver, process)
    attach!(system, solver, (
        field=field,
        forcing=forcing,
        decay_weights=weights,
        field_out=field,
        mcs_field=published,
    ))
    schedule!(system, solver, Every(Duration(1, scale)))
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(4, scale))
field = current_snapshot(runtime)[path("field")]
expected = 2exp(-0.2 * 0.2)
result = (
    observed=field[1, 1],
    expected,
    maximum_error=maximum(abs.(field .- expected)),
)
@assert result.maximum_error < 1.0e-8
```

![A smooth curve in the SciML field panel shows the spatially constant field decaying over time.](../assets/example-results.svg)

Diffusion contributes zero for a spatially constant periodic field, leaving an
analytic exponential decay. This gives the numerical handoff a meaningful,
independently computed check.

**Material defaults.** 5×5 field at 2.0, diffusion 0.1, decay 0.2, four
0.05-second ticks, Tsit5 with `1e-10` tolerances.

**Expected result.** Maximum error below `1e-8`.

**Establishes.** Real solver handoff and candidate publication for this bounded
analytic case.

**Does not establish.** General PDE convergence, other algorithms, or other
backends.

**Backend / runtime / seed.** CPU/Float64/host, deterministic, no seed.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/examples/sciml_field_adapter.jl`

**Next step.** [Implement an independent custom adapter](@ref custom-engine-adapter).
