module Wortel2021Serial

using Potts
using SciMLBase
using Symbolics
using ModelingToolkitBase: @parameters

"""
    run_wortel_2021(; mcs = 2, seed = 0x3302)

Build and execute the serial CPU integration witness for the activity-coupled
cell-migration mechanisms described by Wortel et al. (2021). This is a product
and API witness, not a reproduction of the paper's full calibrated campaign.
"""
function run_wortel_2021(; mcs::Integer=2, seed::Integer=0x3302)
    mcs >= 1 || throw(ArgumentError("mcs must be positive"))

    @variables activity_value activity_history
    @parameters begin
        target_volume = 6.0
        volume_strength = 1.0
        maximum_activity = 5.0
        activity_strength = 4.0
        temperature = 8.0
    end

    endothelial = CellKind(:endothelial; extinction=RetireAtZero())
    extracellular = MediumKind(:extracellular)
    activity = SiteState(
        activity_value;
        name=:activity,
        owner=endothelial,
        initial=0.0,
        lifecycle=ClearOnOwnershipChange(),
    )
    memory = HistoryState(
        activity_history;
        name=:activity_history,
        initial=0.0,
        of=activity_value,
        depth=2,
        cadence=EveryMCS(),
    )
    copy = ProposalContext(:copy)
    surface_anchor = CellBinding(:surface_anchor)

    source = PottsSystem(
        name=:wortel_2021,
        statements=(@statements begin
            Lattice(
                (8, 8);
                boundary=Periodic(),
                relations=(
                    proposal=Moore(),
                    contact=Moore(),
                    surface=Moore(),
                    activity_neighborhood=Moore(),
                    connectivity=Moore(),
                    connectivity_background=VonNeumann(),
                ),
            )
            endothelial
            extracellular
            Volume(endothelial; target=target_volume, strength=volume_strength)
            ContactEnergy([
                (extracellular ↔ endothelial) => 6.0,
                (endothelial ↔ endothelial) => 2.0,
            ])
            HamiltonianTerm(
                :surface_constraint;
                domain=cells(endothelial),
                anchor=surface_anchor,
                expression=0.05 * (cell_surface(surface_anchor) - 8.0)^2,
            )
            activity
            memory
            ActEnergy(
                endothelial,
                activity_value;
                maximum=maximum_activity,
                strength=activity_strength,
                reduction=:activity_neighborhood,
            )
            AcceptedCopy(
                :activate,
                Assign(activity_value, maximum_activity);
                when=copy.is_extension,
            )
            Synchronous(
                :decay,
                Assign(activity_value, max(activity_value - 1, 0));
                phase=AfterMCS(),
            )
            LocalConnectivity(endothelial)
            Protocol(Sweep(; temperature); name=:main)
            Observation(:occupied_sites, occupancy(endothelial, :lattice))
        end),
        unknowns=[activity_value, activity_history],
        parameters=[
            target_volume,
            volume_strength,
            maximum_activity,
            activity_strength,
            temperature,
        ],
    )
    scheduled = mtkcompile(source)

    labels = zeros(Int32, 8, 8)
    labels[2:3, 2:3] .= 1
    labels[6:7, 6:7] .= 2
    initial = PottsInitialState(
        ownership=LabelledCells(
            labels;
            cells=[endothelial, endothelial],
            medium=extracellular,
        ),
        values=(activity_value => zeros(Float32, 8, 8),),
    )
    problem = PottsProblem(scheduled, initial, (0, Int(mcs)); seed)
    solution = solve(
        problem,
        SequentialCPM();
        backend=CPUBackend(),
        scalar_type=Float32,
        save_everystep=true,
        observables=(:occupied_sites,),
    )

    final = last(solution)
    @assert solution.retcode == SciMLBase.ReturnCode.Success
    @assert all(isfinite, final[:activity])
    @assert 0.0f0 <= minimum(final[:activity])
    @assert maximum(final[:activity]) <= 5.0f0
    @assert last(final[:activity_history]) == final[:activity]
    @assert final[:occupied_sites] == count(!iszero, final.ownership)

    return (; source, scheduled, problem, solution, activity_value)
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = run_wortel_2021()
    println(
        "Wortel serial witness passed: mcs=",
        last(result.solution).mcs,
        ", occupied_sites=",
        last(result.solution)[:occupied_sites],
    )
end

end
