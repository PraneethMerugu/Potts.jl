"""
    OpenVTGrowingMonolayer(; name, lattice = (400, 400), A₀ = 25.0, λ = 20.0, τ = 84.0,
        β = 0.0, T = 20.0, J = [0.0 20.0; 20.0 20.0])

Build the OpenVT growing-monolayer benchmark (OpenVT reference models, `monolayer/`) with
the Artistoo parameter set: one cell grows into a colony on a closed lattice.

- An area constraint `λ (volume − V_target)²` with no net adhesion (`J_cc = J_cM = 20`).
- The target area grows by `A₀/τ` per MCS, so an unconstrained cell doubles in `τ` MCS.
- A cell divides at the deterministic size `2A₀` along a uniformly random plane, and both
  daughters restart at `V_target = A₀`.
- Type-1 contact inhibition: a cell grows only while `volume ≥ β V_target`. `β = 0` (the
  default) is the uninhibited baseline.

The kinds are `medium` and `cell`, and the cell variable is `V_target`. The lattice is
closed with Moore contacts, and copies come from the 8 Moore neighbors. Seed with
[`openvt_monolayer_state`](@ref). The benchmark measures cell count, colony area and radius
against time. The manuscript's parameter set is
[`OpenVTReferenceMonolayer`](@ref).

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (400, 400)`: the lattice size (structural).
- `A₀ = 25.0`: the target area of a new cell, in sites.
- `λ = 20.0`: the area strength.
- `τ = 84.0`: the doubling time of an unconstrained cell, in MCS.
- `β = 0.0`: the type-1 inhibition threshold.
- `T = 20.0`: the Metropolis temperature.
- `J = [0.0 20.0; 20.0 20.0]`: the contact energies over (medium, cell).

# Returns
- `PottsSystem`: the model.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> OpenVTGrowingMonolayer(; name = :colony, lattice = (100, 100)) isa PottsSystem
true
```

See also [`openvt_monolayer_state`](@ref), [`OpenVTReferenceMonolayer`](@ref).
"""
@potts_model OpenVTGrowingMonolayer begin
    @structural_parameters begin
        lattice = (400, 400)
    end
    @kinds medium cell
    @parameters begin
        A₀ = 25.0
        λ = 20.0
        τ = 84.0
        β = 0.0
        T = 20.0
        J[kind, kind] = [0.0 20.0; 20.0 20.0]
    end
    @variables V_target(cell) = A₀
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - V_target)^2
        contacts => J[kind, neighbor_kind]
    end
    @after_mcs V_target ~
        ifelse(volume >= β * Pre(V_target), Pre(V_target) + A₀ / τ, Pre(V_target))
    @divide cells(cell) when = volume >= 2A₀, along = RandomPlane(), V_target => A₀
    @sweep Metropolis(; temperature = T)
end

"""
    openvt_monolayer_state(; lattice = (400, 400), area0 = 25) -> Vector{Pair}

Return the initial state of [`OpenVTGrowingMonolayer`](@ref): one square cell of area close
to `area0` near the lattice center.

The square has side `round(Int, √area0)`.

# Keywords
- `lattice = (400, 400)`: the lattice size.
- `area0 = 25`: the target area, the model's `A₀`.

# Returns
- `Vector{Pair}`: the operating point `[ownership => σ, kind => [:cell]]`, with
  `σ::Matrix{Int32}`.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> σ = openvt_monolayer_state(; lattice = (20, 20))[1].second;

julia> count(==(1), σ)
25
```

See also [`OpenVTGrowingMonolayer`](@ref).
"""
function openvt_monolayer_state(; lattice = (400, 400), area0 = 25)
    σ = zeros(Int32, lattice)
    s = round(Int, sqrt(area0))
    lo = lattice .÷ 2 .- s ÷ 2
    σ[lo[1]:(lo[1] + s - 1), lo[2]:(lo[2] + s - 1)] .= 1
    return [ownership => σ, kind => [:cell]]
end
