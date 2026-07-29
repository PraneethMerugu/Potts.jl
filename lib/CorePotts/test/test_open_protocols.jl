using Test
using CorePotts

module DownstreamLifecycleFixture
using CorePotts

struct OddMCS <: AbstractMCSSchedule end
CorePotts.is_due(::OddMCS, mcs::Integer) = mcs > 0 ? isodd(mcs) :
    throw(ArgumentError("custom schedules also reject nonpositive MCS values"))

struct AboveVolume <: AbstractLifecycleTrigger
    threshold::Int32
end
CorePotts.lifecycle_triggered(trigger::AboveVolume, snapshot::PreLifecycleSnapshot,
    id::CellID) = finite_volume(snapshot.state, id) > trigger.threshold

struct RecordDivision <: AbstractLifecycleEffect end
CorePotts.plan_lifecycle_effect(::RecordDivision, snapshot::PreLifecycleSnapshot,
    id::CellID) = (cell = id, mcs = snapshot.mcs)

struct VolumeWeightedDivision <: AbstractDivisionPolicy end
function CorePotts.division_property_update(::VolumeWeightedDivision, descriptor, value,
        context::DivisionPropertyContext)
    child = convert(typeof(value), context.child_volume)
    return DivisionPropertyUpdate(value - child, child)
end

struct OffsetTransition <: AbstractTransitionPolicy
    offset::Int32
end
CorePotts.transition_property_value(policy::OffsetTransition, descriptor, value,
    context::TransitionPropertyContext) = value + policy.offset

struct SentinelRetirement <: AbstractRetirementPolicy
    value::Int32
end
CorePotts.retired_property_value(policy::SentinelRetirement, descriptor) = policy.value

struct OffsetPlane <: AbstractDivisionGeometry
    offset::Float32
end
function CorePotts.division_region(geometry::OffsetPlane,
        context::DivisionSiteContext{N, T}) where {N, T}
    return context.coordinate[1] - context.center[1] < geometry.offset ? UInt8(1) : UInt8(2)
end

struct DiagonalLayout <: AbstractInitialLayout
    provisional_id::ProvisionalCellID
    reversed::Bool
end
CorePotts.initial_layout_requirements(::DiagonalLayout) = InitialLayoutRequirements(2)
function CorePotts.emit_initial_claims!(collector::InitialClaimCollector{2}, layout::DiagonalLayout)
    declare_initial_cell!(collector, layout.provisional_id, CellTypeID(3))
    sites = CartesianIndex{2}[CartesianIndex(1, 1), CartesianIndex(2, 2)]
    layout.reversed && reverse!(sites)
    for site in sites
        emit_initial_cell_claim!(collector, site, layout.provisional_id)
    end
    return collector
end
end

@testset "lifecycle and persistence open scalar protocols" begin
    @test is_due(EveryMCS(), 11)
    @test is_due(OnceAtMCS(3), 3)
    @test !is_due(OnceAtMCS(3), 4)
    @test is_due(AtMCS((9, 1, 5, 5)), 5)
    @test isbits(AtMCS((9, 1, 5)))
    @test is_due(PeriodicMCS(2, 3), 8)
    @test !is_due(PeriodicMCS(2, 3; stop = 7), 8)
    @test is_due(DownstreamLifecycleFixture.OddMCS(), 7)
    @test_throws ArgumentError is_due(EveryMCS(), 0)
    @test_throws ArgumentError OnceAtMCS(0)
    @test_throws ArgumentError AtMCS((0, 1))

    provenance = ComponentIdentity(:lifecycle_fixture, v"1.0.0", :test)
    schema = PropertySchema(PropertyDescriptor(:resource, Int32,
        ConstantInitializer(Int32(10)); requester = provenance,
        division = DownstreamLifecycleFixture.VolumeWeightedDivision(),
        transition = DownstreamLifecycleFixture.OffsetTransition(Int32(4)),
        retirement = DownstreamLifecycleFixture.SentinelRetirement(Int32(-9))))
    owners = reshape(OwnerRef[CellOwner(1), CellOwner(1), MediumOwner(1), MediumOwner(1)], 2, 2)
    state = LogicalPottsState(owners, CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)), medium_domains = (MediumID(1),),
        property_schema = schema)
    @test property_values(state, :resource) == Int32[10, -9, -9]

    snapshot = PreLifecycleSnapshot(state, 2)
    trigger = DownstreamLifecycleFixture.AboveVolume(Int32(1))
    effect = DownstreamLifecycleFixture.RecordDivision()
    @test lifecycle_triggered(trigger, snapshot, CellID(1))
    @test plan_lifecycle_effect(effect, snapshot, CellID(1)) == (cell = CellID(1), mcs = 2)
    event = LifecycleEvent(ActiveCellsTarget(), DownstreamLifecycleFixture.OddMCS(), trigger,
        effect; semantic_id = 0x42, priority = 7)
    @test isbits(event)

    divided = logical_state(apply_division_batch(state,
        [DivisionRequest(CellID(1), [2])]))
    @test property_value(divided, :resource, CellID(1)) == 9
    @test property_value(divided, :resource, CellID(2)) == 1
    transitioned = transition_cell_type(divided, CellID(1), CellTypeID(2))
    @test property_value(transitioned, :resource, CellID(1)) == 13
    retired = immediately_remove_cell(transitioned, CellID(2), MediumID(1))
    @test property_values(logical_state(retired), :resource)[2] == -9

    claims = LifecycleConflictClaim[
        LifecycleConflictClaim(CellID(2), Int32(4), 0x20, Int32(12)),
        LifecycleConflictClaim(CellID(1), Int32(2), 0x10, Int32(10)),
        LifecycleConflictClaim(CellID(1), Int32(5), 0x11, Int32(11)),
    ]
    @test resolve_lifecycle_conflicts(StableLifecyclePriority(), claims) == Int32[11, 12]
    @test resolve_lifecycle_conflicts(StableLifecyclePriority(), reverse(claims)) == Int32[11, 12]
    @test_throws LifecycleConflictError resolve_lifecycle_conflicts(
        RejectLifecycleConflicts(), claims)
    tied = vcat(claims, LifecycleConflictClaim(CellID(1), Int32(5), 0x12, Int32(13)))
    @test_throws LifecycleConflictError resolve_lifecycle_conflicts(
        StableLifecyclePriority(), tied)

    geometry = DownstreamLifecycleFixture.OffsetPlane(0.0f0)
    contexts = [DivisionSiteContext((Float32(x), 0.0f0), (0.0f0, 0.0f0)) for x in (-1, 1)]
    labels = UInt8[division_region(geometry, context) for context in contexts]
    report = validate_binary_partition(labels)
    @test report.valid
    @test (report.parent_sites, report.child_sites) == (1, 1)
    @test !validate_binary_partition(UInt8[1, 1]).valid
    @test !validate_binary_partition(UInt8[1, 3]).valid

    custom = DownstreamLifecycleFixture.DiagonalLayout(ProvisionalCellID(80), false)
    custom_reversed = DownstreamLifecycleFixture.DiagonalLayout(ProvisionalCellID(80), true)
    other = CoordinateCellLayout(20, 2, CartesianIndex{2}[CartesianIndex(1, 2)])
    initialized_a = finalize_initial_state((2, 2), custom, other;
        capacity = CellCapacity(2), medium_domains = (MediumID(1),))
    initialized_b = finalize_initial_state((2, 2), other, custom_reversed;
        capacity = CellCapacity(2), medium_domains = (MediumID(1),))
    state_a = logical_state(initialized_a)
    state_b = logical_state(initialized_b)
    @test lattice_storage(state_a) == lattice_storage(state_b)
    @test initialization_report(initialized_a).provisional_to_runtime ==
          initialization_report(initialized_b).provisional_to_runtime
    @test initialization_report(initialized_a).provisional_to_runtime ==
          [ProvisionalCellID(20) => CellID(1), ProvisionalCellID(80) => CellID(2)]
end
