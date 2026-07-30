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

struct MediumPlacement{K}
    kind::K
end

struct OwnershipLayout{N, P <: Tuple, M}
    shape::NTuple{N, Int}
    placements::P
    medium::M
end

function OwnershipLayout(
        shape::NTuple{N, <:Integer},
        placements::CellPlacement...;
        medium,
    ) where {N}
    normalized_shape = Tuple(Int.(shape))
    all(>(0), normalized_shape) ||
        throw(ArgumentError("ownership layout dimensions must be positive"))
    labels = Int[placement.label for placement in placements]
    length(unique(labels)) == length(labels) ||
        throw(ArgumentError("ownership layout cell labels must be unique"))
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
        Symbol(statement_id(kind)) => index
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
    medium_index == program.medium_kind ||
        throw(ArgumentError("initial medium does not match the executable medium"))
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
            index == program.medium_kind &&
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
            index == program.medium_kind &&
                throw(ArgumentError("a positive cell label cannot use the medium kind"))
            cell_kinds[label] = Int16(index)
        end
    end
    return copy(labelled.labels), cell_kinds
end

function _materialize_layout(
        executable::PottsExecutable, layout::OwnershipLayout
    )
    layout.shape == executable.core_program.shape ||
        throw(ArgumentError("ownership layout shape does not match the executable"))
    maximum_label = maximum(
        (placement.label for placement in layout.placements); init = 0
    )
    labels = zeros(Int32, layout.shape)
    cells = Dict{Int, Any}()
    for placement in layout.placements
        cells[placement.label] = placement.kind
        for coordinates in placement.sites
            length(coordinates) == length(layout.shape) ||
                throw(ArgumentError("cell placement site has the wrong dimension"))
            all(1 <= coordinates[i] <= layout.shape[i]
                for i in eachindex(coordinates)) ||
                throw(ArgumentError("cell placement site is outside the lattice"))
            index = CartesianIndex(coordinates)
            labels[index] == 0 ||
                throw(ArgumentError("cell placements overlap at $(coordinates)"))
            labels[index] = Int32(placement.label)
        end
    end
    Set(keys(cells)) == Set(1:maximum_label) || throw(ArgumentError(
        "ownership layout labels must be contiguous from 1"
    ))
    return _materialize_labelled(
        executable, LabelledCells(labels; cells, medium = layout.medium)
    )
end

function _state_name(value)
    value isa AbstractPottsStatement && return Symbol(statement_id(value))
    value isa Symbol && return value
    return try
        Symbol(Symbolics.getname(Symbolics.unwrap(value)))
    catch
        throw(ArgumentError("initial state keys require a symbolic or statement identity"))
    end
end

function _initial_value_map(initial::PottsInitialState)
    result = Dict{Symbol, Any}()
    for (key, value) in initial.values
        name = _state_name(key)
        haskey(result, name) &&
            throw(ArgumentError("duplicate initial value for `$name`"))
        result[name] = _defensive_copy(value)
    end
    return result
end

function _core_initial_state(executable::PottsExecutable, initial::PottsInitialState)
    ownership, cell_kinds = initial.ownership isa LabelledCells ?
        _materialize_labelled(executable, initial.ownership) :
        _materialize_layout(executable, initial.ownership)
    values = _initial_value_map(initial)
    known = Set{Symbol}((:activity, :field))
    unknown = setdiff(Set(keys(values)), known)
    isempty(unknown) ||
        throw(ArgumentError("unknown initial state value$(length(unknown) == 1 ? "" : "s"): " *
                            join(string.(sort!(collect(unknown))), ", ")))
    T = eltype(executable.core_program.parameter_defaults)
    activity = get(values, :activity, nothing)
    field = get(values, :field, nothing)
    return CorePotts.ProgramInitialState(
        ownership,
        cell_kinds;
        scalar_type = T,
        activity,
        field,
    )
end
