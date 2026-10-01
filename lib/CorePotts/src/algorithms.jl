# Acceptance laws and algorithms.

abstract type AcceptanceLaw end

"""
    Metropolis(; offset = 0)

Accept if `ΔH ≤ offset`, otherwise with probability `exp(-(ΔH - offset)/T)`. At `T ≤ 0`
ties (`ΔH == offset`) are accepted with probability ½ (CompuCell3D convention). The
Morpheus yield `Y` corresponds to `offset = -Y`. On GPU backends without Float64 (Metal)
a floating-point offset is stored as `Float32`.
"""
struct Metropolis{T} <: AcceptanceLaw
    offset::T
end
Metropolis(; offset = 0) = Metropolis(offset)

# The acceptance law: the algorithm's, else the model's, else Metropolis().
_law(alg, f) = something(alg.acceptance, f.acceptance, Metropolis())

# Backends without doubles (Metal) cannot even truncate a Float64 field on the device.
_device_law(law, backend) = law
_device_law(law::Metropolis{Float64}, backend) =
    backend isa KernelAbstractions.CPU ? law : Metropolis(Float32(law.offset))

"""Barker (heat-bath) acceptance: probability `1 / (1 + exp(ΔH/T))`."""
struct Barker <: AcceptanceLaw end

@inline function accept(law::Metropolis, dH::T, temperature::T, u::T) where {T}
    x = dH - T(law.offset)
    if temperature <= zero(T)
        return x < zero(T) || (x == zero(T) && u < T(0.5))
    end
    return x <= zero(T) || u < exp(-x / temperature)
end

@inline function accept(::Barker, dH::T, temperature::T, u::T) where {T}
    temperature <= zero(T) && return dH < zero(T) || (dH == zero(T) && u < T(0.5))
    return u < inv(one(T) + exp(dH / temperature))
end

abstract type CPMAlgorithm <: SciMLBase.AbstractSciMLAlgorithm end

# Potts dynamics advance in whole MCS: a discrete-time algorithm (D-075 Q2). Keep this
# method when the planned `AbstractPottsAlgorithm <: AbstractDEAlgorithm` lands: it
# overrides SciMLBase's default `false`.
SciMLBase.isdiscrete(::CPMAlgorithm) = true

"""
    SequentialCPM(; acceptance = nothing, proposal = nothing)

Random-site sequential dynamics on the host: one MCS is `N` copy attempts with
replacement over the mobile (not frozen) lattice sites, so `N` is the number of mobile
sites, which can change during a run when the frozen mask follows the state (D-081). The
fidelity reference. `acceptance = nothing` uses the
model's law (`CPMFunction(…; acceptance)`), else `Metropolis()`; `proposal = nothing` uses
the problem's copy neighbourhood (`PottsProblem(…; proposal)`, default `VonNeumann(1)`).
"""
Base.@kwdef struct SequentialCPM{A, R} <: CPMAlgorithm
    acceptance::A = nothing
    proposal::R = nothing
end

"""
    CheckerboardCPM(; acceptance = nothing, proposal = nothing)

Parallel dynamics on CPU or GPU (KernelAbstractions). Sites are colored so that same-color
targets lie outside each other's read/write footprints; each MCS visits every site once in
a random color order. Accepted proposals claim their cells with a unique priority and
commit only if they win every claim, so each cell changes at most once per color.
`acceptance` and `proposal` default to the model's, as for `SequentialCPM`.
"""
Base.@kwdef struct CheckerboardCPM{A, R} <: CPMAlgorithm
    acceptance::A = nothing
    proposal::R = nothing
end
