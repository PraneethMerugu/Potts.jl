# The model built in docs/models/openvt.jl. The page shows its fragments (the lines after
# each `#> name` marker, up to the next marker or `#<`) and then runs the whole file;
# lib/PottsModels/test/tutorial_models.jl checks that it compiles to the same problem as
# `PottsModels.OpenVTGrowingMonolayer`.
@potts_model GrowingMonolayer begin
    #> lattice
    @structural_parameters begin
        lattice = (400, 400)
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    #> kinds
    @kinds medium cell
    #> parameters
    @parameters begin
        A₀ = 25.0
        λ = 20.0
        τ = 84.0
        β = 0.0
        T = 20.0
        J[kind, kind] = [0.0 20.0; 20.0 20.0]
    end
    #> variables
    @variables V_target(cell) = A₀
    #<
    @energy begin
        #> area
        cells(cell) => λ * (volume - V_target)^2
        #> contacts
        contacts => J[kind, kind′]
        #<
    end
    #> growth
    @after_mcs V_target ~ ifelse(volume >= β * Pre(V_target), Pre(V_target) + A₀ / τ, Pre(V_target))
    #> division
    @divide cells(cell) when = volume >= 2A₀, along = RandomPlane(), V_target => A₀
    #> sweep
    @sweep Metropolis(; temperature = T)
end
