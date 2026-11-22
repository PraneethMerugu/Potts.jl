# Ordered relationships (chains) and energies over three consecutive members: the order
# under linking and unlinking, the exact energy change of an angle term against a
# brute-force oracle, the refusals, and the solver restriction.

@testsetup module OrderedSetup
using Potts, Test
using Potts: CorePotts
using Random: Xoshiro

# A chain of six square cells in a zigzag, so that no triple is straight; `shift` moves it
# along the first axis (across a periodic seam when it passes the edge)
function zigzag(dims; side = 5, shift = 0)
    σ = zeros(Int32, dims)
    for c in 1:6
        x0 = 2 + (c - 1) * side + shift
        y0 = 6 + (iseven(c) ? 2 : 0)
        for i in x0:(x0 + side - 1), j in y0:(y0 + side - 1)
            σ[mod1(i, dims[1]), j] = c
        end
    end
    return σ
end
const ZIGZAG_LINKS = [(1, 2), (2, 3), (3, 4), (4, 5), (5, 6)]

function ctx_of(prob)
    return (;
        lattice = prob.lattice, contact = prob.contact, prob.relations...,
        (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...,
    )
end

# Independent geometry: minimum-image arms by trying the images one period away (embedded
# on a hexagonal lattice), and the inverse circumradius from the side lengths (Kahan's
# stable Heron formula), not from the cross product the package uses
function arm(lat, x, y)
    best = nothing
    for i in -1:1, j in -1:1
        ((i == 0 || lat.periodic[1]) && (j == 0 || lat.periodic[2])) || continue
        δ = (x[1] - y[1] + i * lat.dims[1], x[2] - y[2] + j * lat.dims[2])
        e = CorePotts.embed(lat, δ)
        (best === nothing || hypot(e...) < hypot(best...)) && (best = e)
    end
    return best
end
function inverse_radius(lat, p, q, n)
    a = hypot(arm(lat, p, q)...)
    b = hypot(arm(lat, n, q)...)
    c = hypot((arm(lat, p, q) .- arm(lat, n, q))...)
    a, b, c = sort([a, b, c]; rev = true)
    K = sqrt(max((a + (b + c)) * (c - (a - b)) * (c + (a - b)) * (a + (b - c)), 0.0)) / 4
    return a * b * c == 0 ? 0.0 : 4K / (a * b * c)
end
# The angle at `q` from the dot product of the arms (`π` when an arm is zero), not from the
# cross product the package uses
function pivot_angle_acos(lat, p, q, n)
    u, v = arm(lat, p, q), arm(lat, n, q)
    nu, nv = hypot(u...), hypot(v...)
    (nu == 0 || nv == 0) && return float(π)
    return acos(clamp(sum(u .* v) / (nu * nv), -1.0, 1.0))
end
# Σ f(p, q, n) over the chain's triples with three alive members (pivots in `pivots` when
# given); `cent(c)` gives the centroids
function triple_energy(
        f, u, lat; cent = c -> CorePotts.centroid(Float64, u.cell, lat, c),
        pivots = nothing
    )
    L = u.cell.links__chain
    H = 0.0
    for q in axes(L, 2)
        pivots === nothing || q in pivots || continue
        p, n = L[1, q], L[2, q]
        (p != 0 && n != 0) || continue
        all(c -> u.cell.volume[c] > 0, (p, q, n)) || continue
        H += f(cent(p), cent(q), cent(n))
    end
    return H
end
# Σ ξ κ² and Σ β (π − θ)²
function curvature_energy(u, lat, ξ; kw...)
    return triple_energy((p, q, n) -> ξ * inverse_radius(lat, p, q, n)^2, u, lat; kw...)
end
function bend_energy(u, lat, β; kw...)
    f = (p, q, n) -> β * (π - pivot_angle_acos(lat, p, q, n))^2
    return triple_energy(f, u, lat; kw...)
end
# Every Moore(1) copy between two different owners in state `u` (not medium to medium)
function all_copies(prob, u)
    lat = prob.lattice
    out = Any[]
    for t in eachindex(u.ownership), off in CorePotts.relation(Moore(1), lat).offsets
        x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, off)
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.ownership[t] == u.ownership[s] && continue
        push!(out, CorePotts.Proposal(t, s, x, 1, u.ownership[t], u.ownership[s]))
    end
    return out
end

# Random copies (Moore(1) sources) on the states of a short trajectory
function copies(prob; n = 500, rng = Xoshiro(5))
    sol = solve(
        remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = Moore(1));
        saveat = [0, 2, 4]
    )
    lat = prob.lattice
    R = CorePotts.relation(Moore(1), lat)
    out = Tuple{Any, Any}[]
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.ownership))
        x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, R.offsets[rand(rng, 1:length(R))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.ownership[t] == u.ownership[s] && continue
        push!(out, (u, CorePotts.Proposal(t, s, x, 1, u.ownership[t], u.ownership[s])))
    end
    return out
end
function after(prob, u, prop)
    a = deepcopy(u)
    a.ownership[prop.target] = prop.new
    prob.f.commit!(a, prob.p, prop, ctx_of(prob))
    return a
end
# whether the copy changes a triple: `old` or `new` in a chain of three or more
function in_triple(u, c)
    L = u.cell.links__chain
    return c != 0 && (L[1, c] != 0 || L[2, c] != 0)
end

# Starruß 2007 Eq 9 and 10, written with the DSL: `θ(c) ⋅ d` for a copy offset
# `d = (dx, dy)`, where θ is the unit vector of `separation(prev, next)` (the chord toward
# the head); the head uses its successor's θ (the chord from itself to the member after
# next) and the tail its predecessor's (the chord from the member before last to itself);
# medium and unlinked cells give 0 (`separation` of a dead referent is 0)
function chord_dot(chain, c, dx, dy)
    P = Potts.DSL
    p, n = P.prev(chain, c), P.next(chain, c)
    back = ifelse(P.alive(p), ifelse(P.alive(n), p, P.prev(chain, p)), c)
    front = ifelse(P.alive(p), ifelse(P.alive(n), n, c), P.next(chain, n))
    s = P.separation(back, front)
    len = sqrt(s[1]^2 + s[2]^2)
    return ifelse(len > 0, (s[1] * dx + s[2] * dy) / len, 0.0)
end

export chord_dot, zigzag, ZIGZAG_LINKS, ctx_of, arm, inverse_radius, curvature_energy,
    bend_energy, copies, all_copies, after, in_triple
end

@testitem "ordered relationships: rank, prev and next under link and unlink" setup = [
    OrderedSetup,
] tags = [:potts, :symbolic] begin
    using Potts
    using Potts: CorePotts
    using Random: Xoshiro
    # ranks are consistent with the links: a head has rank 1, a successor one more
    function consistent(s, n)
        return all(1:n) do c
            p, x = CorePotts.chain_prev(s, c), CorePotts.chain_next(s, c)
            (p == 0 ? CorePotts.chain_rank(s, c) == 1 :
                CorePotts.chain_rank(s, c) == CorePotts.chain_rank(s, p) + 1) &&
                (x == 0 || CorePotts.chain_prev(s, x) == c) &&
                CorePotts.linked(s, c, x) == (x != 0)
        end
    end
    rng = Xoshiro(3)
    n = 12
    for _ in 1:20
        s = CorePotts.empty_links(2, n)
        for _ in 1:40                         # random links and unlinks
            a, b = rand(rng, 1:n), rand(rng, 1:n)
            if rand(rng) < 0.7
                ok = CorePotts.add_chain_link!(s, a, b)
                @test ok || a == b || CorePotts.linked(s, a, b) ||
                    CorePotts.chain_next(s, a) != b
            else
                CorePotts.remove_link!(s, a, b)
            end
            @test consistent(s, n)
        end
    end
    s = CorePotts.empty_links(2, 6)
    for (x, y) in [(1, 2), (2, 3), (3, 4), (4, 5)]
        @test CorePotts.add_chain_link!(s, x, y)
    end
    @test CorePotts.chain_rank.(Ref(s), 1:6) == [1, 2, 3, 4, 5, 1]
    @test !CorePotts.add_chain_link!(s, 5, 1)                  # a cycle
    @test !CorePotts.add_chain_link!(s, 2, 6)                  # a second successor
    @test !CorePotts.add_chain_link!(s, 6, 3)                  # a second predecessor
    @test CorePotts.add_chain_link!(s, 6, 1)                   # a new head
    @test CorePotts.chain_rank.(Ref(s), 1:6) == [2, 3, 4, 5, 6, 1]
    # unlink 2 → 3: 3 heads the rest, ranked again from 1
    CorePotts.remove_link!(s, 2, 3)
    @test CorePotts.chain_rank.(Ref(s), 1:6) == [2, 3, 1, 2, 3, 1]
    # the lifecycle's death of 4 drops its links: the chain splits there
    CorePotts.remove_incident!(s, 4)
    @test CorePotts.chain_rank.(Ref(s), 1:6) == [2, 3, 1, 1, 1, 1]
    @test (CorePotts.chain_next(s, 3), CorePotts.chain_prev(s, 5)) == (0, 0)

    # the symbolic reads equal the store's, in updates and drives
    @potts_model Order begin
        @kinds medium seg cut
        @variables begin
            r(cell) = 0.0
            pv(cell)::CellRef
            nx(cell)::CellRef
            lk(cell) = 0.0
        end
        @relationship chain(cell, cell) ordered = true
        @lattice Lattice((40, 24); neighborhood = Moore(1))
        @energy cells => (volume - 25)^2
        @after_mcs begin
            r ~ rank(chain, id)
            pv ~ prev(chain, id)
            nx ~ next(chain, id)
            lk ~ ifelse(linked(chain, id, next(chain, id)), 1.0, 0.0)
        end
        @drive copy => 0.0 * kind[next(chain, old)] + 0.0 * rank(chain, new)
        @unlink chain when = kind[b] == cut
        @sweep Metropolis(; temperature = 2.0)
    end
    kinds = [:seg, :seg, :cut, :seg, :seg, :seg]
    op = [ownership => zigzag((40, 24)), kind => kinds, :chain => ZIGZAG_LINKS]
    prob = PottsProblem(Order(; name = :order), op, (0, 2))
    u = solve(prob, SequentialCPM()).u[end]
    s = CorePotts.link_store(u.cell, :chain)
    # the rule removed 2 → 3 (b = 3 is `cut`); 3 → 4 stays
    @test CorePotts.chain_rank.(Ref(s), 1:6) == [1, 2, 1, 2, 3, 4]
    @test u.cell.r == Float64.(CorePotts.chain_rank.(Ref(s), 1:6))
    @test u.cell.pv == CorePotts.chain_prev.(Ref(s), 1:6)
    @test u.cell.nx == CorePotts.chain_next.(Ref(s), 1:6)
    @test u.cell.lk == [1.0, 0.0, 1.0, 1.0, 1.0, 0.0]

    # `@link` makes links from the cell its condition holds for, never a branch or a cycle
    @potts_model Grow begin
        @kinds medium seg
        @relationship chain(cell, cell) ordered = true
        @lattice Lattice((40, 24); neighborhood = Moore(1))
        @energy cells => (volume - 25)^2
        @link chain when = new_contact(a, b)
        @sweep Metropolis(; temperature = 2.0)
    end
    g = PottsProblem(Grow(; name = :grow), [ownership => zigzag((40, 24))], (0, 1))
    s = CorePotts.link_store(solve(g, SequentialCPM()).u[end].cell, :chain)
    @test sort(CorePotts.chain_rank.(Ref(s), 1:6)) == 1:6        # one chain of six
    @test all(c -> CorePotts.link_count(s, c) <= 2, 1:6)
end

@testitem "angle terms: exact energy change" setup = [OrderedSetup] tags = [
    :potts, :symbolic,
] begin
    using Potts
    using Potts: CorePotts
    @potts_model BentSquare begin
        @kinds medium seg
        @parameters begin
            ξ = 300.0
            β = 2.0
            J[kind, kind] = [0 10; 10 4]
        end
        @relationship chain(cell, cell) ordered = true
        @lattice Lattice((40, 24); boundary = Closed(), neighborhood = Moore(1))
        @energy begin
            cells => (volume - 25)^2
            contacts => J[kind, neighbor_kind]
            edges(chain) => (distance - 5)^2
            angles(chain) => ξ * curvature^2 + β * (π - angle)^2
        end
        @sweep Metropolis(; temperature = 8.0)
    end
    @potts_model BentSeam begin                       # periodic: the chain crosses x = 1
        @extend BentSquare()
        @lattice Lattice((40, 24); neighborhood = Moore(1))
    end
    @potts_model BentHex begin                        # periodic hexagonal
        @extend BentSquare()
        @lattice Lattice((40, 24); geometry = Hexagonal(), neighborhood = Hex(1))
    end
    cases = (
        (BentSquare(; name = :sq), 0), (BentSeam(; name = :seam), 30),
        (BentHex(; name = :hex), 30),
    )
    for (sys, shift) in cases
        op = [ownership => zigzag((40, 24); shift), :chain => ZIGZAG_LINKS]
        prob = PottsProblem(sys, op, (0, 4))
        # the same model without curvature, and without the bend
        noκ = remake(prob; p = [:ξ => 0.0])
        noθ = remake(prob; p = [:β => 0.0])
        lat = prob.lattice
        worst_self = worst_κ = worst_θ = 0.0
        ntriple = nstale = nlocal = 0
        for (u, prop) in copies(prob)
            a = after(prob, u, prop)
            dH = energy_change(prob, u, prop)
            # the generated total energy agrees (the self-check)
            dtot = total_energy(prob, a) - total_energy(prob, u) +
                Potts._killing_credit(prob, u, prop, a)
            worst_self = max(worst_self, abs(dH - dtot))
            # each part against a brute-force sum over every triple
            dκ = dH - energy_change(noκ, u, prop)
            dθ = dH - energy_change(noθ, u, prop)
            Δκ = curvature_energy(a, lat, 300.0) - curvature_energy(u, lat, 300.0)
            worst_κ = max(worst_κ, abs(dκ - Δκ))
            Δθ = bend_energy(a, lat, 2.0) - bend_energy(u, lat, 2.0)
            worst_θ = max(worst_θ, abs(dθ - Δθ))
            # negative controls, on the copies that change a triple without a kill: an
            # oracle that ignores the shift of `new`'s centroid, and one that evaluates
            # only the triples pivoted at `old` and `new` (no two-hop triples)
            if in_triple(u, prop.new) && (prop.old == 0 || a.cell.volume[prop.old] > 0)
                ntriple += 1
                cent0 = c -> CorePotts.centroid(Float64, u.cell, lat, c)
                stale = c -> c == prop.new ? cent0(c) :
                    CorePotts.centroid(Float64, a.cell, lat, c)
                wrong = curvature_energy(a, lat, 300.0; cent = stale) -
                    curvature_energy(u, lat, 300.0)
                nstale += abs(dκ - wrong) > 1.0e-6
                pv = (prop.old, prop.new)
                local_only = curvature_energy(a, lat, 300.0; pivots = pv) -
                    curvature_energy(u, lat, 300.0; pivots = pv)
                nlocal += abs(dκ - local_only) > 1.0e-6
            end
        end
        @test worst_self < 1.0e-8
        @test worst_κ < 1.0e-8
        @test worst_θ < 1.0e-6                       # acos near π loses digits
        @test ntriple > 50
        @test nstale >= 0.9 * ntriple
        @test nlocal >= 0.5 * ntriple
    end
end

@testitem "angle terms: killing copies and dead members" setup = [OrderedSetup] tags = [
    :potts, :symbolic,
] begin
    using Potts
    using Potts: CorePotts
    @potts_model Frail begin
        @kinds medium seg
        @parameters begin
            ξ = 300.0
            β = 2.0
        end
        @relationship chain(cell, cell) ordered = true
        @lattice Lattice((30, 20); boundary = Closed(), neighborhood = Moore(1))
        @energy begin
            cells => (volume - 9)^2
            angles(chain) => ξ * curvature^2 + β * (π - angle)^2
        end
        @sweep Metropolis(; temperature = 2.0)
    end
    # chain 1 – … – 7: cell 3 has one site (a copy can kill it), cell 5 none (dead, still
    # linked)
    σ = zeros(Int32, 30, 20)
    σ[2:4, 2:4] .= 1
    σ[5:7, 4:6] .= 2
    σ[8, 7] = 3
    σ[9:11, 5:7] .= 4
    σ[13:15, 9:11] .= 6
    σ[16:18, 6:8] .= 7
    links = [(1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7)]
    prob = PottsProblem(Frail(; name = :frail), [ownership => σ, :chain => links], (0, 1))
    flat = remake(prob; p = [:ξ => 0.0, :β => 0.0])
    u, lat = prob.u0, prob.lattice
    @test u.cell.volume[[3, 5]] == [1, 0]
    worst_self = worst_oracle = 0.0
    nkill = 0
    for prop in all_copies(prob, u)
        a = after(prob, u, prop)
        dH = energy_change(prob, u, prop)
        dtot = total_energy(prob, a) - total_energy(prob, u) +
            Potts._killing_credit(prob, u, prop, a)
        worst_self = max(worst_self, abs(dH - dtot))
        E(v) = curvature_energy(v, lat, 300.0) + bend_energy(v, lat, 2.0)
        dangle = dH - energy_change(flat, u, prop)
        worst_oracle = max(worst_oracle, abs(dangle - (E(a) - E(u))))
        nkill += prop.old != 0 && a.cell.volume[prop.old] == 0
    end
    @test nkill > 0                                  # copies that kill cell 3
    @test worst_self < 1.0e-8
    @test worst_oracle < 1.0e-6
end

@testitem "angle terms: geometry helpers" tags = [:potts, :symbolic] begin
    using Potts
    using Potts: CorePotts
    sq = CorePotts.Lattice((20, 20))
    @test CorePotts.pivot_angle(Float64, sq, (1.0, 1.0), (3.0, 1.0), (5.0, 1.0)) ≈ π
    @test CorePotts.menger_curvature(Float64, sq, (1.0, 1.0), (3.0, 1.0), (5.0, 1.0)) == 0
    # a right angle with arms of length 1 and √2 apart: R = √2 / 2
    @test CorePotts.menger_curvature(Float64, sq, (4.0, 5.0), (5.0, 5.0), (5.0, 6.0)) ≈ √2
    # across the periodic seam: the arms are the minimum images
    @test CorePotts.pivot_angle(Float64, sq, (19.0, 5.0), (1.0, 5.0), (1.0, 7.0)) ≈ π / 2
    # coincident points: no bend, no circle
    @test CorePotts.pivot_angle(Float64, sq, (1.0, 1.0), (1.0, 1.0), (4.0, 1.0)) ≈ π
    @test CorePotts.menger_curvature(Float64, sq, (2.0, 2.0), (1.0, 1.0), (2.0, 2.0)) == 0
    # a hexagonal lattice: three neighbors of one site at 60° from each other
    hx = CorePotts.Lattice((20, 20); geometry = CorePotts.Hexagonal())
    @test CorePotts.pivot_angle(Float64, hx, (6.0, 5.0), (5.0, 5.0), (5.0, 6.0)) ≈ π / 3
    @test CorePotts.menger_curvature(Float64, hx, (6.0, 5.0), (5.0, 5.0), (5.0, 6.0)) ≈
        √3                                         # equilateral, side 1: R = 1/√3
end

@testitem "ordered relationships: refusals" setup = [OrderedSetup] tags = [
    :potts, :symbolic,
] begin
    using Potts
    using Potts: CorePotts, PottsCompileError
    @test_throws "capacity is 2" Potts.relationship(:chain; ordered = true, capacity = 3)
    nbad = Ref(0)
    mk(body) = eval(:(@potts_model $(Symbol(:Bad, nbad[] += 1)) begin
        @kinds medium seg
        @relationship chain(cell, cell) ordered = true
        @relationship web(cell, cell) capacity = 4
        @lattice Lattice((40, 24); neighborhood = Moore(1))
        $(body.args...)
        @sweep Metropolis(; temperature = 2.0)
    end))
    compile(body) = mtkcompile(Base.invokelatest(mk(body); name = :bad))
    @test_throws PottsCompileError compile(quote
        @energy angles(web) => curvature
    end)
    @test_throws PottsCompileError compile(quote
        @drive copy => rank(web, new)
    end)
    @test_throws PottsCompileError compile(quote
        @energy angles(chain) => volume[pivot] * curvature
    end)
    @test_throws PottsCompileError compile(quote
        @energy angles(chain) => kind[prev(chain, pivot)] * curvature
    end)
    @test_throws PottsCompileError compile(quote
        @variables w(chain) = 1.0
        @energy angles(chain) => w * curvature
    end)
    # the arguments of `prev`, `next`, `rank` and `linked` are cells
    @test_throws "is not a cell" compile(quote
        @drive copy => 0.1 * rank(chain, volume[old])
    end)
    @test_throws "is not a cell" compile(quote
        @drive copy => 0.1 * kind[prev(chain, 1000)]
    end)
    @test_throws "is not a cell" compile(quote
        @drive copy => 0.1 * linked(web, old, 2.5)
    end)
    # `pivot`, `angle` and `curvature` exist only in angle terms
    @test_throws "bound only in angle terms" compile(quote
        @drive copy => angle
    end)
    @test_throws "bound only in angle terms" compile(quote
        @energy cells => curvature
    end)
    @test_throws "bound only in angle terms" compile(quote
        @variables o(cell) = 0.0
        @after_mcs o ~ volume[pivot]
    end)
    @test mtkcompile(Base.invokelatest(mk(quote
        @variables stiff(cell) = 1.0
        @energy angles(chain) => stiff[pivot] * curvature + stiff[a] * (π - angle)
        @drive copy => 0.1 * linked(web, old, new)
    end); name = :ok)) isa Potts.CompiledPottsSystem
    for n in (:prev, :next, :rank, :linked, :angles, :pivot, :angle, :curvature)
        @test_throws r"reserved|built-in" eval(:(@potts_model $(Symbol(:Shadow, n)) begin
            @kinds medium seg
            @parameters $n = 1.0
            @lattice Lattice((8, 8))
            @sweep Metropolis(; temperature = 2.0)
        end))
    end
    # initial links: a branch or a cycle is an `ArgumentError`
    @potts_model Bent begin
        @kinds medium seg
        @relationship chain(cell, cell) ordered = true
        @lattice Lattice((40, 24); neighborhood = Moore(1))
        @energy angles(chain) => 300.0 * curvature^2
        @sweep Metropolis(; temperature = 2.0)
    end
    σ = zeros(Int32, 40, 24)
    σ[1:3, 1:3] .= 1
    σ[5:7, 1:3] .= 2
    σ[9:11, 1:3] .= 3
    for links in ([(1, 2), (1, 3)], [(1, 2), (3, 2)], [(1, 2), (2, 3), (3, 1)])
        @test_throws ArgumentError PottsProblem(
            Bent(; name = :b), [ownership => σ, :chain => links], (0, 1)
        )
    end
    # the parallel solvers are refused with an error naming the sequential solver
    op = [ownership => σ, :chain => [(1, 2), (2, 3)]]
    prob = PottsProblem(Bent(; name = :b), op, (0, 1))
    @test_throws "SequentialCPM()" solve(prob, CheckerboardCPM())
    @test solve(prob, SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
end

@testitem "propulsion along the chain: Starruß Eq 9 in a drive" setup = [
    OrderedSetup,
] tags = [:potts, :symbolic] begin
    using Potts
    using Potts: CorePotts
    @potts_model Rod begin
        @kinds medium seg
        @parameters ω = 0.5
        @relationship chain(cell, cell) ordered = true
        @lattice Lattice((40, 24); boundary = Closed(), neighborhood = Moore(1))
        @energy cells => (volume - 25)^2
        @drive copy => -ω * (
            chord_dot(chain, old, direction[1], direction[2]) +
                chord_dot(chain, new, direction[1], direction[2])
        )
        @sweep Metropolis(; temperature = 2.0)
    end
    op = [ownership => zigzag((40, 24)), :chain => ZIGZAG_LINKS]
    prob = PottsProblem(Rod(; name = :rod), op, (0, 2))
    u, lat = prob.u0, prob.lattice
    # by hand: the centroids at the moment of the copy and Eq 9 on the chain 1 → … → 6
    S = [collect(CorePotts.centroid(Float64, u.cell, lat, c)) for c in 1:6]
    unit(v) = v / hypot(v...)
    θ(c) = c == 0 ? [0.0, 0.0] : c == 1 ? θ(2) : c == 6 ? θ(5) : unit(S[c - 1] - S[c + 1])
    worst, nmoving = 0.0, 0
    props = all_copies(prob, u)
    for prop in props
        d = collect(CorePotts.coordinates(lat, prop.target)) .-
            collect(CorePotts.coordinates(lat, prop.source))
        expected = -0.5 * (sum(d .* θ(prop.old)) + sum(d .* θ(prop.new)))
        drive = prob.f.delta_H(u, prob.p, prop, ctx_of(prob)) - energy_change(prob, u, prop)
        worst = max(worst, abs(drive - expected))
        nmoving += abs(expected) > 0.05
    end
    @test length(props) > 100
    @test worst < 1.0e-12
    @test nmoving > length(props) ÷ 2
    # a forward copy gains: the head segment pushing into the medium ahead of it (toward
    # −x, away from its successor) lowers ΔH
    @test θ(1)[1] < -0.5
    # drives read live state on every solver, so the parallel one runs this model
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test solve(prob, alg).retcode == Potts.SciMLBase.ReturnCode.Success
    end
end
