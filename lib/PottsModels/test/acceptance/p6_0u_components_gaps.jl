# P6.0u (ROADMAP Phase 6, step 0; D-084, D-088, D-081, D-080 follow-ups): the remaining
# `@components` gaps and three review nits. Frozen (AUTONOMY §7.3; D-133).
#
#  1. MTK `tstops` and `assertions` of a component System are rejected by name at
#     `mtkcompile`, like the F7 fields (D-084): today they are accepted and ignored.
#  2. A component binding that Potts rejects (a variable's or parameter's value given as an
#     MTK expression: `y(t) = 2k`, `y(t) = 2z`, `k2 = 2k`, `initial_conditions = [y => 2k]`,
#     a discrete `X(t) = !Y`) names the component: `component \`comp7\`` (the F7 form) or the
#     location `@components cells comp7` (the form discrete ticks already carry). Today:
#     "cell variable `comp7₊y` has no initial value", "unknown symbol `k2` in …",
#     "`2k` does not reduce to a number …", without the component.
#  3. An `x′` `UndefVarError` raised inside a hand-written (non-`@potts_model`) `@extend` base
#     propagates unchanged; the extension does not relabel it with its own (or another
#     base's) description of `x` (D-088 residual). Today it becomes "`x′`: primes exist only
#     for site/field variables … `x` is a cell variable" from the outer model.
#  4. `init` does not warn about `frozen_varies` when the system defines `frozen_varies`
#     itself (outside CorePotts), even as `false` (a deliberately static mask); the warning
#     still fires for a custom `remake_frozen` with CorePotts' default `frozen_varies` (D-081).
#  5. The temperature's `integral(Pre(x))` error carries its location "in @sweep" (D-080).
#
# Errors may surface while a macro expands (a `LoadError`), at `mtkcompile`, at
# `PottsProblem` or at `solve`; the helpers unwrap a `LoadError` and say which stage they
# require. Fingerprints of the fixtures touched are pinned (recorded on fe057508).
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, @variables, @parameters
const P60U_MTKB = Potts.ModelingToolkitBase

const P60U_SYSTEM = Ref{Any}(nothing)
const P60U_ONE = (s = zeros(Int32, 10, 10); s[3:5, 3:5] .= 1; s)
const P60U_OP = [ownership => P60U_ONE, kind => [:A]]

"""A one-kind model with the component `comp = P60U_SYSTEM[]` in `scope` (`cells(A)` or
`model`) and the extra statements `stmts`."""
function p60u_model(sys, comp::Symbol, stmts...; scope = :(cells(A)))
    P60U_SYSTEM[] = sys
    decl = Expr(:macrocall, Symbol("@components"), LineNumberNode(@__LINE__, Symbol(@__FILE__)), scope,
        :($comp = P60U_SYSTEM[]))
    ex = quote
        @potts_model P60uModel begin
            @kinds medium A
            $decl
            $(stmts...)
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        P60uModel(; name = :p60u)
    end
    return Base.invokelatest(eval, ex)
end

"""`:ok` if `f()` throws an `ArgumentError` (possibly inside a `LoadError`) whose message
matches every one of `words` (strings or regexes); otherwise what happened."""
function p60u_rejection(f, words...)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        e isa ArgumentError || return "not an ArgumentError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        msg = sprint(showerror, e)
        all(w -> occursin(w, msg), words) || return "message does not match $(words): $(first(msg, 500))"
        return :ok
    end
    return "accepted silently"
end

"""Positive control: the model compiles, builds a problem and runs one MCS."""
function p60u_builds(m, op = P60U_OP)
    mtkcompile(m) isa CompiledPottsSystem || return false
    prob = PottsProblem(m, op, (0, 1))
    return Symbol(solve(prob, SequentialCPM(; proposal = Moore(1))).retcode) === :Success
end

"""Build, make the problem and run one MCS: the stage where a binding is rejected is free."""
p60u_full(m) = (mtkcompile(m); solve(PottsProblem(m, P60U_OP, (0, 1)), SequentialCPM(; proposal = Moore(1))))

p60u_fingerprint(m, op = P60U_OP) = PottsProblem(m, op, (0, 1)).f.fingerprint

"""A message names component `c`: the F7 form `component \`c\``, or the location
`@components cells c` / `@components model c` (as discrete ticks carry today)."""
p60u_names(c) = Regex("component `$c`|@components (?:cells|model)\\S* $c\\b")

# ---------------------------------------------------------------------------------------
# 1. MTK tstops and assertions

"""The continuous component `comp7`: `D(y) ~ -k y`, `D(z) ~ -z`, plus `feature(y, z, k)`."""
function p60u_continuous(feature = (y, z, k) -> (;))
    t = Potts.t
    @variables y(t) = 1.0 z(t) = 0.0
    @parameters k = 0.3
    return System([Potts.D(y) ~ -k * y, Potts.D(z) ~ -z], t; name = :comp7, feature(y, z, k)...)
end

"""The discrete component `net7`: a counter `C(k) ~ C(k-1) + 1`, plus `feature(C)`."""
function p60u_discrete(feature = C -> (;))
    t = Potts.t
    k = ShiftIndex(t, 0)
    @variables C(t) = 0.0
    return System([C(k) ~ C(k - 1) + 1], t; name = :net7, feature(C)...)
end

"""`comp7` holding a subsystem `inner` (`D(y) ~ -y`) that carries `feature(y)`."""
function p60u_nested(feature = y -> (;))
    t = Potts.t
    @variables y(t) = 1.0
    inner = System([Potts.D(y) ~ -y], t; name = :inner, feature(y)...)
    @variables z(t) = 0.0
    return System([Potts.D(z) ~ -z], t; name = :comp7, systems = [inner])
end

@testset "P6.0u 1: MTK tstops and assertions are rejected by name" begin
    # positive controls: the same components without the feature build and run
    @test p60u_builds(p60u_model(p60u_continuous(), :comp7))
    @test p60u_builds(p60u_model(p60u_continuous(), :comp7; scope = :model))
    @test p60u_builds(p60u_model(p60u_discrete(), :net7))
    @test p60u_builds(p60u_model(p60u_nested(), :comp7))
    # empty tstops/assertions are no feature: accepted
    @test p60u_builds(p60u_model(p60u_continuous((y, z, k) -> (; tstops = Float64[])), :comp7))
    # `guesses` stay ignored (D-084)
    @test p60u_builds(p60u_model(p60u_continuous((y, z, k) -> (; guesses = [z => 0.0])), :comp7))
    # an F7 field is still rejected (unchanged)
    @test p60u_rejection(() -> mtkcompile(p60u_model(p60u_continuous((y, z, k) -> (; continuous_events = [[y ~ 0.5] => [y ~ 1.0]])), :comp7)),
        p60u_names("comp7"), "continuous_events") === :ok

    rejected(sys, comp, word; scope = :(cells(A))) =
        p60u_rejection(() -> mtkcompile(p60u_model(sys, comp; scope)), p60u_names(String(comp)), word)
    # tstops: today accepted, and the run never stops at t = 0.5
    @test rejected(p60u_continuous((y, z, k) -> (; tstops = [0.5])), :comp7, "tstops") === :ok
    @test rejected(p60u_continuous((y, z, k) -> (; tstops = [0.5])), :comp7, "tstops"; scope = :model) === :ok
    @test rejected(p60u_discrete(C -> (; tstops = [0.5])), :net7, "tstops") === :ok
    @test rejected(p60u_nested(y -> (; tstops = [0.5])), :comp7, "tstops") === :ok
    # assertions: today accepted, and never checked
    @test rejected(p60u_continuous((y, z, k) -> (; assertions = Dict(y > -1.0 => "y negative"))), :comp7, "assertions") === :ok
    @test rejected(p60u_continuous((y, z, k) -> (; assertions = Dict(y > -1.0 => "y negative"))), :comp7, "assertions";
        scope = :model) === :ok
    @test rejected(p60u_discrete(C -> (; assertions = Dict(C >= 0 => "C negative"))), :net7, "assertions") === :ok
    @test rejected(p60u_nested(y -> (; assertions = Dict(y > -1.0 => "y negative"))), :comp7, "assertions") === :ok
end

# ---------------------------------------------------------------------------------------
# 2. Binding rejections name the component

@testset "P6.0u 2: binding rejections name the component ($scope)" for scope in (:(cells(A)), :model)
    t = Potts.t
    D = Potts.D
    rejected(sys, comp, words...) = p60u_rejection(() -> p60u_full(p60u_model(sys, comp; scope)),
        p60u_names(String(comp)), words...)
    builds(sys, comp) = p60u_builds(p60u_model(sys, comp; scope))
    # positive controls: plain values, and plain values given as MTK initial conditions
    let
        @parameters k = 0.3
        @variables y(t) = 1.0 z(t) = 0.0
        @test builds(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7), :comp7)
        @variables y(t)
        @test builds(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7, initial_conditions = [y => 2.0]), :comp7)
    end
    # a variable's value bound to a parameter (today: "… `comp7₊y` has no initial value")
    let
        @parameters k = 0.3
        @variables y(t) = 2k z(t) = 0.0
        @test rejected(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7), :comp7, r"\by\b") === :ok
    end
    # the same binding as an MTK initial condition (today: "`2k` does not reduce …")
    let
        @parameters k = 0.3
        @variables y(t) z(t) = 0.0
        @test rejected(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7, initial_conditions = [y => 2k]), :comp7, "2k") === :ok
    end
    # a parameter bound to another (today: "unknown symbol `k2` in …")
    let
        @parameters k = 0.3
        @parameters k2 = 2k
        @variables y(t) = 1.0 z(t) = 0.0
        @test rejected(System([D(y) ~ -k2 * y, D(z) ~ -k * z], t; name = :comp7), :comp7, "k2") === :ok
    end
    # a variable bound to another variable (today: "… `comp7₊y` has no initial value")
    let
        @parameters k = 0.3
        @variables z(t) = 0.5
        @variables y(t) = 2z
        @test rejected(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7), :comp7, r"\by\b") === :ok
    end
    # discrete: a node bound to another node (today: "… `net7₊X` has no initial value")
    let kk = ShiftIndex(t, 0)
        @variables Y(t)::Bool = false
        @variables X(t)::Bool = !Y
        @test rejected(System([X(kk) ~ !X(kk - 1), Y(kk) ~ X(kk - 1)], t; name = :net7), :net7, r"\bX\b") === :ok
    end
    # discrete: a parameter bound to another (named by its tick location today: unchanged)
    let kk = ShiftIndex(t, 0)
        @parameters s::Bool = false
        @parameters s2::Bool = !s
        @variables X(t)::Bool = false
        @test rejected(System([X(kk) ~ s2], t; name = :net7), :net7, "s2") === :ok
    end
end

@testset "P6.0u 2: a Potts parameter without a value is not blamed on a component" begin
    # negative control: the model's own parameter, next to a valid component
    m = p60u_model(p60u_continuous(), :comp7, :(@parameters q), :(@energy cells => q * volume))
    @test p60u_rejection(() -> p60u_full(m), "`q`", "no default") === :ok
    @test p60u_rejection(() -> p60u_full(m), r"^(?!.*component)"s) === :ok
end

# ---------------------------------------------------------------------------------------
# 3. `x′` errors from inside a hand-written `@extend` base

@potts_model P60uInner begin
    @kinds medium A
    @variables qq(cell) = 1.0
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
"""A hand-written base that reads an unbound `qq′` (a bug inside the base)."""
P60uHandBad(; name = :hand) = (qq′ + 1; P60uInner(; name))
"""A hand-written base that works."""
P60uHandOK(; name = :hand) = P60uInner(; name)
@potts_model P60uBadInner begin
    @kinds medium A
    @variables qq(cell) = 1.0
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9.0)^2 + qq′
    @sweep Metropolis(; temperature = 1.0)
end

# extensions of the bad hand-written base: the outer model declares `qq` as a cell variable,
# as a parameter, not at all, or an earlier base declares it
@potts_model P60uOuterCell begin
    @extend base = P60uHandBad()
    @variables qq(cell) = 2.0
end
@potts_model P60uOuterParam begin
    @extend base = P60uHandBad()
    @parameters qq = 2.0
end
@potts_model P60uOuterNone begin
    @extend base = P60uHandBad()
end
@potts_model P60uOuterTwo begin
    @extend first = P60uHandOK()
    @extend second = P60uHandBad()
end
# controls
@potts_model P60uOuterMacroBase begin              # a `@potts_model` base translates with its own description
    @extend base = P60uBadInner()
    @parameters qq = 2.0
end
@potts_model P60uOuterOwnPrime begin               # the outer model's own `g′`
    @extend base = P60uHandOK()
    @variables g(cell) = 2.0
    @energy cells => 0.1 * g′ * volume
end
@potts_model P60uOuterInherited begin              # `qq′` of `qq` bound from a hand-written base
    @extend qq = base = P60uHandOK()
    @energy cells => 0.1 * qq′ * volume
end
@potts_model P60uOuterOK begin
    @extend qq = base = P60uHandOK()
    @energy cells => 0.1 * qq * volume
end

"""`:ok` if `f()` throws the `UndefVarError` of `var` (possibly in a `LoadError`); otherwise what happened."""
function p60u_undef(f, var::Symbol)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        e isa UndefVarError && e.var === var && return :ok
        return "not the UndefVarError of $var: $(typeof(e)): $(first(sprint(showerror, e), 400))"
    end
    return "accepted silently"
end

@testset "P6.0u 3: an `x′` error inside a hand-written @extend base is not relabelled" begin
    qq′ = Symbol("qq′")
    # targets: the base's own error, whatever the outer model or an earlier base calls `qq`
    @test p60u_undef(() -> P60uOuterCell(; name = :o), qq′) === :ok
    @test p60u_undef(() -> P60uOuterParam(; name = :o), qq′) === :ok
    @test p60u_undef(() -> P60uOuterTwo(; name = :o), qq′) === :ok
    # control: with nothing named `qq` outside the base it is already unchanged
    @test p60u_undef(() -> P60uOuterNone(; name = :o), qq′) === :ok
    @test p60u_undef(() -> P60uHandBad(), qq′) === :ok
    # controls: a `@potts_model` base's own description (a cell variable, not the outer parameter)
    @test p60u_rejection(() -> P60uOuterMacroBase(; name = :o), "`qq′`", "primes exist only for site/field variables",
        "`qq` is a cell variable") === :ok
    # controls: the extension's own primes are still translated, after a hand-written base
    @test p60u_rejection(() -> P60uOuterOwnPrime(; name = :o), "`g′`", "primes exist only for site/field variables",
        "`g` is a cell variable") === :ok
    @test p60u_rejection(() -> P60uOuterInherited(; name = :o), "`qq′`", "primes exist only for site/field variables",
        "`qq` is a cell variable") === :ok
    # control: a valid extension of a hand-written base builds and runs
    @test p60u_builds(P60uOuterOK(; name = :o))
end

# ---------------------------------------------------------------------------------------
# 4. `init`'s `frozen_varies` warning

# a custom `remake_frozen` with `frozen_varies` defined outside CorePotts: false on purpose
# (a static mask), false through a supertype, true (the documented contract)
struct P60uStatic end
CorePotts.remake_frozen(::P60uStatic, prob, u) = prob.frozen
CorePotts.frozen_varies(::P60uStatic) = false
abstract type P60uStaticFamily end
struct P60uStaticMember <: P60uStaticFamily end
CorePotts.frozen_varies(::P60uStaticFamily) = false
CorePotts.remake_frozen(::P60uStaticMember, prob, u) = prob.frozen
struct P60uVaries end
CorePotts.remake_frozen(::P60uVaries, prob, u) = prob.frozen
CorePotts.frozen_varies(::P60uVaries) = true
# a custom `remake_frozen` with CorePotts' default `frozen_varies` (the warning's case)
struct P60uForgot end
CorePotts.remake_frozen(::P60uForgot, prob, u) = prob.frozen

"""A hand-written CorePotts problem (zero ΔH) with system `sys` and a static frozen row."""
function p60u_core_problem(sys)
    lat = CorePotts.Lattice((10, 10))
    st = CorePotts.initial_state(P60U_ONE, Int32[1])
    f = CorePotts.CPMFunction((st, p, prop, ctx) -> 0.0; temperature = (st, p, prop, ctx) -> 1.0, sys)
    fz = falses(10, 10)
    fz[1, :] .= true
    return CorePotts.PottsProblem(f, st, lat, (0, 2), (;); frozen = fz)
end

@testset "P6.0u 4: frozen_varies defined outside CorePotts silences init's warning" begin
    alg = CorePotts.SequentialCPM()
    W = Base.CoreLogging.Warn
    # targets: a deliberately static mask
    @test (@test_logs min_level = W CorePotts.init(p60u_core_problem(P60uStatic()), alg)) isa CorePotts.PottsIntegrator
    @test (@test_logs min_level = W CorePotts.init(p60u_core_problem(P60uStaticMember()), alg)) isa CorePotts.PottsIntegrator
    @test (@test_logs min_level = W CorePotts.solve(p60u_core_problem(P60uStatic()), alg)).retcode |> Symbol === :Success
    # the mask stays static (frozen_varies is false): row 1 never moves
    sol = CorePotts.solve(p60u_core_problem(P60uStatic()), alg)
    @test !CorePotts.frozen_varies(P60uStatic()) && sol.stats.refreshes == 0
    # controls: the warning still fires for CorePotts' default `frozen_varies`
    @test (@test_logs (:warn, r"frozen_varies") CorePotts.init(p60u_core_problem(P60uForgot()), alg)) isa CorePotts.PottsIntegrator
    @test (@test_logs (:warn, r"P60uForgot") CorePotts.init(p60u_core_problem(P60uForgot()), alg)) isa CorePotts.PottsIntegrator
    # controls: no warning for `frozen_varies = true`, no system, or a Potts model (frozen_kinds)
    @test (@test_logs min_level = W CorePotts.init(p60u_core_problem(P60uVaries()), alg)) isa CorePotts.PottsIntegrator
    @test (@test_logs min_level = W CorePotts.init(p60u_core_problem(nothing), alg)) isa CorePotts.PottsIntegrator
    @test (@test_logs min_level = W init(PottsProblem(P60uOuterOK(; name = :o), P60U_OP, (0, 1)), SequentialCPM())) isa
          CorePotts.PottsIntegrator
end

# ---------------------------------------------------------------------------------------
# 5. The temperature's `integral(Pre(x))` error says where

"""A model with a site variable `w` and the temperature `temp` (law `law`)."""
function p60u_temperature(temp; law = :Metropolis)
    ex = quote
        @potts_model P60uTemp begin
            @kinds medium A
            @variables w(site) = 1.0
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep $law(; temperature = $temp)
        end
        P60uTemp(; name = :tp)
    end
    return Base.invokelatest(eval, ex)
end

const P60U_INTEGRAL_PRE = "`integral(Pre(x))` is only available in update blocks"

@testset "P6.0u 5: the temperature's integral(Pre) error is located in @sweep" begin
    # targets
    for law in (:Metropolis, :Barker)
        @test p60u_rejection(() -> mtkcompile(p60u_temperature(:(1.0 + 0.01 * integral(Pre(w))); law)),
            P60U_INTEGRAL_PRE, "in @sweep") === :ok
    end
    # controls: `integral(w)` and a constant build and run
    @test p60u_builds(p60u_temperature(:(1.0 + 0.01 * integral(w))))
    @test p60u_builds(p60u_temperature(1.0; law = :Barker))
    # control: the equation form keeps its own location (unchanged)
    eqn = quote
        @potts_model P60uEqn begin
            @kinds medium A
            @variables w(site) = 1.0
            @variables s(cell) = 0.0
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @equations D(s) ~ integral(Pre(w)) - s
            @sweep Metropolis(; temperature = 1.0)
        end
        P60uEqn(; name = :eq)
    end
    @test p60u_rejection(() -> mtkcompile(Base.invokelatest(eval, eqn)), P60U_INTEGRAL_PRE, "in @equations") === :ok
end

# ---------------------------------------------------------------------------------------
# Unchanged pins: the fixtures this item touches build the same code

p60u_pinned() = (
    "continuous component" => () -> p60u_fingerprint(p60u_model(p60u_continuous(), :comp7)),
    "continuous component (model)" => () -> p60u_fingerprint(p60u_model(p60u_continuous(), :comp7; scope = :model)),
    "discrete component" => () -> p60u_fingerprint(p60u_model(p60u_discrete(), :net7)),
    "nested component" => () -> p60u_fingerprint(p60u_model(p60u_nested(), :comp7)),
    "guesses" => () -> p60u_fingerprint(p60u_model(p60u_continuous((y, z, k) -> (; guesses = [z => 0.0])), :comp7)),
    "extension of a hand-written base" => () -> p60u_fingerprint(P60uOuterOK(; name = :o)),
    "temperature integral(w)" => () -> p60u_fingerprint(p60u_temperature(:(1.0 + 0.01 * integral(w)))),
)

const P60U_FINGERPRINTS = Dict{String, UInt64}(
    "continuous component" => 0xd05b5078a727a931,
    "continuous component (model)" => 0x94d13acb0982ab1f,
    "discrete component" => 0x6f00d56711a7f58d,
    "nested component" => 0x827131fff6d3cb01,
    "guesses" => 0xd05b5078a727a931,
    "extension of a hand-written base" => 0x977c2dcc29ef21c7,
    "temperature integral(w)" => 0xf442642dcc5e4cb6,
)

@testset "P6.0u: fingerprints unchanged" begin
    fps = Dict(name => fp() for (name, fp) in p60u_pinned())
    for (name, _) in p60u_pinned()
        @test fps[name] == P60U_FINGERPRINTS[name]
        fps[name] == P60U_FINGERPRINTS[name] || @info "P6.0u: fingerprint $name = $(repr(fps[name]))"
    end
    @test fps["guesses"] == fps["continuous component"]
end
