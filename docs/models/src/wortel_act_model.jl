# The model built in docs/models/wortel_act.jl. The page shows its fragments (the lines after
# each `#> name` marker, up to the next marker or `#<`) and then runs the whole file;
# lib/PottsModels/test/tutorial_models.jl checks that it compiles to the same problem as
# `PottsModels.WortelAct`.
@potts_model ActMigration begin
    #> lattice
    @structural_parameters begin
        lattice = (200, 200)
        connected = false
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    #> kinds
    @kinds medium cell
    #> parameters
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
    #> variables
    @variables act(site) = 0.0
    #<
    @energy begin
        #> shape
        cells(cell) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
        #> contacts
        contacts => J[kind, kind′]
        #<
    end
    #> drive
    act_mean(s) = geomean(act[n] for n in Moore(1; include_self = true)(s) if owner[n] == owner[s])
    @drive copy => -(λ_act / max_act) * (act_mean(source) - act_mean(target))
    #> updates
    @on_copy act[target] ~ ifelse(new != 0, max_act, 0.0)
    @after_mcs act ~ max(Pre(act) - 1, 0)
    #> constraint
    if connected
        @constraint connectivity(cell; rule = ArcOrPair())
    end
    #> sweep
    @sweep Metropolis(; temperature = T)
end
