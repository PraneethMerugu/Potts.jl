"""
    NativeComponent(source; name, family, time, scope=Global(),
                    cadence=EveryMCS(), split=CPMThenComponents(),
                    inputs=(), outputs=(), initialization=PreserveNativeInitialization(),
                    events=PreserveNativeEvents(), lifecycle=GlobalNativeLifecycle(),
                    algorithm=LateBoundNativeAlgorithm(),
                    capabilities=StandardNativeCapability())

Declare a native ModelingToolkit component without translating it into Potts
equations. `Global()` stores one state for the trajectory; `PerCell()` stores
one state for every live finite Potts cell. `source` is retained by identity.
Its hierarchy, defaults, initialization equations, observations, and events
remain under ModelingToolkit ownership.
"""
struct NativeComponent{
        S <: ModelingToolkitBase.AbstractSystem,
        F <: AbstractNativeComponentFamily,
        SC <: AbstractNativeComponentScope,
        TP <: AbstractNativeTimePolicy,
        C <: AbstractCadence,
        SP <: AbstractNativeSplitPolicy,
        I <: Tuple,
        O <: Tuple,
        IP <: AbstractNativeInitializationPolicy,
        EP <: AbstractNativeEventPolicy,
        LP <: AbstractNativeLifecyclePolicy,
        AP <: AbstractNativeAlgorithmPolicy,
        CP <: AbstractNativeCapabilityPolicy,
    }
    name::Symbol
    source::S
    family::F
    scope::SC
    time::TP
    cadence::C
    split::SP
    inputs::I
    outputs::O
    initialization::IP
    events::EP
    lifecycle::LP
    algorithm::AP
    capabilities::CP

    function NativeComponent(
            ::_NativeConstructionToken,
            name::Symbol,
            source::S,
            family::F,
            scope::SC,
            time::TP,
            cadence::C,
            split::SP,
            inputs::I,
            outputs::O,
            initialization::IP,
            events::EP,
            lifecycle::LP,
            algorithm::AP,
            capabilities::CP,
        ) where {
            S <: ModelingToolkitBase.AbstractSystem,
            F <: AbstractNativeComponentFamily,
            SC <: AbstractNativeComponentScope,
            TP <: AbstractNativeTimePolicy,
            C <: AbstractCadence,
            SP <: AbstractNativeSplitPolicy,
            I <: Tuple,
            O <: Tuple,
            IP <: AbstractNativeInitializationPolicy,
            EP <: AbstractNativeEventPolicy,
            LP <: AbstractNativeLifecyclePolicy,
            AP <: AbstractNativeAlgorithmPolicy,
            CP <: AbstractNativeCapabilityPolicy,
        }
        return new{S, F, SC, TP, C, SP, I, O, IP, EP, LP, AP, CP}(
            name,
            source,
            family,
            scope,
            time,
            cadence,
            split,
            inputs,
            outputs,
            initialization,
            events,
            lifecycle,
            algorithm,
            capabilities,
        )
    end
end

function NativeComponent(
        source::ModelingToolkitBase.AbstractSystem;
        name,
        family::AbstractNativeComponentFamily,
        time::AbstractNativeTimePolicy,
        scope::AbstractNativeComponentScope = Global(),
        cadence::AbstractCadence = EveryMCS(),
        split::AbstractNativeSplitPolicy = CPMThenComponents(),
        inputs = (),
        outputs = (),
        initialization::AbstractNativeInitializationPolicy =
            PreserveNativeInitialization(),
        events::AbstractNativeEventPolicy = PreserveNativeEvents(),
        lifecycle::AbstractNativeLifecyclePolicy = GlobalNativeLifecycle(),
        algorithm::AbstractNativeAlgorithmPolicy = LateBoundNativeAlgorithm(),
        capabilities::AbstractNativeCapabilityPolicy =
            StandardNativeCapability(),
    )
    name isa Symbol || throw(ArgumentError(
        "NativeComponent requires a Symbol `name`"
    ))
    isempty(String(name)) && throw(ArgumentError(
        "NativeComponent name cannot be empty"
    ))
    scope isa Union{Global, PerCell} || throw(ArgumentError(
        "native component scope must be Global() or PerCell()"
    ))
    time isa FixedPhysicalTime || throw(ArgumentError(
            "native components require FixedPhysicalTime"
    ))
    split isa CPMThenComponents || throw(ArgumentError(
            "native components currently admit only the CPMThenComponents split"
    ))
    cadence isa Union{EveryMCS, Every} || throw(ArgumentError(
        "native component cadence must be EveryMCS() or Every(n)"
    ))
    initialization isa PreserveNativeInitialization || throw(ArgumentError(
            "native components require PreserveNativeInitialization()"
    ))
    events isa PreserveNativeEvents || throw(ArgumentError(
            "native components require PreserveNativeEvents()"
    ))
    if scope isa Global
        lifecycle isa GlobalNativeLifecycle || throw(ArgumentError(
            "Global native components require GlobalNativeLifecycle()"
        ))
    else
        lifecycle isa PerCellNativeLifecycle || throw(ArgumentError(
            "PerCell native components require an explicit PerCellNativeLifecycle"
        ))
    end
    algorithm isa LateBoundNativeAlgorithm || throw(ArgumentError(
        "native numerical algorithms must remain late-bound"
    ))
    capabilities isa Union{
        StandardNativeCapability, _MethodOfLinesNativeCapability,
    } || throw(ArgumentError(
        "native execution requires a package-owned late capability policy"
    ))
    input_ports = _native_port_tuple(inputs, NativeInput, "inputs")
    output_ports = _native_port_tuple(
        outputs, Union{NativeOutput, NativeFieldOutput}, "outputs"
    )
    _validate_native_ports(input_ports, output_ports)
    _validate_native_scope_ports(scope, input_ports, output_ports)
    return NativeComponent(
        _NATIVE_CONSTRUCTION_TOKEN,
        name,
        source,
        family,
        scope,
        time,
        cadence,
        split,
        input_ports,
        output_ports,
        initialization,
        events,
        lifecycle,
        algorithm,
        capabilities,
    )
end

function _validate_native_scope_ports(scope::Global, inputs::Tuple, outputs::Tuple)
    all(port -> potts_endpoint(port) isa ModelState, inputs) ||
        throw(ArgumentError("Global native inputs must target ModelState declarations"))
    all(port -> port isa NativeFieldOutput ||
        potts_endpoint(port) isa ModelState, outputs) || throw(ArgumentError(
        "Global native outputs must target ModelState or use NativeFieldOutput"
    ))
    return nothing
end

function _validate_native_scope_ports(scope::PerCell, inputs::Tuple, outputs::Tuple)
    all(port -> potts_endpoint(port) isa Union{ModelState, CellState}, inputs) ||
        throw(ArgumentError(
            "PerCell native inputs must target ModelState or CellState declarations"
        ))
    all(port -> potts_endpoint(port) isa CellState, outputs) ||
        throw(ArgumentError(
            "PerCell native outputs must target CellState declarations"
        ))
    return nothing
end

function _native_port_tuple(values, ::Type{P}, label::AbstractString) where {P}
    tuple = values isa P ? (values,) : try
        Tuple(values)
    catch
        throw(ArgumentError("NativeComponent $label must be an iterable of $P"))
    end
    all(value -> value isa P, tuple) || throw(ArgumentError(
        "NativeComponent $label must contain only $P values"
    ))
    return tuple
end

function _validate_native_ports(inputs::Tuple, outputs::Tuple)
    _assert_unique_native_values(inputs, "input")
    _assert_unique_native_values(outputs, "output")
    for input in inputs, output in outputs
        isempty(intersect(
            collect(native_variables(input)), collect(native_variables(output))
        )) || throw(ArgumentError(
            "an MTK symbolic value cannot be both a NativeInput and NativeOutput"
        ))
    end
    for (index, output) in pairs(outputs), prior in Iterators.take(outputs, index - 1)
        isequal(potts_endpoint(output), potts_endpoint(prior)) || continue
        throw(ArgumentError(
            "a Potts endpoint may have only one NativeOutput writer"
        ))
    end
    return nothing
end

function _assert_unique_native_values(ports::Tuple, label::AbstractString)
    for (index, port) in pairs(ports), prior in Iterators.take(ports, index - 1)
        isempty(intersect(
            collect(native_variables(port)), collect(native_variables(prior))
        )) || throw(ArgumentError("duplicate native $label symbolic value"))
    end
    return nothing
end

"""Return the original ModelingToolkit source system."""
native_source(component::NativeComponent) = getfield(component, :source)
"""Return the declared `ODEComponent` or `DAEComponent` family."""
native_family(component::NativeComponent) = getfield(component, :family)
"""Return the component's ordered native input ports."""
native_inputs(component::NativeComponent) = getfield(component, :inputs)
"""Return the component's ordered native output ports."""
native_outputs(component::NativeComponent) = getfield(component, :outputs)
Base.nameof(component::NativeComponent) = getfield(component, :name)

function _rebuild_native_component(
        component::NativeComponent;
        name = nameof(component),
        inputs = native_inputs(component),
        outputs = native_outputs(component),
    )
    return NativeComponent(
        native_source(component);
        name,
        family = getfield(component, :family),
        scope = getfield(component, :scope),
        time = getfield(component, :time),
        cadence = getfield(component, :cadence),
        split = getfield(component, :split),
        inputs,
        outputs,
        initialization = getfield(component, :initialization),
        events = getfield(component, :events),
        lifecycle = getfield(component, :lifecycle),
        algorithm = getfield(component, :algorithm),
        capabilities = getfield(component, :capabilities),
    )
end

function _map_native_potts_endpoints(f, component::NativeComponent; name = nameof(component))
    inputs = Tuple(
        NativeInput(native_variable(port), f(potts_endpoint(port)), native_value_type(port))
        for port in native_inputs(component)
    )
    outputs = Tuple(
        port isa NativeFieldOutput ? NativeFieldOutput(
            reshape(collect(native_variables(port)), getfield(port, :shape)),
            f(potts_endpoint(port));
            coordinates = getfield(port, :coordinates),
            value_type = native_value_type(port),
        ) : NativeOutput(
            native_variable(port), f(potts_endpoint(port)), native_value_type(port)
        )
        for port in native_outputs(component)
    )
    return _rebuild_native_component(component; name, inputs, outputs)
end

native_time_at(component::NativeComponent, completed_mcs::Integer) =
    native_time_at(getfield(component, :time), completed_mcs)

"""Return the positive MCS cadence stride of a native component."""
function native_cadence_stride(component::NativeComponent)
    cadence = getfield(component, :cadence)
    cadence isa EveryMCS && return 1
    return Int(getfield(cadence, :cadence))
end

"""Test whether a native component is due at an MCS boundary."""
function native_due(component::NativeComponent, completed_mcs::Integer)
    completed_mcs >= 0 || throw(ArgumentError(
        "completed MCS must be nonnegative"
    ))
    completed_mcs == 0 && return false
    return mod(completed_mcs, native_cadence_stride(component)) == 0
end

"""Return the physical interval ending at a due completed-MCS boundary."""
function native_time_interval(component::NativeComponent, completed_mcs::Integer)
    native_due(component, completed_mcs) || throw(ArgumentError(
        "native component $(repr(component.name)) is not due at MCS $completed_mcs"
    ))
    stride = native_cadence_stride(component)
    clock = getfield(component, :time)
    return (
        native_time_at(clock, completed_mcs - stride),
        native_time_at(clock, completed_mcs),
    )
end

function _assert_single_native_writers(endpoints)
    outputs = filter(endpoint ->
        endpoint.port isa Union{NativeOutput, NativeFieldOutput}, endpoints)
    for (index, endpoint) in pairs(outputs), prior in Iterators.take(outputs, index - 1)
        isequal(potts_endpoint(endpoint), potts_endpoint(prior)) || continue
        throw(ArgumentError(
            "Potts coupling endpoint has multiple native writers at " *
            "$(prior.component_path) and $(endpoint.component_path)"
        ))
    end
    return nothing
end

