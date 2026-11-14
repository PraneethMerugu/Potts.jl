# The interval coefficient evaluator: enclosure under sampling, tightness on monotone terms,
# the declared-interval refusal, allocation-free warm calls and a negative control.

@testsetup module LF_compile_interval
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields: Compile
using LatticeFields.IR: Grid
using LatticeFields: IR
using LatticeFields.IR: ProgramBuilder
using Random: Xoshiro
using LatticeFields.IR: add!
using LatticeFields.IR: field!
using LatticeFields.IR: kernel
using LatticeFields.IR: load
using LatticeFields.IR: param
using LatticeFields.IR: program
using LatticeFields.Compile: semantic
using LatticeFields.IR: store
using LatticeFields.Compile: interval_function, interval_expr
using LatticeFields.IR: IRError

"""
A kernel with a reaction coefficient `p1·u² − p2/(1 + u) + exp(−p1)·|u − p3|`.
"""
function reaction_prog()
    pb = ProgramBuilder(Grid((4, 4)); nparams = 3)
    u = field!(pb, "u")
    r = field!(pb, "r"; role = :aux)
    kb = kernel(pb)
    x = load(kb, u)
    p1, p2, p3 = param(kb, 1), param(kb, 2), param(kb, 3)
    store(kb, r, p1 * x^2 - p2 / (1 + x) + exp(-p1) * abs(x - p3))
    add!(pb, kb, "rate")
    return semantic(program(pb))
end
coef(p, u) = p[1] * u^2 - p[2] / (1 + u) + exp(-p[1]) * abs(u - p[3])
include("../shared/export_all.jl")
end

@testitem "interval evaluator" setup = [LF_compile_interval] tags = [:latticefields, :compile] begin
@testset "interval evaluator" begin
    s = reaction_prog()
    k = s.kernels[1]
    root = k.stores[1].value
    lo, hi = (0.5, 0.1, -1.0), (2.0, 3.0, 1.0)
    f = interval_function(s, k, [root]; bounds = Dict("u" => (-0.5, 4.0)))
    (enc,) = f(lo, hi)
    rng = Xoshiro(9)
    samples = [coef(lo .+ rand(rng, 3) .* (hi .- lo), -0.5 + 4.5rand(rng))
               for _ in 1:20_000]
    @test all(v -> enc[1] <= v <= enc[2], samples)
    @test (@allocated f(lo, hi)) == 0
    # tightness: a monotone product of parameters is enclosed within a few ulps
    pb = ProgramBuilder(Grid((2, 2)); nparams = 2)
    w = field!(pb, "w")
    kb = kernel(pb)
    store(kb, w, param(kb, 1) * param(kb, 2))
    add!(pb, kb, "prod")
    s2 = semantic(program(pb))
    (e2,) = interval_function(s2, s2.kernels[1], [s2.kernels[1].stores[1].value])(
        (
            2.0, 3.0), (5.0, 7.0))
    @test e2[1] <= 6.0 && e2[2] >= 35.0 && e2[2] - e2[1] <= 29 * (1 + 1e-14)
    # a state read without a declared interval is a build error that names the field
    err = try
        interval_expr(s, k, [root])
    catch e
        e
    end
    @test err isa IRError && occursin("`u`", err.msg)
    # negative control: on the tight product, the evaluator's enclosure shrunk by 1% of its
    # width at each end fails the same sampling check (corners included)
    ps = [(2.0 + 3rand(rng)) * (3.0 + 4rand(rng)) for _ in 1:2_000]
    append!(ps, [a * b for a in (2.0, 5.0) for b in (3.0, 7.0)])
    @test all(v -> e2[1] <= v <= e2[2], ps)
    w = e2[2] - e2[1]
    @test !all(v -> e2[1] + 0.01w <= v <= e2[2] - 0.01w, ps)
end
end
