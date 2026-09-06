include("fixtures/ExternalCompilerSPIFixture.jl")
include("fixtures/ExternalSurfaceOperationFixture.jl")
using .ExternalCompilerSPIFixture

@inline _external_tracker_lane_digits(accumulator, value) =
    accumulator * Int32(100) + value
@inline _external_tracker_lane_digits_finish(accumulator, count) = accumulator

function external_spi_materialization(term_count; mismatched = false)
    fixture = ExternalCompilerSPIFixture.model(term_count; mismatched)
    completed = complete(
        fixture.source; registry = ExternalCompilerSPIFixture.registry()
    )
    scheduled = mtkcompile(completed)
    problem = PottsProblem(
        scheduled,
        fixture.initial,
        (0, 1);
        p = (fixture.weight => 2.0,),
        seed = 0x5e71,
    )
    return (; fixture, completed, scheduled, problem)
end

@testset "external tracker operations keep qualified relation identity" begin
    @variables external_tracker_gate
    cell = CellKind(:external_surface_cell; extinction = RetireAtZero())
    medium = MediumKind(:external_surface_medium)
    gate = FieldState(
        external_tracker_gate; name = :external_tracker_gate, initial = 0.0)
    proposal = ProposalContext(:external_surface_copy)
    surface_digits = LocalMath.bounded_fold(
        identity, _external_tracker_lane_digits, Int32(0),
        _external_tracker_lane_digits_finish;
        domain = LocalMath.Where(>=(Int32(0))),
        oninvalid = LocalMath.RejectInvalid(),
        onempty = LocalMath.RejectEmpty(),
        order = LocalMath.CanonicalLeftFold(),
    )
    source = PottsSystem(
        name = :external_surface_relations,
        statements = StatementSet((
            Lattice(
                (3, 3);
                boundary = Closed(),
                relations = (
                    proposal = VonNeumann(),
                    surface = VonNeumann(),
                    surface_alt = Moore(),
                ),
            ),
            cell,
            medium,
            gate,
            ProposalConstraint(
                :external_neighbor_surface,
                proposal.is_extension &
                (field_value(gate, proposal.source_site) == 1) &
                (field_value(gate, proposal.target_site) == 2) &
                (surface_digits(gather(
                    ExternalSurfaceOperationFixture.external_cell_surface,
                    :surface_alt;
                    at = proposal.target_site,
                )) == 808) &
                (surface_digits(gather(
                    ExternalSurfaceOperationFixture.external_cell_surface_alt,
                    :surface;
                    at = proposal.target_site,
                )) >= 0),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [external_tracker_gate],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 3, 3)
    source_site = CartesianIndex(2, 2)
    repeated_owner_site = CartesianIndex(1, 3)
    target_site = CartesianIndex(1, 2)
    labels[source_site] = 1
    labels[repeated_owner_site] = 1
    gate_values = zeros(Float64, 3, 3)
    gate_values[source_site] = 1
    gate_values[target_site] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (external_tracker_gate => gate_values,),
    )
    integrator = init(
        PottsProblem(scheduled, initial, (0, 1); seed = 0x5e72),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    # This is package-owned qualification of the private late-materialization
    # artifact, not an author-facing access path. The report itself is the
    # immutable Potts/CorePotts boundary authority.
    reports = getfield(getfield(integrator, :plan), :reports)
    inspections = filter(
        report -> report.quantity === :cell_surface,
        reports.execution.trackers.descriptors,
    )
    @test length(inspections) == 2
    @test allunique(getproperty.(inspections, :source_handle))
    @test Set(getproperty.(inspections, :proposal_cost)) == Set((
        (class = :bounded_neighborhood, maximum_neighbors = Int16(4)),
        (class = :bounded_neighborhood, maximum_neighbors = Int16(8)),
    ))
    @test reports.execution.trackers.groups == 2

    # The VN surface tracker reports eight exposed faces for the two
    # diagonally separated owner sites. Moore traversal reaches that owner
    # twice, in canonical lane order, while absent and medium lanes do not
    # participate: 0 -> 8 -> 808.
    function witness(algorithm)
        return solve(
            PottsProblem(scheduled, initial, (0, 1); seed = UInt64(0x5e72)),
            algorithm;
            backend = CPUBackend(), scalar_type = Float64,
            save_everystep = true,
        )
    end
    sequential = witness(SequentialCPM())
    checkerboard = witness(CheckerboardSweepCPM())
    @test last(sequential).ownership == labels
    @test last(checkerboard).ownership == labels
    @test sequential.stats.accepted == 0
    @test checkerboard.stats.accepted == 0

    mixed = PottsSystem(
        name = :mixed_tracker_projection_use,
        statements = StatementSet((
            Lattice(
                (3, 3); boundary = Closed(),
                relations = (
                    proposal = VonNeumann(), surface = VonNeumann(),
                    surface_alt = Moore(),
                ),
            ),
            cell,
            medium,
            HamiltonianTerm(
                :mixed_tracker_projection,
                domain = sites(:lattice),
                anchor = SiteBinding(:mixed_tracker_projection_site),
                expression = ExternalSurfaceOperationFixture.external_cell_surface(
                    proposal.target_site) +
                    surface_digits(gather(
                        ExternalSurfaceOperationFixture.external_cell_surface,
                        :surface_alt; at = proposal.target_site,
                    )),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    )
    @test_throws Potts.PottsValidationError mtkcompile(mixed)
end

@testset "external CompilerSPI lowering is authenticated and executable" begin
    payload = ExternalCompilerSPIFixture.ExternalDescriptorPayload(0x0001)
    encoded = CorePotts.CompilerSPI.descriptor_payload_checkpoint_encode(payload)
    @test encoded == (schema = UInt16(1),)
    @test CorePotts.CompilerSPI.descriptor_payload_checkpoint_reconstruct(
        payload, encoded
    ) === payload
    @test CorePotts.CompilerSPI.descriptor_payload_adapt(identity, payload) ===
          payload
    @test CorePotts.CompilerSPI.descriptor_payload_inspection(payload) == (
        family = :ExternalDescriptorPayload,
        schema = UInt16(1),
    )

    materialized = external_spi_materialization(1)
    completed_again = complete(
        materialized.fixture.source;
        registry = ExternalCompilerSPIFixture.registry(),
    )
    @test completed_system_fingerprint(materialized.completed) ==
          completed_system_fingerprint(completed_again)

    record = only(filter(
        candidate -> candidate.identity.local_id ==
                     StatementID(:external_energy_1),
        inspect(materialized.completed, Statements()),
    ))
    @test record.kind === :HamiltonianTerm
    @test record.provenance.schema === ExternalCompilerSPIFixture.SCHEMA
    @test record.provenance.registered_lowering_identity ===
          :lower_external_site_energy
    @test record.provenance.registered_descriptor_payload_type ===
          ExternalCompilerSPIFixture.ExternalDescriptorPayload

    integrator = init(
        materialized.problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    reports = getfield(getfield(integrator, :plan), :reports)
    inspections = collect(Iterators.flatten(
        reports.descriptors.descriptor_inspections
    ))
    external_inspection = only(filter(
        item -> item.qualified_source.local_id ==
                StatementID(:external_energy_1),
        inspections,
    ))
    @test external_inspection.payload == (
        family = :ExternalDescriptorPayload,
        schema = UInt16(1),
    )

    solution = solve!(integrator)
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test solution.stats.accepted == 0
    @test solution.stats.null_attempts == 0
    @test solution.stats.constraint_rejections == 4
    @test last(solution).ownership == materialized.fixture.initial.ownership.labels

    unqualified_replay = init(
        materialized.problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    capability = inspect(unqualified_replay, Capabilities())
    @test capability.key.core.mechanisms.support_family ===
          :external_execution_protocol_v1
    @test capability.status === CorePotts.BackendSPI.Supported
    @test !capability.exact_replay
    @test capability.evidence.core.key === capability.key.core
    @test !capability.evidence.core.exact_replay
    replay_error = try
        checkpoint(unqualified_replay)
        nothing
    catch caught
        caught
    end
    @test replay_error isa CorePotts.BackendSPI.ProgramCapabilityError
    @test replay_error.operation === :checkpoint

    mismatched = external_spi_materialization(1; mismatched = true)
    error = try
        init(
            mismatched.problem,
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        nothing
    catch caught
        caught
    end
    @test error isa Potts.PottsValidationError
    @test error.stage === :descriptor_lowering
    @test only(error.diagnostics).kind === :descriptor_payload_type_mismatch
end

@testset "external descriptor growth stays data-shaped" begin
    one = external_spi_materialization(1)
    many = external_spi_materialization(6)
    one_integrator = init(
        one.problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    many_integrator = init(
        many.problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    one_report = getfield(getfield(one_integrator, :plan), :reports).descriptors
    many_report = getfield(getfield(many_integrator, :plan), :reports).descriptors
    # The registered Hamiltonian family grows by data; the one fixed proposal
    # constraint remains a second, count-invariant descriptor group.
    @test one_report.occurrences == 2
    @test many_report.occurrences == 7
    @test one_report.groups == many_report.groups == 2
    @test sum(one_report.instances) == one_report.occurrences
    @test sum(many_report.instances) == many_report.occurrences
    @test maximum(one_report.instances) == 1
    @test maximum(many_report.instances) == 6
    @test one_report.evaluator_nodes == many_report.evaluator_nodes
    @test one_report.group_splits == many_report.group_splits
    @test one_report.workspaces == 1
    @test many_report.workspaces == 6
end
