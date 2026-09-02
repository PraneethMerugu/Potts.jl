using Metal

include("../../src/proposal_execution_parity.jl")

proposal_execution_report = run_proposal_execution_parity(
    Metal.MtlArray; backend_name = :metal
)
println((
    witness = proposal_execution_report.schema,
    measured_batches = proposal_execution_report.measured_batches,
    median_seconds = proposal_execution_report.median_seconds,
))
