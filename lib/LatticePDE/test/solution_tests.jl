# F4-04 (F4 design §3.5, §5): an owned solve returns SciML's `ODESolution` (`build_solution`, linear
# interpolation). A field read on a solution of a lattice problem follows SciML (ruling Q18): `sol[c]`
# is one grid per save, `field_series(sol, c)` a lazy `FieldSeries` of size `(nt, dims…)`
# (MethodOfLines' shape); `sol[x]` the site centers; the bare callable `c`
# a key; `sol(t, x, y)` multilinear; `sol.ps` the parameters at the end; `sol.stats` a
# `LatticeStats`. Negative control at the F4-03 commit (~/lpwork/f4b5/nc04.log): `sol(0.05)` is
# not callable (a `FieldSolution`), `sol[c]` a vector of grids, `sol[u]` "Invalid symbol".

@testsetup module LP_solution
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
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
using OrdinaryDiffEqTsit5: Tsit5

cbsys32() = bsys([D(bce) ~ 0.01 * Δ(bce) - bce], [bc(0, x, y) ~ x * y], Any[]; T = 0.3, dvs = [bce])
include("shared/export_all.jl")
end

@testitem "F4-04: the owned solution is an ODESolution: sol(t), Array, stats, ps" setup = [LP_solution] tags = [:latticepde, :solution] begin
@testset "F4-04: the owned solution is an ODESolution: sol(t), Array, stats, ps" begin
    sp = discretize(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ x * y], [bD, bk]; T = 0.3, dvs = [bce]),
        LatticeDiscretization(Grid((8, 8)); T = Float64))
    s = solve(sp, ExplicitEuler(); dt = 0.01, saveat = 0.1)
    @test s isa SciMLBase.ODESolution && s.prob isa SciMLBase.ODEProblem && s.alg isa ExplicitEuler
    @test s.t ≈ [0.0, 0.1, 0.2, 0.3] && s(0.1) == s.u[2] && s(0.15) ≈ (s.u[2] .+ s.u[3]) ./ 2
    @test Array(s) == reduce(hcat, s.u) && s.stats isa LFP.LatticeStats && s.stats.nf == 30
    @test substep_counts(s) == [s.stats.counts[1]] && LFP.field_stats(s).solves == 0
    # sol.ps: the values at the end of the run (a write on the integrator)
    ig = init(sp, ExplicitEuler(); dt = 0.01)
    step!(ig, 0.1, true)
    ig.ps[bk] = 3.0
    @test solve!(ig).ps[bk] == 3.0 && sp.ps[bk] == 2.0
end
end

@testitem "F4-04 (Q18): sol[c] is one grid per save; field_series is time first; sol[x]; sol[c] by the callable" setup = [LP_solution] tags = [:latticepde, :solution] begin
@testset "F4-04 (Q18): sol[c] is one grid per save; field_series is time first; sol[x]; sol[c] by the callable" begin
    sp = discretize(bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ x * y], [bD, bk]; T = 0.3, dvs = [bce]),
        LatticeDiscretization(Grid((8, 8)); T = Float64))
    so = solve(sp, ExplicitEuler(); dt = 0.01, saveat = 0.1)
    st = solve(sp, Tsit5(); saveat = 0.1, abstol = 1e-10, reltol = 1e-10)
    for s in (so, st)
        v = s[bce]
        @test v isa Vector{Matrix{Float64}} && length(v) == 4 && v[2] == reshape(s.u[2], 8, 8) == s[bce, 2]
        @test v[end] == s[bce, end] == reshape(s.u[end], 8, 8)
        c = field_series(s, bce)
        @test c isa LFP.FieldSeries && size(c) == (4, 8, 8)
        @test Array(c) == permutedims(reshape(reduce(hcat, s.u), 8, 8, 4), (3, 1, 2))
        @test c[2, :, :] == v[2] && c[end, 3, 5] == s.u[end][3 + 8 * 4]
        @test s[bc] == v && s[:bc] == v                           # the bare callable and the name
        @test s[x] == range(1 / 16; step = 1 / 8, length = 8) && s[y] == s[x]
    end
    # lazy: `field_series` copies no grid (a 32×32 run: one grid is 8 KiB)
    s32 = solve(discretize(cbsys32(), LatticeDiscretization(Grid((32, 32)); T = Float64)), ExplicitEuler(); dt = 0.01,
        saveat = 0.1)
    lazy(s) = @allocated field_series(s, bce)
    lazy(s32)
    @test lazy(s32) < 8 * 32^2 || (println("F4-04 lazy ", lazy(s32)); false)
    @test maximum(abs, Array(field_series(so, bce)) .- Array(field_series(st, bce))) < 0.05  # (EE against Tsit5)
    # sol(t, x, y): multilinear between the site centers, linear in time between the saves
    g = reshape(so(0.15), 8, 8)
    @test so(0.15, 1 / 16, 3 / 16; idxs = bce) ≈ g[1, 2]
    @test so(0.15, 2 / 16, 3 / 16; idxs = bce) ≈ (g[1, 2] + g[2, 2]) / 2
    @test so(0.15, 0.0, 0.0) ≈ [g[1, 1]]                         # past the outermost centers: the edge value
end
end
