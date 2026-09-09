using Potts: anchor_value

@testset "scope names remain reversible qualified identities" begin
    names = (:population, Symbol("λ₊膜"), Symbol("outer₊__potts_scoped_cell__inner"))
    kind = CellKind(:cell; extinction = RetireAtZero())
    lattice = LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(), max_cells = 2)
    for name in names
        @test CellBinding(name).name === name
        @test SiteBinding(name).name === name
        @test CellBinding(name, cells(kind)).name === name
        @test SiteBinding(name, sites(lattice)).name === name
        function component(component_name)
            @variables signal
            declarations = scoped(cells(kind), name) do anchor
                StatementSet(
                    (
                        CellState(signal; initial = 0.0, retirement = RetireTo(0.0)),
                        Synchronous(:identity, Assign(signal, anchor_value(anchor))),
                    )
                )
            end
            PottsSystem(name = component_name, statements = StatementSet((kind, declarations...)), unknowns = (signal,))
        end
        completed = complete(PottsSystem(name = :root, systems = (component(:first), component(Symbol("prefix__potts_scoped_cell__component")))))
        records = Potts._completion_data(completed).source_graph.records
        bindings = [Potts._record_options(record).scope for record in records if record.kind === :CellState]
        @test all(binding -> binding.name === name, bindings)
        @test !isequal(anchor_value(bindings[1]), anchor_value(bindings[2]))
    end
end

@testset "reserved substrings do not classify unrelated quantities as anchors" begin
    for name in (Symbol("ordinary__potts_scoped_cell__quantity"), Symbol("__potts_scoped_site__quantity"))
        quantity = Symbolics.variable(name)
        source = PottsSystem(
            name = Symbol("component__potts_scoped_cell__text"),
            statements = StatementSet((ModelState(quantity; initial = 1.0), Synchronous(:increment, Assign(quantity, quantity + 1)))),
            unknowns = (quantity,),
        )
        completed = complete(source)
        effects = inspect(completed, Effects())
        @test only(filter(item -> item[1].local_id == Potts.StatementID(:increment), effects))[3].basis === :per_invocation
    end
end
