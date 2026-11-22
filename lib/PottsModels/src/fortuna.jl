# The F-actin field of the Fortuna model as a plain MTK `PDESystem` on the 3D lattice,
# coupled into the model with `@fields`. Its one input, `source`, is a 0/1 site field that
# the `@fields` line binds to the site predicate of Eq 6: a lamellipodium site with a face
# neighbor in the substrate. The parameters keep the names and defaults of the model.
module FortunaField
    using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters,
        t_nounits as t
    using Potts.LatticePDE: laplacian, lattice_domain
    const Dt = Differential(t)
    @parameters x y z
    @variables F(..) source(..)::Bool [input = true]

    # Eq 6: `∂F/∂t = D_F ΔF − k_decay F + k_source [source]`, on the whole lattice. The
    # periodic x and y axes and the closed z axis come from the model's lattice (no
    # condition: zero flux at the z faces).
    function factin(lattice)
        @parameters D_F = 1.0e-4 k_decay = 0.9 k_source = 0.9
        X, S = F(t, x, y, z), source(t, x, y, z)
        eq = Dt(X) ~ D_F * laplacian(X) - k_decay * X + k_source * S
        return PDESystem(
            [eq], [F(0, x, y, z) ~ 0.0], lattice_domain(t, (x, y, z), lattice),
            [t, x, y, z], [X, S], [D_F, k_decay, k_source]; name = :factin
        )
    end
end

"""
    FortunaMigration(; name, lattice = (120, 120, 31), drive = :extension_only,
        factin_source = :substrate_contact, R = 15.0, φ_n = 0.15, φ_l = 0.05, T = 100.0,
        λ = 10.0, λ_F = 150.0, c = 0.1, D_F = 1.0e-4, k_decay = 0.9, k_source = 0.9, J)

Build the 3D crawling-cell model of Fortuna et al. (2020): one cell made of a cytoplasm, a
nucleus and a lamellipodium on a flat substrate, driven by an F-actin field that the
lamellipodium makes where it touches the substrate.

- **Lattice.** `lattice = (L, L, L_z)`, periodic in x and y, closed in z, with a frozen
  `substrate` plane at z = 1 and a frozen `lid` plane at z = L_z. Contacts reach the 32
  neighbors of the fourth shell (`NeighborOrder(4)`); copies go between face neighbors
  (`VonNeumann(1)`). [`fortuna_lattice`](@ref) gives the lattice of a radius `R` and a
  lamellipodium fraction `φ_l`.
- **Energies.** Eq 5: `λ (volume − V_target)²` for each compartment, with targets fixed
  from t = 0 at `(1 − φ_n − φ_l)V`, `φ_n V` and `φ_l V`, `V = (4π/3)R³`. Eq 4: the
  contact energies `J` of Table 1 (J_cytoplasm–lamellipodium = 20), plus a lid row taken
  from the authors' code (the paper has no lid).
- **F-actin.** Eq 6: `∂F/∂t = D_F ΔF − k_decay F + k_source` on lamellipodium sites with
  a substrate face neighbor, on the whole lattice. The field is the `PDESystem`
  `FortunaField.factin`, coupled with `@fields`; the site predicate is its input. With
  `factin_source = :all_lamellipodium` the source covers every lamellipodium site, as Eq 9 of
  Thomas et al. (2022) prints it.
- **Drive.** Eq 7 as printed: a copy of a lamellipodium into the medium (an extension)
  adds `λ_F (F(target) − F(source))` to ΔH. With `drive = :extension_retraction` the same
  term also applies to a copy of the medium into a lamellipodium (a retraction), as in the
  authors' code.
- **Protrusion.** Once per MCS, after the sweep and the field step, each cytoplasm site
  with a substrate face neighbor converts to the lamellipodium with probability
  `p = c (1 − V₃/(φ_l V))`, with `V₃` the lamellipodium volume at the start of the pass.
  The first conversion creates the lamellipodium; `lam_births` counts the creations.
- **Observables**, read on the cytoplasm row (the cluster root): `nx`, `ny` (the nucleus
  centroid in x and y), `lx`, `ly` (the lamellipodium centroid), `Πx`, `Πy` (the
  cytoplasm–nucleus polarization Π_CN−N, minimum image) and `lam_cyto` (the lamellipodium
  sites with a cytoplasm face neighbor; 0 means that the lamellipodium is detached).

The fields run on the default discretization (the fused lattice fields of LatticePDE).

Differences from the paper, and choices where it is silent (the model page has the same
table):
- protrusion rate `c`: not stated; 0.1, the constant of the authors' code, provisional
  until the reproduction runner calibrates it on the volume check (0.1, then 0.3, then
  1.0);
- `V₃` in `p`: the actual lamellipodium volume at the start of each protrusion pass;
- J_cytoplasm–lamellipodium: 20 as in Table 1 (the authors' code uses 10);
- lid: not in the paper; a frozen lid plane at z = L_z with the contact row of the
  authors' code;
- field solver: not stated; one explicit Euler step per MCS, as in the authors' code
  (`field_solver = ExplicitEuler(substeps = 1)`);
- field boundary conditions: not stated; periodic in x and y, zero flux in z, on the
  whole lattice including the substrate and lid planes, as in the authors' code;
- update order: not stated; sweep, then field step, then protrusion. The field step is the
  same update as the authors' code (CompuCell3D diffuses and decays, then secretes; with
  one explicit step per MCS and a source that does not depend on F the two are
  identical). Secreting first would give F ≈ 0.1;
- drive: Eq 7 as printed, extensions only (the default); `drive = :extension_retraction`
  adds retractions, as in the authors' code;
- targets: the paper's, fixed from t = 0;
- start: the concentric spheres of the supplement (S1, p. 6): an outer ball of radius R
  and a nucleus ball of 216 sites, relaxing to the targets (see [`fortuna_layout`](@ref));
  the authors' code instead puts a cube nucleus in a ball that rests on the substrate;
- lattice: `8R`, or `10R` when `R ≥ 20` and `φ_l ≥ 0.2`, truncated, the rule of the
  authors' code inside the paper's range;
- nucleus track: the nucleus center of mass, in x and y.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (120, 120, 31)`: the lattice size (structural); the lattice of `R = 15`.
- `drive = :extension_only`: the copies that the F-actin drive applies to (structural).
  `:extension_only` is Eq 7 as printed; `:extension_retraction` adds retractions, as the
  authors' code does.
- `factin_source = :substrate_contact`: the sites of the F-actin source (structural).
  `:substrate_contact` is Eq 6 of Fortuna et al. (2020), the lamellipodium sites with a
  substrate face neighbor; `:all_lamellipodium` is Eq 9 of Thomas et al. (2022), every
  lamellipodium site. Throws an `ArgumentError` for any other value.
- `R = 15.0`: the cell radius in sites. Pass the radius of the lattice you use.
- `φ_n = 0.15`, `φ_l = 0.05`: the nucleus and lamellipodium volume fractions.
- `T = 100.0`, `λ = 10.0`: the temperature and the volume constraint strength.
- `λ_F = 150.0`: the F-actin drive.
- `c = 0.1`: the protrusion rate (not stated in the paper).
- `D_F = 1.0e-4`, `k_decay = 0.9`, `k_source = 0.9`: the F-actin field parameters.
- `J`: the contact energies over the kinds (Table 1 and the lid row).

# Returns
- `PottsSystem`: the model.

# Examples
```julia
using PottsModels, Potts
R, φ_l = 10, 0.05
sys = FortunaMigration(; name = :fortuna, lattice = fortuna_lattice(R, φ_l))
op = [fortuna_layout(R, sys); :R => Float64(R); :φ_l => φ_l]
prob = PottsProblem(sys, op, (0, 1000); seed = 1,
    field_solver = ExplicitEuler(substeps = 1))
sol = solve(prob, SequentialCPM(); saveat = 50)
```

# References
- Fortuna, Perrone, Krug, Susin, Belmonte, Thomas, Glazier & de Almeida, Biophys. J. 118,
  2801 (2020).
- Thomas, Fortuna, Perrone, Graner & de Almeida, Physica A 587, 126511 (2022): the
  polarization study, with the source of Eq 9 (`factin_source = :all_lamellipodium`).

See also [`fortuna_lattice`](@ref), [`fortuna_layout`](@ref).
"""
@potts_model FortunaMigration begin
    @structural_parameters begin
        lattice = (120, 120, 31)                   # R = 15: int(8R)² × int(2.1R)
        drive = :extension_only                    # or :extension_retraction
        factin_source = :substrate_contact         # or :all_lamellipodium
    end
    @kinds medium substrate[frozen] lid[frozen] cytoplasm lamellipodium nucleus
    @parameters begin
        R = 15.0                                   # cell radius (sites)
        φ_n = 0.15                                 # nucleus volume fraction (Table 1)
        φ_l = 0.05                                 # lamellipodium volume fraction
        T = 100.0                                  # temperature (Table 1)
        λ = 10.0                                   # volume constraint, every compartment
        λ_F = 150.0                                # F-actin drive (Eq 7)
        c = 0.1                                    # protrusion rate; the authors' constant
        J[kind, kind] = Pairs(
            default = 0.0,
            (medium, substrate) => 20, (medium, cytoplasm) => 20,
            (medium, lamellipodium) => 40 / 3, (medium, nucleus) => 100,
            (substrate, cytoplasm) => 20, (substrate, lamellipodium) => 20 / 3,
            (substrate, nucleus) => 100,
            (cytoplasm, lamellipodium) => 20,      # Table 1 (the authors' code uses 10)
            (cytoplasm, nucleus) => 20, (lamellipodium, nucleus) => 40,
            # the lid row, from the authors' code
            (medium, lid) => -20, (lid, cytoplasm) => 20,
            (lid, lamellipodium) => 40 / 3, (lid, nucleus) => 100
        )
    end
    @variables begin
        # fixed from t = 0; V = (4π/3)R³
        V_target(cell) = ifelse(
            kind == nucleus, φ_n,
            ifelse(
                kind == lamellipodium, φ_l,
                ifelse(kind == cytoplasm, 1 - φ_n - φ_l, 0.0)
            )
        ) * (4 / 3 * 3.141592653589793 * R^3)
        lam_births(model) = 0.0                    # lamellipodium creations
    end
    @lattice Lattice(
        lattice; boundary = (Periodic(), Periodic(), Closed()),
        neighborhood = NeighborOrder(4)
    )
    @relations proposal = VonNeumann(1)

    touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0

    # Eq 6: the source on lamellipodium sites with a substrate face neighbor (the `ifelse`
    # skips the neighbor fold at the other sites); Thomas et al. (2022) Eq 9: the source
    # on every lamellipodium site
    factin_source in (:substrate_contact, :all_lamellipodium) || throw(
        ArgumentError(
            "FortunaMigration: `factin_source` must be one of :substrate_contact, \
            :all_lamellipodium, got $(repr(factin_source))"
        )
    )
    @fields F = FortunaField.factin(lattice) (
        FortunaField.source => (
            factin_source === :substrate_contact ?
                ifelse(kind == lamellipodium, touches_substrate(site), false) :
                kind == lamellipodium
        ),
    )
    @energy begin
        cells(cytoplasm, lamellipodium, nucleus) => λ * (volume - V_target)^2    # Eq 5
        contacts => J[kind, neighbor_kind]                                       # Eq 4
    end
    # Eq 7: the F-actin term on an extension (a lamellipodium copied into the medium); the
    # variant also applies it to a retraction (the medium copied into a lamellipodium)
    drive in (:extension_only, :extension_retraction) || throw(
        ArgumentError(
            "FortunaMigration: `drive` must be one of :extension_only, \
            :extension_retraction, got $(repr(drive))"
        )
    )
    if drive === :extension_only
        @drive copy => ifelse(
            (kind[new] == lamellipodium) & (old == 0), λ_F * (F[target] - F[source]), 0.0
        )
    else
        @drive copy => ifelse(
            ((kind[new] == lamellipodium) & (old == 0)) |
                ((kind[old] == lamellipodium) & (new == 0)),
            λ_F * (F[target] - F[source]), 0.0
        )
    end
    # p on the start-of-pass lamellipodium volume; clamped to [0, 1]; NaN converts nothing
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = touches_substrate(site)
        p = c * (1 - volume[to] / (φ_l * (4 / 3 * 3.141592653589793 * R^3)))
        lam_births += created
    end
    @observed begin
        nx(cell) ~ centroid(sibling(nucleus), 1)
        ny(cell) ~ centroid(sibling(nucleus), 2)
        lx(cell) ~ centroid(sibling(lamellipodium), 1)
        ly(cell) ~ centroid(sibling(lamellipodium), 2)
        Πx(cell) ~ volume * minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1) /
            (volume + volume[sibling(nucleus)])
        Πy(cell) ~ volume * minimum_image(centroid(2) - centroid(sibling(nucleus), 2), 2) /
            (volume + volume[sibling(nucleus)])
        lam_cyto(cell) ~ integral(
            (kind == lamellipodium) *
                (count(true for n in VonNeumann(1)(site) if kind[n] == cytoplasm) > 0);
            over = cluster
        )
    end
    @sweep Metropolis(; temperature = T)
end

"""
    fortuna_lattice(R, φ_l) -> (L, L, L_z)

Return the lattice of [`FortunaMigration`](@ref) at cell radius `R` and lamellipodium
fraction `φ_l`.

`L = int(8R)`, or `int(10R)` when `R ≥ 20` and `φ_l ≥ 0.2`, and `L_z = int(2.1R)`: the
rule of the authors' code, inside the paper's range `L ∈ [8R, 14R]`, `L_z = 2.1R`. `int`
truncates.

# Examples
```julia
fortuna_lattice(15, 0.10)   # (120, 120, 31)
```
"""
function fortuna_lattice(R::Real, φ_l::Real)
    L = (R >= 20 && φ_l >= 0.2) ? trunc(Int, 10R) : trunc(Int, 8R)
    return (L, L, trunc(Int, 2.1R))
end

"""
    fortuna_layout(R, sys; nucleus = :ball) -> [ownership => σ, kind => kinds, cluster => ids]

Return the start of [`FortunaMigration`](@ref) on the lattice of `sys`: the paper's two
concentric balls (supplement S1, p. 6), no lamellipodium, the substrate plane at z = 1 and
the lid at z = L_z. With `nucleus = :cube` the nucleus is a cube of 6³ sites instead, the
start of Thomas et al. (2022): "a spherical cell with no lamellipodium engulfing a cubic
nucleus resting over the substrate".

- Both balls are centered at `(L/2 + 1, L/2 + 1, R + 3/2)`, both strict (`d < r`). The
  supplement puts the center at `L_z/2` with `L_z = 2.1R`, so the ball rests on the
  substrate in the continuum. On the lattice that center can leave an empty layer, so the
  center sits `R` above the substrate's top face (z = 3/2): the lowest layer of the ball
  is z = 2 for every `R`.
- The outer ball has radius `R`, the whole cell volume `V = (4π/3)R³`. Its top layer is
  z = 2R + 1; the lid is painted last, so it cuts that layer where `L_z ≤ 2R + 1`. The
  cytoplasm is the outer ball minus the nucleus.
- The nucleus ball has the volume of 216 sites, `r_n = ∛(216/(4π/3))`. Its site count
  depends on where the center falls on the lattice (216 for a center between sites in z,
  fewer for a center on a site).
- The start volumes are not the targets: the volume constraints relax them to the fixed
  targets `(1 − φ_n − φ_l)V`, `φ_n V` and `φ_l V`.
- The cube (`nucleus = :cube`) spans `ceil(c − 3):ceil(c − 3) + 5` on each axis around
  the same center `c`: 216 sites for every `R`. Thomas et al. do not state its size; 6³ is
  the cube of the authors' code, with the code's offset (`x − 3:x + 2` around an integer
  center), so in x and y it sits half a site off the ball's center.
- Cells: 1 cytoplasm, 2 nucleus, 3 substrate, 4 lid; the cytoplasm and the nucleus share
  a cluster.

# Keywords
- `nucleus::Symbol = :ball`: `:ball` (Fortuna et al. 2020, supplement S1) or `:cube`
  (Thomas et al. 2022). Throws an `ArgumentError` for any other value.

The operating point holds no parameter values: add `:R => R, :φ_l => φ_l`.

# Examples
```julia
sys = FortunaMigration(; name = :fortuna, lattice = fortuna_lattice(10, 0.05))
op = [fortuna_layout(10, sys); :R => 10.0; :φ_l => 0.05]
```
"""
function fortuna_layout(R::Real, sys; nucleus::Symbol = :ball)
    nucleus in (:ball, :cube) || throw(
        ArgumentError("fortuna_layout: `nucleus` must be :ball or :cube, got $(repr(nucleus))")
    )
    L, _, Lz = Potts.lattice(sys).dims
    c = (L / 2 + 1, L / 2 + 1, R + 1.5)                    # resting on the substrate
    center = Point(c...)
    region = if nucleus === :ball
        Interior(Sphere(center, cbrt(216 / (4π / 3))))
    else
        map(x -> (ceil(Int, x - 3)):(ceil(Int, x - 3) + 5), c)   # 6³ sites
    end
    body = Group(
        Objects(Interior(Sphere(center, Float64(R))); kinds = [:cytoplasm]),
        Fill(:nucleus; region)
    )
    return layout(
        overlay(
            body, Fill(:substrate; region = (1:L, 1:L, 1:1)),
            Fill(:lid; region = (1:L, 1:L, Lz:Lz))
        ), sys
    )
end
