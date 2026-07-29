using Distributed
using SciMLBase

function distributed_ensemble_problem()
    volume = QuadraticVolumeHamiltonian(number_type = Float32)
    owners = fill(MediumOwner(1), 5, 5)
    fill!(view(owners, 2:4, 2:3), CellOwner(1))
    logical = LogicalPottsState(owners, CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = (MediumID(1),), property_schema = required_properties(volume))
    property_values(logical, :target_volume)[1] = 6
    property_values(logical, :volume_strength)[1] = 1
    domain = CorePotts.CartesianDomain((5, 5))
    proposal = first_shell_relation(ProposalRole(), Val(2))
    surface = first_shell_relation(SurfaceRole(), Val(2))
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    model = CorePotts.PottsModel(proposal, tracker;
        components = ScientificComponentSet(energies = (volume,)))
    return CorePotts.PottsProblem(model, logical, domain, (0, 2); seed = 0x539)
end

@testset "distributed execution distributed CPU ensemble" begin
    if BACKEND_GROUP == "CPU"
        project = dirname(Base.active_project())
        worker = only(addprocs(1; exeflags = "--project=$(project)"))
        try
            remotecall_wait(Core.eval, worker, Main, :(using CorePotts, SciMLBase))
            problem = distributed_ensemble_problem()
            ensemble = EnsembleProblem(problem; seed = 0xabc)
            serial = solve(ensemble, SequentialCPM(), EnsembleSerial(); trajectories = 3)
            distributed = solve(
                ensemble, SequentialCPM(), EnsembleDistributed(); trajectories = 3)
            expected = [ensemble_seed(EnsembleSeedDerivationV1(), UInt64(0xabc), index)
                        for index in 1:3]
            @test [solution.provenance.seed for solution in serial.u] == expected
            @test [solution.provenance.seed for solution in distributed.u] == expected
            serial_states = [lattice_storage(logical_snapshot(
                solution.u[end].state.potts)) for solution in serial.u]
            distributed_states = [lattice_storage(logical_snapshot(
                solution.u[end].state.potts)) for solution in distributed.u]
            @test distributed_states == serial_states
        finally
            rmprocs(worker)
        end
    end
end
