# follow-ups of D-078 (solver placement): canonical solver
# strings and reserved internal suffixes. Decision: D-130 (amends D-016/D-078, after D-123).
#
# The defects, measured on c0f80561:
#  b. `_canonical_value` (src/solvers.jl) prints a non-scalar value nested deeper than 8
#     levels by its type alone. `Adaptive(Rodas5P(); isoutofdomain = Guard(nest(12, 1.0)))`
#     and the same with 2.0 print the same canonical string, so they fingerprint alike (a
#     checkpoint loads across them) and, given to two ODE unknowns through `solvers`, share
#     one solver group: one `_AdaptiveODE` phase integrates both with the first solver and the
#     second is silently dropped. A self-referential value is cut the same way. At depth 3
#     the two differ (two phases, two fingerprints).
#  c. `_check_internal_suffix` (src/system.jl) rejects declared scalar variables and
#     parameters ending in `__ode`, `__tick` or `__next`, and, because components are bound
#     into a rebuilt `PottsSystem`, component unknowns (`comp₊x__ode`), discrete nodes
#     (`net₊X__tick`) and component parameters (`comp₊k__ode`) too. It misses the name of a
#     vector quantity (the `vector` option: `@variables v__ode(cell)[1:2]`,
#     `@parameters d__tick[1:2]`, `s__next(site)[1:2]`), `@observed` names (`n__ode`) and a
#     component's observed names (`comp₊w__ode`): all build and run today.
#  d. A closure or anonymous function in an `Adaptive` solver (a keyword such as
#     `isoutofdomain`, or a field of the algorithm such as `Rodas5P(step_limiter! = …)`)
#     prints in the canonical string by its compiler-generated type name
#     (`Main.var"#2#3"{Float64}(w=Float64:0.3)`), whose counter depends on what the session
#     lowered before. Two fresh processes running the same script get the same names, so
#     the same fingerprint, and a checkpoint loads from one into the other; a process whose
#     closure has another body at the same position gets the same name too, so two
#     different closures fingerprint alike across sessions and a checkpoint loads across
#     them (unsafe). The body is never hashed.
#
# Rule (D-130), pinned here:
#  B. A value nested deeper than the canonical printer's cap (8 levels), or a cyclic value,
#     is an `ArgumentError` when its canonical string is built, never a silent truncation.
#     For a solver, building the problem (`PottsProblem`, `remake`) throws and the message
#     names `Adaptive` and, for a keyword, the keyword. Values within the cap keep their
#     canonical strings (no pin moves).
#  C. Every name Potts declares is checked for the reserved suffixes: also the name of a
#     vector quantity, `@observed` names and component observed names. The `ArgumentError`
#     (when the model is built or compiled) names the quantity and the suffix. Names that
#     merely contain a suffix elsewhere are accepted.
#  D. An `Adaptive` solver whose canonical string contains a compiler-generated name
#     (`var"#`: an anonymous function, a closure, a local named function, a wrapper holding
#     one) is accepted (idiomatic SciML), as `ode_solver`, in `solvers` and in `remake`.
#     Its fingerprint also hashes a per-session token: within a session the same closure
#     (or one of the same type and captures) fingerprints alike and its checkpoints load,
#     and different closures fingerprint apart; across sessions the fingerprint always
#     differs, so a checkpoint never loads into another session (the fingerprint
#     `ArgumentError`) and cannot collide with another session's closure. Named functions,
#     callable structs and stable wrappers (`Returns(false)`) fingerprint as before and
#     load across sessions. (`combine` keeps its D-123 rejection.)
#  E. `tools/fingerprint_compare.jl` exists and parses (tooling: it compares fingerprints
#     of the published models and fixtures between two checkouts, e.g. a `git archive`
#     copy; not run here).
#  Unchanged pins: the fixtures recorded on c0f80561 and every PottsModels system (the
#  D-122/D-124 pins). The after-MCS phase order (item a) is documentation only.

@testsetup module CanonicalSolverStringsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex
using OrdinaryDiffEqRosenbrock: Rodas5P
using TOML: TOML
const solver_string_Adaptive = Potts.Adaptive
const solver_string_RK4 = Potts.RK4
const solver_string_EE = Potts.ExplicitEuler
# ---------------------------------------------------------------------------------------
# Fixtures. The solver definitions are one source string, evaluated here and in the
# subprocess (part D), so both sessions build exactly the same solvers.
const DEFS = raw"""
@potts_model SolverStringPair begin
    @kinds medium A
    @parameters k = 0.3
    @variables begin
        y(cell) = 1.0
        s(cell) = 2.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations begin
        D(y) ~ -k * y
        D(s) ~ -0.5 * s
    end
    @sweep Metropolis(; temperature = 1.0)
end
function solver_string_sigma()
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[7:9, 7:9] .= 2
    return σ
end
solver_string_op() = [ownership => solver_string_sigma(), kind => [:A, :A]]

ood(u, p, t) = false                            # a named function
struct SolverStringGuard{G}                                  # a callable struct (an `isoutofdomain`)
    inner::G
end
(g::SolverStringGuard)(u, p, t) = false
struct SolverStringLeaf
    w::Float64
end
struct SolverStringNest
    inner::Any
end
# a value nested `n` levels: Guard ∘ Nest^n ∘ Leaf(w)
solver_string_nest(n, w) = n == 0 ? SolverStringLeaf(w) : SolverStringNest(solver_string_nest(n - 1, w))

const STABLE = [
    "RK4()" => solver_string_RK4(),
    "Rodas5P()" => solver_string_Adaptive(Rodas5P()),
    "Rodas5P(reltol = 1e-6)" => solver_string_Adaptive(Rodas5P(); reltol = 1e-6),
    "Rodas5P(isoutofdomain = ood)" => solver_string_Adaptive(Rodas5P(); isoutofdomain = ood),
    "Rodas5P(isoutofdomain = Guard(0.3))" => solver_string_Adaptive(Rodas5P(); isoutofdomain = SolverStringGuard(0.3)),
    "Rodas5P(isoutofdomain = Guard(0.7))" => solver_string_Adaptive(Rodas5P(); isoutofdomain = SolverStringGuard(0.7)),
    "Rodas5P(isoutofdomain = Returns(false))" => solver_string_Adaptive(Rodas5P(); isoutofdomain = Returns(false)),
    "Rodas5P(isoutofdomain = Guard(nest(3, 1.0)))" => solver_string_Adaptive(Rodas5P(); isoutofdomain = SolverStringGuard(solver_string_nest(3, 1.0))),
    "Rodas5P(isoutofdomain = Guard(nest(3, 2.0)))" => solver_string_Adaptive(Rodas5P(); isoutofdomain = SolverStringGuard(solver_string_nest(3, 2.0))),
]
problem(solver; T = Float64) = PottsProblem(SolverStringPair(; name = :pair), solver_string_op(), (0, 6); T, seed = 1, ode_solver = solver)
stable_problem(label; T = Float64) = problem(Dict(STABLE)[label]; T)
"""
# The definitions are evaluated in `Main`, as the worker processes below evaluate them, so the
# fingerprints of the two agree (shared/main_definitions.jl).
include(joinpath(@__DIR__, "..", "shared", "main_definitions.jl"))
define_in_main(
    @__MODULE__, :SolverStringPair, quote
        using Potts, PottsModels, TOML
        using OrdinaryDiffEqRosenbrock: Rodas5P
        const solver_string_Adaptive = Potts.Adaptive
        const solver_string_RK4 = Potts.RK4
    end, DEFS, "canonical_solver_strings_definitions"
)
"""`:ok` if `f()` throws an `ArgumentError` whose message contains every one of `words`;
otherwise a description of what happened (shown by `@test` on failure)."""
function rejection(f, words...)
    try
        f()
    catch e
        e isa ArgumentError || return "not an ArgumentError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        isempty(words) || occursin(first(words), sprint(showerror, e)) || return "message does not name $(first(words))"
        return :ok
    end
    return "accepted silently"
end
adaptive_phases(prob) = count(ph -> ph isa Potts._AdaptiveODE, prob.f.phases.after_mcs)
solver_string_var(sys, n) = only(filter(x -> string(x) in (string(n), string(n, "(t)")), Potts.declared_variables(sys)))
"""The pair model with `y => a` and `s => b` through `solvers`."""
function solver_string_split(a, b)
    sys = SolverStringPair(; name = :pair)
    return PottsProblem(sys, solver_string_op(), (0, 6); seed = 1, solvers = [solver_string_var(sys, :y) => a, solver_string_var(sys, :s) => b])
end
# deep and cyclic values (B)
mutable struct SolverStringCycle
    next::Any
    w::Float64
end
solver_string_cycle(w) = (c = SolverStringCycle(nothing, w); c.next = c; c)
deep(w; n = 12) = SolverStringGuard(solver_string_nest(n, w))
const DEEP = [
    "isoutofdomain = Guard(nest(12, 1.0))" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = deep(1.0)), "isoutofdomain"),
    "isoutofdomain = Guard(nest(30, 1.0))" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = deep(1.0; n = 30)), "isoutofdomain"),
    "isoutofdomain = Guard(cycle(1.0))" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = SolverStringGuard(solver_string_cycle(1.0))), "isoutofdomain"),
    "Rodas5P(step_limiter! = Guard(nest(12, 1.0)))" => (() -> solver_string_Adaptive(Rodas5P(step_limiter! = deep(1.0))), nothing),
]
# compiler-generated names (D)
solver_string_mk(w) = (u, p, t) -> any(<(w), u)
function solver_string_local()
    inner(u, p, t) = false           # a local named function: a closure type `#inner#…`
    return inner
end
anon = (u, p, t) -> false
# a non-constant global bound to an anonymous function
const UNSTABLE = [
    "isoutofdomain = anonymous" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = (u, p, t) -> false), "isoutofdomain"),
    "isoutofdomain = global anonymous" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = anon), "isoutofdomain"),
    "isoutofdomain = closure solver_string_mk(0.3)" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = solver_string_mk(0.3)), "isoutofdomain"),
    "isoutofdomain = local named function" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = solver_string_local()), "isoutofdomain"),
    "isoutofdomain = Guard(anonymous)" => (() -> solver_string_Adaptive(Rodas5P(); isoutofdomain = SolverStringGuard((u, p, t) -> false)), "isoutofdomain"),
    "Rodas5P(step_limiter! = anonymous)" => (() -> solver_string_Adaptive(Rodas5P(step_limiter! = (u, i, p, t) -> nothing)), nothing),
    "Rodas5P(step_limiter! = closure)" => (
        () -> solver_string_Adaptive(
            Rodas5P(
                step_limiter! = let c = 0.0
                    (u, i, p, t) -> (u .= max.(u, c); nothing)
                end
            )
        ), nothing,
    ),
]
# a weight closure in a named relation (hashed by value, D-122/D-124): not a solver
@potts_model SolverStringWeighted begin
    @kinds medium A
    @relations far = Weighted(Moore(1), o -> 2.0)
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @energy contacts(far) => 1.0 * weight
    @sweep Metropolis(; temperature = 1.0)
end
# ---------------------------------------------------------------------------------------
# C. Reserved suffixes on every declared name
const SUFFIXES = ("__ode", "__tick", "__next")
"""A one-kind model with the extra statements `stmts`, built and compiled."""
function build(stmts...)
    ex = quote
        @potts_model Names begin
            @kinds medium A
            $(stmts...)
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0)
        end
        m = Names(; name = :names)
        mtkcompile(m)
        m
    end
    return Base.invokelatest(eval, ex)
end
function runs(m)
    return Symbol(
        solve(
            PottsProblem(m, [ownership => (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s), kind => [:A]], (0, 2)),
            SequentialCPM()
        ).retcode
    ) === :Success
end
# `@potts_model` resolves a component's system in module scope: a global slot
const SYSTEM = Ref{Any}(nothing)
function solver_string_component(sys, comp::Symbol)
    SYSTEM[] = sys
    return build(:(@components cells(A) $comp = SYSTEM[]))
end
function continuous(names...; observed = nothing)
    t = Potts.t
    xs = [only(Potts.ModelingToolkitBase.@variables $n(t) = 1.0) for n in names]
    eqs = [Potts.D(x) ~ -0.1 * x for x in xs]
    if observed !== nothing
        w = only(Potts.ModelingToolkitBase.@variables $observed(t))
        push!(eqs, w ~ 2 * xs[1])
    end
    return System(eqs, t; name = :comp)
end
# ---------------------------------------------------------------------------------------
# D. Compiler-generated names in a solver: accepted, fingerprint bound to the session
const CLOSURE = (u, p, t) -> false
const CLOSURE_OTHER = (u, p, t) -> any(isnan, u)
closure_problem(f = CLOSURE) = problem(solver_string_Adaptive(Rodas5P(); isoutofdomain = f))
"""Run the pair model with `isoutofdomain = <body>` in a fresh, unperturbed `julia`
process; it writes its fingerprint and a checkpoint after 2 MCS, and, given `other` (a
checkpoint path), whether that checkpoint is `refused` (ArgumentError) or `loaded`."""
function solver_string_session(dir, tag, body; other = nothing)
    outfile = joinpath(dir, "session $tag.toml")
    script = joinpath(dir, "session $tag.jl")
    ckpath = joinpath(dir, "session $tag.jls")
    write(
        script, """
        using Potts, PottsModels, TOML
        using OrdinaryDiffEqRosenbrock: Rodas5P
        const solver_string_Adaptive = Potts.Adaptive
        const solver_string_RK4 = Potts.RK4
        """ * DEFS * """
            const SESSION_CLOSURE = $body
            prob = problem(solver_string_Adaptive(Rodas5P(); isoutofdomain = SESSION_CLOSURE))
            r = Dict{String, Any}("fp" => repr(prob.f.fingerprint))
            integ = init(prob, SequentialCPM())
            step!(integ)
            step!(integ)
            save_checkpoint($(repr(ckpath)), checkpoint(integ))
            r["ck"] = $(repr(ckpath))
            other = $(repr(other))
            if other !== nothing
                r["other"] = try
                    init(prob, SequentialCPM(); checkpoint = load_checkpoint(other))
                    "loaded"
                catch e
                    e isa ArgumentError ? "refused" : "error: " * first(sprint(showerror, e), 200)
                end
            end
            open(io -> TOML.print(io, r), $(repr(outfile)), "w")
            """
    )
    run(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $script`)
    return TOML.parsefile(outfile)
end
"""Build the stable-solver fixtures in a fresh `julia` process (perturbed first) and return
their fingerprints and the paths of checkpoints written after 2 MCS."""
function solver_string_worker(dir)
    outfile = joinpath(dir, "out.toml")
    script = joinpath(dir, "worker.jl")
    write(
        script, """
        using Potts, PottsModels, TOML
        using OrdinaryDiffEqRosenbrock: Rodas5P
        const solver_string_Adaptive = Potts.Adaptive
        const solver_string_RK4 = Potts.RK4
        # perturb the session: compiler-generated names now start elsewhere
        for i in 1:9
            @eval noise = (x -> x + \$i)
        end
        struct NoiseType end
        module NoiseModule; f(a, b) = a; g = (a, b) -> b; end
        """ * DEFS * """
            r = Dict{String, Any}()
            for (label, _) in STABLE
                prob = stable_problem(label)
                r["fp " * label] = repr(prob.f.fingerprint)
                integ = init(prob, SequentialCPM())
                for _ in 1:2
                    step!(integ)
                end
                path = joinpath($(repr(dir)), "ck " * string(hash(label)) * ".jls")
                save_checkpoint(path, checkpoint(integ))
                r["ck " * label] = path
            end
            open(io -> TOML.print(io, r), $(repr(outfile)), "w")
            """
    )
    run(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $script`)
    return TOML.parsefile(outfile)
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "canonical solver strings: controls" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # Controls (pass on the base)
    @testset "canonical solver strings: controls" begin
        # every stable solver builds; equal specifications built afresh fingerprint alike
        for (label, _) in STABLE
            @test stable_problem(label).f.fingerprint == stable_problem(label).f.fingerprint
        end
        # stable solvers that differ fingerprint apart, pairwise
        fps = [label => stable_problem(label).f.fingerprint for (label, _) in STABLE]
        for i in eachindex(fps), j in (i + 1):lastindex(fps)
            @test fps[i].second != fps[j].second
        end
        # within the cap, nested values print in full: two solvers differing at depth 3 are two
        # groups (two phases) and two fingerprints
        a = STABLE[end - 1].second
        b = STABLE[end].second
        @test adaptive_phases(solver_string_split(a, b)) == 2
        @test adaptive_phases(solver_string_split(a, a)) == 1
        @test solver_string_split(a, b).f.fingerprint != solver_string_split(a, a).f.fingerprint
        # a callable struct and a named function run as `isoutofdomain`
        for label in ("Rodas5P(isoutofdomain = Guard(0.3))", "Rodas5P(isoutofdomain = ood)", "Rodas5P(isoutofdomain = Guard(nest(3, 1.0)))")
            sol = solve(stable_problem(label), SequentialCPM())
            @test Symbol(sol.retcode) === :Success
            @test sol.u[end].cell.y[1] ≈ exp(-0.3 * 6) rtol = 1.0e-2
        end
        # negative control: the `var"#` probe detects an anonymous function's printed type
        @test occursin("var\"#", sprint(show, typeof(anon)))
        @test occursin("var\"#", sprint(show, typeof(solver_string_mk(0.3))))
        @test !occursin("var\"#", sprint(show, typeof(ood)))
        # a weight closure in a named relation is not a solver: still accepted (D-122/D-124)
        @test Symbol(solve(PottsProblem(SolverStringWeighted(; name = :w), solver_string_op(), (0, 2)), SequentialCPM()).retcode) === :Success
    end
end

@testitem "canonical solver strings B: values beyond the canonical cap are an ArgumentError" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # B. A value deeper than the cap, or cyclic, is an error, not a truncation
    @testset "canonical solver strings B: values beyond the canonical cap are an ArgumentError" begin
        for (label, (mk, kw)) in DEEP
            words = kw === nothing ? ("Adaptive",) : ("Adaptive", kw)
            @testset "$label" begin
                @test rejection(() -> problem(mk()), words...) === :ok                       # ode_solver
                @test rejection(() -> solver_string_split(solver_string_RK4(), mk()), words...) === :ok            # solvers
                prob = problem(solver_string_RK4())
                @test rejection(() -> remake(prob; ode_solver = mk()), words...) === :ok           # remake
            end
        end
        # the reproducer: two solvers that differ only deep down no longer share a group (today
        # one phase integrates both with the first solver) and no longer fingerprint alike
        @test rejection(
            () -> solver_string_split(
                solver_string_Adaptive(Rodas5P(); isoutofdomain = deep(1.0)),
                solver_string_Adaptive(Rodas5P(); isoutofdomain = deep(2.0))
            ), "Adaptive"
        ) === :ok
        @test rejection(
            () -> problem(solver_string_Adaptive(Rodas5P(); isoutofdomain = SolverStringGuard(solver_string_cycle(2.0)))),
            "Adaptive"
        ) === :ok
    end
end

@testitem "canonical solver strings C: reserved suffixes on vector, observed and component observed names" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical solver strings C: reserved suffixes on vector, observed and component observed names" begin
        for suf in SUFFIXES
            @testset "$suf" begin
                v = Symbol(:v, suf)
                d = Symbol(:d, suf)
                n = Symbol(:n, suf)
                @test rejection(() -> build(:(@variables $v(cell)[1:2] = 0.0)), String(v), suf) === :ok
                @test rejection(() -> build(:(@parameters $d[1:2] = 1.0)), String(d), suf) === :ok
                @test rejection(() -> build(:(@observed $n ~ sum(volume for c in cells))), String(n), suf) === :ok
            end
        end
        @test rejection(() -> build(:(@variables s__next(site)[1:2] = 0.0)), "s__next", "__next") === :ok
        @test rejection(() -> build(:(@variables m__tick(model)[1:3] = 0.0)), "m__tick", "__tick") === :ok
        # a component's observed name `comp₊w__ode`
        @test rejection(() -> solver_string_component(continuous(:z; observed = :w__ode), :comp), "w__ode", "__ode") === :ok
    end
end

@testitem "canonical solver strings C: controls (regression guards and accepted names)" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical solver strings C: controls (regression guards and accepted names)" begin
        # rejected on the base: scalar variables and parameters, component unknowns, discrete
        # nodes and component parameters
        @test rejection(() -> build(:(@variables x__ode(cell) = 0.0)), "x__ode", "__ode") === :ok
        @test rejection(() -> build(:(@parameters q__next = 1.0)), "q__next", "__next") === :ok
        @test rejection(() -> solver_string_component(continuous(:x, :x__ode), :comp), "x__ode", "__ode") === :ok
        t = Potts.t
        k = ShiftIndex(t, 0)
        Xs = Potts.ModelingToolkitBase.@variables X(t)::Bool = false X__tick(t)::Bool = true
        net = System([Xs[1](k) ~ !Xs[1](k - 1), Xs[2](k) ~ Xs[1](k - 1)], t; name = :net)
        @test rejection(() -> solver_string_component(net, :net), "X__tick", "__tick") === :ok
        yk = only(Potts.ModelingToolkitBase.@variables yk(t) = 1.0)
        kk = only(Potts.ModelingToolkitBase.@parameters k__ode = 0.3)
        @test rejection(() -> solver_string_component(System([Potts.D(yk) ~ -kk * yk], t; name = :comp), :comp), "k__ode", "__ode") === :ok
        # accepted: a suffix that is not at the end, and the same quantities with other names
        @test runs(
            build(
                :(@variables v__oder(cell)[1:2] = 0.0), :(@parameters ode__d[1:2] = 1.0),
                :(@observed n_ode ~ sum(volume for c in cells)), :(@variables s__nexts(site)[1:2] = 0.0)
            )
        )
        @test runs(solver_string_component(continuous(:z; observed = :w), :comp))
        @test runs(solver_string_component(continuous(:x, :x_ode), :comp))
    end
end

@testitem "canonical solver strings D: an Adaptive solver with a compiler-generated name builds" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical solver strings D: an Adaptive solver with a compiler-generated name builds" begin
        for (label, (mk, _)) in UNSTABLE
            @testset "$label" begin
                @test problem(mk()) isa PottsProblem                                   # ode_solver
                @test solver_string_split(solver_string_RK4(), mk()) isa PottsProblem                        # solvers
                prob = problem(solver_string_RK4())
                @test remake(prob; ode_solver = mk()) isa PottsProblem                       # remake
                @test remake(prob; ode_solver = mk()).f.fingerprint != prob.f.fingerprint
            end
        end
    end
end

@testitem "canonical solver strings D: within a session, closures fingerprint by identity and checkpoints load" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical solver strings D: within a session, closures fingerprint by identity and checkpoints load" begin
        fp(f) = closure_problem(f).f.fingerprint
        # the same closure object, and closures of the same type with the same captures, alike
        @test fp(CLOSURE) == fp(CLOSURE)
        @test fp(solver_string_mk(-1.0)) == fp(solver_string_mk(-1.0))
        # different closures (another body, other captures) and the stable solver differ
        fps = [
            fp(CLOSURE), fp(CLOSURE_OTHER), fp(solver_string_mk(-1.0)), fp(solver_string_mk(-2.0)),
            stable_problem("Rodas5P()").f.fingerprint, stable_problem("Rodas5P(isoutofdomain = ood)").f.fingerprint,
        ]
        for i in eachindex(fps), j in (i + 1):lastindex(fps)
            @test fps[i] != fps[j]
        end
        # the closure runs, and its checkpoint loads in this session (in memory and on disk)
        prob = closure_problem()
        sol = solve(prob, SequentialCPM())
        @test Symbol(sol.retcode) === :Success
        @test sol.u[end].cell.y[1] ≈ exp(-0.3 * 6) rtol = 1.0e-2
        integ = init(prob, SequentialCPM())
        step!(integ)
        step!(integ)
        ck = checkpoint(integ)
        again = init(closure_problem(), SequentialCPM(); checkpoint = ck)
        @test again.t == 2 && again.u.ownership == ck.state.ownership
        mktempdir() do dir
            path = joinpath(dir, "closure.jls")
            save_checkpoint(path, ck)
            @test init(closure_problem(), SequentialCPM(); checkpoint = load_checkpoint(path)).t == 2
        end
        # negative controls: refused by another closure and by the stable solver
        @test_throws ArgumentError init(closure_problem(CLOSURE_OTHER), SequentialCPM(); checkpoint = ck)
        @test_throws ArgumentError init(stable_problem("Rodas5P()"), SequentialCPM(); checkpoint = ck)
    end
end

@testitem "canonical solver strings D: a closure's fingerprint is bound to its session" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical solver strings D: a closure's fingerprint is bound to its session" begin
        mktempdir() do dir
            a1 = solver_string_session(dir, "a1", "(u, p, t) -> false")
            a2 = solver_string_session(dir, "a2", "(u, p, t) -> false"; other = a1["ck"])           # same script
            b = solver_string_session(dir, "b", "(u, p, t) -> any(isnan, u)"; other = a1["ck"])     # another body
            # the same source in two sessions: different fingerprints, the checkpoint refused
            @test a1["fp"] != a2["fp"]
            @test a2["other"] == "refused"
            # another closure in another session never collides
            @test a1["fp"] != b["fp"]
            @test b["other"] == "refused"
            # nor loads here
            @test_throws ArgumentError init(closure_problem(), SequentialCPM(); checkpoint = load_checkpoint(a1["ck"]))
            # control: within its own session the checkpoint is a valid one of that problem
            @test load_checkpoint(a1["ck"]).fingerprint == parse(UInt64, a1["fp"])
        end
    end
end

@testitem "canonical solver strings D: stable solvers fingerprint alike in another process" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical solver strings D: stable solvers fingerprint alike in another process" begin
        mktempdir() do dir
            r = solver_string_worker(dir)
            for (label, _) in STABLE
                @testset "$label" begin
                    here = stable_problem(label)
                    @test here.f.fingerprint == parse(UInt64, r["fp " * label])
                    ck = load_checkpoint(r["ck " * label])
                    integ = init(here, SequentialCPM(); checkpoint = ck)
                    @test integ.t == 2
                    @test current_state(integ).ownership == ck.state.ownership
                end
            end
            # negative controls: another solver's fingerprint differs and its checkpoint is refused
            g3, g7 = "Rodas5P(isoutofdomain = Guard(0.3))", "Rodas5P(isoutofdomain = Guard(0.7))"
            @test parse(UInt64, r["fp " * g3]) != stable_problem(g7).f.fingerprint
            @test_throws ArgumentError init(stable_problem(g7), SequentialCPM(); checkpoint = load_checkpoint(r["ck " * g3]))
            @test_throws ArgumentError init(
                stable_problem("Rodas5P()"), SequentialCPM();
                checkpoint = load_checkpoint(r["ck Rodas5P(isoutofdomain = ood)"])
            )
        end
    end
end

@testitem "canonical solver strings E: tools/fingerprint_compare.jl exists and parses" setup = [CanonicalSolverStringsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # E. The fingerprint comparison tool
    @testset "canonical solver strings E: tools/fingerprint_compare.jl exists and parses" begin
        path = joinpath(@__DIR__, "..", "..", "..", "..", "tools", "fingerprint_compare.jl")
        @test isfile(path)
        if isfile(path)
            ex = Meta.parseall(read(path, String); filename = path)
            bad = Ref(false)
            walk(x) = x isa Expr && (x.head in (:error, :incomplete) ? (bad[] = true) : foreach(walk, x.args))
            walk(ex)
            @test !bad[]
        end
    end
end
