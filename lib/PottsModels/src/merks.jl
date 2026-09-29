"""
    MerksVasculogenesis(; name, lattice = (8, 8), …)

Vasculogenesis by chemotaxis to an autocrine chemoattractant (Merks, Brodsky, Goligorsky,
Newman & Glazier, Dev. Biol. 289, 44, 2006): cells secrete `c`, which diffuses and decays;
extensions into the medium are biased up the gradient; cells stay connected. The field is
advanced by explicit Euler with two substeps per MCS and clipped at zero, as in the legacy
code.
"""
@potts_model MerksVasculogenesis begin
    @structural_parameters begin
        lattice = (8, 8)
    end
    @kinds medium endothelial
    @parameters begin
        λ = 1.0
        V₀ = 6.0
        χ = 2.0
        Dc = 0.08
        σc = 0.02
        δc = 0.01
        T = 6.0
    end
    @variables c(field) = 0.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy cells(endothelial) => λ * (volume - V₀)^2
    @drive copy => ifelse((old == 0) && (kind[new] == endothelial), -χ * (c[target] - c[source]), 0.0)
    @equations D(c) ~ Dc * Δ(c) - δc * c + σc * (kind == endothelial)
    @constraint connectivity(endothelial; rule = :merks)
    @sweep Metropolis(; temperature = T, field_solver = ExplicitEuler(substeps = 2, lower = 0.0))
end
