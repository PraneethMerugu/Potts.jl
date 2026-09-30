"""
    WortelAct(; name, lattice = (8, 8), …)

Actin-inspired protrusive migration (Niculescu, Textor & de Boer, PLoS Comput. Biol. 11,
e1004280, 2015; the Wortel et al. 2021 parameterization used by the legacy code). A copy
into a site gains `λ_act/max_act` times the difference of the geometric-mean activity
around source and target (`geomean_shifted`, D-034). An extension into the medium is fully
active, any other gained site inactive; activity decays by one per MCS. Cells stay connected (Merks ring rule).

Legacy semantics that differ from the papers and Artistoo (the reference code):
- the mean is the shifted geometric mean; the papers use the plain one (zero if any
  same-cell neighbour is inactive);
- copies by the medium (retractions) get no Act term; the papers penalise retracting active
  sites (`+(λ_act/max_act)·GM(target)`), which about halves persistence when missing;
- only extensions into the medium activate a site; the papers activate every gained site;
- connectivity is always enforced, so the papers' "broken cell" regime cannot occur;
- the defaults are a legacy 8×8 toy. Niculescu et al. 2015's amoeboid cell: 200² torus,
  `T = 20`, `λ = 50`, `V₀ = 500`, `λₛ = 2`, `S₀ = 340`, `J = [0 20; 20 100]`,
  `λ_act = 200`, `max_act = 20`.
"""
@potts_model WortelAct begin
    @structural_parameters begin
        lattice = (8, 8)
    end
    @kinds medium endothelial
    @parameters begin
        λ = 1.0
        V₀ = 6.0
        λₛ = 0.05
        S₀ = 8.0
        λ_act = 4.0
        max_act = 5.0
        T = 8.0
        J[kind, kind] = [0.0 6.0; 6.0 2.0]
    end
    @variables act(site) = 0.0
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(endothelial) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
        contacts => J[kind, kind′]
    end
    act_mean(s) = geomean_shifted(act[n] for n in Moore(1; include_self = true)(s) if owner[n] == owner[s])
    @drive copy => ifelse(kind[new] == endothelial, -(λ_act / max_act) * (act_mean(source) - act_mean(target)), 0.0)
    @on_copy act[target] ~ ifelse((old == 0) && (new != 0), max_act, 0.0)
    @after_mcs act ~ max(Pre(act) - 1, 0)
    @constraint connectivity(endothelial; rule = :merks)
    @sweep Metropolis(; temperature = T)
end
