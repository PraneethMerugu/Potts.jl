# P6.0ao (ROADMAP Phase 6, step 0): computed parameter defaults that call functions or read
# a kind-table entry. Frozen (AUTONOMY §7.2).
#
# Today (e006198b) a computed default is evaluated by substituting the parameter values
# (`_resolve_defaults!`, src/problem.jl) and is accepted only if the substitution folds to a
# number. Calls are not evaluated, so `w = sqrt(a₀) + π` stays `π + sqrt(4.0)` and the
# build fails with "parameter `w` = `π + sqrt(4.0)` does not reduce to numbers"; the same
# for `exp`, `log`, `abs`, `min`/`max`, `ifelse` (and `c ? a : b`), `floor`, `mod`, `rem`,
# a user function registered with `@register_symbolic`, a kind-table entry `V₀[2]`
# (`Potts.at(V₀, 2)`) or `J[P, Q]` (`Potts.at2`), and a kind table whose entries call
# functions (`J[kind, kind] = [0 sqrt(Jx) …]`). `div(a₀, 2)` / `a₀ ÷ 2` throw a MethodError
# on `Num` when the model is built, and a table entry reading another table
# (`V₁[kind] = [0.0, V₀[1] - 1]`) silently drops the index (the literal is not rewritten).
#
# Rule (D-117). A computed default (scalar, or kind-table entry) is evaluated numerically:
# the parameter values are substituted and the expression is then evaluated with Julia's
# functions — Base math (`sqrt`, `exp`, `log`, `abs`, `^`, `min`, `max`, `floor`, `mod`,
# `rem`, `div`/`÷`), `ifelse` and comparisons (and `c ? a : b`, `&&`), constants (`π`, `ℯ`),
# functions registered with `@register_symbolic`, and kind-table reads. A kind-table read
# `V₀[k]` / `J[k, l]` takes kind numbers as everywhere in a model (medium = 0, the kinds in
# `@kinds` order; a kind's name is its number), so with `@kinds medium P Q`, `V₀[2]` is
# `V₀[Q]`, the third entry. The value is converted to the problem's scalar type (Float32
# problems stay Float32). The input graph of D-112 sees through calls and table reads: a
# computed parameter is re-derived by a change iff one of the parameters its expression
# reads (inside any call or index) is in the change or is re-derived by it.
# A default that cannot be a number — it reads a variable or built-in (`volume`, `kind`), or
# draws a random number (`rand()`: a default is evaluated once per build and must be
# deterministic) — or that reads a kind table outside its kinds, is an `ArgumentError` that
# names the parameter. A function that fails on the values (`sqrt` of a negative number)
# raises an error at build, never a silent NaN.
#
# Fixture: two 3×3 cells on a 12×12 lattice with von Neumann contacts, P at x = 3:5 and Q
# at x = 6:8 (y = 3:5), as in P6.0ak. P–Q share 3 contact pairs; P–medium and Q–medium
# 9 pairs each, so contacts = 9 J[M,P] + 9 J[M,Q] + 3 J[P,Q] and
# cells = λ ((9 − V₁[P])² + (9 − V₁[Q])²).
# Defaults (a₀ = 4, Jx = 16, V₀ = [0, 9, 8], λ = 1):
#   w  = sqrt(4) + π                                    = 2 + π
#   e₁ = exp(0) + log(1) + |−4| + 4² + 4^0.5 + min(4,3) + max(4,3) = 1+0+4+16+2+3+4 = 30
#   g  = 4ℯ
#   c  = ifelse(4 > 1, 8, 3) = 8;  c₂ = 4 > 5 ? 1 : 2 = 2;  c₃ = (4 > 1 && 4 < 5) ? 10 : 20 = 10
#   h  = floor(4/3) + mod(7, 4) + rem(7, 2) = 1 + 3 + 1 = 5
#   m  = p60ao_twice_plus_one(4) = 9                     (registered function)
#   u  = V₀[2] + 1 = V₀[Q] + 1 = 9;  u_P = V₀[P] + 1 = 10
#   J  = [0 4 4; 4 2 11; 4 11 14] (sqrt(Jx) = 4);  j = J[P, Q] + J[0, 1] = 11 + 4 = 15
#   V₁ = [0, u_P − 2, sqrt(u)] = [0, 8, 3];  z = 2 sqrt(u) = 6         (chains)
#   E  = 9·4 + 9·4 + 3·11 + (9 − 8)² + (9 − 3)² = 105 + 37 = 142
using Test, Potts, PottsModels
using Potts: Symbolics

p60ao_twice_plus_one(x) = 2x + 1
Symbolics.@register_symbolic p60ao_twice_plus_one(x)

@potts_model P60aoFns begin
    @kinds medium P Q
    @parameters begin
        a₀ = 4.0
        w = sqrt(a₀) + π
        e₁ = exp(a₀ - 4) + log(a₀ / 4) + abs(-a₀) + a₀^2 + a₀^0.5 + min(a₀, 3.0) + max(a₀, 3.0)
        g = a₀ * ℯ
        c = ifelse(a₀ > 1, 2a₀, 3.0)
        c₂ = a₀ > 5 ? 1.0 : 2.0
        c₃ = (a₀ > 1 && a₀ < 5) ? 10.0 : 20.0
        h = floor(a₀ / 3) + mod(a₀ + 3, 4) + rem(a₀ + 3, 2)
        m = p60ao_twice_plus_one(a₀)
        V₀[kind] = [0.0, 9.0, 8.0]
        u = V₀[2] + 1
        u_P = V₀[P] + 1
        Jx = 16.0
        J[kind, kind] = [0 sqrt(Jx) sqrt(Jx); sqrt(Jx) 2 Jx-5; sqrt(Jx) Jx-5 14]
        j = J[P, Q] + J[0, 1]
        V₁[kind] = [0.0, u_P - 2, sqrt(u)]
        z = 2sqrt(u)
        λ = 1.0
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => λ * (volume - V₁[kind])^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 10.0)
end

# a kind table whose entries read another table's entries (kind numbers or names):
# R = [0, V₀[1] − 1, 2 V₀[Q]] = [0, 8, 16]; E = (9 − 8)² + (9 − 16)² = 50
@potts_model P60aoTabRead begin
    @kinds medium P Q
    @parameters begin
        V₀[kind] = [0.0, 9.0, 8.0]
        R[kind] = [0.0, V₀[1] - 1, 2V₀[Q]]
        λ = 1.0
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => λ * (volume - R[kind])^2
    end
    @sweep Metropolis(; temperature = 10.0)
end

# integer division: `div` and `÷` (Float64 parameters: div(7.0, 2) = 3.0, 7.0 ÷ 3 = 2.0)
@potts_model P60aoDiv begin
    @kinds medium P Q
    @parameters begin
        n = 7.0
        d = div(n, 2) + n ÷ 3
        λ = 1.0
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => λ * (volume - d)^2
    end
    @sweep Metropolis(; temperature = 10.0)
end

# negative controls: defaults that cannot be numbers
@potts_model P60aoVolume begin
    @kinds medium P Q
    @parameters begin
        w = volume + 1
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => w * volume
    end
    @sweep Metropolis(; temperature = 10.0)
end

@potts_model P60aoKindVar begin
    @kinds medium P Q
    @parameters begin
        V₀[kind] = [0.0, 9.0, 8.0]
        w = V₀[kind] + 1
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => w * volume
    end
    @sweep Metropolis(; temperature = 10.0)
end

@potts_model P60aoRand begin
    @kinds medium P Q
    @parameters begin
        w = rand()
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => w * volume
    end
    @sweep Metropolis(; temperature = 10.0)
end

@potts_model P60aoOutOfRange begin
    @kinds medium P Q
    @parameters begin
        V₀[kind] = [0.0, 9.0, 8.0]
        w = V₀[3] + 1
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => w * volume
    end
    @sweep Metropolis(; temperature = 10.0)
end

function p60ao_blocks()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:5] .= 2
    return [ownership => σ, kind => [:P, :Q]]
end

const P60AO_SCALARS = (:a₀, :w, :e₁, :g, :c, :c₂, :c₃, :h, :m, :u, :u_P, :Jx, :j, :z, :λ)
p60ao_vals(q) = merge(NamedTuple(k => getp(q, k)(q) for k in P60AO_SCALARS),
    (J = Matrix(getp(q, :J)(q)), V₀ = Vector(getp(q, :V₀)(q)), V₁ = Vector(getp(q, :V₁)(q))))
p60ao_ivals(i) = merge(NamedTuple(k => i.ps[k] for k in P60AO_SCALARS),
    (J = Matrix(i.ps[:J]), V₀ = Vector(i.ps[:V₀]), V₁ = Vector(i.ps[:V₁])))
p60ao_Jf(s, x) = [0 s s; s 2 x-5; s x-5 14]          # J with sqrt(Jx) = s, Jx = x
p60ao_e₁(a) = exp(a - 4) + log(a / 4) + abs(a) + a^2 + sqrt(a) + min(a, 3.0) + max(a, 3.0)

function p60ao_error(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end
# the error of building a model's problem (the system or the problem may raise it)
p60ao_build_error(M; kw...) = p60ao_error(() -> PottsProblem(M(; name = :neg), p60ao_blocks(), (0, 5); kw...))
p60ao_names(e, name) = e isa ArgumentError && occursin("`$name`", sprint(showerror, e))

@testset "P6.0ao: computed defaults with functions and kind-table entries" begin
    op = p60ao_blocks()

    @testset "a kind table reading another table" begin
        st = P60aoTabRead(; name = :tabread)
        pt = PottsProblem(st, op, (0, 5))
        @test Vector(getp(pt, :R)(pt)) == [0.0, 8.0, 16.0]
        @test total_energy(pt) == 1 + 49                     # 50
        qt = remake(pt; p = [:V₀ => [0.0, 5.0, 3.0]])
        @test Vector(getp(qt, :R)(qt)) == [0.0, 4.0, 6.0]
        qe = remake(pt; p = [:R => [0.0, 7.0, 7.0]])
        @test Vector(getp(remake(qe; p = [:λ => 2.0]), :R)(remake(qe; p = [:λ => 2.0]))) == [0.0, 7.0, 7.0]
        @test Vector(getp(remake(qe; p = [:V₀ => [0.0, 5.0, 3.0]]), :R)(remake(qe; p = [:V₀ => [0.0, 5.0, 3.0]]))) == [0.0, 4.0, 6.0]
        p32 = PottsProblem(st, op, (0, 5); T = Float32)
        @test getp(p32, :R)(p32) isa AbstractVector{Float32}
        @test Vector(getp(p32, :R)(p32)) == Float32[0, 8, 16]
    end

    @testset "integer division" begin
        sd = P60aoDiv(; name = :div)
        pd = PottsProblem(sd, op, (0, 5))
        @test getp(pd, :d)(pd) == 5.0                        # div(7, 2) + 7 ÷ 3 = 3 + 2
        @test total_energy(pd) == 2 * (9 - 5)^2              # 32
        qd = remake(pd; p = [:n => 10.0])
        @test getp(qd, :d)(qd) == 8.0                        # 5 + 3
    end


    @testset "negative controls" begin
        # a default reading a built-in variable, the kind variable, or a draw: no number
        @test p60ao_names(p60ao_build_error(P60aoVolume), :w)
        @test p60ao_names(p60ao_build_error(P60aoKindVar), :w)
        @test p60ao_names(p60ao_build_error(P60aoRand), :w)
        @test p60ao_names(p60ao_build_error(P60aoRand; T = Float32), :w)
        # a kind number outside the kinds (0:2)
        @test p60ao_names(p60ao_build_error(P60aoOutOfRange), :w)
    end

    @testset "the fixture" begin
        sys = P60aoFns(; name = :fns)
        prob = PottsProblem(sys, op, (0, 5); seed = 7)
        v = p60ao_vals(prob)

        @testset "Base functions, constants, ifelse at build" begin
            @test v.a₀ == 4.0
            @test v.w ≈ 2 + π atol = 1e-12
            @test v.e₁ ≈ 30.0 atol = 1e-12
            @test v.g ≈ 4ℯ atol = 1e-12
            @test v.c == 8.0
            @test v.c₂ == 2.0
            @test v.c₃ == 10.0
            @test v.h == 5.0
            @test typeof(prob.p) === typeof(PottsProblem(sys, [op; :w => 0.0], (0, 5)).p)
            @test all(k -> getp(prob, k)(prob) isa Float64, P60AO_SCALARS)
        end

        @testset "registered function" begin
            @test v.m == 9.0
        end

        @testset "kind-table reads (kind numbers, medium = 0) and tables with functions" begin
            @test v.u == 9.0                                     # V₀[2] = V₀[Q] = 8
            @test v.u_P == 10.0                                  # V₀[P] = 9
            @test v.J == p60ao_Jf(4.0, 16.0)
            @test eltype(getp(prob, :J)(prob)) === Float64
            @test v.j == 15.0                                    # J[P, Q] + J[0, 1] = 11 + 4
            @test v.V₁ == [0.0, 8.0, 3.0]                        # [0, u_P − 2, sqrt(u)]
            @test v.z == 6.0                                     # 2 sqrt(u)
            @test total_energy(prob) == 142.0
        end

        @testset "operating point" begin
            p9 = PottsProblem(sys, [op; :a₀ => 9.0], (0, 5); seed = 7)
            v9 = p60ao_vals(p9)
            @test v9.w ≈ 3 + π atol = 1e-12
            @test v9.c == 18.0 && v9.c₂ == 1.0 && v9.c₃ == 20.0 && v9.m == 19.0
            @test v9.h == 3.0 + 0.0 + 0.0                        # floor(3) + mod(12, 4) + rem(12, 2)
            pV = PottsProblem(sys, [op; :V₀ => [0.0, 5.0, 15.0]], (0, 5); seed = 7)
            vV = p60ao_vals(pV)
            @test (vV.u, vV.u_P, vV.V₁, vV.z) == (16.0, 6.0, [0.0, 4.0, 4.0], 8.0)
            @test total_energy(pV) == 105 + 2 * (9 - 4)^2       # 155
            pw = PottsProblem(sys, [op; [:w => 1.0, :u => 4.0]], (0, 5); seed = 7)
            vw = p60ao_vals(pw)
            @test vw.w == 1.0 && vw.u == 4.0
            @test vw.V₁ == [0.0, 8.0, 2.0] && vw.z == 4.0       # follow the explicit u
        end

        @testset "remake: computed defaults follow their inputs (D-112 through calls and reads)" begin
            q = remake(prob; p = [:a₀ => 9.0])
            vq = p60ao_vals(q)
            @test vq.w ≈ 3 + π atol = 1e-12
            @test vq.e₁ ≈ p60ao_e₁(9.0) rtol = 1e-12
            @test vq.g ≈ 9ℯ atol = 1e-12
            @test (vq.c, vq.c₂, vq.c₃, vq.h, vq.m) == (18.0, 1.0, 20.0, 3.0, 19.0)
            # parameters that do not read a₀ are untouched
            @test (vq.u, vq.u_P, vq.j, vq.z) == (9.0, 10.0, 15.0, 6.0)
            @test vq.J == p60ao_Jf(4.0, 16.0) && vq.V₁ == [0.0, 8.0, 3.0]
            @test typeof(q.p) === typeof(prob.p)
            # the false branch of ifelse
            q0 = remake(prob; p = [:a₀ => 0.5])
            @test getp(q0, :c)(q0) == 3.0 && getp(q0, :c₃)(q0) == 20.0
            # a table read: V₀ → u, u_P, V₁ (and z through u)
            r = remake(prob; p = [:V₀ => [0.0, 5.0, 15.0]])
            vr = p60ao_vals(r)
            @test (vr.u, vr.u_P, vr.V₁, vr.z) == (16.0, 6.0, [0.0, 4.0, 4.0], 8.0)
            @test vr.w ≈ 2 + π atol = 1e-12
            @test vr.m == 9.0
            @test total_energy(r) == 155.0
            # a table whose entries call functions: Jx → J → j
            s = remake(prob; p = [:Jx => 25.0])
            vs = p60ao_vals(s)
            @test vs.J == p60ao_Jf(5.0, 25.0)
            @test vs.j == 20.0 + 5.0
            @test total_energy(s) == 9 * 5 + 9 * 5 + 3 * 20 + 37   # 187
        end

        @testset "remake: explicit values survive changes that touch none of their inputs" begin
            # w = sqrt(a₀) + π
            q1 = remake(prob; p = [:w => 1.0])
            @test getp(q1, :w)(q1) == 1.0
            @test getp(remake(q1; p = [:λ => 2.0]), :w)(remake(q1; p = [:λ => 2.0])) == 1.0
            q1j = remake(q1; p = [:Jx => 25.0])
            @test getp(q1j, :w)(q1j) == 1.0 && getp(q1j, :j)(q1j) == 25.0
            q1a = remake(q1; p = [:a₀ => 16.0])                  # its input: re-derived
            @test getp(q1a, :w)(q1a) ≈ 4 + π atol = 1e-12
            # m = p60ao_twice_plus_one(a₀): the registered call is seen through
            q2 = remake(prob; p = [:m => 0.5])
            @test getp(remake(q2; p = [:λ => 2.0]), :m)(remake(q2; p = [:λ => 2.0])) == 0.5
            @test getp(remake(q2; p = [:a₀ => 5.0]), :m)(remake(q2; p = [:a₀ => 5.0])) == 11.0
            # c = ifelse(a₀ > 1, 2a₀, 3): inputs in the condition and the branches
            q3 = remake(prob; p = [:c => -1.0])
            @test getp(remake(q3; p = [:Jx => 20.0]), :c)(remake(q3; p = [:Jx => 20.0])) == -1.0
            @test getp(remake(q3; p = [:a₀ => 5.0]), :c)(remake(q3; p = [:a₀ => 5.0])) == 10.0
            # u = V₀[2] + 1: kept under a₀, re-derived under V₀; its dependants follow
            q4 = remake(prob; p = [:u => 4.0])                   # u named: V₁, z re-derived
            v4 = p60ao_vals(q4)
            @test (v4.u, v4.V₁, v4.z) == (4.0, [0.0, 8.0, 2.0], 4.0)
            v4a = p60ao_vals(remake(q4; p = [:a₀ => 9.0]))
            @test (v4a.u, v4a.V₁, v4a.z) == (4.0, [0.0, 8.0, 2.0], 4.0)
            @test total_energy(remake(q4; p = [:a₀ => 9.0])) == 105 + 1 + 49   # 155
            v4V = p60ao_vals(remake(q4; p = [:V₀ => [0.0, 5.0, 15.0]]))
            @test (v4V.u, v4V.V₁, v4V.z) == (16.0, [0.0, 4.0, 4.0], 8.0)
            # V₁ (a table reading a table entry and a computed scalar)
            q5 = remake(prob; p = [:V₁ => [0.0, 7.0, 7.0]])
            @test p60ao_vals(remake(q5; p = [:a₀ => 9.0])).V₁ == [0.0, 7.0, 7.0]
            @test p60ao_vals(remake(q5; p = [:Jx => 20.0])).V₁ == [0.0, 7.0, 7.0]
            @test total_energy(remake(q5; p = [:a₀ => 9.0])) == 105 + 2 * 4   # 113
            @test p60ao_vals(remake(q5; p = [:V₀ => [0.0, 5.0, 15.0]])).V₁ == [0.0, 4.0, 4.0]
            # J with function entries: explicit numbers kept under a₀, re-derived under Jx
            M = [0 5 5; 5 1 3; 5 3 1]
            q6 = remake(prob; p = [:J => M])
            @test p60ao_vals(q6).j == 3.0 + 5.0                  # j follows J: M[P,Q] + M[0,1]
            v6 = p60ao_vals(remake(q6; p = [:a₀ => 9.0]))
            @test v6.J == M && v6.j == 8.0
            v6J = p60ao_vals(remake(q6; p = [:Jx => 25.0]))
            @test v6J.J == p60ao_Jf(5.0, 25.0) && v6J.j == 25.0
        end

        @testset "integrator setters" begin
            integ = init(prob, SequentialCPM())
            step!(integ)
            integ.ps[:a₀] = 9.0
            @test integ.ps[:w] ≈ 3 + π atol = 1e-12
            @test integ.ps[:m] == 19.0 && integ.ps[:c] == 18.0
            integ.ps[:w] = 1.0
            integ.ps[:λ] = 2.0
            @test integ.ps[:w] == 1.0
            setp(integ, :V₀)(integ, [0.0, 5.0, 15.0])
            iv = p60ao_ivals(integ)
            @test (iv.u, iv.u_P, iv.V₁, iv.z, iv.w) == (16.0, 6.0, [0.0, 4.0, 4.0], 8.0, 1.0)
            integ.ps[:Jx] = 25.0
            @test p60ao_ivals(integ).J == p60ao_Jf(5.0, 25.0) && integ.ps[:j] == 25.0
            @test typeof(integ.p) === typeof(prob.p)
            step!(integ)
            @test integ.t == 2
        end

        @testset "Float32" begin
            p32 = PottsProblem(sys, op, (0, 5); seed = 7, T = Float32)
            v32 = p60ao_vals(p32)
            @test all(k -> getp(p32, k)(p32) isa Float32, P60AO_SCALARS)
            @test eltype(getp(p32, :J)(p32)) === Float32 && eltype(getp(p32, :V₁)(p32)) === Float32
            @test v32.w ≈ Float32(2 + π) rtol = 4eps(Float32)
            @test v32.e₁ ≈ 30.0f0 rtol = 4eps(Float32)
            @test v32.g ≈ Float32(4ℯ) rtol = 4eps(Float32)
            @test (v32.c, v32.c₂, v32.c₃, v32.h, v32.m) == (8.0f0, 2.0f0, 10.0f0, 5.0f0, 9.0f0)
            @test (v32.u, v32.u_P, v32.j, v32.z) == (9.0f0, 10.0f0, 15.0f0, 6.0f0)
            @test v32.J == Float32.(p60ao_Jf(4.0, 16.0)) && v32.V₁ == Float32[0, 8, 3]
            @test total_energy(p32) == 142.0f0
            q32 = remake(p32; p = [:a₀ => 9.0])
            @test typeof(q32.p) === typeof(p32.p)
            @test getp(q32, :w)(q32) isa Float32
            @test getp(q32, :w)(q32) ≈ Float32(3 + π) rtol = 4eps(Float32)
            i32 = init(p32, SequentialCPM())
            i32.ps[:Jx] = 25.0
            @test eltype(i32.ps[:J]) === Float32 && Matrix(i32.ps[:J]) == Float32.(p60ao_Jf(5.0, 25.0))
            @test typeof(i32.p) === typeof(p32.p)
        end

        @testset "negative controls on the fixture" begin
            # a function that fails on the values raises, at build and on remake (no NaN)
            @test p60ao_error(() -> PottsProblem(sys, [op; :a₀ => -1.0], (0, 5))) isa Exception
            @test p60ao_error(() -> remake(prob; p = [:a₀ => -1.0])) isa Exception
            @test p60ao_error(() -> remake(prob; p = [:u => -1.0])) isa Exception    # sqrt(u) in V₁
            # unknown names and asymmetric contact tables are still rejected
            @test p60ao_error(() -> remake(prob; p = [:nosuch => 1.0])) isa ArgumentError
            err = p60ao_error(() -> remake(prob; p = [:J => [0 1 2; 1 0 0; 3 0 0]]))
            @test err isa ArgumentError && occursin("symmetric", sprint(showerror, err))
            # the source problem is unchanged by every remake above
            v0 = p60ao_vals(prob)
            @test v0.w ≈ 2 + π atol = 1e-12
            @test (v0.a₀, v0.u, v0.j, v0.z, v0.m) == (4.0, 9.0, 15.0, 6.0, 9.0)
            @test v0.V₁ == [0.0, 8.0, 3.0] && v0.J == p60ao_Jf(4.0, 16.0)
            @test total_energy(prob) == 142.0
        end
    end
end
