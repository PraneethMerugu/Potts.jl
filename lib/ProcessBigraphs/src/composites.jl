struct StaticComposite
    schema::AbstractSchema
    initial_values::Any
    scale::TimeScale
    processes::Tuple{Vararg{ProcessDeclaration}}
    steps::Tuple{Vararg{StepDeclaration}}
    bindings::Tuple{Vararg{PortBinding}}
end

function StaticComposite(
    schema::AbstractSchema,
    initial_values,
    scale::TimeScale;
    processes=(),
    steps=(),
    bindings=(),
)
    StaticComposite(schema, deepcopy(initial_values), scale,
        tuple(processes...), tuple(steps...), tuple(bindings...))
end

struct CompiledComposite
    epoch::StructuralEpoch
    plan::ExecutionPlan
    initial::CommittedSnapshot
    preflight_report::PreflightReport
    fingerprint::String
end

model_fingerprint(composite::CompiledComposite) = composite.fingerprint
step_layers(composite::CompiledComposite) = composite.plan.layers
structural_epoch(composite::CompiledComposite) = deepcopy(composite.epoch)
structural_provenance(composite::CompiledComposite) = composite.epoch.provenance
structural_fingerprint(composite::CompiledComposite) = composite.epoch.fingerprint
canonical_structure(composite::CompiledComposite) = deepcopy(composite.epoch.structure)

_leaf_type(::LeafSchema{T,N}) where {T,N} = N == 0 ? T : AbstractArray{T,N}
_leaf_element_type(::LeafSchema{T}) where {T} = T
_port_matches(::PortSpec{P}, ::LeafSchema{T,0}) where {P,T} = P == T
_port_matches(::PortSpec{P}, ::LeafSchema{T,N}) where {P,T,N} =
    P <: AbstractArray{T,N}

function _owners(composite::StaticComposite)
    tuple(composite.processes..., composite.steps...)
end

function _validate_identities(composite::StaticComposite)
    ids = [declaration.id for declaration in _owners(composite)]
    length(ids) == length(unique(ids)) ||
        _fail(:duplicate_declaration_identity, "process and step identities must be unique")
    Set(ids)
end

function _port_map(declaration)
    declared = ports(declaration.law)
    all(port -> port isa PortSpec, declared) ||
        _fail(:invalid_port_declaration, "ports() must return only PortSpec values";
            owner=declaration.id)
    names = [port.name for port in declared]
    length(names) == length(unique(names)) ||
        _fail(:duplicate_port_name, "one declaration contains duplicate port names";
            owner=declaration.id)
    Dict(port.name => port for port in declared)
end

function _validate_bindings(composite::StaticComposite, layers::Tuple)
    declarations = Dict(declaration.id => declaration for declaration in _owners(composite))
    concurrency_group = Dict{String,Any}(
        process.id => (:process_batch,) for process in composite.processes)
    for (layer_index, layer) in enumerate(layers), id in layer
        concurrency_group[id] = (:step_layer, layer_index)
    end
    binding_keys = [(binding.owner, binding.port) for binding in composite.bindings]
    length(binding_keys) == length(unique(binding_keys)) ||
        _fail(:duplicate_port_binding, "a port is bound more than once")
    outputs = Dict{Path,Vector{Tuple{String,PortSpec}}}()

    for binding in composite.bindings
        haskey(declarations, binding.owner) ||
            _fail(:unknown_binding_owner, "binding references an unknown declaration";
                owner=binding.owner)
        portmap = _port_map(declarations[binding.owner])
        haskey(portmap, binding.port) ||
            _fail(:unknown_bound_port, "binding references an unknown port";
                owner=binding.owner, port=binding.port)
        port = portmap[binding.port]
        leaf = schema_at(composite.schema, binding.target)
        leaf isa LeafSchema ||
            _fail(:port_targets_branch, "ports must bind to leaf state"; target=binding.target)
        _port_matches(port, leaf) ||
            _fail(:port_schema_mismatch, "port type does not match leaf value type";
                owner=binding.owner, port=binding.port,
                expected=string(_leaf_type(leaf)),
                actual=string(typeof(port).parameters[1]))
        if port.direction === :output
            port.update_law == leaf.update_law ||
                _fail(:port_update_law_mismatch,
                    "output port law must match the leaf publication law";
                    owner=binding.owner, port=binding.port,
                    expected=leaf.update_law, actual=port.update_law)
            push!(get!(outputs, binding.target, Tuple{String,PortSpec}[]),
                (binding.owner, port))
        end
    end

    bound = Set(binding_keys)
    for declaration in values(declarations), port in values(_port_map(declaration))
        (declaration.id, port.name) in bound || port.optional ||
            _fail(:unbound_required_port, "required port has no binding";
                owner=declaration.id, port=port.name)
    end

    for (target, writers) in outputs
        length(writers) <= 1 && continue
        leaf = schema_at(composite.schema, target)
        leaf.update_law === :replace || continue
        grouped = Dict{Any,Vector{String}}()
        for (owner, _) in writers
            push!(get!(grouped, concurrency_group[owner], String[]), owner)
        end
        for (group, owners) in grouped
            length(owners) <= 1 && continue
            _fail(:static_replace_conflict,
                "replace-law state has multiple writers in one publication layer";
                target, group, writers=Tuple(sort!(owners)))
        end
    end
    nothing
end

function _step_layers(composite::StaticComposite, ids::Set{String})
    step_ids = Set(step.id for step in composite.steps)
    for step in composite.steps, dependency in step.dependencies
        dependency in step_ids ||
            _fail(:unknown_step_dependency, "step dependency is not a declared step";
                step=step.id, dependency)
        dependency == step.id &&
            _fail(:step_cycle, "a step cannot depend on itself"; step=step.id)
    end
    remaining = Dict(step.id => Set(step.dependencies) for step in composite.steps)
    layers = Tuple[]
    completed = Set{String}()
    while !isempty(remaining)
        ready = sort!([id for (id, dependencies) in remaining
            if dependencies <= completed])
        isempty(ready) &&
            _fail(:step_cycle, "step dependency graph contains a cycle";
                remaining=sort!(collect(keys(remaining))))
        push!(layers, tuple(ready...))
        union!(completed, ready)
        foreach(id -> delete!(remaining, id), ready)
    end
    tuple(layers...)
end

function preflight(composite::StaticComposite)
    transfers = Pair{Tuple{String,Symbol},TransferDeclaration}[]
    domains = Pair{String,Symbol}[]
    declarations = Dict(declaration.id => declaration for declaration in _owners(composite))
    for declaration in _owners(composite)
        push!(domains, declaration.id => declaration.domain)
    end
    for binding in composite.bindings
        declaration = declarations[binding.owner]
        port = _port_map(declaration)[binding.port]
        leaf = schema_at(composite.schema, binding.target)
        required = port.residency === :inherit ? declaration.domain : port.residency
        present = leaf.residency === :agnostic ? required : leaf.residency
        if present != required
            transfer = binding.transfer
            isnothing(transfer) &&
                _fail(:hidden_transfer, "cross-residency port requires an explicit transfer";
                    owner=binding.owner, port=binding.port, target=binding.target,
                    source=present, destination=required)
            transfer.source == present && transfer.destination == required ||
                _fail(:transfer_endpoint_mismatch,
                    "declared transfer does not match state and process residency";
                    owner=binding.owner, port=binding.port)
            if all(dimension -> dimension isa Int, leaf.shape) &&
                    isbitstype(_leaf_element_type(leaf))
                minimum_bytes = sizeof(_leaf_element_type(leaf)) *
                    (isempty(leaf.shape) ? 1 : prod(Int.(leaf.shape)))
                transfer.max_bytes >= minimum_bytes ||
                    _fail(:transfer_bound_too_small,
                        "declared transfer bound cannot contain the static leaf";
                        owner=binding.owner, port=binding.port,
                        declared=transfer.max_bytes, minimum=minimum_bytes)
            end
            push!(transfers, (binding.owner, binding.port) => transfer)
        elseif !isnothing(binding.transfer)
            _fail(:redundant_transfer, "same-residency binding cannot declare a transfer";
                owner=binding.owner, port=binding.port)
        end
    end
    sort!(domains; by=first)
    sort!(transfers; by=pair -> first(pair))
    identity = canonical_fingerprint((
        :preflight_v1,
        tuple(domains...),
        tuple(transfers...),
    ))
    PreflightReport(tuple(domains...), tuple(transfers...), identity)
end
