using Test
using Metal
import KernelAbstractions
import LocalMath

struct LocalMathCoreMetalSite end
struct LocalMathCoreMetalWinner end
struct LocalMathCoreMetalProposal end

@inline function (::LocalMathCoreMetalProposal)(item::Int32, reads, parameters)
    label = something(getfield(reads, 1)[1].value)
    volume = something(getfield(reads, 2)[1].value)
    # The source order is scientifically observable in finite precision.
    energy = label == Int32(1) ? 1.0f8 : 0f0
    energy += -1.0f8
    energy += Float32(volume)
    rank = label == Int32(1) ? Int32(2) : Int32(1)
    return (
        energy = LocalMath.UniqueValue(energy),
        proposal = LocalMath.ResolutionValue(rank, item),
    )
end

@testset "CorePotts LocalMath feasibility uses packed Metal relations" begin
    backend = Metal.MetalBackend()
    sites = LocalMath.Space(LocalMathCoreMetalSite, 2)
    winners = LocalMath.Space(LocalMathCoreMetalWinner, 1)
    label = LocalMath.Field(sites, Int32)
    volume = LocalMath.Field(sites, Int32)
    energy = LocalMath.Field(sites, Float32)
    winner = LocalMath.Field(winners, Int32)
    packed = LocalMath.PackedRelation(
        sites => sites; degree_bound = 1, capacity = 2)
    identity = LocalMath.IdentityRelation(sites)
    resolution_route = LocalMath.FixedRelation(sites => winners; degree = 1)
    stage = LocalMath.Stage(sites, (
        label = LocalMath.Access(label, packed; required = true),
        volume = LocalMath.Access(volume, packed; required = true),
    ), (
        LocalMath.Publication((LocalMath.FieldPublication(
            energy, identity, LocalMath.PublicationValue(:energy)),),
            LocalMath.Unique(Float32)),
        LocalMath.Publication((LocalMath.FieldPublication(
            winner, resolution_route,
            LocalMath.PublicationValue(:proposal)),),
            LocalMath.Resolve(Int32, Int32;
                lower = Int32(1), upper = Int32(2))),
    ), LocalMath.Evaluator(LocalMathCoreMetalProposal()),
        LocalMath.Control(),
        LocalMath.SourceOrigin(:corepotts_localmath_feasibility, 1))

    label_storage = Metal.MtlArray(Int32[1, 2])
    volume_storage = Metal.MtlArray(Int32[1, 3])
    energy_storage = Metal.MtlArray(zeros(Float32, 2))
    winner_storage = Metal.MtlArray(Int32[-1])
    packed_generation = Metal.MtlArray(UInt64[7])
    packed_validated = Metal.MtlArray(UInt64[0])
    packed_status = Metal.MtlArray(Int32[0])
    route_generation = Metal.MtlArray(UInt64[9])
    route_validated = Metal.MtlArray(UInt64[0])
    route_status = Metal.MtlArray(Int32[0])
    packed_storage = (
        active = Metal.MtlArray(Bool[true, true]),
        endpoints = Metal.MtlArray(reshape(Int32[1, 2], 1, 2)),
        offsets = Metal.MtlArray(Int32[1]),
        counts = Metal.MtlArray(Int32[2]),
    )
    route_storage = (
        endpoints = Metal.MtlArray(reshape(Int32[1, 1], 1, 2)),
        counts = Metal.MtlArray(Int32[1, 1]),
    )
    prepared = LocalMath.prepare(LocalMath.LocalLaw(stage),
        label => label_storage,
        volume => volume_storage,
        energy => energy_storage,
        winner => winner_storage,
        packed => LocalMath.MutableRelationStorage(packed_storage;
            generation = packed_generation,
            status = packed_status,
            validated_generations = packed_validated),
        resolution_route => LocalMath.MutableRelationStorage(route_storage;
            generation = route_generation,
            status = route_status,
            validated_generations = route_validated);
        backend)
    wait(LocalMath.execute!(prepared))
    @test Array(energy_storage) == Float32[1, -1.0f8]
    @test Array(winner_storage) == Int32[2]
    @test Array(packed_validated) == Array(packed_generation)
    @test Array(route_validated) == Array(route_generation)
end
