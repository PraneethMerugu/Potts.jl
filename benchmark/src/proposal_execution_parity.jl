isdefined(@__MODULE__, :run_localmath_execution_parity) ||
    include("localmath_execution_parity.jl")

function _proposal_parity_external_hamiltonian_disposition(
        array_convert, backend_name, side
    )
    fixture = localmath_graph_fixture(
        ; side, include_external = true
    )
    try
        runtime = _localmath_graph_runtime(fixture, array_convert)
        CorePotts.enqueue_program_mcs!(runtime)
        receipt = CorePotts.settle_program!(
            runtime, _localmath_graph_request(; full_snapshot = true)
        )
        receipt.failure === nothing || throw(receipt.failure)
        return :canonical_graph
    catch error
        error isa CorePotts.BackendSPI.ProgramCapabilityError || rethrow()
        backend_name === :cpu && rethrow()
        return :explicit_capability_rejection
    end
end

function run_proposal_execution_parity(
        array_convert = identity;
        backend_name::Symbol = :cpu,
        side::Integer = GRAPH_PARITY_SIDE,
        warm_batches::Integer = GRAPH_PARITY_WARM_BATCHES,
        measured_batches::Integer = GRAPH_PARITY_MEASURED_BATCHES,
    )
    external_hamiltonian_disposition =
        _proposal_parity_external_hamiltonian_disposition(
            array_convert, backend_name, side
        )
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
