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
the problem's copy neighborhood (`PottsProblem(…; proposal)`, default `VonNeumann(1)`).

`skip_interior = true` draws only boundary sites (D-177, D-198): mobile sites with a mobile
proposal neighbor of another owner. Every other pick would propose a copy of its own owner
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

# Printed as the keyword call that rebuilds it (the type parameter `S` is not a keyword);
# keywords at their defaults are left out.
function Base.show(io::IO, a::SequentialCPM)
    print(io, "SequentialCPM(")
    kw = String[]
    a.acceptance === nothing || push!(kw, "acceptance = " * repr(a.acceptance; context = io))
    a.proposal === nothing || push!(kw, "proposal = " * repr(a.proposal; context = io))
    a.skip_interior && push!(kw, "skip_interior = true")
    isempty(kw) || print(io, "; ", join(kw, ", "))
    print(io, ")")
    return nothing
end

"""
    CheckerboardCPM(; acceptance = nothing, proposal = nothing, skip_interior = false,
        counts = false, block = nothing, parts = nothing, switches = 1)

Parallel dynamics on CPU or GPU (KernelAbstractions), lockless (after Sultan et al., arXiv
2312.09317). The lattice is cut into blocks of `parts` sub-regions of side `block` along each
axis. A phase activates the same sub-region in every block; one work item per block makes
its attempts there one after another, each against the current state, and commits an
accepted copy at once. Nothing is claimed: per-cell totals change by atomic adds and are read
as they are. Each MCS draws `parts^d · switches` phases at random, so every site is attempted
once per MCS on average, as with `SequentialCPM`. `acceptance` and `proposal` default to the
model's, as for `SequentialCPM`.

- `parts`: sub-regions per block along each axis (default: about 64 phases per MCS, 8 in 2D
  and 4 in 3D). More parts mean fewer copies in flight at once.
- `block`: the side of a sub-region (default: the smallest with `(parts - 1) · block` at least
  the copy footprint's read + write distance, and at least the window of a windowed `Global`
  search).
- `switches`: phases per sub-region per MCS (default 1); each phase makes 1/`switches` of
  the sub-region's attempts.
- `counts = true`: count accepted and committed copies into `stats.accepted` and
  `stats.committed` (brought up to date at the host read points).
- `skip_interior = true`: accepted; an attempt at an interior site already ends after two
  reads, so the dynamics are those of `skip_interior = false`.

On a device the outcome depends on the timing of the work items, so runs are not
reproducible bit for bit. On the CPU the work items run one after another, so each attempt
sees every earlier one, and a run is reproducible.

Copies to one cell in flight at the same time read its totals before each other's commit.
Cell trackers stay exact: moments add atomically and re-center once per MCS, pieces trackers
add their changes, and an `@on_copy` write that reads its own cell value adds the difference.
A copy whose decision needs a whole-cell search (a `Global` veto without window, pieces off
their local fast path) is decided after its phase by one work item, with no copy in flight.

The kinetics match `SequentialCPM` within the statistical resolution of the P6.0bl checks
(foam, cell sorting, the OpenVT chain and monolayer, Akeeb invasion, a 3D RPE sheet), except
that small cells in a crowded monolayer are lost more often (OpenVT case (b): 1.7 against 0.2
per run). See `docs/design/research/checkerboard-kinetics.md`.
"""
Base.@kwdef struct CheckerboardCPM{A, R} <: CPMAlgorithm
    acceptance::A = nothing
    proposal::R = nothing
    skip_interior::Bool = false
    counts::Bool = false
    block::Union{Nothing, Int} = nothing
    parts::Union{Nothing, Int} = nothing
    switches::Int = 1
end

# The boundary-site sweep (`SequentialCPM(; skip_interior = true)`), known from the type.
_skips_interior(::CPMAlgorithm) = false
_skips_interior(::SequentialCPM{A, R, S}) where {A, R, S} = S
