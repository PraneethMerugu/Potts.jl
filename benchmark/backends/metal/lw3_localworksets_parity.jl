using Metal

include("../../src/lw3_localworksets_parity.jl")

lw3_localworksets_parity_report = run_lw3_localworksets_parity(
    Metal.MtlArray;
    backend_name = :metal,
)
println(
    (
        witness = lw3_localworksets_parity_report.schema,
        measured_batches = lw3_localworksets_parity_report.measured_batches,
        median_ratio = lw3_localworksets_parity_report.median_ratio,
        upper95 = lw3_localworksets_parity_report.paired_bootstrap_upper_95,
        threshold = lw3_localworksets_parity_report.threshold,
        passed = lw3_localworksets_parity_report.paired_bootstrap_upper_95 <=
            lw3_localworksets_parity_report.threshold,
    )
)
