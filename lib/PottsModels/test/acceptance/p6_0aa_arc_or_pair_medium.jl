# P6.0aa (ROADMAP Phase 6, step 0; topology-neighborhood-audit §6 item 4): the pair
# exemption of `connectivity(k; rule = :arc_or_pair)` needs a medium-free ring, as in TST's
# `ConnectivityPreservedP` (ca.cpp:1218), which Wortel/Niculescu cite. Frozen (AUTONOMY §7.3).
#
# Semantics pinned here (the losing cell `old` is of a constrained kind, 2D square lattice,
# the 8-site Moore ring of the target):
#   accept  ⇔  ring_arcs ≤ 1  ||  (ring_cells == 2 && ring_medium == 0)
# - `ring_arcs`: maximal runs of `old` on the ring (an out-of-domain site is not `old`);
# - `ring_cells`: distinct cells (medium excluded) on the ring;
# - `ring_medium`: ring sites owned by the medium. An out-of-domain site on a `Closed()`
#   face is NOT medium (TST counts its σ = −1 frame as a cell). On a `Periodic()` axis the
#   ring wraps, so the wrapped sites are ordinary sites.
#
# Ring order of the target x = (i, j) (offsets (di, dj), clockwise as in CorePotts):
#   (-1,-1) (0,-1) (1,-1) (1,0) (1,1) (0,1) (-1,1) (-1,0)
# Every fixture below lists the eight ring owners in this order, by hand.
#
# The predicate is read the way the other acceptance files read it (`p6_0m_defects.jl`):
# the compiled constraint `prob.f.constraint` of a `@potts_model` built through the public
# `connectivity(...; rule = :arc_or_pair)`, and of the published `WortelAct(connected = true)`.
using Potts: CorePotts

p60aa_allows(prob, σ, x, y) = prob.f.constraint(prob.u0, prob.p,
    CorePotts.Proposal(CorePotts.linear_index(prob.lattice, x), CorePotts.linear_index(prob.lattice, y),
        x, 1, σ[x...], σ[y...]), Potts._host_ctx(prob))     # target x takes source y's owner

@potts_model P60aaPeriodic begin
    @kinds medium A
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy cells => (volume - 7)^2
    @constraint connectivity(A; rule = :arc_or_pair)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60aaClosed begin
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 7)^2
    @constraint connectivity(A; rule = :arc_or_pair)
    @sweep Metropolis(; temperature = 1.0)
end

p60aa_prob(M, σ) = PottsProblem(M(; name = :aa), [ownership => σ, kind => fill(:A, maximum(σ))], (0, 1))
p60aa_model_allows(M, σ, x, y) = p60aa_allows(p60aa_prob(M, σ), σ, x, y)

"""Number of 8-connected pieces of cell `c` in `σ` (non-periodic; fixtures stay off the
wrap). Used to show that an accepted copy really splits the cell."""
function p60aa_pieces(σ, c)
    seen = falses(size(σ))
    n = 0
    for I in CartesianIndices(σ)
        (σ[I] == c && !seen[I]) || continue
        n += 1
        stack = [I]; seen[I] = true
        while !isempty(stack)
            J = pop!(stack)
            for d in CartesianIndices((-1:1, -1:1))
                K = J + d
                (checkbounds(Bool, σ, K) && σ[K] == c && !seen[K]) || continue
                seen[K] = true; push!(stack, K)
            end
        end
    end
    return n
end
p60aa_after(σ, x, y) = (a = copy(σ); a[x...] = σ[y...]; a)

# A vertical bar of cell 1 through column 6 (rows 3:9); the target is its middle (6, 6).
const P60AA_X = (6, 6)
const P60AA_SRC = (6, 5)        # the source left of the target: (0, -1) on the ring

# ---------------------------------------------------------------------------------------

@testset "P6.0aa: cell–cell–medium junction is not the pair exemption" begin
    # σ: bar of 1 at (3:9, 6); cell 2 at (6, 5); everything else medium.
    # Ring of (6,6): (5,5)=0 (6,5)=2 (7,5)=0 (7,6)=1 (7,7)=0 (6,7)=0 (5,7)=0 (5,6)=1
    #   ring_arcs = 2 (1 at positions 4 and 8, separated), ring_cells = 2 (1, 2),
    #   ring_medium = 5.  Current rule: 2 ≤ 1 false, ring_cells == 2 true → ACCEPT.
    #   Fixed rule: ring_medium = 5 ≠ 0 → REFUSE.
    σ = zeros(Int32, 12, 12); σ[3:9, 6] .= 1; σ[6, 5] = 2
    @test p60aa_pieces(σ, 1) == 1
    @test p60aa_pieces(p60aa_after(σ, P60AA_X, P60AA_SRC), 1) == 2      # the copy splits cell 1
    @test !p60aa_model_allows(P60aaPeriodic, σ, P60AA_X, P60AA_SRC)
    @test !p60aa_model_allows(P60aaClosed, σ, P60AA_X, P60AA_SRC)             # away from the edge: same

    # one medium site is enough. σ: everything cell 2 except the bar, and (5,7) medium.
    # Ring: (5,5)=2 (6,5)=2 (7,5)=2 (7,6)=1 (7,7)=2 (6,7)=2 (5,7)=0 (5,6)=1
    #   arcs 2, cells 2, medium 1 → current ACCEPT, fixed REFUSE.
    σ1 = fill(Int32(2), 12, 12); σ1[3:9, 6] .= 1; σ1[5, 7] = 0
    @test !p60aa_model_allows(P60aaPeriodic, σ1, P60AA_X, P60AA_SRC)

    # the published model that motivated the item: WortelAct(connected = true), same junction
    # (kind `cell`; its constraint is `connectivity(cell; rule = :arc_or_pair)`)
    wprob = PottsProblem(WortelAct(; name = :w, lattice = (12, 12), connected = true),
        [ownership => σ, kind => [:cell, :cell]], (0, 1))
    @test !p60aa_allows(wprob, σ, P60AA_X, P60AA_SRC)
end

@testset "P6.0aa: controls the fix must keep" begin
    # pure two-cell ring, no medium. σ: cell 2 everywhere except the bar.
    # Ring: (5,5)=2 (6,5)=2 (7,5)=2 (7,6)=1 (7,7)=2 (6,7)=2 (5,7)=2 (5,6)=1
    #   arcs 2, cells 2, medium 0 → ACCEPT under both rules (TST exempts it although the bar
    #   is split; the rule is local).
    σ = fill(Int32(2), 12, 12); σ[3:9, 6] .= 1
    @test p60aa_model_allows(P60aaPeriodic, σ, P60AA_X, P60AA_SRC)
    wprob = PottsProblem(WortelAct(; name = :w, lattice = (12, 12), connected = true),
        [ownership => σ, kind => [:cell, :cell]], (0, 1))
    @test p60aa_allows(wprob, σ, P60AA_X, P60AA_SRC)

    # medium on the ring but one arc: an ordinary junction copy stays accepted.
    # σ: cell 1 block (3:6, 3:6), cell 2 block (7:9, 3:6), medium elsewhere. Target (6,6),
    # source (7,6). Ring of (6,6): (5,5)=1 (6,5)=1 (7,5)=2 (7,6)=2 (7,7)=0 (6,7)=0 (5,7)=0
    #   (5,6)=1 → the 1s at positions 1, 2, 8 are one cyclic arc → arcs 1 → ACCEPT.
    σ = zeros(Int32, 12, 12); σ[3:6, 3:6] .= 1; σ[7:9, 3:6] .= 2
    @test p60aa_model_allows(P60aaPeriodic, σ, (6, 6), (7, 6))

    # three cells on the ring with medium: refused under both rules (arcs 2, cells 3).
    # σ: bar of 1, cell 2 at (6,5), cell 3 at (6,7). Ring: 0 2 0 1 0 3 0 1.
    σ = zeros(Int32, 12, 12); σ[3:9, 6] .= 1; σ[6, 5] = 2; σ[6, 7] = 3
    @test !p60aa_model_allows(P60aaPeriodic, σ, P60AA_X, P60AA_SRC)

    # zero arcs (the cell's last site) still pass: TST lets a cell vanish (P6.0m scope).
    σ = zeros(Int32, 12, 12); σ[6, 6] = 1; σ[6, 5] = 2
    @test p60aa_model_allows(P60aaPeriodic, σ, P60AA_X, P60AA_SRC)
end

@testset "P6.0aa: out-of-domain sites on a Closed edge are not medium" begin
    # σ (Closed 12×12): cell 1 along the top edge row 1, cols 3:9; cell 2 below it, rows 2:4,
    # cols 3:9; medium elsewhere. Target (1,6), source (2,6).
    # Ring of (1,6): (0,5)=OUT (1,5)=1 (2,5)=2 (2,6)=2 (2,7)=2 (1,7)=1 (0,7)=OUT (0,6)=OUT
    #   arcs 2 (1 at positions 2 and 6), cells 2, medium 0 (the three OUT sites are not
    #   medium) → ACCEPT, like the pure two-cell ring. (Counting OUT as medium would refuse.)
    σ = zeros(Int32, 12, 12); σ[1, 3:9] .= 1; σ[2:4, 3:9] .= 2
    @test p60aa_model_allows(P60aaClosed, σ, (1, 6), (2, 6))

    # the same edge junction with one real medium site, (2,7) = 0:
    # Ring: OUT 1 2 2 0 1 OUT OUT → arcs 2, cells 2, medium 1 → current ACCEPT, fixed REFUSE.
    σm = copy(σ); σm[2, 7] = 0
    @test !p60aa_model_allows(P60aaClosed, σm, (1, 6), (2, 6))

    # the same σ on a Periodic lattice: row 0 wraps to row 12, whose cols 5:7 are medium.
    # Ring: (12,5)=0 1 2 2 2 1 (12,7)=0 (12,6)=0 → arcs 2, cells 2, medium 3
    #   → current ACCEPT, fixed REFUSE (wrapped sites are ordinary sites, not out of domain).
    @test !p60aa_model_allows(P60aaPeriodic, σ, (1, 6), (2, 6))
end

# ---------------------------------------------------------------------------------------
# A single cell in medium: ring_cells ≤ 1, so the pair clause never fires and the rule is
# the plain one-arc rule, before and after the fix. Every retraction (medium source) of every
# site of the cell is checked against an arc count computed here, independently.

"""Arcs of `c` on the Moore ring of `x` (out-of-domain on a closed lattice is not `c`)."""
function p60aa_arcs(σ, x, c; periodic)
    ring = ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))
    L = size(σ)
    on = map(ring) do (di, dj)
        y = (x[1] + di, x[2] + dj)
        if periodic
            y = (mod1(y[1], L[1]), mod1(y[2], L[2]))
        elseif !(1 <= y[1] <= L[1] && 1 <= y[2] <= L[2])
            return false
        end
        σ[y...] == c
    end
    all(on) && return 1
    return count(k -> on[k] && !on[k == 1 ? 8 : k - 1], 1:8)
end

@testset "P6.0aa: single cell in medium is the one-arc rule ($(periodic ? "Periodic" : "Closed"))" for periodic in (true, false)
    M = periodic ? P60aaPeriodic : P60aaClosed
    shapes = Matrix{Int32}[]
    # a U (bridges and a cavity), touching the top edge (row 1) and the left edge (col 1)
    s = zeros(Int32, 12, 12); s[1:6, 1] .= 1; s[6, 1:5] .= 1; s[1:6, 5] .= 1; s[3, 2:3] .= 1
    push!(shapes, s)
    # an annulus with a diagonal tail (corner contacts) in the interior
    s = zeros(Int32, 12, 12); s[4:8, 4:8] .= 1; s[5:7, 5:7] .= 0; s[6, 6] = 1
    s[9, 9] = 1; s[10, 10] = 1; s[10, 11] = 1
    push!(shapes, s)
    for σ in shapes
        prob = p60aa_prob(M, σ)
        n = accepted = refused = 0
        agree = 0
        for I in CartesianIndices(σ)
            σ[I] == 1 || continue
            x = Tuple(I)
            for (di, dj) in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1))
                y = (x[1] + di, x[2] + dj)
                if periodic
                    y = (mod1(y[1], 12), mod1(y[2], 12))
                elseif !(1 <= y[1] <= 12 && 1 <= y[2] <= 12)
                    continue
                end
                σ[y...] == 0 || continue
                want = p60aa_arcs(σ, x, 1; periodic) <= 1
                got = p60aa_allows(prob, σ, x, y)
                n += 1; accepted += want; refused += !want
                agree += got == want
            end
        end
        @test agree == n
        @test accepted > 0 && refused > 0           # non-vacuous: both outcomes occur
    end
end
