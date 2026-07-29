"""Target and strength values used by volume constraint declarations."""
struct VolumeParameters{T <: AbstractFloat}
    target::T
    strength::T

    function VolumeParameters(target::T, strength::T) where {T <: AbstractFloat}
        isfinite(target) && target >= zero(T) || throw(ArgumentError(
            "volume target must be finite and non-negative"))
        isfinite(strength) && strength >= zero(T) || throw(ArgumentError(
            "volume strength must be finite and non-negative"))
        return new{T}(target, strength)
    end
end

function VolumeParameters(target::Real, strength::Real)
    T = float(promote_type(typeof(target), typeof(strength)))
    return VolumeParameters(T(target), T(strength))
end

function _volume_bindings(pairs::Tuple)
    isempty(pairs) && throw(ArgumentError("a volume constraint must bind at least one cell type"))
    all(pair -> _is_cell_reference(first(pair)) && last(pair) isa NamedTuple &&
        haskey(last(pair), :target) && (haskey(last(pair), :strength) || haskey(last(pair), :λ)),
        pairs) || throw(ArgumentError(
        "volume entries must be `CellType => (target=..., strength=...)`"))
    numeric_types = map(pairs) do pair
        values = last(pair)
        strength = haskey(values, :strength) ? values.strength : values.λ
        promote_type(typeof(values.target), typeof(strength))
    end
    T = float(promote_type(numeric_types...))
    entries = map(pairs) do pair
        values = last(pair)
        strength = haskey(values, :strength) ? values.strength : values.λ
        Binding{CellType, VolumeParameters{T}}(
            _cell_reference(first(pair)), VolumeParameters(T(values.target), T(strength)))
    end
    return BindingTable{CellType, VolumeParameters{T}}(Tuple(entries))
end

"""Conservative quadratic finite-cell volume Hamiltonian declaration."""
struct VolumeConstraint{T <: AbstractFloat}
    name::SemanticName
    bindings::BindingTable{CellType, VolumeParameters{T}}
end

function VolumeConstraint(pairs::Pair...; name::Symbol = :volume,
        namespace::Namespace = Namespace())
    bindings = _volume_bindings(pairs)
    T = typeof(first(bindings).value.target)
    return VolumeConstraint{T}(SemanticName(name; namespace), bindings)
end

semantic_identity(component::VolumeConstraint) = component.name

"""First-class fluctuating-volume mechanical declaration, distinct from the exact constraint."""
struct FluctuatingVolumeConstraint{T <: AbstractFloat, N, D}
    name::SemanticName
    bindings::BindingTable{CellType, VolumeParameters{T}}
    eta::T
    noise::N
    initialization::CorePotts.MechanicalInitialization
    division::D
end

function FluctuatingVolumeConstraint(pairs::Pair...; name::Symbol = :fluctuating_volume,
        namespace::Namespace = Namespace(), eta::Real = 1.0,
        noise = CorePotts.AlgorithmTemperatureNoise(),
        initialization::CorePotts.MechanicalInitialization =
            CorePotts.ConstitutiveMeanInitialization,
        division = CorePotts.ConstitutiveResetAfterDivision())
    bindings = _volume_bindings(pairs)
    T = typeof(first(bindings).value.target)
    rate = T(eta)
    isfinite(rate) && rate > zero(T) || throw(ArgumentError(
        "fluctuating-volume eta must be finite and positive"))
    return FluctuatingVolumeConstraint{T, typeof(noise), typeof(division)}(
        SemanticName(name; namespace), bindings, rate, noise, initialization, division)
end

semantic_identity(component::FluctuatingVolumeConstraint) = component.name

"""Target major-axis RMS extent and quadratic strength for one finite cell type."""
struct ElongationParameters{T <: AbstractFloat}
    target::T
    strength::T

    function ElongationParameters(target::T, strength::T) where {T <: AbstractFloat}
        isfinite(target) && target >= zero(T) || throw(ArgumentError(
            "elongation target must be finite and non-negative"))
        isfinite(strength) && strength >= zero(T) || throw(ArgumentError(
            "elongation strength must be finite and non-negative"))
        return new{T}(target, strength)
    end
end

function _elongation_bindings(pairs::Tuple)
    isempty(pairs) && throw(ArgumentError(
        "an elongation constraint must bind at least one cell type"))
    all(pair -> _is_cell_reference(first(pair)) && last(pair) isa NamedTuple &&
        haskey(last(pair), :target) && (haskey(last(pair), :strength) ||
        haskey(last(pair), :λ)), pairs) || throw(ArgumentError(
        "elongation entries must be `CellType => (target=..., strength=...)`"))
    numeric_types = map(pairs) do pair
        values = last(pair)
        strength = haskey(values, :strength) ? values.strength : values.λ
        promote_type(typeof(values.target), typeof(strength))
    end
    T = float(promote_type(numeric_types...))
    entries = map(pairs) do pair
        values = last(pair)
        strength = haskey(values, :strength) ? values.strength : values.λ
        Binding{CellType, ElongationParameters{T}}(_cell_reference(first(pair)),
            ElongationParameters(T(values.target), T(strength)))
    end
    return BindingTable{CellType, ElongationParameters{T}}(Tuple(entries))
end

"""Exact conservative penalty on each finite cell's major-axis RMS extent."""
struct Elongation{T <: AbstractFloat, D <: CorePotts.AbstractDivisionPolicy}
    name::SemanticName
    bindings::BindingTable{CellType, ElongationParameters{T}}
    target_division::D
end

function Elongation(pairs::Pair...; name::Symbol = :elongation,
        namespace::Namespace = Namespace(),
        target_division::CorePotts.AbstractDivisionPolicy =
            CorePotts.UnsupportedDivision(:elongation_target_policy_required))
    bindings = _elongation_bindings(pairs)
    T = typeof(first(bindings).value.target)
    return Elongation{T, typeof(target_division)}(
        SemanticName(name; namespace), bindings, target_division)
end

semantic_identity(component::Elongation) = component.name

"""Target boundary measure and quadratic strength for one finite cell type."""
struct BoundaryParameters{Q <: Real, T <: AbstractFloat}
    target::Q
    strength::T

    function BoundaryParameters(target::Q, strength::T) where {
            Q <: Real, T <: AbstractFloat}
        isfinite(target) && target >= zero(Q) || throw(ArgumentError(
            "boundary target must be finite and non-negative"))
        isfinite(strength) && strength >= zero(T) || throw(ArgumentError(
            "boundary strength must be finite and non-negative"))
        return new{Q, T}(target, strength)
    end
end

function _boundary_bindings(metric::CorePotts.AbstractBoundaryMetric, pairs::Tuple)
    isempty(pairs) && throw(ArgumentError(
        "a boundary constraint must bind at least one cell type"))
    all(pair -> _is_cell_reference(first(pair)) && last(pair) isa NamedTuple &&
        haskey(last(pair), :target) && (haskey(last(pair), :strength) ||
        haskey(last(pair), :λ)), pairs) || throw(ArgumentError(
        "boundary entries must be `CellType => (target=..., strength=...)`"))
    strengths = map(pair -> haskey(last(pair), :strength) ?
        last(pair).strength : last(pair).λ, pairs)
    T = float(promote_type(map(typeof, strengths)...))
    if metric isa CorePotts.BoundaryEdgeCount
        all(pair -> last(pair).target isa Integer, pairs) || throw(ArgumentError(
            "boundary-edge-count targets must be integers"))
        entries = map(zip(pairs, strengths)) do (pair, strength)
            Binding{CellType, BoundaryParameters{Int64, T}}(_cell_reference(first(pair)),
                BoundaryParameters(Int64(last(pair).target), T(strength)))
        end
        return BindingTable{CellType, BoundaryParameters{Int64, T}}(Tuple(entries))
    end
    Q = float(promote_type(map(pair -> typeof(last(pair).target), pairs)..., T))
    entries = map(zip(pairs, strengths)) do (pair, strength)
        Binding{CellType, BoundaryParameters{Q, T}}(_cell_reference(first(pair)),
            BoundaryParameters(Q(last(pair).target), T(strength)))
    end
    return BindingTable{CellType, BoundaryParameters{Q, T}}(Tuple(entries))
end

"""Conservative quadratic finite-cell boundary Hamiltonian declaration."""
struct BoundaryConstraint{Q <: Real, T <: AbstractFloat,
        M <: CorePotts.AbstractBoundaryMetric}
    name::SemanticName
    bindings::BindingTable{CellType, BoundaryParameters{Q, T}}
    metric::M
end

function BoundaryConstraint(pairs::Pair...; name::Symbol = :boundary,
        namespace::Namespace = Namespace(),
        metric::CorePotts.AbstractBoundaryMetric = CorePotts.BoundaryEdgeCount())
    bindings = _boundary_bindings(metric, pairs)
    parameter = first(bindings).value
    return BoundaryConstraint{typeof(parameter.target), typeof(parameter.strength),
        typeof(metric)}(SemanticName(name; namespace), bindings, metric)
end

semantic_identity(component::BoundaryConstraint) = component.name

"""First-class fluctuating/HST finite-cell boundary-tension declaration."""
struct FluctuatingBoundaryConstraint{Q <: Real, T <: AbstractFloat, N,
        M <: CorePotts.AbstractBoundaryMetric, TD, D}
    name::SemanticName
    bindings::BindingTable{CellType, BoundaryParameters{Q, T}}
    eta::T
    noise::N
    initialization::CorePotts.MechanicalInitialization
    metric::M
    target_division::TD
    division::D
end

function FluctuatingBoundaryConstraint(pairs::Pair...;
        name::Symbol = :fluctuating_boundary, namespace::Namespace = Namespace(),
        eta::Real = 1.0,
        noise = CorePotts.AlgorithmTemperatureNoise(),
        initialization::CorePotts.MechanicalInitialization =
            CorePotts.ConstitutiveMeanInitialization,
        metric::CorePotts.AbstractBoundaryMetric = CorePotts.BoundaryEdgeCount(),
        target_division = CorePotts.UnsupportedDivision(
            :surface_target_policy_required),
        division = CorePotts.ConstitutiveResetAfterDivision())
    bindings = _boundary_bindings(metric, pairs)
    parameter = first(bindings).value
    T = typeof(parameter.strength)
    rate = T(eta)
    isfinite(rate) && rate > zero(T) || throw(ArgumentError(
        "fluctuating-boundary eta must be finite and positive"))
    return FluctuatingBoundaryConstraint{typeof(parameter.target), T, typeof(noise),
        typeof(metric), typeof(target_division), typeof(division)}(
        SemanticName(name; namespace), bindings, rate, noise, initialization,
        metric, target_division, division)
end

semantic_identity(component::FluctuatingBoundaryConstraint) = component.name

"""Exact global finite-cell connectedness constraint; omit it to permit fragmentation."""
struct PreserveConnectivity
    name::SemanticName
end

PreserveConnectivity(; name::Symbol = :connectivity,
    namespace::Namespace = Namespace()) =
    PreserveConnectivity(SemanticName(name; namespace))

semantic_identity(component::PreserveConnectivity) = component.name

"""
Eight-neighbor local connectedness test used by lattice-vascular models.

Unlike [`PreserveConnectivity`](@ref), this is the source-bounded local
connectivity rule: it rejects a fragmenting copy unless the donor
neighborhood contains exactly two distinct finite-cell identities.
"""
struct LocalConnectivity
    name::SemanticName
end

LocalConnectivity(; name::Symbol=:local_connectivity,
    namespace::Namespace=Namespace()) =
    LocalConnectivity(SemanticName(name; namespace))

semantic_identity(component::LocalConnectivity) = component.name

"""Unordered contact/adhesion Hamiltonian declaration."""
struct Adhesion{T <: AbstractFloat}
    name::SemanticName
    law::PairwiseLaw{T}
end

function Adhesion(pairs::Pair...; name::Symbol = :adhesion,
        namespace::Namespace = Namespace(), default = nothing)
    law = PairwiseLaw(pairs...; name, namespace, symmetric = true, default)
    return Adhesion(law.name, law)
end

semantic_identity(component::Adhesion) = component.name

"""One simultaneous per-cell property addition at an integer-MCS lifecycle boundary."""
struct PropertyUpdate{T, S, G}
    name::SemanticName
    source::SemanticName
    role::Symbol
    cell_types::Tuple
    amount::T
    schedule::S
    trigger::G
end

_lifecycle_trigger(trigger::CorePotts.AbstractLifecycleTrigger) = trigger
_lifecycle_trigger(trigger) = throw(ArgumentError(
    "$(typeof(trigger)) is not a supported lifecycle trigger"))

function PropertyUpdate(source, cell_types...;
        name::Symbol = :property_update, namespace::Namespace = Namespace(),
        role::Symbol = :target, amount::Real,
        schedule::CorePotts.AbstractMCSSchedule = CorePotts.EveryMCS(),
        trigger = CorePotts.AlwaysLifecycleTrigger())
    isempty(cell_types) && throw(ArgumentError(
        "a property update must target at least one cell type"))
    all(_is_cell_reference, cell_types) || throw(ArgumentError(
        "property updates must target CellType or CellRole values"))
    role in (:value, :target, :strength) || throw(ArgumentError(
        "property updates support :value, :target, or :strength roles"))
    T = float(typeof(amount))
    value = T(amount)
    isfinite(value) || throw(ArgumentError("a property update amount must be finite"))
    resolved_trigger = _lifecycle_trigger(trigger)
    scope = Tuple(_cell_reference(value) for value in cell_types)
    return PropertyUpdate(SemanticName(name; namespace), semantic_identity(source), role,
        Tuple(sort!(unique!(collect(scope)); by = _identity_text)), value,
        schedule, resolved_trigger)
end


function StochasticPropertyUpdate(source, cell_types...;
        name::Symbol = :stochastic_property_update, namespace::Namespace = Namespace(),
        role::Symbol = :target, amount::Real,
        schedule::CorePotts.AbstractMCSSchedule = CorePotts.EveryMCS(),
        probability::Real, draw::Symbol = :activation)
    T = float(promote_type(typeof(amount), typeof(probability)))
    operation = _semantic_rng_code(
        SemanticName(name; namespace), draw, UInt16(0x03ff))
    trigger = CorePotts.BernoulliCellTrigger(T(probability), operation)
    return PropertyUpdate(source, cell_types...; name, namespace, role,
        amount = T(amount), schedule, trigger)
end


semantic_identity(rule::PropertyUpdate) = rule.name

function _semantic_rng_code(identity::SemanticName, role::Symbol, maximum::UInt16)
    payload = string(_identity_text(identity), '|', role)
    digest = SHA.sha256(codeunits(payload))
    value = (UInt16(digest[1]) << 8) | UInt16(digest[2])
    return Int(mod(value, maximum + UInt16(1)))
end

"""Explicitly name a direct CorePotts component when more than one instance is composed."""
struct NamedCoreComponent{C}
    name::SemanticName
    component::C
end


NamedCoreComponent(name::Symbol, component; namespace::Namespace = Namespace()) =
    NamedCoreComponent(SemanticName(name; namespace), component)

semantic_identity(component::NamedCoreComponent) = component.name

function _core_semantic_identity(component)
    identity = try
        CorePotts.component_identity(component)
    catch
        return nothing
    end
    return SemanticName(identity.key)
end

function semantic_identity(component)
    identity = _core_semantic_identity(component)
    identity === nothing && throw(ArgumentError(
        "$(typeof(component)) does not provide a semantic identity"))
    return identity
end
