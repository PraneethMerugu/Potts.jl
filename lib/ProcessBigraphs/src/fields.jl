const FIELD_BOUNDARY_KINDS = (:periodic, :dirichlet, :neumann, :mixed)
const FIELD_SAMPLING_LAWS = (:nearest, :linear)
const FIELD_PLACEMENTS = (:cell_centered,)
const FIELD_OPERATION_KINDS =
    (:evolve, :sample, :deposit, :exchange, :uptake, :account, :custom)

struct FieldGeometry{N,T<:Real}
    dimensions::NTuple{N,Int}
    origin::NTuple{N,T}
    spacing::NTuple{N,T}
    extent::NTuple{N,T}
    axis_order::NTuple{N,Symbol}
end

function FieldGeometry(
    dimensions::NTuple{N,<:Integer};
    origin::NTuple{N,<:Real}=ntuple(_ -> 0.0, N),
    spacing::NTuple{N,<:Real}=ntuple(_ -> 1.0, N),
    axis_order::NTuple{N,Symbol}=ntuple(i -> Symbol(:x, i), N),
) where {N}
    N in (2, 3) ||
        _fail(:unsupported_field_rank, "Phase 16 fields must be 2D or 3D"; rank=N)
    all(value -> value > 0, dimensions) ||
        _fail(:invalid_field_dimensions, "field dimensions must be positive";
            dimensions)
    all(value -> value > 0 && isfinite(value), spacing) ||
        _fail(:invalid_field_spacing, "field spacing must be positive and finite";
            spacing)
    all(isfinite, origin) ||
        _fail(:invalid_field_origin, "field origin must be finite"; origin)
    length(unique(axis_order)) == N ||
        _fail(:duplicate_field_axis, "field axis identities must be unique"; axis_order)
    T = promote_type(
        map(typeof, origin)...,
        map(typeof, spacing)...,
    )
    normalized_dimensions = ntuple(i -> Int(dimensions[i]), N)
    normalized_origin = ntuple(i -> convert(T, origin[i]), N)
    normalized_spacing = ntuple(i -> convert(T, spacing[i]), N)
    extent = ntuple(i ->
        normalized_origin[i] +
        normalized_dimensions[i] * normalized_spacing[i], N)
    FieldGeometry(
        normalized_dimensions,
        normalized_origin,
        normalized_spacing,
        extent,
        axis_order,
    )
end

struct FieldBoundary
    axis::Int
    side::Symbol
    kind::Symbol
    parameters::NamedTuple
end

function FieldBoundary(
    axis::Integer,
    side::Symbol,
    kind::Symbol;
    parameters::NamedTuple=NamedTuple(),
)
    axis > 0 || _fail(:invalid_boundary_axis, "boundary axis must be positive"; axis)
    side in (:low, :high) ||
        _fail(:invalid_boundary_side, "boundary side must be low or high"; side)
    kind in FIELD_BOUNDARY_KINDS ||
        _fail(:invalid_boundary_kind, "unknown field boundary kind"; kind)
    if kind === :periodic
        isempty(parameters) ||
            _fail(:periodic_boundary_parameters,
                "periodic boundaries cannot carry solver-specific parameters")
    elseif kind === :dirichlet
        haskey(parameters, :value) ||
            _fail(:missing_dirichlet_value,
                "Dirichlet boundaries require a declared value")
    elseif kind === :neumann
        haskey(parameters, :flux) ||
            _fail(:missing_neumann_flux,
                "Neumann boundaries require a declared flux")
    else
        all(key -> haskey(parameters, key), (:alpha, :beta, :value)) ||
            _fail(:missing_mixed_boundary_parameters,
                "mixed boundaries require alpha, beta, and value")
    end
    FieldBoundary(Int(axis), side, kind, deepcopy(parameters))
end

function periodic_field_boundaries(rank::Integer)
    rank in (2, 3) ||
        _fail(:unsupported_field_rank, "Phase 16 fields must be 2D or 3D"; rank)
    tuple((
        FieldBoundary(axis, side, :periodic)
        for axis in 1:rank for side in (:low, :high)
    )...)
end

struct FieldDescriptor{N,T<:Real}
    id::String
    species::Tuple{Vararg{Symbol}}
    geometry::FieldGeometry{N,T}
    numeric_type::DataType
    units::Tuple{Vararg{Pair{Symbol,String}}}
    placement::Symbol
    sampling_law::Symbol
    boundaries::Tuple{Vararg{FieldBoundary}}
    operation::String
    positivity::Symbol
    conservation::Symbol
    insufficiency::Symbol
    accounting_tolerance::Float64
    backend::Symbol
    residency::Symbol
    semantic_time::LogicalTime
    version::UInt64
    fingerprint::String
end

function FieldDescriptor(
    id::AbstractString,
    species,
    geometry::FieldGeometry{N,T};
    numeric_type::DataType=Float64,
    units=tuple((Symbol(name) => "dimensionless" for name in species)...),
    placement::Symbol=:cell_centered,
    sampling_law::Symbol=:linear,
    boundaries=periodic_field_boundaries(N),
    operation::AbstractString="prescribed",
    positivity::Symbol=:reject,
    conservation::Symbol=:conservative,
    insufficiency::Symbol=:reject,
    accounting_tolerance::Real=0.0,
    backend::Symbol=:cpu,
    residency::Symbol=:host,
    semantic_time::LogicalTime=LogicalTime(0, TimeScale(1)),
    version::Integer=0,
) where {N,T<:Real}
    isempty(id) && _fail(:empty_field_identity, "field identity cannot be empty")
    normalized_species = tuple(Symbol.(species)...)
    isempty(normalized_species) &&
        _fail(:empty_field_species, "field descriptor requires at least one species")
    length(normalized_species) == length(unique(normalized_species)) ||
        _fail(:duplicate_field_species, "field species identities must be unique")
    numeric_type <: Number ||
        _fail(:invalid_field_numeric_type, "field numeric type must be numeric";
            numeric_type)
    normalized_units = tuple((Symbol(first(unit)) => String(last(unit))
        for unit in units)...)
    Set(first.(normalized_units)) == Set(normalized_species) ||
        _fail(:field_unit_mismatch,
            "field units must cover each species exactly once")
    placement in FIELD_PLACEMENTS ||
        _fail(:unsupported_field_placement,
            "Phase 16 stable fields are cell-centered"; placement)
    sampling_law in FIELD_SAMPLING_LAWS ||
        _fail(:unsupported_sampling_law, "unsupported field sampling law";
            sampling_law)
    normalized_boundaries = tuple(boundaries...)
    length(normalized_boundaries) == 2N ||
        _fail(:incomplete_field_boundaries,
            "every low/high field face must be declared";
            expected=2N, actual=length(normalized_boundaries))
    faces = Set((boundary.axis, boundary.side) for boundary in normalized_boundaries)
    faces == Set((axis, side) for axis in 1:N for side in (:low, :high)) ||
        _fail(:invalid_field_boundary_faces,
            "field boundary faces must cover every axis exactly once")
    for axis in 1:N
        low = only(boundary for boundary in normalized_boundaries
            if boundary.axis == axis && boundary.side === :low)
        high = only(boundary for boundary in normalized_boundaries
            if boundary.axis == axis && boundary.side === :high)
        (low.kind === :periodic) == (high.kind === :periodic) ||
            _fail(:unpaired_periodic_boundary,
                "periodic boundaries must be paired on an axis"; axis)
    end
    positivity in (:reject, :allow, :declared_floor) ||
        _fail(:invalid_positivity_policy, "unknown field positivity policy"; positivity)
    conservation in (:conservative, :nonconservative) ||
        _fail(:invalid_conservation_policy, "unknown field conservation policy";
            conservation)
    insufficiency in (:reject, :partial_proportional, :stable_priority) ||
        _fail(:invalid_insufficiency_policy, "unknown field insufficiency policy";
            insufficiency)
    accounting_tolerance >= 0 && isfinite(accounting_tolerance) ||
        _fail(:invalid_accounting_tolerance,
            "field accounting tolerance must be finite and nonnegative")
    backend in ENGINE_BACKENDS ||
        _fail(:unknown_engine_backend, "unknown field backend"; backend)
    residency in (:host, :device, :unified) ||
        _fail(:unknown_engine_residency, "unknown field residency"; residency)
    version >= 0 && version <= typemax(UInt64) ||
        _fail(:field_version_overflow, "field version must fit UInt64"; version)
    payload = (
        :process_bigraph_field_descriptor_v1,
        String(id),
        normalized_species,
        geometry,
        string(numeric_type),
        normalized_units,
        placement,
        sampling_law,
        normalized_boundaries,
        String(operation),
        positivity,
        conservation,
        insufficiency,
        Float64(accounting_tolerance),
        backend,
        residency,
        semantic_time,
        UInt64(version),
    )
    FieldDescriptor(
        String(id),
        normalized_species,
        geometry,
        numeric_type,
        normalized_units,
        placement,
        sampling_law,
        normalized_boundaries,
        String(operation),
        positivity,
        conservation,
        insufficiency,
        Float64(accounting_tolerance),
        backend,
        residency,
        semantic_time,
        UInt64(version),
        canonical_fingerprint(payload),
    )
end

struct FieldState{D<:FieldDescriptor,T}
    descriptor::D
    time::LogicalTime
    version::UInt64
    values::Tuple{Vararg{T}}
    fingerprint::String
end

function FieldState(
    descriptor::D,
    values::AbstractArray;
    time::LogicalTime=descriptor.semantic_time,
    version::Integer=descriptor.version,
) where {D<:FieldDescriptor}
    expected = (descriptor.geometry.dimensions..., length(descriptor.species))
    size(values) == expected ||
        _fail(:field_shape_mismatch,
            "field realization shape does not match its descriptor";
            expected, actual=size(values))
    eltype(values) == descriptor.numeric_type ||
        _fail(:field_eltype_mismatch,
            "field realization numeric type does not match its descriptor";
            expected=descriptor.numeric_type, actual=eltype(values))
    _same_scale(descriptor.semantic_time, time)
    time >= descriptor.semantic_time ||
        _fail(:field_time_regression,
            "field state cannot precede its descriptor semantic time")
    version >= descriptor.version && version <= typemax(UInt64) ||
        _fail(:field_version_regression,
            "field state version cannot precede the descriptor version")
    owned = copy(values)
    if descriptor.positivity === :reject && any(value -> value < zero(value), owned)
        _fail(:negative_field_state,
            "field state violates its reject-negative positivity policy")
    end
    fingerprint = canonical_fingerprint((
        :process_bigraph_field_state_v1,
        descriptor.fingerprint,
        time,
        UInt64(version),
        tuple(vec(owned)...),
    ))
    FieldState(descriptor, time, UInt64(version), tuple(vec(owned)...), fingerprint)
end

function field_values(state::FieldState)
    shape = (state.descriptor.geometry.dimensions...,
        length(state.descriptor.species))
    reshape(collect(state.values), shape)
end

struct FieldSampler{N,T<:Real}
    field::String
    species::Symbol
    position::NTuple{N,T}
    law::Symbol
end

function FieldSampler(
    descriptor::FieldDescriptor{N},
    species::Symbol,
    position::NTuple{N,<:Real};
    law::Symbol=descriptor.sampling_law,
) where {N}
    species in descriptor.species ||
        _fail(:unknown_field_species, "field sampler requested an unknown species";
            field=descriptor.id, species)
    law in FIELD_SAMPLING_LAWS ||
        _fail(:unsupported_sampling_law, "unsupported field sampling law"; law)
    T = promote_type(map(typeof, position)...)
    FieldSampler(descriptor.id, species,
        ntuple(i -> convert(T, position[i]), N), law)
end

function _field_species_index(descriptor::FieldDescriptor, species::Symbol)
    index = findfirst(==(species), descriptor.species)
    isnothing(index) &&
        _fail(:unknown_field_species, "unknown field species";
            field=descriptor.id, species)
    index
end

function _boundary_pair(descriptor::FieldDescriptor, axis::Int)
    low = only(boundary for boundary in descriptor.boundaries
        if boundary.axis == axis && boundary.side === :low)
    high = only(boundary for boundary in descriptor.boundaries
        if boundary.axis == axis && boundary.side === :high)
    low, high
end

function _normalize_position(descriptor::FieldDescriptor{N}, position) where {N}
    geometry = descriptor.geometry
    ntuple(N) do axis
        value = position[axis]
        low = geometry.origin[axis]
        high = geometry.extent[axis]
        low_boundary, high_boundary = _boundary_pair(descriptor, axis)
        if low <= value < high
            value
        elseif low_boundary.kind === :periodic &&
               high_boundary.kind === :periodic
            width = high - low
            low + mod(value - low, width)
        else
            _fail(:field_sample_out_of_bounds,
                "field coordinate lies outside a nonperiodic domain";
                field=descriptor.id, axis, value, low, high)
        end
    end
end

function _field_weights(
    descriptor::FieldDescriptor{N},
    position,
    law::Symbol,
) where {N}
    geometry = descriptor.geometry
    normalized = _normalize_position(descriptor, position)
    if law === :nearest
        index = ntuple(N) do axis
            coordinate = (normalized[axis] - geometry.origin[axis]) /
                geometry.spacing[axis]
            clamp(floor(Int, coordinate) + 1, 1, geometry.dimensions[axis])
        end
        return ((index, 1.0),)
    end

    lower = ntuple(N) do axis
        coordinate = (normalized[axis] - geometry.origin[axis]) /
            geometry.spacing[axis] + 0.5
        floor(Int, coordinate)
    end
    fraction = ntuple(N) do axis
        coordinate = (normalized[axis] - geometry.origin[axis]) /
            geometry.spacing[axis] + 0.5
        coordinate - floor(coordinate)
    end
    weighted = Pair{NTuple{N,Int},Float64}[]
    for corner in Iterators.product(ntuple(_ -> (0, 1), N)...)
        raw = ntuple(axis -> lower[axis] + corner[axis], N)
        index = ntuple(N) do axis
            dimension = geometry.dimensions[axis]
            low_boundary, high_boundary = _boundary_pair(descriptor, axis)
            if low_boundary.kind === :periodic && high_boundary.kind === :periodic
                mod1(raw[axis], dimension)
            else
                clamp(raw[axis], 1, dimension)
            end
        end
        weight = prod(corner[axis] == 0 ?
            1 - fraction[axis] : fraction[axis] for axis in 1:N)
        existing = findfirst(pair -> first(pair) == index, weighted)
        if isnothing(existing)
            push!(weighted, index => Float64(weight))
        else
            weighted[existing] = index => (last(weighted[existing]) + Float64(weight))
        end
    end
    tuple(weighted...)
end

function sample_field(state::FieldState, sampler::FieldSampler)
    sampler.field == state.descriptor.id ||
        _fail(:field_sampler_identity_mismatch,
            "field sampler belongs to another field")
    species_index = _field_species_index(state.descriptor, sampler.species)
    weights = _field_weights(state.descriptor, sampler.position, sampler.law)
    values = field_values(state)
    sum(last(weight) *
        values[first(weight)..., species_index] for weight in weights)
end

struct FieldDeposition{N,T<:Real}
    field::String
    species::Symbol
    source::String
    positions::Tuple{Vararg{NTuple{N,T}}}
    quantities::Tuple{Vararg{T}}
    law::Symbol
    units::String
    conservative::Bool
end

function FieldDeposition(
    descriptor::FieldDescriptor{N},
    species::Symbol,
    source::AbstractString,
    positions,
    quantities;
    law::Symbol=descriptor.sampling_law,
    units=nothing,
    conservative::Bool=true,
) where {N}
    species in descriptor.species ||
        _fail(:unknown_field_species, "deposition requested an unknown species";
            species)
    normalized_positions = tuple(positions...)
    normalized_quantities = tuple(quantities...)
    length(normalized_positions) == length(normalized_quantities) ||
        _fail(:deposition_length_mismatch,
            "deposition positions and quantities must have equal length")
    isempty(normalized_positions) &&
        _fail(:empty_field_deposition, "field deposition cannot be empty")
    all(position -> length(position) == N, normalized_positions) ||
        _fail(:field_position_rank_mismatch,
            "deposition position rank does not match the field")
    all(quantity -> isfinite(quantity), normalized_quantities) ||
        _fail(:nonfinite_field_quantity, "deposition quantities must be finite")
    T = promote_type(
        (typeof(value) for position in normalized_positions for value in position)...,
        map(typeof, normalized_quantities)...,
    )
    declared_units = species in descriptor.species ?
        last(only(unit for unit in descriptor.units if first(unit) === species)) :
        ""
    normalized_units = isnothing(units) ? declared_units : String(units)
    FieldDeposition(
        descriptor.id,
        species,
        String(source),
        tuple((ntuple(i -> convert(T, position[i]), N)
            for position in normalized_positions)...),
        tuple(convert.(T, normalized_quantities)...),
        law,
        normalized_units,
        conservative,
    )
end

struct FieldAccounting
    operation::Symbol
    source_quantity::Float64
    destination_quantity::Float64
    declared_source_or_sink::Float64
    residual::Float64
    tolerance::Float64
    conservative::Bool
end

function deposit_field(state::FieldState, deposition::FieldDeposition)
    descriptor = state.descriptor
    deposition.field == descriptor.id ||
        _fail(:field_deposition_identity_mismatch,
            "field deposition belongs to another field")
    species_index = _field_species_index(descriptor, deposition.species)
    declared_units = last(only(unit for unit in descriptor.units
        if first(unit) === deposition.species))
    deposition.units == declared_units ||
        _fail(:field_unit_mismatch, "deposition units do not match field units";
            expected=declared_units, actual=deposition.units)
    current = field_values(state)
    candidate = copy(current)
    source = sum(Float64, deposition.quantities)
    for (position, quantity) in zip(deposition.positions, deposition.quantities)
        for weighted in _field_weights(descriptor, position, deposition.law)
            index, weight = weighted
            candidate[index..., species_index] +=
                convert(eltype(candidate), quantity * weight)
        end
    end
    destination = sum(Float64, candidate) - sum(Float64, current)
    residual = source - destination
    tolerance = descriptor.accounting_tolerance
    deposition.conservative && abs(residual) > tolerance &&
        _fail(:field_conservation_failure,
            "conservative deposition exceeded its accounting tolerance";
            source, destination, residual, tolerance)
    next_version = try
        Base.Checked.checked_add(state.version, UInt64(1))
    catch
        _fail(:field_version_overflow, "field state version exceeds UInt64";
            field=descriptor.id)
    end
    next = FieldState(descriptor, candidate;
        time=state.time, version=next_version)
    accounting = FieldAccounting(
        :deposit,
        source,
        destination,
        deposition.conservative ? 0.0 : source - destination,
        deposition.conservative ? residual : 0.0,
        tolerance,
        deposition.conservative,
    )
    next, accounting
end

struct FieldExchange{T<:Real}
    id::String
    available::T
    demands::Tuple{Vararg{Pair{String,T}}}
    allocation::Symbol
    insufficiency::Symbol
    positivity::Symbol
    conservative::Bool
    declared_source_or_sink::T
    tolerance::Float64
end

function FieldExchange(
    id::AbstractString,
    available::Real,
    demands;
    allocation::Symbol=:proportional,
    insufficiency::Symbol=:partial_proportional,
    positivity::Symbol=:reject,
    conservative::Bool=true,
    declared_source_or_sink::Real=0,
    tolerance::Real=0,
)
    available >= 0 && isfinite(available) ||
        _fail(:invalid_exchange_available,
            "exchange availability must be finite and nonnegative")
    normalized_demands = tuple((String(first(demand)) => last(demand)
        for demand in demands)...)
    isempty(normalized_demands) &&
        _fail(:empty_field_exchange, "field exchange requires consumers")
    identities = String[first(demand) for demand in normalized_demands]
    length(identities) == length(unique(identities)) ||
        _fail(:duplicate_exchange_consumer,
            "field exchange consumer identities must be unique")
    all(demand -> last(demand) >= 0 && isfinite(last(demand)),
        normalized_demands) ||
        _fail(:invalid_exchange_demand,
            "exchange demands must be finite and nonnegative")
    allocation in (:proportional, :stable_priority) ||
        _fail(:invalid_exchange_allocation, "unknown exchange allocation law";
            allocation)
    insufficiency in (:reject, :partial_proportional, :stable_priority) ||
        _fail(:invalid_insufficiency_policy, "unknown exchange insufficiency policy";
            insufficiency)
    positivity in (:reject, :allow, :declared_floor) ||
        _fail(:invalid_positivity_policy, "unknown exchange positivity policy";
            positivity)
    tolerance >= 0 && isfinite(tolerance) ||
        _fail(:invalid_accounting_tolerance,
            "exchange tolerance must be finite and nonnegative")
    T = promote_type(
        typeof(available),
        typeof(declared_source_or_sink),
        (typeof(last(demand)) for demand in normalized_demands)...,
    )
    FieldExchange(
        String(id),
        convert(T, available),
        tuple((first(demand) => convert(T, last(demand))
            for demand in normalized_demands)...),
        allocation,
        insufficiency,
        positivity,
        conservative,
        convert(T, declared_source_or_sink),
        Float64(tolerance),
    )
end

struct FieldExchangeResult{T<:Real}
    allocations::Tuple{Vararg{Pair{String,T}}}
    remaining::T
    accounting::FieldAccounting
end

function execute_exchange(exchange::FieldExchange{T}) where {T}
    total_demand = sum(last, exchange.demands; init=zero(T))
    available = exchange.available
    if total_demand > available && exchange.insufficiency === :reject
        _fail(:insufficient_field_material,
            "field exchange demand exceeds availability";
            exchange=exchange.id, available, total_demand)
    end
    allocations = if total_demand <= available
        exchange.demands
    elseif exchange.insufficiency === :partial_proportional
        ratio = available / total_demand
        tuple((first(demand) => last(demand) * ratio
            for demand in exchange.demands)...)
    else
        remaining = available
        result = Pair{String,T}[]
        for demand in sort(collect(exchange.demands); by=first)
            allocated = min(last(demand), remaining)
            push!(result, first(demand) => allocated)
            remaining -= allocated
        end
        tuple(result...)
    end
    allocated = sum(last, allocations; init=zero(T))
    remaining = available - allocated + exchange.declared_source_or_sink
    if exchange.positivity === :reject && remaining < zero(T)
        _fail(:negative_exchange_result,
            "field exchange would produce a negative reservoir";
            exchange=exchange.id, remaining)
    end
    destination = Float64(allocated + remaining)
    source = Float64(available)
    declared = Float64(exchange.declared_source_or_sink)
    residual = source + declared - destination
    exchange.conservative && abs(residual) > exchange.tolerance &&
        _fail(:field_conservation_failure,
            "field exchange exceeded its accounting tolerance";
            exchange=exchange.id, residual, tolerance=exchange.tolerance)
    accounting = FieldAccounting(
        :exchange,
        source,
        destination,
        declared,
        residual,
        exchange.tolerance,
        exchange.conservative,
    )
    FieldExchangeResult(allocations, remaining, accounting)
end

struct FieldIterationRegion
    id::String
    operations::Tuple{Vararg{String}}
    max_iterations::Int
end

function FieldIterationRegion(
    id::AbstractString,
    operations;
    max_iterations::Integer,
)
    normalized = tuple(String.(operations)...)
    isempty(id) && _fail(:empty_field_iteration_identity,
        "field iteration identity cannot be empty")
    isempty(normalized) && _fail(:empty_field_iteration_region,
        "field iteration region requires operations")
    length(normalized) == length(unique(normalized)) ||
        _fail(:duplicate_field_iteration_operation,
            "field iteration operations must be unique")
    max_iterations > 0 ||
        _fail(:invalid_iteration_bound, "field iteration bound must be positive")
    FieldIterationRegion(String(id), normalized, Int(max_iterations))
end

struct NamedFieldOperation
    id::String
    kind::Symbol
    start_time::LogicalTime
    target_time::LogicalTime
    input_mode::Symbol
    dependencies::Tuple{Vararg{String}}
end

function NamedFieldOperation(
    id::AbstractString,
    kind::Symbol,
    start_time::LogicalTime,
    target_time::LogicalTime;
    input_mode::Symbol=:frozen,
    dependencies=(),
)
    isempty(id) && _fail(:empty_field_operation_identity,
        "field operation identity cannot be empty")
    kind in FIELD_OPERATION_KINDS ||
        _fail(:unknown_field_operation, "unknown field operation kind"; kind)
    _same_scale(start_time, target_time)
    target_time >= start_time ||
        _fail(:field_operation_time_regression,
            "field operation target cannot precede its start"; id)
    input_mode in ENGINE_INPUT_MODES ||
        _fail(:unknown_engine_input_mode, "unknown field input mode"; input_mode)
    normalized_dependencies = tuple(String.(dependencies)...)
    length(normalized_dependencies) == length(unique(normalized_dependencies)) ||
        _fail(:duplicate_field_dependency,
            "field operation dependencies must be unique"; id)
    NamedFieldOperation(
        String(id),
        kind,
        start_time,
        target_time,
        input_mode,
        normalized_dependencies,
    )
end

struct FieldSplitPlan
    operations::Tuple{Vararg{NamedFieldOperation}}
    iterative_regions::Tuple{Vararg{FieldIterationRegion}}
    fingerprint::String
end

function FieldSplitPlan(operations; iterative_regions=())
    normalized_operations = tuple(operations...)
    isempty(normalized_operations) &&
        _fail(:empty_field_split, "a field split requires named operations")
    ids = String[operation.id for operation in normalized_operations]
    length(ids) == length(unique(ids)) ||
        _fail(:duplicate_field_operation, "field operation identities must be unique")
    id_set = Set(ids)
    for operation in normalized_operations
        Set(operation.dependencies) <= id_set ||
            _fail(:unknown_field_dependency,
                "field operation depends on an unknown operation";
                operation=operation.id)
        operation.id in operation.dependencies &&
            _fail(:self_field_dependency,
                "field operation cannot directly depend on itself";
                operation=operation.id)
    end
    regions = tuple(iterative_regions...)
    region_ids = String[region.id for region in regions]
    length(region_ids) == length(unique(region_ids)) ||
        _fail(:duplicate_field_iteration_region,
            "field iteration-region identities must be unique")
    all(region -> Set(region.operations) <= id_set, regions) ||
        _fail(:unknown_field_iteration_operation,
            "field iteration region contains an unknown operation")
    memberships = Dict{String,String}()
    for region in regions, operation in region.operations
        haskey(memberships, operation) &&
            _fail(:overlapping_field_iteration_regions,
                "field operation belongs to multiple iteration regions";
                operation)
        memberships[operation] = region.id
    end

    node(operation) = get(memberships, operation, operation)
    outer_edges = Set{Tuple{String,String}}()
    for operation in normalized_operations, dependency in operation.dependencies
        source = node(dependency)
        destination = node(operation.id)
        source == destination || push!(outer_edges, (source, destination))
    end
    nodes = Set(vcat(ids, region_ids))
    for operation in keys(memberships)
        delete!(nodes, operation)
    end
    indegree = Dict(node => 0 for node in nodes)
    adjacency = Dict(node => String[] for node in nodes)
    for (source, destination) in outer_edges
        push!(adjacency[source], destination)
        indegree[destination] += 1
    end
    queue = sort!([node for node in nodes if indegree[node] == 0])
    visited = 0
    while !isempty(queue)
        current = popfirst!(queue)
        visited += 1
        for destination in sort!(adjacency[current])
            indegree[destination] -= 1
            indegree[destination] == 0 && push!(queue, destination)
        end
        sort!(queue)
    end
    visited == length(nodes) ||
        _fail(:undeclared_field_algebraic_loop,
            "field operation graph contains an undeclared algebraic loop")
    fingerprint = canonical_fingerprint((
        :process_bigraph_field_split_v1,
        normalized_operations,
        regions,
    ))
    FieldSplitPlan(normalized_operations, regions, fingerprint)
end

function _canonical(io::IO, geometry::FieldGeometry)
    write(io, "FG")
    _canonical(io, geometry.dimensions)
    _canonical(io, geometry.origin)
    _canonical(io, geometry.spacing)
    _canonical(io, geometry.extent)
    _canonical(io, geometry.axis_order)
end

function _canonical(io::IO, boundary::FieldBoundary)
    write(io, "FB")
    _canonical(io, boundary.axis)
    _canonical(io, boundary.side)
    _canonical(io, boundary.kind)
    _canonical(io, boundary.parameters)
end

function _canonical(io::IO, operation::NamedFieldOperation)
    write(io, "FO")
    _canonical(io, operation.id)
    _canonical(io, operation.kind)
    _canonical(io, operation.start_time)
    _canonical(io, operation.target_time)
    _canonical(io, operation.input_mode)
    _canonical(io, operation.dependencies)
end

function _canonical(io::IO, region::FieldIterationRegion)
    write(io, "FR")
    _canonical(io, region.id)
    _canonical(io, region.operations)
    _canonical(io, region.max_iterations)
end
