"""Supertype of counter-based symbolic random distributions."""
abstract type AbstractPottsDistribution end

"""`Bernoulli(probability)` declares one keyed Boolean draw."""
struct Bernoulli{P} <: AbstractPottsDistribution
    probability::P
end

"""`Uniform(minimum=0.0, maximum=1.0)` declares one keyed uniform draw."""
struct Uniform{A, B} <: AbstractPottsDistribution
    minimum::A
    maximum::B
end
Uniform() = Uniform(0.0, 1.0)

"""`Normal(mean, standard_deviation)` declares one keyed Gaussian draw."""
struct Normal{M, S} <: AbstractPottsDistribution
    mean::M
    standard_deviation::S
end

"""`UnitVector(dimensions)` declares one keyed isotropic unit-vector draw."""
struct UnitVector{N} <: AbstractPottsDistribution end
UnitVector(dimensions::Integer) =
    dimensions > 0 ? UnitVector{Int(dimensions)}() :
    throw(ArgumentError("UnitVector dimensions must be positive"))

"""Stable semantic identity that makes a symbolic random draw order-independent."""
struct DrawKey
    value::Symbol
    function DrawKey(value::Symbol)
        isempty(String(value)) && throw(ArgumentError("a DrawKey cannot be empty"))
        return new(value)
    end
end

_draw_key_token(key::DrawKey) =
    _potts_token(Symbol("__potts_draw__", key.value); T = Int)

"""Construct a symbolic counter-based draw from `distribution` at `key`."""
draw(distribution::Bernoulli, key::DrawKey) =
    _potts_draw(1, distribution.probability, 0, _draw_key_token(key))
draw(distribution::Uniform, key::DrawKey) =
    _potts_draw(2, distribution.minimum, distribution.maximum, _draw_key_token(key))
draw(distribution::Normal, key::DrawKey) =
    _potts_draw(3, distribution.mean, distribution.standard_deviation, _draw_key_token(key))
draw(::UnitVector{N}, key::DrawKey) where {N} =
    _potts_draw(4, N, 0, _draw_key_token(key))
