using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics
using InteractiveUtils
import CorePotts

include("../test/fixtures/DescriptorSpecializationFixtures.jl")
using .DescriptorSpecializationFixtures
include("../test/fixtures/NeutralExternalTerms.jl")
using .NeutralExternalTerms

function state_schema(index)
    return CorePotts.CompilerSPI.StateBlockSchema(
        CorePotts.CompilerSPI.QualifiedResourceIdentity(
            (), Symbol(:state_, index)
        ),
        v"1.0.0",
        :site,
        Float64,
        (2,),
        2,
        :structure_of_arrays,
        :provided_or_zero,
        :shape_and_finite,
        :logical,
        :preserve,
        :declared,
        :bounded_write,
        :adapt_storage,
        :copy,
        :logical_copy,
        :qualified,
        true,
    )
end

function state_block_typed_ir_size(state, handle)
    typed = only(code_typed(
        CorePotts.CompilerSPI.state_block,
        Tuple{typeof(state), typeof(handle)};
        optimize = true,
    ))
    return ncodeunits(sprint(show, first(typed)))
end

function compile_external_model(count::Integer)
    @variables external_activity
    @parameters external_weight = 2.0
    endothelial = CellKind(
        :external_endothelial; extinction = RetireAtZero()
    )
    extracellular = MediumKind(:external_medium)
    site = SiteBinding(:external_site)
    activity = SiteState(
        external_activity;
        name = :external_activity,
        initial = 1.0,
        owner = endothelial,
        lifecycle = PreserveOnOwnershipChange(),
    )
    terms = AbstractPottsStatement[
        NeutralExternalTerms.ExternalWeightedSiteTerm(
            Symbol(:external_, index),
            external_weight,
            external_activity,
            endothelial,
            site,
        )
        for index in 1:count
    ]
    @named external = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3)),
            endothelial,
            extracellular,
            activity,
            terms...,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [external_activity],
        parameters = [external_weight],
    )
    scheduled = mtkcompile(complete(
        external; registry = NeutralExternalTerms.registry()
    ))
    return PottsToolkit._lower_execution_plan(
        scheduled,
        SequentialCPM(),
        CPUBackend(),
        Float32,
    )
end

@testset "full specialization-growth qualification" begin
    one = DescriptorSpecializationFixtures.lower_direct_model(1)
    many = DescriptorSpecializationFixtures.lower_direct_model(32)
    stress = DescriptorSpecializationFixtures.lower_direct_model(128)
    parameter_only = DescriptorSpecializationFixtures.lower_direct_model(
        32;
        weight_default = 7.0,
    )

    @test typeof(one) === typeof(many) ===
          typeof(stress) === typeof(parameter_only)
    reports = (
        one.reports.descriptors,
        many.reports.descriptors,
        stress.reports.descriptors,
        parameter_only.reports.descriptors,
    )
    @test getfield.(reports, :groups) == (1, 1, 1, 1)
    @test getfield.(reports, :occurrences) == (1, 32, 128, 32)
    @test many.reports.descriptors.group_splits ==
          stress.reports.descriptors.group_splits ==
          parameter_only.reports.descriptors.group_splits
    @test many.reports.descriptors.kernel_families ==
          stress.reports.descriptors.kernel_families ==
          parameter_only.reports.descriptors.kernel_families

    state_layouts = Tuple(
        CorePotts.CompilerSPI.StateLayout([
            state_schema(index) for index in 1:count
        ])
        for count in (1, 32, 1024)
    )
    states = map(
        CorePotts.CompilerSPI.allocate_auxiliary_state, state_layouts
    )
    handles = map(layout -> last(layout.entries).handle, state_layouts)
    @test allequal(typeof(layout) for layout in state_layouts)
    @test allequal(typeof(state) for state in states)
    @test allequal(typeof(handle) for handle in handles)
    @test allequal(state_block_typed_ir_size.(states, handles))

    external_programs = Tuple(
        compile_external_model(count) for count in (1, 32, 128)
    )
    @test allequal(typeof(program) for program in external_programs)
    @test allequal(
        typeof(program.core_program) for program in external_programs
    )
    external_reports = map(
        program -> program.reports.descriptors, external_programs
    )
    @test getfield.(external_reports, :occurrences) == (1, 32, 128)
end
