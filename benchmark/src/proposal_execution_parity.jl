isdefined(@__MODULE__, :run_localmath_execution_parity) ||
    include("localmath_execution_parity.jl")

function _proposal_parity_external_hamiltonian_disposition(
        side
    )
    fixture = localmath_graph_fixture(; side, include_external = true)
    try
        _localmath_graph_runtime(fixture, identity)
    catch error
        error isa ArgumentError || rethrow()
        occursin("without a bounded gathered lowering", sprint(showerror, error)) ||
            rethrow()
        return :cold_compiler_rejection
    end
    error("external contextual operation unexpectedly passed cold Core compilation")
end

function run_proposal_execution_parity(
        array_convert = identity;
        backend_name::Symbol = :cpu,
        side::Integer = GRAPH_PARITY_SIDE,
        warm_batches::Integer = GRAPH_PARITY_WARM_BATCHES,
        measured_batches::Integer = GRAPH_PARITY_MEASURED_BATCHES,
    )
    external_hamiltonian_disposition =
        _proposal_parity_external_hamiltonian_disposition(side)
    report = run_localmath_execution_parity(
        array_convert;
        backend_name,
        side,
        warm_batches,
        measured_batches,
        include_external = false,
        schema = :proposal_parity_checkerboard_canonical_graph_v2,
    )
    return merge(report, (; external_hamiltonian_disposition))
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(run_proposal_execution_parity())
end
