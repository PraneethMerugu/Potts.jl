using Test
import TOML

module ResolvedAggregateCompilerSchema

    include(joinpath(
        @__DIR__, "..", "benchmark", "compiler_contract_schema.jl",
    ))

end


@testset "resolved aggregate compiler report is machine readable" begin
    arguments = (Int32(1),)
    measured = @timed Base.code_typed(
        identity, Tuple{Int32}; optimize = true,
    )
    record = ResolvedAggregateCompilerSchema._compiler_typed_boundary_record(
        measured,
        ("value",),
        arguments,
        ("serialization smoke input",),
        (Dict{String, String}(),);
        role = "ordinary report serialization smoke",
        signature = "identity",
    )
    @test record["return_is_concrete"]
    @test record["any_argument_slots"] == 0
    @test record["typed_method_matches"] == 1
    @test record["aggregate_payload_summary_bytes"] ==
        Base.summarysize(arguments)

    report = Dict{String, Any}(
        "schema_version" => 1,
        "profile" => "potts_resolved_aggregate_compiler_contract",
        "smoke" => record,
    )
    output = IOBuffer()
    ResolvedAggregateCompilerSchema.emit_resolved_aggregate_compiler_report(
        report; io = output,
    )
    parsed = TOML.parse(String(take!(output)))
    @test parsed["schema_version"] == 1
    @test parsed["profile"] == report["profile"]
    @test parsed["smoke"]["payload"][1]["semantic_origin"] ==
        "serialization smoke input"
end
