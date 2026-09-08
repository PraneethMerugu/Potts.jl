@testset "component reconnections retain system-initial field dimensions" begin
    @variables memory::NamedTuple{(:amount,), Tuple{Float64}}
    @variables replacement_memory::NamedTuple{(:amount,), Tuple{Float64}}
    @variables incoming::NamedTuple{(:amount,), Tuple{Float64}}
    original_state = ModelState(memory)
    replacement_state = ModelState(replacement_memory)
    reference_units = ReferenceUnits(length = 1.0u"m", time = 1.0u"s")
    original_reference = ComponentReference((:producer,), original_state)
    producer = PottsSystem(
        name = :producer, statements = StatementSet(original_state),
        unknowns = (memory,), initial_conditions = Dict(memory => (amount = 2.0u"m",)),
    )
    reader = PottsSystem(
        name = :reader, imports = (incoming => original_reference,), outputs = (incoming,),
    )
    source = PottsSystem(
        name = :root,
        statements = StatementSet(
            (
                Lattice((2, 2); spacing = (1.0u"m", 1.0u"m")),
                Protocol(Sweep(; temperature = 0.0); name = :main, duration_per_mcs = 1.0u"s"),
            )
        ),
        systems = (producer, reader),
    )
    function reconnect(value; references = reference_units)
        replacement = PottsSystem(
            name = :producer, statements = StatementSet(replacement_state),
            unknowns = (replacement_memory,),
            initial_conditions = Dict(replacement_memory => (amount = value,)),
        )
        return replace_component(
            source, (:producer,) => replacement;
            reconnect = (original_reference => ComponentReference((:producer,), replacement_state),),
            reference_units = references,
        )
    end
    compatible = complete(reconnect(3.0u"m"); reference_units)
    values = ModelingToolkitBase.initial_conditions(compatible)
    @test values[ModelingToolkitBase.renamespace(:producer, replacement_memory)] == (amount = 3.0u"m",)
    @test_throws r"incompatible declaration contracts" reconnect(3.0u"s")
    @test_throws r"missing reference-unit anchor" reconnect(3.0u"m"; references = DeclaredReferenceUnits())
    @test_throws r"missing reference-unit anchor" reconnect(3.0u"m"; references = ReferenceUnits(time = 1.0u"s"))
    @test_throws r"missing reference-unit anchor" reconnect(3.0u"s"; references = ReferenceUnits(length = 1.0u"m"))
end
