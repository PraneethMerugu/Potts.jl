isdefined(@__MODULE__, :_site_aggregate_problem) || include("fixtures/site_aggregates.jl")

_site_aggregate_maintenance_contract(; structured = false)

@testset "different contribution laws do not share one maintained value" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _site_aggregate_problem(; distinct = true)
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        SPI = CorePotts.CompilerSPI
        @test count(item -> item isa SPI.SiteSumTracker, SPI.tracker_instances(integrator.plan.core_program.tracker_plan)) == 2
        step!(integrator)
        @test Array(integrator.u[:amount]) == Float32[3, 3, 0]
        @test Array(integrator.u[:repeated]) == Float32[5, 4, 0]
    end
end

@testset "integer unit-site aggregates reuse exact ownership counts" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _site_aggregate_problem(; contribution = _ -> 1)
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        SPI = CorePotts.CompilerSPI
        trackers = SPI.tracker_instances(integrator.plan.core_program.tracker_plan)
        @test count(item -> item isa SPI.OwnershipCountTracker, trackers) == 1
        @test !any(item -> item isa SPI.SiteSumTracker, trackers)
        expected_counts = Int32[count(==(owner), model.labels) for owner in eachindex(integrator.u.cell_kinds)]
        @test Array(SPI.program_tracker_values(integrator.runtime, Val(:cell_volume))) == expected_counts
        step!(integrator)
        @test Array(integrator.u[:amount]) == Float32[2, 1, 0]
        @test Array(integrator.u[:repeated]) == Float32[2, 1, 0]
    end
end

@testset "aggregate source and consumer scopes stay distinct" begin
    @variables signal amount other
    kind = CellKind(:cell; extinction = ForbidExtinction())
    lattice = LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed())
    site = SiteBinding(:source, sites(lattice))
    cell = CellBinding(:first, cells(kind))
    second = CellBinding(:second, cells(kind))
    function source(expression)
        PottsSystem(
            name = :scope_aggregate,
            statements = StatementSet(
                (
                    lattice, kind,
                    FieldState(signal; initial = 1.0, scope = site),
                    CellState(amount; initial = 0.0, scope = cell),
                    CellState(other; initial = 0.0, scope = second),
                    Synchronous(:read, Assign(amount, expression); anchor = cell),
                )
            ),
            unknowns = (signal, amount, other)
        )
    end
    @test complete(source(aggregate(signal; over = site, by = cell))) isa PottsSystem
    @test_throws r"outside its lexical scope" complete(source(aggregate(signal; over = site, by = second)))
    orphan = SiteBinding(:orphan, sites(lattice))
    @test_throws r"unresolved_symbolic_leaf|not declared" complete(source(aggregate(signal; over = orphan, by = cell)))
    @test_throws r"site or field" complete(source(aggregate(other; over = site, by = cell)))
    # The legal maintained read does not authorize a separate direct site read
    # in the same cell expression, even when both read the identical source.
    @test_throws r"CellState or ModelState reads" complete(source(aggregate(signal; over = site, by = cell) + signal))
end

@testset "mixed source and parameter publication has no intermediate aggregate" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _site_aggregate_problem()
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        setu(integrator, model.signal)(integrator, fill(1.0f20, 2, 2))
        before = integrator.u
        failure = try
            setp(integrator, model.gain)(integrator, 1.0f20)
            nothing
        catch error
            error
        end
        @test failure isa LocalMath.LocalMathValidationError
        @test occursin("contract: :runtime_stage_validation", sprint(showerror, failure))
        @test integrator.u === before
        @test getp(integrator, model.gain)(integrator) == 1.0f0
        setu(integrator, (model.signal, model.gain))(integrator, (fill(1.0f-20, 2, 2), 1.0f20))
        expected = _independent_owner_sum(Array(integrator.u[:signal]), model.labels, 1.0f20)
        restored = init(model.problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
        step!(integrator)
        step!(restored)
        @test Array(integrator.u[:amount]) == Array(restored.u[:amount]) == expected
        @test Array(integrator.u[:repeated]) == expected
        @test integrator.u.ownership == model.labels
    end
end

@testset "aggregate algebra and tolerance admission" begin
    kind = CellKind(:cell; extinction = ForbidExtinction())
    lattice = Lattice((2, 2); boundary = Closed())
    site = SiteBinding(:source, sites(lattice))
    cell = CellBinding(:owner, cells(kind))
    @variables signal
    @test_throws r"maintenance/rebuild" aggregate(signal; over = site, by = cell, combine = max)
    @test_throws r"SiteBinding" aggregate(signal; over = sites(lattice), by = cell)
    @test_throws r"CellBinding" aggregate(signal; over = site, by = cells(kind))
    for tolerance in (-1.0, Inf, NaN, true)
        @test_throws r"finite nonnegative" _site_aggregate_problem(; atol = tolerance)
        @test_throws r"finite nonnegative" _site_aggregate_problem(; rtol = tolerance)
    end
    @test_throws r"absolute tolerance" _site_aggregate_problem(; atol = 1.0u"m")
    @test_throws r"relative tolerance" _site_aggregate_problem(; rtol = 1.0u"m")
    for literal in (2, true)
        model = _site_aggregate_problem(; contribution = _ -> literal)
        @test_throws r"floating contribution" init(model.problem; scalar_type = Float32)
    end
end

@testset "aggregate absolute tolerances use source physical units" begin
    reference_units = ReferenceUnits(length = 2.0u"m", time = 1.0u"s")
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _site_aggregate_problem(; unit = 2.0u"m", reference_units)
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        step!(integrator)
        @test Array(integrator.u[:amount]) == Float32[3, 3, 0]
        @test Array(integrator.u[:repeated]) == Float32[3, 3, 0]
    end
    @test _site_aggregate_problem(; unit = 2.0u"m", reference_units, atol = 0.25u"m").problem isa PottsProblem
    @test_throws r"absolute tolerance" _site_aggregate_problem(; unit = 2.0u"m", reference_units, atol = 1.0)
    @test_throws r"absolute tolerance" _site_aggregate_problem(; unit = 2.0u"m", reference_units, atol = 1.0u"s")
end
