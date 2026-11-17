# Launch descriptions run through Exec (Problems.bind): the linear and Cartesian wrappers on
# the host executor agree bit for bit with the padded oracle loops (every `run_step!` of the
# suite checks it); here the check itself is shown to fail on a one-ulp difference, and the
# binding is shown to follow the spec (static ndrange, n = G.n, Cartesian wrapper).

@testsetup module LF_schedule_exec_binding
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
using Random: Xoshiro
include("../shared/export_all.jl")
end

@testitem "Exec binding: oracle comparison detects one ulp (negative control)" setup = [LF_schedule_exec_binding] tags = [:latticefields, :schedule] begin
@testset "Exec binding: oracle comparison detects one ulp (negative control)" begin
    s, sp = build(diffusion2((9, 7)))
    st = HostStore(s; init = (k, A) -> (A .= rand(Xoshiro(3), Float32, length(A))))
    ref = _snapshot(st)
    run_step!(s, sp, st, (0.1, 1.0, 1.0))                      # passes: Exec == oracle
    for l in sp.launches
        oracle_launch!(s, l, ref, (0.1, 1.0, 1.0), (0.0, 0.0))
    end
    Problems.swap!(ref, sp)
    u, r = current(st, s, "u"), current(ref, s, "u")
    @test _same(u, r)
    r[17] = nextfloat(r[17])
    @test !_same(u, r)                                          # one ulp is a difference
end
end

@testitem "Exec binding follows the launch description" setup = [LF_schedule_exec_binding] tags = [:latticefields, :schedule] begin
@testset "Exec binding follows the launch description" begin
    s, sp = build(diffusion2((9, 7)))
    l = only(sp.launches)
    st = HostStore(s)
    P = Problems.launch_parameters(l.kernel, (0.1, 1.0, 1.0))
        L = Problems.bind_program(HOST, s, l, Problems.launch_arrays(st, l), P, (0.0, 0.0))
    S, P2, G = L.params[2]
    @test L.params[3] == Int(G.n) == 63 && G.n isa Int32        # n is G.n, in the index type
    @test G.rt === (0.0f0, 0.0f0) && P2 === P
    L2 = Problems.retime(L, (1.5, 0.25))
    @test L2.params[2][3].rt === (1.5f0, 0.25f0) && L2.kernel === L.kernel
    @test (@allocated Problems.retime(L, (1.5f0, 0.25f0))()) == 0
    # a box stencil takes the Cartesian wrapper; its body receives `Int` coordinates
    pb = ProgramBuilder(Grid((6, 5)); periodic = (true, true), nparams = 1)
    u = field!(pb, "u")
    v = field!(pb, "v")
    kb = kernel(pb)
    store(kb, v, load(kb, u; offset = (1, 1)) * param(kb, 1))
    add!(pb, kb, "box")
    sx, spx = build(pb)
    lx = only(spx.launches)
    @test lx.kernel.strategy == :cartesian
    stx = HostStore(sx)
        Lx = Problems.bind_program(HOST, sx, lx, Problems.launch_arrays(stx, lx), (2.0f0,), (0.0, 0.0))
    @test Lx.params[3] == (6, 5)
    copyto!(current(stx, sx, "u"), Float32.(1:30))
    Lx()
    @test reshape(current(stx, sx, "v"), 6, 5)[1, 1] ==
          2 * reshape(Float32.(1:30), 6, 5)[2, 2]
end
end
