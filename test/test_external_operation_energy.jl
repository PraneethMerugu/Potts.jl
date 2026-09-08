include("fixtures/ExternalCompilerSPIFixture.jl")

@testset "external state operation has the independently computed Hamiltonian sign" begin
    @variables external_energy_gate
    @parameters external_energy_weight = 0.5
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    gate = FieldState(external_energy_gate; initial = 0.0)
    site = SiteBinding(:energy_site)
    proposal = ProposalContext(:energy_copy)
    read_value = ExternalCompilerSPIFixture.external_site_value
    source = PottsSystem(
        name = :external_energy_oracle,
        statements = StatementSet(
            (
                Lattice((3, 3); boundary = Closed(), relations = (proposal = VonNeumann(),)),
                cell,
                medium,
                gate,
                HamiltonianTerm(
                    :weighted_occupancy; domain = sites(:lattice), anchor = site,
                    expression = external_energy_weight *
                        read_value(external_energy_gate, Potts.anchor_value(site)) *
                        occupancy(cell, site),
                ),
                ProposalConstraint(
                    :isolated_extension,
                    proposal.is_extension &
                        (read_value(external_energy_gate, proposal.source_site) == 1) &
                        (read_value(external_energy_gate, proposal.target_site) == 2),
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = [external_energy_gate],
        parameters = [external_energy_weight],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 3, 3)
    source_site = CartesianIndex(2, 2)
    target_site = CartesianIndex(1, 2)
    labels[source_site] = 1
    gate_values = zeros(Float64, 3, 3)
    gate_values[source_site] = 1
    gate_values[target_site] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (external_energy_gate => gate_values,),
    )
    after_extension = copy(labels)
    after_extension[target_site] = 1

    # Full lattice sum, independent of operation transfer, evaluator, or delta
    # lowering. Only the marked extension passes the proposal-context reads.
    energy(ownership, weight) = weight * sum(gate_values[ownership .== 1])
    @test energy(after_extension, -0.5) - energy(labels, -0.5) == -1.0
    @test energy(after_extension, 0.5) - energy(labels, 0.5) == 1.0
    run(weight, seed) = solve(
        PottsProblem(
            scheduled, initial, (0, 1); p = (external_energy_weight => weight,), seed,
        ),
        SequentialCPM(); backend = CPUBackend(), scalar_type = Float64,
    )
    witness = nothing
    for seed in UInt64(1):UInt64(256)
        favorable = run(-0.5, seed)
        favorable.stats.accepted == 1 || continue
        unfavorable = run(0.5, seed)
        unfavorable.stats.energy_rejections > 0 || continue
        witness = (; favorable, unfavorable)
        break
    end
    @test witness !== nothing
    witness === nothing && error("no external Hamiltonian sign witness found")
    @test witness.favorable.retcode == SciMLBase.ReturnCode.Success
    @test witness.unfavorable.retcode == SciMLBase.ReturnCode.Success
    @test last(witness.favorable).ownership == after_extension
    @test last(witness.unfavorable).ownership == labels
    @test witness.unfavorable.stats.accepted == 0
end
