# The model built in docs/models/graner_glazier.jl. The page shows its fragments (the lines
# after each `#> name` marker, up to the next marker or `#<`) and then runs the whole file;
# lib/PottsModels/test/tutorial_models.jl checks that it compiles to the same problem as
# `PottsModels.GranerGlazier`.
@potts_model CellSorting begin
    #> lattice
    @structural_parameters begin
        lattice = (72, 72)
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    #> kinds
    @kinds medium dark light
    #> parameters
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    #<
    @energy begin
        #> area
        cells(dark, light) => λ * (volume - V₀)^2
        #> contacts
        contacts => J[kind, kind′]
        #<
    end
    #> sweep
    @sweep Metropolis(; temperature = T)
end
