# P6.0ab (ROADMAP Phase 6, step 0): two small API defects found by the docs authors
# (2026-10-01). Frozen (AUTONOMY §7.3).
#
# Defect 1: a kind table whose entries are expressions of parameters.
#   docs/src/manual/parameters.md: "`V₀ = 2A₀` | a default computed from other parameters",
#   and "A computed default such as `V_big = 2A₀` follows its inputs: `remake` with a new
#   `A₀` also changes `V_big`." Setting a parameter of an integrator re-derives the same way
#   (`set_parameter`, A-53). A kind table is a parameter (`J[kind, kind] = …`), so the same
#   rule applies to its entries: `J[kind, kind] = [0 Jx Jx; Jx 2 Jx-5; Jx Jx-5 14]` builds
#   with the values of `Jx`, and follows `Jx` under a constructor keyword, `remake` and
#   `integ.ps[:Jx] = v`. The need is recorded in the model sketches
#   (docs/design/research/model-specs/sketches/10_akeeb_invasion.md, friction 4: "Kind tables
#   cannot contain parameters"; scanning `J_LF` needs a host-built matrix today).
#   Today (2f54c1e9) `PottsProblem` raises
#       MethodError: no method matching Float64(::Symbolics.Num)
#   from `_param_value` (src/problem.jl:326), because `_resolve_defaults!` substitutes only
#   scalar symbolic defaults and leaves a `Matrix{Num}` / `Vector{Num}` unevaluated.
#
# Defect 2: `observe(sol, :name)`.
#   `observe`'s docstring (src/observed.jl): "Evaluate the model quantity or expression `x`
#   (e.g. `volume`, an `@observed` name, …)". Every other reader takes names as Symbols
#   (docs/src/manual/indexing.md: `sol[:x]`, `getu(sol, :x)`, `getp(prob, :λ)`), so
#   `observe(sol, :name)` must equal `observe(sol, x)` for the quantity `x` that
#   `Potts.lookup(sys, :name)` returns (an `@observed` name, a declared variable, a built-in,
#   a parameter), and likewise `observe(prob, :name)`. Today `observe(sol, :nA)` raises
#       ErrorException: cannot lower constant nA
#   (the Symbol is lowered as a literal). An unknown name must give an `ArgumentError` that
#   names it, not a lowering error or a MethodError (today: "cannot lower constant nosuch").
#
# Values are checked by hand. Contact pairs are counted once (docs/src/manual/energy.md).
using Test, Potts, PottsModels

# ---------------------------------------------------------------------------------------
# Defect 1 fixtures: two 3×3 cells, A at x = 3:5 and B at x = 6:8 (y = 3:5), on a 12×12
# lattice with von Neumann contacts. A–B share 3 pairs; A–medium and B–medium 12 − 3 = 9
# pairs each. Contacts: 9 J[M,A] + 9 J[M,B] + 3 J[A,B] = 18 Jx + 3 (Jx − 5).
# Cells: λ (9 − V₀[A])² + λ (9 − V₀[B])² = (9 − Vt)² + (9 − 2Vt)² (λ = 1).
#   Jx = 16, Vt = 9:  288 + 33 + 0 + 81  = 402
#   Jx = 30, Vt = 10: 540 + 75 + 1 + 121 = 737
#   Jx = 20, Vt = 9:  360 + 45 + 0 + 81  = 486

@potts_model P60abTable begin
    @kinds medium A B
    @parameters begin
        Jx = 16.0
        Vt = 9.0
        λ = 1.0
        J[kind, kind] = [0 Jx Jx; Jx 2 Jx-5; Jx Jx-5 14]
        V₀[kind] = [0.0, Vt, 2Vt]
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(A, B) => λ * (volume - V₀[kind])^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 10.0)
end

# the same model with the tables written out for Jx = 16, Vt = 9
@potts_model P60abTableLiteral begin
    @kinds medium A B
    @parameters begin
        λ = 1.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        V₀[kind] = [0.0, 9.0, 18.0]
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(A, B) => λ * (volume - V₀[kind])^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 10.0)
end

# a contact table from parameters that is not symmetric for the defaults (Jy ≠ Jx)
@potts_model P60abAsym begin
    @kinds medium A B
    @parameters begin
        Jx = 16.0
        Jy = 17.0
        J[kind, kind] = [0 Jx Jy; Jx 2 11; Jx 11 14]
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy contacts => J[kind, kind′]
    @sweep Metropolis(; temperature = 10.0)
end

function p60ab_blocks()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:5] .= 2
    return [ownership => σ, kind => [:A, :B]]
end

p60ab_J(x) = [0 x x; x 2 x-5; x x-5 14]

@testset "P6.0ab: small API defects" begin

@testset "P6.0ab defect 1: a kind table computed from parameters" begin
    prob = PottsProblem(P60abTable(; name = :kt), p60ab_blocks(), (0, 5); seed = 3)
    J = getp(prob, :J)(prob)
    V = getp(prob, :V₀)(prob)
    @test J == p60ab_J(16.0) && eltype(J) === Float64 && size(J) == (3, 3)
    @test V == [0.0, 9.0, 18.0] && eltype(V) === Float64
    @test total_energy(prob) == 402.0

    # the same values as the literal tables, and the same run
    lit = PottsProblem(P60abTableLiteral(; name = :kt), p60ab_blocks(), (0, 5); seed = 3)
    @test getp(lit, :J)(lit) == J && getp(lit, :V₀)(lit) == V
    @test total_energy(lit) == total_energy(prob)
    s1 = solve(prob, SequentialCPM())
    s2 = solve(lit, SequentialCPM())
    @test s1.u[end].σ == s2.u[end].σ
    @test total_energy(prob, s1.u[end]) == total_energy(lit, s2.u[end])

    # remake with new inputs re-derives both tables (as `V_big = 2A₀` does)
    p2 = remake(prob; p = [:Jx => 30.0, :Vt => 10.0])
    @test getp(p2, :J)(p2) == p60ab_J(30.0)
    @test getp(p2, :V₀)(p2) == [0.0, 10.0, 20.0]
    @test getp(p2, :Jx)(p2) == 30.0
    @test total_energy(p2) == 737.0
    @test typeof(p2.p) === typeof(prob.p)                       # nothing recompiles
    # an explicit table wins over its expression
    M = [0 5 5; 5 1 3; 5 3 1]
    p3 = remake(prob; p = [:J => M])
    @test getp(p3, :J)(p3) == M

    # a constructor keyword gives a new default; the table follows it
    p4 = PottsProblem(P60abTable(; name = :kt, Jx = 20.0), p60ab_blocks(), (0, 5); seed = 3)
    @test getp(p4, :J)(p4) == p60ab_J(20.0)
    @test total_energy(p4) == 486.0

    # setting the input on a running integrator re-derives the table
    integ = init(prob, SequentialCPM())
    step!(integ)
    integ.ps[:Jx] = 40.0
    @test integ.ps[:Jx] == 40.0
    @test integ.ps[:J] == p60ab_J(40.0)
    @test typeof(integ.p) === typeof(prob.p)

    # negative control: a table from parameters that is not symmetric for its values gives
    # the contact-table error, not a MethodError
    err = try
        PottsProblem(P60abAsym(; name = :asym), p60ab_blocks(), (0, 5))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test err isa ArgumentError && occursin("symmetric", sprint(showerror, err))
    # and it builds once the inputs make it symmetric
    ok = PottsProblem(P60abAsym(; name = :asym, Jy = 16.0), p60ab_blocks(), (0, 5))
    @test getp(ok, :J)(ok) == [0 16 16; 16 2 11; 16 11 14]
end

# ---------------------------------------------------------------------------------------
# Defect 2 fixture: two 3×3 cells of kind A (x = 3:5 and 7:9, y = 3:5 and 7:9) on a 12×12
# lattice, saved at every MCS 0:4. `age` counts MCS (`@after_mcs age += 1`), so at saved time
# t each cell's age is t; `nA` counts live A cells (2 throughout: no lifecycle, and a 9-site
# volume target at strength 1 keeps both cells alive at T = 10).

@potts_model P60abObs begin
    @kinds medium A
    @parameters λ = 1.0
    @variables age(cell) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => λ * (volume - 9.0)^2
    @after_mcs age += 1
    @observed nA ~ count(true for c in cells(A))
    @sweep Metropolis(; temperature = 10.0)
end

@testset "P6.0ab defect 2: observe by Symbol" begin
    sys = P60abObs(; name = :ob)
    σ = zeros(Int32, 12, 12); σ[3:5, 3:5] .= 1; σ[7:9, 7:9] .= 2
    prob = PottsProblem(sys, [ownership => σ, kind => [:A, :A]], (0, 4); seed = 1)
    sol = solve(prob, SequentialCPM(); saveat = 1)
    @test sol.t == 0:4
    sym(n) = Potts.lookup(sys, n)

    # an @observed name
    @test observe(sol, :nA) == [2, 2, 2, 2, 2]
    @test observe(sol, :nA) == observe(sol, sym(:nA)) == sol[:nA]
    @test observe(prob, :nA) == 2 == observe(prob, sym(:nA))
    # a declared cell variable
    @test observe(sol, :age) == [fill(Float64(t), 2) for t in 0:4]
    @test observe(sol, :age) == observe(sol, sym(:age))
    @test observe(prob, :age) == [0.0, 0.0]
    # a built-in
    @test observe(sol, :volume) == [u.cell.volume for u in sol.u]
    @test observe(prob, :volume) == [9, 9]
    # a parameter
    @test observe(sol, :λ) == [1.0, 1.0, 1.0, 1.0, 1.0] == observe(sol, sym(:λ))
    @test observe(prob, :λ) == 1.0

    # negative control: an unknown name is an ArgumentError that names it
    for x in (sol, prob)
        err = try
            observe(x, :nosuch)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test err isa ArgumentError && occursin("nosuch", sprint(showerror, err))
    end
end

end # P6.0ab
