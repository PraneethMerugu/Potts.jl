using Metal

include("../../src/lw3_localworksets_parity.jl")

lw3_localworksets_parity_report = run_lw3_localworksets_parity(
    Metal.MtlArray;
    backend_name = :metal,
)
println(lw3_localworksets_parity_report)
