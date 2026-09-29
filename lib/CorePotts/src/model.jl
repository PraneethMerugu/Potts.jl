# The numerical model interface: state, proposals, and the functions a model supplies.

"""
    CPMState(σ, cell; site = (;), model = (;))

Structure-of-arrays model state.

- `σ`: site → cell id (`Int32`, `0` = medium), an `N`-dimensional array.
- `cell`: `NamedTuple` of per-cell vectors; must contain `kind::Vector{Int32}` and
  `volume::Vector{Int32}`; may contain any other tracked or authored cell quantity.
- `site`, `model`: `NamedTuple`s of per-site arrays and model-level 1-element arrays.
"""
struct CPMState{A, C, S, M}
    σ::A
    cell::C
    site::S
    model::M
end
CPMState(σ, cell; site = (;), model = (;)) = CPMState(σ, cell, site, model)
Adapt.@adapt_structure CPMState

ncells(st::CPMState) = length(st.cell.kind)

"""
    initial_state(σ, kinds; cell = (;), site = (;), model = (;))

Build a host `CPMState`: `σ` labels sites with ids `1:length(kinds)` (`0` = medium) and
`kinds[c] ≥ 1` is the kind of cell `c`. Volumes are computed from `σ`.
"""
function initial_state(σ::AbstractArray{<:Integer}, kinds::AbstractVector{<:Integer};
        cell = (;), site = (;), model = (;))
    n = length(kinds)
    volume = zeros(Int32, n)
    for s in σ
        0 <= s <= n || throw(ArgumentError("site label $s outside 0:$n"))
        s > 0 && (volume[s] += Int32(1))
    end
    all(>=(1), kinds) || throw(ArgumentError("cell kinds must be ≥ 1 (0 is the medium)"))
    base = (; kind = Vector{Int32}(kinds), volume, generation = ones(Int32, n))
    return CPMState(Array{Int32}(σ), merge(base, cell), site, model)
end

"""
    Proposal

One copy attempt: the spin of `source` would be copied into `target` (linear indices);
`x` are the target's coordinates; `old`/`new` are the losing/gaining cells; `dir` indexes
the proposal relation.
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
    Footprint(; read = 1, write = 0)

Largest lattice distance, from the target, that a model's functions read (`read`) and
write besides the target itself (`write`). Sets the checkerboard coloring stride.
"""
Base.@kwdef struct Footprint
    read::Int = 1
    write::Int = 0
end

"""
    CPMFunction(delta_H; commit! = commit_volume!, constraint = always, claims = no_claims,
                temperature, footprint = Footprint(), fingerprint = 0, sys = nothing)

The model, as plain Julia functions (the numerical analogue of `ODEFunction`). Each takes
`(st, p, prop, ctx)` where `ctx` carries the lattice and relations:

- `delta_H` → energy change (plus energy-like drives) of accepting `prop`
- `commit!` → effects of an accepted copy beyond the ownership write (trackers, state)
- `constraint` → `false` vetoes the proposal
- `claims` → tuple of extra cell ids (beyond old/new) whose quantities the other
  functions read; they are claimed in checkerboard execution
- `temperature` → the copy temperature

Symbolic models (`Potts.PottsProblem`) generate these functions; hand-written ones work
identically.
"""
struct CPMFunction{DH, CM, CN, CL, TT, SYS}
    delta_H::DH
    commit!::CM
    constraint::CN
    claims::CL
    temperature::TT
    footprint::Footprint
    fingerprint::UInt64
    sys::SYS
end

function CPMFunction(delta_H; commit! = commit_volume!, constraint = always,
        claims = no_claims, temperature, footprint = Footprint(), fingerprint = 0,
        sys = nothing)
    return CPMFunction(delta_H, commit!, constraint, claims, temperature, footprint,
        UInt64(fingerprint), sys)
end

@inline always(st, p, prop, ctx) = true
@inline no_claims(st, p, prop, ctx) = ()

"""Default `commit!`: maintain `st.cell.volume`."""
@inline function commit_volume!(st, p, prop, ctx)
    prop.old != 0 && @inbounds(st.cell.volume[prop.old] -= Int32(1))
    prop.new != 0 && @inbounds(st.cell.volume[prop.new] += Int32(1))
    return nothing
end

# ---------------------------------------------------------------------------------------
# Energy primitives used by generated and hand-written models.

"""
    contact_delta(σ, ctx, prop, J)

Change of `Σ_{unordered pairs} J(owner, owner′)` over the contact relation when `prop` is
accepted. `J(a, b)` takes cell ids (`0` = medium) and is only evaluated for `a ≠ b`.
"""
@inline function contact_delta(σ, ctx, prop::Proposal{N}, J::F) where {N, F}
    a, b = prop.old, prop.new
    dH = zero(typeof(J(a, b)))
    for off in ctx.contact.offsets
        inside, y = shift(ctx.lattice, prop.x, off)
        inside || continue
        n = @inbounds σ[linear_index(ctx.lattice, y)]
        n != b && (dH += J(b, n))
        n != a && (dH -= J(a, n))
    end
    return dH
end

"""Change of `Σ_cells E(volume, cell)` when `prop` moves one site from `old` to `new`."""
@inline function volume_delta(volume, prop, E::F) where {F}
    a, b = prop.old, prop.new
    dH = zero(typeof(E(Int32(1), Int32(1))))
    if a != 0
        v = @inbounds volume[a]
        dH += E(v - Int32(1), a) - E(v, a)
    end
    if b != 0
        v = @inbounds volume[b]
        dH += E(v + Int32(1), b) - E(v, b)
    end
    return dH
end
