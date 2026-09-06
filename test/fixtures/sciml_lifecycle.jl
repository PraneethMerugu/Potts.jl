const LIFECYCLE_SII = SymbolicIndexingInterface

@parameters begin
    lifecycle_target = 4.0
    lifecycle_strength = 2.0
    lifecycle_temperature = 3.0
end
@variables lifecycle_marker

function _lifecycle_fixture(
        name::Symbol;
        marker_value = 1.25,
        attempts = AttemptsPerSite(1),
    )
    cell = CellKind(:lifecycle_cell; extinction = RetireAtZero())
    medium = MediumKind(:lifecycle_medium)
    source = PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice(
                (6, 6);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            SiteState(
                lifecycle_marker;
                name = :lifecycle_marker,
                owner = cell,
                initial = 0.25,
            ),
            Volume(
                cell;
                target = lifecycle_target,
                strength = lifecycle_strength,
            ),
            Observation(:lifecycle_marker_snapshot, lifecycle_marker),
            Protocol(
                Sweep(; temperature = lifecycle_temperature, attempts);
                name = :lifecycle_protocol,
            ),
        )),
        unknowns = [lifecycle_marker],
        parameters = [
            lifecycle_target,
            lifecycle_strength,
            lifecycle_temperature,
        ],
        initial_conditions = Dict(lifecycle_marker => 0.25),
    )
    labels = zeros(Int, 6, 6)
    labels[2:3, 2:3] .= 1
    labels[4:5, 4:5] .= 2
    marker = fill(marker_value, 6, 6)
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [cell, cell],
            medium,
        ),
        values = (lifecycle_marker => marker,),
    )
    return (
        source,
        system = mtkcompile(source),
        initial,
        cell,
        medium,
        labels,
        marker,
    )
end

function _lifecycle_problem(
        fixture;
        tspan = (0, 6),
        seed = 0x6a5b_0002,
        replica = 1,
        repeat = 1,
    )
    return PottsProblem(
        fixture.system,
        fixture.initial,
        tspan;
        p = (
            lifecycle_target => 5.0,
            lifecycle_strength => 1.5,
            lifecycle_temperature => 2.5,
        ),
        seed,
        replica,
        repeat,
    )
end

function _lifecycle_same_state(left, right)
    return left.mcs == right.mcs &&
           left.ownership == right.ownership &&
           left.cell_kinds == right.cell_kinds &&
           left.cell_generations == right.cell_generations &&
           left.volumes == right.volumes &&
           left[:lifecycle_marker] == right[:lifecycle_marker] &&
           left[:lifecycle_marker_snapshot] ==
           right[:lifecycle_marker_snapshot]
end
