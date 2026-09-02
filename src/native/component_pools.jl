# Fixed-capacity, structure-of-arrays native state owned above CorePotts. Core
# owns identity validation and two-bank publication; this file owns only the
# native logical representation and the scientific value assigned per event.

import CorePotts.BackendSPI:
    AbstractBulkComponentStatePolicy,
    clone_component_state,
    copy_component_state!,
    validate_component_state,
    initialize_component_state!,
    remove_component_state!,
    retire_component_state!,
    transition_component_state!,
    divide_component_state!

struct NativeCellStateBank{U <: Tuple, P <: Tuple, D, T}
    u::U
    p::P
    du::D
    t::Vector{T}
    retcode::Vector{SciMLBase.ReturnCode.T}
end

function _native_cell_columns(values::Tuple, capacity::Int)
    return map(values) do value
        column = Vector{typeof(value)}(undef, capacity)
        for slot in eachindex(column)
            column[slot] = deepcopy(value)
        end
        column
    end
end

function NativeCellStateBank(template::NativeLogicalState, capacity::Integer)
    0 < capacity <= typemax(Int32) || throw(ArgumentError(
        "native cell-state capacity must be in 1:typemax(Int32)"
    ))
    count = Int(capacity)
    du = template.du === nothing ? nothing : _native_cell_columns(template.du, count)
    return NativeCellStateBank(
        _native_cell_columns(template.u, count),
        _native_cell_columns(template.p, count),
        du,
        fill(template.t, count),
        fill(template.retcode, count),
    )
end

struct _NativePreserveAction end
struct _NativeUnsupportedAction
    event::Symbol
end
mutable struct _NativePreparedCreationAction{S}
    states::Vector{Union{Nothing, S}}
end
struct _NativeResetAction{S}
    state::S
end
struct _NativeTransformAction{F}
    transform::F
end
struct _NativeCopyDaughtersAction end
struct _NativeParentResetDaughterAction{S}
    daughter::S
end
struct _NativeResetDaughtersAction{P, D}
    parent::P
    daughter::D
end
struct _NativeSplitDaughtersAction{F}
    fraction::F
end
struct _NativeTransformDaughtersAction{P, D}
    parent::P
    daughter::D
end

"""Compiled per-cell state policy consumed by the CorePotts bulk-state seam."""
struct NativeCellStatePolicy{S, C, T, D} <: AbstractBulkComponentStatePolicy
    template::S
    creation::C
    transition::T
    division::D
end

"""Potts-owned wrapper giving a Core bulk pool one stable component path."""
struct NativeCellStatePool{P, Q}
    path::Tuple{Vararg{Symbol}}
    storage::P
    policy::Q
end

function NativeCellStatePool(
        path,
        active,
        generations,
        kinds,
        bank::NativeCellStateBank,
        policy::NativeCellStatePolicy;
        completed_mcs::Integer = 0,
        last_transaction_identity::Integer = 0,
    )
    normalized = _qualified_native_path(path, "NativeCellStatePool")
    policy.template.path == normalized || throw(ArgumentError(
        "native cell-state policy path does not match its component pool"
    ))
    storage = CorePotts.BackendSPI.BulkComponentStatePool(
        active, generations, kinds, bank, policy;
        completed_mcs, last_transaction_identity,
    )
    return NativeCellStatePool(normalized, storage, policy)
end

Base.length(pool::NativeCellStatePool) = length(pool.storage)

struct NativeCellStateSnapshot{P <: Tuple, A, G, K}
    path::P
    active::A
    generations::G
    kinds::K
    identities::Vector{Union{Nothing, CorePotts.CellIdentity}}
    states::Vector{Union{Nothing, NativeLogicalState}}
    capacity::Int
    completed_mcs::Int
    last_transaction_identity::UInt64
end

function native_cell_state_snapshot(pool::NativeCellStatePool)
    bank = CorePotts.BackendSPI.component_state_snapshot(pool.storage)
    metadata = CorePotts.BackendSPI.component_metadata_snapshot(pool.storage)
    identities = Union{Nothing, CorePotts.CellIdentity}[
        CorePotts.BackendSPI.component_identity(pool.storage, slot)
        for slot in 1:length(pool)
    ]
    states = Union{Nothing, NativeLogicalState}[
        identity === nothing ? nothing :
        native_cell_state(pool.policy, bank, slot)
        for (slot, identity) in enumerate(identities)
    ]
    return NativeCellStateSnapshot(
        pool.path,
        metadata.active,
        metadata.generations,
        metadata.kinds,
        identities,
        states,
        length(pool),
        CorePotts.BackendSPI.bulk_component_completed_mcs(pool.storage),
        CorePotts.BackendSPI.bulk_component_last_transaction_identity(pool.storage),
    )
end

function native_cell_state(pool::NativeCellStatePool, identity::CorePotts.CellIdentity)
    observed = CorePotts.BackendSPI.component_identity(
        pool.storage, Int(identity.slot)
    )
    observed == identity || throw(CorePotts.BackendSPI.StaleCellIdentityError(
        0,
        identity,
        observed !== nothing,
        observed === nothing ? UInt32(0) : observed.generation,
        observed === nothing ? Int16(0) : observed.kind,
    ))
    bank = CorePotts.BackendSPI.component_state_snapshot(pool.storage)
    return native_cell_state(pool.policy, bank, Int(identity.slot))
end

function NativeCellStatePolicy(
        template::NativeLogicalState;
        creation = _NativeResetAction(template),
        transition = _NativePreserveAction(),
        division = _NativeCopyDaughtersAction(),
    )
    return NativeCellStatePolicy(template, creation, transition, division)
end

function _native_cell_state_policy(
        component::ScheduledNativeComponent,
        template::NativeLogicalState,
        capacity::Integer,
    )
    applicable(
        _lower_native_cell_state_policy, component, template, capacity
    ) && return _lower_native_cell_state_policy(
        component, template, capacity
    )
    declaration = getfield(component, :declaration)
    lifecycle = getfield(declaration, :lifecycle)
    lifecycle isa PerCellNativeLifecycle || throw(ArgumentError(
        "a native cell-state pool requires PerCellNativeLifecycle"
    ))
    creation = lifecycle.creation isa PreserveNativeInitialization ?
        _NativePreparedCreationAction(
            Union{Nothing, typeof(template)}[nothing for _ in 1:capacity]
        ) : _NativeUnsupportedAction(:creation)
    transition = if lifecycle.transition isa Preserve
        _NativePreserveAction()
    elseif lifecycle.transition isa Unsupported
        _NativeUnsupportedAction(:transition)
    elseif lifecycle.transition isa ResetTo &&
            lifecycle.transition.expression isa NativeLogicalState
        _NativeResetAction(lifecycle.transition.expression)
    elseif lifecycle.transition isa Transform &&
            applicable(lifecycle.transition.expression, template, nothing)
        _NativeTransformAction(lifecycle.transition.expression)
    else
        throw(ArgumentError(
            "symbolic per-cell transition policies require the ModelingToolkit lifecycle lowering"
        ))
    end
    division = if lifecycle.division isa CopyToDaughters
        _NativeCopyDaughtersAction()
    elseif lifecycle.division isa Unsupported
        _NativeUnsupportedAction(:division)
    elseif lifecycle.division isa SplitConservatively
        fraction = lifecycle.division.fraction
        fraction isa Real && isfinite(fraction) && 0 <= fraction <= 1 ||
            throw(ArgumentError(
                "native SplitConservatively fraction must be finite and in [0, 1]"
            ))
        _NativeSplitDaughtersAction(fraction)
    elseif lifecycle.division isa PreserveParentResetDaughter &&
            lifecycle.division.expression isa NativeLogicalState
        _NativeParentResetDaughterAction(lifecycle.division.expression)
    elseif lifecycle.division isa ResetBoth &&
            lifecycle.division.parent_expression isa NativeLogicalState &&
            lifecycle.division.daughter_expression isa NativeLogicalState
        _NativeResetDaughtersAction(
            lifecycle.division.parent_expression,
            lifecycle.division.daughter_expression,
        )
    else
        throw(ArgumentError(
            "symbolic per-cell division policies require the ModelingToolkit lifecycle lowering"
        ))
    end
    return NativeCellStatePolicy(template; creation, transition, division)
end

function _copy_native_columns!(destination::Tuple, source::Tuple)
    length(destination) == length(source) || throw(ArgumentError(
        "native component-state column schemas do not match"
    ))
    for (destination_column, source_column) in zip(destination, source)
        for slot in eachindex(destination_column, source_column)
            destination_column[slot] = deepcopy(source_column[slot])
        end
    end
    return destination
end

function _clone_native_column(source)
    destination = similar(source)
    for slot in eachindex(destination, source)
        destination[slot] = deepcopy(source[slot])
    end
    return destination
end

function clone_component_state(
        ::NativeCellStatePolicy, state::NativeCellStateBank
    )
    du = state.du === nothing ? nothing : map(_clone_native_column, state.du)
    return NativeCellStateBank(
        map(_clone_native_column, state.u), map(_clone_native_column, state.p), du,
        copy(state.t), copy(state.retcode),
    )
end

function copy_component_state!(
        ::NativeCellStatePolicy,
        destination::NativeCellStateBank,
        source::NativeCellStateBank,
    )
    _copy_native_columns!(destination.u, source.u)
    _copy_native_columns!(destination.p, source.p)
    (destination.du === nothing) == (source.du === nothing) ||
        throw(ArgumentError("native component-state derivative schemas do not match"))
    destination.du === nothing || _copy_native_columns!(destination.du, source.du)
    copyto!(destination.t, source.t)
    copyto!(destination.retcode, source.retcode)
    return destination
end

function validate_component_state(
        ::NativeCellStatePolicy, state::NativeCellStateBank, capacity::Integer
    )
    collections = Any[state.u..., state.p..., state.t, state.retcode]
    state.du === nothing || append!(collections, state.du)
    all(column -> length(column) == capacity, collections) ||
        throw(ArgumentError("native component-state columns do not match capacity"))
    all(isfinite, state.t) || throw(ArgumentError(
        "native component-state time contains a nonfinite value"
    ))
    all(_valid_native_cell_value, (state.u..., state.p...)) ||
        throw(ArgumentError(
            "native component-state values contain a nonfinite or unsupported value"
        ))
    state.du === nothing || all(_valid_native_cell_value, state.du) ||
        throw(ArgumentError(
            "native component-state derivatives contain a nonfinite or unsupported value"
        ))
    return nothing
end

_valid_native_cell_value(value::AbstractFloat) = isfinite(value)
_valid_native_cell_value(value::Number) = isfinite(value)
_valid_native_cell_value(value::Union{Bool, Symbol, AbstractString, Enum}) = true
_valid_native_cell_value(value::Tuple) = all(_valid_native_cell_value, value)
_valid_native_cell_value(value::NamedTuple) =
    all(_valid_native_cell_value, values(value))
_valid_native_cell_value(value::AbstractArray) =
    all(_valid_native_cell_value, value)
_valid_native_cell_value(value) = false

@inline _native_event_slot(identity::CorePotts.CellIdentity) = Int(identity.slot)

function native_cell_state(
        policy::NativeCellStatePolicy,
        state::NativeCellStateBank,
        slot::Integer,
    )
    checkbounds(state.t, slot)
    u = map(column -> deepcopy(column[slot]), state.u)
    p = map(column -> deepcopy(column[slot]), state.p)
    du = state.du === nothing ? nothing :
         map(column -> deepcopy(column[slot]), state.du)
    return NativeLogicalState(
        policy.template.path, u, p, du, state.t[slot], state.retcode[slot]
    )
end

function _write_native_cell_state!(
        state::NativeCellStateBank, slot::Integer, value::NativeLogicalState
    )
    length(state.u) == length(value.u) || throw(ArgumentError(
        "native reset state has the wrong unknown schema"
    ))
    length(state.p) == length(value.p) || throw(ArgumentError(
        "native reset state has the wrong parameter schema"
    ))
    (state.du === nothing) == (value.du === nothing) || throw(ArgumentError(
        "native reset state has the wrong derivative schema"
    ))
    for (column, item) in zip(state.u, value.u)
        column[slot] = deepcopy(item)
    end
    for (column, item) in zip(state.p, value.p)
        column[slot] = deepcopy(item)
    end
    if state.du !== nothing
        for (column, item) in zip(state.du, value.du)
            column[slot] = deepcopy(item)
        end
    end
    state.t[slot] = value.t
    state.retcode[slot] = value.retcode
    return state
end

function _apply_native_action!(policy, bank, slot, action::_NativeResetAction, event)
    _write_native_cell_state!(bank, slot, action.state)
end
function _apply_native_action!(
        policy, bank, slot, action::_NativePreparedCreationAction, event
    )
    replacement = action.states[slot]
    replacement === nothing && throw(ArgumentError(
        "native creation state was not prepared before lifecycle staging"
    ))
    _write_native_cell_state!(bank, slot, replacement)
    action.states[slot] = nothing
    return bank
end
_apply_native_action!(policy, bank, slot, ::_NativePreserveAction, event) = bank
function _apply_native_action!(policy, bank, slot, action::_NativeTransformAction, event)
    prior = native_cell_state(policy, bank, slot)
    replacement = action.transform(prior, event)
    replacement isa NativeLogicalState || throw(ArgumentError(
        "compiled native lifecycle transform must return NativeLogicalState"
    ))
    return _write_native_cell_state!(bank, slot, replacement)
end
function _apply_native_action!(policy, bank, slot, action::_NativeUnsupportedAction, event)
    throw(ArgumentError("native component does not support $(action.event) lifecycle events"))
end

function initialize_component_state!(policy::NativeCellStatePolicy, bank, event)
    return _apply_native_action!(
        policy, bank, _native_event_slot(event.after), policy.creation, event
    )
end

remove_component_state!(::NativeCellStatePolicy, bank, event) = bank
retire_component_state!(::NativeCellStatePolicy, bank, event) = bank

function transition_component_state!(policy::NativeCellStatePolicy, bank, event)
    return _apply_native_action!(
        policy, bank, _native_event_slot(event.before), policy.transition, event
    )
end

function _copy_native_slot!(bank::NativeCellStateBank, destination::Int, source::Int)
    for column in (bank.u..., bank.p...)
        column[destination] = deepcopy(column[source])
    end
    if bank.du !== nothing
        for column in bank.du
            column[destination] = deepcopy(column[source])
        end
    end
    bank.t[destination] = bank.t[source]
    bank.retcode[destination] = bank.retcode[source]
    return bank
end

function _scale_native_value(value, fraction)
    value isa Number && return value * fraction
    value isa AbstractArray && return value .* fraction
    throw(ArgumentError(
        "SplitConservatively requires numeric native unknown values; got $(typeof(value))"
    ))
end

function _divide_native_state!(policy, bank, parent, daughter, ::_NativeCopyDaughtersAction, event)
    return _copy_native_slot!(bank, daughter, parent)
end
function _divide_native_state!(policy, bank, parent, daughter, action::_NativeParentResetDaughterAction, event)
    return _write_native_cell_state!(bank, daughter, action.daughter)
end
function _divide_native_state!(policy, bank, parent, daughter, action::_NativeResetDaughtersAction, event)
    _write_native_cell_state!(bank, parent, action.parent)
    return _write_native_cell_state!(bank, daughter, action.daughter)
end
function _divide_native_state!(policy, bank, parent, daughter, action::_NativeSplitDaughtersAction, event)
    prior = native_cell_state(policy, bank, parent)
    parent_u = map(value -> _scale_native_value(value, action.fraction), prior.u)
    daughter_u = map(value -> _scale_native_value(value, one(action.fraction) - action.fraction), prior.u)
    _write_native_cell_state!(bank, parent, NativeLogicalState(
        prior.path, parent_u, prior.p, prior.du, prior.t, prior.retcode
    ))
    return _write_native_cell_state!(bank, daughter, NativeLogicalState(
        prior.path, daughter_u, prior.p, prior.du, prior.t, prior.retcode
    ))
end
function _divide_native_state!(policy, bank, parent, daughter, action::_NativeTransformDaughtersAction, event)
    prior = native_cell_state(policy, bank, parent)
    parent_state = action.parent(prior, event)
    daughter_state = action.daughter(prior, event)
    parent_state isa NativeLogicalState && daughter_state isa NativeLogicalState ||
        throw(ArgumentError(
            "compiled native daughter transforms must return NativeLogicalState"
        ))
    _write_native_cell_state!(bank, parent, parent_state)
    return _write_native_cell_state!(bank, daughter, daughter_state)
end
function _divide_native_state!(policy, bank, parent, daughter, action::_NativeUnsupportedAction, event)
    throw(ArgumentError("native component does not support $(action.event) lifecycle events"))
end

function divide_component_state!(policy::NativeCellStatePolicy, bank, event)
    parent = _native_event_slot(event.parent_before.cell)
    daughter = _native_event_slot(event.daughter_after.cell)
    return _divide_native_state!(
        policy, bank, parent, daughter, policy.division, event
    )
end

_native_runtime_path(state::NativeLogicalState) = state.path
_native_runtime_path(state::NativeCellStatePool) = state.path
_native_runtime_path(state::NativeCellStateSnapshot) = state.path

_native_runtime_template(state::NativeLogicalState) = state
_native_runtime_template(state::NativeCellStatePool) = state.policy.template

function _native_runtime_terminated(state::NativeLogicalState)
    return state.retcode === SciMLBase.ReturnCode.Terminated
end
function _native_runtime_terminated(state::NativeCellStatePool)
    snapshot = native_cell_state_snapshot(state)
    return any(
        value -> value !== nothing &&
            value.retcode === SciMLBase.ReturnCode.Terminated,
        snapshot.states,
    )
end
