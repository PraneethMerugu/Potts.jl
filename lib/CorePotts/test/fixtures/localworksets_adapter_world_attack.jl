using Test
import CorePotts

include(joinpath(@__DIR__, "..", "test_program_v1_support.jl"))

function candidate_runtime()
    ownership = zeros(Int32, 6, 6)
    ownership[2:3, 2:3] .= 1
    ownership[4:5, 4:5] .= 2
    initial = CorePotts.ProgramInitialState(
        ownership, Int16[2, 2]; scalar_type = Float64
    )
    program = test_program(CorePotts.CheckerboardProgramEngine())
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0x51a7), UInt32(3);
        repeat = UInt32(2),
    )
    return CorePotts._localworksets_candidate_runtime(runtime)
end

function settle_full!(runtime)
    return CorePotts.settle_program!(
        runtime,
        CorePotts.ProgramSettlementRequest(
            CorePotts.PublicStepSettlement; full_snapshot = true
        ),
    )
end

length(ARGS) == 1 || error("expected one adapter attack profile")
profile = only(ARGS)
candidate = candidate_runtime()
CorePotts.enqueue_program_mcs!(candidate)
prepared = candidate.engine_workspace.prepared
before = CorePotts.LocalWorksets.inspect(prepared)
@test before.submitted == UInt64(2)
@test before.drained == UInt64(0)

if profile == "broad"
    # Broad run and wait replacements may share one irreversible world. The
    # trusted candidate must drain through both, while a previously prepared
    # but uncached candidate must reject the changed run! authority.
    unsubmitted = candidate_runtime()
    function CorePotts.LocalWorksets.run!(
            prepared::CorePotts.LocalWorksets.PreparedWork,
            submission::NamedTuple,
        )
        error("hostile exact broad run!")
    end
    function Base.wait(event::CorePotts.LocalWorksets.WorkEvent)
        error("hostile exact broad wait")
    end
    @test which(
        CorePotts.LocalWorksets.run!,
        Tuple{CorePotts.LocalWorksets.PreparedWork, NamedTuple},
    ).module === Main
    @test which(
        Base.wait, Tuple{CorePotts.LocalWorksets.WorkEvent}
    ).module === Main

    receipt = settle_full!(candidate)
    @test receipt.committed_mcs == 1
    fresh_prepared = unsubmitted.engine_workspace.prepared
    failure = try
        CorePotts.enqueue_program_mcs!(unsubmitted)
        nothing
    catch caught
        caught
    end
    @test failure isa CorePotts.LifecycleBackendFailure
    fresh = CorePotts.LocalWorksets.inspect(fresh_prepared)
    @test fresh.submitted == fresh.drained == UInt64(0)
    @test all(isnothing, fresh_prepared.leases)
    @test !fresh.poisoned
elseif profile == "specific"
    event = candidate.engine_workspace.last_event
    function CorePotts.LocalWorksets.run!(
            prepared::typeof(prepared), submission::NamedTuple
        )
        error("hostile more-specific run!")
    end
    function Base.wait(event::typeof(event))
        error("hostile more-specific wait")
    end
    @test which(
        CorePotts.LocalWorksets.run!, Tuple{typeof(prepared), NamedTuple}
    ).module === Main
    @test which(Base.wait, Tuple{typeof(event)}).module === Main
    CorePotts.enqueue_program_mcs!(candidate)
    receipt = settle_full!(candidate)
    @test receipt.committed_mcs == 2
else
    error("unknown adapter attack profile: $profile")
end

after = CorePotts.LocalWorksets.inspect(prepared)
@test after.submitted == after.drained == UInt64(2 * receipt.committed_mcs)
@test all(isnothing, prepared.leases)
@test !after.poisoned
