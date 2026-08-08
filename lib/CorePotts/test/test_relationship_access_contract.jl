struct IncidentAccessProbe{T, V <: AbstractVector{T}} <: AbstractVector{T}
    values::V
    permitted::Int
    accesses::Base.RefValue{Int}
end

Base.IndexStyle(::Type{<:IncidentAccessProbe}) = IndexLinear()
Base.size(values::IncidentAccessProbe) = size(values.values)
function Base.getindex(values::IncidentAccessProbe, index::Int)
    index == values.permitted || error(
        "relationship lookup escaped its endpoint incident list"
    )
    values.accesses[] += 1
    return @inbounds values.values[index]
end

@testset "relationship lookup cost is incident-local" begin
    capacity = 1024
    active = falses(capacity)
    endpoint_a = zeros(Int32, capacity)
    endpoint_b = zeros(Int32, capacity)
    active[777] = true
    endpoint_a[777] = Int32(1)
    endpoint_b[777] = Int32(2)
    active_accesses = Ref(0)
    endpoint_a_accesses = Ref(0)
    endpoint_b_accesses = Ref(0)
    state = (
        active = IncidentAccessProbe(active, 777, active_accesses),
        endpoint_a = IncidentAccessProbe(
            endpoint_a, 777, endpoint_a_accesses
        ),
        endpoint_b = IncidentAccessProbe(
            endpoint_b, 777, endpoint_b_accesses
        ),
        degree = Int16[1, 1],
        incident_edges = reshape(Int32[777, 777], 1, 2),
    )
    @test CorePotts._relationship_edge(state, Int32(1), Int32(2)) == 777
    @test active_accesses[] == 1
    @test endpoint_a_accesses[] == 1
    @test endpoint_b_accesses[] == 1

    endpoint_b[777] = Int32(3)
    @test CorePotts._relationship_edge(state, Int32(1), Int32(2)) === nothing
    @test active_accesses[] == 2
    @test endpoint_a_accesses[] == 2
    @test endpoint_b_accesses[] == 2
end
