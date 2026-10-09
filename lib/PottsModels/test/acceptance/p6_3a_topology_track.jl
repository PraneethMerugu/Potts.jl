# P6.3a (ROADMAP Phase 6, step 3): R4 topology values dispatched on geometry, the soft E₀
# drive, the `Global()` placeholder, and the opt-in accepted-ΔH accumulator
# `track = (:ΔH,)` → `stats.accepted_ΔH` (D-075; 01 F9, model-spec 01 §7.7 / D-17).
# Decision: D-140. Frozen (AUTONOMY §7.3).
#
# Semantics pinned here:
#
# 1. Topology values on every geometry. The copy-scope values `ring_arcs`, `ring_cells`,
#    `ring_medium` (and `local_components`) read the target's neighbour SHELL:
#      - square 2D: the 8 Moore sites; hexagonal 2D: the 6 hex neighbours;
#      - cubic 3D: the 26 Moore sites (today: `MethodError`, the ring values are 2D-only).
#    An out-of-domain site (a `Closed()` face) reads as neither medium nor a cell; on a
#    `Periodic()` axis the shell wraps. With `old` the losing cell:
#      ring_arcs   = pieces of `old`'s shell sites, two shell sites adjacent iff they are
#                    lattice face neighbours (square/cubic: offsets differ by one unit along
#                    one axis; hex: offsets differ by a hex neighbour offset). 0 if old == 0.
#                    On a ring (2D) these pieces are exactly the arcs; in 3D they are the
#                    face-connected pieces of the 26-shell. So ring_arcs == local_components
#                    on every geometry (both pinned).
#      ring_cells  = distinct cell ids (> 0) on the shell;
#      ring_medium = shell sites owned by the medium (0).
#    The oracle below computes all of them independently (explicit offset lists and a BFS),
#    over random states on square, hex and 3D, Periodic and Closed; 3D also has hand-checked
#    fixtures. The values are read both through `CorePotts.ring_*` and through a compiled
#    `@drive` (the DSL dispatch).
# 2. The ring rules on hex and 3D: `connectivity(k; rule = :arc_or_pair)` (arcs ≤ 1, or two
#    cells and no medium on the shell) and `connectivity(k)` (`local_components == 1`),
#    hand-checked junctions (the P6.0aa fixtures transposed to hex and 3D).
# 3. The soft E₀ drive (01a p.49; TST `conn_diss`, model-spec 01 §7.3) is an ordinary
#    expression, no new DSL name:
#      @drive copy => E₀ * ((kind[old] == A) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))
#    Its ΔH equals the brute-force energy difference plus E₀ times an independently computed
#    break indicator, for every copy of random states on square, hex and 3D; it runs under
#    SequentialCPM and CheckerboardCPM in 3D. Sibling: soft (E₀) connectivity on a 3D lattice
#    keeps cells whole where E₀ = 0 (negative control) does not.
# 4. `Global(; window = nothing)` is a reserved DSL name (placeholder until P6.9): it
#    constructs (`window` is `nothing` or a positive integer, else `ArgumentError`). A
#    model that uses `!connected(old; rule = Global())` was an `ArgumentError` until P6.9;
#    re-frozen for P6.9a: it now builds and runs on every algorithm.
#    (Re-frozen under D-189 ruling 6: `components(old; scope = Global()) > 1` is gone, with
#    no alias; its meaning, "old is in more than one piece", is now `!connected(old; rule = …)`.)
#    Control: the same model with `local_components` builds.
# 5. `PottsProblem(sys, op, tspan; track = (:ΔH,))` accumulates Σ ΔH over the ACCEPTED
#    (committed) copies of every sweep into `sol.stats.accepted_ΔH::Float64`; ΔH is the
#    model's copy ΔH, energy plus every drive (what `prob.f.delta_H` returns), without the
#    acceptance law's offset. `track = ()` (the default) gives `stats.accepted_ΔH === nothing`.
#    Only `:ΔH` is a valid name for now; any other is an `ArgumentError`.
#    Oracle: with integer-valued energies and a drive that is the copy difference of a state
#    function G(σ) = μ Σ_x w[x]·[σ(x) ≠ 0], Σ accepted ΔH == Φ(end) − Φ(start), with
#    Φ = total_energy + G, exactly (Float64, integers). `no_extinction` keeps every copy
#    non-killing (no D-083 credit). Pinned on SequentialCPM (after every `step!` too) and
#    CheckerboardCPM (at the read points: end of `solve`, `checkpoint`), and with a
#    non-zero Metropolis offset (the offset is not accumulated).
#    Tracking leaves everything else unchanged: the same σ, columns, `accepted` and
#    `attempts`; the fingerprint without tracking is the one of the base (6abfd43c, pinned);
#    with tracking it differs (D-075 amends D-016: `track` is hashed). `remake(prob; track)`
#    switches it either way. Checkpoint continuation, `reinit!` and `merge` of stats carry
#    the accumulator.
#    The CPMFunction gains a `track` field (the CorePotts hook), `nothing` when off.
# 6. Metal (skipped without POTTS_GPU=metal and Metal loaded): CheckerboardCPM with Float32
#    tracks the same sum (integer-valued, so exact to rounding at the read points) and a
#    quiet MCS with tracking on makes 0 syncs, 0 transfers (the reduction runs only at read
#    points, D-140).
#
# Today this fails with: `MethodError: no method matching ring_arcs(::Array{Int32, 3}, …,
# ::Proposal{3})` (3D values, rules, E₀ drive, sibling), `MethodError: … PottsProblem(…;
# track::Tuple{Symbol})` (track), `UndefVarError: Global` / no `:Global` in `Potts.DSL`
# (placeholder), `FieldError: … CPMFunction has no field track`. The square and hex value
# and rule tests pass on the base (controls).
using Potts: CorePotts
using Statistics: mean

# ---------------------------------------------------------------------------------------
# Independent oracle for the shell values

const P63A_HEX = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
p63a_shell(geom::Symbol) =
    geom === :hex ? collect(P63A_HEX) :
    geom === :square ? [(i, j) for i in -1:1 for j in -1:1 if (i, j) != (0, 0)] :
    [(i, j, k) for i in -1:1 for j in -1:1 for k in -1:1 if (i, j, k) != (0, 0, 0)]
p63a_adjacent(geom, a, b) = geom === :hex ? (a .- b) in P63A_HEX : sum(abs, a .- b) == 1

"""Owner of site `x .+ o` (−1 outside a closed lattice)."""
function p63a_owner(σ, x, o; periodic)
    y = x .+ o
    if periodic
        y = map(mod1, y, size(σ))
    elseif !all(1 .<= y .<= size(σ))
        return -1
    end
    return Int(σ[y...])
end

"""(arcs, cells, medium) of the shell of `x` for the losing cell `σ[x]`, by explicit BFS."""
function p63a_ring_oracle(σ, x, geom; periodic)
    shell = p63a_shell(geom)
    old = Int(σ[x...])
    own = [p63a_owner(σ, x, o; periodic) for o in shell]
    cells = length(unique(filter(>(0), own)))
    medium = count(==(0), own)
    old == 0 && return (0, cells, medium)
    mine = [shell[k] for k in eachindex(shell) if own[k] == old]
    seen = falses(length(mine))
    pieces = 0
    for s in eachindex(mine)
        seen[s] && continue
        pieces += 1
        stack = [s]; seen[s] = true
        while !isempty(stack)
            a = pop!(stack)
            for b in eachindex(mine)
                (!seen[b] && p63a_adjacent(geom, mine[a], mine[b])) || continue
                seen[b] = true; push!(stack, b)
            end
        end
    end
    return (pieces, cells, medium)
end

p63a_breaks(r) = !((r[1] <= 1) | ((r[2] == 2) & (r[3] == 0)))   # the arc-or-pair predicate, negated

# ---------------------------------------------------------------------------------------
# Models: one readback model per (geometry, boundary). The drive encodes the three values
# as ring_arcs + 100 ring_cells + 10000 ring_medium (each < 100), so the compiled code's
# values are recovered from `delta_H − energy_change`.

const P63A_LATTICES = [
    (:square, true) => :(Lattice((9, 8); boundary = Periodic(), neighborhood = Moore(1))),
    (:square, false) => :(Lattice((9, 8); boundary = Closed(), neighborhood = Moore(1))),
    (:hex, true) => :(Lattice((9, 8); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1))),
    (:hex, false) => :(Lattice((9, 8); geometry = Hexagonal(), boundary = Closed(), neighborhood = Hex(1))),
    (:cubic, true) => :(Lattice((6, 5, 5); boundary = Periodic(), neighborhood = Moore(1))),
    (:cubic, false) => :(Lattice((6, 5, 5); boundary = Closed(), neighborhood = Moore(1))),
]
p63a_name(prefix, geom, periodic) = Symbol(prefix, uppercasefirst(string(geom)), periodic ? "Periodic" : "Closed")

for ((geom, periodic), lat) in P63A_LATTICES
    @eval @potts_model $(p63a_name("P63aRing", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @energy cells => (volume - 9)^2
        @drive copy => ring_arcs + 100 * ring_cells + 10000 * ring_medium
        @sweep Metropolis(; temperature = 1.0)
    end
    @eval @potts_model $(p63a_name("P63aSoft", geom, periodic)) begin
        @kinds medium A B
        @parameters begin
            E₀ = 2000.0
            J[kind, kind] = [0.0 6.0 6.0; 6.0 3.0 4.0; 6.0 4.0 3.0]
        end
        @lattice $lat
        @energy begin
            cells => (volume - 9)^2
            contacts => J[kind, kind′]
        end
        @drive copy => E₀ * ((kind[old] == A) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))
        @sweep Metropolis(; temperature = 4.0)
    end
end
p63a_model(prefix, geom, periodic) = getfield(@__MODULE__, p63a_name(prefix, geom, periodic))

"""A random state of labels 0:3 (medium about 1/4), every label present, kinds A, B, A."""
function p63a_random_σ(dims, seed)
    st = UInt64(seed) * 0x9E3779B97F4A7C15 + 1
    σ = zeros(Int32, dims)
    for i in eachindex(σ)
        st = st * 6364136223846793005 + 1442695040888963407
        σ[i] = Int32((st >> 33) % 4)
    end
    σ[1] = 1; σ[2] = 2; σ[3] = 3
    return σ
end
p63a_problem(M, σ; tspan = (0, 1), kw...) =
    PottsProblem(M(; name = :p63a), [ownership => σ, kind => [:A, :B, :A]], tspan; kw...)
p63a_prop(lat, x, y, σ) = CorePotts.Proposal(CorePotts.linear_index(lat, x), CorePotts.linear_index(lat, y),
    x, 1, σ[x...], σ[y...])

"""Every (target, shell neighbour) pair of `σ` with different owners, inside the lattice."""
function p63a_pairs(σ, geom; periodic)
    out = Tuple{Any, Any}[]
    for I in CartesianIndices(σ), o in p63a_shell(geom)
        x = Tuple(I)
        y = x .+ o
        if periodic
            y = map(mod1, y, size(σ))
        elseif !all(1 .<= y .<= size(σ))
            continue
        end
        σ[x...] == σ[y...] || push!(out, (x, y))
    end
    return out
end

# ---------------------------------------------------------------------------------------

@testset "P6.3a: shell values on $geom ($(periodic ? "Periodic" : "Closed")), random states" for ((geom, periodic), _) in P63A_LATTICES
    M = p63a_model("P63aRing", geom, periodic)
    nagree = ntotal = 0
    seen_arcs = Set{Int}()
    for seed in 1:3
        σ = p63a_random_σ(geom === :cubic ? (6, 5, 5) : (9, 8), seed)
        prob = p63a_problem(M, σ)
        u = prob.u0
        ctx = Potts._host_ctx(prob)
        for x in Tuple.(CartesianIndices(σ))
            σ[x...] == 0 && continue
            # any neighbour with another owner as the source (the values read only the target)
            ys = [y for (xx, y) in p63a_pairs(σ, geom; periodic) if xx == x]
            isempty(ys) && continue
            prop = p63a_prop(prob.lattice, x, first(ys), σ)
            want = p63a_ring_oracle(σ, x, geom; periodic)
            direct = (CorePotts.ring_arcs(u.σ, ctx, prop), CorePotts.ring_cells(u.σ, ctx, prop),
                CorePotts.ring_medium(u.σ, ctx, prop))
            lc = CorePotts.local_components(u.σ, ctx, prop)
            d = round(Int, prob.f.delta_H(u, prob.p, prop, ctx) - energy_change(prob, u, prop))
            compiled = (d % 100, (d ÷ 100) % 100, d ÷ 10000)
            ntotal += 1
            nagree += (direct == want) & (compiled == want) & (lc == want[1])
            push!(seen_arcs, want[1])
        end
    end
    @test nagree == ntotal
    @test ntotal >= 50
    @test length(seen_arcs) >= 3                       # non-vacuous: several piece counts occur
end

@testset "P6.3a: 3D shell values, hand-checked fixtures" begin
    # 7×7×7, target c = (4, 4, 4) owned by cell 1; listed sites are cell 1, the rest medium
    # unless stated. (arcs, cells, medium) by hand; 26 shell sites on the periodic lattice.
    c = (4, 4, 4)
    fixtures = [
        # two opposite faces: not face-adjacent → 2 pieces; 26 − 2 = 24 medium
        ([(-1, 0, 0), (1, 0, 0)], (2, 1, 24)),
        # bridged over the +y side: (−1,0,0)–(−1,1,0)–(0,1,0)–(1,1,0)–(1,0,0) → 1 piece; 21 medium
        ([(-1, 0, 0), (1, 0, 0), (-1, 1, 0), (0, 1, 0), (1, 1, 0)], (1, 1, 21)),
        # an edge diagonal alone does not connect: (−1,0,0) and (0,1,0) differ in two axes → 2
        ([(-1, 0, 0), (0, 1, 0)], (2, 1, 24)),
        # … the edge site (−1,1,0) joins them → 1
        ([(-1, 0, 0), (0, 1, 0), (-1, 1, 0)], (1, 1, 23)),
        # a corner and its face-adjacent edge site → 1
        ([(-1, -1, -1), (-1, -1, 0)], (1, 1, 24)),
        # the eight sites of the z = 0 ring form one piece → 1; 18 medium
        ([(i, j, 0) for i in -1:1 for j in -1:1 if (i, j) != (0, 0)], (1, 1, 18)),
        # top and bottom layers (9 + 9): 2 pieces; 8 medium (the z = 0 ring)
        ([(i, j, k) for i in -1:1 for j in -1:1 for k in (-1, 1)], (2, 1, 8)),
        # … plus (1, 0, 0), which touches (1,0,1) and (1,0,−1) → 1; 7 medium
        ([[(i, j, k) for i in -1:1 for j in -1:1 for k in (-1, 1)]; [(1, 0, 0)]], (1, 1, 7)),
        # three isolated corners → 3
        ([(-1, -1, -1), (1, 1, 1), (1, -1, 1)], (3, 1, 23)),
    ]
    for (sites, want) in fixtures
        σ = zeros(Int32, 7, 7, 7); σ[c...] = 1
        foreach(o -> σ[(c .+ o)...] = 1, sites)
        @test p63a_ring_oracle(σ, c, :cubic; periodic = true) == want         # the oracle agrees by hand
        lat = CorePotts.Lattice((7, 7, 7))                                    # periodic cubic
        ctx = (; lattice = lat)
        prop = p63a_prop(lat, c, (4, 4, 6), σ)      # the values read only the target and `old`
        @test (CorePotts.ring_arcs(σ, ctx, prop), CorePotts.ring_cells(σ, ctx, prop), CorePotts.ring_medium(σ, ctx, prop)) == want
        @test CorePotts.local_components(σ, ctx, prop) == want[1]
    end
    # a second cell on the shell: cell 2 at the +x face, cell 3 at a corner; medium 22
    σ = zeros(Int32, 7, 7, 7); σ[c...] = 1; σ[3, 4, 4] = 1; σ[5, 4, 4] = 2; σ[5, 5, 5] = 3; σ[4, 4, 5] = 2
    lat = CorePotts.Lattice((7, 7, 7)); ctx = (; lattice = lat)
    prop = CorePotts.Proposal(CorePotts.linear_index(lat, c), CorePotts.linear_index(lat, (5, 4, 4)), c, 1, Int32(1), Int32(2))
    @test (CorePotts.ring_arcs(σ, ctx, prop), CorePotts.ring_cells(σ, ctx, prop), CorePotts.ring_medium(σ, ctx, prop)) == (1, 3, 22)
    # Closed corner (1,1,1): only offsets in {0,1}³ are inside (7 sites); cell 1 at (2,1,1)
    σ = zeros(Int32, 7, 7, 7); σ[1, 1, 1] = 1; σ[2, 1, 1] = 1
    latc = CorePotts.Lattice((7, 7, 7); boundary = CorePotts.Closed()); ctxc = (; lattice = latc)
    prop = CorePotts.Proposal(CorePotts.linear_index(latc, (1, 1, 1)), CorePotts.linear_index(latc, (1, 2, 1)), (1, 1, 1), 1, Int32(1), Int32(0))
    @test (CorePotts.ring_arcs(σ, ctxc, prop), CorePotts.ring_cells(σ, ctxc, prop), CorePotts.ring_medium(σ, ctxc, prop)) == (1, 1, 6)
    # the same state periodic: all 26 inside, 25 medium
    prop = CorePotts.Proposal(CorePotts.linear_index(lat, (1, 1, 1)), CorePotts.linear_index(lat, (1, 2, 1)), (1, 1, 1), 1, Int32(1), Int32(0))
    @test (CorePotts.ring_arcs(σ, ctx, prop), CorePotts.ring_cells(σ, ctx, prop), CorePotts.ring_medium(σ, ctx, prop)) == (1, 1, 25)
    # pieces joined only across the periodic seam: target (1,4,4), cell 1 at (7,4,4) [−x,
    # wrapped] and (2,4,4) [+x]: periodic 2 pieces; closed: −x is outside → 1 piece, and
    # 17 − 1 = 16 medium (in-domain shell sites have x-offset 0 or 1: 2·9 − 1 = 17)
    σ = zeros(Int32, 7, 7, 7); σ[1, 4, 4] = 1; σ[7, 4, 4] = 1; σ[2, 4, 4] = 1
    x = (1, 4, 4)
    prop = CorePotts.Proposal(CorePotts.linear_index(lat, x), CorePotts.linear_index(lat, (1, 5, 4)), x, 1, Int32(1), Int32(0))
    @test (CorePotts.ring_arcs(σ, ctx, prop), CorePotts.ring_medium(σ, ctx, prop)) == (2, 24)
    @test (CorePotts.ring_arcs(σ, ctxc, prop), CorePotts.ring_medium(σ, ctxc, prop)) == (1, 16)
    # the medium as the losing owner: no arcs
    prop = CorePotts.Proposal(CorePotts.linear_index(lat, (4, 4, 2)), CorePotts.linear_index(lat, (4, 4, 1)), (4, 4, 2), 1, Int32(0), Int32(1))
    @test CorePotts.ring_arcs(σ, ctx, prop) == 0
end

# ---------------------------------------------------------------------------------------
# The ring rules on hex and 3D (the P6.0aa junctions)

@potts_model P63aPairHex begin
    @kinds medium A
    @lattice Lattice((12, 12); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1))
    @energy cells => (volume - 7)^2
    @constraint connectivity(A; rule = :arc_or_pair)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P63aLocalHex begin
    @kinds medium A
    @lattice Lattice((12, 12); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1))
    @energy cells => (volume - 7)^2
    @constraint connectivity(A)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P63aPairCubic begin
    @kinds medium A
    @lattice Lattice((7, 7, 7); boundary = Periodic(), neighborhood = Moore(1))
    @energy cells => (volume - 7)^2
    @constraint connectivity(A; rule = :arc_or_pair)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P63aLocalCubic begin
    @kinds medium A
    @lattice Lattice((7, 7, 7); boundary = Periodic(), neighborhood = Moore(1))
    @energy cells => (volume - 7)^2
    @constraint connectivity(A)
    @sweep Metropolis(; temperature = 1.0)
end

function p63a_allows(M, σ, x, y)
    prob = PottsProblem(M(; name = :r), [ownership => σ, kind => fill(:A, maximum(σ))], (0, 1))
    return prob.f.constraint(prob.u0, prob.p, p63a_prop(prob.lattice, x, y, σ), Potts._host_ctx(prob))
end

@testset "P6.3a: arc-or-pair and local rules on hex" begin
    # Hex 12×12, target (6,6) in a bar of cell 1 along q (rows 3:9 of column 6, i.e. offsets
    # (±1, 0) are cell 1); source (6,5) = cell 2, offset (0,−1). Ring order (1,0) (0,1)
    # (−1,1) (−1,0) (0,−1) (1,−1): 1 0 0 1 2 0 → arcs 2, cells 2, medium 3.
    x, y = (6, 6), (6, 5)
    σ = zeros(Int32, 12, 12); σ[3:9, 6] .= 1; σ[6, 5] = 2
    @test p63a_ring_oracle(σ, x, :hex; periodic = true) == (2, 2, 3)
    @test !p63a_allows(P63aPairHex, σ, x, y)          # medium on the ring: no pair exemption
    @test !p63a_allows(P63aLocalHex, σ, x, y)
    # cell 2 everywhere else: ring 1 2 2 1 2 2 → arcs 2, cells 2, medium 0
    σ2 = fill(Int32(2), 12, 12); σ2[3:9, 6] .= 1
    @test p63a_ring_oracle(σ2, x, :hex; periodic = true) == (2, 2, 0)
    @test p63a_allows(P63aPairHex, σ2, x, y)           # the pair exemption
    @test !p63a_allows(P63aLocalHex, σ2, x, y)         # the local rule still refuses
    # bridge (0,1) and (−1,1) to cell 1: ring 1 1 1 1 2 0 → one arc → both accept
    σ3 = copy(σ); σ3[6, 7] = 1; σ3[5, 7] = 1
    @test p63a_ring_oracle(σ3, x, :hex; periodic = true) == (1, 2, 1)
    @test p63a_allows(P63aPairHex, σ3, x, y) && p63a_allows(P63aLocalHex, σ3, x, y)
end

@testset "P6.3a: arc-or-pair and local rules on 3D" begin
    # 7³, target (4,4,4) in a bar of cell 1 along x (2:6, 4, 4); source (4,3,4) = cell 2.
    # Shell: cell 1 at (±1,0,0) → 2 pieces; cells 2; medium 26 − 3 = 23 → refused by both rules.
    x, y = (4, 4, 4), (4, 3, 4)
    σ = zeros(Int32, 7, 7, 7); σ[2:6, 4, 4] .= 1; σ[4, 3, 4] = 2
    @test p63a_ring_oracle(σ, x, :cubic; periodic = true) == (2, 2, 23)
    @test !p63a_allows(P63aPairCubic, σ, x, y)
    @test !p63a_allows(P63aLocalCubic, σ, x, y)
    # cell 2 everywhere else: 2 pieces, 2 cells, no medium → pair exemption only
    σ2 = fill(Int32(2), 7, 7, 7); σ2[2:6, 4, 4] .= 1
    @test p63a_ring_oracle(σ2, x, :cubic; periodic = true) == (2, 2, 0)
    @test p63a_allows(P63aPairCubic, σ2, x, y)
    @test !p63a_allows(P63aLocalCubic, σ2, x, y)
    # one medium site on the shell, (5,5,5): the exemption is gone
    σ2m = copy(σ2); σ2m[5, 5, 5] = 0
    @test !p63a_allows(P63aPairCubic, σ2m, x, y)
    # bridge over +y: (3,5,4), (4,5,4), (5,5,4) → one piece → both accept, medium or not
    σ3 = copy(σ); σ3[3:5, 5, 4] .= 1
    @test p63a_ring_oracle(σ3, x, :cubic; periodic = true) == (1, 2, 20)
    @test p63a_allows(P63aPairCubic, σ3, x, y) && p63a_allows(P63aLocalCubic, σ3, x, y)
end

# ---------------------------------------------------------------------------------------
# The soft E₀ drive

@testset "P6.3a: soft E₀ drive ΔH = brute force + E₀·[break], $geom ($(periodic ? "Periodic" : "Closed"))" for ((geom, periodic), _) in P63A_LATTICES
    M = p63a_model("P63aSoft", geom, periodic)
    E₀ = 2000.0
    worst = 0.0
    nbreak_A = nbreak_B = nkeep_A = 0
    for seed in 4:5
        σ = p63a_random_σ(geom === :cubic ? (6, 5, 5) : (9, 8), seed)
        prob = p63a_problem(M, σ)
        u = prob.u0
        ctx = Potts._host_ctx(prob)
        kinds = (:A, :B, :A)
        for (x, y) in p63a_pairs(σ, geom; periodic)
            prop = p63a_prop(prob.lattice, x, y, σ)
            old = prop.old
            (old != 0 && u.cell.volume[old] == 1) && continue           # no killing copies here
            a = deepcopy(u); a.σ[prop.target] = prop.new
            prob.f.commit!(a, prob.p, prop, ctx)
            brk = old != 0 && kinds[old] === :A && p63a_breaks(p63a_ring_oracle(σ, x, geom; periodic))
            want = total_energy(prob, a) - total_energy(prob, u) + E₀ * brk
            worst = max(worst, abs(prob.f.delta_H(u, prob.p, prop, ctx) - want))
            if old != 0
                b = p63a_breaks(p63a_ring_oracle(σ, x, geom; periodic))
                nbreak_A += b & (kinds[old] === :A); nbreak_B += b & (kinds[old] === :B)
                nkeep_A += !b & (kinds[old] === :A)
            end
        end
        # E₀ = 0: the drive vanishes (negative control on the indicator's weight)
        prob0 = remake(prob; p = [:E₀ => 0.0])
        for (x, y) in first(p63a_pairs(σ, geom; periodic), 40)
            prop = p63a_prop(prob0.lattice, x, y, σ)
            @test prob0.f.delta_H(u, prob0.p, prop, ctx) == energy_change(prob0, u, prop)
        end
    end
    @test worst < 1e-9
    @test nbreak_A > 0 && nkeep_A > 0 && nbreak_B > 0   # breaking copies of both kinds occur
end

@testset "P6.3a: soft E₀ drive runs in 3D under both algorithms" begin
    for (geom, periodic) in ((:cubic, true), (:cubic, false), (:hex, false))
        M = p63a_model("P63aSoft", geom, periodic)
        σ = p63a_random_σ(geom === :cubic ? (6, 5, 5) : (9, 8), 7)
        prob = p63a_problem(M, σ; tspan = (0, 3))
        for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM())
            sol = solve(prob, alg)
            @test Symbol(sol.retcode) === :Success
            u = sol.u[end]
            @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
        end
    end
end

# The soft-connectivity sibling: Merks' E₀ rule (arc-or-pair, soft) on a 3D lattice. Cells
# in a cheap medium (J_cM = 1) at T = 15 fragment with E₀ = 0 (negative control); with E₀ = 1e4
# (exp(−E₀/T) ≈ 0) the losing cell never splits locally and the 26-shell rule keeps every
# cell face-connected (VonNeumann(1) copies never gain a detached site).
@potts_model P63aSoftSibling3D begin
    @kinds medium A
    @parameters begin
        E₀ = 1.0e4
        λ = 1.0
        V₀ = 27.0
        T = 15.0
        J[kind, kind] = [0.0 1.0; 1.0 8.0]
    end
    @lattice Lattice((12, 12, 12); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(A) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @drive copy => E₀ * ((kind[old] == A) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))
    @sweep Metropolis(; temperature = T)
end

"""Number of cells of `σ` (3D periodic) with more than one face-connected piece."""
function p63a_split3(σ)
    n = 0
    for c in 1:maximum(σ)
        sites = findall(==(c), σ)
        isempty(sites) && continue
        seen = Set([first(sites)]); stack = [first(sites)]
        while !isempty(stack)
            I = pop!(stack)
            for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
                J = CartesianIndex(map(mod1, Tuple(I) .+ d, size(σ)))
                (σ[J] == c && !(J in seen)) || continue
                push!(seen, J); push!(stack, J)
            end
        end
        n += length(seen) < length(sites)
    end
    return n
end

@testset "P6.3a: soft-connectivity sibling (3D, E₀ drive)" begin
    σ = zeros(Int32, 12, 12, 12); k = 0
    for i in (2, 8), j in (2, 8), l in (2, 8)
        k += 1; σ[i:(i + 2), j:(j + 2), l:(l + 2)] .= k
    end
    nsplit = Dict{Float64, Int}()
    for E in (1.0e4, 0.0)
        n = 0
        for seed in 1:3
            prob = PottsProblem(P63aSoftSibling3D(; name = :s), [ownership => σ, kind => fill(:A, k)], (0, 40); seed)
            E == 0.0 && (prob = remake(prob; p = [:E₀ => 0.0]))
            sol = solve(prob, SequentialCPM(); saveat = 10:10:40)
            n += sum(p63a_split3(u.σ) for u in sol.u)      # the initial cubes are whole
        end
        nsplit[E] = n
    end
    # split cells summed over the snapshots at MCS 10, 20, 30, 40 of 3 seeds (8 cells each:
    # at most 96). Measured with the freeze stub: 0 and 70.
    @test nsplit[1.0e4] == 0                # the penalty keeps every cell whole
    @test nsplit[0.0] >= 30                 # control: without it cells fragment
end

# ---------------------------------------------------------------------------------------
# `Global()` placeholder

"""The exception thrown while defining and building `body` (a quoted model), or `nothing`."""
function p63a_build_error(body::Expr)
    try
        Core.eval(@__MODULE__, body)
    catch e
        return e isa LoadError ? e.error : e
    end
    return nothing
end

@testset "P6.3a: Global() is a DSL name that builds (P6.9a)" begin
    @test :Global in keys(Potts.DSL)
    G = Potts.DSL.Global
    @test G().window === nothing
    @test G(; window = 8).window == 8
    @test_throws ArgumentError G(; window = 0)
    @test_throws ArgumentError G(; window = -2)
    for (name, alg) in ((:P63aGlobalSeq, :(SequentialCPM())), (:P63aGlobalCb, :(CheckerboardCPM())))
        e = p63a_build_error(quote
            @potts_model $name begin
                @kinds medium A
                @lattice Lattice((10, 10); neighborhood = Moore(1))
                @energy cells => (volume - 9)^2
                @drive copy => 100.0 * !connected(old; rule = Global())
                @sweep Metropolis(; temperature = 1.0)
            end
            let σ = zeros(Int32, 10, 10)
                σ[3:5, 3:5] .= 1
                solve(PottsProblem($name(; name = :g), [ownership => σ, kind => [:A]], (0, 1)), $alg)
            end
        end)
        # re-frozen for P6.9a: `Global()` is now a rule value and builds and runs (it was an
        # ArgumentError placeholder until P6.9)
        @test e === nothing
    end
    # control: the local value in the same place builds and runs
    e = p63a_build_error(quote
        @potts_model P63aLocalOk begin
            @kinds medium A
            @lattice Lattice((10, 10); neighborhood = Moore(1))
            @energy cells => (volume - 9)^2
            @drive copy => 100.0 * (local_components > 1)
            @sweep Metropolis(; temperature = 1.0)
        end
        let σ = zeros(Int32, 10, 10)
            σ[3:5, 3:5] .= 1
            solve(PottsProblem(P63aLocalOk(; name = :g), [ownership => σ, kind => [:A]], (0, 1)), CheckerboardCPM())
        end
    end)
    @test e === nothing
end

# ---------------------------------------------------------------------------------------
# track = (:ΔH,) → stats.accepted_ΔH

@potts_model P63aTrack begin
    @kinds medium A
    @parameters begin
        λ = 2.0
        V₀ = 24.0
        μ = 3.0
        T = 12.0
        J[kind, kind] = [0.0 8.0; 8.0 5.0]
    end
    @variables w(site) = 0.0
    @lattice Lattice((24, 24); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @drive copy => μ * w[target] * (ifelse(new == 0, 0.0, 1.0) - ifelse(old == 0, 0.0, 1.0))
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end
@potts_model P63aTrackOffset begin
    @kinds medium A
    @parameters begin
        λ = 2.0
        V₀ = 24.0
        μ = 3.0
        T = 12.0
        J[kind, kind] = [0.0 8.0; 8.0 5.0]
    end
    @variables w(site) = 0.0
    @lattice Lattice((24, 24); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @drive copy => μ * w[target] * (ifelse(new == 0, 0.0, 1.0) - ifelse(old == 0, 0.0, 1.0))
    @constraint no_extinction
    @sweep Metropolis(; temperature = T, offset = 3.0)
end

# fingerprint of `p63a_track_problem()` without tracking, recorded on the base (6abfd43c)
const P63A_TRACK_FINGERPRINT = 0xfaf6f0df2f2a1b79

const P63A_W = [Float64((3i + 5j) % 5) for i in 1:24, j in 1:24]     # integer weights 0:4
function p63a_track_σ()
    σ = zeros(Int32, 24, 24); k = 0
    for i in 3:8:19, j in 3:8:19
        k += 1; σ[i:(i + 3), j:(j + 3)] .= k
    end
    return σ
end
p63a_track_problem(M = P63aTrack; T = Float64, tspan = (0, 12), seed = 5, kw...) =
    PottsProblem(M(; name = :tr), [ownership => p63a_track_σ(), kind => fill(:A, 9), :w => copy(P63A_W)], tspan;
        T, seed, kw...)
"""Φ = H + G: the state function whose difference the accepted ΔH must equal."""
p63a_Φ(prob, u) = total_energy(prob, u) + 3.0 * sum(P63A_W[i] for i in eachindex(P63A_W) if u.σ[i] != 0)
p63a_G(u) = 3.0 * sum(P63A_W[i] for i in eachindex(P63A_W) if u.σ[i] != 0)
p63a_same(u, v) = u.σ == v.σ && u.cell == v.cell && u.site == v.site && u.model == v.model

@testset "P6.3a: track keyword, off by default" begin
    prob = p63a_track_problem()
    @test prob.f.fingerprint == P63A_TRACK_FINGERPRINT                  # unchanged from the base
    @test p63a_track_problem(; track = ()).f.fingerprint == P63A_TRACK_FINGERPRINT
    @test :track in fieldnames(CorePotts.CPMFunction)                   # the CorePotts hook
    @test prob.f.track === nothing                                      # off: nothing compiled
    on = p63a_track_problem(; track = (:ΔH,))
    @test on.f.track !== nothing
    @test on.f.fingerprint != P63A_TRACK_FINGERPRINT                    # D-075: track is hashed
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test solve(prob, alg).stats.accepted_ΔH === nothing
        @test solve(p63a_track_problem(; track = ()), alg).stats.accepted_ΔH === nothing
    end
    @test_throws ArgumentError p63a_track_problem(; track = (:chemo,))
    @test_throws ArgumentError p63a_track_problem(; track = (:ΔH, :foo))
    # remake switches it both ways and lands on the same fingerprints
    @test remake(prob; track = (:ΔH,)).f.fingerprint == on.f.fingerprint
    @test remake(on; track = ()).f.fingerprint == P63A_TRACK_FINGERPRINT
    @test remake(on; track = ()).f.track === nothing
end

@testset "P6.3a: accepted_ΔH = Φ(end) − Φ(start) ($(nameof(typeof(alg))), $(M === P63aTrack ? "offset 0" : "offset 3"))" for
        alg in (SequentialCPM(), CheckerboardCPM()), M in (P63aTrack, P63aTrackOffset)
    off = p63a_track_problem(M)
    on = p63a_track_problem(M; track = (:ΔH,))
    a, b = solve(off, alg), solve(on, alg)
    u0, u = on.u0, b.u[end]
    acc = b.stats.accepted_ΔH
    @test acc isa Float64
    @test acc == p63a_Φ(on, u) - p63a_Φ(on, u0)                         # exact: integer-valued
    # non-vacuous: the energy and the drive both move, so leaving out the drive would fail
    @test abs(p63a_G(u) - p63a_G(u0)) >= 30                             # measured ≥ 57
    @test abs(total_energy(on, u) - total_energy(on, u0)) >= 10       # measured ≥ 21 (base RNG)
    @test acc != total_energy(on, u) - total_energy(on, u0)
    # tracking changes nothing else
    @test p63a_same(a.u[end], u)
    @test a.stats.attempts == b.stats.attempts && a.stats.accepted == b.stats.accepted
    @test a.t == b.t
    # a remade problem tracks the same run
    @test solve(remake(off; track = (:ΔH,)), alg).stats.accepted_ΔH == acc
end

@testset "P6.3a: accepted_ΔH at every step (SequentialCPM) and at checkpoints (CheckerboardCPM)" begin
    on = p63a_track_problem(; track = (:ΔH,))
    Φ0 = p63a_Φ(on, on.u0)
    integ = init(on, SequentialCPM(); save_start = false, save_end = false)
    for _ in 1:6
        step!(integ)
        @test integ.stats.accepted_ΔH == p63a_Φ(on, integ.u) - Φ0
    end
    integ = init(on, CheckerboardCPM(); save_start = false, save_end = false)
    for _ in 1:3
        step!(integ); step!(integ)
        ck = checkpoint(integ)
        @test ck.stats.accepted_ΔH == p63a_Φ(on, ck.state) - Φ0
    end
end

@testset "P6.3a: accepted_ΔH across checkpoint, reinit! and merge" begin
    on = p63a_track_problem(; track = (:ΔH,))
    full = solve(on, SequentialCPM()).stats.accepted_ΔH
    integ = init(on, SequentialCPM())
    for _ in 1:5
        step!(integ)
    end
    ck = checkpoint(integ)
    i2 = init(on, SequentialCPM(); checkpoint = ck)
    @test solve!(i2).stats.accepted_ΔH == full                     # cumulative across the restart
    # a checkpoint of the untracked problem does not load into the tracked one (fingerprint)
    ioff = init(p63a_track_problem(), SequentialCPM()); step!(ioff)
    @test_throws ArgumentError init(on, SequentialCPM(); checkpoint = checkpoint(ioff))
    # reinit! clears it: the same run again gives the same sum
    integ = init(on, SequentialCPM())
    s1 = solve!(integ).stats.accepted_ΔH
    reinit!(integ)
    @test integ.stats.accepted_ΔH == 0.0
    @test solve!(integ).stats.accepted_ΔH == s1 == full
    # ensemble totals add; untracked stays nothing
    s2 = solve(p63a_track_problem(; track = (:ΔH,), seed = 9), SequentialCPM()).stats
    @test merge(solve(on, SequentialCPM()).stats, s2).accepted_ΔH == full + s2.accepted_ΔH
    @test merge(solve(p63a_track_problem(), SequentialCPM()).stats,
        solve(p63a_track_problem(; seed = 9), SequentialCPM()).stats).accepted_ΔH === nothing
end

# ---------------------------------------------------------------------------------------
# Metal

const P63A_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()

@testset "P6.3a: track on the device (CheckerboardCPM, Float32)" begin
    if P63A_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM()
        off = p63a_track_problem(; T = Float32)
        on = p63a_track_problem(; T = Float32, track = (:ΔH,))
        a, b = solve(off, alg; backend), solve(on, alg; backend)
        Φ0 = p63a_Φ(on, on.u0)
        @test b.stats.accepted_ΔH isa Float64
        @test isapprox(b.stats.accepted_ΔH, p63a_Φ(on, b.u[end]) - Φ0; atol = 0.5)
        @test p63a_same(a.u[end], b.u[end])
        @test a.stats.attempts == b.stats.attempts
        @test solve(off, alg; backend).stats.accepted_ΔH === nothing
        # no per-MCS sync: a quiet MCS costs 0 syncs and 0 transfers, tracked or not
        for prob in (off, on)
            integ = init(prob, alg; backend, save_start = false, save_end = false)
            step!(integ)
            for _ in 1:4
                c0 = (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes)
                step!(integ)
                @test (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes) .- c0 == (0, 0, 0)
            end
            if prob === on                                       # exact at the read point
                ck = checkpoint(integ)
                @test isapprox(ck.stats.accepted_ΔH, p63a_Φ(on, ck.state) - Φ0; atol = 0.5)
            end
        end
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
