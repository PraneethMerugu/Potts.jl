# `discretize` takes a field's
# default `@variables c(..) = v` as its initial value when no condition `c(0, …) ~ v` gives one;
# with both, the condition wins (as the coupling into a model does). Oracles: the same system
# with the value written as a condition (bitwise, owned path and Tsit5), and a Dual default's
# derivative against central differences. Negative control (the base 4ca38af7): every testset
# fails, "field `dfc` has no initial condition `dfc(0, …) ~ value`".

@testsetup module LP_fielddefaults
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
using OrdinaryDiffEqTsit5: Tsit5
using ForwardDiff: ForwardDiff

@parameters dfD = 0.2 dfk = 0.5
@variables dfc(..) = 0.3 dfn(..) dfa(..) = 7.0
dfdom = [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
dfdisc() = LatticeDiscretization(Grid((8, 8)); T = Float64)
# `dfc` decays and diffuses from its default; `dfa` is an aux field (its default is unused)
function dfsys(bcs = []; name = :df)
    return PDESystem(
        [D(dfc(t, x, y)) ~ dfD * laplacian(dfc(t, x, y)) - dfk * dfc(t, x, y) + 0.1 * x],
        bcs, dfdom, [t, x, y], [dfc(t, x, y)], [dfD, dfk]; name
    )
end
function dfmsg(f)
    return try
        f()
        "built"
    catch e
        sprint(showerror, e)
    end
end
include("shared/export_all.jl")
end

@testitem "a field's default is its initial value (owned path and Tsit5)" setup = [LP_fielddefaults] tags = [:latticepde, :fielddefaults] begin
    @testset "a field's default is its initial value (owned path and Tsit5)" begin
        pd = discretize(dfsys(), dfdisc())
        pc = discretize(dfsys([dfc(0, x, y) ~ 0.3]), dfdisc())
        @test pd.u0 == pc.u0 && all(==(0.3), pd.u0)
        a, b = solve(pd, ExplicitEuler(); dt = 1.0e-3), solve(pc, ExplicitEuler(); dt = 1.0e-3)
        @test a.u[end] == b.u[end] && maximum(abs, a.u[end] .- 0.3) > 1.0e-3       # bitwise; the field moved
        o1 = solve(pd, Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10)
        o2 = solve(pc, Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10)
        @test SciMLBase.successful_retcode(o1) && o1.u[end] == o2.u[end]
        @test maximum(abs, o1.u[end] .- a.u[end]) < 1.0e-3                         # the ODE path agrees
        # an aux field's default is not an initial value (it has none); the run is unchanged
        sa = PDESystem(
            [
                D(dfc(t, x, y)) ~ dfD * laplacian(dfc(t, x, y)) - dfk * dfc(t, x, y) + 0.1 * dfa(t, x, y),
                dfa(t, x, y) ~ x,
            ], [], dfdom, [t, x, y], [dfc(t, x, y), dfa(t, x, y)], [dfD, dfk]; name = :dfa
        )
        pa = discretize(sa, dfdisc())
        @test pa.u0 == pd.u0 && isapprox(solve(pa, ExplicitEuler(); dt = 1.0e-3).u[end], a.u[end]; rtol = 1.0e-12)
    end
end

@testitem "with a default and a condition, the condition wins" setup = [LP_fielddefaults] tags = [:latticepde, :fielddefaults] begin
    @testset "with a default and a condition, the condition wins" begin
        p = discretize(dfsys([dfc(0, x, y) ~ x]), dfdisc())
        q = discretize(
            PDESystem(
                [D(dfn(t, x, y)) ~ dfD * laplacian(dfn(t, x, y)) - dfk * dfn(t, x, y) + 0.1 * x],
                [dfn(0, x, y) ~ x], dfdom, [t, x, y], [dfn(t, x, y)], [dfD, dfk]; name = :dfn
            ), dfdisc()
        )
        @test p.u0 == q.u0 && !any(==(0.3), p.u0)
        @test solve(p, ExplicitEuler(); dt = 1.0e-3).u[end] == solve(q, ExplicitEuler(); dt = 1.0e-3).u[end]
        @test solve(p, Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10).u[end] == solve(q, Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10).u[end]
        # `initial_conditions` over the default too
        r = discretize(
            PDESystem(
                [D(dfc(t, x, y)) ~ dfD * laplacian(dfc(t, x, y)) - dfk * dfc(t, x, y) + 0.1 * x], [], dfdom,
                [t, x, y], [dfc(t, x, y)], [dfD, dfk]; name = :dfi, initial_conditions = Dict(dfc(t, x, y) => 0.9)
            ), dfdisc()
        )
        @test all(==(0.9), r.u0)
        # a field with no value at all is still refused
        @test_throws ArgumentError discretize(
            PDESystem(
                [D(dfn(t, x, y)) ~ -dfn(t, x, y)], [], dfdom, [t, x, y], [dfn(t, x, y)], Num[];
                name = :dfz
            ), dfdisc()
        )
    end
end

@testitem "a Dual default: the derivative against central differences" setup = [LP_fielddefaults] tags = [:latticepde, :fielddefaults] begin
    @testset "a Dual default: the derivative against central differences" begin
        function J(v)
            @variables dfv(..) = v
            s = PDESystem(
                [D(dfv(t, x, y)) ~ dfD * laplacian(dfv(t, x, y)) - dfk * dfv(t, x, y) * dfv(t, x, y)], [], dfdom, [t, x, y],
                [dfv(t, x, y)], [dfD, dfk]; name = :dfd
            )
            return sum(solve(discretize(s, dfdisc()), ExplicitEuler(; substeps = 1); dt = 1.0e-3).u[end])   # (a nonlinear decay: no bound)
        end
        v0, h = 0.4, 1.0e-6
        d = ForwardDiff.derivative(J, v0)
        @test d ≈ (J(v0 + h) - J(v0 - h)) / 2h rtol = 1.0e-6
        @test d > 0 && J(v0) ≈ ForwardDiff.value(J(ForwardDiff.Dual(v0, 1.0)))
    end
end
