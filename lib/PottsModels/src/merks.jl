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
It is `layout(merks_layout(; lattice, kw...), lattice)` (D-087).
"""
merks_state(; lattice = (500, 500), kw...) = layout(merks_layout(; lattice, kw...), lattice)

"""
    merks_layout(; lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice,
        n = 282, side = 10, seed = 1) -> Scattered

The layout behind [`merks_state`](@ref): `n` endothelial boxes of `side²` sites, one medium
site apart, at uniformly random corners in a centred `region` (`off + 2 : off + R − 1` per
axis, `off = (lattice − region) ÷ 2`), drawn from a `StableRNG(seed)`:
`Scattered(n, (side, side); region, kinds = [:endothelial], seed, gap = 1)`.
"""
function merks_layout(; lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice,
        n = 282, side = 10, seed = 1)
    off = (lattice .- region) .÷ 2
    reg = ntuple(d -> (off[d] + 2):(off[d] + region[d] - 1), 2)
    return Scattered(n, (side, side); region = reg, kinds = [:endothelial], seed, gap = 1)
end

"""
    merks2006_layout(; lattice = (500, 500), kw...)

The [`Merks2006`](@ref) start: [`merks_layout`](@ref)`(; lattice, kw...)` inside a frozen
border one site thick, `overlay(Frame(:border; width = 1), merks_layout(; lattice, kw...))`.
The default is the paper's Fig. 4 geometry: 282 cells of 10² over the central 333² of 500².
"""
merks2006_layout(; lattice = (500, 500), kw...) = overlay(Frame(:border; width = 1), merks_layout(; lattice, kw...))

"""
    merks2008_sprout(; rounds = 50, divisions = 7, seed = 1)

The [`Merks2008`](@ref) sprouting start of the released parameter files (`sprout_*.par`):
one Eden blob grown for `rounds` rounds from the lattice centre with 8 neighbours,
divided `divisions` times (7 gives 128 cells, 8 the 256 of 01b Fig. 12), inside a frozen
border two sites thick:

```julia
overlay(Frame(:border; width = 2),
    Splits(Eden(Center(); rounds, kinds = [:endothelial], seed, neighborhood = Moore(1)), divisions;
        splits = :allow))
```

A few of the 128 cells are cut into pieces, as in the authors' code, so `splits = :allow`.
"""
merks2008_sprout(; rounds = 50, divisions = 7, seed = 1) =
    overlay(Frame(:border; width = 2),
        Splits(Eden(Center(); rounds, kinds = [:endothelial], seed, neighborhood = Moore(1)), divisions; splits = :allow))

"""
    merks2008_denovo(; lattice = (202, 202), n = 360, rounds = 10,
        region = (3:(lattice[1] - 2), 3:(lattice[2] - 2)), seed = 1)

The [`Merks2008`](@ref) de novo start: `n` point seeds drawn with replacement in `region`
(coinciding seeds merge), each grown for `rounds` Eden rounds with 8 neighbours, inside a
frozen border two sites thick:

```julia
overlay(Frame(:border; width = 2),
    Eden(RandomPoints(n; region, replace = true, seed); rounds, kinds = [:endothelial], seed,
        neighborhood = Moore(1), shortfall = :allow))
```

The default is the released files' (`denovo_*.par`: 360 seeds on the 198² interior of 200²,
about 355 cells of 47 sites). 01b Fig. 2's geometry is
`merks2008_denovo(; lattice = (502, 502), n = 1000, region = (85:417, 85:417))`.
"""
merks2008_denovo(; lattice = (202, 202), n = 360, rounds = 10, region = (3:(lattice[1] - 2), 3:(lattice[2] - 2)),
    seed = 1) =
    overlay(Frame(:border; width = 2),
        Eden(RandomPoints(n; region, replace = true, seed); rounds, kinds = [:endothelial], seed,
            neighborhood = Moore(1), shortfall = :allow))

_merks_choice(x, allowed, model, key) = x in allowed ? x :
                                        throw(ArgumentError("$model: `$key` must be one of $(join(repr.(allowed), ", ")), got $(repr(x))"))

"""
    Merks2006(; name, lattice = (500, 500), rule = :soft, …)

Vasculogenesis by autocrine chemotaxis of elongated cells: Merks, Brodsky, Goligorsky,
Newman & Glazier, *Dev. Biol.* **289**, 44 (2006) (model-spec 01, Variant E; D-050 M1–M5).
Kinds `medium`, `endothelial` and `border[frozen]`; start it with
[`merks2006_layout`](@ref).

- Energy (Eqs. 1, 4, 5): `Σ J(1 − δ)` over the 8 Moore neighbours, `λ (a − A)²` and
  `λ_L (l − L)²` for every endothelial cell, with the length `l = 4√(λ_max/a)` from the
  cell's inertia tensor (`major_length`).
- Chemotaxis at every copy (Eq. 2, the files' `vecadherinknockout = true`):
  `−χ (f(c[target]) − f(c[source]))` with `f(c) = c/(1 + s c)`, `χ = χcM` when the target's
  or the source's owner is the medium and `χcc` otherwise; both are 1000 (the paper's γ)
  and `s = 0`.
- Connectivity (D-050 M3): `rule = :soft` adds `E₀` to every copy that breaks the losing
  endothelial cell's 8-site ring (TST's `ConnectivityPreservedP`; under Metropolis this is
  TST's threshold shift, D-140); `rule = :hard` vetoes those copies instead.
- A frozen border (`Frame(:border)`, one site thick) with `J(c,B) = 100`, `J(M,B) = 0`
  (D-050 M4).
- The field (Eq. 6, D-050 M5): `∂c/∂t = D Δc + α[endothelial] − ε c [medium]`, 5-point `Δ`,
  held at `c = 0` on the border after every substep (`@boundary`), stepped before the sweep
  of each MCS (`@schedule fields, sweep`).

Parameters, in lattice units (Δx = 2 µm, 1 MCS = 30 s): `T = 50`, `λ = 50`, `A = 100`,
`λ_L = 5`, `L = 50` ("about 100 µm"; the released files' 60 is `L = 60.0`), `E₀ = 5000`,
`χcM = χcc = 1000`, `s = 0`, `Dc = 0.75` (10⁻¹³ m²/s), `α = ε = 5.4·10⁻³` (1.8·10⁻⁴ s⁻¹),
`J = [0 20 0; 20 40 100; 0 100 0]` over (medium, endothelial, border). λ, A, λ_L, E₀ and
`J(M,B)` are not in the paper; they are the 2008 code's values, assumed for 2006.

The paper's field solver is 15 explicit substeps of 2 s per MCS:

```julia
prob = PottsProblem(Merks2006(; name = :m), layout(merks2006_layout(), (500, 500)), (0, 5760);
    field_solver = ExplicitEuler(substeps = 15))
```
"""
@potts_model Merks2006 begin
    @structural_parameters begin
        lattice = (500, 500)
        rule = :soft
    end
    @kinds medium endothelial border[frozen]
    @parameters begin
        T = 50.0
        λ = 50.0
        A = 100.0
        λ_L = 5.0
        L = 50.0
        E₀ = 5000.0
        χcM = 1000.0
        χcc = 1000.0
        s = 0.0
        Dc = 0.75
        α = 5.4e-3
        ε = 5.4e-3
        J[kind, kind] = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]
    end
    @variables c(field) = 0.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(endothelial) => λ * (volume - A)^2 + λ_L * (major_length - L)^2
        contacts => J[kind, kind′]
    end
    @drive copy => -ifelse((old == 0) | (new == 0), χcM, χcc) *
                   (c[target] / (1 + s * c[target]) - c[source] / (1 + s * c[source]))
    if _merks_choice(rule, (:soft, :hard), "Merks2006", :rule) === :soft
        @drive copy => E₀ * ((kind[old] == endothelial) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))
    else
        @constraint connectivity(endothelial; rule = :arc_or_pair)
    end
    @equations D(c) ~ Dc * Δ(c) + α * (kind == endothelial) - ε * c * (kind == medium)
    @boundary c begin
        sites(kind == border) => Dirichlet(0.0)
    end
    @schedule fields, sweep
    @sweep Metropolis(; temperature = T)
end

"""
    Merks2008(; name, lattice = (202, 202), mode = :extension_retraction, …)

Contact-inhibited chemotaxis in de novo and sprouting blood-vessel growth: Merks, Perryn,
Shirinifard & Glazier, *PLoS Comput. Biol.* **4**, e1000163 (2008) (model-spec 01,
Variant CI; D-050 M1, M4–M7, P6.3e). Kinds `medium`, `endothelial` and `border[frozen]`;
start it with [`merks2008_sprout`](@ref) (Figs. 4–11) or [`merks2008_denovo`](@ref)
(Fig. 2).

- Energy (Eq. 2): `Σ J(1 − δ)` over the 20 neighbours of `NeighborOrder(4)` (first to
  fourth order, the files' `neighbours = 3`), and `λ (a − A)²` for every endothelial cell.
  Copies also take their source among the 20 neighbours.
- Chemotaxis (Eq. 3): `−χ (f(c[target]) − f(c[source]))`, `f(c) = c/(1 + s c)`, with
  `χ = χcM` at cell–medium copies (the target's or the source's owner is the medium) and
  `χcc` at cell–cell copies. `χcc = 0` is contact inhibition; `χcc = χcM` removes it, and
  any value between is the continuous ratio of Fig. 5 (D-050 M7). `mode =
  :extension_only` (Eq. 4) drops the term when the source is the medium (a retraction).
- A frozen border (`Frame(:border; width = 2)`; the authors' 1-site frame on 200², whose
  20-site stencil reaches one site further, P6.3e) with `J(c,B) = 100`, `J(M,B) = 0`.
- The field (Eq. 1): `∂c/∂t = D Δc + α[endothelial] − ε c [medium]`, 5-point `Δ`, `c = 0`
  on the border after every substep, stepped before the sweep of each MCS. As in the
  released code the field is off for the first `t_relax` MCS (MCS 0 to `t_relax − 1`, the
  files' `relaxation`, D-050 M6), so chemotaxis starts after it.

Parameters, in lattice units (Δx = 2 µm, 1 MCS = 30 s): `T = 50`, `λ = 25`, `A = 50`,
`χcM = 500`, `χcc = 0`, `s = 0`, `Dc = 0.75` (10⁻¹³ m²/s), `α = ε = 0.03` (10⁻³ s⁻¹),
`t_relax = 100`, `J = [0 20 0; 20 40 100; 0 100 0]` over (medium, endothelial, border).

The paper's field solver is 15 explicit substeps of 2 s per MCS:

```julia
prob = PottsProblem(Merks2008(; name = :m), layout(merks2008_sprout(), (202, 202)), (0, 10_100);
    field_solver = ExplicitEuler(substeps = 15))
```
"""
@potts_model Merks2008 begin
    @structural_parameters begin
        lattice = (202, 202)
        mode = :extension_retraction
    end
    @kinds medium endothelial border[frozen]
    @parameters begin
        T = 50.0
        λ = 25.0
        A = 50.0
        χcM = 500.0
        χcc = 0.0
        s = 0.0
        Dc = 0.75
        α = 0.03
        ε = 0.03
        t_relax = 100.0
        J[kind, kind] = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]
    end
    @variables c(field) = 0.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        cells(endothelial) => λ * (volume - A)^2
        contacts => J[kind, kind′]
    end
    if _merks_choice(mode, (:extension_retraction, :extension_only), "Merks2008", :mode) === :extension_retraction
        @drive copy => -ifelse((old == 0) | (new == 0), χcM, χcc) *
                       (c[target] / (1 + s * c[target]) - c[source] / (1 + s * c[source]))
    else
        @drive copy => ifelse(new == 0, 0.0,
            -ifelse(old == 0, χcM, χcc) * (c[target] / (1 + s * c[target]) - c[source] / (1 + s * c[source])))
    end
    @equations D(c) ~ ifelse(mcs >= t_relax, Dc * Δ(c) + α * (kind == endothelial) - ε * c * (kind == medium), 0.0)
    @boundary c begin
        sites(kind == border) => Dirichlet(0.0)
    end
    @schedule fields, sweep
    @sweep Metropolis(; temperature = T)
end
