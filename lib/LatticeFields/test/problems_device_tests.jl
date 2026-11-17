# Generated FV kernels on a device (Metal or ROCm), Float32: the x1 device axes (fused vs
# split on the device, device vs host executor, one-ulp negative control), and the owned and
# ODE problems on device arrays against the host. Included by runtests.jl when
# LATTICEFIELDS_GPU is set (device_backend.jl defines DEV).

@testsetup module LF_problems_device
using Test, LatticeFields
# imports an earlier file made in the old single Main
using ForwardDiff: Dual
using ForwardDiff: ForwardDiff
include("shared/lf_runner.jl")
include("exec_helpers.jl")
include("host_runner.jl")
include("fixtures.jl")
include("device_backend.jl")
include("shared/problems_owned.jl")
include("shared/problems_x1_exact.jl")
using LatticeFields.Problems: FieldStore, FieldProblem, ExplicitEuler, ode_problem,
                              LatticeIndex, FieldSlot
using CommonSolve: solve, init, step!

devopts() = CompileOptions(; T = Float32, float64_ok = Exec.default_float(DEV) === Float64)

"""
One step of program `s`/`sp` from inputs `X` (one per field `u1…uK`) on `backend`.
"""
function step_on(backend, s, sp, X, P)
    st = FieldStore(backend, s)
    foreach(k -> copyto!(Problems.current(st, s, "u$k"), X[k]), eachindex(X))
    Problems.run_step!(backend, s, sp, st, P)
    KA.synchronize(backend)
    return reduce(vcat, [reinterpret(UInt32, Array(Problems.current(st, s, "u$k")))
                         for k in eachindex(X)])
end
include("shared/export_all.jl")
end

@testitem "x1 device (gpu): K=K T=T length(dims)D" setup = [LF_problems_device] tags = [:latticefields, :problems, :gpu_only] begin
using .LF_problems_device: instances
@testset "x1 device ($gpu): K=$K T=$T $(length(dims))D" for (dims, K, T) in (
    ((64, 48), 4, 3), ((64, 48), 8, 0), ((16, 12, 10), 4, 3))
    X, P = inputs(dims, K), speciesP(K, T)
    s = semantic(program(species(dims, K, T; kernels = :each)))
    fused = plan(s; options = devopts())
    split = plan(s; options = devopts(), fuse = false)
    @test length(fused.launches) < length(split.launches) == K
    ref = step_on(DEV, s, fused, X, P)
    @test step_on(DEV, s, split, X, P) == ref                       # fusion on the device
    host = step_on(KA.CPU(), s, fused, X, P)
    d = count(host .!= ref)
    @info "x1 device vs host executor ($gpu, $(length(dims))D K=$K T=$T): $d differing words of $(length(ref))"
    @test d == 0                                                     # same body, same bits
    Xp = deepcopy(X)
    Xp[1][length(X[1]) ÷ 2 + 7] = nextfloat(Xp[1][length(X[1]) ÷ 2 + 7])
    @test count(step_on(DEV, s, fused, Xp, P) .!= ref) > 0          # negative control
end
end

@testitem "owned and ODE problems on gpu" setup = [LF_problems_device] tags = [:latticefields, :problems, :gpu_only] begin
using .LF_problems_device: instances
@testset "owned and ODE problems on $gpu" begin
    dims = (40, 30)
    u0 = rand(Xoshiro(5), Float32, prod(dims))
    ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)])
    args = (euler2(dims), u0, (0.0, 0.2), [0.2])        # eltype(u0) = Float32 decides
    dev = FieldProblem(args...; state = ["u"], kind = :rate, index = ix, backend = DEV,
        options = devopts())
    host = FieldProblem(args...; state = ["u"], kind = :rate, index = ix)
    sd = solve(dev, ExplicitEuler(; substeps = 1); dt = 0.05, saveat = 0.1)
    sh = solve(host, ExplicitEuler(; substeps = 1); dt = 0.05, saveat = 0.1)
    @test sd.t == sh.t && all(i -> sd[:u, i] == sh[:u, i], eachindex(sd.t))   # bit for bit
    @test sd[:u][end] != sd[:u][1]
    integ, hi = init(dev, ExplicitEuler(; substeps = 1); dt = 0.05),
    init(host, ExplicitEuler(; substeps = 1); dt = 0.05)
    step!(integ)
    step!(hi)
    KA.synchronize(DEV)
    @test Array(integ[:u]) == hi[:u]                                # device state, indexed by symbol
    b = @allocated (step!(integ); KA.synchronize(DEV))
    @info "owned warm step on $gpu: $b host bytes (KA 0.9 launch cost; the host executor is 0)"
    # the ODE right side on device arrays equals the host one
    ixr = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)])
    od = ode_problem(
        euler2(dims; rate = true), u0, (0.0, 1.0), [0.5]; state = ["u"],
        rates = Dict("u" => "∂u"), index = ixr, backend = DEV, options = devopts())
    oh = ode_problem(
        euler2(dims; rate = true), u0, (0.0, 1.0), [0.5]; state = ["u"],
        rates = Dict("u" => "∂u"), index = ixr)
    dud, duh = similar(od.u0), similar(oh.u0)
    od.f(dud, od.u0, od.p, 0.0)
    oh.f(duh, oh.u0, oh.p, 0.0)
    KA.synchronize(DEV)
    @test Array(dud) == duh
end
end

@testitem "Dual{Float32} parameters on gpu (P5)" setup = [LF_problems_device] tags = [:latticefields, :problems, :gpu_only] begin
using .LF_problems_device: instances
@testset "Dual{Float32} parameters on $gpu (P5)" begin
    dims = (16, 12)
    u0 = rand(Xoshiro(7), Float32, prod(dims))
    ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)], parameters = [:D => 1])
    mk(backend) = FieldProblem(euler2(dims), u0, (0.0, 0.2), [0.05]; state = ["u"], kind = :rate,
        index = ix, backend)
    alg = ExplicitEuler(; substeps = 1)
    Jdev(prob) = D -> sum(abs2, Array(solve(SciMLBase.remake(prob; p = [D]), alg; dt = 0.05).u[end]))
    dd, dh = ForwardDiff.derivative(Jdev(mk(DEV)), 0.05), ForwardDiff.derivative(Jdev(mk(KA.CPU())), 0.05)
    @test dd isa Float32 && isapprox(dd, dh; rtol = 1e-5) && dd != 0
    # Float64 values are refused on a backend without Float64 hardware (Metal); where the
    # hardware has it (ROCm) a Float64 problem runs on the device (capability, P5 C2-1)
        Exec.supports(DEV, Float64) || @test_throws ["ArgumentError", "no Float64 compute", "use T = Float32"] FieldProblem(
            euler2(dims), Float64.(u0),
        (0.0, 0.2), [0.05]; state = ["u"], kind = :rate, index = ix, backend = DEV)
    if Exec.supports(DEV, Float64)
        p64(backend) = FieldProblem(euler2(dims), Float64.(u0), (0.0, 0.2), [0.05]; state = ["u"],
            kind = :rate, index = ix, backend)
        ud, uh = Array(solve(p64(DEV), alg; dt = 0.05).u[end]), solve(p64(KA.CPU()), alg; dt = 0.05).u[end]
        @test eltype(ud) == Float64 && isapprox(ud, uh; rtol = 1e-13)
    end
end
end

@testitem "Dual{Float64} into a Float32 ODE on gpu: the message names the fix (review round 5)" setup = [LF_problems_device] tags = [:latticefields, :problems, :gpu_only] begin
using .LF_problems_device: instances
@testset "Dual{Float64} into a Float32 ODE on $gpu: the message names the fix (review round 5)" begin
    if !Exec.supports(DEV, Float64)
        dims = (8, 6)
        od = ode_problem(euler2(dims; rate = true), zeros(Float32, prod(dims)), (0.0, 1.0), [0.5];
            state = ["u"], rates = Dict("u" => "∂u"), backend = DEV, options = devopts())
        U = KA.allocate(DEV, Dual{Nothing, Float64, 1}, prod(dims))
        err = try
            od.f(similar(U), U, [0.5], 0.0)
        catch e
            e
        end
        @test err isa ArgumentError && occursin("Float32 parameters", err.msg)
    end
end
end
