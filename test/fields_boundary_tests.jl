# Values of a PDESystem's conditions (expressions of parameters, the
# coordinates `x`, `y`, `z` and the time), lowered into value fields. Oracles:
# LatticePDE's own run of the same PDESystem (no cells: the field does not depend on the CPM),
# hand values of the Robin slots, a manufactured solution with a time-dependent Dirichlet face
# and a space-dependent Neumann face (order 2) and the hand ghost-rule matrix of one
# BackwardEuler step.
# Before the fix (925110cc): 3 errors; each expression is refused at the model ("… is an
# expression of parameters; …"); the coordinates and `mcs` were refused there too.

@testsetup module FieldsBoundarySetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts, Test


# Models couple their fields with `@fields`
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))
isdefined(@__MODULE__, :observed_orders) || include(joinpath(@__DIR__, "shared", "stats_helpers.jl"))

module FbPDE
using ..FieldPDE
@variables c(..) dk(..) [input = true]
const X = (t, x, y)
const C = c(X...)
const Dx, Dy = Differential(x), Differential(y)
# the manufactured solution on `n × n` sites of spacing 1/n
function mms(n)
    @parameters Dd = 1.0
        return pdesys(
            [Dt(C) ~ Dd * laplacian(C) + (cos(π * x / 2) + x * y^2) - Dd * (1 + t) * (2x - (π^2 / 4) * cos(π * x / 2))],
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1 + t, c(t, 1, y) ~ (1 + t) * y^2, Dy(c(t, x, 1)) ~ 2 * (1 + t) * x], (n, n), [C], [Dd];
        spacing = 1 / n)
end
    # temporal MMS for ExplicitEuler: u = (1 + t)^2 * φ on 8 × 8 with small Dd so temporal error O(dt) dominates
    function mms_ee(n = 8)
        @parameters Dd = 0.002
        φ = cos(π * x / 2) + x * y^2
        Δφ = 2x - (π^2 / 4) * cos(π * x / 2)
        return pdesys(
            [Dt(C) ~ Dd * laplacian(C) + 2 * (1 + t) * φ - Dd * (1 + t)^2 * Δφ],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ (1 + t)^2, c(t, 1, y) ~ (1 + t)^2 * y^2, Dy(c(t, x, 1)) ~ 2 * (1 + t)^2 * x],
            (n, n), [C], [Dd]; spacing = 1 / n
        )
    end
site() = (@parameters Dc = 0.2 g1 = 1.0;
        pdesys(
            [Dt(C) ~ Dc * laplacian(C) - 0.1 * C],
              [c(0, x, y) ~ 0.0, (1 + 0.1y) * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0,
                  g1 * (1 + 0.5 * t) * c(t, 16, y) + 2.0 * Dx(c(t, 16, y)) ~ 0.0,
                  2.0 * c(t, x, 16) + (0.5 + 0.05x) * Dy(c(t, x, 16)) ~ 0.5], (16, 16), [C], [Dc, g1]))
    tab() = pdesys(
        [Dt(C) ~ dk(X...) * laplacian(C) - 0.05 * C], [c(0, x, y) ~ 1.0, (-0.5 - 0.1 * t) * c(t, 0, y) - 1.0 * Dx(c(t, 0, y)) ~ 0.0],
    (16, 16), [C, dk(X...)])
# the faces: Dirichlet values of parameters, a coordinate and the time; a Neumann flux of a coordinate
faces() = (@parameters Dc = 0.2 g1 = 1.0 g2 = 0.5 c0 = 2.0 ω = 0.3;
        pdesys(
            [Dt(C) ~ Dc * laplacian(C)], [
                c(0, x, y) ~ 0.0, c(t, 0, y) ~ g1 + g2, c(t, 12, y) ~ 0.5y, c(t, x, 0) ~ c0 * sin(ω * t),
                   Dy(c(t, x, 10)) ~ 0.1x], (12, 10), [C], [Dc, g1, g2, c0, ω]))
# Robin coefficients of parameters: α (`g1 + g2`) and β (`h1 + h2`, of ∂c/∂x on the low face)
robin() = (@parameters Dc = 0.2 g1 = 1.0 g2 = 0.5;
        pdesys([Dt(C) ~ Dc * laplacian(C)], [c(0, x, y) ~ 0.0, (g1 + g2) * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0], (12, 10), [C], [Dc, g1, g2])
    )
robin_beta() = (@parameters Dc = 0.2 h1 = 0.5 h2 = 0.25;
        pdesys([Dt(C) ~ Dc * laplacian(C)], [c(0, x, y) ~ 0.0, c(t, 0, y) - (h1 + h2) * Dx(c(t, 0, y)) ~ 1.0], (12, 10), [C], [Dc, h1, h2])
    )
# a Robin coefficient `g1 + r` that reads `r`: a coordinate (`:y`), the time (`:t`) or an input (`:vin`)
@variables vin(..) [input = true]
function bad(r)
    @parameters g1 = 1.0
    coef = g1 + (r === :y ? y : r === :t ? t : vin(X...))
        return pdesys([Dt(C) ~ laplacian(C)], [c(0, x, y) ~ 0.0, coef * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0], (8, 8), [C, vin(X...)], [g1])
end
    mid() = pdesys([Dt(C) ~ 0.2 * laplacian(C)], [c(0, x, y) ~ 1.0, (1 - t) * c(t, 0, y) - 0.5 * Dx(c(t, 0, y)) ~ 0.0], (16, 16), [C])
end


@potts_model FbFaces begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @fields FbPDE.faces()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbRobin begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @fields FbPDE.robin()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbRobinBeta begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @fields FbPDE.robin_beta()
    @sweep Metropolis(; temperature = 1.0)
end


fb_op(dims, p = []) = [ownership => zeros(Int32, dims...), kind => Symbol[], p...]

fb_run(M, k, fs; p = []) = Array(solve(PottsProblem(M(; name = :m), fb_op((12, 10), p), (0, k); field_solver = fs),
    SequentialCPM()).u[end].site.c)

# LatticePDE's own run of `sys` over `k` MCS (one window of length 1 each), parameters `p`
const LP = Potts.LatticePDE

function fb_own(sys, dims, k, fs; p = [])
    prob = LP.remake(LP.discretize(sys, LP.LatticeDiscretization(LP.Grid(dims); T = Float64)); tspan = (0.0, Float64(k)))
    isempty(p) || (prob = LP.remake(prob; p))
    return reshape(LP.solve(prob, fs; dt = 1.0).u[end], dims)   # the coupled run's solver, one window per MCS
end

# the coupled run against the owned one: bitwise for the explicit step, to the inner solver's
# tolerance for the implicit one
fb_same(a, o, fs) = fs isa ExplicitEuler ? a == o : maximum(abs, a .- o) <= 1e-9

fb_msg(f) = try
    f()
    "built"
catch e
    sprint(showerror, e)
end


# the manufactured solution u = (1 + t) φ, φ = cos(πx/2) + x y² on [0, 1]², with the source
# u_t − D Δu: u = 1 + t at x = 0 and (1 + t) y² at x = 1 (time-dependent Dirichlet faces),
# ∂u/∂y = 0 at y = 0 and 2(1 + t) x at y = 1 (a space-dependent Neumann face)
@potts_model _FbMMS begin
    @structural_parameters begin
        n = 16
    end
    @kinds medium A
    @lattice Lattice((n, n); boundary = Closed(), spacing = (1 / n, 1 / n))
    @fields FbPDE.mms(n)
    @sweep Metropolis(; temperature = 1.0)
end

FbMMS16(; name = :FbMMS16) = _FbMMS(; name, n = 16)
FbMMS32(; name = :FbMMS32) = _FbMMS(; name, n = 32)
FbMMS64(; name = :FbMMS64) = _FbMMS(; name, n = 64)

@potts_model _FbBadBcs begin
    @structural_parameters begin
        r = :y
    end
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @fields FbPDE.bad(r) (FbPDE.vin => volume[owner])
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbMMSEE begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed(), spacing = (1 / 8, 1 / 8))
    @fields FbPDE.mms_ee(8)
    @sweep Metropolis(; temperature = 1.0)
end


# Robin coefficients that vary by site or in time. The coupled run
# equals LatticePDE's own run of the PDESystem (prior `@boundary` oracle checked bitwise),
# and one BackwardEuler MCS equals the hand ghost-rule matrix.
# Before the fix (ca232825): the models are refused ("… reads `y`; … planned").
@potts_model FbSiteBcs begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @fields FbPDE.site()
    @sweep Metropolis(; temperature = 1.0)
end


# A kind table with a time-varying Robin face under the automatic explicit count
# (each window is counted with the tables and inputs of the bind; base 895c1a02: "reads tables
# that were not given" in the first window), and a face whose bound fails within the run's time
# span is refused at the problem, naming the time (base: the run threw partway through `solve`)
@potts_model FbTab begin
    @kinds medium A
    @parameters Dk[kind] = [0.2, 0.3]
    @lattice Lattice((16, 16); boundary = Closed())
    @fields FbPDE.tab() (FbPDE.dk => Dk[kind])
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbMid begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @fields FbPDE.mid()
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "condition values of parameters, coordinates and the time" setup = [FieldsBoundarySetup] tags = [:potts, :fields_boundary] begin
    @testset "condition values of parameters, coordinates and the time" begin
        for fs in (ExplicitEuler(; substeps = 2), BackwardEuler())
            a = fb_run(FbFaces, 6, fs)
            @test fb_same(a, fb_own(FbPDE.faces(), (12, 10), 6, fs), fs) && maximum(a) > 0.5
            w = fb_run(FbFaces, 6, fs; p = [:g1 => 2.0])
            @test fb_same(w, fb_own(FbPDE.faces(), (12, 10), 6, fs; p = [:g1 => 2.0]), fs) && w != a
        end
    end
end

@testitem "a Robin coefficient of parameters" setup = [FieldsBoundarySetup] tags = [:potts, :fields_boundary] begin
    @testset "a Robin coefficient of parameters" begin
        SII = Potts.SymbolicIndexingInterface
        slotv(M, s; p = []) = (pr = PottsProblem(M(; name = :m), fb_op((12, 10), p), (0, 1)); SII.getp(pr, s)(pr))
        @test slotv(FbRobin, :c_x_low_α) == 1.5 && slotv(FbRobin, :c_x_low_α; p = [:g1 => 3.0]) == 3.5   # g1 + g2
        for fs in (ExplicitEuler(; substeps = 2), BackwardEuler())
            a = fb_run(FbRobin, 6, fs)
            @test fb_same(a, fb_own(FbPDE.robin(), (12, 10), 6, fs), fs) && maximum(a) > 0
            w = fb_run(FbRobin, 6, fs; p = [:g1 => 3.0])
            @test fb_same(w, fb_own(FbPDE.robin(), (12, 10), 6, fs; p = [:g1 => 3.0]), fs) && w != a
        end
    end
end

@testitem "manufactured solution, order 2 (time-dependent Dirichlet, space-dependent Neumann)" setup = [FieldsBoundarySetup] tags = [:potts, :fields_boundary] begin
    @testset "manufactured solution, order 2 (time-dependent Dirichlet, space-dependent Neumann)" begin
        φ(x, y) = cos(π * x / 2) + x * y^2
        errs = map([16, 32, 64]) do n
            M = getfield(@__MODULE__, Symbol(:FbMMS, n))
            xs = ((1:n) .- 0.5) ./ n
            φ0 = [φ(x, y) for x in xs, y in xs]
            s = solve(PottsProblem(M(; name = :m), fb_op((n, n), [:c => φ0]), (0, 1); field_solver = BackwardEuler(; substeps = 20)),
                SequentialCPM())
            maximum(abs, Array(s.u[end].site.c) .- 2 .* φ0)
        end
        hs = [1 / n for n in (16, 32, 64)]
        om = observed_orders(hs, errs)
        @test all(o -> abs(o - 2) < 0.1, om) || (println("manufactured errors ", errs, " orders ", om); false)
        @test abs(observed_order(hs, errs) - 2) < 0.1
    end
end

@testitem "ExplicitEuler manufactured solution temporal convergence order 1" setup = [FieldsBoundarySetup] tags = [:potts, :fields_boundary] begin
    @testset "ExplicitEuler manufactured solution temporal convergence order 1" begin
        φ(x, y) = cos(π * x / 2) + x * y^2
        n = 8
        xs = ((1:n) .- 0.5) ./ n
        φ0 = [φ(x, y) for x in xs, y in xs]
        substeps = [4, 8, 16, 32]
        dts = [1.0 / k for k in substeps]
        errs = map(substeps) do k
            s = solve(
                PottsProblem(
                    FbMMSEE(; name = :m), fb_op((n, n), [:c => φ0]), (0, 1);
                    field_solver = ExplicitEuler(; substeps = k)
                ), SequentialCPM()
            )
            maximum(abs, Array(s.u[end].site.c) .- 4 .* φ0)
        end
        om = observed_orders(dts, errs)
        @test all(o -> abs(o - 1.0) < 0.15, om) || (println("EE MMS errors ", errs, " orders ", om); false)
        @test abs(observed_order(dts, errs) - 1.0) < 0.15
    end
end

# Slot convention: a slot means one quantity however the face is written (base 6d11bc85: the condition
# slot held −0.75, the coefficient of ∂c/∂x); a coefficient that reads more than parameters is
# refused in the model's words, naming the read and the PDESystem (base: LatticePDE's "… is one
# value at every site: …", with the first `@equations` line)
@testitem "one slot convention; the refusal names the read" setup = [FieldsBoundarySetup] tags = [:potts, :fields_boundary] begin
    @testset "one slot convention; the refusal names the read" begin
        SII = Potts.SymbolicIndexingInterface
        slotv(M) = (pr = PottsProblem(M(; name = :m), fb_op((12, 10)), (0, 1)); SII.getp(pr, :c_x_low_β)(pr))
        @test slotv(FbRobinBeta) == 0.75                                   # β of ∂c/∂n: h1 + h2
        for fs in (ExplicitEuler(; substeps = 2), BackwardEuler())
            a = fb_run(FbRobinBeta, 6, fs)
            @test fb_same(a, fb_own(FbPDE.robin_beta(), (12, 10), 6, fs), fs) && maximum(a) > 0
        end
        # (a coefficient of the coordinates or the time is a value field; one that reads an
        # input is refused, naming the read (the bound `volume`) and the PDESystem)
        for (r, word) in ((:y, "built"), (:t, "built"), (:vin, "volume"))
            M = _FbBadBcs(; name = Symbol(:FbBadBcs, r), r)
            e = fb_msg(() -> PottsProblem(M, fb_op((8, 8)), (0, 1)))
            @test occursin(word, e) || (println("condition ", r, ": ", e); false)
        end
    end
end

@testitem "per-site and time-varying Robin coefficients" setup = [FieldsBoundarySetup] tags = [:potts, :fields_boundary] begin
    @testset "per-site and time-varying Robin coefficients" begin
        run(M, k, fs; p = []) = Array(solve(PottsProblem(M(; name = :m), fb_op((16, 16), p), (0, k); field_solver = fs),
            SequentialCPM()).u[end].site.c)
        tight = BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 64))
        for fs in (ExplicitEuler(; substeps = 4), tight)
            a = run(FbSiteBcs, 3, fs)
            @test fb_same(a, fb_own(FbPDE.site(), (16, 16), 3, fs), fs) && maximum(a) > 0.1
            w = run(FbSiteBcs, 3, fs; p = [:g1 => 3.0])
            @test fb_same(w, fb_own(FbPDE.site(), (16, 16), 3, fs; p = [:g1 => 3.0]), fs) && w != a
        end
        # one MCS (t from 0 to 1) is one BackwardEuler step at t = 1: the hand ghost-rule matrix (h = 1,
        # site (i, j) at (i − ½, j − ½); ghost from `α (u_g + u_i)/2 + β (u_g − u_i) = g` with the outward β)
        n = 16
        lin(i, j) = i + (j - 1) * n
        L, b = zeros(n^2, n^2), zeros(n^2)
        for j in 1:n, i in 1:n
            r = lin(i, j)
            L[r, r] -= 0.1
            for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                ii, jj = i + di, j + dj
                if 1 <= ii <= n && 1 <= jj <= n
                    L[r, lin(ii, jj)] += 0.2
                    L[r, r] -= 0.2
                    continue
                end
                face = di < 0 ? (1 + 0.1 * (j - 0.5), 1.0, 1.0) : di > 0 ? (1 + 0.5 * 1.0, 2.0, 0.0) :
                       dj > 0 ? (2.0, 0.5 + 0.05 * (i - 0.5), 0.5) : nothing
                face === nothing && continue
                α, β, g = face
                den = α / 2 + β
                L[r, r] += 0.2 * ((β - α / 2) / den - 1)
                b[r] += 0.2 * g / den
            end
        end
        a = run(FbSiteBcs, 1, BackwardEuler(; substeps = 1, linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 64)))
        @test maximum(abs, vec(a) .- (Float64.((1:(n^2)) .== (1:(n^2))') - L) \ b) < 1e-10
    end
end

@testitem "windows counted with tables; a span that fails is refused at the problem" setup = [FieldsBoundarySetup] tags = [:potts, :fields_boundary] begin
    @testset "windows counted with tables; a span that fails is refused at the problem" begin
        s = solve(PottsProblem(FbTab(; name = :m), fb_op((16, 16)), (0, 3); field_solver = ExplicitEuler()), SequentialCPM())
        @test all(isfinite, Array(s.u[end].site.c))
        @test_throws ArgumentError PottsProblem(FbMid(; name = :m), fb_op((16, 16)), (0, 4); field_solver = ExplicitEuler())
        # a span that ends before it fails is accepted
        @test fb_msg(() -> PottsProblem(FbMid(; name = :m), fb_op((16, 16)), (0, 1); field_solver = ExplicitEuler())) == "built"
    end
end
