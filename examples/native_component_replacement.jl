module NativeComponentReplacementExample

using Potts
using Symbolics
using ModelingToolkitBase: @independent_variables, @named, Differential
import ModelingToolkit

"""A native accumulator consumes a shared Potts state through an explicit alias."""
function accumulator(name, variable, input; gain = 1.0)
    @independent_variables t
    @variables x(t) = 0.0 drive(t)
    @named equations = ModelingToolkit.System([Differential(t)(x) ~ gain * drive], t)
    @variables incoming
    input_port = ModelState(incoming; initial = 0.0)
    state = ModelState(variable; initial = 0.0)
    native = NativeComponent(
        equations;
        name = :ode,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (NativeInput(drive, input_port; value_type = Float64),),
        outputs = (NativeOutput(x, state; value_type = Float64),),
    )
    source = PottsSystem(
        name = name,
        statements = StatementSet(state),
        native_components = (native,),
        imports = (incoming => input,),
        outputs = (variable,),
    )
    return (; source, state, native, equations, x, drive)
end

"""Two native instances share one held state; a third reads the first output."""
function shared_input_model()
    @variables forcing amount total
    forcing_state = ModelState(forcing; initial = 2.0)
    input = ComponentReference((), forcing_state)
    left = accumulator(:left, amount, input)
    right = accumulator(:right, amount, input; gain = 3.0)
    reader = accumulator(:reader, total, ComponentReference((:left,), left.state))
    source = PottsSystem(
        name = :native_shared,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()),
                CellKind(:cell; extinction = RetireAtZero()),
                MediumKind(:medium),
                forcing_state,
                ProposalConstraint(:freeze, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        systems = (left.source, right.source, reader.source),
    )
    return (; source, forcing_state, left, right, reader)
end

"""Replace owned native equations and reconnect the surviving reader explicitly."""
function replaced_input_model()
    original = shared_input_model()
    @variables response
    replacement = accumulator(
        :left, response, ComponentReference((), original.forcing_state); gain = 5.0
    )
    replaced = replace_component(
        original.source, (:left,) => replacement.source;
        reconnect = (
            ComponentReference((:left,), original.left.state) =>
                ComponentReference((:left,), replacement.state),
        ),
    )
    return (; original, replacement, replaced)
end

end
