# The field recipe: `fieldplot` draws the grid of the chosen save of a lattice field
# solution (a heatmap in 2D, a volume in 3D), from a field algorithm or an OrdinaryDiffEq
# solver; an `Observable` index moves it; the axes are the system's coordinates; an
# attribute change redraws; `record_field` writes one frame per save. Negative controls: a
# value that is not a field solution has no frames, and a bad save number is an error.

@testsetup module MP_fields
using Test, CairoMakie, MakiePotts, LatticePDE, ModelingToolkitBase
using ModelingToolkitBase: t_nounits as t, D_nounits as D
using OrdinaryDiffEqTsit5: Tsit5
using MakiePotts: FieldFrames, field_frames

function spot2d(dims = (16, 12); spacing = 1.0)
    @parameters x y
    @variables c(..)
    C = c(t, x, y)
    dom = lattice_domain(t, (x, y), dims; spacing, tspan = (0.0, 2.0))
    ic = [c(0, x, y) ~ exp(-((x - 8)^2 + (y - 6)^2) / 4)]
    @named sys = PDESystem(D(C) ~ laplacian(C) - 0.1 * C, ic, dom, [t, x, y], [C], [])
    return discretize(sys, LatticeDiscretization(Grid(dims))), c, x, y
end

# a fine field `c` and a field `m` on the grid coarsened by 4, spacing 0.5
function coarse2d()
    @parameters x y
    @variables c(..) m(..) [lattice_level = Coarse(4)]
    C, M = c(t, x, y), m(t, x, y)
    dom = lattice_domain(t, (x, y), (16, 8); spacing = 0.5, tspan = (0.0, 1.0))
    @named sys = PDESystem(
        [D(C) ~ laplacian(C), D(M) ~ laplacian(M) + C - M],
        [c(0, x, y) ~ x, m(0, x, y) ~ 0.0], dom, [t, x, y], [C, M], []
    )
    return discretize(sys, LatticeDiscretization(Grid((16, 8)))), c, m, x
end

function spot3d()
    @parameters x y z
    @variables u(..)
    U = u(t, x, y, z)
    dom = lattice_domain(t, (x, y, z), (8, 8, 6); tspan = (0.0, 1.0))
    ic = [u(0, x, y, z) ~ exp(-((x - 4)^2 + (y - 4)^2 + (z - 3)^2) / 4)]
    @named sys = PDESystem(D(U) ~ laplacian(U), ic, dom, [t, x, y, z], [U], [])
    return discretize(sys, LatticeDiscretization(Grid((8, 8, 6)))), u
end

# the array the child plot of `plt` draws (the last argument of the heatmap or volume)
function drawn(plt)
    child = plt.plots[1]
    return child[child isa Heatmap ? 3 : 4][]
end
end

@testitem "fieldplot: 2D heatmap of a save" setup = [MP_fields] tags = [
    :makiepotts, :core,
] begin
    using .MP_fields: spot2d, drawn, field_frames
    using CairoMakie, MakiePotts, LatticePDE
    prob, c = spot2d()
    sol = solve(prob, ExplicitEuler(); dt = 0.5, saveat = 0.5)
    n = length(sol.t)
    @test n == 5
    fig, ax, plt = fieldplot(sol, c)
    @test plt isa FieldPlot
    @test ax isa Axis
    @test plt.plots[1] isa Heatmap
    @test drawn(plt) ≈ sol[c][n]
    i = Observable(2)
    plt2 = fieldplot!(Axis(fig[1, 2]), sol, c; index = i)
    @test drawn(plt2) ≈ sol[c][2]
    i[] = 4
    @test drawn(plt2) ≈ sol[c][4]
    lo, hi = extrema(reduce(vcat, vec.(sol[c])))
    @test collect(plt2.plots[1].colorrange[]) ≈ [lo, hi]
    @test field_frames(sol, :c).series[3, :, :] == sol[c][3]
end

@testitem "fieldplot: OrdinaryDiffEq solution and 3D volume" setup = [MP_fields] tags = [
    :makiepotts, :core,
] begin
    using .MP_fields: spot2d, spot3d, drawn, Tsit5
    using CairoMakie, MakiePotts, LatticePDE
    prob, c = spot2d()
    sol = solve(prob, Tsit5(); saveat = 1.0)
    fig, ax, plt = fieldplot(sol, c; index = 2)
    @test drawn(plt) ≈ sol[c][2]
    prob3, u = spot3d()
    sol3 = solve(prob3, ExplicitEuler(); dt = 0.25, saveat = 0.5)
    fig3, ax3, plt3 = fieldplot(sol3, u)
    @test ax3 isa LScene
    @test plt3.plots[1] isa Volume
    @test drawn(plt3) ≈ sol3[u][end]
    i = Observable(1)
    plt3b = fieldplot!(LScene(fig3[1, 2]), sol3, u; index = i, alpha = 0.5)
    @test drawn(plt3b) ≈ sol3[u][1]
    i[] = 3
    @test drawn(plt3b) ≈ sol3[u][3]
    @test plt3b.plots[1].alpha[] == 0.5
    # the volume spans the outer faces of the end sites
    @test plt3b.plots[1][1][] == (0.0, 8.0)
    @test plt3b.plots[1][3][] == (0.0, 6.0)
end

@testitem "fieldplot: the axes are the system's coordinates" setup = [MP_fields] tags = [
    :makiepotts, :core,
] begin
    using .MP_fields: spot2d, coarse2d
    using CairoMakie, MakiePotts, LatticePDE
    prob, c, x, y = spot2d(; spacing = 0.5)
    sol = solve(prob, ExplicitEuler(); dt = 0.05, saveat = 1.0)
    fig, ax, plt = fieldplot(sol, c)
    @test plt.xs[] ≈ collect(sol[x])
    @test plt.ys[] ≈ collect(sol[y])
    @test first(plt.xs[]) == 0.25
    # the heatmap's cells span the faces between the centers
    @test plt.plots[1][1][] ≈ 0.0:0.5:8.0
    # a coarse node covers a block of 4 sites: its center is the block's middle
    cprob, cc, m, cx = coarse2d()
    csol = solve(cprob, BackwardEuler(); dt = 0.5)
    _, _, cplt = fieldplot(csol, m)
    @test size(cplt.plots[1][3][]) == (4, 2)
    @test cplt.xs[] ≈ [1.0, 3.0, 5.0, 7.0]
    @test cplt.ys[] ≈ [1.0, 3.0]
    _, _, fplt = fieldplot(csol, cc)
    @test fplt.xs[] ≈ collect(csol[cx])
end

@testitem "fieldplot: attribute and data changes redraw" setup = [MP_fields] tags = [
    :makiepotts, :core,
] begin
    using .MP_fields: spot2d, drawn
    using CairoMakie, MakiePotts, LatticePDE
    CairoMakie.activate!(type = "png")
    prob, c = spot2d()
    sol = solve(prob, ExplicitEuler(); dt = 0.5, saveat = 0.5)
    fig, ax, plt = fieldplot(sol, c)
    before = copy(colorbuffer(fig))
    plt.colormap = :magma
    @test colorbuffer(fig) != before
    # a solution of another size: the grid and the axes follow it
    src = Observable{Any}(sol)
    fig2, ax2, plt2 = fieldplot(src, :c)
    prob2, _ = spot2d((10, 6))
    sol2 = solve(prob2, ExplicitEuler(); dt = 0.5, saveat = 0.5)
    src[] = sol2
    @test size(drawn(plt2)) == (10, 6)
    @test plt2.xs[] ≈ 0.5:1.0:9.5
end

@testitem "record_field: one frame per save" setup = [MP_fields] tags = [
    :makiepotts, :core,
] begin
    using .MP_fields: spot2d
    using CairoMakie, MakiePotts, LatticePDE
    prob, c = spot2d()
    sol = solve(prob, ExplicitEuler(); dt = 0.5, saveat = 0.5)
    mktempdir() do dir
        file = joinpath(dir, "c.mp4")
        @test record_field(file, sol, c; framerate = 5) == file
        @test filesize(file) > 0
        part = joinpath(dir, "part.mp4")
        record_field(part, sol, c; indices = [1, 3, 5], plot = (; colormap = :magma))
        @test filesize(part) > 0
        @test_throws ArgumentError record_field(
            joinpath(dir, "no.mp4"), sol, c;
            framerate = 0
        )
        @test !isfile(joinpath(dir, "no.mp4"))
        @test_throws ArgumentError record_field(
            joinpath(dir, "no.mp4"), sol, c;
            indices = Int[]
        )
        # every index is checked before the first frame, not only the ends
        @test_throws "save 9 is outside 1:5" record_field(
            joinpath(dir, "no.mp4"), sol, c;
            indices = [1, 9, 5]
        )
        @test !isfile(joinpath(dir, "no.mp4"))
    end
end

@testitem "fieldplot: negative controls" setup = [MP_fields] tags = [
    :makiepotts, :core,
] begin
    using .MP_fields: spot2d, FieldFrames, field_frames
    using CairoMakie, MakiePotts, LatticePDE
    @test_throws MethodError field_frames(rand(4, 4), :c)
    @test_throws MethodError fieldplot(rand(4, 4), :c)
    prob, c = spot2d()
    sol = solve(prob, ExplicitEuler(); dt = 0.5, saveat = 0.5)
    # Makie wraps the error of a plot attribute; its message names the save
    @test_throws "save 9 is outside 1:5" fieldplot(sol, c; index = 9)
    @test_throws ArgumentError FieldFrames([0.0, 1.0], zeros(3, 4, 4))
    @test_throws ArgumentError FieldFrames([0.0, 1.0], zeros(2, 4))
    @test_throws ArgumentError FieldFrames([0.0], zeros(1, 3, 2); centers = (1:3, 1:3))
end
