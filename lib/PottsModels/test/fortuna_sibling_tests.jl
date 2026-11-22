# The sibling of `FortunaMigration` (see siblings_tests.jl): a 2D crawler built from public
# primitives only. A front compartment makes its own field and extends up its gradient, as
# Fortuna's lamellipodium does, with no substrate. The field is a plain MTK `PDESystem`
# coupled with `@fields`, its source is every front site, and the drive acts on front
# extensions only.

@testsetup module FortunaSiblingSetup
include(joinpath(@__DIR__, "shared", "common.jl"))
include(joinpath(@__DIR__, "shared", "selfcheck.jl"))
using Statistics: mean
module FrontField
    using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters,
        t_nounits as t
    using Potts.LatticePDE: laplacian, lattice_domain
    const Dt = Differential(t)
    @parameters x y
    @variables F(..) source(..)::Bool [input = true]
    function front_field(lattice)
        @parameters D_F = 0.05 k = 0.5
        X, S = F(t, x, y), source(t, x, y)
        return PDESystem(
            [Dt(X) ~ D_F * laplacian(X) - k * X + k * S], [F(0, x, y) ~ 0.0],
            lattice_domain(t, (x, y), lattice), [t, x, y], [X, S], [D_F, k];
            name = :front
        )
    end
end
@potts_model FrontCrawler begin
    @kinds medium body front
    @parameters begin
        λ = 2.0
        T = 10.0
        λ_F = 20.0
        J[kind, kind] = Pairs(
            default = 0.0, (medium, body) => 10, (medium, front) => 6, (body, front) => 6
        )
    end
    @variables V_target(cell) = ifelse(kind == front, 30.0, ifelse(kind == body, 60.0, 0.0))
    @lattice Lattice((48, 48); boundary = Periodic(), neighborhood = Moore(1))
    @fields F = FrontField.front_field((48, 48)) (FrontField.source => kind == front,)
    @energy begin
        cells(body, front) => λ * (volume - V_target)^2
        contacts => J[kind, neighbor_kind]
    end
    @drive copy => ifelse(
        (kind[new] == front) & (old == 0), λ_F * (F[target] - F[source]), 0.0
    )
    @observed begin
        bx(cell) ~ centroid(1)
        by(cell) ~ centroid(2)
        fx(cell) ~ centroid(sibling(front), 1)
    end
    @sweep Metropolis(; temperature = T)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "FortunaMigration sibling: a 2D front-field crawler" setup = [
    FortunaSiblingSetup,
] tags = [:pottsmodels, :core] begin
    σ = zeros(Int32, 48, 48)
    σ[20:27, 20:27] .= 1
    σ[28:31, 20:27] .= 2
    op = [ownership => σ, kind => [:body, :front], cluster => [1, 1]]
    sys = FrontCrawler(; name = :f)
    @test selfcheck(PottsProblem(sys, op, (0, 1))) < 1.0e-9
    # the body's displacement over 300 MCS, x and y unwrapped
    function displacement(λ_F, seed)
        p = PottsProblem(sys, [op; :λ_F => λ_F], (0, 300); seed)
        sol = solve(p, SequentialCPM(); saveat = 0:10:300)
        xy = [(observe(p, :bx, u)[1], observe(p, :by, u)[1]) for u in sol.u]
        tr = PottsModels.Analysis.unwrap_track(xy, (48, 48), true)
        return hypot((tr[end] .- tr[1])...)
    end
    driven = [displacement(20.0, s) for s in 1:3]
    free = [displacement(0.0, s) for s in 1:3]
    # the field drive moves the cell; control: without it, the cell wanders less. The
    # margin is about half the gap of the means (driven about 10 sites, free about 2.5)
    @test mean(driven) > mean(free) + 4
end
