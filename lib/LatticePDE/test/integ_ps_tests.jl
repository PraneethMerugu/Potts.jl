# F2-13 (F2 design §2.13): integrator parameter access by SciML's convention. `integ.ps[x]`
# reads and writes scalars, whole tables and table entries, through the checks of `setp` and of
# a table write (validation, the substep count, the masks and clamps run again, `reset!`).
# `integ[p]` and `integ[p] = v` of a parameter or table are errors that give the `integ.ps`
# route. Base (244d58e7): `ig.ps` a FieldError; `integ[Dk] = values` wrote the table and
# `integ[k]` read the parameter.

@testsetup module LP_integ_ps
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
include("shared/problems.jl")
include("shared/silent.jl")
include("shared/groups.jl")
psmsg(f) = try
    f(); ""
catch e
    sprint(showerror, e)
end
include("shared/export_all.jl")
end

@testitem "F2-13: integ.ps reads and writes; integ[p] gives the route" setup = [LP_integ_ps] tags = [:latticepde, :integ_ps] begin
@testset "F2-13: integ.ps reads and writes; integ[p] gives the route" begin
    @parameters Dp[1:2] = [1.0, 2.0] kp = 0.5 mvp = 1.0
    pdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    sys = PDESystem([D(ce) ~ Dp[1] * Δ(ce) - kp * ce], [c(0, x, y) ~ 1.0], pdom, [t, x, y], [ce], [Dp, kp]; name = :ps)
    p = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    ig = init(p, ExplicitEuler(; dt = 0.01, substeps = 1))
    # reads: a scalar (as a symbol too), a table, an entry
    @test ig.ps[kp] == 0.5 && ig.ps[:kp] == 0.5 && ig.ps[Dp] == [1.0, 2.0] && ig.ps[Dp[2]] == 2.0
    # writes: a scalar, a whole table, an entry; the problem keeps its own values
    ig.ps[kp] = 0.25
    ig.ps[Dp] = [1.0, 3.0]
    ig.ps[Dp[1]] = 2.0
    @test ig.ps[kp] == 0.25 && ig.ps[Dp] == [2.0, 3.0] && p.p.tables == ["Dp" => [1.0, 2.0]] && p.p.values == [0.5]
    # the step reads them: a uniform field decays by (1 − dt kp / n)ⁿ (Δ = 0)
    n = ig.substeps
    step!(ig)
    @test all(≈((1 - 0.01 * 0.25 / n)^n; rtol = 1e-14), ig[ce])
    # the checks: a negative coefficient is refused and nothing changes; the count follows
    neg(err) = occursin("is negative at these parameters", err)
    @test neg(psmsg(() -> (ig.ps[Dp] = [-1.0, 2.0]))) && ig.ps[Dp] == [2.0, 3.0]
    @test neg(psmsg(() -> (ig.ps[Dp[1]] = -1.0))) && ig.ps[Dp[1]] == 2.0
    @test (ig.ps[Dp] = [1000.0, 2.0]; ig.substeps == 712)       # ρ = 128 Dp[1] + kp, dt = 0.01
    @test (ig.ps[Dp[1]] = 1.0; ig.substeps == 1)
    # `integ[p]` and `integ[p] = v` of a parameter or table: the route, never SciML's deprecation
    for (f, want) in ((() -> ig[kp], "`kp` is a parameter: read `integ.ps[kp]`"),
            (() -> ig[:kp], "read `integ.ps[:kp]`"), (() -> (ig[kp] = 1.0), "write `integ.ps[kp] = v`"),
            (() -> ig[Dp], "`Dp` is a table: read `integ.ps[Dp]`"), (() -> (ig[Dp] = [1.0, 2.0]), "write `integ.ps[Dp] = values`"),
            (() -> (ig[Dp[2]] = 1.0), "write `integ.ps[Dp[2]] = v`"), (() -> ig[[ce, kp]], "`kp` is a parameter"))
        err = psmsg(f)
        @test occursin(want, err) && !occursin("deprecated", err)
    end
    @test ig.ps[Dp] == [1.0, 2.0] && ig.ps[kp] == 0.25            # the refused writes changed nothing
    # fields and inputs index as before: a state write, an input write (the mask follows)
    ig[ce] = fill(0.5, 4, 4)
    @test all(==(0.5), ig[ce])
    K = Int32[i <= 2 ? 1 : 0 for i in 1:4, j in 1:4]
    sv = PDESystem([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, ce ~ masked(qe == 0, mvp)], pdom, [t, x, y], [ce, qe], [mvp]; name = :pm)
    iv = init(discretize(sv, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [qe => K]),
        ExplicitEuler(; dt = 0.001))
    @test iv[ce][3, 1] == 1.0 && iv[ce][1, 1] == 0.0
    # a `ps` write of the mask's value moves the masked sites at once (the init and clamps run again)
    iv.ps[mvp] = 3.0
    @test iv[ce][3, 1] == 3.0 && iv[ce][1, 1] == 0.0
    iv[qe] = zeros(Int32, 4, 4)
    @test all(==(3.0), iv[ce])
    # a `ps` write drops the algorithm's history (`reset!`), as `setp` does
    igs = init(p, GStub(0.01, 0))
    cs = only(igs.runtimes).cache
    igs.ps[Dp[2]] = 5.0
    @test cs.resets == 1
    igs.ps[kp] = 0.1
    @test cs.resets == 2
end
end

# F2-14 (FE-18) in front end B: a parameter's declared `bounds` (MTK metadata) holds at every
# write, refused at the write as in front end A: `setp`, `integ.ps`, owned `remake`,
# `discretize(…; p)`, ODE `remake` and the ODE integrator's `setp` (nothing changes). The bound
# prints as A prints it. Base: the metadata was ignored (a write of 3 ran); review S1 of batch 5:
# `remake` and the ODE paths took the value and refused it only at `init`/`solve`/`step!`.
@testitem "F2-14: a parameter's declared bounds hold in B" setup = [LP_integ_ps] tags = [:latticepde, :integ_ps] begin
@testset "F2-14: a parameter's declared bounds hold in B" begin
    @parameters kb2 = 0.5 [bounds = (0, 2)]
    pdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    sys = PDESystem([D(ce) ~ -kb2 * ce], [c(0, x, y) ~ 1.0], pdom, [t, x, y], [ce], [kb2]; name = :pb)
    p = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    ig = init(p, ExplicitEuler(; dt = 0.1, substeps = 1))
    out(e) = occursin("parameter `kb2` = 3.0 is outside its declared bounds (0, 2)", e)
    @test out(psmsg(() -> (ig.ps[kb2] = 3.0))) && ig.ps[kb2] == 0.5
    @test out(psmsg(() -> setp(ig, kb2)(ig, 3.0))) && ig.ps[kb2] == 0.5
    @test out(psmsg(() -> remake(p; p = [kb2 => 3.0])))
    @test out(psmsg(() -> discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); p = [kb2 => 3.0])))
    o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    @test out(psmsg(() -> remake(o; p = [kb2 => 3.0]))) && out(psmsg(() -> remake(o; p = [3.0])))
    oi = SciMLBase.init(o, Tsit5())
    @test out(psmsg(() -> setp(oi, kb2)(oi, 3.0))) && oi.ps[kb2] == 0.5
    ig.ps[kb2] = 2.0                                       # the bound itself is in
    @test ig.ps[kb2] == 2.0
    setp(oi, kb2)(oi, 1.0)
    @test oi.ps[kb2] == 1.0
end
end

# Review M2/S4 of batch 5: a bound message names the user's parameter (never a slot `#i`) and
# blames the parameter written: base parameters are checked first, then computed ones, and a
# computed parameter's message names the inputs to change (base: "parameter `#2` = 6.0 …" for
# a write of `k = 3.0`)
@testitem "F2-15: bound messages name the parameter written, then the computed ones" setup = [LP_integ_ps] tags = [:latticepde, :integ_ps] begin
@testset "F2-15: bound messages name the parameter written, then the computed ones" begin
    @parameters kbd = 0.5 [bounds = (0, 2)]
    @parameters kbd2 = 2kbd [bounds = (0, 3)]
    pdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    sys = PDESystem([D(ce) ~ -kbd2 * ce], [c(0, x, y) ~ 1.0], pdom, [t, x, y], [ce], [kbd, kbd2]; name = :pq)
    p = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    ig = init(p, ExplicitEuler(; dt = 0.1, substeps = 1))
    e = psmsg(() -> (ig.ps[kbd] = 3.0))
    @test occursin("parameter `kbd` = 3.0 is outside its declared bounds (0, 2)", e) && !occursin("#", e)
    e = psmsg(() -> (ig.ps[kbd] = 1.8))                        # kbd is in; kbd2 = 3.6 is not
    @test occursin("parameter `kbd2` = 3.6 is outside its declared bounds (0, 3): `kbd2` is computed from `kbd`", e)
    @test ig.ps[kbd] == 0.5 && ig.ps[kbd2] == 1.0               # nothing changed
    @test occursin("`kbd2` is computed from `kbd`", psmsg(() -> remake(p; p = [kbd => 1.8])))
    o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
    @test occursin("`kbd2` = 3.6", psmsg(() -> remake(o; p = [kbd => 1.8])))
end
end
