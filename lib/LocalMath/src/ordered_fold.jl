# Typed semantics for bounded ordered recurrence. This file owns declarations
# and kernel-local values; the execution unit lowers them through the ordinary
# LocalMath planning and KernelAbstractions pipeline.

struct _FoldInPlace end
const _ORDERED_FOLD_MAX_EXTENT = Int(typemax(Int32)) - 1
const _ORDERED_FOLD_MAX_COMPONENT_UPDATES = 32
const _ORDERED_FOLD_MAX_TOTAL_UPDATES = 128
const _ORDERED_FOLD_MAX_STEP_BYTES = 1024

"""
    FoldComponent(target::Field; from=nothing, in_place=false)

Declare one typed accumulator component for [`initialized_state`](@ref).
Copied components name an exact same-space, same-element-type source `Field`.
An in-place component passes `in_place=true` and omits `from`.
"""
struct FoldComponent{F<:Field,S}
    target::F
    source::S
    function FoldComponent(target::F, source::S) where {F<:Field,S}
        source isa _FoldInPlace ||
            (source isa Field && source.space == target.space &&
             eltype(source) === eltype(target)) || throw(LocalMathValidationError(
                "a fold-state source must be in-place or an exact same-shaped Field";
                stage = :construct, contract = :fold_state_source,
                expected = (target.space, eltype(target)), actual = source))
        source isa Field && semantic_identity(source) == semantic_identity(target) &&
            throw(LocalMathValidationError(
                "same-Field fold initialization must be explicitly in-place";
                stage = :construct, contract = :fold_state_source,
                actual = semantic_identity(target)))
        return new{F,S}(target, source)
    end
end

FoldComponent(target::Field; from = nothing, in_place::Bool = false) =
    in_place ? (from === nothing || throw(LocalMathValidationError(
        "an in-place fold state must omit from";
        stage = :construct, contract = :fold_state_source));
        FoldComponent(target, _FoldInPlace())) :
    (from isa Field || throw(LocalMathValidationError(
        "a copied fold state requires a source Field";
        stage = :construct, contract = :fold_state_source, actual = from));
     FoldComponent(target, from))

"""Immutable canonical accumulator schema returned by [`initialized_state`](@ref)."""
struct InitializedState{Names, C <: NamedTuple}
    components::C
end

Base.keys(state::InitializedState) = keys(state.components)
Base.values(state::InitializedState) = values(state.components)
Base.getindex(state::InitializedState, name::Symbol) =
    getproperty(state.components, name)

"""
    initialized_state(; component_name=FoldComponent(...), ...)

Construct a canonical named accumulator schema. Component names and targets
must be unique. Copied initialization sources may be shared, but may not alias
any accumulator target; explicit in-place initialization is the sole exception.
"""
function initialized_state(; components...)
    isempty(components) && throw(ArgumentError(
        "initialized_state requires at least one component"
    ))
    named_components = (; components...)
    all(name -> !isempty(String(name)), keys(named_components)) || throw(
        ArgumentError("initialized-state component names must be nonempty")
    )
    all(component -> component isa FoldComponent, values(named_components)) || throw(
        ArgumentError(
            "initialized_state values must be FoldComponent declarations"
        )
    )
    canonical = named_components
    targets = Tuple(semantic_identity(component.target)
        for component in values(canonical))
    length(unique(targets)) == length(targets) || throw(ArgumentError(
        "initialized-state component targets must be unique"
    ))
    copied_sources = Tuple(semantic_identity(component.source)
        for component in values(canonical) if component.source isa Field)
    isempty(intersect(Set(targets), Set(copied_sources))) || throw(ArgumentError(
            "copied fold-component sources may not alias accumulator targets"
        ))
    return InitializedState{keys(canonical), typeof(canonical)}(canonical)
end

InitializedState(; components...) = initialized_state(; components...)

"""
    BoundedWrites(keys, values[, count])

One concrete, statically bounded component-update bundle returned inside a
[`FoldStep`](@ref). `keys` are one-based linear `Int32` component indices;
`count` selects the live tuple prefix. Execution validates the live
count, every destination, and duplicate destinations before applying a step.

Construction is allocation-free and device-compatible. It intentionally does
not perform dynamic destination validation.
"""
struct BoundedWrites{K, T}
    keys::NTuple{K, Int32}
    values::NTuple{K, T}
    count::Int32

    function BoundedWrites{K, T}(
            keys::NTuple{K, Int32}, values::NTuple{K, T}, count::Int32
        ) where {K, T}
        K <= _ORDERED_FOLD_MAX_COMPONENT_UPDATES || throw(ArgumentError(
            "BoundedWrites capacity exceeds the reviewed ordered-fold component limit"
        ))
        return new{K, T}(keys, values, count)
    end
end

function BoundedWrites(
        keys::NTuple{K, Int32}, values::Tuple{T, Vararg{T}},
        count::Int32 = Int32(K),
    ) where {K, T}
    length(values) == K || throw(ArgumentError(
        "BoundedWrites keys and values must have equal capacity"))
    return BoundedWrites{K, T}(keys, values, count)
end

BoundedWrites(::Type{T}) where {T} =
    BoundedWrites{0, T}((), (), Int32(0))

"""
    FoldStep(updates; halt=false)

Return one kernel-local ordered-fold step. `updates` is a named tuple whose
values are [`BoundedWrites`](@ref). Its names are checked against the declared
accumulator schema during planning; the executor applies components in schema
order rather than caller tuple order. `halt=true` stops only the later canonical
prefix and does not imply rollback.
"""
struct FoldStep{Names, U <: NamedTuple}
    updates::U
    halt::Bool
end

_fold_writes_tuple(::Tuple{}) = true
_fold_writes_tuple(updates::Tuple) =
    first(updates) isa BoundedWrites && _fold_writes_tuple(Base.tail(updates))

function FoldStep(
        updates::U;
        halt::Bool = false,
    ) where {U <: NamedTuple}
    _fold_writes_tuple(values(updates)) || throw(ArgumentError(
        "FoldStep updates must be a named tuple of BoundedWrites values"
    ))
    return FoldStep{keys(updates), U}(updates, halt)
end

"""Validate the shared static ABI for a Stage ordered-recurrence transition.

The physical executor remains responsible only for validating live counts,
destinations, and duplicate write keys.
"""
function _validate_ordered_fold_step_type(
        step_type, names::Tuple, value_types::Tuple;
        stage::Symbol = :prepare,
        prefix::Symbol = :ordered_fold,
    )
    step_type isa DataType && isconcretetype(step_type) &&
        step_type <: FoldStep || throw(LocalMathValidationError(
            "ordered-fold transition must infer one concrete FoldStep";
            stage, contract = Symbol(prefix, :_step_type),
            expected = FoldStep, actual = step_type,
        ))
    isbitstype(step_type) && _storage_free_type(step_type) &&
        sizeof(step_type) <= _ORDERED_FOLD_MAX_STEP_BYTES || throw(
            LocalMathValidationError(
                "ordered-fold steps must fit the reviewed storage-free device ABI";
                stage, contract = Symbol(prefix, :_step_storage),
                expected = (
                    storage_free_isbits = true,
                    maximum_bytes = _ORDERED_FOLD_MAX_STEP_BYTES,
                ),
                actual = (
                    step_type,
                    isbits = isbitstype(step_type),
                    bytes = isbitstype(step_type) ? sizeof(step_type) : nothing,
                ),
            ))
    fieldtype(step_type, :halt) === Bool || throw(LocalMathValidationError(
        "ordered-fold transition halt must be Bool";
        stage, contract = Symbol(prefix, :_halt_type),
        expected = Bool, actual = fieldtype(step_type, :halt),
    ))
    update_names = step_type.parameters[1]
    Set(update_names) == Set(names) || throw(LocalMathValidationError(
        "ordered-fold step updates must name every accumulator component";
        stage, contract = Symbol(prefix, :_step_components),
        expected = names, actual = update_names,
    ))
    update_types = step_type.parameters[2].parameters[2].parameters
    total_updates = 0
    for (name, value_type) in zip(names, value_types)
        update_index = findfirst(==(name), update_names)
        writes_type = update_types[update_index]
        writes_type <: BoundedWrites && writes_type.parameters[2] === value_type ||
            throw(LocalMathValidationError(
                "ordered-fold update value type changed for component $name";
                stage, contract = Symbol(prefix, :_step_value_type),
                expected = value_type, actual = writes_type,
            ))
        capacity = writes_type.parameters[1]
        0 <= capacity <= _ORDERED_FOLD_MAX_COMPONENT_UPDATES || throw(
            LocalMathValidationError(
                "ordered-fold component update capacity exceeds the bounded device ABI";
                stage, contract = Symbol(prefix, :_update_capacity),
                port = name,
                expected = 0:_ORDERED_FOLD_MAX_COMPONENT_UPDATES,
                actual = capacity,
            ))
        total_updates = try
            Base.Checked.checked_add(total_updates, capacity)
        catch error
            error isa OverflowError || rethrow()
            throw(LocalMathValidationError(
                "ordered-fold aggregate update capacity overflows";
                stage, contract = Symbol(prefix, :_update_capacity),
            ))
        end
    end
    total_updates <= _ORDERED_FOLD_MAX_TOTAL_UPDATES || throw(
        LocalMathValidationError(
            "ordered-fold aggregate update capacity exceeds the bounded device ABI";
            stage, contract = Symbol(prefix, :_update_capacity),
            expected = _ORDERED_FOLD_MAX_TOTAL_UPDATES, actual = total_updates,
        ))
    return step_type
end

# Shared, backend-neutral FoldStep validation codes.  These belong to the
# ordered-recurrence law ABI, not to either physical executor.
const _ORDERED_FOLD_VALID = UInt8(0)
const _ORDERED_FOLD_UPDATE_COUNT = UInt8(1)
const _ORDERED_FOLD_DESTINATION = UInt8(2)
const _ORDERED_FOLD_DUPLICATE_UPDATE = UInt8(3)
const _ORDERED_FOLD_DUPLICATE_ORDER = UInt8(4)
const _ORDERED_FOLD_INVALID_VALUE = UInt8(5)
const _ORDERED_FOLD_EMPTY_INPUT = UInt8(6)
