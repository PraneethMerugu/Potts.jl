# Compiled manifests, external I/O, initial values, and time contracts.

_manifest_identity(identity::QualifiedStatementID) = (
    path = identity.path,
    local_id = Symbol(identity.local_id),
)

function _qualified_public_name(identity::QualifiedStatementID)
    relative_path = length(identity.path) <= 1 ? () : identity.path[2:end]
    parts = (relative_path..., Symbol(identity.local_id))
    return Symbol(join(String.(parts), "₊"))
end

function _ordered_kind_records(records)
    declarations = filter(
        record -> record.kind in (:CellKind, :MediumKind), records
    )
    return sort(declarations; by = record -> (
        record.kind === :MediumKind ? 0 : 1,
        string(record.identity),
    ))
end

_relationship_order_key(identity::QualifiedStatementID) = string(identity)
_relationship_order_key(record::QualifiedStatement) =
    _relationship_order_key(record.identity)
_relationship_order_key(statement::RelationshipState) =
    String(Symbol(statement_id(statement)))

_is_relationship_resource(::AbstractPottsStatement) = false
_is_relationship_resource(::RelationshipState) = true
_is_relationship_resource(record::QualifiedStatement) =
    record.kind === :RelationshipState

_ordered_relationships(values) = sort(
    filter(_is_relationship_resource, values);
    by = _relationship_order_key,
)

function _manifest_symbol(value)
    value isa AbstractPottsStatement && return Symbol(statement_id(value))
    name = _try_symbolic_name(value)
    name === nothing && return Symbol(string(value))
    return name
end

function _compiled_statement_manifest(completed::PottsSystem)
    return NamedTuple[
        (
            identity = _manifest_identity(record.identity),
            kind = record.kind,
            schema_version = record.schema_version,
            source = record.source isa SourceLocation ? (
                file = record.source.file,
                line = record.source.line,
                module_name = record.source.module_name,
            ) : nothing,
            provenance = record.provenance,
            result_type = record.result_type isa Type ?
                          nameof(record.result_type) : record.result_type,
            shape = record.shape,
            units = record.units,
            reference_conversion = record.reference_conversion,
            reads = Tuple(_manifest_symbol(value) for value in record.reads),
            writes = Tuple(_manifest_symbol(value) for value in record.writes),
            ownership = record.ownership,
            persistence = record.persistence,
            resources = record.resources,
            effect = nameof(typeof(record.effect)),
            bound = (
                maximum = record.bound.maximum,
                basis = record.bound.basis,
            ),
            transaction_identity = record.transaction_identity === nothing ?
                                   nothing :
                                   _manifest_identity(record.transaction_identity),
            lifecycle = record.lifecycle,
            random_operations = Tuple(
                (
                    identity = operation.identity,
                    family = operation.family,
                    reserved = operation.reserved,
                )
                for operation in record.random_operations
            ),
            phase = record.phase === nothing ? nothing : nameof(typeof(record.phase)),
            ordering_dependencies = Tuple(string.(record.ordering_dependencies)),
            engine_admission = Tuple(
                (
                    engine = admission.engine,
                    admitted = admission.admitted,
                    reason = admission.reason,
                )
                for admission in record.engine_admission
            ),
            lowering_identity = record.lowering_identity,
        )
        for record in inspect(completed, Statements())
    ]
end

function _compiled_state_initial(
        completed::PottsSystem,
        record::QualifiedStatement,
        manifest::ParameterManifest,
        ::Type{T},
    ) where {T <: AbstractFloat}
    arguments = _record_arguments(record)
    display_identity = record.identity
    declared = arguments.initial
    variable = arguments.variable
    initial_conditions = ModelingToolkitBase.initial_conditions(completed)
    has_system_initial = haskey(initial_conditions, variable)
    if has_system_initial && declared !== nothing &&
            !isequal(initial_conditions[variable], declared)
        throw(ArgumentError(
            "state `$display_identity` has conflicting declaration and " *
            "PottsSystem initial conditions"
        ))
    end
    value = has_system_initial ? initial_conditions[variable] : declared
    value === nothing && (value = zero(T))
    reference = _reference_for(manifest.reference_units, value)
    converted = T(_numeric_value(value, reference))
    isfinite(converted) ||
        throw(ArgumentError("state `$display_identity` initial value must be finite"))
    return converted, reference
end

function _compiled_state_manifest(
        completed::PottsSystem,
        records,
        manifest::ParameterManifest,
        state_layout::CorePotts.CompilerSPI.StateLayout,
        shape,
        ::Type{T},
    ) where {T <: AbstractFloat}
    result = NamedTuple[]
    for record in records
        record.kind in (
            :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
            :HistoryState,
        ) || continue
        arguments = _record_arguments(record)
        haskey(arguments, :variable) || continue
        role = record.kind === :FieldState ? :field :
               record.kind === :HistoryState ? :history :
               :stored
        storage = record.kind in (:SiteState, :FieldState) ? :site :
                  record.kind === :CellState ? :cell :
                  record.kind === :MediumState ? :medium :
                  record.kind === :ModelState ? :model : :history
        initial, unit = _compiled_state_initial(
            completed, record, manifest, T
        )
        state_shape = storage === :site ? shape :
                      storage === :cell ? :cells :
                      storage === :history ? (
                          shape...,
                          Int(_numeric_value(_statement_option(record, :depth, 1))),
                      ) : ()
        identity = _qualified_resource_identity(record.identity)
        matching_entries = filter(
            entry -> entry.schema.identity == identity,
            state_layout.entries,
        )
        length(matching_entries) == 1 || throw(ArgumentError(
            "compiled state `$(record.identity)` does not resolve to exactly " *
            "one canonical state-layout entry"
        ))
        layout_entry = only(matching_entries)
        key = _symbolic_name(arguments.variable)
        local_key = Symbol(last(split(String(key), '₊')))
        push!(result, (
            key,
            local_key,
            name = _qualified_public_name(record.identity),
            local_name = Symbol(record.identity.local_id),
            identity,
            handle = layout_entry.handle,
            kind = record.kind,
            role,
            storage,
            shape = state_shape,
            scalar_type = T,
            initial,
            unit,
        ))
    end
    return Tuple(result)
end

function _compiled_value_unit(value, manifest::ParameterManifest)
    index = _parameter_index(manifest, value)
    index === nothing || return manifest[index].unit
    return _reference_for(manifest.reference_units, value)
end

function _exact_physical_duration(value)
    _is_quantity(value) || return nothing
    magnitude = Float64(DynamicQuantities.ustrip(value))
    isfinite(magnitude) && magnitude > 0 || throw(ArgumentError(
        "duration_per_mcs must be finite and positive"
    ))
    exact = rationalize(
        Int64,
        magnitude;
        tol = max(eps(magnitude) * 4, eps(Float64)),
    )
    return (
        numerator = numerator(exact),
        denominator = denominator(exact),
        unit = Symbol(string(DynamicQuantities.dimension(value))),
    )
end

function _compiled_time_contract(statements)
    durations = Any[]
    for statement in statements
        value = _statement_option(statement, :duration_per_mcs, nothing)
        value === nothing || push!(durations, value)
    end
    physical = unique(filter(!isnothing, _exact_physical_duration.(durations)))
    length(physical) <= 1 || throw(ArgumentError(
        "all physical duration_per_mcs declarations must identify one exact interval"
    ))
    return (
        native_unit = :mcs,
        ticks_per_mcs = 1,
        duration_per_mcs = isempty(physical) ? nothing : only(physical),
        partial_advance = false,
        publication = :atomic_after_mcs,
    )
end
