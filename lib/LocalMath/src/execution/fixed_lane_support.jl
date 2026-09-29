# Shared fixed-lane vocabulary for direct and buffered lowerings. StaticArrays
# is intentionally bounded here: larger fixed arities retain the ordinary
# tuple spelling instead of manufacturing model-sized StaticVector methods.

const _MAX_STATIC_EMISSION_LANES = 32

function _validate_static_lane_budget(type, ::Val{K}, name) where {K}
    type <: StaticArrays.StaticVector || return nothing
    K <= _MAX_STATIC_EMISSION_LANES || throw(LocalMathValidationError(
        "StaticVector output port :$(name) exceeds the reviewed fixed-lane budget";
        stage = :prepare,
        contract = :static_lane_specialization_budget,
        port = name,
        expected = 1:_MAX_STATIC_EMISSION_LANES,
        actual = K,
        hint = "use the ordinary tuple lane spelling for larger fixed arities",
    ))
    return nothing
end

@inline _emission_value(emission::_Emission) = emission.value
@inline _emission_value(emission::_ConditionalEmission) = emission.value
@inline _emission_enabled(::_Emission) = true
@inline _emission_enabled(emission::_ConditionalEmission) = emission.when
@inline _candidate_rank(candidate::_Candidate) = candidate.rank
@inline _candidate_rank(candidate::_ConditionalCandidate) = candidate.rank
@inline _candidate_value(candidate::_Candidate) = candidate.value
@inline _candidate_value(candidate::_ConditionalCandidate) = candidate.value
@inline _candidate_enabled(::_Candidate) = true
@inline _candidate_enabled(candidate::_ConditionalCandidate) = candidate.when

@inline _emission_lane(
    emission::Union{_Emission, _ConditionalEmission}, ::Val{1}, ::Val{1}
) = emission
@inline _emission_lane(
    candidate::Union{_Candidate, _ConditionalCandidate}, ::Val{1}, ::Val{1}
) = candidate
@inline _emission_lane(emissions::Tuple, ::Val{K}, ::Val{I}) where {K, I} =
    @inbounds emissions[I]
@inline _emission_lane(
    emissions::StaticArrays.StaticVector{K}, ::Val{K}, ::Val{I}
) where {K, I} = @inbounds emissions[I]

function _emission_result_type(type, ::Val{1})
    type isa DataType && isconcretetype(type) || return nothing
    return type
end

function _emission_result_type(type, ::Val{K}) where {K}
    type isa DataType && isconcretetype(type) || return nothing
    tuple_form = type <: Tuple && length(type.parameters) == K
    static_form = type <: StaticArrays.StaticVector{K}
    tuple_form || static_form || return nothing
    return type
end

_emission_lane_types(type::Type{<:Tuple}, ::Val{K}) where {K} =
    type.parameters
_emission_lane_types(
    type::Type{<:StaticArrays.StaticVector{K}}, ::Val{K}
) where {K} = ntuple(_ -> eltype(type), K)
