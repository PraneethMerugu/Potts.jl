# P6.0an (ROADMAP Phase 6, step 0): `remake` with a NamedTuple. Frozen (AUTONOMY §7.2).
#
# Today (a1c3ed57) `remake(prob; p = (λ = 3.0,))` on a model's problem falls back to
# CorePotts' default `remake_parameters` (identity, for hand-written problems), so `prob.p`
# silently becomes the one-field NamedTuple `(λ = 3.0,)`: every other parameter is gone and
# the run fails later (`total_energy`: "type NamedTuple has no field `V₀`"), a Float32
# problem gets a Float64 value. The same fall-through accepts any non-map value (`p = 3.0`,
# `p = (3.0,)`, `p = [1.0, 2.0]`, `p = Any[:λ => 3.0]`) as the parameter object.
# `remake(prob; u0 = (ownership = σ, kind = …))` and `reinit!(integ, (ownership = σ, …))`
# fail with a MethodError / FieldError where the pairs `[:ownership => σ, :kind => …]` work.
#
# Rule (D-115). On a problem of a Potts model:
#   * a NamedTuple given as `p` is a parameter map, the same as the pairs of its fields:
#     `remake(prob; p = (λ = 3.0, J = M))` ≡ `remake(prob; p = [:λ => 3.0, :J => M])`. It is
#     one change (D-112): the parameters it names are set, a computed parameter is re-derived
#     iff one of its inputs is named (transitively), the rest keep their values; values take
#     the problem's scalar type, tables keep their size and are checked (symmetry); a field
#     that is not a parameter is an `ArgumentError` naming it. A NamedTuple naming every
#     parameter sets every value (nothing re-derived); the empty NamedTuple changes nothing.
#   * a vector or tuple whose elements are all `Pair`s (`Any[:λ => 3.0]`, `(:λ => 3.0,)`) is
#     a parameter map too; a `PottsParameters` is a whole parameter object (as today);
#     anything else (a number, a tuple or vector of numbers) is an `ArgumentError`
#     mentioning parameters, never a silent replacement.
#   * a NamedTuple given as `u0` (to `remake` or `reinit!`) is an operating point, the same
#     as the pairs of its fields (`(ownership = σ, kind = [:P, :Q])`).
#   * this holds wherever `remake` is called: an `EnsembleProblem`'s `prob_func`, a problem
#     then `init`ed and changed by setters.
# On a hand-written CorePotts problem (a `CPMFunction` without a model) the parameter
# object is the user's own: `remake(prob; p = x)` replaces it with `x` as given (CorePotts'
# contract, unchanged), whatever `x` is (a partial NamedTuple included).
#
# Energies by hand (fixture of P6.0ak): two 3×3 cells on a 12×12 lattice, von Neumann
# contacts, P at x = 3:5 and Q at x = 6:8 (y = 3:5). P–Q share 3 contact pairs, P–medium
# and Q–medium 9 each (pairs counted once):
#   contacts = 9 J[M,P] + 9 J[M,Q] + 3 J[P,Q];  Jf(x) = [0 x x; x 2 x-5; x x-5 14] gives
#   21x − 15 (x = 16: 321, x = 20: 405); M = [0 5 5; 5 1 3; 5 3 1] gives 99.
#   cells = λ ((9 − V₀[P])² + (9 − V₀[Q])²), V₀ = [0, γ, β], α = 4 → β = 8 → γ = 9.
# Defaults: E = 321 + 1 = 322. With Q moved to x = 9:11 (no P–Q contact; layout `B`):
#   contacts = 12·16 + 12·16 = 384, E = 384 + λ·1.
using Test, Potts, PottsModels
using Potts: CorePotts

@potts_model P60anChain begin
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

function p60an_sigma(; apart = false)
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    apart ? (σ[9:11, 3:5] .= 2) : (σ[6:8, 3:5] .= 2)
    return σ
end

p60an_Jf(x) = [0 x x; x 2 x-5; x x-5 14]
const P60AN_M = [0 5 5; 5 1 3; 5 3 1]

p60an_vals(q) = (α = getp(q, :α)(q), β = getp(q, :β)(q), γ = getp(q, :γ)(q), λ = getp(q, :λ)(q),
    Jx = getp(q, :Jx)(q), J = Matrix(getp(q, :J)(q)), V₀ = Vector(getp(q, :V₀)(q)))
p60an_ivals(i) = (α = i.ps[:α], β = i.ps[:β], γ = i.ps[:γ], λ = i.ps[:λ], Jx = i.ps[:Jx],
    J = Matrix(i.ps[:J]), V₀ = Vector(i.ps[:V₀]))

function p60an_error(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end
p60an_msg(e) = e === nothing ? "" : sprint(showerror, e)

# hand-written CorePotts problem: a constant ΔH and a temperature read from `p`
p60an_hw_dH(st, p, prop, ctx) = p.h
p60an_hw_T(st, p, prop, ctx) = p.T
const P60AN_HW = CorePotts.CPMFunction(p60an_hw_dH; temperature = p60an_hw_T)

@testset "P6.0an: remake with a NamedTuple" begin
    sys = P60anChain(; name = :chain)
    op = [ownership => p60an_sigma(), kind => [:P, :Q]]
    M = P60AN_M
    prob = PottsProblem(sys, op, (0, 5); seed = 7)

    @testset "defaults and pairs (control)" begin
        v = p60an_vals(prob)
        @test (v.α, v.β, v.γ, v.λ, v.Jx) == (4.0, 8.0, 9.0, 1.0, 16.0)
        @test total_energy(prob) == 322.0
        @test total_energy(remake(prob; p = [:λ => 3.0])) == 321 + 3      # 324
    end

    @testset "a NamedTuple is a partial parameter map" begin
        q = remake(prob; p = (λ = 3.0,))
        @test q.p isa Potts.PottsParameters
        @test typeof(q.p) === typeof(prob.p)
        v = p60an_vals(q)
        @test (v.α, v.β, v.γ, v.λ, v.Jx) == (4.0, 8.0, 9.0, 3.0, 16.0)
        @test v.J == p60an_Jf(16.0) && v.V₀ == [0.0, 9.0, 8.0]
        @test total_energy(q) == 324.0
        # the source problem is unchanged
        @test p60an_vals(prob).λ == 1.0 && total_energy(prob) == 322.0
        # an Int value takes the problem's scalar type, as in pairs
        @test getp(remake(prob; p = (λ = 3,)), :λ)(remake(prob; p = (λ = 3,))) === 3.0
        # several fields, one change
        q2 = remake(prob; p = (λ = 2.0, Jx = 20.0))
        v = p60an_vals(q2)
        @test (v.λ, v.Jx, v.J) == (2.0, 20.0, p60an_Jf(20.0))
        @test total_energy(q2) == 405 + 2                       # 407
        # same result as the pairs and the Dict of its fields
        for nt in ((λ = 3.0,), (α = 5.0,), (β = 5.0, λ = 2.0), (J = M,), (Jx = 20.0, J = M),
                   (V₀ = [0.0, 9.0, 9.0],), (α = 5.0, β = 3.0))
            a = remake(prob; p = nt)
            b = remake(prob; p = [k => v for (k, v) in pairs(nt)])
            c = remake(prob; p = Dict(pairs(nt)))
            @test a.p == b.p == c.p
            @test typeof(a.p) === typeof(b.p)
            @test total_energy(a) == total_energy(b)
        end
    end

    @testset "D-112 semantics through a NamedTuple" begin
        # a computed scalar follows its input
        q = remake(prob; p = (α = 5.0,))
        v = p60an_vals(q)
        @test (v.β, v.γ, v.V₀) == (10.0, 11.0, [0.0, 11.0, 10.0])
        @test total_energy(q) == 321 + 4 + 1                    # 326
        # an explicit computed scalar: what reads it follows it
        s1 = remake(prob; p = (β = 5.0,))
        v = p60an_vals(s1)
        @test (v.α, v.β, v.γ, v.V₀) == (4.0, 5.0, 6.0, [0.0, 6.0, 5.0])
        @test total_energy(s1) == 321 + 9 + 16                  # 346
        # ... and survives an unrelated NamedTuple change
        s2 = remake(s1; p = (λ = 2.0,))
        v = p60an_vals(s2)
        @test (v.β, v.γ, v.V₀) == (5.0, 6.0, [0.0, 6.0, 5.0])
        @test total_energy(s2) == 321 + 2 * 25                  # 371
        # ... until its input changes
        @test p60an_vals(remake(s1; p = (α = 5.0,))).β == 10.0
        # a value given with its input in one NamedTuple wins
        s5 = remake(prob; p = (α = 5.0, β = 3.0))
        v = p60an_vals(s5)
        @test (v.α, v.β, v.γ) == (5.0, 3.0, 4.0)
    end

    @testset "a whole kind table as a NamedTuple value" begin
        q1 = remake(prob; p = (J = M,))
        @test p60an_vals(q1).J == M
        @test typeof(q1.p) === typeof(prob.p)
        @test total_energy(q1) == 99 + 1                        # 100
        q2 = remake(q1; p = (λ = 3.0,))                         # unrelated: M kept
        @test p60an_vals(q2).J == M
        @test total_energy(q2) == 99 + 3                        # 102
        r1 = remake(q1; p = (Jx = 20.0,))                       # an input: re-derived
        @test p60an_vals(r1).J == p60an_Jf(20.0)
        @test total_energy(r1) == 405 + 1                       # 406
        r3 = remake(q1; p = (Jx = 20.0, J = M))                 # given with its input: kept
        @test p60an_vals(r3).J == M && p60an_vals(r3).Jx == 20.0
        @test total_energy(r3) == 100.0
        u1 = remake(prob; p = (V₀ = [0.0, 9.0, 9.0],))
        @test p60an_vals(u1).V₀ == [0.0, 9.0, 9.0]
        @test total_energy(u1) == 321.0
    end

    @testset "a NamedTuple naming every parameter; the empty NamedTuple" begin
        # every parameter named: nothing re-derived (α = 5 with β = 8 kept as given)
        full = merge(NamedTuple(prob.p), (α = 5.0,))
        q = remake(prob; p = full)
        v = p60an_vals(q)
        @test (v.α, v.β, v.γ, v.V₀) == (5.0, 8.0, 9.0, [0.0, 9.0, 8.0])
        @test typeof(q.p) === typeof(prob.p)
        @test total_energy(q) == 322.0
        # the NamedTuple of the parameter object round-trips
        @test remake(prob; p = NamedTuple(prob.p)).p == prob.p
        # the empty NamedTuple changes nothing
        e = remake(prob; p = (;))
        @test e.p == prob.p && typeof(e.p) === typeof(prob.p)
        @test total_energy(e) == 322.0
    end

    @testset "other parameter maps and non-maps" begin
        # a vector or tuple of Pairs is a map, whatever its element type
        a = remake(prob; p = Any[:λ => 3.0])
        @test a.p isa Potts.PottsParameters && p60an_vals(a).λ == 3.0
        @test total_energy(a) == 324.0
        t = remake(prob; p = (:λ => 3.0, :Jx => 20.0))
        @test t.p isa Potts.PottsParameters && p60an_vals(t).J == p60an_Jf(20.0)
        @test total_energy(t) == 405 + 3                        # 408
        # a whole parameter object (as today)
        @test remake(prob; p = remake(prob; p = (λ = 2.0,)).p).p == remake(prob; p = [:λ => 2.0]).p
        # values that cannot be a parameter map: a clear error, not a silent replacement
        for bad in (3.0, (3.0,), (3.0, 1.0), [1.0, 2.0])
            err = p60an_error(() -> remake(prob; p = bad))
            @test err isa ArgumentError
            @test occursin("parameter", p60an_msg(err))
        end
    end

    @testset "negative controls: names and values are checked" begin
        err = p60an_error(() -> remake(prob; p = (nosuch = 1.0,)))
        @test err isa ArgumentError && occursin("nosuch", p60an_msg(err))
        err = p60an_error(() -> remake(prob; p = (λ = 2.0, nosuch = 1.0)))
        @test err isa ArgumentError && occursin("nosuch", p60an_msg(err))
        # a variable is not a parameter
        err = p60an_error(() -> remake(prob; p = (volume = 1.0,)))
        @test err isa ArgumentError && occursin("volume", p60an_msg(err))
        # a kind table keeps its size; a contact table is symmetric
        @test p60an_error(() -> remake(prob; p = (J = [0 1; 1 0],))) isa ArgumentError
        err = p60an_error(() -> remake(prob; p = (J = [0 1 2; 1 0 0; 3 0 0],)))
        @test err isa ArgumentError && occursin("symmetric", p60an_msg(err))
        # the problem is untouched by the failed calls
        @test p60an_vals(prob).λ == 1.0 && p60an_vals(prob).J == p60an_Jf(16.0)
    end

    @testset "Float32 problems keep their type" begin
        p32 = PottsProblem(sys, op, (0, 5); seed = 7, T = Float32)
        q = remake(p32; p = (λ = 3.0,))
        @test typeof(q.p) === typeof(p32.p)
        @test getp(q, :λ)(q) === 3.0f0
        @test total_energy(q) == 324.0f0
        r = remake(remake(p32; p = (J = M,)); p = (λ = 3.0,))
        J = getp(r, :J)(r)
        @test eltype(J) === Float32 && Matrix(J) == Float32.(M)
        @test typeof(r.p) === typeof(p32.p)
        @test total_energy(r) == 102.0f0
        s = remake(p32; p = (β = 5,))
        @test getp(s, :β)(s) === 5.0f0 && getp(s, :γ)(s) === 6.0f0
        f = remake(p32; p = NamedTuple(prob.p))                 # Float64 values, every name
        @test typeof(f.p) === typeof(p32.p)
        @test total_energy(f) == 322.0f0
    end

    @testset "u0 as a NamedTuple" begin
        σB = p60an_sigma(; apart = true)
        b = remake(prob; u0 = [:ownership => σB, :kind => [:P, :Q]])     # control: pairs
        @test total_energy(b) == 384 + 1                        # 385
        q = remake(prob; u0 = (ownership = σB, kind = [:P, :Q]))
        @test Array(q.u0.σ) == σB
        @test Array(q.u0.cell.kind)[1:2] == Array(b.u0.cell.kind)[1:2]
        @test total_energy(q) == 385.0
        q2 = remake(prob; u0 = (ownership = p60an_sigma(), kind = [:Q, :P]))
        @test Array(q2.u0.cell.kind)[1:2] == Int32[2, 1]
        # both as NamedTuples in one call
        q3 = remake(prob; p = (λ = 2.0,), u0 = (ownership = σB, kind = [:P, :Q]))
        @test total_energy(q3) == 384 + 2                       # 386
        @test p60an_vals(q3).J == p60an_Jf(16.0)
    end

    @testset "integrators" begin
        # reinit! with a NamedTuple state
        integ = init(prob, SequentialCPM())
        step!(integ)
        reinit!(integ, (ownership = p60an_sigma(; apart = true), kind = [:Q, :P]))
        @test Array(integ.state.σ) == p60an_sigma(; apart = true)
        @test Array(integ.state.cell.kind)[1:2] == Int32[2, 1]
        @test integ.t == 0
        # a problem remade with a NamedTuple, then run and changed by setters
        i2 = init(remake(prob; p = (J = M,)), SequentialCPM())
        @test typeof(i2.p) === typeof(prob.p)
        step!(i2)
        i2.ps[:λ] = 3.0
        @test p60an_ivals(i2).J == M
        i2.ps[:Jx] = 20.0
        @test p60an_ivals(i2).J == p60an_Jf(20.0)
    end

    @testset "EnsembleProblem prob_func with a NamedTuple" begin
        pf(q, ctx) = remake(q; p = (λ = 3.0,))
        ens = solve(EnsembleProblem(prob; prob_func = pf), SequentialCPM(), EnsembleSerial();
            trajectories = 2)
        @test length(ens.u) == 2
        for s in ens.u
            @test typeof(s.prob.p) === typeof(prob.p)
            v = p60an_vals(s.prob)
            @test v.λ == 3.0 && v.J == p60an_Jf(16.0) && v.V₀ == [0.0, 9.0, 8.0]
        end
        @test ens.u[1].u[end].σ != ens.u[2].u[end].σ             # still distinct replicas
        pj(q, ctx) = remake(q; p = (J = M,))
        e2 = solve(EnsembleProblem(prob; prob_func = pj), SequentialCPM(), EnsembleSerial();
            trajectories = 2)
        @test all(s -> p60an_vals(s.prob).J == M, e2.u)
    end

    @testset "hand-written CorePotts problems: p is replaced as given (unchanged)" begin
        σ = p60an_sigma()
        hp = CorePotts.PottsProblem(P60AN_HW, CorePotts.initial_state(σ, Int32[1, 2]),
            CorePotts.Lattice((12, 12)), (0, 3), (h = 0.0, T = 10.0); seed = 1)
        @test hp.p === (h = 0.0, T = 10.0)
        # a NamedTuple replaces the parameter object whole, a partial one included
        @test remake(hp; p = (h = 1.0, T = 5.0)).p === (h = 1.0, T = 5.0)
        @test remake(hp; p = (T = 5.0,)).p === (T = 5.0,)
        @test remake(hp; p = merge(hp.p, (; T = 5.0))).p === (h = 0.0, T = 5.0)
        # any object, as given
        @test remake(hp; p = 3.0).p === 3.0
        @test remake(hp; p = [:T => 5.0]).p == [:T => 5.0]
        # and runs with it
        hi = init(remake(hp; p = (h = 0.0, T = 5.0)), SequentialCPM())
        step!(hi)
        @test hi.p === (h = 0.0, T = 5.0) && hi.t == 1
        e = solve(EnsembleProblem(hp; prob_func = (q, ctx) -> remake(q; p = (h = 0.0, T = 2.0))),
            SequentialCPM(), EnsembleSerial(); trajectories = 2)
        @test all(s -> s.prob.p === (h = 0.0, T = 2.0), e.u)
    end
end
