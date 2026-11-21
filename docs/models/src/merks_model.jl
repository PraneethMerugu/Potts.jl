# The model built in docs/models/merks.jl. The page shows its fragments (the lines after
# each `#> name` marker, up to the next marker or `#<`) and then runs the whole file;
# lib/PottsModels/test/tutorial_models_tests.jl checks that it compiles to the same problem
# as `PottsModels.MerksVasculogenesis`.
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: laplacian, lattice_domain

#> equation
function chemoattractant(lattice)
    t = Potts.t
    @parameters x y Dc = 0.75 σc = 5.4e-3 δc = 5.4e-3
    @variables c(..) cell(..)::Bool [input = true] ecm(..)::Bool [input = true]
    C = c(t, x, y)
    eq = Differential(t)(C) ~ Dc * laplacian(C) + σc * cell(t, x, y) - δc * C * ecm(t, x, y)
    return PDESystem(
        [eq], [c(0, x, y) ~ 0.0], lattice_domain(t, (x, y), lattice), [t, x, y],
        [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc]; name = :merks_field
    )
end
#<

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
        λ = 50.0
        V₀ = 100.0
        λ_L = 5.0
        L = 50.0
        χ = 1000.0
    end
    #> field
    @fields c = chemoattractant(lattice) (
        :cell => kind == endothelial, :ecm => kind == medium,
    )
    #> contact_parameters
    @parameters begin
        T = 50.0
        J[kind, kind] = [0.0 20.0; 20.0 40.0]
    end
    #<
    @energy begin
        #> shape
        cells(endothelial) => λ * (volume - V₀)^2 + λ_L * (major_length - L)^2
        #> contacts
        contacts => J[kind, neighbor_kind]
        #<
    end
    #> drive
    if contact_inhibited
        @drive copy =>
            ifelse(
            (old == 0) && (kind[new] == endothelial), -χ * (c[target] - c[source]),
            0.0
        )
    else
        @drive copy => -χ * (c[target] - c[source])
    end
    #> constraint
    @constraint connectivity(endothelial)
    #> sweep
    @sweep Metropolis(; temperature = T)
end
