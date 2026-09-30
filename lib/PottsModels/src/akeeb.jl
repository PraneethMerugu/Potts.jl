"""
    AkeebInvasion(; name, lattice = (500, 300), J = akeeb_contacts(2.0), μ, …)

Leader/follower collective invasion with proliferation (Akeeb, Marcus & Jiang; ported from
`SCDPotts/scripts/run_akeeb_proliferative.jl`, audited against the authors' CompuCell3D
source in `SCDPotts/research/akeeb_source_audit.md`):

- **Kinds.** Leaders and followers, both kept connected (CompuCell3D's `Connectivity`
  plugin: the losing cell's sites in the 8-ring must form one arc) and never extinct.
- **Energies.** A per-cell target volume, and adhesion
  `J = [0 2 10; 2 16 J_LF; 10 J_LF 5]` (medium, leader, follower).
- **Migration cue.** A static field `cue = y − 1`. A copy whose source or target cell is a
  leader gains `−μ Δcue`: leaders climb the cue (CompuCell3D's default chemotaxis).
- **Growth and division.** Followers with a mitotic clock (`clock ≥ 0`) grow their target
  volume by `rate` per MCS up to `V_max`. They divide when larger than `V_max` and their
  clock exceeds `clock_min + clock_spread · U(0, 1)`, with a fresh draw every MCS. The
  division plane is random, the target volume is split, and clocks restart.

Use `akeeb_state` for the published initial slab.

Faithful to the authors' CompuCell3D model (Akeeb, Marcus & Jiang, PLoS Comput. Biol. 2026;
D-049). One CC3D step is 1 MCS here; the source runs 701. The legacy port's `:merks` ring rule
(which also accepted when exactly two cells occupy the ring) split cells and is no longer
used.
"""
@potts_model AkeebInvasion begin
    @structural_parameters begin
        lattice = (500, 300)
    end
    @kinds medium leader follower
    @parameters begin
        λᵥ = 2.0
        μ = 30.0
        T = 10.0
        V_max = 20.0
        clock_min = 75.0
        clock_spread = 50.0
        J[kind, kind] = [0.0 2.0 10.0; 2.0 16.0 2.0; 10.0 2.0 5.0]
    end
    @variables begin
        V_target(cell) = 10.0
        clock(cell) = -1.0
        rate(cell) = 0.0
        cue(site) = 0.0
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = Moore(1))
    @relations proposal = VonNeumann(1)     # CC3D Potts NeighborOrder 1
    @energy begin
        cells => λᵥ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @drive copy => ifelse((kind[new] == leader) || (kind[old] == leader), -μ * (cue[target] - cue[source]), 0.0)
    @constraint connectivity(leader, follower)   # one arc in the 8-ring: CC3D's Connectivity plugin
    @constraint no_extinction
    @after_mcs begin
        V_target ~ ifelse(Pre(V_target) < V_max, Pre(V_target) + rate, Pre(V_target))
        clock ~ ifelse(Pre(clock) >= 0, Pre(clock) + 1, Pre(clock))
    end
    @divide cells(follower) when = (clock >= 0) && (volume > V_max) && (clock > clock_min + clock_spread * rand()),
        along = RandomPlane(), V_target => Split(), clock => 0.0
    @sweep Metropolis(; temperature = T)
end

"""`akeeb_contacts(J_LF)`: the adhesion table with leader–follower energy `J_LF`."""
akeeb_contacts(jlf) = [0.0 2.0 10.0; 2.0 16.0 jlf; 10.0 jlf 5.0]

"""
    akeeb_state(; lattice = (500, 300), pp = 0.5, seed = 0x5cd2609, slab = 21,
                seeding = :authors) -> operating point

The published initial slab (spec 10 §2.3, §5.2 V-A1, §5.3.6; D-068):
- **Followers.** 3×3 tiles fill `y ≤ slab` (rounded up to whole tiles), clipped at the
  right edge. The lattice must be taller than the slab.
- **Leaders.** One-site leaders go on random follower pixels (`2 ≤ x`, `2 ≤ y ≤ slab − 1`)
  until leaders are a quarter of all cells. `seeding` chooses how a missed draw (a pixel
  that is not a follower's) is treated:
  - `:authors` (default) emulates the authors' CompuCell3D loop: every draw counts one
    leader toward the quota, a leader is painted only on a hit, and the quota is tested
    only after a hit. A miss leaves no cell (a zero-site cell is never alive, D-066 X2),
    so fewer leaders are painted than counted: at 500×300, ≈ 382 of a counted 390.
  - `:retry` redraws a miss, so exactly the quota is painted (390 at 500×300).
- **Clocks.** Each follower has a mitotic clock with probability `pp`, drawn uniformly
  from `0:74`. Followers have `rate = 0.015`.
- **Cue.** `y − 1`.

Draws use `MersenneTwister(seed)` and `(seed + 1)`, as in the source.
"""
function akeeb_state(; lattice = (500, 300), pp = 0.5, seed = 0x5cd2609, slab = 21,
        seeding::Symbol = :authors)
    X, Y = lattice
    top = 3 * cld(slab, 3)                                   # the last tile row ends here
    Y > top || throw(ArgumentError("akeeb_state: lattice height $Y must exceed the slab ($top rows)"))
    seeding in (:authors, :retry) ||
        throw(ArgumentError("akeeb_state: seeding must be :authors or :retry, got :$seeding"))
    σ = zeros(Int32, X, Y)
    kinds = Symbol[]
    for y in 1:3:slab, x in 1:3:X
        push!(kinds, :follower)
        σ[x:min(x + 2, X), y:(y + 2)] .= length(kinds)
    end
    _seed_leaders!(σ, kinds, MersenneTwister(seed), slab, seeding === :retry)
    rng = MersenneTwister(seed + 1)
    clocks = [k === :leader || rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74)) for k in kinds]
    rates = [k === :leader ? 0.0 : 0.015 for k in kinds]
    cue = [Float64(y - 1) for x in 1:X, y in 1:Y]
    return [ownership => σ, kind => kinds, :clock => clocks, :rate => rates, :cue => cue]
end

# Paints one-site leaders on follower pixels until leaders are a quarter of all cells, and
# returns the counted leaders. The authors' loop (`CCIecmSteppables.py`, Main_Simulation_Scan
# S:67–75) is
#     while i < k/100:                      # S:67, k = 25; i = LC/(LC+FC), 0 at the start
#         lc = self.new_cell(self.LC)       # S:68, on every draw: counted += 1
#         x1 = randint(1, dim.x); y1 = randint(1, 20)     # S:70–71 (0-based)
#         if cellField[x1, y1].type == 2:   # S:73, FC only (a leader's pixel is a miss)
#             cellField[x1, y1] = lc        # S:74, paint
#             i = LC/(LC+FC)                # S:75, LC counts every created cell
# so the quota is tested only after a hit. With `retry`, a miss is redrawn and not counted.
function _seed_leaders!(σ, kinds, rng, slab, retry::Bool)
    X = size(σ, 1)
    nf = length(kinds)
    counted = 0
    while true
        x, y = rand(rng, 2:X), rand(rng, 2:(slab - 1))
        hit = 1 <= σ[x, y] <= nf
        (hit || !retry) && (counted += 1)
        hit || continue
        push!(kinds, :leader)
        σ[x, y] = length(kinds)
        4 * counted >= counted + nf && return counted
    end
end
