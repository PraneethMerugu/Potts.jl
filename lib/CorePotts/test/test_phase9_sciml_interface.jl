using SciMLBase
using KernelAbstractions
using Serialization

function phase9_fixture(; tspan = (0, 3), seed = 17, parameters = NamedTuple(),
        parameterization = nothing, lifecycle_events = (), observables = ())
    volume = QuadraticVolumeHamiltonian(number_type = Float32)
    owners = fill(MediumOwner(1), 5, 5)
    fill!(view(owners, 2:4, 2:3), CellOwner(1))
    logical = LogicalPottsState(owners, CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = (MediumID(1),), property_schema = required_properties(volume))
    property_values(logical, :target_volume)[1] = 6
    property_values(logical, :volume_strength)[1] = 1
    domain = CartesianDomain((5, 5))
    proposal = first_shell_relation(ProposalRole(), Val(2))
    surface = first_shell_relation(SurfaceRole(), Val(2))
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    components = ScientificComponentSet(energies = (volume,))
    model = PottsModel(proposal, tracker; components, parameters, parameterization,
        lifecycle_events, observables)
    problem = PottsProblem(model, logical, domain, tspan; seed)
    return (; volume, logical, domain, proposal, tracker, components, model, problem)
end

struct Phase9DeviceCounter{A} <: AbstractPottsDeviceCallback
    counter::A
end
CorePotts.device_callback_requirements(::Phase9DeviceCounter) = ()
CorePotts.device_callback_effects(::Phase9DeviceCounter) = (DeviceObservationEffect(),)
CorePotts.device_callback_priority(::Phase9DeviceCounter) = 0
CorePotts.device_callback_due(::Phase9DeviceCounter, mcs::Integer) = isodd(mcs)
@kernel function phase9_device_counter_kernel!(counter)
    index = @index(Global, Linear)
    index == 1 && (@inbounds counter[1] += UInt32(1))
end
function CorePotts.execute_device_callback!(callback::Phase9DeviceCounter, integrator)
    kernel = phase9_device_counter_kernel!(integrator.inner.plan.backend, 1)
    launch!(integrator.inner.plan, kernel, callback.counter; ndrange = 1)
    return integrator
end

struct Phase9OrderedDeviceCallback{A} <: AbstractPottsDeviceCallback
    output::A
    identity::UInt32
    priority::Int
end
CorePotts.device_callback_requirements(::Phase9OrderedDeviceCallback) = ()
CorePotts.device_callback_effects(::Phase9OrderedDeviceCallback) =
    (DeviceObservationEffect(),)
CorePotts.device_callback_priority(callback::Phase9OrderedDeviceCallback) = callback.priority
CorePotts.device_callback_due(::Phase9OrderedDeviceCallback, mcs::Integer) = mcs == 1
@kernel function phase9_ordered_callback_kernel!(output, identity)
    index = @index(Global, Linear)
    if index == 1
        ordinal = @inbounds(output[1] + UInt32(1))
        @inbounds begin
            output[1] = ordinal
            output[Int(ordinal) + 1] = identity
        end
    end
end
function CorePotts.execute_device_callback!(callback::Phase9OrderedDeviceCallback, integrator)
    kernel = phase9_ordered_callback_kernel!(integrator.inner.plan.backend, 1)
    launch!(integrator.inner.plan, kernel, callback.output, callback.identity; ndrange = 1)
    return integrator
end

struct Phase9UnsupportedControl <: AbstractPottsDeviceCallbackEffect end
struct Phase9UnsupportedDeviceCallback <: AbstractPottsDeviceCallback end
CorePotts.device_callback_requirements(::Phase9UnsupportedDeviceCallback) = ()
CorePotts.device_callback_effects(::Phase9UnsupportedDeviceCallback) =
    (Phase9UnsupportedControl(),)
CorePotts.device_callback_priority(::Phase9UnsupportedDeviceCallback) = 0
CorePotts.device_callback_due(::Phase9UnsupportedDeviceCallback, mcs::Integer) = true

struct Phase9Parameterization end
(::Phase9Parameterization)(p) = ScientificComponentSet(
    kinetic_modifiers = (PositiveYield(p.yield),))
struct Phase9StructParameters
    yield::Float32
end

struct Phase9ExtensionProposal <: AbstractProposalLaw end
CorePotts.construct_proposal_attempt(::Phase9ExtensionProposal, args...) =
    construct_proposal_attempt(NeighborCopyProposal(), args...)

struct Phase9ExtensionSequential{T <: AbstractFloat} <: AbstractSequentialCPMAlgorithm
    temperature::T
end
CorePotts.component_identity(::Phase9ExtensionSequential) =
    ComponentIdentity(:phase9_extension_sequential, v"1.0.0", :test)
CorePotts.algorithm_guarantees(::Phase9ExtensionSequential) =
    algorithm_guarantees(SequentialCPM())
CorePotts.acceptance_law(::Phase9ExtensionSequential) = ConventionalMetropolis()
CorePotts.proposal_law(::Phase9ExtensionSequential) = Phase9ExtensionProposal()

struct Phase9BackendFamily end
struct Phase9CapabilityBackend <: KernelAbstractions.Backend end
CorePotts.backend_capabilities(::Phase9CapabilityBackend) = BackendCapabilities(
    Phase9BackendFamily(), QualifiedBackend, true, true, false, false, (v"1.0.0",))

@testset "Phase 9 problem ownership, remake, and cache" begin
    fixture = phase9_fixture()
    problem = fixture.problem
    @test problem_geometry(problem) === fixture.domain
    @test problem.seed == 17
    @test problem.tspan == (0, 3)
    @test nslots(problem.capacity) == 3
    @test problem.u0 !== fixture.logical
    before = copy(lattice_storage(problem.u0))
    lattice_storage(fixture.logical)[1] = CellOwner(1)
    @test lattice_storage(problem.u0) == before
    @test PottsProblem(fixture.model, problem.u0, fixture.domain, (0, 0)).seed == 0
    @test_throws InvalidPottsProblemError PottsProblem(
        fixture.model, fixture.logical, fixture.domain, (2, 1))
    @test_throws InvalidPottsProblemError PottsProblem(
        fixture.model, fixture.logical, fixture.domain, (0, 1); p = Dict(:x => 1))

    remade = remake(problem; seed = 99, tspan = (2, 4))
    @test remade.seed == 99
    @test remade.tspan == (2, 4)
    @test problem.seed == 17

    cache = PottsCompilationCache()
    first_integrator = init(problem, SequentialCPM(); cache)
    second_integrator = init(problem, SequentialCPM(); cache)
    scheduled_integrator = init(problem, SequentialCPM(); cache, saveat = (1, 2))
    remade_integrator = init(remake(problem; seed = 123, tspan = (0, 2)),
        SequentialCPM(); cache, save_start = false, save_end = false)
    @test length(cache) == 1
    @test cache.misses == 1
    @test cache.hits == 3
    @test first_integrator.inner.state !== second_integrator.inner.state
    @test scheduled_integrator.options.saveat == [1, 2]
    @test remade_integrator.prob.seed == 123
    init(problem, LotteryCPM(); cache, save_start = false, save_end = false)
    @test length(cache) == 2
    @test cache.misses == 2
    @test occursin("artifacts", sprint(show, cache))
    empty!(cache)
    @test isempty(cache.artifacts)

    concurrent_cache = PottsCompilationCache()
    tasks = [Threads.@spawn init(problem, SequentialCPM(); cache = concurrent_cache,
                 save_start = false, save_end = false) for _ in 1:3]
    concurrent_integrators = fetch.(tasks)
    @test length(concurrent_cache) == 1
    @test concurrent_cache.misses == 1
    @test concurrent_cache.hits == 2
    @test length(unique(objectid(integrator.inner.state)
        for integrator in concurrent_integrators)) == 3
end

@testset "Phase 9 authoritative solve and saving" begin
    fixture = phase9_fixture()
    algorithm = SequentialCPM(temperature = 2.0f0)
    one_shot = solve(fixture.problem, algorithm)
    initialized = init(fixture.problem, algorithm)
    interactive = solve!(initialized)
    @test one_shot.retcode == interactive.retcode == ReturnCode.Success
    @test one_shot.t == interactive.t == [0, 3]
    @test lattice_storage(logical_snapshot(one_shot.u[end].state.potts)) ==
          lattice_storage(logical_snapshot(interactive.u[end].state.potts))
    @test length(one_shot) == 2
    @test one_shot(0) === one_shot[1]
    @test_throws UnsavedTimeError one_shot(1)
    @test_throws BoundsError one_shot[3]

    saved = solve(fixture.problem, algorithm; saveat = [1, 2, 2], save_start = false)
    @test saved.t == [1, 2, 3]
    @test all(entry -> entry.residency == :host, saved.u)
    @test saved.u[1].state !== saved.u[2].state

    manual = init(fixture.problem, algorithm; save_everystep = true)
    @test step!(manual) === manual
    @test manual.t == 1
    continued = solve!(manual)
    @test continued.t == [0, 1, 2, 3]
    @test solve!(manual) === continued
    @test_throws IntegratorTerminatedError step!(manual)

    partial = solve(fixture.problem, algorithm; maxiters = 1)
    @test partial.retcode == ReturnCode.MaxIters
    @test partial.t[end] == 1
    zero_budget = solve(fixture.problem, algorithm; maxiters = 0)
    @test zero_budget.retcode == ReturnCode.MaxIters
    @test zero_budget.t == [0]
    @test zero_budget.stats.completed_mcs == 0
    @test_throws UnsupportedSolverOptionError solve(fixture.problem, algorithm; dt = 1)
    @test_throws UnsupportedSolverOptionError solve(fixture.problem, algorithm; mystery = true)
end

@testset "Phase 9 callbacks, resident hook, and structural overhead" begin
    fixture = phase9_fixture(tspan = (0, 4))
    host_hits = Ref(0)
    callback = DiscreteCallback(
        (state, t, integrator) -> t == 2,
        integrator -> begin
            host_hits[] += 1
            terminate!(integrator)
        end;
        save_positions = (false, false))
    terminated = solve(fixture.problem, SequentialCPM(); callback)
    @test terminated.retcode == ReturnCode.Terminated
    @test terminated.t[end] == 2
    @test host_hits[] == 1
    @test terminated.stats.host_callback_boundaries == 2

    requested_save = DiscreteCallback(
        (state, t, integrator) -> t == 1,
        integrator -> savevalues!(integrator))
    requested = solve(fixture.problem, SequentialCPM(); callback = requested_save,
        save_start = false, save_end = false)
    @test requested.t == [1]

    counter = zeros(UInt32, 1)
    device_callback = Phase9DeviceCounter(counter)
    resident = solve(fixture.problem, SequentialCPM(); callback = device_callback)
    @test counter[1] == 2
    @test resident.stats.device_callback_invocations == 2
    @test resident.stats.host_callback_boundaries == 0

    order = zeros(UInt32, 3)
    later = Phase9OrderedDeviceCallback(order, UInt32(20), 20)
    earlier = Phase9OrderedDeviceCallback(order, UInt32(10), 10)
    ordered = solve(phase9_fixture(tspan = (0, 1)).problem, SequentialCPM();
        callback = (later, earlier), save_start = false, save_end = false)
    @test order == UInt32[2, 10, 20]
    @test ordered.stats.device_callback_invocations == 2
    @test_throws UnsupportedSolverOptionError init(fixture.problem, SequentialCPM();
        callback = Phase9UnsupportedDeviceCallback())

    direct_state = compile_scientific_state(deepcopy(fixture.problem.u0), fixture.domain,
        fixture.tracker)
    direct = init_scientific(direct_state, fixture.proposal, fixture.components,
        SequentialCPM(); seed = fixture.problem.seed)
    wrapped = init(fixture.problem, SequentialCPM(); save_start = false, save_end = false)
    direct_launches = direct.plan.metrics.launches
    wrapped_launches = wrapped.inner.plan.metrics.launches
    step!(direct)
    step!(wrapped)
    @test direct.plan.metrics.launches - direct_launches ==
          wrapped.inner.plan.metrics.launches - wrapped_launches
    @test wrapped.inner.plan.metrics.host_synchronizations == 0
    @test wrapped.inner.plan.metrics.device_to_host_transfers == 0
end

@testset "Phase 9 checkpoint path and symbolic parameters" begin
    fixture = phase9_fixture(tspan = (0, 4))
    integrator = init(fixture.problem, LotteryCPM(); save_start = false)
    step!(integrator, 2)
    checkpoint = capture_checkpoint(integrator; retain = true)
    @test length(integrator.checkpoints) == 1
    resumed = restore_checkpoint(checkpoint, fixture.problem, LotteryCPM())
    @test resumed.t == 2
    restored_solution = solve!(resumed)
    step!(integrator, 2)
    uninterrupted = solve!(integrator)
    @test lattice_storage(logical_snapshot(restored_solution.u[end].state.potts)) ==
          lattice_storage(logical_snapshot(uninterrupted.u[end].state.potts))

    parameterized = phase9_fixture(parameters = (yield = 1.5f0,),
        parameterization = Phase9Parameterization())
    handle = PottsParameterHandle(:yield)
    @test parameterized.problem[handle] == 1.5f0
    @test SciMLBase.is_parameter(parameterized.problem, :yield)
    @test SciMLBase.parameter_index(parameterized.problem, :yield) == handle
    @test SciMLBase.parameter_symbols(parameterized.problem) == [:yield]

    mutable_parameters = init(parameterized.problem, SequentialCPM();
        save_start = false, save_end = false)
    @test set_parameter!(mutable_parameters, handle, 2.5f0) === mutable_parameters
    @test mutable_parameters.p[handle] == 2.5f0
    @test_throws ArgumentError set_parameter!(mutable_parameters, handle, 2.5)
    solve!(mutable_parameters)
    @test_throws IntegratorTerminatedError set_parameter!(
        mutable_parameters, handle, 1.0f0)

    structured = phase9_fixture(parameters = Phase9StructParameters(1.25f0),
        parameterization = Phase9Parameterization())
    @test SciMLBase.parameter_symbols(structured.problem) == [:yield]
    structured_integrator = init(structured.problem, SequentialCPM();
        save_start = false, save_end = false)
    set_parameter!(structured_integrator, handle, 1.75f0)
    @test structured_integrator.p[handle] == 1.75f0

    compiled = compile_scientific_state(deepcopy(parameterized.problem.u0),
        parameterized.domain, parameterized.tracker)
    aliased = DeviceInitialState(compiled, AliasInitialState())
    aliased_problem = PottsProblem(parameterized.model, aliased,
        parameterized.domain, (0, 1); p = parameterized.problem.p)
    @test_throws ArgumentError init(aliased_problem, SequentialEquilibrium())
    retried = init(aliased_problem, SequentialCPM(); save_start = false,
        save_end = false)
    @test solve!(retried).retcode == ReturnCode.Success

    failing_callback = DiscreteCallback((state, t, integ) -> true,
        integ -> error("injected callback failure"))
    failing = init(aliased_problem, SequentialCPM(); callback = failing_callback,
        save_start = false, save_end = false)
    @test_throws ErrorException step!(failing)
    @test failing.retcode == ReturnCode.Failure
    after_failure = init(aliased_problem, SequentialCPM(); save_start = false,
        save_end = false)
    @test solve!(after_failure).retcode == ReturnCode.Success
end

@testset "Phase 9 open algorithms, capabilities, reports, and observables" begin
    fixture = phase9_fixture(tspan = (0, 2), observables = (:cell_count,))
    algorithm = Phase9ExtensionSequential(2.0f0)
    solution = solve(fixture.problem, algorithm; save_start = false,
        snapshot_policy = ObservableSnapshotPolicy(integrator ->
            (cell_count = n_cells(logical_state(integrator)),)))
    @test solution_problem(solution) === fixture.problem
    @test solution.retcode == ReturnCode.Success
    @test proposal_law(algorithm) isa Phase9ExtensionProposal
    @test acceptance_law(algorithm) isa ConventionalMetropolis
    handle = PottsObservableHandle(:cell_count)
    @test SciMLBase.is_observed(fixture.problem, :cell_count)
    @test solution[handle] == [1]
    @test_throws UnsavedObservableError solve(fixture.problem, algorithm)[handle]
    @test snapshot_mcs(only(solution.u)) == only(solution.t)
    @test snapshot_residency(only(solution.u)) === :observable
    @test_throws ArgumentError snapshot_state(only(solution.u))

    host_solution = solve(fixture.problem, algorithm; save_start = false,
        snapshot_policy = HostSnapshotPolicy())
    @test snapshot_residency(only(host_solution.u)) === :host
    @test snapshot_state(only(host_solution.u)) isa LogicalPottsState

    report = compatibility_report(fixture.problem, algorithm)
    @test report.qualified
    @test report.dimensions == 2
    @test occursin("qualified=true", sprint(show, report))
    integrator = init(fixture.problem, algorithm; save_start = false,
        save_end = false)
    compiled = compilation_report(integrator)
    @test compiled.host_synchronizations_before_first_mcs == 0
    @test occursin("PottsCompilationReport", sprint(show, compiled))
    @test_throws UnsafePottsSerializationError serialize(IOBuffer(), integrator)
    @test_throws UnsafePottsSerializationError serialize(
        IOBuffer(), integrator.inner)

    capabilities = backend_capabilities(Phase9CapabilityBackend())
    @test capabilities.family isa Phase9BackendFamily
    @test supports(capabilities, QualifiedBackendCapability())
    @test supports(capabilities, SemanticRNGCapability(v"1.0.0"))

    namespace = RNGNamespaceIdentity(0x123456789abcdef)
    @test length(compile_rng_namespaces((namespace,))) == 1
    @test_throws ArgumentError compile_rng_namespaces((namespace, namespace))

    continuous = ContinuousCallback((state, t, integ) -> 1.0,
        integ -> nothing)
    @test_throws UnsupportedSolverOptionError init(
        fixture.problem, algorithm; callback = continuous)
end

@testset "Phase 9 semantic ensembles" begin
    fixture = phase9_fixture(tspan = (0, 2), seed = 0x1234)
    expected = [ensemble_seed(EnsembleSeedDerivationV1(), UInt64(0x1234), i)
                for i in 1:4]
    ensemble = EnsembleProblem(fixture.problem; seed = 0x1234)
    serial = solve(ensemble, SequentialCPM(), EnsembleSerial(); trajectories = 4,
        save_start = false, save_end = false)
    threaded = solve(ensemble, SequentialCPM(), EnsembleThreads(); trajectories = 4,
        save_start = false, save_end = false)
    @test [solution.provenance.seed for solution in serial.u] == expected
    @test [solution.provenance.seed for solution in threaded.u] == expected
    @test [lattice_storage(solution.prob.u0) for solution in serial.u] ==
          [lattice_storage(solution.prob.u0) for solution in threaded.u]

    seen = UInt64[]
    customized = EnsembleProblem(fixture.problem; seed = 0x9876,
        prob_func = (prob, context) -> begin
            push!(seen, prob.seed)
            remake(prob; tspan = (0, context.sim_id))
        end)
    custom_solution = solve(customized, SequentialCPM(), EnsembleSerial(); trajectories = 3,
        save_start = false, save_end = false)
    @test seen == fill(UInt64(0x1234), 3)
    @test [solution.prob.tspan[2] for solution in custom_solution.u] == [1, 2, 3]
    @test [solution.provenance.seed for solution in custom_solution.u] ==
          [ensemble_seed(EnsembleSeedDerivationV1(), UInt64(0x9876), i) for i in 1:3]

    managed = EnsembleProblem(fixture.problem;
        prob_func = (prob, context) -> remake(prob; seed = UInt64(100 + context.sim_id)),
        seed_policy = UserManagedEnsembleSeeds())
    managed_solution = solve(managed, SequentialCPM(), EnsembleSerial(); trajectories = 2,
        save_start = false, save_end = false)
    @test [solution.provenance.seed for solution in managed_solution.u] == UInt64[101, 102]

    rerun_seeds = UInt64[]
    rerunning = EnsembleProblem(fixture.problem; seed = 0x4567, max_reruns = 1,
        output_func = (solution, context) -> begin
            push!(rerun_seeds, solution.provenance.seed)
            return solution, context.repeat == 1
        end)
    rerun_solution = solve(rerunning, SequentialCPM(), EnsembleSerial(); trajectories = 1,
        save_start = false, save_end = false)
    @test length(rerun_solution.u) == 1
    @test rerun_seeds == [
        ensemble_seed(EnsembleSeedDerivationV1(), UInt64(0x4567), 1, 1),
        ensemble_seed(EnsembleSeedDerivationV1(), UInt64(0x4567), 1, 2),
    ]

    unbounded_request = EnsembleProblem(fixture.problem; max_reruns = 0,
        output_func = (solution, context) -> (solution, true))
    @test_throws ArgumentError solve(unbounded_request, SequentialCPM(),
        EnsembleSerial(); trajectories = 1, save_start = false, save_end = false)
end
