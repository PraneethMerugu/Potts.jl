module PottsToolkitMethodOfLinesExt

using PottsToolkit
using MethodOfLines
using ModelingToolkit

import SciMLBase

function _mol_error(message)
    return ArgumentError("MethodOfLinesComponent: " * message)
end

function PottsToolkit.MethodOfLinesComponent(
        pde_system,
        discretization::MethodOfLines.MOLFiniteDifference,
        dependent,
        field::PottsToolkit.FieldState;
        spatial,
        name,
        time::PottsToolkit.FixedPhysicalTime,
        value_type::Type = Float64,
        cadence::PottsToolkit.AbstractCadence = PottsToolkit.EveryMCS(),
    )
    spatial_axes = Tuple(spatial)
    isempty(spatial_axes) && throw(_mol_error(
        "spatial must list the PDE coordinates in Potts lattice order"
    ))
    discrete = MethodOfLines.get_discrete(pde_system, discretization)
    haskey(discrete, dependent) || throw(_mol_error(
        "dependent does not identify a scalarized MethodOfLines variable grid"
    ))
    all(axis -> haskey(discrete, axis), spatial_axes) || throw(_mol_error(
        "every spatial coordinate must be present in the discretized grid"
    ))
    variables = discrete[dependent]
    variables isa AbstractArray || throw(_mol_error(
        "the selected dependent variable does not discretize to an array"
    ))
    coordinates = Tuple(discrete[axis] for axis in spatial_axes)
    size(variables) == Tuple(length(axis) for axis in coordinates) ||
        throw(_mol_error(
            "the dependent-variable grid does not match the ordered coordinate axes"
        ))

    discretized, tspan = SciMLBase.symbolic_discretize(
        pde_system, discretization
    )
    tspan === nothing && throw(_mol_error(
        "time-independent PDE discretizations are not an ODE field component"
    ))
    output = PottsToolkit.NativeFieldOutput(
        variables,
        field;
        coordinates,
        value_type,
    )
    return PottsToolkit.NativeComponent(
        discretized;
        name,
        family = PottsToolkit.ODEComponent(),
        scope = PottsToolkit.Global(),
        time,
        cadence,
        outputs = (output,),
        capabilities = PottsToolkit._MethodOfLinesNativeCapability(),
    )
end

function PottsToolkit._native_field_profile_evidence(
        component::PottsToolkit.ScheduledNativeComponent,
        profile::PottsToolkit.NativeSolveProfile,
    )
    declaration = getfield(component, :declaration)
    getfield(declaration, :capabilities) isa
        PottsToolkit._MethodOfLinesNativeCapability || return nothing
    outputs = PottsToolkit.native_outputs(declaration)
    length(outputs) == 1 && only(outputs) isa PottsToolkit.NativeFieldOutput ||
        return nothing
    isempty(PottsToolkit.native_inputs(declaration)) || return nothing
    getfield(declaration, :scope) isa PottsToolkit.Global || return nothing
    PottsToolkit.native_family(declaration) isa PottsToolkit.ODEComponent ||
        return nothing
    profile.execution isa PottsToolkit.SerialNativeExecution || return nothing
    modelingtoolkit_extension = Base.get_extension(
        PottsToolkit, :PottsToolkitModelingToolkitExt
    )
    modelingtoolkit_extension === nothing && return nothing
    getfield(modelingtoolkit_extension, :_audited_explicit_native_ode)(component) ||
        return nothing
    PottsToolkit._native_event_contract(component).admitted || return nothing
    profile.exact_replay && profile.deterministic || return nothing
    PottsToolkit._native_profile_options_class(profile) in (
        :fixed_step, :fixed_step_bounded_failure,
    ) || return nothing
    algorithm_type = typeof(profile.algorithm)
    algorithm = PottsToolkit._native_package_identity(parentmodule(algorithm_type))
    algorithm.name == "OrdinaryDiffEqTsit5" || return nothing
    algorithm.uuid == "b1df2697-797e-41e3-8120-5422d3b24e4a" || return nothing
    algorithm.version == v"2.1.2" || return nothing
    nameof(algorithm_type) === :Tsit5 || return nothing
    Base.pkgversion(MethodOfLines) == v"0.11.19" || return nothing
    PottsToolkit._native_runtime_stack_identity(component) == getfield(
        modelingtoolkit_extension, :_G5H3_TESTED_NATIVE_STACK
    ) || return nothing
    port = only(outputs)
    evidence = PottsToolkit.CorePotts.BackendSPI.CapabilityEvidenceIdentity(
        :PottsToolkit,
        :g5h4_method_of_lines_field_cpu_exact_replay,
        v"1.0.0",
        PottsToolkit._sha256_hex(
            "g5h4-method-of-lines-field-v1",
            PottsToolkit._native_profile_fingerprint(profile),
            PottsToolkit.native_scheduled_fingerprint(component).hex,
            getfield(port, :shape),
            getfield(port, :coordinates),
            string(Base.pkgversion(MethodOfLines)),
        ),
    )
    return (
        status = PottsToolkit.CorePotts.BackendSPI.Supported,
        maturity = PottsToolkit.CorePotts.BackendSPI.ReplayQualified,
        evidence,
    )
end

end
