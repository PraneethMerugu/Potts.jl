"""
    OpenVTMonolayer(; name, lattice = (12, 8), …)

A single-division fixture inherited from the legacy code under the OpenVT name. It is *not*
the OpenVT growing-monolayer benchmark: epithelial cells with an area constraint and
cell–medium adhesion on a closed lattice divide once, at MCS 0, when their area has reached
the target, splitting a cell mass variable (plane normal `(1, 0)`).

The benchmark (OpenVT reference models, `monolayer/`) grows one central cell into a colony:
target area grows by `A₀/τ` per MCS, cells divide at `2A₀` along a random plane, there is no
net adhesion (`J_cc = J_cM`), optional contact inhibition, and it measures cell count,
colony area and radius against time.
"""
@potts_model OpenVTMonolayer begin
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
