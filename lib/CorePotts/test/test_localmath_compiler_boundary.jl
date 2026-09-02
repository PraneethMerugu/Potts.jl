using Test
import CorePotts
import KernelAbstractions
import LocalMath

function _compiler_color_schedule(checkerboard, color)
    schedules = ntuple(Int(checkerboard.color_count)) do candidate
        CorePotts._checkerboard_color_schedule(checkerboard, candidate)
    end
    combined = collect(zip(map(first, schedules)...))
    return combined, last(schedules[color])
end

struct UnboundedCompilerFootprint <: CorePotts.AbstractFootprint end
struct BlockViewStorageAdaptor end
CorePotts.Adapt.adapt_storage(
    ::BlockViewStorageAdaptor, storage::Vector) = @view storage[:]

@testset "Core state block views expose ordinary strided-array semantics" begin
    view = CorePotts.BlockView(zeros(Float32, 16), 3, (2, 3))
    @test size(view) == (2, 3)
    @test strides(view) == (1, 2)
    adapted = CorePotts.Adapt.adapt(BlockViewStorageAdaptor(), view)
    @test parent(adapted) isa SubArray
    @test adapted.offset == view.offset
    @test adapted.dimensions == view.dimensions
end

function _compiler_inventory_plan(
        footprint = CorePotts.OwnerFootprint();
        operation = CorePotts.ResourceOperation{:cell_volume}(),
        role = CorePotts.ProposalEnergyDriveRole(),
    )
    expression = CorePotts.OperationExpression(
        operation,
        CorePotts.ContextExpression(CorePotts.ContextOperation{:source_cell}()),
    )
    evaluator = CorePotts.StaticEvaluator(expression)
    access = CorePotts.ResourceAccess(
        (), (), footprint, CorePotts.EmptyFootprint(),
        CorePotts.NoWriteAccess())
    descriptor = CorePotts.ProposalDescriptor(
        evaluator, access,
        CorePotts.DescriptorSupport(true, true, true, true),
        (), (), role, 1)
    strategy = CorePotts.DescriptorKernelStrategy{
        typeof(descriptor), typeof(expression), typeof(access),
        typeof(descriptor.role), Val{:proposal}}()
    group = CorePotts.DescriptorGroup(
        CorePotts.DescriptorLaunch(
            strategy, [descriptor], (), ()),
        (family = :compiler_inventory,))
    return CorePotts.DescriptorExecutionPlan(
        (group,), CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]), (),
        Any[:compiler_inventory_source], 1,
        "compiler-inventory-plan-v1",
        CorePotts.HamiltonianDomainResources(1, 1))
end

function _literal_proposal_plan(values)
    descriptors = map(eachindex(values)) do index
        expression = CorePotts.LiteralExpression(Float64(values[index]))
        evaluator = CorePotts.StaticEvaluator(expression)
        access = CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess())
        CorePotts.ProposalDescriptor(
            evaluator, access,
            CorePotts.DescriptorSupport(true, true, true, true),
            (), (), CorePotts.ProposalEnergyDriveRole(), index)
    end
    exemplar = first(descriptors)
    strategy = CorePotts.DescriptorKernelStrategy{
        typeof(exemplar), typeof(exemplar.evaluator.expression),
        typeof(exemplar.access), typeof(exemplar.role), Val{:proposal}}()
    group = CorePotts.DescriptorGroup(
        CorePotts.DescriptorLaunch(strategy, descriptors, (), ()),
        (family = :literal_proposal,))
    return CorePotts.DescriptorExecutionPlan(
        (group,), CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]), (),
        Any[Symbol(:literal_, index) for index in eachindex(values)],
        length(values), "literal-proposal-plan-v1",
        CorePotts.HamiltonianDomainResources(1, 1))
end

function _context_proposal_plan()
    expression = CorePotts.OperationExpression(
        CorePotts.OrderedFold(+),
        CorePotts.ContextExpression(
            CorePotts.ContextOperation{:target_cell}()),
        CorePotts.ContextExpression(
            CorePotts.ContextOperation{:source_cell}()),
    )
    evaluator = CorePotts.StaticEvaluator(expression)
    access = CorePotts.ResourceAccess(
        (), (), CorePotts.OwnerFootprint(), CorePotts.EmptyFootprint(),
        CorePotts.NoWriteAccess())
    descriptor = CorePotts.ProposalDescriptor(
        evaluator, access,
        CorePotts.DescriptorSupport(true, true, true, true),
        (), (), CorePotts.ProposalEnergyDriveRole(), 1)
    strategy = CorePotts.DescriptorKernelStrategy{
        typeof(descriptor), typeof(expression), typeof(access),
        typeof(descriptor.role), Val{:proposal}}()
    group = CorePotts.DescriptorGroup(
        CorePotts.DescriptorLaunch(strategy, [descriptor], (), ()),
        (family = :context_proposal,))
    return CorePotts.DescriptorExecutionPlan(
        (group,), CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]), (),
        Any[:context_proposal], 1, "context-proposal-plan-v1",
        CorePotts.HamiltonianDomainResources(1, 1))
end

function _cell_volume_hamiltonian_plan()
    anchor = CorePotts.ContextExpression(
        CorePotts.ContextOperation{:energy_anchor_cell}())
    volume = CorePotts.OperationExpression(
        CorePotts.ResourceOperation{:cell_volume}(), anchor)
    expression = CorePotts.OperationExpression(
        ^, volume, CorePotts.LiteralExpression(2))
    evaluator = CorePotts.StaticEvaluator(expression)
    access = CorePotts.ResourceAccess(
        (), (), CorePotts.OwnerFootprint(), CorePotts.EmptyFootprint(),
        CorePotts.NoWriteAccess())
    role = CorePotts.HamiltonianRole(
        CorePotts.CellEnergyDomainPlan(Int16(1)),
        CorePotts.SourceTargetCellsAffectedPlan(Int32(2)))
    descriptor = CorePotts.ProposalDescriptor(
        evaluator, access,
        CorePotts.DescriptorSupport(true, true, true, true),
        (), (), role, 1)
    strategy = CorePotts.DescriptorKernelStrategy{
        typeof(descriptor), typeof(expression), typeof(access),
        typeof(role), Val{:proposal}}()
    group = CorePotts.DescriptorGroup(
        CorePotts.DescriptorLaunch(strategy, [descriptor], (), ()),
        (family = :cell_volume_hamiltonian,))
    return CorePotts.DescriptorExecutionPlan(
        (group,), CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]), (),
        Any[:cell_volume_hamiltonian], 1,
        "cell-volume-hamiltonian-plan-v1",
        CorePotts.HamiltonianDomainResources(1, 1))
end

function _contact_hamiltonian_plan()
    anchor = CorePotts.ContextExpression(
        CorePotts.ContextOperation{:energy_anchor_contact}())
    expression = CorePotts.OperationExpression(
        CorePotts.OrderedFold(+),
        CorePotts.OperationExpression(
            CorePotts.ResourceOperation{:contact_owner_a}(), anchor),
        CorePotts.OperationExpression(
            CorePotts.ResourceOperation{:contact_owner_b}(), anchor),
    )
    evaluator = CorePotts.StaticEvaluator(expression)
    access = CorePotts.ResourceAccess(
        (), (), CorePotts.ContactFootprint(), CorePotts.EmptyFootprint(),
        CorePotts.NoWriteAccess())
    role = CorePotts.HamiltonianRole(
        CorePotts.ContactEnergyDomainPlan(Int32(1)),
        CorePotts.IncidentContactsAffectedPlan(Int32(2)))
    descriptor = CorePotts.ProposalDescriptor(
        evaluator, access,
        CorePotts.DescriptorSupport(true, true, true, true),
        (), (), role, 1)
    strategy = CorePotts.DescriptorKernelStrategy{
        typeof(descriptor), typeof(expression), typeof(access),
        typeof(role), Val{:proposal}}()
    group = CorePotts.DescriptorGroup(
        CorePotts.DescriptorLaunch(strategy, [descriptor], (), ()),
        (family = :contact_hamiltonian,))
    resources = CorePotts.HamiltonianDomainResources(
        reshape(Int8[-1, 1], 1, 2), Int32[1], Int32[2], Int32[0])
    return CorePotts.DescriptorExecutionPlan(
        (group,), CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]), (),
        Any[:contact_hamiltonian], 1,
        "contact-hamiltonian-plan-v1", resources)
end

function _compiler_test_gathered_context(;
    source = CartesianIndex(2),
    target = CartesianIndex(1),
    target_linear = Int32(1),
    old_owner = Int32(1),
    new_owner = Int32(2),
    old_kind = Int16(1),
    new_kind = Int16(2),
    volumes = (Int32(4), Int32(9)),
    contact_sites = (),
    contact_owners = (),
    contact_kinds = (),
    reverse_contact_sites = (),
    reverse_contact_owners = (),
    reverse_contact_kinds = (),
    contact_ranges = ((), ()),
)
    return CorePotts._gathered_proposal_context(
        source, target, target_linear,
        old_owner, new_owner, old_kind, new_kind,
        volumes, Int32(1), Int64(1), Int32(1), UInt64(1), 0.0,
        (), (),
        contact_sites, contact_owners, contact_kinds,
        reverse_contact_sites, reverse_contact_owners, reverse_contact_kinds,
        contact_ranges,
        (), (), (), (), nothing, (),
    )
end

_compiler_test_tracker_plan() = CorePotts.TrackerExecutionPlan(
    (CorePotts.OwnershipCountTracker(),),
    "localmath-compiler-boundary-tracker",
)

@testset "ordered scalar execution specializes the binary case" begin
    binary = (
        CorePotts._ExecutableLiteral(2.0),
        CorePotts._ExecutableLiteral(3.0),
    )
    longer = (
        CorePotts._ExecutableLiteral(10.0),
        CorePotts._ExecutableLiteral(3.0),
        CorePotts._ExecutableLiteral(2.0),
    )
    @test CorePotts._execute_proposal_ordered(*, binary, nothing) == 6.0
    @test CorePotts._execute_proposal_ordered(-, longer, nothing) == 5.0
end

@testset "Core compiler emits executable scalar terms in source order" begin
    terms = CorePotts._compile_proposal_terms(
        _literal_proposal_plan((1.0e16, -1.0e16, 1.0)))
    @test isbitstype(typeof(terms))
    @test all(term -> !(term.evaluator isa CorePotts.AbstractStaticExpression),
        terms)
    context = (
        source = CartesianIndex(2), target = CartesianIndex(1),
        old_owner = Int32(1), new_owner = Int32(2),
        old_kind = Int16(1), new_kind = Int16(2),
    )
    evaluation = CorePotts._fold_executable_proposal_terms(
        terms, context, Float64)
    @test evaluation.drive_energy == 1.0

    gathered_terms = CorePotts._compile_proposal_terms(
        _compiler_inventory_plan())
    gathered_context = _compiler_test_gathered_context()
    gathered = CorePotts._fold_executable_proposal_terms(
        gathered_terms, gathered_context, Float64)
    @test gathered.drive_energy == 9.0
    hamiltonian_terms = CorePotts._compile_proposal_terms(
        _compiler_inventory_plan(; role = CorePotts.HamiltonianRole()))
    hamiltonian = CorePotts._fold_executable_proposal_terms(
        hamiltonian_terms, gathered_context, Float64)
    @test hamiltonian.delta_h == 1.0

    cell_terms = CorePotts._compile_proposal_terms(
        _cell_volume_hamiltonian_plan())
    cell_context = _compiler_test_gathered_context(
        old_kind = Int16(1), new_kind = Int16(1),
        volumes = (Int32(2), Int32(2)))
    cell_evaluation = CorePotts._fold_executable_proposal_terms(
        cell_terms, cell_context, Float64)
    @test cell_evaluation.delta_h == 2.0

    contact_terms = CorePotts._compile_proposal_terms(
        _contact_hamiltonian_plan())
    contact_context = _compiler_test_gathered_context(
        source = CartesianIndex(3), target = CartesianIndex(2),
        target_linear = Int32(2), volumes = (Int32(2), Int32(2)),
        contact_sites = (Int32(1), Int32(3)),
        contact_owners = (Int32(1), Int32(2)),
        contact_kinds = (Int16(1), Int16(2)),
        contact_ranges = ((Int32(1),), (Int32(2),)))
    contact_evaluation = CorePotts._fold_executable_proposal_terms(
        contact_terms, contact_context, Float64)
    @test contact_evaluation.delta_h == 2.0

    error = try
        CorePotts._compile_proposal_terms(_compiler_inventory_plan(;
            operation = CorePotts.ResourceOperation{:cell_surface}()))
        nothing
    catch caught
        caught
    end
    @test error isa ArgumentError
    @test occursin("compiler_inventory_source", sprint(showerror, error))
    @test occursin("bounded gathered lowering", sprint(showerror, error))
end

@testset "Core compiler inventories contextual operations in source order" begin
    inventory = CorePotts._proposal_gather_inventory(
        _compiler_inventory_plan())
    @test inventory.source_count == Int32(1)
    @test map(record -> record.kind, inventory.records) ==
        (:operation, :context)
    @test map(record -> record.identity, inventory.records) ==
        (:cell_volume, :source_cell)
    @test map(record -> record.path, inventory.records) ==
        ((), (Int32(1),))
    @test all(record -> record.source == :compiler_inventory_source,
        inventory.records)

    error = try
        CorePotts._proposal_gather_inventory(
            _compiler_inventory_plan(UnboundedCompilerFootprint()))
        nothing
    catch caught
        caught
    end
    @test error isa ArgumentError
    @test occursin("compiler_inventory_source", sprint(showerror, error))
    @test occursin("unsupported or unbounded footprint", sprint(showerror, error))
end

@testset "Core compiler materializes checkerboard geometry through LocalMath" begin
    checkerboard = CorePotts.CheckerboardPlan(
        (5,), (true,), reshape(Int16[1], 1, 1))
    proposal_offsets = reshape(Int8[-1, 1], 1, 2)
    declaration = CorePotts._checkerboard_geometry_declaration(
        checkerboard, proposal_offsets,
        UInt64(0x1234), UInt32(2), UInt32(3))
    backend = KernelAbstractions.CPU()

    function prepare_color(color)
        schedule, batch_size = _compiler_color_schedule(
            checkerboard, color)
        sites = fill((Int32(-1), Int32(-1)), length(schedule))
        semantic = fill(Int32(-1), length(schedule))
        priority = fill(UInt32(0), length(schedule))
        prepared = LocalMath.prepare(
            declaration.law,
            declaration.target_options => schedule,
            declaration.target => zeros(Int32, length(schedule)),
            declaration.sites => sites,
            declaration.semantic => semantic,
            declaration.priority => priority;
            backend)
        return (; prepared, schedule, sites, semantic, priority,
            batch_size)
    end

    first = prepare_color(1)
    second = prepare_color(2)
    @test typeof(first.prepared) === typeof(second.prepared)
    @test LocalMath.inspect(first.prepared).stages[1].planning.phases ==
        ((kind = :direct_identity_unique, count = 1),)
    for (color, values) in ((Int32(1), first), (Int32(2), second))
        wait(LocalMath.execute!(values.prepared; parameters = (
            mcs = Int64(1), color,
            attempt_round = Int32(1), batch_size = values.batch_size)))
        for item in Int32(1):values.batch_size
            target = values.schedule[item][color]
            semantic = target
            address = CorePotts._program_address(
                CorePotts.ProposalDirectionStream, 1, 2, semantic;
                subround = color)
            direction = Int(CorePotts.bounded_uint(
                CorePotts.Philox4x32x10V2(),
                declaration.evaluator.trajectory_seed,
                address, UInt32(2))) + 1
            expected_source = CorePotts._checkerboard_neighbor_linear(
                checkerboard.shape, checkerboard.periodic, target,
                declaration.evaluator.offsets[direction])
            priority_address = CorePotts._program_address(
                CorePotts.CheckerboardPriorityStream, 1, 4, semantic;
                subround = color)
            expected_priority = CorePotts._rng_word(
                CorePotts.Philox4x32x10V2(),
                declaration.evaluator.trajectory_seed,
                priority_address)
            @test values.sites[item] == (target, expected_source)
            @test values.semantic[item] == semantic
            @test values.priority[item] == expected_priority
        end
        inactive = (Int(values.batch_size) + 1):length(values.sites)
        @test all(==((Int32(-1), Int32(-1))), values.sites[inactive])
        @test all(==(Int32(-1)), values.semantic[inactive])
        @test all(iszero, values.priority[inactive])
    end
end

@testset "Core compiler materializes owner keys through IndexRelation" begin
    checkerboard = CorePotts.CheckerboardPlan(
        (4,), (false,), reshape(Int16[1], 1, 1))
    declaration = CorePotts._checkerboard_proposal_topology_declaration(
        checkerboard, reshape(Int8[-1], 1, 1),
        UInt64(0x44), UInt32(0), UInt32(0))
    schedule, batch_size = _compiler_color_schedule(
        checkerboard, 1)
    sites = fill((Int32(0), Int32(0)), length(schedule))
    semantic = zeros(Int32, length(schedule))
    raw_priority = zeros(UInt32, length(schedule))
    owners = fill((Int32(0), Int32(0)), length(schedule))
    actionable = fill(false, length(schedule))
    ownership = Int32[1, 2, 2, 3]
    prepared = LocalMath.prepare(
        declaration.law,
        declaration.target_options => schedule,
        declaration.target => zeros(Int32, length(schedule)),
        declaration.sites => sites,
        declaration.semantic => semantic,
        declaration.priority => raw_priority,
        declaration.ownership => ownership,
        declaration.owners => owners,
        declaration.actionable => actionable;
        backend = KernelAbstractions.CPU())
    wait(LocalMath.execute!(prepared; parameters = (
        mcs = Int64(1), color = Int32(1), attempt_round = Int32(1),
        batch_size)))
    for item in Int32(1):batch_size
        target, source_site = sites[item]
        expected_old = ownership[target]
        expected_new = source_site > 0 ? ownership[source_site] : expected_old
        expected_actionable = source_site > 0 && expected_old != expected_new
        @test owners[item] == (expected_old, expected_new)
        @test actionable[item] == expected_actionable
        @test !expected_actionable || !iszero(raw_priority[item])
        @test expected_actionable || iszero(raw_priority[item])
    end
end

@testset "Core executable terms run inside the LocalMath law" begin
    checkerboard = CorePotts.CheckerboardPlan(
        (4,), (false,), reshape(Int16[1], 1, 1))
    declaration = CorePotts._checkerboard_scientific_declaration(
        checkerboard, reshape(Int8[-1], 1, 1),
        UInt64(0x55), UInt32(0), UInt32(0),
        _context_proposal_plan(), CorePotts.StageExecutionPlan(),
        _compiler_test_tracker_plan(), (),
        CorePotts.RelationshipStorage(()),
        CorePotts.RelationshipStorage(()), 0, 3, Float64)
    schedule, batch_size = _compiler_color_schedule(
        checkerboard, 1)
    count = length(schedule)
    storage = (
        sites = fill((Int32(0), Int32(0)), count),
        semantic = zeros(Int32, count),
        raw_priority = zeros(UInt32, count),
        owners = fill((Int32(0), Int32(0)), count),
        actionable = fill(false, count),
        kinds = fill((Int16(0), Int16(0)), count),
        volumes = fill((Int32(0), Int32(0)), count),
        delta_h = zeros(Float64, count),
        drive_energy = zeros(Float64, count),
        drive_log_bias = zeros(Float64, count),
        kinetic_modifier = zeros(Float64, count),
        constraints_allowed = fill(true, count),
    )
    ownership = Int32[1, 2, 2, 3]
    cell_kinds = Int16[1, 2, 3]
    cell_volumes = Int32[1, 2, 1]
    prepared = LocalMath.prepare(
        declaration.law,
        declaration.target_options => schedule,
        declaration.target => zeros(Int32, length(schedule)),
        declaration.sites => storage.sites,
        declaration.semantic => storage.semantic,
        declaration.priority => storage.raw_priority,
        declaration.ownership => ownership,
        declaration.owners => storage.owners,
        declaration.actionable => storage.actionable,
        declaration.cell_kinds => cell_kinds,
        declaration.cell_volumes => cell_volumes,
        declaration.kinds => storage.kinds,
        declaration.volumes => storage.volumes,
        declaration.evaluation.delta_h => storage.delta_h,
        declaration.evaluation.drive_energy => storage.drive_energy,
        declaration.evaluation.drive_log_bias => storage.drive_log_bias,
        declaration.evaluation.kinetic_modifier => storage.kinetic_modifier,
        declaration.evaluation.constraints_allowed =>
            storage.constraints_allowed;
        backend = KernelAbstractions.CPU())
    wait(LocalMath.execute!(prepared; parameters = (
        mcs = Int64(1), color = Int32(1), attempt_round = Int32(1),
        batch_size)))
    @test isbitstype(typeof(declaration.scientific_evaluator))
    for item in Int32(1):batch_size
        old_owner, new_owner = storage.owners[item]
        expected = storage.actionable[item] ? old_owner + new_owner : 0
        @test storage.drive_energy[item] == expected
        @test storage.delta_h[item] == 0
        @test storage.drive_log_bias[item] == 0
        @test storage.kinetic_modifier[item] == 0
        @test storage.constraints_allowed[item]
        @test storage.kinds[item] == (
            old_owner > 0 ? cell_kinds[old_owner] : Int16(0),
            new_owner > 0 ? cell_kinds[new_owner] : Int16(0),
        )
        @test storage.volumes[item] == (
            old_owner > 0 ? cell_volumes[old_owner] : Int32(0),
            new_owner > 0 ? cell_volumes[new_owner] : Int32(0),
        )
    end
end

@testset "Core acceptance lowers to typed LocalMath disposition ports" begin
    checkerboard = CorePotts.CheckerboardPlan(
        (4,), (false,), reshape(Int16[1], 1, 1))
    scientific = CorePotts._checkerboard_scientific_declaration(
        checkerboard, reshape(Int8[-1], 1, 1),
        UInt64(0x55), UInt32(0), UInt32(0),
        _context_proposal_plan(), CorePotts.StageExecutionPlan(),
        _compiler_test_tracker_plan(), (),
        CorePotts.RelationshipStorage(()),
        CorePotts.RelationshipStorage(()), 0, 3, Float32)
    declaration = CorePotts._checkerboard_acceptance_declaration(
        scientific, CorePotts.CompiledScalar(0.0f0),
        (false, false, false), (true, true, true),
        UInt64(0x55), UInt32(0), UInt32(0))
    schedule, batch_size = _compiler_color_schedule(
        checkerboard, 1)
    count = length(schedule)
    ownership = Int32[1, 2, 2, 3]
    cell_kinds = Int16[1, 2, 3]
    cell_volumes = Int32[2, 2, 1]
    storage = (
        sites = fill((Int32(0), Int32(0)), count),
        semantic = zeros(Int32, count),
        raw_priority = zeros(UInt32, count),
        owners = fill((Int32(0), Int32(0)), count),
        actionable = fill(false, count),
        kinds = fill((Int16(0), Int16(0)), count),
        volumes = fill((Int32(0), Int32(0)), count),
        delta_h = zeros(Float32, count),
        drive_energy = zeros(Float32, count),
        drive_log_bias = zeros(Float32, count),
        kinetic_modifier = zeros(Float32, count),
        constraints_allowed = fill(true, count),
        disposition = zeros(UInt8, count),
        failure_code = zeros(UInt8, count),
        failure_identity = zeros(Int32, count),
    )
    prepared = LocalMath.prepare(
        declaration.law,
        declaration.target_options => schedule,
        declaration.target => zeros(Int32, length(schedule)),
        declaration.sites => storage.sites,
        declaration.semantic => storage.semantic,
        declaration.priority => storage.raw_priority,
        declaration.ownership => ownership,
        declaration.owners => storage.owners,
        declaration.actionable => storage.actionable,
        declaration.cell_kinds => cell_kinds,
        declaration.cell_volumes => cell_volumes,
        declaration.kinds => storage.kinds,
        declaration.volumes => storage.volumes,
        declaration.evaluation.delta_h => storage.delta_h,
        declaration.evaluation.drive_energy => storage.drive_energy,
        declaration.evaluation.drive_log_bias => storage.drive_log_bias,
        declaration.evaluation.kinetic_modifier => storage.kinetic_modifier,
        declaration.evaluation.constraints_allowed =>
            storage.constraints_allowed,
        declaration.disposition => storage.disposition,
        declaration.failure_code => storage.failure_code,
        declaration.failure_identity => storage.failure_identity;
        backend = KernelAbstractions.CPU())
    inspected = LocalMath.inspect(prepared).stages[1:5]
    @test all(read.mode === :required for stage in inspected
        for read in stage.reads)
    @test inspected[2].reads[1].role === :ownership
    @test inspected[3].reads[1].role === :cell_kinds
    wait(LocalMath.execute!(prepared; parameters = (
        mcs = Int64(1), color = Int32(1), attempt_round = Int32(1),
        batch_size)))
    @test isbitstype(typeof(declaration.acceptance_evaluator))
    for item in Int32(1):batch_size
        expected = storage.actionable[item] ?
            CorePotts._PROGRAM_CHECKERBOARD_ENERGY :
            CorePotts._PROGRAM_CHECKERBOARD_NULL
        @test storage.disposition[item] == expected
        @test storage.failure_code[item] ==
            UInt8(CorePotts.ProposalAcceptanceReady)
        @test storage.failure_identity[item] == 0
    end
end

@testset "Core compiler composes acceptance and mutual-maxima selection" begin
    checkerboard = CorePotts.CheckerboardPlan(
        (4,), (false,), reshape(Int16[1], 1, 1))
    scientific = CorePotts._checkerboard_scientific_declaration(
        checkerboard, reshape(Int8[-1], 1, 1),
        UInt64(0x55), UInt32(0), UInt32(0),
        _context_proposal_plan(), CorePotts.StageExecutionPlan(),
        _compiler_test_tracker_plan(), (),
        CorePotts.RelationshipStorage(()),
        CorePotts.RelationshipStorage(()), 0, 3, Float32)
    accepted = CorePotts._checkerboard_acceptance_declaration(
        scientific, CorePotts.CompiledScalar(0.0f0),
        (false, false, false), (true, true, true),
        UInt64(0x55), UInt32(0), UInt32(0))
    tracker_state = CorePotts.TrackerState((Int32[2, 2, 1],))
    declaration = CorePotts._checkerboard_color_declaration(
        accepted, 3, CorePotts.RelationshipStorage(()),
        _compiler_test_tracker_plan(), tracker_state)
    schedule, batch_size = _compiler_color_schedule(
        checkerboard, 1)
    count = length(schedule)
    ownership = Int32[1, 2, 2, 3]
    cell_kinds = Int16[1, 2, 3]
    cell_volumes = Int32[2, 2, 1]
    storage = (
        sites = fill((Int32(0), Int32(0)), count),
        semantic = zeros(Int32, count),
        raw_priority = zeros(UInt32, count),
        owners = fill((Int32(0), Int32(0)), count),
        actionable = fill(false, count),
        kinds = fill((Int16(0), Int16(0)), count),
        volumes = fill((Int32(0), Int32(0)), count),
        delta_h = zeros(Float32, count),
        drive_energy = zeros(Float32, count),
        drive_log_bias = zeros(Float32, count),
        kinetic_modifier = zeros(Float32, count),
        constraints_allowed = fill(true, count),
        disposition = zeros(UInt8, count),
        failure_code = zeros(UInt8, count),
        failure_identity = zeros(Int32, count),
        winners = zeros(Int32, 3),
        report = zeros(UInt64, 5),
        initial_gate = fill(false, 1),
        refreshed_gate = fill(false, 1),
        terminal_gate = fill(false, 1),
    )
    status = CorePotts.StructArrays.StructArray(
        CorePotts.ProgramStatus[CorePotts.ProgramStatus()])
    gate = CorePotts._CheckerboardNoLifecycleOpenGate(status)
    tracker_bindings = CorePotts._checkerboard_tracker_group_bindings(
        declaration.tracker_groups, (; trackers = tracker_state))
    prepared = LocalMath.prepare(
        declaration.law,
        declaration.target_options => schedule,
        declaration.target => zeros(Int32, length(schedule)),
        declaration.sites => storage.sites,
        declaration.semantic => storage.semantic,
        declaration.priority => storage.raw_priority,
        declaration.ownership => ownership,
        declaration.owners => storage.owners,
        declaration.actionable => storage.actionable,
        declaration.cell_kinds => cell_kinds,
        declaration.cell_volumes => cell_volumes,
        declaration.kinds => storage.kinds,
        declaration.volumes => storage.volumes,
        declaration.evaluation.delta_h => storage.delta_h,
        declaration.evaluation.drive_energy => storage.drive_energy,
        declaration.evaluation.drive_log_bias => storage.drive_log_bias,
        declaration.evaluation.kinetic_modifier => storage.kinetic_modifier,
        declaration.evaluation.constraints_allowed =>
            storage.constraints_allowed,
        declaration.disposition => storage.disposition,
        declaration.failure_code => storage.failure_code,
        declaration.failure_identity => storage.failure_identity,
        declaration.winners => storage.winners,
        declaration.status => status,
        declaration.report => storage.report,
        declaration.report_scratch => LocalMath.Allocate(zero(UInt64)),
        declaration.ownership_scratch => LocalMath.Allocate(zero(Int32)),
        tracker_bindings...,
        declaration.external_gate => gate,
        declaration.initial_gate => storage.initial_gate,
        declaration.refreshed_gate => storage.refreshed_gate,
        declaration.terminal_gate => storage.terminal_gate;
        backend = KernelAbstractions.CPU())
    wait(LocalMath.execute!(prepared; parameters = (
        mcs = Int64(1), color = Int32(1), attempt_round = Int32(1),
        batch_size)))
    @test status[1].code ===
        CorePotts.ProgramStatusSuccess
    @test sum(storage.report) == UInt64(batch_size)
    @test all(value -> value in (
        CorePotts._PROGRAM_CHECKERBOARD_NULL,
        CorePotts._PROGRAM_CHECKERBOARD_CONFLICT,
        CorePotts._PROGRAM_CHECKERBOARD_ENERGY,
        CorePotts._PROGRAM_CHECKERBOARD_ACCEPTED,
    ), @view(storage.disposition[1:Int(batch_size)]))
end

struct CoreLocalMathSite end
struct CoreLocalProposalEvaluator{C}
    context::C
end
@inline _core_local_context(
    ::CorePotts.ContextOperation{:source_site}, item::Int32) = item
@inline function (evaluator::CoreLocalProposalEvaluator)(
        item::Int32, reads, parameters)
    _core_local_context(evaluator.context, item)
    label = something(getfield(reads, 1)[1].value)
    volume = something(getfield(reads, 2)[1].value)
    # Deliberately ordered, non-associative Hamiltonian terms.
    energy = (label == Int32(1) ? 1.0e16 : 0.0)
    energy += -1.0e16
    energy += Float64(volume)
    return (proposal = LocalMath.UniqueValue(energy),)
end

function _test_local_proposal_work(source, label, volume, output, read_relation)
    identity = LocalMath.IdentityRelation(source)
    publication = LocalMath.Publication((
        LocalMath.FieldPublication(output, identity,
            LocalMath.PublicationValue(:proposal)),),
        LocalMath.Unique(Float64),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :proposal_resolution))
    stage = LocalMath.Stage(source, (
        label = LocalMath.Access(label, read_relation; required = true),
        volume = LocalMath.Access(volume, read_relation; required = true),
    ), (publication,), LocalMath.Evaluator(CoreLocalProposalEvaluator(
        CorePotts.ContextOperation{:source_site}())),
        LocalMath.Control(),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :core_resource_access_lowering))
    return LocalMath.LocalLaw(stage), identity
end

struct CoreGeometryEvaluator{C}
    source::C
end
@inline function (evaluator::CoreGeometryEvaluator)(
        item::Int32, reads, parameters)
    source = _core_local_context(evaluator.source, item)
    color = getfield(parameters, 1)
    owners = source == Int32(1) ? (Int32(1), Int32(2)) :
        source == Int32(2) ? (Int32(1), Int32(0)) :
        (Int32(2), Int32(0))
    priority = (source == Int32(1) ? Int32(3) :
        source == Int32(2) ? Int32(5) : Int32(4)) + color
    return (
        target = LocalMath.UniqueValue(source),
        owners = LocalMath.UniqueValue(owners),
        priority = LocalMath.UniqueValue(priority),
    )
end

struct CoreGatherEvaluator end
@inline function (::CoreGatherEvaluator)(item::Int32, reads, parameters)
    sample = getfield(reads, 1)[1]
    return (score = LocalMath.UniqueValue(
        something(sample.value, Int32(0))),)
end

struct CoreOwnerResolveEvaluator end
@inline function (::CoreOwnerResolveEvaluator)(item::Int32, reads, parameters)
    priority = something(getfield(reads, 1)[1].value)
    claim = LocalMath.ResolutionValue(priority, item, item)
    return (claim = (claim, claim),)
end

struct CoreConjunctionEvaluator end
@inline function (::CoreConjunctionEvaluator)(item::Int32, reads, parameters)
    winners = getfield(reads, 1)
    accepted = true
    participates = false
    for lane in Int32(1):Int32(length(winners))
        sample = winners[lane]
        if sample.present
            participates = true
            accepted &= sample.value == item
        end
    end
    return (accepted = LocalMath.ConditionalUniqueValue(
        item, participates && accepted),)
end

function _core_boundary_publication(field, relation, port, law)
    return LocalMath.Publication((LocalMath.FieldPublication(
        field, relation, LocalMath.PublicationValue(port)),), law)
end

function _core_compiler_boundary_law()
    proposals = LocalMath.Space(CoreLocalMathSite, 3)
    owners_space = LocalMath.Space(CoreLocalMathSite, 2)
    signal = LocalMath.Field(proposals, Int32)
    target = LocalMath.Field(proposals, Int32)
    owners = LocalMath.Field(proposals, NTuple{2,Int32})
    priority = LocalMath.Field(proposals, Int32)
    score = LocalMath.Field(proposals, Int32)
    winners = LocalMath.Field(owners_space, Int32)
    accepted = LocalMath.Field(proposals, Int32)
    proposal_identity = LocalMath.IdentityRelation(proposals)
    target_relation = LocalMath.IndexRelation(target => proposals;
        optional = true)
    owner_relation = LocalMath.IndexRelation(owners => owners_space;
        optional = true)
    color = LocalMath.Parameter(:color, Int32)

    geometry = LocalMath.Stage(proposals, NamedTuple(), (
        _core_boundary_publication(target, proposal_identity, :target,
            LocalMath.Unique(Int32)),
        _core_boundary_publication(owners, proposal_identity, :owners,
            LocalMath.Unique(NTuple{2,Int32})),
        _core_boundary_publication(priority, proposal_identity, :priority,
            LocalMath.Unique(Int32)),
    ), LocalMath.Evaluator(CoreGeometryEvaluator(
        CorePotts.ContextOperation{:source_site}()), (color,)),
        LocalMath.Control(),
        LocalMath.SourceOrigin(:core_compiler_boundary, 1))
    gather = LocalMath.Stage(proposals,
        (signal = LocalMath.Access(signal, target_relation),),
        (_core_boundary_publication(score, proposal_identity, :score,
            LocalMath.Unique(Int32)),),
        LocalMath.Evaluator(CoreGatherEvaluator()), LocalMath.Control(),
        LocalMath.SourceOrigin(:core_compiler_boundary, 2))
    resolve = LocalMath.Stage(proposals,
        (priority = LocalMath.Access(priority, proposal_identity;
            required = true),),
        (_core_boundary_publication(winners, owner_relation, :claim,
            LocalMath.Resolve(Int32, Int32; maximum = 2,
                direction = LocalMath.ArgMax(),
                tie = LocalMath.TieMin{Int32}(),
                lower = typemin(Int32), upper = typemax(Int32),
                onempty = LocalMath.FillEmpty(Int32(0)))),),
        LocalMath.Evaluator(CoreOwnerResolveEvaluator()), LocalMath.Control(),
        LocalMath.SourceOrigin(:core_compiler_boundary, 3))
    conjunction = LocalMath.Stage(proposals,
        (winners = LocalMath.Access(winners, owner_relation),),
        (_core_boundary_publication(accepted, proposal_identity, :accepted,
            LocalMath.Unique(Int32; coverage = LocalMath.PartialCoverage(),
                onempty = LocalMath.FillEmpty(Int32(0)))),),
        LocalMath.Evaluator(CoreConjunctionEvaluator()), LocalMath.Control(),
        LocalMath.SourceOrigin(:core_compiler_boundary, 4))
    law = LocalMath.sequence(
        LocalMath.LocalLaw(geometry;
            parameters = LocalMath.ParameterSchema(color)),
        LocalMath.LocalLaw(gather), LocalMath.LocalLaw(resolve),
        LocalMath.LocalLaw(conjunction))
    return (; law, signal, target, owners, priority, score, winners, accepted)
end

@testset "Core-shaped compiler boundary reuses one LocalMath schema" begin
    model = _core_compiler_boundary_law()
    backend = KernelAbstractions.CPU()
    function prepared_bank(signal_values)
        storage = (
            signal = copy(signal_values),
            target = zeros(Int32, 3),
            owners = fill((Int32(0), Int32(0)), 3),
            priority = zeros(Int32, 3),
            score = zeros(Int32, 3),
            winners = zeros(Int32, 2),
            accepted = fill(Int32(-1), 3),
        )
        prepared = LocalMath.prepare(model.law,
            model.signal => storage.signal,
            model.target => storage.target,
            model.owners => storage.owners,
            model.priority => storage.priority,
            model.score => storage.score,
            model.winners => storage.winners,
            model.accepted => storage.accepted;
            backend)
        return prepared, storage
    end
    first, first_storage = prepared_bank(Int32[10, 20, 30])
    second, second_storage = prepared_bank(Int32[30, 20, 10])
    @test typeof(first) === typeof(second)
    report = LocalMath.inspect(first)
    @test map(stage -> map(read -> read.mode, stage.reads),
        report.stages)[[2, 4]] == ((:required,), (:required,))
    @test report.stages[2].reads[1].role === :signal
    @test report.stages[4].reads[1].role === :winners
    wait(LocalMath.execute!(first; parameters = (color = Int32(0),)))
    wait(LocalMath.execute!(second; parameters = (color = Int32(1),)))
    @test first_storage.target == second_storage.target == Int32[1, 2, 3]
    @test first_storage.accepted == second_storage.accepted == Int32[0, 2, 3]
end

@testset "Core proposal semantics fit the typed LocalMath waist" begin
    source = LocalMath.Space(CoreLocalMathSite, 2)
    label = LocalMath.Field(source, Int32)
    volume = LocalMath.Field(source, Int32)
    output = LocalMath.Field(source, Float64)
    packed = LocalMath.PackedRelation(
        source => source; degree_bound = 1, capacity = 2)
    work, identity = _test_local_proposal_work(
        source, label, volume, output, packed)
    label_storage = Int32[1, 2]
    volume_storage = Int32[1, 3]
    output_storage = zeros(Float64, 2)
    generations = UInt64[7]
    statuses = Int32[0]
    validated_generations = UInt64[0]
    packed_storage = (active = Bool[true, true],
        endpoints = reshape(Int32[1, 2], 1, 2),
        offsets = Int32[1], counts = Int32[2])
    prepared = LocalMath.prepare(work,
        label => label_storage,
        volume => volume_storage,
        output => output_storage,
        packed => LocalMath.MutableRelationStorage(packed_storage;
            generation = generations,
            status = statuses,
            validated_generations);
        backend = KernelAbstractions.CPU())
    wait(LocalMath.execute!(prepared))
    @test output_storage == Float64[1, -1.0e16 + 3]
    @test map(item -> begin
        energy = item == 1 ? 1.0e16 : 0.0
        energy += -1.0e16
        energy += volume_storage[item]
        energy
    end, eachindex(output_storage)) == output_storage
    @test validated_generations == generations

    addresses = map(Int32(1):Int32(2)) do site
        CorePotts.RNGAddress(; stream = CorePotts.AcceptanceStream,
            mcs = 4, subround = 1, operation = 2,
            entity_kind = CorePotts.SiteEntity, entity = site,
            generation = 7, draw = 0)
    end
    @test addresses[1].entity == UInt32(1)
    @test CorePotts.uniform_open01(Float32, CorePotts.Philox4x32x10V2(),
        UInt64(0x1234), addresses[1]) !=
        CorePotts.uniform_open01(Float32, CorePotts.Philox4x32x10V2(),
            UInt64(0x1234), addresses[2])
end
