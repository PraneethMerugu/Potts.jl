# CheckerboardCPM's preflight counts only the relations
# the copy step reads. Follows D-132; deferred by D-134.
#
# Amended under D-271. The lockless CheckerboardCPM no longer refuses a copy-step read beyond
# the declared footprint: it widens its spacing instead. Sections 2 and 3 now check that it
# runs and that its spacing, `(k - 1) · base` of the block layout with `parts = 2`, covers the
# reach 2; section 1 checks that a boundary-only read leaves the spacing at 1. The text below
# describes the refusal as it was.
#
# The defect. `CorePotts._preflight` (lib/CorePotts/src/problem.jl) refuses CheckerboardCPM
# when any relation of the problem (`prob.relations`: named and inline gathers alike) has a
# radius beyond the declared footprint, `reach(prob.f.footprint, ctx.proposal)`. The compiler
# declares the footprint from the copy step only (energies, drives, expression constraints,
# `@on_copy` updates, the temperature: `src/compile.jl`), so a relation read only at an MCS
# boundary is refused although no copy reads it. Measured on 746f5e99 (12×12 periodic, a fold
# `count(owner[n] == id for n in R(40))`, R = `far = EuclideanBall(2.0)` or inline `EuclideanBall(2.0)`): the
# compiler declares Footprint(read = 1) and `solve(prob, CheckerboardCPM())` throws
#   ArgumentError: CheckerboardCPM: the model declares Footprint(read = 1) but its proposal,
#   contact and named relations reach distance 2; …
# for R read only in a division `when`, a division state rule, a `@link`/`@unlink` `when`, an
# `@after_mcs`/`@before_mcs` update, a cell ODE (`@equations`) and an `@observed` quantity.
# SequentialCPM runs all of them. (The DSL has no other lifecycle rule than `@divide`: no
# removal or transition rule exists yet, `src/codegen.jl`.)
#
# Copy-step reads, measured on the same base (generated code, `Potts._ctx_reads!`):
#  - `@constraint count(owner[n] == new for n in R(target)) >= 0` and a `@drive` reading R
#    around the target: the compiler declares Footprint(read = 2) and CheckerboardCPM accepts
#    (the colouring stride covers the read). Controls: they stay accepted.
#  - `@energy edges(bond) => 0.1 * (count(… R(40) …a) + count(… R(40) …b))`: ΔH reads `ctx.R`
#    in the copy step but the compiler declares Footprint(read = 1); the preflight refuses.
#    This must stay refused (named and inline), alone or next to a boundary read of R.
#
# Amended under D-209. The edge fixtures originally folded `owner[n] == a`/`b`, a
# σ-dependent gather in an edge energy, which D-209 refuses at `mtkcompile` (its ΔH was
# wrong), so they could no longer reach the preflight. A copy-step read beyond the declared
# footprint remains possible with a valid form: a static gather in an edge energy that ΔH
# reads. The edge fixtures (sections 2 and 3, and the "mixed" ones) now fold
#   `0.1 * distance * (count(q[n] == a for n in R(40)) + count(q[n] == b for n in R(40)))`,
# with `q(site)` the initial owner map set from the operating point (declared in those
# fixtures only). `distance` (centroid distance, 3 on :touch) changes with each copy, so the
# generated ΔH reads `ctx.R` at a fixed site (measured: `delta_H` reads it on 487fda85; its
# ΔH is exact against the `gather_energy_tests.jl` oracle), while the compiler still declares
# Footprint(read = 1): the preflight must still refuse it, with the same message. The
# initial edge energy is 0.1 · 8 · 3 = 2.4 (was 0.8). (Such a read is in fact safe under the
# checkerboard, since nothing a copy writes is read; refusing it stays the conservative rule
# of this file, not a correctness requirement. A finer rule is out of scope.) Every
# other fixture, value and digest is unchanged.
#
# Rule pinned here: the preflight reach is the largest radius of the contact relation and of
# the relations the copy-step functions read (ΔH, commit, constraint, temperature,
# connectivity hooks); a relation read only at the MCS boundary (lifecycle, link rules,
# boundary updates, ODEs, observed) does not count. A relation read in both still counts.
# SequentialCPM is unchanged, and a model CheckerboardCPM already accepted keeps its
# trajectory bit for bit under a fixed seed.
#
# Fixtures (the `inline_gather_numbering_tests.jl` template). 12×12 periodic, Moore(1) lattice neighbourhood, two 3×3
# cells of kind A, `(volume - 9)^2`, Metropolis T = 2. "Static" fixtures add
# `@constraint source < 0`, which vetoes every copy, so the state changes only through
# divisions and links and every value below is exact, under either algorithm:
#   :apart  cell 1 = [2:4, 2:4], cell 2 = [6:8, 2:4]   (a gap column x = 5)
#   :touch  cell 1 = [2:4, 2:4], cell 2 = [5:7, 2:4]   (they touch: `new_contact`)
# Site 40 = (4, 4) (a corner of cell 1), 29 = (5, 3) (the gap). EuclideanBall(r): 0 < d² ≤ r²;
# Moore(1): Chebyshev 1. Counts by hand (checked against a brute-force oracle below):
#   around 40, :apart  EuclideanBall(2.0) c1 5 c2 1 | EuclideanBall(3.0) c1 8 c2 4 | Moore(1) c1 3 c2 0
#   around 29, owner 2, :apart  EuclideanBall(2.0) 4 [(6,2),(6,3),(6,4),(7,3)] | EuclideanBall(3.0) 7 | Moore(1) 3
#   around 40, :touch, c1 + c2  EuclideanBall(2.0) 8 | EuclideanBall(3.0) 15 | Moore(1) 5
# The values that need reach 2 (Moore(1), reach 1, gives the other):
#   division `when = (y == 0) & (mcs * c >= 12)`, `y => mcs + 1`: y[1:4] = [4, 13, 4, 13]
#     (EuclideanBall(2.0)), [3, 4, 3, 4] (EuclideanBall(3.0)), [5, 0, 5, 0] (Moore(1): cell 2 never divides)
#   division rule `y => 1 + c29` at MCS 2 for cell 1: y[1:3] = [5, 0, 5] (EuclideanBall(2.0)), [8, 0, 8]
#     (EuclideanBall(3.0)), [4, 0, 4] (Moore(1))
#   `@link when = new_contact(a, b) && mcs * (c1 + c2) >= 24`: first linked at t = 4
#     (EuclideanBall(2.0), m = 3), t = 6 (Moore(1), m = 5); `@unlink` on an initial link: linked at
#     t = 0:3 (EuclideanBall(2.0))
#   `@after_mcs z ~ c`, `@before_mcs z ~ c`, `D(w) ~ c - w` (Euler, one MCS: w = c) and
#   `@observed o(cell) ~ c`: [5, 1] (EuclideanBall(2.0)), [8, 4] (EuclideanBall(3.0)), [3, 0] (Moore(1))
#   :touch with all of them on `far = EuclideanBall(2.0)` (c1 5, c2 3): y[1:2] = [4, 5], first link
#     t = 4, z = o = [5, 3] before any division
# Every value was checked under SequentialCPM on the base (section 4 passes there).
#
# On 746f5e99: sections 0, 2, 3 and 4 pass; section 1 fails 23 of 23 (each the reach
# refusal quoted above, "reach distance 2" or 3); the reach-1 negative control and the cases
# of section 5 (digests recorded on 746f5e99) pass. A prototype that counts only the
# relations read by the generated ΔH, commit, constraint and temperature passes all 213.

@testsetup module BoundaryOnlyReachSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# Fixtures
const LAYOUTS = Dict(:apart => ((2:4, 2:4), (6:8, 2:4)), :touch => ((2:4, 2:4), (5:7, 2:4)))
"""A fold counting the sites of `who` in relation `r` (an inline spec call or a name) around `site`."""
reach_g(r, who = :id; site = 40) = :(count(owner[n] == $who for n in $r($site)))
pair(r) = :($(reach_g(r, :a)) + $(reach_g(r, :b)))
const STATIC = :(@constraint source < 0)
const BOND = :(@relationship bond(cell, cell) capacity = 1)
# boundary-only reads (each a lifecycle, link, boundary-update, ODE or observed site)
reach_divwhen(r) = [STATIC, :(@divide cells(A) when = (y == 0.0) & (mcs * $(reach_g(r)) >= 12), y => mcs + 1.0)]
function reach_divrule(r)
    return [
            STATIC,
            :(@divide cells(A) when = (y == 0.0) & (id == 1) & (mcs == 2), y => 1.0 + $(reach_g(r, 2; site = 29)))
        ]
end
reach_link(r) = [BOND, STATIC, :(@link bond when = new_contact(a, b) && (mcs * $(pair(r)) >= 24))]
reach_unlink(r) = [BOND, STATIC, :(@unlink bond when = mcs * $(pair(r)) >= 24)]
reach_after(r) = [STATIC, :(@after_mcs z ~ $(reach_g(r)))]
reach_before(r) = [STATIC, :(@before_mcs z ~ $(reach_g(r)))]
reach_ode(r) = [STATIC, :(@equations D(w) ~ $(reach_g(r)) - w)]
reach_obs(r) = [STATIC, :(@observed o(cell) ~ $(reach_g(r)))]
# copy-step reads
# the edge energy folds the static site value `q` (the initial owner map, from the operating
# point), the form D-209 allows, times `distance`, so that the generated ΔH reads R (`gather_energy_tests.jl`)
spair(r) = :(count(q[n] == a for n in $r(40)) + count(q[n] == b for n in $r(40)))
const REACH_Q = :(@variables q(site) = 0.0)
reach_edge(r) = [BOND, STATIC, REACH_Q, :(@energy edges(bond) => 0.1 * distance * $(spair(r)))]
reach_constraint(r) = [:(@constraint count(owner[n] == new for n in $r(target)) >= 0)]
reach_drive(r) = [:(@drive copy => 0.1 * count(owner[n] == 1 for n in $r(target)))]
const FAR = :(far = EuclideanBall(2.0))
const REACH_B2 = :(EuclideanBall(2.0))
# label => (layout, @relations body or nothing, statements after the volume energy)
const FIXTURES = [
    # 1. boundary-only reach 2 (named `far = EuclideanBall(2.0)` and inline `EuclideanBall(2.0)`)
    "divwhen far=EuclideanBall(2.0)" => (:apart, FAR, reach_divwhen(:far)),
    "divwhen EuclideanBall(2.0)" => (:apart, nothing, reach_divwhen(REACH_B2)),
    "divrule far=EuclideanBall(2.0)" => (:apart, FAR, reach_divrule(:far)),
    "divrule EuclideanBall(2.0)" => (:apart, nothing, reach_divrule(REACH_B2)),
    "link far=EuclideanBall(2.0)" => (:touch, FAR, reach_link(:far)),
    "link EuclideanBall(2.0)" => (:touch, nothing, reach_link(REACH_B2)),
    "unlink far=EuclideanBall(2.0)" => (:touch, FAR, reach_unlink(:far)),
    "unlink EuclideanBall(2.0)" => (:touch, nothing, reach_unlink(REACH_B2)),
    "after far=EuclideanBall(2.0)" => (:apart, FAR, reach_after(:far)),
    "after EuclideanBall(2.0)" => (:apart, nothing, reach_after(REACH_B2)),
    "before far=EuclideanBall(2.0)" => (:apart, FAR, reach_before(:far)),
    "before EuclideanBall(2.0)" => (:apart, nothing, reach_before(REACH_B2)),
    "ode far=EuclideanBall(2.0)" => (:apart, FAR, reach_ode(:far)),
    "ode EuclideanBall(2.0)" => (:apart, nothing, reach_ode(REACH_B2)),
    "obs far=EuclideanBall(2.0)" => (:apart, FAR, reach_obs(:far)),
    "obs EuclideanBall(2.0)" => (:apart, nothing, reach_obs(REACH_B2)),
    # farther reach (3)
    "divwhen far=EuclideanBall(3.0)" => (:apart, :(far = EuclideanBall(3.0)), reach_divwhen(:far)),
    "divwhen EuclideanBall(3.0)" => (:apart, nothing, reach_divwhen(:(EuclideanBall(3.0)))),
    "divrule EuclideanBall(3.0)" => (:apart, nothing, reach_divrule(:(EuclideanBall(3.0)))),
    "after EuclideanBall(3.0)" => (:apart, nothing, reach_after(:(EuclideanBall(3.0)))),
    "obs far=EuclideanBall(3.0)" => (:apart, :(far = EuclideanBall(3.0)), reach_obs(:far)),
    # reach-1 controls (accepted on the base: the values differ from reach 2)
    "divwhen Moore(1)" => (:apart, nothing, reach_divwhen(:(Moore(1)))),
    "divrule Moore(1)" => (:apart, nothing, reach_divrule(:(Moore(1)))),
    "link Moore(1)" => (:touch, nothing, reach_link(:(Moore(1)))),
    "after Moore(1)" => (:apart, nothing, reach_after(:(Moore(1)))),
    # several boundary sites at once, and a boundary-only far relation beside a copy-step
    # read within the footprint (a Moore(1) constraint around the target)
    "boundary all far=EuclideanBall(2.0)" => (
        :touch, FAR, [
            BOND, STATIC,
            :(@divide cells(A) when = (y == 0.0) & (mcs * $(reach_g(:far)) >= 12), y => mcs + 1.0),
            :(@link bond when = new_contact(a, b) && (mcs * $(pair(:far)) >= 24)),
            :(@after_mcs z ~ $(reach_g(:far))), :(@observed o(cell) ~ $(reach_g(:far)))
        ]
    ),
    "boundary far + copy Moore(1)" => (:apart, FAR, [reach_constraint(:(Moore(1)))..., reach_divwhen(:far)...]),
    # 2. copy-step reads
    "edge far=EuclideanBall(2.0)" => (:touch, FAR, reach_edge(:far)),
    "edge EuclideanBall(2.0)" => (:touch, nothing, reach_edge(REACH_B2)),
    "constraint far=EuclideanBall(2.0)" => (:apart, FAR, reach_constraint(:far)),
    "constraint EuclideanBall(2.0)" => (:apart, nothing, reach_constraint(REACH_B2)),
    "drive far=EuclideanBall(2.0)" => (:apart, FAR, reach_drive(:far)),
    # 3. mixed: one relation read in the copy step (edge energy) and at the boundary
    "mixed far=EuclideanBall(2.0)" => (
        :touch, FAR, [
            reach_edge(:far)...,
            :(@divide cells(A) when = (y == 0.0) & (mcs * $(reach_g(:far)) >= 12), y => mcs + 1.0)
        ]
    ),
    "mixed EuclideanBall(2.0)" => (
        :touch, nothing, [
            reach_edge(REACH_B2)...,
            :(@divide cells(A) when = (y == 0.0) & (mcs * $(reach_g(REACH_B2)) >= 12), y => mcs + 1.0)
        ]
    ),
    "mixed after+edge far=EuclideanBall(2.0)" => (:touch, FAR, [reach_edge(:far)..., :(@after_mcs z ~ $(reach_g(:far)))]),
    # 5. copy dynamics (no veto), accepted by CheckerboardCPM on the base
    "pin constraint EuclideanBall(2.0) + div Moore(1)" => (
        :touch, nothing, [
            reach_constraint(REACH_B2)...,
            :(@divide cells(A) when = (y == 0.0) & ($(reach_g(:(Moore(1)))) >= 3), y => mcs + 1.0),
            :(@after_mcs z ~ $(reach_g(:(Moore(1)))))
        ]
    ),
    "pin drive far=EuclideanBall(2.0)" => (
        :touch, FAR, [
            reach_drive(:far)...,
            :(@energy contacts => 2.0)
        ]
    ),
]
const MODELS = Dict{String, Any}()
const LAYOUT_OF = Dict{String, Symbol}()
for (i, (label, (lk, rel, body))) in enumerate(FIXTURES)
    name = Symbol(:Reach, i)
    ln = LineNumberNode(@__LINE__, Symbol(@__FILE__))
    relx = rel === nothing ? nothing : Expr(:macrocall, Symbol("@relations"), ln, rel)
    @eval @potts_model $name begin
        @kinds medium A
        @variables y(cell) = 0.0 z(cell) = 0.0 w(cell) = 0.0
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
function reach_op(lk; links = false, q = false)
    return Any[
            ownership => sigma(lk), kind => [:A, :A], (links ? [:bond => [(1, 2)]] : [])...,
            (q ? [:q => Float64.(sigma(lk))] : [])...,
        ]
end
"""Does fixture `label` declare the static site value `q` (the edge-energy fixtures of `gather_energy_tests.jl`)?"""
has_q(label) = startswith(label, "edge") || startswith(label, "mixed")
"""The problem of fixture `label`, built once per keyword set (a build error propagates: it is
not this item's defect). `solve` and `init` do not mutate a problem."""
const PROBLEMS = Dict{Any, Any}()
function reach_problem(label; tspan = (0, 16), seed = 1, links = false)
    return get!(PROBLEMS, (label, tspan, seed, links)) do
            PottsProblem(
                Base.invokelatest(MODELS[label]; name = :g), reach_op(LAYOUT_OF[label]; links, q = has_q(label)), tspan;
                seed, capacity = 16
            )
        end
end
reach_solve(label; alg, kw...) = solve(reach_problem(label; kw...), alg; saveat = 1)
# every MCS
"""The CheckerboardCPM refusal of `label`'s problem (its `ArgumentError` message), or `nothing` if it runs."""
function reach_refusal(label; kw...)
    try
        reach_solve(label; alg = CheckerboardCPM(), kw...)
        return nothing
    catch e
        e isa ArgumentError || rethrow()
        return sprint(showerror, e)
    end
end
"""The spacing of CheckerboardCPM(; parts = 2) on `label`'s problem: the smallest gap
`(k - 1) · base` between the active sub-regions of two blocks."""
function reach_spacing(label; kw...)
    l = init(reach_problem(label; kw...), CheckerboardCPM(; parts = 2)).cache.layout
    return (l.k - 1) * minimum(l.base)
end
reach_linked(u) = CorePotts.linked(CorePotts.link_store(u.cell, :bond), 1, 2)
link_times(sol) = [t for (u, t) in zip(sol.u, sol.t) if reach_linked(u)]
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
)
# The boundary-only fixtures and what each must show (a function of the solution under
# either algorithm; the expected value needs the fixture's reach). `links`: start linked.
const BOUNDARY = [
    # label, links, (solution -> observed value), expected
    ("divwhen far=EuclideanBall(2.0)", false, s -> s.u[end].cell.y[1:4], [4.0, 13.0, 4.0, 13.0]),
    ("divwhen EuclideanBall(2.0)", false, s -> s.u[end].cell.y[1:4], [4.0, 13.0, 4.0, 13.0]),
    ("divwhen far=EuclideanBall(3.0)", false, s -> s.u[end].cell.y[1:4], [3.0, 4.0, 3.0, 4.0]),
    ("divwhen EuclideanBall(3.0)", false, s -> s.u[end].cell.y[1:4], [3.0, 4.0, 3.0, 4.0]),
    ("divrule far=EuclideanBall(2.0)", false, s -> s.u[end].cell.y[1:3], [5.0, 0.0, 5.0]),
    ("divrule EuclideanBall(2.0)", false, s -> s.u[end].cell.y[1:3], [5.0, 0.0, 5.0]),
    ("divrule EuclideanBall(3.0)", false, s -> s.u[end].cell.y[1:3], [8.0, 0.0, 8.0]),
    ("link far=EuclideanBall(2.0)", false, link_times, collect(4:16)),
    ("link EuclideanBall(2.0)", false, link_times, collect(4:16)),
    ("unlink far=EuclideanBall(2.0)", true, link_times, collect(0:3)),
    ("unlink EuclideanBall(2.0)", true, link_times, collect(0:3)),
    ("after far=EuclideanBall(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("after EuclideanBall(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("after EuclideanBall(3.0)", false, s -> s.u[end].cell.z[1:2], [8.0, 4.0]),
    ("before far=EuclideanBall(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("before EuclideanBall(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("ode far=EuclideanBall(2.0)", false, s -> s.u[end].cell.w[1:2], [5.0, 1.0]),
    ("ode EuclideanBall(2.0)", false, s -> s.u[end].cell.w[1:2], [5.0, 1.0]),
    ("obs far=EuclideanBall(2.0)", false, s -> observe(s, :o)[end][1:2], [5, 1]),
    ("obs EuclideanBall(2.0)", false, s -> observe(s, :o)[end][1:2], [5, 1]),
    ("obs far=EuclideanBall(3.0)", false, s -> observe(s, :o)[end][1:2], [8, 4]),
]
# the reach-1 controls: the same observables, other values
const REACH1 = [
    ("divwhen Moore(1)", false, s -> s.u[end].cell.y[1:4], [5.0, 0.0, 5.0, 0.0]),
    ("divrule Moore(1)", false, s -> s.u[end].cell.y[1:3], [4.0, 0.0, 4.0]),
    ("link Moore(1)", false, link_times, collect(6:16)),
    ("after Moore(1)", false, s -> s.u[end].cell.z[1:2], [3.0, 0.0]),
]
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "boundary only reach: controls — the hand counts and the reach of each spec" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 0. Controls (pass on the base)
    @testset "boundary only reach: controls — the hand counts and the reach of each spec" begin
        S = SHAPES
        ap, to = sigma(:apart), sigma(:touch)
        @test [oracle(ap, (4, 4), w, S["EuclideanBall(2.0)"]) for w in 1:2] == [5, 1]
        @test [oracle(ap, (4, 4), w, S["EuclideanBall(3.0)"]) for w in 1:2] == [8, 4]
        @test [oracle(ap, (4, 4), w, S["Moore(1)"]) for w in 1:2] == [3, 0]
        @test [oracle(ap, (5, 3), 2, S[k]) for k in ("EuclideanBall(2.0)", "EuclideanBall(3.0)", "Moore(1)")] == [4, 7, 3]
        @test [sum(oracle(to, (4, 4), w, S[k]) for w in 1:2) for k in ("EuclideanBall(2.0)", "EuclideanBall(3.0)", "Moore(1)")] == [8, 15, 5]
        @test LinearIndices((12, 12))[4, 4] == 40 && LinearIndices((12, 12))[5, 3] == 29
        lat = reach_problem("divwhen Moore(1)").lattice
        for (spec, k, r) in ((EuclideanBall(2.0), "EuclideanBall(2.0)", 2), (EuclideanBall(3.0), "EuclideanBall(3.0)", 3), (Moore(1), "Moore(1)", 1))
            rel = CorePotts.relation(spec, lat)
            @test length(rel) == count(S[k](dx, dy) for dx in -5:5, dy in -5:5 if (dx, dy) != (0, 0))
            @test CorePotts.radius(rel) == r
        end
    end
end

@testitem "boundary only reach: controls — the compiler declares the copy-step footprint only" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary only reach: controls — the compiler declares the copy-step footprint only" begin
        # boundary-only fixtures: the relation is in the run context, the footprint stays 1
        for label in ("divwhen far=EuclideanBall(2.0)", "divwhen EuclideanBall(2.0)", "obs EuclideanBall(2.0)", "link far=EuclideanBall(2.0)", "edge far=EuclideanBall(2.0)")
            p = reach_problem(label)
            @test p.f.footprint.read == 1
            @test maximum(r -> CorePotts.radius(r), values(p.relations)) == 2
        end
        # a copy-step read around the target: the compiler declares read = 2
        for label in ("constraint far=EuclideanBall(2.0)", "constraint EuclideanBall(2.0)", "drive far=EuclideanBall(2.0)", "pin constraint EuclideanBall(2.0) + div Moore(1)")
            @test reach_problem(label).f.footprint.read == 2
        end
        # the reach-1 controls run under CheckerboardCPM on the base
        for label in ("divwhen Moore(1)", "divrule Moore(1)", "link Moore(1)", "after Moore(1)")
            @test reach_refusal(label) === nothing
        end
    end
end

@testitem "boundary only reach: a relation read only at the MCS boundary runs under CheckerboardCPM" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Boundary-only reach is accepted by CheckerboardCPM, and the rule sees the far relation
    @testset "boundary only reach: a relation read only at the MCS boundary runs under CheckerboardCPM" begin
        for (label, links, f, expected) in BOUNDARY
            @testset "$label" begin
                msg = reach_refusal(label; links)
                @test msg === nothing                                        # base: the reach refusal
                @test reach_spacing(label; links) == 1                       # the boundary read does not widen it
                if msg === nothing
                    sol = reach_solve(label; alg = CheckerboardCPM(), links)
                    @test Symbol(sol.retcode) === :Success
                    @test sol.t == 0:16
                    @test f(sol) == expected                                 # needs the far relation
                end
            end
        end
        # several boundary sites reading one far relation
        @testset "boundary all far=EuclideanBall(2.0)" begin
            msg = reach_refusal("boundary all far=EuclideanBall(2.0)")
            @test msg === nothing
            if msg === nothing
                sol = reach_solve("boundary all far=EuclideanBall(2.0)"; alg = CheckerboardCPM())
                @test sol.u[end].cell.y[1:2] == [4.0, 5.0]                    # :touch, c1 5 → m 3; c2 3 → m 4
                @test first(link_times(sol)) == 4                      # c1 + c2 = 8 → m 3
                @test sol.u[3].cell.z[1:2] == [5.0, 3.0]                     # t = 2, before any division
                @test observe(sol, :o)[1][1:2] == [5, 3]
            end
        end
        # a far boundary relation beside a copy-step read within the footprint
        @testset "boundary far + copy Moore(1)" begin
            msg = reach_refusal("boundary far + copy Moore(1)")
            @test msg === nothing
            if msg === nothing
                p = reach_problem("boundary far + copy Moore(1)")
                @test p.f.footprint.read == 1
                @test solve(p, CheckerboardCPM()).u[end].cell.y[1:4] == [4.0, 13.0, 4.0, 13.0]
            end
        end
    end
end

@testitem "boundary only reach: negative control — the same observables with reach 1 differ" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary only reach: negative control — the same observables with reach 1 differ" begin
        for (label, links, f, expected) in REACH1
            @testset "$label" begin
                sol = reach_solve(label; alg = CheckerboardCPM(), links)
                @test f(sol) == expected
            end
        end
    end
end

@testitem "boundary only reach: a copy-step read beyond the footprint widens the spacing" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. A copy-step read still counts
    @testset "boundary only reach: a copy-step read beyond the footprint widens the spacing" begin
        for label in ("edge far=EuclideanBall(2.0)", "edge EuclideanBall(2.0)")
            @testset "$label" begin
                p = reach_problem(label; links = true)
                @test total_energy(p, p.u0) ≈ 2.4                            # the edge energy reads EuclideanBall(2.0): 0.1 · 8 · distance 3
                @test p.f.footprint.read == 1                                # under-declared
                @test Symbol(solve(p, CheckerboardCPM()).retcode) === :Success
                @test reach_spacing(label; links = true) >= 2
                @test reach_spacing(label) >= 2                              # unlinked: still read by ΔH
            end
        end
        # copy-step reads the compiler declares (read = 2): accepted, as on the base
        for label in ("constraint far=EuclideanBall(2.0)", "constraint EuclideanBall(2.0)", "drive far=EuclideanBall(2.0)")
            @testset "$label" begin
                @test reach_refusal(label) === nothing
            end
        end
    end
end

@testitem "boundary only reach: a mixed copy-step and boundary read widens the spacing" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. A relation read in the copy step and at the boundary still counts
    @testset "boundary only reach: a mixed copy-step and boundary read widens the spacing" begin
        for label in ("mixed far=EuclideanBall(2.0)", "mixed EuclideanBall(2.0)", "mixed after+edge far=EuclideanBall(2.0)")
            @testset "$label" begin
                p = reach_problem(label; links = true)
                @test length(p.relations) == 1                               # one relation, read at both
                @test Symbol(solve(p, CheckerboardCPM()).retcode) === :Success
                @test reach_spacing(label; links = true) >= 2
            end
        end
    end
end

@testitem "boundary only reach: SequentialCPM runs every fixture, with the same values" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. SequentialCPM is unaffected
    @testset "boundary only reach: SequentialCPM runs every fixture, with the same values" begin
        for (label, links, f, expected) in [BOUNDARY; REACH1]
            @testset "$label" begin
                sol = reach_solve(label; alg = SequentialCPM(), links)
                @test Symbol(sol.retcode) === :Success
                @test f(sol) == expected
            end
        end
        for label in (
                "edge far=EuclideanBall(2.0)", "edge EuclideanBall(2.0)", "mixed far=EuclideanBall(2.0)", "mixed EuclideanBall(2.0)",
                "mixed after+edge far=EuclideanBall(2.0)", "constraint far=EuclideanBall(2.0)", "drive far=EuclideanBall(2.0)", "boundary all far=EuclideanBall(2.0)",
            )
            @testset "$label" begin
                @test Symbol(reach_solve(label; alg = SequentialCPM(), links = startswith(label, "mixed") || startswith(label, "edge")).retcode) === :Success
            end
        end
    end
end

@testitem "boundary only reach: CheckerboardCPM accepts a model SequentialCPM refuses (seed 1)" setup = [BoundaryOnlyReachSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 5. The copy-step trajectory of a model CheckerboardCPM already accepted is unchanged
    @testset "boundary only reach: CheckerboardCPM accepts a model SequentialCPM refuses (seed 1)" begin
        for label in ("pin constraint EuclideanBall(2.0) + div Moore(1)", "pin drive far=EuclideanBall(2.0)", "divwhen Moore(1)")
            @testset "$label" begin
                @test reach_refusal(label) === nothing
            end
        end
        # the fixtures move: copies happen and, where ruled, divisions
        s = reach_solve("pin constraint EuclideanBall(2.0) + div Moore(1)"; alg = CheckerboardCPM(), tspan = (0, 20))
        @test s.u[end].ownership != s.u[1].ownership
        @test s.stats.lifecycle.divisions >= 1
        @test reach_solve("pin drive far=EuclideanBall(2.0)"; alg = CheckerboardCPM(), tspan = (0, 20)).u[end].ownership != sigma(:touch)
    end
end
