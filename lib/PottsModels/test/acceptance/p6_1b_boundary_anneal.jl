# P6.1b (ROADMAP Phase 6, step 1; review R16, D-051 item 6): the two measurements behind the
# Graner–Glazier sorting analysis (spec 09 §9.0, PRE §II D1), as model-agnostic public
# functions of Potts, documented on a manual page and used by the 09 tutorial. Frozen
# (AUTONOMY §7.3).
#
# Surface fixed by the coordinator (D-139):
#
#   Potts.boundary_lengths(prob, u = prob.u0; relation = nothing)
#           -> AbstractDict{Tuple{Symbol, Symbol}, <:Real}                  (public in Potts)
#       The boundary length of state `u` decomposed by kind pair. A bond is an unordered pair
#       of sites {i, j} with j = i + o for an offset o of `relation` (a RelationSpec resolved
#       on the problem's lattice; `nothing` = the problem's contact relation), j inside the
#       lattice and its domain (periodic axes wrap, closed axes and the domain edge do not),
#       and σ[i] ≠ σ[j]. Each bond is counted ONCE, with the relation's weight (1 when
#       unweighted, so counts are integers). It is credited to the pair of the kinds of its
#       two owners (the medium, owner 0, has the model's first kind). Keys are
#       `(kind_a, kind_b)` with kind_a declared no later than kind_b, by the names of
#       `@kinds` (classes are not kinds); EVERY such pair is a key, zeros included
#       (`(medium, medium)` is always 0). Two distinct cells of one kind count under
#       `(k, k)`. So, for a model whose only energy is `contacts => J[kind, kind′]`
#       (times `weight` for a weighted relation),
#           Σ_{(a, b)} J[a, b] · L[(a, b)] == total_energy(prob, u).
#       Square, hexagonal and 3D lattices; host only.
#
#   Potts.anneal(prob, u = prob.u0; mcs, seed = 0, alg = SequentialCPM()) -> state
#                                                                         (public in Potts)
#       The annealed copy of PRE p. 2134 ("we anneal the displayed data only"): a new state,
#       `u` after `mcs` MCS of `prob`'s copy dynamics with the copy temperature 0 for every
#       proposal, whatever the model's temperature expression. Everything else is the run's
#       own: parameters `prob.p`, lattice, relations, proposal, acceptance law and ΔH. `u`
#       and `prob` are not modified. Deterministic in (prob, u, mcs, seed, alg). `mcs = 0`
#       returns an equal copy; `mcs < 0` is an ArgumentError. The measurement is any
#       function of the result, e.g. `boundary_lengths(prob, anneal(prob, u; mcs = 32))`.
#
# Every count below is derived by hand in the comments (bonds listed one by one) and was
# cross-checked with an independent brute-force count over all site pairs.
using Potts: CorePotts

# A lattice from a picture: rows top (y = Y) to bottom (y = 1), σ[x, y].
p61b_lattice(rows) = (Y = length(rows); Int32[rows[Y - y + 1][x] for x in eachindex(rows[1]), y in 1:Y])
# All six keys of a three-kind model, with the expected values (medium, A, B).
p61b_expect(; MA = 0, MB = 0, AA = 0, AB = 0, BB = 0) = Dict((:medium, :medium) => 0, (:medium, :A) => MA,
    (:medium, :B) => MB, (:A, :A) => AA, (:A, :B) => AB, (:B, :B) => BB)
# The contact energies of every fixture model: one power of 1000 per kind pair, so the
# energy spells out each count (all below 1000) in its own three decimal digits.
const P61B_J = [0.0 1.0 1.0e3; 1.0 1.0e6 1.0e9; 1.0e3 1.0e9 1.0e12]
const P61B_KIDX = Dict(:medium => 1, :A => 2, :B => 3)
p61b_energy(L) = sum(P61B_J[P61B_KIDX[a], P61B_KIDX[b]] * v for ((a, b), v) in L)

# ---------------------------------------------------------------------------------------
# Fixture models: contact energy only, one per lattice

const P61B_LATTICES = Dict(
    :sq_closed => :(Lattice((4, 3); boundary = Closed(), neighborhood = Moore(1))),
    :sq_closed_w => :(Lattice((4, 3); boundary = Closed(), neighborhood = Moore(1))),
    :stripes_periodic => :(Lattice((5, 4); boundary = Periodic(), neighborhood = Moore(1))),
    :stripes_closed => :(Lattice((5, 4); boundary = Closed(), neighborhood = Moore(1))),
    :hex_closed => :(Lattice((3, 3); boundary = Closed(), geometry = Hexagonal())),
    :sq3_closed => :(Lattice((3, 3); boundary = Closed(), neighborhood = Moore(1))),
    :hex_stripes_periodic => :(Lattice((4, 4); boundary = Periodic(), geometry = Hexagonal())),
    :hex_stripes_closed => :(Lattice((4, 4); boundary = Closed(), geometry = Hexagonal())),
    :slabs_periodic => :(Lattice((4, 4, 4); boundary = Periodic(), neighborhood = Moore(1))),
    :slabs_closed => :(Lattice((4, 4, 4); boundary = Closed(), neighborhood = Moore(1))),
    :cube_closed => :(Lattice((4, 4, 4); boundary = Closed(), neighborhood = Moore(1))),
)
const P61B_MODELS = Dict{Symbol, Any}()
for (i, (key, lat)) in enumerate(sort!(collect(P61B_LATTICES); by = first))
    name = Symbol(:P61bContact, i)
    if key === :sq_closed_w      # distance-weighted Moore contacts; the energy reads the weight
        @eval @potts_model $name begin
            @kinds medium A B
            @parameters J[kind, kind] = [0.0 1.0 1.0e3; 1.0 1.0e6 1.0e9; 1.0e3 1.0e9 1.0e12]
            @lattice $lat
            @relations contact = Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
            @energy contacts => weight * J[kind, kind′]
            @sweep Metropolis(; temperature = 1.0)
        end
    else
        @eval @potts_model $name begin
            @kinds medium A B
            @parameters J[kind, kind] = [0.0 1.0 1.0e3; 1.0 1.0e6 1.0e9; 1.0e3 1.0e9 1.0e12]
            @lattice $lat
            @energy contacts => J[kind, kind′]
            @sweep Metropolis(; temperature = 1.0)
        end
    end
    P61B_MODELS[key] = @eval $name
end
p61b_prob(key, σ, kinds) = PottsProblem(P61B_MODELS[key](; name = Symbol(:p61b_, key)),
    [ownership => σ, kind => kinds], (0, 1))

# F1, square 4×3, closed, Moore(1). Cells 1, 2 are A, cell 3 is B:
#   y=3:  0 0 3 3
#   y=2:  1 2 3 0
#   y=1:  1 2 0 0
# Bonds (forward offsets (1,0), (0,1), (1,1), (1,-1); a = axial, d = diagonal):
#   (1,0): y1 1-2 AA a, 2-0 MA a | y2 1-2 AA a, 2-3 AB a, 3-0 MB a | y3 0-3 MB a
#   (0,1): x1 1-0 MA a | x2 2-0 MA a | x3 0-3 MB a | x4 0-3 MB a
#   (1,1): (1,1)-(2,2) AA d, (2,1)-(3,2) AB d, (1,2)-(2,3) MA d, (2,2)-(3,3) AB d
#   (1,-1): (1,2)-(2,1) AA d, (2,2)-(3,1) MA d, (3,2)-(4,1) MB d, (1,3)-(2,2) MA d,
#           (2,3)-(3,2) MB d, (3,3)-(4,2) MB d
# Totals: AA 2a+2d = 4, AB 1a+2d = 3, MA 3a+3d = 6, MB 4a+3d = 7, BB 0.
const P61B_F1 = p61b_lattice([[0, 0, 3, 3], [1, 2, 3, 0], [1, 2, 0, 0]])

@testset "P6.1b: boundary_lengths is public in Potts" begin
    @test isdefined(Potts, :boundary_lengths) && Base.ispublic(Potts, :boundary_lengths)
    @test isdefined(Potts, :anneal) && Base.ispublic(Potts, :anneal)
end

@testset "P6.1b: boundary_lengths, square 2D closed (hand counts, energy oracle)" begin
    prob = p61b_prob(:sq_closed, P61B_F1, [:A, :A, :B])
    L = Potts.boundary_lengths(prob)
    @test L isa AbstractDict
    @test Set(keys(L)) == Set(keys(p61b_expect()))            # every pair, ordered by @kinds
    @test Dict(L) == p61b_expect(; MA = 6, MB = 7, AA = 4, AB = 3)
    @test L == Potts.boundary_lengths(prob, prob.u0)
    # oracle: the contact energy is Σ J·L; P61B_J makes it spell 0 000 003 004 007 006
    @test total_energy(prob) == 3_004_007_006
    @test p61b_energy(L) == total_energy(prob)
    # another relation than the contact one: VonNeumann(1) keeps the axial bonds only
    @test Dict(Potts.boundary_lengths(prob; relation = VonNeumann(1))) == p61b_expect(; MA = 3, MB = 4, AA = 2, AB = 1)
    # negative control: kinds swapped (cells 1, 2 B and 3 A) move the counts to the swapped keys
    swapped = p61b_prob(:sq_closed, P61B_F1, [:B, :B, :A])
    @test Dict(Potts.boundary_lengths(swapped)) == p61b_expect(; MA = 7, MB = 6, BB = 4, AB = 3)
    @test p61b_energy(Potts.boundary_lengths(swapped)) == total_energy(swapped)
    # negative control: one site moved from medium to cell 3 changes the counts
    σ2 = copy(P61B_F1)
    σ2[4, 1] = 3                                              # (4,1): 0 → 3
    moved = p61b_prob(:sq_closed, σ2, [:A, :A, :B])
    @test Dict(Potts.boundary_lengths(moved)) != Dict(L)
    @test p61b_energy(Potts.boundary_lengths(moved)) == total_energy(moved)
end

@testset "P6.1b: boundary_lengths, weighted relation" begin
    # F1 with Weighted(Moore(1), 1/|o|): axial bonds weigh 1, diagonal ones w = Float32(1/√2)
    prob = p61b_prob(:sq_closed_w, P61B_F1, [:A, :A, :B])
    L = Potts.boundary_lengths(prob)
    w = Float64(Float32(1 / sqrt(2)))
    want = Dict((:medium, :medium) => 0.0, (:medium, :A) => 3 + 3w, (:medium, :B) => 4 + 3w,
        (:A, :A) => 2 + 2w, (:A, :B) => 1 + 2w, (:B, :B) => 0.0)
    @test Set(keys(L)) == Set(keys(want))
    @test all(isapprox(L[k], want[k]; rtol = 1.0e-6, atol = 1.0e-9) for k in keys(want))
    @test isapprox(p61b_energy(L), total_energy(prob); rtol = 1.0e-6)
end

@testset "P6.1b: boundary_lengths, periodic against closed (square 2D)" begin
    # Stripes on 5×4, one owner per column x: 1 (A), 2 (A), 3 (B), 4 (B), medium.
    # Columns at distance 1 share bonds, columns at distance 2 none (Moore(1)).
    # Periodic: each of the 4 sites of a column has 3 Moore neighbours in the next column:
    #   12 bonds per adjacent column pair, x = 5 → 1 included (MA).
    # Closed: rows y = 1 and y = 4 have 2 such neighbours, rows 2 and 3 have 3: 10 per
    #   pair, and the x = 5 | 1 pair does not touch (MA = 0).
    σ = Int32[(1, 2, 3, 4, 0)[x] for x in 1:5, y in 1:4]
    kinds = [:A, :A, :B, :B]
    per = p61b_prob(:stripes_periodic, σ, kinds)
    clo = p61b_prob(:stripes_closed, σ, kinds)
    @test Dict(Potts.boundary_lengths(per)) == p61b_expect(; MA = 12, AA = 12, AB = 12, BB = 12, MB = 12)
    @test Dict(Potts.boundary_lengths(clo)) == p61b_expect(; MA = 0, AA = 10, AB = 10, BB = 10, MB = 10)
    @test p61b_energy(Potts.boundary_lengths(per)) == total_energy(per)
    @test p61b_energy(Potts.boundary_lengths(clo)) == total_energy(clo)
end

@testset "P6.1b: boundary_lengths, hexagonal 2D" begin
    # Hex 3×3, closed, axial (q, r) drawn like σ[x, y]; neighbours (±1,0), (0,±1), (1,-1), (-1,1).
    # Cell 1 is A, cell 2 is B:
    #   r=3:  0 2 2
    #   r=2:  1 1 2
    #   r=1:  1 0 0
    # Bonds (forward offsets (1,0), (0,1), (1,-1)):
    #   (1,0): r1 1-0 MA | r2 1-2 AB | r3 0-2 MB
    #   (0,1): q1 (1,2)-(1,3) 1-0 MA | q2 (2,1)-(2,2) 0-1 MA, (2,2)-(2,3) 1-2 AB | q3 (3,1)-(3,2) 0-2 MB
    #   (1,-1): (1,2)-(2,1) 1-0 MA, (2,2)-(3,1) 1-0 MA, (1,3)-(2,2) 0-1 MA, (2,3)-(3,2) 2-2 none
    # Totals: MA 6, AB 2, MB 2.
    σ = p61b_lattice([[0, 2, 2], [1, 1, 2], [1, 0, 0]])
    hex = p61b_prob(:hex_closed, σ, [:A, :B])
    @test Dict(Potts.boundary_lengths(hex)) == p61b_expect(; MA = 6, AB = 2, MB = 2)
    @test p61b_energy(Potts.boundary_lengths(hex)) == total_energy(hex)
    # negative control: the same σ on a square Moore(1) lattice adds the (1,1) diagonals
    # (2,1)-(3,2) 0-2 MB, (1,2)-(2,3) 1-2 AB, (2,2)-(3,3) 1-2 AB: MA 6, AB 4, MB 3
    sq = p61b_prob(:sq3_closed, σ, [:A, :B])
    @test Dict(Potts.boundary_lengths(sq)) == p61b_expect(; MA = 6, AB = 4, MB = 3)
    # Hex stripes on 4×4, one owner per column q: 1 (A), 2 (B), medium, medium. A site has
    # two neighbours in column q + 1, (q+1, r) and (q+1, r-1).
    # Periodic: 8 bonds per adjacent column pair; q = 4 → 1 is MA, q = 3 | 4 is medium–medium.
    # Closed: (q+1, r-1) needs r ≥ 2, so 4 + 3 = 7 per pair, and no MA.
    σs = Int32[(1, 2, 0, 0)[q] for q in 1:4, r in 1:4]
    per = p61b_prob(:hex_stripes_periodic, σs, [:A, :B])
    clo = p61b_prob(:hex_stripes_closed, σs, [:A, :B])
    @test Dict(Potts.boundary_lengths(per)) == p61b_expect(; MA = 8, AB = 8, MB = 8)
    @test Dict(Potts.boundary_lengths(clo)) == p61b_expect(; MA = 0, AB = 7, MB = 7)
    @test p61b_energy(Potts.boundary_lengths(per)) == total_energy(per)
    @test p61b_energy(Potts.boundary_lengths(clo)) == total_energy(clo)
end

@testset "P6.1b: boundary_lengths, 3D" begin
    # Slabs on 4×4×4, one owner per x: 1 (A), 2 (A), 3 (B), medium. Moore(1): a site has
    # 9 neighbours in the next slab when (y, z) wrap, so 16 · 9 = 144 bonds per adjacent
    # slab pair (x = 4 → 1 is MA). Closed: Σ_y n(y) · Σ_z n(z) with n = (2, 3, 3, 2), 10 · 10
    # = 100 per pair, and no MA.
    σ = Int32[(1, 2, 3, 0)[x] for x in 1:4, y in 1:4, z in 1:4]
    per = p61b_prob(:slabs_periodic, σ, [:A, :A, :B])
    clo = p61b_prob(:slabs_closed, σ, [:A, :A, :B])
    @test Dict(Potts.boundary_lengths(per)) == p61b_expect(; MA = 144, AA = 144, AB = 144, MB = 144)
    @test Dict(Potts.boundary_lengths(clo)) == p61b_expect(; MA = 0, AA = 100, AB = 100, MB = 100)
    @test p61b_energy(Potts.boundary_lengths(per)) == total_energy(per)
    @test p61b_energy(Potts.boundary_lengths(clo)) == total_energy(clo)
    # One A cube 2×2×2 at (2:3)³ in a closed 4×4×4 medium. Moore(1): each of its 8 sites has
    # 26 in-bounds neighbours, 7 of them in the cube: 8 · 19 = 152. VonNeumann(1): 6
    # neighbours, 3 in the cube: 8 · 3 = 24.
    σc = zeros(Int32, 4, 4, 4)
    σc[2:3, 2:3, 2:3] .= 1
    cube = p61b_prob(:cube_closed, σc, [:A])
    @test Dict(Potts.boundary_lengths(cube)) == p61b_expect(; MA = 152)
    @test Dict(Potts.boundary_lengths(cube; relation = VonNeumann(1))) == p61b_expect(; MA = 24)
    @test total_energy(cube) == 152
end

# ---------------------------------------------------------------------------------------
# Agreement with reproduction 09 (lib/PottsModels/reproductions/09_cell_sorting.jl at
# 8eb9d210): its `bond_counts` and `annealed`, transcribed. Kinds: 1 dark, 2 light.

function p61b_bond_counts_09(σ, k)
    n = Dict(:dd => 0, :ll => 0, :dl => 0, :dM => 0, :lM => 0)
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]
        b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        a == b && continue
        a == 0 && ((a, b) = (b, a))
        key = b == 0 ? (k[a] == 1 ? :dM : :lM) : k[a] == k[b] ? (k[a] == 1 ? :dd : :ll) : :dl
        n[key] += 1
    end
    return n
end
function p61b_annealed_09(σ, k, run; seed = 1)
    q = PottsProblem(GranerGlazier(; name = :p61b_anneal09, lattice = size(σ)),
        [ownership => copy(σ), kind => k, :J => getp(run, :J)(run), :λ => getp(run, :λ)(run),
            :V₀ => getp(run, :V₀)(run), :T => 0.0], (0, 32); seed)
    return ownership(solve(q, SequentialCPM(); saveat = 32).u[end])
end
p61b_as09(L) = Dict(:dd => L[(:dark, :dark)], :ll => L[(:light, :light)], :dl => L[(:dark, :light)],
    :dM => L[(:medium, :dark)], :lM => L[(:medium, :light)])
p61b_hetero(n) = n[:dl] / sum(values(n))
p61b_mean(x) = sum(x) / length(x)
p61b_var(x) = (m = p61b_mean(x); sum(abs2, x .- m) / (length(x) - 1))
p61b_se(x, y) = sqrt(p61b_var(x) / length(x) + p61b_var(y) / length(y))   # SE of the difference of means

@testset "P6.1b: boundary_lengths agrees with reproduction 09's bond_counts" begin
    σ, k = graner_glazier_state()
    prob = PottsProblem(GranerGlazier(; name = :p61b_gg09), [ownership => σ, kind => k], (0, 64); seed = 5)
    L = Potts.boundary_lengths(prob)
    @test L[(:medium, :medium)] == 0
    @test p61b_as09(L) == p61b_bond_counts_09(σ, k)
    # and on a state the run has moved (sorting under way, T = 10)
    u = solve(prob, SequentialCPM()).u[end]
    @test ownership(u) != σ
    @test p61b_as09(Potts.boundary_lengths(prob, u)) == p61b_bond_counts_09(ownership(u), k)
end

# ---------------------------------------------------------------------------------------
# anneal

# The hole fixture: 8×8 periodic, cell 1 on x = 1:4 with a medium hole at (2, 4) (31
# sites), cell 2 on x = 5:8 (32 sites); λ = 1, V₀ = 32, Moore contacts and proposals.
# Copies from the hole's 8 neighbours (all cell 1) into the hole: ΔH = −λ (volume 31 → 32)
# − 8·J(c,M) < 0, accepted. Every other copy has ΔH > 0 before and after the fill (with
# J(d,l) = 11, J(c,M) = 16):
#   cell 1 into a flat-interface site of cell 2: volume −1 + 1, contact 3 → 5 bonds, +22;
#   cell 2 into cell 1: volume ≥ +3 + 1, contact ≥ +11;
#   the hole into a neighbour of cell 1: volume +3, contact 1 → 7 medium bonds, +96;
#   after the fill, cell 1 into cell 2: volume +1 +1, contact +22.
# So at T = 0 the only change is the fill. The hole is never a target with a cell-1 source in
# 32 MCS of 64 attempts each with probability (63/64)^2048 ≈ 1e-14 (sequential), and the
# checkerboard visits every site each MCS.
const P61B_HOLE = (σ = Int32[x <= 4 ? 1 : 2 for x in 1:8, y in 1:8]; σ[2, 4] = 0; σ)
const P61B_FILLED = Int32[x <= 4 ? 1 : 2 for x in 1:8, y in 1:8]

# The same physics with a temperature that is not a parameter named `T` (3θ = 30).
@potts_model P61bHot begin
    @kinds medium A B
    @parameters begin
        λ = 1.0
        V₀ = 32.0
        θ = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice((8, 8); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(A, B) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 3θ)
end

p61b_hole_gg() = PottsProblem(GranerGlazier(; name = :p61b_hole, lattice = (8, 8)),
    [ownership => copy(P61B_HOLE), kind => [1, 2], :V₀ => 32.0], (0, 32); seed = 3)

@testset "P6.1b: anneal fills the hole and nothing else (T = 0, the run's energies)" begin
    prob = p61b_hole_gg()
    for s in 1:5
        a = Potts.anneal(prob, prob.u0; mcs = 32, seed = s)
        @test ownership(a) == P61B_FILLED
        @test a.cell.volume[1:2] == [32, 32]
    end
    @test ownership(Potts.anneal(prob; mcs = 32, seed = 1)) == P61B_FILLED   # u defaults to prob.u0
    @test ownership(Potts.anneal(prob, prob.u0; mcs = 4, seed = 2, alg = CheckerboardCPM())) == P61B_FILLED
    # the temperature is zeroed whatever its expression (here 3θ, not a parameter `T`)
    hot = PottsProblem(P61bHot(; name = :p61b_hot), [ownership => copy(P61B_HOLE), kind => [:A, :B]], (0, 32); seed = 3)
    for s in 1:3
        @test ownership(Potts.anneal(hot, hot.u0; mcs = 32, seed = s)) == P61B_FILLED
    end
    # negative control: the run itself (T = 10, and 3θ = 30) moves more than the hole
    @test ownership(solve(prob, SequentialCPM()).u[end]) != P61B_FILLED
    @test ownership(solve(hot, SequentialCPM()).u[end]) != P61B_FILLED
    # negative control: the run's own parameters, not the model defaults. With λ = 200 and
    # V₀ = 31 the holed state is a strict local minimum (fill: +200 − 128; cell 1 into 2:
    # +200 − 200 + 22; cell 2 into 1: +200 + 600 + 11; hole outward: +200 + 96), so the
    # annealed copy is the input
    stiff = remake(prob; p = [:λ => 200.0, :V₀ => 31.0])
    for s in 1:3
        @test ownership(Potts.anneal(stiff, stiff.u0; mcs = 32, seed = s)) == P61B_HOLE
    end
end

@testset "P6.1b: anneal is a copy, deterministic, and validates mcs" begin
    prob = p61b_hole_gg()
    σ0 = copy(prob.u0.σ)
    v0 = copy(prob.u0.cell.volume)
    p0 = deepcopy(prob.p)
    a = Potts.anneal(prob, prob.u0; mcs = 32, seed = 1)
    @test a !== prob.u0
    @test prob.u0.σ == σ0 && prob.u0.cell.volume == v0      # the input state is unchanged
    @test prob.p == p0 && prob.tspan == (0, 32) && prob.seed == 3
    # it can be measured like any state
    @test Dict(Potts.boundary_lengths(prob, a)) == Dict((:medium, :medium) => 0, (:medium, :dark) => 0,
        (:medium, :light) => 0, (:dark, :dark) => 0, (:dark, :light) => 48, (:light, :light) => 0)
    # 48 = 2 flat interfaces × 8 rows × 3 Moore bonds
    # deterministic in the seed; mcs = 0 is a copy of u
    σ, k = graner_glazier_state()
    gg = PottsProblem(GranerGlazier(; name = :p61b_ggdet), [ownership => σ, kind => k], (0, 64); seed = 5)
    @test ownership(Potts.anneal(gg, gg.u0; mcs = 32, seed = 7)) == ownership(Potts.anneal(gg, gg.u0; mcs = 32, seed = 7))
    z = Potts.anneal(gg, gg.u0; mcs = 0, seed = 7)
    @test z !== gg.u0 && ownership(z) == σ
    @test_throws ArgumentError Potts.anneal(gg, gg.u0; mcs = -1)
end

@testset "P6.1b: annealing lowers the energy; the run at T raises it again" begin
    σ, k = graner_glazier_state()
    prob = PottsProblem(GranerGlazier(; name = :p61b_ggH), [ownership => σ, kind => k], (0, 32); seed = 11)
    H0 = total_energy(prob)
    for s in 1:3
        a = Potts.anneal(prob, prob.u0; mcs = 32, seed = s)
        # every accepted T = 0 copy has ΔH ≤ 0 (a killing one lowers H by more), so H falls
        @test total_energy(prob, a) < H0
        @test sum(values(Potts.boundary_lengths(prob, a))) < sum(values(Potts.boundary_lengths(prob)))
        # negative control: the run's own dynamics (T = 10) from the annealed state raise H
        r = solve(remake(prob; u0 = [ownership => ownership(a), kind => k]), SequentialCPM()).u[end]
        @test total_energy(prob, r) > total_energy(prob, a)
    end
end

@testset "P6.1b: the annealed measurement agrees with reproduction 09" begin
    # 09's protocol: 2 paper MCS (32 of ours) at T = 0 with the run's J, λ, V₀, then the
    # bond counts. Compared over 8 seeds each on the 64-cell PRE start (graner_glazier_state)
    # after 64 MCS of sorting at the defaults: the mean heterotypic fraction and the mean
    # total boundary agree within 5 standard errors of the difference.
    σ, k = graner_glazier_state()
    run = PottsProblem(GranerGlazier(; name = :p61b_gg09a), [ownership => σ, kind => k], (0, 64); seed = 2)
    u = solve(run, SequentialCPM()).u[end]
    σu = ownership(u)
    ours = [p61b_as09(Potts.boundary_lengths(run, Potts.anneal(run, u; mcs = 32, seed = s))) for s in 1:8]
    ref = [p61b_bond_counts_09(p61b_annealed_09(σu, k, run; seed = s), k) for s in 1:8]
    fo, fr = p61b_hetero.(ours), p61b_hetero.(ref)
    no, nr = [sum(values(n)) for n in ours], [sum(values(n)) for n in ref]
    @test abs(p61b_mean(fo) - p61b_mean(fr)) <= 5 * p61b_se(fo, fr) + 1.0e-12
    @test abs(p61b_mean(no) - p61b_mean(nr)) <= 5 * p61b_se(no, nr) + 1.0e-12
    # both are annealed: below the unannealed boundary of the same state
    n_u = sum(values(p61b_bond_counts_09(σu, k)))
    @test maximum(no) < n_u && maximum(nr) < n_u
end
