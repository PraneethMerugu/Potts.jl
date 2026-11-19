# F4-B1 (F4 design §11): an input given as a function of the time, `inputs = [q => t -> values]`.
# A field algorithm writes `f(t)` at the start and after each window, as a callback that writes
# `integ.ps[q] = f(integ.t)` does; an OrdinaryDiffEq solver's right side evaluates `f` at every
# call (ruling Q19), and the masks that read it follow. Negative controls: at 8c3f01cf
# (~/lpwork/f4B1/nc.log) every testset errors, as `discretize` refuses the function; at 1f1b2288
# (input refreshed per accepted step, ~/lpwork/f4B1/q19-nc.log) Tsit5 and Rodas5P with no `dtmax`
# step over the pulse and miss the fine owned run, and the mask is not refused.

@testsetup module LP_timeinputs
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
using SciMLBase: remake
include("shared/lp_runner.jl")
include("shared/discretize.jl")
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqRosenbrock: Rodas5P
using ForwardDiff: ForwardDiff

@parameters tiD = 0.3
@variables tic(..) tiq(..) [input = true]
tice, tiqe = tic(t, x, y), tiq(t, x, y)
const TI_N = 8
# a front that moves along x: site column i is 1 from t = 0.08 i on (6 of 8 by t = 0.5)
tiQ(s) = [s > 0.08i ? 1.0 : 0.0 for i in 1:TI_N, j in 1:TI_N]
tidom() = [t ∈ Interval(0.0, 0.5), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
# a source that reads the input, and a mask that reads it
tisrc() = PDESystem(
    [D(tice) ~ tiD * laplacian(tice) - 0.5 * tice + tiqe], [tic(0, x, y) ~ 0.0], tidom(), [t, x, y],
    [tice, tiqe], [tiD]; name = :tisrc)
timask() = PDESystem(
    [D(tice) ~ tiD * laplacian(tice) - 0.5 * tice], [tic(0, x, y) ~ 0.0, tice ~ masked(tiqe > 0.5, 2.0)],
    tidom(), [t, x, y], [tice, tiqe], [tiD]; name = :timask)
tidisc() = LatticeDiscretization(Grid((TI_N, TI_N)); T = Float64)
# the reference: the input's values at the start, written by a callback after each window or step
tiwrite() = SciMLBase.DiscreteCallback((u, s, i) -> true, i -> (i.ps[tiqe] = tiQ(i.t); nothing);
    save_positions = (false, false))
tiref(sys, alg; kw...) = solve(discretize(sys, tidisc(); inputs = [tiqe => tiQ(0.0)]), alg; callback = tiwrite(), kw...)
tifn(sys, alg; kw...) = solve(discretize(sys, tidisc(); inputs = [tiqe => tiQ]), alg; kw...)
tiwarm(ig) = (step!(ig); step!(ig); @allocated step!(ig))      # (a function barrier)
tiode(prob) = tiwarm(init(prob, Tsit5(); adaptive = false, dt = 0.01, save_everystep = false))
@variables tik(..)::Int32 [input = true]
tike = tik(t, x, y)
tiK(v) = s -> Int32[s > v * i ? 1 : 0 for i in 1:TI_N, j in 1:TI_N]
tiint() = PDESystem(
    [D(tice) ~ tiD * laplacian(tice) - 0.5 * tice + ifelse(tike == 1, 1.0, 0.0)], [tic(0, x, y) ~ 0.0],
    tidom(), [t, x, y], [tice, tike], [tiD]; name = :tiint)

# On an OrdinaryDiffEq solver the right side evaluates the function at every call (ruling Q19),
# so an adaptive solver sees the front at its own stage times: Tsit5 and Rodas5P with no `dtmax`
# match a fine owned run (whose input holds over windows of 1e-4)
const TI_ODE = (; saveat = 0.1, abstol = 1e-8, reltol = 1e-8)
tifine(sys) = tifn(sys, ExplicitEuler(); dt = 1.0e-4, saveat = 0.1)

# Review B1 #1: a refresh keeps what the input does not touch. With `t -> 1.0` read by the rates
# alone, Crank–Nicolson and BDF2 equal their constant-input runs bit for bit, and with a smooth
# source `sin(6t)` in the equation they stay second order (a reset every window made BDF2
# Backward Euler and CN two half steps)
tismooth() = PDESystem(
    [D(tice) ~ tiD * laplacian(tice) - 0.5 * tice + sin(6t) * tiqe], [tic(0, x, y) ~ x], tidom(), [t, x, y],
    [tice, tiqe], [tiD]; name = :tismooth)
include("shared/export_all.jl")
end

@testitem "F4-B1: an input as a function of t, owned path (nameof(typeof(alg)))" setup = [LP_timeinputs] tags = [:latticepde, :timeinputs] begin
    @testset "F4-B1: an input as a function of t, owned path ($(nameof(typeof(alg))))" for (alg, dt) in
        ((ExplicitEuler(), 0.01), (BackwardEuler(), 0.05))
        a = tifn(tisrc(), alg; dt, saveat = 0.1)
        b = tiref(tisrc(), alg; dt, saveat = 0.1)
    @test a.t == b.t && a.u == b.u
    # (control: the function is read, not only its value at the start)
        c = solve(discretize(tisrc(), tidisc(); inputs = [tiqe => tiQ(0.0)]), alg; dt, saveat = 0.1)
    @test c.u[end] != a.u[end] && maximum(a.u[end]) > 0.05
    # an integrator steps it as `solve` does, and reads the input at its time
        ig = init(discretize(tisrc(), tidisc(); inputs = [tiqe => tiQ]), alg; dt)
    step!(ig, 0.3, true)
    @test ig.t == 0.3 && ig[tiqe] == tiQ(ig.t) && ig.u == a.u[4]
end
end

@testitem "F4-B1: an input as a function of t, OrdinaryDiffEq path (nameof(typeof(alg)))" setup = [LP_timeinputs] tags = [:latticepde, :timeinputs] begin
@testset "F4-B1: an input as a function of t, OrdinaryDiffEq path ($(nameof(typeof(alg))))" for alg in (Tsit5(), Rodas5P())
    a = tifn(tisrc(), alg; TI_ODE...)
    o = tifine(tisrc())
    @test a.t ≈ o.t
    e = maximum(i -> maximum(abs, a.u[i] .- o.u[i]), eachindex(a.t))
    @test e < 1e-3 * maximum(o.u[end]) || (println("F4-B1 ODE ", nameof(typeof(alg)), " vs fine owned: ", e); false)
    # (control: with the input held at its start value the field stays 0)
    c = solve(discretize(tisrc(), tidisc(); inputs = [tiqe => tiQ(0.0)]), alg; TI_ODE...)
    @test maximum(abs, c.u[end]) == 0 && maximum(o.u[end]) > 0.05
    # the integrator reads the input at its time
    ig = init(discretize(tisrc(), tidisc(); inputs = [tiqe => tiQ]), alg; TI_ODE...)
    step!(ig, 0.3, true)
    @test ig.t ≈ 0.3 && ig.ps[tiqe] == tiQ(ig.t)
end
end

@testitem "F4-B1: a mask that reads a function input moves (nameof(typeof(alg)))" setup = [LP_timeinputs] tags = [:latticepde, :timeinputs] begin
@testset "F4-B1: a mask that reads a function input moves ($(nameof(typeof(alg))))" for alg in
        (ExplicitEuler(), Tsit5())
    # (on an OrdinaryDiffEq solver a masked value jumps where the input switches, written after
    # the step: the step is bounded, as for a mask whose switch has no event)
        kw = alg isa ExplicitEuler ? (; dt = 0.01, saveat = 0.1) : (; TI_ODE..., dtmax = 0.01)
    a = tifn(timask(), alg; kw...)
    if alg isa ExplicitEuler
        b = tiref(timask(), alg; kw...)
        @test a.t == b.t && a.u == b.u
    else
        o = tifine(timask())
        e = maximum(abs, a.u[end] .- o.u[end])
        @test e < 2e-2 * maximum(o.u[end]) || (println("F4-B1 ODE mask vs fine owned: ", e); false)
            @test_throws ArgumentError tifn(timask(), alg; TI_ODE...)
    end
    on(i) = vec(tiQ(a.t[i]) .> 0.5)
    # the set grows with the front: at each save the masked sites hold 2.0
    @test count(on(2)) < count(on(length(a.t))) < TI_N^2
    alg isa ExplicitEuler && @test all(i -> all(==(2.0), a.u[i][on(i)]), 2:length(a.t))
    @test all(==(2.0), a.u[end][on(length(a.t))])
    # (control: with the input held at its start value no site is masked)
    c = solve(discretize(timask(), tidisc(); inputs = [tiqe => tiQ(0.0)]), alg; kw...)
    @test !any(==(2.0), c.u[end])
end
end

@testitem "F4-B1: remake, refusals and allocations of function inputs" setup = [LP_timeinputs] tags = [:latticepde, :timeinputs] begin
@testset "F4-B1: remake, refusals and allocations of function inputs" begin
    fp = discretize(tisrc(), tidisc(); inputs = [tiqe => tiQ])
    cp = discretize(tisrc(), tidisc(); inputs = [tiqe => tiQ(0.0)])
        alg = ExplicitEuler()
    # a value makes the input constant again; a function makes it follow the time
        @test solve(remake(fp; inputs = [tiqe => tiQ(0.0)]), alg; dt = 0.01).u == solve(cp, alg; dt = 0.01).u
        @test solve(remake(cp; inputs = [tiqe => tiQ]), alg; dt = 0.01).u == solve(fp, alg; dt = 0.01).u
        @test solve(remake(cp; p = [tiqe => tiQ]), alg; dt = 0.01).u == solve(fp, alg; dt = 0.01).u
    # a new time span starts the function at its own start
        @test solve(remake(fp; tspan = (0.1, 0.5)), alg; dt = 0.01).u ==
            solve(remake(cp; tspan = (0.1, 0.5), inputs = [tiqe => tiQ(0.1)]), alg; dt = 0.01, callback = tiwrite()).u
    msg(f) = try
        f(); ""
    catch e
        e isa ArgumentError ? e.msg : sprint(showerror, e)
    end
        ig = init(fp, alg; dt = 0.01)
    @test occursin("function of the time", msg(() -> (ig.ps[tiqe] = tiQ)))
    @test occursin("takes no time argument", msg(() -> discretize(tisrc(), tidisc(); inputs = [tiqe => () -> 1.0])))
    @test occursin("has 4 values", msg(() -> discretize(tisrc(), tidisc(); inputs = [tiqe => s -> zeros(2, 2)])))
        @test occursin("has 4 values", msg(() -> solve(discretize(tisrc(), tidisc(); inputs = [tiqe => s -> s < 0.1 ? zeros(8, 8) : zeros(2, 2)]), alg; dt = 0.01)))
    # a write of an input a function gives is refused on both paths, naming `remake` (review B1 #4)
        for ig in (init(fp, alg; dt = 0.01), init(fp, Tsit5()))
        step!(ig)
        @test occursin("remake(prob; inputs = [:tiq => K])", msg(() -> (ig.ps[tiqe] = fill(7.0, TI_N, TI_N))))
    end
    # a new time span re-evaluates the input at its start (review B1 #7)
    @test remake(fp; tspan = (0.3, 0.5)).ps[tiqe] == tiQ(0.3)
    # values with derivative parts are refused in words (review B1 #5)
    @test occursin("plain numbers", msg(() -> discretize(tisrc(), tidisc();
        inputs = [tiqe => s -> fill(ForwardDiff.Dual(s, 1.0), TI_N, TI_N)])))
    # an out-of-type result on the ODE path is named as such (review B1 #7)
    ip = discretize(tiint(), tidisc(); inputs = [tike => s -> fill(s < 0.1 ? Int64(1) : Int64(2)^40, TI_N, TI_N)])
    @test occursin("integer values in its type's range", msg(() -> solve(ip, Tsit5())))
    # the warm step of constant inputs allocates nothing; with a function, only what it returns
    # (here nothing: it writes one buffer, or returns a number)
    buf = zeros(TI_N, TI_N)
    inplace(s) = (for j in 1:TI_N, i in 1:TI_N
                      buf[i, j] = s > 0.08i ? 1.0 : 0.0
                  end; buf)
        for (a, dt) in ((ExplicitEuler(), 0.01), (BackwardEuler(), 0.05))
            @test tiwarm(init(cp, a; dt, save_everystep = false)) == 0
            @test tiwarm(init(remake(cp; inputs = [tiqe => inplace]), a; dt, save_everystep = false)) == 0
            @test tiwarm(init(remake(cp; inputs = [tiqe => s -> sin(s)]), a; dt, save_everystep = false)) == 0
            @test tiwarm(init(fp, a; dt)) > 0                     # (control: `tiQ` returns a new array)
    end
    # the same on the ODE path (a step whose callback writes the input)
    for g in (nothing, inplace, s -> sin(s))
        pr = g === nothing ? cp : remake(cp; inputs = [tiqe => g])
        tiode(pr)
        @test tiode(pr) == 0
    end
    @test tiode(fp) > 0
end
end

# Threads: each task's copy of the right side has input arrays of its own, so trajectories
# with other input functions (an integer input here, which copies once shared) never write one
# array; EnsembleThreads equals EnsembleSerial bit for bit (run under `julia -t 4`), on the ODE
# path and on the owned path (each integrator has its own store). Negative control at 243293bf
# under -t 4 (~/lpwork/f4B1/thr-nc2.log): Tsit5 19, 24 and 24 of 24 trajectories differ (the
# shared integer input races); the owned path already equal there.
@testitem "F4-B1: function inputs under EnsembleThreads equal EnsembleSerial (nameof(typeof(alg)))" setup = [LP_timeinputs] tags = [:latticepde, :timeinputs] begin
@testset "F4-B1: function inputs under EnsembleThreads equal EnsembleSerial ($(nameof(typeof(alg))))" for alg in
        (Tsit5(), ExplicitEuler())
    Threads.nthreads() > 1 || @warn "F4-B1 ensemble test: one thread (run under `julia -t 4`)"
    base = discretize(tiint(), tidisc(); inputs = [tike => tiK(0.05)])
    pf = (prob, ctx) -> remake(prob; inputs = [tike => tiK(0.01 + 0.005 * ctx.sim_id)])
    ep = SciMLBase.EnsembleProblem(base; prob_func = pf, safetycopy = false)
    kw = alg isa Tsit5 ? (; abstol = 1e-8, reltol = 1e-8, saveat = 0.1) : (; saveat = 0.1)
        s = solve(ep, alg, SciMLBase.EnsembleSerial(); dt = 0.01, trajectories = 24, kw...)
    @test s.u[1].u[end] != s.u[24].u[end]                 # (the trajectories differ)
    for _ in 1:3
            th = solve(ep, alg, SciMLBase.EnsembleThreads(); dt = 0.01, trajectories = 24, kw...)
        bad = count(i -> th.u[i].u != s.u[i].u, 1:24)
        @test bad == 0 || (println("F4-B1 ensemble ", nameof(typeof(alg)), ": ", bad, " of 24 trajectories differ"); false)
    end
end
end

@testitem "F4-B1: a refresh keeps the history of nameof(typeof(alg))" setup = [LP_timeinputs] tags = [:latticepde, :timeinputs] begin
    @testset "F4-B1: a refresh keeps the history of $(nameof(typeof(alg)))" for alg in
        (CrankNicolson(), BDF2())
    sys = tismooth()
    cst = discretize(sys, tidisc(); inputs = [tiqe => 1.0])
    fun = discretize(sys, tidisc(); inputs = [tiqe => s -> 1.0])
        @test solve(fun, alg; dt = 0.05).u == solve(cst, alg; dt = 0.05).u
        ref = solve(fun, alg; dt = 0.05 / 64).u[end]
        e1, e2 = (maximum(abs, solve(fun, alg; dt = h).u[end] .- ref) for h in (0.05, 0.025))
        @test log2(e1 / e2) > 1.8 || (println("F4-B1 order ", nameof(typeof(alg)), ": ", log2(e1 / e2)); false)
end
end

# Review B1 #2, #3: a mask that reads an input function reruns its init launches with no
# allocation (owned window, ODE call), and a fixed step counts as bounded
@testitem "F4-B1: masks that read an input function: bytes and a fixed step" setup = [LP_timeinputs] tags = [:latticepde, :timeinputs] begin
@testset "F4-B1: masks that read an input function: bytes and a fixed step" begin
    buf = zeros(TI_N, TI_N)
    inplace(s) = (for j in 1:TI_N, i in 1:TI_N
                      buf[i, j] = s > 0.08i ? 1.0 : 0.0
                  end; buf)
    mp = discretize(timask(), tidisc(); inputs = [tiqe => inplace])
        @test tiwarm(init(mp, ExplicitEuler(); dt = 0.01, save_everystep = false)) == 0
    o = tiode(mp)                          # (`adaptive = false`: not refused)
    o = tiode(mp)
    @test o <= 4096 || (println("F4-B1 ODE mask step bytes: ", o); false)
    s = solve(mp, Tsit5(); adaptive = false, dt = 0.01, saveat = 0.1)
    @test s.retcode == ReturnCode.Success
end
end
