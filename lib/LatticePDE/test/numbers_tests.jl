# Number types through problems (P5 role model, test matrix rows of C5/C6/C7a): Dual
# derivatives against finite differences on the owned and ODE paths, Rodas5P (Jacobian and
# time gradient through the right side), the BigFloat reference, promotion and plan reuse,
# and hoisted time. Each row has a negative control.

@testsetup module LP_numbers
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
using KernelAbstractions: KernelAbstractions
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/params.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/grids.jl")
include("shared/maskswitch.jl")
include("shared/numbers.jl")
include("shared/export_all.jl")
end

@testitem "AD vs FD: owned path (∂J/∂D, ∂J/∂k, ∂J/∂g)" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "AD vs FD: owned path (∂J/∂D, ∂J/∂k, ∂J/∂g)" begin
        prob = owned(nsys(), 8, 4)
        alg = ExplicitEuler()
        for s in (Dn, kn, gn)
            i = pidx(prob, s)
            Jo(v) = sum(solve(remake(prob; p = withp(prob.p, i, v)), alg; dt = 0.01).u[end])
            v0 = prob.p[i]
            d = ForwardDiff.derivative(Jo, v0)
            @test d isa Float64 && isapprox(d, fd(Jo, v0); rtol = 1.0e-6)
            @test d != 0
            # pairs form promotes the vector too
            Jp(v) = sum(solve(remake(prob; p = [s => v]), alg; dt = 0.01).u[end])
            @test ForwardDiff.derivative(Jp, v0) ≈ d
        end
        # negative control: a remake that drops the derivative parts gives 0
        i = pidx(prob, Dn)
        Jdrop(v) = sum(solve(remake(prob; p = withp(prob.p, i, ForwardDiff.value(v))), alg; dt = 0.01).u[end])
        @test ForwardDiff.derivative(Jdrop, prob.p[i]) == 0
        # Float32 state: the derivative in Dual{Float32} agrees to Float32 accuracy
        p32 = owned(nsys(), 8, 4; T = Float32)
        J32(v) = sum(solve(remake(p32; p = withp(p32.p, i, v)), alg; dt = 0.01).u[end])
        J64(v) = sum(solve(remake(prob; p = withp(prob.p, i, v)), alg; dt = 0.01).u[end])
        @test isapprox(ForwardDiff.derivative(J32, p32.p[i]), ForwardDiff.derivative(J64, prob.p[i]); rtol = 1.0e-3)
        # the substep count is a policy on the primal values: unchanged under Duals
        @test substep_counts(solve(remake(prob; p = withp(prob.p, i, ForwardDiff.Dual(prob.p[i], 1.0))), alg; dt = 0.01)) ==
            substep_counts(solve(prob, alg; dt = 0.01))
    end
end

@testitem "AD vs FD: ODE path, with an aux field" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "AD vs FD: ODE path, with an aux field" begin
        @variables K(..)
        Kn = K(t, x, y)
        sys = psys(
            [D(ce) ~ Dn * laplacian(ce) - Kn * ce, Kn ~ K0n * (1 + gn)],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [Dn, gn, K0n]; dvs = [ce, Kn]
        )
        ode = discretize(sys, LatticeDiscretization(Grid((8, 4)); T = Float64))
        for s in (Dn, gn, K0n)
            i = pidx(ode.f.sys, s)
            function Jd(v)
                pv = withp(ode.p.values, i, v)
                return sum(
                    solve(
                        remake(ode; p = pv, u0 = eltype(pv).(ode.u0)), Tsit5(); abstol = 1.0e-12,
                        reltol = 1.0e-12
                    ).u[end]
                )
            end
            v0 = ode.p.values[i]
            d = ForwardDiff.derivative(Jd, v0)
            @test isapprox(d, fd(Jd, v0); rtol = 1.0e-6) && d != 0
        end
        # Dual parameters through `remake(; p)` alone (SciMLBase promotes `u0` or the right side
        # runs its Dual variant)
        i = pidx(ode.f.sys, Dn)
        J2(v) = sum(solve(remake(ode; p = withp(ode.p.values, i, v)), Tsit5(); abstol = 1.0e-12, reltol = 1.0e-12).u[end])
        @test isapprox(ForwardDiff.derivative(J2, ode.p.values[i]), fd(J2, ode.p.values[i]); rtol = 1.0e-6)
    end
end

@testitem "Rodas5P (Jacobian and time gradient through the right side)" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "Rodas5P (Jacobian and time gradient through the right side)" begin
        sys = psys(
            [D(ce) ~ Dn * laplacian(ce) - kn * ce + 0.1 * sin(ωn * t)],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [Dn, kn, gn, ωn]
        )
        for T in (Float64, Float32)
            ode = discretize(sys, LatticeDiscretization(Grid((8, 4)); T))
            tol = T == Float64 ? 1.0e-8 : 1.0e-4
            r = solve(ode, Rodas5P(); abstol = tol, reltol = tol)
            ts = solve(ode, Tsit5(); abstol = tol, reltol = tol)
            @test SciMLBase.successful_retcode(r) && eltype(r.u[end]) == T
            @test isapprox(r.u[end], ts.u[end]; rtol = 100tol)
        end
    end
end

@testitem "BigFloat reference (host)" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "BigFloat reference (host)" begin
        sys = nsys()
        alg = ExplicitEuler()
        p64, pb, p32 = owned(sys, 8, 4), owned(sys, 8, 4; T = BigFloat), owned(sys, 8, 4; T = Float32)
        @test eltype(pb) == BigFloat && eltype(pb.u0) == BigFloat
        ib = init(pb, alg; dt = 0.01)
        @test all(a -> eltype(a) == BigFloat, ib.store.flat)
        @test all(b -> all(a -> !(eltype(a) <: AbstractFloat) || eltype(a) == BigFloat, b), ib.store.bufs)
        sb, s64, s32 = solve!(ib), solve(p64, alg; dt = 0.01), solve(p32, alg; dt = 0.01)
        @test eltype(sb.u[end]) == BigFloat
        err(a) = maximum(abs, Float64.(a.u[end]) .- s64.u[end]) / maximum(abs, s64.u[end])
        @test err(sb) <= 1.0e-12
        @test err(s32) >= 1.0e-9                    # negative control: Float32 storage (the old F32 lane)
        # a BigFloat `p` is kept, not cut to Float64; it is rounded once to the compute type
        rb = remake(p64; p = big.(p64.p))
        @test eltype(rb.p) == BigFloat && eltype(rb) == Float64
        @test isapprox(solve(rb, alg; dt = 0.01).u[end], s64.u[end]; rtol = 1.0e-14)
        # an unsupported state type is refused by name
        @test_throws ArgumentError owned(sys, 8, 4; T = Int)
    end
end

@testitem "promotion and plan reuse" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "promotion and plan reuse" begin
        sys = nsys()
        alg = ExplicitEuler()
        p32, p64 = owned(sys, 8, 4; T = Float32), owned(sys, 8, 4; T = Float64)
        up = remake(p32; u0 = Float64.(p32.u0))
        @test eltype(up) == Float64 && up.step !== p32.step
        @test isapprox(solve(up, alg; dt = 0.01).u[end], solve(p64, alg; dt = 0.01).u[end]; rtol = 1.0e-12)
        @test maximum(abs, solve(p32, alg; dt = 0.01).u[end] .- solve(p64, alg; dt = 0.01).u[end]) > 1.0e-9   # control
        # value-only remakes reuse the plans (no emission, no compile); a type comes back cached
        @test remake(p32; p = 2 .* p32.p).step === p32.step
        @test remake(p32; u0 = Float64.(p32.u0)).step === up.step
        # plain Float64 parameters never promote a Float32 state
        @test eltype(remake(p32; p = Float64.(p32.p))) == Float32
        # ODE: a Float32 build solved from a Float64 `u0` computes in Float64 (its own bodies)
        o32 = discretize(sys, LatticeDiscretization(Grid((8, 4)); T = Float32))
        o64 = discretize(sys, LatticeDiscretization(Grid((8, 4)); T = Float64))
        a = solve(remake(o32; u0 = Float64.(o32.u0)), Tsit5(); abstol = 1.0e-12, reltol = 1.0e-12).u[end]
        b = solve(o64, Tsit5(); abstol = 1.0e-12, reltol = 1.0e-12).u[end]
        @test eltype(a) == Float64 && isapprox(a, b; rtol = 1.0e-10)
    end
end

@testitem "SciMLStructures: p is a plain vector (Tunable = the scalars)" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "SciMLStructures: p is a plain vector (Tunable = the scalars)" begin
        prob = owned(nsys(), 8, 4)
        @test SciMLStructures.isscimlstructure(prob.p)
        v, re, _ = SciMLStructures.canonicalize(Tunable(), prob.p)
        @test v == prob.p
        Jθ(θ) = sum(solve(remake(prob; p = SciMLStructures.replace(Tunable(), prob.p, θ)), ExplicitEuler(); dt = 0.01).u[end])
        g = ForwardDiff.gradient(Jθ, v)
        i = pidx(prob, kn)
        @test isapprox(g[i], fd(x -> Jθ(withp(v, i, x)), v[i]); rtol = 1.0e-6)
    end
end

@testitem "hoisted time: sin(ω t) at t = 1e5 in Float32" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "hoisted time: sin(ω t) at t = 1e5 in Float32" begin
        T0 = 1.0e5
        sys = PDESystem(
            [D(ce) ~ sin(ωn * t)], [c(T0, x, y) ~ 0.0, c(t, x, 0) ~ c(t, x, 1), c(t, 0, y) ~ c(t, 1, y)],
            [t ∈ Interval(T0, T0 + 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ce], [ωn]; name = :tt
        )
        alg = ExplicitEuler()
        a = solve(owned(sys, 4, 4; T = Float32), alg; dt = 0.01).u[end][1]
        b = solve(owned(sys, 4, 4; T = Float64), alg; dt = 0.01).u[end][1]
        @test abs(a - b) <= 1.0e-6
        # control: `sin(ω t)` evaluated with `t` in Float32 is off by more than 1e-3 at these times
        @test abs(sin(3.0f0 * Float32(T0 + 0.01)) - sin(3.0 * (T0 + 0.01))) > 1.0e-3
    end
end

# Number types per role. Tables keep their element type (a BigFloat
# table stays BigFloat, a Dual table promotes the problem as a Dual `p` does), BigFloat
# defaults are kept, a Bool input reads back as Bool, and a pair-keyed `remake` infers. The
# comments give the base (c2583722) value of each.
@testitem "number types per role" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "number types per role" begin
        @parameters Dt[1:2] = [0.5, 1.0] Dq = 0.1
        tsys = ssys([D(ce) ~ Dq * laplacian(ce) - value_at(Dt, qe) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dq, Dt])
        K = Int32[i <= 2 ? 1 : 2 for i in 1:4, j in 1:4]
        p = sown(tsys; inputs = [qe => K])
        alg = ExplicitEuler()
        third = big"1" / 3
        @testset "a BigFloat table survives remake" begin
            # base: the table became a Vector{Float64} (Float64(1/3))
            rb = remake(p; p = [Dt => [third, big"1.0"]])
            @test eltype(last(only(rb.tables))) == BigFloat && last(only(rb.tables))[1] == third
            @test getp(rb, Dt)(rb)[1] == third
            @test eltype(rb) == Float64                   # rounded once to the compute type of a Float64 state
            @test isapprox(solve(rb, alg; dt = 0.1).u[end], solve(remake(p; p = [Dt => [1 / 3, 1.0]]), alg; dt = 0.1).u[end]; rtol = 1.0e-14)
            # on a BigFloat state the store's table holds the value exactly (base: Float64(1/3))
            pb = discretize(tsys, LatticeDiscretization(Grid((4, 4)); T = BigFloat); inputs = [qe => K])
            ib = init(remake(pb; p = [Dt => [third, big"1.0"]]), alg; dt = 0.1)
            @test eltype(ib.store.tables[1]) == BigFloat && ib.store.tables[1][1] == third
            @test ib.ps[Dt][1] == third                      # the integrator's own copy keeps it
            # an integrator table write converts into the integrator's table type
            ig = init(p, alg; dt = 0.1)
            ig.ps[Dt] = [third, 1]
            @test ig.ps[Dt] == [Float64(third), 1.0] && eltype(ig.ps[Dt]) == Float64
        end
        @testset "a Dual table promotes the problem; ForwardDiff through remake and solve" begin
            # base: `Float64.(…)` of a Dual table threw (MethodError)
            dv = ForwardDiff.Dual(0.5, 1.0)
            rd = remake(p; p = [Dt => [dv, one(dv)]])
            @test eltype(rd) <: ForwardDiff.Dual && eltype(last(only(rd.tables))) <: ForwardDiff.Dual
            J(v) = sum(solve(remake(p; p = [Dt => [v, one(v)]]), alg; dt = 0.1).u[end])
            d = ForwardDiff.derivative(J, 0.5)
            @test d isa Float64 && d != 0 && isapprox(d, fd(J, 0.5); rtol = 1.0e-6)
            # control: the derivative of the entry that no site reads is 0
            J2(v) = sum(solve(remake(p; p = [Dt => [0.5, v]]), alg; dt = 0.1).u[end])
            @test ForwardDiff.derivative(J2, 1.0) != 0                       # kind 2 is read
            Jn(v) = sum(solve(remake(sown(tsys; inputs = [qe => fill(Int32(1), 4, 4)]); p = [Dt => [0.5, v]]), alg; dt = 0.1).u[end])
            @test ForwardDiff.derivative(Jn, 1.0) == 0                       # no site of kind 2
            # a Dual written into a Float64 integrator's table is refused with the route
            ig = init(p, alg; dt = 0.1)
            @test_throws ArgumentError (ig.ps[Dt] = [dv, one(dv)])
            @test ig.ps[Dt] == [0.5, 1.0]                                       # unchanged
        end
        @testset "a Bool input reads back as Bool" begin
            # base: a `UInt8` array (`any`/`count` threw a non-boolean TypeError, `.!` a MethodError)
            dsys = ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, de], Num[])
            half = [i <= 2 for i in 1:4, j in 1:4]
            ig = init(sown(dsys; domain = dm, inputs = [dm => half]), alg; dt = 0.1)
            m = ig[dm]
            @test eltype(m) == Bool && m == half
            @test any(m) && !all(m) && count(m) == 8 && (.!m) == .!half
            # an integer input keeps its type
            @test eltype(init(p, alg; dt = 0.1)[qe]) == Int32
        end
        @testset "a pair-keyed remake infers" begin
            # base: an abstract `FieldProblem` (`rest = Pair[]`, a promotion over the values)
            r1 = @inferred remake(p; p = [Dt => [0.25, 1.0]])
            r2 = @inferred remake(p; p = [Dq => 2.0])
            @test getp(r1, Dt)(r1) == [0.25, 1.0] && r2.p[pidx(r2, Dq)] == 2.0
            # a plain value is written into the problem's parameter type; a Dual promotes it
            @test eltype(remake(p; p = [Dq => big"2.0"]).p) == Float64 && eltype(remake(p; p = [Dq => 2]).p) == Float64
            @test eltype(remake(p; p = [Dq => ForwardDiff.Dual(2.0, 1.0)]).p) <: ForwardDiff.Dual
            # a mixed list (abstract pair type) still works, decided by the values
            r3 = remake(p; p = Pair[Dt => [0.25, 1.0], Dq => 2.0])
            @test getp(r3, Dt)(r3) == [0.25, 1.0] && r3.p[pidx(r3, Dq)] == 2.0
        end
        @testset "BigFloat defaults are kept (SD-03)" begin
            # base: `_default` returned Float64(v): p = [0.3333333333333333]
            @parameters Db = big"1" / 3
            bsys = ssys([D(ce) ~ Db * laplacian(ce)], [c(0, x, y) ~ 1.0], [ce], [Db])
            pbb = discretize(bsys, LatticeDiscretization(Grid((4, 4)); T = BigFloat))
            @test eltype(pbb.p) == BigFloat && pbb.p.values[1] == big"1" / 3
            @test eltype(solve(pbb, ExplicitEuler(); dt = 0.01).u[end]) == BigFloat
            # Float64 defaults stay a Float64 vector
            @test eltype(sown(tsys; inputs = [qe => K]).p) == Float64
        end
    end
end

# Number types per role. A field's declared `lattice_storage`
# holds its own type whatever the problem's (an aux field here: a `FieldProblem`'s state is
# one vector, so its state fields are stored in T and a different declared storage is refused
# in words); `compute_T` compiles a group's kernels in a wider type than its storage; Duals
# keep their partials through a declared storage. Base f5641ce1: `compute_T` is no keyword, a
# declared Float64 storage holds the problem's Float32, so every test fails or errors.
@testitem "lattice_storage, compute_type and solver_type in B" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "lattice_storage, compute_type and solver_type in B" begin
        @parameters kw = 0.25
        @variables wu(..) wK(..) [lattice_storage = Float64] wh(..) [lattice_storage = Float16] wc(..) [lattice_storage = Float64]
        wue, wKe, whe, wce = wu(t, x, y), wK(t, x, y), wh(t, x, y), wc(t, x, y)
        wdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        wsys = PDESystem(
            [wKe ~ 2 * wue, whe ~ wue / 2, D(wue) ~ 0.0625 * laplacian(wue) - kw * wKe], [wu(0, x, y) ~ x * y], wdom, [t, x, y],
            [wue, wKe, whe], [kw]; name = :w
        )
        wd(T) = discretize(wsys, LatticeDiscretization(Grid((16, 16)); T))
        run(T, alg; dt) = (i = init(wd(T), alg; dt); step!(i); i)
        # the stores have the declared types: the state in T, the aux fields in their own
        for T in (Float32, Float64)
            i = run(T, ExplicitEuler(); dt = 0.05)
            @test eltype(i[wue]) == T && eltype(i[wKe]) == Float64 && eltype(i[whe]) == Float16
        end
        # a state field whose declared storage differs from T keeps it on the owned path (each
        # state field has its own arrays), and equals the all-Float64 run: a
        # Float64 field on a Float32 problem; a Float16 and a Float64 field beside a T field
        csys = PDESystem([D(wce) ~ 0.0625 * laplacian(wce) - 0.125 * wce], [wc(0, x, y) ~ x], wdom, [t, x, y], [wce], Any[]; name = :w)
        c32 = solve(
            discretize(csys, LatticeDiscretization(Grid((8, 8)); T = Float32)),
            ExplicitEuler(; compute_type = Float64)
            ; dt = 0.05
        )
        @variables wc64(..)
        c64 = solve(
            discretize(
                PDESystem(
                    [D(wc64(t, x, y)) ~ 0.0625 * laplacian(wc64(t, x, y)) - 0.125 * wc64(t, x, y)], [wc64(0, x, y) ~ x],
                    wdom, [t, x, y], [wc64(t, x, y)], Any[]; name = :w
                ), LatticeDiscretization(Grid((8, 8)); T = Float64)
            ),
            ExplicitEuler()
            ; dt = 0.05
        )
        @test eltype(c32.u[end]) == Float64 && c32.u[end] == c64.u[end]
        msys = PDESystem(
            [
                D(wue) ~ 0.0625 * laplacian(wue) - 0.5 * wue + 0.25 * wce, D(whe) ~ 0.0625 * laplacian(whe) - 0.125 * whe,
                D(wce) ~ 0.0625 * laplacian(wce) - 0.125 * wce,
            ], [wu(0, x, y) ~ 0.0, wh(0, x, y) ~ x, wc(0, x, y) ~ y], wdom, [t, x, y],
            [wue, whe, wce], Any[]; name = :m
        )
        pm = discretize(msys, LatticeDiscretization(Grid((8, 8)); T = Float32))
        im = init(pm, ExplicitEuler(); dt = 0.05)
        step!(im)
        @test eltype(im[wue]) == Float32 && eltype(im[whe]) == Float16 && eltype(im[wce]) == Float64
        sm = solve(pm, BackwardEuler(); dt = 0.05)
        @test SciMLBase.successful_retcode(sm.retcode) && eltype(sm.u[end]) == Float64     # (the saves: their promotion)
        @test sm[wce, end] ≈ solve(remake(pm), ExplicitEuler(); dt = 0.05)[wce, end] rtol = 1.0e-2
        # a write and `reinit!` reach each field in its own type
        im[wce] = fill(0.25, 8, 8)
        @test im[wce] == fill(0.25, 8, 8) && eltype(im[wce]) == Float64
        SciMLBase.reinit!(im)
        i0 = init(pm, ExplicitEuler(); dt = 0.05)
        @test im[whe] == i0[whe] && im[wce] == i0[wce] && im[wue] == i0[wue]
        # an OrdinaryDiffEq solver's state is one vector of T: refused there, with the route
        # (at the solve, the field algorithms take the same problem)
        e = try
            solve(discretize(csys, LatticeDiscretization(Grid((8, 8)); T = Float32)), Tsit5())
            ""
        catch err
            sprint(showerror, err)
        end
        @test occursin("`lattice_storage = Float64` differs from the state's number type Float32", e) &&
            occursin("solve with a field algorithm", e)
        # compute_T: a rate `max(a, u) − b` with `a = 1 + 2⁻²⁵`, `b = 1` is 0 in Float32 (`a` rounds
        # to 1; `max` keeps the host from deriving `a − b` in Float64) and 2⁻²⁵ in Float64: computed in Float64, a Float32 problem follows the Float64 run (to its
        # storage's rounding); computed in Float32 (the control) it stays at 0
        @parameters za = 1 + 2.0^-25 zb = 1.0
        @variables zu(..)
        zue = zu(t, x, y)
        zsys = PDESystem([D(zue) ~ max(za, zue) - zb], [zu(0, x, y) ~ 0.0], wdom, [t, x, y], [zue], [za, zb]; name = :z)
        zrun(T, alg) = (i = init(discretize(zsys, LatticeDiscretization(Grid((4, 4)); T)), alg; dt = 0.5); step!(i); i[zue])
        for (a32, a64) in (
                (ExplicitEuler(), ExplicitEuler(; compute_type = Float64)),
                (BackwardEuler(), BackwardEuler(; compute_type = Float64, solver_type = Float64)),
            )
            ref = zrun(Float64, a32)
            lo, hi = zrun(Float32, a32), zrun(Float32, a64)
            @test all(iszero, lo) && eltype(hi) == Float32                 # the storage stays T
            @test all(>(0), ref) && maximum(abs, Float64.(hi) .- ref) <= 1.0e-7 * maximum(ref)
        end
        # solver_type: the solver's own type, whatever compute_type
        ig = init(wd(Float32), BackwardEuler(; solver_type = Float64); dt = 0.05)
        @test only(only(ig.runtimes).cache.rows).solver.T == Float64
        # Duals flow through a declared storage: an aux field stored in Float32 on a Float64
        # problem holds Dual{…, Float32} under a Dual parameter, and ∂J/∂k agrees with differences
        @variables wK32(..) [lattice_storage = Float32]
        wK32e = wK32(t, x, y)
        dsys = PDESystem(
            [wK32e ~ 2 * wue, D(wue) ~ 0.0625 * laplacian(wue) - kw * wK32e], [wu(0, x, y) ~ x * y], wdom, [t, x, y],
            [wue, wK32e], [kw]; name = :d
        )
        pd = discretize(dsys, LatticeDiscretization(Grid((8, 8)); T = Float64))
        @variables wK64(..)
        wK64e = wK64(t, x, y)
        pr = discretize(
            PDESystem(
                [wK64e ~ 2 * wue, D(wue) ~ 0.0625 * laplacian(wue) - kw * wK64e], [wu(0, x, y) ~ x * y], wdom, [t, x, y],
                [wue, wK64e], [kw]; name = :d
            ), LatticeDiscretization(Grid((8, 8)); T = Float64)
        )
        J(q, v) = sum(solve(remake(q; p = [kw => v]), ExplicitEuler(); dt = 0.05).u[end])
        d, dref = ForwardDiff.derivative(v -> J(pd, v), 0.25), ForwardDiff.derivative(v -> J(pr, v), 0.25)
        @test d != 0 && d != dref && isapprox(d, dref; rtol = 1.0e-5)     # (the aux field's Float32 rounding)
        iz = init(remake(pd; p = [kw => ForwardDiff.Dual(0.25, 1.0)]), ExplicitEuler(); dt = 0.05)
        @test ForwardDiff.valtype(eltype(iz[wK32e])) == Float32
        # the canonical text: `compute_type = :auto` is left out, a type is printed
        LFP = LatticePDE.Problems
        @test occursin("compute_type=Float64", LFP.canonical(BackwardEuler(; compute_type = Float64))) &&
            !occursin("compute_type", LFP.canonical(BackwardEuler()))
        @test LFP.canonical(ExplicitEuler(; compute_type = Float64)) != LFP.canonical(ExplicitEuler())
        # the cache key: independently built equal algorithms print one canonical text, a difference in
        # any field shows, and the key is not the display form (the key names every field, `repr` leaves
        # a default out). Each row: two separately built objects, a third that differs in one field, and
        # whether a default exists to leave out of the display
        canon_cases = Any[
            (ExplicitEuler(), ExplicitEuler(), ExplicitEuler(; substeps = 3), true),
            (ExplicitMap(), ExplicitMap(), ExplicitMap(; compute_type = Float64), false),
            (BackwardEuler(), BackwardEuler(), BackwardEuler(; substeps = 2), true),
            (LatticeNewton(), LatticeNewton(), LatticeNewton(; max_iter = 3), true),
            (CrankNicolson(), CrankNicolson(), CrankNicolson(; nlsolve = LatticeNewton(; max_iter = 2)), true),
            (BDF2(), BDF2(), BDF2(; substeps = 2), true),
            (QuasiSteady(), QuasiSteady(), QuasiSteady(; linsolve = LatticeGMRES()), true),
            (LatticePCG(), LatticePCG(), LatticePCG(; maxiters = 3), true),
            (LatticeMultigrid(), LatticeMultigrid(), LatticeMultigrid(; cycles = 3), true),
            (LatticeGMRES(), LatticeGMRES(), LatticeGMRES(; gmres_restart = 8), true),
        ]
        for (a, b, c, hasdefaults) in canon_cases
            @test isequal(a, b) && LFP.canonical(a) == LFP.canonical(b)
            @test !isequal(a, c) && LFP.canonical(a) != LFP.canonical(c)
            hasdefaults && @test LFP.canonical(a) != repr(a)
        end
        @test LFP.canonical(LatticePDE.VCycle(2, 2)) == LFP.canonical(LatticePDE.VCycle(2, 2)) &&
            LFP.canonical(LatticePDE.VCycle(2, 2)) != LFP.canonical(LatticePDE.VCycle(3, 3))
        # a compute type that is not one is refused, naming the keyword
        e = try
            ExplicitEuler(; compute_type = Int)
            ""
        catch err
            sprint(showerror, err)
        end
        @test occursin("`compute_type` takes `:auto` (the problem's value type), `Float32` or `Float64`", e)
    end
end

# A field stored in Float16 under the implicit algorithms is solved in the
# state's value type (its residual held there; each update rounds once to Float16), with any
# `compute_T`; accurate to its storage against the Float64 run. Base 97045a1b:
# refused, "an implicit solve runs in Float32 or Float64".
@testitem "Float16 storage under the implicit algorithms" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "Float16 storage under the implicit algorithms" begin
        @variables sh(..) [lattice_storage = Float16] s64(..)
        she, s64e = sh(t, x, y), s64(t, x, y)
        sdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        function mk(v, T)
            f = v === she ? sh : s64
            return discretize(
                PDESystem(
                    [D(v) ~ 0.0625 * laplacian(v) - 0.5 * v], [f(0, x, y) ~ x * y + 0.5],
                    sdom, [t, x, y], [v], Any[]; name = :s
                ), LatticeDiscretization(Grid((16, 16)); T)
            )
        end
        ref = solve(mk(s64e, Float64), BackwardEuler(); dt = 0.1).u[end]
        for T in (Float32, Float64), alg in (
                    BackwardEuler(), BackwardEuler(; compute_type = Float64),
                    CrankNicolson(), BDF2(),
                )
            T == Float64 && alg isa BackwardEuler && alg.compute_type === Float64 && continue
            s = solve(mk(she, T), alg; dt = 0.1)
            @test SciMLBase.successful_retcode(s.retcode) && eltype(s.u[end]) == Float16
            r = alg isa BackwardEuler ? ref : solve(mk(s64e, Float64), typeof(alg).name.wrapper(); dt = 0.1).u[end]
            @test maximum(abs, Float64.(s.u[end]) .- r) <= 4.0e-3 * maximum(abs, r)      # (Float16: eps 9.8e-4)
        end
        @test SciMLBase.successful_retcode(solve(mk(she, Float32), QuasiSteady(); dt = 0.1).retcode)
        # a Dual state under an implicit solve (refused before): ∂ sum(u(t))/∂s of the start
        # `s u0` runs, the tangent against central differences
        pr = mk(s64e, Float64)
        Js(v) = sum(solve(remake(pr; u0 = v .* pr.u0), BackwardEuler(); dt = 0.1).u[end])
        @test isapprox(ForwardDiff.derivative(Js, 1.0), fd(Js, 1.0); rtol = 1.0e-7)
    end
end

@testitem "∂u/∂k through BackwardEuler, CrankNicolson, BDF2 and QuasiSteady" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "∂u/∂k through BackwardEuler, CrankNicolson, BDF2 and QuasiSteady" begin
        bcs = [c(0, x, y) ~ x * y, c(t, 0, y) ~ gt]
        lin = town(tsys([D(ce) ~ Dt * laplacian(ce) - kt * ce + gt * x], bcs))
        for alg in (BackwardEuler(; linsolve = TTIGHT), CrankNicolson(; linsolve = TTIGHT), BDF2(; linsolve = TTIGHT))
            for s in (kt, Dt, gt)
                @test tok(tad(lin, alg, s; dt = 0.1)...)
            end
        end
        qs = town(tsys([0 ~ Dt * laplacian(ce) - kt * ce + gt * x], bcs))
        for s in (kt, Dt, gt)
            @test tok(tad(qs, QuasiSteady(; linsolve = TTIGHT), s; dt = 0.1)...)
        end
        # the values of a Dual run are the primal run's, bit for bit (the primal solve is the run's)
        i = pidx(lin, Dt)
        sd = solve(remake(lin; p = withp(lin.p, i, ForwardDiff.Dual(lin.p[i], 1.0))), BackwardEuler(); dt = 0.1)
        @test ForwardDiff.value.(sd.u[end]) == solve(lin, BackwardEuler(); dt = 0.1).u[end]
    end
end

@testitem "a mask and a Robin face; a nonlinear term; a hexagonal lattice; the coupled steady solve" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "a mask and a Robin face; a nonlinear term; a hexagonal lattice; the coupled steady solve" begin
        # the mask's value and the Robin face's β read k
        mr = town(
            tsys(
                [D(ce) ~ Dt * laplacian(ce) - 0.5 * ce + gt], [
                    c(0, x, y) ~ 0.2 + x,
                    ce ~ masked((x > 0.4) & (x < 0.6) & (y > 0.4) & (y < 0.6), 2 * kt), 1.5 * c(t, x, 0) - kt * Differential(y)(c(t, x, 0)) ~ 0.2,
                ]
            ), (10, 10)
        )
        for s in (kt, Dt, gt)
            @test tok(tad(mr, BackwardEuler(; linsolve = TTIGHT), s; dt = 0.1)...)
        end
        # `−k c²`: with `nlsolve = LatticeNewton(; max_iter = 8)` the run converges each stage, and its derivatives are the tangent's;
        # by default one unchecked Newton step does not solve the stage, which is warned
        nl = town(tsys([D(ce) ~ Dt * laplacian(ce) - kt * ce^2 + gt], [c(0, x, y) ~ 0.2 + x]), (10, 10))
        for s in (kt, Dt)
            let (ad_v, fd_v) = tad(nl, BackwardEuler(; linsolve = TTIGHT, nlsolve = LatticeNewton(; max_iter = 8)), s; dt = 0.1)
                @test isapprox(ad_v, fd_v; rtol = 1.0e-5) && ad_v != 0
            end
            @test tok(tad(nl, BackwardEuler(; linsolve = TTIGHT, nlsolve = LatticeNewton(; κ = 1.0e-5, max_iter = 12)), s; dt = 0.1)...)
        end
        i = pidx(nl, kt)
        @test_logs (:warn, r"derivative parts are those of each stage's solution") match_mode = :any solve(
            remake(nl; p = withp(nl.p, i, ForwardDiff.Dual(nl.p[i], 1.0))), BackwardEuler()
            ; dt = 0.1
        )
        hx = town(
            tsys([D(ce) ~ Dt * laplacian(ce) - kt * ce + gt * x], [c(0, x, y) ~ x * y, c(t, 0, y) ~ gt]), (8, 8);
            geometry = LatticeFields.IR.HEX
        )
        for s in (kt, Dt)
            @test tok(tad(hx, BackwardEuler(; linsolve = TTIGHT), s; dt = 0.1)...)
        end
        # A write to the parameter a mask's value reads (`2k`), then windows: equal to a restart
        # at the write, and the tangent after it against central differences. Base (79af8c69): the
        # implicit update kept the old value (Σu off), and the tangent disagreed with the run
        function wrun(v)
            i = pidx(mr, Dt)
            ig = init(remake(mr; p = withp(mr.p, i, v)), BackwardEuler(; linsolve = TTIGHT); dt = 0.1)
            step!(ig)
            u1 = copy(vec(ig[ce]))
            ig.ps[kt] = 0.8
            step!(ig); step!(ig)
            return vec(ig[ce]), u1
        end
        uw, u1 = wrun(mr.p[pidx(mr, Dt)])
        ir = init(remake(mr; u0 = u1, p = withp(mr.p, pidx(mr, kt), 0.8)), BackwardEuler(; linsolve = TTIGHT); dt = 0.1)
        step!(ir); step!(ir)
        @test any(==(1.6), uw) && maximum(abs, uw .- vec(ir[ce])) < 1.0e-12
        Jw(v) = sum(first(wrun(v)))
        @test tok(ForwardDiff.derivative(Jw, mr.p[pidx(mr, Dt)]), fd(Jw, mr.p[pidx(mr, Dt)]; h = 1.0e-5))
        # a coupled steady pair: one FGMRES per derivative part
        cp = town(
            tsys(
                [0 ~ Dt * laplacian(tae) - tae + kt * tbe + x, 0 ~ 0.1 * laplacian(tbe) - tbe - gt * tae + y],
                [ta(0, x, y) ~ 0.0, tb(0, x, y) ~ 0.0]; dvs = [tae, tbe]
            )
        )
        for s in (kt, Dt, gt)
            @test tok(tad(cp, QuasiSteady(; linsolve = LatticeGMRES(; reltol = 1.0e-12)), s; out = sol -> sol[tae, end] .^ 2, dt = 0.1)...)   # (a sum of `a` alone does not see D: zero flux)
        end
    end
end

# A declared storage on a row whose operator varies by site (a field row: a face coefficient of
# the coordinates). Its `jac:` site values are in the row's solve type: a declared Float32 or
# Float64 storage's own, a Float16 field's the problem's type.
# Before the fix (85794414): every case errors ("`inputs`: `w1` holds Float64
# values; this solver's state type is `Float32`", and the Float16 and Float64 forms).
@testitem "a declared storage on a field row under the implicit algorithms" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "a declared storage on a field row under the implicit algorithms" begin
        @variables sfr(..) sfr32(..) [lattice_storage = Float32] sfr16(..) [lattice_storage = Float16] sfr64(..) [lattice_storage = Float64]
        sdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        function mk(f, T)
            return discretize(
                PDESystem(
                    [D(f(t, x, y)) ~ 0.02 * DivKGrad(:harmonic)(1 + x, f(t, x, y)) - f(t, x, y) + 0.5 * y],
                    [f(0, x, y) ~ x * y + 0.5], sdom, [t, x, y], [f(t, x, y)], Any[]; name = :s
                ), LatticeDiscretization(Grid((8, 8)); T)
            )
        end
        for (f, S, T, tol) in ((sfr32, Float32, Float64, 1.0e-5), (sfr16, Float16, Float32, 4.0e-3), (sfr64, Float64, Float32, 1.0e-5))
            for alg in (BackwardEuler(), CrankNicolson(), BDF2(), QuasiSteady())
                r = solve(mk(sfr, Float64), alg; dt = 0.05)[sfr(t, x, y), 2]
                s = solve(mk(f, T), alg; dt = 0.05)
                @test SciMLBase.successful_retcode(s.retcode) && eltype(s[f(t, x, y), 2]) == S
                @test maximum(abs, Float64.(s[f(t, x, y), 2]) .- r) <= tol * maximum(abs, r)
            end
        end
    end
end

@testitem "Float64 on a backend without it; the registry's keys" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using .LP_numbers: fd
    @testset "Float64 on a backend without it; the registry's keys" begin
        LFP = LatticePDE.Problems
        @variables nw(..) [lattice_storage = Float64] nv(..)
        nwe, nve = nw(t, x, y), nv(t, x, y)
        ndom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        function emsg(f)
            return try
                f(); ""
            catch err
                sprint(showerror, err)
            end
        end
        pw = discretize(
            PDESystem([D(nwe) ~ laplacian(nwe)], [nw(0, x, y) ~ x], ndom, [t, x, y], [nwe], Any[]; name = :n),
            LatticeDiscretization(Grid((8, 8)); T = Float32)
        )
        pv = discretize(
            PDESystem([D(nve) ~ laplacian(nve)], [nv(0, x, y) ~ x], ndom, [t, x, y], [nve], Any[]; name = :n),
            LatticeDiscretization(Grid((8, 8)); T = Float32)
        )
        nb = NoF64Backend()
        @test_throws ArgumentError LFP.check_backend_float64(LFP.field_problem(pw).program, ExplicitEuler(), nb, Float32; fields = ["nw"])
        @test_throws ArgumentError LFP.check_backend_float64(LFP.field_problem(pv).program, BackwardEuler(; compute_type = Float64), nb, Float32; fields = ["nv"])
        @test_throws ArgumentError LFP.check_backend_float64(LFP.field_problem(pv).program, BackwardEuler(; solver_type = Float64), nb, Float32; fields = ["nv"])
        # nothing declared, or a backend with Float64: no refusal
        @test LFP.check_backend_float64(LFP.field_problem(pv).program, BackwardEuler(), nb, Float32; fields = ["nv"]) === nothing
        @test LFP.check_backend_float64(LFP.field_problem(pw).program, ExplicitEuler(), LatticeFields.Exec.KernelAbstractions.CPU(), Float32) === nothing
        # N4: a store holding Float64 on such a backend registers its generic bodies by a Float64
        # device array; the same body over Float32 arrays with a Float64 scalar is not skipped
        Ex = LatticeFields.Exec
        saved = copy(Ex.FLOAT64_KERNELS)
        empty!(Ex.FLOAT64_KERNELS)
        LFP._register_float64_store!(nb, [Any[zeros(Float64, 4)]])
        clip = string(typeof(LFP._clip_body!))
        # (the signature text as the scan prints it: a 1D device array by its alias, GROUP=GPU at c319fdba
        # flagged 9 registered bodies keyed on `DeviceArray{Float64,`)
        @test Ex.float64_registered("Tuple{kernel, $clip, AMDGPU.Device.ROCDeviceVector{Float64, 1}, Float64}")
        @test Ex.float64_registered("Tuple{kernel, $clip, ROCDeviceArray{Float64, 3, 1}, Float64}")
        @test !Ex.float64_registered("Tuple{kernel, $clip, AMDGPU.Device.ROCDeviceVector{Float32, 1}, Float64}")
        @test !Ex.float64_registered("Tuple{kernel, $clip, ROCDeviceArray{Float32, 1, 1}, Float64}")
        empty!(Ex.FLOAT64_KERNELS)
        union!(Ex.FLOAT64_KERNELS, saved)
    end
end

@testitem "time and tolerance types: Float32 and BigFloat time spans keep their type" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    using OrdinaryDiffEqTsit5: Tsit5
    sys64 = nsys()
    ref = solve(LFP.field_problem(discretize(sys64, LatticeDiscretization(Grid((8, 4))); tspan = (0.0, 1.0))), ExplicitEuler(); dt = 0.1)
    for TT in (Float32, BigFloat)
        # the span from `tspan` and from the system's own time domain
        span = (TT(0), TT(1))
        disc = LatticeDiscretization(Grid((8, 4)))
        sysT = PDESystem(
            sys64.eqs, sys64.bcs, [t ∈ Interval(span...), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
            [t, x, y], [ce], [Dn, kn, gn]; name = :p
        )
        for prob in (discretize(sys64, disc; tspan = span), discretize(sysT, disc))
            @test prob.tspan isa Tuple{TT, TT}
            fp = LFP.field_problem(prob)
            @test fp.tspan isa Tuple{TT, TT}
            sol = solve(fp, ExplicitEuler(); dt = TT(0.1))
            @test eltype(sol.t) === TT && sol.t ≈ ref.t
            @test sol.u[end] ≈ ref.u[end]
            # the implicit steppers with tolerances of the type
            solb = solve(fp, BackwardEuler(; nlsolve = LatticeNewton()); dt = TT(0.25), abstol = TT(1.0e-8), reltol = TT(1.0e-6), saveat = TT(0.5))
            @test eltype(solb.t) === TT && solb.t ≈ [0, 0.5, 1]
            integ = init(fp, ExplicitEuler(); dt = TT(0.1))
            step!(integ)
            @test integ.t isa TT && integ.t ≈ 0.1
        end
        # the OrdinaryDiffEq path: an `ODEProblem` over the span in its type
        op = discretize(sys64, disc; tspan = span)
        @test eltype(solve(op, Tsit5(); abstol = TT(1.0e-8), reltol = TT(1.0e-6)).t) === TT
    end
    # control: an integer span is promoted to a float type, as SciML does
    @test LFP.field_problem(discretize(sys64, LatticeDiscretization(Grid((8, 4))); tspan = (0, 1))).tspan === (0.0, 1.0)
end

@testitem "time types: a Float32 span through sol(t), reinit!, add_tstop! and step!(integ, dt, true)" setup = [LP_numbers] tags = [:latticepde, :numbers] begin
    sys = nsys()
    fp = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((8, 4))); tspan = (0.0f0, 1.0f0)))
    ref = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((8, 4))); tspan = (0.0, 1.0)))
    sol, sol64 = solve(fp, ExplicitEuler(); dt = 0.1f0), solve(ref, ExplicitEuler(); dt = 0.1)
    # interpolation at a time between saves, in the span's type
    @test sol(0.35f0) ≈ sol64(0.35) rtol = 1.0e-6     # (the times round to Float32)
    # a tstop off the window grid is landed on exactly, in Float32
    integ = init(fp, ExplicitEuler(); dt = 0.1f0)
    SciMLBase.add_tstop!(integ, 0.25f0)
    step!(integ); step!(integ); step!(integ)
    @test integ.t === 0.25f0
    # step!(integ, dt, true) lands on t + dt
    step!(integ, 0.13f0, true)
    @test integ.t === 0.25f0 + 0.13f0
    # reinit! over a new span keeps the type and runs it
    SciMLBase.reinit!(integ; t0 = 0.5f0, tf = 0.75f0)
    @test integ.t === 0.5f0
    solve!(integ)
    @test integ.t === 0.75f0 && eltype(integ.sol.t) === Float32
end
