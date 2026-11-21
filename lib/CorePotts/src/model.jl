# The numerical model interface: state, proposals, and the functions a model supplies.

"""
    CPMState(ownership, cell; site = (;), model = (;), history = (;))

The state of a cellular Potts model, as a structure of arrays.

Build a host state with [`initial_state`](@ref), which checks the shapes. The arrays may
live on a device; `Adapt` moves the whole state.

# Arguments
- `ownership`: the cell number of every site, an `N`-dimensional `Int32` array (`0` is the
  medium). The papers write it σ.
- `cell`: a `NamedTuple` of per-cell arrays, whose last dimension is the cell number. It
  holds `kind`, `volume` and `generation` (`Vector{Int32}` each), and any other tracked or
  authored cell quantity.

# Keywords
- `site = (;)`: per-site arrays, shaped like `ownership` (or like a coarse grid).
- `model = (;)`: model-level quantities, each a 1-element array. Medium properties live
  here.
- `history = (;)`: ring buffers of past values ([`history_buffer`](@ref)).

# Fields
- `ownership`, `cell`, `site`, `model`, `history`: as above.

# Examples
```jldoctest
julia> using CorePotts

julia> st = initial_state(Int32[0 1; 1 2], [1, 2]);

julia> volumes(st), cell_kinds(st)
(Int32[2, 1], Int32[1, 2])
```

See also [`initial_state`](@ref), [`ownership`](@ref), [`volumes`](@ref).
"""
struct CPMState{A, C, S, M, H}
    ownership::A
    cell::C
    site::S
    model::M
    history::H
end
function CPMState(ownership, cell; site = (;), model = (;), history = (;))
    return CPMState(ownership, cell, site, model, history)
end
Adapt.@adapt_structure CPMState

ncells(st::CPMState) = length(st.cell.kind)

# Saved-state accessors: the arrays of a state by name.
"""
    ownership(st::CPMState) -> AbstractArray{Int32}

Return the cell number of every site of `st` (`0` is the medium).

# Arguments
- `st::CPMState`: the state.

# Returns
- The live `ownership` array (not a copy), on the state's backend.

See also [`cell_kinds`](@ref), [`volumes`](@ref).
"""
ownership(st::CPMState) = st.ownership
"""
    cell_kinds(st::CPMState) -> AbstractVector{Int32}

Return the kind of every cell slot of `st`.

Cells have kinds `1, 2, …`; the medium's kind `0` is not stored.

# Arguments
- `st::CPMState`: the state.

# Returns
- The live `st.cell.kind` vector (not a copy).

See also [`ownership`](@ref), [`volumes`](@ref).
"""
cell_kinds(st::CPMState) = st.cell.kind
"""
    cell_generations(st::CPMState) -> AbstractVector{Int32}

Return the generation of every cell slot of `st`.

A slot's generation starts at 1 and increases by one each time the slot is reused for a
new cell (a division daughter or a converted cell). Cell-addressed random draws use it
(see [`cell_entity`](@ref)), so a reused slot does not repeat its earlier draws.

# Arguments
- `st::CPMState`: the state.

# Returns
- The live `st.cell.generation` vector (not a copy).

See also [`cell_kinds`](@ref).
"""
cell_generations(st::CPMState) = st.cell.generation
"""
    volumes(st::CPMState) -> AbstractVector{Int32}

Return the volume, in sites, of every cell slot of `st` (`0` for a free slot).

# Arguments
- `st::CPMState`: the state.

# Returns
- The live `st.cell.volume` vector (not a copy).

# Examples
```jldoctest
julia> using CorePotts

julia> volumes(initial_state(Int32[1 1 0; 2 0 0], [1, 1]))
2-element Vector{Int32}:
 2
 1
```

See also [`ownership`](@ref), [`cell_kinds`](@ref).
"""
volumes(st::CPMState) = st.cell.volume

"""
    initial_state(σ, kinds; cell = (;), site = (;), model = (;), history = (;),
                  shapes = (;))

Build a host [`CPMState`](@ref) from a site array and the kinds of its cells.

The volumes are counted from `σ`, and every generation is set to 1. Each `cell` array must
have one entry per cell along its last dimension, each `model` value must be a 1-element
array, and each `site` array must have the size of `σ`. A site quantity named in `shapes`
must have that size instead (a field on a coarse grid). Any other shape, a cell number
outside `0:length(kinds)` or a kind below 1 throws an `ArgumentError`.

# Arguments
- `σ::AbstractArray{<:Integer}`: the cell number of every site, `0` for the medium and
  `1:length(kinds)` for the cells.
- `kinds::AbstractVector{<:Integer}`: the kind of each cell, all `≥ 1`.

# Keywords
- `cell = (;)`: extra per-cell arrays, merged after `kind`, `volume` and `generation`.
- `site = (;)`: per-site arrays.
- `model = (;)`: model-level quantities, each a 1-element array.
- `history = (;)`: ring buffers ([`history_buffer`](@ref)), not checked.
- `shapes = (;)`: the size of each site quantity that is not on the lattice, by name.

# Returns
- `CPMState`: `ownership` is an `Array{Int32}` copy of `σ`.

# Examples
```jldoctest
julia> using CorePotts

julia> st = initial_state(Int32[0 1; 1 2], [1, 2]; cell = (; target = [2.0, 1.0]));

julia> keys(st.cell)
(:kind, :volume, :generation, :target)
```

See also [`CPMState`](@ref), [`PottsProblem`](@ref).
"""
function initial_state(
        σ::AbstractArray{<:Integer}, kinds::AbstractVector{<:Integer};
        cell = (;), site = (;), model = (;), history = (;), shapes = (;)
    )
    n = length(kinds)
    volume = zeros(Int32, n)
    for s in σ
        0 <= s <= n || throw(ArgumentError("site label $s outside 0:$n"))
        s > 0 && (volume[s] += Int32(1))
    end
    all(>=(1), kinds) || throw(ArgumentError("cell kinds must be ≥ 1 (0 is the medium)"))
    base = (; kind = Vector{Int32}(kinds), volume, generation = ones(Int32, n))
    for (name, a) in pairs(site)
        want = haskey(shapes, name) ? Tuple(shapes[name]) : size(σ)
        size(a) == want && continue
        grid = if want == size(σ)
            "lattice $(size(σ))"
        else
            "its grid $want (lattice $(size(σ)))"
        end
        throw(ArgumentError("site quantity `$name` has size $(size(a)), $grid"))
    end
    for (name, a) in pairs(cell)
        size(a, ndims(a)) == n ||
            throw(ArgumentError("cell quantity `$name` has last \
                dimension $(size(a, ndims(a))), expected $n cells"))
    end
    for (name, a) in pairs(model)
        a isa AbstractArray && length(a) == 1 ||
            throw(ArgumentError("model quantity `$name` must be a 1-element array"))
    end
    return CPMState(Array{Int32}(σ), merge(base, cell), site, model, history)
end

"""
    Proposal{N}

One copy attempt: the cell number of `source` would be copied into `target`.

The algorithms build it and pass it to every model function as `prop`.

# Fields
- `target::Int`: the linear index of the target site.
- `source::Int`: the linear index of the source site.
- `x::NTuple{N, Int}`: the target's lattice coordinates.
- `dir::Int`: the offset number of the source in the proposal relation.
- `old::Int32`: the cell that would lose the target (`0` = medium).
- `new::Int32`: the cell that would gain the target (`0` = medium).

See also [`CPMFunction`](@ref).
"""
struct Proposal{N}
    target::Int
    source::Int
    x::NTuple{N, Int}
    dir::Int
    old::Int32
    new::Int32
end

"""
    Footprint(; read = 1, write = 0, source_read = -1, source_write = -1)

The lattice distances that a model's copy-step functions read and write, which set the
spacing of [`CheckerboardCPM`](@ref)'s blocks.

The distances are Chebyshev distances in sites. Reads and writes anchored at the source
reach [`radius`](@ref)`(proposal)` further from the target. The effective read distance is
the largest of `read`, the proposal radius and the source read reach; the effective write
distance is the larger of `write` and the source write reach.

# Keywords
- `read = 1`: the largest distance from the target that the functions read.
- `write = 0`: the largest distance from the target that they write, besides the target
  itself.
- `source_read = -1`: the largest distance from the source that they read, `-1` for none.
- `source_write = -1`: the largest distance from the source that they write, `-1` for
  none.

# Examples
```jldoctest
julia> using CorePotts

julia> Footprint(; read = 2).write
0
```

See also [`CPMFunction`](@ref), [`CheckerboardCPM`](@ref).
"""
Base.@kwdef struct Footprint
    read::Int = 1
    write::Int = 0
    source_read::Int = -1
    source_write::Int = -1
end

"""
Effective `(read, write)` distances from the target under proposal relation `proposal`.
"""
function reach(fp::Footprint, proposal)
    rp = radius(proposal)
    read = max(fp.read, rp, fp.source_read >= 0 ? rp + fp.source_read : 0)
    write = max(fp.write, fp.source_write >= 0 ? rp + fp.source_write : 0)
    return read, write
end

"""
    CPMFunction(delta_H; commit! = commit_volume!, constraint = always, temperature,
                bias = no_bias, phases = Phases(), lifecycle = nothing,
                acceptance = nothing, footprint = Footprint(), fingerprint = 0,
                sys = nothing, track = nothing, connectivity = nothing)

The model, as plain Julia functions: the numerical analogue of `ODEFunction`.

The per-copy functions take `(st, p, prop, ctx)`: the state, the parameters, the
[`Proposal`](@ref) and the context, which holds the lattice and the relations. Symbolic
models (`Potts.PottsProblem`) generate these functions; hand-written functions work the
same way.

[`CheckerboardCPM`](@ref) spaces its blocks by `footprint`. It widens that spacing to the
contact relation and to any relation in the problem that reaches farther. A symbolic layer
may narrow it to the relations that its generated copy-step functions read
([`copy_step_relations`](@ref)), but only while every copy-step function is its own.

# Arguments
- `delta_H`: the energy change of accepting `prop`, plus any energy-like drives.

# Keywords
- `commit! = commit_volume!`: the effects of an accepted copy beyond the `ownership`
  write (trackers, state).
- `constraint = always`: returns `false` to veto the copy attempt.
- `temperature`: the temperature `T` of the copy attempt (required).
- `bias = no_bias`: a term added to log α, not energy-like: the effective energy change is
  `ΔH − T·bias`.
- `phases = Phases()`: synchronous work before and after each sweep ([`Phases`](@ref)).
- `lifecycle = nothing`: division, removal and transition rules ([`Lifecycle`](@ref)).
- `acceptance = nothing`: the acceptance rule ([`Metropolis`](@ref) or
  [`Barker`](@ref)), used unless the algorithm sets one. `nothing` means `Metropolis()`.
- `footprint = Footprint()`: the read and write distances ([`Footprint`](@ref)).
- `fingerprint = 0`: an identity of the model's code, stored as `UInt64`.
- `sys = nothing`: the symbolic system the functions came from, or `nothing`.
- `track = nothing`: `nothing` accumulates and compiles nothing. Otherwise a callable
  `track(st, p, prop, ctx, dH)`, whose value for every committed copy is summed into
  `stats.accepted_energy_change`. `dH` is the value of `delta_H`, without the bias and the
  acceptance rule's offset. [`TrackEnergyChange`](@ref) sums `dH` itself. Under
  `CheckerboardCPM` a custom callable must also define [`track_eltype`](@ref);
  `SequentialCPM` adds into a `Float64` and does not need it.
- `connectivity = nothing`: the [`ConnectivityHooks`](@ref) of a model with whole-cell
  connectivity, or `nothing`.

# Examples
```julia
using CorePotts
J(a, b) = (a == 0) | (b == 0) ? 16.0 : 2.0
dH(st, p, prop, ctx) = contact_delta(st.ownership, ctx, prop, J) +
    volume_delta(st.cell.volume, prop, (v, c) -> 50.0 * (v - 25)^2)
f = CPMFunction(dH; temperature = (st, p, prop, ctx) -> 10.0)
```

See also [`PottsProblem`](@ref), [`Footprint`](@ref), [`Phases`](@ref).
"""
struct CPMFunction{DH, CM, CN, TT, BI, PH, LC, AC, SYS, TK, CO}
    delta_H::DH
    commit!::CM
    constraint::CN
    temperature::TT
    bias::BI
    phases::PH
    lifecycle::LC
    acceptance::AC
    footprint::Footprint
    fingerprint::UInt64
    sys::SYS
    track::TK
    connectivity::CO
end

function CPMFunction(
        delta_H; commit! = commit_volume!, constraint = always,
        temperature, bias = no_bias, phases = NO_PHASES,
        lifecycle = nothing, acceptance = nothing, footprint = Footprint(), fingerprint = 0,
        sys = nothing, track = nothing, connectivity = nothing
    )
    return CPMFunction(
        delta_H, commit!, constraint, temperature, bias, phases,
        lifecycle, acceptance, footprint, UInt64(fingerprint), sys, track, connectivity
    )
end

"""
    TrackEnergyChange{T}()

The `track` of a [`CPMFunction`](@ref) that sums the energy change ΔH of each committed
copy.

Potts sets it for `track = (:energy_change,)`. `T` is the model's scalar type.
[`CheckerboardCPM`](@ref) accumulates per site in `T`, on the device, between host read
points, which reduce into the `Float64` `stats.accepted_energy_change`.
[`SequentialCPM`](@ref) adds into a `Float64` directly. On the CPU the sum is the exact
change of the energy. On a device, the checkerboard's copies of one cell can be in flight
together, each with ΔH taken against the cell's totals before the other's commit, so the
sum can differ slightly from the change of the energy.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.track_eltype(CorePotts.TrackEnergyChange{Float32}())
Float32
```

See also [`track_eltype`](@ref).
"""
struct TrackEnergyChange{T} end
@inline (::TrackEnergyChange)(st, p, prop, ctx, dH) = dH
"""
    track_eltype(track) -> Type

Return the scalar type of a `track` callable's values (`CPMFunction(…; track)`).

[`CheckerboardCPM`](@ref) accumulates the values per site in this type between host read
points. [`TrackEnergyChange`](@ref)`{T}` returns `T`. Define a method for a custom track,
for example `CorePotts.track_eltype(::MyTrack) = Float64` (`Float32` on Metal). The
fallback throws an `ArgumentError`.

# Arguments
- `track`: the callable.

# Returns
- The scalar type.

See also [`TrackEnergyChange`](@ref), [`CPMFunction`](@ref).
"""
track_eltype(::TrackEnergyChange{T}) where {T} = T
function track_eltype(track)
    throw(
        ArgumentError(
            "CheckerboardCPM needs the scalar type of the custom track $(typeof(track)): " *
                "define `CorePotts.track_eltype(::$(typeof(track))) = Float64` (Float32 on \
                    a device)"
        )
    )
end

"""
The device-side part of a `CPMFunction`: the per-proposal functions, without host-only
fields (`phases`, `sys`), so it is isbits whenever the functions are.
"""
struct DeviceFunctions{DH, CM, CN, TT, BI, PO, DF}
    delta_H::DH
    commit!::CM
    constraint::CN
    temperature::TT
    bias::BI
    # the `Global` veto after the draw (`ConnectivityHooks`), or `nothing`
    post::PO
    defer::DF           # copies the checkerboard runs serially, or `nothing`
end
function DeviceFunctions(delta_H, commit!, constraint, temperature, bias)
    return DeviceFunctions(
        delta_H, commit!, constraint, temperature, bias, nothing, nothing
    )
end
# The track (D-140) is not part of it: the checkerboard carries it with its buffers and
# `SequentialCPM` takes it as an argument, so untracked kernels see exactly these fields
# (`post` and `defer` are `nothing`, zero-size, without whole-cell connectivity).
function device_functions(f::CPMFunction)
    return DeviceFunctions(
        f.delta_H, f.commit!, f.constraint, f.temperature, f.bias,
        _hook(f.connectivity, :post), _hook(f.connectivity, :defer)
    )
end
_hook(::Nothing, name) = nothing
_hook(h, name) = getfield(h, name)
# the hooks of `DeviceFunctions` (or of a `CPMFunction` passed directly)
@inline _post(f) = f.post
@inline _post(f::CPMFunction) = _hook(f.connectivity, :post)
@inline _defer(f) = f.defer
@inline _defer(f::CPMFunction) = _hook(f.connectivity, :defer)
"""Whether `f` has a post-acceptance veto (`Global`; a type-level constant)."""
@inline has_post(f) = !(_post(f) isa Nothing)
"""Whether `f` defers some copies to the serial floods (a type-level constant)."""
@inline has_defer(f) = !(_defer(f) isa Nothing)

"""
    always(st, p, prop, ctx) -> true

The default `constraint` of a [`CPMFunction`](@ref): allow every copy attempt.

# Arguments
- `st`, `p`, `prop`, `ctx`: the state, parameters, proposal and context (unused).

# Returns
- `true`.

See also [`no_bias`](@ref).
"""
@inline always(st, p, prop, ctx) = true
"""Whether the context is the lockless checkerboard's (`lockless = true`; a type-level
constant): commit hooks that would overwrite a cell value add their change atomically
instead."""
@inline _lockless(::NamedTuple{K}) where {K} = :lockless in K
@inline _lockless(ctx) = false
"""
    no_bias(st, p, prop, ctx) -> false

The default `bias` of a [`CPMFunction`](@ref): no copy attempt is biased.

`false` acts as zero in the effective energy change `ΔH − T·bias`.

# Arguments
- `st`, `p`, `prop`, `ctx`: the state, parameters, proposal and context (unused).

# Returns
- `false`.

See also [`always`](@ref).
"""
@inline no_bias(st, p, prop, ctx) = false

"""Effective energy change: `ΔH − T·bias` (a bias adds directly to log α)."""
@inline _effective_dH(f, dH, T, st, p, prop, ctx) = dH - T * f.bias(st, p, prop, ctx)

"""
    oncopy_cell!(a, j, v, pre, ctx) -> nothing

Write the value `v` of an `@on_copy` rule into cell `j` of the cell column `a`.

`v` was computed while `a[j] == pre`. On the lockless checkerboard (`ctx.lockless`), a
numeric column (integer or float, not `Bool`) gets the change `v - pre` by an atomic add,
so concurrent copies into one cell all count (`n[new] ~ n[new] + 1`). Otherwise, and for
other element types, `v` is stored. `j = 0`, the medium, writes nothing.

# Arguments
- `a::AbstractVector`: the cell column.
- `j`: the cell number, `0` or in `1:length(a)`.
- `v`: the new value.
- `pre`: the value of `a[j]` that `v` was computed from.
- `ctx`: the copy-step context.

# Returns
- `nothing`.
"""
@inline function oncopy_cell!(a, j, v, pre, ctx)
    j == 0 && return nothing
    T = eltype(a)
    if _lockless(ctx) && T <: Union{Integer, AbstractFloat} && !(T <: Bool)
        # a cell id is in 1:capacity
        Atomix.@atomic a[j] += convert(T, v) - convert(T, pre)
    else
        # bounds: j is a cell id in 1:capacity = length(a)
        @inbounds a[j] = convert(T, v)
    end
    return nothing
end

"""
    commit_volume!(st, p, prop, ctx) -> nothing

The default `commit!` of a [`CPMFunction`](@ref): keep `st.cell.volume` up to date.

The losing cell's volume decreases by one and the gaining cell's increases by one; the
medium (`0`) has no entry. The adds are atomic, because checkerboard copies into one cell
can commit concurrently.

# Arguments
- `st::CPMState`: the state.
- `p`, `ctx`: the parameters and the context (unused).
- `prop::Proposal`: the accepted copy.

# Returns
- `nothing`.

See also [`volume_delta`](@ref).
"""
@inline function commit_volume!(st, p, prop, ctx)
    # bounds: nonzero owners are cell ids ≤ capacity = length(volume)
    prop.old != 0 && @inbounds(Atomix.@atomic st.cell.volume[prop.old] -= Int32(1))
    prop.new != 0 && @inbounds(Atomix.@atomic st.cell.volume[prop.new] += Int32(1))
    return nothing
end

# ---------------------------------------------------------------------------------------
# Energy primitives used by generated and hand-written models.

"""
    contact_delta(σ, ctx, prop, J; relation = ctx.contact)

Return the change of the contact energy `Σ w·J(σᵢ, σⱼ)`, over unordered pairs of
neighboring sites, when `prop` is accepted.

Only the pairs at the target change. `J(a, b)` takes two cell numbers (`0` = medium) and
is called only for `a ≠ b`. `w` is the relation's [`weight`](@ref) of the offset.

# Arguments
- `σ`: the `ownership` array.
- `ctx`: the copy-step context, which holds `lattice` and the relations.
- `prop::Proposal`: the copy attempt.
- `J`: the contact energy of a pair of cell numbers.

# Keywords
- `relation = ctx.contact`: the contact relation.

# Returns
- The energy change, in the type of `J`'s values.

# Examples
```julia
J(a, b) = (a == 0) | (b == 0) ? 16.0 : 2.0
dH(st, p, prop, ctx) = contact_delta(st.ownership, ctx, prop, J)
```

See also [`volume_delta`](@ref), [`surface_delta`](@ref).
"""
@inline function contact_delta(
        σ, ctx, prop::Proposal{N}, J::F;
        relation = ctx.contact
    ) where {N, F}
    a, b = prop.old, prop.new
    dH = zero(typeof(J(a, b)))
    for k in 1:length(relation)
        # bounds: k ≤ length(relation); inside sites have linear indices ≤ nsites
        inside, y = shift(ctx.lattice, prop.x, @inbounds relation.offsets[k])
        inside || continue
        n = @inbounds σ[linear_index(ctx.lattice, y)]
        w = weight(relation, k)
        n != b && (dH += w * J(b, n))
        n != a && (dH -= w * J(a, n))
    end
    return dH
end

"""
    surface_change(σ, ctx, prop; relation = ctx.surface, T = <weight type>) -> (δold, δnew)

Return the change of the surfaces of the losing and the gaining cell when `prop` is
accepted.

A cell's surface is the weighted count of its bonds, over `relation`, to sites of other
cells. Only these two cells' surfaces change. The losing cell gains the bonds to its own
sites and loses the others; the gaining cell does the opposite.

# Arguments
- `σ`: the `ownership` array.
- `ctx`: the copy-step context.
- `prop::Proposal`: the copy attempt.

# Keywords
- `relation = ctx.surface`: the surface relation.
- `T = typeof(weight(relation, 1))`: the accumulation type: `Int32` for an unweighted
  relation, `Float32` for a weighted one. Pass the tracker's element type; `Float32`
  weights convert exactly.

# Returns
- `(δold, δnew)`: the two changes, of type `T`. Pass them to [`surface_delta`](@ref) and
  [`commit_surface!`](@ref).

See also [`surface_delta`](@ref), [`commit_surface!`](@ref), [`recompute_surface`](@ref).
"""
@inline function surface_change(
        σ, ctx, prop::Proposal{N}; relation = ctx.surface,
        T::Type = typeof(weight(relation, 1))
    ) where {N}
    a, b = prop.old, prop.new
    δa = zero(T)
    δb = δa
    for k in 1:length(relation)
        # bounds: k ≤ length(relation); inside sites have linear indices ≤ nsites
        inside, y = shift(ctx.lattice, prop.x, @inbounds relation.offsets[k])
        inside || continue
        n = @inbounds σ[linear_index(ctx.lattice, y)]
        w = T(weight(relation, k))
        δa += ifelse(n == a, w, -w)     # t leaves a: bonds to a appear, others vanish
        δb += ifelse(n == b, -w, w)     # t joins b: bonds to b vanish, others appear
    end
    return δa, δb
end

"""
    surface_delta(surface, prop, δ, E)

Return the change of `Σ_cells E(surface, cell)` for the surface change
`δ = surface_change(…)`.

The medium (`0`) has no surface term.

# Arguments
- `surface::AbstractVector`: the surface tracker, one entry per cell.
- `prop::Proposal`: the copy attempt.
- `δ`: the `(δold, δnew)` of [`surface_change`](@ref).
- `E`: the energy `E(s, c)` of cell `c` at surface `s`.

# Returns
- The energy change, in the type of `E`'s values.

# Examples
```julia
function dH(st, p, prop, ctx)
    δ = surface_change(st.ownership, ctx, prop; T = eltype(st.cell.surface))
    return surface_delta(st.cell.surface, prop, δ, (s, c) -> 0.5 * (s - 20)^2)
end
```

See also [`surface_change`](@ref), [`commit_surface!`](@ref).
"""
@inline function surface_delta(surface, prop, δ, E::F) where {F}
    a, b = prop.old, prop.new
    δa, δb = δ
    dH = zero(typeof(E(zero(eltype(surface)), Int32(1))))
    if a != 0
        # bounds: nonzero owners a, b are cell ids ≤ capacity = length(surface)
        s = @inbounds surface[a]
        dH += E(s + δa, a) - E(s, a)
    end
    if b != 0
        s = @inbounds surface[b]
        dH += E(s + δb, b) - E(s, b)
    end
    return dH
end

"""
    commit_surface!(surface, prop, δ) -> nothing

Add the surface change `δ = surface_change(…)` to a surface tracker.

It may run before or after the `ownership` write, because the surface relation excludes
the zero offset (checked at `init`). The adds are atomic, as in
[`commit_volume!`](@ref).

# Arguments
- `surface::AbstractVector`: the surface tracker.
- `prop::Proposal`: the accepted copy.
- `δ`: the `(δold, δnew)` of [`surface_change`](@ref).

# Returns
- `nothing`.

See also [`surface_change`](@ref), [`recompute_surface`](@ref).
"""
@inline function commit_surface!(surface, prop, δ)
    # atomic: as `commit_volume!`
    prop.old != 0 && @inbounds(Atomix.@atomic surface[prop.old] += δ[1])
    prop.new != 0 && @inbounds(Atomix.@atomic surface[prop.new] += δ[2])
    return nothing
end

"""
    site_delta(prop, E)

Return the change of `Σ_sites E(site, cell)` when the target changes cell:
`E(target, new) − E(target, old)`.

# Arguments
- `prop::Proposal`: the copy attempt.
- `E`: the energy `E(i, c)` of site `i` owned by cell `c`.

# Returns
- The energy change, in the type of `E`'s values.

# Examples
```julia
# a kind-dependent energy for each site of a field `φ`
dH(st, p, prop, ctx) = site_delta(prop, (i, c) -> c == 0 ? 0.0 : -st.site.φ[i])
```

See also [`volume_delta`](@ref).
"""
@inline function site_delta(prop, E::F) where {F}
    return E(prop.target, prop.new) -
        E(prop.target, prop.old)
end

"""
    recompute_surface(σ, lattice, relation, ncell; T = <weight type>) -> Vector{T}

Compute every cell's surface from scratch, for initialization and tracker checks.

The surface of cell `c` is the weighted count of its bonds, over `relation`, to sites of
other cells (including the medium). The medium itself has no entry.

# Arguments
- `σ`: the `ownership` array, on the host.
- `lattice::Lattice`: the lattice.
- `relation`: the surface relation, from [`relation`](@ref).
- `ncell::Integer`: the number of cell slots.

# Keywords
- `T = typeof(weight(relation, 1))`: the element type: `Int32` for an unweighted relation,
  `Float32` for a weighted one. Pass `T = Float64` for long CPU runs.

# Returns
- `Vector{T}`: one surface per cell slot.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((4, 4)); σ = zeros(Int32, 4, 4); σ[2:3, 2:3] .= 1;

julia> recompute_surface(σ, l, relation(VonNeumann(), l), 1)
1-element Vector{Int32}:
 8
```

See also [`surface_change`](@ref), [`commit_surface!`](@ref).
"""
function recompute_surface(
        σ, lat::Lattice, r::Relation, ncell::Integer; T::Type = typeof(weight(r, 1))
    )
    return _recompute_surface(T, σ, lat, r, ncell)
end

function _recompute_surface(
        ::Type{T}, σ, lat::Lattice, r::Relation, ncell::Integer
    ) where {T}
    S = zeros(T, ncell)
    for i in 1:nsites(lat)
        c = σ[i]
        c == 0 && continue
        x = coordinates(lat, i)
        for k in 1:length(r)
            inside, y = shift(lat, x, r.offsets[k])
            inside || continue
            σ[linear_index(lat, y)] != c && (S[c] += T(weight(r, k)))
        end
    end
    return S
end

# The same sum in integer weight units `u` (`_units_for`): each entry is the exact
# sum of the quantized weights, converted once, as the device lifecycle's cluster-surface
# fold writes it (so the host and a device agree bitwise)
function _recompute_surface(
        ::Type{T}, σ, lat::Lattice, r::Relation, ncell::Integer, u::NamedTuple
    ) where {T}
    A = zeros(Int64, ncell)
    for i in 1:nsites(lat)
        c = σ[i]
        c == 0 && continue
        x = coordinates(lat, i)
        for k in 1:length(r)
            inside, y = shift(lat, x, r.offsets[k])
            inside || continue
            σ[linear_index(lat, y)] != c && (A[c] += u.q[k])
        end
    end
    return [_wvalue(T, a, u.e) for a in A]
end
function _recompute_surface(
        ::Type{T}, σ, lat::Lattice, r::Relation, ncell::Integer, ::Nothing
    ) where {T}
    return _recompute_surface(T, σ, lat, r, ncell)
end

"""
    volume_delta(volume, prop, E)

Return the change of `Σ_cells E(volume, cell)` when `prop` moves the target from the
losing cell to the gaining cell.

The losing cell's volume drops by one and the gaining cell's rises by one. The medium
(`0`) has no volume term.

# Arguments
- `volume::AbstractVector`: the volume tracker (`st.cell.volume`).
- `prop::Proposal`: the copy attempt.
- `E`: the energy `E(v, c)` of cell `c` at volume `v`.

# Returns
- The energy change, in the type of `E`'s values.

# Examples
```julia
dH(st, p, prop, ctx) = volume_delta(st.cell.volume, prop, (v, c) -> 50.0 * (v - 25)^2)
```

See also [`commit_volume!`](@ref), [`contact_delta`](@ref).
"""
@inline function volume_delta(volume, prop, E::F) where {F}
    a, b = prop.old, prop.new
    dH = zero(typeof(E(Int32(1), Int32(1))))
    if a != 0
        # bounds: nonzero owners a, b are cell ids ≤ capacity = length(volume)
        v = @inbounds volume[a]
        dH += E(v - Int32(1), a) - E(v, a)
    end
    if b != 0
        v = @inbounds volume[b]
        dH += E(v + Int32(1), b) - E(v, b)
    end
    return dH
end
