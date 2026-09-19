using StaticArrays
using Symbolics: @variables
using Test: @test
using Potts: anchor_value, @statements

function _scope_population(name, increment; explicit = false)
    @variables polarity[1:2]
    kind = CellKind(:cell; extinction = RetireAtZero())
    declarations = if explicit
        anchor = CellBinding(:population, cells(kind))
        StatementSet(
            (
                CellState(polarity; initial = SVector(1.0, 0.0), retirement = RetireTo(SVector(0.0, 0.0)), scope = anchor),
                Synchronous(:turn, Assign(polarity, SVector(polarity[1], polarity[2] + increment)); anchor),
            )
        )
    else
        scoped(cells(kind), :population) do cell
            @statements begin
                CellState(polarity; initial = SVector(1.0, 0.0), retirement = RetireTo(SVector(0.0, 0.0)))
                Synchronous(:turn, Assign(polarity, SVector(polarity[1], polarity[2] + increment)))
            end
        end
    end
    return PottsSystem(name = name, statements = StatementSet((kind, declarations...)), unknowns = (polarity,))
end

function _scoped_population_contract(algorithm, backend)
    @variables field
    lattice = LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(), max_cells = 2)
    medium = MediumKind(:medium)
    site_declarations = scoped(sites(lattice), :locations) do site
        StatementSet((SiteState(field; initial = 0.0), Synchronous(:sample, Assign(field, field + 1))))
    end
    source = PottsSystem(
        name = :tissue,
        statements = StatementSet((lattice, medium, site_declarations..., ProposalConstraint(:fixed, false), Protocol(Sweep(; temperature = 0.0); name = :main))),
        unknowns = (field,), systems = (_scope_population(:first, 2.0), _scope_population(:second, 3.0)),
    )
    initial = PottsInitialState(ownership = LabelledCells([1 0; 2 0]; cells = [:first₊cell, :second₊cell], medium))
    result = solve(PottsProblem(source, initial, (0, 1); seed = 17), algorithm; backend, scalar_type = Float32)
    @test result.retcode == SciMLBase.ReturnCode.Success
    @test Array(result.u[end][:first₊polarity]) == [SVector(1.0f0, 2.0f0), SVector(1.0f0, 0.0f0)]
    @test Array(result.u[end][:second₊polarity]) == [SVector(1.0f0, 0.0f0), SVector(1.0f0, 3.0f0)]
    return @test Array(result.u[end][:field]) == ones(Float32, 2, 2)
end

function _scoped_anchor_contract(algorithm, backend, domain_kind)
    @variables identity
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    lattice = LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(), max_cells = 2)
    domain = domain_kind === :cell ? cells(cell) : sites(lattice)
    declarations = scoped(domain, :selected) do anchor
        state = domain_kind === :cell ?
            CellState(identity; initial = 0.0, retirement = RetireTo(0.0)) :
            SiteState(identity; initial = 0.0)
        StatementSet((state, Synchronous(:identify, Assign(identity, anchor_value(anchor)))))
    end
    source = PottsSystem(
        name = :identities,
        statements = StatementSet((lattice, cell, medium, declarations..., ProposalConstraint(:fixed, false), Protocol(Sweep(; temperature = 0.0); name = :main))),
        unknowns = (identity,),
    )
    initial = PottsInitialState(ownership = LabelledCells([1 0; 2 2]; cells = [cell, cell], medium))
    solution = solve(PottsProblem(source, initial, (0, 1); seed = 17), algorithm; backend, scalar_type = Float32)
    @test solution.retcode == SciMLBase.ReturnCode.Success
    expected = domain_kind === :cell ? Float32[1, 2] : reshape(Float32[1, 2, 3, 4], 2, 2)
    return @test Array(solution.u[end][:identity]) == expected
end

function _scoped_import_contract(algorithm, backend)
    @variables shared[1:2]
    kind = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source_anchor = CellBinding(:source, cells(kind))
    source_state = CellState(shared; initial = SVector(1.0, 2.0), retirement = RetireTo(SVector(0.0, 0.0)), scope = source_anchor)
    function consumer(name, reverse_components)
        @variables incoming[1:2] result[1:2]
        expression = reverse_components ? SVector(incoming[2], incoming[1]) : incoming
        return PottsSystem(
            name = name,
            statements = scoped(cells(kind), :reader) do cell
                StatementSet(
                    (
                        CellState(result; initial = SVector(0.0, 0.0), retirement = RetireTo(SVector(0.0, 0.0))),
                        Synchronous(:read, Assign(result, expression)),
                    )
                )
            end,
            imports = (incoming => ComponentReference((), source_state),),
            unknowns = (result,),
        )
    end
    source = PottsSystem(
        name = :shared_population,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 2), kind, medium, source_state,
                Synchronous(:advance, Assign(shared, SVector(shared[1] + 1, shared[2] + 2)); anchor = source_anchor),
                ProposalConstraint(:fixed, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (shared,), systems = (consumer(:copy, false), consumer(:reverse, true)),
    )
    initial = PottsInitialState(ownership = LabelledCells([1 1; 1 2]; cells = [kind, kind], medium))
    integrator = init(PottsProblem(source, initial, (0, 2); seed = 17), algorithm; backend, scalar_type = Float32)
    for boundary in 1:2
        step!(integrator)
        # Both imports observe the same declared source at boundary entry,
        # including when that source also changes in this transaction.
        @test Array(integrator.u[:shared]) == fill(SVector(Float32(boundary + 1), Float32(2 * (boundary + 1))), 2)
        @test Array(integrator.u[:copy₊result]) == fill(SVector(Float32(boundary), Float32(2 * boundary)), 2)
        @test Array(integrator.u[:reverse₊result]) == fill(SVector(Float32(2 * boundary), Float32(boundary)), 2)
    end
    return
end
