include("phase14_wang_fixture.jl")

if get(ENV, "POTTS_WANG_RUNTIME_DEFINITIONS_ONLY", "false") != "true"
@testset "Phase 14 canonical Wang plan reaches MCS 500" begin
    side = parse(
        Int, get(
            ENV,
            "POTTS_WANG_RUNTIME_SIDE",
            "32"))
    fixture = _wang_runtime_fixture(side)
    coupled = fixture.coupled
    phase_names = Tuple(
        entry.name
        for entry in coupled.plan.entries
        if entry isa CorePotts.CoupledPhase)
    @test phase_names == (
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
    realized_processes = Tuple(
        CorePotts.invocation_process(
            only(entry.invocations))
        for entry in coupled.plan.entries
        if entry isa CorePotts.CoupledPhase)
    @test realized_processes[2] isa
        CorePotts.CentroidHistorySampleExecution
    @test realized_processes[3] isa
        CorePotts.HistoryDisplacementDirectionExecution
    @test realized_processes[6] isa
        CorePotts.ElasticLinkRetuneExecution
    @test realized_processes[7] isa
        CorePotts.NeighborPolarityAlignmentExecution
    @test realized_processes[8] isa
        CorePotts.HillVectorForceExecution
    @test realized_processes[9] isa
        CorePotts.RelationshipCleanupExecution

    CorePotts.SciMLBase.step!(
        coupled, fixture.target_mcs)
    @test coupled.mcs == 500
    @test fixture.field.time == 500.0f0
    @test fixture.history.latest_sample_mcs ==
          500
    @test fixture.exchange_runtime.initialized[1] ==
          UInt8(1)
    @test fixture.exchange_runtime.publication_epoch[1] ==
          UInt64(379)
    @test all(isfinite,
        CorePotts.scientific_execution(
            fixture.compiled).core.properties.rac)
    @test all(==(1_094_400.0f0),
        CorePotts.scientific_execution(
            fixture.compiled).core.properties.rac_time)
    @test coupled.observations.completed_mcs ==
          500
    @test count(
        record ->
            record.observation ===
            :wang_cell_records,
        coupled.observations.records) ==
          379
    @test count(
        record ->
            record.observation ===
            :wang_geometry,
        coupled.observations.records) ==
          2
    @test fixture.table.workspace.row_count[1] ==
          UInt32(2)
    @test fixture.relationships.count[1] ==
          UInt32(length(fixture.relationships.edges))
    @test fixture.relationships.count[1] <=
          UInt32(16)
end
end
