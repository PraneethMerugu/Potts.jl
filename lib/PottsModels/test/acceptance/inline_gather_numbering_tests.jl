# inline gathers outside the copy step are numbered.
# Decision: D-132 (amends D-107, after D-124).
#
# The defect. The compiler names each inline gather relation `gather1`,
# `gather2`, … (D-107) by scanning `all_exprs` (`src/compile.jl`), the expressions of the copy
# step and of the MCS-boundary updates, ODEs, fields, ticks and the temperature. Six places
# that also lower inline gathers are not in that scan, so their spec has no name and the
# lowering fails with `KeyError: key <spec> not found` (at build, or for `@observed` at the
# first query). Measured on fe057508 (12×12 periodic, a fold `count(owner[n] == … for n in
# R(site))`):
#  - `@divide … when = …`            KeyError at build   (named fold `far(40)`: works)
#  - `@divide … x => <expr>`         KeyError at build   (named: works)
#  - `@link … when = …`              KeyError at build   (named: works)
#  - `@unlink … when = …`            KeyError at build   (named: works)
#  - `@energy edges(rel) => …`       KeyError at build   (named: works)
#  - `@observed o ~ …`               KeyError at `observe` (named: works)
# A gather shared with a scanned site (`Moore(1)` in an energy and in a division `when`)
# works today: the division reads the energy's `gather1`, which is the same relation. No
# site silently reads another site's relation: every miss is a loud KeyError.
# Already scanned (work today, not retested here beyond controls): cell, cluster, contact and
# site energies, drives, expression constraints, updates (all phases), field PDEs, cell and
# model ODEs, the temperature, discrete ticks.
# Out of scope: `along = (…)` with any non-constant expression (named or inline) fails with
# `MethodError: Float64(::Num)`; a division plane is a constant (not a gather question).
#
# Rule pinned here (D-132): every inline gather the compiler lowers is numbered, including
# those in division `when` and state rules, `@link`/`@unlink` `when`, `edges(rel)` energies
# and `@observed` quantities. An inline gather behaves exactly like the named fold of the same
# spec (same values, same trajectory under a fixed seed). Several sites reading different
# specs read different relations (each its own value). Their relations are fingerprinted
# under D-124 like any other gather read by generated code (division and link `when`, rules
# and edge energies are generated code); a relation read only by `@observed` is not, and an
# `@observed` quantity never changes a model's fingerprint (it also does not renumber the
# gathers of the generated code). Models whose gathers were all already scanned keep their
# fingerprints, as do named relations at the new sites and every published model.
#
# Amended under D-209. The cell and edge energy fixtures originally folded
# `count(owner[n] == who for n in R(site))`, a σ-dependent gather that D-209 refuses at
# `mtkcompile` (its ΔH was wrong). They now fold `count(q[n] == who for n in R(site))`, with
# `q` the initial owner map set from the operating point (a static site value; every
# fixture's operating point carries it). On the initial state, and on every state of the
# vetoed fixtures, the value is the old count, so every energy below is unchanged; the
# numbering question (which spec gets which `gatherN`) is the same. Division, link, observed
# and drive gathers keep `owner[n]` (boundary and copy-step reads D-209 allows). The two
# pinned fixtures whose energy changed form ("at energy Moore(1)(40)", "edge far=Moore(1)")
# are re-pinned with values recorded on 487fda85; no other pin moves.
#
# Fixtures. 12×12 periodic, Moore(1) lattice neighbourhood, two 3×3 cells of kind A,
# `(volume - 9)^2`, Metropolis T = 2 (the `relation_fingerprint_tests.jl` template). "Static" fixtures add
# `@constraint source < 0`, which vetoes every copy, so the state changes only through
# divisions and links and every count below is exact:
#   :apart  cell 1 = [2:4, 2:4], cell 2 = [6:8, 2:4]   (a gap column x = 5)
#   :touch  cell 1 = [2:4, 2:4], cell 2 = [5:7, 2:4]   (they touch: `new_contact`)
#   :relation_fingerprint  cell 1 = [2:4, 2:4], cell 2 = [7:9, 7:9]   (the `relation_fingerprint_tests.jl` layout)
# Site 40 = (4, 4) (a corner of cell 1), 29 = (5, 3) (the gap / the boundary), 143 = (11, 12)
# (no cell within reach). EuclideanBall(r): 0 < d² ≤ r²; Moore(k): Chebyshev 1..k; VonNeumann(1):
# the four axis neighbours. Counts by hand (checked against a brute-force oracle below):
#   around 40, :apart   EuclideanBall(2.0)  c1 5 [(2,4),(3,4),(4,2),(4,3),(3,3)]  c2 1 [(6,4)]
#                       EuclideanBall(3.0)  c1 8                                   c2 4 [(6,2),(6,3),(6,4),(7,4)]
#                       Moore(1)   c1 3                                   c2 0
#                       Moore(2)   c1 8                                   c2 3 [(6,2),(6,3),(6,4)]
#   around 40, :touch   EuclideanBall(2.0)  c1 5  c2 3 [(5,3),(5,4),(6,4)]           sum  8
#                       EuclideanBall(3.0)  c1 8  c2 7 [+ (5,2),(6,3),(6,2),(7,4)]   sum 15
#                       Moore(1)   c1 3  c2 2 [(5,3),(5,4)]                 sum  5
#                       Moore(2)   c1 8  c2 6 [(5..6, 2..4)]                sum 14
#                       VonNeumann(1) c1 2 c2 1                             sum  3
#   around 29, owner 2, :apart   Moore(1) 3, VonNeumann(1) 1, Moore(2) 6
#   around 40, :relation_fingerprint   Moore(1) c1 3, Moore(2) c1 8, VonNeumann(1) c1 2 (c2 0 for all)
# Division `when = (y == 0) & (mcs * count(owner[n] == id for n in R(40)) >= 12)` with
# `y => mcs + 1` fires for a cell at the first MCS m with m·count ≥ 12 and records m + 1:
# EuclideanBall(2.0) c1 m = 3, c2 m = 12; EuclideanBall(3.0) c1 m = 2, c2 m = 3; Moore(1) c1 m = 4, c2 never.
# Link `when = new_contact(a, b) && mcs * (count_a + count_b) >= 24` (and the same `@unlink`
# on a linked pair) fires at m = 3 (EuclideanBall(2.0), 8), 2 (EuclideanBall(3.0), 15), 5 (Moore(1), 5).

@testsetup module InlineGatherNumberingSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# Fixtures
const LAYOUTS = Dict(
    :apart => ((2:4, 2:4), (6:8, 2:4)),
    :touch => ((2:4, 2:4), (5:7, 2:4)),
    :relation_fingerprint => ((2:4, 2:4), (7:9, 7:9)),
)
"""A fold counting the sites of `who` in relation `r` (an inline spec call or a name) around `site`."""
gather_g(r, who = :id; site = 40) = :(count(owner[n] == $who for n in $r($site)))
gather_pair(r; site = 40) = :($(gather_g(r, :a; site)) + $(gather_g(r, :b; site)))
# the same folds over the static site value `q` (the initial owner map, from the operating
# point): the energy form allowed under D-209; every energy fixture uses it
gather_s(r, who = :id; site = 40) = :(count(q[n] == $who for n in $r($site)))
spair(r; site = 40) = :($(gather_s(r, :a; site)) + $(gather_s(r, :b; site)))
const STATIC = :(@constraint source < 0)
const BOND = :(@relationship bond(cell, cell) capacity = 1)
function gather_divwhen(r; site = 40)
    return [
        STATIC,
        :(@divide cells(A) when = (y == 0.0) & (mcs * $(gather_g(r; site)) >= 12), y => mcs + 1.0)
    ]
end
function gather_divrule(r)
    return [
        STATIC,
        :(@divide cells(A) when = (y == 0.0) & (id == 1) & (mcs == 2), y => 1.0 + $(gather_g(r, 2; site = 29)))
    ]
end
gather_link(r; site = 40) = [BOND, STATIC, :(@link bond when = new_contact(a, b) && (mcs * $(gather_pair(r; site)) >= 24))]
gather_unlink(r) = [BOND, STATIC, :(@unlink bond when = mcs * $(gather_pair(r)) >= 24)]
gather_edge(r) = [BOND, STATIC, :(@energy edges(bond) => 0.1 * $(spair(r)))]
gather_obs(r) = [:(@observed o(cell) ~ $(gather_g(r)))]
# dynamic (no veto): the same sites under copies, for the inline/named equivalence
dyn_div(r) = [:(@divide cells(A) when = (y == 0.0) & ($(gather_g(r)) >= 3), y => mcs + 1.0 + $(gather_g(r, 2; site = 29)))]
function dyn_link(r)
    return [
        BOND, :(@link bond when = new_contact(a, b) && ($(gather_pair(r)) >= 5)),
        :(@unlink bond when = $(gather_pair(r)) <= 3), :(@energy edges(bond) => 2.0 * $(spair(r)))
    ]
end
# label => (layout, @relations body or nothing, statements after the volume energy)
const FIXTURES = [
    "sq" => (:relation_fingerprint, nothing, []),
    # division when
    "divwhen EuclideanBall(2.0)" => (:apart, nothing, gather_divwhen(:(EuclideanBall(2.0)))),
    "divwhen EuclideanBall(3.0)" => (:apart, nothing, gather_divwhen(:(EuclideanBall(3.0)))),
    "divwhen Moore(1)" => (:apart, nothing, gather_divwhen(:(Moore(1)))),
    "divwhen NeighborOrder(2)" => (:apart, nothing, gather_divwhen(:(NeighborOrder(2)))),
    "divwhen EuclideanBall(2.0) empty" => (:apart, nothing, gather_divwhen(:(EuclideanBall(2.0)); site = 143)),
    "divwhen far=EuclideanBall(2.0)" => (:apart, :(far = EuclideanBall(2.0)), gather_divwhen(:far)),
    "divwhen far=EuclideanBall(3.0)" => (:apart, :(far = EuclideanBall(3.0)), gather_divwhen(:far)),
    "divwhen gather-free" => (
        :apart, nothing, [
            STATIC,
            :(@divide cells(A) when = (y == 0.0) & (mcs * volume >= 27), y => mcs + 1.0)
        ]
    ),
    # division state rule
    "divrule Moore(1)" => (:apart, nothing, gather_divrule(:(Moore(1)))),
    "divrule VonNeumann(1)" => (:apart, nothing, gather_divrule(:(VonNeumann(1)))),
    "divrule Moore(2)" => (:apart, nothing, gather_divrule(:(Moore(2)))),
    "divrule far=Moore(1)" => (:apart, :(far = Moore(1)), gather_divrule(:far)),
    # link / unlink when
    "link EuclideanBall(2.0)" => (:touch, nothing, gather_link(:(EuclideanBall(2.0)))),
    "link EuclideanBall(3.0)" => (:touch, nothing, gather_link(:(EuclideanBall(3.0)))),
    "link Moore(1)" => (:touch, nothing, gather_link(:(Moore(1)))),
    "link EuclideanBall(2.0) empty" => (:touch, nothing, gather_link(:(EuclideanBall(2.0)); site = 143)),
    "link far=EuclideanBall(2.0)" => (:touch, :(far = EuclideanBall(2.0)), gather_link(:far)),
    "link far=EuclideanBall(3.0)" => (:touch, :(far = EuclideanBall(3.0)), gather_link(:far)),
    "unlink EuclideanBall(2.0)" => (:touch, nothing, gather_unlink(:(EuclideanBall(2.0)))),
    "unlink EuclideanBall(3.0)" => (:touch, nothing, gather_unlink(:(EuclideanBall(3.0)))),
    "unlink far=EuclideanBall(2.0)" => (:touch, :(far = EuclideanBall(2.0)), gather_unlink(:far)),
    # edge energy
    "edge Moore(1)" => (:touch, nothing, gather_edge(:(Moore(1)))),
    "edge Moore(2)" => (:touch, nothing, gather_edge(:(Moore(2)))),
    "edge VonNeumann(1)" => (:touch, nothing, gather_edge(:(VonNeumann(1)))),
    "edge far=Moore(1)" => (:touch, :(far = Moore(1)), gather_edge(:far)),
    # observed
    "obs Moore(1)" => (:relation_fingerprint, nothing, gather_obs(:(Moore(1)))),
    "obs Moore(2)" => (:relation_fingerprint, nothing, gather_obs(:(Moore(2)))),
    "obs far=Moore(1)" => (:relation_fingerprint, :(far = Moore(1)), gather_obs(:far)),
    "energy Moore(1)" => (:relation_fingerprint, nothing, [:(@energy cells => 0.1 * $(gather_s(:(Moore(1)))))]),
    "energy Moore(1) + obs VonNeumann(1)" => (
        :relation_fingerprint, nothing,
        [:(@energy cells => 0.1 * $(gather_s(:(Moore(1))))), gather_obs(:(VonNeumann(1)))...]
    ),
    "energy Moore(1) + obs Moore(1)" => (:relation_fingerprint, nothing, [:(@energy cells => 0.1 * $(gather_s(:(Moore(1))))), gather_obs(:(Moore(1)))...]),
    # several sites, several specs
    "all apart" => (
        :apart, nothing, [
            STATIC, :(@energy cells => 0.01 * $(gather_s(:(Moore(2))))),
            :(
                @divide cells(A) when = (y == 0.0) & (mcs * $(gather_g(:(EuclideanBall(2.0)))) >= 12),
                    y => mcs + 1.0 + 100 * $(gather_g(:(VonNeumann(1)), 2; site = 29))
            )
        ]
    ),
    "all touch" => (
        :touch, nothing, [
            BOND, STATIC, :(@energy cells => 0.01 * $(gather_s(:(Moore(1))))),
            :(@link bond when = new_contact(a, b) && (mcs * $(gather_pair(:(EuclideanBall(3.0)))) >= 24)),
            :(@energy edges(bond) => 0.1 * $(spair(:(Moore(2)))))
        ]
    ),
    # dynamic: inline and named twins
    "dyn div EuclideanBall(2.0)" => (:relation_fingerprint, nothing, dyn_div(:(EuclideanBall(2.0)))),
    "dyn div far=EuclideanBall(2.0)" => (:relation_fingerprint, :(far = EuclideanBall(2.0)), dyn_div(:far)),
    "dyn div Moore(1)" => (:relation_fingerprint, nothing, dyn_div(:(Moore(1)))),
    "dyn div far=Moore(1)" => (:relation_fingerprint, :(far = Moore(1)), dyn_div(:far)),
    "dyn link Moore(1)" => (:touch, nothing, dyn_link(:(Moore(1)))),
    "dyn link far=Moore(1)" => (:touch, :(far = Moore(1)), dyn_link(:far)),
    # `relation_fingerprint_tests.jl` fixtures whose gathers were already scanned (pins)
    "at energy Moore(1)(40)" => (:relation_fingerprint, nothing, [:(@energy cells => 0.1 * $(gather_s(:(Moore(1)))))]),
    "at drive Moore(2)/Moore(1)" => (
        :relation_fingerprint, nothing,
        [:(@drive copy => 0.1 * (count(owner[n] == 1 for n in Moore(2)(source)) - count(owner[n] == 1 for n in Moore(1)(target))))]
    ),
    "at ode Moore(2)(40)" => (:relation_fingerprint, nothing, [:(@equations D(y) ~ 0.1 * $(gather_g(:(Moore(2)))) - 0.1y)]),
    "at update Moore(1)(40)" => (:relation_fingerprint, nothing, [:(@after_mcs q ~ 0.1 * $(gather_g(:(Moore(1)), 1)))]),
]
const MODELS = Dict{String, Any}()
const LAYOUT_OF = Dict{String, Symbol}()
for (i, (label, (lk, rel, body))) in enumerate(FIXTURES)
    name = Symbol(:Gather, i)
    ln = LineNumberNode(@__LINE__, Symbol(@__FILE__))
    relx = rel === nothing ? nothing : Expr(:macrocall, Symbol("@relations"), ln, rel)
    @eval @potts_model $name begin
        @kinds medium A
        @variables y(cell) = 0.0 q(site) = 0.0
        @lattice Lattice((12, 12))
        $relx
        @energy cells => (volume - 9.0)^2
        $(body...)
        @sweep Metropolis(; temperature = 2.0)
    end
    MODELS[label] = @eval $name
    LAYOUT_OF[label] = lk
end
function sigma(lk::Symbol)
    σ = zeros(Int32, 12, 12)
    (r1, r2) = LAYOUTS[lk]
    σ[r1...] .= 1
    σ[r2...] .= 2
    return σ
end
function gather_op(lk; links = false)
    return Any[
        ownership => sigma(lk), kind => [:A, :A], :q => Float64.(sigma(lk)),   # q: `gather_energy_tests.jl`
        (links ? [:bond => [(1, 2)]] : [])...,
    ]
end
"""The problem of fixture `label` (a build error propagates: it is the defect)."""
function gather_problem(label; T = Float64, tspan = (0, 16), seed = 1, links = false)
    return PottsProblem(
        Base.invokelatest(MODELS[label]; name = :g), gather_op(LAYOUT_OF[label]; links), tspan;
        T, seed, capacity = 16
    )
end
gather_solve(label; alg = SequentialCPM(), kw...) = solve(gather_problem(label; kw...), alg; saveat = 1)
# every MCS
gather_fp(label; T = Float64) = gather_problem(label; T).f.fingerprint
gather_linked(u) = CorePotts.linked(CorePotts.link_store(u.cell, :bond), 1, 2)
"""The saved times at which cells 1 and 2 are linked."""
link_times(sol) = [t for (u, t) in zip(sol.u, sol.t) if gather_linked(u)]
"""Brute-force count of the sites of `who` around `c` (minimum image on 12×12) within `inside(dx, dy)`."""
function oracle(σ, c, who, inside)
    n = 0
    for x in 1:12, y in 1:12
        dx = mod(x - c[1] + 6, 12) - 6
        dy = mod(y - c[2] + 6, 12) - 6
        (dx, dy) != (0, 0) && inside(dx, dy) && σ[x, y] == who && (n += 1)
    end
    return n
end
const SHAPES = Dict(
    "EuclideanBall(2.0)" => (dx, dy) -> dx^2 + dy^2 <= 4,
    "EuclideanBall(3.0)" => (dx, dy) -> dx^2 + dy^2 <= 9,
    "Moore(1)" => (dx, dy) -> max(abs(dx), abs(dy)) <= 1,
    "Moore(2)" => (dx, dy) -> max(abs(dx), abs(dy)) <= 2,
    "VonNeumann(1)" => (dx, dy) -> abs(dx) + abs(dy) <= 1,
)
"""The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the pair)."""
function gather_distinct(labels; T = Float64)
    fps = [label => gather_fp(label; T) for label in labels]
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        @test x != y
        x != y || @info "inline gather numbering: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end
"""Each label fingerprints like `base` (one @test per label)."""
function gather_like(base, labels; T = Float64)
    f0 = gather_fp(base; T)
    for label in labels
        fp = gather_fp(label; T)
        @test fp == f0
        fp == f0 || @info "inline gather numbering: `$label` ($(repr(fp))) does not fingerprint like `$base` ($(repr(f0)))"
    end
end
"""A checkpoint of `pa` after `k` MCS: refused by `pb` (unless `nothing`), accepted by `pa2`, in memory and on disk."""
function gather_checkpoint(pa, pb, pa2; k = 3, alg = SequentialCPM())
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    pb === nothing || @test (init(pb, alg); true)        # without the checkpoint `pb` starts: the refusal is the checkpoint's
    path = joinpath(mktempdir(), "gather_scan.jls")
    save_checkpoint(path, ck)
    for c in (ck, load_checkpoint(path))
        pb === nothing || @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg; checkpoint = c)
        @test i2.t == k
        @test i2.u.ownership == ck.state.ownership
    end
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "inline gather numbering: controls — the hand counts" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Controls (pass on the base)
    @testset "inline gather numbering: controls — the hand counts" begin
        S = SHAPES
        ap, to, at = sigma(:apart), sigma(:touch), sigma(:relation_fingerprint)
        c40, c29, c143 = (4, 4), (5, 3), (11, 12)
        @test [oracle(ap, c40, w, S["EuclideanBall(2.0)"]) for w in 1:2] == [5, 1]
        @test [oracle(ap, c40, w, S["EuclideanBall(3.0)"]) for w in 1:2] == [8, 4]
        @test [oracle(ap, c40, w, S["Moore(1)"]) for w in 1:2] == [3, 0]
        @test [oracle(ap, c40, w, S["Moore(2)"]) for w in 1:2] == [8, 3]
        @test [oracle(ap, c29, 2, S[k]) for k in ("Moore(1)", "VonNeumann(1)", "Moore(2)")] == [3, 1, 6]
        @test [sum(oracle(to, c40, w, S[k]) for w in 1:2) for k in ("EuclideanBall(2.0)", "EuclideanBall(3.0)", "Moore(1)", "Moore(2)", "VonNeumann(1)")] ==
            [8, 15, 5, 14, 3]
        @test [oracle(at, c40, 1, S[k]) for k in ("Moore(1)", "Moore(2)", "VonNeumann(1)")] == [3, 8, 2]
        @test all(oracle(σ, c143, w, S["EuclideanBall(2.0)"]) == 0 for σ in (ap, to), w in 1:2)
        # the linear indices name those sites (column-major, 12×12)
        @test LinearIndices((12, 12))[4, 4] == 40 && LinearIndices((12, 12))[5, 3] == 29 && LinearIndices((12, 12))[11, 12] == 143
        # the oracle's shapes are the relations' (sizes on the lattice)
        lat = gather_problem("sq").lattice
        for (spec, k) in (
                (EuclideanBall(2.0), "EuclideanBall(2.0)"), (EuclideanBall(3.0), "EuclideanBall(3.0)"), (Moore(1), "Moore(1)"), (Moore(2), "Moore(2)"),
                (VonNeumann(1), "VonNeumann(1)"),
            )
            @test length(CorePotts.relation(spec, lat)) == count(S[k](dx, dy) for dx in -5:5, dy in -5:5 if (dx, dy) != (0, 0))
        end
    end
end

@testitem "inline gather numbering: controls — the static veto holds and the named folds work" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: controls — the static veto holds and the named folds work" begin
        # the veto: nothing moves without a lifecycle event
        sol = gather_solve("divwhen gather-free")
        @test sol.t == 0:16
        @test all(u.ownership == sigma(:apart) for u in sol.u[1:4])         # mcs·9 ≥ 27 first at m = 3, seen at t = 4
        @test sol.stats.lifecycle.divisions == 2
        @test sol.u[end].cell.y[1:4] == [4.0, 4.0, 4.0, 4.0]
        # the named twins: division when, rule, link, unlink, edge energy, observed
        @test gather_solve("divwhen far=EuclideanBall(2.0)").u[end].cell.y[1:4] == [4.0, 13.0, 4.0, 13.0]
        @test gather_solve("divwhen far=EuclideanBall(3.0)").u[end].cell.y[1:4] == [3.0, 4.0, 3.0, 4.0]
        @test gather_solve("divrule far=Moore(1)").u[end].cell.y[1:3] == [4.0, 0.0, 4.0]
        @test first(link_times(gather_solve("link far=EuclideanBall(2.0)"))) == 4
        @test first(link_times(gather_solve("link far=EuclideanBall(3.0)"))) == 3
        s = gather_solve("unlink far=EuclideanBall(2.0)"; links = true)
        @test link_times(s) == [0, 1, 2, 3]
        p = gather_problem("edge far=Moore(1)"; links = true)
        @test total_energy(p, p.u0) ≈ 0.5
        @test observe(gather_problem("obs far=Moore(1)"), :o)[1:2] == [3, 0]
        # a gather shared with a scanned site already works (one relation, read by both)
        @test keys(gather_problem("energy Moore(1) + obs Moore(1)").relations) == (:gather1,)
        @test observe(gather_problem("energy Moore(1) + obs Moore(1)"), :o)[1:2] == [3, 0]
    end
end

@testitem "inline gather numbering: an inline gather in a division `when`" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Each missed site builds and runs, with hand-checked values
    @testset "inline gather numbering: an inline gather in a division `when`" begin
        for (label, y) in (
                "divwhen EuclideanBall(2.0)" => [4.0, 13.0, 4.0, 13.0], "divwhen EuclideanBall(3.0)" => [3.0, 4.0, 3.0, 4.0],
                "divwhen Moore(1)" => [5.0, 0.0, 5.0, 0.0], "divwhen NeighborOrder(2)" => [5.0, 0.0, 5.0, 0.0],
            )
            @testset "$label" begin
                sol = gather_solve(label)
                @test Symbol(sol.retcode) === :Success
                @test sol.u[end].cell.y[1:4] == y
                @test sol.stats.lifecycle.divisions == count(>(0), y) ÷ 2
            end
        end
        # the inline and the named form: the same division times and trajectory
        a, b = gather_solve("divwhen EuclideanBall(2.0)"), gather_solve("divwhen far=EuclideanBall(2.0)")
        @test [u.ownership for u in a.u] == [u.ownership for u in b.u]
        @test [u.cell.y for u in a.u] == [u.cell.y for u in b.u]
        # negative control: no cell within reach of the gather, no division
        sol = gather_solve("divwhen EuclideanBall(2.0) empty")
        @test sol.stats.lifecycle.divisions == 0
        @test all(==(0.0), sol.u[end].cell.y)
    end
end

@testitem "inline gather numbering: an inline gather in a division state rule" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: an inline gather in a division state rule" begin
        for (label, v) in ("divrule Moore(1)" => 4.0, "divrule VonNeumann(1)" => 2.0, "divrule Moore(2)" => 7.0)
            @testset "$label" begin
                sol = gather_solve(label)
                @test sol.stats.lifecycle.divisions == 1
                @test sol.u[end].cell.y[1:3] == [v, 0.0, v]                  # parent and daughter, not cell 2
            end
        end
        a, b = gather_solve("divrule Moore(1)"), gather_solve("divrule far=Moore(1)")
        @test [u.ownership for u in a.u] == [u.ownership for u in b.u] && [u.cell.y for u in a.u] == [u.cell.y for u in b.u]
    end
end

@testitem "inline gather numbering: an inline gather in a `@link` and an `@unlink` `when`" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: an inline gather in a `@link` and an `@unlink` `when`" begin
        # first saved time with the link: the rule fires at MCS m, seen at t = m + 1
        for (label, m) in ("link EuclideanBall(2.0)" => 3, "link EuclideanBall(3.0)" => 2, "link Moore(1)" => 5)
            @testset "$label" begin
                sol = gather_solve(label)
                @test Symbol(sol.retcode) === :Success
                @test link_times(sol) == collect((m + 1):16)
            end
        end
        @test link_times(gather_solve("link EuclideanBall(2.0) empty")) == Int[]      # negative control
        @test link_times(gather_solve("link EuclideanBall(2.0)")) == link_times(gather_solve("link far=EuclideanBall(2.0)"))
        for (label, m) in ("unlink EuclideanBall(2.0)" => 3, "unlink EuclideanBall(3.0)" => 2)
            @testset "$label" begin
                @test link_times(gather_solve(label; links = true)) == collect(0:m)
            end
        end
        @test link_times(gather_solve("unlink EuclideanBall(2.0)"; links = true)) ==
            link_times(gather_solve("unlink far=EuclideanBall(2.0)"; links = true))
    end
end

@testitem "inline gather numbering: an inline gather in an `edges(rel)` energy" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: an inline gather in an `edges(rel)` energy" begin
        for (label, E) in ("edge Moore(1)" => 0.5, "edge Moore(2)" => 1.4, "edge VonNeumann(1)" => 0.3)
            p = gather_problem(label; links = true)
            @test total_energy(p, p.u0) ≈ E
            q = gather_problem(label)                                          # unlinked: no edge term
            @test total_energy(q, q.u0) == 0.0
        end
    end
end

@testitem "inline gather numbering: an inline gather in an `@observed` quantity" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: an inline gather in an `@observed` quantity" begin
        @test observe(gather_problem("obs Moore(1)"), :o)[1:2] == [3, 0]
        @test observe(gather_problem("obs Moore(2)"), :o)[1:2] == [8, 0]
        sol = gather_solve("obs Moore(1)"; tspan = (0, 4))
        @test observe(sol, :o) == observe(gather_solve("obs far=Moore(1)"; tspan = (0, 4)), :o)
        # next to an energy reading another gather: each its own relation
        p = gather_problem("energy Moore(1) + obs VonNeumann(1)")
        @test observe(p, :o)[1:2] == [2, 0]
        @test total_energy(p, p.u0) ≈ 0.3
    end
end

@testitem "inline gather numbering: distinct numbering across sites" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. Several sites, several specs: distinct relations, each read by its own site
    @testset "inline gather numbering: distinct numbering across sites" begin
        @testset "energy Moore(2), division when EuclideanBall(2.0), division rule VonNeumann(1)" begin
            p = gather_problem("all apart"; tspan = (0, 8))
            @test length(p.relations) == 3 && all(k -> startswith(string(k), "gather"), keys(p.relations))
            @test sort([length(CorePotts.relation(r, p.lattice)) for r in values(p.relations)]) == [4, 12, 24]
            @test total_energy(p, p.u0) ≈ 0.01 * (8 + 3)
            sol = solve(p, SequentialCPM())
            @test sol.stats.lifecycle.divisions == 1                         # cell 2 would need m = 12
            @test sol.u[end].cell.y[1:3] == [104.0, 0.0, 104.0]              # m = 3 (EuclideanBall(2.0): 5), + 100·1 (VonNeumann(1))
        end
        @testset "energy Moore(1), link when EuclideanBall(3.0), edge energy Moore(2)" begin
            p = gather_problem("all touch"; tspan = (0, 6))
            @test length(p.relations) == 3
            @test sort([length(CorePotts.relation(r, p.lattice)) for r in values(p.relations)]) == [8, 24, 28]
            @test total_energy(p, p.u0) ≈ 0.05
            sol = solve(p, SequentialCPM(); saveat = 1)
            @test link_times(sol) == collect(3:6)                       # m = 2 (EuclideanBall(3.0): 15)
            @test total_energy(p, sol.u[end]) ≈ 0.05 + 1.4                   # the edge reads Moore(2): 14
        end
    end
end

@testitem "inline gather numbering: inline and named forms run alike under copies (same seed)" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: inline and named forms run alike under copies (same seed)" begin
        # CheckerboardCPM refuses any relation in the run context that reaches beyond the
        # declared footprint (read = 1), named or inline alike, so its twins read Moore(1)
        for (alg, inline, named) in (
                (SequentialCPM(), "dyn div EuclideanBall(2.0)", "dyn div far=EuclideanBall(2.0)"),
                (SequentialCPM(), "dyn div Moore(1)", "dyn div far=Moore(1)"), (CheckerboardCPM(), "dyn div Moore(1)", "dyn div far=Moore(1)"),
            )
            @testset "$inline, $(nameof(typeof(alg)))" begin
                a = gather_solve(inline; alg, tspan = (0, 20))
                b = gather_solve(named; alg, tspan = (0, 20))
                @test a.stats.lifecycle.divisions >= 1                       # the fixture divides
                @test a.stats.lifecycle.divisions == b.stats.lifecycle.divisions
                @test [u.ownership for u in a.u] == [u.ownership for u in b.u]
                @test [u.cell.y for u in a.u] == [u.cell.y for u in b.u]
            end
        end
        for alg in (SequentialCPM(), CheckerboardCPM())
            @testset "dyn link Moore(1) $(nameof(typeof(alg)))" begin
                c = gather_solve("dyn link Moore(1)"; alg, tspan = (0, 20))
                d = gather_solve("dyn link far=Moore(1)"; alg, tspan = (0, 20))
                @test !isempty(link_times(c))                           # the fixture links
                @test [u.ownership for u in c.u] == [u.ownership for u in d.u]
                @test [u.cell.links__bond for u in c.u] == [u.cell.links__bond for u in d.u]
            end
        end
    end
end

@testitem "inline gather numbering: gathers at the new sites are fingerprinted" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. Fingerprints (D-124 applied to the new sites)
    @testset "inline gather numbering: gathers at the new sites are fingerprinted" begin
        for T in (Float64, Float32)
            @testset "division when $T" begin
                gather_distinct(["divwhen EuclideanBall(2.0)", "divwhen EuclideanBall(3.0)", "divwhen Moore(1)", "divwhen gather-free"]; T)
            end
            @testset "division rule $T" begin
                gather_distinct(["divrule Moore(1)", "divrule VonNeumann(1)", "divrule Moore(2)"]; T)
            end
            @testset "link and unlink when $T" begin
                gather_distinct(["link EuclideanBall(2.0)", "link EuclideanBall(3.0)", "link Moore(1)"]; T)
                gather_distinct(["unlink EuclideanBall(2.0)", "unlink EuclideanBall(3.0)"]; T)
            end
            @testset "edge energy $T" begin
                gather_distinct(["edge Moore(1)", "edge Moore(2)", "edge VonNeumann(1)"]; T)
            end
        end
        @testset "resolving alike, alike" begin
            gather_like("divwhen Moore(1)", ["divwhen NeighborOrder(2)"])
        end
        @testset "deterministic" begin
            for (label, _) in FIXTURES
                @test gather_fp(label) == gather_fp(label)
            end
        end
    end
end

@testitem "inline gather numbering: named twins at the new sites (controls, pass on the base)" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: named twins at the new sites (controls, pass on the base)" begin
        gather_distinct(["divwhen far=EuclideanBall(2.0)", "divwhen far=EuclideanBall(3.0)"])
        gather_distinct(["link far=EuclideanBall(2.0)", "link far=EuclideanBall(3.0)"])
    end
end

@testitem "inline gather numbering: `@observed` gathers are not fingerprinted and renumber nothing" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: `@observed` gathers are not fingerprinted and renumber nothing" begin
        gather_like("sq", ["obs Moore(1)", "obs Moore(2)"])
        gather_like("energy Moore(1)", ["energy Moore(1) + obs VonNeumann(1)", "energy Moore(1) + obs Moore(1)"])
        gather_like("energy Moore(1)", ["energy Moore(1) + obs VonNeumann(1)"]; T = Float32)
    end
end

@testitem "inline gather numbering: a checkpoint does not load across a gather at the new sites" setup = [InlineGatherNumberingSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "inline gather numbering: a checkpoint does not load across a gather at the new sites" begin
        pr = gather_problem
        gather_checkpoint(pr("divwhen EuclideanBall(2.0)"), pr("divwhen EuclideanBall(3.0)"), pr("divwhen EuclideanBall(2.0)"))
        gather_checkpoint(pr("link EuclideanBall(3.0)"), pr("link EuclideanBall(2.0)"), pr("link EuclideanBall(3.0)"))
        gather_checkpoint(pr("edge Moore(2)"; links = true), pr("edge Moore(1)"; links = true), pr("edge Moore(2)"; links = true))
        # (radius-1 specs: CheckerboardCPM refuses a radius-2 relation at init, which would pass vacuously)
        gather_checkpoint(pr("divrule Moore(1)"), pr("divrule VonNeumann(1)"), pr("divrule Moore(1)"); alg = CheckerboardCPM())
        # across specs that resolve alike, and across an observed-only gather: loads
        gather_checkpoint(pr("divwhen NeighborOrder(2)"), nothing, pr("divwhen Moore(1)"))
        gather_checkpoint(pr("obs Moore(2)"), nothing, pr("obs Moore(1)"))
    end
end
