using Potts
using ModelingToolkitBase
using Statistics
using Symbolics
using Test

import CorePotts
import LocalMath

isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("../../test/fixtures/NeutralExternalTerms.jl")

const GRAPH_PARITY_SIDE = 128
const GRAPH_PARITY_BATCH_MCS = 10
const GRAPH_PARITY_WARM_BATCHES = 10
const GRAPH_PARITY_MEASURED_BATCHES = 50

function localmath_graph_fixture(
        ;
        side::Integer = GRAPH_PARITY_SIDE,
        include_external::Bool = true,
    )
    side >= 16 || throw(ArgumentError("LocalMath execution parity side must be at least 16"))
    @variables localmath_graph_field
    @parameters localmath_graph_external_weight = 0.125
    cell = CellKind(:localmath_graph_cell; extinction = ForbidExtinction())
    medium = MediumKind(:localmath_graph_medium)
    field = FieldState(localmath_graph_field; name = :localmath_graph_field, initial = 0.0)
    fold_a = SiteBinding(:localmath_graph_fold_a)
    fold_b = SiteBinding(:localmath_graph_fold_b)
    fold_c = SiteBinding(:localmath_graph_fold_c)
    external_site = SiteBinding(:localmath_graph_external_site)
    energy_statements = (
        Volume(cell; target = 64.0, strength = 0.75),
        ContactEnergy([
            (medium ↔ cell) => 5.0,
            (cell ↔ cell) => 1.5,
        ]),
        Elongation(cell; target = 3.0, strength = 0.25),
        HamiltonianTerm(
            :localmath_graph_fold_large_positive;
            domain = sites(:lattice),
            anchor = fold_a,
            expression = Float32(16_384) * occupancy(cell, fold_a),
        ),
        HamiltonianTerm(
            :localmath_graph_fold_large_negative;
            domain = sites(:lattice),
            anchor = fold_b,
            expression = Float32(-16_384) * occupancy(cell, fold_b),
        ),
        HamiltonianTerm(
            :localmath_graph_fold_residual;
            domain = sites(:lattice),
            anchor = fold_c,
            expression = Float32(0.375) * occupancy(cell, fold_c),
        ),
    )
    external_statement = NeutralExternalTerms.ExternalWeightedSiteTerm(
        :localmath_graph_registered_external,
        localmath_graph_external_weight,
        localmath_graph_field,
        cell,
        external_site,
    )
    protocol = Protocol(
        Sweep(; attempts = AttemptsPerSite(1), temperature = 2.0);
        name = :main,
    )
    lattice = Lattice(
        (Int(side), Int(side));
        boundary = Periodic(),
        max_cells = 4,
        relations = (
            proposal = VonNeumann(),
            contact = Moore(),
        ),
    )
    statements = include_external ?
        (lattice, cell, medium, field, energy_statements...,
         external_statement, protocol) :
        (lattice, cell, medium, energy_statements..., protocol)
    source = PottsSystem(
        name = :localmath_execution_parity,
        statements = StatementSet(statements),
        unknowns = include_external ? [localmath_graph_field] : [],
        parameters = include_external ? [localmath_graph_external_weight] : [],
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
        values = include_external ? (localmath_graph_field => field_values,) : (),
    )
    executable = Potts._lower_execution_plan(
        compiled,
        CheckerboardSweepCPM(),
        CPUBackend(),
        Float32,
    )
    return (
        executable,
        program = executable.core_program,
        initial = Potts._core_initial_state(executable, initial),
    )
end

function _localmath_graph_runtime(
        fixture,
        array_convert;
        seed::UInt64 = UInt64(0x6c77335f73656564),
        replica::UInt32 = UInt32(7),
        repeat::UInt32 = UInt32(11),
    )
    runtime = CorePotts.initialize_program(
        fixture.program,
        fixture.initial,
        fixture.program.parameter_defaults,
        seed,
        replica;
        repeat,
    )
    return array_convert === identity ? runtime :
           CorePotts.adapt_program_runtime(array_convert, runtime)
end

_localmath_graph_request(; full_snapshot::Bool) = CorePotts.ProgramSettlementRequest(
    CorePotts.PublicStepSettlement; full_snapshot
)

function _localmath_graph_run_batch!(
        runtime;
        mcs::Integer = GRAPH_PARITY_BATCH_MCS,
        full_snapshot::Bool = false,
    )
    target = CorePotts._checkerboard_execution_position(
        runtime.engine_workspace
    ).submitted_mcs + Int(mcs)
    sample = @timed begin
        CorePotts.enqueue_program_through!(runtime, target)
        CorePotts.settle_program!(
            runtime, _localmath_graph_request(; full_snapshot)
        )
    end
    return (
        seconds = sample.time,
        bytes = sample.bytes,
        allocations = Base.gc_alloc_count(sample.gcstats),
        receipt = sample.value,
    )
end

function _localmath_graph_full_receipt!(runtime)
    return CorePotts.settle_program!(
        runtime, _localmath_graph_request(; full_snapshot = true)
    )
end

function _localmath_graph_assert_receipt_parity(first, second)
    @test first.submitted_mcs == second.submitted_mcs
    @test first.drained_mcs == second.drained_mcs
    @test first.committed_mcs == second.committed_mcs
    @test first.materialized_mcs == second.materialized_mcs
    @test first.counters == second.counters
    @test first.status == second.status
    @test typeof(first.failure) === typeof(second.failure)
    @test first.snapshot.ownership == second.snapshot.ownership
    @test first.snapshot.cell_kinds == second.snapshot.cell_kinds
    @test first.snapshot.cell_generations == second.snapshot.cell_generations
    @test first.snapshot.trackers.values == second.snapshot.trackers.values
    @test collect(first.snapshot.relationships) ==
          collect(second.snapshot.relationships)
    first_descriptor = CorePotts.Adapt.adapt(
        Array, first.snapshot.descriptor_state
    )
    second_descriptor = CorePotts.Adapt.adapt(
        Array, second.snapshot.descriptor_state
    )
    @test map(bank -> bank.values, first_descriptor.banks) ==
          map(bank -> bank.values, second_descriptor.banks)
    return nothing
end

function _localmath_graph_preparation_facts(runtime)
    execution = runtime.engine_workspace
    return (
        clear_report = map(LocalMath.inspect, execution.clear_report),
        color_mechanics = map(
            LocalMath.inspect, execution.color_laws.prepared),
        before_lifecycle = map(execution.stage_boundaries.before) do entry
            map(LocalMath.inspect, entry.prepared)
        end,
        after_lifecycle = map(execution.stage_boundaries.after) do entry
            map(LocalMath.inspect, entry.prepared)
        end,
    )
end

_localmath_graph_all_facts(facts) = (
    facts.clear_report...,
    facts.color_mechanics...,
    Tuple(Iterators.flatten(facts.before_lifecycle))...,
    Tuple(Iterators.flatten(facts.after_lifecycle))...,
)

_localmath_graph_state(fact) = fact.realized.state
_localmath_graph_submitted(fact) = _localmath_graph_state(fact).submitted
_localmath_graph_drained(fact) = _localmath_graph_state(fact).drained
_localmath_graph_provider_completions(fact) =
    _localmath_graph_state(fact).provider_completions
_localmath_graph_scope_completions(fact) =
    _localmath_graph_state(fact).provider_scope_completions

function run_localmath_execution_parity(
        array_convert = identity;
        backend_name::Symbol = :cpu,
        side::Integer = GRAPH_PARITY_SIDE,
        warm_batches::Integer = GRAPH_PARITY_WARM_BATCHES,
        measured_batches::Integer = GRAPH_PARITY_MEASURED_BATCHES,
        include_external::Bool = backend_name === :cpu,
        schema::Symbol = :localmath_checkerboard_mechanics_v1,
    )
    fixture = localmath_graph_fixture(; side, include_external)

    # Two instances of the same production graph provide a deterministic
    # trajectory witness without retaining a reference execution family.
    proof = _localmath_graph_runtime(fixture, array_convert)
    mirror = _localmath_graph_runtime(fixture, array_convert)
    CorePotts.enqueue_program_through!(proof, 12)
    CorePotts.enqueue_program_through!(mirror, 12)
    proof_receipt = _localmath_graph_full_receipt!(proof)
    mirror_receipt = _localmath_graph_full_receipt!(mirror)
    _localmath_graph_assert_receipt_parity(proof_receipt, mirror_receipt)

    runtime = _localmath_graph_runtime(fixture, array_convert)
    initial_facts = _localmath_graph_preparation_facts(runtime)
    for _ in 1:Int(warm_batches)
        _localmath_graph_run_batch!(runtime)
    end

    count = Int(measured_batches)
    samples = Vector{Float64}(undef, count)
    allocated_bytes = Vector{Int}(undef, count)
    allocation_counts = similar(allocated_bytes)
    final_receipt = nothing
    for index in eachindex(samples)
        sample = _localmath_graph_run_batch!(
            runtime; full_snapshot = index == lastindex(samples)
        )
        samples[index] = sample.seconds
        allocated_bytes[index] = sample.bytes
        allocation_counts[index] = sample.allocations
        index == lastindex(samples) && (final_receipt = sample.receipt)
    end

    facts = _localmath_graph_preparation_facts(runtime)
    all_facts = _localmath_graph_all_facts(facts)
    initial_all_facts = _localmath_graph_all_facts(initial_facts)
    initial_workspace_bytes = sum(
        fact.planning.workspace_bytes for fact in initial_all_facts
    )
    color_count = Int(fixture.program.checkerboard_plan.color_count)
    attempts = Int(fixture.program.attempts_per_site)
    total_mcs = (Int(warm_batches) + count) * GRAPH_PARITY_BATCH_MCS
    expected_submissions = UInt64(total_mcs * attempts * color_count)
    settlements = Int(warm_batches) + count
    @test sum(_localmath_graph_submitted, facts.color_mechanics) ==
          expected_submissions
    @test sum(_localmath_graph_submitted, facts.clear_report) == UInt64(total_mcs)
    @test all(fact -> _localmath_graph_submitted(fact) ==
        _localmath_graph_drained(fact), all_facts)
    @test sum(_localmath_graph_provider_completions, all_facts) >= settlements
    @test map(_localmath_graph_scope_completions, all_facts) ==
          map(count -> count + settlements,
              map(_localmath_graph_scope_completions, initial_all_facts))
    @test map(fact -> fact.realized.lease_capacity, all_facts) ==
          map(fact -> fact.realized.lease_capacity, initial_all_facts)
    @test all(fact -> !_localmath_graph_state(fact).poisoned, all_facts)

    execution = runtime.engine_workspace
    inspection = CorePotts._inspect_checkerboard_execution(execution)
    report = (
        schema = schema,
        backend = backend_name,
        registered_external_hamiltonian = include_external,
        side = Int(side),
        batch_mcs = GRAPH_PARITY_BATCH_MCS,
        warm_batches = Int(warm_batches),
        measured_batches = count,
        seconds = samples,
        allocated_bytes,
        allocation_counts,
        median_allocation_count = median(allocation_counts),
        median_allocated_bytes = median(allocated_bytes),
        median_seconds = median(samples),
        color_count,
        attempts_per_site = attempts,
        execution_identity = inspection.identity,
        execution_order = inspection.order,
        clear_report_launches = map(
            fact -> fact.planning.base_provider_launch_count,
            facts.clear_report),
        color_mechanics_launches = map(
            fact -> fact.planning.base_provider_launch_count,
            facts.color_mechanics),
        before_lifecycle_launches = map(
            fact -> fact.planning.base_provider_launch_count,
            Tuple(Iterators.flatten(facts.before_lifecycle))),
        after_lifecycle_launches = map(
            fact -> fact.planning.base_provider_launch_count,
            Tuple(Iterators.flatten(facts.after_lifecycle))),
        settlements = execution.core.execution.settlement_count,
        synchronizations = execution.core.execution.synchronization_count,
        provider_waits = sum(_localmath_graph_provider_completions, all_facts),
        provider_scope_waits = only(unique(
            map(_localmath_graph_scope_completions, all_facts)
        )),
        clear_report_submitted = sum(
            _localmath_graph_submitted, facts.clear_report),
        color_mechanics_submitted = sum(
            _localmath_graph_submitted, facts.color_mechanics),
        color_mechanics_drained = sum(
            _localmath_graph_drained, facts.color_mechanics),
        algorithmic_workspace_bytes = sum(
            fact.planning.workspace_bytes for fact in all_facts
        ),
        algorithmic_workspace_stable = sum(
            fact.planning.workspace_bytes for fact in all_facts
        ) == initial_workspace_bytes,
        workspace_ownership = map(
            fact -> fact.realized.workspace_ownership, all_facts),
        workspace_identities = map(all_facts) do fact
            map(leaf -> (leaf.name, leaf.path), fact.planning.workspace)
        end,
        lease_capacity = map(fact -> fact.realized.lease_capacity, all_facts),
        poisoned = any(fact -> _localmath_graph_state(fact).poisoned,
            all_facts),
        final_ownership_checksum = sum(
            index * Int(owner) for (index, owner) in
                enumerate(final_receipt.snapshot.ownership)
        ),
    )
    @info "canonical checkerboard execution diagnostic" backend = backend_name median = report.median_seconds
    @test report.settlements == settlements
    @test report.synchronizations == settlements
    @test report.provider_waits == settlements
    @test report.color_mechanics_submitted ==
          report.color_mechanics_drained
    @test report.algorithmic_workspace_stable
    @test all(==(:package), report.workspace_ownership)
    @test !report.poisoned
    return report
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(run_localmath_execution_parity())
end
