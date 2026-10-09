# P6.0m (ROADMAP Phase 6, step 0): four confirmed small defects from the API-synthesis
# review. Frozen (AUTONOMY §7.3). Decisions: D-074 (connectivity: exactly one component),
# D-066 (liveness), D-042 (update-block semantics), D-061 (reserved names).
#
# Semantics pinned here:
#  1. `Chemotaxis(c; strength, when)`: an explicit `when` that admits a retraction (the
#     medium gains, `new == 0`) gives that copy the drive `-strength * (c[target] - c[source])`.
#     The default (`kinds = ()`, `when = true`) keeps the documented rule "acts when the
#     gaining cell is a cell": a retraction gets 0, an extension gets the drive.
#  2. `connectivity(k)` (rule `:local`): a copy that takes a site from a constrained cell is
#     accepted iff the cell's sites around the target form EXACTLY one piece (D-074). Zero
#     pieces (the cell's last site; an isolated fragment site) is rejected, like two pieces
#     (a bridge). Square (Moore ring, face-connected pieces) and hexagonal (6-ring arcs).
#  3. `a` and `b` (the edge endpoints) are reserved: a parameter or variable named `a` or `b`
#     is an ArgumentError when the model is built (expansion, construction or mtkcompile).
#  4. `integral(x)` read in an update block that also writes `x` bare folds the NEW values
#     (D-042: a bare name in the block is its new value; a fold inside an update runs before
#     the update that reads it). Saved `s = integral(w)` equals the true sum at every save.
using Potts: CorePotts

# drive part of ΔH = full ΔH (energies + drives) − authored ΔH (energies only)
p60m_drive(prob, prop) = prob.f.delta_H(prob.u0, prob.p, prop, Potts._host_ctx(prob)) -
                         energy_change(prob, prob.u0, prop)
p60m_allows(prob, u, prop) = prob.f.constraint(u, prob.p, prop, Potts._host_ctx(prob))
p60m_prop(lat, σ, x, y) = CorePotts.Proposal(CorePotts.linear_index(lat, x), CorePotts.linear_index(lat, y),
    x, 1, σ[x...], σ[y...])     # target x takes source y's owner

# ---------------------------------------------------------------------------------------
# 1. Chemotaxis on retractions

@potts_model ChemoEither begin
    @kinds medium A
    @variables c(site) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @drive Chemotaxis(c; strength = 1.0, when = (kind[new] == A) | (kind[old] == A))
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model ChemoDefault begin
    @kinds medium A
    @variables c(site) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @drive Chemotaxis(c; strength = 1.0)
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.0m: Chemotaxis drives retractions admitted by `when`" begin
    # c[i, j] = i. Cell 1 (kind A) owns rows 4:7, columns 4:7.
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    cf = [Float64(i) for i in 1:12, j in 1:12]
    op = [ownership => σ, kind => [:A], :c => cf]
    either = PottsProblem(ChemoEither(; name = :ce), op, (0, 1))
    default = PottsProblem(ChemoDefault(; name = :cd), op, (0, 1))
    lat = either.lattice
    # retraction: target (7,5) (cell 1) takes source (8,5) (medium): old = 1, new = 0.
    #   drive = -1.0 * (c[7,5] - c[8,5]) = -(7 - 8) = +1.0
    retract = p60m_prop(lat, σ, (7, 5), (8, 5))
    @test (retract.old, retract.new) == (1, 0)
    # extension: target (8,5) (medium) takes source (7,5) (cell 1): old = 0, new = 1.
    #   drive = -1.0 * (c[8,5] - c[7,5]) = -(8 - 7) = -1.0
    grow = p60m_prop(lat, σ, (8, 5), (7, 5))
    @test (grow.old, grow.new) == (0, 1)
    expected_retract = -1.0 * (cf[7, 5] - cf[8, 5])
    @test expected_retract == 1.0
    # negative control: the defect (gate forced to `new != 0`) gives 0 here, so the check
    # below distinguishes it
    buggy_retract = retract.new != 0 ? expected_retract : 0.0
    @test buggy_retract != expected_retract

    @test p60m_drive(either, retract) ≈ 1.0            # DEFECT CHECK (currently 0.0)
    @test p60m_drive(either, grow) ≈ -1.0            # extension control
    # default `when`: acts when the gaining cell is a cell (docstring), so only extensions
    @test p60m_drive(default, retract) == 0.0
    @test p60m_drive(default, grow) ≈ -1.0
end

# ---------------------------------------------------------------------------------------
# 2. connectivity(k): exactly one component (D-074)

@potts_model ConnOne begin
    @structural_parameters begin
        geometry = CorePotts.Square()
        near = Moore(1)
    end
    @kinds medium A
    @parameters T = 20.0
    @lattice Lattice((12, 12); geometry, neighborhood = near)
    @energy cells => (volume - 1)^2
    @constraint connectivity(A)
    @sweep Metropolis(; temperature = T)
end

# the same model without the constraint (negative control)
@potts_model ConnFree begin
    @structural_parameters begin
        geometry = CorePotts.Square()
        near = Moore(1)
    end
    @kinds medium A
    @parameters T = 20.0
    @lattice Lattice((12, 12); geometry, neighborhood = near)
    @energy cells => (volume - 1)^2
    @sweep Metropolis(; temperature = T)
end

# Independent oracle: the number of pieces the losing cell's sites form in the target's
# neighbour ring, by breadth-first search over the ring sites. Square: the 8 Moore sites,
# adjacent iff they differ by 1 in exactly one coordinate (face-connected). Hexagonal: the 6
# axial neighbours, adjacent iff their difference is itself a hex neighbour offset.
const P60M_HEX = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
const P60M_MOORE = Tuple((i, j) for i in -1:1 for j in -1:1 if (i, j) != (0, 0))
function p60m_pieces(σ, x, cell, hex::Bool)
    offs = hex ? P60M_HEX : P60M_MOORE
    n1, n2 = size(σ)
    mine = [o for o in offs if 1 <= x[1] + o[1] <= n1 && 1 <= x[2] + o[2] <= n2 &&
                                σ[x[1] + o[1], x[2] + o[2]] == cell]
    adjacent(p, q) = (d = (p[1] - q[1], p[2] - q[2]); hex ? d in P60M_HEX : abs(d[1]) + abs(d[2]) == 1)
    seen = falses(length(mine)); pieces = 0
    for s in eachindex(mine)
        seen[s] && continue
        pieces += 1; seen[s] = true; todo = [s]
        while !isempty(todo)
            v = pop!(todo)
            for w in eachindex(mine)
                (!seen[w] && adjacent(mine[v], mine[w])) && (seen[w] = true; push!(todo, w))
            end
        end
    end
    return pieces
end
# fixed rule (D-074) and the defect, on the oracle's piece count
p60m_rule(σ, x, old, hex) = old == 0 || p60m_pieces(σ, x, old, hex) == 1
p60m_buggy(σ, x, old, hex) = old == 0 || p60m_pieces(σ, x, old, hex) <= 1
# the full `Local()` default (re-frozen under D-189 rulings 3 and 10, D-191 CC3D rules 1 and
# 2): the exactly-one rule, plus (ruling 10) a full ring of `old` (every ring site in the
# domain and owned by `old`) is refused, plus (ruling 3) the gaining owner `new` (the medium
# included) must own a face neighbour of x (square: the 4 face sites; hex: all 6 ring sites)
function p60m_local(σ, x, old, new, hex)
    old == 0 && return true
    offs = hex ? P60M_HEX : P60M_MOORE
    n1, n2 = size(σ)
    ring = [(x[1] + o[1], x[2] + o[2]) for o in offs]
    inside(y) = 1 <= y[1] <= n1 && 1 <= y[2] <= n2
    all(y -> inside(y) && σ[y...] == old, ring) && return false          # full ring
    p60m_pieces(σ, x, old, hex) == 1 || return false
    return any(o -> (hex || abs(o[1]) + abs(o[2]) == 1) && inside(x .+ o) && σ[(x .+ o)...] == new, offs)
end

@testset "P6.0m: connectivity(k) rejects zero components ($label)" for (label, geo, nb, hex) in
                                                                       (("square", CorePotts.Square(), Moore(1), false),
                                                                        ("hex", Hexagonal(), Hex(1), true))
    build(σ) = PottsProblem(ConnOne(; name = :c1, geometry = geo, near = nb), [ownership => σ, kind => [:A]], (0, 1))
    # (a) the cell's last site: σ[6,6] alone; medium at (7,6) copies into it. The ring of
    #     (6,6) holds no site of cell 1 → 0 pieces → rejected.
    σ = zeros(Int32, 12, 12); σ[6, 6] = 1
    prob = build(σ); prop = p60m_prop(prob.lattice, σ, (6, 6), (7, 6))
    @test p60m_pieces(σ, (6, 6), 1, hex) == 0
    @test !p60m_rule(σ, (6, 6), 1, hex) && p60m_buggy(σ, (6, 6), 1, hex)   # negative control
    @test !p60m_allows(prob, prob.u0, prop)          # DEFECT CHECK (currently allowed)
    # (b) an isolated fragment site: block rows/cols 3:6 plus σ[10,10]; medium at (11,10)
    #     copies into (10,10). Its ring (square and hex) touches no other site of cell 1.
    σ = zeros(Int32, 12, 12); σ[3:6, 3:6] .= 1; σ[10, 10] = 1
    prob = build(σ); prop = p60m_prop(prob.lattice, σ, (10, 10), (11, 10))
    @test p60m_pieces(σ, (10, 10), 1, hex) == 0
    @test !p60m_allows(prob, prob.u0, prop)          # DEFECT CHECK (currently allowed)
    # (c) a bridge: the line σ[3:9, 6]; medium at (6,7) copies into (6,6). Cell-1 ring
    #     sites: (5,6), (7,6) — offsets (∓1, 0), not adjacent on either lattice → 2 pieces.
    σ = zeros(Int32, 12, 12); σ[3:9, 6] .= 1
    prob = build(σ); prop = p60m_prop(prob.lattice, σ, (6, 6), (6, 7))
    @test p60m_pieces(σ, (6, 6), 1, hex) == 2
    @test !p60m_allows(prob, prob.u0, prop)          # still rejected
    # (d) an ordinary boundary copy: block 3:6 × 3:6; medium at (7,4) copies into (6,4).
    #     Square ring: (5,3),(5,4),(5,5),(6,3),(6,5) — face-connected via (5,3)-(6,3) and
    #     (5,5)-(6,5) → 1 piece. Hex ring (offsets): (0,1)→(6,5), (-1,1)→(5,5), (-1,0)→(5,4),
    #     (0,-1)→(6,3) are cell 1, (1,0)→(7,4) and (1,-1)→(7,3) are medium → one arc.
    σ = zeros(Int32, 12, 12); σ[3:6, 3:6] .= 1
    prob = build(σ); prop = p60m_prop(prob.lattice, σ, (6, 4), (7, 4))
    @test p60m_pieces(σ, (6, 4), 1, hex) == 1
    @test p60m_allows(prob, prob.u0, prop)           # still accepted
    # (e) oracle emulation over every proposal of a scattered state: the constraint equals
    #     the exactly-one rule with `Local()`'s gain test and full-ring refusal (re-frozen
    #     under D-189 rulings 3 and 10: on the square lattice diagonal Moore sources now meet
    #     the gain test); the sample contains copies where the defect differs.
    σ = zeros(Int32, 12, 12)
    for i in 1:12, j in 1:12
        σ[i, j] = Int32(mod(i * 7 + j * 13 + i * j, 5) < 2 ? 1 + mod(i + j, 3) : 0)
    end
    prob = PottsProblem(ConnOne(; name = :c1, geometry = geo, near = nb), [ownership => σ, kind => [:A, :A, :A]], (0, 1))
    offs = hex ? P60M_HEX : P60M_MOORE
    got = Bool[]; want = Bool[]; differs = 0
    for i in 2:11, j in 2:11, o in offs
        y = (i + o[1], j + o[2])
        σ[i, j] == σ[y...] && continue
        push!(got, p60m_allows(prob, prob.u0, p60m_prop(prob.lattice, σ, (i, j), y)))
        push!(want, p60m_local(σ, (i, j), σ[i, j], σ[y...], hex))
        differs += p60m_rule(σ, (i, j), σ[i, j], hex) != p60m_buggy(σ, (i, j), σ[i, j], hex)
    end
    @test differs > 0                                 # negative control: the sample can tell
    @test length(want) > 100
    @test got == want                                 # DEFECT CHECK (differs on 0-piece copies)
end

@testset "P6.0m: a connectivity-constrained single-site cell never disappears ($label, $(nameof(typeof(alg))))" for
    (label, geo, nb) in (("square", CorePotts.Square(), Moore(1)), ("hex", Hexagonal(), Hex(1))),
    alg in (SequentialCPM(; proposal = nb), CheckerboardCPM(; proposal = nb))
    # One site of kind A in medium; E = (volume - 1)^2 at T = 20. The last-site copy costs
    # (0-1)^2 - (1-1)^2 = +1, accepted with probability e^(-1/20) ≈ 0.95 unless constrained.
    # Under D-074 the last-site copy has 0 pieces and is rejected, so volume ≥ 1 at every
    # save for every seed (a hard guarantee, not a statistical one).
    σ = zeros(Int32, 12, 12); σ[6, 6] = 1
    op = [ownership => σ, kind => [:A]]
    held = PottsProblem(ConnOne(; name = :c1, geometry = geo, near = nb), op, (0, 20))
    free = PottsProblem(ConnFree(; name = :c0, geometry = geo, near = nb), op, (0, 20))
    lowest(prob, seed) = minimum(u -> Array(u.cell.volume)[1], solve(remake(prob; seed), alg).u)
    # negative control: without the constraint the cell dies in every seed (measured: by MCS 1)
    @test all(seed -> lowest(free, seed) == 0, 1:8)
    @test all(seed -> lowest(held, seed) >= 1, 1:8)   # DEFECT CHECK (currently dies)
end

# ---------------------------------------------------------------------------------------
# 3. `a` and `b` are reserved (the edge endpoints)

p60m_build(name, body) = mtkcompile(Base.invokelatest(eval(Potts._potts_model(name, body, @__MODULE__)); name = :m))

@testset "P6.0m: parameters and variables named `a` or `b` are rejected" begin
    # the reviewer's case: a parameter `b` used in an edge term, where `b` is the endpoint
    edge_body(bname) = quote
        @kinds medium A
        @parameters begin
            $bname = 5.0
            k = 1.0
        end
        @variables rest(edge) = 3.0
        @relationship bond(cell, cell) capacity = 1
        @lattice Lattice((20, 20))
        @energy begin
            cells => (volume - 16)^2
            edges(bond) => k * (distance - rest)^2 + $bname
        end
        @sweep Metropolis(; temperature = 1.0)
    end
    decl_body(decl) = quote
        @kinds medium A
        $decl
        @lattice Lattice((12, 12))
        @energy cells => (volume - 16)^2
        @sweep Metropolis(; temperature = 1.0)
    end
    # controls: the same bodies with other names build (the error below is the name)
    @test p60m_build(:P60mEdgeOK, edge_body(:bb)) isa Potts.CompiledPottsSystem
    @test p60m_build(:P60mDeclOK, decl_body(:(@parameters a2 = 3.0))) isa Potts.CompiledPottsSystem
    @test p60m_build(:P60mDeclOK2, decl_body(:(@variables b2(cell) = 0.0))) isa Potts.CompiledPottsSystem
    # DEFECT CHECKS (currently accepted); the message names the offending declaration
    @test_throws r"`b`" p60m_build(:P60mEdgeB, edge_body(:b))
    @test_throws ArgumentError p60m_build(:P60mEdgeB2, edge_body(:b))
    for (nm, decl) in (("a", :(@parameters a = 3.0)), ("b", :(@parameters b = 5.0)),
                       ("a", :(@variables a(cell) = 0.0)), ("b", :(@variables b(site) = 0.0)),
                       ("a", :(@variables a(model) = 1.0)))
        @test_throws ArgumentError p60m_build(:P60mDecl, decl_body(decl))
        @test_throws Regex("`$nm`") p60m_build(:P60mDecl, decl_body(decl))
    end
end

# ---------------------------------------------------------------------------------------
# 4. integral(x) of a site variable written in the same @after_mcs

@potts_model IntSameBlock begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        w ~ Pre(w) + 1
        s ~ integral(w)
    end
    @sweep Metropolis(; temperature = 0.0)
end

# control: written before the sweep, read after it (fresh today)
@potts_model IntSplitBlocks begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @before_mcs w ~ Pre(w) + 1
    @after_mcs s ~ integral(w)
    @sweep Metropolis(; temperature = 0.0)
end

@testset "P6.0m: integral(x) folds x's new value in the block that writes it ($(nameof(typeof(alg))))" for
    alg in (SequentialCPM(), CheckerboardCPM())
    # Cell 1 = 4×4 block (16 sites). E = (volume - 16)^2 at T = 0: every copy changes the
    # volume by ±1, ΔH = +1 > 0, rejected, so the cell keeps its 16 sites. w = k at every
    # site after MCS k. At save k: true sum over the cell = 16k → s = 0, 16, 32, 48.
    # The defect (integral refreshed before the block) gives 16(k-1): 0, 0, 16, 32.
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    truth = [16.0 * k for k in 0:3]
    stale = [16.0 * max(k - 1, 0) for k in 0:3]
    @test truth != stale                              # negative control: the check can tell
    for (M, which) in ((IntSplitBlocks, "split (control)"), (IntSameBlock, "same block"))
        sol = solve(PottsProblem(M(; name = :i), [ownership => σ, kind => [:A]], (0, 3)), alg; saveat = 0:3)
        @test [Array(u.cell.volume)[1] for u in sol.u] == fill(16, 4)
        @test [sum(Array(u.site.w)[Array(u.σ) .== 1]) for u in sol.u] == truth
        @test [Array(u.cell.s)[1] for u in sol.u] == truth   # DEFECT CHECK for "same block"
    end
end
