# Canonical inspection is a cold, read-only projection. The concrete Stage
# lowering defines the normalizers because it owns the planning facts; neither
# planning nor execution consumes the result.

@inline _phase_fact(kind::Symbol, count::Integer = 1) =
    (kind, count = Int(count))

"""
    LocalMath.inspect(law::LocalLaw)

Return the law's semantic parameters, relations, stages, source provenance,
and exact backend-independent equivalence tuple. This is a cold immutable
projection; planning and execution never consume it.
"""
inspect(law::LocalLaw; level = nothing) =
    _inspection_projection(_inspect_local_law(law), level)

"""`lowering_identity(plan)` returns the durable selected lowering-family identity."""
lowering_identity(plan::Plan) =
    _lowering_identity(plan.lowering)

_receipt_state(state::UInt8) =
    state == _EXECUTION_RECEIPT_PENDING ? :pending :
    state == _EXECUTION_RECEIPT_SUCCESS ? :success :
    state == _EXECUTION_RECEIPT_SEMANTIC_FAILURE ? :semantic_failure :
    state == _EXECUTION_RECEIPT_DEPENDENCY_FAILURE ? :dependency_failure :
    state == _EXECUTION_RECEIPT_PROVIDER_FAILURE ? :provider_failure : :invalid

"""
    LocalMath.inspect(receipt::ExecutionReceipt)

Return the logical submission identity, dependency summaries, lease generation,
settlement state, and cached failure without synchronizing the provider or
embedding the prepared plan.
"""
function inspect(receipt::ExecutionReceipt; level = nothing)
    report = (lifecycle = :ExecutionReceipt, serial = receipt.serial,
        scope_ordinal = receipt.scope_ordinal,
        lease = (index = receipt.lease_index,
            generation = receipt.lease_generation),
        dependency_join_count = receipt.dependency_join_count,
        dependencies = map(dependency -> (
                serial = dependency.serial,
                scope_ordinal = dependency.scope_ordinal,
                state = _receipt_state(dependency.state),
                failure = dependency.failure,
            ), receipt.dependencies),
        pending = ispending(receipt), state = _receipt_state(receipt.state),
        failure = receipt.failure)
    level === nothing || throw(LocalMathValidationError(
        "inspection levels do not apply to an execution receipt";
        stage = :inspect, contract = :inspection_level,
        expected = nothing, actual = level,
        hint = "call inspect(receipt) for the receipt settlement report"))
    return report
end

const _INSPECTION_LEVELS = (:relations, :numerics, :memory, :kernels)

function _inspection_level_error(report, level, available)
    throw(LocalMathValidationError(
        "the requested inspection level is unavailable for this lifecycle";
        stage = :inspect, contract = :inspection_level,
        expected = available, actual = (lifecycle = report.lifecycle, level),
        hint = "inspect the planned or prepared law for physical facts"))
end

function _semantic_stage_projection(stage)
    return (
        index = stage.index,
        source = stage.source,
        origin = stage.origin,
        reads = stage.reads,
        control = stage.control,
        publications = stage.publications,
    )
end

_inspection_projection(report, ::Nothing) = report

function _inspection_projection(report, level::Symbol)
    level in _INSPECTION_LEVELS || throw(LocalMathValidationError(
        "unknown inspection level";
        stage = :inspect, contract = :inspection_level,
        expected = _INSPECTION_LEVELS, actual = level))
    if level === :relations
        return (
            lifecycle = report.lifecycle,
            parameters = report.parameters,
            relations = report.relations,
            equivalence = report.equivalence,
        )
    elseif level === :numerics
        return (
            lifecycle = report.lifecycle,
            parameters = report.parameters,
            stages = map(_semantic_stage_projection, report.stages),
            equivalence = report.equivalence,
        )
    elseif level === :memory
        report.planning === nothing &&
            _inspection_level_error(report, level, (:relations, :numerics))
        base = (
            lifecycle = report.lifecycle,
            workspace = report.planning.workspace,
            workspace_bytes = report.planning.workspace_bytes,
        )
        return hasproperty(report, :realized) ? merge(base, (
            bindings = report.realized.bindings,
            lease_capacity = report.realized.lease_capacity,
            workspace_ownership = report.realized.workspace_ownership,
        )) : base
    end
    report.planning === nothing &&
        _inspection_level_error(report, level, (:relations, :numerics))
    base = (
        lifecycle = report.lifecycle,
        compiler = report.planning.compiler,
        program_phases = report.planning.program_phases,
        stage_phases = report.planning.stage_phases,
        physical_segments = report.planning.physical_segments,
        stage_local_launch_count = report.planning.stage_local_launch_count,
        program_reset_count = report.planning.program_reset_count,
        provider_launch_count = report.planning.base_provider_launch_count,
        stages = map(stage -> stage.planning, report.stages),
    )
    return hasproperty(report, :realized) ? merge(base, (
        prepared_launch_types = report.realized.prepared_launch_types,
        callback_methods = report.realized.callback_methods,
        provider = report.realized.provider,
        device = report.realized.device,
    )) : base
end

_short_semantic_identity(value) = first(string(semantic_identity(value)), 8)

function _show_space_summary(io::IO, space::Space; identity::Bool = true)
    print(io, "Space(extent=")
    show(io, size(space))
    kind = space_kind(space)
    kind === _IndexSpaceKind || print(io, ", kind=", nameof(kind))
    identity && print(io, ", id=", _short_semantic_identity(space))
    print(io, ")")
end

Base.show(io::IO, space::Space) = _show_space_summary(io, space)
Base.show(io::IO, ::MIME"text/plain", space::Space) =
    _show_space_summary(io, space)

function Base.show(io::IO, field::Field)
    print(io, "Field(")
    show(io, eltype(field))
    print(io, ", space=")
    _show_space_summary(io, field.space; identity = false)
    print(io, ", id=", _short_semantic_identity(field), ")")
end
Base.show(io::IO, ::MIME"text/plain", field::Field) = show(io, field)

_relation_display_name(::_IdentityRelation) = :IdentityRelation
_relation_display_name(::_AffineRelation) = :AffineRelation
_relation_display_name(::_FixedRelation) = :FixedRelation
_relation_display_name(::_ProductRelation) = :ProductRelation
_relation_display_name(::_ComposedRelation) = :ComposedRelation
_relation_display_name(::_BoundaryRelation) = :BoundaryRelation
_relation_display_name(::_RuntimeRelation) = :RuntimeRelation
_relation_display_name(::_FieldIndexRelation) = :IndexRelation
_relation_display_name(::_MaskedRelation) = :MaskedRelation
_relation_display_name(::_SelectedRelation) = :SelectedRelation
_relation_display_name(::_InverseRelation) = :InverseRelation
_relation_display_name(::_PackedRelation) = :PackedRelation

_boundary_display(::StrictBoundary) = :strict
_boundary_display(policy::PeriodicBoundary) = (:periodic, policy.axes)
_boundary_display(::ExteriorBoundary) = :exterior
_boundary_display(policy::MaskedBoundary) =
    (:masked, _boundary_display(policy.fallback))
_boundary_display(policy::GhostBoundary) =
    (:ghost, policy.lower, policy.upper)

function _show_relation_details(io::IO, representation)
    if representation isa _AffineRelation
        print(io, ", offsets=")
        show(io, representation.offsets)
        any(value -> !iszero(value), representation.origin) && begin
            print(io, ", origin=")
            show(io, representation.origin)
        end
    elseif representation isa _BoundaryRelation
        print(io, ", boundary=")
        show(io, _boundary_display(representation.policy))
    elseif representation isa _FieldIndexRelation
        print(io, ", optional=", representation.optional)
    elseif representation isa _RuntimeRelation
        print(io, ", key_type=")
        show(io, representation.key_type)
        print(io, ", ownership=", representation.ownership)
    elseif representation isa _PackedRelation
        print(io, ", capacity=", representation.capacity,
            ", layout=", representation.layout,
            ", ownership=", representation.ownership)
    elseif representation isa _ProductRelation ||
            representation isa _ComposedRelation
        print(io, ", factors=", length(representation.factors))
    end
end

function Base.show(io::IO, relation::Relation)
    representation = relation.representation
    print(io, _relation_display_name(representation), "(")
    _show_space_summary(io, domain(relation); identity = false)
    print(io, " → ")
    _show_space_summary(io, codomain(relation); identity = false)
    print(io, ", degree=", degree_bound(relation),
        ", storage=", _relation_requires_storage(representation) ?
            :required : :computed)
    _show_relation_details(io, representation)
    !iszero(schema_epoch(relation)) &&
        print(io, ", schema_epoch=", schema_epoch(relation))
    print(io, ", id=", _short_semantic_identity(relation), ")")
end

function Base.show(io::IO, ::MIME"text/plain", relation::Relation)
    representation = relation.representation
    println(io, _relation_display_name(representation))
    print(io, "  domain: ")
    _show_space_summary(io, domain(relation))
    print(io, "\n  codomain: ")
    _show_space_summary(io, codomain(relation))
    print(io, "\n  degree: ", degree_bound(relation),
        "\n  storage: ", _relation_requires_storage(representation) ?
            :required : :computed)
    print(io, "\n  identity: ", semantic_identity(relation))
    !iszero(schema_epoch(relation)) &&
        print(io, "\n  schema epoch: ", schema_epoch(relation))
    _show_relation_details(io, representation)
end

function Base.show(io::IO, collection::Collection)
    print(io, "Collection(")
    show(io, eltype(collection))
    print(io, ", capacity=", collection.capacity,
        ", id=", _short_semantic_identity(collection), ")")
end
Base.show(io::IO, ::MIME"text/plain", collection::Collection) =
    show(io, collection)

function _show_parameter_summary(io::IO, parameters)
    isempty(parameters.declarations) && return print(io, "none")
    for (index, declaration) in enumerate(parameters.declarations)
        index == 1 || print(io, ", ")
        print(io, declaration.name, "::")
        show(io, _parameter_type(declaration))
    end
end

_access_mode_name(access::Access) =
    access.mode isa _RequiredAccess ? :required : :samples

function _show_control_summary(io::IO, control::Control)
    parts = Pair{Symbol,Any}[]
    control.prefix isa _NoPrefix || push!(parts, :prefix => control.prefix)
    control.mask isa _NoMask || push!(parts, :mask => control.mask)
    control.subset isa _NoSubset || push!(parts, :subset => control.subset)
    control.gate isa _NoGate || push!(parts, :gate => control.gate)
    isempty(parts) && return print(io, "none")
    for (index, part) in enumerate(parts)
        index == 1 || print(io, ", ")
        print(io, first(part), "=", nameof(typeof(last(part))))
    end
end

function _show_publication_summary(io::IO, publication::Publication)
    facts = _stage_publication_context(publication)
    print(io, join(facts.ports, ", "), " — ", facts.details.law.kind)
    print(io, ", conflicts=", facts.details.law.conflicts)
    hasproperty(facts.details.law, :onempty) &&
        print(io, ", empty=", nameof(typeof(facts.details.law.onempty)))
    destinations = map(facts.details.components) do component
        component.kind === :field ?
            (kind = :field, id = first(string(component.field), 8)) :
        component.kind === :collection ?
            (kind = :collection, id = first(string(component.collection), 8)) :
            (kind = :fold_state, id = nothing)
    end
    print(io, ", destinations=")
    show(IOContext(io, :compact => true), destinations)
end

function _show_law_summary(io::IO, work::LocalLaw)
    fields, relations, collections = _law_descriptor_requirements(work)
    println(io, "LocalLaw")
    print(io, "  parameters: ")
    _show_parameter_summary(io, work.parameters)
    println(io, "\n  descriptors:")
    for field in fields
        print(io, "    field: ")
        show(io, field)
        println(io)
    end
    for relation in relations
        print(io, "    relation: ")
        show(io, relation)
        println(io)
    end
    for collection in collections
        print(io, "    collection: ")
        show(io, collection)
        println(io)
    end
    println(io, "  stages:")
    for (index, stage) in enumerate(work.stages)
        print(io, "    stage ", index, "\n      domain: ")
        _show_space_summary(io, stage.source; identity = false)
        print(io, "\n      reads:")
        if isempty(stage.accesses)
            print(io, " none")
        else
            for (role, access) in pairs(stage.accesses)
                print(io, "\n        ", role)
                if access isa Access
                    print(io, " via ",
                        _relation_display_name(access.relation.representation),
                        " — ", _access_mode_name(access))
                else
                    print(io, " — ", nameof(typeof(access)))
                end
            end
        end
        print(io, "\n      writes:")
        if isempty(stage.publications)
            print(io, " none")
        else
            for publication in stage.publications
                print(io, "\n        ")
                _show_publication_summary(io, publication)
            end
        end
        print(io, "\n      control: ")
        _show_control_summary(io, stage.control)
        _has_source_origin(stage.origin) && begin
            print(io, "\n      origin: ")
            _show_validation_origin(io, stage.origin)
        end
        index == length(work.stages) || println(io)
    end
end

Base.show(io::IO, work::LocalLaw) =
    print(io, "LocalLaw(stages=", length(work.stages), ")")
Base.show(io::IO, ::MIME"text/plain", work::LocalLaw) =
    _show_law_summary(io, work)
Base.show(io::IO, plan::Plan) =
    print(io, "Plan(family=stage_program",
        ", backend=", typeof(plan.backend), ")")
function Base.show(io::IO, ::MIME"text/plain", plan::Plan)
    _show_law_summary(io, plan.bound.law)
    report = inspect(plan)
    print(io, "\n  planning: backend=", typeof(plan.backend),
        ", workspace_bytes=", report.planning.workspace_bytes,
        ", physical_segments=", length(report.planning.physical_segments),
        ", provider_launches=", report.planning.base_provider_launch_count)
end
Base.show(io::IO, prepared::PreparedPlan) =
    print(io, "PreparedPlan(provider=", _lane_provider(prepared.lane),
        ", submitted=", prepared.submitted,
        ", outstanding=", prepared.outstanding,
        ", dependency_arity=", prepared.dependency_arity, ")")
function Base.show(io::IO, ::MIME"text/plain", prepared::PreparedPlan)
    _show_law_summary(io, prepared.plan.bound.law)
    report = inspect(prepared)
    field_ownership = map(value -> value.ownership,
        report.realized.bindings.fields)
    relation_ownership = map(value -> value.ownership,
        report.realized.bindings.relations)
    print(io, "\n  prepared: provider=", report.realized.provider,
        ", device=", report.realized.device,
        ", workspace_bytes=", report.planning.workspace_bytes,
        ", lease_capacity=", report.realized.lease_capacity,
        ", dependency_arity=", report.realized.dependency_arity,
        "\n  storage ownership: fields=", field_ownership,
        ", relations=", relation_ownership,
        "\n  execution: physical_segments=",
        length(report.planning.physical_segments),
        ", provider_launches=", report.planning.base_provider_launch_count,
        ", outstanding=", prepared.outstanding)
end
Base.show(io::IO, receipt::ExecutionReceipt) =
    print(io, "ExecutionReceipt(serial=", receipt.serial,
        ", ordinal=", receipt.scope_ordinal,
        ", dependencies=", length(receipt.dependencies),
        ", pending=", ispending(receipt), ")")
