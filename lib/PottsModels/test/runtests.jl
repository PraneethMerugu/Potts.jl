# PottsModels: every model builds, compiles and runs, and its derived ΔH matches the brute-
# force energy difference; mechanism tests (mechanisms.jl) check what each model is for.
using Test, Potts, PottsModels, Aqua, TOML
using Potts: CorePotts
using Statistics: mean
# device selection (D-157): the acceptance files' device testsets run here only when
# POTTS_GPU = metal | rocm; the GPU group runs them from test/gpu.jl
isdefined(Main, :PottsDevices) || include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "devices.jl"))
# test-only models that the acceptance files use by name (D-254)
isdefined(Main, :SingleDivisionFixture) || include(joinpath(@__DIR__, "fixtures.jl"))

function selfcheck(prob; n = 200)
    sol = solve(remake(prob; tspan = (0, 3)), SequentialCPM(; proposal = Moore(1)))
    lat = prob.lattice
    ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
    moore = CorePotts.relation(Moore(1), lat)
    worst = 0.0
    for u in sol.u, i in 1:n
        t = mod1(i * 7919, length(u.σ)); x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, moore.offsets[mod1(i, length(moore))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.σ[t], u.σ[s])
        a = deepcopy(u); a.σ[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx)
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    return worst
end

# POTTSMODELS_SHARD = "k/n" (default "1/1", everything): CI runs the files below in n
# parallel processes (.github/ci/parallel.sh). Files are dealt to shards by longest-first
# greedy over their measured wall times (shard_weights.toml; a file it does not list weighs
# its median), so every process computes the same split and every file runs in exactly one
# shard. Shard 1 also runs the model checks below and Aqua.
const POTTSMODELS_SHARD = let (k, n) = parse.(Int, split(get(ENV, "POTTSMODELS_SHARD", "1/1"), '/'))
    1 <= k <= n || throw(ArgumentError("POTTSMODELS_SHARD = $k/$n: need 1 ≤ k ≤ n"))
    (k, n)
end
const POTTSMODELS_FIRST_SHARD = POTTSMODELS_SHARD[1] == 1

POTTSMODELS_FIRST_SHARD && @testset "PottsModels" begin
    σ, kinds = graner_glazier_state()
    @test size(σ) == (72, 72) && length(kinds) == 64 && size(first(graner_glazier_state(2))) == (144, 144)
    two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
    cases = [
        ("Graner–Glazier", GranerGlazier(; name = :gg), [ownership => σ, kind => kinds]),
        ("Wortel Act", WortelAct(; name = :act, lattice = (8, 8)), [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]]),
        ("Wortel Act (connected)", WortelAct(; name = :act, lattice = (8, 8), connected = true),
            [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]]),
        ("Merks", MerksVasculogenesis(; name = :merks, lattice = (8, 8)), [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]],
            (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0))),
        ("Merks 2006", Merks2006(; name = :m6, lattice = (16, 16)),
            layout(merks2006_layout(; lattice = (16, 16), n = 3, side = 4), (16, 16)), (; field_solver = ExplicitEuler(substeps = 15))),
        ("Merks 2006 (hard connectivity)", Merks2006(; name = :m6, lattice = (16, 16), rule = :hard),
            layout(merks2006_layout(; lattice = (16, 16), n = 3, side = 4), (16, 16)), (; field_solver = ExplicitEuler(substeps = 15))),
        ("Merks 2008", Merks2008(; name = :m8, lattice = (16, 16)),
            [layout(merks2008_denovo(; lattice = (16, 16), n = 4, rounds = 2), (16, 16)); :t_relax => 0.0],
            (; field_solver = ExplicitEuler(substeps = 15))),
        ("Merks 2008 (extension only)", Merks2008(; name = :m8, lattice = (16, 16), mode = :extension_only),
            [layout(merks2008_denovo(; lattice = (16, 16), n = 4, rounds = 2), (16, 16)); :t_relax => 0.0],
            (; field_solver = ExplicitEuler(substeps = 15))),
        ("single-division fixture", SingleDivisionFixture(; name = :fixture), [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]]),
        ("OpenVT growing monolayer", OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)), openvt_monolayer_state(; lattice = (24, 24))),
        ("sheared foam", ShearedFoam(; name = :foam, lattice = (32, 32)),
            [sheared_foam_state(; lattice = (32, 32)); :ytop => 32.0; :ymid => 16.5; :γ0 => 2.0; :T => 1.0]),
        ("sheared foam (periodic bulk shear)", ShearedFoam(; name = :foam, lattice = (32, 32)),
            [sheared_foam_state(; lattice = (32, 32)); :ytop => 32.0; :ymid => 16.5; :β => 0.5; :bulk => 1.0; :periodic => 1.0; :T => 1.0]),
    ]
    @testset "$label" for (label, sys, op, kw...) in cases
        prob = PottsProblem(sys, op, (0, 10); get(kw, 1, (;))...)
        @test selfcheck(prob) < 1e-9
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
        @test Symbol(sol.retcode) === :Success
        u = sol.u[end]
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
    end
    @testset "Akeeb invasion (99×60)" begin
        op = akeeb_state(; lattice = (99, 60))
        n0 = length(op[2].second)
        @test count(==(:follower), op[2].second) == 231 && 70 <= count(==(:leader), op[2].second) <= 77
        # 300 MCS: about 1 in 4 state seeds has no division by MCS 200 (MersenneTwister and
        # StableRNG states alike, 120 seeds each); by 300 every seed has divided
        # a layout carries no lattice (D-091): on a wider lattice the 99-wide slab is painted
        # and the rest stays medium
        wide = layout(akeeb_layout(; lattice = (99, 60)), (500, 300))[1].second
        @test all(>(0), wide[1:99, 1:21]) && all(==(0), wide[100:end, :]) && all(==(0), wide[:, 22:end])
        @test_throws ArgumentError layout(akeeb_layout(; lattice = (99, 60)), (99, 60, 4)) # 3D
        @test_throws ArgumentError akeeb_layout(; lattice = (99, 20))                      # below the slab
        prob = PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (99, 60)), op, (0, 300); capacity = 1000)
        @test selfcheck(prob) < 1e-9
        sol = solve(prob, SequentialCPM(; proposal = VonNeumann(1)))
        u = sol.u[end]
        @test sol.stats.lifecycle.divisions > 0
        @test all(>(0), u.cell.volume[1:n0])                                             # no extinction
        @test all(c -> u.cell.clock[c] >= 0 || u.cell.clock[c] == -1, 1:n0)
        p0 = remake(prob; u0 = akeeb_state(; lattice = (99, 60), pp = 0.0))
        @test solve(p0, SequentialCPM(; proposal = VonNeumann(1))).stats.lifecycle.divisions == 0
        @test akeeb_contacts(-2.0)[2, 3] == akeeb_contacts(-2.0)[3, 2] == -2.0
    end
    @testset "graner_glazier_aggregate margin" begin
        for margin in (0, 10, 30)
            σm, km = graner_glazier_aggregate(200; seed = 1, margin)
            occupied = σm .!= 0
            rows = findall(vec(any(occupied; dims = 2))); cols = findall(vec(any(occupied; dims = 1)))
            @test length(km) == 200 && size(σm, 1) == size(σm, 2)
            # at least `margin` medium rows and columns on every side: a gap of ≥ 2margin to the periodic image
            @test first(rows) > margin && first(cols) > margin
            @test last(rows) <= size(σm, 1) - margin && last(cols) <= size(σm, 2) - margin
        end
        # the lattice grows by exactly twice the change of margin; the default is 60
        @test size(graner_glazier_aggregate(200; seed = 1, margin = 30)[1], 1) ==
              size(graner_glazier_aggregate(200; seed = 1)[1], 1) - 60
        @test_throws ArgumentError graner_glazier_aggregate(200; seed = 1, margin = -1)
    end
    @testset "Akeeb seeding emulates the authors' CC3D loop (D-068, spec 10 §5.3.6)" begin
        # the counted inventory of the leader layer at the published 500×300, slab 21
        n = 400
        painted, counted = zeros(Int, n), zeros(Int, n)
        quiet(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())
        for s in 1:n
            point, report = quiet(() -> layout(akeeb_layout(; seed = s), (500, 300); report = true))
            σ, kinds = point[1].second, point[2].second
            t = only(r for r in report if r.type === :InsertUntil)
            counted[s], painted[s] = t.counted, t.painted
            @test count(==(:leader), kinds) == painted[s]
            @test sort(σ[σ .> 1169]) == 1170:(1169 + painted[s])             # one site per leader
        end
        # the spec owner's 20k-rep seeding simulation: 382.1 ± 2.7 painted, 7.9 ± 2.8 empty,
        # inventory 390 in 96.1 % (our 20k: 382.14 ± 2.73, 7.90 ± 2.74, 96.1 %); 3·SE ≈ 0.4
        @test abs(mean(painted) - 382.1) < 0.5
        @test abs(mean(counted .- painted) - 7.9) < 0.5
        @test all(>=(390), counted) && 0.93 < mean(counted .== 390) <= 0.995
        # `akeeb_state` paints this layout; negative control: `:retry` paints exactly the quota
        o = akeeb_state(; seed = 3)
        @test count(==(:follower), o[2].second) == 1169 && count(==(:leader), o[2].second) == painted[3]
        @test all(s -> count(==(:leader), akeeb_state(; seed = s, seeding = :retry)[2].second) == 390, 1:5)
        @test_throws ArgumentError akeeb_state(; seeding = :other)
    end
    @test Potts.lattice(GranerGlazier(; name = :big, lattice = (144, 144), T = 5.0)).dims == (144, 144)
    @test occursin("Graner & Glazier", string(@doc GranerGlazier))
end

# Every file runs in its own testset, all inside one: a file whose tests fail, or that
# throws while loading, is recorded and the later files still run (a bare `include` chain
# stopped at the first failing file's top-level testset). The outer testset throws at its
# end, so a failure still exits non-zero. `include` evaluates each file at top level, so its
# `const`s, structs and `@potts_model`s are globals as before.
const POTTSMODELS_TEST_FILES = [
    "mechanisms.jl", "papers.jl", "siblings.jl", "analysis.jl", "akeeb_u0.jl", "openvt_analysis.jl", "guardrails.jl", "tutorial_models.jl",
    "foam_src.jl", "callbacks_gc.jl",
    (joinpath("acceptance", f) for f in sort(filter(endswith(".jl"), readdir(joinpath(@__DIR__, "acceptance")))))...,
    # paper reproductions (ROADMAP Phase 6 "Acceptance for model reproductions"): the SMOKE
    # tier runs here, the FULL tier under POTTS_FULL_REPRODUCTION=true
    (joinpath("reproductions", f) for f in sort(filter(endswith(".jl"), readdir(joinpath(@__DIR__, "reproductions")))))...,
]

function pottsmodels_shards(files, n)
    weights = let p = joinpath(@__DIR__, "shard_weights.toml")
        isfile(p) ? Dict{String, Float64}(k => Float64(v) for (k, v) in TOML.parsefile(p)["seconds"]) : Dict{String, Float64}()
    end
    known = [weights[f] for f in files if haskey(weights, f)]
    fallback = isempty(known) ? 1.0 : sort(known)[cld(length(known), 2)]
    w(f) = get(weights, f, fallback)
    load = zeros(n)
    shard = Dict{String, Int}()
    for f in sort(files; by = f -> (-w(f), f))                # longest first, ties by name
        j = argmin(load)
        shard[f] = j
        load[j] += w(f)
    end
    return [[f for f in files if shard[f] == j] for j in 1:n]
end
const POTTSMODELS_SHARD_FILES = let fs = pottsmodels_shards(POTTSMODELS_TEST_FILES, POTTSMODELS_SHARD[2])[POTTSMODELS_SHARD[1]]
    # POTTSMODELS_SHARD_ORDER = reverse: run the shard's files last to first (a check for
    # state that one file leaves for a later one)
    get(ENV, "POTTSMODELS_SHARD_ORDER", "forward") == "reverse" ? reverse(fs) : fs
end
POTTSMODELS_SHARD[2] > 1 && @info "PottsModels shard $(POTTSMODELS_SHARD[1])/$(POTTSMODELS_SHARD[2]): $(length(POTTSMODELS_SHARD_FILES)) of $(length(POTTSMODELS_TEST_FILES)) files" POTTSMODELS_SHARD_FILES

# shared Base-only helpers that several files use (mechanisms.jl includes it;
# papers.jl calls `akeeb_metrics` without including it), loaded once whatever the shard order
include(joinpath(@__DIR__, "akeeb_metrics.jl"))
_pm_is_testset(ex) = ex isa Expr && ex.head === :macrocall && ex.args[1] === Symbol("@testset")

# Each file runs in a module of its own (TS1b; TS0 TS1-6), without editing the frozen files.
# The module sees what the old single Main gave the file: the runner's imports and helpers
# (above), and every name that an earlier file in the full order defined or imported, the
# latest definition winning. Its own definitions stay in its module, so a later file cannot
# rebind them. An earlier file that has not run in this process (another shard, or the reverse
# order) is loaded first with its top-level testsets dropped, as the shard preload did; so a
# shard still starts from the globals the single process had (e.g. siblings.jl uses
# mechanisms.jl's `split_cells`). In the files, `Main` means the file's module (the frozen
# files reach `Main.PottsDevices` and an earlier file's `Main.p63d_compactness`). A file in
# PM_IN_MAIN runs in Main instead when its tests run (only then: a definitions-only load of it
# goes to a module like any other), and the earlier names it lacks are set there as plain
# globals, since the file writes some of them itself.
module PMFiles end
const PM_MODULES = Dict{String, Module}()       # file => its module (full run or definitions only)
const PM_EXPORTS = Dict{String, Vector{Pair{Symbol, Any}}}()   # file => the names it offers later files
const PM_SKIP = (:eval, :include, :Base, :Core, :Main, :PMFiles, :PM_MODULES, :PM_EXPORTS, :PMEarlier)
_pm_names(m, skip = ()) = [n => getglobal(m, n) for n in names(m; all = true, imported = true)
                           if !startswith(string(n), '#') && !(n in PM_SKIP) && !(n in skip) && n !== nameof(m) && isdefined(m, n)]
const PM_RUNNER = _pm_names(@__MODULE__)
const PM_RUNNER_USINGS = :(using Test, Potts, PottsModels, Aqua, TOML; using Potts: CorePotts; using Statistics: mean)
# Frozen files whose recorded fingerprints and checkpoints hold their own definitions as
# `Main.<name>` (the generated code names them): they run in Main, as before, until T2 replaces
# those pins (R3). Main sees the earlier files' names through a module of their bindings.
const PM_IN_MAIN = Set(["acceptance/p6_0ai_integral_fold_hoist.jl", "acceptance/p6_0as_sweep_validation.jl",
    "acceptance/p6_0ax_gather_scan.jl", "acceptance/p6_0b2_link_followups.jl", "acceptance/p6_0c2_canonical_followups.jl",
    "acceptance/p6_0o_abstract_system.jl"])
_pm_main_to(m, ex) = ex === :Main ? m : ex isa Expr && ex.head !== :quote ? Expr(ex.head, (_pm_main_to(m, a) for a in ex.args)...) : ex
_pm_bulk_using(ex) = ex isa Expr && ex.head in (:using, :import) && all(a -> a isa Expr && a.head === :. && a.args[1] !== :., ex.args)
"""Names a file defines at top level (its own definitions win over an earlier file's)."""
function _pm_own(path)
    out = Set{Symbol}()
    name(x) = x isa Symbol ? x : x isa Expr && x.head in (:call, :where, :(::), :curly, :<:, :ref) ? name(x.args[1]) : nothing
    function walk(ex)
        ex isa Expr || return
        ex.head === :const && return walk(ex.args[1])
        if ex.head in (:(=), :function, :struct, :abstract, :module)
            t = ex.head in (:struct, :module) ? ex.args[2] : ex.args[1]
            t isa Expr && t.head === :tuple ? foreach(a -> (n = name(a); n === nothing || push!(out, n)), t.args) :
                (n = name(t); n === nothing || push!(out, n))
        elseif ex.head === :macro
            push!(out, Symbol("@", name(ex.args[1])))
        elseif ex.head === :macrocall
            m = last(split(string(ex.args[1]), '.'))          # Core.@doc -> @doc
            if m == "@potts_model" && length(ex.args) >= 3
                push!(out, ex.args[3])                          # @potts_model Name …
            elseif m in ("@testitem", "@testsetup", "@parameters", "@variables")
                nothing                                         # the item, the setup and the DSL own these
            else
                for a in ex.args[2:end]                         # a docstring wraps its definition in @doc
                    (a isa LineNumberNode || a isa String) && continue
                    walk(a)
                end
            end
        elseif ex.head === :block
            foreach(walk, ex.args)
        end
    end
    for ex in Meta.parseall(read(path, String)).args
        walk(ex)
    end
    return out
end

# Names a PM_IN_MAIN file declares at its top level: that file's own run declares them in Main,
# so they are never injected there (a plain global would block the file's `const` under the
# reverse shard order, where an in-Main file runs before the one that defines the name).
const PM_MAIN_OWN = let s = Set{Symbol}()
    for f in PM_IN_MAIN
        s = union(s, _pm_own(joinpath(@__DIR__, f)))
    end
    s
end

function _pm_module(f; defs_only)
    i = findfirst(==(f), POTTSMODELS_TEST_FILES)
    earlier = POTTSMODELS_TEST_FILES[1:(i - 1)]                # the providers, in the full order
    for g in earlier
        haskey(PM_MODULES, g) || _pm_module(g; defs_only = true)
    end
    path = joinpath(@__DIR__, f)
    inmain = f in PM_IN_MAIN && !defs_only                     # only a real run goes to Main
    name = Symbol(defs_only ? "defs_" : "", replace(f, r"[^A-Za-z0-9]" => "_"))
    m = inmain ? (@__MODULE__) : Core.eval(PMFiles, Expr(:module, true, name, Expr(:block)))
    before = inmain ? Set(first.(Base.invokelatest(_pm_names, m))) : Set{Symbol}()
    inmain || Core.eval(m, PM_RUNNER_USINGS)
    latest = inmain ? Dict{Symbol, Any}() : Dict{Symbol, Any}(PM_RUNNER)
    for g in earlier
        for ex in Meta.parseall(read(joinpath(@__DIR__, g), String)).args   # whole-package imports
            _pm_bulk_using(ex) && Core.eval(m, ex)
        end
        foreach(((n, v),) -> latest[n] = v, PM_EXPORTS[g])
    end
    own = _pm_own(path)
    # Names any in-Main file binds when it loads: statically (PM_MAIN_OWN) and by evaluating code
    # at load time (`include_string(@__MODULE__, raw"..." ...)`, generated code), which shows up in
    # its definitions-only load's exports. That file's own run declares them in Main, so injecting
    # one first makes the run fail ("cannot declare Main.X constant"/"cannot define function X").
    mainown = copy(PM_MAIN_OWN)
    for g in PM_IN_MAIN
        haskey(PM_EXPORTS, g) && union!(mainown, first.(PM_EXPORTS[g]))
    end
    foreach(n -> delete!(latest, n), union(own, mainown, before))
    if inmain
        # Main keeps a name it already has; a name it lacks becomes a plain global, as the old
        # single process had it. An imported binding would refuse the file's own top-level
        # writes (p6_0o assigns `s` inside a `@block`-style operand list), and so would a
        # `using` of a module of them.
        pre = union(before, keys(latest))
        for (n, v) in latest
            startswith(string(n), '@') && continue
            n in mainown && continue           # an in-Main file's own run declares it in Main
            isdefined(m, n) || Core.eval(m, Expr(:(=), n, QuoteNode(v)))
        end
    else
        e = Core.eval(m, Expr(:module, true, :PMEarlier,
            Expr(:block, (:(const $n = $(QuoteNode(v))) for (n, v) in latest)..., Expr(:export, keys(latest)...))))
        Core.eval(m, Expr(:using, Expr(:., :., nameof(e))))
        # an earlier file's name that a package the file uses also exports was the old Main's own
        # binding and won; here both are implicit imports, so import it explicitly
        clash = Base.invokelatest() do
            us = filter(!=(e), ccall(:jl_module_usings, Any, (Any,), m))
            [n for (n, v) in latest if any(M -> isdefined(M, n) && Base.isexported(M, n) && getglobal(M, n) !== v, us)]
        end
        isempty(clash) || Core.eval(m, Expr(:using, Expr(:(:), Expr(:., :., nameof(e)), (Expr(:., n) for n in clash)...)))
    end
    Base.include(ex -> defs_only && _pm_is_testset(ex) ? nothing : inmain ? ex : _pm_main_to(m, ex), m, path)
    PM_MODULES[f] = m
    # (the file's bindings are newer than this call's world: read them in the latest world)
    PM_EXPORTS[f] = Base.invokelatest() do
        inmain ? [p for p in _pm_names(m) if Base.binding_module(m, p[1]) === m && (p[1] in own || !(p[1] in pre))] :
            [p for p in _pm_names(m, before) if Base.binding_module(m, p[1]) !== e]
    end
    return m
end

@testset "PottsModels files" begin
    @testset "$f" for f in POTTSMODELS_SHARD_FILES
        _pm_module(f; defs_only = false)
    end
    POTTSMODELS_FIRST_SHARD && @testset "Aqua" begin
        Aqua.test_all(PottsModels; deps_compat = (; check_extras = false))
    end
end
