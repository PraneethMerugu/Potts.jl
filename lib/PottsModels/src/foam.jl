"""
    ShearedFoam(; name, lattice = (256, 256), J, Γ, T, γ0, β, bulk, periodic, ω, ytop, ymid)

A sheared two-dimensional dry foam (Jiang, Swart, Saxena, Asipauskas & Glazier, Phys. Rev.
E 59, 5819, 1999): a large-Q Potts model whose cells are gas bubbles, with a wall energy, an
area constraint and a shear term that biases copies along x.

- **Lattice.** x periodic, y closed walls without wall cells (spec 04 A-2); contacts and
  proposals over `NeighborOrder(4)`, the 20 neighbors up to the fourth shell (p. 5822).
- **Energies.** Eq. (1): a wall energy `J` for every unlike neighbor pair and an area
  constraint `Γ(a − A)²` per bubble, with a per-bubble target area `A` (default `16² = 256`,
  p. 5823). A dry foam: every site belongs to a bubble. `Γ = 0` lets the foam coarsen.
- **Shear.** Copying the source's bubble into the target site adds the bias
  `G(t) · γ(y) · (x_target − x_source)` (Eq. 2 in the displacement form, `direction[1]`,
  minimum image along x). `bulk = 0`: Eq. 6, boundary shear, `γ = +γ0` on the row `y = 1`,
  `−γ0` on `y = ytop`, zero elsewhere. `bulk = 1`: Eq. 7, bulk shear, `γ = −β (y − ymid)`.
  `periodic = 0`: steady, `G = 1`; `periodic = 1`: `G = sin(ω · mcs)`. A positive `γ` biases
  copies towards −x, so the top row moves +x and the bottom −x (Figs. 2, 4, 5). Set
  `ytop = L_y` and `ymid = (L_y + 1)/2` for another lattice height.
- **Temperature.** `T = 1e-6`, the T → 0⁺ limit of the paper's T = 0 (ties accepted,
  uphill moves rejected).

Use [`sheared_foam_state`](@ref) for the paper's ordered start, a brick wall of 16² bubbles.

Differences from the paper:
- the shear term is the displacement form above; read literally, Eq. 2's absolute `x_i`
  makes the bias grow with x. Model `γ0` and `β` are the paper's times a calibrated scale κ;
- the paper proposes only at wall sites and only to an unlike neighbor, counting every pick
  as a trial. Run with `SequentialCPM(; skip_interior = true)`: wall sites only, a uniform
  neighbor among the 20, so one paper MCS is τ = 1/ū of ours (ū the mean unlike share of a
  wall site's neighbors).
"""
@potts_model ShearedFoam begin
    @structural_parameters begin
        lattice = (256, 256)                       # sites (p.5822)
    end
    @kinds medium bubble                           # dry foam: no site is medium
    @parameters begin
        J = 3.0                                    # wall energy per unlike pair (p.5823)
        Γ = 1.0                                    # area constraint (p.5823); Γ = 0 coarsens
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
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    # γ > 0 biases copies towards −x: the top row moves +x and the bottom −x (Figs. 2, 4, 5)
    @drive copy => ifelse(periodic > 0.5, sin(ω * mcs), 1.0) *
                   ifelse(bulk > 0.5, -β * (position[target][2] - ymid),
        γ0 * (ifelse(position[target][2] < 1.5, 1.0, 0.0) - ifelse(position[target][2] > ytop - 0.5, 1.0, 0.0))) *
                   direction[1]
    @sweep Metropolis(; temperature = T)
end

"""
    sheared_foam_state(; lattice = (256, 256), side = 16)

The ordered start of [`ShearedFoam`](@ref) (Jiang et al. 1999, p. 5823): square bubbles of
`side²` sites in common bond, as `[ownership => σ, kind => [:bubble, …], :A => [side², …]]`.
Brick row `r = 0, 1, …` covers `y = side·r + 1 … side·(r + 1)`; odd rows are shifted by
`side ÷ 2` along x, wrapping around the periodic x axis, and bubble ids run along each row,
`id = r · (L_x ÷ side) + column + 1`. The lattice sides should be multiples of `side`; on
256² that is the paper's 256 bubbles of 16².
"""
function sheared_foam_state(; lattice = (256, 256), side::Integer = 16)
    L = Tuple(lattice)
    σ = Int32[(r = (y - 1) ÷ side; r * (L[1] ÷ side) + mod(x - 1 - (isodd(r) ? side ÷ 2 : 0), L[1]) ÷ side + 1)
              for x in 1:L[1], y in 1:L[2]]
    n = Int(maximum(σ))
    return [ownership => σ, kind => fill(:bubble, n), :A => fill(Float64(side)^2, n)]
end
