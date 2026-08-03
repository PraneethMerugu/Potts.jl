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

struct RelationshipCapacityOperation end
@inline (::RelationshipCapacityOperation)(schema) = schema.capacity

function relationship_typed_ir_size(storage)
    signature = Tuple{
        RelationshipCapacityOperation,
        typeof(storage),
        Int32,
        Tuple{},
    }
    typed = only(code_typed(
        CorePotts._call_relationship_slot, signature; optimize = true
    ))
    return ncodeunits(sprint(show, first(typed)))
end

function state_schema(index)
    return CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), Symbol(:state_, index)),
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
        CorePotts.state_block,
        Tuple{typeof(state), typeof(handle)};
        optimize = true,
    ))
    return ncodeunits(sprint(show, first(typed)))
end

function workspace_schema(index)
    return CorePotts.WorkspaceSchema(
        CorePotts.QualifiedResourceIdentity((), Symbol(:workspace_, index)),
        v"1.0.0",
        Float64,
        (2,),
        2,
        Array,
        :zero,
        :proposal,
        :read_write,
        :adapt_storage,
        :qualified,
        false,
    )
end

function workspace_block_typed_ir_size(workspaces, handle)
    typed = only(code_typed(
        CorePotts.workspace_block,
        Tuple{typeof(workspaces), typeof(handle)};
        optimize = true,
    ))
    return ncodeunits(sprint(show, first(typed)))
end

function compile_external_model(count::Integer)
    @variables external_activity
    @parameters external_weight = 2.0
    endothelial = CellKind(:external_endothelial)
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
    return compile(
        complete(external; registry = NeutralExternalTerms.registry());
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
end

@testset "full specialization-growth qualification" begin
    one = DescriptorSpecializationFixtures.compile_direct_model(1)
    many = DescriptorSpecializationFixtures.compile_direct_model(32)
    stress = DescriptorSpecializationFixtures.compile_direct_model(1024)
    parameter_only = DescriptorSpecializationFixtures.compile_direct_model(
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
    @test getfield.(reports, :occurrences) == (1, 32, 1024, 32)
    @test many.reports.descriptors.group_splits ==
          stress.reports.descriptors.group_splits ==
          parameter_only.reports.descriptors.group_splits
    @test many.reports.descriptors.kernel_families ==
          stress.reports.descriptors.kernel_families ==
          parameter_only.reports.descriptors.kernel_families

    schema = CorePotts.RelationshipStoreSchema(1, 1)
    relationship_storages = Tuple(
        CorePotts.RelationshipStorage(ntuple(_ -> schema, count))
        for count in (1, 32, 1024)
    )
    @test allequal(typeof(storage) for storage in relationship_storages)
    @test allequal(relationship_typed_ir_size.(relationship_storages))
    @test CorePotts._call_relationship_slot(
        RelationshipCapacityOperation(),
        last(relationship_storages),
        Int32(1024),
        (),
    ) == 1

    state_layouts = Tuple(
        CorePotts.StateLayout([state_schema(index) for index in 1:count])
        for count in (1, 32, 1024)
    )
    states = map(CorePotts.allocate_auxiliary_state, state_layouts)
    handles = map(layout -> last(layout.entries).handle, state_layouts)
    @test allequal(typeof(layout) for layout in state_layouts)
    @test allequal(typeof(state) for state in states)
    @test allequal(typeof(handle) for handle in handles)
    @test allequal(state_block_typed_ir_size.(states, handles))

    workspace_layouts = Tuple(
        CorePotts.WorkspaceLayout([
            workspace_schema(index) for index in 1:count
        ])
        for count in (1, 32, 1024)
    )
    workspaces = map(
        CorePotts.allocate_runtime_workspaces, workspace_layouts
    )
    workspace_handles = map(
        layout -> last(layout.entries).handle, workspace_layouts
    )
    @test allequal(typeof(layout) for layout in workspace_layouts)
    @test allequal(typeof(runtime) for runtime in workspaces)
    @test allequal(typeof(handle) for handle in workspace_handles)
    @test allequal(workspace_block_typed_ir_size.(
        workspaces, workspace_handles
    ))

    external_programs = Tuple(
        compile_external_model(count) for count in (1, 32, 1024)
    )
    @test allequal(typeof(program) for program in external_programs)
    @test allequal(
        typeof(program.core_program) for program in external_programs
    )
    external_reports = map(
        program -> program.reports.descriptors, external_programs
    )
    @test getfield.(external_reports, :occurrences) == (1, 32, 1024)
end
