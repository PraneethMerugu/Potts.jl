using PottsToolkit
using ModelingToolkitBase
using Random
using Statistics
using Symbolics
using Test

import CorePotts

isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("../../test/fixtures/NeutralExternalTerms.jl")

# A 32×32 diagnostic is dominated by the fixed cost of forty validated claim
# submissions per ten-MCS batch, and 64×64 remained close enough to the 1.05
# boundary to be sensitive to unrelated Metal runner load. Qualification uses
# 128×128 so the predeclared test measures the vertical rather than host-launch
# jitter; the batch count, queued-MCS count, bootstrap rule, and threshold are
# unchanged.
const LW3_SIDE = 128
const LW3_BATCH_MCS = 10
const LW3_WARM_BATCHES = 10
const LW3_MEASURED_BATCHES = 50
const LW3_BOOTSTRAP_SAMPLES = 10_000
const LW3_BOOTSTRAP_SEED = UInt64(0x6c77335f626f6f74)

function lw3_localworksets_fixture(
        ;
        side::Integer = LW3_SIDE,
        include_external::Bool = true,
    )
    side >= 16 || throw(ArgumentError("LW-3 parity side must be at least 16"))
    @variables lw3_field
    @parameters lw3_external_weight = 0.125
    cell = CellKind(:lw3_cell; extinction = ForbidExtinction())
    medium = MediumKind(:lw3_medium)
    field = FieldState(lw3_field; name = :lw3_field, initial = 0.0)
    fold_a = SiteBinding(:lw3_fold_a)
    fold_b = SiteBinding(:lw3_fold_b)
    fold_c = SiteBinding(:lw3_fold_c)
    external_site = SiteBinding(:lw3_external_site)
    energy_statements = (
        Volume(cell; target = 64.0, strength = 0.75),
        ContactEnergy([
            (medium ↔ cell) => 5.0,
            (cell ↔ cell) => 1.5,
        ]),
        Elongation(cell; target = 3.0, strength = 0.25),
        HamiltonianTerm(
            :lw3_fold_large_positive;
            domain = sites(:lattice),
            anchor = fold_a,
            expression = Float32(16_384) * occupancy(cell, fold_a),
        ),
        HamiltonianTerm(
            :lw3_fold_large_negative;
            domain = sites(:lattice),
            anchor = fold_b,
            expression = Float32(-16_384) * occupancy(cell, fold_b),
        ),
        HamiltonianTerm(
            :lw3_fold_residual;
            domain = sites(:lattice),
            anchor = fold_c,
            expression = Float32(0.375) * occupancy(cell, fold_c),
        ),
    )
    external_statement = NeutralExternalTerms.ExternalWeightedSiteTerm(
        :lw3_registered_external,
        lw3_external_weight,
        lw3_field,
        cell,
        external_site,
    )
    protocol = Protocol(
        Sweep(; attempts = AttemptsPerSite(1), temperature = 2.0);
        name = :main,
    )
    statements = if include_external
        (
            Lattice(
                (Int(side), Int(side));
                boundary = Periodic(),
                max_cells = 4,
                relations = (
                    proposal = VonNeumann(),
                    contact = Moore(),
                ),
            ),
            cell,
            medium,
            field,
            energy_statements...,
            external_statement,
            protocol,
        )
    else
        (
            Lattice(
                (Int(side), Int(side));
                boundary = Periodic(),
                max_cells = 4,
                relations = (
                    proposal = VonNeumann(),
                    contact = Moore(),
                ),
            ),
            cell,
            medium,
            energy_statements...,
            protocol,
        )
    end
    source = PottsSystem(
        name = :lw3_localworksets_parity,
        statements = StatementSet(statements),
        unknowns = include_external ? [lw3_field] : [],
        parameters = include_external ? [lw3_external_weight] : [],
    )
    compiled = mtkcompile(complete(
        source; registry = NeutralExternalTerms.registry()
    ))
    labels = zeros(Int32, Int(side), Int(side))
    width = max(4, div(Int(side), 4))
    lo = div(Int(side) - width, 2) + 1
    hi = lo + width - 1
    labels[lo:hi, lo:hi] .= Int32(1)
    field_values = reshape(
        Float32[
            Float32(mod(index, 17)) / Float32(16)
            for index in 0:(Int(side)^2 - 1)
        ],
        Int(side),
        Int(side),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = include_external ? (lw3_field => field_values,) : (),
    )
    executable = PottsToolkit._lower_execution_plan(
        compiled,
        CheckerboardSweepCPM(),
        CPUBackend(),
        Float32,
    )
    return (
        executable,
        program = executable.core_program,
        initial = PottsToolkit._core_initial_state(executable, initial),
    )
end

function _lw3_runtime(
        fixture,
        array_convert;
        seed::UInt64 = UInt64(0x6c77335f73656564),
        replica::UInt32 = UInt32(7),
        repeat::UInt32 = UInt32(11),
        candidate::Bool = false,
        queue_mcs_capacity::Integer = 12,
    )
    runtime = CorePotts.initialize_program(
        fixture.program,
        fixture.initial,
        fixture.program.parameter_defaults,
        seed,
        replica;
        repeat,
    )
    runtime = array_convert === identity ? runtime :
              CorePotts.adapt_program_runtime(array_convert, runtime)
    return candidate ? CorePotts._localworksets_candidate_runtime(
        runtime; queue_mcs_capacity
    ) : runtime
end

_lw3_request(; full_snapshot::Bool) = CorePotts.ProgramSettlementRequest(
    CorePotts.PublicStepSettlement; full_snapshot
)

function _lw3_run_batch!(
        runtime;
        mcs::Integer = LW3_BATCH_MCS,
        full_snapshot::Bool = false,
    )
    target = runtime.engine_workspace.execution.submitted_mcs + Int(mcs)
    sample = @timed begin
        CorePotts.enqueue_program_through!(runtime, target)
        CorePotts.settle_program!(
            runtime, _lw3_request(; full_snapshot)
        )
    end
    return (
        seconds = sample.time,
        bytes = sample.bytes,
        receipt = sample.value,
    )
end

function _lw3_full_receipt!(runtime)
    return CorePotts.settle_program!(
        runtime, _lw3_request(; full_snapshot = true)
    )
end

function _lw3_assert_receipt_parity(direct, candidate)
    @test direct.submitted_mcs == candidate.submitted_mcs
    @test direct.drained_mcs == candidate.drained_mcs
    @test direct.committed_mcs == candidate.committed_mcs
    @test direct.materialized_mcs == candidate.materialized_mcs
    @test direct.counters == candidate.counters
    @test direct.status == candidate.status
    @test direct.failure == candidate.failure
    @test direct.snapshot.ownership == candidate.snapshot.ownership
    @test direct.snapshot.cell_kinds == candidate.snapshot.cell_kinds
    @test direct.snapshot.cell_generations == candidate.snapshot.cell_generations
    @test direct.snapshot.trackers.values == candidate.snapshot.trackers.values
    @test collect(direct.snapshot.relationships) ==
          collect(candidate.snapshot.relationships)
    direct_descriptor = CorePotts.Adapt.adapt(
        Array, direct.snapshot.descriptor_state
    )
    candidate_descriptor = CorePotts.Adapt.adapt(
        Array, candidate.snapshot.descriptor_state
    )
    @test map(bank -> bank.values, direct_descriptor.banks) ==
          map(bank -> bank.values, candidate_descriptor.banks)
    return nothing
end

function _lw3_bootstrap_upper(
        direct::Vector{Float64},
        candidate::Vector{Float64};
        samples::Integer = LW3_BOOTSTRAP_SAMPLES,
        seed::UInt64 = LW3_BOOTSTRAP_SEED,
    )
    length(direct) == length(candidate) || throw(ArgumentError(
        "paired bootstrap inputs must have equal length"
    ))
    rng = Xoshiro(seed)
    count = length(direct)
    ratios = Vector{Float64}(undef, Int(samples))
    indices = Vector{Int}(undef, count)
    for sample_index in eachindex(ratios)
        rand!(rng, indices, 1:count)
        ratios[sample_index] = median(@view candidate[indices]) /
                               median(@view direct[indices])
    end
    return quantile(ratios, 0.95), ratios
end

function run_lw3_localworksets_parity(
        array_convert = identity;
        backend_name::Symbol = :cpu,
        side::Integer = LW3_SIDE,
        warm_batches::Integer = LW3_WARM_BATCHES,
        measured_batches::Integer = LW3_MEASURED_BATCHES,
    )
    # Registered external operations remain covered on CPU. The current Metal
    # provider intentionally rejects external execution families until they
    # have their own reviewed capability row, so the Metal parity witness uses
    # the complete built-in Hamiltonian surface without self-authorizing that
    # external operation.
    include_external = backend_name === :cpu
    fixture = lw3_localworksets_fixture(; side, include_external)

    proof_direct = _lw3_runtime(fixture, array_convert)
    proof_candidate = _lw3_runtime(fixture, array_convert; candidate = true)
    CorePotts.enqueue_program_through!(proof_direct, 12)
    CorePotts.enqueue_program_through!(proof_candidate, 12)
    direct_proof = _lw3_full_receipt!(proof_direct)
    candidate_proof = _lw3_full_receipt!(proof_candidate)
    _lw3_assert_receipt_parity(direct_proof, candidate_proof)
    @test Array(proof_direct.engine_workspace.cell_max_priority) == Array(
        proof_candidate.engine_workspace.direct.cell_max_priority
    )
    @test Array(proof_direct.engine_workspace.cell_min_identity) == Array(
        proof_candidate.engine_workspace.direct.cell_min_identity
    )
    @test Array(proof_direct.engine_workspace.dispositions) == Array(
        proof_candidate.engine_workspace.direct.dispositions
    )

    direct = _lw3_runtime(fixture, array_convert)
    candidate = _lw3_runtime(fixture, array_convert; candidate = true)
    initial_facts = CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    )
    for _ in 1:Int(warm_batches)
        _lw3_run_batch!(direct)
        _lw3_run_batch!(candidate)
    end

    direct_samples = Vector{Float64}(undef, Int(measured_batches))
    candidate_samples = similar(direct_samples)
    direct_allocations = Vector{Int}(undef, Int(measured_batches))
    candidate_allocations = similar(direct_allocations)
    order_rng = Xoshiro(UInt64(0x6c77335f6f726465))
    candidate_first = rand(order_rng, Bool, Int(measured_batches))
    final_direct = nothing
    final_candidate = nothing
    for index in eachindex(direct_samples)
        full_snapshot = index == lastindex(direct_samples)
        if candidate_first[index]
            candidate_sample = _lw3_run_batch!(candidate; full_snapshot)
            direct_sample = _lw3_run_batch!(direct; full_snapshot)
        else
            direct_sample = _lw3_run_batch!(direct; full_snapshot)
            candidate_sample = _lw3_run_batch!(candidate; full_snapshot)
        end
        direct_samples[index] = direct_sample.seconds
        candidate_samples[index] = candidate_sample.seconds
        direct_allocations[index] = direct_sample.bytes
        candidate_allocations[index] = candidate_sample.bytes
        if full_snapshot
            final_direct = direct_sample.receipt
            final_candidate = candidate_sample.receipt
        end
    end
    _lw3_assert_receipt_parity(final_direct, final_candidate)

    upper, _ = _lw3_bootstrap_upper(direct_samples, candidate_samples)
    direct_workspace = direct.engine_workspace
    candidate_workspace = candidate.engine_workspace
    facts = CorePotts.LocalWorksets.inspect(candidate_workspace.prepared)
    @test direct_workspace.color_order == candidate_workspace.direct.color_order
    @test facts.lowering_detail.workspace.rank_identity ==
          initial_facts.lowering_detail.workspace.rank_identity
    @test facts.lowering_detail.workspace.identity_identity ==
          initial_facts.lowering_detail.workspace.identity_identity
    @test facts.lease_identity == initial_facts.lease_identity
    color_count = Int(fixture.program.checkerboard_plan.color_count)
    direct_median_allocation = median(direct_allocations)
    candidate_median_allocation = median(candidate_allocations)
    report = (
        schema = :lw3_localworksets_parity_v1,
        backend = backend_name,
        registered_external_hamiltonian = include_external,
        side = Int(side),
        batch_mcs = LW3_BATCH_MCS,
        warm_batches = Int(warm_batches),
        measured_batches = Int(measured_batches),
        bootstrap_samples = LW3_BOOTSTRAP_SAMPLES,
        bootstrap_seed = LW3_BOOTSTRAP_SEED,
        candidate_first,
        direct_seconds = direct_samples,
        candidate_seconds = candidate_samples,
        direct_allocated_bytes = direct_allocations,
        candidate_allocated_bytes = candidate_allocations,
        direct_median_allocated_bytes = direct_median_allocation,
        candidate_median_allocated_bytes = candidate_median_allocation,
        median_allocated_byte_delta =
            candidate_median_allocation - direct_median_allocation,
        allocation_comparison =
            :raw_candidate_including_leases_and_events_vs_unadjusted_direct,
        direct_median_seconds = median(direct_samples),
        candidate_median_seconds = median(candidate_samples),
        median_ratio = median(candidate_samples) / median(direct_samples),
        paired_bootstrap_upper_95 = upper,
        threshold = 1.05,
        color_count,
        checkerboard_body_launches_per_mcs = 1 + 9 * color_count,
        localworksets_claim_launches_per_color = facts.launches,
        direct_settlements = direct_workspace.execution.settlement_count,
        candidate_settlements = candidate_workspace.execution.settlement_count,
        direct_synchronizations = direct_workspace.execution.synchronization_count,
        candidate_synchronizations =
            candidate_workspace.execution.synchronization_count,
        localworksets_waits = facts.wait_count,
        localworksets_submitted = facts.submitted,
        localworksets_drained = facts.drained,
        localworksets_workspace = facts.lowering_detail.workspace,
        localworksets_topology_transfer_bytes = facts.topology_transfer_bytes,
        localworksets_record_capacity = facts.record_capacity,
        localworksets_poisoned = facts.poisoned,
        final_ownership_checksum = sum(
            index * Int(owner) for (index, owner) in
                enumerate(final_candidate.snapshot.ownership)
        ),
    )
    @info "LW-3 paired noninferiority diagnostic" backend = backend_name median_ratio = report.median_ratio upper_95 = report.paired_bootstrap_upper_95 direct_median = report.direct_median_seconds candidate_median = report.candidate_median_seconds
    @test report.localworksets_claim_launches_per_color == 4
    @test report.direct_settlements == report.candidate_settlements
    @test report.direct_synchronizations == report.candidate_synchronizations
    @test report.localworksets_waits == report.candidate_settlements
    @test report.localworksets_submitted == report.localworksets_drained
    @test report.localworksets_topology_transfer_bytes == 0
    @test !report.localworksets_poisoned
    # This conservative raw comparison gives the direct path no synthetic
    # lease/event allowance. The candidate still must not allocate more at the
    # median; its prepared claim runtime replaces direct per-MCS claim-kernel
    # runtime construction.
    @test report.candidate_median_allocated_bytes <=
          report.direct_median_allocated_bytes
    @test report.paired_bootstrap_upper_95 <= report.threshold
    return report
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(run_lw3_localworksets_parity())
end
