using DynamicQuantities, StaticArrays, Symbolics, SymbolicIndexingInterface

module ExternalScalingName
    import CorePotts
    import Potts
    import Symbolics
    function multiply end
    Symbolics.@register_symbolic multiply(left, right)::Real
    struct ScalarMultiply <: CorePotts.CompilerSPI.AbstractContextualOperation end
    Potts.operation_transfer(::typeof(multiply), ::Int) = Potts.OperationTransfer(
        :external_scalar_multiply; arity = 2, result_rule = :promote_numeric,
        unit_rule = :dimensionless, operand_rule = :numeric,
        footprint_rule = Potts.InheritFootprintRule(), owner = :ExternalScalingName,
    )
    CorePotts.CompilerSPI.operation_callable(::Val{:external_scalar_multiply}, version::VersionNumber) =
        version == v"1.0.0" ? ScalarMultiply() : throw(ArgumentError("unsupported external scalar multiplication version"))
    CorePotts.CompilerSPI.operation_context_supported(
        ::ScalarMultiply,
        ::Type{CorePotts.CompilerSPI.AbstractSiteStageEvaluationContext}
    ) = true
    (::ScalarMultiply)(arguments::Tuple, context) = *(arguments...)
    function multiply_identity end
    Symbolics.@register_symbolic multiply_identity(left, right)::Real
    Potts.operation_transfer(::typeof(multiply_identity), ::Int) = Potts.OperationTransfer(
        :multiply; arity = 2, result_rule = :promote_numeric,
        unit_rule = :dimensionless, operand_rule = :numeric,
        footprint_rule = Potts.InheritFootprintRule(), owner = :ExternalScalingName,
    )
end

function _fixed_scaling_problem(
        logical_shape; unit = 1.0, target_initial = nothing,
        right_initial = nothing, assigned_value = nothing,
        array_product = false, reference_units = nothing
    )
    @parameters gain = 2.0
    if logical_shape == (2, 2)
        @variables value[1:2, 1:2] left[1:2, 1:2] right[1:2, 1:2]
        initial = map(value -> value * unit, SMatrix{2, 2}(1.0, -2.0, 3.0, 4.0))
    elseif logical_shape == (2,)
        @variables value[1:2] left[1:2] right[1:2]
        initial = map(value -> value * unit, SVector(1.0, -2.0))
    else
        @variables value left right
        initial = 3.0 * unit
    end
    target_initial === nothing && (target_initial = initial isa StaticArrays.StaticArray ? map(zero, initial) : zero(initial))
    right_initial === nothing && (right_initial = target_initial)
    assigned_value === nothing && (assigned_value = array_product ? value * value : gain * value)
    lattice = LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed())
    kind = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :fixed_scaling,
        statements = StatementSet(
            (
                lattice, kind, medium,
                ModelState(value; initial),
                ModelState(left; initial = target_initial),
                ModelState(right; initial = right_initial),
                Synchronous(
                    :scale,
                    Assign(left, assigned_value),
                    Assign(right, value * gain)
                ),
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (value, left, right), parameters = (gain,),
    )
    initial_state = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [kind], medium))
    system = reference_units === nothing ? source : complete(source; reference_units)
    return (; problem = PottsProblem(system, initial_state, (0, 2); seed = 17), value, gain, initial)
end

@testset "scalar multiplication preserves declared scalar vector and tensor shape" begin
    for logical_shape in ((), (2,), (2, 2)), algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _fixed_scaling_problem(logical_shape)
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        initial = integrator.u[:value]
        step!(integrator)
        @test integrator.u[:left] == 2.0f0 * initial
        @test integrator.u[:right] == initial * 2.0f0
        @test typeof(integrator.u[:left]) === typeof(initial)
        @test typeof(integrator.u[:right]) === typeof(initial)
        setp(integrator, model.gain)(integrator, -3.0)
        step!(integrator)
        @test integrator.u[:left] == -3.0f0 * initial
        @test integrator.u[:right] == initial * -3.0f0
        @test integrator.u[:value] == initial
    end
end

@testset "fixed-array scaling preserves physical reference units" begin
    references = ReferenceUnits(length = 2.0u"m", time = 1.0u"s")
    for logical_shape in ((2,), (2, 2)), algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _fixed_scaling_problem(logical_shape; unit = 2.0u"m", reference_units = references)
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        expected = logical_shape == (2,) ? SVector(2.0f0, -4.0f0) :
            SMatrix{2, 2}(2.0f0, -4.0f0, 6.0f0, 8.0f0)
        step!(integrator)
        @test integrator.u[:left] == expected
        @test integrator.u[:right] == expected
    end
    for logical_shape in ((), (2,), (2, 2)), algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        wrong = logical_shape == () ? 0.0u"s" : logical_shape == (2,) ?
            map(value -> value * u"s", zero(SVector{2, Float64})) :
            map(value -> value * u"s", zero(SMatrix{2, 2, Float64}))
        @test_throws Potts.PottsValidationError init(
            _fixed_scaling_problem(
                logical_shape;
                unit = 2.0u"m", target_initial = wrong, reference_units = references
            ).problem,
            algorithm; scalar_type = Float32
        )
        # The first effect is valid; the second target alone has incompatible units.
        @test_throws Potts.PottsValidationError init(
            _fixed_scaling_problem(
                logical_shape;
                unit = 2.0u"m", right_initial = wrong, reference_units = references
            ).problem,
            algorithm; scalar_type = Float32
        )
    end
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM()), literal in (0, 6.0u"m")
        model = _fixed_scaling_problem(
            (); unit = 2.0u"m", assigned_value = literal,
            target_initial = 0.0u"cm", reference_units = references
        )
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        step!(integrator)
        @test integrator.u[:left] == (iszero(literal) ? 0.0f0 : 3.0f0)
    end
    @test_throws Potts.PottsValidationError init(
        _fixed_scaling_problem(
            ();
            unit = 2.0u"m", assigned_value = 1, reference_units = references
        ).problem;
        scalar_type = Float32
    )
end

@testset "scalar-array admission does not reinterpret matrix multiplication" begin
    @test_throws Potts.PottsValidationError _fixed_scaling_problem((2, 2); array_product = true)
    @test_throws ArgumentError init(
        _fixed_scaling_problem(
            (2, 2);
            target_initial = zero(SVector{2, Float64})
        ).problem; scalar_type = Float32
    )
end

@testset "an external operation named multiply retains its own scalar contract" begin
    @parameters gain = 2.0
    @variables signal[1:2] result
    function source(operation, operand)
        expression = Symbolics.wrap(Symbolics.term(operation, gain, operand))
        return PottsSystem(
            name = :external_scaling, statements = StatementSet(
                (
                    LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed()),
                    ModelState(signal; initial = SVector(1.0, 2.0)),
                    ModelState(result; initial = 0.0),
                    Synchronous(:scale, Assign(result, expression)),
                )
            ), unknowns = (signal, result), parameters = (gain,)
        )
    end
    for operation in (ExternalScalingName.multiply, ExternalScalingName.multiply_identity)
        @test complete(source(operation, 3.0)) isa PottsSystem
        @test_throws r"operand types.*violate rule.*numeric" complete(source(operation, signal))
    end
end
