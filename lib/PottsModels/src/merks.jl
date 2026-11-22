# The chemoattractant of the Merks models as plain MTK `PDESystem`s on the lattice, coupled
# into each model with `@fields`. Their inputs are 0/1 site fields that the `@fields` line
# binds to kind tests: `cell` (an endothelial site), `ecm` (a medium site) and `frame` (a
# border site). The parameters keep the names and defaults of the models.
module MerksField
    using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters,
        t_nounits as t
    using Potts.LatticePDE: laplacian, masked, step_index, lattice_domain
    const Dt = Differential(t)
    @parameters x y
    @variables c(..) cell(..)::Bool [input = true] ecm(..)::Bool [input = true] frame(
        ..
    )::Bool [input = true]
    const C = c(t, x, y)

    # `∂c/∂t = D Δc + α δ_cell − ε c (1 − δ_cell)` (2006 Eq. 6) with zero flux at the
    # lattice faces
    function vasculogenesis(lattice)
        @parameters Dc = 0.75 σc = 5.4e-3 δc = 5.4e-3
        eq = Dt(C) ~ Dc * laplacian(C) + σc * cell(t, x, y) - δc * C * ecm(t, x, y)
        return PDESystem(
            [eq], [c(0, x, y) ~ 0.0], lattice_domain(t, (x, y), lattice), [t, x, y],
            [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc]; name = :merks_field
        )
    end

    # the same equation, held at `c = 0` on the border sites after every substep
    function merks2006(lattice)
        @parameters Dc = 0.75 α = 5.4e-3 ε = 5.4e-3
        eq = Dt(C) ~ Dc * laplacian(C) + α * cell(t, x, y) - ε * C * ecm(t, x, y)
        return PDESystem(
            [eq], [c(0, x, y) ~ 0.0, C ~ masked(frame(t, x, y), 0.0)],
            lattice_domain(t, (x, y), lattice),
            [t, x, y], [C, cell(t, x, y), ecm(t, x, y), frame(t, x, y)], [Dc, α, ε];
            name = :merks_field
        )
    end

    # 2008 Eq. 1: as `merks2006`, but off for the first `t_relax` MCS (`step_index(t)` is
    # the MCS)
    function merks2008(lattice)
        @parameters Dc = 0.75 α = 0.03 ε = 0.03 t_relax = 100.0
        rate = Dc * laplacian(C) + α * cell(t, x, y) - ε * C * ecm(t, x, y)
        eq = Dt(C) ~ ifelse(step_index(t) >= t_relax, rate, 0.0)
        return PDESystem(
            [eq], [c(0, x, y) ~ 0.0, C ~ masked(frame(t, x, y), 0.0)],
            lattice_domain(t, (x, y), lattice),
            [t, x, y], [C, cell(t, x, y), ecm(t, x, y), frame(t, x, y)],
            [Dc, α, ε, t_relax]; name = :merks_field
        )
    end
end

"""
    MerksVasculogenesis(; name, lattice = (500, 500), contact_inhibited = false,
        λ = 50.0, V₀ = 100.0, λ_L = 5.0, L = 50.0, χ = 1000.0, T = 50.0,
        J = [0.0 20.0; 20.0 40.0])

Build the Merks 2006 vasculogenesis model: chemotaxis to an autocrine chemoattractant, with
elongated cells.

- `H = Σ J + λ Σ (a − V₀)² + λ_L Σ (l − L)²` (Eqs. 1, 4), with the cell length
  `l = 4√(λ_max(I)/a)` (Eq. 5, the `major_length` built-in). Elongation is what turns the
  round islands of pure chemotaxis into networks.
- Chemotaxis `ΔH = −χ (c(target) − c(source))` on every copy (Eq. 2, Savill–Hogeweg form).
  With `contact_inhibited = true` it acts only on extensions of a cell into the medium: the
  extension-only variant of Eq. 4 of Merks et al. 2008 (that paper's Figs. 11–13). It is
  not that paper's standard contact-inhibited model, which applies chemotaxis to every copy
  between a cell and the medium, extensions and retractions alike.
- `∂c/∂t = Dc ∇²c + σc δ_cell − δc c (1 − δ_cell)` (Eq. 6): cells secrete, and the
  chemoattractant decays only in the matrix. The field has zero flux at the lattice faces.
- Cells stay connected: a copy may not split a cell (a hard veto for the paper's
  connectivity penalty; `Local()`, the CompuCell3D rule: one arc of the losing cell on the
  8-ring, no full ring, and the gaining cell owns a face neighbor of the target).

The kinds are `medium` and `endothelial`, on a closed lattice with Moore contacts and
copies. Defaults are the 2006 parameter set in lattice units (2 µm/px, 30 s/MCS):
`T = 50`, `χ = 1000`, `J_cc = 40`, `J_cM = 20`, target area `V₀ = 100` with `λ = 50`, and
target length `L = 50` ("about 100 µm" in the paper text) with `λ_L = 5`. The field
parameters are `Dc = 0.75` (10⁻¹³ m²/s) and `σc = δc = 5.4·10⁻³` (1.8·10⁻⁴ s⁻¹). The 2008
runs used other values (`V₀ = 50` and Dataset S1); pass them as keywords, with
`contact_inhibited = true` for the extension-only variant.

Differences from the paper:
- connectivity is a hard veto, not the soft penalty `E₀ > 2000` on connectivity-breaking
  copies;
- the closed lattice edges cost nothing; the paper has frozen border cells with
  `J_cB = 100`;
- the field boundary is zero-flux; the paper's code holds `c = 0` on the outer ring
  (absorbing);
- `L = 50` follows the paper text; the released parameter files named for Fig. 4
  (`longcells.par`) use `L = 60`; pass `L = 60.0` for that reading.

The field solver is a problem keyword with no default. This model's is the paper's
schedule of 15 explicit Euler substeps per MCS (`Δt = 2 s`),
`field_solver = ExplicitEuler(substeps = 15, lower_bound = 0.0)`, which clips the field at
zero.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (500, 500)`: the lattice size (structural).
- `contact_inhibited = false`: apply chemotaxis only to extensions into the medium
  (structural).
- `λ = 50.0`, `V₀ = 100.0`: the area strength and target area.
- `λ_L = 5.0`, `L = 50.0`: the length strength and target length.
- `χ = 1000.0`: the chemotaxis strength.
- `T = 50.0`: the Metropolis temperature.
- `J = [0.0 20.0; 20.0 40.0]`: the contact energies over (medium, endothelial).

# Returns
- `PottsSystem`: the model.

# Examples
```julia
using PottsModels, Potts
prob = PottsProblem(MerksVasculogenesis(; name = :merks), merks_state(), (0, 10_000);
    field_solver = ExplicitEuler(substeps = 15, lower_bound = 0.0))
```

# References
- Merks, Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44 (2006).
- Merks et al., PLoS Comput. Biol. 4, e1000163 (2008).

See also [`merks_state`](@ref), [`Merks2006`](@ref), [`Merks2008`](@ref).
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
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @fields c = MerksField.vasculogenesis(lattice) (
        MerksField.cell => kind == endothelial, MerksField.ecm => kind == medium,
    )
    @parameters begin
        T = 50.0
        J[kind, kind] = [0.0 20.0; 20.0 40.0]
    end
    @relations proposal = Moore(1)
    @energy begin
        cells(endothelial) => λ * (volume - V₀)^2 + λ_L * (major_length - L)^2
        contacts => J[kind, neighbor_kind]
    end
    if contact_inhibited
        @drive copy =>
            ifelse(
            (old == 0) && (kind[new] == endothelial), -χ * (c[target] - c[source]),
            0.0
        )
    else
        @drive copy => -χ * (c[target] - c[source])
    end
    @constraint connectivity(endothelial)
    @sweep Metropolis(; temperature = T)
end

"""
    merks_state(; lattice = (500, 500),
        region = lattice == (500, 500) ? (333, 333) : lattice, n = 282, side = 10,
        seed = 1)

Return the start of [`MerksVasculogenesis`](@ref): `n` square endothelial cells at random
positions.

It is `layout(merks_layout(; lattice, kw...), lattice)`. The default is the 2006 paper's:
282 cells of 10² sites over 333 × 333 sites of a 500² lattice; 10² is the target area
`V₀ = 100`.

# Keywords
- `lattice = (500, 500)`: the lattice size.
- `region`, `n`, `side`, `seed`: as for [`merks_layout`](@ref).

# Returns
- The operating point `[ownership => σ, kind => fill(:endothelial, n)]`.

# Examples
```julia
using PottsModels
op = merks_state(; lattice = (100, 100), n = 20)
```

See also [`merks_layout`](@ref).
"""
merks_state(; lattice = (500, 500), kw...) = layout(merks_layout(; lattice, kw...), lattice)

"""
    merks_layout(; lattice = (500, 500),
        region = lattice == (500, 500) ? (333, 333) : lattice, n = 282, side = 10,
        seed = 1) -> Scattered

Return the layout behind [`merks_state`](@ref): `n` endothelial boxes of `side²` sites,
at least one medium site apart.

The boxes lie inside a centered `region`, `off + 2 : off + R − 1` per axis with
`off = (lattice − region) ÷ 2`; their corners are uniformly random in
`off + 2 : off + R − side`. The layout is
`Scattered(n, (side, side); region, kinds = [:endothelial], seed, gap = 1)`.

# Keywords
- `lattice = (500, 500)`: the lattice size, used to center `region`.
- `region`: the size `(R₁, R₂)` of the centered region; `(333, 333)` on the default
  lattice, else the whole lattice.
- `n = 282`: the number of cells.
- `side = 10`: the box side, in sites.
- `seed = 1`: the seed of the positions.

# Returns
- `Scattered`: the layout.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> merks_layout() isa Potts.AbstractLayout
true
```

See also [`merks2006_layout`](@ref).
"""
function merks_layout(;
        lattice = (500, 500), region = lattice == (500, 500) ? (333, 333) : lattice,
        n = 282, side = 10, seed = 1
    )
    off = (lattice .- region) .÷ 2
    reg = ntuple(d -> (off[d] + 2):(off[d] + region[d] - 1), 2)
    return Scattered(n, (side, side); region = reg, kinds = [:endothelial], seed, gap = 1)
end

"""
    merks2006_layout(; lattice = (500, 500), kw...) -> AbstractLayout

Return the [`Merks2006`](@ref) start: [`merks_layout`](@ref) inside a frozen border one
site thick.

It is `overlay(Frame(:border; width = 1), merks_layout(; lattice, kw...))`. The default is
the paper's Fig. 4 geometry: 282 cells of 10² over the central 333² of 500².

# Keywords
- `lattice = (500, 500)`: the lattice size.
- `kw...`: passed to [`merks_layout`](@ref).

# Returns
- `AbstractLayout`: the layout; paint it with `layout(l, lattice)`.

# Examples
```julia
using PottsModels, Potts
op = layout(merks2006_layout(), (500, 500))
```

See also [`Merks2006`](@ref).
"""
function merks2006_layout(; lattice = (500, 500), kw...)
    return overlay(Frame(:border; width = 1), merks_layout(; lattice, kw...))
end

"""
    merks2008_sprout(; rounds = 50, divisions = 7, seed = 1) -> AbstractLayout

Return the [`Merks2008`](@ref) sprouting start of the released parameter files
(`sprout_*.par`): one Eden blob, divided, inside a frozen border two sites thick.

The blob grows for `rounds` rounds from the lattice center with 8 neighbors and is divided
`divisions` times (7 gives 128 cells, 8 the 256 of the 2008 paper's Fig. 12):

```julia
overlay(Frame(:border; width = 2),
    Splits(Eden(Center(); rounds, kinds = [:endothelial], seed,
        neighborhood = Moore(1)), divisions; splits = :allow))
```

A few of the 128 cells are cut into pieces, as in the authors' code, so
`splits = :allow`.

# Keywords
- `rounds = 50`: the Eden rounds.
- `divisions = 7`: the number of times the blob is divided.
- `seed = 1`: the seed of the growth.

# Returns
- `AbstractLayout`: the layout; paint it with `layout(l, lattice)`.

# Examples
```julia
using PottsModels, Potts
op = layout(merks2008_sprout(), (202, 202))
```

See also [`merks2008_denovo`](@ref).
"""
function merks2008_sprout(; rounds = 50, divisions = 7, seed = 1)
    return overlay(
        Frame(:border; width = 2),
        Splits(
            Eden(Center(); rounds, kinds = [:endothelial], seed, neighborhood = Moore(1)),
            divisions; splits = :allow
        )
    )
end

"""
    merks2008_denovo(; lattice = (202, 202), n = 360, rounds = 10,
        region = (3:(lattice[1] - 2), 3:(lattice[2] - 2)), seed = 1) -> AbstractLayout

Return the [`Merks2008`](@ref) de novo start: `n` point seeds, each grown by Eden rounds,
inside a frozen border two sites thick.

The seeds are drawn with replacement in `region`, so coinciding seeds merge, and each grows
for `rounds` Eden rounds with 8 neighbors:

```julia
overlay(Frame(:border; width = 2),
    Eden(RandomPoints(n; region, replace = true, seed); rounds,
        kinds = [:endothelial], seed, neighborhood = Moore(1), shortfall = :allow))
```

The default is the released files' (`denovo_*.par`: 360 seeds on the 198² interior of 200²,
about 355 cells of 47 sites). The 2008 paper's Fig. 2 geometry is
`merks2008_denovo(; lattice = (502, 502), n = 1000, region = (85:417, 85:417))`.

# Keywords
- `lattice = (202, 202)`: the lattice size, used for the default `region`.
- `n = 360`: the number of seeds.
- `rounds = 10`: the Eden rounds.
- `region`: the ranges the seeds are drawn from.
- `seed = 1`: the seed of the draws and the growth.

# Returns
- `AbstractLayout`: the layout; paint it with `layout(l, lattice)`.

# Examples
```julia
using PottsModels, Potts
op = layout(merks2008_denovo(), (202, 202))
```

See also [`merks2008_sprout`](@ref).
"""
function merks2008_denovo(;
        lattice = (202, 202), n = 360, rounds = 10, region = (
            3:(lattice[1] - 2), 3:(lattice[2] - 2),
        ),
        seed = 1
    )
    return overlay(
        Frame(:border; width = 2),
        Eden(
            RandomPoints(n; region, replace = true, seed); rounds, kinds = [:endothelial],
            seed,
            neighborhood = Moore(1), shortfall = :allow
        )
    )
end

function _structural_choice(x, allowed, model, key)
    if x in allowed
        return x
    else
        throw(ArgumentError("$model: `$key` must be one of $(join(repr.(allowed), ", ")), \
            got $(repr(x))"))
    end
end

"""
    Merks2006(; name, lattice = (500, 500), rule = :soft, T = 50.0, λ = 50.0, A = 100.0,
        λ_L = 5.0, L = 50.0, E₀ = 5000.0, χcM = 1000.0, χcc = 1000.0, s = 0.0,
        J = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0])

Build the Merks 2006 vasculogenesis model with a frozen border: autocrine chemotaxis of
elongated cells.

The kinds are `medium`, `endothelial` and `border[frozen]`; start it with
[`merks2006_layout`](@ref). The model follows Variant E of
`docs/design/research/model-specs/01_merks.md`.

- Energy (Eqs. 1, 4, 5): `Σ J(1 − δ)` over the 8 Moore neighbors, `λ (a − A)²` and
  `λ_L (l − L)²` for every endothelial cell, with the length `l = 4√(λ_max/a)` from the
  cell's inertia tensor (`major_length`).
- Chemotaxis at every copy (Eq. 2, the files' `vecadherinknockout = true`):
  `−χ (f(c[target]) − f(c[source]))` with `f(c) = c/(1 + s c)`, `χ = χcM` when the target's
  or the source's owner is the medium and `χcc` otherwise; both are 1000 (the paper's γ)
  and `s = 0`.
- Connectivity: `rule = :soft` adds `E₀` to every copy that breaks the losing endothelial
  cell's 8-site ring (TST's `ConnectivityPreservedP`; under Metropolis this is TST's
  threshold shift); `rule = :hard` vetoes those copies instead.
- A frozen border (`Frame(:border)`, one site thick) with `J(c,B) = 100`, `J(M,B) = 0`.
- The field (Eq. 6): `∂c/∂t = Dc Δc + α[endothelial] − ε c [medium]`, 5-point
  `laplacian`, held at `c = 0` on the border after every substep (the masked condition
  `c ~ masked(frame, 0.0)`), stepped before each MCS's sweep
  (`@schedule fields, sweep`). The field is a plain MTK `PDESystem`, coupled with
  `@fields`.

Parameters, in lattice units (Δx = 2 µm, 1 MCS = 30 s): `T = 50`, `λ = 50`, `A = 100`,
`λ_L = 5`, `L = 50` ("about 100 µm"; the released files' 60 is `L = 60.0`), `E₀ = 5000`,
`χcM = χcc = 1000`, `s = 0`, and the field parameters `Dc = 0.75` (10⁻¹³ m²/s) and
`α = ε = 5.4·10⁻³` (1.8·10⁻⁴ s⁻¹). λ, A, λ_L, E₀ and `J(M,B)` are not in the paper; they
are the 2008 code's values, assumed for 2006. The paper's field solver is 15 explicit
substeps of 2 s per MCS.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (500, 500)`: the lattice size (structural).
- `rule = :soft`: `:soft` (penalty `E₀`) or `:hard` (veto) connectivity (structural).
  Throws an `ArgumentError` for another value.
- `T = 50.0`: the Metropolis temperature.
- `λ = 50.0`, `A = 100.0`: the area strength and target area.
- `λ_L = 5.0`, `L = 50.0`: the length strength and target length.
- `E₀ = 5000.0`: the connectivity penalty of `rule = :soft`.
- `χcM = 1000.0`, `χcc = 1000.0`: the chemotaxis strengths at cell–medium and cell–cell
  copies.
- `s = 0.0`: the saturation of `f`.
- `J = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]`: the contact energies over
  (medium, endothelial, border).

# Returns
- `PottsSystem`: the model.

# Examples
```julia
using PottsModels, Potts
prob = PottsProblem(Merks2006(; name = :m), layout(merks2006_layout(), (500, 500)),
    (0, 5760); field_solver = ExplicitEuler(substeps = 15))
```

# References
- Merks, Brodsky, Goligorsky, Newman & Glazier, Dev. Biol. 289, 44 (2006).

See also [`Merks2008`](@ref), [`MerksVasculogenesis`](@ref).
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
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @fields c = MerksField.merks2006(lattice) (
        MerksField.cell => kind == endothelial, MerksField.ecm => kind == medium,
        MerksField.frame => kind == border,
    )
    @parameters J[kind, kind] = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]
    @relations proposal = Moore(1)
    @energy begin
        cells(endothelial) => λ * (volume - A)^2 + λ_L * (major_length - L)^2
        contacts => J[kind, neighbor_kind]
    end
    @drive copy =>
        -ifelse((old == 0) | (new == 0), χcM, χcc) *
        (c[target] / (1 + s * c[target]) - c[source] / (1 + s * c[source]))
    if _structural_choice(rule, (:soft, :hard), "Merks2006", :rule) === :soft
        @drive connectivity(endothelial; rule = ArcOrPair(), penalty = E₀)
    else
        @constraint connectivity(endothelial; rule = ArcOrPair())
    end
    @schedule fields, sweep
    @sweep Metropolis(; temperature = T)
end

"""
    Merks2008(; name, lattice = (202, 202), mode = :extension_retraction, T = 50.0,
        λ = 25.0, A = 50.0, χcM = 500.0, χcc = 0.0, s = 0.0,
        J = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0])

Build the Merks 2008 model of contact-inhibited chemotaxis in de novo and sprouting
blood-vessel growth.

The kinds are `medium`, `endothelial` and `border[frozen]`; start it with
[`merks2008_sprout`](@ref) (Figs. 4–11) or [`merks2008_denovo`](@ref) (Fig. 2). The model
follows Variant CI of `docs/design/research/model-specs/01_merks.md`.

- Energy (Eq. 2): `Σ J(1 − δ)` over the 20 neighbors of `NeighborOrder(4)` (first to
  fourth order, the files' `neighbours = 3`), and `λ (a − A)²` for every endothelial cell.
  Copies also take their source among the 20 neighbors.
- Chemotaxis (Eq. 3): `−χ (f(c[target]) − f(c[source]))`, `f(c) = c/(1 + s c)`, with
  `χ = χcM` at cell–medium copies (the target's or the source's owner is the medium) and
  `χcc` at cell–cell copies. `χcc = 0` is contact inhibition; `χcc = χcM` removes it, and
  any value between is the continuous ratio of Fig. 5. `mode = :extension_only` (Eq. 4)
  drops the term when the source is the medium (a retraction).
- A frozen border (`Frame(:border; width = 2)`; the authors' 1-site frame on 200², whose
  20-site stencil reaches one site further) with `J(c,B) = 100`, `J(M,B) = 0`.
- The field (Eq. 1): `∂c/∂t = Dc Δc + α[endothelial] − ε c [medium]`, 5-point
  `laplacian`, `c = 0` on the border after every substep, stepped before each MCS's
  sweep. As in the released code the field is off for the first `t_relax` MCS (MCS 0 to
  `t_relax − 1`, the files' `relaxation`), so chemotaxis starts after it.

Parameters, in lattice units (Δx = 2 µm, 1 MCS = 30 s): `T = 50`, `λ = 25`, `A = 50`,
`χcM = 500`, `χcc = 0`, `s = 0`, and the field parameters `Dc = 0.75` (10⁻¹³ m²/s),
`α = ε = 0.03` (10⁻³ s⁻¹) and `t_relax = 100`. The paper's field solver is 15 explicit
substeps of 2 s per MCS.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (202, 202)`: the lattice size (structural).
- `mode = :extension_retraction`: `:extension_retraction` or `:extension_only`
  (structural). Throws an `ArgumentError` for another value.
- `T = 50.0`: the Metropolis temperature.
- `λ = 25.0`, `A = 50.0`: the area strength and target area.
- `χcM = 500.0`, `χcc = 0.0`: the chemotaxis strengths at cell–medium and cell–cell copies.
- `s = 0.0`: the saturation of `f`.
- `J = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]`: the contact energies over
  (medium, endothelial, border).

# Returns
- `PottsSystem`: the model.

# Examples
```julia
using PottsModels, Potts
prob = PottsProblem(Merks2008(; name = :m), layout(merks2008_sprout(), (202, 202)),
    (0, 10_100); field_solver = ExplicitEuler(substeps = 15))
```

# References
- Merks, Perryn, Shirinifard & Glazier, PLoS Comput. Biol. 4, e1000163 (2008).

See also [`Merks2006`](@ref), [`MerksVasculogenesis`](@ref).
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
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = NeighborOrder(4))
    @fields c = MerksField.merks2008(lattice) (
        MerksField.cell => kind == endothelial, MerksField.ecm => kind == medium,
        MerksField.frame => kind == border,
    )
    @parameters J[kind, kind] = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]
    @relations proposal = NeighborOrder(4)
    @energy begin
        cells(endothelial) => λ * (volume - A)^2
        contacts => J[kind, neighbor_kind]
    end
    if _structural_choice(
            mode, (:extension_retraction, :extension_only), "Merks2008", :mode
        ) === :extension_retraction
        @drive copy =>
            -ifelse((old == 0) | (new == 0), χcM, χcc) *
            (c[target] / (1 + s * c[target]) - c[source] / (1 + s * c[source]))
    else
        @drive copy => ifelse(
            new == 0, 0.0,
            -ifelse(old == 0, χcM, χcc) *
                (c[target] / (1 + s * c[target]) - c[source] / (1 + s * c[source]))
        )
    end
    @schedule fields, sweep
    @sweep Metropolis(; temperature = T)
end
