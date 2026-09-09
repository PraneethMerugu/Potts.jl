using StaticArrays

function _trigonometric_system(variable, expression; initial = 0.2, parameters = ())
    @variables trig_result
    return PottsSystem(
        name = :trigonometric_values,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()),
                CellKind(:cell; extinction = RetireAtZero()), MediumKind(:medium),
                ModelState(variable; initial), ModelState(trig_result; initial = 0.0),
                Synchronous(:evaluate_angle, Assign(trig_result, expression)),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (variable, trig_result), parameters = parameters,
    )
end

@testset "sine and cosine are dimensionless real scalar operations" begin
    @variables angle
    for operation in (sin, cos)
        analysis = Potts._analyze_completed_system(complete(_trigonometric_system(angle, operation(angle))))
        root = only(filter(root -> root.role === :effect_1_value, analysis.graph.roots))
        @test analysis.facts.shape[root.node] == ()
        @test analysis.facts.result_type[root.node] === Real
        @test analysis.facts.units[root.node] == :dimensionless
        @test analysis.graph.nodes[root.node].operation === (operation === sin ? :sine : :cosine)
    end
end

@testset "trigonometric arguments reject physical dimensions" begin
    @variables angle
    @parameters distance = 1.0u"m"
    for operation in (sin, cos)
        error = try
            complete(
                _trigonometric_system(angle, operation(distance); parameters = (distance,));
                reference_units = ReferenceUnits(length = 1.0u"m"),
            )
            nothing
        catch caught
            caught
        end
        @test error isa Potts.PottsValidationError
        if error isa Potts.PottsValidationError
            @test any(
                diagnostic -> diagnostic.kind === :illegal_operation_units &&
                    occursin("dimensionless", diagnostic.actual), error.diagnostics
            )
        end
    end
end

@testset "scalar trigonometry does not admit complex or array operands" begin
    @variables complex_angle::ComplexF64 vector_angle[1:2]
    for operation in (sin, cos)
        @test_throws ArgumentError Symbolics.term(operation, vector_angle; type = Real)
        expression = Symbolics.term(operation, complex_angle; type = Real)
        error = try
            complete(_trigonometric_system(complex_angle, expression; initial = 0.2 + 0.1im))
            nothing
        catch caught
            caught
        end
        @test error isa Potts.PottsValidationError
        if error isa Potts.PottsValidationError
            @test any(
                diagnostic -> diagnostic.kind === :illegal_operation_use &&
                    occursin("operand", diagnostic.actual), error.diagnostics
            )
        end
    end
end
