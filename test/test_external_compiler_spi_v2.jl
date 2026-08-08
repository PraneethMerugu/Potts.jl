include("fixtures/ExternalCompilerSPIFixture.jl")
include("fixtures/ExternalSurfaceOperationFixture.jl")
using .ExternalCompilerSPIFixture

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
    cell = CellKind(:external_surface_cell; extinction = RetireAtZero())
    medium = MediumKind(:external_surface_medium)
    anchor = CellBinding(:external_surface_anchor)
    source = PottsSystem(
        name = :external_surface_relations,
        statements = StatementSet((
            Lattice(
                (5, 5);
                boundary = Periodic(),
                relations = (
                    proposal = VonNeumann(),
                    surface = VonNeumann(),
                    surface_alt = Moore(),
                ),
            ),
            cell,
            medium,
            HamiltonianTerm(
                :external_surface_four;
                domain = cells(cell),
                anchor,
                expression =
                    ExternalSurfaceOperationFixture.external_cell_surface(
                        anchor_value(anchor)
                    ),
            ),
            HamiltonianTerm(
                :external_surface_eight;
                domain = cells(cell),
                anchor,
                expression =
                    ExternalSurfaceOperationFixture.external_cell_surface_alt(
                        anchor_value(anchor)
                    ),
            ),
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 5, 5)
    labels[3, 3] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
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
    # immutable PottsToolkit/CorePotts boundary authority.
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

    solution = solve!(integrator)
    @test solution.retcode == SciMLBase.ReturnCode.Success
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
          :lower_g5h_external_site_energy
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
    @test capability.key.core.mechanisms.qualification_family ===
          :external_execution_protocol_v1
    @test capability.maturity === CorePotts.BackendSPI.Functional
    @test capability.evidence.core isa
          CorePotts.BackendSPI.CapabilityEvidenceIdentity
    @test capability.evidence.core.suite ===
          :sequential_external_cpu_protocol_v1
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
    @test error isa PottsToolkit.PottsValidationError
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
    @test one_report.kernel_families == many_report.kernel_families
    @test one_report.workspaces == 1
    @test many_report.workspaces == 6
end
