isdefined(@__MODULE__, :_scheduled_draw_problem) ||
    include("fixtures/scheduled_process_draws.jl")

function _operational_identity_problem(
        prefix::Union{Nothing, Symbol};
        contribution = (gain, signal) -> gain * signal,
    )
    author_name(name) = prefix === nothing ? name : Symbol(prefix, :_, name)
    gain = Symbolics.variable(author_name(:gain))
    signal = Symbolics.variable(author_name(:signal))
    amount = Symbolics.variable(author_name(:amount))
    lattice = LatticeDomain(
        author_name(:space);
        shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(),
        max_cells = 3,
    )
    kind = CellKind(
        author_name(:cell); extinction = ForbidExtinction(),
    )
    medium = MediumKind(author_name(:medium))
    declarations = scoped(
            sites(lattice), author_name(:locations),
        ) do site
        consumers = scoped(
                cells(kind), author_name(:owners),
            ) do cell
            quantity = aggregate(
                contribution(gain, signal); over = site, by = cell,
            )
            StatementSet((
                CellState(amount; initial = 0.0),
                Synchronous(
                    author_name(:measure), Assign(amount, quantity),
                ),
            ))
        end
        StatementSet((FieldState(signal; initial = 0.0), consumers...))
    end
    system = PottsSystem(
        name = author_name(:maintained_signal),
        statements = StatementSet((
            lattice, kind, medium, declarations...,
            ProposalConstraint(author_name(:fixed_ownership), false),
            Protocol(
                Sweep(; temperature = 0.0); name = author_name(:main),
            ),
        )),
        unknowns = (signal, amount),
        parameters = (gain,),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(
            Int32[1 2; 1 0]; cells = [kind, kind], medium,
        ),
        values = (signal => reshape(Float32[1, 2, 3, 4], 2, 2),),
    )
    problem = PottsProblem(
        system, initial, (0, 1); p = (gain => 1.0,), seed = 17,
    )
    return (; problem, amount, gain)
end

function _aggregate_contribution_node(ir)
    fact = first(filter(!isnothing, ir.facts.site_aggregate))
    return ir.graph.nodes[Int(fact.contribution)]
end

@testset "operational scalar products ignore author spelling" begin
    baseline = _operational_identity_problem(nothing)
    renamed = _operational_identity_problem(:renamed)
    baseline_ir = Potts._analyze_completed_system(baseline.problem.system)
    renamed_ir = Potts._analyze_completed_system(renamed.problem.system)
    baseline_product = _aggregate_contribution_node(baseline_ir)
    renamed_product = _aggregate_contribution_node(renamed_ir)
    baseline_cache = Potts._OperationalCanonicalizationCache(
        length(baseline_ir.graph.nodes),
    )
    renamed_cache = Potts._OperationalCanonicalizationCache(
        length(renamed_ir.graph.nodes),
    )

    @test baseline_product.operation === renamed_product.operation === :multiply
    @test Potts._scalar_product_is_commutatively_canonicalizable(
        baseline_ir.graph, baseline_ir, baseline_product, baseline_cache,
    )
    @test Potts._scalar_product_is_commutatively_canonicalizable(
        renamed_ir.graph, renamed_ir, renamed_product, renamed_cache,
    )

    baseline_order = Potts._operational_operand_order(
        baseline_ir.graph, baseline_ir, baseline_product, baseline_cache,
    )
    renamed_order = Potts._operational_operand_order(
        renamed_ir.graph, renamed_ir, renamed_product, renamed_cache,
    )
    operand_roles(ir, operands) = map(
        operand -> ir.graph.nodes[Int(operand)].payload_kind,
        operands,
    )
    @test operand_roles(baseline_ir, baseline_order) ==
        operand_roles(renamed_ir, renamed_order)
    @test Potts._operational_expression_shape_key(
        baseline_ir.graph, baseline_ir, baseline_product.identity,
        baseline_cache,
    ) == Potts._operational_expression_shape_key(
        renamed_ir.graph, renamed_ir, renamed_product.identity,
        renamed_cache,
    )

    baseline_integrator = init(
        baseline.problem, CheckerboardSweepCPM(); scalar_type = Float32,
    )
    renamed_integrator = init(
        renamed.problem, CheckerboardSweepCPM(); scalar_type = Float32,
    )
    @test typeof(baseline_integrator.plan.core_program) ===
        typeof(renamed_integrator.plan.core_program)
    @test typeof(baseline_integrator.plan.core_program.tracker_plan) ===
        typeof(renamed_integrator.plan.core_program.tracker_plan)
    @test typeof(baseline.problem.p) === typeof(renamed.problem.p)
    @test typeof(baseline.problem) === typeof(renamed.problem)
    @test baseline.problem.p[:gain] == renamed.problem.p[:renamed_gain] == 1.0
    @test baseline.problem.p.named == (gain = 1.0,)
    @test renamed.problem.p.named == (renamed_gain = 1.0,)
    remade = remake(baseline.problem; p = (gain = 2.5,))
    @test typeof(remade.p) === typeof(baseline.problem.p)
    @test remade.p[:gain] == 2.5
    remade_buffer = SymbolicIndexingInterface.remake_buffer(
        baseline.problem.system,
        baseline.problem.p,
        (baseline.gain,),
        (3.5,),
    )
    @test typeof(remade_buffer) === typeof(baseline.problem.p)
    @test remade_buffer[:gain] == 3.5
    parameter_error = try
        remake(baseline.problem; p = (gain = Inf,))
        nothing
    catch caught
        caught
    end
    @test parameter_error isa ArgumentError
    @test occursin("gain", sprint(showerror, parameter_error))
    @test scheduled_system_fingerprint(baseline.problem.system) !=
        scheduled_system_fingerprint(renamed.problem.system)
    @test Potts._execution_plan_fingerprint(baseline_integrator.plan) !=
        Potts._execution_plan_fingerprint(renamed_integrator.plan)
    step!(baseline_integrator)
    step!(renamed_integrator)
    @test Array(baseline_integrator.u[:amount]) == Float32[3, 3, 0]
    @test Array(renamed_integrator.u[:renamed_amount]) == Float32[3, 3, 0]
    saved = checkpoint(baseline_integrator)
    restored = init(
        remake(baseline.problem; p = (gain = 9.0,)),
        CheckerboardSweepCPM(); scalar_type = Float32, checkpoint = saved,
    )
    restored_parameters = last(restored.parameter_history).second
    @test propertynames(restored_parameters) == (:gain,)
    @test restored_parameters.named == (gain = 1.0f0,)
    @test restored_parameters[:gain] == 1.0f0
    @test_throws ArgumentError init(
        renamed.problem,
        CheckerboardSweepCPM(); scalar_type = Float32, checkpoint = saved,
    )
end

@testset "observable and positional expressions retain operand order" begin
    derived = _operational_identity_problem(
        :division; contribution = (gain, signal) -> gain / signal,
    )
    derived_ir = Potts._analyze_completed_system(derived.problem.system)
    division = only(filter(
        node -> node.operation === :divide,
        derived_ir.graph.nodes,
    ))
    derived_cache = Potts._OperationalCanonicalizationCache(
        length(derived_ir.graph.nodes),
    )
    @test !Potts._scalar_product_is_commutatively_canonicalizable(
        derived_ir.graph, derived_ir, division, derived_cache,
    )
    @test Potts._operational_operand_order(
        derived_ir.graph, derived_ir, division, derived_cache,
    ) === division.operands

    powered = _operational_identity_problem(
        :power; contribution = (gain, signal) -> signal^2,
    )
    powered_ir = Potts._analyze_completed_system(powered.problem.system)
    power = only(filter(
        node -> node.operation === :power,
        powered_ir.graph.nodes,
    ))
    powered_cache = Potts._OperationalCanonicalizationCache(
        length(powered_ir.graph.nodes),
    )
    @test Potts._operand_order_is_observable(
        powered_ir.graph, power.identity, powered_cache,
    )

    draw_problem = _scheduled_draw_problem()
    draw_ir = Potts._analyze_completed_system(draw_problem.system)
    draws = filter(node -> node.operation === :draw, draw_ir.graph.nodes)
    draw_cache = Potts._OperationalCanonicalizationCache(
        length(draw_ir.graph.nodes),
    )
    @test !isempty(draws)
    @test all(
        node -> Potts._operand_order_is_observable(
            draw_ir.graph, node.identity, draw_cache,
        ),
        draws,
    )
end

@testset "operational canonicalization memoizes shared normalized nodes" begin
    model = _operational_identity_problem(nothing)
    ir = Potts._analyze_completed_system(model.problem.system)
    product = _aggregate_contribution_node(ir)
    builder = Potts._TermGraphBuilder(
        ir.graph.nodes,
        Dict{String, Int32}(),
        Potts.PottsDiagnostic[],
    )
    root = product.identity
    for _ in 1:40
        root = Potts._push_term_node!(
            builder,
            product.operation,
            product.schema_version,
            Int32[root, root],
            product.payload_kind,
            product.payload,
            product.transfer,
            product.callable,
            product.record,
            product.source;
            intern = false,
        )
        push!(ir.facts.shape, ())
        push!(
            ir.facts.result_type,
            ir.facts.result_type[Int(product.identity)],
        )
    end

    # Forty duplicated levels have over one trillion paths but only forty
    # additional nodes. Both traversals must therefore follow DAG identity.
    shape_cache = Potts._OperationalCanonicalizationCache(
        length(ir.graph.nodes),
    )
    @test Potts._operational_expression_shape_key(
        ir.graph, ir, root, shape_cache,
    ) isa String
    observability_cache = Potts._OperationalCanonicalizationCache(
        length(ir.graph.nodes),
    )
    @test !Potts._operand_order_is_observable(
        ir.graph, root, observability_cache,
    )
end
