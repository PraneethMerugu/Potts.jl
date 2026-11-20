# Review F4 b2 (#3): a moving mask set that switches on over a quiet state. Tsit5 and Rodas5P take
# long steps over a zero state, and a set `(t > 0.3) & (k == 1)` was never applied (the masked
# sites ended at 0.0, the owned run at 2.0). A comparison of `t` with parameters and constants is
# now a continuous callback at its root (`MaskEvent`): the switch is exact, and the run equals the
# owned one. A predicate whose switch has no event (here `t > q`, an input) is refused on an
# OrdinaryDiffEq solver unless `dtmax` or `tstops` is given. Negative control at 70400aba:
# the masked sites end at 0.0 under both solvers; the
# unlocated predicate is not refused.

@testsetup module LP_maskswitch
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
include("shared/maskswitch.jl")
include("shared/export_all.jl")
end

@testitem "review b2 #3: a mask set switching on over a quiet state under Tsit5 and Rodas5P" setup = [LP_maskswitch] tags = [:latticepde, :maskswitch] begin
    @testset "review b2 #3: a mask set switching on over a quiet state under Tsit5 and Rodas5P" begin
        for (name, pred) in (
                ("t > 0.3", (t > 0.3) & (mke == 1)), ("t > mt0", (t > mt0) & (mke == 1)),
                ("0.3 < t", (0.3 < t) & (mke == 1)),
            )
            sys = PDESystem(
                [D(mce) ~ mD * laplacian(mce) - 0.5 * mce], [mc(0, x, y) ~ 0.0, mce ~ masked(pred, 2.0)], mdom,
                [t, x, y], [mce, mke], [mD, mt0]; name = :ms
            )
            p = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64); inputs = [mke => MK])
            o = solve(p, ExplicitEuler(); dt = 1.0e-4, saveat = [0.2, 1.0])
            for alg in (Tsit5(), Rodas5P())
                s = solve(p, alg; abstol = 1.0e-9, reltol = 1.0e-9, saveat = [0.2, 1.0])
                @test unique(s.u[end][vec(MK .== 1)]) == [2.0] && all(iszero, s(0.2))   # (off before the switch)
                e = maximum(abs, s.u[end] .- o.u[end])
                @test e < 1.0e-3 || (println("b2 #3 ", name, " ", nameof(typeof(alg)), " vs owned ", e); false)
            end
        end
        # a switch the solver cannot locate (`t` against an input): refused, unless the step is bounded
        sys = PDESystem(
            [D(mce) ~ mD * laplacian(mce) - 0.5 * mce], [mc(0, x, y) ~ 0.0, mce ~ masked(t > mqe, 2.0)], mdom,
            [t, x, y], [mce, mqe], [mD]; name = :mu
        )
        p = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64); inputs = [mqe => fill(0.3, 8, 8)])
        @test_throws ArgumentError solve(p, Tsit5())
        o = solve(p, ExplicitEuler(); dt = 1.0e-3)
        @test unique(o.u[end]) == [2.0]                                # (the owned run applies it)
        s = solve(p, Tsit5(); dtmax = 0.01)
        @test unique(s.u[end]) == [2.0]
        @test unique(solve(p, Tsit5(); tstops = [0.3, 0.31]).u[end]) == [2.0]
    end
end
