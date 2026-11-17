# F4-00 (F4 design §3.3): one parameter object, `LatticeParameters`, for B's problems: the
# scalar parameters, the tables, the inputs and the clock's step index. Inputs and tables are
# written on every solver through `integ.ps[sym] = v` and `remake(prob; p, inputs)`, and read
# with `getp`, `prob.ps`, `sol.ps`. Negative controls: the base (3ed05c3b) ran each new
# claim against its raw parameter vector; the results it gave are in the comments.
# This file at the base: 3 pass, 2 fail, 6 errors (every testset fails).

@testsetup module LP_params
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
# imports an earlier file made in the old single Main
using SciMLBase: ReturnCode
using SymbolicIndexingInterface: SymbolicIndexingInterface
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/params.jl")
include("shared/export_all.jl")
end

@testitem "F4-00: integ.ps writes give the next window of a restart (owned and Tsit5)" setup = [LP_params] tags = [:latticepde, :params] begin
@testset "F4-00: integ.ps writes give the next window of a restart (owned and Tsit5)" begin
    # the owned integrator: a scalar, a table and an input written through `integ.ps`, then one
    # window against a fresh problem started from the written values
    po = discretize(wsys(), wdisc(); inputs = [wke => WK1])
        alg = ExplicitEuler(; substeps = 1)
        ig = init(po, alg; dt = 0.01)
    step!(ig)
    ig.ps[kw0] = 0.3
    ig.ps[Dw] = [0.25, 0.75]
    ig.ps[wke] = WK2                                   # (base: "`wk` names nothing of this problem")
    @test ig.ps[kw0] == 0.3 && ig.ps[Dw] == [0.25, 0.75] && ig.ps[wke] == WK2
    u1 = copy(ig[ce])
    step!(ig)
        r = init(remake(po; u0 = vec(u1), tspan = (0.01, 1.0), p = [kw0 => 0.3, Dw => [0.25, 0.75]], inputs = [wke => WK2]), alg; dt = 0.01)
    step!(r)
    @test maximum(abs, ig[ce] .- r[ce]) <= 1e-12
    # control: the window with the old input differs
        r0 = init(remake(po; u0 = vec(u1), tspan = (0.01, 1.0), p = [kw0 => 0.3, Dw => [0.25, 0.75]]), alg; dt = 0.01)
    step!(r0)
    @test maximum(abs, ig[ce] .- r0[ce]) > 1e-6

    # a Tsit5 integrator of the ODE problem: the same three writes (base: the input write and
    # the table write were refused, "is a table" and "names nothing")
    o = discretize(wsys(), wdisc(); inputs = [wke => WK1])
    oi = init(o, Tsit5(); adaptive = false, dt = 0.01)
    step!(oi)
    oi.ps[kw0] = 0.3
    oi.ps[Dw] = [0.25, 0.75]
    oi.ps[wke] = WK2
    @test oi.ps[kw0] == 0.3 && oi.ps[Dw] == [0.25, 0.75] && oi.ps[wke] == WK2 && oi.ps[Dw[2]] == 0.75
    u1, t1 = copy(oi.u), oi.t
    step!(oi)
    o2 = discretize(wsys(), wdisc(); inputs = [wke => WK1])
    ri = init(remake(o2; u0 = u1, tspan = (t1, 1.0), p = [kw0 => 0.3, Dw => [0.25, 0.75]], inputs = [wke => WK2]), Tsit5();
        adaptive = false, dt = 0.01)
    step!(ri)
    @test maximum(abs, oi.u .- ri.u) <= 1e-12
    r0 = init(remake(o2; u0 = u1, tspan = (t1, 1.0), p = [kw0 => 0.3, Dw => [0.25, 0.75]]), Tsit5(); adaptive = false,
        dt = 0.01)
    step!(r0)
    @test maximum(abs, oi.u .- r0.u) > 1e-6                    # control: the old input
    # a refused input write changes nothing (a value that is no kind of an Int32 map)
    @test occursin("integer values", wmsg(() -> (oi.ps[wke] = fill(0.5, 8, 8)))) && oi.ps[wke] == WK2
end
end

@testitem "F4-00: remake with inputs, tables and u0 pairs on the ODE problem" setup = [LP_params] tags = [:latticepde, :params] begin
@testset "F4-00: remake with inputs, tables and u0 pairs on the ODE problem" begin
    o = discretize(wsys(), wdisc(); inputs = [wke => WK1])
    # inputs through `remake` reach an OrdinaryDiffEq solve (base: SciML's "Unrecognized keyword
    # arguments: [:inputs]" from `solve`)
    a = solve(remake(o; inputs = [wke => WK2]), Tsit5(); abstol = 1e-10, reltol = 1e-10)
    b = solve(discretize(wsys(), wdisc(); inputs = [wke => WK2]), Tsit5(); abstol = 1e-10, reltol = 1e-10)
    @test a.retcode == SciMLBase.ReturnCode.Success && maximum(abs, a.u[end] .- b.u[end]) <= 1e-12
    @test maximum(abs, a.u[end] .- solve(o, Tsit5(); abstol = 1e-10, reltol = 1e-10).u[end]) > 1e-6   # control
    @test o.ps[wke] == WK1                                     # the source keeps its input
    # an input as a parameter pair, and a whole table
    c2 = solve(remake(o; p = [wke => WK2, Dw => [0.5, 1.0]]), Tsit5(); abstol = 1e-10, reltol = 1e-10)
    @test maximum(abs, c2.u[end] .- b.u[end]) <= 1e-12
    # tables read on the problem and its solution (base: `getp(o, Dw)` "Invalid symbol")
    @test getp(o, Dw)(o) == [0.5, 1.0] && o.ps[Dw] == [0.5, 1.0] && o.ps[Dw[1]] == 0.5 && b.ps[Dw] == [0.5, 1.0]
    d = remake(o; p = [Dw => [0.1, 0.2]])
    @test d.ps[Dw] == [0.1, 0.2] && o.ps[Dw] == [0.5, 1.0]
    # an entry is no key of a remake; a table needs its length
    @test occursin("entry 2 of the table `Dw`", wmsg(() -> remake(o; p = [Dw[2] => 5.0])))
    @test occursin("has 2 entries", wmsg(() -> remake(o; p = [Dw => [1.0]])))
    # `u0` pairs over the state (base: KeyError)
    u = remake(o; u0 = [ce => 2.0])
    @test all(==(2.0), u.u0) && length(u.u0) == 64
    @test occursin("not a field of the state", wmsg(() -> remake(o; u0 = [:typo => 2.0])))
    # an unknown input is named with the inputs
    @test occursin("its inputs: `wk`", wmsg(() -> remake(o; inputs = [:nope => WK2])))
end
end

@testitem "F4-00: SciMLStructures portions of LatticeParameters" setup = [LP_params] tags = [:latticepde, :params] begin
@testset "F4-00: SciMLStructures portions of LatticeParameters" begin
    o = discretize(wsys(), wdisc(); inputs = [wke => WK1])
    lp = o.p
    @test lp isa LatticePDE.Problems.LatticeParameters && SciMLStructures.isscimlstructure(lp)
    v, re, alias = SciMLStructures.canonicalize(Tunable(), lp)
    @test v == [0.2] && alias
    # Duals round-trip through `Tunable` (the tables and inputs are kept)
    vd = ForwardDiff.Dual.(v, 1.0)
    q = re(vd)
    @test eltype(q.values) <: ForwardDiff.Dual && q.tables == lp.tables && q.inputs == lp.inputs
    @test SciMLStructures.canonicalize(Tunable(), q)[1] == vd
    # a derivative through the replaced parameters, against a difference
    J(θ) = sum(solve(remake(o; p = SciMLStructures.replace(Tunable(), o.p, [θ])), Tsit5(); abstol = 1e-12,
        reltol = 1e-12).u[end])
    @test isapprox(ForwardDiff.derivative(J, 0.2), (J(0.2 + 1e-6) - J(0.2 - 1e-6)) / 2e-6; rtol = 1e-6)
    # `Constants` are the tables, `Discrete` the inputs and the step index
    @test SciMLStructures.canonicalize(Constants(), lp)[1] == [0.5, 1.0]
    dv = SciMLStructures.canonicalize(Discrete(), lp)[1]
    @test dv == [Float64.(vec(WK1)); 0.0]
    q2 = SciMLStructures.replace(Discrete(), lp, [Float64.(vec(WK2)); 3.0])
    @test q2.tick[] == 3 && reshape(last(only(q2.inputs)), 8, 8) == WK2 && lp.tick[] == 0
end
end

@testitem "F4-00: a table written on an OrdinaryDiffEq integrator is checked at the next call" setup = [LP_params] tags = [:latticepde, :params] begin
@testset "F4-00: a table written on an OrdinaryDiffEq integrator is checked at the next call" begin
    o = discretize(wsys(), wdisc(); inputs = [wke => WK1])
    oi = init(o, Tsit5())
    step!(oi)
    # (base: the write itself was refused, "`Dw` is a table … an ODE problem's tables are fixed")
    setp(oi, Dw)(oi, [-1.0, 1.0])
    @test oi.ps[Dw] == [-1.0, 1.0]
    @test occursin("negative", wmsg(() -> step!(oi)))
    # control: a positive table steps
    oj = init(discretize(wsys(), wdisc(); inputs = [wke => WK1]), Tsit5())
    setp(oj, Dw)(oj, [0.1, 1.0])
    step!(oj)
    @test oj.t > 0
end
end

@testitem "F4-00 (review 5): a plain parameter vector holds no inputs, which are not read as zero" setup = [LP_params] tags = [:latticepde, :params] begin
@testset "F4-00 (review 5): a plain parameter vector holds no inputs, which are not read as zero" begin
    o = discretize(wsys(), wdisc(); inputs = [wke => WK1])
    raw = SciMLBase.ODEProblem(o.f, o.u0, o.tspan, copy(o.p.values))
        # (at 0a182a0e: no error; the input read as zero, so `value_at(Dw, 0)` gave the rate 0)
    e = wmsg(() -> solve(raw, Tsit5()))
    @test occursin("plain vector", e) && occursin("`wk`", e)
    @test SciMLBase.successful_retcode(solve(SciMLBase.ODEProblem(o.f, o.u0, o.tspan, o.p), Tsit5()))   # control
end
end
