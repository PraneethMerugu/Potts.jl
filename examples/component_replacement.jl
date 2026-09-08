module ComponentReplacementExample

using Potts
using Symbolics
using ModelingToolkitBase: @parameters

function accumulator(name, variable, input; gain = 1.0)
    @variables incoming
    state = ModelState(variable; initial = 0.0)
    source = PottsSystem(
        name = name,
        statements = StatementSet(
            (
                state,
                Synchronous(:advance, Assign(variable, variable + gain * incoming)),
            )
        ),
        imports = (incoming => input,),
        outputs = (variable,),
    )
    return (; source, state)
end

"""Two independently owned accumulators consume one root-owned parameter."""
function shared_input_model()
    @parameters forcing = 2.0
    @variables amount
    shared = ComponentReference((), forcing)
    left = accumulator(:left, amount, shared)
    right = accumulator(:right, amount, shared; gain = 3.0)
    source = PottsSystem(
        name = :shared_input,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Periodic()),
                CellKind(:cell; extinction = RetireAtZero()),
                MediumKind(:medium),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        parameters = (forcing,),
        systems = (left.source, right.source),
    )
    return (; source, forcing, left, right)
end

"""Replace an accumulator, retaining its shared input and reconnecting a reader."""
function replaced_input_model()
    original = shared_input_model()
    @variables total response
    old_output = ComponentReference((:left,), original.left.state)
    reader = accumulator(:reader, total, old_output)
    source = compose(original.source, [reader.source])
    replacement = accumulator(
        :left, response, ComponentReference((), original.forcing); gain = 5.0,
    )
    replaced = replace_component(
        source, (:left,) => replacement.source;
        reconnect = (old_output => ComponentReference((:left,), replacement.state),),
    )
    return (; source, replaced, forcing = original.forcing, replacement, reader)
end

end
