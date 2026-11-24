# The problem `discretize` returns runs on OrdinaryDiffEq's solvers
# with masks, `step_index(t)` and steady rows, and a system with no time gives a
# `LinearProblem` (every row linear) or a `NonlinearProblem`. Negative controls (the base
# 3ed05c3b, `problem = :ode`): each was refused at `discretize`, "masked conditions … need
# problem = :owned", "`step_index(t)` … needs a field algorithm", "the steady rows of `bc`
# make the system a DAE"; a system with no time gave a `SteadyStateProblem`. Before the fix:
# 1 pass, 2 fail, 6 errors (every testset fails).

@testsetup module LP_odepath
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
# imports an earlier file made in the old single Main
using SciMLBase: ReturnCode
using SymbolicIndexingInterface: SymbolicIndexingInterface
include("shared/preamble.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/export_all.jl")
end

@testitem "a masked condition under Tsit5 holds its value and equals the owned run" setup =
    [LP_odepath] tags = [
    :latticepde, :odepath,
] begin
    @testset "a masked condition under Tsit5 holds its value and equals the owned run" begin
        prob = discretize(omsys(), odisc(); inputs = [ode_k => OK1])
        s = solve(prob, Tsit5(); OTOL..., saveat = 0.02)
        @test SciMLBase.successful_retcode(s) && length(s.t) == 11
        # every save, the first too
        @test all(u -> all(==(2.0), reshape(u, 8, 8)[OK1 .== 1]), s.u)
        o = solve(prob, ExplicitEuler(); dt = 1.0e-5, saveat = 0.2)
        @test maximum(abs, s.u[end] .- o.u[end]) < 1.0e-4 ||
            (println("masked vs owned ", maximum(abs, s.u[end] .- o.u[end])); false)
        # control: the other sites move
        @test maximum(abs, reshape(s.u[end], 8, 8)[OK1 .== 0] .- 2.0) > 0.1
    end
end

@testitem "a mask moves with an input write in a callback" setup = [LP_odepath] tags = [
    :latticepde, :odepath,
] begin
    @testset "a mask moves with an input write in a callback" begin
        prob = discretize(omsys(), odisc(); inputs = [ode_k => OK1])
        cb = SciMLBase.DiscreteCallback(
            (u, t, i) -> t == 0.1, i -> (
                i.ps[ode_k] = OK2; nothing
            )
        )
        s = solve(
            prob, Tsit5(); OTOL..., callback = cb, tstops = [0.1], saveat = [0.1, 0.2]
        )
        U = reshape(s.u[end], 8, 8)
        # the new set holds
        @test all(==(2.0), U[OK2 .== 1])
        # the old set is released
        @test all(<(1.99), U[OK1 .== 1])
        # a restart at the write with the new input, from the state at 0.1
        a = s.u[findfirst(==(0.1), s.t)]
        r = solve(
            remake(prob; u0 = a, tspan = (0.1, 0.2), inputs = [ode_k => OK2]),
            Tsit5(); OTOL...
        )
        @test maximum(abs, s.u[end] .- r.u[end]) < 1.0e-8
    end
end

@testitem "step_index(t) under Tsit5 lands on every boundary" setup = [LP_odepath] tags = [
    :latticepde, :odepath,
] begin
    @testset "step_index(t) under Tsit5 lands on every boundary" begin
        sk = PDESystem(
            [D(ode_c) ~ -ode_c + 0.1 * step_index(t)], [oc(0, x, y) ~ x], odom(1.0), [
                t, x, y,
            ], [ode_c], Num[];
            name = :ok
        )
        prob = discretize(sk, odisc(; clock = 0.25))
        s = solve(prob, Tsit5(); OTOL...)
        @test SciMLBase.successful_retcode(s) && all(b -> b in s.t, (0.25, 0.5, 0.75))
        o = solve(prob, ExplicitEuler(); dt = 1.0e-5, saveat = 1.0)
        @test maximum(abs, s.u[end] .- o.u[end]) < 1.0e-5 ||
            (println("step_index vs owned ", maximum(abs, s.u[end] .- o.u[end])); false)
        # the exact value at t = 1 (a piecewise decay to 0.1 k on each period)
        u = collect(prob.u0)
        for k in 0:3
            u = 0.1k .+ (u .- 0.1k) .* exp(-0.25)
        end
        @test maximum(abs, s.u[end] .- u) < 1.0e-8
        # control: the same function and state with no clock callback reads k = 0 throughout
        bp = copy(prob.p)
        bp.tick[] = 0
        bare = SciMLBase.ODEProblem(prob.f, prob.u0, prob.tspan, bp)
        @test maximum(abs, solve(bare, Tsit5(); OTOL...).u[end] .- u) > 1.0e-2
        # a second solve starts again from k = 0
        @test solve(prob, Tsit5(); OTOL...).u[end] == s.u[end]
    end
end

@testitem "a steady row under Rodas5P equals the owned QuasiSteady run" setup = [
    LP_odepath,
] tags = [
    :latticepde, :odepath,
] begin
    @testset "a steady row under Rodas5P equals the owned QuasiSteady run" begin
        ss = PDESystem(
            [
                D(ode_c) ~ oD * laplacian(ode_c) - ode_c + ode_v,
                0 ~ 0.1 * laplacian(ode_v) - ode_v + ode_c,
            ],
            [oc(0, x, y) ~ x, oc(t, 0, y) ~ 1.0], odom(0.1), [t, x, y], [ode_c, ode_v],
            [oD]; name = :os
        )
        prob = discretize(ss, odisc())
        M = prob.f.mass_matrix
        @test M isa Diagonal && count(iszero, M.diag) == 64 && count(isone, M.diag) == 64
        s = solve(prob, Rodas5P(); OTOL...)
        @test SciMLBase.successful_retcode(s)
        o = solve(
            prob, BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 64));
            dt = 1.0e-5, saveat = 0.1
        )
        @test maximum(abs, s.u[end] .- o.u[end]) < 1.0e-4 ||
            (println("steady vs owned ", maximum(abs, s.u[end] .- o.u[end])); false)
        # the steady rows hold at the end (the residual of `v`'s row is 0)
        du = similar(s.u[end])
        prob.f(du, s.u[end], prob.p, 0.1)
        @test maximum(abs, du[65:128]) < 1.0e-8
    end
end

@testitem "a system with no time gives a LinearProblem or a NonlinearProblem" setup = [
    LP_odepath,
] tags = [
    :latticepde, :odepath,
] begin
    @testset "a system with no time gives a LinearProblem or a NonlinearProblem" begin
        fdom = [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        @variables ow(..)
        owe = ow(x, y)
        sl = PDESystem(
            [0 ~ 0.3 * laplacian(owe) - 2.0 * owe + x],
            [ow(0, y) ~ 1.0], fdom, [x, y], [owe], Num[]; name = :ol
        )
        lp = discretize(sl, odisc())
        @test lp isa SciMLBase.LinearProblem && lp.A isa LFP.LatticeOperator
        q = solve(
            lp, QuasiSteady(;
                linsolve = LatticePCG(; reltol = 1.0e-14, maxiters = 400)
            )
        )
        @test maximum(abs, lp.A * q.u[1] .- lp.b) < 1.0e-8 * maximum(abs, lp.b)
        # (the default: QuasiSteady)
        @test solve(lp).retcode == SciMLBase.ReturnCode.Success
        # A against the matrix of its columns: the same operator as the right side's
        # Jacobian
        n = length(lp.b)
        Am = reduce(hcat, (lp.A * [i == j ? 1.0 : 0.0 for i in 1:n]) for j in 1:n)
        @test maximum(abs, Am \ lp.b .- q.u[1]) < 1.0e-8
        # a nonlinear row gives a NonlinearProblem of the right side (zero at the steady
        # state)
        sn = PDESystem(
            [0 ~ 0.3 * laplacian(owe) - owe^3 - owe + x],
            [ow(0, y) ~ 1.0], fdom, [x, y], [owe], Num[]; name = :on
        )
        np = discretize(sn, odisc())
        @test np isa SciMLBase.NonlinearProblem
        r = solve(
            np, QuasiSteady(;
                linsolve = LatticePCG(; reltol = 1.0e-14, maxiters = 400)
            )
        )
        du = similar(r.u[1])
        np.f(du, r.u[1], np.p)
        # (QuasiSteady's Newton tolerance)
        @test maximum(abs, du) < 1.0e-6
        # control: the cubic term
        @test maximum(abs, lp.A * r.u[1] .- lp.b) > 1.0e-3
    end
end

@testitem "(R1): a mask value that reads t moves at its rate ∂v/∂t, at the solver's \
    order" setup = [LP_odepath] tags = [
    :latticepde, :odepath,
] begin
    @testset "(R1): a mask value that reads t moves at its rate ∂v/∂t, at the solver's \
        order" begin
        prob = discretize(
            qsys(1.0 + sin(10 * t)),
            LatticeDiscretization(Grid((16, 16)); T = Float64); inputs = [qke => QK]
        )
        # the owned reference: ExplicitEuler at dt and 2dt, extrapolated (Richardson, order
        # 2)
        r1 = solve(prob, ExplicitEuler(); dt = 1.0e-5, saveat = [0.5, 1.0])
        r2 = solve(prob, ExplicitEuler(); dt = 2.0e-5, saveat = [0.5, 1.0])
        ref = 2 .* r1.u[end] .- r2.u[end]
        for alg in (Tsit5(), Rodas5P())
            s = solve(prob, alg; abstol = 1.0e-9, reltol = 1.0e-9, saveat = [0.5, 1.0])
            e = maximum(abs, s.u[end] .- ref)
            mv = maximum(abs, reshape(s.u[end], 16, 16)[1, :] .- (1 + sin(10.0)))
            # (0a182a0e, the held value: Tsit5 at 1e-8 0.0033, Rodas5P at 1e-8 0.0059,
            # f4b1-rev/pA.log P1)
            @test e < 1.0e-5 && mv < 1.0e-6 ||
                (println("R1 ", nameof(typeof(alg)), " err ", e, " masked ", mv); false)
        end
        # the default tolerances too (0a182a0e: Tsit5 0.020, Rodas5P 0.30)
        for alg in (Tsit5(), Rodas5P())
            e = maximum(abs, solve(prob, alg; saveat = [1.0]).u[end] .- ref)
            @test e < 2.0e-3 ||
                (println("R1 default ", nameof(typeof(alg)), " err ", e); false)
        end
        # control: EE's own error is first order
        @test maximum(abs, r1.u[end] .- r2.u[end]) > 1.0e-5
    end
end

@testitem "(re-review): masked values jump at a new step index and at a write on the \
    integrator" setup = [LP_odepath] tags = [
    :latticepde, :odepath,
] begin
    @testset "(re-review): masked values jump at a new step index and at a write on the \
        integrator" begin
        # E1: a value that reads step_index(t) (clock 0.25) is 1 + k in period k, as the
        # owned run (9d30a15a: 1.0 at every save; the other sites off by 2.19)
        prob = discretize(
            rrsys(1.0 + step_index(t)), odisc(; clock = 0.25);
            inputs = [rrke => RRK, rrqe => zeros(8, 8)]
        )
        s = solve(prob, Tsit5(); abstol = 1.0e-9, reltol = 1.0e-9, saveat = [0.2, 0.6, 0.9])
        o = solve(prob, ExplicitEuler(); dt = 1.0e-5, saveat = [0.2, 0.6, 0.9])
        @test [unique(u[RRM]) for u in s.u] == [[1.0], [3.0], [4.0]] ||
            (println("E1 masked ", [unique(u[RRM]) for u in s.u]); false)
        # (the owned saves hold t0 and the end too)
        e1 = maximum(abs, s.u[end] .- o.u[findfirst(τ -> abs(τ - 0.9) < 1.0e-9, o.t)])
        @test e1 < 1.0e-4 || (println("E1 err ", e1); false)
        # E2: a value 2ea, `integ.ps[rra] = 1.5` (9d30a15a: 2.0)
        @test all(≈(3.0; atol = 1.0e-12), rrwrite(rra * 2.0, rra, 1.5)) ||
            (println("E2 ", unique(rrwrite(rra * 2.0, rra, 1.5))); false)
        # E3: a value 1 + rrq, an input write rrq = 2 (9d30a15a: 1.0)
        @test all(≈(3.0; atol = 1.0e-12), rrwrite(1.0 + rrqe, rrqe, fill(2.0, 8, 8))) ||
            (println("E3 ", unique(rrwrite(1.0 + rrqe, rrqe, fill(2.0, 8, 8)))); false)
        # E5: a value rra(1 + sin 10t), `integ.ps[rra] = 2` at 0.5: the value and its rate
        # follow (9d30a15a: 0.871 at t = 1 for 0.912)
        w = rrwrite(rra * (1.0 + sin(10 * t)), rra, 2.0)
        @test maximum(abs, w .- 2(1 + sin(10.0))) < 1.0e-6 ||
            (println("E5 ", unique(w)); false)
        # control: with no write the value stays rra(1 + sin 10t) at rra = 1
        @test maximum(
            abs, rrwrite(rra * (1.0 + sin(10 * t)), rra, 1.0) .-
                (1 + sin(10.0))
        ) < 1.0e-6
    end
end

@testitem "(gate): a Dual parameter that a mask value reads promotes the state" setup = [
    LP_odepath,
] tags = [
    :latticepde, :odepath,
] begin
    @testset "(gate): a Dual parameter that a mask value reads promotes the state" begin
        # (4f2217e2: remake raised "no method matching Float64(::ForwardDiff.Dual…)" in
        # _clamp_masks!)
        prob = discretize(
            rrsys(2.0 * rra), odisc(); inputs = [
                rrke => RRK, rrqe => zeros(8, 8),
            ]
        )
        i = LatticePDE.Problems.SII.parameter_index(prob, rra)
        function dual(a)
            q = collect(ForwardDiff.Dual{Nothing, Float64, 1}, prob.p.values)
            q[i] = ForwardDiff.Dual(a, 1.0)
            return q
        end
        flt(a) = (q = copy(prob.p.values); q[i] = a; q)
        # a weighted sum of the free sites
        w = vec(RRK .== 0) .* (1:64)
        for (alg, kw, tol) in (
                (ExplicitEuler(), (; dt = 1.0e-3), 1.0e-6),
                (Tsit5(), (; abstol = 1.0e-11, reltol = 1.0e-11), 1.0e-5),
            )
            g(q) = sum(w .* solve(remake(prob; p = q), alg; kw...).u[end])
            r = remake(prob; p = dual(1.2))
            @test eltype(r.u0) <: ForwardDiff.Dual &&
                all(==(ForwardDiff.Dual{Nothing}(2.4, 2.0)), r.u0[RRM])
            d = ForwardDiff.partials(g(dual(1.2)), 1)
            fd = (g(flt(1.2 + 1.0e-5)) - g(flt(1.2 - 1.0e-5))) / 2.0e-5
            @test abs(d - fd) < tol * abs(fd) && abs(fd) > 1 ||
                (println("gate Dual ", nameof(typeof(alg)), " ", d, " ", fd); false)
        end
        # the integrator: a Dual write of the parameter moves the masked values with their
        # partials
        it = init(remake(prob; p = dual(1.2)), Tsit5(); abstol = 1.0e-9, reltol = 1.0e-9)
        SciMLBase.step!(it, 0.5, true)
        it.ps[rra] = ForwardDiff.Dual{Nothing}(1.5, 1.0)
        SciMLBase.step!(it, 0.5, true)
        @test all(==(ForwardDiff.Dual{Nothing}(3.0, 2.0)), it.u[RRM])
    end
end

@testitem "prob.u0 holds the masked values, on every route" setup = [LP_odepath] tags = [
    :latticepde, :odepath,
] begin
    @testset "prob.u0 holds the masked values, on every route" begin
        prob = discretize(omsys(), odisc(); inputs = [ode_k => OK1])
        M1 = vec(OK1 .== 1)
        # (0a182a0e: u0 at the masked sites 0.25 … the initial value x, f4b1-rev/pC.log)
        @test all(==(2.0), prob.u0[M1])
        # no built-in callback
        bare = SciMLBase.ODEProblem(prob.f, prob.u0, prob.tspan, prob.p)
        @test all(==(2.0), solve(bare, Tsit5(); OTOL...).u[end][M1])
        ss = SciMLBase.SteadyStateProblem(prob)
        du = similar(prob.u0)
        ss.f(du, ss.u0, ss.p, 0.0)
        @test all(==(2.0), ss.u0[M1]) && all(iszero, du[M1])
        # remake: new inputs move the masked values, a new `u0` takes them
        q = remake(prob; inputs = [ode_k => OK2])
        @test all(==(2.0), q.u0[vec(OK2 .== 1)]) && q.u0[64] != prob.u0[64] &&
            all(==(2.0), prob.u0[M1])   # (the source kept)
        @test all(==(2.0), remake(prob; u0 = zeros(64)).u0[M1]) &&
            remake(prob; u0 = zeros(64)).u0[end] == 0.0
    end
end

@testitem "parameter writes on a time-free LinearProblem; factorizations" setup = [
    LP_odepath,
] tags = [
    :latticepde, :odepath,
] begin
    @testset "parameter writes on a time-free LinearProblem; factorizations" begin
        @parameters ls = 1.0 la = 2.0
        @variables lw(..)
        lwe = lw(x, y)
        sl = PDESystem(
            [0 ~ 0.3 * laplacian(lwe) - la * lwe + ls * x], [lw(0, y) ~ 1.0], [
                x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0),
            ],
            [x, y], [lwe], [ls, la]; name = :pl
        )
        lp = discretize(sl, odisc())
        function qs(p)
            return solve(
                p, QuasiSteady(;
                    linsolve = LatticePCG(; reltol = 1.0e-14, maxiters = 400)
                )
            ).u[1]
        end
        # (0a182a0e: "objects of type Nothing are not callable")
        lp.ps[ls] = 3.0
        setp(lp, la)(lp, 5.0)
        q = qs(lp)
        # A and b follow the writes
        @test lp.ps[ls] == 3.0 && maximum(abs, lp.A * q .- lp.b) < 1.0e-10
        @test maximum(
            abs, q .- qs(
                remake(
                    discretize(sl, odisc()); p = [
                        ls => 3.0, la => 5.0,
                    ]
                )
            )
        ) < 1.0e-12
        # (0a182a0e: GMRES was off by 1.1 after a parameter write)
        r = solve(lp, LinearSolve.KrylovJL_GMRES(); abstol = 1.0e-13, reltol = 1.0e-13)
        @test maximum(abs, r.u .- q) < 1.0e-9 ||
            (println("GMRES error: ", maximum(abs, r.u .- q)); false)
        # a factorization names its routes (0a182a0e: "no method matching
        # copy(::LatticeOperator)"); the assembled matrix is one
        e = try
            solve(lp, LinearSolve.LUFactorization())
            ""
        catch err
            sprint(showerror, err)
        end
        @test occursin("stores no matrix", e) && occursin("lattice_matrix", e)
        r = solve(
            SciMLBase.LinearProblem(LFP.lattice_matrix(lp.A), lp.b),
            LinearSolve.LUFactorization()
        )
        @test maximum(abs, r.u .- q) < 1.0e-10
    end
end

@testitem "(R2): steady rows start from our QuasiSteady solve at t0; explicit inits \
    stay" setup = [LP_odepath] tags = [
    :latticepde, :odepath,
] begin
    @testset "(R2): steady rows start from our QuasiSteady solve at t0; explicit inits \
        stay" begin
        ss = PDESystem(
            [
                D(ode_c) ~ oD * laplacian(ode_c) - ode_c + ode_v,
                0 ~ 0.1 * laplacian(ode_v) - ode_v + ode_c,
            ],
            [oc(0, x, y) ~ x, oc(t, 0, y) ~ 1.0], odom(0.1), [t, x, y], [ode_c, ode_v],
            [oD]; name = :os2
        )
        prob = discretize(ss, odisc())
        # (no OrdinaryDiffEqNonlinearSolve needed)
        ig = init(prob, Rodas5P(); OTOL...)
        du = similar(ig.u)
        prob.f(du, ig.u, prob.p, 0.0)
        # the rows solved, `c` kept
        @test maximum(abs, du[65:128]) < 1.0e-8 && ig.u[1:64] == prob.u0[1:64]
        # (0a182a0e: the default was BrownFullBasicInit, a MethodError without
        # OrdinaryDiffEqNonlinearSolve)
        e = try
            init(prob, Rodas5P(); initializealg = SciMLBase.CheckInit())
            nothing
        catch err
            err
        end
        # an explicit CheckInit still checks (u0 has v = 0)
        @test e isa SciMLBase.CheckInitFailureError
    end
end
