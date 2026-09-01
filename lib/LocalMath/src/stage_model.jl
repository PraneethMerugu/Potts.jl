# Private semantic foundation for stage-tuple execution. These values
# describe scientific structure only; they do not add a planner or executor.

mutable struct _StageModelSeal end
const _STAGE_MODEL_SEAL = _StageModelSeal()

abstract type _ParameterBounds end
struct _UnboundedParameter <: _ParameterBounds
    function _UnboundedParameter(seal::_StageModelSeal)
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        return new()
    end
end
_UnboundedParameter() = _UnboundedParameter(_STAGE_MODEL_SEAL)
struct _ClosedParameterBounds{T} <: _ParameterBounds
    lower::T
    upper::T
    function _ClosedParameterBounds(
            seal::_StageModelSeal, lower::T, upper::T
        ) where {T}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        _storage_value_type(T) || throw(LocalMathValidationError(
            "parameter bounds require an admitted storage value type";
            stage = :construct, contract = :parameter_bounds_type, actual = T,
        ))
        lower <= upper || throw(LocalMathValidationError(
            "parameter bounds must be ordered";
            stage = :construct, contract = :parameter_bounds,
            expected = :ordered, actual = (lower, upper),
        ))
        return new{T}(lower, upper)
    end
end
_ClosedParameterBounds(lower, upper) =
    _ClosedParameterBounds(_STAGE_MODEL_SEAL, lower, upper)

"""`Parameter(name, T; bounds=nothing)` declares one typed submission parameter."""
struct Parameter{T,B<:_ParameterBounds}
    name::Symbol
    bounds::B
    function Parameter(
            seal::_StageModelSeal, ::Type{T}, name::Symbol, bounds::B
        ) where {T,B<:_ParameterBounds}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        bounds isa Union{_UnboundedParameter,_ClosedParameterBounds} || throw(
            LocalMathValidationError(
                "foreign parameter-bound laws are not admitted";
                stage = :construct, contract = :parameter_bounds,
                actual = B,
            )
        )
        return new{T,B}(name, bounds)
    end
end

_device_parameter_type(type::Type) = _storage_value_type(type)

function _device_type_parameter(parameter)
    # Symbols carried as type parameters are compile-time callable identity,
    # not runtime metadata. Runtime Symbol values remain rejected by
    # `_device_evaluator_capture`, and the closed-callable effect analysis is
    # still the final authority over the method body.
    parameter isa Symbol && return true
    parameter isa Union{UUIDs.UUID,Val,Ptr,Ref,NamedTuple} && return false
    parameter isa Bool && return true
    parameter isa Enum && return true
    parameter isa Integer && return 0 <= parameter <= 32
    parameter isa Tuple && return all(_device_type_parameter, parameter)
    if parameter isa Type
        parameter <: Union{Ptr,Ref,AbstractArray,NamedTuple,Val,Space,Field,Relation} &&
            return false
        _storage_value_type(parameter) && return true
        return isconcretetype(parameter) && isbitstype(parameter) &&
            _device_type_parameters(parameter)
    end
    return false
end

function _device_type_parameters(type::Type)
    type isa DataType || return false
    return all(_device_type_parameter, type.parameters)
end

function _device_evaluator_capture(value)
    T = typeof(value)
    _device_parameter_type(T) && return true
    value isa Union{
        Symbol,UUIDs.UUID,Val,Ptr,Ref,AbstractArray,NamedTuple,
        Space,Field,Relation,
    } && return false
    isconcretetype(T) && isbitstype(T) || return false
    value isa Function && fieldcount(T) == 0 && return true
    _device_type_parameters(T) || return false
    return all(index -> _device_evaluator_capture(getfield(value, index)),
        1:fieldcount(T))
end

function _device_capture_rejection(value; path::Tuple = (:evaluator,))
    T = typeof(value)
    _device_parameter_type(T) && return nothing
    if value isa AbstractArray
        return (path, type = T, reason = :array_capture,
            hint = "declare the array as a Field and gather it explicitly")
    elseif value isa Symbol
        return (path, type = T, reason = :runtime_symbol,
            hint = "put symbolic identity in the callable type, not a runtime field")
    elseif value isa Union{Ref,Ptr}
        return (path, type = T, reason = :reference_capture,
            hint = "pass immutable scalar data or declare device storage explicitly")
    elseif value isa Union{Space,Field,Relation}
        return (path, type = T, reason = :descriptor_capture,
            hint = "declare the descriptor as a Stage access instead of capturing it")
    elseif value isa Union{UUIDs.UUID,Val,NamedTuple}
        return (path, type = T, reason = :unsupported_capture,
            hint = "capture only concrete isbits scalar or tuple values")
    elseif !isconcretetype(T)
        return (path, type = T, reason = :nonconcrete_capture,
            hint = "use a concrete callable type")
    end
    # Immutable callable wrappers commonly become non-isbits because one of
    # their captures is not device-safe. Report that scientific capture rather
    # than stopping at the opaque wrapper type.
    if !ismutabletype(T)
        for index in 1:fieldcount(T)
            name = fieldname(T, index)
            rejected = _device_capture_rejection(getfield(value, index);
                path = (path..., name))
            rejected === nothing || return rejected
        end
    end
    if !isbitstype(T)
        return (path, type = T, reason = :mutable_or_nonisbits_capture,
            hint = "store mutable data in Fields and capture only immutable isbits values")
    elseif !_device_type_parameters(T)
        return (path, type = T, reason = :unsafe_type_parameter,
            hint = "use device-value type parameters and compile-time Symbol identities only")
    end
    return nothing
end

function _device_callable_rejection(value; path::Tuple)
    _has_call_methods(value) || return (
        path, type = typeof(value), reason = :not_callable,
        hint = "pass an ordinary callable struct or function")
    return _device_capture_rejection(value; path)
end

function _has_call_methods(value)
    return try
        !isempty(methods(value))
    catch
        false
    end
end

function _device_law_callable(value)
    T = typeof(value)
    isconcretetype(T) && isbitstype(T) && _has_call_methods(value) || return false
    # A zero-field function has no runtime capture to transport to a device.
    # Its typed body is still subjected to the ordinary closed-callable effect
    # analysis during planning, so restricting its defining module adds no
    # safety and rejects hygienic macro-generated callables unnecessarily.
    value isa Function && fieldcount(T) == 0 && return true
    return _device_evaluator_capture(value)
end

function Parameter(
        name::Symbol, ::Type{T}; bounds = nothing
    ) where {T}
    bounds = bounds === nothing ? _UnboundedParameter() :
        bounds isa Tuple && length(bounds) == 2 ?
            _ClosedParameterBounds(bounds[1], bounds[2]) : bounds
    isempty(String(name)) && throw(LocalMathValidationError(
        "a parameter name must be nonempty";
        stage = :construct, contract = :parameter_name,
    ))
    _device_parameter_type(T) || throw(LocalMathValidationError(
        "a parameter requires an admitted device-value type";
        stage = :construct, contract = :parameter_type,
        expected = :numeric_bool_enum_tuple_or_static_array, actual = T,
    ))
    bounds isa Union{_UnboundedParameter,_ClosedParameterBounds} || throw(
        LocalMathValidationError(
        "parameter bounds must be a closed package-owned law";
        stage = :construct, contract = :parameter_bounds,
        expected = Union{_UnboundedParameter,_ClosedParameterBounds},
        actual = typeof(bounds),
    ))
    bounds isa _ClosedParameterBounds && typeof(bounds.lower) !== T && throw(
        LocalMathValidationError(
            "parameter bounds must have the declared parameter type";
            stage = :construct, contract = :parameter_bounds_type,
            expected = T, actual = typeof(bounds.lower),
        )
    )
    return Parameter(
        _STAGE_MODEL_SEAL, T, name, bounds
    )
end

_parameter_type(::Parameter{T}) where {T} = T

"""Cold exact parameter declarations; names are values, never type keys."""
struct ParameterSchema{D<:Tuple}
    declarations::D
    function ParameterSchema(declarations::D) where {D<:Tuple}
        all(declaration -> declaration isa Parameter, declarations) ||
            throw(LocalMathValidationError(
                "ParameterSchema accepts only typed parameter declarations";
                stage = :construct, contract = :parameter_schema,
            ))
        names = map(declaration -> declaration.name, declarations)
        length(unique(names)) == length(names) || throw(
            LocalMathValidationError(
                "ParameterSchema contains a duplicate name";
                stage = :construct, contract = :parameter_schema_names,
                expected = :unique, actual = names,
            )
        )
        return new{D}(declarations)
    end
end

ParameterSchema() = ParameterSchema(())
ParameterSchema(declarations::Parameter...) =
    ParameterSchema(declarations)

"""Host-only positional submission metadata; parameter names remain values."""
struct _StageParameterSlot{T,B<:_ParameterBounds}
    name::Symbol
    bounds::B
end

struct _StageParameterLayout{S<:Tuple}
    slots::S
end

@inline _stage_parameter_slot(
        declaration::Parameter{T,B}) where {T,B} =
    _StageParameterSlot{T,B}(declaration.name, declaration.bounds)

_stage_parameter_layout(schema::ParameterSchema) =
    _StageParameterLayout(map(_stage_parameter_slot, schema.declarations))

@inline _stage_parameter_in_bounds(value, ::_UnboundedParameter) = true
@inline _stage_parameter_in_bounds(value, bounds::_ClosedParameterBounds) =
    bounds.lower <= value <= bounds.upper

function _merge_parameter_schemas(schemas::Tuple)
    merged = ()
    for schema in schemas
        schema isa ParameterSchema || throw(LocalMathValidationError(
            "parameter schema composition requires ParameterSchema values";
            stage = :construct, contract = :parameter_schema_composition,
        ))
        for declaration in schema.declarations
            position = findfirst(
                existing -> existing.name === declaration.name, merged
            )
            if position === nothing
                merged = (merged..., declaration)
            else
                existing = merged[position]
                typeof(existing) === typeof(declaration) &&
                    existing.bounds == declaration.bounds || throw(
                        LocalMathValidationError(
                            "repeated parameter declarations must agree exactly";
                            stage = :construct,
                            contract = :parameter_schema_composition,
                            expected = existing, actual = declaration,
                        )
                    )
            end
        end
    end
    return ParameterSchema(merged)
end

struct _ParameterSlot{N} end

"""`Evaluator(callable, parameters=())` declares one concrete isbits stage calculation."""
struct Evaluator{E,P<:Tuple}
    evaluator::E
    parameters::P
    function Evaluator(evaluator::E, parameters::P = ()) where {E,P<:Tuple}
        isconcretetype(E) && isbitstype(E) && _has_call_methods(evaluator) &&
            _device_evaluator_capture(evaluator) ||
            throw(LocalMathValidationError(
            "a stage evaluator must be one concrete structurally device-admissible callable value";
            stage = :construct, contract = :stage_evaluator,
            expected = :device_safe_callable,
            actual = _device_callable_rejection(evaluator;
                path = (:evaluator,)),
            hint = "move array or descriptor state into declared Stage accesses",
        ))
        ParameterSchema(parameters)
        return new{E,P}(evaluator, parameters)
    end
end

struct _StageEntryVersion end

_relation_ghost_space(::Any) = nothing
_relation_ghost_space(relation::Relation) =
    _relation_ghost_space(relation.representation)
_relation_ghost_space(representation::_BoundaryRelation) =
    _relation_ghost_space(representation.policy)
_relation_ghost_space(policy::GhostBoundary) = policy.ghost_space
_relation_ghost_space(representation::_MaskedRelation) =
    _relation_ghost_space(representation.base)
function _relation_ghost_space(representation::_SelectedRelation)
    _relation_ghost_space(representation.injection) === nothing || throw(
        LocalMathValidationError(
            "stage selection does not admit a ghost-boundary injection";
            stage = :construct, contract = :explicit_composite_halo_law,
        )
    )
    return _relation_ghost_space(representation.base)
end
function _relation_ghost_space(representation::_ProductRelation)
    any(factor -> _relation_ghost_space(factor) !== nothing,
        representation.factors) && throw(LocalMathValidationError(
        "a product Relation does not admit a ghost-boundary factor";
        stage = :construct, contract = :product_ghost_boundary,
        expected = :explicit_product_halo_law,
    ))
    return nothing
end
function _relation_ghost_space(representation::_ComposedRelation)
    any(factor -> _relation_ghost_space(factor) !== nothing,
        representation.factors) && throw(LocalMathValidationError(
        "composed ghost Relations require an explicit halo law";
        stage = :construct, contract = :composed_ghost_boundary,
        expected = :explicit_composed_halo_law,
    ))
    return nothing
end

abstract type _AccessMode end
struct _SampleAccess <: _AccessMode end
struct _RequiredAccess <: _AccessMode end

struct Access{F<:Field,R<:Relation,V,G,M<:_AccessMode}
    field::F
    relation::R
    version::V
    ghost::G
    mode::M
    function Access(
            field::F, relation::R, version::V, ghost::G, mode::M,
        ) where {F<:Field,R<:Relation,V,G,M<:_AccessMode}
        version isa _StageEntryVersion || throw(LocalMathValidationError(
            "Field access is admitted only at stage entry";
            stage = :construct, contract = :access_version,
            expected = _StageEntryVersion, actual = V,
        ))
        codomain(relation) == field.space || throw(LocalMathValidationError(
            "an access Relation must terminate at the accessed Field Space";
            stage = :construct, contract = :access_codomain,
            expected = field.space, actual = codomain(relation),
        ))
        ghost_space = _relation_ghost_space(relation)
        if ghost_space === nothing
            ghost === nothing || throw(LocalMathValidationError(
                "a ghost Field is valid only for a relation with a ghost boundary";
                stage = :construct, contract = :access_ghost,
                actual = typeof(ghost),
            ))
        else
            ghost isa Field && ghost.space == ghost_space &&
                eltype(ghost) === eltype(field) || throw(LocalMathValidationError(
                "a ghost-boundary access requires an explicit same-typed Field on its ghost Space";
                stage = :construct, contract = :access_ghost,
                expected = (ghost_space, eltype(field)),
                actual = ghost === nothing ? nothing : (ghost.space, eltype(ghost)),
            ))
        end
        return new{F,R,V,G,M}(field, relation, version, ghost, mode)
    end
end

"""
    Access(field, relation; ghost=nothing, required=true)

Declare a stage-entry read of `field` through `relation`. Required reads make a
missing endpoint a transaction failure. Pass `required=false` only when absence
is part of the numerical law; the evaluator then receives sample-aware values
whose lanes report whether an endpoint is present.

The relation must terminate at `field.space`. A `ghost` Field is accepted only
for a relation carrying a `GhostBoundary` policy.
"""
Access(field::Field, relation::Relation; ghost = nothing, required::Bool = true) =
    Access(field, relation, _StageEntryVersion(), ghost,
        required ? _RequiredAccess() : _SampleAccess())

abstract type _CollectionAccessLaw end

"""Read the dense group whose key is the current Stage item, with a hard occupancy bound."""
struct _BoundedGroup{K} <: _CollectionAccessLaw end
"""`BoundedGroup(maximum)` declares a static grouped-collection occupancy bound."""
function BoundedGroup(maximum::Integer)
    maximum isa Bool && throw(LocalMathValidationError(
        "a bounded Collection group requires an integer occupancy bound";
        stage = :construct, contract = :collection_group_bound, actual = maximum))
    1 <= maximum <= 32 || throw(LocalMathValidationError(
        "a bounded Collection group exceeds the reviewed static occupancy bound";
        stage = :construct, contract = :collection_group_bound,
        expected = 1:32, actual = maximum))
    return _BoundedGroup{Int(maximum)}()
end

"""Read one selected compacted position from the current producer item."""
struct _SourcePositionsAccess{K,L} <: _CollectionAccessLaw end

"""`CollectionAccess(collection, BoundedGroup(maximum))` reads one dense collection group."""
struct CollectionAccess{C,L<:_CollectionAccessLaw}
    collection::C
    law::L
end
function CollectionAccess(collection, law::_BoundedGroup)
    collection isa Collection || throw(LocalMathValidationError(
        "a Collection access requires a Collection descriptor";
        stage = :construct, contract = :collection_access_descriptor,
        expected = Collection, actual = typeof(collection)))
    return CollectionAccess{typeof(collection),typeof(law)}(collection, law)
end

"""
    SourcePositionAccess(collection, lane=1)

Read the retained compacted position for one static producer emission `lane`.
The producing `Collect` must request `persistent_source_position()`. Planning
resolves the producer's full emission width and rejects a lane outside it.
"""
function SourcePositionAccess(collection, lane::Integer = 1)
    collection isa Collection || throw(LocalMathValidationError(
        "a source-position access requires a Collection descriptor";
        stage = :construct, contract = :collection_access_descriptor,
        expected = Collection, actual = typeof(collection)))
    lane isa Bool && throw(LocalMathValidationError(
        "a source-position Collection access lane must be an integer";
        stage = :construct, contract = :collection_source_position_lane,
        actual = lane))
    1 <= lane <= 32 || throw(LocalMathValidationError(
        "a source-position Collection access exceeds the reviewed static lane bound";
        stage = :construct, contract = :collection_source_position_lane,
        expected = 1:32, actual = lane))
    L = Int(lane)
    return CollectionAccess{typeof(collection),_SourcePositionsAccess{0,L}}(
        collection, _SourcePositionsAccess{0,L}())
end

"""Device-resident live Collection count used as a Stage prefix."""
struct _CollectionCount{C}
    collection::C
end
"""`CollectionCount(collection)` uses the device-resident live record count as a stage prefix."""
function CollectionCount(collection)
    collection isa Collection || throw(LocalMathValidationError(
        "a Collection count requires a Collection descriptor";
        stage = :construct, contract = :collection_count_descriptor,
        expected = Collection, actual = typeof(collection)))
    return _CollectionCount(collection)
end

struct _NoPrefix end
struct _ParameterPrefix{D<:Parameter}
    parameter::D
end
struct _FieldPrefix{F<:Field}
    field::F
    function _FieldPrefix(field::F) where {F<:Field}
        length(field.space) == 1 && eltype(field) <: Integer &&
            eltype(field) !== Bool || throw(LocalMathValidationError(
                "a Field prefix requires one singleton non-Bool integer Field";
                stage = :construct, contract = :field_prefix,
                actual = (size(field.space), eltype(field)),
            ))
        return new{F}(field)
    end
end

struct _NoMask end
struct _MaskSelection{F<:Field}
    field::F
    function _MaskSelection(field::F) where {F<:Field}
        eltype(field) === Bool || throw(LocalMathValidationError(
            "a mask selection requires a Boolean Field";
            stage = :construct, contract = :mask_selection,
            expected = Bool, actual = eltype(field),
        ))
        return new{F}(field)
    end
end

struct _NoSubset end
struct _SubsetSelection{R<:Relation}
    relation::R
    function _SubsetSelection(relation::R) where {R<:Relation}
        degree_bound(relation) == 1 || throw(LocalMathValidationError(
            "a subset selection must be unary identity-or-absent";
            stage = :construct, contract = :subset_degree,
            expected = 1, actual = degree_bound(relation),
        ))
        _identity_or_absent_relation(relation) || throw(
            LocalMathValidationError(
                "a subset selection must preserve source identity when present";
                stage = :construct, contract = :subset_identity,
                actual = typeof(relation.representation),
            )
        )
        return new{R}(relation)
    end
end

_identity_or_absent_relation(relation::Relation{_IdentityRelation}) = true
_identity_or_absent_relation(relation::Relation{<:_MaskedRelation}) =
    _identity_or_absent_relation(relation.representation.base)
_identity_or_absent_relation(::Relation) = false

struct _NoGate end
struct _ParameterGate{D<:Parameter}
    parameter::D
    function _ParameterGate(parameter::D) where {D<:Parameter}
        _parameter_type(parameter) === Bool || throw(LocalMathValidationError(
            "a parameter gate requires a Boolean parameter";
            stage = :construct, contract = :parameter_gate,
            expected = Bool, actual = _parameter_type(parameter),
        ))
        return new{D}(parameter)
    end
end
struct _FieldGate{F<:Field}
    field::F
    function _FieldGate(field::F) where {F<:Field}
        length(field.space) == 1 && eltype(field) === Bool || throw(
            LocalMathValidationError(
                "a Field gate requires one singleton Boolean Field";
                stage = :construct, contract = :field_gate,
                actual = (size(field.space), eltype(field)),
            )
        )
        return new{F}(field)
    end
end

"""`Control(; prefix=nothing, mask=nothing, subset=nothing, gate=nothing)` limits stage participation."""
struct Control{P,M,S,G}
    prefix::P
    mask::M
    subset::S
    gate::G
    function Control(prefix::P, mask::M, subset::S, gate::G) where {P,M,S,G}
        prefix isa Union{_NoPrefix,_ParameterPrefix,_FieldPrefix,_CollectionCount} || throw(
            LocalMathValidationError("invalid Control prefix";
                stage = :construct, contract = :control_prefix, actual = P)
        )
        mask isa Union{_NoMask,_MaskSelection} || throw(
            LocalMathValidationError("invalid Control mask";
                stage = :construct, contract = :control_mask, actual = M)
        )
        subset isa Union{_NoSubset,_SubsetSelection} || throw(
            LocalMathValidationError("invalid Control subset";
                stage = :construct, contract = :control_subset, actual = S)
        )
        gate isa Union{_NoGate,_ParameterGate,_FieldGate} || throw(
            LocalMathValidationError("invalid Control gate";
                stage = :construct, contract = :control_gate, actual = G)
        )
        return new{P,M,S,G}(prefix, mask, subset, gate)
    end
end

_control_prefix(value::_NoPrefix) = value
_control_prefix(value::Union{_ParameterPrefix,_FieldPrefix,_CollectionCount}) = value
_control_prefix(::Nothing) = _NoPrefix()
_control_prefix(value::Parameter) = _ParameterPrefix(value)
_control_prefix(value::Field) = _FieldPrefix(value)
_control_mask(value::_NoMask) = value
_control_mask(value::_MaskSelection) = value
_control_mask(::Nothing) = _NoMask()
_control_mask(value::Field) = _MaskSelection(value)
_control_subset(value::_NoSubset) = value
_control_subset(value::_SubsetSelection) = value
_control_subset(::Nothing) = _NoSubset()
_control_subset(value::Relation) = _SubsetSelection(value)
_control_gate(value::Union{_NoGate,_ParameterGate,_FieldGate}) = value
_control_gate(::Nothing) = _NoGate()
_control_gate(value::Parameter) = _ParameterGate(value)
_control_gate(value::Field) = _FieldGate(value)

Control(; prefix = nothing, mask = nothing, subset = nothing, gate = nothing) =
    Control(_control_prefix(prefix), _control_mask(mask),
        _control_subset(subset), _control_gate(gate))

abstract type _PublicationComponentRole end
"""`PublicationValue(name)` selects a named field from an evaluator result."""
struct PublicationValue{Name} <: _PublicationComponentRole
    function PublicationValue(
            seal::_StageModelSeal, ::Val{Name}
        ) where {Name}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        Name isa Symbol || throw(LocalMathValidationError(
            "an evaluator value label must be a Symbol";
            stage = :construct, contract = :publication_value_label,
            actual = Name,
        ))
        return new{Name}()
    end
end

"""Cold identity and capacity of one bounded finite-sequence result."""
struct Collection{T}
    capacity::Int32
    id::UUIDs.UUID
    function Collection(
            ::Type{T}, capacity::Integer;
            id::UUIDs.UUID = _new_semantic_identity(),
        ) where {T}
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a Collection requires an admitted storage value type";
            stage = :construct, contract = :collection_value_type, actual = T,
        ))
        capacity isa Bool && throw(LocalMathValidationError(
            "a Collection capacity must be an integer";
            stage = :construct, contract = :collection_capacity,
            actual = capacity,
        ))
        0 <= capacity < typemax(Int32) || throw(LocalMathValidationError(
            "a Collection capacity must fit below the reserved Int32 terminal";
            stage = :construct, contract = :collection_capacity,
            expected = 0:(typemax(Int32) - 1), actual = capacity,
        ))
        return new{T}(Int32(capacity), id)
    end
end
Base.eltype(::Type{Collection{T}}) where {T} = T
Base.eltype(::Collection{T}) where {T} = T
semantic_identity(collection::Collection) = collection.id

_control_prefix(value::Collection) = _CollectionCount(value)

"""`CollectionPublication(collection, role)` publishes a named result to bounded compacted storage."""
struct CollectionPublication{S<:Collection,Q<:_PublicationComponentRole}
    collection::S
    role::Q
end

"""`FoldPublication(role)` connects a named result to an `OrderedFold`."""
struct FoldPublication{Q<:_PublicationComponentRole}
    role::Q
end
function PublicationValue(label::Symbol)
        isempty(String(label)) && throw(LocalMathValidationError(
            "an evaluator value label must be nonempty";
            stage = :construct, contract = :publication_value_label,
        ))
    return PublicationValue(_STAGE_MODEL_SEAL, Val(label))
end
_evaluator_value_name(::PublicationValue{Name}) where {Name} = Name

"""`FieldPublication(field, relation, role)` routes a named result into a Field."""
struct FieldPublication{F<:Field,R<:Relation,Q<:_PublicationComponentRole}
    field::F
    relation::R
    role::Q
    function FieldPublication(
            field::F, relation::R, role::Q
        ) where {F<:Field,R<:Relation,Q<:_PublicationComponentRole}
        codomain(relation) == field.space || throw(LocalMathValidationError(
            "a publication Relation must terminate at its component Field Space";
            stage = :construct, contract = :publication_codomain,
            expected = field.space, actual = codomain(relation),
        ))
        return new{F,R,Q}(field, relation, role)
    end
end

"""`TotalCoverage()` requires every destination to be written."""
struct TotalCoverage end
"""`PartialCoverage()` permits destinations with no candidate."""
struct PartialCoverage end
"""`UnreachableEmpty()` makes an empty destination a validation failure."""
struct UnreachableEmpty end
"""`PreserveEmpty()` keeps the stage-entry destination value when no candidate participates."""
struct PreserveEmpty end
"""`FillEmpty(value)` writes `value` when no candidate participates."""
struct FillEmpty{T}
    value::T
    function FillEmpty(seal::_StageModelSeal, value::T) where {T}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a Unique fill value must use an admitted storage type";
            stage = :construct, contract = :unique_fill_type, actual = T,
        ))
        return new{T}(value)
    end
end
FillEmpty(value) = FillEmpty(_STAGE_MODEL_SEAL, value)

"""`RejectOverflow()` fails a collection publication rather than truncating it."""
struct RejectOverflow end
"""`EmptyCollection()` publishes a valid empty compacted sequence."""
struct EmptyCollection end
"""`CollectedValue(record, participates=true)` supplies one Collect record."""
struct CollectedValue{T}
    value::T
    participates::Bool
    function CollectedValue(value::T, participates::Bool = true) where {T}
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a collected value requires an admitted storage type";
            stage = :construct, contract = :collect_result_type, actual = T,
        ))
        return new{T}(value, participates)
    end
end
"""`GroupedCollectedValue(group, record, participates=true)` supplies one keyed Collect record."""
struct GroupedCollectedValue{K,T}
    key::K
    value::T
    participates::Bool
    function GroupedCollectedValue(
            key::K, value::T, participates::Bool = true,
        ) where {K,T}
        K === Int32 || throw(LocalMathValidationError(
            "a keyed Collect group must be exactly Int32";
            stage = :construct, contract = :collect_group_key_type,
            expected = Int32, actual = K))
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a keyed collected value requires an admitted storage type";
            stage = :construct, contract = :collect_result_type, actual = T))
        return new{K,T}(key, value, participates)
    end
end

"""`FoldValue(value, participates=true)` supplies one ordered recurrence value."""
struct FoldValue{T}
    value::T
    participates::Bool
    function FoldValue(value::T, participates::Bool = true) where {T}
        _storage_value_type(T) || throw(LocalMathValidationError(
            "an ordered-fold value requires an admitted storage type";
            stage = :construct, contract = :ordered_fold_result_type,
            actual = T,
        ))
        return new{T}(value, participates)
    end
end

"""
    Collect(T; maximum=1, groups=one_group(), order=source_order(), projection omitted)

Declare a bounded compacted sequence. Pass `persistent_source_position()` when
a later stage requires retained source positions.
"""
struct Collect{T,K,G,O,P,V,E}
    groups::G
    order::O
    projection::P
    overflow::V
    onempty::E
    function Collect(
            seal::_StageModelSeal, ::Type{T}, ::Val{K}, groups::G, order::O,
            projection::P, overflow::V, onempty::E,
        ) where {T,K,G,O,P,V,E}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        _storage_value_type(T) || throw(LocalMathValidationError(
            "Collect values require an admitted storage type";
            stage = :construct, contract = :collect_value_type, actual = T,
        ))
        1 <= K <= 32 || throw(LocalMathValidationError(
            "Collect emission width must be a reviewed small static bound";
            stage = :construct, contract = :collect_emission_width,
            expected = 1:32, actual = K,
        ))
        groups isa Union{_OneGroup,_GroupBy,_RoutedGroups} || throw(LocalMathValidationError(
            "Collect requires one group, value-derived groups, or explicit dense routed groups";
            stage = :construct, contract = :collect_groups, actual = G,
        ))
        order isa Union{_SourceOrder,_CanonicalBy} || throw(
            LocalMathValidationError(
                "Collect requires source_order or canonical_by semantics";
                stage = :construct, contract = :collect_order, actual = O,
            ))
        projection isa Union{
            _NoPersistentProjection,_PersistentSourcePosition} || throw(
            LocalMathValidationError(
                "Collect projection is closed to none or source position";
                stage = :construct, contract = :collect_projection,
                actual = P,
            ))
        overflow isa RejectOverflow || throw(LocalMathValidationError(
            "Collect currently requires deterministic overflow rejection";
            stage = :construct, contract = :collect_overflow, actual = V,
        ))
        onempty isa EmptyCollection || throw(LocalMathValidationError(
            "Collect empty input must publish the valid empty sequence";
            stage = :construct, contract = :collect_empty, actual = E,
        ))
        return new{T,K,G,O,P,V,E}(
            groups, order, projection, overflow, onempty)
    end
end

function Collect(
        ::Type{T}; maximum::Integer = 1, groups = _OneGroup(),
        order = _SourceOrder(), projection = _NoPersistentProjection(),
        overflow = RejectOverflow(), onempty = EmptyCollection(),
    ) where {T}
    maximum isa Bool && throw(LocalMathValidationError(
        "Collect emission width must be an integer";
        stage = :construct, contract = :collect_emission_width,
        actual = maximum,
    ))
    return Collect(_STAGE_MODEL_SEAL, T, Val(Int(maximum)), groups,
        order, projection, overflow, onempty)
end


"""`OrderedFold(T, state, transition; order=source_order())` declares a finite ordered recurrence."""
struct OrderedFold{T,A,F,O}
    state::A
    transition::F
    order::O
    function OrderedFold(
            seal::_StageModelSeal, ::Type{T}, state::A, transition::F,
            order::O,
        ) where {T,A,F,O}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        _storage_value_type(T) || throw(LocalMathValidationError(
            "OrderedFold values require an admitted storage type";
            stage = :construct, contract = :ordered_fold_value_type,
            actual = T,
        ))
        state isa InitializedState || throw(LocalMathValidationError(
            "OrderedFold requires one typed Field state";
            stage = :construct, contract = :ordered_fold_state, actual = A,
        ))
        _device_law_callable(transition) || throw(LocalMathValidationError(
            "OrderedFold transition must be a concrete device-admissible callable";
            stage = :construct, contract = :ordered_fold_transition,
            actual = _device_callable_rejection(transition;
                path = (:ordered_fold, :transition)),
        ))
        order isa Union{_SourceOrder,_CanonicalBy} || throw(
            LocalMathValidationError(
                "OrderedFold requires source_order or canonical_by semantics";
                stage = :construct, contract = :ordered_fold_order,
                actual = O,
            ))
        return new{T,A,F,O}(state, transition, order)
    end
end
OrderedFold(::Type{T}, state::InitializedState, transition;
        order = _SourceOrder()) where {T} =
    OrderedFold(_STAGE_MODEL_SEAL, T, state, transition, order)

"""`UniqueValue(value)` supplies one unconditional Unique value."""
struct UniqueValue{T}
    value::T
    function UniqueValue(value::T) where {T}
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a Unique result value must use an admitted storage type";
            stage = :construct, contract = :unique_result_type, actual = T,
        ))
        return new{T}(value)
    end
end
"""`ConditionalUniqueValue(value, participates)` conditionally supplies a Unique value."""
struct ConditionalUniqueValue{T}
    value::T
    participates::Bool
    function ConditionalUniqueValue(value::T, participates::Bool) where {T}
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a Unique result value must use an admitted storage type";
            stage = :construct, contract = :unique_result_type, actual = T,
        ))
        return new{T}(value, participates)
    end
end

"""`RoutedUniqueValue(key, value)` supplies one runtime-routed Unique value."""
struct RoutedUniqueValue{K,T}
    key::K
    value::T
    function RoutedUniqueValue(key::K, value::T) where {K,T}
        K in (Int32, UInt32) || throw(LocalMathValidationError(
            "a routed Unique key must be Int32 or UInt32";
            stage = :construct, contract = :runtime_relation_key_type,
            expected = (Int32, UInt32), actual = K,
        ))
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a routed Unique value requires an admitted storage type";
            stage = :construct, contract = :unique_result_type, actual = T,
        ))
        return new{K,T}(key, value)
    end
end
"""`ConditionalRoutedUniqueValue(key, value, participates)` conditionally supplies a routed Unique value."""
struct ConditionalRoutedUniqueValue{K,T}
    key::K
    value::T
    participates::Bool
    function ConditionalRoutedUniqueValue(
            key::K, value::T, participates::Bool,
        ) where {K,T}
        K in (Int32, UInt32) || throw(LocalMathValidationError(
            "a routed Unique key must be Int32 or UInt32";
            stage = :construct, contract = :runtime_relation_key_type,
            expected = (Int32, UInt32), actual = K,
        ))
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a routed Unique value requires an admitted storage type";
            stage = :construct, contract = :unique_result_type, actual = T,
        ))
        return new{K,T}(key, value, participates)
    end
end

"""`Unique(T; maximum=1, coverage=TotalCoverage(), onempty=UnreachableEmpty())` rejects conflicts."""
struct Unique{T,K,C,E}
    coverage::C
    onempty::E
    function Unique(
            seal::_StageModelSeal, ::Type{T}, ::Val{K}, coverage::C, onempty::E
        ) where {T,K,C,E}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        _storage_value_type(T) || throw(LocalMathValidationError(
            "Unique values require an admitted storage value type";
            stage = :construct, contract = :unique_value_type, actual = T,
        ))
        1 <= K <= 32 || throw(LocalMathValidationError(
            "Unique emission width must be a reviewed small static bound";
            stage = :construct, contract = :unique_emission_width,
            expected = 1:32, actual = K,
        ))
        valid_empty = coverage isa TotalCoverage ?
            onempty isa UnreachableEmpty :
            coverage isa PartialCoverage &&
                (onempty isa PreserveEmpty ||
                 (onempty isa FillEmpty && typeof(onempty.value) === T))
        valid_empty || throw(LocalMathValidationError(
            "Unique coverage and empty behavior are incoherent";
            stage = :construct, contract = :unique_empty_law,
            actual = (coverage, onempty),
        ))
        return new{T,K,C,E}(coverage, onempty)
    end
end

function Unique(
        ::Type{T}; maximum::Integer = 1,
        coverage = TotalCoverage(), onempty = UnreachableEmpty(),
    ) where {T}
    maximum isa Bool && throw(LocalMathValidationError(
        "Unique emission width must be an integer";
        stage = :construct, contract = :unique_emission_width,
        actual = maximum,
    ))
    1 <= maximum <= 32 || throw(LocalMathValidationError(
        "Unique emission width must be a reviewed small static bound";
        stage = :construct, contract = :unique_emission_width,
        expected = 1:32, actual = maximum,
    ))
    return Unique(
        _STAGE_MODEL_SEAL, T, Val(Int(maximum)), coverage, onempty
    )
end

"""`Contribution(value, participates=true)` supplies one deterministic Reduce contribution."""
struct Contribution{T}
    value::T
    participates::Bool
    function Contribution(value::T, participates::Bool = true) where {T}
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a Reduce contribution requires an admitted storage value type";
            stage = :construct, contract = :reduce_result_type, actual = T,
        ))
        return new{T}(value, participates)
    end
end

"""`RoutedContribution(key, value, participates=true)` supplies one routed Reduce contribution."""
struct RoutedContribution{K,T}
    key::K
    value::T
    participates::Bool
    function RoutedContribution(
            key::K, value::T, participates::Bool = true,
        ) where {K,T}
        K in (Int32, UInt32) || throw(LocalMathValidationError(
            "a routed Reduce key must be Int32 or UInt32";
            stage = :construct, contract = :runtime_relation_key_type,
            expected = (Int32, UInt32), actual = K,
        ))
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a routed Reduce contribution requires an admitted storage type";
            stage = :construct, contract = :reduce_result_type, actual = T,
        ))
        return new{K,T}(key, value, participates)
    end
end

"""`IdentitySeed(value)` initializes a reduction from a mathematical identity."""
struct IdentitySeed{T}
    value::T
    function IdentitySeed(value::T) where {T}
        _storage_value_type(T) || throw(LocalMathValidationError(
            "a Reduce identity requires an admitted storage value type";
            stage = :construct, contract = :reduce_seed_type, actual = T,
        ))
        return new{T}(value)
    end
end
"""`ExistingSeed()` initializes a reduction from the stage-entry destination value."""
struct ExistingSeed end
"""Left-associated seed then participating candidates in (source item, Relation lane) order."""
struct CanonicalLeftFold end
"""Explicitly permits the planner's centrally qualified atomic reassociation."""
struct RelaxedAtomic end

"""`Reduce(T, operation; maximum, seed, order)` declares an explicitly initialized fold."""
struct Reduce{T,K,F,S,O}
    operation::F
    seed::S
    order::O
    function Reduce(
            seal::_StageModelSeal, ::Type{T}, ::Val{K}, operation::F,
            seed::S, order::O,
        ) where {T,K,F,S,O}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        _storage_value_type(T) || throw(LocalMathValidationError(
            "Reduce values require an admitted storage value type";
            stage = :construct, contract = :reduce_value_type, actual = T,
        ))
        1 <= K <= 32 || throw(LocalMathValidationError(
            "Reduce emission width must be a reviewed small static bound";
            stage = :construct, contract = :reduce_emission_width,
            expected = 1:32, actual = K,
        ))
        seed isa ExistingSeed ||
            (seed isa IdentitySeed && typeof(seed.value) === T) || throw(
                LocalMathValidationError(
                    "Reduce seed must be Existing or an exact-typed identity";
                    stage = :construct, contract = :reduce_seed,
                    expected = T, actual = typeof(seed),
                )
            )
        order isa Union{CanonicalLeftFold,RelaxedAtomic} || throw(
            LocalMathValidationError(
                "Reduce requires an explicit canonical or relaxed order law";
                stage = :construct, contract = :reduce_order,
                actual = typeof(order),
            )
        )
        _device_law_callable(operation) || throw(LocalMathValidationError(
            "Reduce operation must be one concrete structurally device-admissible callable";
            stage = :construct, contract = :reduce_operation,
            actual = _device_callable_rejection(operation;
                path = (:reduce, :operation)),
        ))
        return new{T,K,F,S,O}(operation, seed, order)
    end
end

"""`ArgMin()` selects the smallest Resolve rank."""
struct ArgMin end
"""`ArgMax()` selects the largest Resolve rank."""
struct ArgMax end
struct _CanonicalOrdinal end
_storage_value_type(::Type{_CanonicalOrdinal}) = true
"""Tie by the canonical item-major, lane-minor candidate ordinal."""
struct CanonicalSourceLaneTie end
"""`TieMin{T}()` selects the smallest bounded tie after equal ranks."""
struct TieMin{I} end
"""`TieMax{T}()` selects the largest bounded tie after equal ranks."""
struct TieMax{I} end

_resolve_tie_type(::CanonicalSourceLaneTie) = _CanonicalOrdinal
_resolve_tie_type(::TieMin{I}) where {I} = I
_resolve_tie_type(::TieMax{I}) where {I} = I

"""`ResolutionValue(rank, tie, payload, participates=true)` supplies one Resolve candidate."""
struct ResolutionValue{R,I,T}
    rank::R
    tie::I
    value::T
    participates::Bool
    function ResolutionValue(
            rank::R, tie::I, value::T, participates::Bool = true,
        ) where {R,I,T}
        _storage_value_type(R) && _storage_value_type(I) &&
            _storage_value_type(T) || throw(
            LocalMathValidationError(
                "a Resolve candidate requires admitted rank, tie, and value types";
                stage = :construct, contract = :resolve_result_type,
                actual = (R, I, T),
            )
        )
        _qualified_rank_shape(R) &&
            (I === _CanonicalOrdinal || _qualified_rank_shape(I)) || throw(
                LocalMathValidationError(
                    "Resolve rank and explicit tie types require a total qualified shape";
                    stage = :construct, contract = :resolve_order_shape,
                    expected = :qualified_total_order_shape,
                    actual = (R, I),
                )
            )
        return new{R,I,T}(rank, tie, value, participates)
    end
end
ResolutionValue(rank::R, value::T, participates::Bool = true) where {R,T} =
    ResolutionValue(rank, _CanonicalOrdinal(), value, participates)

"""`RoutedResolutionValue(key, rank, tie, payload, participates=true)` supplies one routed Resolve candidate."""
struct RoutedResolutionValue{K,R,I,T}
    key::K
    rank::R
    tie::I
    value::T
    participates::Bool
    function RoutedResolutionValue(
            key::K, rank::R, tie::I, value::T,
            participates::Bool = true,
        ) where {K,R,I,T}
        K in (Int32, UInt32) || throw(LocalMathValidationError(
            "a routed Resolve key must be Int32 or UInt32";
            stage = :construct, contract = :runtime_relation_key_type,
            expected = (Int32, UInt32), actual = K,
        ))
        _storage_value_type(R) && _storage_value_type(I) &&
            _storage_value_type(T) || throw(LocalMathValidationError(
                "a routed Resolve candidate requires admitted rank, tie, and value types";
                stage = :construct, contract = :resolve_result_type,
                actual = (R, I, T),
            ))
        _qualified_rank_shape(R) &&
            (I === _CanonicalOrdinal || _qualified_rank_shape(I)) || throw(
                LocalMathValidationError(
                    "routed Resolve rank and tie require qualified total shapes";
                    stage = :construct, contract = :resolve_order_shape,
                    actual = (R, I),
                )
            )
        return new{K,R,I,T}(key, rank, tie, value, participates)
    end
end
RoutedResolutionValue(
        key::K, rank::R, value::T, participates::Bool = true,
    ) where {K,R,T} = RoutedResolutionValue(
        key, rank, _CanonicalOrdinal(), value, participates)

"""`Resolve(rank_type, value_type; maximum, direction, tie, lower, upper, onempty)` selects one bounded candidate."""
struct Resolve{R,I,T,K,D,L,E}
    direction::D
    tie::L
    lower::R
    upper::R
    onempty::E
    function Resolve(
            seal::_StageModelSeal, ::Type{R}, ::Type{I}, ::Type{T}, ::Val{K},
            direction::D, tie::L,
            lower::R, upper::R, onempty::E,
        ) where {R,I,T,K,D,L,E}
        seal === _STAGE_MODEL_SEAL || error("invalid stage-model seal")
        _storage_value_type(R) && _storage_value_type(I) &&
            _storage_value_type(T) || throw(
            LocalMathValidationError(
                "Resolve requires admitted rank and payload types";
                stage = :construct, contract = :resolve_value_type,
                actual = (R, I, T),
                )
            )
        _qualified_rank_shape(R) &&
            (I === _CanonicalOrdinal || _qualified_rank_shape(I)) || throw(
                LocalMathValidationError(
                    "Resolve rank and explicit tie types require a total qualified shape";
                    stage = :construct, contract = :resolve_order_shape,
                    expected = :qualified_total_order_shape,
                    actual = (R, I),
                )
            )
        1 <= K <= 32 || throw(LocalMathValidationError(
            "Resolve emission width must be a reviewed small static bound";
            stage = :construct, contract = :resolve_emission_width,
            expected = 1:32, actual = K,
        ))
        direction isa Union{ArgMin,ArgMax} || throw(
            LocalMathValidationError(
                "Resolve requires an explicit ArgMin or ArgMax law";
                stage = :construct, contract = :resolve_direction,
                actual = typeof(direction),
            )
        )
        ordered_bounds = try
            !isless(upper, lower)
        catch
            false
        end
        ordered_bounds || throw(LocalMathValidationError(
            "Resolve rank bounds must form a closed ordered interval";
            stage = :construct, contract = :resolve_rank_bounds,
            expected = :lower_not_greater_than_upper,
            actual = (lower, upper),
        ))
        onempty isa PreserveEmpty ||
            (onempty isa FillEmpty && typeof(onempty.value) === T) || throw(
                LocalMathValidationError(
                    "Resolve empty behavior must preserve or fill the payload type";
                    stage = :construct, contract = :resolve_empty,
                    expected = T, actual = typeof(onempty),
                )
            )
        return new{R,I,T,K,D,L,E}(direction, tie, lower, upper, onempty)
    end
end

function Resolve(
        ::Type{R}, ::Type{T}; maximum::Integer = 1,
        direction = ArgMin(), tie = CanonicalSourceLaneTie(),
        lower::R, upper::R, onempty = PreserveEmpty(),
    ) where {R,T}
    maximum isa Bool && throw(LocalMathValidationError(
        "Resolve emission width must be an integer";
        stage = :construct, contract = :resolve_emission_width,
        actual = maximum,
    ))
    1 <= maximum <= 32 || throw(LocalMathValidationError(
        "Resolve emission width must be a reviewed small static bound";
        stage = :construct, contract = :resolve_emission_width,
        expected = 1:32, actual = maximum,
    ))
    tie isa Union{CanonicalSourceLaneTie,TieMin,TieMax} || throw(
        LocalMathValidationError(
        "Resolve requires a canonical or explicit total tie law";
        stage = :construct, contract = :resolve_tie,
        actual = typeof(tie),
    ))
    I = _resolve_tie_type(tie)
    return Resolve(_STAGE_MODEL_SEAL, R, I, T, Val(Int(maximum)),
        direction, tie, lower, upper, onempty)
end

function Reduce(
        ::Type{T}, operation;
        maximum::Integer = 1,
        seed,
        order = CanonicalLeftFold(),
    ) where {T}
    maximum isa Bool && throw(LocalMathValidationError(
        "Reduce emission width must be an integer";
        stage = :construct, contract = :reduce_emission_width,
        actual = maximum,
    ))
    1 <= maximum <= 32 || throw(LocalMathValidationError(
        "Reduce emission width must be a reviewed small static bound";
        stage = :construct, contract = :reduce_emission_width,
        expected = 1:32, actual = maximum,
    ))
    return Reduce(
        _STAGE_MODEL_SEAL, T, Val(Int(maximum)), operation, seed, order,
    )
end

_unique_value_type(::Unique{T}) where {T} = T
_unique_width(::Unique{T,K}) where {T,K} = K
_publication_value_type(::Unique{T}) where {T} = T
_publication_value_type(::Reduce{T}) where {T} = T
_publication_value_type(::Resolve{R,I,T}) where {R,I,T} = T
_publication_value_type(::Collect{T}) where {T} = T
_publication_value_type(::OrderedFold{T}) where {T} = T
_publication_width(::Unique{T,K}) where {T,K} = K
_publication_width(::Reduce{T,K}) where {T,K} = K
_publication_width(::Resolve{R,I,T,K}) where {R,I,T,K} = K
_publication_width(::Collect{T,K}) where {T,K} = K
_publication_width(::OrderedFold) = 1

_unique_relation_admitted(::Union{
    _IdentityRelation,_AffineRelation,_FixedRelation,_ProductRelation,
    _ComposedRelation,
    _BoundaryRelation,_MaskedRelation,_SelectedRelation,_InverseRelation,
    _PackedRelation,_RuntimeRelation,_FieldIndexRelation,
}) = true
_unique_relation_admitted(_) = false

_runtime_relation_key_type(::Relation{<:_RuntimeRelation{K}}) where {K} = K
_runtime_relation_key_type(::Relation) = nothing

function _validate_publication(components::Tuple, law::Unique)
    length(components) == 1 &&
        only(components).role isa PublicationValue || throw(
            LocalMathValidationError(
                "Unique owns exactly one evaluator-fed value component";
                stage = :construct, contract = :unique_components,
            )
        )
    _unique_relation_admitted(only(components).relation.representation) ||
        throw(LocalMathValidationError(
            "Unique admits only structurally addressed Relations";
            stage = :construct, contract = :unique_relation,
            actual = typeof(only(components).relation.representation),
        ))
    _relation_ghost_space(only(components).relation) === nothing || throw(
        LocalMathValidationError(
            "Unique does not publish into a ghost boundary";
            stage = :construct, contract = :unique_ghost_publication,
        )
    )
    _unique_width(law) == degree_bound(only(components).relation) || throw(
        LocalMathValidationError(
            "Unique result lanes must map exactly to the publication Relation lanes";
            stage = :construct, contract = :unique_relation_degree,
            expected = degree_bound(only(components).relation),
            actual = _unique_width(law),
        )
    )
    eltype(only(components).field) === _unique_value_type(law) || throw(
        LocalMathValidationError(
            "Unique value type must equal its destination Field type";
            stage = :construct, contract = :unique_component_type,
            expected = _unique_value_type(law),
            actual = eltype(only(components).field),
        )
    )
    return nothing
end

function _validate_publication(components::Tuple, law::Reduce)
    length(components) == 1 &&
        only(components).role isa PublicationValue || throw(
            LocalMathValidationError(
                "Reduce owns exactly one evaluator-fed contribution component";
                stage = :construct, contract = :reduce_components,
            )
        )
    _unique_relation_admitted(only(components).relation.representation) ||
        throw(LocalMathValidationError(
            "Reduce admits only structurally addressed Relations";
            stage = :construct, contract = :reduce_relation,
            actual = typeof(only(components).relation.representation),
        ))
    _relation_ghost_space(only(components).relation) === nothing || throw(
        LocalMathValidationError(
            "Reduce does not publish into a ghost boundary";
            stage = :construct, contract = :reduce_ghost_publication,
        )
    )
    _publication_width(law) == degree_bound(only(components).relation) || throw(
        LocalMathValidationError(
            "Reduce result lanes must map exactly to Relation lanes";
            stage = :construct, contract = :reduce_relation_degree,
            expected = degree_bound(only(components).relation),
            actual = _publication_width(law),
        )
    )
    eltype(only(components).field) === _publication_value_type(law) || throw(
        LocalMathValidationError(
            "Reduce value type must equal its destination Field type";
            stage = :construct, contract = :reduce_component_type,
            expected = _publication_value_type(law),
            actual = eltype(only(components).field),
        )
    )
    return nothing
end

function _validate_publication(components::Tuple, law::Resolve)
    length(components) == 1 &&
        only(components).role isa PublicationValue || throw(
            LocalMathValidationError(
                "Resolve owns exactly one evaluator-fed candidate component";
                stage = :construct, contract = :resolve_components,
            )
        )
    _unique_relation_admitted(only(components).relation.representation) ||
        throw(LocalMathValidationError(
            "Resolve admits only structurally addressed Relations";
            stage = :construct, contract = :resolve_relation,
            actual = typeof(only(components).relation.representation),
        ))
    _relation_ghost_space(only(components).relation) === nothing || throw(
        LocalMathValidationError(
            "Resolve does not publish into a ghost boundary";
            stage = :construct, contract = :resolve_ghost_publication,
        )
    )
    _publication_width(law) == degree_bound(only(components).relation) || throw(
        LocalMathValidationError(
            "Resolve candidate lanes must map exactly to Relation lanes";
            stage = :construct, contract = :resolve_relation_degree,
            expected = degree_bound(only(components).relation),
            actual = _publication_width(law),
        )
    )
    eltype(only(components).field) === _publication_value_type(law) || throw(
        LocalMathValidationError(
            "Resolve payload type must equal its destination Field type";
            stage = :construct, contract = :resolve_component_type,
            expected = _publication_value_type(law),
            actual = eltype(only(components).field),
        )
    )
    return nothing
end

function _validate_publication(components::Tuple, law::Collect)
    length(components) == 1 &&
        only(components) isa CollectionPublication &&
        only(components).role isa PublicationValue || throw(
            LocalMathValidationError(
                "Collect owns exactly one evaluator-fed Collection component";
                stage = :construct, contract = :collect_components,
            ))
    eltype(only(components).collection) === _publication_value_type(law) ||
        throw(LocalMathValidationError(
            "Collect value type must equal its Collection element type";
            stage = :construct, contract = :collect_component_type,
            expected = _publication_value_type(law),
            actual = eltype(only(components).collection),
        ))
    return nothing
end

function _validate_publication(components::Tuple, law::OrderedFold)
    length(components) == 1 &&
        only(components) isa FoldPublication &&
        only(components).role isa PublicationValue || throw(
            LocalMathValidationError(
                "OrderedFold owns exactly one evaluator-fed recurrence component";
                stage = :construct, contract = :ordered_fold_components,
            ))
    return nothing
end

function _validate_publication(components::Tuple, law)
    throw(LocalMathValidationError(
        "Publication uses an unsupported mathematical law";
        stage = :construct, contract = :publication_law,
        actual = typeof(law),
    ))
end

"""`Publication(components, law, origin)` attaches destinations to one publication law."""
struct Publication{C<:Tuple,L}
    components::C
    law::L
    origin::SourceOrigin
    function Publication(
            components::C, law::L, origin::SourceOrigin = _NO_SOURCE_ORIGIN,
        ) where {C<:Tuple,L}
        isempty(components) && throw(LocalMathValidationError(
            "a Publication requires at least one component";
            stage = :construct, contract = :publication_components,
        ))
        all(component -> component isa Union{
            FieldPublication,CollectionPublication,
            FoldPublication}, components) ||
            throw(LocalMathValidationError(
                "Publication components must use the closed component descriptor";
                stage = :construct, contract = :publication_components,
            ))
        _validate_publication(components, law)
        return new{C,L}(components, law, origin)
    end
end

Publication(field::Field, relation::Relation, law;
        value::Symbol = :value, origin::SourceOrigin = _NO_SOURCE_ORIGIN) =
    Publication((FieldPublication(
        field, relation, PublicationValue(value)),), law, origin)

Publication(collection::Collection, law;
        value::Symbol = :value, origin::SourceOrigin = _NO_SOURCE_ORIGIN) =
    Publication((CollectionPublication(
        collection, PublicationValue(value)),), law, origin)

Publication(law::OrderedFold;
        value::Symbol = :value, origin::SourceOrigin = _NO_SOURCE_ORIGIN) =
    Publication((FoldPublication(
        PublicationValue(value)),), law, origin)

function _evaluator_port_names(publications::Tuple)
    return Tuple(_evaluator_value_name(component.role)
        for publication in publications
        for component in publication.components
        if component.role isa PublicationValue)
end

function _validate_stage_publication_fields(publications::Tuple)
    spatial = Tuple(
        semantic_identity(component.field)
        for publication in publications
        for component in publication.components
        if component isa FieldPublication
    )
    folds = Tuple(
        semantic_identity(component.target)
        for publication in publications
        if publication.law isa OrderedFold
        for component in values(publication.law.state.components)
    )
    identities = (spatial..., folds...)
    length(unique(identities)) == length(identities) || throw(
        LocalMathValidationError(
            "one Stage cannot publish the same Field through multiple components";
            stage = :construct,
            contract = :stage_publication_field_uniqueness,
            expected = :one_explicit_conflict_law_per_destination_field,
            actual = identities,
        )
    )
    return nothing
end


function _validate_stage_collection_uniqueness(publications::Tuple)
    identities = Tuple(
        semantic_identity(component.collection)
        for publication in publications
        for component in publication.components
        if component isa CollectionPublication
    )
    length(unique(identities)) == length(identities) || throw(
        LocalMathValidationError(
            "one Stage cannot publish the same Collection more than once";
            stage = :construct,
            contract = :stage_collection_uniqueness,
            actual = identities,
        ))
    return nothing
end

function _validate_stage_publication_domain(
        publication::Publication, source::Space)
    for component in publication.components
        component isa Union{
            CollectionPublication,FoldPublication} && continue
        domain(component.relation) == source || throw(LocalMathValidationError(
            "every spatial Publication Relation must originate at the stage source";
            stage = :construct, contract = :stage_publication_domain,
        ))
    end
    if publication.law isa Collect
        width = _publication_width(publication.law)
        length(source) <= div(Int(typemax(Int32) - 1), width) || throw(
            LocalMathValidationError(
                "Collect source/lane ordinals must fit below the reserved Int32 terminal";
                stage = :construct, contract = :collect_candidate_ordinal,
                expected = :nonterminal_int32, actual = (length(source), width),
            ))
    end
    return nothing
end


function _validate_ordered_fold_stage_boundary(
        publications::Tuple, accesses::NamedTuple, control::Control)
    position = findfirst(publication -> publication.law isa OrderedFold,
        publications)
    position === nothing && return nothing
    length(publications) == 1 || throw(LocalMathValidationError(
        "OrderedFold must be the sole terminal publication of its Stage";
        stage = :construct, contract = :ordered_fold_terminal_publication,
        expected = 1, actual = length(publications),
    ))
    law = publications[position].law
    targets = Set(semantic_identity(component.target)
        for component in values(law.state.components))
    copied_sources = Set(semantic_identity(component.source)
        for component in values(law.state.components)
        if component.source isa Field)
    read_fields = Set(semantic_identity(access.field) for access in values(accesses))
    isempty(intersect(targets, read_fields)) || throw(LocalMathValidationError(
        "OrderedFold targets cannot be ordinary Stage reads";
        stage = :construct, contract = :ordered_fold_target_access_alias,
        actual = intersect(targets, read_fields),
    ))
    control_fields = UUIDs.UUID[]
    control.prefix isa _FieldPrefix &&
        push!(control_fields, semantic_identity(control.prefix.field))
    control.mask isa _MaskSelection &&
        push!(control_fields, semantic_identity(control.mask.field))
    control.gate isa _FieldGate &&
        push!(control_fields, semantic_identity(control.gate.field))
    if control.subset isa _SubsetSelection
        # Reuse the single relation-descriptor closure authority: masked,
        # product, selected, and boundary subset dependencies are controls too.
        subset_fields, _ = _required_descriptor_closure(
            (), (control.subset.relation,),
        )
        append!(control_fields, semantic_identity.(subset_fields))
    end
    isempty(intersect(targets, Set(control_fields))) || throw(
        LocalMathValidationError(
            "OrderedFold targets cannot govern their own Stage control";
            stage = :construct,
            contract = :ordered_fold_target_control_alias,
            actual = intersect(targets, Set(control_fields)),
        ))
    isempty(intersect(copied_sources, Set(control_fields))) || throw(
        LocalMathValidationError(
            "OrderedFold copied sources cannot govern the same Stage control";
            stage = :construct,
            contract = :ordered_fold_source_control_alias,
            actual = intersect(copied_sources, Set(control_fields)),
        ))
    return nothing
end

function _unique_lane_type_valid(lane::Type, publication::Publication)
    expected_value = _unique_value_type(publication.law)
    key_type = _runtime_relation_key_type(only(publication.components).relation)
    if key_type === nothing
        lane <: Union{UniqueValue,ConditionalUniqueValue} || return false
        lane.parameters[1] === expected_value || return false
        publication.law.coverage isa TotalCoverage &&
            lane <: ConditionalUniqueValue && return false
    else
        lane <: Union{RoutedUniqueValue,ConditionalRoutedUniqueValue} ||
            return false
        lane.parameters[1] === key_type && lane.parameters[2] === expected_value ||
            return false
        publication.law.coverage isa TotalCoverage &&
            lane <: ConditionalRoutedUniqueValue && return false
    end
    return true
end

function _reduce_lane_type_valid(lane::Type, publication::Publication)
    key_type = _runtime_relation_key_type(only(publication.components).relation)
    if key_type === nothing
        lane <: Contribution || return false
        return lane.parameters[1] === _publication_value_type(publication.law)
    end
    lane <: RoutedContribution || return false
    return lane.parameters[1] === key_type &&
        lane.parameters[2] === _publication_value_type(publication.law)
end
function _resolve_lane_type_valid(lane::Type, publication::Publication)
    law = publication.law
    key_type = _runtime_relation_key_type(only(publication.components).relation)
    if key_type === nothing
        lane <: ResolutionValue || return false
        return lane.parameters[1] === typeof(law.lower) &&
            lane.parameters[2] === _resolve_tie_type(law.tie) &&
            lane.parameters[3] === _publication_value_type(law)
    end
    lane <: RoutedResolutionValue || return false
    return lane.parameters[1] === key_type &&
        lane.parameters[2] === typeof(law.lower) &&
        lane.parameters[3] === _resolve_tie_type(law.tie) &&
        lane.parameters[4] === _publication_value_type(law)
end
function _collect_lane_type_valid(lane::Type, publication::Publication)
    if publication.law.groups isa _RoutedGroups
        lane <: GroupedCollectedValue || return false
        return lane.parameters[1] === Int32 &&
            lane.parameters[2] === _publication_value_type(publication.law)
    end
    lane <: CollectedValue || return false
    return lane.parameters[1] === _publication_value_type(publication.law)
end
function _ordered_fold_lane_type_valid(lane::Type, publication::Publication)
    lane <: FoldValue || return false
    return lane.parameters[1] === _publication_value_type(publication.law)
end

_publication_lane_type_valid(lane::Type, publication::Publication{C,<:Unique}) where {C} =
    _unique_lane_type_valid(lane, publication)
_publication_lane_type_valid(lane::Type, publication::Publication{C,<:Reduce}) where {C} =
    _reduce_lane_type_valid(lane, publication)
_publication_lane_type_valid(lane::Type, publication::Publication{C,<:Resolve}) where {C} =
    _resolve_lane_type_valid(lane, publication)
_publication_lane_type_valid(lane::Type, publication::Publication{C,<:Collect}) where {C} =
    _collect_lane_type_valid(lane, publication)
_publication_lane_type_valid(lane::Type, publication::Publication{C,<:OrderedFold}) where {C} =
    _ordered_fold_lane_type_valid(lane, publication)

function _validate_evaluator_result_type(publications::Tuple, result_type)
    isconcretetype(result_type) && result_type <: NamedTuple || throw(
        LocalMathValidationError(
            "a stage evaluator must infer one concrete NamedTuple result";
            stage = :construct, contract = :evaluator_result_type,
            expected = :concrete_named_tuple, actual = result_type,
        )
    )
    names = _evaluator_port_names(publications)
    result_type.parameters[1] == names || throw(LocalMathValidationError(
        "evaluator result labels and order must exactly match publications";
        stage = :construct, contract = :evaluator_result_ports,
        expected = names, actual = result_type.parameters[1],
        hint = "return a NamedTuple whose fields match the publication roles in authored order",
    ))
    result_types = result_type.parameters[2].parameters
    for (publication, port_type) in zip(publications, result_types)
        port = only(_evaluator_value_name(component.role)
            for component in publication.components
            if component.role isa PublicationValue)
        width = _publication_width(publication.law)
        lanes = if width == 1
            (port_type,)
        elseif port_type <: Tuple && length(port_type.parameters) == width
            port_type.parameters
        else
            throw(LocalMathValidationError(
                "evaluator result has the wrong fixed emission width";
                stage = :construct, contract = :evaluator_result_width,
                port, origin = publication.origin,
                expected = (width, law = typeof(publication.law)),
                actual = (inferred_result_type = port_type,),
            ))
        end
        all(lane -> lane isa Type && isconcretetype(lane) &&
            _publication_lane_type_valid(lane, publication), lanes) || throw(
                LocalMathValidationError(
                    "evaluator result has an invalid publication carrier type";
                    stage = :construct, contract = :evaluator_result_lane,
                    port, origin = publication.origin,
                    expected = (law = typeof(publication.law),
                        value_type = _publication_value_type(publication.law)),
                    actual = (inferred_result_type = port_type,),
                    hint = "return the carrier required by this publication law and value type",
                )
            )
    end
    return nothing
end

function _validate_stage_control(control::Control, source::Space, spec::Evaluator)
    if control.prefix isa _ParameterPrefix
        declaration = control.prefix.parameter
        _parameter_type(declaration) <: Integer &&
            _parameter_type(declaration) !== Bool || throw(
                LocalMathValidationError(
                    "a parameter prefix requires a non-Bool integer parameter";
                    stage = :construct, contract = :parameter_prefix,
                    actual = _parameter_type(declaration),
                )
            )
    end
    if control.prefix isa _CollectionCount
        Int(control.prefix.collection.capacity) <= length(source) || throw(
            LocalMathValidationError(
                "a Collection-count prefix requires a source large enough for every live record";
                stage = :construct, contract = :collection_count_source,
                expected = Int(control.prefix.collection.capacity),
                actual = length(source),
            )
        )
    end
    if control.mask isa _MaskSelection
        control.mask.field.space == source || throw(LocalMathValidationError(
            "a mask Field must belong to the stage source Space";
            stage = :construct, contract = :mask_source,
        ))
    end
    if control.subset isa _SubsetSelection
        relation = control.subset.relation
        domain(relation) == source && codomain(relation) == source || throw(
            LocalMathValidationError(
                "a subset Relation must be unary over the stage source Space";
                stage = :construct, contract = :subset_source,
                expected = source, actual = (domain(relation), codomain(relation)),
            )
        )
    end
    return nothing
end

"""
    Stage(source, accesses, publications, evaluator;
          parameters=ParameterSchema(), control=Control(), origin omitted)

Declare one finite local calculation. Pass
`SourceOrigin(source, line; label=nothing)` when provenance is available.
"""
struct Stage{S<:Space,A,P,E<:Evaluator,C<:Control,O}
    source::S
    accesses::A
    publications::P
    evaluator::E
    control::C
    origin::O
    function Stage(
            source::S, accesses::A, publications::P, evaluator::E,
            control::C, origin::O,
        ) where {S<:Space,A,P,E<:Evaluator,C<:Control,O}
        accesses isa NamedTuple || throw(LocalMathValidationError(
            "Stage accesses must be an evaluator-role NamedTuple";
            stage = :construct, contract = :stage_accesses, actual = A,
        ))
        all(access -> access isa Union{Access,CollectionAccess}, values(accesses)) || throw(
            LocalMathValidationError(
                "Stage accesses must contain only Field or Collection Access descriptors";
                stage = :construct, contract = :stage_accesses,
            )
        )
        all(name -> !isempty(String(name)), keys(accesses)) || throw(
            LocalMathValidationError(
                "Stage access role labels must be nonempty";
                stage = :construct, contract = :stage_access_labels,
                actual = keys(accesses),
            )
        )
        all(access -> !(access isa Access) || domain(access.relation) == source,
            values(accesses)) ||
            throw(LocalMathValidationError(
                "every Access Relation must originate at the stage source";
                stage = :construct, contract = :stage_access_domain,
            ))
        publications isa Tuple && !isempty(publications) || throw(
            LocalMathValidationError(
                "Stage publications must be a nonempty tuple";
                stage = :construct, contract = :stage_publications,
            )
        )
        all(publication -> publication isa Publication, publications) || throw(
            LocalMathValidationError(
                "Stage publications must contain only Publication values";
                stage = :construct, contract = :stage_publications,
            )
        )
        foreach(publication -> _validate_stage_publication_domain(
            publication, source), publications)
        _validate_stage_publication_fields(publications)
        _validate_stage_collection_uniqueness(publications)
        _validate_ordered_fold_stage_boundary(publications, accesses, control)
        labels = _evaluator_port_names(publications)
        length(unique(labels)) == length(labels) || throw(
            LocalMathValidationError(
                "evaluator-fed publication labels must be unique";
                stage = :construct, contract = :stage_publication_labels,
                actual = labels,
            )
        )
        origin isa SourceOrigin || throw(LocalMathValidationError(
            "a Stage origin must be SourceOrigin";
            stage = :construct, contract = :stage_origin, actual = O,
        ))
        _validate_stage_control(control, source, evaluator)
        return new{S,A,P,E,C,O}(
            source, accesses, publications, evaluator, control, origin
        )
    end
end

function Stage(source::Space, accesses::NamedTuple, publications::Tuple,
        evaluator; parameters = ParameterSchema(), control = Control(),
        origin::SourceOrigin = _NO_SOURCE_ORIGIN)
    schema = parameters isa ParameterSchema ? parameters : ParameterSchema(parameters)
    return Stage(source, accesses, publications,
        Evaluator(evaluator, schema.declarations), control, origin)
end
