function _heterogeneous_scalar_aggregate_problem(names)
    plain_signal = Symbolics.variable(names.plain_signal)
    scaled_signal = Symbolics.variable(names.scaled_signal)
    plain_amount = Symbolics.variable(names.plain_amount)
    scaled_amount = Symbolics.variable(names.scaled_amount)
    gain = Symbolics.variable(names.gain)
    lattice = LatticeDomain(
        names.lattice;
        shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(),
        max_cells = 3,
    )
    kind = CellKind(names.kind; extinction = ForbidExtinction())
    medium = MediumKind(names.medium)
    declarations = scoped(sites(lattice), names.sites) do site
        consumers = scoped(cells(kind), names.cells) do cell
            plain = aggregate(plain_signal; over = site, by = cell)
            scaled = aggregate(gain * scaled_signal; over = site, by = cell)
            StatementSet((
                CellState(plain_amount; initial = 0.0),
                CellState(scaled_amount; initial = 0.0),
                Synchronous(names.publish_plain, Assign(plain_amount, plain)),
                Synchronous(names.publish_scaled, Assign(scaled_amount, scaled)),
            ))
        end
        StatementSet((
            FieldState(plain_signal; initial = 0.0),
            FieldState(scaled_signal; initial = 0.0),
            consumers...,
        ))
    end
    system = PottsSystem(
        name = names.system,
        statements = StatementSet((
            lattice, kind, medium, declarations...,
            ProposalConstraint(names.constraint, false),
            Protocol(Sweep(; temperature = 0.0); name = names.protocol),
        )),
        unknowns = (plain_signal, scaled_signal, plain_amount, scaled_amount),
        parameters = (gain,),
    )
    labels = Int32[1 2; 1 0]
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [kind, kind], medium,
        ),
        values = (
            plain_signal => reshape(Float32[1, 2, 3, 4], 2, 2),
            scaled_signal => reshape(Float32[5, 6, 7, 8], 2, 2),
        ),
    )
    problem = PottsProblem(
        system, initial, (0, 1); p = (gain => 2.0,), seed = 41,
    )
    return (;
        problem,
        plain_amount_name = names.plain_amount,
        scaled_amount_name = names.scaled_amount,
    )
end

const _AGGREGATE_ORDER_BASELINE_NAMES = (
    plain_signal = :alpha_signal,
    scaled_signal = :omega_signal,
    plain_amount = :alpha_amount,
    scaled_amount = :omega_amount,
    gain = :gain,
    lattice = :aggregate_space,
    kind = :aggregate_cell,
    medium = :aggregate_medium,
    sites = :aggregate_sites,
    cells = :aggregate_cells,
    publish_plain = :publish_plain,
    publish_scaled = :publish_scaled,
    system = :heterogeneous_aggregates,
    constraint = :fixed_ownership,
    protocol = :main,
)

const _AGGREGATE_ORDER_RENAMED_NAMES = (
    plain_signal = :omega_signal,
    scaled_signal = :alpha_signal,
    plain_amount = :omega_amount,
    scaled_amount = :alpha_amount,
    gain = :renamed_gain,
    lattice = :renamed_space,
    kind = :renamed_cell,
    medium = :renamed_medium,
    sites = :renamed_sites,
    cells = :renamed_cells,
    publish_plain = :renamed_plain,
    publish_scaled = :renamed_scaled,
    system = :renamed_heterogeneous_aggregates,
    constraint = :renamed_fixed_ownership,
    protocol = :renamed_main,
)

@testset "heterogeneous aggregate layout ignores author identity" begin
    baseline = _heterogeneous_scalar_aggregate_problem(
        _AGGREGATE_ORDER_BASELINE_NAMES,
    )
    renamed = _heterogeneous_scalar_aggregate_problem(
        _AGGREGATE_ORDER_RENAMED_NAMES,
    )
    baseline_integrator = init(
        baseline.problem, CheckerboardSweepCPM(); scalar_type = Float32,
    )
    renamed_integrator = init(
        renamed.problem, CheckerboardSweepCPM(); scalar_type = Float32,
    )

    @test typeof(baseline_integrator.plan.core_program.tracker_plan) ===
        typeof(renamed_integrator.plan.core_program.tracker_plan)
    @test typeof(baseline_integrator.plan.core_program) ===
        typeof(renamed_integrator.plan.core_program)
    baseline_instances = Base.method_instances(
        CorePotts.advance_mcs!, Tuple{typeof(baseline_integrator.runtime)},
        Base.get_world_counter(),
    )
    renamed_instances = Base.method_instances(
        CorePotts.advance_mcs!, Tuple{typeof(renamed_integrator.runtime)},
        Base.get_world_counter(),
    )
    @test length(baseline_instances) == length(renamed_instances) == 1
    @test only(baseline_instances) === only(renamed_instances)

    step!(baseline_integrator)
    step!(renamed_integrator)
    @test Array(baseline_integrator.u[baseline.plain_amount_name]) ==
        Array(renamed_integrator.u[renamed.plain_amount_name]) ==
        Float32[3, 3, 0]
    @test Array(baseline_integrator.u[baseline.scaled_amount_name]) ==
        Array(renamed_integrator.u[renamed.scaled_amount_name]) ==
        Float32[22, 14, 0]
end
