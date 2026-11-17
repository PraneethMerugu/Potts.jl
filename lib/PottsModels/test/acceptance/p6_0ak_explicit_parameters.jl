# P6.0ak (ROADMAP Phase 6, step 0): computed parameters and the changes that touch them.
#
# A parameter whose default is an expression of other parameters (a scalar `β = 2α`, or a
# kind table whose entries are expressions, D-111) is "computed". Before D-F2-1 (D-112) an
# explicit value of it could be given (`remake`, a setter, the operating point) and survived
# changes that touched none of its inputs.
#
# Rule (D-F2-1, as in ModelingToolkit). A computed parameter is read-only:
#   * every write of it (an operating-point entry, `remake(prob; p = …)`, `integ.ps[x] = v`,
#     `setp`) is an `ArgumentError` that names it, its expression and its base inputs, and
#     nothing is set;
#   * after every change of base parameters, every computed parameter is derived again from
#     them, along chains: α → β = 2α → γ = β + 1, and a kind table whose entries read β and γ
#     (`V₀[kind] = [0, γ, β]`) follows both;
#   * a fixed value is a redeclaration: the constructor keyword `P60akChain(; β = 5.0)` makes
#     β a base parameter (a number default), so it then survives every change, and what reads
#     it follows it;
#   * a parameter object given whole (a checkpoint's `p`) gives its base values; the computed
#     ones are derived again, so a checkpoint restores bitwise;
#   * values keep the problem's scalar type (Float32 problems stay Float32).
#
# Energies are checked by hand. Fixture: two 3×3 cells on a 12×12 lattice with von Neumann
# contacts, P at x = 3:5 and Q at x = 6:8 (y = 3:5). P–Q share 3 contact pairs; P–medium and
# Q–medium 12 − 3 = 9 pairs each (pairs counted once, docs/src/manual/energy.md). So
#   contacts = 9 J[M,P] + 9 J[M,Q] + 3 J[P,Q]
#     J = Jf(x) = [0 x x; x 2 x-5; x x-5 14]: 21x − 15  (x = 16: 321; x = 20: 405)
#     J = M     = [0 5 5; 5 1 3; 5 3 1]:       45 + 45 + 9 = 99
#   cells = λ ((9 − V₀[P])² + (9 − V₀[Q])²) with V₀ = [0, γ, β] by default.
# Defaults α = 4, β = 8, γ = 9, λ = 1, Jx = 16: E = 321 + (0 + 1) = 322.
using Test, Potts, PottsModels

@potts_model P60akChain begin
    @kinds medium P Q
    @parameters begin
        α = 4.0
        β = 2α
        γ = β + 1
        λ = 1.0
        Jx = 16.0
        J[kind, kind] = [0 Jx Jx; Jx 2 Jx-5; Jx Jx-5 14]
        V₀[kind] = [0.0, γ, β]
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => λ * (volume - V₀[kind])^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 10.0)
end

function p60ak_blocks()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:5] .= 2
    return [ownership => σ, kind => [:P, :Q]]
end

p60ak_Jf(x) = [0 x x; x 2 x-5; x x-5 14]
const P60AK_M = [0 5 5; 5 1 3; 5 3 1]

# the values a test reads, as a NamedTuple of plain arrays/numbers
p60ak_vals(q) = (α = getp(q, :α)(q), β = getp(q, :β)(q), γ = getp(q, :γ)(q), λ = getp(q, :λ)(q),
    Jx = getp(q, :Jx)(q), J = Matrix(getp(q, :J)(q)), V₀ = Vector(getp(q, :V₀)(q)))
p60ak_ivals(i) = (α = i.ps[:α], β = i.ps[:β], γ = i.ps[:γ], λ = i.ps[:λ], Jx = i.ps[:Jx],
    J = Matrix(i.ps[:J]), V₀ = Vector(i.ps[:V₀]))

function p60ak_error(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end

# a write of computed parameter `name` refused, naming it and its base inputs `ins`
p60ak_refused(f, name, ins...) = (e = p60ak_error(f); e isa ArgumentError &&
    (m = sprint(showerror, e); occursin("`$name` is computed from", m) && all(i -> occursin("`$i`", m), ins)))

@testset "P6.0ak: computed parameters are read-only and follow their inputs" begin
    sys = P60akChain(; name = :chain)
    op = p60ak_blocks()
    M = P60AK_M
    prob = PottsProblem(sys, op, (0, 5); seed = 7)
    # the fixed-value routes: J = M, or β = 5, declared with a number (base parameters)
    sysJ = P60akChain(; name = :chain, J = M)
    sysβ = P60akChain(; name = :chain, β = 5.0)
    pJ = PottsProblem(sysJ, op, (0, 5); seed = 7)
    pβ = PottsProblem(sysβ, op, (0, 5); seed = 7)

    @testset "defaults (control)" begin
        v = p60ak_vals(prob)
        @test (v.α, v.β, v.γ, v.λ, v.Jx) == (4.0, 8.0, 9.0, 1.0, 16.0)
        @test v.J == p60ak_Jf(16.0) && v.V₀ == [0.0, 9.0, 8.0]
        @test total_energy(prob) == 322.0
        # a computed parameter follows its inputs (β, γ, V₀ from α)
        q = remake(prob; p = [:α => 5.0])
        v = p60ak_vals(q)
        @test (v.β, v.γ, v.V₀, v.J) == (10.0, 11.0, [0.0, 11.0, 10.0], p60ak_Jf(16.0))
        @test total_energy(q) == 321 + 4 + 1                  # 326
    end

    @testset "a table: writes refused, derived from its input" begin
        @test p60ak_refused(() -> remake(prob; p = [:J => M]), :J, :Jx)
        @test p60ak_refused(() -> remake(prob; p = [:Jx => 20.0, :J => M]), :J, :Jx)   # refused whole
        @test p60ak_vals(prob).J == p60ak_Jf(16.0)
        # its input re-derives it, and it stays the expression's value through other changes
        r1 = remake(prob; p = [:Jx => 20.0])
        @test p60ak_vals(r1).J == p60ak_Jf(20.0)
        @test total_energy(r1) == 405 + 1                     # 406
        r2 = remake(r1; p = [:λ => 3.0])
        @test p60ak_vals(r2).J == p60ak_Jf(20.0)
        @test p60ak_vals(remake(r2; p = [:Jx => 30.0])).J == p60ak_Jf(30.0)
        @test typeof(r2.p) === typeof(prob.p)
        # the fixed-value route: J declared with a number survives every change
        @test p60ak_vals(pJ).J == M
        @test total_energy(pJ) == 99 + 1                      # 100
        q2 = remake(pJ; p = [:λ => 3.0])
        @test p60ak_vals(q2).J == M && p60ak_vals(q2).λ == 3.0
        @test total_energy(q2) == 99 + 3                      # 102
        q3 = remake(pJ; p = [:α => 5.0])
        v = p60ak_vals(q3)
        @test v.J == M && (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        @test total_energy(q3) == 99 + 4 + 1                  # 104
        @test p60ak_vals(remake(pJ; p = [:Jx => 20.0, :J => M])).J == M
        @test typeof(pJ.p) !== typeof(prob.p)                 # a new parameter type
    end

    @testset "scalars and chains" begin
        # writes of β, γ or V₀ are refused, naming their base input α
        @test p60ak_refused(() -> remake(prob; p = [:β => 5.0]), :β, :α)
        @test p60ak_refused(() -> remake(prob; p = [:γ => 7.0]), :γ, :α)
        @test p60ak_refused(() -> remake(prob; p = [:V₀ => [0.0, 9.0, 9.0]]), :V₀, :α)
        @test p60ak_refused(() -> remake(prob; p = [:α => 5.0, :β => 3.0]), :β, :α)
        # α moves β, γ and V₀ along the chain; λ and Jx move none of them
        s4 = remake(prob; p = [:α => 5.0])
        v = p60ak_vals(s4)
        @test (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        @test total_energy(s4) == 321 + 4 + 1                 # 326
        v = p60ak_vals(remake(s4; p = [:λ => 2.0, :Jx => 20.0]))
        @test (v.β, v.γ, v.V₀, v.J) == (10.0, 11.0, [0.0, 11.0, 10.0], p60ak_Jf(20.0))
        # the fixed-value route: β declared with a number; γ and V₀ follow it
        v = p60ak_vals(pβ)
        @test (v.α, v.β, v.γ, v.V₀) == (4.0, 5.0, 6.0, [0.0, 6.0, 5.0])
        @test total_energy(pβ) == 321 + 9 + 16                # 346
        s2 = remake(pβ; p = [:λ => 2.0])
        v = p60ak_vals(s2)
        @test (v.β, v.γ, v.V₀) == (5.0, 6.0, [0.0, 6.0, 5.0])
        @test total_energy(s2) == 321 + 2 * 25                # 371
        s3 = remake(pβ; p = [:Jx => 20.0])
        v = p60ak_vals(s3)
        @test (v.β, v.γ, v.J) == (5.0, 6.0, p60ak_Jf(20.0))
        @test total_energy(s3) == 405 + 25                    # 430
        # β is a base parameter now: α no longer moves it; β itself moves γ and V₀
        @test p60ak_vals(remake(pβ; p = [:α => 5.0])).β == 5.0
        t3 = remake(pβ; p = [:β => 4.0])
        v = p60ak_vals(t3)
        @test (v.α, v.β, v.γ, v.V₀) == (4.0, 4.0, 5.0, [0.0, 5.0, 4.0])
        @test total_energy(t3) == 321 + 16 + 25               # 362
        @test p60ak_refused(() -> remake(pβ; p = [:γ => 7.0]), :γ, :β)
    end

    @testset "integrator setters" begin
        integ = init(pJ, SequentialCPM())
        step!(integ)
        integ.ps[:λ] = 3.0
        @test p60ak_ivals(integ).J == M
        setp(integ, :α)(integ, 5.0)
        v = p60ak_ivals(integ)
        @test v.J == M && (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        @test typeof(integ.p) === typeof(pJ.p)

        i2 = init(prob, SequentialCPM())
        for f in (() -> (i2.ps[:J] = M), () -> (i2.ps[:β] = 5.0), () -> setp(i2, :γ)(i2, 7.0),
                  () -> setp(i2, [:λ, :V₀])(i2, [2.0, [0.0, 9.0, 9.0]]))
            @test p60ak_error(f) isa ArgumentError
        end
        v = p60ak_ivals(i2)
        @test (v.β, v.γ, v.λ, v.J) == (8.0, 9.0, 1.0, p60ak_Jf(16.0))   # nothing set
        setp(i2, :Jx)(i2, 18.0)
        @test p60ak_ivals(i2).J == p60ak_Jf(18.0)            # Jx is J's input
        i2.ps[:α] = 5.0
        v = p60ak_ivals(i2)
        @test (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        # the run reads the derived values: the integrator's parameters give the hand energy
        i3 = init(pβ, SequentialCPM())
        i3.ps[:λ] = 2.0
        @test total_energy(remake(pβ; p = i3.p)) == 371.0
    end

    @testset "operating point" begin
        @test p60ak_refused(() -> PottsProblem(sys, [op; :J => M], (0, 5); seed = 7), :J, :Jx)
        @test p60ak_refused(() -> PottsProblem(sys, [op; :β => 5.0], (0, 5); seed = 7), :β, :α)
        @test p60ak_refused(() -> PottsProblem(sys, [op; Potts.lookup(sys, :β) => 5.0], (0, 5); seed = 7), :β, :α)
        # an input in the operating point (control): the computed values follow it
        pa = PottsProblem(sys, [op; :α => 5.0], (0, 5); seed = 7)
        @test (p60ak_vals(pa).β, p60ak_vals(pa).γ) == (10.0, 11.0)
        @test p60ak_vals(remake(pa; p = [:λ => 2.0])).β == 10.0
        # a base parameter of the route model in the operating point
        pe = PottsProblem(sysβ, [op; :β => 4.0], (0, 5); seed = 7)
        @test p60ak_vals(pe).γ == 5.0 && total_energy(pe) == 362.0
    end

    @testset "checkpoint" begin
        integ = init(remake(pβ; p = [:Jx => 20.0]), SequentialCPM())
        step!(integ)
        ck = checkpoint(integ)
        path = joinpath(mktempdir(), "p60ak.jls")
        save_checkpoint(path, ck)
        ck2 = load_checkpoint(path)
        @test Matrix(ck2.p.J) == p60ak_Jf(20.0) && ck2.p.β == 5.0 && ck2.p.γ == 6.0
        # a problem remade with the checkpoint's parameters restores them bitwise
        r = remake(pβ; p = ck2.p)
        @test r.p == ck2.p
        @test total_energy(r) == 405 + 25                     # 430
        r2 = remake(r; p = [:λ => 3.0])
        v = p60ak_vals(r2)
        @test v.J == p60ak_Jf(20.0) && (v.β, v.γ) == (5.0, 6.0)
        @test total_energy(r2) == 405 + 3 * 25                # 480
        # a hand-edited object gets consistent computed values (γ follows β), never a mix
        hand = Potts._with_values(ck2.p, merge(NamedTuple(ck2.p), (γ = 1.0,)))
        @test p60ak_vals(remake(pβ; p = hand)).γ == 6.0
        # a continuation from the checkpoint, then a setter of another parameter
        i2 = init(remake(pβ; p = [:Jx => 20.0]), SequentialCPM(); checkpoint = ck2)
        @test i2.t == 1
        i2.ps[:λ] = 2.0
        v = p60ak_ivals(i2)
        @test v.J == p60ak_Jf(20.0) && v.β == 5.0
        step!(i2)
        @test i2.t == 2
    end

    @testset "Float32" begin
        p32 = PottsProblem(sysJ, op, (0, 5); seed = 7, T = Float32)
        q = remake(p32; p = [:λ => 3.0])
        J = getp(q, :J)(q)
        @test eltype(J) === Float32 && Matrix(J) == Float32.(M)
        @test typeof(q.p) === typeof(p32.p)
        @test total_energy(q) == 102.0f0
        s = remake(PottsProblem(sysβ, op, (0, 5); seed = 7, T = Float32); p = [:λ => 2.0])
        @test getp(s, :β)(s) === 5.0f0 && getp(s, :γ)(s) === 6.0f0
        @test total_energy(s) == 371.0f0
        i32 = init(p32, SequentialCPM())
        i32.ps[:α] = 5.0
        @test eltype(i32.ps[:J]) === Float32 && Matrix(i32.ps[:J]) == Float32.(M)
        @test i32.ps[:β] === 10.0f0
    end

    @testset "negative controls" begin
        # an asymmetric contact table is still rejected
        err = p60ak_error(() -> remake(pJ; p = [:J => [0 1 2; 1 0 0; 3 0 0]]))
        @test err isa ArgumentError && occursin("symmetric", sprint(showerror, err))
        err = p60ak_error(() -> (i = init(pJ, SequentialCPM()); i.ps[:J] = [0 1 2; 1 0 0; 3 0 0]))
        @test err isa ArgumentError && occursin("symmetric", sprint(showerror, err))
        # unknown names are still errors
        @test p60ak_error(() -> remake(pJ; p = [:nosuch => 1.0])) isa ArgumentError
        # a kind table keeps its size
        @test p60ak_error(() -> remake(pJ; p = [:J => [0 1; 1 0]])) isa ArgumentError
        # nothing leaks into another problem: prob itself is unchanged
        @test p60ak_vals(prob).J == p60ak_Jf(16.0) && p60ak_vals(prob).β == 8.0
        @test p60ak_vals(remake(prob; p = [:λ => 3.0])).J == p60ak_Jf(16.0)
    end
end
