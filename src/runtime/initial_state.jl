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

struct PottsInitialState{O, V <: Tuple, N <: Tuple}
    ownership::O
    values::V
    native::N
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

function _native_operating_points(values)
    values === nothing && return ()
    tuple = values isa NativeOperatingPoint ? (values,) : try
        Tuple(values)
    catch
        throw(ArgumentError(
            "native operating points must be NativeOperatingPoint values"
        ))
    end
    all(value -> value isa NativeOperatingPoint, tuple) || throw(ArgumentError(
        "native operating points must contain only NativeOperatingPoint values"
    ))
    paths = map(point -> point.path, tuple)
    length(unique(paths)) == length(paths) || throw(ArgumentError(
        "native operating-point paths must be unique"
    ))
    return map(_defensive_copy, tuple)
end

function PottsInitialState(; ownership, values = (), native = ())
    ownership isa Union{LabelledCells, OwnershipLayout} ||
        throw(ArgumentError(
            "ownership must be LabelledCells(...) or OwnershipLayout(...)"
        ))
    return PottsInitialState(
        _defensive_copy(ownership),
        _initial_value_pairs(values),
        _native_operating_points(native),
    )
end

_defensive_copy(value::LabelledCells) =
    LabelledCells(value.labels; cells = value.cells, medium = value.medium)
_defensive_copy(value::OwnershipLayout) = value
_defensive_copy(value::NativeOperatingPoint) = NativeOperatingPoint(
    value.path; values = value.values, guesses = value.guesses
)
_defensive_copy(value::PottsInitialState) = PottsInitialState(
    ownership = _defensive_copy(value.ownership),
    values = value.values,
    native = value.native,
)

function _kind_symbol(kind)
    kind isa Union{CellKind, MediumKind} && return Symbol(statement_id(kind))
    kind isa Symbol && return kind
    throw(ArgumentError("cell and medium kinds use declarations or Symbol names"))
end

function _kind_indices(executable::_PottsExecutionPlan)
    result = Dict(
        kind => index for (index, kind) in enumerate(executable.reports.kinds)
    )
    identities = executable.reports.kind_identities
    local_counts = Dict{Symbol, Int}()
    for entry in identities
        local_counts[entry.local_name] = get(
            local_counts, entry.local_name, 0
        ) + 1
    end
    for (index, entry) in enumerate(identities)
        local_counts[entry.local_name] == 1 || continue
        result[entry.local_name] = index
    end
    return result
end

function _materialize_labelled(
        executable::_PottsExecutionPlan, labelled::LabelledCells
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
        executable::_PottsExecutionPlan,
        layout::OwnershipLayout,
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
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
                selected = CorePotts.CompilerSPI.initialization_bounded(
                    seed,
                    replica,
                    repeat,
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

function _initial_value_map(executable::_PottsExecutionPlan, initial::PottsInitialState)
    result = Dict{Symbol, Any}()
    entries = (
        executable.reports.states...,
        executable.reports.relationship_states...,
    )
    for (key, value) in initial.values
        key_name = _state_name(key)
        matches = findall(
            entry -> entry.name === key_name ||
                     (haskey(entry, :key) && entry.key === key_name),
            entries,
        )
        if isempty(matches)
            matches = findall(
                entry -> entry.local_name === key_name ||
                         (haskey(entry, :local_key) &&
                          entry.local_key === key_name),
                entries,
            )
        end
        length(matches) <= 1 || throw(ArgumentError(
            "initial state key `$key_name` is ambiguous; use its qualified name"
        ))
        name = isempty(matches) ? key_name : entries[only(matches)].name
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
        cell_capacity,
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
        !supplied && return fill(T(entry.initial), cell_capacity)
        value = values[entry.name]
        value isa AbstractVector && length(value) in (cell_count, cell_capacity) ||
            throw(ArgumentError(
                "initial cell state `$(entry.name)` must have one value per " *
                "active cell or one value per compiled cell slot"
            ))
        result = fill(T(entry.initial), cell_capacity)
        for index in eachindex(value)
            result[index] = _convert_initial_scalar(entry, value[index], T)
        end
        return result
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
                payload_names = keys(relationship.payload_units)
                allowed = (payload_names..., :generation_a, :generation_b)
                all(name -> name in allowed, keys(payload)) ||
                    throw(ArgumentError(
                        "relationship payload contains an unsupported field"
                    ))
                converted = ntuple(length(payload_names)) do slot
                    name = payload_names[slot]
                    haskey(payload, name) ?
                    _convert_relationship_payload_value(
                        relationship,
                        name,
                        getproperty(payload, name),
                        T,
                    ) : nothing
                end
                generation_a = haskey(payload, :generation_a) ?
                               UInt32(payload.generation_a) : nothing
                generation_b = haskey(payload, :generation_b) ?
                               UInt32(payload.generation_b) : nothing
                (
                    entry[1], entry[2], converted,
                    generation_a, generation_b,
                )
            end
        end
        for entry in value
    )
end

function _validate_initial_relationship_endpoints!(
        relationship,
        endpoint_policy::CompiledRelationshipEndpointPolicy,
        entries,
        cell_kinds::Vector{Int16},
    )
    entries === nothing && return entries
    endpoint_policy.direction === :undirected || throw(ArgumentError(
        "initial relationship `$(relationship.name)` requires unsupported " *
        "directed endpoint semantics"
    ))
    for entry in entries
        endpoint_a, endpoint_b = entry[1], entry[2]
        endpoint_a isa Integer && endpoint_b isa Integer || continue
        1 <= endpoint_a <= length(cell_kinds) || continue
        1 <= endpoint_b <= length(cell_kinds) || continue
        actual_a = @inbounds cell_kinds[endpoint_a]
        actual_b = @inbounds cell_kinds[endpoint_b]
        _undirected_endpoint_kinds_match(
            actual_a,
            actual_b,
            endpoint_policy.kind_a,
            endpoint_policy.kind_b,
        ) || throw(ArgumentError(
            "initial relationship `$(relationship.name)` endpoint kinds do " *
            "not satisfy its declared Undirected contract"
        ))
    end
    return entries
end

function _core_initial_state(
        executable::_PottsExecutionPlan,
        initial::PottsInitialState,
        seed::UInt64 = UInt64(0),
        replica::UInt32 = UInt32(1),
        repeat::UInt32 = UInt32(1),
    )
    ownership, cell_kinds = initial.ownership isa LabelledCells ?
        _materialize_labelled(executable, initial.ownership) :
        _materialize_layout(executable, initial.ownership, seed, replica, repeat)
    values = _initial_value_map(executable, initial)
    known = Set{Symbol}()
    union!(known, entry.name for entry in executable.reports.states)
    union!(known, entry.name for entry in executable.reports.relationship_states)
    unknown = setdiff(Set(keys(values)), known)
    isempty(unknown) ||
        throw(ArgumentError("unknown initial state value$(length(unknown) == 1 ? "" : "s"): " *
                            join(string.(sort!(collect(unknown))), ", ")))
    T = eltype(executable.core_program.parameter_defaults)
    lifecycle_plan = executable.core_program.lifecycle_plan
    cell_capacity = lifecycle_plan isa CorePotts.CompilerSPI.LifecycleExecutionPlan ?
        Int(lifecycle_plan.cell_capacity) : length(cell_kinds)
    length(cell_kinds) <= cell_capacity || throw(ArgumentError(
        "initial finite-cell count exceeds compiled max_cells=$cell_capacity"
    ))
    normalized_states = Dict{CorePotts.CompilerSPI.QualifiedResourceIdentity, Any}()
    for entry in executable.reports.states
        normalized_states[entry.identity] = _normalize_initial_state_entry(
            entry,
            values,
            executable.core_program.shape,
            length(cell_kinds),
            cell_capacity,
            T,
        )
    end
    descriptor_layout = executable.core_program.descriptor_plan.state_layout
    descriptor_initial_values = map(descriptor_layout.entries) do layout_entry
        identity = layout_entry.schema.identity
        if haskey(normalized_states, identity)
            value = normalized_states[identity]
            if value isa Tuple && all(item -> item isa AbstractArray, value)
                shape = Tuple(layout_entry.schema.shape)
                length(shape) > 1 && length(value) == last(shape) ||
                    throw(ArgumentError(
                        "history state `$identity` is incompatible with its descriptor layout"
                    ))
                packed = Array{layout_entry.schema.element_type}(undef, shape)
                for index in eachindex(value)
                    copyto!(selectdim(packed, length(shape), index), value[index])
                end
                packed
            elseif value isa AbstractArray
                value
            else
                fill(value, Tuple(layout_entry.schema.shape))
            end
        else
            nothing
        end
    end
    descriptor_state = CorePotts.CompilerSPI.allocate_auxiliary_state(
        descriptor_layout, descriptor_initial_values
    )
    relationships = Tuple(
        let endpoint_policy = _relationship_endpoint_policy(
                executable.relationship_endpoint_policies,
                relationship.identity,
            )
            _validate_initial_relationship_endpoints!(
                relationship,
                endpoint_policy,
                _normalize_initial_relationships(
                    relationship, get(values, relationship.name, nothing), T
                ),
                cell_kinds,
            )
        end
        for relationship in executable.reports.relationship_states
    )
    return CorePotts.ProgramInitialState(
        ownership,
        cell_kinds;
        scalar_type = T,
        relationships,
        descriptor_state,
    )
end
