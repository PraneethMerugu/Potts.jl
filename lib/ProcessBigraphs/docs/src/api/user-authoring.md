# [User authoring API](@id user-authoring-api)

> **Support level:** supported internal beta. These names form the ordinary
> ProcessBigraphs 0.6 authoring boundary. The package is not yet a public
> release, but changes to this boundary require an explicit migration.

ProcessBigraphs models are assembled with named stores, mounted processes,
explicit connections, and explicit schedules. A model definition is data:
`lower`, `validate`, and `compile` inspect the same immutable meaning that the
runtime executes.

```julia
model = compose(:PulseCounter) do system
    count = store!(system, :count, LeafSchema(Int; default=0))
    pulse = mount!(system, :pulse, Pulse(1))
    connect!(system, count, pulse.count, pulse.increment)
    schedule!(system, pulse, Every(1))
end

report = validate(model)
compiled = compile(model)
```

The example is intentionally explicit. ProcessBigraphs never guesses a
connection or schedule from matching names.

## Builders and inspection

```@docs
ProcessBigraphs.CompositeModel
ProcessBigraphs.SimulationProblem
ProcessBigraphs.compose
ProcessBigraphs.store!
ProcessBigraphs.mount!
ProcessBigraphs.connect!
ProcessBigraphs.attach!
ProcessBigraphs.expose!
ProcessBigraphs.schedule!
ProcessBigraphs.iteration!
ProcessBigraphs.parameter!
ProcessBigraphs.observable!
ProcessBigraphs.allow_instances!
ProcessBigraphs.lower
ProcessBigraphs.compile
ProcessBigraphs.validate
ProcessBigraphs.describe
ProcessBigraphs.diagram
ProcessBigraphs.explain
ProcessBigraphs.remake
ProcessBigraphs.parameter_names
ProcessBigraphs.with_parameters
```

## Scheduling

```@docs
ProcessBigraphs.Every
ProcessBigraphs.At
ProcessBigraphs.On
ProcessBigraphs.After
```

## Managed numerical fields

Use `managed_field_process` when ProcessBigraphs should own invocation and
publication timing while an adapter owns the numerical method and heavy
kernels. Authorization is deliberately required at construction time.

```@docs
ProcessBigraphs.managed_field_process
```

```julia
field_process = managed_field_process(
    declaration;
    resource_authorization=(
        backend=:cpu,
        precision=:float64,
        residency=:host,
    ),
    subcycles_per_mcs=15,
)
```

The concrete returned type is private. Mount and schedule the value through
the ordinary process API.
