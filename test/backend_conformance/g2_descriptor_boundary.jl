using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts

include("../fixtures/NeutralExternalTerms.jl")

function _g2_external_site_model(count)
    @variables external_activity
    @parameters external_weight = 2.5
    endothelial = CellKind(:endothelial)
    extracellular = MediumKind(:extracellular)
    proposal = ProposalContext(:copy)
    activity = SiteState(
        external_activity;
        name = :external_activity,
        initial = 1.0,
        owner = endothelial,
        lifecycle = ClearOnOwnershipChange(),
    )
    terms = AbstractPottsStatement[
        NeutralExternalTerms.ExternalWeightedSiteTerm(
            Symbol(:external_site_, index),
            external_weight,
            external_activity,
            proposal,
        )
        for index in 1:count
    ]
    @named model = PottsSystem(
        statements = StatementSet((
            Lattice((4, 4)),
            endothelial,
            extracellular,
            activity,
            terms...,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [external_activity],
        parameters = [external_weight],
    )
    return model
end

"""
    run_g2_descriptor_boundary(device_array, device_zeros; backend_name)

Run the shared G2 descriptor/state/workspace launch qualification against one
backend adaptor. Vendor harnesses supply allocation only; the compiler,
fixture, assertions, launch, and scientific expected value remain shared.
"""
function run_g2_descriptor_boundary(
        device_array,
        device_zeros;
        backend_name::Symbol,
    )
    executable = compile(
        complete(
            _g2_external_site_model(32);
            registry = NeutralExternalTerms.registry(),
        );
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    plan = executable.core_program.descriptor_plan
    group = only(plan.groups)
    launch = CorePotts.adapt_descriptor_launch(device_array, group)

    state_values = zeros(Float32, 4, 4)
    state_values[2] = 7.0f0
    host_state = CorePotts.allocate_auxiliary_state(
        plan.state_layout, (state_values,)
    )
    host_workspaces = CorePotts.allocate_runtime_workspaces(
        plan.workspace_layout
    )
    device_state = CorePotts.adapt_auxiliary_state(
        device_array, plan.state_layout, host_state
    )
    device_workspaces = CorePotts.adapt_runtime_workspaces(
        device_array, plan.workspace_layout, host_workspaces
    )
    parameters = device_array(Float32[2.5])
    context = CorePotts.EvaluatorProbeContext(
        parameters,
        (target_site = Int32(2),),
        device_state,
        device_workspaces,
    )
    output = device_zeros(Float32, 32)
    backend = CorePotts.KernelAbstractions.get_backend(output)
    kernel = CorePotts.descriptor_group_probe_kernel!(backend)
    kernel(output, launch, context; ndrange = length(output))
    CorePotts.KernelAbstractions.synchronize(backend)

    @test Array(output) == fill(17.5f0, 32)
    @test length(launch.instances) == 32
    @test isconcretetype(eltype(launch.instances))
    @test isbits(first(Array(launch.instances)))
    @test CorePotts.handle_bank(only(launch.state_handles)) == 1
    @test CorePotts.handle_slot(only(launch.state_handles)) == 1
    @test CorePotts.handle_bank(only(launch.workspace_handles)) == 1
    @test CorePotts.handle_slot(only(launch.workspace_handles)) == 1

    state_buffer = CorePotts.state_block(
        device_state, only(launch.state_handles)
    ).values
    workspace_buffer = CorePotts.workspace_block(
        device_workspaces, only(launch.workspace_handles)
    ).values
    @test CorePotts.KernelAbstractions.get_backend(state_buffer) == backend
    @test CorePotts.KernelAbstractions.get_backend(workspace_buffer) == backend

    return (
        backend = backend_name,
        descriptors = length(launch.instances),
        descriptor_buffer = nameof(typeof(launch.instances)),
        state_buffer = nameof(typeof(state_buffer)),
        workspace_buffer = nameof(typeof(workspace_buffer)),
        value = first(Array(output)),
    )
end
