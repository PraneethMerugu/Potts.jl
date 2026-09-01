using Metal
using PottsToolkit
using Test
using ModelingToolkitBase
using Symbolics

import CorePotts

_test_checkerboard_core(runtime) =
    CorePotts._checkerboard_core(runtime.engine_workspace)
_test_checkerboard_execution(runtime) =
    CorePotts._checkerboard_execution_position(runtime.engine_workspace)

include("../../../lib/CorePotts/test/backend_conformance/lifecycle_execution.jl")

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

alias_report = run_lifecycle_bank_alias_invariant(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println((lifecycle_transaction = :alias_invariant, report = alias_report))

queue_report = run_queued_lifecycle_mcs(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println((lifecycle_transaction = :queued_mcs, report = queue_report))

lifecycle_report = run_lifecycle_mcs_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println((lifecycle_transaction = :lifecycle_parity, report = lifecycle_report))

capacity_report = run_lifecycle_capacity_failure(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println((lifecycle_transaction = :capacity_failure, report = capacity_report))

canonical_failure_report = run_lifecycle_canonical_state_failure(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println((lifecycle_transaction = :canonical_failure, report = canonical_failure_report))

println((lifecycle_transaction = :complete, status = :passed))
