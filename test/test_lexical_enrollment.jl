module UnrelatedDeclarationMacros
    macro parameters(arguments...)
        return :(42)
    end
end

@testset "lexical system enrollment retains unused declarations and evaluates once" begin
    visits = Symbol[]
    recorded_default() = (push!(visits, :default); 2.0)
    source = @statements PottsSystem(; name = (push!(visits, :keyword); :lexical), parameters = (gain,)) begin
        @parameters base = recorded_default() gain = base unused = 9.0
        @variables amount unused_state
        ModelState(amount; initial = base)
        ModelState(unused_state; initial = 0.0)
        Synchronous(:advance, Assign(amount, amount + gain))
    end
    @test visits == [:default, :keyword]
    @test isequal(parameters(source), [gain, base, unused])
    @test isequal(unknowns(source), [amount, unused_state])
    explicit = PottsSystem(
        name = :lexical, parameters = (gain, base, unused), unknowns = (amount, unused_state),
        statements = StatementSet(
            (
                ModelState(amount; initial = base), ModelState(unused_state; initial = 0.0),
                Synchronous(:advance, Assign(amount, amount + gain)),
            )
        ),
    )
    @test isequal(parameters(complete(source)), parameters(complete(explicit)))
    @test isequal(unknowns(complete(source)), unknowns(complete(explicit)))
    @test all(statement -> statement_source(statement) isa SourceLocation, statements(source))
end

@testset "qualified declaration macros retain whole arrays and imported ownership" begin
    @parameters forcing = 3.0
    child = @statements PottsSystem(; name = :child, imports = (incoming => ComponentReference((), forcing),)) begin
        ModelingToolkitBase.@parameters incoming = 1.0 weights[1:2]
        Symbolics.@variables vector[1:2]
        ModelState(vector; initial = [0.0, 0.0])
        Synchronous(:update, Assign(vector, vector + weights))
    end
    @test length(parameters(child)) == 1
    @test isequal(only(parameters(child)), weights)
    @test isequal(only(unknowns(child)), vector)
    parent = complete(PottsSystem(; name = :parent, parameters = (forcing,), systems = (child,)))
    @test length(unknowns(parent)) == 1
    @test length(parameters(parent)) == 2
    @test_throws ArgumentError @statements PottsSystem(; name = :not_a_declaration) begin
        UnrelatedDeclarationMacros.@parameters impostor
    end
end

@testset "lexical inventories do not invent physical state or hide duplicate declarations" begin
    missing = @statements PottsSystem(; name = :missing_state) begin
        @variables amount
        Synchronous(:advance, Assign(amount, 1.0))
    end
    @test isequal(unknowns(missing), [amount])
    @test_throws r"Assign must target one declared state" mtkcompile(complete(missing))
    duplicate = @statements PottsSystem(; name = :duplicate) begin
        @variables amount
        ModelState(amount; initial = 0.0)
        ModelState(amount; initial = 0.0)
    end
    @test_throws Potts.PottsValidationError complete(duplicate)
    alias_entry = @statements PottsSystem(; name = :duplicate_alias) begin
        @variables amount
        declaration = ModelState(amount; initial = 0.0)
        declaration
    end
    @test_throws Potts.PottsValidationError complete(alias_entry)
    source = @statements PottsSystem(; name = :independent, independent_variables = (time,)) begin
        @variables time amount
        ModelState(amount; initial = 0.0)
    end
    @test isequal(unknowns(source), [amount])
end
