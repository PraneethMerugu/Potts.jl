abstract type AbstractPottsDistribution end

struct Bernoulli{P} <: AbstractPottsDistribution
    probability::P
end

struct Uniform{A, B} <: AbstractPottsDistribution
    minimum::A
    maximum::B
end
Uniform() = Uniform(0.0, 1.0)

struct Normal{M, S} <: AbstractPottsDistribution
    mean::M
    standard_deviation::S
end

struct UnitVector{N} <: AbstractPottsDistribution end
UnitVector(dimensions::Integer) =
    dimensions > 0 ? UnitVector{Int(dimensions)}() :
    throw(ArgumentError("UnitVector dimensions must be positive"))

struct DrawKey
    value::Symbol
    function DrawKey(value::Symbol)
        isempty(String(value)) && throw(ArgumentError("a DrawKey cannot be empty"))
        return new(value)
    end
end

_draw_key_token(key::DrawKey) =
    Symbolics.variable(Symbol("__potts_draw__", key.value); T = Int)

draw(distribution::Bernoulli, key::DrawKey) =
    _potts_draw(1, distribution.probability, 0, _draw_key_token(key))
draw(distribution::Uniform, key::DrawKey) =
    _potts_draw(2, distribution.minimum, distribution.maximum, _draw_key_token(key))
draw(distribution::Normal, key::DrawKey) =
    _potts_draw(3, distribution.mean, distribution.standard_deviation, _draw_key_token(key))
draw(::UnitVector{N}, key::DrawKey) where {N} =
    _potts_draw(4, N, 0, _draw_key_token(key))

