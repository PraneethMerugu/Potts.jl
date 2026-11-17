# F3-20 (F3 design, F3-20): the hexagonal lattice in the solver's operator. Axial coordinates,
# six neighbors ±e₁, ±e₂, ±(e₁ − e₂), the face to +e₁ − e₂ the third face direction of
# `CellOperator(…; hex = true)`. The tests compare a solve with the eliminated system assembled
# here from the six faces and the ghost rule (masks with a value field, a Robin face, a
# Dirichlet face, field face coefficients), measure the residual reduction per V-cycle on hex
# grids that coarsen two and three levels (and one with generated levels above the bottom),
# and check the tangent solve of the diagonal face against a finite difference.
# Base (ee577f6e): `hex` is an unknown keyword of `CellOperator` (MethodError).
# Negative controls (mutations of this tree, F3-20 log in HANDOFF §6): the operator without
# the diagonal faces fails the hand system; a coarse build that drops the diagonal fine faces
# (`RuleWeights(; diagonal = 0)`) fails the cycle-factor bound.

@testsetup module LF_solvers_hex
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
include("../shared/solvers_coefficients.jl")
using LinearAlgebra: norm
using Random: Xoshiro
using LatticeFields.Solvers: tangent!

const HEX6 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))

"""
The eliminated hex system `A x = b` over the active sites of `op` (Float64, from the six
faces and the ghost rule): `(A, b, cells)`. The face to `o` is `face[d]` at the site for
`o = +dir_d`, at the neighbor for `o = −dir_d`; a face leaving the box takes the condition of
axis 1 when it leaves along axis 1, else of axis 2, with the site's face coefficient.
"""
function hex_system(op::CellOperator{2}, inp)
    d, per = op.dims, op.periodic
    n = prod(d)
    fs = (op.face..., op.diag)
    get(x, i) = x isa Real ? Float64(x) : Float64(inp[x][i])
    m = op.mask === nothing ? zeros(UInt8, n) : inp[op.mask]
    act = m .== 0
    f = haskey(inp, "in.f") ? Float64.(inp["in.f"]) : zeros(n)
    cells = findall(act)
    idx = zeros(Int, n)
    idx[cells] .= 1:length(cells)
    A, b = zeros(length(cells), length(cells)), zeros(length(cells))
    LI = LinearIndices(d)
    for (q, i) in enumerate(cells)
        b[q] += f[i]
        A[q, q] += get(op.shift, i)
        c = Tuple(CartesianIndices(d)[i])
        for o in HEX6
            dd = o in ((1, 0), (-1, 0)) ? 1 : o in ((0, 1), (0, -1)) ? 2 : 3
            pos = o in ((1, 0), (0, 1), (1, -1))
            v = c .+ o
            out = ntuple(a -> !(1 <= v[a] <= d[a]) && !per[a], 2)
            if !any(out)
                j = LI[CartesianIndex(mod1(v[1], d[1]), mod1(v[2], d[2]))]
                w = pos ? get(fs[dd], i) : get(fs[dd], j)
                A[q, q] += w
                act[j] ? (A[q, idx[j]] -= w) : (b[q] += w * get(op.value, j))
            else
                a = out[1] ? 1 : 2
                k = v[a] < 1 ? 1 : 2
                w = get(fs[dd], i)
                g, r = op.dirichlet[a][k], op.robin[a][k]
                if g !== nothing
                    A[q, q] += 2w
                    b[q] += 2w * g
                elseif r !== nothing
                    α, β, gr = r
                    A[q, q] += w * α / (α / 2 + β)
                    b[q] += w * gr / (α / 2 + β)
                end
            end
        end
    end
    return A, b, cells
end

function hex_solver(op, inp; inner = DevicePCG(; maxiters = 64, reltol = 1.0e-12), T = Float64, kw...)
    sv = FieldSolver(HostExec(), op; T, inner, kw...)
    for (k, v) in inp
        copyto!(field(sv, k), v)
    end
    return sv
end
function hex_vs_hand(op, inp; kw...)
    sv = hex_solver(op, inp; kw...)
    steady!(sv; maxiter = 64)
    A, b, cells = hex_system(op, inp)
    x = A \ b
    return maximum(abs, solver_solution(sv)[cells] .- x) / maximum(abs, x), sv
end

# a masked disc with a value field, a field face on +e₁ and on the diagonal
function hex_case(dims; periodic = (false, false), kw...)
    n = prod(dims)
    rng = Xoshiro(7)
    ctr = dims ./ 2 .+ 0.3
    mask = UInt8[sum(abs2, Tuple(c) .- ctr) < (dims[1] / 5)^2 for c in CartesianIndices(dims)]
    inp = Dict{String, Any}("in.f" => rand(rng, n), "m" => vec(mask), "mv" => 1 .+ rand(rng, n),
        "w1" => 0.5 .+ rand(rng, n), "w3" => 0.5 .+ rand(rng, n))
    op = CellOperator(dims; hex = true, periodic, face = ("w1", 0.8, "w3"), shift = 0.3, mask = "m",
        value = "mv", name = "c", kw...)
    return op, inp
end

# the residual reduction per stationary V(2, 2) cycle from a random error (zero right side)
function hex_factor(dims; rule = RuleWeights(), masked = true, periodic = (false, false))
    op0, inp = hex_case(dims; periodic)
    op = CellOperator(dims; hex = true, periodic, face = ("w1", 0.8, "w3"), shift = 1e-3,
        mask = masked ? "m" : nothing, value = 0.0,
        dirichlet = (periodic[1] ? (nothing, nothing) : (0.0, 0.0), (nothing, nothing)))
    inp = Dict(k => v for (k, v) in inp if !(k in ("in.f", "mv")) && (masked || k != "m"))
    sv = hex_solver(op, inp; inner = Multigrid(), rule)
    rebuild!(sv)
    lift!(sv)
    act = field(sv, lkey(0, "active")) .!= 0
    copyto!(field(sv, lkey(0, "x")), (rand(Xoshiro(3), length(act)) .- 0.5) .* act)
    rs = Float64[]
    for _ in 1:30
        solve!(sv; host = true, budget = 1)
        push!(rs, scalars(sv).rnorm)
    end
    return (rs[30] / rs[5])^(1 / 25), sv.ctx.L, sv.ctx.lb
end
include("../shared/export_all.jl")
end

@testitem "F3-20: a hex solve equals the hand system of the six faces" setup = [LF_solvers_hex] tags = [:latticefields, :solvers] begin
using .LF_solvers_hex: fd
@testset "F3-20: a hex solve equals the hand system of the six faces" begin
    # closed box: a Robin face (axis 2 low, d > 0), a Robin face whose diagonal is negative (axis 1
    # low, the defect correction), a Dirichlet face (axis 1 high), no-flux axis 2 high
    op, inp = hex_case((13, 11); robin = (((-0.2, 1.0, 0.5), nothing), ((1.0, 0.5, 0.4), nothing)),
        dirichlet = ((nothing, 1.5), (nothing, nothing)))
    e, sv = hex_vs_hand(op, inp)
    @test e < 1e-9 && scalars(sv).status === :done
    # periodic, and periodic on one axis (the diagonal wraps on that axis only); stationary multigrid
    for per in ((true, true), (true, false), (false, true))
        op, inp = hex_case((16, 12); periodic = per,
            robin = per[2] ? ((nothing, nothing), (nothing, nothing)) : ((nothing, nothing), (nothing, (2.0, 1.0, 0.3))))
        @test hex_vs_hand(op, inp)[1] < 1e-9
            @test hex_vs_hand(op, inp; inner = Multigrid(; reltol = 1.0e-12, maxiters = 60))[1] < 1.0e-9
    end
    # Float32: to the Float32 level
    op, inp = hex_case((16, 12))
    @test hex_vs_hand(op, Dict(k => (v isa Vector{Float64} ? Float32.(v) : v) for (k, v) in inp); T = Float32,
            inner = DevicePCG(; reltol = 1.0e-6)
        )[1] < 1.0e-4
    # numbers on every face: an unmasked periodic group deflates its constant mode
    op = CellOperator((12, 10); hex = true, periodic = (true, true), face = (1.0, 2.0, 0.5), shift = 0.01)
    f = rand(Xoshiro(2), 120)
    @test hex_vs_hand(op, Dict("in.f" => f))[1] < 1e-9
    # the refusals name the diagonal and the dims
    @test_throws "the face coefficient of the diagonal `1 − 2` must be > 0" CellOperator((8, 8); hex = true,
        face = (1.0, 1.0, -1.0))
    @test_throws "a hexagonal lattice is 2D" CellOperator((8, 8, 8); hex = true)
    @test_throws "`face` has one coefficient per face direction of a hexagonal lattice" CellOperator((8, 8);
        hex = true, face = (1.0, 1.0))
end
end

@testitem "F3-20: multigrid on hex grids: the residual reduction per V-cycle" setup = [LF_solvers_hex] tags = [:latticefields, :solvers] begin
using .LF_solvers_hex: fd
@testset "F3-20: multigrid on hex grids: the residual reduction per V-cycle" begin
    # 7×6 coarsens two levels, 13×11 and 12×8 three (odd axes: the last coarse cell takes three
    # children); 160×150 has generated levels above the bottom (lb = 2). Measured (F3-20 log):
    # 0.15–0.24 (two levels), 0.19–0.34 (three), 0.37–0.42 at 160×150; the Cartesian grids of
    # the same faces 0.25–0.33 (likely because the hexagonal lattice is not bipartite: with constant
    # faces D⁻¹A ends at 1.5, below
    # the smoother's λ = 2, so its top interval is smoothed less)
    for (dims, L) in (((7, 6), 2), ((13, 11), 3), ((12, 8), 3))
        for masked in (false, true), per in ((false, false), (true, true))
            ρ, l, _ = hex_factor(dims; masked, periodic = per)
            @test l == L
            @test ρ < 0.45 || (println("hex factor ", dims, " masked=", masked, " per=", per, ": ", ρ); false)
        end
    end
    for masked in (false, true)
        ρ, _, lb = hex_factor((160, 150); masked)
        @test lb == 2 && ρ < 0.45
    end
    # a coarse build that drops the diagonal fine faces (axial coarse faces of the axial fine faces
    # alone, no diagonal coarse face): the coarse correction overshoots and the cycles diverge
    # (measured 0.50 at 7×6, 2.1 at 13×11, 6.7 at 160×150)
    @test hex_factor((7, 6); rule = RuleWeights(; diagonal = 0.0))[1] > 0.45
    @test hex_factor((13, 11); rule = RuleWeights(; diagonal = 0.0))[1] > 1
end
end

@testitem "F3-20: the tangent solve of the diagonal face equals a finite difference" setup = [LF_solvers_hex] tags = [:latticefields, :solvers] begin
using .LF_solvers_hex: fd
@testset "F3-20: the tangent solve of the diagonal face equals a finite difference" begin
    op = CellOperator((12, 10); hex = true, face = (1.0, 0.8, 0.6), shift = 0.4,
        robin = ((nothing, nothing), ((1.0, 0.5, 0.7), nothing)), dirichlet = ((nothing, 1.0), (nothing, nothing)))
    f = rand(Xoshiro(5), 120)
    sv = hex_solver(op, Dict("in.f" => f))
    steady!(sv)
    u = solver_solution(sv)
    du = tangent!(sv, u, (:face, 3))
    ε = 1e-6
    op2 = CellOperator((12, 10); hex = true, face = (1.0, 0.8, 0.6 + ε), shift = 0.4,
        robin = op.robin, dirichlet = op.dirichlet)
    s2 = hex_solver(op2, Dict("in.f" => f))
    steady!(s2)
    fd = (solver_solution(s2) .- u) ./ ε
    @test norm(du .- fd) <= 1e-4 * norm(fd)
end
end
