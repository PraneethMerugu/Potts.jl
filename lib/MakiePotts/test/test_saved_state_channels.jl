function _site_slice_oracle(values, axis, index)
    retained_axes = Tuple(filter(!=(axis), ntuple(identity, ndims(values))))
    retained_size = ntuple(i -> size(values, retained_axes[i]), Val(2))
    return [
        values[CartesianIndex(ntuple(source_axis ->
            source_axis == axis ? index :
            site[findfirst(==(source_axis), retained_axes)], Val(3)))]
        for site in CartesianIndices(retained_size)
    ]
end

@testset "saved-state channels use canonical frame projection and validation" begin
    fixture = render_fixture(dimensions = 3)
    state = fixture.state
    site_key = SiteChannelKey(:activity, Float32)
    cell_key = CellChannelKey(:signal, Float64)
    medium_key = MediumChannelKey(:temperature, Float64)
    site_values = reshape(Float32.(1:length(CorePotts.ownership(state))), size(CorePotts.ownership(state)))
    active_identities = [
        RenderCellIdentity(id, CorePotts.cell_generations(state)[id])
        for id in eachindex(CorePotts.volumes(state)) if CorePotts.volumes(state)[id] > 0
    ]
    cell_values = Dict(identity => Float64(identity.id) for identity in active_identities)
    medium_values = Dict(UInt32(1) => 2.5)
    channels = (
        RenderChannel(site_key, site_values; label = "Activity", units = "a.u."),
        RenderChannel(cell_key, cell_values),
        RenderChannel(medium_key, medium_values; units = "K"),
    )

    full = renderframe(state; channels)
    @test channel(full, site_key).values == site_values
    @test channel(full, site_key).values !== site_values
    @test channel(full, cell_key).values == cell_values
    @test channel(full, cell_key).values !== cell_values
    @test channel(full, medium_key).values == medium_values
    @test channel(full, medium_key).values !== medium_values

    for axis in 1:3, index in (1, size(CorePotts.ownership(state), axis))
        request = RenderRequest(extent = OrthogonalSlice(axis, index))
        frame = renderframe(state, request; channels)
        expected = _site_slice_oracle(site_values, axis, index)
        @test channel(frame, site_key).values == expected
        @test frame_size(frame) == size(expected)
        @test channel(frame, cell_key).values == cell_values
        @test channel(frame, medium_key).values == medium_values
    end

    site_before = copy(site_values)
    cell_before = copy(cell_values)
    medium_before = copy(medium_values)
    first_frame = renderframe(state; channels)
    second_frame = renderframe(state; channels)
    fill!(channel(first_frame, site_key).values, -1f0)
    channel(first_frame, cell_key).values[first(active_identities)] = -1.0
    channel(first_frame, medium_key).values[UInt32(1)] = -1.0
    @test channel(second_frame, site_key).values == site_before
    @test channel(second_frame, cell_key).values == cell_before
    @test channel(second_frame, medium_key).values == medium_before
    @test site_values == site_before
    @test cell_values == cell_before
    @test medium_values == medium_before

    solution_fixture = render_fixture()
    solution = CorePotts.solve(solution_fixture.problem, CorePotts.SequentialCPM())
    solution_values = reshape(
        Float32.(1:length(CorePotts.ownership(solution_fixture.state))),
        size(CorePotts.ownership(solution_fixture.state)),
    )
    from_solution = renderframe(
        solution;
        index = firstindex(solution.u),
        channels = (RenderChannel(site_key, solution_values),),
    )
    @test channel(from_solution, site_key).values == solution_values
end

@testset "saved-state channel rejection is all-or-nothing" begin
    fixture = render_fixture(dimensions = 3)
    state = fixture.state
    site_key = SiteChannelKey(:site, Float64)
    cell_key = CellChannelKey(:cell, Float64)
    medium_key = MediumChannelKey(:medium, Float64)
    valid_site = zeros(Float64, size(CorePotts.ownership(state)))
    valid_site_before = copy(valid_site)
    first_identity = RenderCellIdentity(1, CorePotts.cell_generations(state)[1])

    @test_throws MakiePotts.InvalidRenderFrameError renderframe(
        state; channels = (RenderChannel(site_key, zeros(2, 2)),))
    @test_throws MakiePotts.InvalidRenderFrameError renderframe(
        state; channels = (RenderChannel(site_key, fill("wrong", size(CorePotts.ownership(state)))),))
    @test_throws MakiePotts.InvalidRenderFrameError renderframe(
        state; channels = (RenderChannel(cell_key,
            Dict(RenderCellIdentity(first_identity.id, first_identity.generation + 1) => 1.0)),))
    @test_throws MakiePotts.InvalidRenderFrameError renderframe(
        state; channels = (RenderChannel(medium_key, Dict(UInt32(0) => 1.0)),))
    @test_throws MakiePotts.InvalidRenderFrameError renderframe(
        state; channels = (
            RenderChannel(site_key, valid_site),
            RenderChannel(site_key, valid_site),
        ))
    @test_throws MakiePotts.InvalidRenderFrameError renderframe(
        state; channels = (
            RenderChannel(site_key, valid_site),
            RenderChannel(cell_key,
                Dict(RenderCellIdentity(
                    first_identity.id, first_identity.generation + 1) => 1.0)),
        ))
    @test valid_site == valid_site_before
    @test_throws MakiePotts.InvalidRenderFrameError renderframe(
        state; channels = ("not a channel",))
    @test_throws BoundsError renderframe(
        state,
        RenderRequest(extent = OrthogonalSlice(3, size(CorePotts.ownership(state), 3) + 1));
        channels = (RenderChannel(site_key, valid_site),),
    )
end
