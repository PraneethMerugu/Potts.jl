using Test
import LocalMath
const LMID = LocalMath

@testset "validation diagnostics are structured and source-aware" begin
    origin = LMID.SourceOrigin("model.jl", 24; label = :stream)
    nested = ArgumentError("invalid endpoint")
    error = LMID.LocalMathValidationError(
        "a required relation endpoint is out of bounds";
        stage = :execute,
        contract = :relation_endpoint_bounds,
        port = :population,
        binding = :neighbors,
        workspace_leaf = :relation_status,
        expected = 1:4096,
        actual = nested,
        hint = "correct the packed relation before resubmitting",
        origin,
    )
    rendered = sprint(showerror, error)
    expected_lines = (
        "LocalMath validation failed: a required relation endpoint is out of bounds",
        "  lifecycle: :execute",
        "  contract: :relation_endpoint_bounds",
        "  source: model.jl:24 (label: :stream)",
        "  port: :population",
        "  binding: :neighbors",
        "  workspace: :relation_status",
        "  expected: 1:4096",
        "  actual: ArgumentError: invalid endpoint",
        "  hint: correct the packed relation before resubmitting",
    )
    positions = map(line -> findfirst(line, rendered), expected_lines)
    @test all(!isnothing, positions)
    @test issorted(first.(positions))

    minimal = sprint(showerror,
        LMID.LocalMathValidationError("plain contract failure"))
    @test minimal == "LocalMath validation failed: plain contract failure"
end

@testset "program-wide failures are not attributed to stage one" begin
    prepared, _ = _receipt_test_preparation(Int32(1))
    law = prepared.plan.bound.law
    global_error = LMID.LocalMathValidationError(
        "provider scope is unavailable";
        stage = :execute,
        contract = :provider_execution,
    )
    @test LMID._with_work_source_origin(global_error, law,
        :execute, :provider_execution) === global_error

    authored = LMID._with_source_origin(
        ArgumentError("invalid evaluator"), law.stages[1].origin,
        :prepare, :stage_preparation)
    @test authored isa LMID.LocalMathValidationError
    @test authored.origin == law.stages[1].origin
    @test authored.stage === :prepare
    @test authored.contract === :stage_preparation
end

@testset "inspection observes without settlement or synchronization" begin
    prepared, _ = _receipt_test_preparation(Int32(2))
    receipt = LMID.execute!(prepared)
    preparation_before = LMID.inspect(prepared).realized.state
    receipt_before = LMID.inspect(receipt)
    receipt_after = LMID.inspect(receipt)
    preparation_after = LMID.inspect(prepared).realized.state
    @test receipt_before == receipt_after
    @test preparation_before == preparation_after
    @test receipt_before.state === :pending
    @test receipt_before.pending
    wait(receipt)
    @test LMID.inspect(receipt).state === :success
end
