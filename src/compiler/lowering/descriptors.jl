# Symbolic evaluator, descriptor, and layout lowering.

"""
    DescriptorSource

Stable host-side source information supplied to downstream descriptor and
workspace construction hooks. Private compiler IR is deliberately absent.
"""
struct DescriptorSource
    identity::QualifiedStatementID
    kind::Symbol
    schema_version::VersionNumber
    lowering_identity::Symbol
    provenance::Any
end

"""
    DescriptorConstructionContext

Complete, resolved input to a downstream descriptor constructor. Every handle
is compact and every evaluator/tag is concrete before this value is created.
"""
struct DescriptorConstructionContext{A, S, H <: Tuple, W <: Tuple, R}
    access::A
    support::S
    state_handles::H
    workspace_handles::W
    role::R
    source_handle::Int32
    source::DescriptorSource
end

"""
    registered_descriptor_payload(::Val{lowering_identity}, context)

Construct inert isbits metadata for a registered statement family. CorePotts
always owns the proposal descriptor and evaluator execution path; downstream
metadata cannot replace either. The payload value's concrete type must exactly
match the fixed `descriptor_payload_type` in the registered statement contract.
"""
function registered_descriptor_payload end

"""
    registered_workspace_schemas(::Val{lowering_identity}, source, scalar_type, lattice_shape)

Declare reusable workspaces required by a registered descriptor family.
Declarations are host metadata; the compiler resolves them to compact handles.
"""
registered_workspace_schemas(
    ::Val, ::DescriptorSource, ::Type, ::Tuple
) = ()

function _static_literal(value, manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    if value isa Bool || value isa Integer || value isa Symbol
        return CorePotts.LiteralExpression(value)
    elseif value isa Number
        return CorePotts.LiteralExpression(T(_numeric_value(
            value, _reference_for(manifest.reference_units, value)
        )))
    end
    throw(ArgumentError(
        "static evaluator literal is not device-compatible: $(repr(value))"
    ))
end

function _static_parameter(value, manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    scalar = _compiled_scalar(value, manifest, T)
    return CorePotts.ParameterExpression(
        scalar.value, scalar.parameter_index
    )
end

function _static_operation_callable(node::NormalizedTermNode)
    operation = try
        CorePotts.operation_callable(
            Val(node.operation), node.schema_version
        )
    catch error
        if error isa MethodError && error.f === CorePotts.operation_callable
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :missing_concrete_operation_callable,
                    node.source,
                    String(node.operation),
                    node.source.path,
                    "a concrete public CorePotts operation callable",
                    "$(node.operation) $(node.schema_version)",
                    (),
                    UnknownSource(),
                ),),
            ))
        end
        rethrow(error)
    end
    isbits(operation) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_operation_callable,
            node.source,
            String(node.operation),
            node.source.path,
            "an isbits concrete operation callable",
            string(typeof(operation)),
            (),
            UnknownSource(),
        ),),
    ))
    return operation
end

function _bounded_static_operation(operation, arguments::Tuple)
    length(arguments) <= 8 &&
        return CorePotts.OperationExpression(operation, arguments...)
    (
        operation isa CorePotts.OrderedFold &&
        operation.operation in (+, *)
    ) || return CorePotts.OperationExpression(operation, arguments...)
    result = CorePotts.OperationExpression(operation, arguments[1:8]...)
    index = 9
    while index <= length(arguments)
        final = min(index + 6, length(arguments))
        result = CorePotts.OperationExpression(
            operation, result, arguments[index:final]...
        )
        index = final + 1
    end
    return result
end

function _state_record_variable(record::QualifiedStatement)
    record.kind in (
        :SiteState,
        :CellState,
        :MediumState,
        :ModelState,
        :FieldState,
        :HistoryState,
    ) || return nothing
    payload = record.normalized_payload
    payload isa Tuple && !isempty(payload) || return nothing
    arguments = first(payload)
    arguments isa NamedTuple && haskey(arguments, :variable) ||
        return nothing
    return arguments.variable
end

function _state_handle_for_leaf(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        handles::Dict{QualifiedStatementID, CorePotts.StateHandle},
    )
    for record in ir.source.records
        variable = _state_record_variable(record)
        variable === nothing && continue
        isequal(variable, node.payload) || continue
        haskey(handles, record.identity) || continue
        return handles[record.identity]
    end
    return nothing
end

function _draw_handle_for_leaf(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
    )
    name = _try_symbolic_name(node.payload)
    name === nothing && return nothing
    text = String(name)
    prefix = "__potts_draw__"
    startswith(text, prefix) || return nothing
    identity = Symbol(text[(lastindex(prefix) + 1):end])
    identities = Symbol[]
    for record in ir.source.records
        for operation in record.random_operations
            operation.reserved && continue
            operation.identity in identities || push!(identities, operation.identity)
        end
    end
    sort!(identities; by = String)
    index = findfirst(==(identity), identities)
    index === nothing && return nothing
    return UInt16(index + 15)
end

function _lower_static_node(
        graph::NormalizedTermGraph,
        ir::AnalyzedTermIR,
        node_index::Int32,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles::Dict{QualifiedStatementID, CorePotts.StateHandle},
        cache::Dict{Int32, CorePotts.AbstractStaticExpression},
    ) where {T <: AbstractFloat}
    haskey(cache, node_index) && return cache[node_index]
    node = graph.nodes[node_index]
    expression = if node.payload_kind === :literal
        _static_literal(node.payload, manifest, T)
    elseif node.payload_kind === :parameter
        _static_parameter(node.payload, manifest, T)
    elseif node.payload_kind in (:state, :variable)
        handle = _state_handle_for_leaf(ir, node, state_handles)
        handle === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_state_handle,
                node.source,
                repr(node.payload),
                node.source.path,
                "one qualified state resource",
                "no matching state block",
                (),
                UnknownSource(),
            ),),
        ))
        CorePotts.StateExpression(handle)
    elseif node.payload_kind in (
            :proposal_context,
            :relationship_context,
            :relation,
            :kind,
            :relationship_payload,
        )
        # Context operations consume these compiler tokens. They are never
        # looked up by name in the executable.
        CorePotts.LiteralExpression(Int32(0))
    elseif node.payload_kind === :symbolic_leaf
        draw_handle = _draw_handle_for_leaf(ir, node)
        draw_handle === nothing ? throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_symbolic_leaf,
                node.source,
                repr(node.payload),
                node.source.path,
                "a parameter, context token, state handle, or RNG handle",
                "unresolved symbolic leaf",
                (),
                UnknownSource(),
            ),),
        )) : CorePotts.LiteralExpression(draw_handle)
    else
        operation = _static_operation_callable(node)
        arguments = Tuple(
            _lower_static_node(
                graph,
                ir,
                operand,
                manifest,
                T,
                state_handles,
                cache,
            )
            for operand in node.operands
        )
        if operation isa CorePotts.ContextOperation
            CorePotts.ContextExpression(operation)
        else
            _bounded_static_operation(operation, arguments)
        end
    end
    cache[node_index] = expression
    return expression
end

function _descriptor_footprint(locality::Symbol)
    locality === :scalar && return CorePotts.EmptyFootprint()
    locality === :proposal_context &&
        return CorePotts.ProposalContextFootprint()
    locality === :owner_local && return CorePotts.OwnerFootprint()
    locality === :finite_spatial &&
        return CorePotts.FiniteSpatialFootprint(())
    locality === :bounded_relationship &&
        return CorePotts.IncidentRelationshipFootprint(typemax(Int16))
    throw(ArgumentError("unsupported descriptor locality `$locality`"))
end

function _descriptor_support(
        ir::AnalyzedTermIR,
        candidate::DescriptorCandidate,
    )
    roots = Int.(candidate.roots)
    sequential = all(roots) do root
        any(admission ->
            admission.engine === :sequential && admission.admitted,
            ir.facts.engine_admission[root])
    end
    checkerboard = all(roots) do root
        any(admission ->
            admission.engine === :checkerboard && admission.admitted,
            ir.facts.engine_admission[root])
    end
    cpu = all(root -> ir.facts.backend_admission[root].cpu, roots)
    gpu = all(root -> ir.facts.backend_admission[root].gpu, roots)
    reason_code = UInt16(
        (!sequential ? 0x01 : 0x00) |
        (!checkerboard ? 0x02 : 0x00) |
        (!cpu ? 0x04 : 0x00) |
        (!gpu ? 0x08 : 0x00)
    )
    return CorePotts.DescriptorSupport(
        sequential,
        checkerboard,
        cpu,
        gpu,
        reason_code,
    )
end

_qualified_resource_identity(identity::QualifiedStatementID) =
    CorePotts.QualifiedResourceIdentity(
        identity.path, Symbol(identity.local_id)
    )

_storage_class_sort_key(value::Tuple) =
    join((_storage_class_sort_key(item) for item in value), "\u001f")
_storage_class_sort_key(value::Type) =
    "type:" * string(parentmodule(value)) * "." * string(value)
_storage_class_sort_key(value) =
    string(typeof(value), ":", repr(value))

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
        candidate.category === :proposal || continue
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

function _proposal_role(record::QualifiedStatement)
    record.kind === :ProposalEnergy &&
        return CorePotts.ProposalEnergyRole()
    record.kind === :ProposalDrive &&
        return CorePotts.ProposalDriveRole()
    record.kind === :ProposalConstraint &&
        return CorePotts.ProposalConstraintRole()
    record.kind === :ProposalModifier &&
        return CorePotts.ProposalModifierRole()
    throw(ArgumentError("record $(record.identity) is not a proposal term"))
end

function _registered_record(record::QualifiedStatement)
    provenance = record.provenance
    return provenance isa NamedTuple &&
           haskey(provenance, :registered_lowering_identity)
end

function _construct_descriptor(
        record::QualifiedStatement,
        evaluator::CorePotts.StaticEvaluator,
        context::DescriptorConstructionContext,
    )
    payload = if _registered_record(record)
        try
            registered_descriptor_payload(
                Val(_effective_descriptor_identity(record)), context
            )
        catch error
            if error isa MethodError &&
                    error.f === registered_descriptor_payload
                throw(PottsValidationError(
                    :descriptor_lowering,
                    (PottsDiagnostic(
                        :registered_descriptor_payload_missing,
                        record.identity,
                        String(_effective_descriptor_identity(record)),
                        record.identity.path,
                        "a public registered_descriptor_payload implementation",
                        string(_effective_descriptor_identity(record)),
                        (),
                        record.source,
                    ),),
                ))
            end
            rethrow(error)
        end
    else
        CorePotts.EmptyDescriptorPayload()
    end
    _validate_descriptor_payload(payload, record)
    if _registered_record(record)
        expected = record.provenance.registered_descriptor_payload_type
        typeof(payload) === expected || throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :descriptor_payload_type_mismatch,
                record.identity,
                string(typeof(payload)),
                record.identity.path,
                "the fixed registered descriptor payload type $(expected)",
                string(typeof(payload)),
                (),
                record.source,
            ),),
        ))
    end
    return CorePotts.ProposalDescriptor(
        evaluator,
        context.access,
        context.support,
        context.state_handles,
        context.workspace_handles,
        context.role,
        context.source_handle,
        payload,
    )
end

function _validate_descriptor_payload(
        payload,
        record::QualifiedStatement,
    )
    isbits(payload) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_descriptor_payload,
            record.identity,
            string(typeof(payload)),
            record.identity.path,
            "inert isbits descriptor metadata",
            string(typeof(payload)),
            (),
            record.source,
        ),),
    ))
    stack = Any[payload]
    while !isempty(stack)
        value = pop!(stack)
        if value isa Union{
                Function,
                CorePotts.AbstractStaticExpression,
                CorePotts.StaticEvaluator,
                CorePotts.AbstractContextualOperation,
            }
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :executable_descriptor_payload,
                    record.identity,
                    string(typeof(value)),
                    record.identity.path,
                    "inert descriptor metadata with no evaluator or callable",
                    string(typeof(value)),
                    (),
                    record.source,
                ),),
            ))
        end
        value isa Union{
            Number, Symbol, String, Bool, Type, VersionNumber,
        } && continue
        if value isa Tuple || value isa NamedTuple
            append!(stack, value)
        elseif isstructtype(typeof(value))
            append!(
                stack,
                (
                    getfield(value, field)
                    for field in fieldnames(typeof(value))
                ),
            )
        end
    end
    return nothing
end

function _descriptor_protocol_error(
        record::QualifiedStatement,
        descriptor,
        detail,
    )
    return PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :invalid_descriptor_protocol,
            record.identity,
            string(typeof(descriptor)),
            record.identity.path,
            "the complete public CorePotts descriptor protocol",
            String(detail),
            (),
            record.source,
        ),),
    )
end

function _validate_descriptor_protocol(
        descriptor,
        record::QualifiedStatement,
        expected_source_handle::Integer,
    )
    facts = try
        payload = CorePotts.descriptor_checkpoint_encode(descriptor)
        reconstructed = CorePotts.descriptor_checkpoint_reconstruct(
            descriptor, payload
        )
        (
            states = CorePotts.descriptor_state_requirements(descriptor),
            workspaces =
                CorePotts.descriptor_workspace_requirements(descriptor),
            access = CorePotts.descriptor_resource_access(descriptor),
            stage = CorePotts.descriptor_stage(descriptor),
            role = CorePotts.descriptor_role(descriptor),
            dependencies = CorePotts.descriptor_dependencies(descriptor),
            support = CorePotts.descriptor_support(descriptor),
            adapted = CorePotts.descriptor_adapt(nothing, descriptor),
            nodes = CorePotts.descriptor_evaluator_node_count(descriptor),
            source_handle = CorePotts.descriptor_source_handle(descriptor),
            checkpoint_policy =
                CorePotts.descriptor_checkpoint_policy(descriptor),
            reconstructed,
            inspection = CorePotts.descriptor_inspection(descriptor),
        )
    catch error
        throw(_descriptor_protocol_error(
            record, descriptor, sprint(showerror, error)
        ))
    end
    facts.states isa Tuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "state requirements must be a tuple"
        ))
    facts.workspaces isa Tuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "workspace requirements must be a tuple"
        ))
    facts.access isa CorePotts.ResourceAccess ||
        throw(_descriptor_protocol_error(
            record, descriptor, "resource access must be ResourceAccess"
        ))
    facts.stage isa Symbol ||
        throw(_descriptor_protocol_error(
            record, descriptor, "stage must be a Symbol"
        ))
    facts.role isa CorePotts.AbstractProposalRole ||
        throw(_descriptor_protocol_error(
            record, descriptor, "proposal role is invalid"
        ))
    facts.dependencies isa Tuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "dependencies must be a tuple"
        ))
    facts.support isa CorePotts.DescriptorSupport ||
        throw(_descriptor_protocol_error(
            record, descriptor, "support must be DescriptorSupport"
        ))
    typeof(facts.adapted) === typeof(descriptor) &&
        isbits(facts.adapted) ||
        throw(_descriptor_protocol_error(
            record,
            descriptor,
            "host adaptation must preserve an isbits descriptor type",
        ))
    facts.nodes isa Integer && facts.nodes > 0 ||
        throw(_descriptor_protocol_error(
            record, descriptor, "evaluator node count must be positive"
        ))
    facts.source_handle == expected_source_handle ||
        throw(_descriptor_protocol_error(
            record, descriptor, "source handle does not identify its record"
        ))
    facts.checkpoint_policy in (
        :persist_logical_state,
        :reconstruct_from_executable,
        :workspace_only,
    ) || throw(_descriptor_protocol_error(
        record, descriptor, "checkpoint policy is not closed"
    ))
    typeof(facts.reconstructed) === typeof(descriptor) ||
        throw(_descriptor_protocol_error(
            record, descriptor, "checkpoint reconstruction changed type"
        ))
    facts.inspection isa NamedTuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "inspection must be a NamedTuple"
        ))
    return nothing
end

function _proposal_descriptor(
        ir::AnalyzedTermIR,
        candidate::DescriptorCandidate,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        workspace_layout,
        workspace_handles,
    ) where {T <: AbstractFloat}
    length(candidate.roots) == 1 || throw(ArgumentError(
        "a proposal descriptor requires exactly one expression root"
    ))
    root = only(candidate.roots)
    cache = Dict{Int32, CorePotts.AbstractStaticExpression}()
    expression = _lower_static_node(
        ir.graph,
        ir,
        root,
        manifest,
        T,
        state_handles,
        cache,
    )
    evaluator = CorePotts.StaticEvaluator(expression)
    record = ir.source.records[candidate.record]
    resolved_states = _record_state_handles(ir, record, state_handles)
    resolved_workspaces = _record_workspace_handles(
        record, workspace_layout, workspace_handles
    )
    access = CorePotts.ResourceAccess(
        resolved_states,
        isempty(record.writes) ? () : resolved_states,
        _descriptor_footprint(ir.facts.locality[root]),
    )
    context = DescriptorConstructionContext(
        access,
        _descriptor_support(ir, candidate),
        resolved_states,
        resolved_workspaces,
        _proposal_role(record),
        candidate.record,
        _descriptor_source(record),
    )
    descriptor = _construct_descriptor(record, evaluator, context)
    _validate_descriptor_protocol(
        descriptor, record, candidate.record
    )
    isbits(descriptor) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_descriptor,
            record.identity,
            string(typeof(descriptor)),
            record.identity.path,
            "an isbits concrete descriptor",
            string(typeof(descriptor)),
            (),
            record.source,
        ),),
    ))
    return descriptor
end

function _descriptor_group_key(descriptor::CorePotts.ProposalDescriptor)
    return (
        descriptor_type = typeof(descriptor),
        evaluator_type = typeof(descriptor.evaluator.expression),
        footprint_type = typeof(descriptor.access.footprint),
        role_type = typeof(descriptor.role),
        stage = CorePotts.descriptor_stage(descriptor),
    )
end

function _descriptor_groups(descriptors)
    keys = Any[]
    grouped = Vector{Vector{Any}}()
    for descriptor in descriptors
        key = _descriptor_group_key(descriptor)
        index = findfirst(isequal(key), keys)
        if index === nothing
            push!(keys, key)
            push!(grouped, Any[descriptor])
        else
            push!(grouped[index], descriptor)
        end
    end
    groups = ()
    for (key, instances) in zip(keys, grouped)
        descriptor_type = key.descriptor_type
        typed_instances = descriptor_type[
            instance for instance in instances
        ]
        state_handles = Tuple(sort!(unique!(
            CorePotts.StateHandle[
                handle
                for descriptor in instances
                for handle in
                    CorePotts.descriptor_state_requirements(descriptor)
            ]
        ); by = handle -> (
            CorePotts.handle_bank(handle),
            CorePotts.handle_slot(handle),
        )))
        workspace_handles = Tuple(sort!(unique!(
            CorePotts.WorkspaceHandle[
                handle
                for descriptor in instances
                for handle in
                    CorePotts.descriptor_workspace_requirements(descriptor)
            ]
        ); by = handle -> (
            CorePotts.handle_bank(handle),
            CorePotts.handle_slot(handle),
        )))
        strategy = CorePotts.DescriptorKernelStrategy{
            descriptor_type,
            key.evaluator_type,
            key.footprint_type,
            key.role_type,
            Val{:proposal},
        }()
        launch = CorePotts.DescriptorLaunch(
            strategy,
            typed_instances,
            state_handles,
            workspace_handles,
        )
        split = (
            descriptor = nameof(descriptor_type),
            evaluator = nameof(key.evaluator_type),
            footprint = nameof(key.footprint_type),
            role = nameof(key.role_type),
            stage = key.stage,
        )
        groups = (groups..., CorePotts.DescriptorGroup(launch, split))
    end
    return groups
end

function _parameter_only_expression(expression)
    expression isa Union{
        CorePotts.LiteralExpression,
        CorePotts.ParameterExpression,
    } && return true
    expression isa CorePotts.OperationExpression || return false
    return all(_parameter_only_expression, expression.arguments)
end

function _parameter_constraint(
        expression::CorePotts.AbstractStaticExpression,
        predicate::UInt8,
        node::NormalizedTermNode,
    )
    _parameter_only_expression(expression) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :runtime_dependent_partial_operation,
            node.source,
            String(node.operation),
            node.source.path,
            "a parameter-only validated domain or a total device operation",
            "runtime state/context dependent domain",
            (),
            UnknownSource(),
        ),),
    ))
    return CorePotts.ParameterDomainConstraint(
        CorePotts.StaticEvaluator(expression),
        predicate,
        node.record,
    )
end

function _draw_family_code(
        graph::NormalizedTermGraph,
        node::NormalizedTermNode,
    )
    family_node = graph.nodes[first(node.operands)]
    family_node.payload_kind === :literal &&
        family_node.payload isa Integer || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :nonliteral_draw_family,
            node.source,
            String(node.operation),
            node.source.path,
            "a statically known scalar distribution family",
            repr(family_node.payload),
            (),
            UnknownSource(),
        ),),
    ))
    return Int(family_node.payload)
end

function _draw_domain_constraints(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
    ) where {T <: AbstractFloat}
    length(node.operands) == 4 || error(
        "validated draw operation has invalid normalized arity"
    )
    family = _draw_family_code(ir.graph, node)
    cache = Dict{Int32, CorePotts.AbstractStaticExpression}()
    first_parameter = _lower_static_node(
        ir.graph,
        ir,
        node.operands[2],
        manifest,
        T,
        state_handles,
        cache,
    )
    second_parameter = _lower_static_node(
        ir.graph,
        ir,
        node.operands[3],
        manifest,
        T,
        state_handles,
        cache,
    )
    zero_expression = CorePotts.LiteralExpression(zero(T))
    one_expression = CorePotts.LiteralExpression(one(T))
    if family == 1
        lower = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:greater_equal), v"1.0.0"),
            first_parameter,
            zero_expression,
        )
        upper = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:less_equal), v"1.0.0"),
            first_parameter,
            one_expression,
        )
        return (
            _parameter_constraint(lower, 0x03, node),
            _parameter_constraint(upper, 0x03, node),
        )
    elseif family == 2
        ordered = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:less), v"1.0.0"),
            first_parameter,
            second_parameter,
        )
        return (_parameter_constraint(ordered, 0x03, node),)
    elseif family == 3
        positive = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:greater), v"1.0.0"),
            second_parameter,
            zero_expression,
        )
        return (_parameter_constraint(positive, 0x03, node),)
    elseif family == 4
        throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :nonscalar_distribution_in_proposal_term,
                node.source,
                String(node.operation),
                node.source.path,
                "a scalar Bernoulli, Uniform, or Normal distribution",
                "UnitVector",
                (),
                UnknownSource(),
            ),),
        ))
    end
    throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :unknown_draw_family,
            node.source,
            String(node.operation),
            node.source.path,
            "a registered scalar distribution family",
            string(family),
            (),
            UnknownSource(),
        ),),
    ))
end

function _domain_constraints(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
    ) where {T <: AbstractFloat}
    constraints = Any[]
    for node in ir.graph.nodes
        node.transfer === nothing && continue
        node.transfer.totality in (
            :domain_checked, :requires_prelaunch_validation
        ) || continue
        if node.operation === :draw
            append!(
                constraints,
                _draw_domain_constraints(
                    ir, node, manifest, T, state_handles
                ),
            )
            continue
        end
        node.operation in (:logarithm, :square_root) || throw(
            PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :unsupported_totality_rule,
                    node.source,
                    String(node.operation),
                    node.source.path,
                    "a specified prelaunch domain predicate",
                    String(node.operation),
                    (),
                    UnknownSource(),
                ),),
            ),
        )
        length(node.operands) == 1 || error(
            "validated unary operation has invalid normalized arity"
        )
        cache = Dict{Int32, CorePotts.AbstractStaticExpression}()
        operand = _lower_static_node(
            ir.graph,
            ir,
            only(node.operands),
            manifest,
            T,
            state_handles,
            cache,
        )
        predicate = node.operation === :logarithm ? UInt8(0x01) : UInt8(0x02)
        push!(
            constraints,
            _parameter_constraint(operand, predicate, node),
        )
    end
    keys = DataType[]
    values = Vector{Vector{Any}}()
    for constraint in constraints
        key = typeof(constraint)
        index = findfirst(==(key), keys)
        if index === nothing
            push!(keys, key)
            push!(values, Any[constraint])
        else
            push!(values[index], constraint)
        end
    end
    groups = ()
    for (key, entries) in zip(keys, values)
        typed = key[entry for entry in entries]
        groups = (groups..., CorePotts.ConstraintGroup(typed))
    end
    return groups
end

function _lower_descriptor_plan(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
    ) where {T <: AbstractFloat}
    state_layout, state_handles = _state_layout(ir, T)
    workspace_layout, workspace_handles = _workspace_layout(ir, T)
    descriptors = Any[]
    for candidate in ir.candidates
        candidate.category === :proposal || continue
        _descriptor_candidate_enabled(
            ir.source.records[candidate.record]
        ) || continue
        push!(
            descriptors,
            _proposal_descriptor(
                ir,
                candidate,
                manifest,
                T,
                state_handles,
                workspace_layout,
                workspace_handles,
            ),
        )
    end
    groups = _descriptor_groups(descriptors)
    constraints = _domain_constraints(ir, manifest, T, state_handles)
    fingerprint = _sha256_hex(
        "potts-descriptor-execution-plan-v2",
        ir.structural_key,
        Tuple((
            group.split,
            length(group.launch.instances),
            group.launch.state_handles,
            group.launch.workspace_handles,
        ) for group in groups),
        Tuple((
            schema.identity.path,
            schema.identity.name,
            schema.version,
            schema.domain,
            schema.element_type,
            schema.shape,
            schema.capacity,
        ) for schema in state_layout.schemas),
        Tuple((
            schema.identity.path,
            schema.identity.name,
            schema.version,
            schema.element_type,
            schema.shape,
            schema.capacity,
        ) for schema in workspace_layout.schemas),
    )
    return CorePotts.DescriptorExecutionPlan(
        groups,
        state_layout,
        workspace_layout,
        constraints,
        [record.identity for record in ir.source.records],
        Int32(length(descriptors)),
        fingerprint,
    )
end
