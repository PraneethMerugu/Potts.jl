# F4-12a (F4 design §3.8 FE-10): `@boundary` values are what `@bcs` takes: expressions of
# parameters, the coordinates `x`, `y`, `z`, `time` and `mcs`, lowered into F3-07's value
# fields. `Dirichlet(g1 + g2)`, `Dirichlet(0.5y)`, `Dirichlet(c0 * sin(ω * mcs))` and
# `Flux(0.1x)` equal the `@bcs` spellings bitwise; a Robin coefficient of parameters
# (`Robin(g1 + g2, β, g)`) is held by a computed parameter of its face and equals the declared
# computed parameter and the `@bcs` spelling bitwise; a manufactured solution with a
# time-dependent Dirichlet face and a space-dependent Neumann face converges at order 2.
# Base (925110cc, ~/lpwork/f4c/nc12-base.log): 3 errors; each expression is refused at the model ("… is an
# expression of parameters; …"); the coordinates and `mcs` were refused there too.
using Potts, Test

# F4-B4t: the models of the features that stay (the manufactured solution, per-site and
# time-varying Robin faces, kind tables with a time-varying face) couple their fields with
# `@fields`; the `@boundary` models and the tests that compare `@boundary` with `@bcs` stay as
# they are until `@boundary` goes (F4-B6)
isdefined(Main, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))
module FbPDE
using ..FieldPDE
@variables c(..) dk(..) [input = true]
const X = (t, x, y)
const C = c(X...)
const Dx, Dy = Differential(x), Differential(y)
# the manufactured solution on `n × n` sites of spacing 1/n
function mms(n)
    @parameters Dd = 1.0
    return pdesys([Dt(C) ~ Dd * Δ(C) + (cos(π * x / 2) + x * y^2) - Dd * (1 + t) * (2x - (π^2 / 4) * cos(π * x / 2))],
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1 + t, c(t, 1, y) ~ (1 + t) * y^2, Dy(c(t, x, 1)) ~ 2 * (1 + t) * x], (n, n), [C], [Dd];
        spacing = 1 / n)
end
site() = (@parameters Dc = 0.2 g1 = 1.0;
          pdesys([Dt(C) ~ Dc * Δ(C) - 0.1 * C],
              [c(0, x, y) ~ 0.0, (1 + 0.1y) * c(t, 0, y) - Dx(c(t, 0, y)) ~ 1.0,
                  g1 * (1 + 0.5 * t) * c(t, 16, y) + 2.0 * Dx(c(t, 16, y)) ~ 0.0,
                  2.0 * c(t, x, 16) + (0.5 + 0.05x) * Dy(c(t, x, 16)) ~ 0.5], (16, 16), [C], [Dc, g1]))
tab() = pdesys([Dt(C) ~ dk(X...) * Δ(C) - 0.05 * C], [c(0, x, y) ~ 1.0, (-0.5 - 0.1 * t) * c(t, 0, y) - 1.0 * Dx(c(t, 0, y)) ~ 0.0],
    (16, 16), [C, dk(X...)])
mid() = pdesys([Dt(C) ~ 0.2 * Δ(C)], [c(0, x, y) ~ 1.0, (1 - t) * c(t, 0, y) - 0.5 * Dx(c(t, 0, y)) ~ 0.0], (16, 16), [C])
end

@potts_model FbFaces begin
    @kinds medium A
    @parameters Dc = 0.2 g1 = 1.0 g2 = 0.5 c0 = 2.0 ω = 0.3
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c)
    @boundary c begin
        x => (Dirichlet(g1 + g2), Dirichlet(0.5y))
        y => (Dirichlet(c0 * sin(ω * mcs)), Flux(0.1x))
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FbFacesBcs begin
    @kinds medium A
    @parameters Dc = 0.2 g1 = 1.0 g2 = 0.5 c0 = 2.0 ω = 0.3
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c)
    @bcs begin
        c(t, 0, y) ~ g1 + g2
        c(t, 12, y) ~ 0.5y
        c(t, x, 0) ~ c0 * sin(ω * mcs)
        Differential(y)(c(t, x, 10)) ~ 0.1x
    end
    @sweep Metropolis(; temperature = 1.0)
end
# a Robin coefficient of parameters: inline, a declared computed parameter, and `@bcs`
@potts_model FbRobin begin
    @kinds medium A
    @parameters Dc = 0.2 g1 = 1.0 g2 = 0.5
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c)
    @boundary c x => (Robin(g1 + g2, 1.0, 1.0), NoFlux())
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FbRobinDeclared begin
    @kinds medium A
    @parameters Dc = 0.2 g1 = 1.0 g2 = 0.5 ra = g1 + g2
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c)
    @boundary c x => (Robin(ra, 1.0, 1.0), NoFlux())
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FbRobinBcs begin
    @kinds medium A
    @parameters Dc = 0.2 g1 = 1.0 g2 = 0.5
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c)
    @bcs (g1 + g2) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end

# review: β written in `@boundary` and in `@bcs` on a low face: one slot value (β of ∂c/∂n)
@potts_model FbRobinBeta begin
    @kinds medium A
    @parameters Dc = 0.2 h1 = 0.5 h2 = 0.25
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c)
    @boundary c x => (Robin(1.0, h1 + h2, 1.0), NoFlux())
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FbRobinBetaBcs begin
    @kinds medium A
    @parameters Dc = 0.2 h1 = 0.5 h2 = 0.25
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c)
    @bcs c(t, 0, y) - (h1 + h2) * Differential(x)(c(t, 0, y)) ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end

fb_op(dims, p = []) = [ownership => zeros(Int32, dims...), kind => Symbol[], p...]
fb_run(M, k, fs; p = []) = Array(solve(PottsProblem(M(; name = :m), fb_op((12, 10), p), (0, k); field_solver = fs),
    SequentialCPM()).u[end].site.c)
fb_msg(f) = try
    f()
    "built"
catch e
    sprint(showerror, e)
end

@testset "F4-12a: @boundary expression values equal @bcs (bitwise)" begin
    for fs in (ExplicitEuler(; substeps = 2), BackwardEuler())
        a, b = fb_run(FbFaces, 6, fs), fb_run(FbFacesBcs, 6, fs)
        @test a == b && maximum(a) > 0.5
        @test fb_run(FbFaces, 6, fs; p = [:g1 => 2.0]) == fb_run(FbFacesBcs, 6, fs; p = [:g1 => 2.0]) != a
    end
    # a value that reads something else is refused at the model, naming it
    e = fb_msg(() -> Base.invokelatest(eval(:(@potts_model FbBad begin
        @kinds medium A
        @variables c(field) = 0.0
        @lattice Lattice((8, 8); boundary = Closed())
        @equations D(c) ~ Δ(c)
        @boundary c x => (Dirichlet(volume), NoFlux())
        @sweep Metropolis(; temperature = 1.0)
    end)); name = :f))
    @test occursin("reads `volume`", e) && occursin("`time` and `mcs`", e)
end

@testset "F4-12a: a Robin coefficient of parameters" begin
    m = FbRobin(; name = :m)
    @test :c_x_low_α in [Potts.info(q).name for q in Potts.parameters(m)]
    for fs in (ExplicitEuler(; substeps = 2), BackwardEuler())
        a = fb_run(FbRobin, 6, fs)
        @test a == fb_run(FbRobinDeclared, 6, fs) == fb_run(FbRobinBcs, 6, fs) && maximum(a) > 0
        w = fb_run(FbRobin, 6, fs; p = [:g1 => 3.0])
        @test w == fb_run(FbRobinDeclared, 6, fs; p = [:g1 => 3.0]) == fb_run(FbRobinBcs, 6, fs; p = [:g1 => 3.0]) != a
    end
    # a coefficient that reads a field is refused (one that reads a coordinate or the time is a
    # value field, F4-12b below)
    e = fb_msg(() -> Base.invokelatest(eval(:(@potts_model FbBadRobin begin
        @kinds medium A
        @variables c(field) = 0.0
        @lattice Lattice((8, 8); boundary = Closed())
        @equations D(c) ~ Δ(c)
        @boundary c x => (Robin(1 + c, 1.0, 0.0), NoFlux())
        @sweep Metropolis(; temperature = 1.0)
    end)); name = :f))
    @test occursin("reads `c`", e) && occursin("`time` and `mcs`", e)
end

# the manufactured solution u = (1 + t) φ, φ = cos(πx/2) + x y² on [0, 1]², with the source
# u_t − D Δu: u = 1 + t at x = 0 and (1 + t) y² at x = 1 (time-dependent Dirichlet faces),
# ∂u/∂y = 0 at y = 0 and 2(1 + t) x at y = 1 (a space-dependent Neumann face)
for n in (16, 32, 64)
    @eval @potts_model $(Symbol(:FbMMS, n)) begin
        @kinds medium A
        @lattice Lattice(($n, $n); boundary = Closed(), spacing = (1 / $n, 1 / $n))
        @fields FbPDE.mms($n)
        @sweep Metropolis(; temperature = 1.0)
    end
end

@testset "F4-12a: manufactured solution, order 2 (time-dependent Dirichlet, space-dependent Neumann)" begin
    φ(x, y) = cos(π * x / 2) + x * y^2
    errs = map((16, 32, 64)) do n
        M = getfield(@__MODULE__, Symbol(:FbMMS, n))
        xs = ((1:n) .- 0.5) ./ n
        φ0 = [φ(x, y) for x in xs, y in xs]
        s = solve(PottsProblem(M(; name = :m), fb_op((n, n), [:c => φ0]), (0, 1); field_solver = BackwardEuler(; substeps = 20)),
            SequentialCPM())
        maximum(abs, Array(s.u[end].site.c) .- 2 .* φ0)
    end
    om = log2.(errs[1:2] ./ errs[2:3])
    @test all(o -> abs(o - 2) < 0.1, om) || (println("F4-12a manufactured errors ", errs, " orders ", om); false)
end

# F4-12a review: a slot means one quantity however the face is written (base 6d11bc85: the `@bcs`
# slot held −0.75, the coefficient of ∂c/∂x); a `@bcs` coefficient that reads more than
# parameters is refused in the model's words, naming the read and the `@bcs` line (base: LatticePDE's
# "… is one value at every site: …", with the first `@equations` line)
@testset "F4-12a review: one slot convention; the @bcs refusal names the read" begin
    SII = Potts.SymbolicIndexingInterface
    slotv(M) = (pr = PottsProblem(M(; name = :m), fb_op((12, 10)), (0, 1)); SII.getp(pr, :c_x_low_β)(pr))
    @test slotv(FbRobinBeta) == slotv(FbRobinBetaBcs) == 0.75
    for fs in (ExplicitEuler(; substeps = 2), BackwardEuler())
        a = fb_run(FbRobinBeta, 6, fs)
        @test a == fb_run(FbRobinBetaBcs, 6, fs) && maximum(a) > 0
    end
    # (F4-12b: a `@bcs` coefficient of the coordinates or `mcs` is a value field; one that reads
    # an input is refused, naming the read and the `@bcs` line)
    for (coef, word) in ((:(g1 + y), "built"), (:(g1 + mcs), "built"), (:(g1 + volume), "reads `volume`"))
        M = eval(:(@potts_model $(Symbol(:FbBadBcs, hash(coef))) begin
            @kinds medium A
            @parameters g1 = 1.0
            @variables c(field) = 0.0
            @lattice Lattice((8, 8); boundary = Closed())
            @equations D(c) ~ Δ(c)
            @bcs $coef * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 1.0
            @sweep Metropolis(; temperature = 1.0)
        end))
        e = fb_msg(() -> PottsProblem(Base.invokelatest(M; name = :f), fb_op((8, 8)), (0, 1)))
        @test occursin(word, e) && (word == "built" || (occursin("in @bcs", e) && !occursin("step_index", e))) ||
              (println("F4-12b @bcs ", coef, ": ", e); false)
    end
end

# F4-12b (rulings Q14–Q17): Robin coefficients that vary by site or in time. `@boundary` and
# the PDESystem's conditions (`FbSiteBcs`, `@bcs` before F4-B4t) equal each other bitwise, and one
# BackwardEuler MCS equals the hand ghost-rule matrix.
# Base (ca232825, ~/lpwork/f4c/nc12b-base.log): the models are refused ("… reads `y`; … planned, F4-12b").
@potts_model FbSite begin
    @kinds medium A
    @parameters Dc = 0.2 g1 = 1.0
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); boundary = Closed())
    @equations D(c) ~ Dc * Δ(c) - 0.1 * c
    @boundary c begin
        x => (Robin(1 + 0.1y, 1.0, 1.0), Robin(g1 * (1 + 0.5 * time), 2.0, 0.0))
        y => (NoFlux(), Robin(2.0, 0.5 + 0.05x, 0.5))
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FbSiteBcs begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @fields FbPDE.site()
    @sweep Metropolis(; temperature = 1.0)
end

@testset "F4-12b: per-site and time-varying Robin coefficients (A)" begin
    run(M, k, fs; p = []) = Array(solve(PottsProblem(M(; name = :m), fb_op((16, 16), p), (0, k); field_solver = fs),
        SequentialCPM()).u[end].site.c)
    tight = BackwardEuler(; inner = DevicePCG(; rtol = 1e-12, budget = 64))
    for fs in (ExplicitEuler(; substeps = 4), tight)
        a = run(FbSite, 3, fs)
        @test a == run(FbSiteBcs, 3, fs) && maximum(a) > 0.1
        @test run(FbSite, 3, fs; p = [:g1 => 3.0]) == run(FbSiteBcs, 3, fs; p = [:g1 => 3.0]) != a
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
    a = run(FbSiteBcs, 1, BackwardEuler(; substeps = 1, inner = DevicePCG(; rtol = 1e-12, budget = 64)))
    @test maximum(abs, vec(a) .- (Float64.((1:(n^2)) .== (1:(n^2))') - L) \ b) < 1e-10
end

# F4-12b review: a kind table with a time-varying Robin face under the automatic explicit count
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
@testset "F4-12b review: windows counted with tables; a span that fails is refused at the problem" begin
    s = solve(PottsProblem(FbTab(; name = :m), fb_op((16, 16)), (0, 3); field_solver = ExplicitEuler()), SequentialCPM())
    @test all(isfinite, Array(s.u[end].site.c))
    e = fb_msg(() -> PottsProblem(FbMid(; name = :m), fb_op((16, 16)), (0, 4); field_solver = ExplicitEuler()))
    @test occursin("fails in the window ending at t = 2", e) && occursin("Robin coefficients", e) && !occursin("``", e) ||
          (println("F4-12b span ", e); false)
    # a span that ends before it fails is accepted
    @test fb_msg(() -> PottsProblem(FbMid(; name = :m), fb_op((16, 16)), (0, 1); field_solver = ExplicitEuler())) == "built"
end
