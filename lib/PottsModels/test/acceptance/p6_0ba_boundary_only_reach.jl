# P6.0ba (ROADMAP Phase 6, step 0): CheckerboardCPM's preflight counts only the relations
# the copy step reads. Follow-up of P6.0ax (D-132); deferred by D-134.
#
# The defect. `CorePotts._preflight` (lib/CorePotts/src/problem.jl) refuses CheckerboardCPM
# when any relation of the problem (`prob.relations`: named and inline gathers alike) has a
# radius beyond the declared footprint, `reach(prob.f.footprint, ctx.proposal)`. The compiler
# declares the footprint from the copy step only (energies, drives, expression constraints,
# `@on_copy` updates, the temperature: `src/compile.jl`), so a relation read only at an MCS
# boundary is refused although no copy reads it. Measured on 746f5e99 (12×12 periodic, a fold
# `count(owner[n] == id for n in R(40))`, R = `far = Ball(2.0)` or inline `Ball(2.0)`): the
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
# Amended under D-209 (P6.0ca). The edge fixtures originally folded `owner[n] == a`/`b`, a
# σ-dependent gather in an edge energy, which D-209 refuses at `mtkcompile` (its ΔH was
# wrong), so they could no longer reach the preflight. A copy-step read beyond the declared
# footprint remains possible with a valid form: a static gather in an edge energy that ΔH
# reads. The edge fixtures (sections 2 and 3, and the "mixed" ones) now fold
#   `0.1 * distance * (count(q[n] == a for n in R(40)) + count(q[n] == b for n in R(40)))`,
# with `q(site)` the initial owner map set from the operating point (declared in those
# fixtures only). `distance` (centroid distance, 3 on :touch) changes with each copy, so the
# generated ΔH reads `ctx.R` at a fixed site (measured: `delta_H` reads it on 487fda85; its
# ΔH is exact against the P6.0ca oracle), while the compiler still declares
# Footprint(read = 1): the preflight must still refuse it, with the same message. The
# initial edge energy is 0.1 · 8 · 3 = 2.4 (was 0.8). (Such a read is in fact safe under the
# checkerboard, since nothing a copy writes is read; refusing it stays the conservative rule
# of this file, not a correctness requirement. A finer rule is not part of P6.0ba.) Every
# other fixture, value and digest is unchanged.
#
# Rule pinned here: the preflight reach is the largest radius of the contact relation and of
# the relations the copy-step functions read (ΔH, commit, constraint, temperature,
# connectivity hooks); a relation read only at the MCS boundary (lifecycle, link rules,
# boundary updates, ODEs, observed) does not count. A relation read in both still counts.
# SequentialCPM is unchanged, and a model CheckerboardCPM already accepted keeps its
# trajectory bit for bit under a fixed seed.
#
# Fixtures (the P6.0ax template). 12×12 periodic, Moore(1) lattice neighbourhood, two 3×3
# cells of kind A, `(volume - 9)^2`, Metropolis T = 2. "Static" fixtures add
# `@constraint source < 0`, which vetoes every copy, so the state changes only through
# divisions and links and every value below is exact, under either algorithm:
#   :apart  cell 1 = [2:4, 2:4], cell 2 = [6:8, 2:4]   (a gap column x = 5)
#   :touch  cell 1 = [2:4, 2:4], cell 2 = [5:7, 2:4]   (they touch: `new_contact`)
# Site 40 = (4, 4) (a corner of cell 1), 29 = (5, 3) (the gap). Ball(r): 0 < d² ≤ r²;
# Moore(1): Chebyshev 1. Counts by hand (checked against a brute-force oracle below):
#   around 40, :apart  Ball(2.0) c1 5 c2 1 | Ball(3.0) c1 8 c2 4 | Moore(1) c1 3 c2 0
#   around 29, owner 2, :apart  Ball(2.0) 4 [(6,2),(6,3),(6,4),(7,3)] | Ball(3.0) 7 | Moore(1) 3
#   around 40, :touch, c1 + c2  Ball(2.0) 8 | Ball(3.0) 15 | Moore(1) 5
# The values that need reach 2 (Moore(1), reach 1, gives the other):
#   division `when = (y == 0) & (mcs * c >= 12)`, `y => mcs + 1`: y[1:4] = [4, 13, 4, 13]
#     (Ball(2.0)), [3, 4, 3, 4] (Ball(3.0)), [5, 0, 5, 0] (Moore(1): cell 2 never divides)
#   division rule `y => 1 + c29` at MCS 2 for cell 1: y[1:3] = [5, 0, 5] (Ball(2.0)), [8, 0, 8]
#     (Ball(3.0)), [4, 0, 4] (Moore(1))
#   `@link when = new_contact(a, b) && mcs * (c1 + c2) >= 24`: first linked at t = 4
#     (Ball(2.0), m = 3), t = 6 (Moore(1), m = 5); `@unlink` on an initial link: linked at
#     t = 0:3 (Ball(2.0))
#   `@after_mcs z ~ c`, `@before_mcs z ~ c`, `D(w) ~ c - w` (Euler, one MCS: w = c) and
#   `@observed o(cell) ~ c`: [5, 1] (Ball(2.0)), [8, 4] (Ball(3.0)), [3, 0] (Moore(1))
#   :touch with all of them on `far = Ball(2.0)` (c1 5, c2 3): y[1:2] = [4, 5], first link
#     t = 4, z = o = [5, 3] before any division
# Every value was checked under SequentialCPM on the base (section 4 passes there).
#
# On 746f5e99: sections 0, 2, 3 and 4 pass; section 1 fails 23 of 23 (each the reach
# refusal quoted above, "reach distance 2" or 3); the reach-1 negative control and the pins
# of section 5 (digests recorded on 746f5e99) pass. A prototype that counts only the
# relations read by the generated ΔH, commit, constraint and temperature passes all 213.
using Potts: CorePotts
using SHA: sha256

# ---------------------------------------------------------------------------------------
# Fixtures

const P60BA_LAYOUTS = Dict(:apart => ((2:4, 2:4), (6:8, 2:4)), :touch => ((2:4, 2:4), (5:7, 2:4)))
"""A fold counting the sites of `who` in relation `r` (an inline spec call or a name) around `site`."""
p60ba_g(r, who = :id; site = 40) = :(count(owner[n] == $who for n in $r($site)))
p60ba_pair(r) = :($(p60ba_g(r, :a)) + $(p60ba_g(r, :b)))
const P60BA_STATIC = :(@constraint source < 0)
const P60BA_BOND = :(@relationship bond(cell, cell) capacity = 1)

# boundary-only reads (each a lifecycle, link, boundary-update, ODE or observed site)
p60ba_divwhen(r) = [P60BA_STATIC, :(@divide cells(A) when = (y == 0.0) & (mcs * $(p60ba_g(r)) >= 12), y => mcs + 1.0)]
p60ba_divrule(r) = [P60BA_STATIC,
    :(@divide cells(A) when = (y == 0.0) & (id == 1) & (mcs == 2), y => 1.0 + $(p60ba_g(r, 2; site = 29)))]
p60ba_link(r) = [P60BA_BOND, P60BA_STATIC, :(@link bond when = new_contact(a, b) && (mcs * $(p60ba_pair(r)) >= 24))]
p60ba_unlink(r) = [P60BA_BOND, P60BA_STATIC, :(@unlink bond when = mcs * $(p60ba_pair(r)) >= 24)]
p60ba_after(r) = [P60BA_STATIC, :(@after_mcs z ~ $(p60ba_g(r)))]
p60ba_before(r) = [P60BA_STATIC, :(@before_mcs z ~ $(p60ba_g(r)))]
p60ba_ode(r) = [P60BA_STATIC, :(@equations D(w) ~ $(p60ba_g(r)) - w)]
p60ba_obs(r) = [P60BA_STATIC, :(@observed o(cell) ~ $(p60ba_g(r)))]
# copy-step reads
# the edge energy folds the static site value `q` (the initial owner map, from the operating
# point), the form D-209 allows, times `distance`, so that the generated ΔH reads R (P6.0ca)
p60ba_spair(r) = :(count(q[n] == a for n in $r(40)) + count(q[n] == b for n in $r(40)))
const P60BA_Q = :(@variables q(site) = 0.0)
p60ba_edge(r) = [P60BA_BOND, P60BA_STATIC, P60BA_Q, :(@energy edges(bond) => 0.1 * distance * $(p60ba_spair(r)))]
p60ba_constraint(r) = [:(@constraint count(owner[n] == new for n in $r(target)) >= 0)]
p60ba_drive(r) = [:(@drive copy => 0.1 * count(owner[n] == 1 for n in $r(target)))]

const P60BA_FAR = :(far = Ball(2.0))
const P60BA_B2 = :(Ball(2.0))
# label => (layout, @relations body or nothing, statements after the volume energy)
const P60BA_FIXTURES = [
    # 1. boundary-only reach 2 (named `far = Ball(2.0)` and inline `Ball(2.0)`)
    "divwhen far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_divwhen(:far)),
    "divwhen Ball(2.0)" => (:apart, nothing, p60ba_divwhen(P60BA_B2)),
    "divrule far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_divrule(:far)),
    "divrule Ball(2.0)" => (:apart, nothing, p60ba_divrule(P60BA_B2)),
    "link far=Ball(2.0)" => (:touch, P60BA_FAR, p60ba_link(:far)),
    "link Ball(2.0)" => (:touch, nothing, p60ba_link(P60BA_B2)),
    "unlink far=Ball(2.0)" => (:touch, P60BA_FAR, p60ba_unlink(:far)),
    "unlink Ball(2.0)" => (:touch, nothing, p60ba_unlink(P60BA_B2)),
    "after far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_after(:far)),
    "after Ball(2.0)" => (:apart, nothing, p60ba_after(P60BA_B2)),
    "before far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_before(:far)),
    "before Ball(2.0)" => (:apart, nothing, p60ba_before(P60BA_B2)),
    "ode far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_ode(:far)),
    "ode Ball(2.0)" => (:apart, nothing, p60ba_ode(P60BA_B2)),
    "obs far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_obs(:far)),
    "obs Ball(2.0)" => (:apart, nothing, p60ba_obs(P60BA_B2)),
    # farther reach (3)
    "divwhen far=Ball(3.0)" => (:apart, :(far = Ball(3.0)), p60ba_divwhen(:far)),
    "divwhen Ball(3.0)" => (:apart, nothing, p60ba_divwhen(:(Ball(3.0)))),
    "divrule Ball(3.0)" => (:apart, nothing, p60ba_divrule(:(Ball(3.0)))),
    "after Ball(3.0)" => (:apart, nothing, p60ba_after(:(Ball(3.0)))),
    "obs far=Ball(3.0)" => (:apart, :(far = Ball(3.0)), p60ba_obs(:far)),
    # reach-1 controls (accepted on the base: the values differ from reach 2)
    "divwhen Moore(1)" => (:apart, nothing, p60ba_divwhen(:(Moore(1)))),
    "divrule Moore(1)" => (:apart, nothing, p60ba_divrule(:(Moore(1)))),
    "link Moore(1)" => (:touch, nothing, p60ba_link(:(Moore(1)))),
    "after Moore(1)" => (:apart, nothing, p60ba_after(:(Moore(1)))),
    # several boundary sites at once, and a boundary-only far relation beside a copy-step
    # read within the footprint (a Moore(1) constraint around the target)
    "boundary all far=Ball(2.0)" => (:touch, P60BA_FAR, [P60BA_BOND, P60BA_STATIC,
        :(@divide cells(A) when = (y == 0.0) & (mcs * $(p60ba_g(:far)) >= 12), y => mcs + 1.0),
        :(@link bond when = new_contact(a, b) && (mcs * $(p60ba_pair(:far)) >= 24)),
        :(@after_mcs z ~ $(p60ba_g(:far))), :(@observed o(cell) ~ $(p60ba_g(:far)))]),
    "boundary far + copy Moore(1)" => (:apart, P60BA_FAR, [p60ba_constraint(:(Moore(1)))..., p60ba_divwhen(:far)...]),
    # 2. copy-step reads
    "edge far=Ball(2.0)" => (:touch, P60BA_FAR, p60ba_edge(:far)),
    "edge Ball(2.0)" => (:touch, nothing, p60ba_edge(P60BA_B2)),
    "constraint far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_constraint(:far)),
    "constraint Ball(2.0)" => (:apart, nothing, p60ba_constraint(P60BA_B2)),
    "drive far=Ball(2.0)" => (:apart, P60BA_FAR, p60ba_drive(:far)),
    # 3. mixed: one relation read in the copy step (edge energy) and at the boundary
    "mixed far=Ball(2.0)" => (:touch, P60BA_FAR, [p60ba_edge(:far)...,
        :(@divide cells(A) when = (y == 0.0) & (mcs * $(p60ba_g(:far)) >= 12), y => mcs + 1.0)]),
    "mixed Ball(2.0)" => (:touch, nothing, [p60ba_edge(P60BA_B2)...,
        :(@divide cells(A) when = (y == 0.0) & (mcs * $(p60ba_g(P60BA_B2)) >= 12), y => mcs + 1.0)]),
    "mixed after+edge far=Ball(2.0)" => (:touch, P60BA_FAR, [p60ba_edge(:far)..., :(@after_mcs z ~ $(p60ba_g(:far)))]),
    # 5. copy dynamics (no veto), accepted by CheckerboardCPM on the base: trajectory pins
    "pin constraint Ball(2.0) + div Moore(1)" => (:touch, nothing, [p60ba_constraint(P60BA_B2)...,
        :(@divide cells(A) when = (y == 0.0) & ($(p60ba_g(:(Moore(1)))) >= 3), y => mcs + 1.0),
        :(@after_mcs z ~ $(p60ba_g(:(Moore(1)))))]),
    "pin drive far=Ball(2.0)" => (:touch, P60BA_FAR, [p60ba_drive(:far)...,
        :(@energy contacts => 2.0)]),
]
const P60BA_MODELS = Dict{String, Any}()
const P60BA_LAYOUT_OF = Dict{String, Symbol}()
for (i, (label, (lk, rel, body))) in enumerate(P60BA_FIXTURES)
    name = Symbol(:P60baReach, i)
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
    P60BA_MODELS[label] = @eval $name
    P60BA_LAYOUT_OF[label] = lk
end

function p60ba_sigma(lk::Symbol)
    σ = zeros(Int32, 12, 12)
    (r1, r2) = P60BA_LAYOUTS[lk]
    σ[r1...] .= 1
    σ[r2...] .= 2
    return σ
end
p60ba_op(lk; links = false, q = false) = Any[ownership => p60ba_sigma(lk), kind => [:A, :A], (links ? [:bond => [(1, 2)]] : [])...,
    (q ? [:q => Float64.(p60ba_sigma(lk))] : [])...]
"""Does fixture `label` declare the static site value `q` (the edge-energy fixtures, P6.0ca)?"""
p60ba_has_q(label) = startswith(label, "edge") || startswith(label, "mixed")

"""The problem of fixture `label`, built once per keyword set (a build error propagates: it is
not this item's defect). `solve` and `init` do not mutate a problem."""
const P60BA_PROBLEMS = Dict{Any, Any}()
p60ba_problem(label; tspan = (0, 16), seed = 1, links = false) =
    get!(P60BA_PROBLEMS, (label, tspan, seed, links)) do
        PottsProblem(Base.invokelatest(P60BA_MODELS[label]; name = :g), p60ba_op(P60BA_LAYOUT_OF[label]; links, q = p60ba_has_q(label)), tspan;
            seed, capacity = 16)
    end
p60ba_solve(label; alg, kw...) = solve(p60ba_problem(label; kw...), alg; saveat = 1)   # every MCS
"""The CheckerboardCPM refusal of `label`'s problem (its `ArgumentError` message), or `nothing` if it runs."""
function p60ba_refusal(label; kw...)
    try
        p60ba_solve(label; alg = CheckerboardCPM(), kw...)
        return nothing
    catch e
        e isa ArgumentError || rethrow()
        return sprint(showerror, e)
    end
end
p60ba_is_reach_refusal(msg, d) = msg isa String && occursin("CheckerboardCPM", msg) &&
                                 occursin("Footprint(read = 1)", msg) && occursin("reach distance $d", msg)
p60ba_linked(u) = CorePotts.linked(CorePotts.link_store(u.cell, :bond), 1, 2)
p60ba_link_times(sol) = [t for (u, t) in zip(sol.u, sol.t) if p60ba_linked(u)]

"""Brute-force count of the sites of `who` around `c` (minimum image on 12×12) within `inside(dx, dy)`."""
function p60ba_oracle(σ, c, who, inside)
    n = 0
    for x in 1:12, y in 1:12
        dx = mod(x - c[1] + 6, 12) - 6
        dy = mod(y - c[2] + 6, 12) - 6
        (dx, dy) != (0, 0) && inside(dx, dy) && σ[x, y] == who && (n += 1)
    end
    return n
end
const P60BA_SHAPES = Dict(
    "Ball(2.0)" => (dx, dy) -> dx^2 + dy^2 <= 4,
    "Ball(3.0)" => (dx, dy) -> dx^2 + dy^2 <= 9,
    "Moore(1)" => (dx, dy) -> max(abs(dx), abs(dy)) <= 1,
)

# The boundary-only fixtures and what each must show (a function of the solution under
# either algorithm; the expected value needs the fixture's reach). `links`: start linked.
const P60BA_BOUNDARY = [
    # label, links, (solution -> observed value), expected
    ("divwhen far=Ball(2.0)", false, s -> s.u[end].cell.y[1:4], [4.0, 13.0, 4.0, 13.0]),
    ("divwhen Ball(2.0)", false, s -> s.u[end].cell.y[1:4], [4.0, 13.0, 4.0, 13.0]),
    ("divwhen far=Ball(3.0)", false, s -> s.u[end].cell.y[1:4], [3.0, 4.0, 3.0, 4.0]),
    ("divwhen Ball(3.0)", false, s -> s.u[end].cell.y[1:4], [3.0, 4.0, 3.0, 4.0]),
    ("divrule far=Ball(2.0)", false, s -> s.u[end].cell.y[1:3], [5.0, 0.0, 5.0]),
    ("divrule Ball(2.0)", false, s -> s.u[end].cell.y[1:3], [5.0, 0.0, 5.0]),
    ("divrule Ball(3.0)", false, s -> s.u[end].cell.y[1:3], [8.0, 0.0, 8.0]),
    ("link far=Ball(2.0)", false, p60ba_link_times, collect(4:16)),
    ("link Ball(2.0)", false, p60ba_link_times, collect(4:16)),
    ("unlink far=Ball(2.0)", true, p60ba_link_times, collect(0:3)),
    ("unlink Ball(2.0)", true, p60ba_link_times, collect(0:3)),
    ("after far=Ball(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("after Ball(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("after Ball(3.0)", false, s -> s.u[end].cell.z[1:2], [8.0, 4.0]),
    ("before far=Ball(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("before Ball(2.0)", false, s -> s.u[end].cell.z[1:2], [5.0, 1.0]),
    ("ode far=Ball(2.0)", false, s -> s.u[end].cell.w[1:2], [5.0, 1.0]),
    ("ode Ball(2.0)", false, s -> s.u[end].cell.w[1:2], [5.0, 1.0]),
    ("obs far=Ball(2.0)", false, s -> observe(s, :o)[end][1:2], [5, 1]),
    ("obs Ball(2.0)", false, s -> observe(s, :o)[end][1:2], [5, 1]),
    ("obs far=Ball(3.0)", false, s -> observe(s, :o)[end][1:2], [8, 4]),
]
# the reach-1 controls: the same observables, other values
const P60BA_REACH1 = [
    ("divwhen Moore(1)", false, s -> s.u[end].cell.y[1:4], [5.0, 0.0, 5.0, 0.0]),
    ("divrule Moore(1)", false, s -> s.u[end].cell.y[1:3], [4.0, 0.0, 4.0]),
    ("link Moore(1)", false, p60ba_link_times, collect(6:16)),
    ("after Moore(1)", false, s -> s.u[end].cell.z[1:2], [3.0, 0.0]),
]

"""SHA-256 of a CheckerboardCPM run of `label` (seed 1, 20 MCS, every MCS saved): σ, the cell
columns y and z, the link and lifecycle counts, the attempt count, the RNG key and the clock."""
function p60ba_digest(label)
    prob = p60ba_problem(label; tspan = (0, 20), seed = 1)
    integ = init(prob, CheckerboardCPM(); saveat = 1)
    sol = solve!(integ)
    io = IOBuffer()
    for u in sol.u
        write(io, htol.(vec(u.σ)))
        write(io, htol.(Float64.(u.cell.y)), htol.(Float64.(u.cell.z)))
    end
    write(io, htol(Int64(sol.stats.attempts)), htol(Int64(sol.stats.lifecycle.divisions)), htol(Int64(sol.stats.mcs)))
    write(io, htol(integ.key.k0), htol(integ.key.k1), htol(Int64(integ.t)))
    return bytes2hex(sha256(take!(io)))
end

# ---------------------------------------------------------------------------------------
# 0. Controls (pass on the base)

@testset "P6.0ba: controls — the hand counts and the reach of each spec" begin
    S = P60BA_SHAPES
    ap, to = p60ba_sigma(:apart), p60ba_sigma(:touch)
    @test [p60ba_oracle(ap, (4, 4), w, S["Ball(2.0)"]) for w in 1:2] == [5, 1]
    @test [p60ba_oracle(ap, (4, 4), w, S["Ball(3.0)"]) for w in 1:2] == [8, 4]
    @test [p60ba_oracle(ap, (4, 4), w, S["Moore(1)"]) for w in 1:2] == [3, 0]
    @test [p60ba_oracle(ap, (5, 3), 2, S[k]) for k in ("Ball(2.0)", "Ball(3.0)", "Moore(1)")] == [4, 7, 3]
    @test [sum(p60ba_oracle(to, (4, 4), w, S[k]) for w in 1:2) for k in ("Ball(2.0)", "Ball(3.0)", "Moore(1)")] == [8, 15, 5]
    @test LinearIndices((12, 12))[4, 4] == 40 && LinearIndices((12, 12))[5, 3] == 29
    lat = p60ba_problem("divwhen Moore(1)").lattice
    for (spec, k, r) in ((Ball(2.0), "Ball(2.0)", 2), (Ball(3.0), "Ball(3.0)", 3), (Moore(1), "Moore(1)", 1))
        rel = CorePotts.relation(spec, lat)
        @test length(rel) == count(S[k](dx, dy) for dx in -5:5, dy in -5:5 if (dx, dy) != (0, 0))
        @test CorePotts.radius(rel) == r
    end
end

@testset "P6.0ba: controls — the compiler declares the copy-step footprint only" begin
    # boundary-only fixtures: the relation is in the run context, the footprint stays 1
    for label in ("divwhen far=Ball(2.0)", "divwhen Ball(2.0)", "obs Ball(2.0)", "link far=Ball(2.0)", "edge far=Ball(2.0)")
        p = p60ba_problem(label)
        @test p.f.footprint.read == 1
        @test maximum(r -> CorePotts.radius(r), values(p.relations)) == 2
    end
    # a copy-step read around the target: the compiler declares read = 2
    for label in ("constraint far=Ball(2.0)", "constraint Ball(2.0)", "drive far=Ball(2.0)", "pin constraint Ball(2.0) + div Moore(1)")
        @test p60ba_problem(label).f.footprint.read == 2
    end
    # the reach-1 controls run under CheckerboardCPM on the base
    for label in ("divwhen Moore(1)", "divrule Moore(1)", "link Moore(1)", "after Moore(1)")
        @test p60ba_refusal(label) === nothing
    end
end

# ---------------------------------------------------------------------------------------
# 1. Boundary-only reach is accepted by CheckerboardCPM, and the rule sees the far relation

@testset "P6.0ba: a relation read only at the MCS boundary runs under CheckerboardCPM" begin
    for (label, links, f, expected) in P60BA_BOUNDARY
        @testset "$label" begin
            msg = p60ba_refusal(label; links)
            @test msg === nothing                                        # base: the reach refusal
            if msg === nothing
                sol = p60ba_solve(label; alg = CheckerboardCPM(), links)
                @test Symbol(sol.retcode) === :Success
                @test sol.t == 0:16
                @test f(sol) == expected                                 # needs the far relation
            end
        end
    end
    # several boundary sites reading one far relation
    @testset "boundary all far=Ball(2.0)" begin
        msg = p60ba_refusal("boundary all far=Ball(2.0)")
        @test msg === nothing
        if msg === nothing
            sol = p60ba_solve("boundary all far=Ball(2.0)"; alg = CheckerboardCPM())
            @test sol.u[end].cell.y[1:2] == [4.0, 5.0]                    # :touch, c1 5 → m 3; c2 3 → m 4
            @test first(p60ba_link_times(sol)) == 4                      # c1 + c2 = 8 → m 3
            @test sol.u[3].cell.z[1:2] == [5.0, 3.0]                     # t = 2, before any division
            @test observe(sol, :o)[1][1:2] == [5, 3]
        end
    end
    # a far boundary relation beside a copy-step read within the footprint
    @testset "boundary far + copy Moore(1)" begin
        msg = p60ba_refusal("boundary far + copy Moore(1)")
        @test msg === nothing
        if msg === nothing
            p = p60ba_problem("boundary far + copy Moore(1)")
            @test p.f.footprint.read == 1
            @test solve(p, CheckerboardCPM()).u[end].cell.y[1:4] == [4.0, 13.0, 4.0, 13.0]
        end
    end
end

@testset "P6.0ba: negative control — the same observables with reach 1 differ" begin
    for (label, links, f, expected) in P60BA_REACH1
        @testset "$label" begin
            sol = p60ba_solve(label; alg = CheckerboardCPM(), links)
            @test f(sol) == expected
        end
    end
end

# ---------------------------------------------------------------------------------------
# 2. A copy-step read still counts

@testset "P6.0ba: a copy-step read beyond the footprint is still refused" begin
    for label in ("edge far=Ball(2.0)", "edge Ball(2.0)")
        @testset "$label" begin
            p = p60ba_problem(label; links = true)
            @test total_energy(p, p.u0) ≈ 2.4                            # the edge energy reads Ball(2.0): 0.1 · 8 · distance 3
            @test_throws ArgumentError solve(p, CheckerboardCPM())
            @test p60ba_is_reach_refusal(p60ba_refusal(label; links = true), 2)
            @test p60ba_is_reach_refusal(p60ba_refusal(label), 2)        # unlinked: still read by ΔH
        end
    end
    # copy-step reads the compiler declares (read = 2): accepted, as on the base
    for label in ("constraint far=Ball(2.0)", "constraint Ball(2.0)", "drive far=Ball(2.0)")
        @testset "$label" begin
            @test p60ba_refusal(label) === nothing
        end
    end
end

# ---------------------------------------------------------------------------------------
# 3. A relation read in the copy step and at the boundary still counts

@testset "P6.0ba: a mixed copy-step and boundary read is still refused" begin
    for label in ("mixed far=Ball(2.0)", "mixed Ball(2.0)", "mixed after+edge far=Ball(2.0)")
        @testset "$label" begin
            p = p60ba_problem(label; links = true)
            @test length(p.relations) == 1                               # one relation, read at both
            @test_throws ArgumentError solve(p, CheckerboardCPM())
            @test p60ba_is_reach_refusal(p60ba_refusal(label; links = true), 2)
        end
    end
end

# ---------------------------------------------------------------------------------------
# 4. SequentialCPM is unaffected

@testset "P6.0ba: SequentialCPM runs every fixture, with the same values" begin
    for (label, links, f, expected) in [P60BA_BOUNDARY; P60BA_REACH1]
        @testset "$label" begin
            sol = p60ba_solve(label; alg = SequentialCPM(), links)
            @test Symbol(sol.retcode) === :Success
            @test f(sol) == expected
        end
    end
    for label in ("edge far=Ball(2.0)", "edge Ball(2.0)", "mixed far=Ball(2.0)", "mixed Ball(2.0)",
        "mixed after+edge far=Ball(2.0)", "constraint far=Ball(2.0)", "drive far=Ball(2.0)", "boundary all far=Ball(2.0)")
        @testset "$label" begin
            @test Symbol(p60ba_solve(label; alg = SequentialCPM(), links = startswith(label, "mixed") || startswith(label, "edge")).retcode) === :Success
        end
    end
end

# ---------------------------------------------------------------------------------------
# 5. The copy-step trajectory of a model CheckerboardCPM already accepted is unchanged

@testset "P6.0ba: CheckerboardCPM trajectories pinned (bitwise, seed 1)" begin
    # digests recorded on the base (746f5e99); the change must not move them
    pins = [
        "pin constraint Ball(2.0) + div Moore(1)" => "454cc71e753685b958b160c695244a5dbe804833757c95ce4a97b77b73f7c0ce",
        "pin drive far=Ball(2.0)" => "95ff11bf42aa82506ae52e1bffd2b7094b19b984ae20d778238835cbaa00de0c",
        "divwhen Moore(1)" => "59db9594bd7f19d9ce18eff4e792ae194fcef1be080075faea5dd2442195e4d1",
    ]
    for (label, d) in pins
        @testset "$label" begin
            @test p60ba_refusal(label) === nothing
            @test p60ba_digest(label) == d
        end
    end
    # the pinned fixtures move (not a frozen state): copies happen and, where ruled, divisions
    s = p60ba_solve("pin constraint Ball(2.0) + div Moore(1)"; alg = CheckerboardCPM(), tspan = (0, 20))
    @test s.u[end].σ != s.u[1].σ
    @test s.stats.lifecycle.divisions >= 1
    @test p60ba_solve("pin drive far=Ball(2.0)"; alg = CheckerboardCPM(), tspan = (0, 20)).u[end].σ != p60ba_sigma(:touch)
end
