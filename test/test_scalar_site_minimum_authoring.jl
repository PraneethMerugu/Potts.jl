isdefined(@__MODULE__, :_site_minimum_problem) || include("fixtures/site_aggregates.jl")

@testset "minimum aggregate authoring uses one bounded operation" begin
    kind = CellKind(:cell; extinction = ForbidExtinction())
    lattice = Lattice((2, 2); boundary = Closed())
    site = SiteBinding(:source, sites(lattice))
    cell = CellBinding(:owner, cells(kind))
    @variables signal
    @test_throws r"requires a finite empty-owner value" aggregate(
        signal; over = site, by = cell, combine = min, maximum_sites = 4,
    )
    @test_throws r"requires a maximum_sites" aggregate(
        signal; over = site, by = cell, combine = min, empty = 0.0,
    )
    @test_throws r"additive aggregate does not accept" aggregate(
        signal; over = site, by = cell, empty = 0.0,
    )
    @test_throws r"additive aggregate does not accept" aggregate(
        signal; over = site, by = cell, maximum_sites = 4,
    )
    @test_throws r"does not use additive comparison tolerances" aggregate(
        signal; over = site, by = cell, combine = min, empty = 0.0,
        maximum_sites = 4, atol = 1.0,
    )
    @test_throws r"explicit maintenance/rebuild contract" aggregate(
        signal; over = site, by = cell,
        combine = (left, right) -> min(left, right),
        empty = 0.0, maximum_sites = 4,
    )

    authored = aggregate(
        signal; over = site, by = cell, combine = min,
        empty = 19.0, maximum_sites = 4,
    )
    term = Symbolics.unwrap(authored)
    @test Symbolics.operation(term) === Potts._potts_cell_site_minimum
    @test length(Symbolics.arguments(term)) == 5
    @test Symbolics.value(Symbolics.arguments(term)[4]) == 19.0
    @test Symbolics.value(Symbolics.arguments(term)[5]) == 4
    transfer = Potts.operation_transfer(Potts._potts_cell_site_minimum, 5)
    @test transfer.identity === :cell_site_minimum
    @test transfer.tracker_requirements == (:site_minimum,)

    additive = Symbolics.unwrap(aggregate(signal; over = site, by = cell))
    @test Symbolics.operation(additive) === Potts._potts_cell_site_sum
    @test length(Symbolics.arguments(additive)) == 5
end
