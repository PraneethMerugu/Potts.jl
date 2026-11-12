# The group layer on a builder program (F2-06): `advance!` of a `GroupRuntime` equals the
# integrator's step, `ends_in = :slot1` brings an odd count back to slot 1 with the same
# values, and the runtime's host parts allocate nothing (AllocCheck, and `@allocated` of a
# warm `advance!`).

@testsetup module LF_problems_owned_group
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.Solvers: V
include("../host_runner.jl")
include("../fixtures.jl")
include("../shared/problems_owned.jl")
using LatticeFields.Problems: Problems as LFP, FieldProblem, ExplicitEuler, LatticeIndex, FieldSlot
using AllocCheck: check_allocs
using CommonSolve: init, step!
using SciMLBase: ReturnCode
include("../shared/export_all.jl")
end

@testitem "GroupRuntime: advance!, ends_in = :slot1, no allocation" setup = [LF_problems_owned_group] tags = [:latticefields, :problems] begin
@testset "GroupRuntime: advance!, ends_in = :slot1, no allocation" begin
    dims = (12, 10)
    u0 = rand(Xoshiro(5), Float32, prod(dims))
    ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)], parameters = [:D => 1])
    prob = FieldProblem(euler2(dims), Float64.(u0), (0.0, 0.1), [0.5]; state = ["u"], kind = :rate, index = ix)
    alg = ExplicitEuler(; dt = 0.05, substeps = 3)
    a, b = init(prob, alg), init(prob, alg)
    ra = only(a.runtimes)
    @test ra.ends_in === :parity && ra.n == 3
    # a runtime bound to `b`'s store, ending in slot 1
    rb = LFP.bind_group(prob.group, alg, b.store, copy(prob.p); n = 3, dt = 0.05, c = 0.0, ends_in = :slot1,
        backend = prob.backend, options = prob.options, V = Float64)
    @test LFP.advance!(ra, (0.0, 0)) == ReturnCode.Success
    @test LFP.advance!(rb, (0.0, 0)) == ReturnCode.Success
    @test a.store.cur[1] == 2 && b.store.cur[1] == 1              # odd count: slot 2, or back in slot 1
    @test Array(a.store.flat[2]) == Array(b.store.flat[1])          # the same values
    # the host parts of a step allocate nothing
    @test isempty(check_allocs(LFP._swap!, (typeof(ra.store.cur), typeof(ra.swaps))))
    @test isempty(check_allocs(LFP._slot1!, (typeof(rb.copies), typeof(rb.store.cur), typeof(rb.swaps), Int)))
    warm(rt) = (LFP.advance!(rt, (0.0, 0)); @allocated LFP.advance!(rt, (0.0, 0)))
    @test warm(ra) == 0 && warm(rb) == 0
    @test_throws ArgumentError LFP.bind_group(prob.group, alg, b.store, copy(prob.p); n = 3, dt = 0.05, c = 0.0,
        ends_in = :last, backend = prob.backend, options = prob.options, V = Float64)
end
end
