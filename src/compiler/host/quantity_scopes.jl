# Quantity domains are owned by their declarations. Queries resolve those
# declarations in the frozen source; no separate scope table is retained.
function _scope_resource(records, owner, binding)
    binding isa Union{CellBinding, SiteBinding} && _scoped_anchor(binding) ||
        throw(ArgumentError("a quantity scope requires a bound cell or site anchor"))
    domain = binding.domain
    valid = binding isa CellBinding ? domain isa Cells : domain isa Sites
    valid || throw(ArgumentError("scope anchor and domain have incompatible kinds"))
    kind = domain isa Cells ? :CellKind : :LatticeDomain
    requested = _energy_domain_resource(domain)
    # Qualification resolved this reference against the complete context inventory,
    # including enclosing declarations absent from a reusable child's record slice.
    requested isa QualifiedStatementID && return requested
    resource = _resource_record(records, owner.identity.path, kind, requested)
    resource === nothing && throw(ArgumentError("scope for $(owner.identity) has no declared $kind"))
    return resource.identity
end

function _quantity_scope(records, record)
    owner = _state_sample_record(records, record)
    binding = get(_record_options(owner), :scope, nothing)
    binding === nothing && return nothing
    valid = owner.kind === :CellState ? binding isa CellBinding :
        owner.kind in (:SiteState, :FieldState) && binding isa SiteBinding
    valid || throw(ArgumentError("$(owner.identity) has an incompatible quantity scope"))
    return (;
        binding, kind = binding isa CellBinding ? :cell : :site,
        resource = _scope_resource(records, owner, binding),
    )
end

function _qualify_quantity_scopes(statement, path, inventory)
    statement isa Union{SynchronousProcess, CellState, SiteState, FieldState} || return statement
    options = _statement_options(statement)
    for name in (:scope, :anchor)
        binding = get(options, name, nothing)
        binding isa Union{CellBinding, SiteBinding} && _scoped_anchor(binding) || continue
        domain = binding.domain
        valid = binding isa CellBinding ? domain isa Cells : domain isa Sites
        valid || throw(ArgumentError("scope anchor and domain have incompatible kinds"))
        kind = domain isa Cells ? :CellKind : :LatticeDomain
        owner = _resource_record(inventory.statements, path, kind, _energy_domain_resource(domain))
        owner === nothing && throw(ArgumentError("scope for $path has no declared $kind"))
        resolved = _resource_identity(owner)
        qualified = binding isa CellBinding ? CellBinding(Cells(resolved), _binding_token(binding)) :
            SiteBinding(Sites(resolved), _binding_token(binding))
        options = merge(options, NamedTuple{(name,)}((qualified,)))
    end
    arguments = _statement_arguments(statement)
    if statement isa SynchronousProcess && arguments.domain isa Union{Cells, Sites}
        domain = arguments.domain
        kind = domain isa Cells ? :CellKind : :LatticeDomain
        owner = _resource_record(inventory.statements, path, kind, _energy_domain_resource(domain))
        if owner !== nothing
            resolved = _resource_identity(owner)
            domain = domain isa Cells ? Cells(resolved) : Sites(resolved)
            arguments = merge(arguments, (; domain))
        end
    end
    return _with_scope_payload(statement; arguments, options)
end

function _record_scope_bindings(record)
    options = _record_options(record)
    return (get(options, :scope, nothing), get(options, :anchor, nothing))
end

_scope_binding_matches(binding, value) = isequal(_binding_token(binding), value)
_scope_binding_matches(binding, payload::AnchorBindingPayload) =
    payload.name === _anchor_token_name(binding) &&
    payload.kind === (binding isa CellBinding ? :cell_anchor : :site_anchor)

function _resolved_scoped_anchor(source, value)
    found = nothing
    for owner in source.records, binding in _record_scope_bindings(owner)
        binding isa Union{SiteBinding, CellBinding} && _scoped_anchor(binding) || continue
        _scope_binding_matches(binding, value) || continue
        resource = _scope_resource(source.records, owner, binding)
        payload = AnchorBindingPayload(
            binding isa CellBinding ? :cell_anchor : :site_anchor,
            _anchor_token_name(binding), resource,
        )
        found === nothing || (found.kind === payload.kind && found.resource == payload.resource) ||
            throw(ArgumentError("one lexical scope name identifies conflicting domains; use distinct scope names"))
        found = payload
    end
    return found
end

function _synchronous_quantity_domain(records, record)
    arguments = _record_arguments(record)
    declared = nothing
    target_kind = nothing
    for effect in arguments.effects
        effect isa Assign || continue
        payload = _resolved_state_payload(records, effect.target)
        payload === nothing && continue
        owner = only(filter(candidate -> candidate.identity == payload.identity, records))
        kind = owner.kind === :CellState ? :cell : owner.kind === :ModelState ? :model :
            owner.kind in (:SiteState, :FieldState) ? :site : nothing
        kind === nothing && continue
        target_kind === nothing || target_kind === kind ||
            throw(ArgumentError("synchronous effects must share one iteration domain"))
        target_kind = kind
        scope = _quantity_scope(records, owner)
        scope === nothing && continue
        declared === nothing || declared.resource == scope.resource ||
            throw(ArgumentError("synchronous targets belong to different quantity populations"))
        declared = scope
    end
    explicit = arguments.domain
    if explicit !== nothing
        explicit_kind = explicit isa Cells ? :cell : explicit isa Sites ? :site : explicit isa ModelDomain ? :model : nothing
        if target_kind !== nothing && target_kind !== explicit_kind
            message = explicit_kind === :cell ? "synchronous cells(kind) domain requires CellState targets" :
                "explicit process domain disagrees with its target quantities"
            throw(ArgumentError(message))
        end
        kind = explicit isa Cells ? :CellKind : explicit isa Sites ? :LatticeDomain : nothing
        if kind === nothing
            declared === nothing || throw(ArgumentError("explicit process domain disagrees with its target quantities"))
            return target_kind === nothing ? nothing : (; binding = nothing, kind = target_kind, resource = nothing)
        end
        requested = _energy_domain_resource(explicit)
        resource = requested isa QualifiedStatementID ? requested : begin
                owner = _resource_record(records, record.identity.path, kind, requested)
                owner === nothing ? nothing : owner.identity
            end
        # Unscoped declarations retain the ordinary explicit process context.
        if declared === nothing
            return (; binding = nothing, kind = explicit isa Cells ? :cell : :site, resource)
        end
        resource !== nothing && resource == declared.resource ||
            throw(ArgumentError("explicit process domain disagrees with its target quantities"))
    end
    return declared !== nothing ? declared : target_kind === nothing ? nothing :
        (; binding = nothing, kind = target_kind, resource = nothing)
end

function _resolve_quantity_effect_bounds!(records)
    for index in eachindex(records)
        record = records[index]
        record.kind === :SynchronousProcess || continue
        domain = _synchronous_quantity_domain(records, record)
        (domain === nothing || domain.resource === nothing) && continue
        bound = EffectBound(length(_record_arguments(record).effects), domain.kind === :cell ? :per_cell : :per_site)
        records[index] = _with_statement_contracts(record; bound)
    end
    return records
end

function _validate_quantity_scopes(source, graph; enclosing_root)
    for record in source.records
        record.kind in (:CellState, :SiteState, :FieldState, :HistoryState) &&
            _quantity_scope(source.records, record)
        for binding in _record_scope_bindings(record)
            binding isa Union{SiteBinding, CellBinding} && _scoped_anchor(binding) || continue
            _resolved_scoped_anchor(source, _binding_token(binding))
        end
    end
    for (index, record) in enumerate(source.records)
        record.kind === :SynchronousProcess || continue
        domain = _synchronous_quantity_domain(source.records, record)
        binding = get(_record_options(record), :anchor, nothing)
        anchor = if binding === nothing
            nothing
        else
            _scope_resource(source.records, record, binding)
            _resolved_scoped_anchor(source, _binding_token(binding))
        end
        if domain !== nothing && anchor !== nothing
            anchor.kind === Symbol(domain.kind, :_anchor) &&
                (domain.resource === nothing || domain.resource == anchor.resource) ||
                throw(ArgumentError("process lexical anchor disagrees with its target iteration domain"))
        end
        visited = Set{Int32}()
        function visit(node_index)
            node_index in visited && return
            push!(visited, node_index)
            node = graph.nodes[Int(node_index)]
            payload = node.payload
            if payload isa AnchorBindingPayload && _resolved_scoped_anchor(source, payload) !== nothing
                anchor !== nothing && payload.name === anchor.name && payload.resource == anchor.resource ||
                    throw(ArgumentError("process expression captures an anchor outside its lexical scope"))
            elseif payload isa Union{StateBindingPayload, VariableBindingPayload} && domain !== nothing
                owner = _state_record_for_leaf(source, node)
                if owner === nothing
                    # Enclosing inputs are resolved by the root's existing full
                    # reference graph, not copied into each child source graph.
                    (anchor === nothing || !enclosing_root) && return nothing
                    throw(
                        PottsValidationError(
                            :completion, (
                                PottsDiagnostic(
                                    :unresolved_symbolic_leaf, record.identity, repr(payload.value),
                                    record.identity.path, "a declared state, parameter, or scoped context binding",
                                    "unresolved symbolic leaf in a scoped process", (), record.source,
                                ),
                            )
                        )
                    )
                end
                sample = _state_sample_record(source, owner)
                allowed = domain.kind === :cell ? (:CellState, :ModelState) :
                    domain.kind === :model ? (:ModelState,) : (:SiteState, :FieldState, :ModelState)
                if !(sample.kind in allowed)
                    message = domain.kind === :cell ? "a synchronous CellState assignment requires CellState or ModelState reads and parameters" :
                        domain.kind === :model ? "a synchronous ModelState assignment may read only ModelState values and parameters" :
                        "process reads a quantity from an incompatible storage domain"
                    throw(ArgumentError(message))
                end
                read_scope = _quantity_scope(source.records, owner)
                read_scope === nothing || domain.resource === nothing || read_scope.resource == domain.resource ||
                    throw(ArgumentError("process reads a quantity from a different population"))
            end
            foreach(visit, node.operands)
            return nothing
        end
        for root in graph.roots
            root.record == index && visit(root.node)
        end
    end
    return nothing
end
