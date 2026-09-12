using StaticArrays, Symbolics, ModelingToolkitBase, SymbolicIndexingInterface, DynamicQuantities
import LocalMath

function _site_aggregate_problem(;
        structured = false, atol = 0, rtol = 0, contribution = identity,
        unit = 1.0, reference_units = nothing, distinct = false, evolve = false,
        logical_shape = structured ? (2,) : (),
    )
    @parameters gain = 1.0
    logical_shape in ((), (2,), (2, 2)) || throw(ArgumentError("unsupported aggregate fixture shape"))
    tensor = logical_shape == (2, 2)
    vector = logical_shape == (2,)
    if tensor
        @variables signal[1:2, 1:2] amount[1:2, 1:2] repeated[1:2, 1:2]
        initial_value = map(value -> value * unit, zero(SMatrix{2, 2, Float64}))
        local_value = gain * signal
    elseif vector
        @variables signal[1:2] amount[1:2] repeated[1:2]
        initial_value = SVector(0.0 * unit, 0.0 * unit)
        local_value = SVector(gain * signal[1], gain * signal[2])
    else
        @variables signal amount repeated
        initial_value = 0.0 * unit
        local_value = gain * signal
    end
    lattice = LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(), max_cells = 3)
    kind = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    declarations = scoped(sites(lattice), :locations) do site
        cell_declarations = scoped(cells(kind), :owners) do cell
            quantity = aggregate(contribution(local_value); over = site, by = cell, atol, rtol)
            second_quantity = distinct ? aggregate(local_value + gain; over = site, by = cell, atol, rtol) : quantity
            StatementSet(
                (
                    CellState(amount; initial = initial_value),
                    CellState(repeated; initial = initial_value),
                    Synchronous(:measure, Assign(amount, quantity)),
                    Synchronous(:measure_again, Assign(repeated, second_quantity)),
                )
            )
        end
        update = !evolve ? () : (
                Synchronous(
                    :source_update,
                    Assign(signal, vector ? SVector(signal[1] + unit, signal[2] + 2unit) : tensor ? 2signal : signal + unit)
                ),
            )
        StatementSet((FieldState(signal; initial = initial_value), update..., cell_declarations...))
    end
    system = PottsSystem(
        name = :maintained_signal,
        statements = StatementSet(
            (
                lattice, kind, medium, declarations...,
                ProposalConstraint(:fixed_ownership, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (signal, amount, repeated), parameters = (gain,)
    )
    labels = Int32[1 2; 1 0]
    values = tensor ? reshape([SMatrix{2, 2}(Float32(i), Float32(-i), Float32(2i), Float32(3i)) for i in 1:4], 2, 2) :
        vector ? reshape([SVector(Float32(i), Float32(2i)) for i in 1:4], 2, 2) :
        reshape(Float32[1, 2, 3, 4], 2, 2)
    values = map(
        value -> value isa StaticArrays.StaticArray ?
            map(leaf -> leaf * unit, value) : value * unit, values
    )
    initial = PottsInitialState(ownership = LabelledCells(labels; cells = [kind, kind], medium), values = (signal => values,))
    completed = reference_units === nothing ? system : complete(system; reference_units)
    return (; problem = PottsProblem(completed, initial, (0, 4); seed = 17), signal, amount, repeated, gain, labels)
end

function _independent_owner_sum(values, labels, gain)
    z = zero(first(values))
    return [sum((gain * values[i] for i in eachindex(labels) if labels[i] == owner); init = z) for owner in 1:3]
end

function _site_minimum_problem(; empty = 19.0, maximum_sites = 4)
    @variables signal amount repeated
    lattice = LatticeDomain(
        :space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(),
        max_cells = 3,
    )
    kind = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    declarations = scoped(sites(lattice), :locations) do site
        consumers = scoped(cells(kind), :owners) do cell
            quantity = aggregate(
                signal; over = site, by = cell, combine = min, empty,
                maximum_sites,
            )
            StatementSet((
                CellState(amount; initial = 0.0),
                CellState(repeated; initial = 0.0),
                Synchronous(:measure, Assign(amount, quantity)),
                Synchronous(:measure_again, Assign(repeated, quantity)),
            ))
        end
        StatementSet((FieldState(signal; initial = 0.0), consumers...))
    end
    system = PottsSystem(
        name = :minimum_signal,
        statements = StatementSet((
            lattice, kind, medium, declarations...,
            ProposalConstraint(:fixed_ownership, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = (signal, amount, repeated),
    )
    labels = Int32[1 2; 1 0]
    values = Float32[1 5; 3 4]
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [kind, kind], medium),
        values = (signal => values,),
    )
    return (;
        problem = PottsProblem(system, initial, (0, 3); seed = 17),
        signal, amount, repeated, labels, empty = Float32(empty), maximum_sites,
    )
end

function _independent_owner_minimum(values, labels, empty, owners)
    return Float32[
        minimum((values[index] for index in eachindex(labels) if labels[index] == owner); init = empty)
        for owner in 1:owners
    ]
end

function _site_aggregate_maintenance_contract(; structured = false, logical_shape = structured ? (2,) : ())
    return @testset "site aggregates share maintenance across two quantity consumers" begin
        for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
            model = _site_aggregate_problem(; structured, logical_shape)
            integrator = init(model.problem, algorithm; scalar_type = Float32)
            SPI = CorePotts.CompilerSPI
            trackers = filter(item -> item isa SPI.SiteSumTracker, SPI.tracker_instances(integrator.plan.core_program.tracker_plan))
            @test length(trackers) == 1
            key = SPI.tracker_quantity(only(trackers))
            if isempty(logical_shape) && algorithm isa SequentialCPM
                # Owning compiler boundary: only the aggregate's source is deferred.
                # A separate compiled direct read of that identical handle survives.
                ir = Potts._analyze_completed_system(model.problem.system)
                manifest = Potts._scheduled_data(model.problem.system).parameters
                _, handles = Potts._state_layout(ir, model.problem.system, manifest, Float32)
                record = only(filter(item -> item.identity.local_id == Potts.StatementID(:measure), ir.source.records))
                source_record = only(filter(item -> item.identity.local_id == Potts.StatementID(:signal), ir.source.records))
                handle = handles[source_record.identity]
                tracker_only = Potts._record_state_handles(ir, record, handles; expressions = (SPI.LiteralExpression(0.0f0),))
                mixed_read = Potts._record_state_handles(ir, record, handles; expressions = (SPI.StateExpression(handle),))
                @test !(handle in tracker_only)
                @test handle in mixed_read
            end
            expected = _independent_owner_sum(Array(integrator.u[:signal]), model.labels, 1.0f0)
            # Tracker owners are declared cell identities; logical CellState
            # storage also includes unused capacity, checked below.
            @test Array(SPI.program_tracker_values(integrator.runtime, key)) == expected[eachindex(integrator.u.cell_kinds)]
            @test iszero(last(expected)) # unused capacity is not an active cell
            step!(integrator)
            @test Array(integrator.u[:amount]) == expected
            @test Array(integrator.u[:repeated]) == expected
            changed = logical_shape == (2, 2) ? fill(SMatrix{2, 2}(2.0f0, -1.0f0, 3.0f0, 5.0f0), 2, 2) :
                logical_shape == (2,) ? fill(SVector(2.0f0, -1.0f0), 2, 2) : fill(2.0f0, 2, 2)
            setu(integrator, model.signal)(integrator, changed)
            expected = _independent_owner_sum(changed, model.labels, 1.0f0)
            @test Array(SPI.program_tracker_values(integrator.runtime, key)) == expected[eachindex(integrator.u.cell_kinds)]
            @test integrator.u.ownership == model.labels
            setp(integrator, model.gain)(integrator, 3.0)
            expected = _independent_owner_sum(changed, model.labels, 3.0f0)
            @test Array(SPI.program_tracker_values(integrator.runtime, key)) == expected[eachindex(integrator.u.cell_kinds)]
            saved = checkpoint(integrator)
            restored = init(model.problem, algorithm; scalar_type = Float32, checkpoint = saved)
            step!(integrator)
            step!(restored)
            @test Array(integrator.u[:amount]) == Array(restored.u[:amount]) == expected
            @test Array(integrator.u[:repeated]) == Array(restored.u[:repeated]) == expected
            @test restored.t == integrator.t == 2
        end
    end
end
