@testset "model authoring construction-only macro contract" begin
    function referenced_names!(names::Set{Symbol}, value)
        if value isa GlobalRef
            push!(names, value.name)
        elseif value isa DataType
            push!(names, nameof(value))
        elseif value isa Symbol
            push!(names, value)
        elseif value isa Expr
            foreach(argument -> referenced_names!(names, argument), value.args)
        elseif value isa QuoteNode
            referenced_names!(names, value.value)
        end
        return names
    end

    expansions = (
        rule = macroexpand(@__MODULE__, :(
            PottsToolkit.@rule phase = phase_probe() probe(cell) = probe(cell) + 1.0f0)),
        rules = macroexpand(@__MODULE__, :(
            PottsToolkit.@rules phase = phase_probe() begin
                probe(cell) = probe(cell) + 1.0f0
            end)),
        trigger = macroexpand(@__MODULE__, :(
            PottsToolkit.@trigger ready(cell) = probe(cell) >= 1.0f0)),
    )

    referenced = map(expansions) do expansion
        referenced_names!(Set{Symbol}(), expansion)
    end
    @test Set((:Rule, :ScalarCall, :AddOperation, :_rule_reference,
        :OwnerReference, :RuleLiteral, :SourceLocation)) ⊆ referenced.rule
    @test Set((:RuleGroup, :Rule, :ScalarCall, :SourceLocation)) ⊆ referenced.rules
    @test Set((:TriggerRule, :ScalarCall, :GreaterEqualOperation,
        :SourceLocation)) ⊆ referenced.trigger

    engine_operations = Set((
        :solve, :solve!, :init, :step!, :lower, :problem,
        :compile, :launch!, :synchronize, :adapt,
    ))
    @test all(isempty(intersect(names, engine_operations)) for names in referenced)

    expansion_observations = Ref(0)
    phase_probe = () -> begin
        expansion_observations[] += 1
        PottsToolkit.Phase(:must_not_run_during_expansion)
    end
    macroexpand(@__MODULE__, :(
        PottsToolkit.@rule phase = phase_probe() probe(cell) = probe(cell) + 1.0f0))
    @test expansion_observations[] == 0
end

@testset "model authoring closed scalar parser inventory" begin
    cell = PottsToolkit.CellType(:scalar_inventory_cell)
    medium = PottsToolkit.Medium(:scalar_inventory_medium)
    signal = PottsToolkit.CellProperty(:scalar_inventory_signal, cell;
        initial = 0.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    phase = PottsToolkit.Phase(:scalar_inventory)

    inventory = PottsToolkit.@rule phase = phase signal(owner) =
        if signal(owner) >= 2.0f0 && !(signal(owner) == 3.0f0)
            clamp(max(abs(-signal(owner)), sqrt(4.0f0)), 0.0f0, 10.0f0) +
            exp(0.0f0) + log(1.0f0) + sin(0.0f0) + cos(0.0f0) + tan(0.0f0)
        else
            ifelse(signal(owner) != 0.0f0,
                min(signal(owner)^2 / 2.0f0, 5.0f0), 0.0f0)
        end

    @test PottsToolkit.evaluate(inventory, (scalar_inventory_signal = 2.0f0,)) == 4.0f0
    @test PottsToolkit.evaluate(inventory, (scalar_inventory_signal = 3.0f0,)) == 4.5f0
    @test Base.isvalid(PottsToolkit.PottsModel(medium, cell, signal, inventory))

    @test_throws ArgumentError macroexpand(@__MODULE__, :(
        PottsToolkit.@rule phase = phase signal(owner) = rand()))
    @test_throws ArgumentError macroexpand(@__MODULE__, :(
        PottsToolkit.@rule phase = phase signal(owner) = signal[owner]))
    @test_throws ArgumentError macroexpand(@__MODULE__, :(
        PottsToolkit.@rule phase = phase signal(owner) = while true
            signal(owner)
        end))
end
