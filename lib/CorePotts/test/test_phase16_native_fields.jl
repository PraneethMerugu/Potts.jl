using KernelAbstractions

function p16c_engine(
    values;
    spacing=ntuple(_ -> one(eltype(values)), ndims(values)),
    boundaries=ntuple(
        _ -> AxisFieldBoundary(PeriodicFieldBoundary()),
        ndims(values),
    ),
    diffusion=eltype(values)(0.1),
    decay=zero(eltype(values)),
    tick_duration=eltype(values)(0.01),
    substeps_per_tick=1,
    reject_negative=true,
)
    plan = ExecutionPlan(KernelAbstractions.CPU(); block_size=64)
    geometry = CorePotts.NativeFieldGeometry(
        size(values);
        spacing,
        number_type=eltype(values),
    )
    CorePotts.NativeFieldEngine(
        :phase16_native,
        values,
        plan;
        geometry,
        boundaries,
        diffusion,
        decay,
        tick_duration,
        substeps_per_tick,
        reject_negative,
    )
end

function p16c_publish_allocations(engine)
    @allocated CorePotts.publish_native_field!(engine)
end

function p16c_stage_allocations(engine, target)
    @allocated CorePotts.stage_native_field!(engine, target)
end

function p16c_periodic_reference(
    values,
    spacing,
    diffusion,
    decay,
    forcing,
    dt,
)
    result = similar(values)
    for index in CartesianIndices(values)
        center = values[index]
        laplacian = zero(center)
        coordinates = Tuple(index)
        for axis in 1:ndims(values)
            low = Base.setindex(
                coordinates,
                mod1(coordinates[axis] - 1, size(values, axis)),
                axis,
            )
            high = Base.setindex(
                coordinates,
                mod1(coordinates[axis] + 1, size(values, axis)),
                axis,
            )
            laplacian += (
                values[low...] + values[high...] - 2center
            ) / (spacing[axis] * spacing[axis])
        end
        result[index] = center +
            dt * (diffusion * laplacian + forcing[index] - decay * center)
    end
    result
end

@testset "Phase 16.C native CPU staged transaction" begin
    initial = reshape(Float64.(1:20), 4, 5)
    engine = p16c_engine(
        initial;
        spacing=(0.5, 2.0),
        diffusion=0.1,
        decay=0.03,
        tick_duration=0.01,
    )
    engine.forcing .= reshape(range(0.0, 0.19; length=20), 4, 5)
    forcing = copy(engine.forcing)
    expected = p16c_periodic_reference(
        initial,
        (0.5, 2.0),
        0.1,
        0.03,
        forcing,
        0.01,
    )
    authoritative = engine.published
    CorePotts.stage_native_field!(engine, 1)
    @test engine.published === authoritative
    @test engine.time_tick == 0
    @test engine.publication_epoch == 0
    @test engine.plan.metrics.device_to_host_transfers == 0
    CorePotts.complete_native_field!(engine)
    @test engine.published === authoritative
    @test engine.completed
    CorePotts.publish_native_field!(engine)
    @test engine.published !== authoritative
    @test engine.published ≈ expected atol=1.0e-14
    @test engine.time_tick == 1
    @test engine.publication_epoch == 1
    @test !engine.staged
    @test !engine.completed
    @test engine.plan.metrics.launches == 2
    @test engine.plan.metrics.host_synchronizations == 1
    @test engine.plan.metrics.host_to_device_transfers == 0
    @test engine.plan.metrics.device_to_host_transfers == 0

    CorePotts.stage_native_field!(engine, 2)
    CorePotts.complete_native_field!(engine)
    p16c_publish_allocations(engine)
    CorePotts.stage_native_field!(engine, 3)
    CorePotts.complete_native_field!(engine)
    @test p16c_publish_allocations(engine) == 0

    CorePotts.stage_native_field!(engine, 4)
    @test_throws ArgumentError CorePotts.stage_native_field!(engine, 5)
    CorePotts.discard_native_field!(engine)
    @test engine.time_tick == 3
    @test_throws ArgumentError CorePotts.stage_native_field!(engine, 3)
end

@testset "Phase 16.C native CPU 2D/3D and boundary oracle" begin
    for dimensions in ((4, 5), (3, 4, 5))
        initial = fill(2.5f0, dimensions)
        engine = p16c_engine(
            initial;
            diffusion=0.1f0,
            decay=0.0f0,
            tick_duration=0.01f0,
        )
        CorePotts.advance_native_field!(engine, 1)
        @test engine.published == initial
        @test engine.time_tick == 1
    end

    constant = fill(3.0, 5, 4)
    boundary_sets = (
        ntuple(_ -> AxisFieldBoundary(ZeroNeumannFieldBoundary()), 2),
        ntuple(_ -> AxisFieldBoundary(
            DirichletFieldBoundary(3.0)), 2),
        ntuple(_ -> AxisFieldBoundary(
            MixedFieldBoundary(1.0, 1.0, 3.0)), 2),
        (
            AxisFieldBoundary(
                PeriodicFieldBoundary(),
                PeriodicFieldBoundary(),
            ),
            AxisFieldBoundary(
                ZeroNeumannFieldBoundary(),
                DirichletFieldBoundary(3.0),
            ),
        ),
    )
    for boundaries in boundary_sets
        engine = p16c_engine(
            constant;
            boundaries,
            diffusion=0.2,
            tick_duration=0.01,
        )
        CorePotts.advance_native_field!(engine, 1)
        @test engine.published == constant
    end

    @test_throws ArgumentError MixedFieldBoundary(0.0, 0.0, 1.0)
    @test_throws ArgumentError p16c_engine(
        zeros(Float64, 2, 2);
        boundaries=(AxisFieldBoundary(PeriodicFieldBoundary()),),
    )
end

@testset "Phase 16.C native CPU conservation and manufactured refinement" begin
    impulse = zeros(Float64, 16, 12)
    impulse[3, 7] = 1.0
    engine = p16c_engine(
        impulse;
        spacing=(0.5, 0.75),
        diffusion=0.2,
        tick_duration=0.001,
    )
    initial_mass = sum(engine.published) * prod(engine.geometry.spacing)
    for tick in 1:20
        CorePotts.advance_native_field!(engine, tick)
    end
    final_mass = sum(engine.published) * prod(engine.geometry.spacing)
    @test final_mass ≈ initial_mass atol=1.0e-13
    @test minimum(engine.published) >= 0

    errors = Float64[]
    diffusion = 0.1
    dt = 1.0e-4
    for n in (16, 32)
        dx = 1 / n
        initial = [
            1 + 0.1cos(2π * (i - 1) / n)
            for i in 1:n, j in 1:n
        ]
        engine = p16c_engine(
            initial;
            spacing=(dx, dx),
            diffusion,
            tick_duration=dt,
        )
        CorePotts.advance_native_field!(engine, 1)
        exact_factor = exp(-4π^2 * diffusion * dt)
        exact = [
            1 + 0.1exact_factor * cos(2π * (i - 1) / n)
            for i in 1:n, j in 1:n
        ]
        push!(errors, maximum(abs, engine.published .- exact))
    end
    @test errors[2] < errors[1] / 3
end

@testset "Phase 16.C native CPU failure, allocation, and restart" begin
    initial = fill(1.0f0, 32, 32)
    failing = p16c_engine(
        initial;
        diffusion=0.1f0,
        tick_duration=0.01f0,
    )
    failing.forcing[17] = Float32(NaN)
    before = copy(failing.published)
    CorePotts.stage_native_field!(failing, 1)
    @test_throws ArgumentError CorePotts.complete_native_field!(failing)
    CorePotts.discard_native_field!(failing)
    @test failing.published == before
    @test failing.time_tick == 0
    @test failing.publication_epoch == 0

    unstable = p16c_engine(
        initial;
        spacing=(0.01f0, 0.01f0),
        diffusion=1.0f0,
        tick_duration=1.0f0,
    )
    @test_throws ArgumentError CorePotts.stage_native_field!(unstable, 1)
    @test unstable.published == initial
    @test !unstable.staged

    allocation = p16c_engine(
        initial;
        diffusion=0.1f0,
        tick_duration=0.01f0,
        substeps_per_tick=2,
    )
    CorePotts.stage_native_field!(allocation, 1)
    CorePotts.complete_native_field!(allocation)
    CorePotts.publish_native_field!(allocation)
    p16c_stage_allocations(allocation, 2)
    CorePotts.discard_native_field!(allocation)
    @test p16c_stage_allocations(allocation, 2) == 0
    CorePotts.complete_native_field!(allocation)
    CorePotts.publish_native_field!(allocation)

    baseline = p16c_engine(
        initial;
        diffusion=0.1f0,
        tick_duration=0.01f0,
        substeps_per_tick=2,
    )
    for tick in 1:4
        CorePotts.advance_native_field!(baseline, tick)
    end
    expected = copy(baseline.published)
    for cut in 0:4
        engine = p16c_engine(
            initial;
            diffusion=0.1f0,
            tick_duration=0.01f0,
            substeps_per_tick=2,
        )
        for tick in 1:4
            CorePotts.advance_native_field!(engine, tick)
            if tick == cut
                engine = CorePotts.NativeFieldEngine(
                    :phase16_native,
                    copy(engine.published),
                    ExecutionPlan(KernelAbstractions.CPU(); block_size=64);
                    geometry=engine.geometry,
                    boundaries=engine.boundaries,
                    diffusion=engine.diffusion,
                    decay=engine.decay,
                    tick_duration=engine.tick_duration,
                    substeps_per_tick=engine.substeps_per_tick,
                    reject_negative=engine.reject_negative,
                    time_tick=engine.time_tick,
                )
            end
        end
        @test engine.published == expected
        @test engine.time_tick == 4
    end
end
