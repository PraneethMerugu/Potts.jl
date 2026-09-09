@testset "statement assembly preserves declared ownership and parameter dependencies" begin
    @variables amount unused_state misspelled
    @parameters base = 2.0 gain = base unused_parameter = 9.0
    declarations = @statements begin
        ModelState(amount; initial = base)
        ModelState(unused_state; initial = 0.0)
        Synchronous(:advance, Assign(amount, amount + gain))
        Observation(:recorded_amount, amount)
    end
    assembled = PottsSystem(declarations; name = :assembled, parameters = (unused_parameter,))
    @test isequal(unknowns(assembled), [amount, unused_state])
    @test isequal(parameters(assembled), [unused_parameter, base, gain])
    @test length(statements(assembled)) == length(declarations)
    explicit = PottsSystem(
        name = :assembled, statements = declarations,
        unknowns = (amount, unused_state), parameters = (unused_parameter, base, gain),
    )
    @test isequal(unknowns(complete(assembled)), unknowns(complete(explicit)))
    @test isequal(parameters(complete(assembled)), parameters(complete(explicit)))
    invalid = PottsSystem(
        StatementSet((ModelState(amount; initial = 0.0), Synchronous(:typo, Assign(misspelled, 1.0))));
        name = :invalid,
    )
    @test isequal(unknowns(invalid), [amount])
    @test isempty(parameters(invalid))
    @test_throws Potts.PottsValidationError complete(invalid)
end

@testset "assembly discovers whole and indexed parameter arrays without scalarizing ownership" begin
    @parameters weights[1:2] offset = 2.0 initial_only = 4.0 observed_only = 5.0 index::Int = 1
    @variables amount vector[1:2] observation
    source = PottsSystem(
        StatementSet(
            (
                ModelState(amount; initial = 0.0), ModelState(vector; initial = [0.0, 0.0]),
                Synchronous(:scalar_update, Assign(amount, weights[index] + offset)),
                Synchronous(:vector_update, Assign(vector, weights)),
            )
        );
        name = :array_parameters,
        initial_conditions = Dict(amount => initial_only),
        observed = (observation ~ amount + observed_only,),
    )
    @test count(value -> isequal(Symbolics.unwrap(value), Symbolics.unwrap(weights)), parameters(source)) == 1
    @test length(parameters(source)) == 5
    @test any(isequal(index), parameters(source))
    @test any(isequal(initial_only), parameters(source))
    @test any(isequal(observed_only), parameters(source))
    collected = Potts._collect_symbolics((values = [offset, 7.0], nested = (weights,)))
    @test length(collected) == 2
end

@testset "assembled imported parameter resolves through the owning parent" begin
    @parameters forcing = 2.0 incoming = 9.0
    @variables amount
    child = PottsSystem(
        StatementSet((ModelState(amount; initial = 0.0), Synchronous(:advance, Assign(amount, amount + incoming))));
        name = :child, imports = (incoming => ComponentReference((), forcing),),
    )
    completed = complete(PottsSystem(name = :parent, parameters = (forcing,), systems = (child,)))
    @test isequal(parameters(completed), [forcing])
    @test length(unknowns(completed)) == 1

    @parameters aliases[1:2]
    indexed_child = PottsSystem(
        StatementSet((ModelState(amount; initial = 0.0), Synchronous(:advance, Assign(amount, amount + aliases[1]))));
        name = :indexed_child, imports = (aliases[1] => ComponentReference((), forcing),),
    )
    @test isempty(parameters(indexed_child))
    indexed_completed = complete(PottsSystem(name = :parent, parameters = (forcing,), systems = (indexed_child,)))
    @test isequal(parameters(indexed_completed), [forcing])
end

@testset "assembly follows declared defaults and preserves imported parameter ownership" begin
    @parameters root = 3.0 middle = root leaf = middle imported = 1.0
    @variables amount
    declarations = StatementSet(
        (
            ModelState(amount; initial = 0.0),
            Synchronous(:advance, Assign(amount, leaf + imported)),
        )
    )
    source = PottsSystem(
        declarations; name = :child,
        imports = (imported => ComponentReference((), root),),
    )
    @test isequal(parameters(source), [leaf, middle, root])
    @test !any(isequal(imported), parameters(source))
    # An imported alias cannot also become an owned state merely by enrollment.
    conflicting = PottsSystem(
        StatementSet(ModelState(imported; initial = 0.0)); name = :child,
        imports = (imported => ComponentReference((), root),),
    )
    @test_throws ArgumentError complete(PottsSystem(name = :parent, parameters = (root,), systems = (conflicting,)))
end

@testset "assembly retains whole structured state references" begin
    @variables vector[1:2] tensor[1:2, 1:2]
    declarations = StatementSet((ModelState(vector; initial = [1.0, 2.0]), ModelState(tensor; initial = [1.0 0.0; 0.0 1.0])))
    source = PottsSystem(declarations; name = :structured)
    @test length(unknowns(source)) == 2
    @test isequal(only(filter(value -> size(value) == (2,), unknowns(source))), vector)
    @test isequal(only(filter(value -> size(value) == (2, 2), unknowns(source))), tensor)
end
