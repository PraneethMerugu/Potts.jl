function bridge_problem(; duration_per_mcs = nothing)
    @parameters target=4.0 strength=1.0 temperature=3.0
    cell = CellKind(:cell)
    medium = MediumKind(:medium)
    @named system = PottsSystem(
        statements = StatementSet((
            Lattice((6, 6)),
            cell,
            medium,
            Volume(cell; target, strength),
            duration_per_mcs === nothing ?
            Protocol(Sweep(; temperature); name = :main) :
            Protocol(
                Sweep(; temperature);
                name = :main,
                duration_per_mcs,
            ),
        )),
        parameters = [target, strength, temperature],
        inputs = [temperature],
        outputs = [:ownership],
    )
    executable = compile(
        complete(system);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 6, 6)
    labels[3:4, 3:4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    return PottsProblem(executable, initial, (0, 2); seed = 17)
end

function physical_bridge_context(
        component, start_tick, target_tick, scale;
        continuation = nothing,
    )
    start = ProcessBigraphs.LogicalTime(start_tick, scale)
    stop = ProcessBigraphs.LogicalTime(target_tick, scale)
    native = bridge_context(component, 0)
    return ProcessBigraphs.InvocationContext(
        "potts",
        "physical-$start_tick-$target_tick",
        start,
        stop,
        ProcessBigraphs.Duration(target_tick - start_tick, scale),
        continuation,
        native.outputs,
        ProcessBigraphs.ModelRNGContext(
            "potts-bridge",
            ProcessBigraphs.NormalizedRootSeed(1),
            "potts",
            start,
            "physical-$start_tick-$target_tick",
        ),
    )
end

function bridge_context(component, start_tick, continuation = nothing)
    scale = ProcessBigraphs.TimeScale(1, 1, :mcs)
    start = ProcessBigraphs.LogicalTime(start_tick, scale)
    stop = ProcessBigraphs.LogicalTime(start_tick + 1, scale)
    endpoint_manifest = ProcessBigraphs.semantic_parameters(
        component
    ).endpoint_manifest.outputs
    output_ports = filter(
        port -> port.direction === :output,
        ProcessBigraphs.ports(component),
    )
    output_bindings = Tuple(
        entry.endpoint => (
            ProcessBigraphs.path("outputs", String(entry.endpoint)),
            ProcessBigraphs.LeafSchema(
                begin
                    value_type = typeof(port).parameters[1]
                    value_type <: AbstractArray ?
                        eltype(value_type) : value_type
                end;
                shape = entry.shape,
                update_law = :replace,
            ),
        )
        for (entry, port) in zip(endpoint_manifest, output_ports)
    )
    rng = ProcessBigraphs.ModelRNGContext(
        "potts-bridge",
        ProcessBigraphs.NormalizedRootSeed(1),
        "potts",
        start,
        "event-$start_tick",
    )
    return ProcessBigraphs.InvocationContext(
        "potts",
        "event-$start_tick",
        start,
        stop,
        ProcessBigraphs.Duration(1, scale),
        continuation,
        output_bindings,
        rng,
    )
end

@testset "ProcessBigraphs whole-MCS bridge" begin
    component = process_component(bridge_problem())
    parameters = ProcessBigraphs.semantic_parameters(component)
    @test parameters.time.native_unit === :mcs
    @test !parameters.time.partial_advance
    @test parameters.scheduling_owner ===
          :process_bigraphs_outer_corepotts_inner
    component_ports = ProcessBigraphs.ports(component)
    input_port = only(filter(port -> port.direction === :input, component_ports))
    @test input_port.interval_behavior === :frozen
    @test all(
        port -> port.update_law === :replace,
        filter(port -> port.direction === :output, component_ports),
    )

    input_values = (
        input_port.name => 2.5,
    )
    view = ProcessBigraphs.PortView(
        UInt64(0), "snapshot-0", input_values
    )
    first = ProcessBigraphs.invoke(
        component, view, bridge_context(component, 0)
    )
    @test first.diagnostics.publication === :committed
    @test first.diagnostics.mcs == 1
    @test length(first.deltas) ==
          count(port -> port.direction === :output, component_ports)

    second = ProcessBigraphs.invoke(
        component, view, bridge_context(component, 1, first.continuation)
    )
    @test second.diagnostics.mcs == 2

    dual_owner_process = EquationProcess(
        :dual_owner, (); writes = ()
    )
    @test_throws ArgumentError EquationComponent(
        component, dual_owner_process; name = :invalid_dual_owner
    )

    corrupted = PottsCheckpoint(
        first.continuation.schema,
        first.continuation.executable_fingerprint,
        first.continuation.core,
        first.continuation.parameter_history,
        first.continuation.replay_class,
        "corrupted",
    )
    @test_throws ArgumentError ProcessBigraphs.invoke(
        component, view, bridge_context(component, 1, corrupted)
    )

    bad_scale = ProcessBigraphs.TimeScale(1, 2, :mcs)
    bad_start = ProcessBigraphs.LogicalTime(0, bad_scale)
    bad_stop = ProcessBigraphs.LogicalTime(1, bad_scale)
    bad_context = ProcessBigraphs.InvocationContext(
        "potts",
        "fractional",
        bad_start,
        bad_stop,
        ProcessBigraphs.Duration(1, bad_scale),
        nothing,
        bridge_context(component, 0).outputs,
        ProcessBigraphs.ModelRNGContext(
            "potts-bridge",
            ProcessBigraphs.NormalizedRootSeed(1),
            "potts",
            bad_start,
            "fractional",
        ),
    )
    @test_throws ArgumentError ProcessBigraphs.invoke(
        component, view, bad_context
    )

    physical = process_component(
        bridge_problem(duration_per_mcs = 30.0u"s")
    )
    physical_time = ProcessBigraphs.semantic_parameters(physical).time
    @test physical_time.duration_per_mcs ==
          (numerator = 30, denominator = 1, unit = :s)
    physical_input = only(filter(
        port -> port.direction === :input,
        ProcessBigraphs.ports(physical),
    ))
    physical_view = ProcessBigraphs.PortView(
        UInt64(0),
        "physical-snapshot",
        (physical_input.name => 2.5,),
    )
    five_seconds = ProcessBigraphs.TimeScale(5, 1, :s)
    physical_result = ProcessBigraphs.invoke(
        physical,
        physical_view,
        physical_bridge_context(physical, 0, 6, five_seconds),
    )
    @test physical_result.diagnostics.mcs == 1
    seven_seconds = ProcessBigraphs.TimeScale(7, 1, :s)
    @test_throws ArgumentError ProcessBigraphs.invoke(
        physical,
        physical_view,
        physical_bridge_context(physical, 0, 1, seven_seconds),
    )
end
