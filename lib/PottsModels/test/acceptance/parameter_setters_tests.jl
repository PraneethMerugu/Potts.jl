# parameter-setter loose ends (after the computed parameters).
# the read-only computed-parameter rule (user OK 2026-10-20): a list naming
# a computed parameter (β) is refused whole; lists of base parameters are one change.
#
# Today (e006198b):
#   1. `setp(integ, [:λ, :w])` (a parameter and a state) builds SII's generic setter, which
#      then throws a `MethodError` (`set_parameter(::PottsParameters, ::Float64,
#      ::Nothing)`) when applied, after it has set `λ`.
#   2. `SII.setsym(integ, [:β, :α])` is applied one name at a time: β = 5 is set, then the
#      change of α re-derives β (= 2α = 10), so the result depends on the order; D-112
#      makes a list one change.
#   3. `SII.remake_buffer(prob, prob.p, [:λ], [3.0])` overflows the stack: SII's untyped
#      fallback calls its deprecated `Dict` method, which calls the fallback again.
#   4. `setp`/`getp`/`integ.ps[x]` on a hand-written CorePotts problem (`CPMFunction`
#      without a model, `f.sys === nothing`) throw `MethodError:
#      symbolic_container(::Nothing)`, although CorePotts' own `set_parameter(p::NamedTuple,
#      v, i::Symbol)` (and `SII.set_parameter!(integ, v, :T)`) already set a NamedTuple
#      parameter object by name.
#
# Rule (D-116).
#   * `setp(x, list)` (x an integrator, problem, function or model description) whose list
#     names a state (as well as parameters) is an `ArgumentError` when the setter is built,
#     pointing to `setu` / `setsym`; nothing is set.
#   * `SII.setsym(integ, list)`: the parameters of the list are set as one change (the
#     read-only computed-parameter rule: then every computed parameter is derived again; a
#     list naming one is refused whole), the same as `setp(integ, those parameters)`; its
#     states are set as by `setu`. A list of states only works as today; a list of
#     parameters only ≡ `setp`; a mixed list sets the states and the parameters, the
#     parameters as one change. A single name is unchanged. A name that is neither is an
#     `ArgumentError` when the setter is built. A rejected parameter value leaves the
#     parameters unchanged (all-or-nothing, as `setp`).
#   * `SII.remake_buffer(prob, prob.p, keys, vals)` on a model's problem returns a new
#     parameter object equal to `remake(prob; p = Dict(keys .=> vals)).p` (one change, the
#     problem's scalar type, the same type); keys may be names or symbolic parameters; the
#     original is untouched; an unknown key is an `ArgumentError`.
#   * A hand-written CorePotts problem whose parameter object is a NamedTuple: its fields
#     are its parameters by name. `getp`, `setp` (one name or a list), `integ.ps[x]` work on
#     an integrator (values converted to the field's type, so the object's type never
#     changes), `getp` works on the problem, `setp` applied to the problem is the usual
#     "problem parameters are immutable" `ArgumentError`; a name that is not a field is an
#     `ArgumentError` when the setter is built. A parameter object that is not a NamedTuple
#     has no names: `setp`/`getp` by name are an `ArgumentError` (never a `MethodError`).
#
# Values by hand (fixture of `computed_parameters_tests.jl`/`remake_namedtuple_tests.jl`
# plus a cell variable w, default 0): two 3×3 cells P (x = 3:5) and Q (x = 6:8) on a 12×12
# lattice, von Neumann contacts:
#   contacts = 9 J[M,P] + 9 J[M,Q] + 3 J[P,Q] = 21 Jx − 15 = 321 at Jx = 16;
#   cells = λ ((9 − V₀[P] + w)² + (9 − V₀[Q] + w)²), V₀ = [0, γ, β], α = 4 → β = 8 → γ = 9.
#   Defaults: 321 + 1 = 322. λ = 3: 324. α = 5 (β = 10, γ = 11): 321 + 4 + 1 = 326.
#   One change {λ = 2, α = 5} (β = 10, γ = 11): 321 + 2 (4 + 1) = 331.

@testsetup module ParameterSettersSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: CorePotts
const SII = CorePotts.SymbolicIndexingInterface
@potts_model Chain begin
    @kinds medium P Q
    @parameters begin
        α = 4.0
        β = 2α
        γ = β + 1
        λ = 1.0
        Jx = 16.0
        J[kind, kind] = [0 Jx Jx; Jx 2 Jx - 5; Jx Jx - 5 14]
        V₀[kind] = [0.0, γ, β]
    end
    @variables w(cell) = 0.0
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => λ * (volume - V₀[kind] + w)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 10.0)
end
function sigma()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:5] .= 2
    return σ
end
setter_Jf(x) = [0 x x; x 2 x - 5; x x - 5 14]
function ivals(i)
    return (
        α = i.ps[:α], β = i.ps[:β], γ = i.ps[:γ], λ = i.ps[:λ], Jx = i.ps[:Jx],
        J = Matrix(i.ps[:J]), V₀ = Vector(i.ps[:V₀]),
    )
end
function pvals(q)
    return (
        α = getp(q, :α)(q), β = getp(q, :β)(q), γ = getp(q, :γ)(q), λ = getp(q, :λ)(q),
        Jx = getp(q, :Jx)(q), J = Matrix(getp(q, :J)(q)), V₀ = Vector(getp(q, :V₀)(q)),
    )
end
setter_w(i) = Vector(i[:w])[1:2]
function setter_error(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end
msg(e) = e === nothing ? "" : sprint(showerror, e)
# `remake_buffer` without risking the test process: SII's untyped 4-argument fallback calls
# its deprecated `Dict` method, which (unless a package adds a method) calls the fallback
# again, forever. When both calls would resolve to SII's own generic methods, the call is
# known to recurse and is not made; otherwise it is made, and a `StackOverflowError` is
# caught all the same.
function setter_remake_buffer(sys, buf, ks, vs)
    S = SII
    m4 = which(S.remake_buffer, Tuple{typeof(sys), typeof(buf), typeof(ks), typeof(vs)})
    d = Dict(ks .=> vs)
    m3 = which(S.remake_buffer, Tuple{typeof(sys), typeof(buf), typeof(d)})
    if m4.module === S && m4.sig == Tuple{typeof(S.remake_buffer), Any, Any, Any, Any} &&
            m3.module === S
        # not called: would recurse (SII fallback ↔ Dict)
        return StackOverflowError()
    end
    try
        return S.remake_buffer(sys, buf, ks, vs)
    catch e
        return e
    end
end
# hand-written CorePotts problems: a constant ΔH and a temperature read from `p`
hw_dH(st, p, prop, ctx) = p.h
hw_T(st, p, prop, ctx) = p.T
const SETTER_HW = CorePotts.CPMFunction(hw_dH; temperature = hw_T)
hwt_dH(st, p, prop, ctx) = p[1]
hwt_T(st, p, prop, ctx) = p[2]
const HWT = CorePotts.CPMFunction(hwt_dH; temperature = hwt_T)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "parameter setters: parameter-setter loose ends" setup = [
    ParameterSettersSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "parameter setters: parameter-setter loose ends" begin
        sys = Chain(; name = :chain)
        op = [ownership => sigma(), kind => [:P, :Q]]
        prob = PottsProblem(sys, op, (0, 5); seed = 7)
        fresh() = init(prob, SequentialCPM())

        @testset "fixture (control)" begin
            v = pvals(prob)
            @test (v.α, v.β, v.γ, v.λ, v.Jx) == (4.0, 8.0, 9.0, 1.0, 16.0)
            @test v.J == setter_Jf(16.0) && v.V₀ == [0.0, 9.0, 8.0]
            @test total_energy(prob) == 322.0
            i = fresh()
            @test setter_w(i) == [0.0, 0.0]
            # setp with a list naming the computed β is refused whole (the read-only
            # computed-parameter rule); a list of base parameters is one change, then β, γ,
            # V₀ follow α
            @test setter_error(() -> setp(i, [:β, :α])(i, [5.0, 5.0])) isa ArgumentError
            @test ivals(i).α == 4.0
            setp(i, [:λ, :α])(i, [2.0, 5.0])
            v = ivals(i)
            @test (v.α, v.β, v.γ, v.V₀, v.λ) == (5.0, 10.0, 11.0, [0.0, 11.0, 10.0], 2.0)
            # setu with a list of states works
            i = fresh()
            setu(i, [:w])(i, [[0.5, 0.5]])
            @test setter_w(i) == [0.5, 0.5]
        end

        @testset "setp with states in the list is an ArgumentError" begin
            for x in (fresh(), prob, prob.f, prob.f.sys)
                @test_throws ArgumentError setp(x, [:λ, :w])
            end
            i = fresh()
            @test_throws ArgumentError setp(i, [:w, :β, :α])
            # symbolic keys too
            @test_throws ArgumentError setp(i, [Potts.lookup(sys, :λ), :w])
            # nothing was set
            @test ivals(i).λ == 1.0 && setter_w(i) == [0.0, 0.0]
            # negative controls: a list of parameters, an unknown name (as before)
            @test setter_error(() -> setp(i, [:λ, :Jx])) === nothing
            @test_throws ArgumentError setp(i, [:λ, :zz])
        end

        @testset "setsym with a list: the parameters are one change" begin
            # parameters only: the same as setp (β, γ derived from the new α)
            i = fresh()
            SII.setsym(i, [:λ, :α])(i, [2.0, 5.0])
            v = ivals(i)
            @test (v.α, v.β, v.γ, v.V₀, v.λ) == (5.0, 10.0, 11.0, [0.0, 11.0, 10.0], 2.0)
            @test v.J == setter_Jf(16.0)
            # order does not matter
            i = fresh()
            SII.setsym(i, [:α, :λ])(i, [5.0, 2.0])
            @test (i.ps[:α], i.ps[:β], i.ps[:γ], i.ps[:λ]) == (5.0, 10.0, 11.0, 2.0)
            # a tuple of names, symbolic names
            i = fresh()
            SII.setsym(i, (:λ, :α))(i, (2.0, 5.0))
            @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 10.0, 11.0)
            i = fresh()
            SII.setsym(i, [Potts.lookup(sys, :λ), Potts.lookup(sys, :α)])(i, [2.0, 5.0])
            @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 10.0, 11.0)
            # a list naming a computed parameter (β, the table J) is refused whole, when
            # built
            for names in ([:β, :α], [:α, :β], [:J, :Jx, :λ], [:β, :α, :w])
                i = fresh()
                @test setter_error(() -> SII.setsym(i, names)) isa ArgumentError
                @test (i.ps[:α], i.ps[:β], i.ps[:λ]) == (4.0, 8.0, 1.0)
            end
            # a table's input in a list: the table follows it
            i = fresh()
            SII.setsym(i, [:Jx, :λ])(i, [20.0, 2.0])
            v = ivals(i)
            @test (v.J, v.Jx, v.λ) == (setter_Jf(20.0), 20.0, 2.0)
            # mixed: states set, the parameters as one change
            i = fresh()
            SII.setsym(i, [:λ, :α, :w])(i, [2.0, 5.0, [0.5, 0.5]])
            v = ivals(i)
            @test (v.α, v.β, v.γ, v.V₀) == (5.0, 10.0, 11.0, [0.0, 11.0, 10.0])
            @test setter_w(i) == [0.5, 0.5]
            i = fresh()
            SII.setsym(i, [:w, :λ, :α])(i, [[0.5, 0.25], 2.0, 5.0])
            @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 10.0, 11.0)
            @test setter_w(i) == [0.5, 0.25]
            # states only: as today
            i = fresh()
            SII.setsym(i, [:w])(i, [[0.5, 0.5]])
            @test setter_w(i) == [0.5, 0.5]
            @test ivals(i).β == 8.0
            # a single name: unchanged (α re-derives β and γ)
            i = fresh()
            SII.setsym(i, :α)(i, 5.0)
            @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 10.0, 11.0)
            # the integrator runs on after the change
            i = fresh()
            SII.setsym(i, [:λ, :α])(i, [2.0, 5.0])
            step!(i)
            @test i.t == 1 && (i.ps[:β], i.ps[:γ]) == (10.0, 11.0)
            # negative controls: an unknown name; a rejected value leaves the parameters as
            # they were
            @test setter_error(() -> SII.setsym(fresh(), [:λ, :zz])) isa ArgumentError
            i = fresh()
            # Jx is a number
            e = setter_error(() -> SII.setsym(i, [:α, :Jx])(i, [5.0, [1.0, 2.0]]))
            @test e isa ArgumentError
            @test (i.ps[:α], i.ps[:β], i.ps[:J]) == (4.0, 8.0, setter_Jf(16.0))
        end

        @testset "remake_buffer on a model's problem" begin
            r = setter_remake_buffer(prob, prob.p, [:λ], [3.0])
            @test !(r isa Exception)
            if !(r isa Exception)
                @test typeof(r) === typeof(prob.p)
                @test r == remake(prob; p = Dict(:λ => 3.0)).p
                @test total_energy(remake(prob; p = r)) == 324.0
            end
            # an input change re-derives what reads it
            r = setter_remake_buffer(prob, prob.p, [:α], [5.0])
            @test !(r isa Exception)
            if !(r isa Exception)
                q = remake(prob; p = r)
                v = pvals(q)
                @test (v.α, v.β, v.γ, v.V₀) == (5.0, 10.0, 11.0, [0.0, 11.0, 10.0])
                @test total_energy(q) == 326.0
            end
            # several keys: one change, in either order
            for (ks, vs) in (([:λ, :α], [2.0, 5.0]), ([:α, :λ], [5.0, 2.0]))
                r = setter_remake_buffer(prob, prob.p, ks, vs)
                @test !(r isa Exception)
                r isa Exception && continue
                @test r == remake(prob; p = Dict(ks .=> vs)).p
                q = remake(prob; p = r)
                @test (pvals(q).β, pvals(q).γ) == (10.0, 11.0)
                @test total_energy(q) == 331.0
            end
            # keys naming the computed β: refused whole (the read-only computed-parameter
            # rule)
            @test setter_remake_buffer(prob, prob.p, [:β, :α], [5.0, 5.0]) isa ArgumentError
            # values take the problem's scalar type; symbolic keys
            r = setter_remake_buffer(prob, prob.p, [:λ], [3])
            @test !(r isa Exception) && typeof(r) === typeof(prob.p)
            r isa Exception ||
                @test getp(remake(prob; p = r), :λ)(remake(prob; p = r)) === 3.0
            r = setter_remake_buffer(prob, prob.p, [Potts.lookup(sys, :λ)], [3.0])
            @test !(r isa Exception) && r == remake(prob; p = Dict(:λ => 3.0)).p
            # the original is untouched
            @test pvals(prob).λ == 1.0 && pvals(prob).β == 8.0
            @test total_energy(prob) == 322.0
            # negative controls: an unknown key; a variable is not a parameter
            @test setter_remake_buffer(prob, prob.p, [:zz], [1.0]) isa ArgumentError
            @test setter_remake_buffer(prob, prob.p, [:λ, :zz], [2.0, 1.0]) isa
                ArgumentError
            @test setter_remake_buffer(prob, prob.p, [:w], [1.0]) isa ArgumentError
        end

        @testset "hand-written CorePotts problems: a NamedTuple's fields are its \
            parameters" begin
            σ = sigma()
            hp = CorePotts.PottsProblem(
                SETTER_HW, CorePotts.initial_state(σ, Int32[1, 2]),
                CorePotts.Lattice((12, 12)), (0, 3), (h = 0.0, T = 10.0); seed = 1
            )
            hinit() = init(hp, SequentialCPM())
            # control: CorePotts' own setter already sets a field by name
            i = hinit()
            SII.set_parameter!(i, 5.0, :T)
            @test i.p === (h = 0.0, T = 5.0)

            # getp
            i = hinit()
            @test setter_error(() -> getp(i, :T)) === nothing
            setter_error(() -> getp(i, :T)) === nothing && @test getp(i, :T)(i) === 10.0
            @test setter_error(() -> getp(hp, :h)) === nothing
            setter_error(() -> getp(hp, :h)) === nothing && @test getp(hp, :h)(hp) === 0.0
            # setp, one name: converted to the field's type
            i = hinit()
            e = setter_error(() -> setp(i, :T)(i, 5))
            @test e === nothing && i.p === (h = 0.0, T = 5.0)
            # setp, a list
            i = hinit()
            e = setter_error(() -> setp(i, [:T, :h])(i, [5.0, 1.0]))
            @test e === nothing && i.p === (h = 1.0, T = 5.0)
            # integ.ps
            i = hinit()
            e = setter_error(() -> (i.ps[:h] = 2.0))
            @test e === nothing && i.p === (h = 2.0, T = 10.0)
            e = setter_error(() -> i.ps[:T])
            @test e === nothing && i.ps[:T] === 10.0
            # the run uses the new value: ΔH = h, accepted with probability min(1,
            # exp(−h/T))
            i = init(remake(hp; p = (h = 1.0e9, T = 1.0)), SequentialCPM())
            step!(i)
            # control: nothing accepted
            @test i.stats.accepted == 0
            e = setter_error(() -> setp(i, :h)(i, -1.0))
            @test e === nothing
            e === nothing && (step!(i); @test i.stats.accepted > 0)
            # setp applied to the problem writes the problem's parameters (SciML), not
            # another's
            hq = remake(hp)
            e = setter_error(() -> setp(hq, :T)(hq, 5.0))
            @test e === nothing && hq.p === (h = 0.0, T = 5.0)
            @test hp.p === (h = 0.0, T = 10.0)
            # negative controls: a name that is not a field
            @test_throws ArgumentError setp(hinit(), :zz)
            @test_throws ArgumentError setp(hinit(), [:T, :zz])
            @test_throws ArgumentError getp(hinit(), :zz)
            # a parameter object without names: a clear ArgumentError, not a MethodError
            tp = CorePotts.PottsProblem(
                HWT, CorePotts.initial_state(σ, Int32[1, 2]),
                CorePotts.Lattice((12, 12)), (0, 3), (0.0, 10.0); seed = 1
            )
            ti = init(tp, SequentialCPM())
            @test setter_error(() -> setp(ti, :T)) isa ArgumentError
            @test setter_error(() -> setp(ti, [:T, :h])) isa ArgumentError
            @test setter_error(() -> getp(ti, :T)) isa ArgumentError
            @test ti.p === (0.0, 10.0)
        end
    end
end
