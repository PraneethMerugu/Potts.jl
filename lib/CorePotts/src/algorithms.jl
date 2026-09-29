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

"""
    SequentialCPM(; acceptance = Metropolis(), proposal = VonNeumann(1))

Random-site sequential dynamics on the host: one MCS is `N` copy attempts with
replacement over the lattice sites. The fidelity reference.
"""
Base.@kwdef struct SequentialCPM{A, R} <: CPMAlgorithm
    acceptance::A = Metropolis()
    proposal::R = VonNeumann(1)
end

"""
    CheckerboardCPM(; acceptance = Metropolis(), proposal = VonNeumann(1))

Parallel dynamics on CPU or GPU (KernelAbstractions). Sites are colored so that same-color
targets lie outside each other's read/write footprints; each MCS visits every site once in
a random color order. Accepted proposals claim their cells with a unique priority and
commit only if they win every claim, so each cell changes at most once per color.
"""
Base.@kwdef struct CheckerboardCPM{A, R} <: CPMAlgorithm
    acceptance::A = Metropolis()
    proposal::R = VonNeumann(1)
end
