# Test-only models (D-254): not published, so not in PottsModels. The acceptance files use
# them by their bare names; every runner that includes an acceptance file includes this file
# first, guarded: `isdefined(Main, :SingleDivisionFixture) || include(…/fixtures.jl)`.
using Potts

"""
    SingleDivisionFixture(; name, lattice = (12, 8), …)

A small division fixture (it is not the OpenVT benchmark, see `OpenVTGrowingMonolayer`).
Epithelial cells with an area constraint and cell–medium adhesion on a closed lattice divide
once, at MCS 0, when their area has reached the target, splitting a cell mass variable
(plane normal `(1, 0)`).
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
