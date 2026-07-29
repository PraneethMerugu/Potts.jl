"""
    Act(; maximum_activity, strength, neighborhood, algorithm, observation_every=1)

Level-1 Act-CPM declaration. It lowers completely to the coupled semantic kernel and the
ordered CPU/Metal/ROCm realization; it owns no separate runtime or checkpoint semantics.
"""
struct Act{T <: AbstractFloat, R, A} <: AbstractLevel1Declaration
    maximum_activity::T
    strength::T
    neighborhood::R
    algorithm::A
    observation_every::UInt64
end

function Act(; maximum_activity::Real, strength::Real, neighborhood,
        spacing=nothing, weights=nothing,
        algorithm = CorePotts.BudgetedSequentialCPM(
            CorePotts.AttemptsPerSite(1)),
        observation_every::Integer = 1)
    relation = if neighborhood isa CorePotts.AbstractTopology
        CorePotts.static_relation(
            CorePotts.SpatialQueryRole(),
            neighborhood;
            spacing,
            weights,
        )
    elseif neighborhood isa CorePotts.StaticCartesianRelation{
            <:CorePotts.SpatialQueryRole}
        spacing === nothing && weights === nothing || throw(ArgumentError(
            "Act spacing and weights belong to topology construction; " *
            "an existing relation is already canonical"))
        neighborhood
    else
        throw(ArgumentError(
            "Act neighborhood must be a supported topology or SpatialQueryRole relation"))
    end
    algorithm isa CorePotts.AbstractSequentialCPMAlgorithm ||
        throw(ArgumentError("Act requires an ordered sequential algorithm"))
    algorithm isa CorePotts.SequentialEquilibrium && throw(ArgumentError(
        "Act is non-equilibrium and cannot use SequentialEquilibrium"))
    observation_every > 0 ||
        throw(ArgumentError("Act observation cadence must be positive"))
    maximum_value, strength_value =
        promote(float(maximum_activity), float(strength))
    return Act(maximum_value, strength_value, relation,
        algorithm, UInt64(observation_every))
end

function lower(declaration::Act)
    return CorePotts.ActivityProgram(
        maximum = declaration.maximum_activity,
        strength = declaration.strength,
        relation = declaration.neighborhood,
        algorithm = declaration.algorithm,
        observation_cadence = declaration.observation_every)
end

CorePotts.canonical_coupled_model(declaration::Act) =
    CorePotts.canonical_coupled_model(lower(declaration))
