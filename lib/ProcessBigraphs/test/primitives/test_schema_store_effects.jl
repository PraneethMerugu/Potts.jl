@testset "schema and immutable committed projections" begin
    schema = BranchSchema(
        cell=BranchSchema(
            mass=LeafSchema(Float64; default=1.0, units="fg", ontology="mass",
                update_law=:add),
            signal=LeafSchema(Float32; shape=(2,), default=Float32[1, 2],
                update_law=:indexed),
        ),
    )
    scale = TimeScale(1, 10, :second)
    snapshot = initial_snapshot(schema, Dict(); time=LogicalTime(0, scale))
    @test snapshot[path("cell", "mass")] == 1.0
    signal = snapshot[path("cell", "signal")]
    signal[1] = 99
    @test snapshot[path("cell", "signal")] == Float32[1, 2]
    projection = project(snapshot, path("cell"); recursive=true)
    projected_signal = projection[path("cell", "signal")]
    projected_signal[2] = 88
    @test projection[path("cell", "signal")] == Float32[1, 2]
    @test paths(projection) ==
        (path("cell", "mass"), path("cell", "signal"))
    @test schema_at(schema, path("cell", "mass")) isa LeafSchema{Float64,0}
    @test_throws ProcessBigraphError initial_snapshot(schema,
        Dict(path("cell", "signal") => Float32[1]); time=LogicalTime(0, scale))
    @test_throws ProcessBigraphError initial_snapshot(schema,
        Dict(path("unknown") => 1); time=LogicalTime(0, scale))
end

@testset "typed update algebra and atomic reconciliation" begin
    scale = TimeScale(1)
    schema = BranchSchema(
        total=LeafSchema(Float64; default=0.0, update_law=:add),
        owner=LeafSchema(String; default="none", update_law=:replace),
        record=LeafSchema(Dict{String,Int};
            default=Dict{String,Int}(), update_law=:keyed),
        array=LeafSchema(Int; shape=(3,), default=[0, 0, 0], update_law=:indexed),
        members=LeafSchema(Set{Int}; default=Set{Int}(), update_law=:set),
        trace=LeafSchema(Vector{String}; default=String[], update_law=:append_stable),
    )
    snapshot = initial_snapshot(schema, Dict(); time=LogicalTime(0, scale))
    total = path("total")
    effects = [
        delta(snapshot, total, AdditiveUpdate(), 1.0; producer="z", event_id="e"),
        delta(snapshot, total, AdditiveUpdate(), 1e16; producer="a", event_id="e"),
        delta(snapshot, total, AdditiveUpdate(), -1e16; producer="m", event_id="e"),
    ]
    forward = reconcile(snapshot, effects, LogicalTime(1, scale))
    reversed_snapshot = reconcile(snapshot, Base.reverse(effects), LogicalTime(1, scale))
    @test snapshot[total] == 0.0
    @test forward[total] == reversed_snapshot[total]
    @test snapshot_fingerprint(forward) == snapshot_fingerprint(reversed_snapshot)

    updated = reconcile(forward, [
        delta(forward, path("record"), KeyedUpdate(), ("a" => 1,);
            producer="a", event_id="e2"),
        delta(forward, path("array"), IndexedUpdate(), (2 => 7,);
            producer="b", event_id="e2"),
        delta(forward, path("members"), SetUpdate(),
            SetPatch(additions=(1, 2)); producer="c", event_id="e2"),
        delta(forward, path("trace"), StableAppend(), ["x", "y"];
            producer="d", event_id="e2"),
    ], LogicalTime(2, scale))
    @test updated[path("record")] == Dict("a" => 1)
    @test updated[path("array")] == [0, 7, 0]
    @test updated[path("members")] == Set([1, 2])
    @test updated[path("trace")] == ["x", "y"]

    conflict = [
        delta(updated, path("owner"), ReplaceUpdate(), "a";
            producer="a", event_id="e3"),
        delta(updated, path("owner"), ReplaceUpdate(), "b";
            producer="b", event_id="e3"),
    ]
    before = snapshot_fingerprint(updated)
    @test_throws ProcessBigraphError reconcile(updated, conflict, LogicalTime(3, scale))
    @test snapshot_fingerprint(updated) == before

    keyed_conflict = [
        delta(updated, path("record"), KeyedUpdate(), ("x" => 1,);
            producer="a", event_id="e3"),
        delta(updated, path("record"), KeyedUpdate(), ("x" => 2,);
            producer="b", event_id="e3"),
    ]
    @test_throws ProcessBigraphError reconcile(updated, keyed_conflict,
        LogicalTime(3, scale))
end
