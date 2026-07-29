@testset "serial runtime versioned update algebra" begin
    laws = (
        AdditiveUpdate(),
        MultiplicativeUpdate(),
        ReplaceUpdate(),
        KeyedUpdate(),
        IndexedUpdate(),
        SetUpdate(),
        StableAppend(),
    )
    @test map(law_identity, laws) == (
        :add, :multiply, :replace, :keyed, :indexed, :set, :append_stable)
    @test all(contract -> contract.version == "1.0.0",
        map(update_law_contract, laws))
    @test map(contract -> contract.conflict_policy,
        map(update_law_contract, laws)) == (
        :deterministic_fold,
        :deterministic_fold,
        :single_writer,
        :disjoint_targets,
        :disjoint_targets,
        :disjoint_add_remove,
        :deterministic_fold,
    )

    scale = TimeScale(1)
    schema = BranchSchema(
        additive=LeafSchema(Int; default=1, update_law=:add),
        multiplicative=LeafSchema(Int; default=2, update_law=:multiply),
        replacement=LeafSchema(String; default="none", update_law=:replace),
        keyed=LeafSchema(Dict{String,Int};
            default=Dict{String,Int}(), update_law=:keyed),
        indexed=LeafSchema(Int;
            default=[0, 0], shape=(2,), update_law=:indexed),
        members=LeafSchema(Set{Int};
            default=Set{Int}(), update_law=:set),
        appended=LeafSchema(Vector{String};
            default=String[], update_law=:append_stable),
    )
    initial = initial_snapshot(schema, Dict(); time=LogicalTime(0, scale))
    effects = Delta[
        delta(initial, path("additive"), AdditiveUpdate(), 2;
            producer="b", event_id="event"),
        delta(initial, path("additive"), AdditiveUpdate(), 3;
            producer="a", event_id="event"),
        delta(initial, path("multiplicative"), MultiplicativeUpdate(), 3;
            producer="b", event_id="event"),
        delta(initial, path("multiplicative"), MultiplicativeUpdate(), 5;
            producer="a", event_id="event"),
        delta(initial, path("replacement"), ReplaceUpdate(), "owner";
            producer="a", event_id="event"),
        delta(initial, path("keyed"), KeyedUpdate(), ("left" => 1,);
            producer="a", event_id="event"),
        delta(initial, path("keyed"), KeyedUpdate(), ("right" => 2,);
            producer="b", event_id="event"),
        delta(initial, path("indexed"), IndexedUpdate(), (1 => 4,);
            producer="a", event_id="event"),
        delta(initial, path("indexed"), IndexedUpdate(), (2 => 5,);
            producer="b", event_id="event"),
        delta(initial, path("members"), SetUpdate(),
            SetPatch(additions=(1, 2));
            producer="a", event_id="event"),
        delta(initial, path("appended"), StableAppend(), ("a",);
            producer="a", event_id="event"),
        delta(initial, path("appended"), StableAppend(), ("b",);
            producer="b", event_id="event"),
    ]
    forward = reconcile(initial, effects, LogicalTime(1, scale))
    reverse_order = reconcile(initial, reverse(effects), LogicalTime(1, scale))
    @test snapshot_fingerprint(forward) ==
        snapshot_fingerprint(reverse_order)
    @test forward[path("additive")] == 6
    @test forward[path("multiplicative")] == 30
    @test forward[path("replacement")] == "owner"
    @test forward[path("keyed")] == Dict("left" => 1, "right" => 2)
    @test forward[path("indexed")] == [4, 5]
    @test forward[path("members")] == Set((1, 2))
    @test forward[path("appended")] == ["a", "b"]

    conflicts = (
        Delta[
            delta(initial, path("replacement"), ReplaceUpdate(), "a";
                producer="a", event_id="event"),
            delta(initial, path("replacement"), ReplaceUpdate(), "b";
                producer="b", event_id="event"),
        ],
        Delta[
            delta(initial, path("keyed"), KeyedUpdate(), ("x" => 1,);
                producer="a", event_id="event"),
            delta(initial, path("keyed"), KeyedUpdate(), ("x" => 2,);
                producer="b", event_id="event"),
        ],
        Delta[
            delta(initial, path("indexed"), IndexedUpdate(), (1 => 1,);
                producer="a", event_id="event"),
            delta(initial, path("indexed"), IndexedUpdate(), (1 => 2,);
                producer="b", event_id="event"),
        ],
        Delta[
            delta(initial, path("members"), SetUpdate(),
                SetPatch(additions=(1,));
                producer="a", event_id="event"),
            delta(initial, path("members"), SetUpdate(),
                SetPatch(removals=(1,));
                producer="b", event_id="event"),
        ],
    )
    for conflict in conflicts
        @test_throws ProcessBigraphError reconcile(
            initial, conflict, LogicalTime(1, scale))
        @test snapshot_fingerprint(initial) ==
            snapshot_fingerprint(initial)
    end
end

@testset "serial runtime bounded metamorphic scheduler cases" begin
    scale = TimeScale(1)
    for case_id in 1:16
        first_amount = case_id
        second_amount = 17 - case_id
        forward = c15_add_composite(processes=(
            "left" => (first_amount, 1),
            "right" => (second_amount, 2),
        ))
        reversed = c15_add_composite(processes=(
            "right" => (second_amount, 2),
            "left" => (first_amount, 1),
        ))
        left = initialize_runtime(forward, SerialExecutor(root_seed=case_id))
        right = initialize_runtime(reversed, SerialExecutor(root_seed=case_id))
        run_until!(left, LogicalTime(4, scale))
        run_until!(right, LogicalTime(4, scale))
        @test snapshot_fingerprint(current_snapshot(left)) ==
            snapshot_fingerprint(current_snapshot(right))
        @test event_trace(left) == event_trace(right)
    end
end
