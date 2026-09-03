import LocalMath

LocalMath.@localmath function _localmath_symbolic_geometric_mean(
        x::T, y::T,
    ) where {T}
    sqrt(x * y)
end

LocalMath.@localmath function _localmath_nested_square(x)
    x * x
end

LocalMath.@localmath function _localmath_nested_penalty(x, y)
    _localmath_nested_square(x - y) + _localmath_symbolic_geometric_mean(x, y)
end

LocalMath.@localmath function _localmath_symbolic_branch(x)
    if x > zero(x)
        x
    else
        -x
    end
end

@testset "transparent LocalMath functions trace through Symbolics" begin
    @variables localmath_x localmath_y
    traced = _localmath_symbolic_geometric_mean(localmath_x, localmath_y)
    @test traced isa Symbolics.Num
    compiled = Symbolics.build_function(
        traced, localmath_x, localmath_y; expression = Val(false))
    @test compiled(4.0, 9.0) == 6.0
    @test _localmath_symbolic_geometric_mean(4.0, 9.0) == 6.0

    nested = _localmath_nested_penalty(localmath_x, localmath_y)
    nested_compiled = Symbolics.build_function(
        nested, localmath_x, localmath_y; expression = Val(false))
    @test nested_compiled(4.0, 9.0) == 31.0
    @test _localmath_nested_penalty(4.0, 9.0) == 31.0

    # Transparent definitions are ordinary Julia: unsupported data-dependent
    # scalar control flow rejects where the authored function is invoked with
    # symbolic values instead of becoming a hidden runtime interpreter.
    branch_error = try
        _localmath_symbolic_branch(localmath_x)
        nothing
    catch error
        error
    end
    @test branch_error isa TypeError
    @test occursin("non-boolean", sprint(showerror, branch_error))
end

@testset "bounded LocalMath terms lower through Potts semantics" begin
    @variables bounded_signal
    cell = CellKind(:bounded_cell; extinction = RetireAtZero())
    medium = MediumKind(:bounded_medium)
    signal = FieldState(
        bounded_signal; name = :bounded_signal, initial = 1.0)
    site = SiteBinding(:bounded_site)
    neighbor_sum = LocalMath.bounded_fold(
        identity,
        +,
        0.0,
        (sum, count) -> sum;
        domain = LocalMath.Where(isfinite),
        oninvalid = LocalMath.RejectInvalid(),
        onempty = LocalMath.FillEmpty(0.0),
        order = LocalMath.CanonicalLeftFold(),
    )
    source = PottsSystem(
        name = :bounded_term_system,
        statements = StatementSet((
            Lattice((3, 3); relations = (
                contact = VonNeumann(), proposal = VonNeumann())),
            cell,
            medium,
            signal,
            HamiltonianTerm(
                :bounded_signal_energy;
                domain = sites(:lattice),
                anchor = site,
                expression = neighbor_sum(bounded_values(
                    signal, :contact, anchor_value(site))),
            ),
            Protocol(Sweep(); name = :bounded_protocol),
        )),
        unknowns = [bounded_signal],
    )
    scheduled = mtkcompile(source)
    @test is_scheduled(scheduled)

    ownership = reshape(Int32[1, 1, 0, 1, 0, 0, 0, 0, 0], 3, 3)
    initial = PottsInitialState(
        ownership = LabelledCells(ownership; cells = [cell], medium),
        values = (bounded_signal => ones(3, 3),),
    )
    solution = solve(
        PottsProblem(scheduled, initial, (0, 1); seed = 0x61),
        SequentialCPM(); backend = CPUBackend(), scalar_type = Float64,
    )
    @test solution.stats.candidate_attempts == 9

    checkerboard_solution = solve(
        PottsProblem(scheduled, initial, (0, 1); seed = 0x61),
        CheckerboardSweepCPM(); backend = CPUBackend(), scalar_type = Float64,
    )
    @test checkerboard_solution.stats.candidate_attempts == 9
    @test checkerboard_solution.stats.candidate_attempts ==
          checkerboard_solution.stats.accepted +
          checkerboard_solution.stats.null_attempts +
          checkerboard_solution.stats.rejected
    @test size(last(checkerboard_solution).ownership) == size(ownership)

    @test_throws ArgumentError bounded_values(signal, 17, anchor_value(site))

    missing_relation_source = PottsSystem(
        name = :bounded_term_missing_relation,
        statements = StatementSet((
            Lattice((3, 3); relations = (proposal = VonNeumann(),)),
            cell,
            medium,
            signal,
            HamiltonianTerm(
                :missing_bounded_relation;
                domain = sites(:lattice),
                anchor = site,
                expression = neighbor_sum(bounded_values(
                    signal, :missing_contact, anchor_value(site))),
            ),
            Protocol(Sweep(); name = :bounded_protocol),
        )),
        unknowns = [bounded_signal],
    )
    relation_error = try
        mtkcompile(missing_relation_source)
        nothing
    catch error
        error
    end
    @test relation_error isa Potts.PottsValidationError
    @test occursin("missing_contact", sprint(showerror, relation_error))
end

@testset "PottsSystem contract" begin
    @variables t x(t)
    @parameters k

    source_equations = [x ~ k]
    source_unknowns = [x]
    source_parameters = [k]
    source_initial = Dict(x => 1.0)
    site_anchor = SiteBinding(:site_anchor)
    @named child = PottsSystem(
        statements = StatementSet((
            CellKind(:cell; extinction = RetireAtZero()),
            HamiltonianTerm(
                :energy;
                domain = sites(:lattice),
                anchor = site_anchor,
                expression = k * x,
            ),
        )),
        equations = source_equations,
        unknowns = source_unknowns,
        parameters = source_parameters,
        independent_variables = [t],
        inputs = [k],
        outputs = [x],
        initial_conditions = source_initial,
    )

    empty!(source_equations)
    empty!(source_unknowns)
    empty!(source_parameters)
    empty!(source_initial)
    @test equations(child) == [x ~ k]
    @test length(unknowns(child)) == 1 && isequal(only(unknowns(child)), x)
    @test length(parameters(child)) == 1 && isequal(only(parameters(child)), k)
    @test initial_conditions(child)[x] == 1.0
    @test isequal(child.x, ModelingToolkitBase.renamespace(child, x))
    @test !iscomplete(child)

    @named parent = PottsSystem()
    tree = compose(parent, [child])
    @test isequal(
        tree.child.x,
        ModelingToolkitBase.renamespace(
            parent, ModelingToolkitBase.renamespace(child, x)
        ),
    )
    @test nameof(tree) == :parent
    @test propertynames(tree) == [:child]
    qualified_tree = complete(tree)
    energy_record = only(filter(
        record -> record.identity.local_id == StatementID(:energy),
        inspect(qualified_tree, Statements()),
    ))
    @test any(isequal(
        ModelingToolkitBase.renamespace(:child, x)
    ), energy_record.reads)
    @test any(isequal(
        ModelingToolkitBase.renamespace(:child, k)
    ), energy_record.reads)
    @test !any(isequal(x), energy_record.reads)
    @test !any(isequal(k), energy_record.reads)
    @test !any(isequal(x), inspect(qualified_tree, Variables()))

    @test ModelingToolkitBase.equations(tree) == [
        ModelingToolkitBase.renamespace(:child, x) ~
        ModelingToolkitBase.renamespace(:child, k),
    ]
    @test isequal(ModelingToolkitBase.independent_variables(tree), [t])
    @test isequal(ModelingToolkitBase.inputs(tree), [
        ModelingToolkitBase.renamespace(:child, k),
    ])
    @test isequal(ModelingToolkitBase.outputs(tree), [
        ModelingToolkitBase.renamespace(:child, x),
    ])
    @test ModelingToolkitBase.initial_conditions(tree) == Dict(
        ModelingToolkitBase.renamespace(:child, x) => 1.0
    )

    flattened = flatten(tree)
    @test isempty(ModelingToolkitBase.get_systems(flattened))
    @test ModelingToolkitBase.equations(flattened) ==
          ModelingToolkitBase.equations(tree)
    @test isequal(
        ModelingToolkitBase.unknowns(flattened),
        ModelingToolkitBase.unknowns(tree),
    )
    @test isequal(
        ModelingToolkitBase.parameters(flattened),
        ModelingToolkitBase.parameters(tree),
    )
    @test isequal(
        ModelingToolkitBase.inputs(flattened),
        ModelingToolkitBase.inputs(tree),
    )
    @test isequal(
        ModelingToolkitBase.outputs(flattened),
        ModelingToolkitBase.outputs(tree),
    )
    @test ModelingToolkitBase.initial_conditions(flattened) ==
          ModelingToolkitBase.initial_conditions(tree)
    @test Symbol(statement_id(only(filter(
        statement -> statement isa HamiltonianTerm,
        statements(flattened),
    )))) == :child₊energy

    renamed = Symbolics.rename(child, :renamed)
    @test nameof(renamed) == :renamed
    @test nameof(child) == :child

    substituted = substitute(child, Dict(k => 2.0))
    @test equations(substituted) == [x ~ 2.0]
    @test isempty(ModelingToolkitBase.get_ps(substituted))
    @test occursin("2.0", sprint(show, statements(substituted)[2]))

    @named addition = PottsSystem(
        statements = StatementSet(MediumKind(:medium)),
        unknowns = [x],
        independent_variables = [t],
    )
    merged = extend(addition, child)
    @test length(statements(merged)) == 3
    @test length(unknowns(merged)) == 1 && isequal(only(unknowns(merged)), x)
    @test_throws ArgumentError extend(child, child)

    completed = complete(child)
    @test iscomplete(completed)
    @test complete(completed) === completed
    @test_throws ArgumentError compose(completed, PottsSystem[])
    @test_throws ArgumentError Symbolics.rename(completed, :other)
    @test_throws ArgumentError substitute(completed, Dict(k => 3.0))
end
