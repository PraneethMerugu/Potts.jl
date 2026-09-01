using Test
import LocalMath
const LMPL = LocalMath

@testset "positional Stage parameter layout" begin
    count = LMPL.Parameter(:count, Int32;
        bounds = LMPL._ClosedParameterBounds(Int32(0), Int32(8)))
    scale = LMPL.Parameter(:scale, Float32)
    layout = LMPL._stage_parameter_layout(LMPL.ParameterSchema(count, scale))
    renamed = LMPL._stage_parameter_layout(LMPL.ParameterSchema(
        LMPL.Parameter(:n, Int32;
            bounds = LMPL._ClosedParameterBounds(Int32(0), Int32(8))),
        LMPL.Parameter(:factor, Float32)))

    @test typeof(layout) === typeof(renamed)
    @test @inferred(LMPL._canonical_submission(
        layout, (scale = 2.5f0, count = Int32(3)))) === (Int32(3), 2.5f0)

    names_error = try
        LMPL._canonical_submission(layout, (scale = 2.5f0, other = Int32(3)))
        nothing
    catch error
        error
    end
    @test names_error isa LMPL.LocalMathValidationError
    @test names_error.contract === :submission_slot_names

    arity_error = try
        LMPL._canonical_submission(layout, (count = Int32(3),))
        nothing
    catch error
        error
    end
    @test arity_error isa LMPL.LocalMathValidationError
    @test arity_error.contract === :submission_slot_names

    type_error = try
        LMPL._canonical_submission(layout, (count = Int64(3), scale = 2.5f0))
        nothing
    catch error
        error
    end
    @test type_error isa LMPL.LocalMathValidationError
    @test type_error.contract === :submission_value_type

    bounds_error = try
        LMPL._canonical_submission(layout, (count = Int32(9), scale = 2.5f0))
        nothing
    catch error
        error
    end
    @test bounds_error isa LMPL.LocalMathValidationError
    @test bounds_error.contract === :submission_value_bounds
end
