using Test
using LocalMath
using KernelAbstractions

const LWCG = LocalMath

function allocate_test_grouping(backend, candidates, destinations, name)
    spec = LWCG._destination_grouping_workspace_spec(
        candidates, destinations; path = (name,), name_prefix = name)
    authority = LWCG._WorkspaceAuthority(spec.leaves, spec.template)
    workspace = LWCG._materialize_workspace(
        authority.template, authority, LWCG._WorkspaceAllocator(backend))
    return LWCG._destination_grouping_from_workspace(workspace, spec.shape)
end

function reset_test_grouping!(grouping)
    fill!(grouping.destinations, Int32(0))
    fill!(grouping.valid, UInt8(0))
    fill!(grouping.order_a, Int32(0))
    fill!(grouping.order_b, Int32(0))
    fill!(grouping.starts, Int32(1))
    fill!(grouping.invalid_ordinal, typemax(Int32))
    return grouping
end

@testset "canonical candidate grouping" begin
    backend = KernelAbstractions.CPU()
    grouping = allocate_test_grouping(backend, 6, 3, :small)
    reset_test_grouping!(grouping)

    copyto!(grouping.destinations, Int32[2, 1, 2, 3, 1, 3])
    copyto!(grouping.valid, UInt8[1, 1, 1, 0, 1, 0])
    LWCG._group_destinations!(backend, grouping)
    KernelAbstractions.synchronize(backend)

    @test Array(LWCG._destination_grouping_order(grouping)) ==
        Int32[2, 5, 1, 3, 4, 6, 0, 0]
    @test Array(grouping.starts) == Int32[1, 3, 5, 5]
    @test collect(LWCG._destination_segment(grouping, 1)) == Int32[1, 2]
    @test collect(LWCG._destination_segment(grouping, 2)) == Int32[3, 4]
    @test isempty(LWCG._destination_segment(grouping, 3))
    @test LWCG._destination_grouping_success(grouping)

    reset_test_grouping!(grouping)
    copyto!(grouping.destinations, Int32[0, 1, 2, 4, 3, 2])
    copyto!(grouping.valid, fill(UInt8(1), 6))
    LWCG._group_destinations!(backend, grouping)
    KernelAbstractions.synchronize(backend)
    @test !LWCG._destination_grouping_success(grouping)
    @test Array(grouping.invalid_ordinal) == Int32[1]
    @test Array(grouping.valid) == UInt8[0, 1, 1, 0, 1, 1]
    @test Array(grouping.starts) == Int32[1, 2, 4, 5]

    empty_grouping = allocate_test_grouping(backend, 0, 0, :empty)
    reset_test_grouping!(empty_grouping)
    LWCG._group_destinations!(backend, empty_grouping)
    KernelAbstractions.synchronize(backend)
    @test Array(empty_grouping.starts) == Int32[1]
    @test LWCG._destination_grouping_success(empty_grouping)

    n = 513
    destinations = Int32[mod1(37 * i, 17) for i in 1:n]
    valid = UInt8[i % 7 == 0 ? 0 : 1 for i in 1:n]
    wide = allocate_test_grouping(backend, n, 17, :wide)
    reset_test_grouping!(wide)
    copyto!(wide.destinations, destinations)
    copyto!(wide.valid, valid)
    LWCG._group_destinations!(backend, wide)
    KernelAbstractions.synchronize(backend)
    expected_live = sort(Int32.(1:n); by = ordinal -> (
        valid[ordinal] == 0,
        valid[ordinal] == 0 ? typemax(Int32) : destinations[ordinal],
        ordinal,
    ))
    expected_order = vcat(expected_live,
        zeros(Int32, Int(wide.sort_capacity) - n))
    @test Array(LWCG._destination_grouping_order(wide)) == expected_order
    live_order = filter(ordinal -> valid[ordinal] != 0, expected_live)
    sorted_destinations = Int32[destinations[ordinal] for ordinal in live_order]
    expected_starts = Int32[searchsortedfirst(sorted_destinations, destination)
        for destination in 1:18]
    @test Array(wide.starts) == expected_starts

    @test_throws LWCG.LocalMathValidationError LWCG._destination_grouping_capacity(
        typemax(Int32))
    @test_throws LWCG.LocalMathValidationError LWCG._destination_grouping_workspace_spec(
        1, typemax(Int32); path = (:overflow,), name_prefix = :overflow)
end
