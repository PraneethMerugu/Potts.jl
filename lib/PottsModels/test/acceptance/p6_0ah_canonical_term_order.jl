# P6.0ah (ROADMAP Phase 6, step 0): canonical term order in generated code (D-105).
# Symbolics stores a sum or product as a dictionary of terms and hands its operands to
# `lower` in that dictionary's order, which follows the terms' hashes. The hash of a term
# includes the hash of its function, and the hash of a Potts-registered operator
# (`population`, `gather`, `at`) is derived from its type, so it changes with each package
# build's module id. The generated arithmetic of a rate with several terms therefore changes
# order between builds of identical source, and its floating-point result by a few ulp.
# Base functions (`sin`, `exp`) hash stably across builds, but the same mechanism orders
# their terms; within one session, repeated `generated_code` calls can also swap two operands
# (hash-consed terms rebuilt with another dictionary history). Frozen (AUTONOMY §7.3).
#
# How a different build is reproduced inside one process: this file adds methods
# `Base.hash(::typeof(op), h)` for the operators above that return the ordinary hash while
# `P60AH_SALT[] == 0` and a salted one otherwise. A salted hash is exactly what another build
# gives those operators (an arbitrary, different value); Symbolics' term order changes with
# it (negative control below), and nothing else in the model does. The salt is 0 outside
# `p60ah_salted`, so the rest of the suite sees the ordinary hashes.
#
# Measured on the code before the change (feat/p6-0ah at b011b772, Julia 1.12, Symbolics
# 7.41.1, SymbolicUtils 4.48.0; this file run alone):
#   - item 1: salts 1–4 change the generated code of every fixture except `P60ahSum16` under
#     the Potts operators, and of every fixture under `sin`/`cos`/`exp` (`P60ahModelPop` in 18 of
#     24 cases; 162 of 192 code comparisons fail); final states move by a few ulp (e.g. `P60ahMix` z by 4.4e-16) in 30
#     of 64 state comparisons; `P60ahMix`'s fingerprint changes under 2 of 8 salted builds:
#     the numbering of hoisted population folds (`__odepop1`, `__odepop2`, …, model state
#     columns) follows the term order, and `_commutative_order!` does not normalise names, so
#     fingerprints are NOT fully canonical today for models with several hoisted folds;
#   - item 2: `P60ahSum16`'s code changes between rounds (3 of 18 fail; two operands of a sum
#     swap, as in the P6.0ag review's `14tt + y_1` → `y_1 + 14tt`); its states are equal;
#   - item 3 (two fresh Potts builds, different module ids and `hash(population)`): 48 of 96
#     report entries differ: the code of 20 of 24 fixture × solver × T cases (all four
#     fixtures) and 28 of 48 final states (by a few ulp); no fingerprint differs between them;
#   - item 4 passes.
#
# Pinned here:
#  1. Generated code is independent of operator hashes. For each fixture, each solver
#     (`ExplicitEuler()`, `RK4()`, `Adaptive(Rodas5P())`) and T ∈ {Float64, Float32}, every
#     expression of `Potts.generated_code` (line numbers stripped) under salts 1–4 of the
#     Potts operators, and separately of `sin`/`cos`/`exp`, is identical to the unsalted
#     one; the problem fingerprint and the final state (σ and every cell and model column,
#     RK4, both algorithms, Float64 and Float32, 10 MCS, seed 7) are bitwise identical too.
#     Negative control: the salt does reorder Symbolics' operands of a sum of Potts terms.
#  2. Within one session, four rounds of (`generated_code`, problem build, solve, GC) give
#     identical code, fingerprints and states.
#  3. Across package builds (opt-in, `POTTS_CROSSBUILD=1`): two Julia processes, each with a
#     fresh first depot in which it recompiles Potts (`Base.compilecache`), so the two load
#     Potts builds with different module ids (checked, as is that `hash(population)`
#     differs). Both report the generated code, fingerprint and final states of every
#     fixture × solver × T × algorithm; they must be identical. Run by the coordinator with
#       POTTS_CROSSBUILD=1 julia --project=lib/PottsModels/test -e 'using Test, Potts, PottsModels;
#           include("lib/PottsModels/test/acceptance/p6_0ah_canonical_term_order.jl")'
#     from the repository root (the worker processes take about 3.5 minutes, the whole file
#     about 5; the temporary depots are deleted afterwards). Skipped by default (it compiles
#     Potts twice).
#  4. Fingerprints that must not change: GranerGlazier, MerksVasculogenesis and the ODE
#     fixture `P60ahAt` (gather, `at` and Base terms in a cell rate; folds only in a model
#     update, none hoisted), all salt-invariant today. Fingerprints that may change (once, to a
#     canonical value): models whose ODEs hoist two or more population folds (`P60ahMix`,
#     `P60ahModelPop` here), whose fold numbering is build-dependent today; they are pinned
#     only as salt-invariant (item 1), not to a value. Results within a build stay the same
#     in law; values are not pinned to recorded numbers (a canonical order may differ from
#     today's by a few ulp).
using Test, Potts, PottsModels
using Potts: CorePotts
using TOML: TOML

# ---------------------------------------------------------------------------------------
# Fixtures and helpers, shared verbatim with the cross-build worker processes (item 3).

const P60AH_SHARED = raw"""
using OrdinaryDiffEqRosenbrock: Rodas5P

# Two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice.
# Cell and model scope, population folds, a gather, an indexed read (`at`) and Base terms.
@potts_model P60ahMix begin
    @kinds medium A
    @variables y(cell) = 0.0 z(cell) = 1.0 g(model) = 0.5
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ 0.01 * sum(z[c] for c in cells) + 0.02 * sum(volume[owner[n]] for n in Moore(1)(42)) + 0.03 * y[3 - id] +
               0.04 * sin(y) + 0.05 * exp(-z) - 0.1y
        D(z) ~ 0.01 * sum(y[c] for c in cells) * z + 0.02 * mean(z[c] for c in cells) - 0.1z + 0.001volume
        D(g) ~ 0.001 * sum(volume[c] for c in cells) + 0.001 * sum(1.0 for s in sites) + 0.002 * sum(y[c] for c in cells) -
               0.1g + 0.01 * cos(g)
    end
    @sweep Metropolis(; temperature = 1.0)
end

# A model ODE over three population folds plus Base terms (P6.0ag's ModelPop, extended).
@potts_model P60ahModelPop begin
    @kinds medium A
    @variables g(model) = 0.0 h(model) = 1.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(g) ~ 0.001 * sum(volume[c] for c in cells) + 0.001 * sum(1.0 for s in sites) + 0.002 * sum(surface[c] for c in cells) -
               0.1g + 0.01 * sin(h)
        D(h) ~ 0.5 * exp(-g) - 0.2h + 0.0001 * sum(volume[c] for c in cells) * h
    end
    @sweep Metropolis(; temperature = 1.0)
end

# A cell rate with two gathers, an indexed read and Base terms (no hoisted fold); a model
# update over three folds.
@potts_model P60ahAt begin
    @kinds medium A
    @variables y(cell) = 0.0 g(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ 0.03 * y[3 - id] + 0.04 * sin(y) + 0.05 * exp(-y) + 0.02 * sum(volume[owner[n]] for n in Moore(1)(42)) +
               0.01 * sum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - 0.1y
    end
    @after_mcs g ~ 0.01 * sum(volume[c] for c in cells) + 0.02 * sum(y[c] for c in cells) + 0.3 * g + 0.001 * sum(1.0 for s in sites)
    @sweep Metropolis(; temperature = 1.0)
end

# Base operators only: a 16-term sum (P6.0ag's Sum16, with its own variable name and
# coefficient so that no other test file has built these terms before: hash-consed terms
# are shared across models, and the within-session swap of item 2 shows on fresh terms).
eval(quote
    @potts_model P60ahSum16 begin
        @kinds medium A
        @variables w(cell) = 0.0
        @lattice Lattice((12, 8))
        @energy cells => (volume - 16.0)^2
        @equations D(w) ~ $(Expr(:call, :+, [:(0.0013 * exp(-$i * w) * sin($i * time + w) / (1 + $i * w^2)) for i in 1:16]...))
        @sweep Metropolis(; temperature = 1.0)
    end
end)

const P60AH_MODELS = (P60ahMix, P60ahModelPop, P60ahAt, P60ahSum16)
const P60AH_SOLVERS = (("ExplicitEuler()", Potts.ExplicitEuler()), ("RK4()", Potts.RK4()),
    ("Adaptive(Rodas5P())", Potts.Adaptive(Rodas5P())))
const P60AH_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const P60AH_N = 10

function p60ah_sigma()
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return s
end
p60ah_op(M) = Any[ownership => p60ah_sigma(), kind => [:A, :A], (M === P60ahSum16 ? (:w => [1.0, 2.0],) : ())...]
p60ah_problem(M, solver; T = Float64) = PottsProblem(M(; name = :x), p60ah_op(M), (0, P60AH_N); T, seed = 7, ode_solver = solver)

# Line numbers out, including those of macro calls (`@inbounds` records the source path).
function p60ah_strip!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing)
    foreach(p60ah_strip!, ex.args)
    return ex
end
p60ah_str(ex) = string(p60ah_strip!(deepcopy(ex)))

# Every expression of `generated_code` as text: `name => text` (phases numbered).
function p60ah_code(M, solver; T = Float64)
    g = Potts.generated_code(M(; name = :x); T, ode_solver = solver)
    out = Pair{String, String}[]
    for k in propertynames(g)
        v = getproperty(g, k)
        if v isa AbstractVector
            for (i, x) in enumerate(v)
                push!(out, "$k[$i]" => p60ah_str(x))
            end
        else
            push!(out, String(k) => p60ah_str(v))
        end
    end
    return out
end

p60ah_word(x::Float64) = string(reinterpret(UInt64, x); base = 16)
p60ah_word(x::Float32) = string(reinterpret(UInt32, x); base = 16)
p60ah_word(x::Integer) = string(x)
p60ah_word(x) = repr(x)

# The final state as text, bit for bit: σ and every numeric cell and model column.
function p60ah_digest(u)
    out = ["σ=" * join(p60ah_word.(vec(Array(u.σ))), ",")]
    for part in (:cell, :model)
        cols = getproperty(u, part)
        for n in propertynames(cols)
            v = getproperty(cols, n)
            (v isa AbstractArray{<:Number} || v isa Number) || continue
            push!(out, "$part.$n=" * join(p60ah_word.(vec(collect(v))), ","))
        end
    end
    return out
end

# Code, fingerprint and final states of every fixture × solver × T × algorithm.
function p60ah_report(; solvers = P60AH_SOLVERS)
    out = Dict{String, Any}()
    for M in P60AH_MODELS, (sl, solver) in solvers, T in (Float64, Float32)
        key = "$(nameof(M)) | $sl | $T"
        prob = p60ah_problem(M, solver; T)
        out[key * " | code"] = [k * " :: " * v for (k, v) in p60ah_code(M, solver; T)]
        out[key * " | fingerprint"] = string(prob.f.fingerprint; base = 16)
        for alg in P60AH_ALGS
            out[key * " | $(nameof(typeof(alg)))"] = p60ah_digest(solve(prob, alg).u[end])
        end
    end
    return out
end
"""

include_string(@__MODULE__, P60AH_SHARED)

# ---------------------------------------------------------------------------------------
# Salted operator hashes (another build's hashes, in this process)

const P60AH_SALT = Ref{UInt}(0)
const P60AH_SALTED = Ref{Tuple}(())
const P60AH_POTTS_OPS = (Potts.population, Potts.gather, Potts.at, Potts.at2)
const P60AH_BASE_OPS = (sin, cos, exp)
for f in (P60AH_POTTS_OPS..., P60AH_BASE_OPS...)
    @eval function Base.hash(g::typeof($f), h::UInt)
        (P60AH_SALT[] == 0 || !any(x -> x === g, P60AH_SALTED[])) && return invoke(hash, Tuple{Function, UInt}, g, h)
        return hash(P60AH_SALT[], hash(:p60ah_salt, h))
    end
end

"""Run `f()` with the hashes of `ops` salted by `s` (0: the ordinary hashes)."""
function p60ah_salted(f, ops, s)
    P60AH_SALTED[] = ops
    P60AH_SALT[] = s
    try
        return f()
    finally
        P60AH_SALT[] = 0
        P60AH_SALTED[] = ()
    end
end

const P60AH_SALTS = 1:4
const P60AH_OPSETS = (("Potts operators", P60AH_POTTS_OPS), ("sin, cos, exp", P60AH_BASE_OPS))

# ---------------------------------------------------------------------------------------
# 2. Repeated calls within one session (first: on fixtures no earlier test has built)

@testset "P6.0ah: repeated generated_code and problem builds are identical ($(nameof(M)))" for M in reverse(P60AH_MODELS)
    for (sl, solver) in P60AH_SOLVERS[1:2]
        first_code = first_fp = first_u = nothing
        for rep in 1:4
            c = p60ah_code(M, solver)
            prob = p60ah_problem(M, solver)
            u = p60ah_digest(solve(prob, CheckerboardCPM(; proposal = Moore(1))).u[end])
            if rep == 1
                first_code, first_fp, first_u = c, prob.f.fingerprint, u
            else
                @test c == first_code
                @test prob.f.fingerprint == first_fp
                @test u == first_u
            end
            GC.gc(true)
        end
    end
end

# ---------------------------------------------------------------------------------------
# 1. Independent of operator hashes

@testset "P6.0ah: the salt is a different build (negative control)" begin
    # unsalted, the added methods return the ordinary hash
    for f in (P60AH_POTTS_OPS..., P60AH_BASE_OPS...)
        @test hash(f, UInt(17)) == invoke(hash, Tuple{Function, UInt}, f, UInt(17))
    end
    Potts.Symbolics.@variables a b
    sx() = string.(Potts.SymbolicUtils.arguments(Potts.Symbolics.unwrap(Potts.population(a, b, true) + Potts.gather(a, b, a, b) +
                                                                         Potts.at(a, b) + Potts.population(b, a, true) + sin(a))))
    sx0 = sx()
    orders = [p60ah_salted(sx, P60AH_POTTS_OPS, s) for s in P60AH_SALTS]
    @test all(o -> sort(o) == sort(sx0), orders)       # the same terms
    @test any(o -> o != sx0, orders)                   # in another order
    @test sx() == sx0                                  # restored
end

@testset "P6.0ah: generated code independent of operator hashes ($(nameof(M)), $opl)" for M in P60AH_MODELS,
                                                                                            (opl, ops) in P60AH_OPSETS
    for (sl, solver) in P60AH_SOLVERS, T in (Float64, Float32)
        base = p60ah_code(M, solver; T)
        for s in P60AH_SALTS
            salted = p60ah_salted(() -> p60ah_code(M, solver; T), ops, s)
            same = salted == base
            @test same
            if !same
                bad = [first(b) for (a, b) in zip(salted, base) if a != b]
                @info "P6.0ah: code depends on operator hashes: $(nameof(M)) $opl salt $s $sl $T: $(join(bad, ", "))"
            end
        end
    end
end

@testset "P6.0ah: fingerprints and results independent of operator hashes ($(nameof(M)), $opl)" for M in P60AH_MODELS,
                                                                                                     (opl, ops) in P60AH_OPSETS
    for T in (Float64, Float32)
        prob = p60ah_problem(M, Potts.RK4(); T)
        want = [p60ah_digest(solve(prob, alg).u[end]) for alg in P60AH_ALGS]
        for s in P60AH_SALTS
            fp, got = p60ah_salted(ops, s) do
                p = p60ah_problem(M, Potts.RK4(); T)
                p.f.fingerprint, [p60ah_digest(solve(p, alg).u[end]) for alg in P60AH_ALGS]
            end
            @test fp == prob.f.fingerprint
            @test got == want
        end
    end
end

# ---------------------------------------------------------------------------------------
# 3. Across package builds (opt-in)

"""Run the shared fixtures in a fresh Julia process that recompiles Potts into its own first
depot; return the report and the loaded Potts build's id and `hash(population)`."""
function p60ah_worker(dir)
    depot = mkpath(joinpath(dir, "depot"))
    shared = joinpath(dir, "shared.jl")
    write(shared, P60AH_SHARED)
    outfile = joinpath(dir, "report.toml")
    script = joinpath(dir, "worker.jl")
    write(script, """
    Base.compilecache(Base.identify_package("Potts"))   # a new Potts build in this depot
    using Potts, TOML
    include_string(Main, read($(repr(shared)), String))
    r = p60ah_report()
    r["build id"] = string(Base.module_build_id(Potts))
    r["hash(population)"] = string(hash(Potts.population))
    r["cache"] = Base.pkgorigins[Base.PkgId(Potts)].cachepath
    open(io -> TOML.print(io, r), $(repr(outfile)), "w")
    """)
    env = copy(ENV)
    env["JULIA_DEPOT_PATH"] = join([depot; DEPOT_PATH], Sys.iswindows() ? ";" : ":")
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $script`
    run(setenv(cmd, env))
    return TOML.parsefile(outfile)
end

@testset "P6.0ah: identical code and results across package builds" begin
    if get(ENV, "POTTS_CROSSBUILD", "") == "1"
        mktempdir() do dir
            a = p60ah_worker(mkpath(joinpath(dir, "a")))
            b = p60ah_worker(mkpath(joinpath(dir, "b")))
            # preconditions: two different builds, loaded from the fresh depots
            @test a["build id"] != b["build id"]
            @test a["hash(population)"] != b["hash(population)"]
            @test startswith(a["cache"], joinpath(dir, "a")) && startswith(b["cache"], joinpath(dir, "b"))
            meta = ("build id", "hash(population)", "cache")
            ka = sort!(filter(k -> !(k in meta), collect(keys(a))))
            @test ka == sort!(filter(k -> !(k in meta), collect(keys(b))))
            for k in ka
                same = a[k] == b[k]
                @test same
                same || @info "P6.0ah: differs across builds: $k"
            end
        end
    else
        @test_skip "cross-build check (set POTTS_CROSSBUILD=1)"
    end
end

# ---------------------------------------------------------------------------------------
# 4. Fingerprints that must not change

p60ah_published() = (
    (:GranerGlazier, () -> (σ = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => σ[1], kind => σ[2]], (0, 10)))),
    (:MerksVasculogenesis, () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0))),
    (:P60ahAt_RK4, () -> p60ah_problem(P60ahAt, Potts.RK4())),
    (:P60ahAt_Euler, () -> p60ah_problem(P60ahAt, Potts.ExplicitEuler())),
)
const P60AH_FINGERPRINTS = Dict{Symbol, UInt64}(
    :GranerGlazier => 0x04a4528dcdf3fcb8,   # re-pinned under D-122
    :MerksVasculogenesis => 0x984e2ad5906fc999,   # re-pinned under D-122
    :P60ahAt_RK4 => 0x52fad8cebbee12ed,   # re-pinned under D-124
    :P60ahAt_Euler => 0xe41e0c4a682a9697,   # re-pinned under D-124
)

@testset "P6.0ah: fingerprints unchanged" begin
    for (name, build) in p60ah_published()
        fp = build().f.fingerprint
        @test fp == P60AH_FINGERPRINTS[name]
        fp == P60AH_FINGERPRINTS[name] || @info "P6.0ah: fingerprint $name = $(repr(fp))"
    end
end
