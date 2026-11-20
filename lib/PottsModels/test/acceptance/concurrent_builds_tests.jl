# concurrent model builds are deterministic (D-109).
# A model constructor numbers its bound variables (gather `n_k`, population folds `c_k`/`s_k`)
# and its draws (`rand()` → `random_uniform(k)`) from one counter. Today that counter is a
# global `Ref` (`Potts._GATHER_COUNT`), reset by every non-nested build and incremented without
# atomics, so two builds that overlap (on two threads, or two tasks on one thread that yield
# while building) share and reset each other's numbering: their bound variables get other
# names than in a serial build, and one model can get the same name twice. The lattice
# dimension read by `centroid()` (`Potts._DIM`, reset by every build) and the `@extend`
# nesting depth (`Potts._NESTING`) are global build state of the same kind; the accept line
# ("the same generated code and fingerprints as built serially") covers them too, and
# `YieldCentroid` exercises `_DIM`.
#
# How the overlap is produced:
#  - tasks (`Threads.@spawn`): the fixtures `Yield*` call `yield()` between their
#    sections (as any helper that reads a file or logs may do), so builds running as tasks
#    interleave at those points even on one thread. This part is deterministic and meaningful
#    under any thread count, including the default `julia` (1 thread).
#  - threads (`Threads.@threads`): reference models and fixtures without `yield()` built on
#    several threads at once; meaningful only with `julia -t 4` (the item's accept line). With
#    one thread this part builds serially and passes trivially (noted by an @info, not skipped).
# Each build's system is then checked in the main task, serially, against a serial build of
# the same constructor: the text of every `Potts.generated_code` expression (line numbers
# stripped), the problem fingerprint, and that no bound-variable name stands for two
# different folds within the model.
#
# Measured on the code before the change (feat/p6-0aj at 2f54c1e9, Julia 1.12.6; this file run
# alone):
#   - `julia` (1 thread): items 1, 3 and 4 pass; item 2 fails in every round: 12 of 20 task
#     builds differ (every `Yield`, `YieldCentroid` and `ConcurrentBase` build; the ones
#     without `yield()` run to completion one at a time and match), e.g. `ConcurrentBase` gets
#     `[c_36, n_35]` instead of `[c_3, n_2]`, with another fingerprint;
#   - `julia -t 4` (3 runs): items 1 and 4 pass; item 2 fails in every round (20 of 20 task
#     builds differ) and item 3 in every round (16 to 21 of 32 threaded builds differ: every
#     model with bound variables or draws, WortelAct, WortelAct connected, AkeebInvasion and
#     the fixtures; GranerGlazier and MerksVasculogenesis, which have none, never differ);
#     names reused within one model occur in every run (e.g. two folds bound by `c_2`), and
#     `YieldCentroid` builds throw "`centroid()` … need the model's @lattice declared
#     before them" (another build reset `Potts._DIM` in between) 2 to 5 times per run.
#
# Pinned here:
#  1. Preconditions (negative controls): a serial build of every fixture is reproducible
#     (two serial builds agree), every bound name in it is used by one fold only, the
#     fixtures do have bound variables and draws, and the task fixtures do yield.
#  2. Builds as tasks: 4 rounds of 20 builds (4 copies each of `Yield`,
#     `YieldCentroid`, `ConcurrentBase`, `Plain` and WortelAct, all spawned before any is
#     fetched) give the serial code, fingerprint and bound names, with no name reused within
#     a model and no build error.
#  3. Builds on threads: 4 rounds of `Threads.@threads` over 32 builds (4 copies each of
#     WortelAct, WortelAct connected, AkeebInvasion, GranerGlazier, MerksVasculogenesis,
#     `Plain`, `Yield`, `YieldCentroid`) give the same as item 2.
#  4. A nested `@extend` base still continues the outer model's numbering (a merged model
#     has no collisions) when built as a task alongside others.

@testsetup module ConcurrentBuildsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: Symbolics, SymbolicUtils
# ---------------------------------------------------------------------------------------
# Fixtures (12×8 lattice, two 4×4 cells)
@potts_model ConcurrentBase begin
    @kinds medium A
    @variables rb(cell) = 0.0 hb(cell) = 0.0
    @lattice Lattice((12, 8))
    yield()
    @after_mcs rb ~ rand()
    yield()
    @equations D(hb) ~ 0.01 * sum(volume[owner[n]] for n in Moore(1)(42)) + 0.001 * sum(hb[c] for c in cells) - 0.1hb
    @sweep Metropolis(; temperature = 1.0)
end
# Gathers, population folds over cells and sites, draws and a nested base, with `yield()`
# between the sections that create bound variables.
@potts_model Yield begin
    @kinds medium A
    @variables y(cell) = 0.0 z(cell) = 1.0 r(cell) = 0.0 g(model) = 0.5
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    yield()
    @equations begin
        D(y) ~ 0.01 * sum(z[c] for c in cells) + 0.02 * sum(volume[owner[n]] for n in Moore(1)(42)) - 0.1y
        D(z) ~ 0.02 * mean(z[c] for c in cells) + 0.01 * sum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - 0.1z
    end
    yield()
    @after_mcs r ~ rand()
    yield()
    @extend base = ConcurrentBase()
    yield()
    @after_mcs g ~ 0.01 * sum(volume[c] for c in cells) + 0.3 * g + 0.001 * sum(1.0 for s in sites) +
        0.01 * maximum(y[c] for c in cells)
    yield()
    @drive copy => 0.1 * (sum(volume[owner[n]] for n in Moore(1)(source)) - sum(volume[owner[n]] for n in Moore(1)(target)))
    @sweep Metropolis(; temperature = 1.0)
end
# The same model without `yield()` (for the threads part).
@potts_model Plain begin
    @kinds medium A
    @variables y(cell) = 0.0 z(cell) = 1.0 r(cell) = 0.0 g(model) = 0.5
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ 0.01 * sum(z[c] for c in cells) + 0.02 * sum(volume[owner[n]] for n in Moore(1)(42)) - 0.1y
        D(z) ~ 0.02 * mean(z[c] for c in cells) + 0.01 * sum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - 0.1z
    end
    @after_mcs r ~ rand()
    @after_mcs g ~ 0.01 * sum(volume[c] for c in cells) + 0.3 * g + 0.001 * sum(1.0 for s in sites) +
        0.01 * maximum(y[c] for c in cells)
    @drive copy => 0.1 * (sum(volume[owner[n]] for n in Moore(1)(source)) - sum(volume[owner[n]] for n in Moore(1)(target)))
    @sweep Metropolis(; temperature = 1.0)
end
# `centroid()` reads the lattice dimension declared earlier in the same build.
@potts_model YieldCentroid begin
    @kinds medium A
    @variables pos(cell)[1:2] = 0.0 w(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    yield()
    @after_mcs w ~ rand() + 0.01 * sum(volume[owner[n]] for n in Moore(1)(42))
    yield()
    @after_mcs pos ~ centroid()
    @sweep Metropolis(; temperature = 1.0)
end
function sigma()
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return s
end
two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
const FIXTURE_OP = Any[ownership => sigma(), kind => [:A, :A]]
const CONCURRENT_GG = graner_glazier_state()
const AKEEB = akeeb_state(; lattice = (99, 60))
# label => (constructor, initial state, problem keywords)
const CASES = Dict{String, Tuple{Any, Any, NamedTuple}}(
    "Yield" => (() -> Yield(; name = :x), FIXTURE_OP, (;)),
    "YieldCentroid" => (() -> YieldCentroid(; name = :x), FIXTURE_OP, (;)),
    "ConcurrentBase" => (() -> ConcurrentBase(; name = :x), FIXTURE_OP, (;)),
    "Plain" => (() -> Plain(; name = :x), FIXTURE_OP, (;)),
    "WortelAct" => (
        () -> WortelAct(; name = :act, lattice = (8, 8)),
        Any[ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (;),
    ),
    "WortelAct connected" => (
        () -> WortelAct(; name = :act, lattice = (8, 8), connected = true),
        Any[ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (;),
    ),
    "AkeebInvasion" => (() -> AkeebInvasion(; name = :akeeb, lattice = (99, 60)), AKEEB, (; capacity = 1000)),
    "GranerGlazier" => (() -> GranerGlazier(; name = :gg), Any[ownership => CONCURRENT_GG[1], kind => CONCURRENT_GG[2]], (;)),
    "MerksVasculogenesis" => (
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        Any[ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]],
        (; field_solver = Potts.ExplicitEuler(substeps = 2, lower_bound = 0.0)),
    ),
)
const TASK_LABELS = ("Yield", "YieldCentroid", "ConcurrentBase", "Plain", "WortelAct")
const THREAD_LABELS = (
    "WortelAct", "WortelAct connected", "AkeebInvasion", "GranerGlazier",
    "MerksVasculogenesis", "Plain", "Yield", "YieldCentroid",
)
const ROUNDS = 4
const COPIES = 4
# ---------------------------------------------------------------------------------------
# What is compared

# Line numbers out, including those of macro calls (`@inbounds` records the source path).
function strip_lines!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing)
    foreach(strip_lines!, ex.args)
    return ex
end
# Every expression of `generated_code` as text (phases numbered).
function concurrent_code(sys, kw)
    g = Potts.generated_code(sys; (haskey(kw, :field_solver) ? (; field_solver = kw.field_solver) : (;))...)
    out = String[]
    for k in propertynames(g)
        v = getproperty(g, k)
        for (i, x) in enumerate(v isa AbstractVector ? v : [v])
            push!(out, "$k[$i] :: " * string(strip_lines!(deepcopy(x))))
        end
    end
    return out
end
# Every gather / population fold of the system, by its bound variable: name => distinct folds.
function binders(sys)
    out = Dict{String, Set{String}}()
    seen = Base.IdSet{Any}()
    function walk(x)
        x isa Symbolics.Num && return walk(Symbolics.unwrap(x))     # (a `Num` is a `Number`)
        x isa Union{Symbol, Number, AbstractString, Nothing, Function, Type, LineNumberNode} && return
        if x isa SymbolicUtils.BasicSymbolic
            SymbolicUtils.iscall(x) || return
            if SymbolicUtils.operation(x) in (Potts.gather, Potts.population)
                n = string(first(SymbolicUtils.arguments(x)))
                push!(get!(Set{String}, out, n), string(x))
            end
            foreach(walk, SymbolicUtils.arguments(x))
            return
        end
        ismutable(x) && (x in seen && return; push!(seen, x))
        if x isa Symbolics.Equation
            walk(x.lhs); walk(x.rhs)
        elseif x isa AbstractDict
            foreach(walk, values(x))
        elseif x isa Union{AbstractArray, Tuple, NamedTuple}
            foreach(walk, x)
        elseif x isa Pair
            walk(x.first); walk(x.second)
        elseif parentmodule(typeof(x)) in (Potts, Potts.CorePotts)
            for f in fieldnames(typeof(x))
                isdefined(x, f) && walk(getfield(x, f))
            end
        end
    end
    if sys isa Potts.PottsSystem
        for f in (:energies, :drives, :constraints, :updates, :equations, :divisions, :link_rules, :observed, :variables, :relations)
            walk(getfield(getfield(sys, :part), f))   # the Potts payload (D-256)
        end
    else
        walk(sys)
    end
    return out
end
concurrent_reused(sys) = sort!([n for (n, s) in binders(sys) if length(s) > 1])
"""Code, fingerprint, bound names and reused names of a built system (or the error it threw)."""
function signature(label, sys)
    sys isa Exception && return (;
        code = ["error: " * sprint(showerror, sys)], fingerprint = UInt64(0), names = String[],
        reused = String[],
    )
    _, op, kw = CASES[label]
    prob = PottsProblem(sys, op, (0, 1); kw...)
    b = binders(sys)
    return (;
        code = concurrent_code(sys, kw), fingerprint = prob.f.fingerprint, names = sort!(collect(keys(b))),
        reused = sort!([n for (n, s) in b if length(s) > 1]),
    )
end
function concurrent_build(label)
    return try
        CASES[label][1]()
    catch e
        e
    end
end
const SERIAL = Dict(l => signature(l, concurrent_build(l)) for l in keys(CASES))
"""Compare the systems `built` (label => system) with the serial builds; return the failures."""
function check(built, how)
    bad = String[]
    for (label, sys) in built
        s = signature(label, sys)
        ref = SERIAL[label]
        why = String[]
        s.code == ref.code || push!(
            why, "code differs (" * join([first(split(a, " :: ")) for (a, r) in zip(s.code, ref.code) if a != r], ", ") *
                (length(s.code) == length(ref.code) ? "" : "; $(length(s.code)) vs $(length(ref.code)) expressions") * ")"
        )
        s.fingerprint == ref.fingerprint || push!(why, "fingerprint $(repr(s.fingerprint)) ≠ $(repr(ref.fingerprint))")
        s.names == ref.names || push!(why, "bound names $(s.names) ≠ $(ref.names)")
        isempty(s.reused) || push!(why, "names reused within the model: $(s.reused)")
        any(startswith("error: "), s.code) && push!(why, first(s.code))
        isempty(why) || push!(bad, "$how $label: " * join(why, "; "))
    end
    return bad
end
# ---------------------------------------------------------------------------------------
# 3. Builds on threads (meaningful with `julia -t 4`)
Threads.nthreads() < 4 && @info "concurrent builds: running with $(Threads.nthreads()) thread(s); the threads part " *
    "(item 3) is meaningful under `julia -t 4`"
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "concurrent builds: serial builds are reproducible and well named" setup = [ConcurrentBuildsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Preconditions
    @testset "concurrent builds: serial builds are reproducible and well named ($label)" for label in sort!(collect(keys(CASES)))
        ref = SERIAL[label]
        @test !any(startswith("error: "), ref.code)
        @test isempty(ref.reused)
        @test isempty(check([label => concurrent_build(label)], "serial"))
    end
end

@testitem "concurrent builds: the fixtures have bound variables, draws and yields (negative controls)" setup = [ConcurrentBuildsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "concurrent builds: the fixtures have bound variables, draws and yields (negative controls)" begin
        for label in ("Yield", "Plain", "ConcurrentBase", "WortelAct", "WortelAct connected", "YieldCentroid")
            @test !isempty(SERIAL[label].names)
        end
        @test length(SERIAL["Yield"].names) > length(SERIAL["Plain"].names)   # + the base's
        @test any(c -> occursin("CorePotts.draw(", c), SERIAL["AkeebInvasion"].code)   # `rand()` (a numbered draw)
        @test isempty(SERIAL["GranerGlazier"].names)
        # the yielding fixtures do yield: a build in a task lets another task run
        ran = Ref(false)
        t = Threads.@spawn (ran[] = true)
        Threads.nthreads() == 1 && (Yield(; name = :x); @test ran[])
        wait(t)
        # the walker sees a reuse when there is one: two folds with the same bound variable
        Symbolics.@variables c₀ a₀ b₀
        @test concurrent_reused([Potts.population(c₀, a₀, true) + Potts.population(c₀, b₀, true)]) == ["c₀"]
        @test concurrent_reused([Potts.population(c₀, a₀, true) + Potts.population(b₀, b₀, true)]) == String[]
    end
end

@testitem "concurrent builds: models built as concurrent tasks match the serial build (round)" setup = [ConcurrentBuildsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Builds as tasks (meaningful on any number of threads)
    @testset "concurrent builds: models built as concurrent tasks match the serial build (round $round)" for round in 1:ROUNDS
        labels = [l for l in TASK_LABELS for _ in 1:COPIES]
        tasks = [Threads.@spawn concurrent_build(l) for l in labels]   # all started before any is fetched
        built = [l => fetch(t) for (l, t) in zip(labels, tasks)]
        @test length(built) >= 16
        bad = check(built, "task")
        @test isempty(bad)
        isempty(bad) || @info "concurrent builds: $(length(bad)) of $(length(built)) task builds differ from the serial build (round $round)" bad[1:min(end, 6)]
    end
end

@testitem "concurrent builds: models built on threads match the serial build (round)" setup = [ConcurrentBuildsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "concurrent builds: models built on $(Threads.nthreads()) threads match the serial build (round $round)" for round in 1:ROUNDS
        labels = [l for _ in 1:COPIES for l in THREAD_LABELS]
        built = Vector{Any}(undef, length(labels))
        Threads.@threads :dynamic for i in eachindex(labels)
            built[i] = labels[i] => concurrent_build(labels[i])
        end
        @test length(built) >= 16
        bad = check(built, "thread")
        @test isempty(bad)
        isempty(bad) || @info "concurrent builds: $(length(bad)) of $(length(built)) threaded builds differ from the serial build (round $round)" bad[1:min(end, 6)]
    end
end

@testitem "concurrent builds: @extend numbering in concurrent builds" setup = [ConcurrentBuildsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. A nested base continues the outer numbering, also when built as a task
    @testset "concurrent builds: @extend numbering in concurrent builds" begin
        serial = SERIAL["Yield"]
        base = SERIAL["ConcurrentBase"]
        # the merged model has more bound names than its base alone, all distinct (no restart at 1
        # inside the base)
        @test length(serial.names) > length(base.names)
        @test isempty(serial.reused)
        tasks = [Threads.@spawn concurrent_build(l) for l in repeat(["Yield", "ConcurrentBase"], 8)]
        for t in tasks
            sys = fetch(t)
            @test !(sys isa Exception) && isempty(concurrent_reused(sys))
        end
    end
end
