using Test
using Metal
using KernelAbstractions
using Potts
import CorePotts

include("../../../lib/CorePotts/test/test_compiled_program_support.jl")

@kernel function corepotts_rng_v2_words!(words, addresses, seed)
    index = @index(Global, Linear)
    raw = CorePotts._rng_words(
        CorePotts.Philox4x32x10V2(), seed, addresses[index]
    )
    @inbounds for lane in 1:4
        words[lane, index] = raw[lane]
    end
end

@kernel function corepotts_rng_v2_open_uniform_extrema!(uniforms)
    index = @index(Global, Linear)
    raw = index == 1 ? ntuple(_ -> UInt32(0), 4) :
          ntuple(_ -> typemax(UInt32), 4)
    uniforms[index] = CorePotts._uniform_open01_from_words(Float32, raw)
end

@testset "CorePotts stabilization contracts execute on real Metal" begin
    Metal.allowscalar(false)
    backend = Metal.MetalBackend()

    base = CorePotts.RNGAddress(
        stream = CorePotts.AcceptanceStream,
        mcs = 9,
        subround = 1,
        operation = 4,
        entity_kind = CorePotts.CellEntity,
        entity = 7,
        generation = 3,
        invocation = 1,
        draw = 2,
    )
    addresses = CorePotts.RNGAddress[
        base,
        CorePotts.RNGAddress(
            stream = CorePotts.ProposalDirectionStream, mcs = 9,
            subround = 1, operation = 4,
            entity_kind = CorePotts.CellEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = CorePotts._RNG_MAX_MCS, subround = 1, operation = 4,
            entity_kind = CorePotts.CellEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream, mcs = 9,
            subround = typemax(UInt8), operation = 4,
            entity_kind = CorePotts.CellEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream, mcs = 9, subround = 1,
            operation = CorePotts.rng_operation_limit(),
            entity_kind = CorePotts.CellEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream, mcs = 9, subround = 1,
            operation = 4, entity_kind = CorePotts.DestinationEntity,
            entity = 7, generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream, mcs = 9, subround = 1,
            operation = 4, entity_kind = CorePotts.CellEntity,
            entity = typemax(UInt32), generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream, mcs = 9, subround = 1,
            operation = 4, entity_kind = CorePotts.CellEntity, entity = 7,
            generation = typemax(UInt64), invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream, mcs = 9, subround = 1,
            operation = 4, entity_kind = CorePotts.CellEntity, entity = 7,
            generation = 3, invocation = typemax(UInt8), draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream, mcs = 9, subround = 1,
            operation = 4, entity_kind = CorePotts.CellEntity, entity = 7,
            generation = 3, invocation = 1, draw = CorePotts._RNG_MAX_DRAW,
        ),
    ]
    device_addresses = Metal.MtlArray(addresses)
    device_words = Metal.MtlArray(zeros(UInt32, 4, length(addresses)))
    corepotts_rng_v2_words!(backend)(
        device_words, device_addresses, UInt64(0x123456789abcdef0);
        ndrange = length(addresses),
    )
    KernelAbstractions.synchronize(backend)
    raw_words = eachcol(Array(device_words))
    @test all(words -> Tuple(words) != Tuple(first(raw_words)), raw_words[2:end])
    @test all(stream -> UInt8(stream) <= 0x0f, instances(CorePotts.RNGStream))

    device_uniforms = Metal.MtlArray(zeros(Float32, 2))
    corepotts_rng_v2_open_uniform_extrema!(backend)(
        device_uniforms; ndrange = 2
    )
    KernelAbstractions.synchronize(backend)
    uniforms = Array(device_uniforms)
    @test all(value -> 0.0f0 < value < 1.0f0, uniforms)

    base_program = test_program(
        CorePotts.CheckerboardProgramEngine(); scalar_type = Float32
    )
    adapted_backend = CorePotts.AdaptedProgramBackend{:MetalBackend}()
    unsupported = (
        capability_test_program(
            base_program; backend = adapted_backend,
            descriptor_plan = cpu_only_descriptor_plan(),
        ),
        capability_test_program(
            base_program; backend = adapted_backend,
            stage_plan = cpu_only_stage_plan(),
        ),
        capability_test_program(
            base_program; backend = adapted_backend,
            tracker_plan = CorePotts.TrackerExecutionPlan(
                (CPUOnlyCapabilityTracker(),), "cpu-only-metal-tracker-plan-v1"
            ),
        ),
    )
    for program in unsupported
        report = CorePotts.program_capability_report(program)
        @test report.status === CorePotts.BackendSPI.Unsupported
        @test_throws CorePotts.ProgramCapabilityError CorePotts.initialize_program(
            program, test_initial(Float32), Float32[], UInt64(0x703), UInt32(1)
        )
    end

    relationship_program, relationship_initial =
        contradictory_relationship_test_program()
    relationship_program = capability_test_program(
        relationship_program; backend = adapted_backend,
        scalar_type = Float32,
    )
    runtime = CorePotts.initialize_program(
        relationship_program, relationship_initial, Float32[],
        UInt64(0xacce), UInt32(1),
    )
    runtime = CorePotts.BackendSPI.adapt_program_runtime(Metal.MtlArray, runtime)
    ownership_before = copy(runtime.ownership)
    relationship_before = copy(only(runtime.relationships))
    @test_throws CorePotts.LifecycleBackendFailure CorePotts.advance_mcs!(runtime)
    relationship_after = only(runtime.relationships)
    @test runtime.mcs == 0
    @test runtime.ownership == ownership_before
    @test relationship_after.active == relationship_before.active
    @test relationship_after.payload == relationship_before.payload
end
