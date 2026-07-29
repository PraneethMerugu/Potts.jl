abstract type AbstractFieldBoundary end
struct PeriodicFieldBoundary <: AbstractFieldBoundary end
struct ZeroNeumannFieldBoundary <: AbstractFieldBoundary end
struct DirichletFieldBoundary{T <: AbstractFloat} <: AbstractFieldBoundary
    value::T
end
struct MixedFieldBoundary{T <: AbstractFloat} <: AbstractFieldBoundary
    alpha::T
    beta::T
    value::T
    function MixedFieldBoundary(alpha::T, beta::T, value::T) where {
            T<:AbstractFloat}
        all(isfinite, (alpha, beta, value)) ||
            throw(ArgumentError("mixed field boundary parameters must be finite"))
        !(iszero(alpha) && iszero(beta)) ||
            throw(ArgumentError(
                "mixed field boundary requires nonzero alpha or beta"))
        new{T}(alpha, beta, value)
    end
end
struct AxisFieldBoundary{L <: AbstractFieldBoundary, U <: AbstractFieldBoundary}
    negative::L
    positive::U
end
function AxisFieldBoundary(boundary::B) where {B <: AbstractFieldBoundary}
    AxisFieldBoundary(boundary, boundary)
end

abstract type AbstractFieldInterpolation end
struct NearestFieldInterpolation <: AbstractFieldInterpolation end
struct MultilinearFieldInterpolation <: AbstractFieldInterpolation end

"""Immutable descriptor plus backend-adaptable cell-centered scalar field storage."""
struct CellCenteredField{N, T <: AbstractFloat, A <: AbstractArray{T, N},
    B <: Tuple, I <: AbstractFieldInterpolation}
    values::A
    origin::SVector{N, T}
    spacing::SVector{N, T}
    boundaries::B
    interpolation::I
    semantic_time::T
    synchronization_epoch::UInt64
end

function CellCenteredField(values::AbstractArray{T, N};
        origin = ntuple(_ -> zero(T), Val(N)),
        spacing = ntuple(_ -> one(T), Val(N)),
        boundaries = ntuple(_ -> AxisFieldBoundary(PeriodicFieldBoundary()), Val(N)),
        interpolation::AbstractFieldInterpolation = MultilinearFieldInterpolation(),
        semantic_time::Real = 0, synchronization_epoch::Integer = 0) where {
        T <: AbstractFloat, N}
    N in (2, 3) || throw(ArgumentError("spatial fields support two or three dimensions"))
    all(>(0), size(values)) || throw(ArgumentError("field dimensions must be positive"))
    length(boundaries) == N ||
        throw(ArgumentError("one field boundary pair is required per axis"))
    normalized_origin = SVector{N, T}(Tuple(T.(origin)))
    normalized_spacing = SVector{N, T}(Tuple(T.(spacing)))
    all(value -> isfinite(value) && value > zero(T), normalized_spacing) ||
        throw(ArgumentError("field spacing must be positive and finite"))
    isfinite(semantic_time) || throw(ArgumentError("field semantic time must be finite"))
    0 <= synchronization_epoch <= typemax(UInt64) || throw(ArgumentError(
        "field synchronization epoch must fit UInt64"))
    return CellCenteredField(
        values, normalized_origin, normalized_spacing, Tuple(boundaries),
        interpolation, T(semantic_time), UInt64(synchronization_epoch))
end

function Adapt.adapt_structure(to, field::CellCenteredField)
    return CellCenteredField(Adapt.adapt(to, field.values), field.origin, field.spacing,
        field.boundaries, field.interpolation, field.semantic_time, field.synchronization_epoch)
end

@inline function _field_linear_index(indices::NTuple{N, Int32}, dims::NTuple{
        N, Int}) where {N}
    index = Int32(0)
    stride = Int32(1)
    for dimension in 1:N
        index += indices[dimension] * stride
        stride *= Int32(dims[dimension])
    end
    return Int(index + Int32(1))
end

struct FieldIndexResolution{N, T}
    indices::NTuple{N, Int32}
    fixed::Bool
    invalid::Bool
    value::T
end

@inline function _resolve_field_face(
        ::PeriodicFieldBoundary, index, extent, state, ::Val{D}) where {D}
    indices = Base.setindex(state.indices, Int32(mod(index, extent)), D)
    return FieldIndexResolution(indices, state.fixed, state.invalid, state.value)
end

@inline function _resolve_field_face(::ZeroNeumannFieldBoundary, index, extent, state,
        ::Val{D}) where {D}
    indices = Base.setindex(state.indices, Int32(clamp(index, 0, extent - 1)), D)
    return FieldIndexResolution(indices, state.fixed, state.invalid, state.value)
end

@inline function _resolve_field_face(face::DirichletFieldBoundary, index, extent, state,
        ::Val{D}) where {D}
    T = typeof(state.value)
    value = T(face.value)
    invalid = state.invalid | (state.fixed & (state.value != value))
    return FieldIndexResolution(state.indices, true, invalid, value)
end

@inline function _resolve_field_face(
        ::MixedFieldBoundary, index, extent, state, ::Val{D}) where {D}
    throw(ArgumentError(
        "mixed field boundaries require an evolution discretization and are not sampleable"))
end

@inline _resolve_field_indices(::Tuple{}, indices::NTuple{N, Int32}, dims::NTuple{N, Int},
    state::FieldIndexResolution{N, T}, ::Val{D}) where {N, T, D} = state

@inline function _resolve_field_indices(boundaries::Tuple, indices::NTuple{N, Int32},
        dims::NTuple{N, Int}, state::FieldIndexResolution{N, T},
        ::Val{D}) where {N, T, D}
    index = indices[D]
    axis = first(boundaries)
    next_state = if index < 0
        _resolve_field_face(axis.negative, index, dims[D], state, Val(D))
    elseif index >= dims[D]
        _resolve_field_face(axis.positive, index, dims[D], state, Val(D))
    else
        state
    end
    return _resolve_field_indices(
        Base.tail(boundaries), indices, dims, next_state, Val(D + 1))
end

@inline function _field_value(field::CellCenteredField{N, T}, indices::NTuple{
        N, Int32}) where {N, T}
    initial = FieldIndexResolution(indices, false, false, zero(T))
    resolution = _resolve_field_indices(
        field.boundaries, indices, size(field.values), initial, Val(1))
    resolution.invalid && throw(ArgumentError(
        "field sample crosses Dirichlet faces with incompatible corner values"))
    return resolution.fixed ? resolution.value :
           @inbounds(field.values[_field_linear_index(resolution.indices, size(field.values))])
end

@inline function _physical_site_center(domain, site::Integer, ::Type{T}) where {T}
    dims = _proposal_dims(domain)
    spacing = domain isa CartesianDomain ? domain.spacing : domain.descriptor.spacing
    coordinates = _site_coordinates(site, dims)
    return SVector{length(dims), T}(ntuple(
        dimension -> (T(coordinates[dimension]) + T(0.5)) * T(spacing[dimension]),
        length(dims)))
end

@inline function sample_field(
        field::CellCenteredField{N, T, A, B, NearestFieldInterpolation},
        domain, site::Integer) where {N, T, A, B}
    position = _physical_site_center(domain, site, T)
    indices = ntuple(
        dimension -> Int32(floor(
            (position[dimension] - field.origin[dimension]) / field.spacing[dimension])),
        Val(N))
    return _field_value(field, indices)
end

@inline function sample_field(
        field::CellCenteredField{N, T, A, B, MultilinearFieldInterpolation},
        domain, site::Integer) where {N, T, A, B}
    position = _physical_site_center(domain, site, T)
    coordinate = SVector{N, T}(ntuple(
        dimension -> (position[dimension] - field.origin[dimension]) /
                     field.spacing[dimension] - T(0.5),
        Val(N)))
    base = ntuple(dimension -> Int32(floor(coordinate[dimension])), Val(N))
    fraction = SVector{N, T}(ntuple(
        dimension -> coordinate[dimension] -
                     T(base[dimension]), Val(N)))
    result = zero(T)
    for corner in UInt32(0):((UInt32(1) << N) - UInt32(1))
        indices = ntuple(
            dimension -> base[dimension] +
                         Int32((corner >> (dimension - 1)) & UInt32(1)), Val(N))
        weight = one(T)
        for dimension in 1:N
            upper = ((corner >> (dimension - 1)) & UInt32(1)) != 0
            weight *= upper ? fraction[dimension] : one(T) - fraction[dimension]
        end
        result += weight * _field_value(field, indices)
    end
    return result
end

abstract type AbstractFieldResponse end
struct LinearResponse <: AbstractFieldResponse end
struct MichaelisMentenResponse{T <: AbstractFloat} <: AbstractFieldResponse
    scale::T
    function MichaelisMentenResponse(scale::T) where {T <: AbstractFloat}
        isfinite(scale) && scale > zero(T) || throw(ArgumentError(
            "Michaelis-Menten scale must be positive and finite"))
        new{T}(scale)
    end
end
struct SaturationLinearResponse{T <: AbstractFloat} <: AbstractFieldResponse
    scale::T
    function SaturationLinearResponse(scale::T) where {T <: AbstractFloat}
        isfinite(scale) && scale >= zero(T) || throw(ArgumentError(
            "saturation-linear scale must be non-negative and finite"))
        new{T}(scale)
    end
end

@inline field_response(::LinearResponse, concentration) = concentration
@inline function field_response(response::MichaelisMentenResponse, concentration)
    concentration >= zero(concentration) || throw(DomainError(concentration,
        "Michaelis-Menten response requires non-negative concentration"))
    return concentration / (response.scale + concentration)
end
@inline function field_response(response::SaturationLinearResponse, concentration)
    denominator = one(concentration) + response.scale * concentration
    denominator > zero(denominator) || throw(DomainError(concentration,
        "saturation-linear response crossed its singularity"))
    return concentration / denominator
end

"""Finite-cell property plus explicit medium-domain scalar values."""
struct OwnerScalarCoupling{P <: CellPropertyRef, T <: AbstractFloat, N}
    property::P
    medium_ids::NTuple{N, UInt32}
    medium_values::NTuple{N, T}
end

function OwnerScalarCoupling(property::Symbol, medium_values::Pair...;
        number_type::Type{T} = Float64) where {T <: AbstractFloat}
    entries = sort!(collect(medium_values); by = entry -> value(first(entry)))
    all(entry -> first(entry) isa MediumID && last(entry) isa Real, entries) ||
        throw(ArgumentError("medium couplings must be `MediumID => Real` pairs"))
    ids = Tuple(value(first(entry)) for entry in entries)
    length(unique(ids)) == length(ids) || throw(ArgumentError(
        "each medium must have one scalar coupling"))
    values = Tuple(T(last(entry)) for entry in entries)
    all(isfinite, values) || throw(ArgumentError("owner couplings must be finite"))
    return OwnerScalarCoupling(CellPropertyRef(property), ids, values)
end

@inline function owner_scalar(state, coupling::OwnerScalarCoupling, owner::OwnerRef)
    if is_cell_owner(owner)
        return @inbounds _property_column(state, coupling.property)[Int(owner.value)]
    end
    @inbounds for index in eachindex(coupling.medium_ids)
        coupling.medium_ids[index] == owner.value && return coupling.medium_values[index]
    end
    throw(ArgumentError("medium owner has no scalar coupling"))
end

"""Globally integrable occupancy coupling to one immutable field snapshot."""
struct ExternalFieldOccupancyHamiltonian{F <: CellCenteredField,
    C <: OwnerScalarCoupling, R <: AbstractFieldResponse, T <: AbstractFloat} <:
       AbstractEnergy
    field::F
    coupling::C
    response::R
    energy_scale::T
end

function Adapt.adapt_structure(to, component::ExternalFieldOccupancyHamiltonian)
    return ExternalFieldOccupancyHamiltonian(
        Adapt.adapt(to, component.field), component.coupling, component.response,
        component.energy_scale)
end

function ExternalFieldOccupancyHamiltonian(field::CellCenteredField,
        coupling::OwnerScalarCoupling; response::AbstractFieldResponse = LinearResponse(),
        energy_scale::Real = 1)
    T = float(promote_type(eltype(field.values), typeof(energy_scale)))
    isfinite(energy_scale) && energy_scale > 0 || throw(ArgumentError(
        "external-field energy scale must be positive and finite"))
    return ExternalFieldOccupancyHamiltonian(field, coupling, response, T(energy_scale))
end

function component_identity(::ExternalFieldOccupancyHamiltonian)
    ComponentIdentity(:external_field_occupancy, v"1.0.0", :energy)
end
required_relations(::ExternalFieldOccupancyHamiltonian) = (:field_sampling,)

function energy_change(component::ExternalFieldOccupancyHamiltonian,
        proposal::CopyProposal, state, domain)
    concentration = sample_field(component.field, domain, proposal.recipient)
    potential = field_response(component.response, concentration)
    losing = owner_scalar(state, component.coupling, proposal.losing)
    gaining = owner_scalar(state, component.coupling, proposal.gaining)
    return component.energy_scale * (losing - gaining) * potential
end

function global_energy(component::ExternalFieldOccupancyHamiltonian, state, domain)
    T = typeof(component.energy_scale)
    result = zero(T)
    mutable_sites = domain isa CartesianDomain ? findall(vec(domain.mutable_mask)) :
                    domain.storage.mutable_sites
    for site_value in mutable_sites
        site = Int(site_value)
        owner = _proposal_owner_at(state, site)
        concentration = sample_field(component.field, domain, site)
        result -= component.energy_scale * owner_scalar(state, component.coupling, owner) *
                  field_response(component.response, concentration)
    end
    return result
end

abstract type AbstractChemotaxisMode end
struct ExtensionChemotaxis <: AbstractChemotaxisMode end
struct RetractionChemotaxis <: AbstractChemotaxisMode end
struct ReciprocalChemotaxis <: AbstractChemotaxisMode end

"""Native nonconservative donor-to-recipient chemotaxis log bias."""
struct ChemotaxisDrive{F <: CellCenteredField, C <: OwnerScalarCoupling,
    R <: AbstractFieldResponse, M <: AbstractChemotaxisMode} <: AbstractDrive
    field::F
    sensitivity::C
    response::R
    mode::M
end

function Adapt.adapt_structure(to, component::ChemotaxisDrive)
    return ChemotaxisDrive(Adapt.adapt(to, component.field), component.sensitivity,
        component.response, component.mode)
end

component_identity(::ChemotaxisDrive) = ComponentIdentity(:chemotaxis, v"1.0.0", :drive)
required_relations(::ChemotaxisDrive) = (:field_sampling,)

@inline _responding_sensitivity(state, coupling, owner) = is_cell_owner(owner) ?
                                                          owner_scalar(state, coupling, owner) :
                                                          zero(eltype(coupling.medium_values))

@inline function _chemotaxis_coefficient(::ExtensionChemotaxis, state, coupling, proposal)
    return _responding_sensitivity(state, coupling, proposal.gaining)
end
@inline function _chemotaxis_coefficient(::RetractionChemotaxis, state, coupling, proposal)
    return -_responding_sensitivity(state, coupling, proposal.losing)
end
@inline function _chemotaxis_coefficient(::ReciprocalChemotaxis, state, coupling, proposal)
    return _responding_sensitivity(state, coupling, proposal.gaining) -
           _responding_sensitivity(state, coupling, proposal.losing)
end

function drive_log_bias(component::ChemotaxisDrive, proposal::CopyProposal, state, domain)
    donor = field_response(component.response, sample_field(component.field, domain, proposal.donor))
    recipient = field_response(component.response,
        sample_field(component.field, domain, proposal.recipient))
    coefficient = _chemotaxis_coefficient(component.mode, state,
        component.sensitivity, proposal)
    return coefficient * (recipient - donor)
end

"""Morpheus-style non-Hamiltonian positive yield barrier."""
struct PositiveYield{T <: AbstractFloat} <: AbstractKineticModifier
    barrier::T
    function PositiveYield(barrier::T) where {T <: AbstractFloat}
        isfinite(barrier) && barrier >= zero(T) || throw(ArgumentError(
            "positive yield must be finite and non-negative"))
        new{T}(barrier)
    end
end

function component_identity(::PositiveYield)
    ComponentIdentity(:positive_yield, v"1.0.0", :kinetic_modifier)
end
component_semantic_data(component::PositiveYield) = (barrier = component.barrier,)
kinetic_barrier(modifier::PositiveYield, proposal, state) = modifier.barrier

_field_boundary_semantics(::PeriodicFieldBoundary) = (kind = :periodic,)
_field_boundary_semantics(::ZeroNeumannFieldBoundary) = (kind = :zero_neumann,)
function _field_boundary_semantics(boundary::DirichletFieldBoundary)
    return (kind = :dirichlet, value = boundary.value)
end
function _field_boundary_semantics(boundary::MixedFieldBoundary)
    return (kind = :mixed, alpha = boundary.alpha,
        beta = boundary.beta, value = boundary.value)
end

function _coupling_semantics(coupling::OwnerScalarCoupling)
    return (
        finite_cell_property = property_key(coupling.property),
        medium_values = ntuple(
            index -> (
                medium_id = coupling.medium_ids[index],
                value = coupling.medium_values[index]),
            length(coupling.medium_ids))
    )
end

_field_response_semantics(::LinearResponse) = (kind = :linear,)
_field_response_semantics(response::MichaelisMentenResponse) =
    (kind = :michaelis_menten, scale = response.scale)
_field_response_semantics(response::SaturationLinearResponse) =
    (kind = :saturation_linear, scale = response.scale)

_chemotaxis_mode_semantics(::ExtensionChemotaxis) = :extension
_chemotaxis_mode_semantics(::RetractionChemotaxis) = :retraction
_chemotaxis_mode_semantics(::ReciprocalChemotaxis) = :reciprocal

function _field_semantic_data(field::CellCenteredField)
    return (
        placement = :cell_centered,
        dimensions = ndims(field.values),
        shape = size(field.values),
        values = field.values,
        origin = Tuple(field.origin),
        spacing = Tuple(field.spacing),
        boundaries = map(
            axis -> (negative = _field_boundary_semantics(axis.negative),
                positive = _field_boundary_semantics(axis.positive)),
            field.boundaries),
        interpolation = nameof(typeof(field.interpolation)),
        semantic_time = field.semantic_time,
        synchronization_epoch = field.synchronization_epoch,
    )
end

function capabilities(::ExternalFieldOccupancyHamiltonian{F}) where {
        N, F <: CellCenteredField{N}}
    return ScientificCapabilities(dimensions = (N,))
end

function capabilities(::ChemotaxisDrive{F}) where {N, F <: CellCenteredField{N}}
    return ScientificCapabilities(dimensions = (N,))
end

function component_semantic_data(component::ExternalFieldOccupancyHamiltonian)
    return (
        field = _field_semantic_data(component.field),
        coupling = _coupling_semantics(component.coupling),
        response = _field_response_semantics(component.response),
        energy_scale = component.energy_scale,
    )
end

function component_semantic_data(component::ChemotaxisDrive)
    return (
        field = _field_semantic_data(component.field),
        sensitivity = _coupling_semantics(component.sensitivity),
        response = _field_response_semantics(component.response),
        mode = _chemotaxis_mode_semantics(component.mode),
    )
end

function _potts_domain_field_semantics(domain)
    descriptor = domain isa CartesianDomain ? domain : domain.descriptor
    return (
        shape = descriptor.dims,
        spacing = Tuple(descriptor.spacing),
        boundaries = map(
            axis -> (
                negative = _boundary_semantics(axis.negative),
                positive = _boundary_semantics(axis.positive)),
            descriptor.boundaries)
    )
end

function field_semantics_report(field::CellCenteredField, domain)
    return (
        placement = :cell_centered,
        interpolation = nameof(typeof(field.interpolation)),
        field_shape = size(field.values),
        field_origin = Tuple(field.origin),
        field_spacing = Tuple(field.spacing),
        field_boundaries = map(
            axis -> (negative = _field_boundary_semantics(axis.negative),
                positive = _field_boundary_semantics(axis.positive)),
            field.boundaries),
        potts_domain = _potts_domain_field_semantics(domain),
        sampling_role = :field_discretization,
        semantic_time = field.semantic_time,
        synchronization_epoch = field.synchronization_epoch
    )
end

function field_semantics_report(component::ExternalFieldOccupancyHamiltonian, domain)
    return (
        component = component_identity(component),
        category = :hamiltonian,
        law = :external_field_occupancy,
        response = nameof(typeof(component.response)),
        energy_scale = component.energy_scale,
        coupling = _coupling_semantics(component.coupling),
        field = field_semantics_report(component.field, domain)
    )
end

function field_semantics_report(component::ChemotaxisDrive, domain)
    return (
        component = component_identity(component),
        category = :nonconservative_drive,
        law = :donor_to_recipient_field_difference,
        response = nameof(typeof(component.response)),
        mode = nameof(typeof(component.mode)),
        sensitivity = _coupling_semantics(component.sensitivity),
        contributes_to_hamiltonian = false,
        field = field_semantics_report(component.field, domain)
    )
end
