struct LabelledCells{A <: AbstractArray, C, M}
    labels::A
    cells::C
    medium::M
end

"""
    LabelledCells(labels; cells, medium)

Declare one concrete ownership lattice. Label `0` is the declared medium;
positive labels index `cells`, whose entries are cell-kind declarations or names.
All mutable inputs are defensively copied.
"""
function LabelledCells(labels::AbstractArray{<:Integer}; cells, medium)
    copied_labels = Int32.(labels)
    copied_cells = if cells isa AbstractDict
        Dict(Int(key) => _defensive_copy(value) for (key, value) in cells)
    else
        Any[_defensive_copy(value) for value in cells]
    end
    return LabelledCells(copied_labels, copied_cells, _defensive_copy(medium))
end

struct CellPlacement{K, S}
    label::Int
    kind::K
    sites::S
    function CellPlacement(label::Integer, kind, sites)
        label > 0 || throw(ArgumentError("cell placement labels must be positive"))
        copied = Tuple(Tuple(Int.(site)) for site in sites)
        new{typeof(kind), typeof(copied)}(Int(label), kind, copied)
    end
end

struct MediumPlacement{K, S}
    kind::K
    sites::S
end

abstract type AbstractProceduralPlacement end

"""
    RandomSitePlacement(name, kind; count, sites_per_cell=1, first_label=1)

Place a fixed number of cells by sampling distinct currently unassigned lattice
sites from the dedicated initialization RNG stream. The placement identity,
master seed, and replica determine the result without consuming any simulation
draw site.
"""
struct RandomSitePlacement{K} <: AbstractProceduralPlacement
    name::Symbol
    kind::K
    count::Int
    sites_per_cell::Int
    first_label::Int
    function RandomSitePlacement(
            name::Symbol,
            kind;
            count::Integer,
            sites_per_cell::Integer = 1,
            first_label::Integer = 1,
        )
        isempty(String(name)) &&
            throw(ArgumentError("procedural placement name cannot be empty"))
        count > 0 ||
            throw(ArgumentError("procedural placement count must be positive"))
        sites_per_cell > 0 ||
            throw(ArgumentError("sites_per_cell must be positive"))
        first_label > 0 ||
            throw(ArgumentError("first_label must be positive"))
        return new{typeof(kind)}(
            name, kind, Int(count), Int(sites_per_cell), Int(first_label)
        )
    end
end

function MediumPlacement(kind, sites::Union{Tuple, AbstractVector})
    copied = Tuple(Tuple(Int.(site)) for site in sites)
    return MediumPlacement{typeof(kind), typeof(copied)}(kind, copied)
end

struct OwnershipLayout{N, P <: Tuple, M}
    shape::NTuple{N, Int}
    placements::P
    medium::M
end

function OwnershipLayout(
        shape::NTuple{N, <:Integer},
        placements::Union{
            CellPlacement, MediumPlacement, AbstractProceduralPlacement
        }...;
        medium,
    ) where {N}
    normalized_shape = Tuple(Int.(shape))
    all(>(0), normalized_shape) ||
        throw(ArgumentError("ownership layout dimensions must be positive"))
    labels = Int[
        placement.label for placement in placements
        if placement isa CellPlacement
    ]
    for placement in placements
        placement isa RandomSitePlacement || continue
        append!(
            labels,
            placement.first_label:
            (placement.first_label + placement.count - 1),
        )
    end
    length(unique(labels)) == length(labels) ||
        throw(ArgumentError("ownership layout cell labels must be unique"))
    procedural_names = Symbol[
        placement.name for placement in placements
        if placement isa AbstractProceduralPlacement
    ]
    length(unique(procedural_names)) == length(procedural_names) ||
        throw(ArgumentError("procedural placement names must be unique"))
    return OwnershipLayout{N, typeof(placements), typeof(medium)}(
        normalized_shape, placements, _defensive_copy(medium)
    )
end

struct PottsInitialState{O, V <: Tuple}
    ownership::O
    values::V
end

function _initial_value_pairs(values)
    values === nothing && return ()
    values isa AbstractDict && return Tuple(
        _defensive_copy(key) => _defensive_copy(value) for (key, value) in values
    )
    values isa Pair && return (_defensive_copy(first(values)) =>
                                _defensive_copy(last(values)),)
    values isa NamedTuple && return Tuple(
        key => _defensive_copy(getproperty(values, key)) for key in keys(values)
    )
    values isa Tuple || values isa AbstractVector || throw(ArgumentError(
        "initial `values` must be pairs, a dictionary, or a named tuple"
    ))
    all(value -> value isa Pair, values) ||
        throw(ArgumentError("initial `values` entries must be pairs"))
    return Tuple(
        _defensive_copy(first(value)) => _defensive_copy(last(value))
        for value in values
    )
end

function PottsInitialState(; ownership, values = ())
    ownership isa Union{LabelledCells, OwnershipLayout} ||
        throw(ArgumentError(
            "ownership must be LabelledCells(...) or OwnershipLayout(...)"
        ))
    return PottsInitialState(_defensive_copy(ownership), _initial_value_pairs(values))
end

_defensive_copy(value::LabelledCells) =
    LabelledCells(value.labels; cells = value.cells, medium = value.medium)
_defensive_copy(value::OwnershipLayout) = value
_defensive_copy(value::PottsInitialState) = PottsInitialState(
    ownership = _defensive_copy(value.ownership),
    values = value.values,
)

function _kind_symbol(kind)
    kind isa Union{CellKind, MediumKind} && return Symbol(statement_id(kind))
    kind isa Symbol && return kind
    throw(ArgumentError("cell and medium kinds use declarations or Symbol names"))
end

function _kind_indices(executable::PottsExecutable)
    return Dict(
        kind => index
        for (index, kind) in enumerate(executable.reports.kinds)
    )
end

function _materialize_labelled(
        executable::PottsExecutable, labelled::LabelledCells
    )
    program = executable.core_program
    size(labelled.labels) == program.shape ||
        throw(ArgumentError("initial ownership shape does not match the executable"))
    kinds = _kind_indices(executable)
    medium_name = _kind_symbol(labelled.medium)
    medium_index = get(kinds, medium_name, nothing)
    medium_index !== nothing && program.medium_kinds[medium_index] ||
        throw(ArgumentError("initial medium is not a declared executable medium"))
    maximum_label = Int(maximum(labelled.labels; init = Int32(0)))
    minimum(labelled.labels; init = Int32(0)) >= 0 ||
        throw(ArgumentError("ownership labels must be nonnegative"))
    cell_kinds = Vector{Int16}(undef, maximum_label)
    if labelled.cells isa AbstractDict
        expected = Set(1:maximum_label)
        actual = Set(keys(labelled.cells))
        expected == actual || throw(ArgumentError(
            "labelled cells must define exactly labels 1:$maximum_label"
        ))
        for label in 1:maximum_label
            name = _kind_symbol(labelled.cells[label])
            index = get(kinds, name, nothing)
            index === nothing &&
                throw(ArgumentError("unknown initial cell kind `$name`"))
            program.medium_kinds[index] &&
                throw(ArgumentError("a positive cell label cannot use the medium kind"))
            cell_kinds[label] = Int16(index)
        end
    else
        length(labelled.cells) == maximum_label || throw(ArgumentError(
            "cell kind vector length must equal maximum ownership label"
        ))
        for label in 1:maximum_label
            name = _kind_symbol(labelled.cells[label])
            index = get(kinds, name, nothing)
            index === nothing &&
                throw(ArgumentError("unknown initial cell kind `$name`"))
            program.medium_kinds[index] &&
                throw(ArgumentError("a positive cell label cannot use the medium kind"))
            cell_kinds[label] = Int16(index)
        end
    end
    return copy(labelled.labels), cell_kinds
end

function _materialize_layout(
        executable::PottsExecutable,
        layout::OwnershipLayout,
        seed::UInt64,
        replica::UInt32,
    )
    layout.shape == executable.core_program.shape ||
        throw(ArgumentError("ownership layout shape does not match the executable"))
    cell_placements = Tuple(
        placement for placement in layout.placements
        if placement isa CellPlacement
    )
    procedural_placements = Tuple(sort(
        collect(
            placement for placement in layout.placements
            if placement isa RandomSitePlacement
        );
        by = placement -> String(placement.name),
    ))
    maximum_label = maximum(
        Iterators.flatten((
            (placement.label for placement in cell_placements),
            (
                placement.first_label + placement.count - 1
                for placement in procedural_placements
            ),
        ));
        init = 0,
    )
    kinds = _kind_indices(executable)
    default_medium_name = _kind_symbol(layout.medium)
    default_medium_index = get(kinds, default_medium_name, nothing)
    default_medium_index !== nothing &&
        executable.core_program.medium_kinds[default_medium_index] ||
        throw(ArgumentError(
            "ownership layout default medium is not a declared medium kind"
        ))
    background = default_medium_index == executable.core_program.medium_kind ?
                 Int32(0) : -Int32(default_medium_index)
    labels = fill(background, layout.shape)
    assigned = falses(layout.shape)
    cells = Dict{Int, Any}()
    for placement in layout.placements
        placement isa MediumPlacement || continue
        medium_name = _kind_symbol(placement.kind)
        medium_index = get(kinds, medium_name, nothing)
        medium_index !== nothing &&
            executable.core_program.medium_kinds[medium_index] ||
            throw(ArgumentError(
                "medium placement uses undeclared medium kind `$medium_name`"
            ))
        encoded = medium_index == default_medium_index ?
                  Int32(0) : -Int32(medium_index)
        for coordinates in placement.sites
            length(coordinates) == length(layout.shape) ||
                throw(ArgumentError("medium placement site has the wrong dimension"))
            all(1 <= coordinates[i] <= layout.shape[i]
                for i in eachindex(coordinates)) ||
                throw(ArgumentError("medium placement site is outside the lattice"))
            index = CartesianIndex(coordinates)
            assigned[index] &&
                throw(ArgumentError("ownership placements overlap at $(coordinates)"))
            assigned[index] = true
            labels[index] = encoded
        end
    end
    for placement in cell_placements
        isempty(placement.sites) &&
            throw(ArgumentError("every placed cell must own at least one site"))
        cells[placement.label] = placement.kind
        for coordinates in placement.sites
            length(coordinates) == length(layout.shape) ||
                throw(ArgumentError("cell placement site has the wrong dimension"))
            all(1 <= coordinates[i] <= layout.shape[i]
                for i in eachindex(coordinates)) ||
                throw(ArgumentError("cell placement site is outside the lattice"))
            index = CartesianIndex(coordinates)
            assigned[index] &&
                throw(ArgumentError("cell placements overlap at $(coordinates)"))
            assigned[index] = true
            labels[index] = Int32(placement.label)
        end
    end
    available = Int[
        index for index in eachindex(labels) if !assigned[index]
    ]
    required_sites = sum((
        placement.count * placement.sites_per_cell
        for placement in procedural_placements
    ); init = 0)
    required_sites <= length(available) || throw(ArgumentError(
        "procedural placements require $required_sites unassigned sites but " *
        "only $(length(available)) are available"
    ))
    for (operation_index, placement) in enumerate(procedural_placements)
        name = _kind_symbol(placement.kind)
        kind_index = get(kinds, name, nothing)
        kind_index !== nothing &&
            !executable.core_program.medium_kinds[kind_index] ||
            throw(ArgumentError(
                "procedural cell placement uses unknown or medium kind `$name`"
            ))
        invocation = 0
        for offset in 0:(placement.count - 1)
            label = placement.first_label + offset
            cells[label] = placement.kind
            for _ in 1:placement.sites_per_cell
                selected = CorePotts.initialization_bounded(
                    seed,
                    replica,
                    operation_index,
                    invocation,
                    length(available),
                )
                invocation += 1
                linear_index = available[selected]
                available[selected] = pop!(available)
                labels[linear_index] = Int32(label)
                assigned[linear_index] = true
            end
        end
    end
    Set(keys(cells)) == Set(1:maximum_label) || throw(ArgumentError(
        "ownership layout labels must be contiguous from 1"
    ))
    _, cell_kinds = _materialize_labelled(
        executable,
        LabelledCells(
            map(owner -> owner < 0 ? Int32(0) : owner, labels);
            cells,
            medium = layout.medium,
        ),
    )
    return labels, cell_kinds
end

function _state_name(value)
    value isa AbstractPottsStatement && return Symbol(statement_id(value))
    value isa Symbol && return value
    return try
        Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value)))
    catch
        throw(ArgumentError("initial state keys require a symbolic or statement identity"))
    end
end

function _initial_value_map(executable::PottsExecutable, initial::PottsInitialState)
    result = Dict{Symbol, Any}()
    for (key, value) in initial.values
        key_name = _state_name(key)
        state_index = findfirst(
            entry -> entry.key === key_name, executable.reports.states
        )
        name = state_index === nothing ?
               key_name : executable.reports.states[state_index].name
        haskey(result, name) &&
            throw(ArgumentError("duplicate initial value for `$name`"))
        result[name] = _defensive_copy(value)
    end
    return result
end

function _convert_initial_scalar(entry, value, ::Type{T}) where {
        T <: AbstractFloat,
    }
    converted = if entry.unit === nothing
        _is_quantity(value) && throw(ArgumentError(
            "initial state `$(entry.name)` is dimensionless"
        ))
        T(_numeric_value(value))
    else
        _is_quantity(value) || throw(ArgumentError(
            "initial state `$(entry.name)` requires units compatible with $(entry.unit)"
        ))
        T(_numeric_value(value, entry.unit))
    end
    isfinite(converted) ||
        throw(ArgumentError("initial state `$(entry.name)` must be finite"))
    return converted
end

function _normalize_initial_state_entry(
        entry,
        values,
        shape,
        cell_count,
        ::Type{T},
    ) where {T <: AbstractFloat}
    supplied = haskey(values, entry.name)
    if entry.storage === :history
        depth = last(entry.shape)
        if !supplied
            return Tuple(fill(T(entry.initial), shape) for _ in 1:depth)
        end
        value = values[entry.name]
        value isa Union{Tuple, AbstractVector} && length(value) == depth ||
            throw(ArgumentError(
                "initial history `$(entry.name)` requires $depth lattice snapshots"
            ))
        return Tuple(
            begin
                snapshot = value[index]
                snapshot isa AbstractArray && size(snapshot) == shape ||
                    throw(ArgumentError(
                        "initial history `$(entry.name)` snapshot $index has the wrong shape"
                    ))
                map(item -> _convert_initial_scalar(entry, item, T), snapshot)
            end
            for index in 1:depth
        )
    elseif entry.storage === :site
        !supplied && return fill(T(entry.initial), shape)
        value = values[entry.name]
        value isa AbstractArray && size(value) == shape ||
            throw(ArgumentError(
                "initial site state `$(entry.name)` has the wrong shape"
            ))
        return map(item -> _convert_initial_scalar(entry, item, T), value)
    elseif entry.storage === :cell
        !supplied && return fill(T(entry.initial), cell_count)
        value = values[entry.name]
        value isa AbstractVector && length(value) == cell_count ||
            throw(ArgumentError(
                "initial cell state `$(entry.name)` must have one value per cell"
            ))
        return T[_convert_initial_scalar(entry, item, T) for item in value]
    else
        !supplied && return T(entry.initial)
        value = values[entry.name]
        value isa AbstractArray && throw(ArgumentError(
            "initial $(entry.storage) state `$(entry.name)` must be scalar"
        ))
        return _convert_initial_scalar(entry, value, T)
    end
end

function _convert_relationship_payload_value(
        relationship,
        name::Symbol,
        value,
        ::Type{T},
    ) where {T <: AbstractFloat}
    reference = getproperty(relationship.payload_units, name)
    converted = if reference === nothing
        _is_quantity(value) && throw(ArgumentError(
            "relationship payload `$name` for `$(relationship.name)` is dimensionless"
        ))
        T(_numeric_value(value))
    else
        _is_quantity(value) || throw(ArgumentError(
            "relationship payload `$name` for `$(relationship.name)` requires " *
            "units compatible with $reference"
        ))
        T(_numeric_value(value, reference))
    end
    isfinite(converted) ||
        throw(ArgumentError(
            "relationship payload `$name` for `$(relationship.name)` must be finite"
        ))
    return converted
end

function _normalize_initial_relationships(
        relationship,
        value,
        ::Type{T},
    ) where {T <: AbstractFloat}
    value === nothing && return nothing
    value isa Union{Tuple, AbstractVector} ||
        throw(ArgumentError(
            "initial relationship `$(relationship.name)` must be a collection"
        ))
    length(value) <= relationship.capacity ||
        throw(ArgumentError(
            "initial relationship `$(relationship.name)` exceeds compiled capacity"
        ))
    return Tuple(
        begin
            entry isa Tuple && length(entry) in (2, 3) ||
                throw(ArgumentError(
                    "relationship entries are `(a, b)` or `(a, b, payload)`"
                ))
            if length(entry) == 2
                (entry[1], entry[2])
            else
                payload = entry[3]
                payload isa NamedTuple || throw(ArgumentError(
                    "relationship payloads must be named tuples"
                ))
                allowed = (
                    :strength,
                    :target,
                    :maximum,
                    :generation_a,
                    :generation_b,
                )
                all(name -> name in allowed, keys(payload)) ||
                    throw(ArgumentError(
                        "relationship payload contains an unsupported field"
                    ))
                converted = NamedTuple{keys(payload)}(map(
                    name -> name in (:generation_a, :generation_b) ?
                            UInt32(getproperty(payload, name)) :
                            _convert_relationship_payload_value(
                                relationship,
                                name,
                                getproperty(payload, name),
                                T,
                            ),
                    keys(payload),
                ))
                (entry[1], entry[2], converted)
            end
        end
        for entry in value
    )
end

function _core_initial_state(
        executable::PottsExecutable,
        initial::PottsInitialState,
        seed::UInt64 = UInt64(0),
        replica::UInt32 = UInt32(1),
    )
    ownership, cell_kinds = initial.ownership isa LabelledCells ?
        _materialize_labelled(executable, initial.ownership) :
        _materialize_layout(executable, initial.ownership, seed, replica)
    values = _initial_value_map(executable, initial)
    known = Set{Symbol}((:activity, :field))
    union!(known, entry.name for entry in executable.reports.states)
    union!(known, entry.name for entry in executable.reports.relationship_states)
    unknown = setdiff(Set(keys(values)), known)
    isempty(unknown) ||
        throw(ArgumentError("unknown initial state value$(length(unknown) == 1 ? "" : "s"): " *
                            join(string.(sort!(collect(unknown))), ", ")))
    T = eltype(executable.core_program.parameter_defaults)
    activity_entry = findfirst(entry -> entry.role === :activity,
        executable.reports.states)
    field_entry = findfirst(entry -> entry.role === :field,
        executable.reports.states)
    history_entry = findfirst(entry -> entry.role === :history,
        executable.reports.states)
    activity_name = activity_entry === nothing ? :activity :
                    executable.reports.states[activity_entry].name
    field_name = field_entry === nothing ? :field :
                 executable.reports.states[field_entry].name
    history_name = history_entry === nothing ? :history :
                   executable.reports.states[history_entry].name
    normalized_states = Dict{Symbol, Any}()
    for entry in executable.reports.states
        normalized_states[entry.name] = _normalize_initial_state_entry(
            entry,
            values,
            executable.core_program.shape,
            length(cell_kinds),
            T,
        )
    end
    activity = activity_entry === nothing ? nothing :
               normalized_states[activity_name]
    field = field_entry === nothing ? nothing : normalized_states[field_name]
    history = history_entry === nothing ? nothing :
              normalized_states[history_name]
    stored_entries = filter(
        entry -> entry.role === :stored, executable.reports.states
    )
    stored_names = Tuple(entry.name for entry in stored_entries)
    stored_states = NamedTuple{stored_names}(
        Tuple(normalized_states[entry.name] for entry in stored_entries)
    )
    descriptor_layout = executable.core_program.descriptor_plan.state_layout
    descriptor_initial_values = map(descriptor_layout.entries) do layout_entry
        name = layout_entry.schema.identity.name
        if haskey(stored_states, name)
            value = getproperty(stored_states, name)
            value isa AbstractArray ? value :
                fill(value, Tuple(layout_entry.schema.shape))
        else
            nothing
        end
    end
    descriptor_state = CorePotts.allocate_auxiliary_state(
        descriptor_layout, descriptor_initial_values
    )
    relationships = if isempty(executable.reports.relationship_states)
        nothing
    else
        relationship = only(executable.reports.relationship_states)
        _normalize_initial_relationships(
            relationship, get(values, relationship.name, nothing), T
        )
    end
    return CorePotts.ProgramInitialState(
        ownership,
        cell_kinds;
        scalar_type = T,
        activity,
        field,
        history,
        stored_states,
        relationships,
        descriptor_state,
    )
end
