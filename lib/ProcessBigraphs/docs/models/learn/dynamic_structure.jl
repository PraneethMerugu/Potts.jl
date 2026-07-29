using ProcessBigraphs

scale = TimeScale(1)
cell = compose(:CellDefinition; scale) do child
    state = store!(
        child, :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    expose!(child, :state, state; role=:bidirectional)
end

host = compose(:DynamicHost; scale, profile=:reproducible) do system
    shared = store!(
        system, :shared,
        LeafSchema(Int; default=0, update_law=:add),
    )
    allow_instances!(system, :cells, cell; capacity=8)
    observable!(system, :shared, shared)
end

report = validate(host)
plan = compile(host)
result = (
    valid=isempty(report.diagnostics),
    model=semantic_fingerprint(host),
    structure=structural_fingerprint(plan),
    template_policy=(name=:cells, capacity=8),
)
@assert result.valid
