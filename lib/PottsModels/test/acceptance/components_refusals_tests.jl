# the remaining
# `@components` gaps and three review nits.
# Parameter bindings (user OK 2026-10-22; amends D-133): bindings of parameters build.
#
#  1. MTK `tstops` and `assertions` of a component System are rejected by name at
#     `mtkcompile`, like the F7 fields (D-084): today they are accepted and ignored.
#  2. A component binding of parameters builds (FE-18): `y(t) = 2k` and
#     `initial_conditions = [y => 2k]` give the initial value 2k, `k2 = 2k` is the computed
#     (read-only) parameter `comp7₊k2`, a discrete `s2 = !s` the computed `net7₊s2`. A binding
#     that reads an unknown (`y(t) = 2z`, a discrete `X(t) = !Y`) is rejected, naming the
#     component: `component \`comp7\` (the F7 form) or the location `@components cells comp7`
#     (the form discrete ticks already carry). Before FE-18 every one of these was rejected.
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

@testsetup module ComponentsRefusalsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, @variables, @parameters
const MTKB = Potts.ModelingToolkitBase
const SYSTEM = Ref{Any}(nothing)
const ONE = (s = zeros(Int32, 10, 10); s[3:5, 3:5] .= 1; s)
const REFUSAL_OP = [ownership => ONE, kind => [:A]]
"""A one-kind model with the component `comp = SYSTEM[]` in `scope` (`cells(A)` or
`model`) and the extra statements `stmts`."""
function refusal_model(sys, comp::Symbol, stmts...; scope = :(cells(A)))
    SYSTEM[] = sys
    decl = Expr(
        :macrocall, Symbol("@components"), LineNumberNode(@__LINE__, Symbol(@__FILE__)), scope,
        :($comp = SYSTEM[])
    )
    ex = quote
        @potts_model Model begin
            @kinds medium A
            $decl
            $(stmts...)
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        Model(; name = :components_gaps)
    end
    return Base.invokelatest(eval, ex)
end
"""`:ok` if `f()` throws an `ArgumentError` (possibly inside a `LoadError`) whose message
matches every one of `words` (strings or regexes); otherwise what happened."""
function rejection(f, words...)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        e isa Union{ArgumentError, Potts.PottsCompileError} || return "not an ArgumentError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        isempty(words) || occursin(first(words), sprint(showerror, e)) || return "message does not match $(first(words))"
        return :ok
    end
    return "accepted silently"
end
"""Positive control: the model compiles, builds a problem and runs one MCS."""
function refusal_builds(m, op = REFUSAL_OP)
    mtkcompile(m) isa CompiledPottsSystem || return false
    prob = PottsProblem(m, op, (0, 1))
    return Symbol(solve(prob, SequentialCPM(; proposal = Moore(1))).retcode) === :Success
end
"""Build, make the problem and run one MCS: the stage where a binding is rejected is free."""
full(m) = (mtkcompile(m); solve(PottsProblem(m, REFUSAL_OP, (0, 1)), SequentialCPM(; proposal = Moore(1))))
refusal_fingerprint(m, op = REFUSAL_OP) = PottsProblem(m, op, (0, 1)).f.fingerprint
"""A message names component `c`: the F7 form `component \`c\``, or the location
`@components cells c` / `@components model c` (as discrete ticks carry today)."""
refusal_names(c) = Regex("component `$c`|@components (?:cells|model)\\S* $c\\b")
# ---------------------------------------------------------------------------------------
# 1. MTK tstops and assertions
"""The continuous component `comp7`: `D(y) ~ -k y`, `D(z) ~ -z`, plus `feature(y, z, k)`."""
function refusal_continuous(feature = (y, z, k) -> (;))
    t = Potts.t
    @variables y(t) = 1.0 z(t) = 0.0
    @parameters k = 0.3
    return System([Potts.D(y) ~ -k * y, Potts.D(z) ~ -z], t; name = :comp7, feature(y, z, k)...)
end
"""The discrete component `net7`: a counter `C(k) ~ C(k-1) + 1`, plus `feature(C)`."""
function refusal_discrete(feature = C -> (;))
    t = Potts.t
    k = ShiftIndex(t, 0)
    @variables C(t) = 0.0
    return System([C(k) ~ C(k - 1) + 1], t; name = :net7, feature(C)...)
end
"""`comp7` holding a subsystem `inner` (`D(y) ~ -y`) that carries `feature(y)`."""
function refusal_nested(feature = y -> (;))
    t = Potts.t
    @variables y(t) = 1.0
    inner = System([Potts.D(y) ~ -y], t; name = :inner, feature(y)...)
    @variables z(t) = 0.0
    return System([Potts.D(z) ~ -z], t; name = :comp7, systems = [inner])
end
# ---------------------------------------------------------------------------------------
# 3. `x′` errors from inside a hand-written `@extend` base
@potts_model Inner begin
    @kinds medium A
    @variables qq(cell) = 1.0
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
"""A hand-written base that reads an unbound `qq′` (a bug inside the base)."""
HandBad(; name = :hand) = (qq′ + 1; Inner(; name))
"""A hand-written base that works."""
HandOK(; name = :hand) = Inner(; name)
@potts_model BadInner begin
    @kinds medium A
    @variables qq(cell) = 1.0
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9.0)^2 + qq′
    @sweep Metropolis(; temperature = 1.0)
end
# extensions of the bad hand-written base: the outer model declares `qq` as a cell variable,
# as a parameter, not at all, or an earlier base declares it
@potts_model OuterCell begin
    @extend base = HandBad()
    @variables qq(cell) = 2.0
end
@potts_model OuterParam begin
    @extend base = HandBad()
    @parameters qq = 2.0
end
@potts_model OuterNone begin
    @extend base = HandBad()
end
@potts_model OuterTwo begin
    @extend first = HandOK()
    @extend second = HandBad()
end
# controls
@potts_model OuterMacroBase begin              # a `@potts_model` base translates with its own description
    @extend base = BadInner()
    @parameters qq = 2.0
end
@potts_model OuterOwnPrime begin               # the outer model's own `g′`
    @extend base = HandOK()
    @variables g(cell) = 2.0
    @energy cells => 0.1 * g′ * volume
end
@potts_model OuterInherited begin              # `qq′` of `qq` bound from a hand-written base
    @extend qq = base = HandOK()
    @energy cells => 0.1 * qq′ * volume
end
@potts_model OuterOK begin
    @extend qq = base = HandOK()
    @energy cells => 0.1 * qq * volume
end
"""`:ok` if `f()` throws the `UndefVarError` of `var` (possibly in a `LoadError`); otherwise what happened."""
function refusal_undef(f, var::Symbol)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        e isa UndefVarError && e.var === var && return :ok
        return "not the UndefVarError of $var: $(typeof(e)): $(first(sprint(showerror, e), 400))"
    end
    return "accepted silently"
end
# ---------------------------------------------------------------------------------------
# 4. `init`'s `frozen_varies` warning

# a custom `remake_frozen` with `frozen_varies` defined outside CorePotts: false on purpose
# (a static mask), false through a supertype, true (the documented contract)
struct Static end
CorePotts.remake_frozen(::Static, prob, u) = prob.frozen
CorePotts.frozen_varies(::Static) = false
abstract type StaticFamily end
struct StaticMember <: StaticFamily end
CorePotts.frozen_varies(::StaticFamily) = false
CorePotts.remake_frozen(::StaticMember, prob, u) = prob.frozen
struct Varies end
CorePotts.remake_frozen(::Varies, prob, u) = prob.frozen
CorePotts.frozen_varies(::Varies) = true
# a custom `remake_frozen` with CorePotts' default `frozen_varies` (the warning's case)
struct Forgot end
CorePotts.remake_frozen(::Forgot, prob, u) = prob.frozen
"""A hand-written CorePotts problem (zero ΔH) with system `sys` and a static frozen row."""
function core_problem(sys)
    lat = CorePotts.Lattice((10, 10))
    st = CorePotts.initial_state(ONE, Int32[1])
    f = CorePotts.CPMFunction((st, p, prop, ctx) -> 0.0; temperature = (st, p, prop, ctx) -> 1.0, sys)
    fz = falses(10, 10)
    fz[1, :] .= true
    return CorePotts.PottsProblem(f, st, lat, (0, 2), (;); frozen = fz)
end
# ---------------------------------------------------------------------------------------
# 5. The temperature's `integral(Pre(x))` error says where
"""A model with a site variable `w` and the temperature `temp` (law `law`)."""
function refusal_temperature(temp; law = :Metropolis)
    ex = quote
        @potts_model Temp begin
            @kinds medium A
            @variables w(site) = 1.0
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep $law(; temperature = $temp)
        end
        Temp(; name = :tp)
    end
    return Base.invokelatest(eval, ex)
end
const INTEGRAL_PRE = "`integral(Pre(x))` is only available in update blocks"
# ---------------------------------------------------------------------------------------
# Unchanged pins: the fixtures this item touches build the same code
pinned() = (
    "continuous component" => () -> refusal_fingerprint(refusal_model(refusal_continuous(), :comp7)),
    "continuous component (model)" => () -> refusal_fingerprint(refusal_model(refusal_continuous(), :comp7; scope = :model)),
    "discrete component" => () -> refusal_fingerprint(refusal_model(refusal_discrete(), :net7)),
    "nested component" => () -> refusal_fingerprint(refusal_model(refusal_nested(), :comp7)),
    "guesses" => () -> refusal_fingerprint(refusal_model(refusal_continuous((y, z, k) -> (; guesses = [z => 0.0])), :comp7)),
    "extension of a hand-written base" => () -> refusal_fingerprint(OuterOK(; name = :o)),
    "temperature integral(w)" => () -> refusal_fingerprint(refusal_temperature(:(1.0 + 0.01 * integral(w)))),
)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "components refusals 1: MTK tstops and assertions are rejected by name" setup = [ComponentsRefusalsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "components refusals 1: MTK tstops and assertions are rejected by name" begin
        # positive controls: the same components without the feature build and run
        @test refusal_builds(refusal_model(refusal_continuous(), :comp7))
        @test refusal_builds(refusal_model(refusal_continuous(), :comp7; scope = :model))
        @test refusal_builds(refusal_model(refusal_discrete(), :net7))
        @test refusal_builds(refusal_model(refusal_nested(), :comp7))
        # empty tstops/assertions are no feature: accepted
        @test refusal_builds(refusal_model(refusal_continuous((y, z, k) -> (; tstops = Float64[])), :comp7))
        # `guesses` stay ignored (D-084)
        @test refusal_builds(refusal_model(refusal_continuous((y, z, k) -> (; guesses = [z => 0.0])), :comp7))
        # an F7 field is still rejected (unchanged)
        @test rejection(
            () -> mtkcompile(refusal_model(refusal_continuous((y, z, k) -> (; continuous_events = [[y ~ 0.5] => [y ~ 1.0]])), :comp7)),
            refusal_names("comp7"), "continuous_events"
        ) === :ok

        rejected(sys, comp, word; scope = :(cells(A))) =
            rejection(() -> mtkcompile(refusal_model(sys, comp; scope)), refusal_names(String(comp)), word)
        # tstops: today accepted, and the run never stops at t = 0.5
        @test rejected(refusal_continuous((y, z, k) -> (; tstops = [0.5])), :comp7, "tstops") === :ok
        @test rejected(refusal_continuous((y, z, k) -> (; tstops = [0.5])), :comp7, "tstops"; scope = :model) === :ok
        @test rejected(refusal_discrete(C -> (; tstops = [0.5])), :net7, "tstops") === :ok
        @test rejected(refusal_nested(y -> (; tstops = [0.5])), :comp7, "tstops") === :ok
        # assertions: today accepted, and never checked
        @test rejected(refusal_continuous((y, z, k) -> (; assertions = Dict(y > -1.0 => "y negative"))), :comp7, "assertions") === :ok
        @test rejected(
            refusal_continuous((y, z, k) -> (; assertions = Dict(y > -1.0 => "y negative"))), :comp7, "assertions";
            scope = :model
        ) === :ok
        @test rejected(refusal_discrete(C -> (; assertions = Dict(C >= 0 => "C negative"))), :net7, "assertions") === :ok
        @test rejected(refusal_nested(y -> (; assertions = Dict(y > -1.0 => "y negative"))), :comp7, "assertions") === :ok
    end
end

@testitem "components refusals 2: bindings of parameters build; bindings of unknowns are rejected, naming the component" setup = [ComponentsRefusalsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Binding rejections name the component
    @testset "components refusals 2: bindings of parameters build; bindings of unknowns are rejected, naming the component ($scope)" for scope in (:(cells(A)), :model)
        t = Potts.t
        D = Potts.D
        rejected(sys, comp, words...) = rejection(
            () -> full(refusal_model(sys, comp; scope)),
            refusal_names(String(comp)), words...
        )
        builds(sys, comp) = refusal_builds(refusal_model(sys, comp; scope))
        problem(sys, comp) = (m = refusal_model(sys, comp; scope); mtkcompile(m); PottsProblem(m, REFUSAL_OP, (0, 1)))
        first_value(prob, name) = first(vcat(Potts.observe(prob, name)))
        # positive controls: plain values, and plain values given as MTK initial conditions
        let
            @parameters k = 0.3
            @variables y(t) = 1.0 z(t) = 0.0
            @test builds(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7), :comp7)
            @variables y(t)
            @test builds(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7, initial_conditions = [y => 2.0]), :comp7)
        end
        # a variable's value bound to a parameter: its initial value 2k = 0.6 (FE-18; before:
        # rejected, "… `comp7₊y` has no initial value")
        let
            @parameters k = 0.3
            @variables y(t) = 2k z(t) = 0.0
            sys = System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7)
            @test builds(sys, :comp7)
            @test first_value(problem(sys, :comp7), :comp7₊y) ≈ 0.6
        end
        # the same binding as an MTK initial condition (before: "`2k` does not reduce …")
        let
            @parameters k = 0.3
            @variables y(t) z(t) = 0.0
            sys = System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7, initial_conditions = [y => 2k])
            @test builds(sys, :comp7)
            @test first_value(problem(sys, :comp7), :comp7₊y) ≈ 0.6
        end
        # a parameter bound to another: the computed, read-only `comp7₊k2 = 0.6` (before: "unknown
        # symbol `k2` in …")
        let
            @parameters k = 0.3
            @parameters k2 = 2k
            @variables y(t) = 1.0 z(t) = 0.0
            sys = System([D(y) ~ -k2 * y, D(z) ~ -k * z], t; name = :comp7)
            @test builds(sys, :comp7)
            prob = problem(sys, :comp7)
            @test getp(prob, :comp7₊k2)(prob) ≈ 0.6
            @test rejection(() -> remake(prob; p = [:comp7₊k2 => 1.0]), "comp7₊k2") === :ok
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
        # discrete: a parameter bound to another: the computed `net7₊s2 = !s = true` (before:
        # rejected, named by its tick location)
        let kk = ShiftIndex(t, 0)
            @parameters s::Bool = false
            @parameters s2::Bool = !s
            @variables X(t)::Bool = false
            sys = System([X(kk) ~ s2], t; name = :net7)
            @test builds(sys, :net7)
            prob = problem(sys, :net7)
            @test getp(prob, :net7₊s2)(prob) == true
        end
    end
end

@testitem "components refusals 2: a Potts parameter without a value is not blamed on a component" setup = [ComponentsRefusalsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "components refusals 2: a Potts parameter without a value is not blamed on a component" begin
        # negative control: the model's own parameter, next to a valid component
        m = refusal_model(refusal_continuous(), :comp7, :(@parameters q), :(@energy cells => q * volume))
        @test rejection(() -> full(m), "`q`", "no default") === :ok
        @test rejection(() -> full(m), r"^(?!.*component)"s) === :ok
    end
end

@testitem "components refusals 3: an `x′` error inside a hand-written @extend base is not relabelled" setup = [ComponentsRefusalsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "components refusals 3: an `x′` error inside a hand-written @extend base is not relabelled" begin
        qq′ = Symbol("qq′")
        # targets: the base's own error, whatever the outer model or an earlier base calls `qq`
        @test refusal_undef(() -> OuterCell(; name = :o), qq′) === :ok
        @test refusal_undef(() -> OuterParam(; name = :o), qq′) === :ok
        @test refusal_undef(() -> OuterTwo(; name = :o), qq′) === :ok
        # control: with nothing named `qq` outside the base it is already unchanged
        @test refusal_undef(() -> OuterNone(; name = :o), qq′) === :ok
        @test refusal_undef(() -> HandBad(), qq′) === :ok
        # controls: a `@potts_model` base's own description (a cell variable, not the outer parameter)
        @test rejection(
            () -> OuterMacroBase(; name = :o), "`qq′`", "primes exist only for site/field variables",
            "`qq` is a cell variable"
        ) === :ok
        # controls: the extension's own primes are still translated, after a hand-written base
        @test rejection(
            () -> OuterOwnPrime(; name = :o), "`g′`", "primes exist only for site/field variables",
            "`g` is a cell variable"
        ) === :ok
        @test rejection(
            () -> OuterInherited(; name = :o), "`qq′`", "primes exist only for site/field variables",
            "`qq` is a cell variable"
        ) === :ok
        # control: a valid extension of a hand-written base builds and runs
        @test refusal_builds(OuterOK(; name = :o))
    end
end

@testitem "components refusals 4: frozen_varies defined outside CorePotts silences init's warning" setup = [ComponentsRefusalsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "components refusals 4: frozen_varies defined outside CorePotts silences init's warning" begin
        alg = CorePotts.SequentialCPM()
        W = Base.CoreLogging.Warn
        function warn_logs(f)
            logger = Test.TestLogger(; min_level = W)
            val = Base.CoreLogging.with_logger(f, logger)
            return val, logger.logs
        end
        # targets: a deliberately static mask (order-independent: check specifically for frozen_varies
        # in an isolated TestLogger so unrelated once-per-session warnings cannot cause order dependence)
        for sys in (Static(), StaticMember())
            integ, logs = warn_logs(() -> CorePotts.init(core_problem(sys), alg))
            @test integ isa CorePotts.PottsIntegrator
            @test !any(r -> occursin("frozen_varies", string(r.message)), logs)
        end
        sol, logs = warn_logs(() -> CorePotts.solve(core_problem(Static()), alg))
        @test Symbol(sol.retcode) === :Success
        @test !any(r -> occursin("frozen_varies", string(r.message)), logs)
        # the mask stays static (frozen_varies is false): row 1 never moves
        @test !CorePotts.frozen_varies(Static()) && sol.stats.refreshes == 0
        # controls: the warning still fires for CorePotts' default `frozen_varies`
        integ_f, logs_f = warn_logs(() -> CorePotts.init(core_problem(Forgot()), alg))
        @test integ_f isa CorePotts.PottsIntegrator
        @test any(r -> r.level == W && occursin("frozen_varies", string(r.message)) && occursin("Forgot", string(r.message)), logs_f)
        # controls: no frozen_varies warning for `frozen_varies = true`, no system, or a Potts model (frozen_kinds)
        for prob in (
                core_problem(Varies()), core_problem(nothing),
                PottsProblem(OuterOK(; name = :o), REFUSAL_OP, (0, 1)),
            )
            integ_c, logs_c = warn_logs(() -> init(prob, alg))
            @test integ_c isa CorePotts.PottsIntegrator
            @test !any(r -> occursin("frozen_varies", string(r.message)), logs_c)
        end
    end
end

@testitem "components refusals 5: the temperature's integral(Pre) error is located in @sweep" setup = [ComponentsRefusalsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "components refusals 5: the temperature's integral(Pre) error is located in @sweep" begin
        # targets
        for law in (:Metropolis, :Barker)
            @test rejection(
                () -> mtkcompile(refusal_temperature(:(1.0 + 0.01 * integral(Pre(w))); law)),
                INTEGRAL_PRE, "in @sweep"
            ) === :ok
        end
        # controls: `integral(w)` and a constant build and run
        @test refusal_builds(refusal_temperature(:(1.0 + 0.01 * integral(w))))
        @test refusal_builds(refusal_temperature(1.0; law = :Barker))
        # control: the equation form keeps its own location (unchanged)
        eqn = quote
            @potts_model Eqn begin
                @kinds medium A
                @variables w(site) = 1.0
                @variables s(cell) = 0.0
                @lattice Lattice((10, 10))
                @energy cells => (volume - 9.0)^2
                @equations D(s) ~ integral(Pre(w)) - s
                @sweep Metropolis(; temperature = 1.0)
            end
            Eqn(; name = :eq)
        end
        @test rejection(() -> mtkcompile(Base.invokelatest(eval, eqn)), INTEGRAL_PRE, "in @equations") === :ok
    end
end

@testitem "components refusals: a guess does not move the fingerprint" setup = [ComponentsRefusalsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "components refusals: a guess does not move the fingerprint" begin
        fps = Dict(name => fp() for (name, fp) in pinned())
        @test fps["guesses"] == fps["continuous component"]
    end
end
