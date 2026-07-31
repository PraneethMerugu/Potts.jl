# Canonical storage representations, value-level banks, and resource slots.

function _canonical_bank_handles(
        schemas,
        storage_class,
        handle_type,
    )
    classes = Any[]
    for schema in schemas
        class = storage_class(schema)
        any(isequal(class), classes) || push!(classes, class)
    end
    sort!(classes; by = _storage_class_sort_key)
    banks = [
        only(findall(isequal(storage_class(schema)), classes))
        for schema in schemas
    ]
    order = sortperm(eachindex(schemas); by = index -> banks[index])
    counts = zeros(Int, length(classes))
    handles = Vector{Any}(undef, length(schemas))
    for index in order
        bank = banks[index]
        counts[bank] += 1
        handles[index] = handle_type(
            classes[bank],
            bank,
            counts[bank],
        )
    end
    return order, handles
end

function _state_layout(
        ir::AnalyzedTermIR, ::Type{T}
    ) where {T <: AbstractFloat}
    records = QualifiedStatement[]
    schemas = CorePotts.StateBlockSchema[]
    handles = Dict{QualifiedStatementID, CorePotts.StateHandle}()
    lattice_shape = _lattice_shape(ir)
    for record in ir.source.records
        record.kind in (
            :SiteState,
            :CellState,
            :MediumState,
            :ModelState,
            :FieldState,
            :HistoryState,
            :RelationshipState,
        ) || continue
        declared_capacity = if record.shape isa NamedTuple &&
                haskey(record.shape, :capacity)
            Int(record.shape.capacity)
        elseif record.shape isa Tuple &&
                all(item -> item isa Integer, record.shape)
            prod(record.shape; init = 1)
        else
            0
        end
        domain = record.ownership === :relationship ? :relationship :
                 record.ownership === :cell ? :cell :
                 record.ownership === :medium ? :medium :
                 record.ownership === :model ? :model : :site
        shape = if domain === :site && !isempty(lattice_shape)
            lattice_shape
        elseif record.shape isa Tuple &&
                all(item -> item isa Integer && item > 0, record.shape)
            Tuple(Int.(record.shape))
        elseif declared_capacity > 0
            (declared_capacity,)
        else
            (1,)
        end
        capacity = prod(shape; init = 1)
        element_type = record.result_type isa Type &&
                       record.result_type <: Integer ?
                       record.result_type : T
        schema = CorePotts.StateBlockSchema(
            _qualified_resource_identity(record.identity),
            record.schema_version,
            domain,
            element_type,
            shape,
            capacity,
            :structure_of_arrays,
            :provided_or_zero,
            :shape_and_finite,
            record.persistence,
            record.lifecycle,
            :declared,
            record.effect isa PureRead ? :read_only : :bounded_write,
            :adapt_storage,
            :copy,
            record.persistence === :logical ?
                :logical_copy : :reconstruct_from_initial,
            :qualified,
            record.persistence === :logical,
        )
        push!(records, record)
        push!(schemas, schema)
    end
    order, assigned = _canonical_bank_handles(
        schemas,
        CorePotts.state_storage_class,
        CorePotts.StateHandle,
    )
    entries = ()
    for index in order
        handle = assigned[index]
        entries = (
            entries...,
            CorePotts.StateEntry(handle, schemas[index]),
        )
        handles[records[index].identity] = handle
    end
    return CorePotts.StateLayout(entries), handles
end

function _lattice_shape(ir::AnalyzedTermIR)
    index = findfirst(record -> record.kind === :LatticeDomain, ir.source.records)
    index === nothing && return ()
    shape = ir.source.records[index].shape
    return shape isa Tuple ? shape : ()
end

function _effective_descriptor_identity(record::QualifiedStatement)
    provenance = record.provenance
    if provenance isa NamedTuple &&
            haskey(provenance, :registered_lowering_identity)
        return provenance.registered_lowering_identity
    end
    return record.lowering_identity
end

_descriptor_source(record::QualifiedStatement) = DescriptorSource(
    record.identity,
    record.kind,
    record.schema_version,
    _effective_descriptor_identity(record),
    record.provenance,
)

function _descriptor_candidate_enabled(record::QualifiedStatement)
    _registered_record(record) && return true
    record.kind === :HamiltonianTerm && return true
    payload = record.normalized_payload
    payload isa Tuple && length(payload) >= 2 || return true
    options = payload[2]
    options isa NamedTuple || return true
    mechanism = haskey(options, :mechanism) ? options.mechanism : nothing
    return mechanism in (nothing, :symbolic)
end

function _workspace_layout(ir::AnalyzedTermIR, ::Type{T}) where {
        T <: AbstractFloat,
    }
    schemas = CorePotts.WorkspaceSchema[]
    schema_keys = Vector{Vector{Tuple{
        QualifiedStatementID,
        CorePotts.QualifiedResourceIdentity,
    }}}()
    handles = Dict{
        Tuple{QualifiedStatementID, CorePotts.QualifiedResourceIdentity},
        CorePotts.WorkspaceHandle,
    }()
    shape = _lattice_shape(ir)
    for candidate in ir.candidates
        candidate.category in (
            :hamiltonian, :drive, :constraint, :modifier,
        ) || continue
        record = ir.source.records[candidate.record]
        _descriptor_candidate_enabled(record) || continue
        source = _descriptor_source(record)
        declarations = registered_workspace_schemas(
            Val(_effective_descriptor_identity(record)), source, T, shape
        )
        declarations isa Tuple || throw(ArgumentError(
            "registered_workspace_schemas must return a tuple"
        ))
        for schema in declarations
            schema isa CorePotts.WorkspaceSchema || throw(ArgumentError(
                "registered workspace declarations must be WorkspaceSchema values"
            ))
            key = (record.identity, schema.identity)
            existing = findfirst(
                candidate -> candidate.identity == schema.identity,
                schemas,
            )
            if existing === nothing
                push!(schemas, schema)
                push!(schema_keys, [key])
            else
                existing_schema = schemas[existing]
                (
                    existing_schema.version,
                    existing_schema.element_type,
                    existing_schema.shape,
                    existing_schema.capacity,
                    existing_schema.container_type,
                    existing_schema.initialization,
                    existing_schema.lifetime,
                    existing_schema.access,
                    existing_schema.adaptation,
                    existing_schema.inspection,
                    existing_schema.shareable,
                ) == (
                    schema.version,
                    schema.element_type,
                    schema.shape,
                    schema.capacity,
                    schema.container_type,
                    schema.initialization,
                    schema.lifetime,
                    schema.access,
                    schema.adaptation,
                    schema.inspection,
                    schema.shareable,
                ) || throw(ArgumentError(
                    "conflicting qualified workspace identity $(schema.identity)"
                ))
                push!(schema_keys[existing], key)
            end
        end
    end
    order, assigned = _canonical_bank_handles(
        schemas,
        CorePotts.workspace_storage_class,
        CorePotts.WorkspaceHandle,
    )
    entries = ()
    for index in order
        handle = assigned[index]
        entries = (
            entries...,
            CorePotts.WorkspaceEntry(handle, schemas[index]),
        )
        for key in schema_keys[index]
            handles[key] = handle
        end
    end
    return CorePotts.WorkspaceLayout(entries), handles
end

function _record_state_handles(
        ir::AnalyzedTermIR,
        record::QualifiedStatement,
        handles::Dict{QualifiedStatementID, CorePotts.StateHandle},
    )
    result = CorePotts.StateHandle[]
    for identity in record.resources
        haskey(handles, identity) || continue
        handle = handles[identity]
        handle in result || push!(result, handle)
    end
    for state_record in ir.source.records
        haskey(handles, state_record.identity) || continue
        variable = _state_record_variable(state_record)
        variable === nothing && continue
        any(read -> isequal(read, variable), record.reads) || continue
        handle = handles[state_record.identity]
        handle in result || push!(result, handle)
    end
    sort!(
        result;
        by = handle -> (
            CorePotts.handle_bank(handle),
            CorePotts.handle_slot(handle),
        ),
    )
    return Tuple(result)
end

function _record_workspace_handles(
        record::QualifiedStatement,
        workspace_layout::CorePotts.WorkspaceLayout,
        handles,
    )
    values = CorePotts.WorkspaceHandle[]
    for schema in workspace_layout.schemas
        key = (record.identity, schema.identity)
        haskey(handles, key) || continue
        push!(values, handles[key])
    end
    sort!(
        values;
        by = handle -> (
            CorePotts.handle_bank(handle),
            CorePotts.handle_slot(handle),
        ),
    )
    return Tuple(values)
end

function _domain_plan(ir::AnalyzedTermIR, candidate::DescriptorCandidate)
    fact = candidate.energy_domain
    fact.kind === :sites && return CorePotts.SiteEnergyDomainPlan()
    if fact.kind === :cells
        kind = _compiled_kind_index(
            ir, Symbol(statement_id(fact.resource))
        )
        kind === nothing && throw(ArgumentError(
            "cell energy domain has no compiled kind index"
        ))
        return CorePotts.CellEnergyDomainPlan(kind)
    end
    owner = ir.source.records[candidate.record]
    if fact.kind === :contacts
        relation = _resource_record(
            ir.source, owner, :SpatialRelation, fact.resource
        )
        relation === nothing && throw(ArgumentError(
            "contact energy domain has no compiled relation handle"
        ))
        handle = findfirst(
            record -> record.identity == relation.identity,
            ir.source.records,
        )
        return CorePotts.ContactEnergyDomainPlan(Int32(handle))
    end
    if fact.kind === :edges
        relationship = _resource_record(
            ir.source, owner, :RelationshipState, fact.resource
        )
        relationship === nothing && throw(ArgumentError(
            "relationship energy domain has no compiled resource handle"
        ))
        handle = findfirst(
            record -> record.identity == relationship.identity,
            ir.source.records,
        )
        return CorePotts.RelationshipEnergyDomainPlan(Int32(handle))
    end
    throw(ArgumentError("unsupported energy domain plan `$(fact.kind)`"))
end

function _affected_plan(candidate::DescriptorCandidate)
    fact = candidate.affected_anchors
    maximum = Int32(fact.maximum)
    fact.kind === :target_site &&
        return CorePotts.TargetSiteAffectedPlan(maximum)
    fact.kind === :source_and_target_cells &&
        return CorePotts.SourceTargetCellsAffectedPlan(maximum)
    fact.kind === :incident_contacts &&
        return CorePotts.IncidentContactsAffectedPlan(maximum)
    fact.kind === :incident_relationships &&
        return CorePotts.IncidentRelationshipsAffectedPlan(maximum)
    throw(ArgumentError("unsupported affected-anchor plan `$(fact.kind)`"))
end

function _proposal_role(
        ir::AnalyzedTermIR,
        candidate::DescriptorCandidate,
        record::QualifiedStatement,
    )
    record.kind === :HamiltonianTerm && return CorePotts.HamiltonianRole(
        _domain_plan(ir, candidate),
        _affected_plan(candidate),
    )
    record.kind === :ProposalDrive &&
        return CorePotts.ProposalDriveRole()
    record.kind === :ProposalConstraint &&
        return CorePotts.ProposalConstraintRole()
    record.kind === :ProposalModifier &&
        return CorePotts.ProposalModifierRole()
    throw(ArgumentError("record $(record.identity) is not a proposal term"))
end
