module PottsToolkitModelingToolkitExt

using PottsToolkit
import ModelingToolkit
import ModelingToolkitBase
import SHA
import SciMLBase
import SymbolicIndexingInterface
import Symbolics

_native_token(tag::AbstractString, value::AbstractString) =
    string(tag, ncodeunits(value), ':', value)

function _native_canonical_value(value)
    value === nothing && return "N"
    value === missing && return "M"
    if value isa Union{Bool, Integer, AbstractFloat, Symbol, AbstractString,
            VersionNumber, Enum}
        return _native_token(string(nameof(typeof(value)), ':'), repr(value))
    elseif value isa Module
        return _native_token("Module:", string(value))
    elseif value isa DataType
        return _native_token("DataType:", string(value))
    end
    symbolic = try
        !(SymbolicIndexingInterface.symbolic_type(value) isa
            SymbolicIndexingInterface.NotSymbolic)
    catch
        false
    end
    symbolic && return string(
        _native_token("SymbolicType:", string(typeof(value))),
        _native_token("Value:", string(value)),
    )
    if value isa Union{
            ModelingToolkitBase.SymbolicContinuousCallback,
            ModelingToolkitBase.SymbolicDiscreteCallback,
        }
        # Eventful native runtime is not admitted. Use the public display
        # representation for structural identity without reading callback
        # implementation fields.
        return string(
            _native_token("CallbackType:", string(typeof(value))),
            _native_token("Display:", repr(value)),
        )
    end
    if value isa NamedTuple
        fields = String[
            string(
                _native_token("Key:", String(key)),
                _native_canonical_value(getfield(value, key)),
            )
            for key in keys(value)
        ]
        return string(
            _native_token("NamedTupleType:", string(typeof(value))),
            _native_token("Fields:", join(fields)),
        )
    elseif value isa Tuple
        return string(
            _native_token("TupleType:", string(typeof(value))),
            _native_token("Items:", join(_native_canonical_value.(value))),
        )
    elseif value isa Pair
        return string(
            _native_token("PairType:", string(typeof(value))),
            _native_canonical_value(first(value)),
            _native_canonical_value(last(value)),
        )
    elseif value isa AbstractDict
        entries = sort!(String[
            string(
                _native_canonical_value(key),
                _native_canonical_value(item),
            )
            for (key, item) in pairs(value)
        ])
        return string(
            _native_token("DictType:", string(typeof(value))),
            _native_token("Entries:", join(entries)),
        )
    elseif value isa AbstractSet
        entries = sort!(_native_canonical_value.(collect(value)))
        return string(
            _native_token("SetType:", string(typeof(value))),
            _native_token("Entries:", join(entries)),
        )
    elseif value isa AbstractRange
        # Array axes are ranges whose own `axes` recurse to another equal
        # range. Encode their public sequence contract directly so canonical
        # array fingerprints cannot recurse indefinitely.
        endpoints = isempty(value) ? "Empty" : string(
            _native_token("First:", _native_canonical_value(first(value))),
            _native_token("Step:", _native_canonical_value(step(value))),
            _native_token("Last:", _native_canonical_value(last(value))),
        )
        return string(
            _native_token("RangeType:", string(typeof(value))),
            _native_token("Length:", string(length(value))),
            _native_token("Endpoints:", endpoints),
        )
    elseif value isa AbstractArray
        items = _native_canonical_value.(collect(value))
        return string(
            _native_token("ArrayType:", string(typeof(value))),
            _native_token("ElementType:", string(eltype(value))),
            _native_token("Axes:", _native_canonical_value(axes(value))),
            _native_token("Items:", join(items)),
        )
    elseif isstructtype(typeof(value))
        fields = String[
            string(
                _native_token("Field:", String(field)),
                _native_canonical_value(getfield(value, field)),
            )
            for field in fieldnames(typeof(value))
        ]
        return string(
            _native_token("StructType:", string(typeof(value))),
            _native_token("Fields:", join(fields)),
        )
    end
    return string(
        _native_token("OpaqueType:", string(typeof(value))),
        _native_token("Representation:", repr(value)),
    )
end

function _native_public_property(system, property::Symbol, default = nothing)
    has_property = getfield(ModelingToolkitBase, Symbol(:has_, property))
    has_property(system) || return default
    return getfield(ModelingToolkitBase, Symbol(:get_, property))(system)
end

function _native_nested_system_payload(value)
    value isa ModelingToolkitBase.AbstractSystem || return value
    return _native_system_fingerprint_payload(value)
end

function _native_system_fingerprint_payload(
        system; include_recursive_events::Bool = true
    )
    # These are the public SYS_PROPS that can affect standard ODE/DAE
    # construction, code generation, initialization, callbacks, observations,
    # or hierarchy. Deliberately omitted: the unique `tag`; presentation-only
    # GUI metadata; parent links; and derived/mutable caches (`schedule`,
    # `tearing_state`, `metadata`'s MutableCacheKey, `irstructure_tlv`,
    # `index_cache`, and `parameter_bindings_graph`). The exact upstream stack
    # is a separate capability-key dimension.
    return (
        type = typeof(system),
        equations = _native_public_property(system, :eqs, ()),
        noise_equations = _native_public_property(system, :noise_eqs),
        independent_variable = _native_public_property(system, :iv),
        independent_variables = _native_public_property(system, :ivs, ()),
        unknowns = _native_public_property(system, :unknowns, ()),
        dependent_variables = _native_public_property(system, :dvs, ()),
        parameters = _native_public_property(system, :ps, ()),
        source_tspan = _native_public_property(system, :tspan),
        brownians = _native_public_property(system, :brownians, ()),
        poissonians = _native_public_property(system, :poissonians, ()),
        jumps = _native_public_property(system, :jumps, ()),
        name = _native_public_property(system, :name, nameof(system)),
        description = _native_public_property(system, :description, ""),
        variable_names = _native_public_property(system, :var_to_name, ()),
        bindings = _native_public_property(system, :bindings, ()),
        initial_conditions =
            _native_public_property(system, :initial_conditions, ()),
        guesses = _native_public_property(system, :guesses, ()),
        observed = _native_public_property(system, :observed, ()),
        constraints = _native_public_property(system, :constraints, ()),
        boundary_conditions = _native_public_property(system, :bcs, ()),
        domain = _native_public_property(system, :domain),
        connector_type = _native_public_property(system, :connector_type),
        preface = _native_public_property(system, :preface),
        initialization_system = _native_nested_system_payload(
            _native_public_property(system, :initializesystem)
        ),
        initialization_equations =
            _native_public_property(system, :initialization_eqs, ()),
        is_initialization_system =
            _native_public_property(system, :is_initializesystem, false),
        is_discrete = _native_public_property(system, :is_discrete, false),
        state_priorities =
            _native_public_property(system, :state_priorities, ()),
        irreducibles = _native_public_property(system, :irreducibles, ()),
        maybe_zeros = _native_public_property(system, :maybe_zeros, ()),
        assertions = _native_public_property(system, :assertions, ()),
        ignored_connections =
            _native_public_property(system, :ignored_connections),
        is_dde = _native_public_property(system, :is_dde, false),
        tstops = _native_public_property(system, :tstops, ()),
        inputs = _native_public_property(system, :inputs, ()),
        outputs = _native_public_property(system, :outputs, ()),
        is_scheduled = _native_public_property(system, :isscheduled, false),
        costs = _native_public_property(system, :costs, ()),
        consolidate = _native_public_property(system, :consolidate),
        analytically_integrated =
            _native_public_property(system, :analytically_integrated, ()),
        continuous_events = include_recursive_events ?
            ModelingToolkitBase.continuous_events(system) : (),
        discrete_events = include_recursive_events ?
            ModelingToolkitBase.discrete_events(system) : (),
        systems = Tuple(
            _native_system_fingerprint_payload(
                child; include_recursive_events = false
            )
            for child in ModelingToolkitBase.get_systems(system)
        ),
    )
end

function _native_system_tree(system)
    result = Any[system]
    for child in ModelingToolkitBase.get_systems(system)
        append!(result, _native_system_tree(child))
    end
    return result
end

function _native_feature_nonempty(value)
    value === nothing && return false
    try
        return !isempty(value)
    catch
        return value !== false
    end
end

function _preflight_native_public_semantics(component, system)
    for node in _native_system_tree(system)
        checks = (
            (:noise_equations, _native_public_property(node, :noise_eqs)),
            (:poissonians, _native_public_property(node, :poissonians, ())),
            (:preface, _native_public_property(node, :preface)),
            (:constraints, _native_public_property(node, :constraints, ())),
            (:assertions, _native_public_property(node, :assertions, ())),
            (:tstops, _native_public_property(node, :tstops, ())),
            (:boundary_conditions, _native_public_property(node, :bcs, ())),
            (:domain, _native_public_property(node, :domain)),
            (:costs, _native_public_property(node, :costs, ())),
            (:ignored_connections,
                _native_public_property(node, :ignored_connections)),
        )
        for (capability, value) in checks
            _native_feature_nonempty(value) || continue
            throw(_path_error(
                component,
                capability,
                    "native ODE/DAE runtime profiles do not admit nonempty $capability",
            ))
        end
        _native_public_property(node, :is_initializesystem, false) &&
            throw(_path_error(
                component, :initialization_system,
                "an MTK initialization subsystem cannot be a native runtime root",
            ))
        _native_public_property(node, :is_discrete, false) &&
            throw(_path_error(
                component, :discrete_system,
                "native ODE/DAE runtime profiles admit continuous systems only",
            ))
        _native_public_property(node, :is_dde, false) &&
            throw(_path_error(
                component, :delay_system,
                "native ODE/DAE runtime profiles do not admit delay differential systems",
            ))
    end
    any(
        parameter -> SymbolicIndexingInterface.is_timeseries_parameter(
            system, parameter
        ),
        ModelingToolkitBase.parameters(system),
    ) && throw(_path_error(
        component,
        :discrete_parameters,
            "native ODE/DAE runtime profiles do not admit discrete/time-series parameters",
    ))
    return nothing
end

function PottsToolkit.native_source_fingerprint(
        source::ModelingToolkitBase.AbstractSystem
    )
    payload = string(
        _native_token("Schema:", "potts-native-source-v2"),
        _native_canonical_value(_native_system_fingerprint_payload(source)),
    )
    return PottsToolkit.NativeSourceFingerprint(
        bytes2hex(SHA.sha256(codeunits(payload)))
    )
end

function PottsToolkit.mtkcompile_native(
        component::PottsToolkit.CompletedNativeComponent; kwargs...
    )
    haskey(kwargs, :inputs) && throw(ArgumentError(
        "native component inputs are owned by its NativeInput declarations"
    ))
    haskey(kwargs, :outputs) && throw(ArgumentError(
        "native component outputs are owned by its NativeOutput declarations"
    ))
    declaration = component.declaration
    original = PottsToolkit.native_source(declaration)
    all(
        equation -> equation isa Symbolics.Equation,
        ModelingToolkitBase.equations(original),
    ) || throw(ArgumentError(
        "native domain systems with non-equation semantics require an explicit " *
        "conversion to a concrete MTK ODE/DAE System (for example " *
        "Catalyst.ode_model); PottsToolkit never chooses that interpretation",
    ))
    inputs = Any[
        PottsToolkit.native_variable(port)
        for port in PottsToolkit.native_inputs(declaration)
    ]
    outputs = Any[
        variable
        for port in PottsToolkit.native_outputs(declaration)
        for variable in PottsToolkit.native_variables(port)
    ]

    # Full ModelingToolkit owns every structural pass. PottsToolkit retains the
    # returned system and the original source; it does not reconstruct either.
    scheduled = ModelingToolkitBase.mtkcompile(
        original; inputs, outputs, kwargs...
    )
    scheduled_fingerprint = PottsToolkit.native_source_fingerprint(scheduled)
    return PottsToolkit.ScheduledNativeComponent(
        component.path,
        declaration,
        original,
        scheduled,
        component.endpoints,
        component.source_fingerprint,
        scheduled_fingerprint,
    )
end

struct NativeLogicalStateView{U, P, T}
    u::U
    p::P
    t::T
end

SymbolicIndexingInterface.state_values(view::NativeLogicalStateView) = view.u
SymbolicIndexingInterface.parameter_values(view::NativeLogicalStateView) = view.p
SymbolicIndexingInterface.current_time(view::NativeLogicalStateView) = view.t

function _path_error(component, capability, message)
    return PottsToolkit.NativeCapabilityError(
        PottsToolkit.native_component_path(component), capability, message
    )
end

function _require_native_logical_value(component, value, label)
    path = PottsToolkit.native_component_path(component)
    if value isa AbstractFloat
        isfinite(value) || throw(_path_error(
            component, :logical_checkpoint, "$label is nonfinite"
        ))
        return nothing
    elseif value isa Union{Bool, Integer, Symbol, AbstractString, Enum}
        return nothing
    elseif value isa Tuple || value isa NamedTuple
        foreach(item -> _require_native_logical_value(
            component, item, label
        ), values(value))
        return nothing
    elseif value isa AbstractArray
        isbitstype(eltype(value)) || throw(_path_error(
            component, :fixed_dimension_state,
            "$label has non-isbits element type $(eltype(value))",
        ))
        all(item -> !(item isa AbstractFloat) || isfinite(item), value) ||
            throw(_path_error(
                component, :logical_checkpoint, "$label is nonfinite"
            ))
        return nothing
    end
    throw(_path_error(
        component,
        :logical_checkpoint,
        "$label has mutable or opaque value type $(typeof(value))",
    ))
end

const _EXACT_TSIT5_PACKAGE_UUID = "b1df2697-797e-41e3-8120-5422d3b24e4a"
const _EXACT_TSIT5_PACKAGE_VERSION = v"2.1.2"
const _FUNCTIONAL_IDA_PACKAGE_UUID = "c3572dad-4567-51f8-b174-8c6c989267f4"
const _FUNCTIONAL_IDA_PACKAGE_VERSION = v"6.4.2"

function _package_identity(module_value)
    package = PottsToolkit._native_package_identity(module_value)
    return (
        package = package.name,
        uuid = package.uuid,
        version = package.version,
    )
end

const _TESTED_NATIVE_RUNTIME_STACK = (
    ModelingToolkit = (
        package = "ModelingToolkit",
        uuid = "961ee093-0014-501f-94e3-6117800e7a78",
        version = v"11.37.1",
    ),
    ModelingToolkitBase = (
        package = "ModelingToolkitBase",
        uuid = "7771a370-6774-4173-bd38-47e70ca0b839",
        version = v"1.58.1",
    ),
    SciMLBase = (
        package = "SciMLBase",
        uuid = "0bca4576-84f4-4d90-8ffe-ffa030f20462",
        version = v"3.39.1",
    ),
    SymbolicIndexingInterface = (
        package = "SymbolicIndexingInterface",
        uuid = "2efcf032-c050-4f8e-a9bb-153293bab1f5",
        version = v"0.3.51",
    ),
    Symbolics = (
        package = "Symbolics",
        uuid = "0c5d862f-8b57-4792-8d23-62f2024744c7",
        version = v"7.37.0",
    ),
    Julia = (
        version = v"1.12.1",
        kernel = :Darwin,
        architecture = :aarch64,
        word_size = 64,
        machine = "arm64-apple-darwin24.0.0",
    ),
)

function PottsToolkit._native_runtime_stack_identity(
        ::PottsToolkit.ScheduledNativeComponent
    )
    return (
        ModelingToolkit = _package_identity(ModelingToolkit),
        ModelingToolkitBase = _package_identity(ModelingToolkitBase),
        SciMLBase = _package_identity(SciMLBase),
        SymbolicIndexingInterface =
            _package_identity(SymbolicIndexingInterface),
        Symbolics = _package_identity(Symbolics),
        Julia = (
            version = VERSION,
            kernel = Sys.KERNEL,
            architecture = Sys.ARCH,
            word_size = Sys.WORD_SIZE,
            machine = Sys.MACHINE,
        ),
    )
end

function _is_public_default_algorithm_instance(algorithm)
    algorithm_type = typeof(algorithm)
    algorithm_module = parentmodule(algorithm_type)
    algorithm_name = nameof(algorithm_type)
    isdefined(algorithm_module, algorithm_name) || return false
    constructor = getfield(algorithm_module, algorithm_name)
    default = try
        constructor()
    catch
        return false
    end
    return typeof(default) === algorithm_type && isequal(algorithm, default)
end

const _AUDITED_SCALAR_OPERATIONS = (+, -, *, /, ^)

function _replay_safe_numeric_literal(value)
    return try
        Symbolics.value(value) isa Number
    catch
        false
    end
end

function _replay_safe_scalar_expression(value, known)
    unwrapped = Symbolics.unwrap(value)
    any(candidate -> isequal(unwrapped, Symbolics.unwrap(candidate)), known) &&
        return true
    Symbolics.iscall(unwrapped) || return _replay_safe_numeric_literal(unwrapped)
    operation = Symbolics.operation(unwrapped)
    operation isa ModelingToolkitBase.Differential ||
        any(candidate -> operation === candidate, _AUDITED_SCALAR_OPERATIONS) ||
        return false
    return all(
        argument -> _replay_safe_scalar_expression(argument, known),
        Symbolics.arguments(unwrapped),
    )
end

function _replay_safe_scalar_equation(equation, known; check_lhs::Bool = true)
    equation isa Symbolics.Equation || return false
    (!check_lhs || _replay_safe_scalar_expression(equation.lhs, known)) &&
        _replay_safe_scalar_expression(equation.rhs, known)
end

function _replay_safe_scalar_map(value, known)
    value === nothing && return true
    try
        return all(pair ->
            _replay_safe_scalar_expression(first(pair), known) &&
            _replay_safe_scalar_expression(last(pair), known),
            pairs(value),
        )
    catch
        return false
    end
end

function _replay_safe_native_lifecycle_map(component, expression)
    expression isa PottsToolkit.NativeLogicalState && return true
    system = PottsToolkit.native_scheduled_system(component)
    known = Any[
        ModelingToolkitBase.unknowns(system)...,
        ModelingToolkitBase.parameters(system)...,
        ModelingToolkitBase.independent_variables(system)...,
        ModelingToolkitBase.inputs(system)...,
        ModelingToolkitBase.outputs(system)...,
    ]
    declarations = expression isa Pair ? (expression,) : try
        Tuple(expression)
    catch
        return false
    end
    isempty(declarations) && return false
    all(pair -> pair isa Pair, declarations) || return false
    indices = Int[]
    for pair in declarations
        index = SymbolicIndexingInterface.variable_index(system, first(pair))
        index isa Integer || return false
        _replay_safe_scalar_expression(last(pair), known) || return false
        push!(indices, Int(index))
    end
    return length(unique(indices)) == length(indices)
end

function _replay_safe_native_lifecycle(component, lifecycle)
    lifecycle isa PottsToolkit.PerCellNativeLifecycle || return false
    lifecycle.creation isa Union{
        PottsToolkit.PreserveNativeInitialization, PottsToolkit.Unsupported,
    } || return false
    transition = lifecycle.transition
    transition_ok = transition isa Union{
        PottsToolkit.Preserve, PottsToolkit.Unsupported,
    } || transition isa PottsToolkit.ResetTo &&
        _replay_safe_native_lifecycle_map(component, transition.expression) ||
        transition isa PottsToolkit.Transform &&
        _replay_safe_native_lifecycle_map(component, transition.expression)
    transition_ok || return false
    division = lifecycle.division
    return division isa Union{
            PottsToolkit.CopyToDaughters, PottsToolkit.Unsupported,
        } || division isa PottsToolkit.SplitConservatively &&
            division.fraction isa Real && isfinite(division.fraction) &&
            0 <= division.fraction <= 1 ||
        division isa PottsToolkit.PreserveParentResetDaughter &&
            _replay_safe_native_lifecycle_map(component, division.expression) ||
        division isa PottsToolkit.ResetBoth &&
            _replay_safe_native_lifecycle_map(
                component, division.parent_expression
            ) && _replay_safe_native_lifecycle_map(
                component, division.daughter_expression
            ) ||
        division isa PottsToolkit.TransformDaughters &&
            _replay_safe_native_lifecycle_map(
                component, division.parent_expression
            ) && _replay_safe_native_lifecycle_map(
                component, division.daughter_expression
            )
end

function _replay_safe_explicit_native_ode(component)
    system = PottsToolkit.native_scheduled_system(component)
    ivs = ModelingToolkitBase.independent_variables(system)
    length(ivs) == 1 || return false
    unknowns = ModelingToolkitBase.unknowns(system)
    equations = ModelingToolkitBase.equations(system)
    !isempty(unknowns) && length(equations) == length(unknowns) || return false
    differential = ModelingToolkitBase.Differential(only(ivs))
    expected = differential.(unknowns)
    return all(lhs -> any(isequal(lhs), expected),
        (equation.lhs for equation in equations)) &&
        length(unique(equation.lhs for equation in equations)) ==
        length(equations)
end

function PottsToolkit._native_replay_schema(
        component::PottsToolkit.ScheduledNativeComponent
    )
    unreviewed = (family = :unreviewed, fingerprint = nothing)
    system = PottsToolkit.native_original_system(component)
    events = PottsToolkit._native_event_contract(component)
    events.runtime_policy === :event_free || return unreviewed
    for node in _native_system_tree(system)
        unsupported = (
            _native_public_property(node, :noise_eqs),
            _native_public_property(node, :poissonians, ()),
            _native_public_property(node, :preface),
            _native_public_property(node, :constraints, ()),
            _native_public_property(node, :assertions, ()),
            _native_public_property(node, :tstops, ()),
            _native_public_property(node, :bcs, ()),
            _native_public_property(node, :domain),
            _native_public_property(node, :costs, ()),
            _native_public_property(node, :initializesystem),
            _native_public_property(node, :ignored_connections),
        )
        all(value -> !_native_feature_nonempty(value), unsupported) ||
            return unreviewed
        _native_public_property(node, :is_discrete, false) && return unreviewed
        _native_public_property(node, :is_dde, false) && return unreviewed
    end
    known = Any[
        ModelingToolkitBase.unknowns(system)...,
        ModelingToolkitBase.parameters(system)...,
        ModelingToolkitBase.independent_variables(system)...,
        ModelingToolkitBase.inputs(system)...,
        ModelingToolkitBase.outputs(system)...,
    ]
    observed = ModelingToolkitBase.observed(system)
    append!(known, (equation.lhs for equation in observed))
    all(equation -> _replay_safe_scalar_equation(equation, known),
        ModelingToolkitBase.equations(system)) || return unreviewed
    all(equation -> _replay_safe_scalar_equation(
        equation, known; check_lhs = false
        ), observed) || return unreviewed
    all(equation -> _replay_safe_scalar_equation(equation, known),
        ModelingToolkitBase.initialization_equations(system)) ||
        return unreviewed
    _replay_safe_scalar_map(
        ModelingToolkitBase.initial_conditions(system), known
    ) ||
        return unreviewed
    _replay_safe_scalar_map(ModelingToolkitBase.guesses(system), known) ||
        return unreviewed
    schema_payload = (
        equations = ModelingToolkitBase.equations(system),
        observed,
        initialization_equations =
            ModelingToolkitBase.initialization_equations(system),
        unknowns = ModelingToolkitBase.unknowns(system),
        parameters = ModelingToolkitBase.parameters(system),
        independent_variables =
            ModelingToolkitBase.independent_variables(system),
        inputs = ModelingToolkitBase.inputs(system),
        outputs = ModelingToolkitBase.outputs(system),
    )
    return (
        family = :scalar_algebraic_differential_v1,
        fingerprint = bytes2hex(SHA.sha256(codeunits(
            _native_canonical_value(schema_payload)
        ))),
    )
end

function PottsToolkit._native_profile_evidence(
        component::PottsToolkit.ScheduledNativeComponent,
        profile::PottsToolkit.NativeSolveProfile,
    )
    if any(endpoint -> endpoint.port isa PottsToolkit.NativeFieldOutput,
            PottsToolkit.native_coupling_endpoints(component))
        return applicable(
            PottsToolkit._native_field_profile_evidence, component, profile
        ) ? PottsToolkit._native_field_profile_evidence(component, profile) : nothing
    end
    declaration = getfield(component, :declaration)
    family = PottsToolkit.native_family(declaration)
    events = PottsToolkit._native_event_contract(component)
    events.admitted || return nothing
    algorithm_type = typeof(profile.algorithm)
    algorithm_module = parentmodule(algorithm_type)
    package = PottsToolkit._native_package_identity(algorithm_module)
    version = package.version
    options_class = PottsToolkit._native_profile_options_class(profile)
    tested_stack = PottsToolkit._native_runtime_stack_identity(component) ==
        _TESTED_NATIVE_RUNTIME_STACK
    default_algorithm = _is_public_default_algorithm_instance(
        profile.algorithm
    )
    replay_schema = PottsToolkit._native_replay_schema(component)
    scope = getfield(declaration, :scope)
    lifecycle = getfield(declaration, :lifecycle)
    scope_qualified = scope isa PottsToolkit.Global ||
        scope isa PottsToolkit.PerCell &&
        _replay_safe_native_lifecycle(component, lifecycle)
    execution_qualified = profile.execution isa PottsToolkit.SerialNativeExecution ||
        scope isa PottsToolkit.PerCell &&
        profile.execution isa PottsToolkit.BatchedNativeExecution &&
        _replay_safe_explicit_native_ode(component)
    ode_replay_qualified = tested_stack && default_algorithm &&
        scope_qualified && execution_qualified &&
        replay_schema.family === :scalar_algebraic_differential_v1 &&
        profile.exact_replay && profile.deterministic &&
        family isa PottsToolkit.ODEComponent &&
        package.name == "OrdinaryDiffEqTsit5" &&
        package.uuid == _EXACT_TSIT5_PACKAGE_UUID &&
        version == _EXACT_TSIT5_PACKAGE_VERSION &&
        nameof(algorithm_type) === :Tsit5 &&
        options_class in (:fixed_step, :fixed_step_bounded_failure)
    ode_replay_qualified || return nothing
    suite = scope isa PottsToolkit.PerCell &&
            profile.execution isa PottsToolkit.BatchedNativeExecution ?
        :per_cell_batched_cpu_native_ode_exact_replay :
        scope isa PottsToolkit.PerCell ?
        :per_cell_serial_native_ode_exact_replay :
        options_class === :fixed_step_bounded_failure ?
        :native_failure_atomicity_exact :
        :native_ode_exact_replay
    evidence_fingerprint = PottsToolkit._sha256_hex(
        "native-runtime-evidence-v2",
        PottsToolkit._native_profile_fingerprint(profile),
        PottsToolkit.native_scheduled_fingerprint(component).hex,
        PottsToolkit._native_runtime_stack_identity(component),
        replay_schema,
        events,
        scope,
        lifecycle,
    )
    evidence = PottsToolkit._capability_evidence_identity(
        :PottsToolkit,
        suite,
        v"1.0.0",
        evidence_fingerprint,
    )
    return (
        status = PottsToolkit.CorePotts.BackendSPI.Supported,
        exact_replay = true,
        evidence,
    )
end

function PottsToolkit.preflight_native_component(
        component::PottsToolkit.ScheduledNativeComponent,
        point::PottsToolkit.NativeOperatingPoint,
        profile::PottsToolkit.NativeSolveProfile,
        initial_time,
    )
    path = PottsToolkit.native_component_path(component)
    point.path == path || throw(PottsToolkit.NativeProfileError(
        path, "operating-point path does not match the scheduled component"
    ))
    profile.path == path || throw(PottsToolkit.NativeProfileError(
        path, "solve-profile path does not match the scheduled component"
    ))
    initial_time isa Real && isfinite(initial_time) || throw(_path_error(
        component,
        :physical_time,
            "native runtime requires a finite scalar Real clock; quantity clocks are not yet admitted",
    ))
    declaration = getfield(component, :declaration)
    family = PottsToolkit.native_family(declaration)
    family isa Union{PottsToolkit.ODEComponent, PottsToolkit.DAEComponent} ||
        throw(_path_error(
            component, :problem_family,
            "only ODEComponent and DAEComponent use the native ODE/DAE runtime",
        ))
    execution = profile.execution
    execution isa Union{
        PottsToolkit.SerialNativeExecution,
        PottsToolkit.BatchedNativeExecution,
        PottsToolkit.MetalNativeExecution,
    } || throw(_path_error(
        component,
        :native_execution_mode,
        "unknown native execution mode $(typeof(execution))",
    ))
    if execution isa Union{
            PottsToolkit.BatchedNativeExecution,
            PottsToolkit.MetalNativeExecution,
        }
        getfield(declaration, :scope) isa PottsToolkit.PerCell ||
            execution isa PottsToolkit.MetalNativeExecution || throw(_path_error(
                component,
                :native_execution_mode,
                "BatchedNativeExecution requires a PerCell component",
            ))
        family isa PottsToolkit.ODEComponent || throw(_path_error(
            component,
            :native_execution_mode,
            "batched/Metal native execution admits only fixed-shape ODE components",
        ))
        _replay_safe_explicit_native_ode(component) || throw(_path_error(
            component,
            :native_execution_mode,
            "batched/Metal native execution requires an explicit identity-mass-matrix ODE with one retained differential equation per unknown",
        ))
        PottsToolkit._native_profile_options_class(profile) in (
            :fixed_step, :fixed_step_bounded_failure,
        ) || throw(_path_error(
            component,
            :native_execution_mode,
            "batched/Metal native execution requires adaptive=false and a positive fixed dt",
        ))
    end
    system = PottsToolkit.native_scheduled_system(component)
    isempty(ModelingToolkitBase.brownians(system)) || throw(_path_error(
        component, :problem_family, "SDE systems require a distinct adapter"
    ))
    isempty(ModelingToolkitBase.jumps(system)) || throw(_path_error(
        component, :problem_family,
        "jump and hybrid systems require an explicit semantic adapter",
    ))
    _preflight_native_public_semantics(component, system)
    events = PottsToolkit._native_event_contract(component)
    events.admitted || throw(_path_error(
        component,
        :native_events,
        events.reason,
    ))
    symbolic_values = (
        ModelingToolkitBase.unknowns(system)...,
        ModelingToolkitBase.parameters(system)...,
    )
    any(value -> value isa Symbolics.Arr, symbolic_values) &&
        throw(_path_error(
            component, :fixed_dimension_state,
            "dynamic or unscalarized array state is outside the native runtime profile",
        ))
    for endpoint in PottsToolkit.native_coupling_endpoints(component)
        variables = PottsToolkit.native_variables(endpoint.port)
        all(variable -> variable isa Symbolics.Num, variables) ||
            throw(_path_error(
                component, :typed_io,
                "native runtime profiles admit only scalar input/output symbols",
            ))
        for variable in variables
            try
                SymbolicIndexingInterface.getsym(system, variable)
            catch error
                throw(PottsToolkit.NativeExecutionError(
                    path, :symbolic_index_preflight, error
                ))
            end
        end
    end
    foreach(pair -> _require_native_logical_value(
        component, last(pair), "operating-point value"
    ), point.values)
    foreach(pair -> _require_native_logical_value(
        component, last(pair), "initialization guess"
    ), point.guesses)
    if profile.exact_replay
        evidence = PottsToolkit._native_profile_evidence(component, profile)
        (evidence === nothing || !evidence.exact_replay) &&
            throw(_path_error(
                component,
                :exact_replay_evidence,
                "the requested exact replay contract has no matching closed native evidence row",
            ))
    end
    return nothing
end

function _merge_pairs(groups...)
    result = Pair{Any, Any}[]
    for group in groups, pair in group
        index = findfirst(
            existing -> isequal(first(existing), first(pair)), result
        )
        copied = first(pair) => deepcopy(last(pair))
        if index === nothing
            push!(result, copied)
        else
            result[index] = copied
        end
    end
    return result
end

function _native_problem(
        component,
        operating_pairs,
        guesses,
        tspan;
        continuation::Bool,
    )
    system = PottsToolkit.native_scheduled_system(component)
    declaration = getfield(component, :declaration)
    kwargs = isempty(guesses) ? NamedTuple() : (; guesses = collect(guesses))
    continuation && (kwargs = merge(kwargs, (; build_initializeprob = false)))
    family = PottsToolkit.native_family(declaration)
    if family isa PottsToolkit.ODEComponent
        return SciMLBase.ODEProblem(
            system, collect(operating_pairs), tspan; kwargs...
        )
    elseif family isa PottsToolkit.DAEComponent
        return SciMLBase.DAEProblem(
            system, collect(operating_pairs), tspan; kwargs...
        )
    end
    throw(_path_error(
        component, :problem_family,
        "no standard native problem constructor is registered",
    ))
end

function _native_parameter_values(system, source)
    parameters = ModelingToolkitBase.parameters(system)
    isempty(parameters) && return ()
    values = SymbolicIndexingInterface.getp(system, parameters)(source)
    return Tuple(deepcopy(value) for value in values)
end

function _native_derivative_values(component, integrator)
    declaration = getfield(component, :declaration)
    PottsToolkit.native_family(declaration) isa PottsToolkit.DAEComponent ||
        return nothing
    values = SciMLBase.get_du(integrator)
    return Tuple(deepcopy(value) for value in values)
end

function _capture_native_state(component, integrator, retcode)
    return PottsToolkit.NativeLogicalState(
        PottsToolkit.native_component_path(component),
        Tuple(deepcopy(value) for value in
            SymbolicIndexingInterface.state_values(integrator)),
        _native_parameter_values(
            PottsToolkit.native_scheduled_system(component), integrator
        ),
        _native_derivative_values(component, integrator),
        SymbolicIndexingInterface.current_time(integrator),
        retcode,
    )
end

function PottsToolkit.initialize_native_component(
        component::PottsToolkit.ScheduledNativeComponent,
        point::PottsToolkit.NativeOperatingPoint,
        profile::PottsToolkit.NativeSolveProfile,
        inputs::Tuple,
        initial_time,
    )
    PottsToolkit.preflight_native_component(
        component, point, profile, initial_time
    )
    return PottsToolkit._initialize_preflighted_native_component(
        component, point, profile, inputs, initial_time
    )
end

function PottsToolkit._initialize_preflighted_native_component(
        component::PottsToolkit.ScheduledNativeComponent,
        point::PottsToolkit.NativeOperatingPoint,
        profile::PottsToolkit.NativeSolveProfile,
        inputs::Tuple,
        initial_time,
    )
    declaration = getfield(component, :declaration)
    stride = PottsToolkit.native_cadence_stride(declaration)
    clock = getfield(declaration, :time)
    terminal_time = initial_time + stride * getfield(clock, :duration_per_mcs)
    operating = _merge_pairs(point.values, inputs)
    problem = _native_problem(
        component,
        operating,
        point.guesses,
        (initial_time, terminal_time);
        continuation = false,
    )
    solve_options = if PottsToolkit.native_family(
            getfield(component, :declaration)
        ) isa PottsToolkit.DAEComponent
        merge(profile.options, (; initializealg = SciMLBase.OverrideInit()))
    else
        profile.options
    end
    integrator = SciMLBase.init(
        problem, profile.algorithm; solve_options...
    )
    reached = SymbolicIndexingInterface.current_time(integrator)
    reached == initial_time || throw(_path_error(
        component, :initialization,
        "standard native init changed physical time from $initial_time to $reached",
    ))
    return _capture_native_state(
        component, integrator, SciMLBase.ReturnCode.Default
    )
end

function PottsToolkit._native_initial_problem(
        component::PottsToolkit.ScheduledNativeComponent,
        point::PottsToolkit.NativeOperatingPoint,
        inputs::Tuple,
        initial_time,
    )
    declaration = getfield(component, :declaration)
    stride = PottsToolkit.native_cadence_stride(declaration)
    clock = getfield(declaration, :time)
    terminal_time = initial_time + stride * getfield(clock, :duration_per_mcs)
    return _native_problem(
        component,
        _merge_pairs(point.values, inputs),
        point.guesses,
        (initial_time, terminal_time);
        continuation = false,
    )
end

function _continuation_operating_pairs(component, state, inputs)
    system = PottsToolkit.native_scheduled_system(component)
    unknowns = ModelingToolkitBase.unknowns(system)
    parameters = ModelingToolkitBase.parameters(system)
    length(unknowns) == length(state.u) || throw(_path_error(
        component, :fixed_dimension_state,
        "scheduled unknown count changed since the last logical boundary",
    ))
    length(parameters) == length(state.p) || throw(_path_error(
        component, :fixed_dimension_state,
        "scheduled parameter count changed since the last logical boundary",
    ))
    state_pairs = Pair{Any, Any}[
        unknowns .=> state.u;
        parameters .=> state.p;
    ]
    declaration = getfield(component, :declaration)
    if PottsToolkit.native_family(declaration) isa PottsToolkit.DAEComponent
        state.du === nothing && throw(_path_error(
            component, :dae_derivative_state,
            "DAE continuation requires a stored derivative vector",
        ))
        length(state.du) == length(unknowns) || throw(_path_error(
            component, :dae_derivative_state,
            "stored DAE derivative width does not match scheduled unknowns",
        ))
        ivs = ModelingToolkitBase.independent_variables(system)
        length(ivs) == 1 || throw(_path_error(
            component, :physical_time,
            "native differential systems require one independent variable",
        ))
        differential = ModelingToolkitBase.Differential(only(ivs))
        append!(state_pairs, differential.(unknowns) .=> state.du)
    end
    return _merge_pairs(state_pairs, inputs)
end

function PottsToolkit._native_continuation_problem(
        component::PottsToolkit.ScheduledNativeComponent,
        state::PottsToolkit.NativeLogicalState,
        inputs::Tuple,
        target_time,
    )
    operating = _continuation_operating_pairs(component, state, inputs)
    return _native_problem(
        component,
        operating,
        (),
        (state.t, target_time);
        continuation = true,
    )
end

function PottsToolkit._native_logical_from_problem_solution(
        component::PottsToolkit.ScheduledNativeComponent,
        problem,
        final_state,
        reached,
        retcode,
    )
    view = NativeLogicalStateView(final_state, problem.p, reached)
    return PottsToolkit.NativeLogicalState(
        PottsToolkit.native_component_path(component),
        Tuple(deepcopy(value) for value in final_state),
        _native_parameter_values(
            PottsToolkit.native_scheduled_system(component), view
        ),
        nothing,
        reached,
        retcode,
    )
end

function PottsToolkit.advance_native_component(
        component::PottsToolkit.ScheduledNativeComponent,
        state::PottsToolkit.NativeLogicalState,
        profile::PottsToolkit.NativeSolveProfile,
        inputs::Tuple,
        target_time,
    )
    path = PottsToolkit.native_component_path(component)
    state.path == path || throw(PottsToolkit.NativeProfileError(
        path, "logical-state path does not match scheduled component"
    ))
    profile.path == path || throw(PottsToolkit.NativeProfileError(
        path, "solve-profile path does not match scheduled component"
    ))
    state.t < target_time || throw(_path_error(
        component, :physical_time,
        "native target time $target_time must follow logical time $(state.t)",
    ))
    problem = PottsToolkit._native_continuation_problem(
        component, state, inputs, target_time
    )
    integrator = SciMLBase.init(
        problem, profile.algorithm; profile.options...
    )
    solution = SciMLBase.solve!(integrator)
    retcode = solution.retcode
    reached = SymbolicIndexingInterface.current_time(integrator)
    accepted_retcode = retcode === SciMLBase.ReturnCode.Success ||
                       (retcode === SciMLBase.ReturnCode.Terminated &&
                        reached == target_time)
    accepted_retcode && reached == target_time ||
        throw(PottsToolkit.NativeSolveFailure(
            path, retcode, reached, target_time
        ))
    return _capture_native_state(component, integrator, retcode)
end

struct NativeBatchedODEFunction{F}
    lane_function::F
    state_width::Int
end

function (function_value::NativeBatchedODEFunction)(du, u, parameters, time)
    width = function_value.state_width
    @inbounds for lane in eachindex(parameters)
        first_index = (lane - 1) * width + 1
        last_index = first_index + width - 1
        du_lane = @view du[first_index:last_index]
        u_lane = @view u[first_index:last_index]
        function_value.lane_function(
            du_lane, u_lane, parameters[lane], time
        )
    end
    return nothing
end

function PottsToolkit._advance_native_cell_batch(
        component::PottsToolkit.ScheduledNativeComponent,
        lanes::AbstractVector,
        profile::PottsToolkit.NativeSolveProfile,
        target_time,
    )
    profile.execution isa PottsToolkit.BatchedNativeExecution ||
        throw(_path_error(
            component,
            :native_execution_mode,
            "the batched lane entry point requires BatchedNativeExecution",
        ))
    isempty(lanes) && return PottsToolkit.NativeLogicalState[]
    lane_problems = map(lanes) do lane
        operating = _continuation_operating_pairs(
            component, lane.state, lane.inputs
        )
        _native_problem(
            component,
            operating,
            (),
            (lane.state.t, target_time);
            continuation = true,
        )
    end
    reference = first(lane_problems)
    SciMLBase.isinplace(reference) || throw(_path_error(
        component,
        :native_execution_mode,
        "BatchedNativeExecution requires an in-place ODE function",
    ))
    mass_matrix = reference.f.mass_matrix
    identity_mass_matrix = try
        mass_matrix == one(mass_matrix)
    catch
        false
    end
    identity_mass_matrix || throw(_path_error(
            component,
            :native_execution_mode,
            "BatchedNativeExecution cannot discard a nonidentity ODE mass matrix",
        ))
    state_width = length(reference.u0)
    state_width > 0 || throw(_path_error(
        component,
        :native_execution_mode,
        "BatchedNativeExecution requires a nonempty fixed-shape state",
    ))
    all(problem ->
        SciMLBase.isinplace(problem) &&
        typeof(problem.f) === typeof(reference.f) &&
        length(problem.u0) == state_width &&
        eltype(problem.u0) === eltype(reference.u0),
        lane_problems,
    ) || throw(_path_error(
        component,
        :native_execution_mode,
        "batched lanes do not share one fixed in-place ODE schema",
    ))
    parameter_type = typeof(reference.p)
    all(problem -> typeof(problem.p) === parameter_type, lane_problems) ||
        throw(_path_error(
            component,
            :native_execution_mode,
            "batched lanes do not share one fixed parameter-buffer schema",
        ))
    parameters = parameter_type[problem.p for problem in lane_problems]
    initial = Vector{eltype(reference.u0)}(
        undef, state_width * length(lanes)
    )
    for (lane, problem) in enumerate(lane_problems)
        first_index = (lane - 1) * state_width + 1
        copyto!(initial, first_index, problem.u0, 1, state_width)
    end
    batched_function = NativeBatchedODEFunction(reference.f, state_width)
    problem = SciMLBase.ODEProblem(
        batched_function,
        initial,
        (first(lanes).state.t, target_time),
        parameters,
    )
    integrator = SciMLBase.init(
        problem, profile.algorithm; profile.options...
    )
    solution = SciMLBase.solve!(integrator)
    retcode = solution.retcode
    reached = SymbolicIndexingInterface.current_time(integrator)
    retcode === SciMLBase.ReturnCode.Success && reached == target_time ||
        throw(PottsToolkit.NativeSolveFailure(
            PottsToolkit.native_component_path(component),
            retcode,
            reached,
            target_time,
        ))
    system = PottsToolkit.native_scheduled_system(component)
    final = SymbolicIndexingInterface.state_values(integrator)
    state_type = typeof(first(lanes).state)
    results = Vector{state_type}(undef, length(lanes))
    for lane in eachindex(lanes)
        first_index = (lane - 1) * state_width + 1
        last_index = first_index + state_width - 1
        lane_problem = lane_problems[lane]
        parameter_view = NativeLogicalStateView(
            lane_problem.u0, lane_problem.p, reached
        )
        results[lane] = PottsToolkit.NativeLogicalState(
            PottsToolkit.native_component_path(component),
            Tuple(deepcopy(final[index]) for index in first_index:last_index),
            _native_parameter_values(system, parameter_view),
            nothing,
            reached,
            retcode,
        )
    end
    return results
end

function _native_parameter_buffer(component, state)
    system = PottsToolkit.native_scheduled_system(component)
    parameters = ModelingToolkitBase.parameters(system)
    length(parameters) == length(state.p) || throw(_path_error(
        component, :fixed_dimension_state,
        "logical parameter width does not match the scheduled system",
    ))
    return ModelingToolkitBase.MTKParameters(
        system, parameters .=> state.p
    )
end

function PottsToolkit.native_state_view(
        component::PottsToolkit.ScheduledNativeComponent,
        state::PottsToolkit.NativeLogicalState,
    )
    state.path == PottsToolkit.native_component_path(component) ||
        throw(ArgumentError("native state and component paths do not match"))
    return NativeLogicalStateView(
        state.u, _native_parameter_buffer(component, state), state.t
    )
end

function PottsToolkit.native_component_value(
        component::PottsToolkit.ScheduledNativeComponent,
        state::PottsToolkit.NativeLogicalState,
        symbolic,
    )
    system = PottsToolkit.native_scheduled_system(component)
    getter = SymbolicIndexingInterface.getsym(system, symbolic)
    return getter(PottsToolkit.native_state_view(component, state))
end

struct NativeLifecycleAssignment{G}
    index::Int
    getter::G
end

struct NativeLifecycleStateTransform{C, A}
    component::C
    assignments::A
end

struct PreserveNativeLifecycleState end

(::PreserveNativeLifecycleState)(state, _event) = state

function (transform::NativeLifecycleStateTransform)(state, _event)
    state.path == PottsToolkit.native_component_path(transform.component) ||
        throw(ArgumentError("native lifecycle state path does not match its component"))
    view = PottsToolkit.native_state_view(transform.component, state)
    # Every right-hand side observes the same pre-event state. This gives a
    # declarative map simultaneous-assignment semantics.
    values = map(assignment -> assignment.getter(view), transform.assignments)
    unknowns = collect(state.u)
    for (assignment, value) in zip(transform.assignments, values)
        prior = unknowns[assignment.index]
        converted = try
            convert(typeof(prior), value)
        catch error
            throw(ArgumentError(
                "native lifecycle expression for unknown $(assignment.index) " *
                "cannot convert $(typeof(value)) to $(typeof(prior)): " *
                sprint(showerror, error)
            ))
        end
        converted isa AbstractFloat && !isfinite(converted) &&
            throw(ArgumentError("native lifecycle expression produced a nonfinite value"))
        unknowns[assignment.index] = deepcopy(converted)
    end
    return PottsToolkit.NativeLogicalState(
        state.path,
        Tuple(unknowns),
        state.p,
        state.du,
        state.t,
        state.retcode,
    )
end

function _native_lifecycle_pairs(component, expression, label)
    pairs = expression isa Pair ? (expression,) : try
        Tuple(expression)
    catch
        throw(_path_error(
            component,
            :native_lifecycle,
            "$label requires a Pair or tuple of `native_unknown => expression` pairs",
        ))
    end
    !isempty(pairs) || throw(_path_error(
        component, :native_lifecycle,
        "$label cannot be empty; use Preserve() for an explicit no-op",
    ))
    all(pair -> pair isa Pair, pairs) || throw(_path_error(
        component, :native_lifecycle,
        "$label must contain only `native_unknown => expression` pairs",
    ))
    return pairs
end

function _compile_native_lifecycle_transform(component, expression, label)
    system = PottsToolkit.native_scheduled_system(component)
    assignments = map(_native_lifecycle_pairs(component, expression, label)) do pair
        target, value = pair
        index = SymbolicIndexingInterface.variable_index(system, target)
        index isa Integer || throw(_path_error(
            component,
            :native_lifecycle,
            "$label target $(repr(target)) is not a retained native unknown",
        ))
        getter = try
            SymbolicIndexingInterface.getsym(system, value)
        catch error
            throw(PottsToolkit.NativeExecutionError(
                PottsToolkit.native_component_path(component),
                :lifecycle_symbolic_compilation,
                error,
            ))
        end
        NativeLifecycleAssignment(Int(index), getter)
    end
    indices = Tuple(assignment.index for assignment in assignments)
    length(unique(indices)) == length(indices) || throw(_path_error(
        component, :native_lifecycle,
        "$label assigns the same native unknown more than once",
    ))
    return NativeLifecycleStateTransform(component, assignments)
end

function PottsToolkit._lower_native_cell_state_policy(
        component::PottsToolkit.ScheduledNativeComponent,
        template::PottsToolkit.NativeLogicalState,
        capacity::Integer,
    )
    declaration = getfield(component, :declaration)
    lifecycle = getfield(declaration, :lifecycle)
    lifecycle isa PottsToolkit.PerCellNativeLifecycle || throw(_path_error(
        component, :native_lifecycle,
        "a PerCell native component requires PerCellNativeLifecycle",
    ))

    creation = lifecycle.creation isa PottsToolkit.PreserveNativeInitialization ?
        PottsToolkit._NativePreparedCreationAction(
            Union{Nothing, typeof(template)}[nothing for _ in 1:capacity]
        ) : PottsToolkit._NativeUnsupportedAction(:creation)

    transition = if lifecycle.transition isa PottsToolkit.Preserve
        PottsToolkit._NativePreserveAction()
    elseif lifecycle.transition isa PottsToolkit.Unsupported
        PottsToolkit._NativeUnsupportedAction(:transition)
    elseif lifecycle.transition isa PottsToolkit.ResetTo
        expression = lifecycle.transition.expression
        expression isa PottsToolkit.NativeLogicalState ?
            PottsToolkit._NativeResetAction(expression) :
            PottsToolkit._NativeTransformAction(
                _compile_native_lifecycle_transform(
                    component, expression, "ResetTo transition"
                )
            )
    elseif lifecycle.transition isa PottsToolkit.Transform
        expression = lifecycle.transition.expression
        applicable(expression, template, nothing) ?
            PottsToolkit._NativeTransformAction(expression) :
            PottsToolkit._NativeTransformAction(
                _compile_native_lifecycle_transform(
                    component, expression, "Transform transition"
                )
            )
    else
        error("validated native transition policy reached an unknown lowering branch")
    end

    division = if lifecycle.division isa PottsToolkit.CopyToDaughters
        PottsToolkit._NativeCopyDaughtersAction()
    elseif lifecycle.division isa PottsToolkit.Unsupported
        PottsToolkit._NativeUnsupportedAction(:division)
    elseif lifecycle.division isa PottsToolkit.SplitConservatively
        fraction = lifecycle.division.fraction
        fraction isa Real && isfinite(fraction) && 0 <= fraction <= 1 ||
            throw(_path_error(
                component, :native_lifecycle,
                "SplitConservatively fraction must be finite and in [0, 1]",
            ))
        PottsToolkit._NativeSplitDaughtersAction(fraction)
    elseif lifecycle.division isa PottsToolkit.PreserveParentResetDaughter
        expression = lifecycle.division.expression
        if expression isa PottsToolkit.NativeLogicalState
            PottsToolkit._NativeParentResetDaughterAction(expression)
        else
            PottsToolkit._NativeTransformDaughtersAction(
                PreserveNativeLifecycleState(),
                _compile_native_lifecycle_transform(
                    component, expression,
                    "PreserveParentResetDaughter daughter",
                ),
            )
        end
    elseif lifecycle.division isa PottsToolkit.ResetBoth
        parent = lifecycle.division.parent_expression
        daughter = lifecycle.division.daughter_expression
        if parent isa PottsToolkit.NativeLogicalState &&
                daughter isa PottsToolkit.NativeLogicalState
            PottsToolkit._NativeResetDaughtersAction(parent, daughter)
        else
            PottsToolkit._NativeTransformDaughtersAction(
                _compile_native_lifecycle_transform(
                    component, parent, "ResetBoth parent"
                ),
                _compile_native_lifecycle_transform(
                    component, daughter, "ResetBoth daughter"
                ),
            )
        end
    elseif lifecycle.division isa PottsToolkit.TransformDaughters
        parent = lifecycle.division.parent_expression
        daughter = lifecycle.division.daughter_expression
        parent_transform = applicable(parent, template, nothing) ? parent :
            _compile_native_lifecycle_transform(
                component, parent, "TransformDaughters parent"
            )
        daughter_transform = applicable(daughter, template, nothing) ? daughter :
            _compile_native_lifecycle_transform(
                component, daughter, "TransformDaughters daughter"
            )
        PottsToolkit._NativeTransformDaughtersAction(
            parent_transform, daughter_transform
        )
    else
        error("validated native division policy reached an unknown lowering branch")
    end
    return PottsToolkit.NativeCellStatePolicy(
        template; creation, transition, division
    )
end

end
