# P6.0ap (ROADMAP Phase 6, step 0): parameter-setter loose ends (P6.0ak review). Frozen
# (AUTONOMY §7.2).
#
# Today (e006198b):
#   1. `setp(integ, [:λ, :w])` (a parameter and a state) builds SII's generic setter, which
#      then throws a `MethodError` (`set_parameter(::PottsParameters, ::Float64, ::Nothing)`)
#      when applied, after it has set `λ`.
#   2. `SII.setsym(integ, [:β, :α])` is applied one name at a time: β = 5 is set, then the
#      change of α re-derives β (= 2α = 10), so the result depends on the order; D-112
#      makes a list one change.
#   3. `SII.remake_buffer(prob, prob.p, [:λ], [3.0])` overflows the stack: SII's untyped
#      fallback calls its deprecated `Dict` method, which calls the fallback again.
#   4. `setp`/`getp`/`integ.ps[x]` on a hand-written CorePotts problem (`CPMFunction`
#      without a model, `f.sys === nothing`) throw `MethodError: symbolic_container(::Nothing)`,
#      although CorePotts' own `set_parameter(p::NamedTuple, v, i::Symbol)` (and
#      `SII.set_parameter!(integ, v, :T)`) already set a NamedTuple parameter object by name.
#
# Rule (D-116).
#   * `setp(x, list)` (x an integrator, problem, function or model description) whose list
#     names a state (as well as parameters) is an `ArgumentError` when the setter is built,
#     pointing to `setu` / `setsym`; nothing is set.
#   * `SII.setsym(integ, list)`: the parameters of the list are set as one change (D-112),
#     the same as `setp(integ, those parameters)`; its states are set as by `setu`. A list of
#     states only works as today; a list of parameters only ≡ `setp`; a mixed list sets the
#     states and the parameters, the parameters as one change. A single name is unchanged.
#     A name that is neither is an `ArgumentError` when the setter is built. A rejected
#     parameter value leaves the parameters unchanged (all-or-nothing, as `setp`).
#   * `SII.remake_buffer(prob, prob.p, keys, vals)` on a model's problem returns a new
#     parameter object equal to `remake(prob; p = Dict(keys .=> vals)).p` (one change, the
#     problem's scalar type, the same type); keys may be names or symbolic parameters; the
#     original is untouched; an unknown key is an `ArgumentError`.
#   * A hand-written CorePotts problem whose parameter object is a NamedTuple: its fields are
#     its parameters by name. `getp`, `setp` (one name or a list), `integ.ps[x]` work on an
#     integrator (values converted to the field's type, so the object's type never
#     changes), `getp` works on the problem, `setp` applied to the problem is the usual
#     "problem parameters are immutable" `ArgumentError`; a name that is not a field is an
#     `ArgumentError` when the setter is built. A parameter object that is not a NamedTuple
#     has no names: `setp`/`getp` by name are an `ArgumentError` (never a `MethodError`).
#
# Values by hand (fixture of P6.0ak/P6.0an plus a cell variable w, default 0): two 3×3 cells
# P (x = 3:5) and Q (x = 6:8) on a 12×12 lattice, von Neumann contacts:
#   contacts = 9 J[M,P] + 9 J[M,Q] + 3 J[P,Q] = 21 Jx − 15 = 321 at Jx = 16;
#   cells = λ ((9 − V₀[P] + w)² + (9 − V₀[Q] + w)²), V₀ = [0, γ, β], α = 4 → β = 8 → γ = 9.
#   Defaults: 321 + 1 = 322. λ = 3: 324. α = 5 (β = 10, γ = 11): 321 + 4 + 1 = 326.
#   One change {β = 5, α = 5} (γ = 6): 321 + 9 + 16 = 346; one name at a time (β, then α)
#   gives β = 10, γ = 11 (326) instead.
using Test, Potts, PottsModels
using Potts: CorePotts
const P60AP_SII = CorePotts.SymbolicIndexingInterface

@potts_model P60apChain begin
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
    @variables w(cell) = 0.0
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(P, Q) => λ * (volume - V₀[kind] + w)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 10.0)
end

function p60ap_sigma()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:5] .= 2
    return σ
end
p60ap_Jf(x) = [0 x x; x 2 x-5; x x-5 14]

p60ap_ivals(i) = (α = i.ps[:α], β = i.ps[:β], γ = i.ps[:γ], λ = i.ps[:λ], Jx = i.ps[:Jx],
    J = Matrix(i.ps[:J]), V₀ = Vector(i.ps[:V₀]))
p60ap_pvals(q) = (α = getp(q, :α)(q), β = getp(q, :β)(q), γ = getp(q, :γ)(q), λ = getp(q, :λ)(q),
    Jx = getp(q, :Jx)(q), J = Matrix(getp(q, :J)(q)), V₀ = Vector(getp(q, :V₀)(q)))
p60ap_w(i) = Vector(i[:w])[1:2]

function p60ap_error(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end
p60ap_msg(e) = e === nothing ? "" : sprint(showerror, e)

# `remake_buffer` without risking the test process: SII's untyped 4-argument fallback calls
# its deprecated `Dict` method, which (unless a package adds a method) calls the fallback
# again, forever. When both calls would resolve to SII's own generic methods, the call is
# known to recurse and is not made; otherwise it is made, and a `StackOverflowError` is
# caught all the same.
function p60ap_remake_buffer(sys, buf, ks, vs)
    S = P60AP_SII
    m4 = which(S.remake_buffer, Tuple{typeof(sys), typeof(buf), typeof(ks), typeof(vs)})
    d = Dict(ks .=> vs)
    m3 = which(S.remake_buffer, Tuple{typeof(sys), typeof(buf), typeof(d)})
    if m4.module === S && m4.sig == Tuple{typeof(S.remake_buffer), Any, Any, Any, Any} &&
       m3.module === S
        return StackOverflowError()          # not called: would recurse (SII fallback ↔ Dict)
    end
    try
        return S.remake_buffer(sys, buf, ks, vs)
    catch e
        return e
    end
end

# hand-written CorePotts problems: a constant ΔH and a temperature read from `p`
p60ap_hw_dH(st, p, prop, ctx) = p.h
p60ap_hw_T(st, p, prop, ctx) = p.T
const P60AP_HW = CorePotts.CPMFunction(p60ap_hw_dH; temperature = p60ap_hw_T)
p60ap_hwt_dH(st, p, prop, ctx) = p[1]
p60ap_hwt_T(st, p, prop, ctx) = p[2]
const P60AP_HWT = CorePotts.CPMFunction(p60ap_hwt_dH; temperature = p60ap_hwt_T)

@testset "P6.0ap: parameter-setter loose ends" begin
    sys = P60apChain(; name = :chain)
    op = [ownership => p60ap_sigma(), kind => [:P, :Q]]
    prob = PottsProblem(sys, op, (0, 5); seed = 7)
    fresh() = init(prob, SequentialCPM())

    @testset "fixture (control)" begin
        v = p60ap_pvals(prob)
        @test (v.α, v.β, v.γ, v.λ, v.Jx) == (4.0, 8.0, 9.0, 1.0, 16.0)
        @test v.J == p60ap_Jf(16.0) && v.V₀ == [0.0, 9.0, 8.0]
        @test total_energy(prob) == 322.0
        i = fresh()
        @test p60ap_w(i) == [0.0, 0.0]
        # setp with a list is one change (D-112); one name at a time would give β = 10
        setp(i, [:β, :α])(i, [5.0, 5.0])
        v = p60ap_ivals(i)
        @test (v.α, v.β, v.γ, v.V₀) == (5.0, 5.0, 6.0, [0.0, 6.0, 5.0])
        # setu with a list of states works
        i = fresh()
        setu(i, [:w])(i, [[0.5, 0.5]])
        @test p60ap_w(i) == [0.5, 0.5]
    end

    @testset "setp with states in the list is an ArgumentError" begin
        for x in (fresh(), prob, prob.f, prob.f.sys)
            e = p60ap_error(() -> setp(x, [:λ, :w]))
            @test e isa ArgumentError
            @test occursin("setu", p60ap_msg(e)) || occursin("setsym", p60ap_msg(e))
        end
        i = fresh()
        e = p60ap_error(() -> setp(i, [:w, :β, :α]))
        @test e isa ArgumentError
        @test occursin("setu", p60ap_msg(e)) || occursin("setsym", p60ap_msg(e))
        # symbolic keys too
        e = p60ap_error(() -> setp(i, [Potts.lookup(sys, :λ), :w]))
        @test e isa ArgumentError
        # nothing was set
        @test p60ap_ivals(i).λ == 1.0 && p60ap_w(i) == [0.0, 0.0]
        # negative controls: a list of parameters, an unknown name (as before)
        @test p60ap_error(() -> setp(i, [:λ, :Jx])) === nothing
        e = p60ap_error(() -> setp(i, [:λ, :zz]))
        @test e isa ArgumentError && occursin("zz", p60ap_msg(e))
    end

    @testset "setsym with a list: the parameters are one change" begin
        # parameters only: the same as setp (β = 5 kept, γ re-derived from β)
        i = fresh()
        P60AP_SII.setsym(i, [:β, :α])(i, [5.0, 5.0])
        v = p60ap_ivals(i)
        @test (v.α, v.β, v.γ, v.V₀) == (5.0, 5.0, 6.0, [0.0, 6.0, 5.0])
        @test v.λ == 1.0 && v.J == p60ap_Jf(16.0)
        # order does not matter
        i = fresh()
        P60AP_SII.setsym(i, [:α, :β])(i, [5.0, 5.0])
        @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 5.0, 6.0)
        # a tuple of names, symbolic names
        i = fresh()
        P60AP_SII.setsym(i, (:β, :α))(i, (5.0, 5.0))
        @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 5.0, 6.0)
        i = fresh()
        P60AP_SII.setsym(i, [Potts.lookup(sys, :β), Potts.lookup(sys, :α)])(i, [5.0, 5.0])
        @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 5.0, 6.0)
        # an explicit table survives an unrelated change in the same list
        i = fresh()
        M = [0 5 5; 5 1 3; 5 3 1]
        P60AP_SII.setsym(i, [:J, :Jx, :λ])(i, [M, 20.0, 2.0])
        v = p60ap_ivals(i)
        @test (v.J, v.Jx, v.λ) == (M, 20.0, 2.0)
        # mixed: states set, the parameters as one change
        i = fresh()
        P60AP_SII.setsym(i, [:β, :α, :w])(i, [5.0, 5.0, [0.5, 0.5]])
        v = p60ap_ivals(i)
        @test (v.α, v.β, v.γ, v.V₀) == (5.0, 5.0, 6.0, [0.0, 6.0, 5.0])
        @test p60ap_w(i) == [0.5, 0.5]
        i = fresh()
        P60AP_SII.setsym(i, [:w, :β, :α])(i, [[0.5, 0.25], 5.0, 5.0])
        @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 5.0, 6.0)
        @test p60ap_w(i) == [0.5, 0.25]
        # states only: as today
        i = fresh()
        P60AP_SII.setsym(i, [:w])(i, [[0.5, 0.5]])
        @test p60ap_w(i) == [0.5, 0.5]
        @test p60ap_ivals(i).β == 8.0
        # a single name: unchanged (α re-derives β and γ)
        i = fresh()
        P60AP_SII.setsym(i, :α)(i, 5.0)
        @test (i.ps[:α], i.ps[:β], i.ps[:γ]) == (5.0, 10.0, 11.0)
        # the integrator runs on after the change
        i = fresh()
        P60AP_SII.setsym(i, [:β, :α])(i, [5.0, 5.0])
        step!(i)
        @test i.t == 1 && (i.ps[:β], i.ps[:γ]) == (5.0, 6.0)
        # negative controls: an unknown name; a rejected table leaves the parameters as they were
        @test p60ap_error(() -> P60AP_SII.setsym(fresh(), [:β, :zz])) isa ArgumentError
        i = fresh()
        e = p60ap_error(() -> P60AP_SII.setsym(i, [:α, :J])(i, [5.0, [0 9 9; 8 1 1; 9 1 1]]))
        @test e isa ArgumentError
        @test (i.ps[:α], i.ps[:β], i.ps[:J]) == (4.0, 8.0, p60ap_Jf(16.0))
    end

    @testset "remake_buffer on a model's problem" begin
        r = p60ap_remake_buffer(prob, prob.p, [:λ], [3.0])
        @test !(r isa Exception)
        if !(r isa Exception)
            @test typeof(r) === typeof(prob.p)
            @test r == remake(prob; p = Dict(:λ => 3.0)).p
            @test total_energy(remake(prob; p = r)) == 324.0
        end
        # an input change re-derives what reads it
        r = p60ap_remake_buffer(prob, prob.p, [:α], [5.0])
        @test !(r isa Exception)
        if !(r isa Exception)
            q = remake(prob; p = r)
            v = p60ap_pvals(q)
            @test (v.α, v.β, v.γ, v.V₀) == (5.0, 10.0, 11.0, [0.0, 11.0, 10.0])
            @test total_energy(q) == 326.0
        end
        # several keys: one change, in either order
        for (ks, vs) in (([:β, :α], [5.0, 5.0]), ([:α, :β], [5.0, 5.0]))
            r = p60ap_remake_buffer(prob, prob.p, ks, vs)
            @test !(r isa Exception)
            r isa Exception && continue
            @test r == remake(prob; p = Dict(ks .=> vs)).p
            q = remake(prob; p = r)
            @test (p60ap_pvals(q).β, p60ap_pvals(q).γ) == (5.0, 6.0)
            @test total_energy(q) == 346.0
        end
        # values take the problem's scalar type; symbolic keys
        r = p60ap_remake_buffer(prob, prob.p, [:λ], [3])
        @test !(r isa Exception) && typeof(r) === typeof(prob.p)
        r isa Exception || @test getp(remake(prob; p = r), :λ)(remake(prob; p = r)) === 3.0
        r = p60ap_remake_buffer(prob, prob.p, [Potts.lookup(sys, :λ)], [3.0])
        @test !(r isa Exception) && r == remake(prob; p = Dict(:λ => 3.0)).p
        # the original is untouched
        @test p60ap_pvals(prob).λ == 1.0 && p60ap_pvals(prob).β == 8.0
        @test total_energy(prob) == 322.0
        # negative controls: an unknown key; a variable is not a parameter
        @test p60ap_remake_buffer(prob, prob.p, [:zz], [1.0]) isa ArgumentError
        @test p60ap_remake_buffer(prob, prob.p, [:λ, :zz], [2.0, 1.0]) isa ArgumentError
        @test p60ap_remake_buffer(prob, prob.p, [:w], [1.0]) isa ArgumentError
    end

    @testset "hand-written CorePotts problems: a NamedTuple's fields are its parameters" begin
        σ = p60ap_sigma()
        hp = CorePotts.PottsProblem(P60AP_HW, CorePotts.initial_state(σ, Int32[1, 2]),
            CorePotts.Lattice((12, 12)), (0, 3), (h = 0.0, T = 10.0); seed = 1)
        hinit() = init(hp, SequentialCPM())
        # control: CorePotts' own setter already sets a field by name
        i = hinit()
        P60AP_SII.set_parameter!(i, 5.0, :T)
        @test i.p === (h = 0.0, T = 5.0)

        # getp
        i = hinit()
        @test p60ap_error(() -> getp(i, :T)) === nothing
        p60ap_error(() -> getp(i, :T)) === nothing && @test getp(i, :T)(i) === 10.0
        @test p60ap_error(() -> getp(hp, :h)) === nothing
        p60ap_error(() -> getp(hp, :h)) === nothing && @test getp(hp, :h)(hp) === 0.0
        # setp, one name: converted to the field's type
        i = hinit()
        e = p60ap_error(() -> setp(i, :T)(i, 5))
        @test e === nothing && i.p === (h = 0.0, T = 5.0)
        # setp, a list
        i = hinit()
        e = p60ap_error(() -> setp(i, [:T, :h])(i, [5.0, 1.0]))
        @test e === nothing && i.p === (h = 1.0, T = 5.0)
        # integ.ps
        i = hinit()
        e = p60ap_error(() -> (i.ps[:h] = 2.0))
        @test e === nothing && i.p === (h = 2.0, T = 10.0)
        e = p60ap_error(() -> i.ps[:T])
        @test e === nothing && i.ps[:T] === 10.0
        # the run uses the new value: ΔH = h, accepted with probability min(1, exp(−h/T))
        i = init(remake(hp; p = (h = 1.0e9, T = 1.0)), SequentialCPM())
        step!(i)
        @test i.stats.accepted == 0                                 # control: nothing accepted
        e = p60ap_error(() -> setp(i, :h)(i, -1.0))
        @test e === nothing
        e === nothing && (step!(i); @test i.stats.accepted > 0)
        # setp applied to the problem: immutable, as on a model's problem
        e = p60ap_error(() -> setp(hp, :T)(hp, 5.0))
        @test e isa ArgumentError && occursin("remake", p60ap_msg(e))
        @test hp.p === (h = 0.0, T = 10.0)
        # negative controls: a name that is not a field
        e = p60ap_error(() -> setp(hinit(), :zz))
        @test e isa ArgumentError
        @test occursin("zz", p60ap_msg(e))
        @test p60ap_error(() -> setp(hinit(), [:T, :zz])) isa ArgumentError
        @test p60ap_error(() -> getp(hinit(), :zz)) isa ArgumentError
        # a parameter object without names: a clear ArgumentError, not a MethodError
        tp = CorePotts.PottsProblem(P60AP_HWT, CorePotts.initial_state(σ, Int32[1, 2]),
            CorePotts.Lattice((12, 12)), (0, 3), (0.0, 10.0); seed = 1)
        ti = init(tp, SequentialCPM())
        @test p60ap_error(() -> setp(ti, :T)) isa ArgumentError
        @test p60ap_error(() -> setp(ti, [:T, :h])) isa ArgumentError
        @test p60ap_error(() -> getp(ti, :T)) isa ArgumentError
        @test ti.p === (0.0, 10.0)
    end
end
