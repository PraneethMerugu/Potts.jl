using OrdinaryDiffEqTsit5: Tsit5

@testset "ModelingToolkitStandardLibrary exact replay" begin
    @named replay_filter =
        ModelingToolkitStandardLibrary.Blocks.FirstOrder(T = 1.0, k = 2.0)
    filter_input = Symbolics.wrap(only(ModelingToolkitBase.inputs(replay_filter)))
    filter_output = Symbolics.wrap(only(ModelingToolkitBase.outputs(replay_filter)))
    @variables replay_drive replay_output
    drive_state = ModelState(replay_drive; name = :replay_drive, initial = 1.0)
    output_state = ModelState(replay_output; name = :replay_output, initial = 0.0)
    component = NativeComponent(
        replay_filter;
        name = :filter,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.25),
        inputs = (NativeInput(filter_input, drive_state; value_type = Float64),),
        outputs = (NativeOutput(filter_output, output_state; value_type = Float64),),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    scheduled = mtkcompile(PottsSystem(
        name = :mtsl_replay,
        statements = StatementSet((
            Lattice((4, 4)), cell, medium, drive_state, output_state,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [replay_drive, replay_output],
        native_components = (component,),
    ))
    path = (:mtsl_replay, :filter)
    labels = zeros(Int, 4, 4)
    labels[2, 2] = 1
    problem = PottsProblem(
        scheduled,
        PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
            native = (NativeOperatingPoint(path),),
        ),
        (0, 2);
        seed = 0x508,
    )
    profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "mtsl-first-order-exact-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.005,
    )
    uninterrupted = init(
        problem, SequentialCPM(); native_profiles = (profile,)
    )
    step!(uninterrupted)
    captured = checkpoint(uninterrupted)
    restored = init(
        problem, SequentialCPM(); native_profiles = (profile,),
        checkpoint = captured,
    )
    step!(uninterrupted)
    step!(restored)
    @test restored.u.replay_output == uninterrupted.u.replay_output
    @test checkpoint(restored).checksum == checkpoint(uninterrupted).checksum
end

