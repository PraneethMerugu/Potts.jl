module DescriptorSpecializationFixtures

using PottsToolkit
using ModelingToolkitBase
using Symbolics

function direct_model(count::Integer; weight_default = 2.0)
    count > 0 || throw(ArgumentError("term count must be positive"))
    @parameters weight = weight_default
    site = SiteBinding(:site)
    endothelial = CellKind(:endothelial; extinction = RetireAtZero())
    extracellular = MediumKind(:extracellular)
    terms = AbstractPottsStatement[
        HamiltonianTerm(
            Symbol(:direct_, index);
            domain = sites(:lattice),
            anchor = site,
            expression = weight * occupancy(endothelial, site),
        )
        for index in 1:count
    ]
    @named direct = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3)),
            endothelial,
            extracellular,
            terms...,
            Protocol(Sweep(); name = :main),
        )),
        parameters = [weight],
    )
    return direct
end

function compile_direct_model(count::Integer; weight_default = 2.0)
    return compile(
        complete(direct_model(count; weight_default));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
end

end
