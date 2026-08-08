@testset "per-cell native state pool lifecycle and atomicity" begin
    path = (:root, :cell_component)
    template = PottsToolkit.NativeLogicalState(
        path,
        (8.0, Float64[4.0, 6.0]),
        (3.0,),
        nothing,
        0.0,
        SciMLBase.ReturnCode.Success,
    )
    policy = PottsToolkit.NativeCellStatePolicy(template)
    bank = PottsToolkit.NativeCellStateBank(template, 3)
    pool = CorePotts.BackendSPI.BulkComponentStatePool(
        Bool[true, false, false],
        UInt32[1, 0, 0],
        Int16[2, 0, 0],
        bank,
        policy,
    )

    transition = CorePotts.TransitionLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(1, 1, 1, 1),
        CorePotts.CellIdentity(1, 1, 2),
        CorePotts.CellIdentity(1, 1, 3),
    )
    divide = CorePotts.DivideLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(2, 1, 1, 1),
        CorePotts.CellIdentity(1, 1, 3),
        CorePotts.CellIdentity(1, 1, 3),
        CorePotts.CellIdentity(2, 1, 3),
    )
    create = CorePotts.CreateLifecycleEvent(
        CorePotts.QualifiedLifecycleRequestIdentity(3, 1, 3, 1),
        CorePotts.CellIdentity(3, 1, 4),
    )
    receipt = CorePotts.LifecycleReceipt(
        1, 101, CorePotts.LifecycleEvent[transition, divide, create]
    )
    transaction = CorePotts.BackendSPI.stage_lifecycle_receipt!(pool, receipt)
    @test CorePotts.BackendSPI.bulk_component_completed_mcs(pool) == 0
    @test CorePotts.BackendSPI.component_identity(pool, 2) === nothing
    candidate = CorePotts.BackendSPI.component_transaction_state(transaction)
    @test PottsToolkit.native_cell_state(policy, candidate, 2).u == template.u
    @test PottsToolkit.native_cell_state(policy, candidate, 3).u == template.u
    CorePotts.BackendSPI.commit_component_state_transaction!(transaction)
    @test CorePotts.BackendSPI.bulk_component_completed_mcs(pool) == 1
    @test CorePotts.BackendSPI.component_identity(pool, 1) == CorePotts.CellIdentity(1, 1, 3)
    @test CorePotts.BackendSPI.component_identity(pool, 2) == CorePotts.CellIdentity(2, 1, 3)
    @test CorePotts.BackendSPI.component_identity(pool, 3) == CorePotts.CellIdentity(3, 1, 4)

    removal_receipt = CorePotts.LifecycleReceipt(
        2,
        102,
        CorePotts.LifecycleEvent[
            CorePotts.RemoveCellLifecycleEvent(
                CorePotts.QualifiedLifecycleRequestIdentity(1, 2, 2, 1),
                CorePotts.CellIdentity(2, 1, 3),
            ),
            CorePotts.RetireLifecycleEvent(
                CorePotts.QualifiedLifecycleRequestIdentity(2, 2, 3, 1),
                CorePotts.CellIdentity(3, 1, 4),
                77,
                88,
            ),
        ],
    )
    CorePotts.BackendSPI.apply_lifecycle_receipt!(pool, removal_receipt)
    @test CorePotts.BackendSPI.component_identity(pool, 2) === nothing
    @test CorePotts.BackendSPI.component_identity(pool, 3) === nothing
    removed_metadata = CorePotts.BackendSPI.component_metadata_snapshot(pool)
    @test removed_metadata.generations == UInt32[1, 1, 1]
    @test removed_metadata.kinds == Int16[3, 0, 0]

    snapshot = CorePotts.BackendSPI.component_state_snapshot(pool)
    snapshot.u[2][1][1] = -99.0
    @test PottsToolkit.native_cell_state(policy,
        CorePotts.BackendSPI.component_state_snapshot(pool), 1).u[2][1] == 4.0
    @test PottsToolkit.native_cell_state(policy,
        CorePotts.BackendSPI.component_state_snapshot(pool), 2).u[2][1] == 4.0

    unsupported_policy = PottsToolkit.NativeCellStatePolicy(
        template;
        creation = PottsToolkit._NativeUnsupportedAction(:creation),
    )
    unsupported_pool = CorePotts.BackendSPI.BulkComponentStatePool(
        Bool[true, false], UInt32[1, 0], Int16[2, 0],
        PottsToolkit.NativeCellStateBank(template, 2), unsupported_policy,
    )
    failing = CorePotts.LifecycleReceipt(
        1,
        201,
        CorePotts.LifecycleEvent[CorePotts.CreateLifecycleEvent(
            CorePotts.QualifiedLifecycleRequestIdentity(1, 2, 2, 1),
            CorePotts.CellIdentity(2, 1, 2),
        )],
    )
    before = CorePotts.BackendSPI.component_state_snapshot(unsupported_pool)
    @test_throws ArgumentError CorePotts.BackendSPI.stage_lifecycle_receipt!(
        unsupported_pool, failing
    )
    @test CorePotts.BackendSPI.component_identity(unsupported_pool, 2) === nothing
    @test CorePotts.BackendSPI.bulk_component_completed_mcs(unsupported_pool) == 0
    @test CorePotts.BackendSPI.component_state_snapshot(unsupported_pool).u == before.u

    split_policy = PottsToolkit.NativeCellStatePolicy(
        template;
        division = PottsToolkit._NativeSplitDaughtersAction(0.25),
    )
    split_pool = CorePotts.BackendSPI.BulkComponentStatePool(
        Bool[true, false], UInt32[1, 0], Int16[2, 0],
        PottsToolkit.NativeCellStateBank(template, 2), split_policy,
    )
    split_receipt = CorePotts.LifecycleReceipt(
        1,
        301,
        CorePotts.LifecycleEvent[CorePotts.DivideLifecycleEvent(
            CorePotts.QualifiedLifecycleRequestIdentity(1, 3, 1, 1),
            CorePotts.CellIdentity(1, 1, 2),
            CorePotts.CellIdentity(1, 1, 2),
            CorePotts.CellIdentity(2, 1, 2),
        )],
    )
    CorePotts.BackendSPI.apply_lifecycle_receipt!(split_pool, split_receipt)
    settled = CorePotts.BackendSPI.component_state_snapshot(split_pool)
    @test PottsToolkit.native_cell_state(split_policy, settled, 1).u ==
          (2.0, [1.0, 1.5])
    @test PottsToolkit.native_cell_state(split_policy, settled, 2).u ==
          (6.0, [3.0, 4.5])

    wrapped = PottsToolkit.NativeCellStatePool(
        path,
        Bool[true, false],
        UInt32[2, 1],
        Int16[5, 0],
        PottsToolkit.NativeCellStateBank(template, 2),
        policy;
        completed_mcs = 7,
        last_transaction_identity = 44,
    )
    identity = CorePotts.CellIdentity(1, 2, 5)
    @test PottsToolkit.native_cell_state(wrapped, identity).u == template.u
    @test_throws CorePotts.BackendSPI.StaleCellIdentityError PottsToolkit.native_cell_state(
        wrapped, CorePotts.CellIdentity(1, 1, 5)
    )
    logical = PottsToolkit.native_cell_state_snapshot(wrapped)
    @test logical.path == path
    @test logical.active == Bool[true, false]
    @test logical.generations == UInt32[2, 1]
    @test logical.kinds == Int16[5, 0]
    @test logical.identities == [identity, nothing]
    @test logical.states[1].u == template.u
    @test logical.states[2] === nothing
    @test logical.capacity == 2
    @test logical.completed_mcs == 7
    @test logical.last_transaction_identity == 44
end
