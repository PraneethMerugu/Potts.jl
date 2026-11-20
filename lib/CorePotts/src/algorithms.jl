# Acceptance laws and algorithms.

abstract type AbstractAcceptanceLaw end

"""
    Metropolis(; offset = 0)

Accept if `ΔH ≤ offset`, otherwise with probability `exp(-(ΔH - offset)/T)`. At `T ≤ 0`
ties (`ΔH == offset`) are accepted with probability ½ (CompuCell3D convention). The
Morpheus yield `Y` corresponds to `offset = -Y`. On GPU backends without Float64 (Metal)
a floating-point offset is stored as `Float32`.
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
_device_law(law::Metropolis{Float64}, backend) =
    Exec.default_float(backend) === Float64 ? law : Metropolis(Float32(law.offset))

"""
    Barker(; offset = 0)

Barker (heat-bath) acceptance: probability `1 / (1 + exp((ΔH - offset)/T))`. The offset
shifts ΔH exactly as in `Metropolis`, so at `T ≤ 0` the two laws coincide: accept
if `ΔH < offset`, and ties (`ΔH == offset`) with probability ½. On GPU backends without
Float64 (Metal) a floating-point offset is stored as `Float32`.
"""
struct Barker{T} <: AbstractAcceptanceLaw
    offset::T
end
Barker(; offset = 0) = Barker(offset)

_device_law(law::Barker{Float64}, backend) =
    Exec.default_float(backend) === Float64 ? law : Barker(Float32(law.offset))

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
    CheckerboardCPM(; acceptance = nothing, proposal = nothing, parts = nothing, region = nothing,
        switches = 1, threads = :auto, inline_max_blocks = 512, fused_lifecycle_max_sites = 65536,
        fused_lifecycle_max_cells = 8192)

Parallel dynamics on the CPU or a GPU (KernelAbstractions), lockless (after Sultan et al.,
arXiv 2312.09317). The lattice is cut into blocks; each block has `parts` sub-regions along
each axis, each `region` sites wide. A phase activates the same sub-region in every block,
and one work item per block makes its attempts there one after another, each against the
current state, and commits an accepted copy at once. Nothing is claimed: per-cell totals
change by atomic adds and are read as they are. Each MCS draws `parts^d · switches` phases
at random, so every site is attempted once per MCS on average, as with `SequentialCPM`.
`acceptance` and `proposal` default to the model's, as for `SequentialCPM`.

- `parts`: sub-regions per block along each axis (default: about 64 phases per MCS, 8 in 2D
  and 4 in 3D). More parts mean fewer copies in flight at once.
- `region`: the side of a sub-region in sites (default: the smallest with
  `(parts - 1) · region` at least the distance a copy reads and writes around its target,
  including the window of a windowed `Global` search).
- `switches`: phases per sub-region per MCS (default 1); each phase makes 1/`switches` of
  the sub-region's attempts.
- `threads` (CPU only): `:auto` runs a phase with one Julia thread, or with at most
  `inline_max_blocks` blocks, or as a trajectory of a threaded ensemble,
  inline, else threaded; `false` always inline;
  `true` always threaded. `integ.cache.inline` says which.
- `inline_max_blocks` (CPU only, default 512): with `threads = :auto`, a phase with at most
  this many blocks runs inline (`0` threads every phase).
- `fused_lifecycle_max_sites`, `fused_lifecycle_max_cells` (devices only, defaults 65536 and
  8192): up to this many sites and cell slots the device lifecycle runs as one launch; a
  larger problem launches one kernel per stage (`0` always does).

`stats.accepted` and `stats.committed` count the copies (equal: a copy commits when it is
accepted), brought up to date at the host read points.

Reproducibility. Every phase is checked before it runs. One whose work items would share a cell
(possible when a cell is wider than the block spacing) runs inline, one work item after another,
so its decisions are exact and order-free; every other phase is a colouring, whose items share no
cell (of those a copy's decision or commit touches: its target's, its source's, or a neighbour's),
so it reaches the same decisions inline or threaded. A CPU
run is therefore reproducible from its seed at any thread count: the same seed gives the same
trajectory at one thread and at four. Device runs depend on the timing of the work items and are
not (user ruling 2026-11-04).

Threading. A phase whose items share a cell runs inline, so a geometry whose cells are wider than
`(parts - 1) * region + 1` across serialises every phase that contains two of them, and gains
nothing from threads. Measured on the PC, 2026-11-12, on a 200 × 200 and a 400 × 400 lattice tiled
by 10 × 10 cells and on 30 × 30 lattices tiled by 5 × 5 cells; the serialised count is a property of
the layout and the state, the times were taken on a loaded lane:

| geometry | items per phase | cell side | spacing | serialised phases |
| --- | --- | --- | --- | --- |
| 30 × 30, 5 × 5 cells, `region = 1, parts = 3` | 100 | 5 | 3 | 9 / 9 |
| 30 × 30, 5 × 5 cells, `parts = 2` | 225 | 5 | 2 | 4 / 4 |
| 30 × 30, 5 × 5 cells, default | 9 | 5 | 8 | 0 / 64 |
| 200 × 200, 10 × 10 cells, default | 625 | 10 | 8 | 64 / 64 |
| 400 × 400, 10 × 10 cells, default | 2500 | 10 | 8 | 64 / 64 |

So threading survives on small-cell geometries and is gone on the wide-cell ones, which are the
ones the default layout produces: 10 × 10 cells are wider than the 8-site spacing the default
`parts = 8, region = 1` gives. The trade at 400 × 400 with 1600 cells is the four-thread gain such a
geometry had before this rule, about 1.4× (2.76 ms to 1.96 ms per MCS); the 3.3–3.7× recorded for
`inline_max_blocks` is a 5000-block measurement and does not describe it.

Cell trackers stay exact: moments add atomically and re-center once per MCS, pieces trackers add
their changes, and an `@on_copy` write that reads its own cell value adds the difference. (A
float-valued column accumulated by concurrent commits can differ in its last bits by thread
count: an integer column is exact.) `stats.accepted_energy_change` sums the accepted copies' ΔH and
reconciles with the trajectory's energy change, since no two work items act on one cell unless
they run one after another. A copy whose decision needs a whole-cell search (a `Global` veto
without window, pieces off their local fast path) is decided after its phase by one work item,
with no copy in flight.

The kinetics match `SequentialCPM` within the statistical resolution of the checkerboard kinetics checks
(foam, cell sorting, the OpenVT chain and monolayer, Akeeb invasion, a 3D RPE sheet, the
Act cell's persistence); the Act cell moves up to 6 % faster at weak activity. See
`docs/design/research/checkerboard-kinetics.md`.
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
                (:inline_max_blocks, inline_max_blocks), (:fused_lifecycle_max_sites, fused_lifecycle_max_sites),
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
CheckerboardCPM(acceptance::A, proposal::R, args...) where {A, R} = CheckerboardCPM{A, R}(acceptance, proposal, args...)

# printed as the keyword call that rebuilds it; keywords at their defaults are left out
function Base.show(io::IO, a::CheckerboardCPM)
    kw = String[]
    for (k, d) in ((:acceptance, nothing), (:proposal, nothing), (:region, nothing), (:parts, nothing),
            (:switches, 1), (:threads, :auto), (:inline_max_blocks, _INLINE_MAX_BLOCKS),
            (:fused_lifecycle_max_sites, _FUSED_LIFECYCLE_MAX_SITES), (:fused_lifecycle_max_cells, _FUSED_LIFECYCLE_MAX_CELLS),
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
