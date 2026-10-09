# P6.3j (ROADMAP Phase 6, step 3; D-189 ruling 12): the cell-scope Euler-characteristic
# tracker. Decision: D-192 (design note docs/design/research/euler-tracker.md). Frozen
# (AUTONOMY §7.3).
#
# Semantics pinned here:
#
#  1. Surface (note §2.1). `euler` is a cell built-in: the Euler characteristic χ of the
#     cell's site set, exact after every copy, like `volume` and `surface`.
#      - cell scope (`@energy cells(k) => …`, `@observed q(cell) ~ …`): `euler` (face
#        adjacency) and `euler(; adjacency = :face | :full)`;
#      - copy scope (`@drive copy => …`): the before-values `euler[c]` and
#        `euler(c; adjacency = :face | :full)` with `c` in {old, new}; the medium reads 0
#        (as `volume[c]`). A bare `euler` in a drive is an `ArgumentError` (as `volume`).
#     The state carries one `Int32` column per adjacency the model reads (D-192):
#     `cell.euler` (`:face`) and `cell.euler_full` (`:full`), tracked whenever the model
#     reads `euler`, in an energy, a drive or only in `@observed` (D-192 Q5). The observed
#     values equal the columns.
#  2. What χ is (note §1.1, the Rosenfeld pairing). The cell X under the named adjacency,
#     its complement under the dual one:
#      - square `:face` 4/8 (graph complex: sites, 4-adjacent pairs, full 2×2 blocks);
#      - square `:full` 8/4 (union of closed unit pixels);
#      - hex (6/6, the only adjacency): sites, adjacent pairs, triangles;
#      - cubic `:face` 6/26 (sites, 6-adjacent pairs, full 2×2 squares, full 2×2×2 cubes);
#      - cubic `:full` 26/6 (union of closed unit voxels).
#     Out-of-domain sites are never in X (closed faces: note §1.4). On a periodic axis χ is
#     that of the subcomplex of the torus (D-192 Q2): a band round the torus reads 0.
#  3. Oracles, independent of the kernel: (a) a recount of the complex above, exact on tori;
#     (b) flood fills of the cell (its adjacency) and of its complement (the dual
#     adjacency), χ = pieces − bounded complement pieces in 2D and hex, on closed lattices
#     and on periodic ones when the cell does not wrap; in 3D the floods give b₀ and the
#     cavities b₂ and the recount must leave b₁ = b₀ + b₂ − χ ≥ 0. (a) and (b) agree, and
#     match hand values on reference shapes (passes on the base: the oracle is checked
#     before it judges anything).
#  4. Exactness: after random copy sequences of real integrators (SequentialCPM, CPU
#     CheckerboardCPM, BoundarySiteCPM), checked after every MCS, on square 12×12, hex
#     10×10 and cubic 6×6×6, Closed and Periodic, both adjacencies (hex: `:face`), the
#     tracked columns equal oracle (a) for every cell (dead cells read 0). Also after
#     divisions (the lifecycle rebuild) and at t = 0 (the initial rebuild).
#  5. Energies: `energy_change` (and `delta_H` with a drive) equals the brute-force
#     difference of the energy computed from oracle χ, for every copy of random states;
#     `total_energy` equals the brute-force energy; `commit!` leaves the columns equal to
#     the oracle. Float64 and Float32.
#  6. Build errors: `adjacency = :full` on a hexagonal lattice (D-192 Q4), in an energy, a
#     drive or `@observed`, is an `ArgumentError` naming the hexagonal lattice; an unknown
#     adjacency is an `ArgumentError` listing `:face` and `:full`; a bare `euler` in a drive
#     is an `ArgumentError`. Controls: `:face` (explicit or default) on hex builds.
#  7. Negative controls (they test the test): a test-side incremental tracker built from the
#     note's closed forms passes the same oracle harness on every geometry, and each mutant
#     is caught: a wrong sign (gaining side; and the 3D duality sign), the wrong adjacency
#     (the `:face` update used for `:full`), and a skipped losing-cell update. In the
#     compiled model the two adjacencies' columns differ where they must (the diamond).
#  8. Cost (D-171, D-058 item 4): a model that never names `euler` has no euler column, no
#     "euler" in any generated expression, and the fingerprint recorded on the base
#     (2b128db5) for each fixture below. A model that reads `euler` makes zero warm
#     allocations per `step!` (CPU: SequentialCPM, CheckerboardCPM, BoundarySiteCPM).
#  9. Device (POTTS_GPU=metal|rocm, else `@test_skip`): CheckerboardCPM in Float32 tracks
#     `euler` exactly (Int32 columns equal oracle (a)).
#
# Today this fails with `UndefVarError: euler not defined` at every model that names
# `euler` (sections 1, 4, 5, 6 controls, 7 compiled, 8 allocations, 9). The oracle checks,
# the test-side negative controls, the fingerprint pins and the no-column checks pass on
# the base (controls).
using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Geometry (index space). Hex: axial offsets, listed in cyclic order round the site.

const P63J_HEX = ((1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1))
const P63J_SQ4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
const P63J_SQ8 = Tuple((i, j) for i in -1:1 for j in -1:1 if (i, j) != (0, 0))
const P63J_CU6 = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
const P63J_CU26 = Tuple((i, j, k) for k in -1:1 for j in -1:1 for i in -1:1 if (i, j, k) != (0, 0, 0))

"""Neighbour offsets of `adj` on `geom` (hex has one adjacency)."""
p63j_nbrs(geom, adj) = geom === :hex ? P63J_HEX :
                       geom === :square ? (adj === :face ? P63J_SQ4 : P63J_SQ8) :
                       (adj === :face ? P63J_CU6 : P63J_CU26)
p63j_dual(adj) = adj === :face ? :full : :face
p63j_adjs(geom) = geom === :hex ? (:face,) : (:face, :full)

"""`X[i]`, wrapped on a periodic lattice; false outside a closed one."""
function p63j_get(X, i, periodic)
    L = size(X)
    if periodic
        return X[map(mod1, i, L)...]
    end
    all(k -> 1 <= i[k] <= L[k], eachindex(i)) || return false
    return X[i...]
end

# ---------------------------------------------------------------------------------------
# Oracle (a): the complex recount (exact on tori; every periodic axis ≥ 3 here)

"""Graph complex: sites − adjacent pairs + full 2-cells (− full 3-cells), square/cubic `:face`."""
function p63j_chi_graph(X, periodic)
    g(i) = p63j_get(X, i, periodic)
    d = ndims(X)
    χ = 0
    for I in CartesianIndices(X)
        i = Tuple(I)
        χ += g(i)
        for a in 1:d                                          # edges along each axis
            e = ntuple(k -> k == a ? 1 : 0, d)
            χ -= g(i) & g(i .+ e)
        end
        for a in 1:d, b in (a + 1):d                          # full 2×2 squares
            sq = all(g(i .+ ntuple(k -> k == a ? u : k == b ? v : 0, d)) for u in 0:1, v in 0:1)
            χ += sq
        end
        if d == 3                                             # full 2×2×2 cubes
            χ -= all(g(i .+ (u, v, w)) for u in 0:1, v in 0:1, w in 0:1)
        end
    end
    return χ
end

"""Union of closed unit pixels/voxels (`:full`): vertices − edges + faces (− cubes)."""
function p63j_chi_closed(X, periodic)
    L = size(X)
    d = ndims(X)
    w(j) = periodic ? ntuple(k -> mod(j[k], L[k]), d) : j
    cells = [Set{Any}() for _ in 0:d]                          # by dimension
    for I in CartesianIndices(X)
        X[I] || continue
        i = Tuple(I)
        # every face of the closed unit cube [i, i + 1]: a corner c ∈ i + {0,1}^d and the
        # set of axes it spans (the axes not spanned sit at the corner's value)
        for span in Iterators.product(ntuple(_ -> (false, true), d)...)
            for o in Iterators.product(ntuple(k -> span[k] ? (0,) : (0, 1), d)...)
                push!(cells[count(span) + 1], (w(i .+ o), span))
            end
        end
    end
    return sum((-1)^k * length(cells[k + 1]) for k in 0:d)
end

"""Hex triangulation: sites − adjacent pairs + triangles of mutually adjacent sites."""
function p63j_chi_hex(X, periodic)
    g(i) = p63j_get(X, i, periodic)
    χ = 0
    for I in CartesianIndices(X)
        i = Tuple(I)
        χ += g(i)
        for e in ((1, 0), (0, 1), (-1, 1))                    # one of each opposite pair
            χ -= g(i) & g(i .+ e)
        end
        χ += g(i) & g(i .+ (1, 0)) & g(i .+ (0, 1))
        χ += g(i .+ (1, 0)) & g(i .+ (0, 1)) & g(i .+ (1, 1))
    end
    return χ
end

"""Oracle (a): χ of the site set `X` under `adj` on `geom`."""
p63j_chi(X, geom, adj; periodic) =
    geom === :hex ? p63j_chi_hex(X, periodic) :
    adj === :face ? p63j_chi_graph(X, periodic) : p63j_chi_closed(X, periodic)

# ---------------------------------------------------------------------------------------
# Oracle (b): flood fills of the cell and of its complement (dual adjacency)

"""(pieces, pieces touching the array's border) of `M` under the offsets `nbrs` (closed)."""
function p63j_pieces(M, nbrs)
    seen = falses(size(M))
    n = 0
    touching = 0
    L = size(M)
    for I in CartesianIndices(M)
        (M[I] && !seen[I]) || continue
        n += 1
        t = false
        stack = [Tuple(I)]
        seen[I] = true
        while !isempty(stack)
            j = pop!(stack)
            any(k -> j[k] == 1 || j[k] == L[k], eachindex(j)) && (t = true)
            for o in nbrs
                y = j .+ o
                all(k -> 1 <= y[k] <= L[k], eachindex(y)) || continue
                (M[y...] && !seen[y...]) || continue
                seen[y...] = true
                push!(stack, y)
            end
        end
        touching += t
    end
    return n, touching
end

"""`X` translated on the torus so that it misses the first slab of every axis, or `nothing`
when on some axis it meets every slab (it may wrap; flood fills do not apply)."""
function p63j_unwrapped(X)
    Y = X
    for a in 1:ndims(X)
        free = findfirst(s -> !any(selectdim(Y, a, s)), 1:size(X, a))
        free === nothing && return nothing
        Y = circshift(Y, ntuple(k -> k == a ? 1 - free : 0, ndims(X)))
    end
    return Y
end

"""Oracle (b) on a non-wrapping (or closed) site set: 2D/hex → χ; 3D → (b₀, b₂)."""
function p63j_flood(X, geom, adj)
    P = falses(size(X) .+ 2)
    P[(2:(n + 1) for n in size(X))...] .= X               # padded: outside is background
    b0, _ = p63j_pieces(P, p63j_nbrs(geom, adj))
    nc, touching = p63j_pieces(.!P, p63j_nbrs(geom, p63j_dual(adj)))
    bounded = nc - touching                               # holes (2D) or cavities (3D)
    return geom === :cubic ? (b0, bounded) : b0 - bounded
end

"""The oracle value of cell `c` and whether (b) agreed with (a) (`nothing`: (b) not applicable)."""
function p63j_oracle(σ, c, geom, adj; periodic)
    X = σ .== c
    χ = p63j_chi(X, geom, adj; periodic)
    Y = periodic ? p63j_unwrapped(X) : X
    Y === nothing && return χ, nothing
    f = p63j_flood(Y, geom, adj)
    ok = geom === :cubic ? (f[1] + f[2] - χ >= 0) : (f == χ)
    # on a torus a non-wrapping cell has its planar χ
    periodic && (ok &= p63j_chi(Y, geom, adj; periodic = false) == χ)
    return χ, ok
end

"""Oracle χ of every cell 1:n of `σ` (dead cells: 0), counting oracle disagreements."""
function p63j_oracle_all(σ, n, geom, adj; periodic)
    vals = zeros(Int, n)
    bad = 0
    flooded = 0
    for c in 1:n
        vals[c], ok = p63j_oracle(σ, c, geom, adj; periodic)
        ok === nothing && continue
        flooded += 1
        bad += !ok
    end
    return vals, bad, flooded
end

# ---------------------------------------------------------------------------------------
# A test-side incremental tracker from the note's closed forms (§1.2), for the negative
# controls: correct, it passes the harness; each mutant must be caught.

const P63J_RING2 = ((-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1))  # bit k-1
const P63J_FACE4 = UInt32(0b10101010)
const P63J_TRIOS2 = (UInt32(0b10000011), UInt32(0b00001110), UInt32(0b00111000), UInt32(0b11100000))
p63j_bit3(o) = UInt32(1) << (findfirst(==(o), P63J_CU26) - 1)
const P63J_FACE6 = reduce(|, p63j_bit3(o) for o in P63J_CU6)
const P63J_TRIOS3 = [p63j_bit3(o) | p63j_bit3(ntuple(k -> k == a ? o[a] : 0, 3)) | p63j_bit3(ntuple(k -> k == b ? o[b] : 0, 3))
                     for o in P63J_CU26 if count(!=(0), o) == 2
                     for (a, b) in ((findfirst(!=(0), o), findlast(!=(0), o)),)]
const P63J_OCTS = [reduce(|, p63j_bit3(o) for o in P63J_CU26 if all(k -> o[k] == 0 || o[k] == s[k], 1:3))
                   for s in Iterators.product((-1, 1), (-1, 1), (-1, 1))]
p63j_has(m, t) = (m & t) == t
p63j_D4(m) = 1 - count_ones(m & P63J_FACE4) + count(t -> p63j_has(m, t), P63J_TRIOS2)
p63j_Dhex(m) = 1 - count_ones(m) + count_ones(m & ((m >> 1) | ((m & 0x1) << 5)))
p63j_D6(m) = 1 - count_ones(m & P63J_FACE6) + count(t -> p63j_has(m, t), P63J_TRIOS3) - count(t -> p63j_has(m, t), P63J_OCTS)
p63j_shell(geom) = geom === :hex ? P63J_HEX : geom === :square ? P63J_RING2 : P63J_CU26

"""Owner of site `y` (−1 outside a closed lattice)."""
function p63j_owner(σ, y, periodic)
    periodic && return Int(σ[map(mod1, y, size(σ))...])
    all(k -> 1 <= y[k] <= size(σ, k), eachindex(y)) || return -1
    return Int(σ[y...])
end

"""Membership mask of cell `c` on the shell of `x` (x itself excluded)."""
function p63j_mask(σ, x, c, geom; periodic)
    m = UInt32(0)
    for (k, o) in enumerate(p63j_shell(geom))
        p63j_owner(σ, x .+ o, periodic) == c && (m |= UInt32(1) << (k - 1))
    end
    return m
end

"""Δχ when the target is added to a set with shell mask `m` (`mutant` changes the rule)."""
function p63j_D(m, geom, adj; mutant = :none)
    geom === :hex && return p63j_Dhex(m)
    full = adj === :full && mutant !== :wrong_adjacency
    if geom === :square
        return full ? p63j_D4(~m & 0xff) : p63j_D4(m)
    end
    full || return p63j_D6(m)
    return mutant === :duality_sign ? p63j_D6(~m & 0x03ffffff) : -p63j_D6(~m & 0x03ffffff)
end

"""Replay `copies` (target, new owner) from `σ0` with the test-side tracker; the number of
copies after which some tracked χ differs from oracle (a)."""
function p63j_replay(σ0, n, copies, geom, adj; periodic, mutant = :none)
    σ = copy(σ0)
    χ = p63j_oracle_all(σ, n, geom, adj; periodic)[1]
    bad = 0
    for (x, new) in copies
        old = Int(σ[x...])
        if old != 0 && mutant !== :skip_losing
            χ[old] -= p63j_D(p63j_mask(σ, x, old, geom; periodic), geom, adj; mutant)
        end
        if new != 0
            d = p63j_D(p63j_mask(σ, x, new, geom; periodic), geom, adj; mutant)
            χ[new] += mutant === :gain_sign ? -d : d
        end
        σ[x...] = new
        bad += χ != p63j_oracle_all(σ, n, geom, adj; periodic)[1]
    end
    return bad
end

"""A deterministic random state of labels 0:n (medium about 1/(n+1)), every label present."""
function p63j_random_σ(dims, n, seed)
    st = UInt64(seed) * 0x9E3779B97F4A7C15 + 1
    σ = zeros(Int32, dims)
    for i in eachindex(σ)
        st = st * 6364136223846793005 + 1442695040888963407
        σ[i] = Int32((st >> 33) % (n + 1))
    end
    for c in 1:n
        σ[c] = c
    end
    return σ
end

"""A deterministic random copy sequence: each copy takes a shell neighbour's owner."""
function p63j_copies(σ0, geom, len, seed; periodic)
    σ = copy(σ0)
    st = UInt64(seed) * 0xD1B54A32D192ED03 + 7
    nxt(k) = (st = st * 6364136223846793005 + 1442695040888963407; Int((st >> 33) % k) + 1)
    shell = p63j_shell(geom)
    out = Tuple{Any, Int}[]
    while length(out) < len
        x = Tuple(CartesianIndices(σ)[nxt(length(σ))])
        y = x .+ shell[nxt(length(shell))]
        if periodic
            y = map(mod1, y, size(σ))
        elseif !all(k -> 1 <= y[k] <= size(σ, k), eachindex(y))
            continue
        end
        σ[x...] == σ[y...] && continue
        push!(out, (x, Int(σ[y...])))
        σ[x...] = σ[y...]
    end
    return out
end

# ---------------------------------------------------------------------------------------
# Section 3: the oracle itself (passes on the base)

@testset "P6.3j: the oracle (reference shapes, (a) = (b))" begin
    sq(dims) = zeros(Int32, dims)
    # square 2D, closed 12×12
    σ = sq((12, 12))
    σ[2:4, 2:4] .= 1                                        # disc
    σ[6:10, 2:6] .= 2; σ[7:9, 3:5] .= 0                     # annulus (width 1)
    σ[2, 9] = 3; σ[4, 9] = 3; σ[3, 8] = 3; σ[3, 10] = 3     # diamond round an empty centre
    σ[10:11, 9:11] .= 4; σ[12, 9] = 4; σ[12, 11] = 4        # pocket open to the closed wall
    want = Dict(:face => [1, 0, 4, 1], :full => [1, 0, 0, 1])
    for adj in (:face, :full)
        vals, bad, flooded = p63j_oracle_all(σ, 4, :square, adj; periodic = false)
        @test vals == want[adj]
        @test bad == 0 && flooded == 4
    end
    # periodic: a band round the torus reads 0 (D-192 Q2); a disc 1; the whole torus 0
    σ = sq((12, 12)); σ[3:4, :] .= 1; σ[7:9, 5:7] .= 2
    for adj in (:face, :full)
        @test p63j_oracle_all(σ, 2, :square, adj; periodic = true)[1] == [0, 1]
        @test p63j_oracle(σ, 1, :square, adj; periodic = true)[2] === nothing   # wraps: (b) n/a
        @test p63j_chi(trues(6, 6), :square, adj; periodic = true) == 0
    end
    # hex: a 7-site hexagon 1, the 6-ring round an empty centre 0
    σ = sq((10, 10)); σ[3, 3] = 1; foreach(o -> σ[(3, 3) .+ o...] = 1, P63J_HEX)
    foreach(o -> σ[(7, 6) .+ o...] = 2, P63J_HEX)
    for periodic in (false, true)
        vals, bad, flooded = p63j_oracle_all(σ, 2, :hex, :face; periodic)
        @test vals == [1, 0] && bad == 0 && flooded == 2
    end
    # cubic 3D, closed 7×7×7: a solid ring 0, a hollow cube 2, two edge-diagonal voxels 2 / 1
    σ = sq((7, 7, 7))
    σ[1:3, 1:3, 1] .= 1; σ[2, 2, 1] = 0
    σ[4:6, 4:6, 4:6] .= 2; σ[5, 5, 5] = 0
    σ[1, 6, 6] = 3; σ[2, 7, 6] = 3
    for (adj, w) in ((:face, [0, 2, 2]), (:full, [0, 2, 1]))
        vals, bad, flooded = p63j_oracle_all(σ, 3, :cubic, adj; periodic = false)
        @test vals == w && bad == 0 && flooded == 3
    end
    # a rod through a periodic axis: 0 (one tunnel)
    σ = sq((6, 6, 6)); σ[2, 2, :] .= 1
    @test p63j_chi(σ .== 1, :cubic, :face; periodic = true) == 0
    @test p63j_chi(σ .== 1, :cubic, :full; periodic = true) == 0
    # (a) = (b) on random states, every geometry and boundary
    for (geom, dims) in ((:square, (9, 8)), (:hex, (9, 8)), (:cubic, (5, 5, 4))), periodic in (false, true),
        adj in p63j_adjs(geom)
        nbad = nflood = 0
        for seed in 1:6
            σ = p63j_random_σ(dims, 3, seed)
            _, bad, flooded = p63j_oracle_all(σ, 3, geom, adj; periodic)
            nbad += bad; nflood += flooded
        end
        @test nbad == 0
        periodic || @test nflood == 18
    end
end

# ---------------------------------------------------------------------------------------
# Section 7a: negative controls on the harness (pass on the base)

@testset "P6.3j: negative controls (test-side tracker and mutants)" begin
    for (geom, dims, len) in ((:square, (8, 7), 300), (:hex, (8, 7), 300), (:cubic, (5, 4, 4), 120)), periodic in (false, true)
        σ0 = p63j_random_σ(dims, 3, 11)
        copies = p63j_copies(σ0, geom, len, 5; periodic)
        for adj in p63j_adjs(geom)
            # the correct closed forms pass the harness after every copy
            @test p63j_replay(σ0, 3, copies, geom, adj; periodic) == 0
            # a skipped losing-cell update and a wrong (gaining-side) sign are caught
            @test p63j_replay(σ0, 3, copies, geom, adj; periodic, mutant = :skip_losing) > 0
            @test p63j_replay(σ0, 3, copies, geom, adj; periodic, mutant = :gain_sign) > 0
            # the wrong adjacency (the `:face` update for `:full`) is caught
            adj === :full && @test p63j_replay(σ0, 3, copies, geom, adj; periodic, mutant = :wrong_adjacency) > 0
            # the 3D duality sign (D₂₆ = +D₆(~m)) is caught
            (geom === :cubic && adj === :full) &&
                @test p63j_replay(σ0, 3, copies, geom, adj; periodic, mutant = :duality_sign) > 0
        end
    end
end

# ---------------------------------------------------------------------------------------
# Models

const P63J_GEOMS = [
    (:square, false) => (:(Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))), :(Moore(1)), (12, 12)),
    (:square, true) => (:(Lattice((12, 12); boundary = Periodic(), neighborhood = Moore(1))), :(Moore(1)), (12, 12)),
    (:hex, false) => (:(Lattice((10, 10); geometry = Hexagonal(), boundary = Closed(), neighborhood = Hex(1))), :(Hex(2)), (10, 10)),
    (:hex, true) => (:(Lattice((10, 10); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1))), :(Hex(2)), (10, 10)),
    (:cubic, false) => (:(Lattice((6, 6, 6); boundary = Closed(), neighborhood = Moore(1))), :(Moore(1)), (6, 6, 6)),
    (:cubic, true) => (:(Lattice((6, 6, 6); boundary = Periodic(), neighborhood = Moore(1))), :(Moore(1)), (6, 6, 6)),
]
p63j_name(prefix, geom, periodic) = Symbol(prefix, uppercasefirst(string(geom)), periodic ? "Periodic" : "Closed")
p63j_model(prefix, geom, periodic) = getfield(@__MODULE__, p63j_name(prefix, geom, periodic))
const P63J_V0 = Dict(:square => 20, :hex => 14, :cubic => 30)

for ((geom, periodic), (lat, prop, _)) in P63J_GEOMS
    V0 = P63J_V0[geom]
    hex = geom === :hex
    # tracked through energies (A: `:face`, B: `:full`), read back through `@observed`
    energyB = hex ? :(ε * euler(; adjacency = :face)) : :(ε * euler(; adjacency = :full))
    obs = Expr(:macrocall, Symbol("@observed"), LineNumberNode(@__LINE__, Symbol(@__FILE__)),
        hex ? :(χ4(cell) ~ euler) : Expr(:block, :(χ4(cell) ~ euler), :(χ8(cell) ~ euler(; adjacency = :full))))
    @eval @potts_model $(p63j_name("P63jTrack", geom, periodic)) begin
        @kinds medium A B
        @parameters ε = 0.0078125
        @lattice $lat
        @relations proposal = $prop
        @energy begin
            cells => 0.25 * (volume - $V0)^2
            cells(A) => ε * euler
            cells(B) => $energyB
        end
        $obs
        @sweep Metropolis(; temperature = 6.0)
    end
    # tracked only because `@observed` reads it (D-192 Q5)
    @eval @potts_model $(p63j_name("P63jObs", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @relations proposal = $prop
        @energy cells => 0.25 * (volume - $V0)^2
        $obs
        @sweep Metropolis(; temperature = 6.0)
    end
    # the control twin: never names `euler` (no column, no code; fingerprint pinned)
    @eval @potts_model $(p63j_name("P63jPlain", geom, periodic)) begin
        @kinds medium A B
        @parameters ε = 0.0078125
        @lattice $lat
        @relations proposal = $prop
        @energy begin
            cells => 0.25 * (volume - $V0)^2
            cells(A) => ε * surface
        end
        @observed s(cell) ~ surface
        @sweep Metropolis(; temperature = 6.0)
    end
end

"""Four compact cells (kinds A, B, A, B) on `dims`: 2D squares of side L/2 − 1 (12: 25 sites,
10: 16), 3D cubes of side 3 (27 sites)."""
function p63j_blocks(dims)
    σ = zeros(Int32, dims)
    if length(dims) == 2
        h = dims[1] ÷ 2
        lo, hi = 1:(h - 1), (h + 1):(2h - 1)
        σ[lo, lo] .= 1; σ[hi, lo] .= 2; σ[lo, hi] .= 3; σ[hi, hi] .= 4
    else
        σ[1:3, 1:3, 1:3] .= 1; σ[4:6, 1:3, 1:3] .= 2; σ[1:3, 4:6, 4:6] .= 3; σ[4:6, 4:6, 1:3] .= 4
    end
    return σ
end
const P63J_KINDS = [:A, :B, :A, :B]
p63j_problem(M, σ; tspan = (0, 20), kw...) =
    PottsProblem(M(; name = :p63j), [ownership => σ, kind => P63J_KINDS[1:maximum(σ)]], tspan; seed = 3, kw...)

p63j_col(u, adj) = Array(adj === :face ? u.cell.euler : u.cell.euler_full)

"""Tracked vs oracle (a) for every cell and adjacency; returns (mismatches, checks, values seen)."""
function p63j_compare(u, geom, adjs; periodic)
    σ = Array(u.σ)
    # every cell up to the last live one (dead cells read 0; unused capacity is not read)
    n = something(findlast(>(0), Array(u.cell.volume)), 0)
    bad = checks = 0
    seen = Set{Int}()
    for adj in adjs
        col = p63j_col(u, adj)[1:n]
        want = p63j_oracle_all(σ, n, geom, adj; periodic)[1]
        bad += count(col .!= want)
        checks += n
        union!(seen, want)
    end
    return bad, checks, seen
end

# ---------------------------------------------------------------------------------------
# Section 1: surface and state columns

@testset "P6.3j: columns, observables and the initial rebuild ($geom, $(periodic ? "Periodic" : "Closed"))" for ((geom, periodic), (_, _, dims)) in P63J_GEOMS
    adjs = p63j_adjs(geom)
    σ = p63j_random_σ(dims, 4, 21)                             # fragmented, holed cells
    for prefix in ("P63jTrack", "P63jObs")
        prob = p63j_problem(p63j_model(prefix, geom, periodic), σ)
        u = prob.u0
        @test haskey(u.cell, :euler) && eltype(u.cell.euler) == Int32
        @test haskey(u.cell, :euler_full) == (geom !== :hex)
        geom === :hex || @test eltype(u.cell.euler_full) == Int32
        bad, checks, seen = p63j_compare(u, geom, adjs; periodic)
        @test bad == 0 && checks == 4 * length(adjs)
        @test getu(prob, :χ4)(prob) == u.cell.euler
        geom === :hex || @test getu(prob, :χ8)(prob) == u.cell.euler_full
    end
end

@testset "P6.3j: reference shapes through the compiled model" begin
    # square closed: disc 1/1, annulus 0/0, diamond 4/0, pocket at the wall 1/1
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[6:10, 2:6] .= 2; σ[7:9, 3:5] .= 0
    σ[2, 9] = 3; σ[4, 9] = 3; σ[3, 8] = 3; σ[3, 10] = 3
    σ[10:11, 9:11] .= 4; σ[12, 9] = 4; σ[12, 11] = 4
    u = p63j_problem(P63jTrackSquareClosed, σ).u0
    @test u.cell.euler == [1, 0, 4, 1]
    @test u.cell.euler_full == [1, 0, 0, 1]
    @test u.cell.euler != u.cell.euler_full                  # the adjacencies differ (control)
    # square periodic: a band round the torus reads 0 (D-192 Q2), a disc 1
    σ = zeros(Int32, 12, 12); σ[3:4, :] .= 1; σ[7:9, 5:7] .= 2
    u = p63j_problem(P63jTrackSquarePeriodic, σ).u0
    @test u.cell.euler == [0, 1] && u.cell.euler_full == [0, 1]
    # hex: a 7-site hexagon 1, a 6-ring 0
    σ = zeros(Int32, 10, 10); σ[3, 3] = 1; foreach(o -> σ[(3, 3) .+ o...] = 1, P63J_HEX)
    foreach(o -> σ[(7, 6) .+ o...] = 2, P63J_HEX)
    @test p63j_problem(P63jTrackHexClosed, σ).u0.cell.euler == [1, 0]
    @test p63j_problem(P63jTrackHexPeriodic, σ).u0.cell.euler == [1, 0]
    # cubic closed: a solid ring 0/0, a hollow cube 2/2, two edge-diagonal voxels 2/1
    σ = zeros(Int32, 6, 6, 6)
    σ[1:3, 1:3, 1] .= 1; σ[2, 2, 1] = 0
    σ[4:6, 4:6, 4:6] .= 2; σ[5, 5, 5] = 0
    σ[1, 5, 5] = 3; σ[2, 6, 5] = 3
    u = p63j_problem(P63jTrackCubicClosed, σ).u0
    @test u.cell.euler == [0, 2, 2] && u.cell.euler_full == [0, 2, 1]
    # cubic periodic: a rod through a periodic axis 0/0
    σ = zeros(Int32, 6, 6, 6); σ[2, 2, :] .= 1; σ[4:5, 4:5, 2:3] .= 2
    u = p63j_problem(P63jTrackCubicPeriodic, σ).u0
    @test u.cell.euler == [0, 1] && u.cell.euler_full == [0, 1]
end

# ---------------------------------------------------------------------------------------
# Section 4: exactness after random copy sequences of real integrators

const P63J_ALGS = [("SequentialCPM", SequentialCPM()), ("CheckerboardCPM", CheckerboardCPM()), ("BoundarySiteCPM", BoundarySiteCPM())]

@testset "P6.3j: tracked χ = oracle after every MCS ($geom, $(periodic ? "Periodic" : "Closed"))" for ((geom, periodic), (_, _, dims)) in P63J_GEOMS
    adjs = p63j_adjs(geom)
    for (label, alg) in P63J_ALGS, prefix in ("P63jTrack", "P63jObs")
        prefix == "P63jObs" && label != "SequentialCPM" && continue
        prob = p63j_problem(p63j_model(prefix, geom, periodic), p63j_blocks(dims); tspan = (0, 15))
        integ = init(prob, alg; save_start = false, save_end = false)
        bad = checks = 0
        seen = Set{Int}()
        obs_ok = true
        for _ in 1:15
            step!(integ)
            b, k, s = p63j_compare(integ.state, geom, adjs; periodic)
            bad += b; checks += k; union!(seen, s)
            obs_ok &= integ[:χ4] == integ.state.cell.euler
            geom === :hex || (obs_ok &= integ[:χ8] == integ.state.cell.euler_full)
        end
        @test bad == 0
        @test checks >= 15 * 2 * length(adjs)
        @test obs_ok
        # non-vacuous: the runs change topology (several χ values, holes or fragments)
        @test length(seen) >= 3
    end
end

for (geom, periodic) in ((:square, true), (:cubic, false))
    lat, prop, _ = Dict(P63J_GEOMS)[(geom, periodic)]
    @eval @potts_model $(p63j_name("P63jDivide", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @relations proposal = $prop
        @energy cells => 0.25 * (volume - 24)^2
        @observed begin
            χ4(cell) ~ euler
            χ8(cell) ~ euler(; adjacency = :full)
        end
        @divide cells(A) when = volume >= 22, along = $(geom === :cubic ? (1.0, 0.0, 0.0) : (1.0, 0.0))
        @sweep Metropolis(; temperature = 6.0)
    end
end

@testset "P6.3j: tracked χ = oracle across divisions (the lifecycle rebuild)" begin
    for (geom, periodic) in ((:square, true), (:cubic, false))
        _, _, dims = Dict(P63J_GEOMS)[(geom, periodic)]
        M = p63j_model("P63jDivide", geom, periodic)
        prob = p63j_problem(M, p63j_blocks(dims); tspan = (0, 12), capacity = 64)
        integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
        bad = 0
        for _ in 1:12
            step!(integ)
            bad += p63j_compare(integ.state, geom, (:face, :full); periodic)[1]
        end
        @test bad == 0
        @test integ.stats.lifecycle.divisions > 0
    end
end

# ---------------------------------------------------------------------------------------
# Section 5: energies (exact ΔH)

# small lattices: random states of 3 cells (fragmented, holed) and every copy pair
const P63J_DH_DIMS = Dict(:square => (9, 8), :hex => (9, 8), :cubic => (5, 5, 4))
p63j_dh_lattice(geom, periodic) =
    let b = periodic ? :(Periodic()) : :(Closed()), d = P63J_DH_DIMS[geom]
        geom === :hex ? :(Lattice($d; geometry = Hexagonal(), boundary = $b, neighborhood = Hex(1))) :
        :(Lattice($d; boundary = $b, neighborhood = Moore(1)))
    end

for ((geom, periodic), (_, prop, _)) in P63J_GEOMS
    hex = geom === :hex
    full = hex ? :face : :full
    lat = p63j_dh_lattice(geom, periodic)
    drive = geom === :square ? :(ν * euler(old; adjacency = :full) + ρ * euler[new]) :
            geom === :hex ? :(ν * euler(old; adjacency = :face) + ρ * euler[new]) :
            :(ν * euler(new; adjacency = :face) + ρ * euler(old; adjacency = :full))
    @eval @potts_model $(p63j_name("P63jDH", geom, periodic)) begin
        @kinds medium A B
        @parameters begin
            λ = 3.0
            μ = 0.5
            ν = 0.25
            ρ = 0.125
        end
        @lattice $lat
        @relations proposal = $prop
        @energy begin
            cells(A) => λ * (1 - euler)^2
            cells(B) => μ * euler(; adjacency = $(QuoteNode(full)))
        end
        @drive copy => $drive
        @sweep Metropolis(; temperature = 1.0)
    end
end

"""The drive's terms: (adjacency, side, weight) per geometry (the medium reads 0)."""
p63j_drive_terms(geom) =
    geom === :square ? ((:full, :old, 0.25), (:face, :new, 0.125)) :
    geom === :hex ? ((:face, :old, 0.25), (:face, :new, 0.125)) :
    ((:face, :new, 0.25), (:full, :old, 0.125))

"""Brute-force energy: Σ_A 3(1 − χ_face)² + Σ_B ½ χ_full (hex: χ_face), kinds A, B, A."""
function p63j_energy(σ, geom; periodic)
    E = 0.0
    for (c, k) in enumerate((:A, :B, :A))
        E += k === :A ? 3.0 * (1 - p63j_oracle(σ, c, geom, :face; periodic)[1])^2 :
             0.5 * p63j_oracle(σ, c, geom, geom === :hex ? :face : :full; periodic)[1]
    end
    return E
end

p63j_prop(lat, x, y, σ) = CorePotts.Proposal(CorePotts.linear_index(lat, x), CorePotts.linear_index(lat, y),
    x, 1, σ[x...], σ[y...])

# every geometry and boundary in Float64; the closed ones also in Float32
const P63J_DH_ROWS = [[(g, p, Float64) for ((g, p), _) in P63J_GEOMS]; [(g, false, Float32) for g in (:square, :hex, :cubic)]]

@testset "P6.3j: ΔH = brute-force difference ($geom, $(periodic ? "Periodic" : "Closed"), $T)" for (geom, periodic, T) in P63J_DH_ROWS
    M = p63j_model("P63jDH", geom, periodic)
    dims = P63J_DH_DIMS[geom]
    shell = p63j_shell(geom)
    nE = nD = ntot = nnz = 0
    commit_bad = 0
    for seed in 1:2
        σ = p63j_random_σ(dims, 3, 30 + seed)
        prob = PottsProblem(M(; name = :dh), [ownership => σ, kind => [:A, :B, :A]], (0, 1); T)
        u = prob.u0
        ctx = Potts._host_ctx(prob)
        tol = T === Float64 ? 0.0 : 1.0e-3
        @test isapprox(total_energy(prob, u), p63j_energy(σ, geom; periodic); atol = tol)
        E0 = p63j_energy(σ, geom; periodic)
        k = 0
        for I in CartesianIndices(σ), o in shell
            x = Tuple(I)
            k += 1
            k % 3 == 0 || continue                               # every third pair (light)
            y = x .+ o
            if periodic
                y = map(mod1, y, size(σ))
            elseif !all(j -> 1 <= y[j] <= size(σ, j), eachindex(y))
                continue
            end
            old, new = Int(σ[x...]), Int(σ[y...])
            old == new && continue
            old != 0 && count(==(old), σ) == 1 && continue        # no killing copies (D-083)
            prop = p63j_prop(prob.lattice, x, y, σ)
            σ1 = copy(σ); σ1[x...] = new
            dE = p63j_energy(σ1, geom; periodic) - E0
            drive = sum(w * (c == 0 ? 0 : p63j_oracle(σ, c, geom, adj; periodic)[1])
                        for (adj, side, w) in p63j_drive_terms(geom) for c in (side === :old ? old : new))
            ΔE = energy_change(prob, u, prop)
            ΔH = prob.f.delta_H(u, prob.p, prop, ctx)
            ntot += 1
            nnz += dE != 0
            nE += isapprox(ΔE, dE; atol = tol)
            nD += isapprox(ΔH - ΔE, drive; atol = tol)
            # commit! moves both columns to the oracle values of the new state
            a = deepcopy(u); a.σ[x...] = new
            prob.f.commit!(a, prob.p, prop, ctx)
            for adj in p63j_adjs(geom)
                commit_bad += p63j_col(a, adj) != p63j_oracle_all(σ1, 3, geom, adj; periodic)[1]
            end
        end
    end
    @test ntot >= 40
    @test nnz >= ntot ÷ 4                                        # the energy moves (non-vacuous)
    @test nE == ntot
    @test nD == ntot
    @test commit_bad == 0
end

# ---------------------------------------------------------------------------------------
# Section 6: build errors

"""The exception of building `@potts_model` `ex` into a problem (`nothing` if it builds)."""
function p63j_build(ex, σ)
    try
        M = Core.eval(@__MODULE__, ex)
        Base.invokelatest() do
            sys = M(; name = :b)
            PottsProblem(sys, [ownership => σ, kind => [:A]], (0, 1))
        end
        return nothing
    catch e
        while e isa LoadError
            e = e.error
        end
        return e
    end
end

const P63J_BUILD_N = Ref(0)
function p63j_build_case(lat, line)
    name = Symbol(:P63jBuild, P63J_BUILD_N[] += 1)
    return :(@potts_model $name begin
        @kinds medium A
        @lattice $lat
        @energy cells => (volume - 9)^2
        $line
        @sweep Metropolis(; temperature = 1.0)
    end)
end

@testset "P6.3j: build errors" begin
    hexlat = :(Lattice((10, 10); geometry = Hexagonal(), neighborhood = Hex(1)))
    sqlat = :(Lattice((10, 10)))
    σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
    msg(e) = sprint(showerror, e)
    # `adjacency = :full` on hex: an ArgumentError naming the hexagonal lattice (D-192 Q4)
    for line in (:(@energy cells => euler(; adjacency = :full)),
                 :(@drive copy => euler(old; adjacency = :full)),
                 :(@observed q(cell) ~ euler(; adjacency = :full)))
        e = p63j_build(p63j_build_case(hexlat, line), σ)
        @test e isa ArgumentError
        @test e isa ArgumentError && occursin(r"hex"i, msg(e)) && occursin("full", msg(e))
    end
    # controls: `:face`, explicit or default, builds on hex; `:full` builds on square
    for line in (:(@energy cells => euler(; adjacency = :face)), :(@energy cells => euler),
                 :(@drive copy => euler(old; adjacency = :face)), :(@observed q(cell) ~ euler))
        @test p63j_build(p63j_build_case(hexlat, line), σ) === nothing
    end
    @test p63j_build(p63j_build_case(sqlat, :(@energy cells => euler(; adjacency = :full))), σ) === nothing
    # an unknown adjacency lists the two valid ones
    for lat in (sqlat, hexlat)
        e = p63j_build(p63j_build_case(lat, :(@energy cells => euler(; adjacency = :diag))), σ)
        @test e isa ArgumentError && occursin(":face", msg(e)) && occursin(":full", msg(e))
    end
    # controls on the harness (the base): a surface energy builds; a bare `volume` in a drive
    # is an ArgumentError
    @test p63j_build(p63j_build_case(sqlat, :(@energy cells => surface)), σ) === nothing
    @test p63j_build(p63j_build_case(sqlat, :(@drive copy => volume)), σ) isa ArgumentError
    # a bare `euler` in a drive is an ArgumentError (index it, as `volume`)
    e = p63j_build(p63j_build_case(sqlat, :(@drive copy => euler)), σ)
    @test e isa ArgumentError && occursin("euler", msg(e))
end

# ---------------------------------------------------------------------------------------
# Section 8: zero cost when unused; zero warm allocations when used

# Recorded on the base (2b128db5), before P6.3j: the P63jPlain fixtures, built with
# `p63j_problem(…, p63j_blocks(dims))`.
const P63J_PLAIN_FINGERPRINTS = Dict(
    (:square, false) => 0xf384a9144f7167cd,
    (:square, true) => 0x9056c4276da99ce6,
    (:hex, false) => 0x6b84140adb26d013,
    (:hex, true) => 0x94094140ecbf3d4a,
    (:cubic, false) => 0x414571a554730797,
    (:cubic, true) => 0x9ecd5d7f62370195,
)

p63j_mentions_euler(x) = occursin("euler", string(x))

@testset "P6.3j: a model that never names euler is unchanged" begin
    for ((geom, periodic), (_, _, dims)) in P63J_GEOMS
        M = p63j_model("P63jPlain", geom, periodic)
        prob = p63j_problem(M, p63j_blocks(dims))
        @test prob.f.fingerprint == P63J_PLAIN_FINGERPRINTS[(geom, periodic)]
        prob.f.fingerprint == P63J_PLAIN_FINGERPRINTS[(geom, periodic)] ||
            @info "P6.3j: fingerprint $geom periodic=$periodic = $(repr(prob.f.fingerprint))"
        @test !any(k -> occursin("euler", string(k)), keys(prob.u0.cell))
        g = generated_code(M(; name = :p63j))
        @test !any(p63j_mentions_euler, (g.delta_H, g.commit!, g.constraint, g.total_energy, g.delta_E))
        @test !any(p63j_mentions_euler, g.phases)
    end
    # the published models carry no euler column
    σ, kinds = graner_glazier_state()
    prob = PottsProblem(GranerGlazier(; name = :gg), [ownership => σ, kind => kinds], (0, 1))
    @test !any(k -> occursin("euler", string(k)), keys(prob.u0.cell))
end

@testset "P6.3j: a model that reads euler differs in fingerprint (control)" begin
    for ((geom, periodic), (_, _, dims)) in P63J_GEOMS
        a = p63j_problem(p63j_model("P63jPlain", geom, periodic), p63j_blocks(dims)).f.fingerprint
        b = p63j_problem(p63j_model("P63jTrack", geom, periodic), p63j_blocks(dims)).f.fingerprint
        @test a != b
    end
end

"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function p63j_warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end

@testset "P6.3j: zero warm allocations ($geom, $(periodic ? "Periodic" : "Closed"))" for ((geom, periodic), (_, _, dims)) in P63J_GEOMS
    plain = p63j_problem(p63j_model("P63jPlain", geom, periodic), p63j_blocks(dims))
    for (label, alg) in P63J_ALGS
        @test all(==(0), p63j_warm_allocs(plain, alg))           # control (the base)
    end
    for (label, alg) in P63J_ALGS
        @test all(==(0), p63j_warm_allocs(p63j_problem(p63j_model("P63jTrack", geom, periodic), p63j_blocks(dims)), alg))
        # energy and drive reads, both adjacencies
        dh = PottsProblem(p63j_model("P63jDH", geom, periodic)(; name = :dh),
            [ownership => p63j_random_σ(P63J_DH_DIMS[geom], 3, 31), kind => [:A, :B, :A]], (0, 10))
        @test all(==(0), p63j_warm_allocs(dh, alg))
    end
end

# ---------------------------------------------------------------------------------------
# Section 9: device (Float32)

const P63J_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()

@testset "P6.3j: Float32 on the CPU (Int32 columns, exact)" begin
    for (geom, periodic) in ((:square, true), (:cubic, false))
        _, _, dims = Dict(P63J_GEOMS)[(geom, periodic)]
        prob = p63j_problem(p63j_model("P63jTrack", geom, periodic), p63j_blocks(dims); T = Float32)
        sol = solve(prob, CheckerboardCPM())
        u = sol.u[end]
        @test eltype(u.cell.euler) == Int32 && eltype(u.cell.euler_full) == Int32
        @test p63j_compare(u, geom, (:face, :full); periodic)[1] == 0
    end
end

@testset "P6.3j: euler on the device (CheckerboardCPM, Float32)" begin
    if P63J_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        for (geom, periodic) in ((:square, true), (:hex, false), (:cubic, false))
            _, _, dims = Dict(P63J_GEOMS)[(geom, periodic)]
            prob = p63j_problem(p63j_model("P63jTrack", geom, periodic), p63j_blocks(dims); T = Float32)
            sol = solve(prob, CheckerboardCPM(); backend)
            u = sol.u[end]
            @test eltype(u.cell.euler) == Int32
            @test p63j_compare(u, geom, p63j_adjs(geom); periodic)[1] == 0
        end
        # across divisions: the device rebuild
        prob = p63j_problem(P63jDivideSquarePeriodic, p63j_blocks((12, 12)); tspan = (0, 12), capacity = 64, T = Float32)
        sol = solve(prob, CheckerboardCPM(); backend)
        @test sol.stats.lifecycle.divisions > 0
        @test p63j_compare(sol.u[end], :square, (:face, :full); periodic = true)[1] == 0
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
