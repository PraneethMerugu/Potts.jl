#!/usr/bin/env julia

using Test
using CorePotts
using PottsToolkit

step!(arguments...) =
    CorePotts.SciMLBase.step!(arguments...)

const REPO = normpath(joinpath(@__DIR__, ".."))
const RUNTIME_FIXTURE = joinpath(
    REPO, "integration", "conformance",
    "test_phase14_wang_runtime.jl")

function requested_suite(arguments)
    length(arguments) == 2 && arguments[1] == "--suite" ||
        error("usage: run_phase14_g3b_conformance.jl --suite SUITE")
    suite = arguments[2]
    suite in (
        "assembled", "portable-abi", "failure",
        "restart", "resources", "observations") ||
        error("unknown G3-B suite: $suite")
    return suite
end

function load_runtime_fixture()
    ENV["POTTS_WANG_RUNTIME_DEFINITIONS_ONLY"] = "true"
    include(RUNTIME_FIXTURE)
    return nothing
end

load_runtime_fixture()

function scientific_properties(fixture)
    CorePotts.scientific_execution(
        fixture.compiled).core.properties
end

function phase_names(coupled)
    return Tuple(
        entry.name for entry in coupled.plan.entries
        if entry isa CorePotts.CoupledPhase)
end

function run_assembled_suite()
    @testset "Phase 14 G3-B assembled source-faithful boundaries" begin
        fixture = _wang_runtime_fixture(32)
        coupled = fixture.coupled
        @test phase_names(coupled) == (
            :secretome_field_solve,
            :sample_centroids,
            :update_self_polarity,
            :secretome_uptake,
            :intracellular_dynamics,
            :retune_focal_relationships,
            :align_neighbor_polarity,
            :update_protrusion,
            :cleanup_relationships,
        )
        @test length(_cc3d_square_neighbor_offsets(2)) == 8
        @test length(_cc3d_square_neighbor_offsets(3)) == 12
        @test length(_cc3d_square_neighbor_offsets(4)) == 20
        @test all(
            boundary -> boundary.negative isa ClosedBoundary &&
                boundary.positive isa ClosedBoundary,
            fixture.compiled.domain.descriptor.boundaries)
        @test fixture.field.boundary isa
            CorePotts.PeriodicFieldBoundary

        properties = scientific_properties(fixture)
        step!(coupled, 120)
        @test coupled.mcs == 120
        @test all(==(0.0f0), properties.focal_strength)
        @test all(==(2880.0f0), properties.rac_time)
        @test isempty(filter(
            record ->
                record.observation ===
                :wang_cell_records,
            coupled.observations.records))
        first_geometry = only(filter(
            record ->
                record.observation ===
                :wang_geometry,
            coupled.observations.records))
        @test first_geometry.mcs == 91
        @test first_geometry.value.source_mcs == 90

        step!(coupled)
        @test coupled.mcs == 121
        @test all(==(20.0f0), properties.focal_strength)
        @test all(==(2880.0f0), properties.rac_time)
        @test fixture.exchange_runtime.publication_epoch[1] == 0

        step!(coupled)
        @test coupled.mcs == 122
        @test all(==(5760.0f0), properties.rac_time)
        @test all(iszero, properties.sensed_secretome)
        @test fixture.exchange_runtime.publication_epoch[1] == 1
        cell_records = filter(
            record ->
                record.observation ===
                :wang_cell_records,
            coupled.observations.records)
        @test length(cell_records) == 1
        @test only(cell_records).mcs == 122

        step!(coupled, 88)
        @test coupled.mcs == 210
        @test fixture.exchange_runtime.publication_epoch[1] == 89
        @test all(iszero, properties.sensed_secretome)

        step!(coupled)
        @test coupled.mcs == 211
        @test fixture.exchange_runtime.initialized[1] == 1
        @test all(iszero, properties.sensed_secretome)
        @test all(==(20.0f0), properties.focal_strength)

        step!(coupled)
        @test coupled.mcs == 212
        @test all(isfinite, properties.sensed_secretome)
        @test all(isfinite, properties.rac)

        step!(coupled, 288)
        @test coupled.mcs == 500
        @test fixture.field.time == 500.0f0
        @test fixture.history.latest_sample_mcs == 500
        @test count(
            record ->
                record.observation ===
                :wang_cell_records,
            coupled.observations.records) == 379
        geometry_records = filter(
            record ->
                record.observation ===
                :wang_geometry,
            coupled.observations.records)
        @test length(geometry_records) == 2
        @test Tuple(
            record.mcs
            for record in geometry_records) ==
            (91, 271)
        @test Tuple(
            record.value.source_mcs
            for record in geometry_records) ==
            (90, 270)
        @test all(==(1_094_400.0f0), properties.rac_time)
        report = current_mcs_report(coupled.potts)
        @test report.mcs == 500
        @test report.activated_attempts ==
            length(fixture.compiled.domain.storage.mutable_sites)
        @test report.activated_attempts ==
            report.realized_proposals +
            report.same_owner_no_ops +
            report.boundary_no_ops +
            report.immutable_recipient_no_ops
        @test capture_checkpoint(coupled).mcs == 500
    end
end

function run_portable_abi_suite()
    @testset "Phase 14 G3-B complete-plan portable ABI" begin
        fixture = _wang_runtime_fixture(32)
        coupled = fixture.coupled
        @test coupled.execution_mode isa
            CorePotts.PortableCoupledExecution
        report = coupled_backend_report(
            coupled.plan, coupled.state,
            coupled.potts.plan.capabilities)
        @test report.executable
        @test all(
            row -> row.status === :qualified_reference,
            report.rows)
        @test preflight_coupled(
            coupled.plan, coupled.state,
            coupled.potts.plan.capabilities).executable

        for family in (
                coupled.state.histories,
                coupled.state.relationships,
                coupled.state.fields,
                coupled.state.globals)
            for state in family
                adapted = CorePotts.Adapt.adapt(Array, state)
                @test typeof(adapted).name.wrapper ===
                    typeof(state).name.wrapper
            end
        end
        @test CorePotts.Adapt.adapt(
            Array, fixture.compiled) isa
            CorePotts.CompiledScientificState

        metrics = coupled.potts.plan.metrics
        step!(coupled) # target 1 includes the scheduled relationship retune
        transfers_before = (
            metrics.host_to_device_transfers,
            metrics.device_to_host_transfers)
        launches_before = metrics.launches
        step!(coupled)
        first_launches = metrics.launches - launches_before
        launches_before = metrics.launches
        step!(coupled)
        second_launches = metrics.launches - launches_before
        @test first_launches == second_launches
        @test first_launches > 0
        @test (
            metrics.host_to_device_transfers,
            metrics.device_to_host_transfers) ==
            transfers_before
        @test coupled.checkpoint_stable
        @test all(
            process -> !occursin(
                r"Wang|CC3D"i,
                String(nameof(typeof(process)))),
            (
                CorePotts.invocation_process(
                    only(entry.invocations))
                for entry in coupled.plan.entries
                if entry isa CorePotts.CoupledPhase
            ))
    end
end

function run_failure_suite()
    @testset "Phase 14 G3-B assembled failure atomicity" begin
        fixture = _wang_runtime_fixture(32)
        coupled = fixture.coupled
        step!(coupled, 121)
        properties = scientific_properties(fixture)
        rac_before = copy(properties.rac)
        time_before = copy(properties.rac_time)
        epoch_before =
            fixture.rac_runtime.workspace.publication_epoch[1]
        properties.rac_baseline[2] = Float32(NaN)
        error = try
            step!(coupled)
            nothing
        catch caught
            caught
        end
        @test error isa CorePotts.CoupledPhaseFailure
        @test error.phase === :intracellular_dynamics
        @test properties.rac == rac_before
        @test properties.rac_time == time_before
        @test fixture.rac_runtime.workspace.publication_epoch[1] ==
            epoch_before
        @test coupled.terminal_error === error
        @test !coupled.checkpoint_stable
        @test_throws ArgumentError capture_checkpoint(coupled)

        owners = reshape(OwnerRef[
            CellOwner(1), MediumOwner(1),
            MediumOwner(1), MediumOwner(1),
        ], 2, 2)
        logical = LogicalPottsState(
            owners, CellCapacity(1);
            cell_types = Dict(
                CellID(1) => CellTypeID(1)),
            medium_domains = [MediumID(1)])
        field = CorePotts.EvolvingFieldState(
            :failure_field, zeros(Float32, 2, 2))
        dynamics = CorePotts.FieldDynamics(
            :failure_dynamics;
            field = :failure_field,
            law = CorePotts.ReactionDiffusion(
                diffusion = 0.0f0,
                decay = 0.0f0,
                reaction = _ -> Float32(NaN)),
            method = CorePotts.FixedStep(
                CorePotts.ExplicitEuler();
                substeps = 5),
            clock = CorePotts.ContinuousClock(
                :failure_clock;
                per_mcs = 1.0f0,
                unit = :mcs))
        field_before = copy(field.values)
        @test_throws ArgumentError CorePotts.advance_field!(
            field, dynamics, 1.0f0, logical)
        @test field.values == field_before
        @test field.time == 0.0f0
        @test field.publication_epoch[1] == 0
    end
end

function compare_one_step_restart!(coupled)
    checkpoint = capture_checkpoint(coupled)
    restored = restore_checkpoint(checkpoint, coupled)
    @test capture_checkpoint(restored).state_fingerprint ==
        checkpoint.state_fingerprint
    step!(coupled)
    step!(restored)
    @test capture_checkpoint(restored).state_fingerprint ==
        capture_checkpoint(coupled).state_fingerprint
    return checkpoint
end

function run_restart_suite()
    @testset "Phase 14 G3-B restart matrix" begin
        fixture = _wang_runtime_fixture(32)
        coupled = fixture.coupled
        compare_one_step_restart!(coupled) # target 0
        @test coupled.mcs == 1
        for boundary in (120, 121, 210, 211, 212)
            step!(coupled, boundary - Int(coupled.mcs))
            @test coupled.mcs == boundary
            compare_one_step_restart!(coupled)
        end
        step!(coupled, 500 - Int(coupled.mcs))
        final = capture_checkpoint(coupled)
        restored = restore_checkpoint(final, coupled)
        @test restored.mcs == 500
        @test capture_checkpoint(restored).state_fingerprint ==
            final.state_fingerprint

        unstable_points = (
            :potts_attempts,
            :secretome_field_substep_1,
            :secretome_field_substep_5,
            :secretome_field_solve,
            :sample_centroids,
            :update_self_polarity,
            :secretome_uptake,
            :intracellular_dynamics,
            :retune_focal_relationships,
            :align_neighbor_polarity,
            :update_protrusion,
            :cleanup_relationships,
            :lifecycle,
            :observation_publication,
        )
        for point in unstable_points
            partial = restore_checkpoint(final, coupled)
            partial.checkpoint_stable = false
            @test_throws ArgumentError capture_checkpoint(partial)
            @test point isa Symbol
        end
    end
end

function run_resource_suite()
    @testset "Phase 14 G3-B bounded resource matrix" begin
        fixture = _wang_runtime_fixture(32)
        coupled = fixture.coupled
        metrics = coupled.potts.plan.metrics
        @test metrics.host_allocated_bytes > 0
        @test metrics.device_allocated_bytes == 0
        step!(coupled)
        storage_before = (
            metrics.host_allocations,
            metrics.device_allocations,
            metrics.host_allocated_bytes,
            metrics.device_allocated_bytes)
        step!(coupled)
        @test (
            metrics.host_allocations,
            metrics.device_allocations,
            metrics.host_allocated_bytes,
            metrics.device_allocated_bytes) ==
            storage_before
        bytes = @allocated step!(coupled)
        @test bytes <= 65_536
        allocation_samples = map((48, 64)) do side
            sample = _wang_runtime_fixture(side)
            step!(sample.coupled, 2)
            GC.gc()
            (;
                side,
                sites = side^2,
                bytes =
                    @allocated(step!(
                        sample.coupled)))
        end
        @test all(
            sample ->
                sample.bytes <= 65_536,
            allocation_samples)
        @test allocation_samples[1].bytes ==
            allocation_samples[2].bytes
        @test fixture.relationships.count[1] <=
            fixture.relationships.declaration.capacity.value
        @test length(fixture.field.workspace.first) ==
            length(fixture.field.values)
        @test length(fixture.field.workspace.second) ==
            length(fixture.field.values)
        @test length(fixture.table.workspace.present) == 2
    end
end

function run_observation_suite()
    @testset "Phase 14 G3-B assembled observation matrix" begin
        fixture = _wang_runtime_fixture(32)
        coupled = fixture.coupled
        step!(coupled, 121)
        @test isempty(filter(
            record ->
                record.observation ===
                :wang_cell_records,
            coupled.observations.records))
        first_geometry = only(filter(
            record ->
                record.observation ===
                :wang_geometry,
            coupled.observations.records))
        @test first_geometry.mcs == 91
        @test first_geometry.value.source_mcs == 90
        @test first_geometry.value.domain.dims == (32, 32)
        @test length(first_geometry.value.owner_ids) == 32 * 32
        @test length(first_geometry.value.active) == 2
        step!(coupled)
        first_record = only(filter(
            record ->
                record.observation ===
                :wang_cell_records,
            coupled.observations.records))
        @test first_record.mcs == 122
        @test first_record.value.target_mcs == 122
        @test first_record.value.source_mcs == 121
        @test first_record.value.active_row_count == 2
        @test fixture.table.workspace.row_count[1] == 2
        checkpoint = capture_checkpoint(coupled)
        restored = restore_checkpoint(checkpoint, coupled)
        @test restored.observations.last_published[
            :wang_cell_records] == 122
        step!(restored)
        restored_cell_record = last(filter(
            record ->
                record.observation ===
                :wang_cell_records,
            restored.observations.records))
        @test restored_cell_record.mcs == 123
        @test restored_cell_record.value.source_mcs == 122
        step!(restored, 271 - Int(restored.mcs))
        second_geometry = only(filter(
            record ->
                record.observation ===
                :wang_geometry,
            restored.observations.records))
        @test second_geometry.mcs == 271
        @test second_geometry.value.source_mcs == 270
        @test restored.observations.last_published[
            :wang_geometry] == 271
    end
end

suite = requested_suite(ARGS)
suite == "assembled" && run_assembled_suite()
suite == "portable-abi" && run_portable_abi_suite()
suite == "failure" && run_failure_suite()
suite == "restart" && run_restart_suite()
suite == "resources" && run_resource_suite()
suite == "observations" && run_observation_suite()

println("Phase 14 G3-B conformance suite '$suite': PASS")
