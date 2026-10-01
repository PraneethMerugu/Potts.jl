# The model built in docs/models/merks.jl. The page shows its fragments (the lines after
# each `#> name` marker, up to the next marker or `#<`) and then runs the whole file;
# lib/PottsModels/test/tutorial_models.jl checks that it compiles to the same problem as
# `PottsModels.MerksVasculogenesis`.
@potts_model Vasculogenesis begin
    #> lattice
    @structural_parameters begin
        lattice = (500, 500)
        contact_inhibited = false
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    #> kinds
    @kinds medium endothelial
    #> parameters
    @parameters begin
        λ = 25.0
        V₀ = 50.0
        λ_L = 5.0
        L = 30.0
        χ = 1000.0
        Dc = 0.75
        σc = 5.4e-3
        δc = 5.4e-3
        T = 50.0
        J[kind, kind] = [0.0 20.0; 20.0 40.0]
    end
    #> field
    @variables c(field) = 0.0
    #<
    @energy begin
        #> shape
        cells(endothelial) => λ * (volume - V₀)^2 + λ_L * (major_length - L)^2
        #> contacts
        contacts => J[kind, kind′]
        #<
    end
    #> drive
    if contact_inhibited
        @drive copy => ifelse((old == 0) && (kind[new] == endothelial), -χ * (c[target] - c[source]), 0.0)
    else
        @drive copy => -χ * (c[target] - c[source])
    end
    #> equation
    @equations D(c) ~ Dc * Δ(c) + σc * (kind == endothelial) - δc * c * (kind == medium)
    #> constraint
    @constraint connectivity(endothelial; rule = :local)
    #> sweep
    @sweep Metropolis(; temperature = T)
end
