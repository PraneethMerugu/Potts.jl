module PottsToolkitModelingToolkitExt

using PottsToolkit
import ModelingToolkit
import ModelingToolkitBase

function _require_supported_external_system(system)
    ModelingToolkitBase.iscomplete(system) && throw(ArgumentError(
        "EquationComponent requires symbolic source, not a completed external system"
    ))
    isempty(ModelingToolkitBase.get_brownians(system)) || throw(ArgumentError(
        "EquationComponent does not admit Brownian or noise equations"
    ))
    isempty(ModelingToolkitBase.get_jumps(system)) || throw(ArgumentError(
        "EquationComponent does not admit jump systems or unconverted reaction semantics"
    ))
    ivs = ModelingToolkitBase.independent_variables(system)
    length(ivs) <= 1 || throw(ArgumentError(
        "EquationComponent admits at most one continuous independent variable"
    ))
    return nothing
end

function PottsToolkit.EquationComponent(
        external::ModelingToolkitBase.AbstractSystem,
        process::PottsToolkit.EquationProcess;
        name = nothing,
    )
    name isa Symbol || throw(ArgumentError(
        "EquationComponent requires `name`; use `@named field = EquationComponent(...)`"
    ))
    _require_supported_external_system(external)

    nested = PottsToolkit.PottsSystem[
        PottsToolkit.EquationComponent(
            child,
            PottsToolkit.EquationProcess(
                Symbol(PottsToolkit.statement_id(process)),
                ModelingToolkitBase.equations(child);
                writes = (),
            );
            name = nameof(child),
        )
        for child in ModelingToolkitBase.get_systems(external)
    ]

    return PottsToolkit.PottsSystem(
        name = name,
        statements = PottsToolkit.StatementSet(process),
        equations = ModelingToolkitBase.get_eqs(external),
        unknowns = ModelingToolkitBase.get_unknowns(external),
        parameters = ModelingToolkitBase.get_ps(external),
        independent_variables = ModelingToolkitBase.independent_variables(external),
        systems = nested,
        inputs = ModelingToolkitBase.inputs(external),
        outputs = ModelingToolkitBase.outputs(external),
        initial_conditions = ModelingToolkitBase.get_initial_conditions(external),
        observed = ModelingToolkitBase.get_observed(external),
        continuous_events = ModelingToolkitBase.get_continuous_events(external),
        discrete_events = ModelingToolkitBase.get_discrete_events(external),
    )
end

end
