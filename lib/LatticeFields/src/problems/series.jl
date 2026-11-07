# Solutions of lattice problems (F4-04; F4 design §3.5): an owned solve returns SciML's
# `ODESolution` (linear interpolation: `sol(t)`, `Array(sol)`, `sol.ps`, `sol.alg`, `sol.stats`),
# and a field read on any solution of a lattice problem (owned or OrdinaryDiffEq) is time first,
# MethodOfLines' shape (Q-G), as a lazy view of the saves.

"""
    FieldSeries

A field's values over the saves of a solution, time first (F4-04; MethodOfLines' shape, ruling
Q-G): an `AbstractArray` of size `(nt, dims...)` whose entries are read from the saved states
when indexed, with no copy of the series. `s[i, :, :]` (or `sol[c, i]`) is the grid at save `i`,
`Array(s)` copies the whole series. An aux field (`K ~ rhs`) is evaluated from the saved state
at each save time when that save is read. On a device the saves are device arrays: read whole
grids (`s[i, :, :]`, `Array(s)`), not single entries.
"""
struct FieldSeries{T, N, F} <: AbstractArray{T, N}
    size::NTuple{N, Int}
    slice::F                            # i -> the grid at save i (a view of the save for a state field)
end
FieldSeries{T}(size::NTuple{N, Int}, slice::F) where {T, N, F} = FieldSeries{T, N, F}(size, slice)
Base.size(s::FieldSeries) = s.size
Base.IndexStyle(::Type{<:FieldSeries}) = IndexCartesian()
Base.@propagate_inbounds Base.getindex(s::FieldSeries{T, N}, I::Vararg{Int, N}) where {T, N} =
    s.slice(I[1])[Base.tail(I)...]
# a whole grid at save `i` (a copy, on the saves' device)
Base.getindex(s::FieldSeries{T, N}, i::Int, c::Colon, cs::Colon...) where {T, N} =
    length(cs) == N - 2 ? copy(s.slice(i)) : invoke(getindex, Tuple{AbstractArray, Vararg{Any}}, s, i, c, cs...)
function Base.Array(s::FieldSeries{T}) where {T}
    out = Array{T}(undef, s.size)
    for i in 1:s.size[1]
        selectdim(out, 1, i) .= Array(s.slice(i))
    end
    return out
end

# a state field `slot` of the flat saves `u`
struct _StateSlice{U, R, D}
    u::U
    range::R                            # the field's indices in a save
    dims::D
end
(s::_StateSlice)(i) = reshape(view(s.u[i], s.range), s.dims)
# an aux field of the saves, evaluated at each save time (the last one read is kept)
mutable struct _AuxSlice{S}
    sol::S
    key::String
    i::Int
    last::Any
end
function (s::_AuxSlice)(i)
    i == s.i && return s.last
    ix = _lindex(s.sol)
    s.last = ix.auxeval[](s.sol.u[i], s.sol.prob.p, s.sol.t[i], s.key)
    s.i = i
    return s.last
end

"""
    field_series(sol, c) -> FieldSeries

The time-first values of the field, aux field or input `c` of a solution (F4-04; F4 design
§3.5, ruling Q4): `size = (length(sol.t), dims...)`, a lazy view of the saves. In front end B
`sol[c]` is the same; in front end A (`PottsSolution`, per-MCS states) this accessor gives the
time-first view.
"""
function field_series(sol, sym)
    s = _field_series(sol, sym)
    s === nothing || return s
    ix = _lindex(sol)
    ix isa LatticeIndex && throw(ArgumentError(string("field_series: `", _symtext(sym), "` is not a field of the ",
        "solution's problem; its fields: ", join(("`$(_symtext(v))`" for v in ix.varsyms), ", "))))
    # another solution (front end A's per-MCS states): the grid of each save through SII's getter
    g = SII.getsym(sol, sym)
    nt = length(sol.t)
    nt == 0 && throw(ArgumentError("field_series: the solution has no saves"))
    v = g(sol, 1)
    v isa AbstractArray || throw(ArgumentError(string("field_series: `", _symtext(sym), "` is not a field (it reads ",
        "a ", typeof(v), " per save)")))
    return FieldSeries{eltype(v)}((nt, size(v)...), _GetterSlice(g, sol))
end
struct _GetterSlice{G, S}
    g::G
    sol::S
end
(s::_GetterSlice)(i) = s.g(s.sol, i)
# the series of `sym` when it names a state or aux field of a lattice solution, else nothing
# the `LatticeIndex` of a solution (a solution's container is its problem, whose is the index)
function _lindex(x)
    for _ in 1:4
        x isa LatticeIndex && return x
        y = SII.symbolic_container(x)
        y === x && return nothing
        x = y
    end
    return nothing
end
function _field_series(sol, sym)
    ix = _lindex(sol)
    ix isa LatticeIndex || return nothing
    sym isa Union{AbstractArray, Tuple} && return nothing
    k = ix.key(sym)
    nt = length(sol.t)
    slot = get(ix.vars, k, nothing)
    if slot isa FieldSlot
        T = eltype(eltype(sol.u))
        r = slot.range
        nt > 0 && length(sol.u[1]) < last(r) && return nothing   # (a subset SciML saved: its own reads)
        return FieldSeries{T}((nt, slot.dims...), _StateSlice(sol.u, r, slot.dims))
    end
    a = get(ix.aux, k, nothing)
    if a !== nothing
        ix.auxeval[] === nothing && return nothing
        g = _AuxSlice(sol, a, 0, nothing)
        nt == 0 && return FieldSeries{eltype(eltype(sol.u))}((0,), g)
        v = g(1)
        return FieldSeries{eltype(v)}((nt, size(v)...), g)
    end
    return nothing
end

"""
    LatticeStats

The statistics of an owned solve (`sol.stats`, F4-04): `nf` the windows stepped (shortened ones
too), `nsolve` the implicit solves, `counts` the substep count of each field group
([`substep_counts`](@ref)), and the solver counters of the groups' status words
([`field_stats`](@ref)): `solves`, `budget`, `floor`, `newton_budget`.
"""
struct LatticeStats
    nf::Int
    nsolve::Int
    counts::Vector{Int}
    solves::Int64
    budget::Int64
    floor::Int64
    newton_budget::Int64
end
function LatticeStats(integ::FieldIntegrator)
    f = field_stats(integ)
    return LatticeStats(integ.windows, f.solves, substep_counts(integ), f.solves, f.budget, f.floor, f.newton_budget)
end
const LatticeSolution = typewith(SciMLBase.ODESolution, :prob, LatticeProblem)
field_stats(s::LatticeSolution) = _stats(s.stats)
_stats(t::LatticeStats) = (; solves = t.solves, budget = t.budget, floor = t.floor, newton_budget = t.newton_budget)
_stats(t) = throw(ArgumentError("field_stats: the solution was not computed by a field algorithm (an owned solve)"))
substep_counts(s::LatticeSolution) = s.stats isa LatticeStats ? copy(s.stats.counts) :
    throw(ArgumentError("substep_counts: the solution was not computed by a field algorithm (an owned solve)"))

# the solution of an owned solve of the SciML problem `sp` (F4-04): `build_solution` over the
# saves, with linear interpolation (a map's states are constant between steps), and `prob` at
# the integrator's current parameters, tables and inputs (`sol.ps` reads the values written
# during the run)
function _ode_solution(integ::FieldIntegrator, sp)
    q = _final_problem(integ, sp)
    ts, us = integ.ts, integ.us
    interp = sp isa SciMLBase.DiscreteProblem ? SciMLBase.ConstantInterpolation(ts, us) :
             SciMLBase.LinearInterpolation(ts, us)
    return SciMLBase.build_solution(q, integ.alg, ts, us; interp, dense = true, retcode = integ.retcode,
        stats = LatticeStats(integ))
end
function _final_problem(integ::FieldIntegrator, sp)
    lp = sp.p
    lp isa LatticeParameters || return sp
    ins = Pair{String, Any}[k => (v === nothing ? v : _read_input(integ, k)) for (k, v) in lp.inputs]
    q = LatticeParameters(copy(integ.p), eltype(integ.tables)[k => copy(v) for (k, v) in integ.tables], ins;
        tick = _tick(integ))
    T = sp isa SciMLBase.DiscreteProblem ? SciMLBase.DiscreteProblem : SciMLBase.ODEProblem
    return invoke(SciMLBase.remake, Tuple{T}, sp; p = q)
end

# Time-first reads on every solution of a lattice problem (Q-G): `sol[c]` of a state or aux field
# is a `FieldSeries`; `sol[x]` the coordinates of the site centers; anything else as SciML reads it.
# (The methods for integer, colon and index-array arguments keep SciML's reads, unambiguously.)
function Base.getindex(sol::LatticeSolution, sym)
    s = _field_series(sol, sym)
    s === nothing || return s
    c = _coordinate(sol, sym)
    c === nothing || return c
    return invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, Any}, sol, sym)
end
Base.getindex(sol::LatticeSolution, i::Int) = invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, Int}, sol, i)
Base.getindex(sol::LatticeSolution, i::Colon) = invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, Colon}, sol, i)
Base.getindex(sol::LatticeSolution, i::AbstractArray{Int}) =
    invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, AbstractArray{Int}}, sol, i)
Base.getindex(sol::LatticeSolution, i::CartesianIndex) =
    invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, CartesianIndex}, sol, i)
function _coordinate(sol, sym)
    ix = _lindex(sol)
    ix isa LatticeIndex || return nothing
    sym isa Union{AbstractArray, Tuple} && return nothing
    return get(ix.coords, ix.key(sym), nothing)
end

"""
    sol(t, x, y…; idxs = nothing)

The state at time `t` (linear in time between the saves) and at the point `(x, y…)`, multilinear
between the site centers (constant past the outermost centers): the value of field `idxs`, or
with `idxs = nothing` a vector of every state field's value, in state order (F4-04; F4 design
§3.5, MethodOfLines' spatial interpolation).
"""
function (sol::LatticeSolution)(t::Real, x::Real, ys::Real...; idxs = nothing)
    ix = _lindex(sol)
    u = sol(t)
    pt = (x, ys...)
    cs = [c for c in ix.coordsyms]
    length(cs) == length(pt) || throw(ArgumentError(string("sol(t, x…): the lattice has ", length(cs),
        " coordinates; got ", length(pt))))
    ranges = Tuple(ix.coords[ix.key(c)] for c in cs)
    at(v) = (slot = ix.vars[ix.key(v)]; _multilinear(reshape(view(u, slot.range), slot.dims), ranges, pt))
    idxs === nothing && return [at(v) for v in ix.varsyms]
    return at(idxs)
end
# multilinear interpolation of the grid values `g` (site centers `ranges`) at `pt`
function _multilinear(g, ranges, pt)
    N = length(pt)
    lo, w = map(ranges, pt) do r, x
        n = length(r)
        n == 1 && return (1, 0.0)
        f = clamp((x - first(r)) / step(r), 0.0, n - 1.0)
        i = min(floor(Int, f), n - 2)
        return (i + 1, f - i)
    end |> v -> (map(first, v), map(last, v))
    acc = zero(float(eltype(g)))
    for corner in Iterators.product(ntuple(_ -> (0, 1), N)...)
        c = prod(ntuple(d -> corner[d] == 1 ? w[d] : 1 - w[d], N))
        iszero(c) && continue
        acc += c * g[ntuple(d -> min(lo[d] + corner[d], size(g, d)), N)...]
    end
    return acc
end
Base.:(==)(a::LatticeStats, b::LatticeStats) = all(f -> getfield(a, f) == getfield(b, f), fieldnames(LatticeStats))
