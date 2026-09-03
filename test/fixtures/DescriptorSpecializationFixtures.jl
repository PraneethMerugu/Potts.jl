module DescriptorSpecializationFixtures

using Potts
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

function lower_direct_model(count::Integer; weight_default = 2.0)
    scheduled = mtkcompile(complete(direct_model(count; weight_default)))
    return Potts._lower_scheduled_execution_plan(
        scheduled,
        SequentialCPM(),
        CPUBackend(),
        Float32,
    )
end

end
