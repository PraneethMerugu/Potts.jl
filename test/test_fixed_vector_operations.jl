using StaticArrays

function _fixed_vector_operation_system(variable, expression; parameters = ())
    return PottsSystem(
        name = :vector_expression,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()),
                CellKind(:cell; extinction = RetireAtZero()),
                MediumKind(:medium),
                ModelState(variable; initial = SVector(1.0, 0.0)),
                Synchronous(:update, Assign(variable, expression)),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (variable,), parameters = parameters,
    )
end

@testset "fixed-vector expressions have logical shape and scalar element reads" begin
    @variables direction[1:2]
    for expression in (
            SVector(-direction[2], direction[1]),
            SVector(direction[1] + 1, direction[2] - 2),
            SVector(3.0f0, 4.0f0),
        )
        completed = complete(_fixed_vector_operation_system(direction, expression))
        analysis = Potts._analyze_completed_system(completed)
        root = only(filter(root -> root.role === :effect_1_value, analysis.graph.roots))
        @test analysis.facts.shape[root.node] == (2,)
        @test analysis.facts.result_type[root.node] <: StaticArrays.StaticVector{2}
        @test analysis.facts.units[root.node] == :dimensionless
        for node in analysis.graph.nodes
            node.operation === :fixed_index || continue
            @test analysis.facts.shape[node.identity] == ()
            @test analysis.facts.result_type[node.identity] <: Number
        end
    end
end

@testset "fixed-vector indexing rejects runtime selection during analysis" begin
    @variables direction[1:2]
    @parameters component::Int = 1
    error = try
        complete(
            _fixed_vector_operation_system(
                direction, SVector(direction[component], direction[1]);
                parameters = (component,),
            )
        )
        nothing
    catch caught
        caught
    end
    @test error isa Potts.PottsValidationError
    if error isa Potts.PottsValidationError
        @test any(error.diagnostics) do diagnostic
            diagnostic.kind === :invalid_fixed_index &&
                occursin("literal integer", diagnostic.actual)
        end
    end
end

@testset "fixed-vector construction does not discard incompatible element units" begin
    @variables direction[1:2]
    @parameters distance = 1.0u"m"
    error = try
        complete(
            _fixed_vector_operation_system(
                direction, SVector(direction[1], distance); parameters = (distance,),
            ); reference_units = ReferenceUnits(length = 1.0u"m"),
        )
        nothing
    catch caught
        caught
    end
    @test error isa Potts.PottsValidationError
    if error isa Potts.PottsValidationError
        @test any(error.diagnostics) do diagnostic
            diagnostic.kind === :illegal_operation_units &&
                occursin("fixed-vector elements", diagnostic.actual)
        end
    end
end

@testset "fixed-vector literal bounds are checked before execution" begin
    @variables direction[1:2]
    for index in (0, 3)
        # Public term construction can express an index without eagerly indexing
        # the symbolic array; the authoring compiler must reject it itself.
        component = Symbolics.term(getindex, direction, index)
        error = try
            complete(
                _fixed_vector_operation_system(
                    direction, SVector(component, direction[1]),
                )
            )
            nothing
        catch caught
            caught
        end
        @test error isa Potts.PottsValidationError
        if error isa Potts.PottsValidationError
            @test any(error.diagnostics) do diagnostic
                diagnostic.kind === :invalid_fixed_index &&
                    occursin("outside fixed-vector shape", diagnostic.actual)
            end
        end
    end
end
