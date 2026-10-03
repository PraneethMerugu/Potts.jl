# P6.0ak (ROADMAP Phase 6, step 0): an explicit value of a computed parameter survives a
# change of an unrelated parameter. Frozen (AUTONOMY §7.2).
#
# A parameter whose default is an expression of other parameters (a scalar `β = 2α`, or a
# kind table whose entries are expressions, D-111) is "computed". Today (eee2dec3) every
# `remake(prob; p = …)` and every integrator setter (`integ.ps[x] = v`, `setp`) re-derives
# every computed parameter it does not set (`_derived_parameters`, src/problem.jl), so an
# explicit value is lost at the next change of an unrelated parameter:
#     remake(remake(prob; p = [:J => M]); p = [:λ => 3]).p.J == the expression's value, not M
# (P6.0ab review, /tmp/p60ab_review/s2.jl; e.g. a `J_LF` scan whose ensemble `prob_func`
# remakes another parameter).
#
# Rule (D-112). A change is the set of parameters a `remake(prob; p = map)` or one setter
# names. A computed parameter is re-derived from its expression by a change iff it is not
# named in the change and one of its expression's inputs is named in the change or is
# itself re-derived by it (transitively, along the chain of computed parameters). Every
# other parameter keeps its current value, explicit or not. So:
#   * an explicit value (from `remake`, a setter, or the operating point of `PottsProblem`)
#     survives any later change that touches none of its inputs;
#   * a change of one of its inputs re-derives it, overriding the explicit value (the
#     expression is the parameter's meaning; give the value again with the input to keep it);
#   * chains: α → β = 2α → γ = β + 1. With β explicit, a change of α re-derives β (α is β's
#     input) and so γ; a change of β alone re-derives γ and keeps α; a change of λ keeps
#     both. With γ explicit, a change of α re-derives β and so γ. A kind table whose entries
#     read β and γ (`V₀[kind] = [0, γ, β]`) is re-derived whenever β or γ is;
#   * a value named in the change itself is never re-derived (as today);
#   * a parameter object given whole (`remake(prob; p = ck.p)` with a checkpoint's
#     parameters) sets every value; nothing is re-derived then or by a later change that
#     touches no input;
#   * the operating point and defaults at `PottsProblem` build as today (every computed
#     parameter not in the operating point is evaluated from the values in effect).
#   * Values keep the problem's scalar type (Float32 problems stay Float32).
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
        contacts => J[kind, kind′]
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

@testset "P6.0ak: explicit parameter values survive unrelated changes" begin
    sys = P60akChain(; name = :chain)
    op = p60ak_blocks()
    M = P60AK_M
    prob = PottsProblem(sys, op, (0, 5); seed = 7)

    @testset "defaults (control)" begin
        v = p60ak_vals(prob)
        @test (v.α, v.β, v.γ, v.λ, v.Jx) == (4.0, 8.0, 9.0, 1.0, 16.0)
        @test v.J == p60ak_Jf(16.0) && v.V₀ == [0.0, 9.0, 8.0]
        @test total_energy(prob) == 322.0
        # a computed parameter never set explicitly follows its inputs (β, γ, V₀ from α)
        q = remake(prob; p = [:α => 5.0])
        v = p60ak_vals(q)
        @test (v.β, v.γ, v.V₀, v.J) == (10.0, 11.0, [0.0, 11.0, 10.0], p60ak_Jf(16.0))
        @test total_energy(q) == 321 + 4 + 1                  # 326
    end

    @testset "explicit table, then remake" begin
        q1 = remake(prob; p = [:J => M])
        @test p60ak_vals(q1).J == M
        @test total_energy(q1) == 99 + 1                      # 100
        # the Accept line: an unrelated parameter keeps M
        q2 = remake(q1; p = [:λ => 3.0])
        @test p60ak_vals(q2).J == M
        @test p60ak_vals(q2).λ == 3.0
        @test total_energy(q2) == 99 + 3                      # 102
        # a parameter that is an input of other computed parameters, but not of J
        q3 = remake(q1; p = [:α => 5.0])
        v = p60ak_vals(q3)
        @test v.J == M
        @test (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        @test total_energy(q3) == 99 + 4 + 1                  # 104
        # several unrelated changes in a row
        q4 = remake(remake(remake(q1; p = [:λ => 2.0]); p = [:α => 4.5]); p = [:λ => 1.0])
        @test p60ak_vals(q4).J == M
        @test typeof(q2.p) === typeof(prob.p) && typeof(q4.p) === typeof(prob.p)

        # an input in the change re-derives the table, overriding the explicit value
        r1 = remake(q1; p = [:Jx => 20.0])
        @test p60ak_vals(r1).J == p60ak_Jf(20.0)
        @test total_energy(r1) == 405 + 1                     # 406
        # ... and from then on it is the expression's value again
        r2 = remake(r1; p = [:λ => 3.0])
        @test p60ak_vals(r2).J == p60ak_Jf(20.0)
        @test p60ak_vals(remake(r2; p = [:Jx => 30.0])).J == p60ak_Jf(30.0)
        # a value given with its input in the same change wins (as before)
        r3 = remake(q1; p = [:Jx => 20.0, :J => M])
        @test p60ak_vals(r3).J == M && p60ak_vals(r3).Jx == 20.0
        @test total_energy(r3) == 100.0
        @test p60ak_vals(remake(r3; p = [:λ => 2.0])).J == M
    end

    @testset "explicit scalars and chains" begin
        # β explicit: γ (input β) and V₀ (inputs γ, β) are re-derived by the same change
        s1 = remake(prob; p = [:β => 5.0])
        v = p60ak_vals(s1)
        @test (v.α, v.β, v.γ, v.V₀) == (4.0, 5.0, 6.0, [0.0, 6.0, 5.0])
        @test total_energy(s1) == 321 + 9 + 16                # 346
        # unrelated changes keep β (and γ, V₀ derived from it)
        s2 = remake(s1; p = [:λ => 2.0])
        v = p60ak_vals(s2)
        @test (v.β, v.γ, v.V₀) == (5.0, 6.0, [0.0, 6.0, 5.0])
        @test total_energy(s2) == 321 + 2 * 25                # 371
        s3 = remake(s1; p = [:Jx => 20.0])
        v = p60ak_vals(s3)
        @test (v.β, v.γ, v.J) == (5.0, 6.0, p60ak_Jf(20.0))
        @test total_energy(s3) == 405 + 25                    # 430
        # a change of β's input re-derives β, and so γ and V₀
        s4 = remake(s1; p = [:α => 5.0])
        v = p60ak_vals(s4)
        @test (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        @test total_energy(s4) == 321 + 4 + 1                 # 326
        # an input and the computed value in one change: the given value wins, and what reads
        # it follows the given value
        s5 = remake(prob; p = [:α => 5.0, :β => 3.0])
        v = p60ak_vals(s5)
        @test (v.α, v.β, v.γ) == (5.0, 3.0, 4.0)
        v = p60ak_vals(remake(s5; p = [:λ => 2.0]))
        @test (v.α, v.β, v.γ, v.V₀) == (5.0, 3.0, 4.0, [0.0, 4.0, 3.0])

        # γ explicit (end of the chain)
        t1 = remake(prob; p = [:γ => 7.0])
        v = p60ak_vals(t1)
        @test (v.β, v.γ, v.V₀) == (8.0, 7.0, [0.0, 7.0, 8.0])
        @test total_energy(t1) == 321 + 4 + 1                 # 326
        t2 = remake(t1; p = [:λ => 2.0])
        @test p60ak_vals(t2).γ == 7.0
        @test total_energy(t2) == 321 + 2 * 5                 # 331
        # γ's input β changes: γ is re-derived
        t3 = remake(t1; p = [:β => 4.0])
        v = p60ak_vals(t3)
        @test (v.α, v.β, v.γ, v.V₀) == (4.0, 4.0, 5.0, [0.0, 5.0, 4.0])
        @test total_energy(t3) == 321 + 16 + 25               # 362
        # α changes: β is re-derived, so γ (whose input β is re-derived) is too
        t4 = remake(t1; p = [:α => 5.0])
        v = p60ak_vals(t4)
        @test (v.β, v.γ) == (10.0, 11.0)

        # an explicit table read through a chain: V₀ keeps its value until β or γ changes
        u1 = remake(prob; p = [:V₀ => [0.0, 9.0, 9.0]])
        @test total_energy(u1) == 321.0
        @test p60ak_vals(remake(u1; p = [:λ => 2.0])).V₀ == [0.0, 9.0, 9.0]
        @test p60ak_vals(remake(u1; p = [:Jx => 20.0])).V₀ == [0.0, 9.0, 9.0]
        @test total_energy(remake(u1; p = [:Jx => 20.0])) == 405.0
        u2 = remake(u1; p = [:α => 5.0])                      # β, γ re-derived, so V₀ too
        @test p60ak_vals(u2).V₀ == [0.0, 11.0, 10.0]
        @test total_energy(u2) == 326.0
    end

    @testset "integrator setters" begin
        integ = init(remake(prob; p = [:J => M]), SequentialCPM())
        step!(integ)
        integ.ps[:λ] = 3.0
        @test p60ak_ivals(integ).J == M
        setp(integ, :α)(integ, 5.0)
        v = p60ak_ivals(integ)
        @test v.J == M && (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        integ.ps[:Jx] = 20.0                                  # an input: re-derived
        @test p60ak_ivals(integ).J == p60ak_Jf(20.0)
        integ.ps[:λ] = 1.0
        @test p60ak_ivals(integ).J == p60ak_Jf(20.0)
        @test typeof(integ.p) === typeof(prob.p)

        # values set by setters, then a setter of another parameter
        i2 = init(prob, SequentialCPM())
        i2.ps[:J] = M
        i2.ps[:λ] = 2.0
        @test p60ak_ivals(i2).J == M
        i2.ps[:β] = 5.0
        v = p60ak_ivals(i2)
        @test (v.β, v.γ, v.V₀) == (5.0, 6.0, [0.0, 6.0, 5.0])
        i2.ps[:λ] = 3.0
        setp(i2, :Jx)(i2, 18.0)
        v = p60ak_ivals(i2)
        @test (v.β, v.γ, v.V₀, v.λ) == (5.0, 6.0, [0.0, 6.0, 5.0], 3.0)
        @test v.J == p60ak_Jf(18.0)                           # Jx is J's input
        i2.ps[:α] = 5.0
        v = p60ak_ivals(i2)
        @test (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        # the run reads the kept values: the integrator's parameters give the hand energy
        i3 = init(prob, SequentialCPM())
        i3.ps[:β] = 5.0
        i3.ps[:λ] = 2.0
        @test total_energy(remake(prob; p = i3.p)) == 371.0
    end

    @testset "operating point" begin
        pe = PottsProblem(sys, [op; :J => M], (0, 5); seed = 7)
        @test p60ak_vals(pe).J == M && total_energy(pe) == 100.0
        @test p60ak_vals(remake(pe; p = [:λ => 3.0])).J == M
        @test total_energy(remake(pe; p = [:λ => 3.0])) == 102.0
        @test p60ak_vals(remake(pe; p = [:α => 5.0])).J == M
        @test p60ak_vals(remake(pe; p = [:Jx => 20.0])).J == p60ak_Jf(20.0)
        ie = init(pe, SequentialCPM())
        ie.ps[:λ] = 2.0
        @test p60ak_ivals(ie).J == M

        pb = PottsProblem(sys, [op; :β => 5.0], (0, 5); seed = 7)
        v = p60ak_vals(pb)
        @test (v.α, v.β, v.γ, v.V₀) == (4.0, 5.0, 6.0, [0.0, 6.0, 5.0])
        @test total_energy(pb) == 346.0
        @test total_energy(remake(pb; p = [:λ => 2.0])) == 371.0
        @test p60ak_vals(remake(pb; p = [:λ => 2.0])).β == 5.0
        @test p60ak_vals(remake(pb; p = [:α => 5.0])).β == 10.0
        # by symbol too
        ps = PottsProblem(sys, [op; Potts.lookup(sys, :β) => 5.0], (0, 5); seed = 7)
        @test p60ak_vals(remake(ps; p = [:Jx => 20.0])).β == 5.0
        # an input in the operating point (control): the computed values follow it
        pa = PottsProblem(sys, [op; :α => 5.0], (0, 5); seed = 7)
        @test (p60ak_vals(pa).β, p60ak_vals(pa).γ) == (10.0, 11.0)
        @test p60ak_vals(remake(pa; p = [:λ => 2.0])).β == 10.0
    end

    @testset "checkpoint" begin
        q1 = remake(prob; p = [:J => M, :β => 5.0])
        integ = init(q1, SequentialCPM())
        step!(integ)
        ck = checkpoint(integ)
        path = joinpath(mktempdir(), "p60ak.jls")
        save_checkpoint(path, ck)
        ck2 = load_checkpoint(path)
        @test Matrix(ck2.p.J) == M && ck2.p.β == 5.0
        # a problem remade with the checkpoint's parameters, then an unrelated change
        r = remake(prob; p = ck2.p)
        @test p60ak_vals(r).J == M && p60ak_vals(r).β == 5.0
        @test total_energy(r) == 99 + 9 + 16                  # 124
        r2 = remake(r; p = [:λ => 3.0])
        v = p60ak_vals(r2)
        @test v.J == M && (v.β, v.γ) == (5.0, 6.0)
        @test total_energy(r2) == 99 + 3 * 25                 # 174
        @test p60ak_vals(remake(r; p = [:Jx => 20.0])).J == p60ak_Jf(20.0)
        # a continuation from the checkpoint, then a setter of another parameter
        i2 = init(q1, SequentialCPM(); checkpoint = ck2)
        @test i2.t == 1
        i2.ps[:λ] = 2.0
        v = p60ak_ivals(i2)
        @test v.J == M && v.β == 5.0
        step!(i2)
        @test i2.t == 2
    end

    @testset "Float32" begin
        p32 = PottsProblem(sys, op, (0, 5); seed = 7, T = Float32)
        q = remake(remake(p32; p = [:J => M]); p = [:λ => 3.0])
        J = getp(q, :J)(q)
        @test eltype(J) === Float32 && Matrix(J) == Float32.(M)
        @test typeof(q.p) === typeof(p32.p)
        @test total_energy(q) == 102.0f0
        s = remake(remake(p32; p = [:β => 5.0]); p = [:λ => 2.0])
        @test getp(s, :β)(s) === 5.0f0 && getp(s, :γ)(s) === 6.0f0
        @test total_energy(s) == 371.0f0
        i32 = init(remake(p32; p = [:J => M]), SequentialCPM())
        i32.ps[:α] = 5.0
        @test eltype(i32.ps[:J]) === Float32 && Matrix(i32.ps[:J]) == Float32.(M)
        @test i32.ps[:β] === 10.0f0
    end

    @testset "negative controls" begin
        q1 = remake(prob; p = [:J => M])
        # an asymmetric contact table is still rejected, kept values or not
        err = p60ak_error(() -> remake(q1; p = [:J => [0 1 2; 1 0 0; 3 0 0]]))
        @test err isa ArgumentError && occursin("symmetric", sprint(showerror, err))
        err = p60ak_error(() -> (i = init(q1, SequentialCPM()); i.ps[:J] = [0 1 2; 1 0 0; 3 0 0]))
        @test err isa ArgumentError && occursin("symmetric", sprint(showerror, err))
        # unknown names are still errors
        @test p60ak_error(() -> remake(q1; p = [:nosuch => 1.0])) isa ArgumentError
        # a kind table keeps its size
        @test p60ak_error(() -> remake(q1; p = [:J => [0 1; 1 0]])) isa ArgumentError
        # an explicit value does not leak into another problem: prob itself is unchanged
        @test p60ak_vals(prob).J == p60ak_Jf(16.0) && p60ak_vals(prob).β == 8.0
        @test p60ak_vals(remake(prob; p = [:λ => 3.0])).J == p60ak_Jf(16.0)
    end
end
