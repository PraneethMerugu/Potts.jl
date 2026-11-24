# Number types in emitted bodies (P5 role model): the conversion primitives, the Float64
# check of backends without doubles (any Float64-based value type, Duals included), lane
# classes, and casts through `lanecast`.

@testsetup module LF_compile_numbers
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.IR: Ex
using LatticeFields: Exec
include("../host_runner.jl")
include("../fixtures.jl")
using ForwardDiff: Dual
using LatticeFields.Compile: lanecast, value_type, primal, withvaltype, promote_dual,
    lanetype,
    check_types
using LatticeFields.IR: IRError, F16, F32, F64
include("../shared/export_all.jl")
end

@testitem "number primitives" setup = [LF_compile_numbers] tags = [
    :latticefields,
    :compile,
] begin
    using .LF_compile_numbers: value_type
    @testset "number primitives" begin
        d = Dual{Nothing}(1.5, 2.0, 3.0)
        @test lanecast(Float32, 1.5) === 1.5f0
        # tag and partials kept
        @test lanecast(Float32, d) === Dual{Nothing}(1.5f0, 2.0f0, 3.0f0)
        @test lanecast(Float64, Dual{Nothing}(1.5f0, 2.0f0)) === Dual{Nothing}(1.5, 2.0)
        @test value_type(typeof(d)) == Float64 && value_type(Float32) == Float32 &&
            value_type(BigFloat) == BigFloat
        @test primal(d) === 1.5 && primal(2.0f0) === 2.0f0
        @test withvaltype(typeof(d), Float32) == Dual{Nothing, Float32, 2} &&
            withvaltype(Float64, Float32) == Float32
        # plain p: no promotion
        @test promote_dual(Float32, Float64) == Float32
        @test promote_dual(Float32, typeof(d)) == Dual{Nothing, Float32, 2}
        @test promote_dual(Float64, BigFloat) == Float64
        # raw IR: fixed
        @test lanetype(F64, Float32) == Float64 && lanetype(F32, Float64) == Float32
        @test lanetype(F64, Float32, :state) == Float32 &&
            lanetype(F32, Float64, :state) == Float64 &&
            # problems: value classes
            lanetype(F16, Float64, :state) == Float16
    end
end

@testitem "backends without Float64: any Float64-based value type is refused, naming the \
    field" setup = [LF_compile_numbers] tags = [
    :latticefields, :compile,
] begin
    using .LF_compile_numbers: value_type
    @testset "backends without Float64: any Float64-based value type is refused, naming \
        the field" begin
        s = semantic(program(diffusion2()))
        k = s.kernels[1]
        nof64(T) = CompileOptions(; T, float64_ok = false)
        @test check_types(s, k, nof64(Float32)) === nothing
        @test check_types(s, k, nof64(Dual{Nothing, Float32, 1})) === nothing
        for T in (Float64, Dual{Nothing, Float64, 1})
            err = try
                check_types(s, k, nof64(T))
            catch e
                e
            end
            @test err isa IRError && occursin("Float64", err.msg)
        end
    end
end

@testitem "casts go through lanecast; :state lanes hold the value type" setup = [
    LF_compile_numbers,
] tags = [
    :latticefields, :compile,
] begin
    using .LF_compile_numbers: value_type
    @testset "casts go through lanecast; :state lanes hold the value type" begin
        s = semantic(program(diffusion2()))
        k = s.kernels[1]
        # T = nothing: Float32
        @test compile_kernel(s, k).T == Float32
        # F32 lane, Float64 compute
        fixed = compile_kernel(s, k, CompileOptions(; T = Float64))
        @test occursin("lanecast", string(fixed.body))
        # the lane holds Float64
        state = compile_kernel(s, k, CompileOptions(; T = Float64, lanes = :state))
        @test !occursin("lanecast", string(state.body))
    end
end

# A declared storage (`fixed`) holds its own type under the state lanes, a
# compute type wider than the storage loads and stores through `lanecast` (`S`), and a
# declared Float64 registers the kernel in Exec's D-157 registry. Base f5641ce1: no `fixed`,
# no `S`, no registry (every test errors).
@testitem "fixed lanes, a compute type wider than the storage, the Float64 registry" setup =
    [LF_compile_numbers] tags = [
    :latticefields, :compile,
] begin
    using .LF_compile_numbers: value_type
    @testset "fixed lanes, a compute type wider than the storage, the Float64 \
        registry" begin
        @test lanetype(F64, Float32, :state, true) == Float64 &&
            lanetype(F32, Float64, :state, true) == Float32
        # control: the value class
        @test lanetype(F64, Float32, :state, false) == Float32
        E = Dual{Nothing, Float64, 1}
        @test LatticeFields.Problems._eltype(F32, E, true) == Dual{Nothing, Float32, 1} &&
            LatticeFields.Problems._eltype(F32, E, false) == E
        s = semantic(program(diffusion2()))
        k = s.kernels[1]
        # storage Float32 (the state lane holds S = Float32), compute in Float64: casts both
        # ways
        wide = compile_kernel(
            s, k,
            CompileOptions(; T = Float64, lanes = :state, S = Float32)
        )
        @test occursin("lanecast(Float64", string(wide.body)) &&
            occursin("lanecast(Float32", string(wide.body))
        @test !occursin(
            "lanecast",
            string(compile_kernel(s, k, CompileOptions(; T = Float32, lanes = :state)).body)
        )
        # the registry: a declared Float64 compile registers its body; an undeclared one
        # does not
        Ex = LatticeFields.Exec
        saved = copy(Ex.FLOAT64_KERNELS)
        empty!(Ex.FLOAT64_KERNELS)
        ck = compile_kernel(
            s, k,
            CompileOptions(; T = Float64, lanes = :state, S = Float32, declared = true)
        )
        sig = string(typeof(LatticeFields.Compile.body_function(ck)))
        @test Ex.float64_registered("Tuple{kernel, " * sig * ", Int64}")
        empty!(Ex.FLOAT64_KERNELS)
        compile_kernel(s, k, CompileOptions(; T = Float64, lanes = :state, S = Float32))
        @test isempty(Ex.FLOAT64_KERNELS) &&
            !Ex.float64_registered("Tuple{kernel, " * sig * ", Int64}")
        # no Float64: none
        compile_kernel(s, k, CompileOptions(; T = Float32, lanes = :state, declared = true))
        @test isempty(Ex.FLOAT64_KERNELS)
        union!(Ex.FLOAT64_KERNELS, saved)
    end
end
