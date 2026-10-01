# P6.0k2 (ROADMAP Phase 6, step 0; D-077 follow-ups, mtk-native-review §3 F7): what an
# `@components` MTK System carries but Potts cannot honour is rejected by name, `Pre` of a
# discrete node reads like the node inside a tick, and Bool reads lower without a double
# `_nonzero`. Frozen (AUTONOMY §7.3).
#
# F4 (the catch in `_compile_discrete` relabelling internal Potts errors) is not observable
# without internals in this environment (MTKBase only: the catch wraps MTKBase's own
# `mtkcompile`); it is left to non-frozen tests. Byte-identical code and fingerprints of the
# published models, and build time / first MCS, are the coordinator's merge check (base and
# merged tree side by side); here only same-session fingerprint equalities are asserted.
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables, @parameters
const P60K2_MTKB = Potts.ModelingToolkitBase

# `@potts_model` resolves a component's system in module scope, so the system under test is
# passed through a global slot; each model is built by `eval` of the macro (statements vary)
const P60K2_SYSTEM = Ref{Any}(nothing)

"""A one-kind model with component `comp = P60K2_SYSTEM[]` and the extra statements `stmts`."""
function p60k2_model(sys, comp::Symbol, stmts...; L = 10)
    P60K2_SYSTEM[] = sys
    ex = quote
        @potts_model P60k2Model begin
            @kinds medium A
            @components cells(A) $comp = P60K2_SYSTEM[]
            $(stmts...)
            @lattice Lattice(($L, $L))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        P60k2Model(; name = :p60k2)
    end
    return Base.invokelatest(eval, ex)
end

"""`:ok` if `f()` throws an `ArgumentError` whose message contains every one of `words`;
otherwise a description of what happened (shown by `@test` on failure)."""
function p60k2_rejection(f, words...)
    try
        f()
    catch e
        e isa ArgumentError || return "not an ArgumentError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        msg = sprint(showerror, e)
        all(w -> occursin(w, msg), words) || return "message does not name $(words): $(first(msg, 400))"
        return :ok
    end
    return "accepted silently"
end

const P60K2_ONE = (s = zeros(Int32, 10, 10); s[3:5, 3:5] .= 1; s)

"""Positive control: the model compiles, builds a problem and runs one MCS."""
function p60k2_builds(m)
    mtkcompile(m) isa CompiledPottsSystem || return false
    prob = PottsProblem(m, [ownership => P60K2_ONE, kind => [:A]], (0, 1))
    return Symbol(solve(prob, SequentialCPM(; proposal = Moore(1))).retcode) === :Success
end

p60k2_fingerprint(m, op, T = Float64) = PottsProblem(m, op, (0, 1); T).f.fingerprint

# ---------------------------------------------------------------------------------------
# F7: features of a component System that Potts would silently ignore

"""The continuous component `comp7`: `D(y) ~ -k y`, `D(z) ~ -z`, plus the keywords
`feature(y, z, k)` (the feature under test, built on the component's own variables)."""
function p60k2_continuous(feature = (y, z, k) -> (;))
    t = Potts.t
    @variables y(t) = 1.0 z(t) = 0.0
    @parameters k = 0.3
    return System([Potts.D(y) ~ -k * y, Potts.D(z) ~ -z], t; name = :comp7, feature(y, z, k)...)
end

"""The discrete component `net7` (a toggle and its lag), plus the keywords `feature(X, Y)`."""
function p60k2_discrete(feature = (X, Y) -> (;))
    t = Potts.t
    k = ShiftIndex(t, 0)
    @variables X(t)::Bool = false Y(t)::Bool = false
    return System([X(k) ~ !X(k - 1), Y(k) ~ X(k - 1)], t; name = :net7, feature(X, Y)...)
end

@testset "P6.0k2 F7: ignored component features are rejected by name" begin
    Pre = P60K2_MTKB.Pre
    # positive controls: the same components without the feature build and run
    @test p60k2_builds(p60k2_model(p60k2_continuous(), :comp7))
    @test p60k2_builds(p60k2_model(p60k2_discrete(), :net7))
    # `guesses` are ignored, as documented (MTK initialisation is not run): accepted, same code
    guessed = p60k2_continuous((y, z, k) -> (; guesses = [z => 0.0]))
    @test p60k2_builds(p60k2_model(guessed, :comp7))
    op = [ownership => P60K2_ONE, kind => [:A]]
    @test p60k2_fingerprint(p60k2_model(guessed, :comp7), op) == p60k2_fingerprint(p60k2_model(p60k2_continuous(), :comp7), op)

    rejected(sys, comp, word) = p60k2_rejection(() -> mtkcompile(p60k2_model(sys, comp)), String(comp), word)

    # initialization_eqs (the r8 reproducer: today `z ~ 5y` is dropped and comp7₊z starts at 0)
    @test rejected(p60k2_continuous((y, z, k) -> (; initialization_eqs = [z ~ 5y], guesses = [z => 0.0])),
        :comp7, r"initiali[sz]ation_eq") === :ok
    @test rejected(p60k2_discrete((X, Y) -> (; initialization_eqs = [Y ~ !X])), :net7, r"initiali[sz]ation_eq") === :ok
    # discrete_events
    @test rejected(p60k2_continuous((y, z, k) -> (; discrete_events = [[1.0] => [y ~ Pre(y) + 10.0]])),
        :comp7, "discrete_events") === :ok
    @test rejected(p60k2_discrete((X, Y) -> (; discrete_events = [[1.0] => [X ~ !Pre(X)]])), :net7, "discrete_events") === :ok
    # continuous_events
    @test rejected(p60k2_continuous((y, z, k) -> (; continuous_events = [[y ~ 0.5] => [y ~ 1.0]])),
        :comp7, "continuous_events") === :ok
    # jumps
    @test rejected(p60k2_continuous((y, z, k) -> (; jumps = [P60K2_MTKB.ConstantRateJump(k * y, [y ~ Pre(y) + 1.0])])),
        :comp7, r"jump") === :ok
end

@testset "P6.0k2 F7: bindings that touch a coupled parameter are rejected by name" begin
    t = Potts.t
    D = Potts.D
    couple = :(@equations comp7.k ~ volume / 90)
    rejected(sys) = p60k2_rejection(() -> mtkcompile(p60k2_model(sys, :comp7, couple)), "comp7", r"bind")
    builds(sys) = p60k2_builds(p60k2_model(sys, :comp7, couple))
    # positive control: the component with `k` coupled and no binding builds
    @test builds(p60k2_continuous())

    # an unknown's initial value bound to the coupled parameter (today: accepted at
    # mtkcompile; the binding is dropped)
    let
        @parameters k = 0.3
        @variables y(t) = 2k z(t) = 0.0
        @test rejected(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7)) === :ok
        @variables y(t) = 1.0                           # control: a plain initial value
        @test builds(System([D(y) ~ -k * y, D(z) ~ -z], t; name = :comp7))
    end
    # a parameter bound to an expression of the coupled parameter
    let
        @parameters k = 0.3
        @parameters k2 = 2k
        @variables y(t) = 1.0 z(t) = 0.0
        @test rejected(System([D(y) ~ -k2 * y, D(z) ~ -k * z], t; name = :comp7)) === :ok
        @test builds(System([D(y) ~ -2k * y, D(z) ~ -k * z], t; name = :comp7))   # control: inline
    end
    # the coupled parameter is itself bound
    let
        @parameters k0 = 0.1
        @parameters k = 2k0
        @variables y(t) = 1.0 z(t) = 0.0
        @test rejected(System([D(y) ~ -k * y, D(z) ~ -k0 * z], t; name = :comp7)) === :ok
        @parameters k = 0.3                             # control: unbound
        @test builds(System([D(y) ~ -k * y, D(z) ~ -k0 * z], t; name = :comp7))
    end
end

# ---------------------------------------------------------------------------------------
# F1: `Pre` of a discrete node, read inside a tick. Ticks are Jacobi (D-077): a coupling
# evaluated in a tick reads every node's pre-tick value, so there `Pre(x)` is `x`, and
# `Pre(x)[j]`, `Pre(x[j])` are `x[j]`. Fixture: the shift register of the Potts suite (a node
# copies its left neighbour's node each tick), as a Bool and as a Real node.

function p60k2_blocks(n, L)
    σ = zeros(Int32, L, L)
    for (c, (i, j)) in enumerate(Iterators.take(((i, j) for i in 1:4:(L - 3), j in 1:4:(L - 3)), n))
        σ[(i + 1):(i + 3), (j + 1):(j + 3)] .= c
    end
    return σ
end

"""The node component `xc`: a Bool node `X(k) ~ s` or a Real node `X(k) ~ w`."""
function p60k2_node(; real = false)
    t = Potts.t
    k = ShiftIndex(t, 0)
    if real
        @variables X(t) = 0.0
        @parameters w = 0.0
        return System([X(k) ~ w], t; name = :xc)
    end
    @variables X(t)::Bool = false
    @parameters s::Bool = false
    return System([X(k) ~ s], t; name = :xc)
end

const P60K2_OP = [ownership => p60k2_blocks(6, 16), kind => fill(1, 6)]
const P60K2_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))

p60k2_shift(real, coupling) = p60k2_model(p60k2_node(; real), :xc, :(@equations $coupling); L = 16)

"""Node values of cells 1–6 at t = 0…4 (as 0/1 integers; anything else is -1), per algorithm."""
function p60k2_ticks(m)
    bit(x) = x == 1 ? 1 : (x == 0 ? 0 : -1)
    prob = PottsProblem(m, P60K2_OP, (0, 4))
    return [[[bit(getproperty(u.cell, Symbol("xc₊X"))[c]) for c in 1:6] for u in solve(prob, alg; saveat = 0:4).u]
            for alg in P60K2_ALGS]
end

@testset "P6.0k2 F1: Pre of a discrete node inside a tick is the node" begin
    shift = [[Int(c <= m) for c in 1:6] for m in 0:4]          # cell c is on after c ticks
    toggle = [fill(isodd(m) ? 1 : 0, 6) for m in 0:4]          # every cell flips each tick
    @test shift != toggle
    for real in (false, true)
        # the plain reads (controls): pass on the current code
        left(x) = real ? :(ifelse(id > 1, $x, 1.0)) : :(ifelse(id > 1, $x > 0.5, true))
        par = real ? :(xc.w) : :(xc.s)
        flip(x) = real ? :(1.0 - $x) : :(!$x)
        plain_shift = :($par ~ $(left(:(xc.X[max(id - 1, 1)]))))
        plain_self = :($par ~ $(flip(:(xc.X))))
        @test all(==(shift), p60k2_ticks(p60k2_shift(real, plain_shift)))
        @test all(==(toggle), p60k2_ticks(p60k2_shift(real, plain_self)))
        fp_shift = p60k2_fingerprint(p60k2_shift(real, plain_shift), P60K2_OP)
        fp_self = p60k2_fingerprint(p60k2_shift(real, plain_self), P60K2_OP)
        @test fp_shift != fp_self                                # the fingerprint separates them
        # `Pre` forms: the same trajectories and the same code as the plain reads
        for (coupling, want, fp) in ((:($par ~ $(left(:(Pre(xc.X)[max(id - 1, 1)])))), shift, fp_shift),
                (:($par ~ $(left(:(Pre(xc.X[max(id - 1, 1)]))))), shift, fp_shift),
                (:($par ~ $(flip(:(Pre(xc.X))))), toggle, fp_self))
            @testset "$(real ? "Real" : "Bool") node: $coupling" begin
                m = p60k2_shift(real, coupling)
                @test all(==(want), p60k2_ticks(m))
                @test p60k2_fingerprint(m, P60K2_OP) == fp
            end
        end
    end
end

# ---------------------------------------------------------------------------------------
# F6: a Bool node read at an index lowers to one `_nonzero`, not `_nonzero(_nonzero(…))`

const P60K2_DOUBLE = r"_nonzero\)?\(\s*\(?\s*(?:Potts\.)?_nonzero\b"

@testset "P6.0k2 F6: no double _nonzero in generated code" begin
    # the pattern finds the defect as Julia prints it, and not a single coercion
    @test occursin(P60K2_DOUBLE, "(Potts._nonzero)(Potts._nonzero(Potts._cellval(st.cell.xc₊X, c)))")
    @test occursin(P60K2_DOUBLE, "Potts._nonzero(Potts._nonzero(x))")
    @test !occursin(P60K2_DOUBLE, "(!)((Potts._nonzero)(Potts._cellval(st.cell.xc₊X, c)))")
    for coupling in (:(xc.s ~ !xc.X[id]), :(xc.s ~ xc.X[id] & (volume > 1)),
            :(xc.s ~ ifelse(id > 1, xc.X[max(id - 1, 1)], true)))
        code = string(generated_code(p60k2_shift(false, coupling)))
        @test occursin("xc₊X", code)                             # the node is read
        @test count(_ -> true, eachmatch(P60K2_DOUBLE, code)) == 0     # (a count, not the code, on failure)
    end
end
