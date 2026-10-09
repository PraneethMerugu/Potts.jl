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

"""
    Barker(; offset = 0)

Barker (heat-bath) acceptance: probability `1 / (1 + exp((ΔH - offset)/T))`. The offset
shifts ΔH exactly as in `Metropolis`, so at `T ≤ 0` the two laws coincide: accept
if `ΔH < offset`, and ties (`ΔH == offset`) with probability ½. On GPU backends without
Float64 (Metal) a floating-point offset is stored as `Float32`.
"""
struct Barker{T} <: AcceptanceLaw
    offset::T
end
Barker(; offset = 0) = Barker(offset)

_device_law(law::Barker{Float64}, backend) =
    backend isa KernelAbstractions.CPU ? law : Barker(Float32(law.offset))

@inline function accept(law::Metropolis, dH::T, temperature::T, u::T) where {T}
    x = dH - T(law.offset)
    if temperature <= zero(T)
        return x < zero(T) || (x == zero(T) && u < T(0.5))
    end
    return x <= zero(T) || u < exp(-x / temperature)
end

@inline function accept(law::Barker, dH::T, temperature::T, u::T) where {T}
    x = dH - T(law.offset)
    temperature <= zero(T) && return x < zero(T) || (x == zero(T) && u < T(0.5))
    return u < inv(one(T) + exp(x / temperature))
end

abstract type CPMAlgorithm <: SciMLBase.AbstractSciMLAlgorithm end

# Potts dynamics advance in whole MCS: a discrete-time algorithm (D-075 Q2). Keep this
# method when the planned `AbstractPottsAlgorithm <: AbstractDEAlgorithm` lands: it
# overrides SciMLBase's default `false`.
SciMLBase.isdiscrete(::CPMAlgorithm) = true

"""
    SequentialCPM(; acceptance = nothing, proposal = nothing, skip_interior = false)

Random-site sequential dynamics on the host: one MCS is `N` copy attempts with
replacement over the mobile (not frozen) lattice sites, so `N` is the number of mobile
sites, which can change during a run when the frozen mask follows the state. The
fidelity reference. `acceptance = nothing` uses the
model's law (`CPMFunction(…; acceptance)`), else `Metropolis()`; `proposal = nothing` uses
the problem's copy neighbourhood (`PottsProblem(…; proposal)`, default `VonNeumann(1)`).

`skip_interior = true` draws only boundary sites (D-177, D-198): mobile sites with a mobile
proposal neighbour of another owner. Every other pick would propose a copy of its own owner
(a null move), so the run of such picks between two boundary picks is drawn at once,
geometric in the boundary fraction. One MCS is still `N` attempts over all mobile sites
(`stats.attempts`), and a skip run ends at the MCS end, so the law of the state after every
MCS is the same as with `skip_interior = false`; the random stream differs, so results are
equal in distribution, not bitwise. Fast on mostly-medium lattices; each MCS also pays one
O(N) pass comparing the state with the boundary set's shadow copy (a few percent of the
sweep at typical cover, more on nearly empty lattices).
"""
struct SequentialCPM{A, R, S} <: CPMAlgorithm
    acceptance::A
    proposal::R
    skip_interior::Bool
    # `S === skip_interior`: the option is part of the type, so the sweep is chosen at
    # compile time and the default compiles to the plain sequential loop
    function SequentialCPM(acceptance::A, proposal::R, skip_interior::Bool) where {A, R}
        return new{A, R, skip_interior}(acceptance, proposal, skip_interior)
    end
end
SequentialCPM(; acceptance = nothing, proposal = nothing, skip_interior::Bool = false) =
    SequentialCPM(acceptance, proposal, skip_interior)

"""
    CheckerboardCPM(; acceptance = nothing, proposal = nothing, skip_interior = false)

Parallel dynamics on CPU or GPU (KernelAbstractions). Sites are colored so that same-color
targets lie outside each other's read/write footprints; each MCS visits every site once in
a random color order. Accepted proposals claim their cells with a unique priority and
commit only if they win every claim, so each cell changes at most once per color.
`acceptance` and `proposal` default to the model's, as for `SequentialCPM`.
`skip_interior = true` is not yet implemented on the checkerboard (P6.0bk): `init` and
`solve` raise an `ArgumentError`.
"""
Base.@kwdef struct CheckerboardCPM{A, R} <: CPMAlgorithm
    acceptance::A = nothing
    proposal::R = nothing
    skip_interior::Bool = false
end

# The boundary-site sweep (`SequentialCPM(; skip_interior = true)`), known from the type.
_skips_interior(::CPMAlgorithm) = false
_skips_interior(::SequentialCPM{A, R, S}) where {A, R, S} = S
