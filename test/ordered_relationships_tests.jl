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
# Σ ξ κ² over the chain's triples with three alive members; `cent(c)` gives the centroids
function curvature_energy(u, lat, ξ; cent = c -> CorePotts.centroid(Float64, u.cell, lat, c))
    L = u.cell.links__chain
    H = 0.0
    for q in axes(L, 2)
        p, n = L[1, q], L[2, q]
        (p != 0 && n != 0) || continue
        all(c -> u.cell.volume[c] > 0, (p, q, n)) || continue
        H += ξ * inverse_radius(lat, cent(p), cent(q), cent(n))^2
    end
    return H
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
in_triple(u, c) = c != 0 && (u.cell.links__chain[1, c] != 0 || u.cell.links__chain[2, c] != 0)

export zigzag, ZIGZAG_LINKS, ctx_of, inverse_radius, curvature_energy, copies, after,
    in_triple
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
        flat = remake(prob; p = [:ξ => 0.0])          # the same model without curvature
        lat = prob.lattice
        worst_self = worst_oracle = worst_control = 0.0
        ntriple = 0
        for (u, prop) in copies(prob)
            a = after(prob, u, prop)
            dH = energy_change(prob, u, prop)
            # the generated total energy agrees (the self-check)
            worst_self = max(
                worst_self,
                abs(
                    dH - (
                        total_energy(prob, a) - total_energy(prob, u) +
                            Potts._killing_credit(prob, u, prop, a)
                    )
                )
            )
            # the curvature part against the brute-force sum over every triple
            dκ = dH - energy_change(flat, u, prop)
            worst_oracle = max(
                worst_oracle,
                abs(dκ - (curvature_energy(a, lat, 300.0) - curvature_energy(u, lat, 300.0)))
            )
            # negative control: an oracle that ignores the shift of `new`'s centroid
            if in_triple(u, prop.new) && (prop.old == 0 || a.cell.volume[prop.old] > 0)
                ntriple += 1
                cent0 = c -> CorePotts.centroid(Float64, u.cell, lat, c)
                stale = c -> c == prop.new ? cent0(c) :
                    CorePotts.centroid(Float64, a.cell, lat, c)
                wrong = curvature_energy(a, lat, 300.0; cent = stale) -
                    curvature_energy(u, lat, 300.0)
                worst_control = max(worst_control, abs(dκ - wrong))
            end
        end
        @test worst_self < 1.0e-8
        @test worst_oracle < 1.0e-8
        @test ntriple > 50
        @test worst_control > 1.0e-3
    end
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
    @test mtkcompile(Base.invokelatest(mk(quote
        @variables stiff(cell) = 1.0
        @energy angles(chain) => stiff[pivot] * curvature + stiff[a] * (π - angle)
        @drive copy => 0.1 * linked(web, old, new)
    end); name = :ok)) isa Potts.CompiledPottsSystem
    @test_throws "reserved" eval(:(@potts_model Shadow begin
        @kinds medium seg
        @parameters angle = 1.0
        @lattice Lattice((8, 8))
        @sweep Metropolis(; temperature = 2.0)
    end))
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
    prob = PottsProblem(Bent(; name = :b), [ownership => σ, :chain => [(1, 2), (2, 3)]], (0, 1))
    @test_throws "SequentialCPM()" solve(prob, CheckerboardCPM())
    @test solve(prob, SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
end
