# sub-stream seeds come from
# one stable mixer, not from `seed + k`.
#
# Surface fixed by the coordinator:
#
#   Potts._substream_seed(seed::Integer, stream::Union{Symbol, AbstractString}) -> UInt64
#       (internal; not exported, not `public`)
#     The seed of sub-stream `stream` of top-level seed `seed` (0 ≤ seed ≤ typemax(UInt64)):
#         _substream_seed(seed, stream) =
#             _splitmix64(_splitmix64(UInt64(seed)) ⊻ UInt64(CorePotts.stream_id(stream)))
#     where `_splitmix64(x)` is one step of Vigna's SplitMix64 from state `x` (add the golden
#     gamma 0x9e3779b97f4a7c15, then the Stafford variant-13 finalizer with shifts 30/27/31
#     and multipliers 0xbf58476d1ce4e5b9 / 0x94d049bb133111eb; `_splitmix64(0) ==
#     0xe220a8397b1dcdaf`). The stream name goes through `CorePotts.stream_id` (FNV-1a of the
#     name, the repo's stable stream identity) because `hash(::Symbol)` is not stable across
#     sessions. Both steps are bijections of UInt64, so for a fixed stream distinct seeds
#     give distinct sub-seeds, and for a fixed seed distinct stream ids do too. The formula is
#     pinned (an independent reference below) so that a sub-stream is the same on every
#     Julia version (D-075, StableRNG only).
#
#   Every place in src/, ext/, lib/*/src/, lib/*/ext/ and lib/PottsModels/reproductions/
#   that derives a sub-stream seed for StableRNG / Xoshiro / MersenneTwister uses it.
#   At commit a5a2819 the only such site is
#       lib/PottsModels/src/akeeb.jl  akeeb_state: rng = StableRNG(seed + 1)   (the clocks)
#   Top-level seeds passed straight through (`StableRNG(l.seed)` in Scattered, InsertUntil,
#   VoronoiBall; `MersenneTwister(seed)` in merks_state; CorePotts' Philox `RNGKey`) are not
#   derivations and are unchanged.
#
#   akeeb_state(; lattice, pp, seed, slab, seeding)
#     σ and kinds unchanged: `layout(akeeb_layout(; lattice, seed, slab, seeding), lattice)`,
#     the leaders drawn by InsertUntil from StableRNG(seed) (so the 16 frozen digests of
#     acceptance/layout_protocol_tests.jl, which hash σ and check kinds only, still hold).
#     The clocks keep their recipe (one cell at a time in id order; a leader draws nothing
#     and gets −1; a follower draws u = rand(rng), −1 if u > pp, else
#     Float64(rand(rng, 0:74))) on the stream
#         StableRNG(Potts._substream_seed(seed, :clock))
#     instead of StableRNG(seed + 1). The clocks therefore change per seed (expected); the
#     law does not.
#
# How the structural check works (a). It parses the source files (Meta.parseall) and walks
# the syntax trees, so comments and docstrings never match and formatting does not matter.
# It flags (1) an RNG constructor or `seed!` whose seed argument is anything but a name, a
# field, a literal, an integer conversion of one of those, or a `_substream_seed(...)` call,
# and (2) any arithmetic (+ - * ⊻ xor | << >> and dotted forms, `+=`) with an operand
# named like a seed (`seed`, `l.seed`, `UInt64(seed)`, …), outside the bodies of
# `_substream_seed` and `_splitmix64*` themselves. (2) catches the two-step form
# `s = seed + 1; StableRNG(s)`. A lowered-code check was not chosen: it needs every method
# and argument type up front and would miss files nobody calls in the test. Limitation: an
# arithmetic derivation on a variable whose name does not contain "seed" is not seen.
#
# How the statistical accept works (b). For N consecutive top-level seeds s, s + 1, it takes
# the first Float64 draw of each sub-stream at s and at s + 1 and requires both
#   - |√N · r| ≤ 5 (Pearson r; under independence √N r → N(0, 1), two-sided tail 5.7e-7), and
#   - χ² of the 100-bin histogram of mod(v − u, 1) ≤ the Wilson–Hilferty 1 − 1e-6 quantile
#     of χ²₉₉ (≈ 181). Independent uniforms give a uniform difference; StableRNG's
#     consecutive-seed coupling is a constant shift (D-082), so the difference piles up in
#     one or two bins. Pearson alone can miss a shift (its r is 1 − 6c(1 − c), zero near
#     c ≈ 0.21).
# 26 statistics in all, so a mixer with truly independent outputs fails one with
# probability ≲ 3e-5. The mixer is deterministic, so the outcome is fixed by the pinned
# formula (it passes with margin when written: |√N r| ≤ 1.7, χ² ≤ 124). Negative controls:
# today's `seed + 1` derivation and bare StableRNG(s) vs StableRNG(s + 1) fail the same test.

@testsetup module SubstreamSeedsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using StableRNGs: StableRNG
# D-138: PottsModels no longer depends on StableRNGs

# ---------------------------------------------------------------------------------------------
# Independent reference of the pinned mixer
# ---------------------------------------------------------------------------------------------
const GAMMA = 0x9e3779b97f4a7c15
function substream_splitmix64(x::UInt64)
    z = x + GAMMA
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end
fnv(name) = (
    h = 0x811c9dc5; for b in codeunits(String(name))
        h = (h ⊻ b) * 0x01000193
    end; h
)
ref(seed, stream) = substream_splitmix64(substream_splitmix64(UInt64(seed)) ⊻ UInt64(fnv(stream)))
has() = isdefined(Potts, :_substream_seed)
mix(seed, stream) = Potts._substream_seed(seed, stream)
# ---------------------------------------------------------------------------------------------
# Statistics (no Statistics dependency in this test environment)
# ---------------------------------------------------------------------------------------------
substream_mean(x) = sum(x) / length(x)
function substream_cor(a, b)
    ma, mb = substream_mean(a), substream_mean(b)
    return sum((a .- ma) .* (b .- mb)) / sqrt(sum(abs2, a .- ma) * sum(abs2, b .- mb))
end
const SUBSTREAM_Z = 5.0
# |√N r| bound, two-sided tail 5.7e-7
# Wilson–Hilferty upper quantile of χ²_k at tail 1e-6 (z = 4.753)
chi2_bound(k; z = 4.753) = k * (1 - 2 / (9k) + z * sqrt(2 / (9k)))^3
chi2(counts, N) = (e = N / length(counts); sum(c -> (c - e)^2 / e, counts))
"""Uniform draws u (at s) and v (at s + 1): Pearson z, χ² of mod(v − u, 1), and the verdict."""
function uniform_pair(u, v; bins = 100)
    N = length(u)
    zr = substream_cor(u, v) * sqrt(N)
    c = zeros(Int, bins)
    for (a, b) in zip(u, v)
        c[min(bins, floor(Int, mod(b - a, 1.0) * bins) + 1)] += 1
    end
    chi = chi2(c, N)
    return (; zr, chi, ok = abs(zr) <= SUBSTREAM_Z && chi <= chi2_bound(bins - 1))
end
"""Draws a, b uniform on 0:(m − 1): Pearson z, χ² of mod(b − a, m), and the verdict."""
function discrete_pair(a, b, m)
    N = length(a)
    zr = substream_cor(a, b) * sqrt(N)
    c = zeros(Int, m)
    for (x, y) in zip(a, b)
        c[mod(Int(y) - Int(x), m) + 1] += 1
    end
    chi = chi2(c, N)
    return (; zr, chi, ok = abs(zr) <= SUBSTREAM_Z && chi <= chi2_bound(m - 1))
end
substream_first(x) = rand(StableRNG(x))
# first draws of sub-stream f at seeds s and of sub-stream g at s + 1, over the block
substream_consecutive(f, g, seeds) = uniform_pair([substream_first(f(s)) for s in seeds], [substream_first(g(s + 1)) for s in seeds])
const SUBSTREAM_N = 20_000
const BLOCKS = (UInt64(0), UInt64(0x05cd2609), UInt64(2)^63)
# zero, Akeeb's default, high bit

# ---------------------------------------------------------------------------------------------
# Structural scan
# ---------------------------------------------------------------------------------------------
const RNGS = (:StableRNG, :LehmerRNG, :Xoshiro, :MersenneTwister)
const ARITH = (:+, :-, :*, :⊻, :xor, :|, :<<, :>>, :>>>, :.+, :.-, :.*, :.⊻)
const CONV = (:UInt64, :Int, :Int64, :UInt, :UInt32, :Int32, :UInt128, :convert, :(%))
# the name in `M.:name`; nothing when it is not a Symbol (`M.:($f)` in an `@eval` loop)
qname(x) = x isa Expr && x.head === :. && length(x.args) == 2 && x.args[2] isa QuoteNode &&
    x.args[2].value isa Symbol ? x.args[2].value : nothing
substream_name(f) = f isa Symbol ? f : f isa GlobalRef ? f.name : qname(f)
iscall(ex, names) = ex isa Expr && ex.head === :call && substream_name(ex.args[1]) in names
seedlike(x) = (n = x isa Symbol ? x : qname(x); n isa Symbol && occursin("seed", lowercase(String(n)))) ||
    (iscall(x, CONV) && any(seedlike, x.args[2:end]))
plain(x) = x isa Symbol || x isa Integer || x isa QuoteNode ||
    (x isa Expr && x.head === :. && length(x.args) == 2 && x.args[2] isa QuoteNode) ||
    iscall(x, (:_substream_seed,)) ||
    (iscall(x, CONV) && all(plain, x.args[2:end]))
function defname(ex)
    ex isa Expr && ex.head in (:function, :(=)) || return nothing
    sig = ex.args[1]
    while sig isa Expr && sig.head in (:where, :(::))
        sig = sig.args[1]
    end
    sig isa Expr && sig.head === :call || return nothing
    return substream_name(sig.args[1])
end
exempt(ex) = (n = defname(ex); n !== nothing && (n === :_substream_seed || startswith(String(n), "_splitmix64")))
"""Every flagged site of one parsed source as (line, kind, expression)."""
function scan(src::AbstractString)
    hits = Tuple{Int, Symbol, String}[]
    line = Ref(0)
    function walk(ex)
        if ex isa LineNumberNode
            line[] = ex.line
            return
        end
        ex isa Expr || return
        exempt(ex) && return
        if ex.head === :call
            n = substream_name(ex.args[1])
            args = [a for a in ex.args[2:end] if !(a isa Expr && a.head in (:parameters, :kw))]
            if n in RNGS && !isempty(args) && !plain(args[1])
                push!(hits, (line[], :rng_argument, string(ex)))
            elseif n === :seed! && length(args) >= 2 && !plain(args[2])
                push!(hits, (line[], :rng_argument, string(ex)))
            elseif n in ARITH && any(seedlike, args)
                push!(hits, (line[], :seed_arithmetic, string(ex)))
            end
        elseif ex.head in (:+=, :-=, :⊻=, :*=) && seedlike(ex.args[1])
            push!(hits, (line[], :seed_arithmetic, string(ex)))
        end
        foreach(walk, ex.args)
    end
    walk(Meta.parseall(src))
    return hits
end
"""Count of RNG constructor / seed! call sites in one parsed source (non-vacuity)."""
function rng_sites(src::AbstractString)
    n = Ref(0)
    walk(ex) = ex isa Expr && ((iscall(ex, (RNGS..., :seed!)) && length(ex.args) >= 2 && (n[] += 1)); foreach(walk, ex.args))
    walk(Meta.parseall(src))
    return n[]
end
const ROOT = pkgdir(Potts)
function substream_files()
    dirs = [joinpath(ROOT, "src"), joinpath(ROOT, "ext"), joinpath(ROOT, "lib", "PottsModels", "reproductions")]
    for lib in readdir(joinpath(ROOT, "lib"); join = true)
        isdir(lib) && append!(dirs, (joinpath(lib, "src"), joinpath(lib, "ext")))
    end
    files = String[]
    for d in dirs
        isdir(d) || continue
        for (root, _, fs) in walkdir(d), f in fs
            endswith(f, ".jl") && push!(files, joinpath(root, f))
        end
    end
    return sort(files)
end
# ---------------------------------------------------------------------------------------------
# (b, end to end) and (c): akeeb_state
# ---------------------------------------------------------------------------------------------
substream_get(op, key) = only(last(p) for p in op if isequal(first(p), key))
recipe(kinds, pp, rng) = [k === :leader || rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74)) for k in kinds]
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "substream seeds: the mixer is the pinned splitmix64 of (seed, stream)" setup = [SubstreamSeedsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------------
    # (a) one helper, used at every derivation site
    # ---------------------------------------------------------------------------------------------
    @testset "substream seeds: the mixer is the pinned splitmix64 of (seed, stream)" begin
        # the reference itself: Vigna's SplitMix64 from state 0, and the repo's stream identity
        @test substream_splitmix64(UInt64(0)) == 0xe220a8397b1dcdaf
        @test fnv(:clock) == CorePotts.stream_id(:clock) == CorePotts.stream_id("clock")
        @test has()
        if has()
            @test !(:_substream_seed in names(Potts))                      # internal: not exported
            @test !Base.ispublic(Potts, :_substream_seed)                   # nor public
            for seed in (0, 1, 2, 0x05cd2609, typemax(UInt64) - 1, typemax(UInt64)), stream in (:clock, :points, :kinds, :a)
                x = mix(seed, stream)
                @test x isa UInt64
                @test x === ref(seed, stream)
                @test mix(seed, String(stream)) === x               # Symbol and String name the same stream
                @test mix(UInt64(seed), stream) === x               # the integer type does not matter
            end
            @test mix(1, :clock) === mix(1, :clock)            # deterministic
            # injective in each argument (on samples) and no derivation by an offset
            @test allunique(mix(s, :clock) for s in 0:10_000)
            @test allunique(mix(7, s) for s in (:clock, :points, :kinds, :orientations, :widths, :a, :b))
            @test all(s -> mix(s, :clock) - UInt64(s) != mix(s + 1, :clock) - UInt64(s + 1), 0:1000)
        end
    end
end

@testitem "substream seeds: no sub-stream seed is derived by arithmetic on a seed" setup = [SubstreamSeedsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "substream seeds: no sub-stream seed is derived by arithmetic on a seed" begin
        files = substream_files()
        # non-vacuous: the scan sees the package sources and the known RNG sites
        @test any(endswith(joinpath("src", "layouts.jl")), files)
        @test any(endswith(joinpath("PottsModels", "src", "akeeb.jl")), files)
        @test any(endswith(joinpath("CorePotts", "src", "rng.jl")), files)
        @test sum(f -> rng_sites(read(f, String)), files) >= 4   # Scattered, InsertUntil, VoronoiBall, akeeb (merks draws through Scattered since D-153)
        hits = [(relpath(f, ROOT), h...) for f in files for h in scan(read(f, String))]
        @test isempty(hits)
        isempty(hits) || @info "substream seeds: seed derivations by arithmetic" hits
        # akeeb_state's clocks go through the mixer (directly, or through the public
        # `Potts.layer_rng(seed, stream)` that wraps it, D-138)
        akeeb = Meta.parseall(read(joinpath(pkgdir(PottsModels), "src", "akeeb.jl"), String))
        body = nothing
        walkdef(ex) = ex isa Expr && (defname(ex) === :akeeb_state ? (body = ex) : foreach(walkdef, ex.args))
        walkdef(akeeb)
        @test body !== nothing
        uses = Ref(0)
        count_uses(ex) = ex isa Expr && ((iscall(ex, (:_substream_seed,)) || (iscall(ex, (:layer_rng,)) && length(ex.args) >= 3)) && (uses[] += 1); foreach(count_uses, ex.args))
        count_uses(body)
        @test uses[] >= 1

        # negative controls: the scan flags today's derivation, the two-step form and the
        # field form, and passes the mixer, plain seeds and the mixer's own body
        @test sort([h[2] for h in scan("rng = StableRNG(seed + 1)")]) == [:rng_argument, :seed_arithmetic]
        @test !isempty(scan("f(seed) = (s = seed + 1; Xoshiro(s))"))
        @test !isempty(scan("g(l) = MersenneTwister(l.seed + k)"))
        @test !isempty(scan("g(l) = StableRNG(UInt64(l.seed) ⊻ 0x1)"))
        @test !isempty(scan("g(l) = StableRNG(hash(l.seed))"))                   # rng_argument
        @test !isempty(scan("g(seed) = (seed += 2; seed)"))
        @test !isempty(scan("g(rng, s) = Random.seed!(rng, s * 3)"))
        @test isempty(scan("rng = StableRNG(Potts._substream_seed(seed, :clock))"))
        @test isempty(scan("rng = StableRNG(_substream_seed(l.seed, :points)); r2 = StableRNG(l.seed); r3 = MersenneTwister(seed)"))
        @test isempty(scan("_substream_seed(seed::Integer, s) = _splitmix64(_splitmix64(UInt64(seed)) ⊻ UInt64(stream_id(s)))"))
        @test isempty(scan("function _splitmix64(x::UInt64)\n z = x + 0x9e3779b97f4a7c15\n z\nend"))
        @test isempty(scan("\"\"\"the clocks use `StableRNG(seed + 1)`\"\"\"\nf(x) = x\n# StableRNG(seed + 1)"))  # docs and comments
        @test isempty(scan("0 <= seed <= typemax(UInt64) || throw(ArgumentError(\"bad\"))"))
    end
end

@testitem "substream seeds: first draws of sub-streams at consecutive seeds are uncorrelated" setup = [SubstreamSeedsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------------
    # (b) consecutive top-level seeds give uncorrelated first draws of each sub-stream
    # ---------------------------------------------------------------------------------------------
    @testset "substream seeds: first draws of sub-streams at consecutive seeds are uncorrelated" begin
        # negative controls first: the same test rejects today's derivation and the bare
        # consecutive StableRNG streams (the D-082 coupling), so it is not vacuous
        root = s -> s                                  # a layer's own stream (InsertUntil's leaders)
        old = s -> s + 1                               # today's clock stream, StableRNG(seed + 1)
        for base in BLOCKS
            seeds = base .+ UInt64.(0:(SUBSTREAM_N - 1))
            @test !substream_consecutive(old, old, seeds).ok          # clocks(s) vs clocks(s + 1): a constant shift
            @test !substream_consecutive(old, root, seeds).ok         # clocks(s) IS leaders(s + 1)
            @test substream_consecutive(old, root, seeds).zr > 100
            @test !substream_consecutive(root, root, seeds).ok        # StableRNG(s) vs StableRNG(s + 1)
        end
        @test has()
        if has()
            clock = s -> mix(s, :clock)
            a, b = s -> mix(s, :points), s -> mix(s, :kinds)
            for base in BLOCKS
                seeds = base .+ UInt64.(0:(SUBSTREAM_N - 1))
                for (f, g, what) in (
                        (clock, clock, "clock(s) ~ clock(s+1)"), (clock, root, "clock(s) ~ leaders(s+1)"),
                        (root, clock, "leaders(s) ~ clock(s+1)"), (a, b, "points(s) ~ kinds(s+1)"),
                    )
                    r = substream_consecutive(f, g, seeds)
                    @test r.ok
                    r.ok || @info "substream seeds: coupled sub-streams" what base r.zr r.chi
                end
            end
        end
    end
end

@testitem "substream seeds: akeeb_state's clocks at consecutive seeds are uncorrelated" setup = [SubstreamSeedsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "substream seeds: akeeb_state's clocks at consecutive seeds are uncorrelated" begin
        # At pp = 1 every follower draws u (never > 1) and then its clock from 0:74; id 1 is a
        # follower, so clock[1] is the clock stream's second draw. 4001 seeds of the 99 × 60 slab.
        lat, N = (99, 60), 4000
        sts = [akeeb_state(; lattice = lat, pp = 1.0, seed = s) for s in 0:N]
        @test all(o -> substream_get(o, kind)[1] === :follower, sts)
        v = [substream_get(o, :clock)[1] for o in sts]
        @test all(x -> x in 0:74, v)
        r = discrete_pair(v[1:(end - 1)], v[2:end], 75)
        @test r.ok
        r.ok || @info "substream seeds: akeeb clocks coupled across seeds" r.zr r.chi bound = chi2_bound(74)
        # negative control: the same statistic on today's recipe, StableRNG(seed + 1), fails
        w = [recipe(substream_get(o, kind)[1:1], 1.0, StableRNG(s + 1))[1] for (s, o) in zip(0:N, sts)]
        @test !discrete_pair(w[1:(end - 1)], w[2:end], 75).ok
    end
end

@testitem "substream seeds: akeeb_state is deterministic per seed, cells unchanged, clock law unchanged" setup = [SubstreamSeedsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "substream seeds: akeeb_state is deterministic per seed, cells unchanged, clock law unchanged" begin
        for (lat, seed, pp, seeding) in (
                ((500, 300), 0x05cd2609, 0.5, :authors), ((99, 60), 1, 0.5, :authors),
                ((99, 60), 2, 0.9, :retry), ((99, 60), 4, 0.0, :authors), ((99, 60), 3, 1.0, :retry),
            )
            a = akeeb_state(; lattice = lat, seed, pp, seeding)
            b = akeeb_state(; lattice = lat, seed, pp, seeding)
            @test all(i -> isequal(a[i], b[i]), 1:5)                                    # deterministic per seed
            @test [first(p) for p in a[3:5]] == [:clock, :rate, :cue]
            # σ and kinds: still the layout from the top-level seed (the leader stream is not moved)
            point = layout(akeeb_layout(; lattice = lat, seed, seeding), lat)
            @test substream_get(a, ownership) == point[1].second && substream_get(a, kind) == point[2].second
            ks = substream_get(a, kind)
            clocks = substream_get(a, :clock)
            # the law: today's recipe, in id order, on the mixed clock stream
            if has()
                @test clocks == recipe(ks, pp, StableRNG(mix(seed, :clock)))
                # negative control: the oracle sees the stream (another sub-stream name differs)
                pp > 0 && @test clocks != recipe(ks, pp, StableRNG(mix(seed, :clocks)))
            else
                @test has()
            end
            # no longer today's stream
            pp > 0 && @test clocks != recipe(ks, pp, StableRNG(seed + 1))
            @test substream_get(a, :rate) == [k === :leader ? 0.0 : 0.015 for k in ks]
            @test substream_get(a, :cue) == [Float64(y - 1) for x in 1:lat[1], y in 1:lat[2]]
            @test all(c -> c == -1.0 || (isinteger(c) && 0 <= c <= 74), clocks)
            @test all(i -> ks[i] !== :leader || clocks[i] == -1.0, eachindex(ks))
            pp == 0 && @test all(==(-1.0), clocks)
            pp == 1 && @test all(i -> ks[i] === :leader || clocks[i] >= 0, eachindex(ks))
        end
        # distinct seeds give distinct clocks
        cs = [substream_get(akeeb_state(; lattice = (99, 60), seed), :clock) for seed in 1:4]
        @test length(unique(cs)) == 4
        # the law in distribution (pp = 0.5, published size): the clocked fraction of followers
        # is 1/2 and the clock is uniform on 0:74. 1169 followers: SD of the fraction 0.0146,
        # bound 5 SD; χ² over 75 values pooled over seeds 1:8 (≈ 4700 clocks) at tail 1e-6.
        pooled = Float64[]
        for seed in 1:8
            o = akeeb_state(; lattice = (500, 300), pp = 0.5, seed)
            ks, cl = substream_get(o, kind), substream_get(o, :clock)
            f = [cl[i] for i in eachindex(ks) if ks[i] === :follower]
            @test abs(count(>=(0), f) / length(f) - 0.5) <= 5 * sqrt(0.25 / length(f))
            append!(pooled, filter(>=(0), f))
        end
        h = zeros(Int, 75)
        foreach(c -> h[Int(c) + 1] += 1, pooled)
        @test chi2(h, length(pooled)) <= chi2_bound(74)
    end
end
