"""
    MerksVasculogenesis(; name, lattice = (500, 500), contact_inhibited = false, …)

Vasculogenesis by chemotaxis to an autocrine chemoattractant, with elongated cells (Merks,
Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44, 2006):

- `H = Σ J + λ Σ (a − A)² + λ_L Σ (l − L)²` (Eqs. 1, 4), with the cell length
  `l = 4√(λ_max(I)/a)` (Eq. 5, the `major_length` built-in). Elongation is what turns the
  round islands of pure chemotaxis into networks.
- Chemotaxis `ΔH = −χ (c(target) − c(source))` on every copy (Eq. 2, Savill–Hogeweg form).
  With `contact_inhibited = true` it acts only on extensions of a cell into the medium (the
  contact-inhibited model of Merks et al., PLoS Comput. Biol. 4, e1000163, 2008).
- `∂c/∂t = D∇²c + α δ_cell − ε c (1 − δ_cell)` (Eq. 6): cells secrete, the chemoattractant
  decays only in the matrix. The field is advanced by explicit Euler, clipped at zero.
- Cells stay connected: a copy may not split a cell (a hard veto for the paper's
  connectivity penalty; the CompuCell3D one-arc rule).

Defaults are the 2006 parameter set in lattice units (2 µm/px, 30 s/MCS):
`T = 50`, `χ = 1000`, `J_cc = 40`, `J_cM = 20`, `D = 0.75` (10⁻¹³ m²/s),
`α = ε = 5.4·10⁻³` (1.8·10⁻⁴ s⁻¹), target area `A = 100` with `λ = 50`, and target length
`L = 50` ("about 100 µm" in the paper text) with `λ_L = 5`, on a 500² lattice with Moore
contacts and copies. Seed with [`merks_state`](@ref): 282 cells of 10² sites over 333².
The 2008 contact-inhibited runs used other values (`A = 50` and Dataset S1); pass them as
keywords with `contact_inhibited = true`.

Differences from the paper:
- connectivity is a hard veto, not the soft penalty `E₀ > 2000` on connectivity-breaking
  copies;
- the closed walls cost nothing; the paper has frozen border cells with `J_cB = 100`;
- the field boundary is zero-flux; the paper's code holds `c = 0` on the outer ring
  (absorbing);
- `L = 50` follows the paper text; the released parameter files labelled for Fig. 4
  (`longcells.par`) use `L = 60`; pass `L = 60.0` for that reading.

The field solver is a problem keyword with no default; this model's is the paper's
schedule of 15 explicit Euler substeps per MCS (`Δt = 2 s`),
`field_solver = ExplicitEuler(substeps = 15, lower = 0.0)`:

```julia
prob = PottsProblem(MerksVasculogenesis(; name = :merks), merks_state(), (0, 10_000);
    field_solver = ExplicitEuler(substeps = 15, lower = 0.0))
```
"""
@potts_model MerksVasculogenesis begin
    @structural_parameters begin
        lattice = (500, 500)
        contact_inhibited = false
    end
    @kinds medium endothelial
    @parameters begin
        λ = 50.0
        V₀ = 100.0
        λ_L = 5.0
        L = 50.0
        χ = 1000.0
        Dc = 0.75
        σc = 5.4e-3
        δc = 5.4e-3
        T = 50.0
        J[kind, kind] = [0.0 20.0; 20.0 40.0]
    end
    @variables c(field) = 0.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(endothelial) => λ * (volume - V₀)^2 + λ_L * (major_length - L)^2
        contacts => J[kind, kind′]
    end
    if contact_inhibited
        @drive copy => ifelse((old == 0) && (kind[new] == endothelial), -χ * (c[target] - c[source]), 0.0)
    else
        @drive copy => -χ * (c[target] - c[source])
    end
    @equations D(c) ~ Dc * Δ(c) + σc * (kind == endothelial) - δc * c * (kind == medium)
    @constraint connectivity(endothelial; rule = :local)
    @sweep Metropolis(; temperature = T)
end

"""
    merks_state(; lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice,
        n = 282, side = 10, seed = 1)

`n` square endothelial cells of `side²` sites (the default 10² is the target area
`A = 100`) at random, non-overlapping positions (one-site gaps) in a centred `region` (Merks
et al. 2006: 282 cells over 333 × 333 sites of a 500² lattice): `[ownership => σ, kind => fill(:endothelial, n)]`.
"""
function merks_state(; lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice,
        n = 282, side = 10, seed = 1)
    rng = MersenneTwister(seed)
    σ = zeros(Int32, lattice)
    off = (lattice .- region) .÷ 2
    placed = 0
    for _ in 1:(1000n)
        placed == n && break
        lo = off .+ (rand(rng, 2:(region[1] - side)), rand(rng, 2:(region[2] - side)))
        box = (lo[1] - 1):(lo[1] + side), (lo[2] - 1):(lo[2] + side)
        all(iszero, view(σ, box...)) || continue
        placed += 1
        σ[lo[1]:(lo[1] + side - 1), lo[2]:(lo[2] + side - 1)] .= placed
    end
    placed == n || throw(ArgumentError("merks_state: only $placed of $n cells fit in $region"))
    return [ownership => σ, kind => fill(:endothelial, n)]
end
