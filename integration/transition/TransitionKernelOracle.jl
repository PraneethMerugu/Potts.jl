module TransitionKernelOracle

using LinearAlgebra
using SparseArrays

export OracleOwnerKind, OracleCellKind, OracleMediumKind, OracleOwner,
       oracle_cell, oracle_medium,
       OracleBoundaryKind, OraclePeriodic, OracleNoFlux, OracleDomain,
       OracleRelation, von_neumann_relation, realize_neighbor,
       OracleMicrostate, OracleVolumeEnergy, OracleContactEnergy,
       AbstractOracleAcceptanceLaw, OracleConventionalMetropolis,
       OracleMetropolisHastings, OracleModel, global_volume_energy,
       global_contact_energy, global_energy,
       OracleProposal, direct_proposal, destination_state,
       StateCatalog, state_id, enumerate_states,
       PrecisionPolicy, ConvergenceRecord, TransitionRecord,
       SparseTransitionKernel, primitive_kernel, sequential_mcs_kernel,
       transition_records, transition_row,
       KernelValidationReport, validate_kernel,
       hand_derived_1d_fixture, ExactProbability

const ExactProbability = Rational{BigInt}

@enum OracleOwnerKind::UInt8 begin
    OracleCellKind = 1
    OracleMediumKind = 2
end

"""A finite-cell or medium identity in the independent logical state."""
struct OracleOwner
    kind::OracleOwnerKind
    id::UInt32

    function OracleOwner(kind::OracleOwnerKind, id::Integer)
        0 < id <= typemax(UInt32) || throw(ArgumentError(
            "oracle owner identities must be positive and fit UInt32"))
        return new(kind, UInt32(id))
    end
end

oracle_cell(id::Integer) = OracleOwner(OracleCellKind, id)
oracle_medium(id::Integer) = OracleOwner(OracleMediumKind, id)

@enum OracleBoundaryKind::UInt8 begin
    OraclePeriodic = 1
    OracleNoFlux = 2
end

"""A rectangular finite domain with a fixed set of mutable recipient sites."""
struct OracleDomain{N}
    dims::NTuple{N, Int}
    boundaries::NTuple{N, OracleBoundaryKind}
    mutable_sites::Vector{Int}
end

function OracleDomain(dims::NTuple{N, <:Integer};
        boundaries = ntuple(_ -> OraclePeriodic, Val(N)),
        mutable_sites = collect(1:prod(dims))) where {N}
    N > 0 || throw(ArgumentError("an oracle domain requires at least one dimension"))
    normalized_dims = ntuple(index -> Int(dims[index]), Val(N))
    all(>(0), normalized_dims) || throw(ArgumentError(
        "oracle domain extents must be positive"))
    length(boundaries) == N || throw(ArgumentError(
        "an oracle domain requires one boundary rule per dimension"))
    normalized_boundaries = ntuple(index -> begin
        boundary = boundaries[index]
        boundary isa OracleBoundaryKind || throw(ArgumentError(
            "oracle boundaries must be OracleBoundaryKind values"))
        boundary
    end, Val(N))
    sites = sort!(unique!(Int.(collect(mutable_sites))))
    isempty(sites) && throw(ArgumentError("an oracle domain requires a mutable site"))
    all(site -> 1 <= site <= prod(normalized_dims), sites) || throw(ArgumentError(
        "oracle mutable sites must lie inside the rectangular domain"))
    return OracleDomain{N}(normalized_dims, normalized_boundaries, sites)
end

"""A finite Cartesian relation. Symmetric relations are required by this first slice."""
struct OracleRelation{N, K, T}
    offsets::NTuple{K, NTuple{N, Int}}
    weights::NTuple{K, T}
end

function OracleRelation(offsets; weights = nothing, symmetric::Bool = true)
    raw_offsets = collect(offsets)
    isempty(raw_offsets) && throw(ArgumentError("an oracle relation requires an offset"))
    N = length(first(raw_offsets))
    N > 0 || throw(ArgumentError("oracle relation offsets must have positive dimension"))
    all(offset -> length(offset) == N, raw_offsets) || throw(ArgumentError(
        "oracle relation offsets must have equal dimension"))
    normalized_offsets = Tuple(Tuple(Int.(offset)) for offset in raw_offsets)
    all(offset -> any(!iszero, offset), normalized_offsets) || throw(ArgumentError(
        "oracle relation offsets must be nonzero"))
    length(unique(normalized_offsets)) == length(normalized_offsets) || throw(ArgumentError(
        "oracle relation offsets must be unique"))
    raw_weights = weights === nothing ? fill(1, length(normalized_offsets)) : collect(weights)
    length(raw_weights) == length(normalized_offsets) || throw(ArgumentError(
        "an oracle relation requires one weight per offset"))
    all(weight -> weight >= zero(weight), raw_weights) || throw(ArgumentError(
        "oracle relation weights must be non-negative"))
    T = promote_type(map(typeof, raw_weights)...)
    normalized_weights = Tuple(convert(T, weight) for weight in raw_weights)
    if symmetric
        for index in eachindex(normalized_offsets)
            opposite = ntuple(axis -> -normalized_offsets[index][axis], N)
            opposite_index = findfirst(==(opposite), normalized_offsets)
            opposite_index === nothing && throw(ArgumentError(
                "a symmetric oracle relation requires every opposite offset"))
            normalized_weights[index] == normalized_weights[opposite_index] || throw(ArgumentError(
                "opposite oracle relation offsets must have equal weights"))
        end
    end
    K = length(normalized_offsets)
    return OracleRelation{N, K, T}(normalized_offsets, normalized_weights)
end

function von_neumann_relation(::Val{N}; weights = nothing) where {N}
    offsets = Tuple(vcat(
        [ntuple(axis -> axis == dimension ? -1 : 0, Val(N)) for dimension in 1:N],
        [ntuple(axis -> axis == dimension ? 1 : 0, Val(N)) for dimension in 1:N]))
    return OracleRelation(offsets; weights)
end

function _coordinates(site::Integer, dims::NTuple{N, Int}) where {N}
    1 <= site <= prod(dims) || throw(BoundsError(1:prod(dims), site))
    return Tuple(CartesianIndices(dims)[site])
end

"""Resolve a direction without calling the production Cartesian implementation."""
function realize_neighbor(domain::OracleDomain{N}, relation::OracleRelation{N},
        site::Integer, direction::Integer) where {N}
    1 <= direction <= length(relation.offsets) || throw(BoundsError(
        relation.offsets, direction))
    coordinate = _coordinates(site, domain.dims)
    offset = relation.offsets[direction]
    realized = ntuple(Val(N)) do axis
        proposed = coordinate[axis] + offset[axis]
        if 1 <= proposed <= domain.dims[axis]
            proposed
        elseif domain.boundaries[axis] === OraclePeriodic
            mod1(proposed, domain.dims[axis])
        else
            0
        end
    end
    any(iszero, realized) && return nothing
    return LinearIndices(domain.dims)[CartesianIndex(realized)]
end

"""An immutable logical microstate suitable for hashing and catalog lookup."""
struct OracleMicrostate{L, D}
    owners::NTuple{L, OracleOwner}
    discrete::D
end

function OracleMicrostate(owners; discrete = NamedTuple())
    owner_tuple = Tuple(owners)
    isempty(owner_tuple) && throw(ArgumentError("an oracle microstate requires a site"))
    all(owner -> owner isa OracleOwner, owner_tuple) || throw(ArgumentError(
        "every oracle site must contain an OracleOwner"))
    return OracleMicrostate{length(owner_tuple), typeof(discrete)}(owner_tuple, discrete)
end

Base.:(==)(left::OracleMicrostate, right::OracleMicrostate) =
    left.owners == right.owners && left.discrete == right.discrete
Base.isequal(left::OracleMicrostate, right::OracleMicrostate) =
    isequal(left.owners, right.owners) && isequal(left.discrete, right.discrete)
Base.hash(state::OracleMicrostate, seed::UInt) =
    hash(state.discrete, hash(state.owners, hash(:oracle_microstate_v1, seed)))

struct OracleVolumeEnergy{T}
    targets::Dict{UInt32, T}
    strengths::Dict{UInt32, T}
end

function OracleVolumeEnergy(targets::AbstractDict, strengths::AbstractDict)
    keys(targets) == keys(strengths) || Set(keys(targets)) == Set(keys(strengths)) ||
        throw(ArgumentError("oracle volume targets and strengths must name the same cells"))
    ids = UInt32[UInt32(id) for id in keys(targets)]
    all(!iszero, ids) || throw(ArgumentError("oracle volume cell IDs must be positive"))
    value_types = Type[typeof(value) for value in values(targets)]
    append!(value_types, typeof(value) for value in values(strengths))
    T = isempty(value_types) ? Int : promote_type(value_types...)
    target_values = Dict{UInt32, T}()
    strength_values = Dict{UInt32, T}()
    for raw_id in keys(targets)
        id = UInt32(raw_id)
        target_values[id] = convert(T, targets[raw_id])
        strength = convert(T, strengths[raw_id])
        strength >= zero(T) || throw(ArgumentError(
            "oracle volume strengths must be non-negative"))
        strength_values[id] = strength
    end
    return OracleVolumeEnergy(target_values, strength_values)
end

struct OracleContactEnergy{T, R <: OracleRelation}
    interactions::Matrix{T}
    owner_types::Dict{OracleOwner, Int}
    relation::R
end

function OracleContactEnergy(interactions::AbstractMatrix, owner_types::AbstractDict,
        relation::OracleRelation)
    size(interactions, 1) == size(interactions, 2) || throw(ArgumentError(
        "oracle contact interactions must be square"))
    issymmetric(interactions) || throw(ArgumentError(
        "oracle unordered contact interactions must be symmetric"))
    T = eltype(interactions)
    types = Dict{OracleOwner, Int}()
    for (owner, owner_type) in owner_types
        owner isa OracleOwner || throw(ArgumentError(
            "oracle contact type keys must be OracleOwner values"))
        1 <= owner_type <= size(interactions, 1) || throw(ArgumentError(
            "an oracle owner type lies outside the interaction matrix"))
        types[owner] = Int(owner_type)
    end
    return OracleContactEnergy(Matrix{T}(interactions), types, relation)
end

abstract type AbstractOracleAcceptanceLaw end
struct OracleConventionalMetropolis <: AbstractOracleAcceptanceLaw end
struct OracleMetropolisHastings <: AbstractOracleAcceptanceLaw end

struct OracleModel{R <: OracleRelation, E <: Tuple, A <: AbstractOracleAcceptanceLaw, T <: Real}
    proposal_relation::R
    energies::E
    acceptance::A
    temperature::T
end

function OracleModel(proposal_relation::OracleRelation, energies::Tuple = ();
        acceptance::AbstractOracleAcceptanceLaw = OracleConventionalMetropolis(),
        temperature::Real = 0)
    temperature >= zero(temperature) || throw(ArgumentError(
        "oracle temperature must be non-negative"))
    all(energy -> energy isa Union{OracleVolumeEnergy, OracleContactEnergy}, energies) ||
        throw(ArgumentError("unsupported oracle energy component"))
    return OracleModel(proposal_relation, energies, acceptance, temperature)
end

function global_volume_energy(component::OracleVolumeEnergy, state::OracleMicrostate,
        ::Type{T} = BigFloat) where {T <: Real}
    volumes = Dict{UInt32, Int}()
    for owner in state.owners
        owner.kind === OracleCellKind || continue
        volumes[owner.id] = get(volumes, owner.id, 0) + 1
    end
    result = zero(T)
    for (id, volume) in volumes
        haskey(component.targets, id) || throw(ArgumentError(
            "missing oracle target for live cell $id"))
        target = convert(T, component.targets[id])
        strength = convert(T, component.strengths[id])
        result += strength * (convert(T, volume) - target)^2
    end
    return result
end

function global_contact_energy(component::OracleContactEnergy,
        state::OracleMicrostate, domain::OracleDomain, ::Type{T} = BigFloat) where {T <: Real}
    length(state.owners) == prod(domain.dims) || throw(ArgumentError(
        "oracle state and domain sizes must match"))
    result = zero(T)
    for site in eachindex(state.owners)
        owner = state.owners[site]
        haskey(component.owner_types, owner) || throw(ArgumentError(
            "missing oracle contact type for owner $owner"))
        owner_type = component.owner_types[owner]
        for direction in eachindex(component.relation.offsets)
            neighbor = realize_neighbor(domain, component.relation, site, direction)
            neighbor === nothing && continue
            neighbor_owner = state.owners[neighbor]
            owner == neighbor_owner && continue
            haskey(component.owner_types, neighbor_owner) || throw(ArgumentError(
                "missing oracle contact type for owner $neighbor_owner"))
            neighbor_type = component.owner_types[neighbor_owner]
            weight = convert(T, component.relation.weights[direction])
            result += weight * convert(T,
                component.interactions[owner_type, neighbor_type])
        end
    end
    return result / convert(T, 2)
end

_global_component_energy(component::OracleVolumeEnergy, state, domain, ::Type{T}) where {T} =
    global_volume_energy(component, state, T)
_global_component_energy(component::OracleContactEnergy, state, domain, ::Type{T}) where {T} =
    global_contact_energy(component, state, domain, T)

function global_energy(model::OracleModel, state::OracleMicrostate,
        domain::OracleDomain, ::Type{T} = BigFloat) where {T <: Real}
    length(state.owners) == prod(domain.dims) || throw(ArgumentError(
        "oracle state and domain sizes must match"))
    result = zero(T)
    for component in model.energies
        result += _global_component_energy(component, state, domain, T)
    end
    return result
end

struct OracleProposal
    recipient::Int
    donor::Int
    losing::OracleOwner
    gaining::OracleOwner
    direction::Int
    forward_multiplicity::Int
    reverse_multiplicity::Int
end

function direct_proposal(state::OracleMicrostate, domain::OracleDomain,
        relation::OracleRelation, recipient::Integer, direction::Integer)
    recipient in domain.mutable_sites || return nothing
    donor = realize_neighbor(domain, relation, recipient, direction)
    donor === nothing && return nothing
    losing = state.owners[recipient]
    gaining = state.owners[donor]
    losing == gaining && return nothing
    forward = 0
    reverse = 0
    for candidate_direction in eachindex(relation.offsets)
        neighbor = realize_neighbor(domain, relation, recipient, candidate_direction)
        neighbor === nothing && continue
        neighbor_owner = state.owners[neighbor]
        forward += neighbor_owner == gaining
        reverse += neighbor_owner == losing
    end
    forward > 0 || error("an oracle proposal has no forward support")
    return OracleProposal(Int(recipient), donor, losing, gaining, Int(direction),
        forward, reverse)
end

function destination_state(state::OracleMicrostate, proposal::OracleProposal)
    state.owners[proposal.recipient] == proposal.losing || throw(ArgumentError(
        "oracle proposal losing owner does not match its source state"))
    state.owners[proposal.donor] == proposal.gaining || throw(ArgumentError(
        "oracle proposal gaining owner does not match its source state"))
    owners = Base.setindex(state.owners, proposal.gaining, proposal.recipient)
    return OracleMicrostate(owners; discrete = state.discrete)
end

struct StateCatalog{S <: OracleMicrostate}
    states::Vector{S}
    index::Dict{S, Int}
end

function StateCatalog(states::AbstractVector{S}) where {S <: OracleMicrostate}
    isempty(states) && throw(ArgumentError("an oracle state catalog must not be empty"))
    unique_states = collect(states)
    length(unique(unique_states)) == length(unique_states) || throw(ArgumentError(
        "an oracle state catalog cannot contain duplicates"))
    return StateCatalog{S}(unique_states,
        Dict{S, Int}(state => index for (index, state) in pairs(unique_states)))
end

function enumerate_states(domain::OracleDomain, owners;
        admissible::Function = _ -> true, discrete = NamedTuple())
    labels = collect(owners)
    isempty(labels) && throw(ArgumentError("state enumeration requires an owner label"))
    all(owner -> owner isa OracleOwner, labels) || throw(ArgumentError(
        "state enumeration labels must be OracleOwner values"))
    count = prod(domain.dims)
    iterators = ntuple(_ -> labels, count)
    states = OracleMicrostate[]
    for assignment in Iterators.product(iterators...)
        state = OracleMicrostate(Tuple(assignment); discrete)
        admissible(state) && push!(states, state)
    end
    return StateCatalog(states)
end

function state_id(catalog::StateCatalog, state::OracleMicrostate)
    id = get(catalog.index, state, 0)
    id == 0 && throw(KeyError(state))
    return id
end

struct PrecisionPolicy
    bits::Int
    refinement_bits::Int
    tolerance::String
end

function PrecisionPolicy(; bits::Integer = 256, refinement_bits::Integer = 128,
        tolerance = "1e-60")
    bits >= 64 || throw(ArgumentError("oracle precision must be at least 64 bits"))
    refinement_bits > 0 || throw(ArgumentError(
        "oracle refinement precision must be positive"))
    tolerance_string = string(tolerance)
    parsed = tryparse(BigFloat, tolerance_string)
    parsed !== nothing && parsed >= 0 || throw(ArgumentError(
        "oracle convergence tolerance must be a non-negative real"))
    return PrecisionPolicy(Int(bits), Int(refinement_bits), tolerance_string)
end

struct ConvergenceRecord
    base_bits::Int
    refined_bits::Int
    maximum_absolute_difference::BigFloat
    tolerance::BigFloat
    converged::Bool
end

struct SparseTransitionKernel{T, S <: OracleMicrostate, C}
    catalog::StateCatalog{S}
    matrix::SparseMatrixCSC{T, Int}
    resolution::Symbol
    convergence::C
end

struct TransitionRecord{T}
    source::Int
    destination::Int
    probability::T
end

function transition_records(kernel::SparseTransitionKernel{T}) where {T}
    records = TransitionRecord{T}[]
    for source in axes(kernel.matrix, 1), destination in axes(kernel.matrix, 2)
        probability = kernel.matrix[source, destination]
        iszero(probability) || push!(records,
            TransitionRecord(source, destination, probability))
    end
    return records
end

function transition_row(kernel::SparseTransitionKernel, state::OracleMicrostate)
    source = state_id(kernel.catalog, state)
    return kernel.matrix[source, :]
end

function _acceptance_probability(::OracleConventionalMetropolis, delta, temperature,
        forward::Int, reverse::Int, ::Type{ExactProbability})
    iszero(temperature) || throw(ArgumentError(
        "exact rational acceptance is limited to zero temperature"))
    return delta <= zero(delta) ? one(ExactProbability) : zero(ExactProbability)
end

function _acceptance_probability(::OracleMetropolisHastings, delta, temperature,
        forward::Int, reverse::Int, ::Type{ExactProbability})
    iszero(temperature) || throw(ArgumentError(
        "exact rational acceptance is limited to zero temperature"))
    reverse == 0 && return zero(ExactProbability)
    delta < zero(delta) && return one(ExactProbability)
    delta > zero(delta) && return zero(ExactProbability)
    return min(one(ExactProbability), ExactProbability(reverse, forward))
end

function _acceptance_probability(::OracleConventionalMetropolis, delta, temperature,
        forward::Int, reverse::Int, ::Type{BigFloat})
    temperature_value = BigFloat(temperature)
    temperature_value > 0 || throw(ArgumentError(
        "BigFloat oracle acceptance requires positive temperature"))
    log_probability = -BigFloat(delta) / temperature_value
    return log_probability >= 0 ? one(BigFloat) : exp(log_probability)
end

function _acceptance_probability(::OracleMetropolisHastings, delta, temperature,
        forward::Int, reverse::Int, ::Type{BigFloat})
    reverse == 0 && return zero(BigFloat)
    temperature_value = BigFloat(temperature)
    temperature_value > 0 || throw(ArgumentError(
        "BigFloat oracle acceptance requires positive temperature"))
    log_probability = -BigFloat(delta) / temperature_value +
                      log(BigFloat(reverse)) - log(BigFloat(forward))
    return log_probability >= 0 ? one(BigFloat) : exp(log_probability)
end

function _primitive_matrix(catalog::StateCatalog, domain::OracleDomain,
        model::OracleModel, ::Type{T}) where {T <: Real}
    relation = model.proposal_relation
    length(first(relation.offsets)) == length(domain.dims) || throw(ArgumentError(
        "oracle proposal relation and domain dimensions must match"))
    state_count = length(catalog.states)
    base_probability = one(T) / convert(T,
        length(domain.mutable_sites) * length(relation.offsets))
    rows = Vector{Dict{Int, T}}(undef, state_count)
    for (source, state) in pairs(catalog.states)
        length(state.owners) == prod(domain.dims) || throw(ArgumentError(
            "an oracle catalog state does not match its domain"))
        row = Dict{Int, T}()
        for recipient in domain.mutable_sites
            for direction in eachindex(relation.offsets)
                proposal = direct_proposal(state, domain, relation, recipient, direction)
                if proposal === nothing
                    row[source] = get(row, source, zero(T)) + base_probability
                    continue
                end
                destination = destination_state(state, proposal)
                destination_index = get(catalog.index, destination, 0)
                destination_index != 0 || throw(ArgumentError(
                    "oracle state catalog is not closed under direct proposals"))
                before = global_energy(model, state, domain, T)
                after = global_energy(model, destination, domain, T)
                probability = _acceptance_probability(model.acceptance,
                    after - before, model.temperature, proposal.forward_multiplicity,
                    proposal.reverse_multiplicity, T)
                row[destination_index] = get(row, destination_index, zero(T)) +
                                         base_probability * probability
                row[source] = get(row, source, zero(T)) +
                              base_probability * (one(T) - probability)
            end
        end
        rows[source] = row
    end
    I = Int[]
    J = Int[]
    V = T[]
    for source in eachindex(rows)
        for destination in sort!(collect(keys(rows[source])))
            probability = rows[source][destination]
            iszero(probability) && continue
            push!(I, source)
            push!(J, destination)
            push!(V, probability)
        end
    end
    return sparse(I, J, V, state_count, state_count)
end

function _matrix_at_precision(catalog, domain, model, bits::Int, attempts::Int)
    return setprecision(bits) do
        primitive = _primitive_matrix(catalog, domain, model, BigFloat)
        result = attempts == 1 ? primitive : primitive^attempts
        dropzeros!(result)
        result
    end
end

function _maximum_absolute_difference(left, right)
    maximum_difference = zero(BigFloat)
    for row in axes(left, 1), column in axes(left, 2)
        difference = abs(BigFloat(left[row, column]) - BigFloat(right[row, column]))
        maximum_difference = max(maximum_difference, difference)
    end
    return maximum_difference
end

function _assemble_kernel(catalog, domain, model, resolution::Symbol, attempts::Int,
        precision::PrecisionPolicy)
    if iszero(model.temperature)
        matrix = _primitive_matrix(catalog, domain, model, ExactProbability)
        attempts == 1 || (matrix = matrix^attempts)
        dropzeros!(matrix)
        return SparseTransitionKernel(catalog, matrix, resolution, nothing)
    end
    base = _matrix_at_precision(catalog, domain, model, precision.bits, attempts)
    refined_bits = precision.bits + precision.refinement_bits
    refined = _matrix_at_precision(catalog, domain, model, refined_bits, attempts)
    difference = setprecision(refined_bits) do
        _maximum_absolute_difference(base, refined)
    end
    tolerance = setprecision(refined_bits) do
        parse(BigFloat, precision.tolerance)
    end
    record = ConvergenceRecord(precision.bits, refined_bits, difference,
        tolerance, difference <= tolerance)
    record.converged || throw(ErrorException(
        "oracle high-precision kernel did not converge: maximum difference $(record.maximum_absolute_difference) exceeds $(record.tolerance)"))
    return SparseTransitionKernel(catalog, refined, resolution, record)
end

function primitive_kernel(catalog::StateCatalog, domain::OracleDomain, model::OracleModel;
        precision::PrecisionPolicy = PrecisionPolicy())
    return _assemble_kernel(catalog, domain, model, :primitive_attempt, 1, precision)
end

function sequential_mcs_kernel(catalog::StateCatalog, domain::OracleDomain,
        model::OracleModel; precision::PrecisionPolicy = PrecisionPolicy())
    return _assemble_kernel(catalog, domain, model, :normalized_mcs,
        length(domain.mutable_sites), precision)
end

struct KernelValidationReport{T}
    valid::Bool
    nonnegative::Bool
    normalized::Bool
    row_sums::Vector{T}
    maximum_row_residual::T
end

function validate_kernel(kernel::SparseTransitionKernel; tolerance = nothing)
    T = eltype(kernel.matrix)
    threshold = if tolerance === nothing
        kernel.convergence === nothing ? zero(T) : convert(T, kernel.convergence.tolerance)
    else
        convert(T, tolerance)
    end
    threshold >= zero(T) || throw(ArgumentError(
        "kernel validation tolerance must be non-negative"))
    nonnegative = all(value -> value >= -threshold, nonzeros(kernel.matrix))
    row_sums = T[sum(kernel.matrix[row, :]) for row in axes(kernel.matrix, 1)]
    residuals = T[abs(value - one(T)) for value in row_sums]
    maximum_residual = maximum(residuals)
    normalized = maximum_residual <= threshold
    return KernelValidationReport(nonnegative && normalized, nonnegative,
        normalized, row_sums, maximum_residual)
end

"""The reviewed two-site, no-flux, zero-energy derivation used by sequential transition."""
function hand_derived_1d_fixture()
    medium = oracle_medium(1)
    cell = oracle_cell(1)
    domain = OracleDomain((2,); boundaries = (OracleNoFlux,))
    relation = von_neumann_relation(Val(1))
    model = OracleModel(relation; temperature = 0)
    catalog = enumerate_states(domain, (medium, cell))
    half = ExactProbability(1, 2)
    quarter = ExactProbability(1, 4)
    three_eighths = ExactProbability(3, 8)
    primitive = ExactProbability[
        1 0 0 0;
        quarter half 0 quarter;
        quarter 0 half quarter;
        0 0 0 1
    ]
    mcs = ExactProbability[
        1 0 0 0;
        three_eighths quarter 0 three_eighths;
        three_eighths 0 quarter three_eighths;
        0 0 0 1
    ]
    return (; medium, cell, domain, relation, model, catalog,
        expected_primitive = primitive, expected_mcs = mcs)
end

end
