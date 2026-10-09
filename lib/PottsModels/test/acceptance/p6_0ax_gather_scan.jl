# P6.0ax (ROADMAP Phase 6, step 0): inline gathers outside the copy step are numbered.
# Decision: D-132 (amends D-107, after D-124). Frozen (AUTONOMY §7.3).
#
# The defect (P6.0at review). The compiler names each inline gather relation `gather1`,
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
# Fixtures. 12×12 periodic, Moore(1) lattice neighbourhood, two 3×3 cells of kind A,
# `(volume - 9)^2`, Metropolis T = 2 (the P6.0at template). "Static" fixtures add
# `@constraint source < 0`, which vetoes every copy, so the state changes only through
# divisions and links and every count below is exact:
#   :apart  cell 1 = [2:4, 2:4], cell 2 = [6:8, 2:4]   (a gap column x = 5)
#   :touch  cell 1 = [2:4, 2:4], cell 2 = [5:7, 2:4]   (they touch: `new_contact`)
#   :p60at  cell 1 = [2:4, 2:4], cell 2 = [7:9, 7:9]   (the P6.0at layout)
# Site 40 = (4, 4) (a corner of cell 1), 29 = (5, 3) (the gap / the boundary), 143 = (11, 12)
# (no cell within reach). Ball(r): 0 < d² ≤ r²; Moore(k): Chebyshev 1..k; VonNeumann(1):
# the four axis neighbours. Counts by hand (checked against a brute-force oracle below):
#   around 40, :apart   Ball(2.0)  c1 5 [(2,4),(3,4),(4,2),(4,3),(3,3)]  c2 1 [(6,4)]
#                       Ball(3.0)  c1 8                                   c2 4 [(6,2),(6,3),(6,4),(7,4)]
#                       Moore(1)   c1 3                                   c2 0
#                       Moore(2)   c1 8                                   c2 3 [(6,2),(6,3),(6,4)]
#   around 40, :touch   Ball(2.0)  c1 5  c2 3 [(5,3),(5,4),(6,4)]           sum  8
#                       Ball(3.0)  c1 8  c2 7 [+ (5,2),(6,3),(6,2),(7,4)]   sum 15
#                       Moore(1)   c1 3  c2 2 [(5,3),(5,4)]                 sum  5
#                       Moore(2)   c1 8  c2 6 [(5..6, 2..4)]                sum 14
#                       VonNeumann(1) c1 2 c2 1                             sum  3
#   around 29, owner 2, :apart   Moore(1) 3, VonNeumann(1) 1, Moore(2) 6
#   around 40, :p60at   Moore(1) c1 3, Moore(2) c1 8, VonNeumann(1) c1 2 (c2 0 for all)
# Division `when = (y == 0) & (mcs * count(owner[n] == id for n in R(40)) >= 12)` with
# `y => mcs + 1` fires for a cell at the first MCS m with m·count ≥ 12 and records m + 1:
# Ball(2.0) c1 m = 3, c2 m = 12; Ball(3.0) c1 m = 2, c2 m = 3; Moore(1) c1 m = 4, c2 never.
# Link `when = new_contact(a, b) && mcs * (count_a + count_b) >= 24` (and the same `@unlink`
# on a linked pair) fires at m = 3 (Ball(2.0), 8), 2 (Ball(3.0), 15), 5 (Moore(1), 5).
using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Fixtures

const P60AX_LAYOUTS = Dict(
    :apart => ((2:4, 2:4), (6:8, 2:4)),
    :touch => ((2:4, 2:4), (5:7, 2:4)),
    :p60at => ((2:4, 2:4), (7:9, 7:9)),
)
"""A fold counting the sites of `who` in relation `r` (an inline spec call or a name) around `site`."""
p60ax_g(r, who = :id; site = 40) = :(count(owner[n] == $who for n in $r($site)))
p60ax_pair(r; site = 40) = :($(p60ax_g(r, :a; site)) + $(p60ax_g(r, :b; site)))
const P60AX_STATIC = :(@constraint source < 0)
const P60AX_BOND = :(@relationship bond(cell, cell) capacity = 1)

p60ax_divwhen(r; site = 40) = [P60AX_STATIC,
    :(@divide cells(A) when = (y == 0.0) & (mcs * $(p60ax_g(r; site)) >= 12), y => mcs + 1.0)]
p60ax_divrule(r) = [P60AX_STATIC,
    :(@divide cells(A) when = (y == 0.0) & (id == 1) & (mcs == 2), y => 1.0 + $(p60ax_g(r, 2; site = 29)))]
p60ax_link(r; site = 40) = [P60AX_BOND, P60AX_STATIC, :(@link bond when = new_contact(a, b) && (mcs * $(p60ax_pair(r; site)) >= 24))]
p60ax_unlink(r) = [P60AX_BOND, P60AX_STATIC, :(@unlink bond when = mcs * $(p60ax_pair(r)) >= 24)]
p60ax_edge(r) = [P60AX_BOND, P60AX_STATIC, :(@energy edges(bond) => 0.1 * $(p60ax_pair(r)))]
p60ax_obs(r) = [:(@observed o(cell) ~ $(p60ax_g(r)))]
# dynamic (no veto): the same sites under copies, for the inline/named equivalence
p60ax_dyn_div(r) = [:(@divide cells(A) when = (y == 0.0) & ($(p60ax_g(r)) >= 3), y => mcs + 1.0 + $(p60ax_g(r, 2; site = 29)))]
p60ax_dyn_link(r) = [P60AX_BOND, :(@link bond when = new_contact(a, b) && ($(p60ax_pair(r)) >= 5)),
    :(@unlink bond when = $(p60ax_pair(r)) <= 3), :(@energy edges(bond) => 2.0 * $(p60ax_pair(r)))]

# label => (layout, @relations body or nothing, statements after the volume energy)
const P60AX_FIXTURES = [
    "sq" => (:p60at, nothing, []),
    # division when
    "divwhen Ball(2.0)" => (:apart, nothing, p60ax_divwhen(:(Ball(2.0)))),
    "divwhen Ball(3.0)" => (:apart, nothing, p60ax_divwhen(:(Ball(3.0)))),
    "divwhen Moore(1)" => (:apart, nothing, p60ax_divwhen(:(Moore(1)))),
    "divwhen NeighborOrder(2)" => (:apart, nothing, p60ax_divwhen(:(NeighborOrder(2)))),
    "divwhen Ball(2.0) empty" => (:apart, nothing, p60ax_divwhen(:(Ball(2.0)); site = 143)),
    "divwhen far=Ball(2.0)" => (:apart, :(far = Ball(2.0)), p60ax_divwhen(:far)),
    "divwhen far=Ball(3.0)" => (:apart, :(far = Ball(3.0)), p60ax_divwhen(:far)),
    "divwhen gather-free" => (:apart, nothing, [P60AX_STATIC,
        :(@divide cells(A) when = (y == 0.0) & (mcs * volume >= 27), y => mcs + 1.0)]),
    # division state rule
    "divrule Moore(1)" => (:apart, nothing, p60ax_divrule(:(Moore(1)))),
    "divrule VonNeumann(1)" => (:apart, nothing, p60ax_divrule(:(VonNeumann(1)))),
    "divrule Moore(2)" => (:apart, nothing, p60ax_divrule(:(Moore(2)))),
    "divrule far=Moore(1)" => (:apart, :(far = Moore(1)), p60ax_divrule(:far)),
    # link / unlink when
    "link Ball(2.0)" => (:touch, nothing, p60ax_link(:(Ball(2.0)))),
    "link Ball(3.0)" => (:touch, nothing, p60ax_link(:(Ball(3.0)))),
    "link Moore(1)" => (:touch, nothing, p60ax_link(:(Moore(1)))),
    "link Ball(2.0) empty" => (:touch, nothing, p60ax_link(:(Ball(2.0)); site = 143)),
    "link far=Ball(2.0)" => (:touch, :(far = Ball(2.0)), p60ax_link(:far)),
    "link far=Ball(3.0)" => (:touch, :(far = Ball(3.0)), p60ax_link(:far)),
    "unlink Ball(2.0)" => (:touch, nothing, p60ax_unlink(:(Ball(2.0)))),
    "unlink Ball(3.0)" => (:touch, nothing, p60ax_unlink(:(Ball(3.0)))),
    "unlink far=Ball(2.0)" => (:touch, :(far = Ball(2.0)), p60ax_unlink(:far)),
    # edge energy
    "edge Moore(1)" => (:touch, nothing, p60ax_edge(:(Moore(1)))),
    "edge Moore(2)" => (:touch, nothing, p60ax_edge(:(Moore(2)))),
    "edge VonNeumann(1)" => (:touch, nothing, p60ax_edge(:(VonNeumann(1)))),
    "edge far=Moore(1)" => (:touch, :(far = Moore(1)), p60ax_edge(:far)),
    # observed
    "obs Moore(1)" => (:p60at, nothing, p60ax_obs(:(Moore(1)))),
    "obs Moore(2)" => (:p60at, nothing, p60ax_obs(:(Moore(2)))),
    "obs far=Moore(1)" => (:p60at, :(far = Moore(1)), p60ax_obs(:far)),
    "energy Moore(1)" => (:p60at, nothing, [:(@energy cells => 0.1 * $(p60ax_g(:(Moore(1)))))]),
    "energy Moore(1) + obs VonNeumann(1)" => (:p60at, nothing,
        [:(@energy cells => 0.1 * $(p60ax_g(:(Moore(1))))), p60ax_obs(:(VonNeumann(1)))...]),
    "energy Moore(1) + obs Moore(1)" => (:p60at, nothing, [:(@energy cells => 0.1 * $(p60ax_g(:(Moore(1))))), p60ax_obs(:(Moore(1)))...]),
    # several sites, several specs
    "all apart" => (:apart, nothing, [P60AX_STATIC, :(@energy cells => 0.01 * $(p60ax_g(:(Moore(2))))),
        :(@divide cells(A) when = (y == 0.0) & (mcs * $(p60ax_g(:(Ball(2.0)))) >= 12),
            y => mcs + 1.0 + 100 * $(p60ax_g(:(VonNeumann(1)), 2; site = 29)))]),
    "all touch" => (:touch, nothing, [P60AX_BOND, P60AX_STATIC, :(@energy cells => 0.01 * $(p60ax_g(:(Moore(1))))),
        :(@link bond when = new_contact(a, b) && (mcs * $(p60ax_pair(:(Ball(3.0)))) >= 24)),
        :(@energy edges(bond) => 0.1 * $(p60ax_pair(:(Moore(2)))))]),
    # dynamic: inline and named twins
    "dyn div Ball(2.0)" => (:p60at, nothing, p60ax_dyn_div(:(Ball(2.0)))),
    "dyn div far=Ball(2.0)" => (:p60at, :(far = Ball(2.0)), p60ax_dyn_div(:far)),
    "dyn div Moore(1)" => (:p60at, nothing, p60ax_dyn_div(:(Moore(1)))),
    "dyn div far=Moore(1)" => (:p60at, :(far = Moore(1)), p60ax_dyn_div(:far)),
    "dyn link Moore(1)" => (:touch, nothing, p60ax_dyn_link(:(Moore(1)))),
    "dyn link far=Moore(1)" => (:touch, :(far = Moore(1)), p60ax_dyn_link(:far)),
    # P6.0at fixtures whose gathers were already scanned (pins)
    "at energy Moore(1)(40)" => (:p60at, nothing, [:(@energy cells => 0.1 * $(p60ax_g(:(Moore(1)))))]),
    "at drive Moore(2)/Moore(1)" => (:p60at, nothing,
        [:(@drive copy => 0.1 * (count(owner[n] == 1 for n in Moore(2)(source)) - count(owner[n] == 1 for n in Moore(1)(target))))]),
    "at ode Moore(2)(40)" => (:p60at, nothing, [:(@equations D(y) ~ 0.1 * $(p60ax_g(:(Moore(2)))) - 0.1y)]),
    "at update Moore(1)(40)" => (:p60at, nothing, [:(@after_mcs q ~ 0.1 * $(p60ax_g(:(Moore(1)), 1)))]),
]
const P60AX_MODELS = Dict{String, Any}()
const P60AX_LAYOUT_OF = Dict{String, Symbol}()
for (i, (label, (lk, rel, body))) in enumerate(P60AX_FIXTURES)
    name = Symbol(:P60axGather, i)
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
    P60AX_MODELS[label] = @eval $name
    P60AX_LAYOUT_OF[label] = lk
end

function p60ax_sigma(lk::Symbol)
    σ = zeros(Int32, 12, 12)
    (r1, r2) = P60AX_LAYOUTS[lk]
    σ[r1...] .= 1
    σ[r2...] .= 2
    return σ
end
p60ax_op(lk; links = false) = Any[ownership => p60ax_sigma(lk), kind => [:A, :A], (links ? [:bond => [(1, 2)]] : [])...]

"""The problem of fixture `label` (a build error propagates: it is the defect)."""
p60ax_problem(label; T = Float64, tspan = (0, 16), seed = 1, links = false) =
    PottsProblem(Base.invokelatest(P60AX_MODELS[label]; name = :g), p60ax_op(P60AX_LAYOUT_OF[label]; links), tspan;
        T, seed, capacity = 16)
p60ax_solve(label; alg = SequentialCPM(), kw...) = solve(p60ax_problem(label; kw...), alg; saveat = 1)   # every MCS
p60ax_fp(label; T = Float64) = p60ax_problem(label; T).f.fingerprint
p60ax_linked(u) = CorePotts.linked(CorePotts.link_store(u.cell, :bond), 1, 2)
"""The saved times at which cells 1 and 2 are linked."""
p60ax_link_times(sol) = [t for (u, t) in zip(sol.u, sol.t) if p60ax_linked(u)]

"""Brute-force count of the sites of `who` around `c` (minimum image on 12×12) within `inside(dx, dy)`."""
function p60ax_oracle(σ, c, who, inside)
    n = 0
    for x in 1:12, y in 1:12
        dx = mod(x - c[1] + 6, 12) - 6
        dy = mod(y - c[2] + 6, 12) - 6
        (dx, dy) != (0, 0) && inside(dx, dy) && σ[x, y] == who && (n += 1)
    end
    return n
end
const P60AX_SHAPES = Dict(
    "Ball(2.0)" => (dx, dy) -> dx^2 + dy^2 <= 4,
    "Ball(3.0)" => (dx, dy) -> dx^2 + dy^2 <= 9,
    "Moore(1)" => (dx, dy) -> max(abs(dx), abs(dy)) <= 1,
    "Moore(2)" => (dx, dy) -> max(abs(dx), abs(dy)) <= 2,
    "VonNeumann(1)" => (dx, dy) -> abs(dx) + abs(dy) <= 1,
)

"""The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the pair)."""
function p60ax_distinct(labels; T = Float64)
    fps = [label => p60ax_fp(label; T) for label in labels]
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        @test x != y
        x != y || @info "P6.0ax: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end
"""Each label fingerprints like `base` (one @test per label)."""
function p60ax_like(base, labels; T = Float64)
    f0 = p60ax_fp(base; T)
    for label in labels
        fp = p60ax_fp(label; T)
        @test fp == f0
        fp == f0 || @info "P6.0ax: `$label` ($(repr(fp))) does not fingerprint like `$base` ($(repr(f0)))"
    end
end
"""A checkpoint of `pa` after `k` MCS: refused by `pb` (unless `nothing`), accepted by `pa2`, in memory and on disk."""
function p60ax_checkpoint(pa, pb, pa2; k = 3, alg = SequentialCPM())
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    pb === nothing || @test (init(pb, alg); true)        # without the checkpoint `pb` starts: the refusal is the checkpoint's
    path = joinpath(mktempdir(), "p60ax.jls")
    save_checkpoint(path, ck)
    for c in (ck, load_checkpoint(path))
        pb === nothing || @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg; checkpoint = c)
        @test i2.t == k
        @test i2.u.σ == ck.state.σ
    end
end

# ---------------------------------------------------------------------------------------
# 1. Controls (pass on the base)

@testset "P6.0ax: controls — the hand counts" begin
    S = P60AX_SHAPES
    ap, to, at = p60ax_sigma(:apart), p60ax_sigma(:touch), p60ax_sigma(:p60at)
    c40, c29, c143 = (4, 4), (5, 3), (11, 12)
    @test [p60ax_oracle(ap, c40, w, S["Ball(2.0)"]) for w in 1:2] == [5, 1]
    @test [p60ax_oracle(ap, c40, w, S["Ball(3.0)"]) for w in 1:2] == [8, 4]
    @test [p60ax_oracle(ap, c40, w, S["Moore(1)"]) for w in 1:2] == [3, 0]
    @test [p60ax_oracle(ap, c40, w, S["Moore(2)"]) for w in 1:2] == [8, 3]
    @test [p60ax_oracle(ap, c29, 2, S[k]) for k in ("Moore(1)", "VonNeumann(1)", "Moore(2)")] == [3, 1, 6]
    @test [sum(p60ax_oracle(to, c40, w, S[k]) for w in 1:2) for k in ("Ball(2.0)", "Ball(3.0)", "Moore(1)", "Moore(2)", "VonNeumann(1)")] ==
          [8, 15, 5, 14, 3]
    @test [p60ax_oracle(at, c40, 1, S[k]) for k in ("Moore(1)", "Moore(2)", "VonNeumann(1)")] == [3, 8, 2]
    @test all(p60ax_oracle(σ, c143, w, S["Ball(2.0)"]) == 0 for σ in (ap, to), w in 1:2)
    # the linear indices name those sites (column-major, 12×12)
    @test LinearIndices((12, 12))[4, 4] == 40 && LinearIndices((12, 12))[5, 3] == 29 && LinearIndices((12, 12))[11, 12] == 143
    # the oracle's shapes are the relations' (sizes on the lattice)
    lat = p60ax_problem("sq").lattice
    for (spec, k) in ((Ball(2.0), "Ball(2.0)"), (Ball(3.0), "Ball(3.0)"), (Moore(1), "Moore(1)"), (Moore(2), "Moore(2)"),
        (VonNeumann(1), "VonNeumann(1)"))
        @test length(CorePotts.relation(spec, lat)) == count(S[k](dx, dy) for dx in -5:5, dy in -5:5 if (dx, dy) != (0, 0))
    end
end

@testset "P6.0ax: controls — the static veto holds and the named folds work" begin
    # the veto: nothing moves without a lifecycle event
    sol = p60ax_solve("divwhen gather-free")
    @test sol.t == 0:16
    @test all(u.σ == p60ax_sigma(:apart) for u in sol.u[1:4])         # mcs·9 ≥ 27 first at m = 3, seen at t = 4
    @test sol.stats.lifecycle.divisions == 2
    @test sol.u[end].cell.y[1:4] == [4.0, 4.0, 4.0, 4.0]
    # the named twins: division when, rule, link, unlink, edge energy, observed
    @test p60ax_solve("divwhen far=Ball(2.0)").u[end].cell.y[1:4] == [4.0, 13.0, 4.0, 13.0]
    @test p60ax_solve("divwhen far=Ball(3.0)").u[end].cell.y[1:4] == [3.0, 4.0, 3.0, 4.0]
    @test p60ax_solve("divrule far=Moore(1)").u[end].cell.y[1:3] == [4.0, 0.0, 4.0]
    @test first(p60ax_link_times(p60ax_solve("link far=Ball(2.0)"))) == 4
    @test first(p60ax_link_times(p60ax_solve("link far=Ball(3.0)"))) == 3
    s = p60ax_solve("unlink far=Ball(2.0)"; links = true)
    @test p60ax_link_times(s) == [0, 1, 2, 3]
    p = p60ax_problem("edge far=Moore(1)"; links = true)
    @test total_energy(p, p.u0) ≈ 0.5
    @test observe(p60ax_problem("obs far=Moore(1)"), :o)[1:2] == [3, 0]
    # a gather shared with a scanned site already works (one relation, read by both)
    @test keys(p60ax_problem("energy Moore(1) + obs Moore(1)").relations) == (:gather1,)
    @test observe(p60ax_problem("energy Moore(1) + obs Moore(1)"), :o)[1:2] == [3, 0]
end

# ---------------------------------------------------------------------------------------
# 2. Each missed site builds and runs, with hand-checked values

@testset "P6.0ax: an inline gather in a division `when`" begin
    for (label, y) in ("divwhen Ball(2.0)" => [4.0, 13.0, 4.0, 13.0], "divwhen Ball(3.0)" => [3.0, 4.0, 3.0, 4.0],
        "divwhen Moore(1)" => [5.0, 0.0, 5.0, 0.0], "divwhen NeighborOrder(2)" => [5.0, 0.0, 5.0, 0.0])
        @testset "$label" begin
            sol = p60ax_solve(label)
            @test Symbol(sol.retcode) === :Success
            @test sol.u[end].cell.y[1:4] == y
            @test sol.stats.lifecycle.divisions == count(>(0), y) ÷ 2
        end
    end
    # the inline and the named form: the same division times and trajectory
    a, b = p60ax_solve("divwhen Ball(2.0)"), p60ax_solve("divwhen far=Ball(2.0)")
    @test [u.σ for u in a.u] == [u.σ for u in b.u]
    @test [u.cell.y for u in a.u] == [u.cell.y for u in b.u]
    # negative control: no cell within reach of the gather, no division
    sol = p60ax_solve("divwhen Ball(2.0) empty")
    @test sol.stats.lifecycle.divisions == 0
    @test all(==(0.0), sol.u[end].cell.y)
end

@testset "P6.0ax: an inline gather in a division state rule" begin
    for (label, v) in ("divrule Moore(1)" => 4.0, "divrule VonNeumann(1)" => 2.0, "divrule Moore(2)" => 7.0)
        @testset "$label" begin
            sol = p60ax_solve(label)
            @test sol.stats.lifecycle.divisions == 1
            @test sol.u[end].cell.y[1:3] == [v, 0.0, v]                  # parent and daughter, not cell 2
        end
    end
    a, b = p60ax_solve("divrule Moore(1)"), p60ax_solve("divrule far=Moore(1)")
    @test [u.σ for u in a.u] == [u.σ for u in b.u] && [u.cell.y for u in a.u] == [u.cell.y for u in b.u]
end

@testset "P6.0ax: an inline gather in a `@link` and an `@unlink` `when`" begin
    # first saved time with the link: the rule fires at MCS m, seen at t = m + 1
    for (label, m) in ("link Ball(2.0)" => 3, "link Ball(3.0)" => 2, "link Moore(1)" => 5)
        @testset "$label" begin
            sol = p60ax_solve(label)
            @test Symbol(sol.retcode) === :Success
            @test p60ax_link_times(sol) == collect((m + 1):16)
        end
    end
    @test p60ax_link_times(p60ax_solve("link Ball(2.0) empty")) == Int[]      # negative control
    @test p60ax_link_times(p60ax_solve("link Ball(2.0)")) == p60ax_link_times(p60ax_solve("link far=Ball(2.0)"))
    for (label, m) in ("unlink Ball(2.0)" => 3, "unlink Ball(3.0)" => 2)
        @testset "$label" begin
            @test p60ax_link_times(p60ax_solve(label; links = true)) == collect(0:m)
        end
    end
    @test p60ax_link_times(p60ax_solve("unlink Ball(2.0)"; links = true)) ==
          p60ax_link_times(p60ax_solve("unlink far=Ball(2.0)"; links = true))
end

@testset "P6.0ax: an inline gather in an `edges(rel)` energy" begin
    for (label, E) in ("edge Moore(1)" => 0.5, "edge Moore(2)" => 1.4, "edge VonNeumann(1)" => 0.3)
        p = p60ax_problem(label; links = true)
        @test total_energy(p, p.u0) ≈ E
        q = p60ax_problem(label)                                          # unlinked: no edge term
        @test total_energy(q, q.u0) == 0.0
    end
end

@testset "P6.0ax: an inline gather in an `@observed` quantity" begin
    @test observe(p60ax_problem("obs Moore(1)"), :o)[1:2] == [3, 0]
    @test observe(p60ax_problem("obs Moore(2)"), :o)[1:2] == [8, 0]
    sol = p60ax_solve("obs Moore(1)"; tspan = (0, 4))
    @test observe(sol, :o) == observe(p60ax_solve("obs far=Moore(1)"; tspan = (0, 4)), :o)
    # next to an energy reading another gather: each its own relation
    p = p60ax_problem("energy Moore(1) + obs VonNeumann(1)")
    @test observe(p, :o)[1:2] == [2, 0]
    @test total_energy(p, p.u0) ≈ 0.3
end

# ---------------------------------------------------------------------------------------
# 3. Several sites, several specs: distinct relations, each read by its own site

@testset "P6.0ax: distinct numbering across sites" begin
    @testset "energy Moore(2), division when Ball(2.0), division rule VonNeumann(1)" begin
        p = p60ax_problem("all apart"; tspan = (0, 8))
        @test length(p.relations) == 3 && all(k -> startswith(string(k), "gather"), keys(p.relations))
        @test sort([length(CorePotts.relation(r, p.lattice)) for r in values(p.relations)]) == [4, 12, 24]
        @test total_energy(p, p.u0) ≈ 0.01 * (8 + 3)
        sol = solve(p, SequentialCPM())
        @test sol.stats.lifecycle.divisions == 1                         # cell 2 would need m = 12
        @test sol.u[end].cell.y[1:3] == [104.0, 0.0, 104.0]              # m = 3 (Ball(2.0): 5), + 100·1 (VonNeumann(1))
    end
    @testset "energy Moore(1), link when Ball(3.0), edge energy Moore(2)" begin
        p = p60ax_problem("all touch"; tspan = (0, 6))
        @test length(p.relations) == 3
        @test sort([length(CorePotts.relation(r, p.lattice)) for r in values(p.relations)]) == [8, 24, 28]
        @test total_energy(p, p.u0) ≈ 0.05
        sol = solve(p, SequentialCPM(); saveat = 1)
        @test p60ax_link_times(sol) == collect(3:6)                       # m = 2 (Ball(3.0): 15)
        @test total_energy(p, sol.u[end]) ≈ 0.05 + 1.4                   # the edge reads Moore(2): 14
    end
end

@testset "P6.0ax: inline and named forms run alike under copies (same seed)" begin
    # CheckerboardCPM refuses any relation in the run context that reaches beyond the
    # declared footprint (read = 1), named or inline alike, so its twins read Moore(1)
    for (alg, inline, named) in ((SequentialCPM(), "dyn div Ball(2.0)", "dyn div far=Ball(2.0)"),
        (SequentialCPM(), "dyn div Moore(1)", "dyn div far=Moore(1)"), (CheckerboardCPM(), "dyn div Moore(1)", "dyn div far=Moore(1)"))
        @testset "$inline, $(nameof(typeof(alg)))" begin
            a = p60ax_solve(inline; alg, tspan = (0, 20))
            b = p60ax_solve(named; alg, tspan = (0, 20))
            @test a.stats.lifecycle.divisions >= 1                       # the fixture divides
            @test a.stats.lifecycle.divisions == b.stats.lifecycle.divisions
            @test [u.σ for u in a.u] == [u.σ for u in b.u]
            @test [u.cell.y for u in a.u] == [u.cell.y for u in b.u]
        end
    end
    for alg in (SequentialCPM(), CheckerboardCPM())
        @testset "dyn link Moore(1), $(nameof(typeof(alg)))" begin
            c = p60ax_solve("dyn link Moore(1)"; alg, tspan = (0, 20))
            d = p60ax_solve("dyn link far=Moore(1)"; alg, tspan = (0, 20))
            @test !isempty(p60ax_link_times(c))                           # the fixture links
            @test [u.σ for u in c.u] == [u.σ for u in d.u]
            @test [u.cell.links__bond for u in c.u] == [u.cell.links__bond for u in d.u]
        end
    end
end

# ---------------------------------------------------------------------------------------
# 4. Fingerprints (D-124 applied to the new sites)

@testset "P6.0ax: gathers at the new sites are fingerprinted" begin
    for T in (Float64, Float32)
        @testset "division when, $T" begin
            p60ax_distinct(["divwhen Ball(2.0)", "divwhen Ball(3.0)", "divwhen Moore(1)", "divwhen gather-free"]; T)
        end
        @testset "division rule, $T" begin
            p60ax_distinct(["divrule Moore(1)", "divrule VonNeumann(1)", "divrule Moore(2)"]; T)
        end
        @testset "link and unlink when, $T" begin
            p60ax_distinct(["link Ball(2.0)", "link Ball(3.0)", "link Moore(1)"]; T)
            p60ax_distinct(["unlink Ball(2.0)", "unlink Ball(3.0)"]; T)
        end
        @testset "edge energy, $T" begin
            p60ax_distinct(["edge Moore(1)", "edge Moore(2)", "edge VonNeumann(1)"]; T)
        end
    end
    @testset "resolving alike, alike" begin
        p60ax_like("divwhen Moore(1)", ["divwhen NeighborOrder(2)"])
    end
    @testset "deterministic" begin
        for (label, _) in P60AX_FIXTURES
            @test p60ax_fp(label) == p60ax_fp(label)
        end
    end
end

@testset "P6.0ax: named twins at the new sites (controls, pass on the base)" begin
    p60ax_distinct(["divwhen far=Ball(2.0)", "divwhen far=Ball(3.0)"])
    p60ax_distinct(["link far=Ball(2.0)", "link far=Ball(3.0)"])
end

@testset "P6.0ax: `@observed` gathers are not fingerprinted and renumber nothing" begin
    p60ax_like("sq", ["obs Moore(1)", "obs Moore(2)"])
    p60ax_like("energy Moore(1)", ["energy Moore(1) + obs VonNeumann(1)", "energy Moore(1) + obs Moore(1)"])
    p60ax_like("energy Moore(1)", ["energy Moore(1) + obs VonNeumann(1)"]; T = Float32)
end

@testset "P6.0ax: a checkpoint does not load across a gather at the new sites" begin
    pr = p60ax_problem
    p60ax_checkpoint(pr("divwhen Ball(2.0)"), pr("divwhen Ball(3.0)"), pr("divwhen Ball(2.0)"))
    p60ax_checkpoint(pr("link Ball(3.0)"), pr("link Ball(2.0)"), pr("link Ball(3.0)"))
    p60ax_checkpoint(pr("edge Moore(2)"; links = true), pr("edge Moore(1)"; links = true), pr("edge Moore(2)"; links = true))
    # (radius-1 specs: CheckerboardCPM refuses a radius-2 relation at init, which would pass vacuously)
    p60ax_checkpoint(pr("divrule Moore(1)"), pr("divrule VonNeumann(1)"), pr("divrule Moore(1)"); alg = CheckerboardCPM())
    # across specs that resolve alike, and across an observed-only gather: loads
    p60ax_checkpoint(pr("divwhen NeighborOrder(2)"), nothing, pr("divwhen Moore(1)"))
    p60ax_checkpoint(pr("obs Moore(2)"), nothing, pr("obs Moore(1)"))
end

# ---------------------------------------------------------------------------------------
# 5. Pins: nothing that built before moves

function p60ax_two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
# The P6.0ah fixture `P60ahAt`, copied verbatim (renamed); its fingerprint does not depend on the name.
@potts_model P60axAhAt begin
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
function p60ax_ah(solver)
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return PottsProblem(P60axAhAt(; name = :x), Any[ownership => s, kind => [:A, :A]], (0, 10); seed = 7, ode_solver = solver)
end

p60ax_pinned() = (
    "sq" => () -> p60ax_problem("sq"),
    "obs Moore(1)" => () -> p60ax_problem("obs Moore(1)"),
    "at energy Moore(1)(40)" => () -> p60ax_problem("at energy Moore(1)(40)"),
    "at drive Moore(2)/Moore(1)" => () -> p60ax_problem("at drive Moore(2)/Moore(1)"),
    "at ode Moore(2)(40)" => () -> p60ax_problem("at ode Moore(2)(40)"),
    "at update Moore(1)(40)" => () -> p60ax_problem("at update Moore(1)(40)"),
    "divwhen far=Ball(2.0)" => () -> p60ax_problem("divwhen far=Ball(2.0)"),
    "divwhen gather-free" => () -> p60ax_problem("divwhen gather-free"),
    "divrule far=Moore(1)" => () -> p60ax_problem("divrule far=Moore(1)"),
    "link far=Ball(2.0)" => () -> p60ax_problem("link far=Ball(2.0)"),
    "unlink far=Ball(2.0)" => () -> p60ax_problem("unlink far=Ball(2.0)"),
    "edge far=Moore(1)" => () -> p60ax_problem("edge far=Moore(1)"),
    "P60ahAt RK4" => () -> p60ax_ah(Potts.RK4()),
    "P60ahAt ExplicitEuler" => () -> p60ax_ah(Potts.ExplicitEuler()),
    "GranerGlazier" => () -> (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10))),
    "WortelAct" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)), p60ax_two_wortel(), (0, 10)),
    "WortelAct connected" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true), p60ax_two_wortel(), (0, 10)),
    "MerksVasculogenesis" => () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0)),
    "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10)),
    "OpenVTGrowingMonolayer" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64),
    "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)), (0, 10);
        capacity = 256),
)
# "sq", "obs Moore(1)" (= "sq": D-124's observed rule) and the PottsModels systems are the
# D-124 pins (p6_0at, p6_0as, p6_0ah); the other fixtures were recorded on fe057508.
const P60AX_FINGERPRINTS = Dict{String, UInt64}(
    "sq" => 0x4f162b777e9799ab,
    "obs Moore(1)" => 0x4f162b777e9799ab,
    "at energy Moore(1)(40)" => 0xfc8fdefc7a8009e2,
    "at drive Moore(2)/Moore(1)" => 0x31e49234ba0e48d6,
    "at ode Moore(2)(40)" => 0x98d4f6f27d29142c,
    "at update Moore(1)(40)" => 0xc9e3fc7178508f76,
    "divwhen far=Ball(2.0)" => 0x870daf9ad46577be,
    "divwhen gather-free" => 0x5329a473752545d4,
    "divrule far=Moore(1)" => 0xb72c5fc2a24ed15c,
    "link far=Ball(2.0)" => 0x83e53d1a3a10bb5e,
    "unlink far=Ball(2.0)" => 0x32e5b92a9482fa19,
    "edge far=Moore(1)" => 0xef5c912facf5e094,
    "P60ahAt RK4" => 0x52fad8cebbee12ed,
    "P60ahAt ExplicitEuler" => 0xe41e0c4a682a9697,
    "GranerGlazier" => 0x04a4528dcdf3fcb8,
    "WortelAct" => 0xce4f1cec820b20fe,
    "WortelAct connected" => 0x7f27099ea6f348a3,   # re-pinned under P6.3g (D-193): fingerprint only
    "MerksVasculogenesis" => 0xe51b575884b86e8d,   # re-pinned under D-189 rulings 3 and 10: dynamics change (gain test, full-shell refusal under Moore(1) copies)
    "SingleDivisionFixture" => 0x13a4ddc2bb677287,
    "OpenVTGrowingMonolayer" => 0xfcecc4612f387b5e,
    "AkeebInvasion" => 0xc0529959e030d017,   # re-pinned under P6.3g (D-193): fingerprint only
)

@testset "P6.0ax: fingerprints of models that built before are unchanged" begin
    for (name, build) in p60ax_pinned()
        fp = build().f.fingerprint
        @test fp == P60AX_FINGERPRINTS[name]
        fp == P60AX_FINGERPRINTS[name] || @info "P6.0ax: fingerprint $name = $(repr(fp))"
    end
end
