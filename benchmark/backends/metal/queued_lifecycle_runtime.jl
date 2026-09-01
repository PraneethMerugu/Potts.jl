using Metal
using PottsToolkit
using Test
using ModelingToolkitBase
using Symbolics

import CorePotts
import LocalMath

_test_checkerboard_core(runtime) =
    CorePotts._checkerboard_core(runtime.engine_workspace)
_test_checkerboard_execution(runtime) =
    CorePotts._checkerboard_execution_position(runtime.engine_workspace)

include("../../../lib/CorePotts/test/backend_conformance/lifecycle_execution.jl")

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

executable, initial = _lifecycle_backend_fixture(division_mcs = 1000)
program = executable.core_program
reference = CorePotts.initialize_program(
    program, initial, program.parameter_defaults, UInt64(0x71), UInt32(1)
)
device = CorePotts.initialize_program(
    program, initial, program.parameter_defaults, UInt64(0x71), UInt32(1)
)
device = CorePotts.adapt_program_runtime(Metal.MtlArray, device)
clear_preparations = device.engine_workspace.clear_report
clear_facts = CorePotts._inspect_checkerboard_execution(
    device.engine_workspace
).clear_report
cache_before = length(Metal.compiler_cache(Metal.device()))

CorePotts.advance_mcs!(reference)
CorePotts.advance_mcs!(reference)
CorePotts.enqueue_program_mcs!(device)
CorePotts.enqueue_program_mcs!(device)
cache_after_enqueue = length(Metal.compiler_cache(Metal.device()))
receipt = CorePotts.settle_program!(
    device,
    CorePotts.ProgramSettlementRequest(
        CorePotts.FinalizationSettlement; full_snapshot = true
    ),
)
cache_after_settlement = length(Metal.compiler_cache(Metal.device()))
snapshot = CorePotts.program_snapshot(reference)

@test _lifecycle_scientific_state(receipt.snapshot) ==
      _lifecycle_scientific_state(snapshot)
@test receipt.submitted_mcs == receipt.drained_mcs == 2
@test all(prepared -> prepared isa LocalMath.PreparedPlan, clear_preparations)
@test device.engine_workspace.core.execution.synchronization_count == 1
@test all(clear_facts) do fact
    fact.planning.base_provider_launch_count > 0 &&
        fact.realized.provider === :KernelAbstractions
end

println((
    witness = :queued_lifecycle_public_runtime,
    mcs = receipt.committed_mcs,
    initialization_stage_counts = map(
        fact -> length(fact.stages) - 2, clear_facts),
    initialization_and_clear_launches = map(
        fact -> fact.planning.base_provider_launch_count, clear_facts),
    cache_before,
    cache_after_enqueue,
    cache_after_settlement,
    enqueue_compile_delta = cache_after_enqueue - cache_before,
    settlement_compile_delta = cache_after_settlement - cache_after_enqueue,
    synchronization_count =
        device.engine_workspace.core.execution.synchronization_count,
))
