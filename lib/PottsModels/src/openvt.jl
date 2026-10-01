"""
    OpenVTGrowingMonolayer(; name, lattice = (400, 400), …)

The OpenVT growing-monolayer benchmark (OpenVT reference models, `monolayer/`) with the
Artistoo parameter set. One cell grows into a colony on a closed lattice:

- area constraint `λ (volume - V_target)²` with no net adhesion (`J_cc = J_cM = 20`);
- the target area grows by `A₀/τ` per MCS, so an unconstrained cell doubles in `τ` MCS;
- a cell divides at the deterministic size `2A₀` along a uniformly random plane, and both
  daughters restart at `V_target = A₀`;
- type-1 contact inhibition: a cell grows only while `volume ≥ β V_target`. `β = 0` (the
  default) is the uninhibited baseline; the benchmark's inhibited runs use `β ≈ 0.9`.

Seed with [`openvt_monolayer_state`](@ref). The benchmark measures cell count, colony area
and radius against time.
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
        contacts => J[kind, kind′]
    end
    @after_mcs V_target ~ ifelse(volume >= β * Pre(V_target), Pre(V_target) + A₀ / τ, Pre(V_target))
    @divide cells(cell) when = volume >= 2A₀, along = RandomPlane(), V_target => A₀
    @sweep Metropolis(; temperature = T)
end

"""
    openvt_monolayer_state(; lattice = (400, 400), A₀ = 25)

One square cell of area ≈ `A₀` at the lattice centre: `[ownership => σ, kind => [:cell]]`.
"""
function openvt_monolayer_state(; lattice = (400, 400), A₀ = 25)
    σ = zeros(Int32, lattice)
    s = round(Int, sqrt(A₀))
    lo = lattice .÷ 2 .- s ÷ 2
    σ[lo[1]:(lo[1] + s - 1), lo[2]:(lo[2] + s - 1)] .= 1
    return [ownership => σ, kind => [:cell]]
end

"""
    SingleDivisionFixture(; name, lattice = (12, 8), …)

A small division fixture (formerly `OpenVTMonolayer`; it is not the OpenVT benchmark, see
[`OpenVTGrowingMonolayer`](@ref)). Epithelial cells with an area constraint and
cell–medium adhesion on a closed lattice divide once, at MCS 0, when their area has
reached the target, splitting a cell mass variable (plane normal `(1, 0)`).
"""
@potts_model SingleDivisionFixture begin
    @structural_parameters begin
        lattice = (12, 8)
    end
    @kinds medium epithelial
    @parameters begin
        λ = 2.0
        V₀ = 8.0
        T = 2.0
        J[kind, kind] = [0.0 4.0; 4.0 0.0]
    end
    @variables mass(cell) = 8.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(epithelial) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @divide cells(epithelial) when = (mcs == 0) && (volume >= V₀), along = (1.0, 0.0), mass => Split()
    @sweep Metropolis(; temperature = T)
end
