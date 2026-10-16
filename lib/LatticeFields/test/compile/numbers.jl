# Number types in emitted bodies (P5 role model): the conversion primitives, the Float64
# check of backends without doubles (any Float64-based value type, Duals included), lane
# classes, and casts through `lanecast`.
using ForwardDiff: Dual
using LatticeFields.Compile: lanecast, valtype, primal, withvaltype, promote_dual, lanetype,
                             check_types
using LatticeFields.IR: IRError, F16, F32, F64

@testset "number primitives" begin
    d = Dual{Nothing}(1.5, 2.0, 3.0)
    @test lanecast(Float32, 1.5) === 1.5f0
    @test lanecast(Float32, d) === Dual{Nothing}(1.5f0, 2.0f0, 3.0f0)          # tag and partials kept
    @test lanecast(Float64, Dual{Nothing}(1.5f0, 2.0f0)) === Dual{Nothing}(1.5, 2.0)
    @test valtype(typeof(d)) == Float64 && valtype(Float32) == Float32 && valtype(BigFloat) == BigFloat
    @test primal(d) === 1.5 && primal(2.0f0) === 2.0f0
    @test withvaltype(typeof(d), Float32) == Dual{Nothing, Float32, 2} && withvaltype(Float64, Float32) == Float32
    @test promote_dual(Float32, Float64) == Float32                              # plain p: no promotion
    @test promote_dual(Float32, typeof(d)) == Dual{Nothing, Float32, 2}
    @test promote_dual(Float64, BigFloat) == Float64
    @test lanetype(F64, BigFloat) == Float64 && lanetype(F32, Float64) == Float32     # raw IR: fixed
    @test lanetype(F64, BigFloat, :state) == BigFloat && lanetype(F32, Float64, :state) == Float64 &&
          lanetype(F16, Float64, :state) == Float16                               # problems: value classes
end

@testset "backends without Float64: any Float64-based value type is refused, naming the field" begin
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
        @test err isa IRError && occursin("u", err.msg) && occursin("Float64", err.msg)
    end
end

@testset "casts go through lanecast; :state lanes hold the value type" begin
    s = semantic(program(diffusion2()))
    k = s.kernels[1]
    @test compile_kernel(s, k).T == Float32                                       # T = nothing: Float32
    fixed = compile_kernel(s, k, CompileOptions(; T = Float64))                   # F32 lane, Float64 compute
    @test occursin("lanecast", string(fixed.body))
    state = compile_kernel(s, k, CompileOptions(; T = Float64, lanes = :state))   # the lane holds Float64
    @test !occursin("lanecast", string(state.body))
end
