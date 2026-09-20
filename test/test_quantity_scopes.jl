include("fixtures/scoped_quantities.jl")

@testset "scoped quantities preserve deterministic component identity" begin
    first = complete(_scope_population(:first, 2.0))
    equivalent = complete(_scope_population(:first, 2.0))
    explicit = complete(_scope_population(:first, 2.0; explicit = true))
    # Declaration content and ordinary normalized expressions, not object identity.
    @test Potts._completion_data(first).fingerprints == Potts._completion_data(equivalent).fingerprints
    @test inspect(first, Effects()) == inspect(explicit, Effects())
    @test only(filter(item -> item[1].local_id == Potts.StatementID(:turn), inspect(first, Effects())))[3].basis === :per_cell
    root = complete(PottsSystem(name = :root, systems = (_scope_population(:first, 2.0), _scope_population(:second, 3.0))))
    records = Potts._completion_data(root).source_graph.records
    bindings = [Potts._record_options(record).scope for record in records if record.kind === :CellState]
    @test !isequal(anchor_value(bindings[1]), anchor_value(bindings[2]))
    @test all(binding -> binding.name === :population, bindings)
end

@testset "scope declarations and lexical anchor captures validate before lowering" begin
    @variables x y
    first = CellKind(:first; extinction = RetireAtZero())
    second = CellKind(:second; extinction = RetireAtZero())
    outer = CellBinding(:outer, cells(first))
    inner = CellBinding(:inner, cells(first))
    function model_with(states, process = ())
        PottsSystem(name = :scope_contract, statements = StatementSet((first, second, states..., process...)), unknowns = (x, y))
    end
    states = (
        CellState(x; initial = 1.0, retirement = RetireTo(0.0), scope = outer),
        CellState(y; initial = 2.0, retirement = RetireTo(0.0), scope = inner),
    )
    @test complete(model_with(states)) isa PottsSystem # unused declarations retain their scope
    @test complete(model_with(states, (Synchronous(:swap, Assign(x, y), Assign(y, x); anchor = inner),))) isa PottsSystem
    @test_throws r"outside its lexical scope" complete(model_with(states, (Synchronous(:captured, Assign(y, anchor_value(outer)); anchor = inner),)))
    orphan = CellBinding(:undeclared_context, cells(first))
    @test_throws r"unresolved_symbolic_leaf" complete(model_with(states, (Synchronous(:orphan, Assign(x, anchor_value(orphan)); anchor = outer),)))
    @variables unbound
    @test_throws r"unresolved_symbolic_leaf" complete(model_with(states, (Synchronous(:unbound, Assign(x, unbound); anchor = outer),)))
    @test complete(model_with(states, (Synchronous(:bound, Assign(y, anchor_value(inner)); anchor = inner),))) isa PottsSystem
    @test_throws r"target quantities" complete(model_with(states, (Synchronous(:wrong, Assign(x, x); domain = cells(second)),)))
    conflicting = CellBinding(:outer, cells(second))
    @test_throws r"conflicting domains" complete(model_with((states[1], CellState(y; initial = 1.0, retirement = RetireTo(0.0), scope = conflicting))))
    missing = CellBinding(:missing, cells(CellKind(:absent)))
    @test_throws r"no declared CellKind" complete(model_with((CellState(x; initial = 1.0, retirement = RetireTo(0.0), scope = missing),)))
    @test_throws r"different population" complete(
        model_with(
            (
                CellState(x; initial = 1.0, retirement = RetireTo(0.0)),
                CellState(y; initial = 1.0, retirement = RetireTo(0.0), scope = CellBinding(:foreign, cells(second))),
            ), (Synchronous(:foreign_read, Assign(x, y); domain = cells(first)),)
        )
    )
    @test_throws r"CellState or ModelState reads" complete(
        model_with(
            (states[1], SiteState(y; initial = 1.0)),
            (Synchronous(:site_read, Assign(x, y)),)
        )
    )
    @test_throws r"target iteration domain" complete(
        model_with(
            (ModelState(x; initial = 0.0),),
            (Synchronous(:singleton, Assign(x, x + 1); anchor = inner),)
        )
    )
    wrong_kind = Potts.QualifiedStatementID((:scope_contract,), Potts.StatementID(:y))
    wrong_scope = CellBinding(:wrong_kind, cells(wrong_kind))
    @test_throws r"no declared CellKind" complete(
        model_with(
            (
                CellState(x; initial = 1.0, retirement = RetireTo(0.0), scope = wrong_scope),
                SiteState(y; initial = 1.0),
            )
        )
    )
end

@testset "imported structured quantities keep their declaring scope" begin
    @variables source_vector[1:2] incoming[1:2] result_vector[1:2]
    kind = CellKind(:cell; extinction = RetireAtZero())
    source_anchor = CellBinding(:source, cells(kind))
    source_state = CellState(source_vector; initial = SVector(1.0, 2.0), retirement = RetireTo(SVector(0.0, 0.0)), scope = source_anchor)
    consumer = PottsSystem(
        name = :consumer,
        statements = scoped(cells(kind), :reader) do cell
            StatementSet(
                (
                    CellState(result_vector; initial = SVector(0.0, 0.0), retirement = RetireTo(SVector(0.0, 0.0))),
                    Synchronous(:read, Assign(result_vector, incoming)),
                )
            )
        end,
        imports = (incoming => ComponentReference((), source_state),), unknowns = (result_vector,),
    )
    source = PottsSystem(name = :imports, statements = StatementSet((kind, source_state)), unknowns = (source_vector,), systems = (consumer,))
    completed = complete(source)
    @test length(unknowns(completed)) == 2
    records = Potts._completion_data(completed).source_graph.records
    @test count(record -> record.kind === :CellState, records) == 2
    @test !any(variable -> isequal(variable, incoming), unknowns(completed))
end

@testset "two scoped populations and site process execute their own quantities" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        _scoped_population_contract(algorithm, CPUBackend())
    end
end

@testset "scoped consumers share one changing imported structured quantity" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        @testset "$algorithm" begin
            _scoped_import_contract(algorithm, CPUBackend())
        end
    end
end
