# [Integrate adapters and solvers](@id adapters-and-solvers)

> **Support level:** qualified SciML extension and managed-field internal beta.

**Outcome.** Give a real SciML solver numerical ownership while
ProcessBigraphs retains schedule, authorization, validation, and publication.

**Prerequisites.** [Write processes, steps, and observers](@ref write-components).

## Complete executed source

```@example adapters-and-solvers
using ProcessBigraphs
using OrdinaryDiffEqTsit5: Tsit5

scale = TimeScale(1, 10, :second)
initial = zeros(Float64, 6, 6)
initial[3:4, 3:4] .= 1

field_problem = BoundedCartesianFieldProblem(
    "tutorial-field",
    initial;
    diffusion=0.05,
    decay=0.01,
    tick_duration=0.1,
    time_scale=scale,
)
declaration = sciml_field_declaration(
    field_problem,
    Tsit5();
    algorithm_id="ordinarydiffeq-tsit5",
    solver_options=(abstol=1.0e-8, reltol=1.0e-8),
)
field_process = managed_field_process(
    declaration;
    resource_authorization=(
        backend=:cpu,
        precision=:float64,
        residency=:host,
    ),
    subcycles_per_mcs=2,
)

model = compose(:SolverBoundary; scale, profile=:reproducible) do system
    field = store!(
        system, :field,
        LeafSchema(
            Float64;
            shape=size(initial),
            default=initial,
            update_law=:replace,
        ),
    )
    forcing = store!(
        system, :forcing,
        LeafSchema(
            Float64;
            shape=size(initial),
            default=zeros(size(initial)),
            update_law=:replace,
        ),
    )
    decay_weights = store!(
        system, :decay_weights,
        LeafSchema(
            Float64;
            shape=size(initial),
            default=ones(size(initial)),
            update_law=:replace,
        ),
    )
    published = store!(
        system, :published,
        LeafSchema(
            Float64;
            shape=size(initial),
            default=initial,
            update_law=:replace,
        ),
    )
    engine = mount!(system, :field_engine, field_process)
    attach!(system, engine, (
        field=field,
        forcing=forcing,
        decay_weights=decay_weights,
        field_out=field,
        mcs_field=published,
    ))
    schedule!(system, engine, Every(Duration(1, scale)))
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(2, scale))
field = current_snapshot(runtime)[path("field")]

result = (
    mass=sum(field),
    minimum=minimum(field),
    commits=event_count(runtime),
    declaration=declaration.fingerprint,
)
@assert result.minimum >= 0
@assert result.commits == 2
```

The selected `Tsit5()` algorithm, tolerances, resources, and publication
cadence are visible at the call site. The solver owns integration and its
private workspace. ProcessBigraphs owns invocation order and commits only a
validated candidate. `mcs_field` publishes only on the configured two-subcycle
boundary.

**Material defaults.** 6×6 periodic field, diffusion 0.05, decay 0.01,
0.1-second ticks, Tsit5, `abstol = reltol = 1e-8`, two subcycles.

**Expected result.** Two commits, finite nonnegative field, stable declaration
fingerprint.

**Establishes.** A real pinned SciML handoff on CPU/Float64/host.

**Does not establish.** It does not claim method independence, physical
calibration, GPU support, or equality to another adapter.

**Backend / runtime / seed.** CPU, Float64, host residency; deterministic field
solve; no stochastic seed.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/adapters_and_solvers.jl`

**Next step.** [Change structure transactionally](@ref dynamic-structure).
