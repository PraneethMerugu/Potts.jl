# canonical term order in generated code (D-105).
# Symbolics stores a sum or product as a dictionary of terms and hands its operands to
# `lower` in that dictionary's order, which follows the terms' hashes. The hash of a term
# includes the hash of its function, and the hash of a Potts-registered operator
# (`population`, `gather`, `value_at`) is derived from its type, so it changes with each package
# build's module id. The generated arithmetic of a rate with several terms therefore changes
# order between builds of identical source, and its floating-point result by a few ulp.
# Base functions (`sin`, `exp`) hash stably across builds, but the same mechanism orders
# their terms; within one session, repeated `generated_code` calls can also swap two operands
# (hash-consed terms rebuilt with another dictionary history).
#
# How a different build is reproduced inside one process: this file adds methods
# `Base.hash(::typeof(op), h)` for the operators above that return the ordinary hash while
# `SALT[] == 0` and a salted one otherwise. A salted hash is exactly what another build
# gives those operators (an arbitrary, different value); Symbolics' term order changes with
# it (negative control below), and nothing else in the model does. The salt is 0 outside
# `canonical_salted`, so the rest of the suite sees the ordinary hashes.
#
# Measured on the code before the change (feat/p6-0ah at b011b772, Julia 1.12, Symbolics
# 7.41.1, SymbolicUtils 4.48.0; this file run alone):
#   - item 1: salts 1–4 change the generated code of every fixture except `CanonicalSum16` under
#     the Potts operators, and of every fixture under `sin`/`cos`/`exp` (`CanonicalModelPop` in 18 of
#     24 cases; 162 of 192 code comparisons fail); final states move by a few ulp (e.g. `Mix` z by 4.4e-16) in 30
#     of 64 state comparisons; `Mix`'s fingerprint changes under 2 of 8 salted builds:
#     the numbering of hoisted population folds (`__odepop1`, `__odepop2`, …, model state
#     columns) follows the term order, and `_commutative_order!` does not normalise names, so
#     fingerprints are NOT fully canonical today for models with several hoisted folds;
#   - item 2: `CanonicalSum16`'s code changes between rounds (3 of 18 fail; two operands of a sum
#     swap, as in `14tt + y_1` → `y_1 + 14tt`); its states are equal;
#   - item 3 (two fresh Potts builds, different module ids and `hash(population)`): 48 of 96
#     report entries differ: the code of 20 of 24 fixture × solver × T cases (all four
#     fixtures) and 28 of 48 final states (by a few ulp); no fingerprint differs between them;
#   - item 4 passes.
#
# Pinned here:
#  1. Generated code is independent of operator hashes. For each fixture, each solver
#     (`ExplicitEuler()`, `Potts.RK4()`, `Adaptive(Rodas5P())`) and T ∈ {Float64, Float32}, every
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
#     fixture × solver × T × algorithm; they must be identical. Run at merge with
#       POTTS_CROSSBUILD=1 julia --project=lib/PottsModels/test -e 'using Test, Potts, PottsModels;
#           include("lib/PottsModels/test/acceptance/canonical_term_order_tests.jl")'
#     from the repository root (the worker processes take about 3.5 minutes, the whole file
#     about 5; the temporary depots are deleted afterwards). Skipped by default (it compiles
#     Potts twice).
#  4. Salt invariance: the fingerprint of every fixture (including `CanonicalAt`, gather, `value_at` and
#     Base terms in a cell rate, and the multi-fold models `Mix`, `CanonicalModelPop`) is the
#     same under every operator-hash salt (item 1). No fingerprint value is stored.

@testsetup module CanonicalTermOrderSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: CorePotts
using TOML: TOML
# ---------------------------------------------------------------------------------------
# Fixtures and helpers, shared verbatim with the cross-build worker processes (item 3).
const SHARED = raw"""
using OrdinaryDiffEqRosenbrock: Rodas5P

# Two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice.
# Cell and model scope, population folds, a gather, an indexed read (`value_at`) and Base terms.
@potts_model Mix begin
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

# A model ODE over three population folds plus Base terms (`ode_expansion_tests.jl`'s population model, extended).
@potts_model CanonicalModelPop begin
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
@potts_model CanonicalAt begin
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

# Base operators only: a 16-term sum (`ode_expansion_tests.jl`'s 16-term sum, with its own variable name and
# coefficient so that no other test file has built these terms before: hash-consed terms
# are shared across models, and the within-session swap of item 2 shows on fresh terms).
eval(quote
    @potts_model CanonicalSum16 begin
        @kinds medium A
        @variables w(cell) = 0.0
        @lattice Lattice((12, 8))
        @energy cells => (volume - 16.0)^2
        @equations D(w) ~ $(Expr(:call, :+, [:(0.0013 * exp(-$i * w) * sin($i * time + w) / (1 + $i * w^2)) for i in 1:16]...))
        @sweep Metropolis(; temperature = 1.0)
    end
end)

const MODELS = (Mix, CanonicalModelPop, CanonicalAt, CanonicalSum16)
const SOLVERS = (("ExplicitEuler()", Potts.ExplicitEuler()), ("RK4()", Potts.RK4()),
    ("Adaptive(Rodas5P())", Potts.Adaptive(Rodas5P())))
const ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const CANONICAL_N = 10

function sigma()
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return s
end
canonical_op(M) = Any[ownership => sigma(), kind => [:A, :A], (M === CanonicalSum16 ? (:w => [1.0, 2.0],) : ())...]
canonical_problem(M, solver; T = Float64) = PottsProblem(M(; name = :x), canonical_op(M), (0, CANONICAL_N); T, seed = 7, ode_solver = solver)

# Line numbers out, including those of macro calls (`@inbounds` records the source path).
function strip_lines!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing)
    foreach(strip_lines!, ex.args)
    return ex
end
str(ex) = string(strip_lines!(deepcopy(ex)))

# Every expression of `generated_code` as text: `name => text` (phases numbered).
function canonical_code(M, solver; T = Float64)
    g = Potts.generated_code(M(; name = :x); T, ode_solver = solver)
    out = Pair{String, String}[]
    for k in propertynames(g)
        v = getproperty(g, k)
        if v isa AbstractVector
            for (i, x) in enumerate(v)
                push!(out, "$k[$i]" => str(x))
            end
        else
            push!(out, String(k) => str(v))
        end
    end
    return out
end

word(x::Float64) = string(reinterpret(UInt64, x); base = 16)
word(x::Float32) = string(reinterpret(UInt32, x); base = 16)
word(x::Integer) = string(x)
word(x) = repr(x)

# The final state as text, bit for bit: σ and every numeric cell and model column.
function digest(u)
    out = ["σ=" * join(word.(vec(Array(u.ownership))), ",")]
    for part in (:cell, :model)
        cols = getproperty(u, part)
        for n in propertynames(cols)
            v = getproperty(cols, n)
            (v isa AbstractArray{<:Number} || v isa Number) || continue
            push!(out, "$part.$n=" * join(word.(vec(collect(v))), ","))
        end
    end
    return out
end

# Code, fingerprint and final states of every fixture × solver × T × algorithm.
function canonical_report(; solvers = SOLVERS)
    out = Dict{String, Any}()
    for M in MODELS, (sl, solver) in solvers, T in (Float64, Float32)
        key = "$(nameof(M)) | $sl | $T"
        prob = canonical_problem(M, solver; T)
        out[key * " | code"] = [k * " :: " * v for (k, v) in canonical_code(M, solver; T)]
        out[key * " | fingerprint"] = string(prob.f.fingerprint; base = 16)
        for alg in ALGS
            out[key * " | $(nameof(typeof(alg)))"] = digest(solve(prob, alg).u[end])
        end
    end
    return out
end
"""
include_string(@__MODULE__, SHARED)
# ---------------------------------------------------------------------------------------
# Salted operator hashes (another build's hashes, in this process)
include(joinpath(@__DIR__, "..", "shared", "salted_hashes.jl"))
const canonical_salted = salted
const SALTS = 1:4
const OPSETS = (("Potts operators", POTTS_OPS), ("sin, cos, exp", BASE_OPS))
# ---------------------------------------------------------------------------------------
# 3. Across package builds (opt-in)
"""Run the shared fixtures in a fresh Julia process that recompiles Potts into its own first
depot; return the report and the loaded Potts build's id and `hash(population)`."""
function canonical_worker(dir)
    depot = mkpath(joinpath(dir, "depot"))
    shared = joinpath(dir, "shared.jl")
    write(shared, SHARED)
    outfile = joinpath(dir, "report.toml")
    script = joinpath(dir, "worker.jl")
    write(
        script, """
        Base.compilecache(Base.identify_package("Potts"))   # a new Potts build in this depot
        using Potts, TOML
        include_string(Main, read($(repr(shared)), String))
        r = canonical_report()
        r["build id"] = string(Base.module_build_id(Potts))
        r["hash(population)"] = string(hash(Potts.population))
        r["cache"] = Base.pkgorigins[Base.PkgId(Potts)].cachepath
        open(io -> TOML.print(io, r), $(repr(outfile)), "w")
        """
    )
    env = copy(ENV)
    env["JULIA_DEPOT_PATH"] = join([depot; DEPOT_PATH], Sys.iswindows() ? ";" : ":")
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $script`
    run(setenv(cmd, env))
    return TOML.parsefile(outfile)
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "canonical term order: repeated generated_code and problem builds are identical" setup = [CanonicalTermOrderSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Repeated calls within one session (first: on fixtures no earlier test has built)
    @testset "canonical term order: repeated generated_code and problem builds are identical ($(nameof(M)))" for M in reverse(MODELS)
        for (sl, solver) in SOLVERS[1:2]
            first_code = first_fp = first_u = nothing
            for rep in 1:4
                c = canonical_code(M, solver)
                prob = canonical_problem(M, solver)
                u = digest(solve(prob, CheckerboardCPM(; proposal = Moore(1))).u[end])
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
end

@testitem "canonical term order: the salt is a different build (negative control)" setup = [CanonicalTermOrderSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Independent of operator hashes
    @testset "canonical term order: the salt is a different build (negative control)" begin
        # unsalted, the added methods return the ordinary hash
        for f in (POTTS_OPS..., BASE_OPS...)
            @test hash(f, UInt(17)) == invoke(hash, Tuple{Function, UInt}, f, UInt(17))
        end
        Potts.Symbolics.@variables a b
        function sx()
            return string.(
                    Potts.SymbolicUtils.arguments(
                        Potts.Symbolics.unwrap(
                            Potts.population(a, b, true) + Potts.gather(a, b, a, b) +
                                Potts.value_at(a, b) + Potts.population(b, a, true) + sin(a)
                        )
                    )
                )
        end
        sx0 = sx()
        orders = [canonical_salted(sx, POTTS_OPS, s) for s in SALTS]
        @test all(o -> sort(o) == sort(sx0), orders)       # the same terms
        @test any(o -> o != sx0, orders)                   # in another order
        @test sx() == sx0                                  # restored
    end
end

@testitem "canonical term order: generated code independent of operator hashes" setup = [CanonicalTermOrderSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical term order: generated code independent of operator hashes ($(nameof(M)), $opl)" for M in MODELS,
            (opl, ops) in OPSETS
        for (sl, solver) in SOLVERS, T in (Float64, Float32)
            base = canonical_code(M, solver; T)
            for s in SALTS
                salted = canonical_salted(() -> canonical_code(M, solver; T), ops, s)
                same = salted == base
                @test same
                if !same
                    bad = [first(b) for (a, b) in zip(salted, base) if a != b]
                    @info "canonical term order: code depends on operator hashes: $(nameof(M)) $opl salt $s $sl $T: $(join(bad, ", "))"
                end
            end
        end
    end
end

@testitem "canonical term order: fingerprints and results independent of operator hashes" setup = [CanonicalTermOrderSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical term order: fingerprints and results independent of operator hashes ($(nameof(M)), $opl)" for M in MODELS,
            (opl, ops) in OPSETS
        for T in (Float64, Float32)
            prob = canonical_problem(M, Potts.RK4(); T)
            want = [digest(solve(prob, alg).u[end]) for alg in ALGS]
            for s in SALTS
                fp, got = canonical_salted(ops, s) do
                    p = canonical_problem(M, Potts.RK4(); T)
                    p.f.fingerprint, [digest(solve(p, alg).u[end]) for alg in ALGS]
                end
                @test fp == prob.f.fingerprint
                @test got == want
            end
        end
    end
end

@testitem "canonical term order: identical code and results across package builds" setup = [CanonicalTermOrderSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "canonical term order: identical code and results across package builds" begin
        if get(ENV, "POTTS_CROSSBUILD", "") == "1"
            mktempdir() do dir
                a = canonical_worker(mkpath(joinpath(dir, "a")))
                b = canonical_worker(mkpath(joinpath(dir, "b")))
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
                    same || @info "canonical term order: differs across builds: $k"
                end
            end
        else
            @test_skip "cross-build check (set POTTS_CROSSBUILD=1)"
        end
    end
end
