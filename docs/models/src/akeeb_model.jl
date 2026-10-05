# The model built in docs/models/akeeb.jl. The page shows its fragments (the lines after
# each `#> name` marker, up to the next marker or `#<`) and then runs the whole file;
# lib/PottsModels/test/tutorial_models.jl checks that it compiles to the same problem as
# `PottsModels.AkeebInvasion`.
@potts_model LeaderFollowerInvasion begin
    #> lattice
    @structural_parameters begin
        lattice = (500, 300)
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = Moore(1))
    @relations proposal = VonNeumann(1)
    #> kinds
    @kinds medium leader follower
    #> parameters
    @parameters begin
        λᵥ = 2.0
        μ = 24.0
        T = 10.0
        V_max = 20.0
        clock_min = 75.0
        clock_spread = 50.0
        J[kind, kind] = [0.0 2.0 10.0; 2.0 16.0 2.0; 10.0 2.0 5.0]
    end
    #> variables
    @variables begin
        V_target(cell) = 10.0
        clock(cell) = -1.0
        rate(cell) = 0.0
        cue(site) = 0.0
    end
    #<
    @energy begin
        #> volume
        cells => λᵥ * (volume - V_target)^2
        #> contacts
        contacts => J[kind, kind′]
        #<
    end
    #> drive
    @drive copy => ifelse((kind[new] == leader) || (kind[old] == leader), -μ * (cue[target] - cue[source]), 0.0)
    #> constraints
    @constraint connectivity(leader, follower)
    @constraint no_extinction
    #> growth
    @after_mcs begin
        V_target ~ ifelse(Pre(V_target) < V_max, Pre(V_target) + rate, Pre(V_target))
        clock ~ ifelse(Pre(clock) >= 0, Pre(clock) + 1, Pre(clock))
    end
    #> division
    @divide cells(follower) when = (clock >= 0) && (volume > V_max) && (clock > clock_min + clock_spread * rand()),
        along = RandomPlane(), V_target => Split(), clock => 0.0
    #> sweep
    @sweep Metropolis(; temperature = T)
end
