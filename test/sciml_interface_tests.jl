# SciMLBase's problem, integrator and solution interface (D-287 R5 to R8), one test generic over
# the three owned paths: a `PottsProblem` (integer MCS), a `FieldProblem` solved directly and the
# discretized `ODEProblem` solved by a field algorithm. Each case gives a problem, an algorithm,
# a step `h` and a write into the live state. Negative control at 8afe9212 (before the integrator
# contract): `step!(integ, h, true)`, `add_tstop!` and `PresetTimeCallback` on a `PottsIntegrator`
# are `MethodError`s, `abstol` a `MethodError`, and a write into `integ.u` is lost (a host copy).

@testsetup module SciMLInterfaceSetup
using Potts, Test
using Potts: CorePotts
using SciMLBase: SciMLBase, ReturnCode, add_tstop!, derivative_discontinuity!, DiscreteCallback, EnsembleProblem,
    EnsembleSerial
using DiffEqCallbacks: PresetTimeCallback, PeriodicCallback
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))
const LP = Potts.LatticePDE
const LFP = Potts.LatticeFields.Problems

@potts_model IfaceSorting begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice((30, 30); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

function iface_op()
    σ = zeros(Int32, 30, 30)
    σ[3:8, 3:8] .= 1; σ[3:8, 9:14] .= 2; σ[9:14, 3:8] .= 3; σ[9:14, 9:14] .= 4   # in contact
    return [ownership => σ, kind => [:dark, :light, :dark, :light]]
end
potts_problem(extra = []; tf = 7, kw...) = PottsProblem(IfaceSorting(; name = :iface), [iface_op(); extra], (0, tf); seed = 3, kw...)

module IfacePDE
    using ..FieldPDE
    @variables c(..)
    const C = c(t, x, y)
    decay(k = 0.5) = (@parameters Dc = 0.2 kc = k; pdesys([Dt(C) ~ Dc * Δ(C) - kc * C], [c(0, x, y) ~ 1.0 + x / 8], (8, 8), [C], [Dc, kc]))
end
field_ode(k = 0.5) = LP.discretize(IfacePDE.decay(k), LP.LatticeDiscretization(LP.Grid((8, 8)); T = Float64))
const DT = 0.1
const KC = only(
    filter(
        p -> Potts.ModelingToolkitBase.getname(p) == :kc,
        Potts.ModelingToolkitBase.parameters(IfacePDE.decay())
    )
)

"""The three paths: `(name, problem, algorithm, h, the windows in the time span, the time span's end)`."""
function iface_cases()
    ode = field_ode()
    return (
        (; name = "PottsProblem", prob = potts_problem(), alg = SequentialCPM(), h = 3, nwin = 7, tf = 7),
        (; name = "FieldProblem", prob = LFP.field_problem(ode), alg = LP.ExplicitEuler(; dt = DT), h = 0.25, nwin = 10, tf = 1.0),
        (; name = "ODE path", prob = remake(ode; tspan = (0.0, 1.0)), alg = LP.ExplicitEuler(; dt = DT), h = 0.25, nwin = 10, tf = 1.0),
    )
end
fix_tspan(c) = c.name == "FieldProblem" ? merge(c, (; prob = remake(c.prob; tspan = (0.0, 1.0)))) : c

"""A copy of the state an integrator holds now (the lattice of a Potts run), comparable across runs."""
state_copy(integ::CorePotts.PottsIntegrator) = copy(current_state(integ).σ)
state_copy(integ) = copy(Array(integ.u))

"""Write into the live state `integ.u`: a cell's kind (Potts: it changes its contact energies) or the field's values."""
live_write!(integ::CorePotts.PottsIntegrator) = (integ.u.cell.kind[1] = integ.u.cell.kind[2]; nothing)
live_write!(integ) = (integ.u .= 2.0; nothing)

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "SciMLBase interface on the owned Potts and field paths" setup = [SciMLInterfaceSetup] tags = [:potts, :sciml_interface] begin
    for c0 in iface_cases()
        c = fix_tspan(c0)
        @testset "$(c.name)" begin
            prob, alg, h = c.prob, c.alg, c.h
            @test SciMLBase.isinplace(prob) === true

            # step!(integ, h, true) lands on t + h; add_tstop! is landed on
            integ = init(prob, alg; save_everystep = false)
            step!(integ, h, true)
            @test integ.t ≈ h
            ts = 2h + (c.name == "PottsProblem" ? 1 : 0.05)
            add_tstop!(integ, ts)
            while integ.t < ts - 1.0e-9
                step!(integ)
            end
            @test integ.t ≈ ts
            @test SciMLBase.check_error(integ) == ReturnCode.Success        # a healthy run in progress
            @test integ.sol.retcode == ReturnCode.Default
            @test SciMLBase.has_stats(integ) && integ.stats !== nothing

            # iteration runs one step per window to the end of the time span
            fresh = init(prob, alg; save_everystep = false)
            n = 0
            for _ in fresh
                n += 1
            end
            @test n == c.nwin && fresh.t ≈ c.tf
            @test SciMLBase.successful_retcode(fresh.sol)

            # DiffEqCallbacks fire at the listed times
            hits = Float64[]
            times = c.name == "PottsProblem" ? [2, 5] : [0.3, 0.75]
            solve(prob, alg; save_everystep = false, callback = PresetTimeCallback(times, i -> push!(hits, i.t)))
            @test hits ≈ times
            per = Float64[]
            Δ = c.name == "PottsProblem" ? 2 : 0.3
            solve(prob, alg; save_everystep = false, callback = PeriodicCallback(i -> push!(per, i.t), Δ))
            want = c.name == "PottsProblem" ? [2, 4, 6] : [0.3, 0.6, 0.9]
            @test per[1:length(want)] ≈ want && all(t -> t <= c.tf + 1.0e-9, per)

            # the default saves every step (SciML); `saveat` and `save_everystep = false` save less
            sol = solve(prob, alg)
            @test length(sol.t) == c.nwin + 1
            @test length(solve(prob, alg; save_everystep = false).t) == 2
            @test sol(sol.t[2]) == sol.u[2]

            # an unknown keyword is refused by name
            @test_throws ArgumentError solve(prob, alg; not_a_keyword = 1)
            err = try
                solve(prob, alg; not_a_keyword = 1)
            catch e
                sprint(showerror, e)
            end
            @test occursin("not_a_keyword", err)

            # a write into the live state, then `derivative_discontinuity!`, changes the next step
            a = init(prob, alg; save_everystep = false)
            b = init(prob, alg; save_everystep = false)
            step!(a); step!(b)
            live_write!(a)
            derivative_discontinuity!(a, true)
            for _ in 1:3
                step!(a); step!(b)
            end
            @test state_copy(a) != state_copy(b)
        end
    end
end

@testitem "SciMLBase interface: Potts solutions, keywords and traits" setup = [SciMLInterfaceSetup] tags = [:potts, :sciml_interface] begin
    prob = potts_problem()
    alg = SequentialCPM()
    @test SciMLBase.isdiscrete(alg)
    @test SciMLBase.supports_solve_rng(prob, alg)

    sol = solve(prob, alg; saveat = 3)
    @test sol.t == [0, 3, 6, 7]
    @test sol(3) == sol[2] && sol(3; idxs = :volume) == sol[:volume][2]
    @test sol([0, 6]) == [sol[1], sol[3]]
    @test_throws ArgumentError sol(4)                                    # not saved: no interpolation
    @test_throws ArgumentError sol(2.5)
    @test !sol.dense
    @test_throws ArgumentError Array(sol)
    @test_throws ArgumentError sol[1, 1]
    @test_throws ArgumentError solve(prob, alg; abstol = 1.0e-6)
    @test_throws ArgumentError solve(prob, alg; dense = true)

    # a list of quantities reads together
    @test sol[[:volume, :kind]] == [[v, k] for (v, k) in zip(sol[:volume], sol[:kind])]
    @test sol[(:volume, :kind)] == [(v, k) for (v, k) in zip(sol[:volume], sol[:kind])]

    # remake with a map equals construction with the value
    r = solve(remake(prob; p = [:T => 4.0]), alg; save_everystep = false)
    d = solve(potts_problem([:T => 4.0]), alg; save_everystep = false)
    @test r.u[end].σ == d.u[end].σ

    # the solve keywords: seed, maxiters, save_idxs, verbose, tstops; problem keywords merge
    @test solve(prob, alg; seed = 9, save_everystep = false).u[end].σ == solve(remake(prob; seed = 9), alg; save_everystep = false).u[end].σ
    @test solve(prob, alg; seed = 9, save_everystep = false).u[end].σ != solve(prob, alg; save_everystep = false).u[end].σ
    m = @test_logs (:warn, r"maxiters") solve(prob, alg; maxiters = 4, save_everystep = false)
    @test m.retcode == ReturnCode.MaxIters && m.t[end] == 4
    @test_logs solve(prob, alg; maxiters = 4, save_everystep = false, verbose = false)
    @test keys(solve(prob, alg; save_idxs = [:σ]).u[end].cell) == ()
    @test potts_problem(; saveat = [7]).kwargs == (; saveat = [7])
    @test solve(potts_problem(; saveat = [5]), alg).t == [0, 5, 7]

    # a callback's save positions: a save after the affect at the MCS it fires
    cb = DiscreteCallback((u, t, i) -> t == 3, i -> nothing; save_positions = (false, true))
    @test solve(prob, alg; save_everystep = false, callback = cb).t == [0, 3, 7]

    # parameters: read on the problem, written on the problem and the integrator
    q = potts_problem()
    @test getp(q, :T)(q) == 10.0
    setp(q, :T)(q, 3.0)
    @test q.ps[:T] == 3.0
    integ = init(q, alg; save_everystep = false)
    integ.ps[:T] = 5.0
    @test getp(integ, :T)(integ) == 5.0
    @test integ.sol.retcode == ReturnCode.Default
    @test solve!(integ).retcode == ReturnCode.Success

    # ensembles: reproducible by replica, and by `seed`
    ens = EnsembleProblem(prob)
    run(; kw...) = [s.u[end].σ for s in solve(ens, alg, EnsembleSerial(); trajectories = 2, save_everystep = false, kw...).u]
    a, b = run(), run()
    @test a == b && a[1] != a[2]
    @test run(; seed = 1) == run(; seed = 1) && run(; seed = 1) != a
end

@testitem "SciMLBase interface: field algorithms, reinit!, remake, get_du" setup = [SciMLInterfaceSetup] tags = [:potts, :sciml_interface] begin
    @test !SciMLBase.isadaptive(LP.ExplicitEuler(; dt = DT))
    @test SciMLBase.alg_order(LP.ExplicitEuler(; dt = DT)) == 1 && SciMLBase.alg_order(LP.CrankNicolson(; dt = DT)) == 2
    @test SciMLBase.has_init(LP.ExplicitEuler(; dt = DT)) && SciMLBase.has_step(LP.ExplicitEuler(; dt = DT))
    ode = field_ode()
    fp = remake(LFP.field_problem(ode); tspan = (0.0, 1.0))
    alg = LP.ExplicitEuler(; dt = DT)

    # an owned solve of a FieldProblem is SciML's ODESolution
    s = solve(fp, alg; saveat = 0.5)
    @test s isa SciMLBase.ODESolution && s.alg isa LP.ExplicitEuler && s.ps[KC] == 0.5
    @test s.t ≈ [0.0, 0.5, 1.0] && s(0.5) ≈ s.u[2]

    # remake with a map equals construction with the value
    @test solve(remake(fp; p = [KC => 2.0]), alg).u[end] ≈ solve(remake(LFP.field_problem(field_ode(2.0)); tspan = (0.0, 1.0)), alg).u[end]
    u2 = fill(2.0, length(fp.u0))
    @test solve(remake(fp; u0 = [IfacePDE.C => fill(2.0, 8, 8)]), alg).u[end] ≈ solve(remake(fp; u0 = u2), alg).u[end]

    # reinit! with a new span; without erasing the saves
    integ = init(fp, alg; save_everystep = false)
    solve!(integ)
    SciMLBase.reinit!(integ; t0 = 0.0, tf = 0.5)
    @test integ.t == 0.0
    @test solve!(integ).t ≈ [0.0, 0.5]
    SciMLBase.reinit!(integ; erase_sol = false, tf = 0.5)
    @test solve!(integ).t ≈ [0.0, 0.5, 0.0, 0.5]                   # the earlier saves are kept
    @test integ.opts.maxiters == typemax(Int)

    # get_du: the rate at the current state (here a uniform state, so the diffusion is zero)
    uni = init(remake(fp; u0 = fill(1.0, length(fp.u0))), alg; save_everystep = false)
    @test SciMLBase.get_du(uni) ≈ fill(-0.5, length(fp.u0))
    # no algorithm and no clock: DiffEqBase's default decides (it needs DifferentialEquations)
    @test_throws SciMLBase.NoDefaultAlgorithmError solve(ode)
end

@testitem "SciMLBase interface: Potts reinit!, tstops and savevalues!" setup = [SciMLInterfaceSetup] tags = [:potts, :sciml_interface] begin
    alg = SequentialCPM()
    prob = potts_problem()                                              # tspan (0, 7)

    # stops given to `init` are kept only in t0 < t ≤ tf; a runtime `add_tstop!` extends the run
    @test solve(prob, alg; tstops = [3, 12], save_everystep = false).t == [0, 7]
    integ = init(prob, alg; tstops = [0, 3, 12], save_everystep = false)
    @test SciMLBase.first_tstop(integ) == 3
    SciMLBase.pop_tstop!(integ)
    @test !SciMLBase.has_tstop(integ)
    add_tstop!(integ, 9)
    @test solve!(integ).t == [0, 9]

    # `add_tstop!` at the current MCS is accepted (reached already); before it is an error
    integ = init(prob, alg; save_everystep = false)
    step!(integ, 2)
    add_tstop!(integ, 2)
    @test_throws ArgumentError add_tstop!(integ, 1)

    # `savevalues!` saves with `force_save`, `save_everystep` or at a `saveat` time
    integ = init(prob, alg; saveat = [4], save_everystep = false)
    step!(integ, 2)
    @test SciMLBase.savevalues!(integ) == (false, false)
    @test SciMLBase.savevalues!(integ, true) == (true, true)
    @test SciMLBase.savevalues!(integ, true) == (false, false)          # once per MCS
    every = init(prob, alg)
    step!(every, 2)
    @test SciMLBase.savevalues!(every) == (false, false)                # saved by the step already
    @test solve!(integ).t == [0, 2, 4, 7]

    # reinit!: a new span, iter and tstops restored, the saves erased or kept
    starts = Ref(0)
    cb = DiscreteCallback((u, t, i) -> false, i -> nothing; initialize = (c, u, t, i) -> (starts[] += 1; nothing))
    integ = init(prob, alg; tstops = [5], save_everystep = false, callback = cb)
    solve!(integ)
    @test starts[] == 1 && integ.iter == 7
    SciMLBase.reinit!(integ; t0 = 2, tf = 6)
    @test integ.t == 2 && integ.iter == 0 && integ.retcode == ReturnCode.Default
    @test starts[] == 2 && SciMLBase.first_tstop(integ) == 5
    @test solve!(integ).t == [2, 6]
    SciMLBase.reinit!(integ; erase_sol = false, reinit_callbacks = false)
    @test starts[] == 2
    @test solve!(integ).t == [2, 6, 0, 7]                               # the earlier saves are kept

    # reinit! takes `saveat`, `tstops` and `reinit_retcode`; stops past `tf` are dropped
    SciMLBase.reinit!(integ; saveat = 3, tstops = [4, 20])
    @test SciMLBase.first_tstop(integ) == 4
    SciMLBase.pop_tstop!(integ)
    @test !SciMLBase.has_tstop(integ)
    @test solve!(integ).t == [0, 3, 6, 7]
    SciMLBase.reinit!(integ)                                            # the save times of `init` again
    @test solve!(integ).t == [0, 7]
    SciMLBase.terminate!(integ)
    SciMLBase.reinit!(integ; reinit_retcode = false)
    @test integ.retcode == ReturnCode.Terminated

    # a span of no MCS is a valid run on both paths; one that runs backward is an error
    SciMLBase.reinit!(integ; t0 = 4, tf = 4)
    @test solve!(integ).t == [4]
    @test_throws ArgumentError SciMLBase.reinit!(integ; t0 = 5, tf = 4)
    fp = remake(LFP.field_problem(field_ode()); tspan = (0.0, 1.0))
    finteg = init(fp, LP.ExplicitEuler(; dt = DT); save_everystep = false)
    SciMLBase.reinit!(finteg; t0 = 0.5, tf = 0.5)
    @test solve!(finteg).t ≈ [0.5]
    @test_throws ArgumentError SciMLBase.reinit!(finteg; t0 = 0.5, tf = 0.25)
end
