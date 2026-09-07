module CustomModel

using Potts
using LocalMath
using ModelingToolkitBase: @parameters
using SciMLBase
using Statistics: mean
using Symbolics

LocalMath.@localmath function scaled_neighbor_signal(
        signal::T, volume::T, gain::T,
    ) where {T}
    gain * signal + T(0.01) * volume
end

"""Run a compact model exercising Potts's composable custom-authoring paths."""
function run_custom_model(; seed::Integer = 0x6c21)
    @variables signal_value activity_value
    @parameters gain = 0.5

    cell = CellKind(:custom_cell; extinction = RetireAtZero())
    partner = CellKind(:custom_partner; extinction = RetireAtZero())
    transitioned = CellKind(:custom_transitioned; extinction = RetireAtZero())
    medium = MediumKind(:custom_medium)
    signal = FieldState(signal_value; name = :signal, initial = 1.0)
    activity = CellState(
        activity_value;
        name = :activity,
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    links = RelationshipState(
        :custom_links;
        endpoints = Undirected(cell, partner),
        payload = (weight = 1.0,),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )

    proposal = ProposalContext(:custom_proposal)
    edge = RelationshipBinding(:custom_edge, links)
    event_cell = CellBinding(:custom_event_cell)
    retune = LifecycleProcess(
        :retune_custom_link;
        domain = edges(links),
        expression = edge.weight > 0,
        effects = (Retune(
            links,
            edge;
            payload = (weight = edge.weight + 1,),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :transition_custom_cells;
        domain = cells(cell),
        anchor = event_cell,
        expression = true,
        effects = (Transition(
            event_cell,
            transitioned;
            state = (activity => Transform(activity_value + 1),),
            relationships = (links => RemoveIncompatible(),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )

    lattice = Lattice(
        (4, 3);
        boundary = Closed(),
        relations = (proposal = VonNeumann(), contact = VonNeumann()),
    )
    protocol = Protocol(Sweep(; temperature = 1.0); name = :main)
    gathered_signal_drive = ProposalDrive(
        :gathered_signal,
        scaled_neighbor_signal(
            mean(gather(signal, :contact; at = proposal.target_site)),
            mean(gather(cell_volume, :contact; at = proposal.target_site)),
            gain,
        ),
    )
    common_statements = (
        lattice,
        cell,
        partner,
        transitioned,
        medium,
        signal,
        activity,
        links,
        Volume(cell; target = 2.0, strength = 1.0),
        ProposalConstraint(:freeze_copy_attempts, false),
        retune,
        transition,
        Observation(:signal_snapshot, signal_value),
    )
    system = PottsSystem(
        name = :custom_model,
        statements = StatementSet((
            common_statements..., gathered_signal_drive, protocol,
        )),
        unknowns = [signal_value, activity_value],
        parameters = [gain],
    )

    labels = zeros(Int32, 4, 3)
    labels[1:2, 2] .= 1
    labels[3:4, 2] .= 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, partner], medium,
        ),
        values = (
            signal_value => reshape(Float64.(1:12), 4, 3),
            activity_value => [1.0, 2.0],
            links => [(1, 2)],
        ),
    )
    problem = PottsProblem(
        system,
        initial,
        (0, 2);
        p = (gain => 0.5,),
        seed,
    )

    solution = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
        observables = (:signal_snapshot,),
    )

    # Custom gathered operations are functionally admitted but do not yet carry
    # the exact-replay qualification required by the checkpoint boundary. The
    # same lifecycle model without that operation demonstrates continuation.
    replay_system = PottsSystem(
        name = :custom_model_replay,
        statements = StatementSet((common_statements..., protocol)),
        unknowns = [signal_value, activity_value],
    )
    replay_problem = PottsProblem(replay_system, initial, (0, 2); seed)
    uninterrupted = solve(
        replay_problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
        observables = (:signal_snapshot,),
    )
    integrator = init(
        replay_problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    step!(integrator)
    captured = checkpoint(integrator)
    resumed = solve!(init(
        replay_problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        checkpoint = captured,
        save_start = false,
    ))

    @assert solution.retcode == SciMLBase.ReturnCode.Success failure_report(solution)
    @assert !inspect(solution, Capabilities()).exact_replay
    @assert uninterrupted.retcode == SciMLBase.ReturnCode.Success
    @assert inspect(uninterrupted, Capabilities()).exact_replay
    @assert resumed.retcode == SciMLBase.ReturnCode.Success
    @assert last(uninterrupted).ownership == last(resumed).ownership
    @assert last(uninterrupted)[:activity] == last(resumed)[:activity]
    @assert last(uninterrupted)[:custom_links].active ==
            last(resumed)[:custom_links].active

    return (;
        system,
        problem,
        solution,
        replay_problem,
        uninterrupted,
        captured,
        resumed,
    )
end

end
