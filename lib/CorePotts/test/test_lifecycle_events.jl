using Test
using CorePotts
using KernelAbstractions
using SciMLBase

module LifecycleExtensionFixture
using CorePotts
struct DoubleProperty{Key} <: AbstractLifecycleEffect end
DoubleProperty(key::Symbol) = DoubleProperty{key}()
double_property_key(::DoubleProperty{Key}) where {Key} = Key


struct DoublePropertyPlan <: AbstractPropertyLifecyclePlan
    cell::CellID
    key::Symbol
end

CorePotts.plan_lifecycle_effect(effect::DoubleProperty, snapshot::PreLifecycleSnapshot,
    id::CellID) = DoublePropertyPlan(id, double_property_key(effect))
CorePotts.validate_lifecycle_plan(plan::DoublePropertyPlan, snapshot) =
    property_value(snapshot.state, plan.key, plan.cell)
function CorePotts.commit_property_plan!(state, plan::DoublePropertyPlan)
    current = property_value(state, plan.key, plan.cell)
    return set_cell_property!(state, plan.key, plan.cell, 2current)
end
CorePotts.compiled_effect_category(::DoubleProperty) = CompiledCustomEffect()
function CorePotts.compiled_apply_effect!(::DoubleProperty{Key}, state, cell,
        properties, mcs, rng, seed) where {Key}
    values = getproperty(state.core.properties, Key)
    @inbounds values[cell] *= 2
    return nothing
end

struct SwapStage end
struct StagedSwapProperty{Key} <: AbstractLifecycleEffect end
StagedSwapProperty(key::Symbol) = StagedSwapProperty{key}()

CorePotts.compiled_effect_category(::StagedSwapProperty) =
    CompiledStagedPropertyEffect()
CorePotts.compiled_effect_stages(::StagedSwapProperty) = (SwapStage(),)
function CorePotts.compiled_effect_workspace(::StagedSwapProperty{Key}, state,
        plan) where {Key}
    values = getproperty(state.potts.storage.properties, Key)
    return CompiledStagedEffectWorkspace(((similar(values),),))
end
function CorePotts.compiled_evaluate_effect_stage!(::StagedSwapProperty{Key},
        ::SwapStage, workspace::Tuple, state, cell, properties, mcs, rng,
        seed) where {Key}
    values = getproperty(state.core.properties, Key)
    other = cell == 1 ? 2 : 1
    @inbounds workspace[1][cell] = values[other]
    return nothing
end
function CorePotts.compiled_commit_effect_stage!(::StagedSwapProperty{Key},
        ::SwapStage, workspace::Tuple, state, cell, properties, mcs, rng,
        seed) where {Key}
    values = getproperty(state.core.properties, Key)
    @inbounds values[cell] = workspace[1][cell]
    return nothing
end
end

function lifecycle_state_fixture(; capacity = 4)
    provenance = ComponentIdentity(:lifecycle_fixture, v"1.0.0", :test)
    schema = PropertySchema(
        PropertyDescriptor(:target, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = SplitOnDivision(),
            transition = PreserveOnTransition()),
        PropertyDescriptor(:age, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = CloneOnDivision(),
            transition = PreserveOnTransition()),
    )
    owners = fill(MediumOwner(1), 4, 4)
    fill!(view(owners, :, 1:2), CellOwner(1))
    fill!(view(owners, 1:2, 3:4), CellOwner(2))
    state = LogicalPottsState(owners, CellCapacity(capacity);
        cell_types = Dict(CellID(1) => CellTypeID(1), CellID(2) => CellTypeID(2)),
        medium_domains = (MediumID(1),), property_schema = schema)
    property_values(state, :target)[1:2] .= Int32[8, 2]
    property_values(state, :age)[1:2] .= Int32[4, 1]
    return state
end

@testset "lifecycle and persistence scalar lifecycle phase" begin
    state = lifecycle_state_fixture()
    growth = LifecycleEvent(ActiveCellsTarget(), EveryMCS(), AlwaysLifecycleTrigger(),
        AddCellProperty(:target, Int32(2)); semantic_id = 1)
    division = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:target, Int32(8)), DivideCell(VectorDivision((0.0, 1.0)));
        semantic_id = 2, priority = 3)
    custom = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:age, Int32(4)), LifecycleExtensionFixture.DoubleProperty(:age);
        semantic_id = 3)
    after, report = apply_lifecycle_phase(state, (division, custom, growth), 1)
    @test report.property_updates == 3
    @test report.successful_divisions == 1
    @test report.failed_division_geometry == 0
    @test active_cell_ids(after) == CellID[CellID(1), CellID(2), CellID(3)]
    @test property_value(after, :target, CellID(1)) == 5
    @test property_value(after, :target, CellID(3)) == 5
    @test property_value(after, :age, CellID(1)) == 8
    @test property_value(after, :age, CellID(3)) == 8
    @test state_invariant_errors(after) == String[]

    transition = LifecycleEvent(ActiveCellsTarget(), EveryMCS(),
        PropertyAtLeast(:age, Int32(1)), TransitionCell(CellTypeID(3));
        semantic_id = 10, priority = 2)
    death = LifecycleEvent(ActiveCellsTarget(), EveryMCS(),
        PropertyAtLeast(:age, Int32(1)), RemoveCellImmediately(MediumID(1));
        semantic_id = 11, priority = 5)
    selected_a, report_a = apply_lifecycle_phase(state, (transition, death), 1;
        resolver = StableLifecyclePriority())
    selected_b, report_b = apply_lifecycle_phase(state, (death, transition), 1;
        resolver = StableLifecyclePriority())
    @test lattice_storage(selected_a) == lattice_storage(selected_b)
    @test report_a.immediate_deaths == report_b.immediate_deaths == 2
    @test n_cells(selected_a) == 0
    @test isempty(reusable_cell_slots(selected_a))

    divided_next, next_report = apply_lifecycle_phase(selected_a,
        (LifecycleEvent(ActiveCellsTarget(), EveryMCS(), AlwaysLifecycleTrigger(),
            DivideCell(VectorDivision((1.0, 0.0))); semantic_id = 12),), 2)
    @test next_report.successful_divisions == 0
    @test isempty(active_cell_ids(divided_next))

    @test_throws LifecycleConflictError apply_lifecycle_phase(state,
        (transition, death), 1; resolver = RejectLifecycleConflicts())

    full = lifecycle_state_fixture(capacity = 2)
    original = copy(lattice_storage(full))
    @test_throws CellCapacityError apply_lifecycle_phase(full, (division,), 1)
    @test lattice_storage(full) == original

    one_site_owners = fill(MediumOwner(1), 2, 2)
    one_site_owners[1, 1] = CellOwner(1)
    one = LogicalPottsState(one_site_owners, CellCapacity(2);
        cell_types = Dict(CellID(1) => CellTypeID(1)), medium_domains = (MediumID(1),),
        property_schema = state.properties.schema)
    property_values(one, :target)[1] = 9
    unchanged, invalid_report = apply_lifecycle_phase(one, (division,), 1)
    @test invalid_report.failed_division_geometry == 1
    @test lattice_storage(unchanged) == lattice_storage(one)

    random_division = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:target, Int32(8)), DivideCell(RandomOrientationDivision(70));
        semantic_id = 70)
    random_a, _ = apply_lifecycle_phase(state, (random_division,), 1; seed = 123)
    random_b, _ = apply_lifecycle_phase(state, (random_division,), 1; seed = 123)
    @test lattice_storage(random_a) == lattice_storage(random_b)

    major_event = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:target, Int32(8)), DivideCell(MajorAxisDivision()); semantic_id = 80)
    major, major_report = apply_lifecycle_phase(state, (major_event,), 1)
    @test major_report.successful_divisions == 1
    @test n_cells(major) == 3
end

@testset "mechanical lifecycle laws" begin
    function mechanical_state(component)
        state = LogicalPottsState(fill(CellOwner(1), 4, 2), CellCapacity(2);
            cell_types = Dict(CellID(1) => CellTypeID(1)),
            medium_domains = (MediumID(1),), property_schema = required_properties(component))
        property_values(state, :target_volume)[1] = 8
        property_values(state, :volume_strength)[1] = 2
        property_values(state, :volume_pressure)[1] = 99
        return state
    end
    event = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1), AlwaysLifecycleTrigger(),
        DivideCell(VectorDivision((1.0, 0.0))); semantic_id = 90)

    constitutive = FluctuatingVolumePressure(number_type = Float32)
    reset_state, _ = apply_lifecycle_phase(mechanical_state(constitutive), (event,), 1;
        lifecycle_components = (constitutive,))
    @test property_values(reset_state, :target_volume)[1:2] == Float32[4, 4]
    @test property_values(reset_state, :volume_pressure)[1:2] == Float32[0, 0]

    preserving = FluctuatingVolumePressure(number_type = Float32,
        division = PreserveMechanicalOnDivision())
    preserved_state, _ = apply_lifecycle_phase(mechanical_state(preserving), (event,), 1;
        lifecycle_components = (preserving,))
    @test property_values(preserved_state, :volume_pressure)[1:2] == Float32[99, 99]

    redraw = FluctuatingVolumePressure(number_type = Float32,
        noise = FixedMechanicalNoise(1.0f0), division = StationaryRedrawAfterDivision())
    redrawn_a, _ = apply_lifecycle_phase(mechanical_state(redraw), (event,), 1;
        lifecycle_components = (redraw,), seed = 812)
    redrawn_b, _ = apply_lifecycle_phase(mechanical_state(redraw), (event,), 1;
        lifecycle_components = (redraw,), seed = 812)
    @test property_values(redrawn_a, :volume_pressure) ==
          property_values(redrawn_b, :volume_pressure)
    @test any(!iszero, property_values(redrawn_a, :volume_pressure)[1:2])

    death = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(2), AlwaysLifecycleTrigger(),
        RemoveCellImmediately(MediumID(1)); semantic_id = 91)
    dead, _ = apply_lifecycle_phase(preserved_state, (death,), 2)
    @test all(iszero, property_values(dead, :volume_pressure))
end

@testset "compiled CPU lifecycle integration" begin
    provenance = ComponentIdentity(:compiled_lifecycle_fixture, v"1.0.0", :test)
    schema = PropertySchema(
        PropertyDescriptor(:target, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = SplitOnDivision(),
            transition = PreserveOnTransition()),
        PropertyDescriptor(:age, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = CloneOnDivision(),
            transition = PreserveOnTransition()))
    logical = LogicalPottsState(fill(CellOwner(1), 4, 4), CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)), medium_domains = (MediumID(1),),
        property_schema = schema)
    property_values(logical, :target)[1] = 16
    property_values(logical, :age)[1] = 5
    domain = CartesianDomain((4, 4))
    proposal = first_shell_relation(ProposalRole(), Val(2))
    surface = first_shell_relation(SurfaceRole(), Val(2))
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    compiled = compile_scientific_state(logical, domain, tracker)
    plan = ExecutionPlan(KernelAbstractions.CPU())
    growth = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), AddCellProperty(:target, Int32(2)); semantic_id = 101)
    division = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:target, Int32(8)), DivideCell(VectorDivision((1.0f0, 0.0f0)));
        semantic_id = 102)
    lifecycle = compile_lifecycle((division, growth), compiled, plan)
    integrator = init_scientific(compiled, proposal, ScientificComponentSet(),
        SequentialCPM(temperature = 0.0f0); plan, lifecycle, seed = 44)
    @test step!(integrator) === integrator
    snapshot = logical_state(integrator)
    @test n_cells(snapshot) == 2
    @test property_values(snapshot, :target)[1:2] == Int32[9, 9]
    @test property_values(snapshot, :age)[1:2] == Int32[5, 5]
    @test current_lifecycle_report(integrator).successful_divisions == 1
    @test isempty(tracker_conformance_errors(integrator.state, tracker, snapshot))
end

@testset "compiled CPU lifecycle failure atomicity and open effect" begin
    logical = lifecycle_state_fixture(capacity = 4)
    domain = CartesianDomain((4, 4))
    proposal = first_shell_relation(ProposalRole(), Val(2))
    surface = first_shell_relation(SurfaceRole(), Val(2))
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)

    function make_integrator(events; resolver = RejectLifecycleConflicts(), source = logical)
        state = compile_scientific_state(source, domain, tracker)
        metrics = ExecutionMetrics()
        plan = ExecutionPlan(KernelAbstractions.CPU(); metrics)
        lifecycle = compile_lifecycle(events, state, plan; resolver)
        integrator = init_scientific(state, proposal, ScientificComponentSet(),
            SequentialCPM(temperature = 0.0f0); plan, lifecycle, seed = 91)
        return integrator, metrics
    end

    custom = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:age, Int32(4)), LifecycleExtensionFixture.DoubleProperty(:age);
        semantic_id = 110)
    custom_integrator, custom_metrics = make_integrator((custom,))
    step!(custom_integrator)
    @test custom_metrics.host_synchronizations == 0
    @test property_values(logical_state(custom_integrator), :age)[1:2] == Int32[8, 1]

    staged = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(),
        LifecycleExtensionFixture.StagedSwapProperty(:age); semantic_id = 109)
    staged_integrator, staged_metrics = make_integrator((staged,))
    step!(staged_integrator)
    @test staged_metrics.host_synchronizations == 0
    @test staged_metrics.device_allocations == 0
    @test property_values(logical_state(staged_integrator), :age)[1:2] == Int32[1, 4]

    transition = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), TransitionCell(CellTypeID(3));
        semantic_id = 111, priority = 1)
    death = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), RemoveCellImmediately(MediumID(1));
        semantic_id = 112, priority = 2)
    conflict_integrator, _ = make_integrator((transition, death))
    before = lattice_storage(logical_state(conflict_integrator))
    @test_throws CompiledLifecycleError run_compiled_lifecycle!(conflict_integrator,
        conflict_integrator.lifecycle, UInt64(1))
    @test conflict_integrator.mcs == 0
    @test lattice_storage(logical_state(conflict_integrator)) == before
    @test n_cells(logical_state(conflict_integrator)) == 2

    selected_integrator, _ = make_integrator((transition, death);
        resolver = StableLifecyclePriority())
    step!(selected_integrator)
    selected = logical_state(selected_integrator)
    @test n_cells(selected) == 0
    @test generation(selected, CellID(1)) == CellGeneration(1)
    @test generation(selected, CellID(2)) == CellGeneration(1)

    full = lifecycle_state_fixture(capacity = 2)
    division = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:target, Int32(8)),
        DivideCell(VectorDivision((1.0f0, 0.0f0))); semantic_id = 113)
    full_integrator, _ = make_integrator((division,); source = full)
    full_before = lattice_storage(logical_state(full_integrator))
    @test_throws CompiledLifecycleError run_compiled_lifecycle!(full_integrator,
        full_integrator.lifecycle, UInt64(1))
    failed = logical_state(full_integrator)
    @test lattice_storage(failed) == full_before
    @test property_values(failed, :target)[1:2] == Int32[8, 2]
end

@testset "compiled lifecycle derived-moment repair" begin
    provenance = ComponentIdentity(:compiled_moment_lifecycle, v"1.0.0", :test)
    schema = PropertySchema(PropertyDescriptor(:age, Int32,
        ConstantInitializer(Int32(0)); requester = provenance,
        division = CloneOnDivision(), transition = PreserveOnTransition()))
    owners = fill(MediumOwner(1), 6, 6)
    fill!(view(owners, 2:5, 2:5), CellOwner(1))
    logical = LogicalPottsState(owners, CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = (MediumID(1),), property_schema = schema)
    domain = CartesianDomain((6, 6))
    proposal = first_shell_relation(ProposalRole(), Val(2))
    surface = first_shell_relation(SurfaceRole(), Val(2))
    connectivity = first_shell_relation(ConnectivityRole(), Val(2))
    boundary_tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    moment_tracker = UnwrappedMomentTracker(connectivity; number_type = Float32)
    state = compile_scientific_state(logical, domain, boundary_tracker; moment_tracker)
    plan = ExecutionPlan(KernelAbstractions.CPU())
    division = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), DivideCell(VectorDivision((1.0f0, 0.0f0)));
        semantic_id = 120)
    lifecycle = compile_lifecycle((division,), state, plan)
    integrator = init_scientific(state, proposal, ScientificComponentSet(),
        SequentialCPM(temperature = 0.0f0); plan, lifecycle, moment_tracker, seed = 8)
    run_compiled_lifecycle!(integrator, lifecycle, UInt64(1))
    snapshot = logical_state(integrator)
    rebuilt = rebuild_tracker(moment_tracker, snapshot, domain)
    @test integrator.state.trackers.moments.tracked == rebuilt.tracked
    @test integrator.state.trackers.moments.coordinate_sums == rebuilt.coordinate_sums
    @test integrator.state.trackers.moments.quadratic_sums == rebuilt.quadratic_sums
    @test moment_is_tracked(integrator.state.trackers.moments, CellOwner(1))
    @test moment_is_tracked(integrator.state.trackers.moments, CellOwner(2))
end
