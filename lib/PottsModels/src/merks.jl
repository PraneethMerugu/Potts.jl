"""
    MerksVasculogenesis(; name, lattice = (8, 8), …)

Vasculogenesis by chemotaxis to an autocrine chemoattractant (Merks, Brodsky, Goligorsky,
Newman & Glazier, Dev. Biol. 289, 44, 2006): cells secrete `c`, which diffuses and decays;
extensions into the medium are biased up the gradient; cells stay connected. The field is
advanced by explicit Euler with at least two substeps per MCS (more when the diffusion
coefficient needs them for stability) and clipped at zero.

This is a reduced form, not the paper's model:
- **no cell-length constraint** `λ_L (l − L)²`, which the paper shows is needed for networks
  (without it cells form round islands), and no adhesion (paper: `J_cc = 40`, `J_cM = 20`);
- chemotaxis acts only on extensions into the medium (the contact-inhibited form of Merks
  et al., PLoS Comput. Biol. 2008), where the 2006 model applies it to every copy;
- `c` decays everywhere (paper: only in the medium);
- the defaults are a legacy 8×8 one-cell toy. In lattice units the paper has
  `T = 50`, `χ = 1000`, `Dc ≈ 0.75`, `σc = δc ≈ 5.4e-3` (2 µm/px, 30 s/MCS), 282 cells of
  area ≈ 100 on 500²;
- connectivity is a hard veto (paper: a penalty of about 2000), and the ring rule keeps the
  legacy two-cell fallback, which lets cells split.
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
