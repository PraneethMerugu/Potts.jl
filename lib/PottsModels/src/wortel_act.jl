"""
    WortelAct(; name, lattice = (200, 200), connected = false, λ = 50.0, V₀ = 500.0,
        λₛ = 2.0, S₀ = 340.0, λ_act = 200.0, max_act = 20.0, T = 20.0,
        J = [0.0 20.0; 20.0 100.0])

Build the Act model of actin-driven cell migration, with the semantics of its reference
code Artistoo.

- **Activity.** Every site a cell gains becomes fully active (`max_act`); a site taken by
  the medium is inactive; activity decays by one per MCS.
- **Act term.** Every copy gains `−(λ_act/max_act)(GM(source) − GM(target))`, where `GM(s)`
  is the plain geometric mean of the activity over `s` and its Moore neighbors owned like
  `s` (zero if any is inactive, and zero for the medium). Retracting active sites is
  therefore penalized.
- **Energies.** Adhesion `J`, area `λ(V − V₀)²` and perimeter `λₛ(P − S₀)²`, where the
  perimeter counts Moore neighbors owned by others.
- **Connectivity.** `connected = true` adds the ring rule
  `connectivity(cell; rule = ArcOrPair())` (one arc, or else two cells and no medium on the
  ring), which Niculescu et al. use for multicellular runs. Without it, cells can break at
  high `λ_act`, as Wortel et al. report.

The kinds are `medium` and `cell`, and the site variable `act` holds the activity. The
lattice is a periodic torus with Moore contacts, and copies come from the 8 neighbors. The
defaults are the amoeboid cell of Niculescu et al. (Methods; Fig. 6) on a 200² torus;
`max_act = 80` gives the keratocyte-like cell.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (200, 200)`: the lattice size (structural).
- `connected = false`: add the connectivity constraint (structural).
- `λ = 50.0`, `V₀ = 500.0`: the area strength and target area.
- `λₛ = 2.0`, `S₀ = 340.0`: the perimeter strength and target perimeter.
- `λ_act = 200.0`: the strength of the Act term.
- `max_act = 20.0`: the activity of a newly gained site, in MCS of decay.
- `T = 20.0`: the Metropolis temperature.
- `J = [0.0 20.0; 20.0 100.0]`: the contact energies over (medium, cell).

# Returns
- `PottsSystem`: the model.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> WortelAct(; name = :act, lattice = (50, 50), max_act = 80.0) isa PottsSystem
true
```

# References
- Niculescu, Textor & de Boer, PLoS Comput. Biol. 11, e1004280 (2015).
- Wortel et al., Biophys. J. 120, 2609 (2021).

See also [`GranerGlazier`](@ref).
"""
@potts_model WortelAct begin
    @structural_parameters begin
        lattice = (200, 200)
        connected = false
    end
    @kinds medium cell
    @parameters begin
        λ = 50.0
        V₀ = 500.0
        λₛ = 2.0
        S₀ = 340.0
        λ_act = 200.0
        max_act = 20.0
        T = 20.0
        J[kind, kind] = [0.0 20.0; 20.0 100.0]
    end
    @variables act(site) = 0.0
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
        contacts => J[kind, neighbor_kind]
    end
    act_mean(s) = geomean(
        act[n]
            for n in Moore(1; include_self = true)(s) if owner[n] == owner[s]
    )
    @drive copy => -(λ_act / max_act) * (act_mean(source) - act_mean(target))
    @on_copy act[target] ~ ifelse(new != 0, max_act, 0.0)
    @after_mcs act ~ max(Pre(act) - 1, 0)
    if connected
        @constraint connectivity(cell; rule = ArcOrPair())
    end
    @sweep Metropolis(; temperature = T)
end
