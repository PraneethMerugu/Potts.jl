"""
    AkeebInvasion(; name, lattice = (500, 300), J = akeeb_contacts(2.0), μ, …)

Leader/follower collective invasion with proliferation (Akeeb, Marcus & Jiang; ported from
`SCDPotts/scripts/run_akeeb_proliferative.jl`, audited against the authors' CompuCell3D
source in `SCDPotts/research/akeeb_source_audit.md`):

- **Kinds.** Leaders and followers, both kept connected and never extinct.
- **Energies.** A per-cell target volume, and adhesion
  `J = [0 2 10; 2 16 J_LF; 10 J_LF 5]` (medium, leader, follower).
- **Migration cue.** A static field `cue = y − 1`. A copy whose source or target cell is a
  leader gains `−μ Δcue`: leaders climb the cue (CompuCell3D's default chemotaxis).
- **Growth and division.** Followers with a mitotic clock (`clock ≥ 0`) grow their target
  volume by `rate` per MCS up to `V_max`. They divide when larger than `V_max` and their
  clock exceeds `clock_min + clock_spread · U(0, 1)`, with a fresh draw every MCS. The
  division plane is random, the target volume is split, and clocks restart.

Use `akeeb_state` for the published initial slab.
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
    @energy begin
        cells => λᵥ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @drive copy => ifelse((kind[new] == leader) || (kind[old] == leader), -μ * (cue[target] - cue[source]), 0.0)
    @constraint connectivity(leader, follower)
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
    akeeb_state(; lattice = (500, 300), pp = 0.5, seed = 0x5cd2609) -> operating point

The published initial slab:
- **Followers.** 3×3 tiles fill `y ≤ 21`, clipped at the right edge.
- **Leaders.** One-site leaders are placed at random follower pixels (`2 ≤ x`,
  `2 ≤ y ≤ 20`) until they are a quarter of all cells.
- **Clocks.** Each follower has a mitotic clock with probability `pp`, drawn uniformly
  from `0:74`. Followers have `rate = 0.015`.
- **Cue.** `y − 1`.

Draws use `MersenneTwister(seed)` and `(seed + 1)`, as in the source.
"""
function akeeb_state(; lattice = (500, 300), pp = 0.5, seed = 0x5cd2609)
    X, Y = lattice
    σ = zeros(Int32, X, Y)
    kinds = Symbol[]
    for y in 1:3:21, x in 1:3:X
        push!(kinds, :follower)
        σ[x:min(x + 2, X), y:(y + 2)] .= length(kinds)
    end
    nf = length(kinds)
    rng = MersenneTwister(seed)
    leaders = 0
    while 4 * leaders < length(kinds)
        x, y = rand(rng, 2:X), rand(rng, 2:20)
        1 <= σ[x, y] <= nf || continue
        push!(kinds, :leader)
        σ[x, y] = length(kinds)
        leaders += 1
    end
    rng = MersenneTwister(seed + 1)
    clocks = [k === :leader || rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74)) for k in kinds]
    rates = [k === :leader ? 0.0 : 0.015 for k in kinds]
    cue = [Float64(y - 1) for x in 1:X, y in 1:Y]
    return [ownership => σ, kind => kinds, :clock => clocks, :rate => rates, :cue => cue]
end
