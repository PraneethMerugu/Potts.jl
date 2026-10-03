# P6.0aj (ROADMAP Phase 6, step 0): concurrent model builds are deterministic (D-109).
# A model constructor numbers its bound variables (gather `n_k`, population folds `c_k`/`s_k`)
# and its draws (`rand()` → `random_uniform(k)`) from one counter. Today that counter is a
# global `Ref` (`Potts._GATHER_COUNT`), reset by every non-nested build and incremented without
# atomics, so two builds that overlap (on two threads, or two tasks on one thread that yield
# while building) share and reset each other's numbering: their bound variables get other
# names than in a serial build, and one model can get the same name twice. The lattice
# dimension read by `centroid()` (`Potts._DIM`, reset by every build) and the `@extend`
# nesting depth (`Potts._NESTING`) are global build state of the same kind; the accept line
# ("the same generated code and fingerprints as built serially") covers them too, and
# `P60ajYieldCentroid` exercises `_DIM`. Frozen (AUTONOMY §7.3).
#
# How the overlap is produced:
#  - tasks (`Threads.@spawn`): the fixtures `P60ajYield*` call `yield()` between their
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
#     builds differ (every `P60ajYield`, `P60ajYieldCentroid` and `P60ajBase` build; the ones
#     without `yield()` run to completion one at a time and match), e.g. `P60ajBase` gets
#     `[c_36, n_35]` instead of `[c_3, n_2]`, with another fingerprint;
#   - `julia -t 4` (3 runs): items 1 and 4 pass; item 2 fails in every round (20 of 20 task
#     builds differ) and item 3 in every round (16 to 21 of 32 threaded builds differ: every
#     model with bound variables or draws, WortelAct, WortelAct connected, AkeebInvasion and
#     the fixtures; GranerGlazier and MerksVasculogenesis, which have none, never differ);
#     names reused within one model occur in every run (e.g. two folds bound by `c_2`), and
#     `P60ajYieldCentroid` builds throw "`centroid()` … need the model's @lattice declared
#     before them" (another build reset `Potts._DIM` in between) 2 to 5 times per run.
#
# Pinned here:
#  1. Preconditions (negative controls): a serial build of every fixture is reproducible
#     (two serial builds agree), every bound name in it is used by one fold only, the
#     fixtures do have bound variables and draws, and the task fixtures do yield.
#  2. Builds as tasks: 4 rounds of 20 builds (4 copies each of `P60ajYield`,
#     `P60ajYieldCentroid`, `P60ajBase`, `P60ajPlain` and WortelAct, all spawned before any is
#     fetched) give the serial code, fingerprint and bound names, with no name reused within
#     a model and no build error.
#  3. Builds on threads: 4 rounds of `Threads.@threads` over 32 builds (4 copies each of
#     WortelAct, WortelAct connected, AkeebInvasion, GranerGlazier, MerksVasculogenesis,
#     `P60ajPlain`, `P60ajYield`, `P60ajYieldCentroid`) give the same as item 2.
#  4. A nested `@extend` base still continues the outer model's numbering (a merged model
#     has no collisions) when built as a task alongside others.
using Test, Potts, PottsModels
using Potts: Symbolics, SymbolicUtils

# ---------------------------------------------------------------------------------------
# Fixtures (12×8 lattice, two 4×4 cells)

@potts_model P60ajBase begin
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
@potts_model P60ajYield begin
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
    @extend base = P60ajBase()
    yield()
    @after_mcs g ~ 0.01 * sum(volume[c] for c in cells) + 0.3 * g + 0.001 * sum(1.0 for s in sites) +
                   0.01 * maximum(y[c] for c in cells)
    yield()
    @drive copy => 0.1 * (sum(volume[owner[n]] for n in Moore(1)(source)) - sum(volume[owner[n]] for n in Moore(1)(target)))
    @sweep Metropolis(; temperature = 1.0)
end

# The same model without `yield()` (for the threads part).
@potts_model P60ajPlain begin
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
@potts_model P60ajYieldCentroid begin
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

function p60aj_sigma()
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return s
end
p60aj_two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)

const P60AJ_FIXTURE_OP = Any[ownership => p60aj_sigma(), kind => [:A, :A]]
const P60AJ_GG = graner_glazier_state()
const P60AJ_AKEEB = akeeb_state(; lattice = (99, 60))

# label => (constructor, initial state, problem keywords)
const P60AJ_CASES = Dict{String, Tuple{Any, Any, NamedTuple}}(
    "P60ajYield" => (() -> P60ajYield(; name = :x), P60AJ_FIXTURE_OP, (;)),
    "P60ajYieldCentroid" => (() -> P60ajYieldCentroid(; name = :x), P60AJ_FIXTURE_OP, (;)),
    "P60ajBase" => (() -> P60ajBase(; name = :x), P60AJ_FIXTURE_OP, (;)),
    "P60ajPlain" => (() -> P60ajPlain(; name = :x), P60AJ_FIXTURE_OP, (;)),
    "WortelAct" => (() -> WortelAct(; name = :act, lattice = (8, 8)),
        Any[ownership => p60aj_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (;)),
    "WortelAct connected" => (() -> WortelAct(; name = :act, lattice = (8, 8), connected = true),
        Any[ownership => p60aj_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (;)),
    "AkeebInvasion" => (() -> AkeebInvasion(; name = :akeeb, lattice = (99, 60)), P60AJ_AKEEB, (; capacity = 1000)),
    "GranerGlazier" => (() -> GranerGlazier(; name = :gg), Any[ownership => P60AJ_GG[1], kind => P60AJ_GG[2]], (;)),
    "MerksVasculogenesis" => (() -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        Any[ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]],
        (; field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0))),
)
const P60AJ_TASK_LABELS = ("P60ajYield", "P60ajYieldCentroid", "P60ajBase", "P60ajPlain", "WortelAct")
const P60AJ_THREAD_LABELS = ("WortelAct", "WortelAct connected", "AkeebInvasion", "GranerGlazier",
    "MerksVasculogenesis", "P60ajPlain", "P60ajYield", "P60ajYieldCentroid")
const P60AJ_ROUNDS = 4
const P60AJ_COPIES = 4

# ---------------------------------------------------------------------------------------
# What is compared

# Line numbers out, including those of macro calls (`@inbounds` records the source path).
function p60aj_strip!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing)
    foreach(p60aj_strip!, ex.args)
    return ex
end

# Every expression of `generated_code` as text (phases numbered).
function p60aj_code(sys, kw)
    g = Potts.generated_code(sys; (haskey(kw, :field_solver) ? (; field_solver = kw.field_solver) : (;))...)
    out = String[]
    for k in propertynames(g)
        v = getproperty(g, k)
        for (i, x) in enumerate(v isa AbstractVector ? v : [v])
            push!(out, "$k[$i] :: " * string(p60aj_strip!(deepcopy(x))))
        end
    end
    return out
end

# Every gather / population fold of the system, by its bound variable: name => distinct folds.
function p60aj_binders(sys)
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
            walk(getfield(sys, f))
        end
    else
        walk(sys)
    end
    return out
end
p60aj_reused(sys) = sort!([n for (n, s) in p60aj_binders(sys) if length(s) > 1])

"""Code, fingerprint, bound names and reused names of a built system (or the error it threw)."""
function p60aj_signature(label, sys)
    sys isa Exception && return (; code = ["error: " * sprint(showerror, sys)], fingerprint = UInt64(0), names = String[],
        reused = String[])
    _, op, kw = P60AJ_CASES[label]
    prob = PottsProblem(sys, op, (0, 1); kw...)
    b = p60aj_binders(sys)
    return (; code = p60aj_code(sys, kw), fingerprint = prob.f.fingerprint, names = sort!(collect(keys(b))),
        reused = sort!([n for (n, s) in b if length(s) > 1]))
end

p60aj_build(label) = try
    P60AJ_CASES[label][1]()
catch e
    e
end

const P60AJ_SERIAL = Dict(l => p60aj_signature(l, p60aj_build(l)) for l in keys(P60AJ_CASES))

"""Compare the systems `built` (label => system) with the serial builds; return the failures."""
function p60aj_check(built, how)
    bad = String[]
    for (label, sys) in built
        s = p60aj_signature(label, sys)
        ref = P60AJ_SERIAL[label]
        why = String[]
        s.code == ref.code || push!(why, "code differs (" * join([first(split(a, " :: ")) for (a, r) in zip(s.code, ref.code) if a != r], ", ") *
                                         (length(s.code) == length(ref.code) ? "" : "; $(length(s.code)) vs $(length(ref.code)) expressions") * ")")
        s.fingerprint == ref.fingerprint || push!(why, "fingerprint $(repr(s.fingerprint)) ≠ $(repr(ref.fingerprint))")
        s.names == ref.names || push!(why, "bound names $(s.names) ≠ $(ref.names)")
        isempty(s.reused) || push!(why, "names reused within the model: $(s.reused)")
        any(startswith("error: "), s.code) && push!(why, first(s.code))
        isempty(why) || push!(bad, "$how $label: " * join(why, "; "))
    end
    return bad
end

# ---------------------------------------------------------------------------------------
# 1. Preconditions

@testset "P6.0aj: serial builds are reproducible and well named ($label)" for label in sort!(collect(keys(P60AJ_CASES)))
    ref = P60AJ_SERIAL[label]
    @test !any(startswith("error: "), ref.code)
    @test isempty(ref.reused)
    @test isempty(p60aj_check([label => p60aj_build(label)], "serial"))
end

@testset "P6.0aj: the fixtures have bound variables, draws and yields (negative controls)" begin
    for label in ("P60ajYield", "P60ajPlain", "P60ajBase", "WortelAct", "WortelAct connected", "P60ajYieldCentroid")
        @test !isempty(P60AJ_SERIAL[label].names)
    end
    @test length(P60AJ_SERIAL["P60ajYield"].names) > length(P60AJ_SERIAL["P60ajPlain"].names)   # + the base's
    @test any(c -> occursin("CorePotts.draw(", c), P60AJ_SERIAL["AkeebInvasion"].code)   # `rand()` (a numbered draw)
    @test isempty(P60AJ_SERIAL["GranerGlazier"].names)
    # the yielding fixtures do yield: a build in a task lets another task run
    ran = Ref(false)
    t = Threads.@spawn (ran[] = true)
    Threads.nthreads() == 1 && (P60ajYield(; name = :x); @test ran[])
    wait(t)
    # the walker sees a reuse when there is one: two folds with the same bound variable
    Symbolics.@variables c₀ a₀ b₀
    @test p60aj_reused([Potts.population(c₀, a₀, true) + Potts.population(c₀, b₀, true)]) == ["c₀"]
    @test p60aj_reused([Potts.population(c₀, a₀, true) + Potts.population(b₀, b₀, true)]) == String[]
end

# ---------------------------------------------------------------------------------------
# 2. Builds as tasks (meaningful on any number of threads)

@testset "P6.0aj: models built as concurrent tasks match the serial build (round $round)" for round in 1:P60AJ_ROUNDS
    labels = [l for l in P60AJ_TASK_LABELS for _ in 1:P60AJ_COPIES]
    tasks = [Threads.@spawn p60aj_build(l) for l in labels]   # all started before any is fetched
    built = [l => fetch(t) for (l, t) in zip(labels, tasks)]
    @test length(built) >= 16
    bad = p60aj_check(built, "task")
    @test isempty(bad)
    isempty(bad) || @info "P6.0aj: $(length(bad)) of $(length(built)) task builds differ from the serial build (round $round)" bad[1:min(end, 6)]
end

# ---------------------------------------------------------------------------------------
# 3. Builds on threads (meaningful with `julia -t 4`)

Threads.nthreads() < 4 && @info "P6.0aj: running with $(Threads.nthreads()) thread(s); the threads part " *
                               "(item 3) is meaningful under `julia -t 4`"

@testset "P6.0aj: models built on $(Threads.nthreads()) threads match the serial build (round $round)" for round in 1:P60AJ_ROUNDS
    labels = [l for _ in 1:P60AJ_COPIES for l in P60AJ_THREAD_LABELS]
    built = Vector{Any}(undef, length(labels))
    Threads.@threads :dynamic for i in eachindex(labels)
        built[i] = labels[i] => p60aj_build(labels[i])
    end
    @test length(built) >= 16
    bad = p60aj_check(built, "thread")
    @test isempty(bad)
    isempty(bad) || @info "P6.0aj: $(length(bad)) of $(length(built)) threaded builds differ from the serial build (round $round)" bad[1:min(end, 6)]
end

# ---------------------------------------------------------------------------------------
# 4. A nested base continues the outer numbering, also when built as a task

@testset "P6.0aj: @extend numbering in concurrent builds" begin
    serial = P60AJ_SERIAL["P60ajYield"]
    base = P60AJ_SERIAL["P60ajBase"]
    # the merged model has more bound names than its base alone, all distinct (no restart at 1
    # inside the base)
    @test length(serial.names) > length(base.names)
    @test isempty(serial.reused)
    tasks = [Threads.@spawn p60aj_build(l) for l in repeat(["P60ajYield", "P60ajBase"], 8)]
    for t in tasks
        sys = fetch(t)
        @test !(sys isa Exception) && isempty(p60aj_reused(sys))
    end
end
