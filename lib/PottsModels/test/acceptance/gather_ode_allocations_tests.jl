# a gather inside a cell-ODE rate allocates on every warm
# MCS (480–1472 B here), on both algorithms and every fixed-step solver; the same rate
# without the gather does not allocate.
#
# Pinned here:
#  1. Zero warm allocations per `step!` (after two warm-up steps, every one of five further
#     steps allocates 0 bytes) for a cell ODE whose rate contains a gather, under
#     `SequentialCPM` and `CheckerboardCPM`, `T = Float64` and `Float32`, with the default
#     solver (`ExplicitEuler()`, one step per MCS), `ExplicitEuler(substeps = 4)` and
#     `Potts.RK4()`. Three gather shapes over a site neighbourhood (the DSL has no
#     cell-neighbour gather; `neighbors(c)` is a roadmap idea, not vocabulary):
#       - `XVol`: a sum of a non-ODE cell variable over `owner[n]` of a literal site's Moore
#         neighbourhood (the planned example);
#       - `XCross`: a conditioned maximum of the cell's own ODE unknown over the other cells
#         around a site (the cross-cell, Jacobi-scratch path of `cell_ode_jacobi_tests.jl`,
#         D-078);
#       - `XRing`: a `count` over a named relation (`@relations ring = VonNeumann(1)`)
#         anchored at a site computed from the cell's `id`.
#     `XPlain` (the same kind of rate without a gather) is the control: zero today.
#     Adaptive solvers are not in the zero-allocation targets: they allocate without a
#     gather too (4416 B per MCS for `XPlain` today, `cell_ode_jacobi_tests.jl` pins zero
#     only for fixed-step).
#  2. Results unchanged: `y` after 10 MCS (seed 7) for every model, algorithm and solver
#     (adaptive included) equals the values recorded inline from the code before the fix,
#     bitwise; and the problem fingerprints of models without a gather in a cell ODE (the
#     control, a cross-cell indexed read without a gather, and four published models) equal
#     the recorded ones.
#  3. Not pinned: type stability of the generated rate. On the code before the fix,
#     `code_typed` of the cell phase is already concretely inferred (no `Any`- or
#     `Core.Box`-typed call, return `Nothing`); the rate closure is `:invoke`d with a static
#     target and allocates because the closure object holding heap references is built and
#     passed (272 B per cell per call), not because inference fails. An inference assertion
#     would pass today and would pin the phase layout (internal), so the allocation targets
#     above are the acceptance.

@testsetup module GatherODEAllocationsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P
const ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const FIXED = (
    ("ExplicitEuler() (default)", (;)), (
        "ExplicitEuler(substeps = 4)", (; ode_solver = Potts.ExplicitEuler(substeps = 4)),
    ),
    ("RK4()", (; ode_solver = Potts.RK4())),
)
const SOLVERS = (
    FIXED..., ("Adaptive(Rodas5P())", (; ode_solver = Potts.Adaptive(Rodas5P()))),
)
# ---------------------------------------------------------------------------------------
# Models: two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice. Site 42
# is (6, 4), on their interface; sites 40 and 44 (`36 + 4id`) are (4, 4) and (8, 4), inside
# cell 1 and cell 2.
@potts_model XVol begin
    @kinds medium A
    @parameters k = 0.01
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ k * sum(volume[owner[n]] for n in Moore(1)(42)) - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model XCross begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~
        0.5 * (maximum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - y)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model XRing begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @relations ring = VonNeumann(1)
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.1 * count(owner[n] == id for n in ring(36 + 4id)) - 0.2y
    @sweep Metropolis(; temperature = 1.0)
end
# the control: a cell rate reading a cell variable, no gather
@potts_model XPlain begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * volume - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end
# a cross-cell indexed read without a gather (`cell_ode_jacobi_tests.jl`'s scratch path);
# zero today
@potts_model XPair begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.5 * (y[3 - id] - y)
    @sweep Metropolis(; temperature = 1.0)
end
const GATHERS = (XVol, XCross, XRing)
const CONTROLS = (XPlain, XPair)
sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
function problem(M, tspan; T = Float64, kw...)
    return PottsProblem(
        M(; name = :x), [ownership => sigma(), kind => [:A, :A], :y => [1.0, 2.0]],
        tspan; T, seed = 7, kw...
    )
end
"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false, save_everystep = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end
const alloc_N = 10
# MCS of the recorded results
function final_y(
        M, alg,
        kw
    )
    return Vector{Float64}(Array(solve(problem(M, (0, alloc_N); kw...), alg).u[end].cell.y))
end
"""Independent `Rodas5P` (`reltol = 1e-12, abstol = 1e-12`) ODE integration over the
recorded `σ` trajectory of `sol`, computing gather inputs and cell volumes by hand from each
post-sweep `σ`."""
function rodas_ref(M, sol)
    u = Float64.(Array(sol.u[1].cell.y))
    for k in 0:(alloc_N - 1)
        σ = Array(sol.u[k + 2].ownership)
        v = (Float64(count(==(1), σ)), Float64(count(==(2), σ)))
        # Site 42 on 12x8 column-major is (6, 4); Moore(1) neighbors wrap periodically.
        moore42 = [
            σ[mod1(6 + dx, 12), mod1(4 + dy, 8)] for dx in -1:1
                for dy in -1:1 if !(dx == 0 && dy == 0)
        ]
        # Cross-cell reads in Potts (XCross, XPair) use the start-of-MCS Jacobi scratch
        # values.
        u_start = copy(u)
        rhs = if M === XVol
            s_vol = sum(o -> o > 0 ? v[o] : 0.0, moore42; init = 0.0)
            (y, _, _) -> [0.01 * s_vol - 0.1 * y[1], 0.01 * s_vol - 0.1 * y[2]]
        elseif M === XCross
            m1 = maximum((u_start[o] for o in moore42 if o > 0 && o != 1); init = 0.0)
            m2 = maximum((u_start[o] for o in moore42 if o > 0 && o != 2); init = 0.0)
            (y, _, _) -> [0.5 * (m1 - y[1]), 0.5 * (m2 - y[2])]
        elseif M === XRing
            # Anchor 36 + 4c on 12x8 column-major is (4c, 4); VonNeumann(1) neighbors wrap
            # periodically.
            cnts = ntuple(2) do c
                ax = 4 * c
                ring = (
                    σ[mod1(ax + 1, 12), 4], σ[mod1(ax - 1, 12), 4],
                    σ[ax, mod1(5, 8)], σ[ax, mod1(3, 8)],
                )
                count(==(c), ring)
            end
            (y, _, _) -> [0.1 * cnts[1] - 0.2 * y[1], 0.1 * cnts[2] - 0.2 * y[2]]
        elseif M === XPlain
            (y, _, _) -> [0.01 * v[1] - 0.1 * y[1], 0.01 * v[2] - 0.1 * y[2]]
        elseif M === XPair
            (y, _, _) -> [0.5 * (u_start[2] - y[1]), 0.5 * (u_start[1] - y[2])]
        else
            error("unknown gather ODE model: $M")
        end
        ode_prob = CorePotts.SciMLBase.ODEProblem(rhs, u, (Float64(k), Float64(k + 1)))
        # Tight 1e-12 reference tolerance makes Rodas5P reference error negligible
        # compared to the tested Potts ODE solvers.
        u = CorePotts.SciMLBase.solve(
            ode_prob, Rodas5P(); reltol = 1.0e-12, abstol = 1.0e-12,
            save_everystep = false
        ).u[end]
    end
    return u
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "gather ode allocations: the fixtures exercise their gathers" setup = [
    GatherODEAllocationsSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # Recorded on the code before the fix (feat/p6-0x at d5bfd3dc, CPU, 1 and 4 threads
    # alike), seed 7, 10 MCS: (model, solver label, algorithm) => y after 10 MCS.

    # --------------------------------------------------------------------------------------
    @testset "gather ode allocations: the fixtures exercise their gathers" begin
        # XVol reads the volumes around site 42, which change: the two algorithms'
        # trajectories differ (they would not if the gather read nothing that moves)
        @test final_y(XVol, SequentialCPM(), (;)) != final_y(XVol, CheckerboardCPM(), (;))
        # XRing: each anchor's VonNeumann neighbours (four at the start) mostly belong to
        # the cell, so y stays near 0.1 · count / 0.2; with a count of 0 it would decay to
        # 0.8^10 · (1, 2) ≈ (0.11, 0.21). SequentialCPM only (D-271): cells drift, and over
        # 64 seeds either algorithm stays above 0.9 in 78 %; the checkerboard's seed 7 does
        # not
        @test all(>(0.9), final_y(XRing, SequentialCPM(), (;)))
        # XCross: each cell reads the other's y across the interface; both end between their
        # initial values 1 and 2
        for alg in ALGS
            @test all(v -> 1.0 < v < 2.0, final_y(XCross, alg, (;)))
        end
        @test Potts._ode_reads_other_cells(mtkcompile(XCross(; name = :x)))
    end
end

@testitem "gather ode allocations: zero warm allocations, no gather (control)" setup = [
    GatherODEAllocationsSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "gather ode allocations: zero warm allocations, no gather (control)" begin
        for M in CONTROLS, T in (Float64, Float32), (label, kw) in FIXED, alg in ALGS
            a = warm_allocs(problem(M, (0, 100); T, kw...), alg)
            @test all(iszero, a)
            all(iszero, a) ||
                @info "gather ode allocations control allocates: $(nameof(M)) $T $label \
                    $(nameof(typeof(alg))) bytes per step = $a"
        end
    end
end

@testitem "gather ode allocations: zero warm allocations, gather in a cell-ODE rate" setup =
    [GatherODEAllocationsSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "gather ode allocations: zero warm allocations, gather in a cell-ODE rate \
        ($(nameof(M)))" for M in GATHERS
        for T in (Float64, Float32), (label, kw) in FIXED, alg in ALGS
            a = warm_allocs(problem(M, (0, 100); T, kw...), alg)
            @test all(iszero, a)
            all(iszero, a) ||
                @info "gather ode allocations gather allocates: $(nameof(M)) $T $label \
                    $(nameof(typeof(alg))) bytes per step = $a"
        end
    end
end

@testitem "gather ode allocations: compiled cell ODE matches independent Rodas5P \
    reference over recorded σ" setup = [GatherODEAllocationsSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "gather ode allocations: compiled cell ODE matches independent Rodas5P \
        reference over recorded σ" begin
        for M in (GATHERS..., CONTROLS...), alg in ALGS
            errs = Dict{String, Float64}()
            for (label, kw) in SOLVERS
                sol = solve(problem(M, (0, alloc_N); kw...), alg; saveat = 0:alloc_N)
                got = Vector{Float64}(Array(sol.u[end].cell.y))
                ref = rodas_ref(M, sol)
                errs[label] = maximum(abs.(got .- ref))
                if label == "Adaptive(Rodas5P())"
                    # Adaptive Rodas5P uses default SciML tolerances (~1e-3 reltol / 1e-6
                    # abstol).
                    @test isapprox(got, ref; rtol = 1.0e-5, atol = 1.0e-6)
                elseif label == "RK4()"
                    # 4th-order RK4 with dt = 1.0 on decay rate 0.5 has O((0.5*dt)^5) ~ 1e-4
                    # error.
                    @test isapprox(got, ref; rtol = 1.0e-3, atol = 1.0e-6)
                elseif label == "ExplicitEuler(substeps = 4)"
                    # dt = 0.25 1st-order Euler error over 10 MCS.
                    @test isapprox(got, ref; rtol = 0.05, atol = 0.05)
                else
                    # dt = 1.0 1st-order Euler error over 10 MCS.
                    @test isapprox(got, ref; rtol = 0.2, atol = 0.2)
                end
            end
            @test errs["ExplicitEuler(substeps = 4)"] < errs["ExplicitEuler() (default)"]
        end
    end
end

@testitem "gather ode allocations: the same run twice gives the same values" setup = [
    GatherODEAllocationsSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "gather ode allocations: the same run twice gives the same values" begin
        for M in (GATHERS..., CONTROLS...), (label, kw) in SOLVERS, alg in ALGS
            @test final_y(M, alg, kw) == final_y(M, alg, kw)
        end
    end
end
