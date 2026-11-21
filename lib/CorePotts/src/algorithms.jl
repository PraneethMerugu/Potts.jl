# Acceptance laws and algorithms.

abstract type AbstractAcceptanceLaw end

"""
    Metropolis(; offset = 0)

The Metropolis rule: accept a copy attempt with probability
`min(1, exp(-(ΔH - offset)/T))`.

At `T ≤ 0` a copy is accepted if `ΔH < offset`, and a tie (`ΔH == offset`) with
probability ½, as in CompuCell3D. Morpheus's yield `Y` corresponds to `offset = -Y`. When
the backend's default float type is not `Float64` (on a device), a `Float64` offset is
stored as `Float32`.

# Keywords
- `offset = 0`: the shift of the energy change.

# Examples
```jldoctest
julia> using CorePotts

julia> Metropolis(; offset = 2.0).offset
2.0
```

See also [`Barker`](@ref), [`CPMFunction`](@ref).
"""
struct Metropolis{T} <: AbstractAcceptanceLaw
    offset::T
end
Metropolis(; offset = 0) = Metropolis(offset)

# The acceptance law: the algorithm's, else the model's, else Metropolis().
_law(alg, f) = something(alg.acceptance, f.acceptance, Metropolis())

# Device code stays in the default float type (`Exec.default_float`, a policy): Float32 on
# every device, so backends without doubles (Metal) never see a Float64 field.
_device_law(law, backend) = law
function _device_law(law::Metropolis{Float64}, backend)
    return Exec.default_float(backend) <: Float64 ? law : Metropolis(Float32(law.offset))
end

"""
    Barker(; offset = 0)

The Barker (heat-bath) rule: accept a copy attempt with probability
`1 / (1 + exp((ΔH - offset)/T))`.

The offset shifts ΔH as in [`Metropolis`](@ref), so at `T ≤ 0` the two rules agree: a copy
is accepted if `ΔH < offset`, and a tie with probability ½. When the backend's default
float type is not `Float64` (on a device), a `Float64` offset is stored as `Float32`.

# Keywords
- `offset = 0`: the shift of the energy change.

# Examples
```jldoctest
julia> using CorePotts

julia> Barker().offset
0
```

See also [`Metropolis`](@ref), [`CPMFunction`](@ref).
"""
struct Barker{T} <: AbstractAcceptanceLaw
    offset::T
end
Barker(; offset = 0) = Barker(offset)

function _device_law(law::Barker{Float64}, backend)
    return Exec.default_float(backend) <: Float64 ? law : Barker(Float32(law.offset))
end

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

abstract type AbstractCPMAlgorithm <: SciMLBase.AbstractSciMLAlgorithm end

# Potts dynamics advance in whole MCS: a discrete-time algorithm (D-075 Q2). Keep this
# method when the planned `AbstractPottsAlgorithm <: AbstractDEAlgorithm` lands: it
# overrides SciMLBase's default `false`.
SciMLBase.isdiscrete(::AbstractCPMAlgorithm) = true

"""
    SequentialCPM(; acceptance = nothing, proposal = nothing, skip_interior = false)

Random-site sequential dynamics on the host: the reference algorithm for kinetics.

One MCS is `N` copy attempts at mobile sites drawn with replacement. `N` is the number of
mobile (not frozen) sites, which can change during a run when the frozen mask follows the
state. Each attempt draws a source among the target's proposal neighbors and commits an
accepted copy at once.

With `skip_interior = true`, only boundary sites are drawn: mobile sites with a mobile
proposal neighbor in another cell. Every other pick would propose a copy of its own cell
number (a null attempt), so the run of such picks between two boundary picks is drawn at
once, from a geometric law in the boundary fraction. One MCS is still `N` attempts
(`stats.attempts`), and a skip run ends at the MCS end. So the law of the state after every
MCS is the same as with `skip_interior = false`, but the random stream differs: the results
are equal in distribution, not bitwise. It is fastest on lattices that are mostly medium.
Each MCS also pays one pass over all sites that compares the state with the boundary set's
copy.

# Keywords
- `acceptance = nothing`: the acceptance rule ([`Metropolis`](@ref) or [`Barker`](@ref)).
  `nothing` uses the model's (`CPMFunction(…; acceptance)`), else `Metropolis()`.
- `proposal = nothing`: the proposal relation. `nothing` uses the problem's
  (`PottsProblem(…; proposal)`, default `VonNeumann(1)`).
- `skip_interior = false`: draw only boundary sites, as above. It accepts no
  [`Repeat`](@ref) with `n > 1`.

# Examples
```jldoctest
julia> using CorePotts

julia> SequentialCPM(; skip_interior = true)
SequentialCPM(; skip_interior = true)
```

See also [`CheckerboardCPM`](@ref), [`PottsProblem`](@ref).
"""
struct SequentialCPM{A, R, S} <: AbstractCPMAlgorithm
    acceptance::A
    proposal::R
    skip_interior::Bool
    # `S === skip_interior`: the option is part of the type, so the sweep is chosen at
    # compile time and the default compiles to the plain sequential loop
    function SequentialCPM(acceptance::A, proposal::R, skip_interior::Bool) where {A, R}
        return new{A, R, skip_interior}(acceptance, proposal, skip_interior)
    end
end
function SequentialCPM(;
        acceptance = nothing, proposal = nothing,
        skip_interior::Bool = false
    )
    return SequentialCPM(acceptance, proposal, skip_interior)
end

# Printed as the keyword call that rebuilds it (the type parameter `S` is not a keyword);
# keywords at their defaults are left out.
function Base.show(io::IO, a::SequentialCPM)
    print(io, "SequentialCPM(")
    kw = String[]
    a.acceptance === nothing ||
        push!(kw, "acceptance = " * repr(a.acceptance; context = io))
    a.proposal === nothing || push!(kw, "proposal = " * repr(a.proposal; context = io))
    a.skip_interior && push!(kw, "skip_interior = true")
    isempty(kw) || print(io, "; ", join(kw, ", "))
    print(io, ")")
    return nothing
end

"""
    CheckerboardCPM(; acceptance = nothing, proposal = nothing, parts = nothing,
                    region = nothing, switches = 1, threads = :auto,
                    inline_max_blocks = 512, fused_lifecycle_max_sites = 65536,
                    fused_lifecycle_max_cells = 8192)

Lockless parallel block dynamics on the CPU or a GPU (KernelAbstractions), after Sultan et
al.

The lattice is cut into blocks, and each block into `parts` sub-regions along each axis,
each `region` sites wide. A phase activates the same sub-region in every block. One work
item per block makes its attempts there one after another, each against the current state,
and commits an accepted copy at once. Nothing is locked: per-cell totals change by atomic
adds and are read as they are. Each MCS draws `parts^d · switches` phases at random, so
every site is attempted once per MCS on average, as with [`SequentialCPM`](@ref).

Cell trackers stay exact: moments add atomically and re-center once per MCS, pieces
trackers add their changes, and an `@on_copy` write that reads its own cell value adds the
difference. A float-valued column summed by concurrent commits can differ in its last bits
with the thread count; an integer column is exact. `stats.accepted` and `stats.committed`
count the copies (they are equal) and are brought up to date at the host read points. A
copy whose decision needs a whole-cell search (a `Global` veto without a window, or pieces
off their local fast path) is decided after its phase by one work item, with no copy in
flight.

Every phase is checked before it runs. A phase whose work items would share a cell (when a
cell is wider than `(parts - 1) · region + 1`) runs inline, one item after another. Every
other phase is a coloring: its items share no cell that a decision or commit touches, so it
reaches the same decisions inline or threaded. A CPU run is therefore reproducible from its
seed at any thread count. A device run depends on the timing of the work items and is not
reproducible. Because shared-cell phases run inline, cells wider than the spacing gain
nothing from threads: with the default 2D layout (spacing 8 sites), a lattice tiled by
10 × 10 cells runs every phase inline, and one tiled by 5 × 5 cells runs none inline.

The kinetics match `SequentialCPM` within the statistical resolution of the project's
checkerboard kinetics checks (foam, cell sorting, the OpenVT chain and monolayer, Akeeb
invasion, a 3D RPE sheet and the Act cell's persistence). The Act cell moves up to 6 %
faster at weak activity.

# Keywords
- `acceptance = nothing`: the acceptance rule; `nothing` uses the model's, as for
  `SequentialCPM`.
- `proposal = nothing`: the proposal relation; `nothing` uses the problem's.
- `parts = nothing`: sub-regions per block along each axis, at least 2. The default gives
  about 64 phases per MCS: 8 in 2D and 4 in 3D. More parts mean fewer copies in flight at
  once.
- `region = nothing`: the side of a sub-region, in sites. The default is the smallest with
  `(parts - 1) · region` at least the distance that a copy reads and writes around its
  target, including the window of a windowed `Global` search. A smaller value throws an
  `ArgumentError`.
- `switches = 1`: phases per sub-region per MCS, at least 1. Each phase makes
  `1/switches` of the sub-region's attempts.
- `threads = :auto`: CPU only. `:auto` runs a phase inline with one Julia thread, with at
  most `inline_max_blocks` blocks, or inside a threaded ensemble, and threaded otherwise.
  `false` always runs inline and `true` always threaded. `integ.cache.inline` tells which.
- `inline_max_blocks = 512`: CPU only. With `threads = :auto`, a phase with at most this
  many blocks runs inline; `0` threads every phase.
- `fused_lifecycle_max_sites = 65536`, `fused_lifecycle_max_cells = 8192`: devices only.
  Up to this many sites and cell slots, the device lifecycle runs as one launch. A larger
  problem launches one kernel per stage, and `0` always does.

# Examples
```jldoctest
julia> using CorePotts

julia> CheckerboardCPM(; parts = 4, threads = false)
CheckerboardCPM(; parts = 4, threads = false)
```

# References
- Sultan, Devi, Mueller and Textor, "A parallelized cellular Potts model that enables
  simulations at tissue scale", arXiv:2312.09317 (2023).

See also [`SequentialCPM`](@ref), [`Footprint`](@ref).
"""
Base.@kwdef struct CheckerboardCPM{A, R} <: AbstractCPMAlgorithm
    acceptance::A = nothing
    proposal::R = nothing
    region::Union{Nothing, Int} = nothing
    parts::Union{Nothing, Int} = nothing
    switches::Int = 1
    threads::Union{Symbol, Bool} = :auto
    inline_max_blocks::Int = _INLINE_MAX_BLOCKS
    fused_lifecycle_max_sites::Int = _FUSED_LIFECYCLE_MAX_SITES
    fused_lifecycle_max_cells::Int = _FUSED_LIFECYCLE_MAX_CELLS
    function CheckerboardCPM{A, R}(
            acceptance, proposal, region, parts, switches, threads, inline_max_blocks,
            fused_lifecycle_max_sites, fused_lifecycle_max_cells
        ) where {A, R}
        for (k, v) in (
                (:inline_max_blocks, inline_max_blocks), (
                    :fused_lifecycle_max_sites, fused_lifecycle_max_sites,
                ),
                (:fused_lifecycle_max_cells, fused_lifecycle_max_cells),
            )
            v >= 0 || throw(ArgumentError("CheckerboardCPM(; $k = $v): use at least 0"))
        end
        return new{A, R}(
            acceptance, proposal, region, parts, switches, threads, inline_max_blocks,
            fused_lifecycle_max_sites, fused_lifecycle_max_cells
        )
    end
end
function CheckerboardCPM(acceptance::A, proposal::R, args...) where {A, R}
    return CheckerboardCPM{A, R}(acceptance, proposal, args...)
end

# printed as the keyword call that rebuilds it; keywords at their defaults are left out
function Base.show(io::IO, a::CheckerboardCPM)
    kw = String[]
    for (k, d) in (
            (:acceptance, nothing), (:proposal, nothing), (:region, nothing),
            (:parts, nothing),
            (:switches, 1), (:threads, :auto), (:inline_max_blocks, _INLINE_MAX_BLOCKS),
            (:fused_lifecycle_max_sites, _FUSED_LIFECYCLE_MAX_SITES), (
                :fused_lifecycle_max_cells, _FUSED_LIFECYCLE_MAX_CELLS,
            ),
        )
        v = getfield(a, k)
        v == d || push!(kw, "$k = " * repr(v; context = io))
    end
    print(io, "CheckerboardCPM(", isempty(kw) ? "" : "; " * join(kw, ", "), ")")
    return nothing
end

# The boundary-site sweep (`SequentialCPM(; skip_interior = true)`), known from the type.
_skips_interior(::AbstractCPMAlgorithm) = false
_skips_interior(::SequentialCPM{A, R, S}) where {A, R, S} = S
