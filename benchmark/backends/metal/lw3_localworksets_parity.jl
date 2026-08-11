using Metal

include("../../src/lw3_localworksets_parity.jl")

println(run_lw3_localworksets_parity(
    Metal.MtlArray;
    backend_name = :metal,
))
