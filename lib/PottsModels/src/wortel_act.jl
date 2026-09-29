"""
    WortelAct(; name, lattice = (8, 8), …)

Actin-inspired protrusive migration (Niculescu, Textor & de Boer, PLoS Comput. Biol. 11,
e1004280, 2015; the Wortel et al. 2021 parameterization used by the legacy code). A copy
into a site gains `λ_act/max_act` times the difference of the geometric-mean activity
around source and target (`geomean_shifted`, D-034); a gained site is fully active and
activity decays by one per MCS. Cells stay connected (Merks ring rule).
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
