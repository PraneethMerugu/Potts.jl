"""
    ShearedFoam(; name, lattice = (256, 256), J = 3.0, Γ = 1.0, T = 1.0e-6, γ0 = 0.0,
        β = 0.0, bulk = 0.0, periodic = 0.0, ω = 2π/4000, ytop = 256.0, ymid = 128.5)

Build a sheared two-dimensional dry foam: a large-Q Potts model whose cells are gas
bubbles, with an interface energy, an area constraint and a shear term that biases copies
along `x`.

- **Lattice.** `x` periodic; `y` closed, with no boundary cells (the paper does not state
  its boundary type; see `docs/design/research/model-specs/04_foam.md`, A-2). Contacts and
  proposals use `NeighborOrder(4)`, the 20 neighbors up to the fourth shell (p. 5822).
- **Energies.** Eq. (1): an interface energy `J` for every unlike neighbor pair and an area
  constraint `Γ(a − A)²` per bubble, with a per-bubble target area `A` (default
  `16² = 256`, p. 5823). A dry foam: every site belongs to a bubble. `Γ = 0` lets the foam
  coarsen.
- **Shear.** Copying the source's bubble into the target site adds the bias
  `G(t) · γ(y) · (x_target − x_source)` (Eq. 2 in the displacement form, `direction[1]`,
  minimum image along `x`). `bulk = 0`: Eq. 6, boundary shear, `γ = +γ0` on the row
  `y = 1`, `−γ0` on `y = ytop`, zero elsewhere. `bulk = 1`: Eq. 7, bulk shear,
  `γ = −β (y − ymid)`. `periodic = 0`: steady, `G = 1`; `periodic = 1`:
  `G = sin(ω · mcs)`. A positive `γ` biases copies towards −x, so the top row moves +x and
  the bottom −x (Figs. 2, 4, 5). Set `ytop = L_y` and `ymid = (L_y + 1)/2` for another
  lattice height.
- **Temperature.** `T = 1e-6`, the T → 0⁺ limit of the paper's T = 0 (ties accepted,
  uphill moves rejected).

The kinds are `medium` (unused) and `bubble`, and the cell variable `A` holds the target
area. Use [`sheared_foam_state`](@ref) for the paper's ordered start, a brick pattern of
16² bubbles.

Differences from the paper:
- the shear term is the displacement form above; read literally, Eq. 2's absolute `x_i`
  makes the bias grow with `x`. Model `γ0` and `β` are the paper's times a calibrated
  scale κ;
- the paper proposes only at sites on a bubble boundary and only to an unlike neighbor,
  counting every pick as a trial. Run with `SequentialCPM(; skip_interior = true)`:
  boundary sites only, a uniform neighbor among the 20, so one paper MCS is τ = 1/ū of ours
  (ū the mean unlike share of a boundary site's neighbors).

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (256, 256)`: the lattice size (structural).
- `J = 3.0`: the interface energy per unlike neighbor pair.
- `Γ = 1.0`: the area strength.
- `T = 1.0e-6`: the Metropolis temperature.
- `γ0 = 0.0`: the boundary shear amplitude (Eq. 6).
- `β = 0.0`: the bulk shear rate (Eq. 7).
- `bulk = 0.0`: `1` selects bulk shear (Eq. 7), `0` boundary shear (Eq. 6).
- `periodic = 0.0`: `1` selects `G = sin(ω · mcs)`, `0` steady shear.
- `ω = 2π/4000`: the angular frequency of periodic shear, per MCS.
- `ytop = 256.0`: the top row, `L_y`.
- `ymid = 128.5`: the mid-plane, `(L_y + 1)/2`.

# Returns
- `PottsSystem`: the model.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> ShearedFoam(; name = :foam, γ0 = 0.5) isa PottsSystem
true
```

# References
- Jiang, Swart, Saxena, Asipauskas & Glazier, Phys. Rev. E 59, 5819 (1999).

See also [`sheared_foam_state`](@ref).
"""
@potts_model ShearedFoam begin
    @structural_parameters begin
        lattice = (256, 256)                       # sites (p.5822)
    end
    @kinds medium bubble                           # dry foam: no site is medium
    @parameters begin
        J = 3.0                                    # wall energy per unlike pair (p.5823)
        # area constraint (p.5823); Γ = 0 coarsens
        Γ = 1.0
        T = 1.0e-6                                 # T → 0⁺ (DV2)
        γ0 = 0.0                                   # boundary shear amplitude (Eq. 6)
        β = 0.0                                    # bulk shear rate (Eq. 7)
        bulk = 0.0                                 # 1: Eq. 7, else Eq. 6
        periodic = 0.0                             # 1: G = sin(ω mcs), else G = 1
        ω = 2π / 4000
        ytop = 256.0                               # the top row, L_y
        ymid = 128.5                               # the mid-plane, (L_y + 1)/2
    end
    @variables begin
        A(cell) = 256.0                            # target area, 16² (p.5823)
    end
    # x periodic, y closed walls (no wall cells, A-2)
    @lattice Lattice(
        lattice; boundary = (Periodic(), Closed()),
        neighborhood = NeighborOrder(4)
    )
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    # γ > 0 biases copies towards −x: the top row moves +x and the bottom −x (Figs. 2, 4, 5)
    @drive copy =>
        ifelse(periodic > 0.5, sin(ω * mcs), 1.0) *
        ifelse(
        bulk > 0.5, -β * (position[target][2] - ymid),
        γ0 * (
            ifelse(position[target][2] < 1.5, 1.0, 0.0) -
                ifelse(position[target][2] > ytop - 0.5, 1.0, 0.0)
        )
    ) *
        direction[1]
    @sweep Metropolis(; temperature = T)
end

"""
    sheared_foam_state(; lattice = (256, 256), side = 16) -> Vector{Pair}

Return the ordered start of [`ShearedFoam`](@ref) (Jiang et al. 1999, p. 5823): square
bubbles of `side²` sites in common bond.

Brick row `r = 0, 1, …` covers `y = side·r + 1 … side·(r + 1)`; odd rows are shifted by
`side ÷ 2` along `x`, wrapping around the periodic `x` axis. Bubble numbers run along each
row: `r · (L_x ÷ side) + column + 1`. The lattice sides should be multiples of `side`; on
256² that is the paper's 256 bubbles of 16².

# Keywords
- `lattice = (256, 256)`: the lattice size.
- `side::Integer = 16`: the side of a bubble, in sites.

# Returns
- `Vector{Pair}`: the operating point
  `[ownership => σ, kind => [:bubble, …], :A => [side², …]]`, with `σ::Matrix{Int32}`.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> u0 = sheared_foam_state(; lattice = (32, 32), side = 8);

julia> length(u0[2].second), u0[3].second[1]
(16, 64.0)
```

See also [`ShearedFoam`](@ref).
"""
function sheared_foam_state(; lattice = (256, 256), side::Integer = 16)
    L = Tuple(lattice)
    σ = Int32[
        (
            r = (y - 1) ÷ side;
            r * (L[1] ÷ side) + mod(x - 1 - (isodd(r) ? side ÷ 2 : 0), L[1]) ÷ side +
                1
        )
            for x in 1:L[1], y in 1:L[2]
    ]
    n = Int(maximum(σ))
    return [ownership => σ, kind => fill(:bubble, n), :A => fill(Float64(side)^2, n)]
end
