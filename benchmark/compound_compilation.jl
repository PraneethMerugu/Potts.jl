# Run each configuration in a fresh Julia process using an environment that
# develops this checkout. Arguments: model|site sequential|checkerboard.
# Example: julia --project=ENV benchmark/compound_compilation.jl site checkerboard
# Timings are observations, not acceptance thresholds. Package loading is
# outside the measured sections; @time reports compilation separately.
using Potts
using Symbolics

function compound_inputs(storage)
    @variables left right
    state = storage === :model ? ModelState : SiteState
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    system = PottsSystem(
        name = :compound_exchange,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                state(left; initial = 2.0), state(right; initial = 7.0),
                Synchronous(:exchange, Assign(left, right), Assign(right, left)),
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (left, right),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium),
    )
    return system, initial
end

function check_exchange(integrator, storage, left, right, time)
    expected(value) = storage === :model ? value : fill(value, 2, 2)
    @assert integrator.u[:left] == expected(left)
    @assert integrator.u[:right] == expected(right)
    @assert integrator.u.ownership == ones(Int32, 2, 2)
    @assert integrator.t == time
    return nothing
end

function measure_compound(storage, algorithm)
    println("storage=", storage, " algorithm=", typeof(algorithm), " Julia=", VERSION)
    println("authoring")
    @time system, initial = compound_inputs(storage)
    println("structural compilation")
    @time scheduled = mtkcompile(system)
    println("problem construction from scheduled system")
    @time problem = PottsProblem(scheduled, initial, (0, 2); seed = 17)
    println("first initialization")
    @time integrator = init(problem, algorithm)
    println("first step")
    @time step!(integrator)
    check_exchange(integrator, storage, 7.0, 2.0, 1)
    println("second step on same integrator")
    @time step!(integrator)
    check_exchange(integrator, storage, 2.0, 7.0, 2)
    println("repeated initialization of same problem")
    @time repeated = init(problem, algorithm)
    println("first step on repeated initialization")
    @time step!(repeated)
    check_exchange(repeated, storage, 7.0, 2.0, 1)
    return nothing
end

length(ARGS) == 2 || error("expected model|site and sequential|checkerboard")
storage = Symbol(ARGS[1])
storage in (:model, :site) || error("storage must be model or site")
algorithm = ARGS[2] == "sequential" ? SequentialCPM() :
    ARGS[2] == "checkerboard" ? CheckerboardSweepCPM() :
    error("algorithm must be sequential or checkerboard")
measure_compound(storage, algorithm)
