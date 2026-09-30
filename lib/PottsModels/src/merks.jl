"""
    MerksVasculogenesis(; name, lattice = (500, 500), contact_inhibited = false, …)

Vasculogenesis by chemotaxis to an autocrine chemoattractant, with elongated cells (Merks,
Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44, 2006; D-049 F-3):

- `H = Σ J + λ Σ (a − A)² + λ_L Σ (l − L)²` (Eqs. 1, 4), with the cell length
  `l = 4√(λ_max(I)/a)` (Eq. 5, the `major_length` built-in). Elongation is what turns the
  round islands of pure chemotaxis into networks.
- Chemotaxis `ΔH = −χ (c(target) − c(source))` on every copy (Eq. 2, Savill–Hogeweg form).
  With `contact_inhibited = true` it acts only on extensions of a cell into the medium (the
  contact-inhibited model of Merks et al., PLoS Comput. Biol. 4, e1000163, 2008).
- `∂c/∂t = D∇²c + α δ_cell − ε c (1 − δ_cell)` (Eq. 6): cells secrete, the chemoattractant
  decays only in the matrix. The field is advanced by explicit Euler with as many substeps
  as `D` needs for stability, clipped at zero.
- Cells stay connected: a copy may not split a cell (a hard veto for the paper's
  connectivity penalty; the CompuCell3D one-arc rule).
- Differences: the closed walls cost nothing (paper: frozen border cells with `J_cB = 100`),
  there is no dissipation threshold `E₀` (its value is not given), and the field takes the
  fewest stable Euler substeps rather than the paper's 15 (spec:
  `docs/design/research/model-specs/01_merks.md`).

Defaults are the paper's in lattice units (2 µm/px, 30 s/MCS): `T = 50`, `χ = 1000`,
`J_cc = 40`, `J_cM = 20`, `D = 0.75`, `α = ε = 5.4·10⁻³`, and the PLoS 2008 cell size
`A = 50`, `λ = 25` with `L = 30`, `λ_L = 5`. Seed with [`merks_state`](@ref).
"""
@potts_model MerksVasculogenesis begin
    @structural_parameters begin
        lattice = (500, 500)
        contact_inhibited = false
    end
    @kinds medium endothelial
    @parameters begin
        λ = 25.0
        V₀ = 50.0
        λ_L = 5.0
        L = 30.0
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
    @sweep Metropolis(; temperature = T, field_solver = ExplicitEuler(substeps = 2, lower = 0.0))
end

"""
    merks_state(; lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice,
        n = 282, side = 7, seed = 1)

`n` square endothelial cells of `side²` sites (≈ `A`) at random, non-overlapping positions
(one-site gaps) in a centred `region` (Merks et al. 2006: 282 cells over 333 × 333 sites of
a 500² lattice): `[ownership => σ, kind => fill(:endothelial, n)]`.
"""
function merks_state(; lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice,
        n = 282, side = 7, seed = 1)
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
