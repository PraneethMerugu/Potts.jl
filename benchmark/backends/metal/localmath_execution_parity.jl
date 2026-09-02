using Metal

include("../../src/localmath_execution_parity.jl")

execution_parity_report = run_localmath_execution_parity(
    Metal.MtlArray;
    backend_name = :metal,
)
println(
    (
        witness = execution_parity_report.schema,
        measured_batches = execution_parity_report.measured_batches,
        median_seconds = execution_parity_report.median_seconds,
    )
)
