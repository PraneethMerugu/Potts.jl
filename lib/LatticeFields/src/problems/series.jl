# Solutions of lattice problems: an owned solve returns SciML's
# `ODESolution` (linear interpolation: `sol(t)`, `Array(sol)`, `sol.ps`, `sol.alg`,
# `sol.stats`). A field read on any solution of a lattice problem (owned, OrdinaryDiffEq, or
# a FieldProblem solved directly) follows SciML and `PottsProblem`: `sol[c]` is one grid per
# save; `field_series(sol, c)` is the time-first lazy view of the saves (MethodOfLines'
# shape).

"""
    FieldSeries

A field's values over the saves of a solution, time first (MethodOfLines' shape): an
`AbstractArray` of size `(nt, dims...)` whose entries are read from the saved states when
indexed, with no copy of the series ([`field_series`](@ref) gives it; `sol[c]` is a vector
of grids). `s[i, :, :]` (or `sol[c, i]`, `sol[c][i]`) is the grid at save `i`, `Array(s)`
copies the whole series. An aux field (`K ~ rhs`) is evaluated from the saved state at each
save time when that save is read. An owned solve saves host vectors; an OrdinaryDiffEq solve
on a device saves device arrays: there read whole grids (`s[i, :, :]`, `Array(s)`), not
single entries.
"""
struct FieldSeries{T, N, F} <: AbstractArray{T, N}
    size::NTuple{N, Int}
    # i -> the grid at save i (a view of the save for a state field)
    slice::F
end
function FieldSeries{T}(size::NTuple{N, Int}, slice::F) where {T, N, F}
    return FieldSeries{T, N, F}(size, slice)
end
Base.size(s::FieldSeries) = s.size
Base.IndexStyle(::Type{<:FieldSeries}) = IndexCartesian()
Base.@propagate_inbounds function Base.getindex(
        s::FieldSeries{T, N}, I::Vararg{
            Int, N,
        }
    ) where {T, N}
    return s.slice(I[1])[Base.tail(I)...]
end
# a whole grid at save `i` (a copy, on the saves' device)
function Base.getindex(s::FieldSeries{T, N}, i::Int, c::Colon, cs::Colon...) where {T, N}
    return if length(cs) == N - 2
        copy(s.slice(i))
    else
        invoke(getindex, Tuple{AbstractArray, Vararg{Any}}, s, i, c, cs...)
    end
end
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

The time-first values of the field, aux field or input `c` of a solution (MethodOfLines'
shape): `size = (length(sol.t), dims...)`, a lazy view of the saves. In both coupled and
standalone routes `sol[c]` is one grid per save (as SciML reads a variable), so
`field_series(sol, c)[i, :, :] == sol[c][i] == sol[c, i]`; this accessor is the time-first
view, for a standalone `FieldProblem`/ODE solution and for a coupled `PottsProblem`
(`PottsSolution`, per-MCS states).
"""
function field_series(sol, sym)
    s = _field_series(sol, sym)
    s === nothing || return s
    ix = _lindex(sol)
    ix isa LatticeIndex && throw(
        ArgumentError(
            string(
                "field_series: `", _symtext(sym), "` is not a field of the ",
                "solution's problem; its fields: ",
                join(("`$(_symtext(v))`" for v in ix.varsyms), ", ")
            )
        )
    )
    # another solution (Potts per-MCS states): the grid of each save through SII's getter
    g = SII.getsym(sol, sym)
    nt = length(sol.t)
    nt == 0 && throw(ArgumentError("field_series: the solution has no saves"))
    v = g(sol, 1)
    v isa AbstractArray || throw(
        ArgumentError(
            string(
                "field_series: `", _symtext(sym), "` is not a field (it reads ",
                "a ", typeof(v), " per save)"
            )
        )
    )
    return FieldSeries{eltype(v)}((nt, size(v)...), _GetterSlice(g, sol))
end
struct _GetterSlice{G, S}
    g::G
    sol::S
end
(s::_GetterSlice)(i) = s.g(s.sol, i)
"""
    site_centers(sol) -> Tuple or nothing

The coordinates of the site centers on each spatial axis of a lattice solution, in axis
order (one range per axis, as `sol[x]` reads one axis), or `nothing` when the solution
carries no coordinates (a `FieldSolution` of a `FieldProblem` built without a system).
"""
function site_centers(sol)
    ix = _lindex(sol)
    ix isa LatticeIndex || return nothing
    isempty(ix.coordsyms) && return nothing
    return Tuple(ix.coords[ix.key(c)] for c in ix.coordsyms)
end
# the series of `sym` when it names a state or aux field of a lattice solution, else nothing
# the `LatticeIndex` of a solution (a solution's container is its problem, whose is the
# index)
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
        idx = get(sol.prob.kwargs, :save_idxs, nothing)
        ss = sol isa SciMLBase.ODESolution ? sol.saved_subsystem : nothing
        smap = if ss isa SciMLBase.SavedSubsystem && ss.state_map isa AbstractDict
            ss.state_map
        else
            nothing
        end
        # (the saves hold `save_idxs` only)
        if idx isa AbstractVector{<:Integer} || smap !== nothing
            pos = if idx isa AbstractVector{<:Integer}
                indexin(r, idx)
            else
                [get(smap, j, nothing) for j in r]
            end
            any(isnothing, pos) && throw(
                ArgumentError(
                    string(
                        "`", _symtext(sym), "` is not saved whole: the ",
                        "solution saved `save_idxs` (", count(!isnothing, pos),
                        " of the field's ", length(r), " sites). ",
                        "Save the field with `save_idxs = ", _symtext(sym),
                        "` (or its flat indices), or read the saved ",
                        "entries as `sol.u[i]`"
                    )
                )
            )
            r = Int.(pos)
            r == first(r):last(r) && (r = first(r):last(r))
        elseif nt > 0 && length(sol.u[1]) < last(r)
            # (a subset SciML saved: its own reads)
            return nothing
        end
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

# a FieldProblem solved directly (a `FieldSolution`): the grids of its own reads, time first
function _field_series(sol::FieldSolution, sym)
    ix = sol.prob.index
    ix isa LatticeIndex || return nothing
    sym isa Union{AbstractArray, Tuple} && return nothing
    haskey(ix.vars, ix.key(sym)) || aux_key(ix, sym) !== nothing || return nothing
    nt = length(sol.t)
    nt == 0 && return nothing
    v = sol[sym, 1]
    return FieldSeries{eltype(v)}((nt, size(v)...), _GetterSlice((s, i) -> s[sym, i], sol))
end
# `sol(t; idxs)` of a FieldSolution, as the owned `ODESolution` reads it: linear in time
# between the saves (a map's state is constant between its steps); `idxs` a field: its grid
function (s::FieldSolution)(t::Real; idxs = nothing)
    ts = s.t
    isempty(ts) && throw(ArgumentError("the solution has no saves"))
    tol = 1.0e-9 * max(abs(ts[end] - ts[1]), 1.0)
    ts[1] - tol <= t <= ts[end] + tol || throw(
        ArgumentError(
            string(
                "sol(t): t = ", t, " is outside the saves [",
                ts[1], ", ", ts[end], "]"
            )
        )
    )
    k = clamp(searchsortedlast(ts, t + tol), 1, length(ts))
    u = if abs(ts[k] - t) <= tol || k == length(ts) || s.prob.kind == :map
        s.u[k]
    else
        s.u[k] .+ ((t - ts[k]) / (ts[k + 1] - ts[k])) .* (s.u[k + 1] .- s.u[k])
    end
    idxs === nothing && return u
    ix = s.prob.index
    slot = ix isa LatticeIndex ? get(ix.vars, ix.key(idxs), nothing) : nothing
    slot isa FieldSlot || throw(
        ArgumentError(
            string(
                "sol(t; idxs): `", _symtext(idxs), "` is not a state field ",
                "of the problem"
            )
        )
    )
    return reshape(u[slot.range], slot.dims)
end

"""
    ImplicitFacts

The resolved implicit facts of one field group ([`implicit_facts`](@ref)), as data (the
report words them): `keys` its fields; `linsolve` its solvers as resolved and `krylov` the
coupled solve's Krylov solver (or `nothing`); `levels` and `solver_type` per solver;
`newton` the Newton count and `given` whether the user gave it; `coupled`, `linear` (a
coupled solve, linear in its state), `exact` (the operator `J̃` is exact at the bound
parameters), `exact0` (exact apart from the signs of the Robin faces and multipliers),
`switch`, `iterate`, `seen` (every term out of the operator has a bound), `cyclic`; `h` the
substep, `ρin` the bound of the terms out of the operator, `θ`, `smin` (the decay); `terms`
the terms out of the operator and `unseen` those no bound sees.
"""
const ImplicitFacts = @NamedTuple{
    keys::Vector{String}, linsolve::Vector{Any}, krylov::Any, levels::Vector{Int},
    solver_type::Vector{Type},
    newton::Int, given::Bool, coupled::Bool, linear::Bool, exact::Bool, exact0::Bool,
    switch::Bool,
    iterate::Bool, seen::Bool, cyclic::Bool, h::Float64, ρin::Float64, θ::Float64,
    smin::Float64,
    terms::Vector{String}, unseen::Vector{String},
}
"""
    LatticeStats

The statistics of an owned solve (`sol.stats`): `nf` the windows stepped (shortened ones
too), `nsolve` the implicit solves, `counts` the substep count of each field group
([`substep_counts`](@ref)), and the solver counters of the groups' status words
([`field_stats`](@ref)): `solves`, `budget`, `floor`, `newton_budget`; `syncs` the host
copies of a device state that callbacks and interpolated saves took (0 with none);
`implicit` the resolved implicit facts of each group, `nothing` for an explicit one
([`implicit_facts`](@ref): `linsolve`, the multigrid levels, `solver_type`, the Newton count
and its rule, the operator's exactness), taken when the solution is built.
"""
struct LatticeStats
    nf::Int
    nsolve::Int
    counts::Vector{Int}
    solves::Int64
    budget::Int64
    floor::Int64
    newton_budget::Int64
    syncs::Int
    implicit::Vector{Union{Nothing, ImplicitFacts}}
    dt::Float64                         # the window
end
function LatticeStats(integ::FieldIntegrator)
    f = field_stats(integ)
    return LatticeStats(
        integ.windows, f.solves, substep_counts(integ), f.solves, f.budget, f.floor,
        f.newton_budget,
        integ.syncs, Union{Nothing, ImplicitFacts}[
            implicit_facts(rt)
                for rt in integ.runtimes
        ],
        _iwindow(integ)
    )
end
function Base.show(io::IO, s::LatticeStats)
    ni = count(!isnothing, s.implicit)
    return print(
        io, "LatticeStats(", s.nf, " windows, ", s.nsolve,
        " implicit solves, substep counts ", s.counts,
        s.budget > 0 ? string(", ", s.budget, " linear budget hits") : "", if s.floor > 0
            string(", ", s.floor, " floors")
        else
            ""
        end,
        s.newton_budget > 0 ? string(", ", s.newton_budget, " Newton budget hits") : "",
        if s.syncs >
                0
            string(
                ", ", s.syncs, " host syncs"
            )
        else
            ""
        end,
        if ni > 0
            string(", implicit facts of ", ni, " of ", length(s.implicit), " groups")
        else
            ""
        end, ")"
    )
end
"""
    LatticeSolution

The solution of a lattice problem in time: SciML's `ODESolution` of the problem `discretize`
returns, from a field algorithm or from an OrdinaryDiffEq solver (`solve` keeps SciML's
solution and does not wrap it in a `PDETimeSeriesSolution`). `sol.t` and `sol.u` are
SciML's: `sol.u[i]` is the flat state vector at `sol.t[i]`, the state fields one after
another.

The field reads differ from `PDETimeSeriesSolution`'s layout:

- `sol[c]` of a state or auxiliary field `c` is a vector with one array per save, each of
  the lattice's size (`sol[c][i][j, k]` is `c` at `sol.t[i]` on site `(j, k)`), where a
  `PDETimeSeriesSolution` returns one array with time as its first dimension;
- `sol[x]` of a coordinate is the coordinates of the site centers;
- `sol(t, x, y…; idxs = c)` interpolates linearly in time and multilinearly in space;
- an integer, colon, index-array or `CartesianIndex` index reads `sol.u` as SciML does.

[`field_series`](@ref) gives a field as one array with time first.
"""
const LatticeSolution = typewith(SciMLBase.ODESolution, :prob, LatticeProblem)
field_stats(s::LatticeSolution) = _stats(s.stats)
function _stats(t::LatticeStats)
    return (;
        solves = t.solves, budget = t.budget,
        floor = t.floor, newton_budget = t.newton_budget,
    )
end
function _stats(t)
    throw(ArgumentError("field_stats: the solution was not computed by a field algorithm \
        (an owned solve)"))
end
function substep_counts(s::LatticeSolution)
    if s.stats isa LatticeStats
        return copy(s.stats.counts)
    else
        throw(ArgumentError("substep_counts: the solution was not computed by a field \
            algorithm (an owned solve)"))
    end
end

# the solution of an owned solve of the SciML problem `sp`: `build_solution` over the
# saves, with linear interpolation (a map's states are constant between steps), and `prob`
# at the integrator's current parameters, tables and inputs (`sol.ps` reads the values
# written during the run)
function _ode_solution(integ::FieldIntegrator, sp)
    q = _final_problem(integ, sp)
    ts, us = integ.ts, integ.us
    interp = if sp isa SciMLBase.DiscreteProblem
        SciMLBase.ConstantInterpolation(ts, us)
    else
        SciMLBase.LinearInterpolation(ts, us)
    end
    return SciMLBase.build_solution(
        q, integ.alg, ts, us; interp, dense = integ.dense, retcode = integ.retcode,
        stats = LatticeStats(integ)
    )
end
function _final_problem(integ::FieldIntegrator, sp)
    lp = sp.p
    lp isa LatticeParameters || return sp
    ins = Pair{String, Any}[
        k => (v === nothing ? v : _read_input(integ, k))
            for (k, v) in lp.inputs
    ]
    q = LatticeParameters(
        copy(integ.p), eltype(integ.tables)[k => copy(v) for (k, v) in integ.tables], ins;
        tick = _tick(integ), fns = lp.fns
    )
    T = sp isa SciMLBase.DiscreteProblem ? SciMLBase.DiscreteProblem : SciMLBase.ODEProblem
    idx = getfield(integ, :saveidxs)
    # (`save_idxs`: the saves hold those indices; the time-first reads find the fields in
    # them)
    if idx === nothing
        return invoke(SciMLBase.remake, Tuple{T}, sp; p = q)
    else
        return invoke(SciMLBase.remake, Tuple{T}, sp; p = q, save_idxs = idx)
    end
end

# Field reads on every solution of a lattice problem: `sol[c]` of a state or aux
# field is one grid per save (as SciML and `PottsProblem` read a variable); `sol[x]` the
# coordinates of the site centers; anything else as SciML reads it. (The methods for
# integer, colon and index-array arguments keep SciML's reads, unambiguously.) `sym` is
# restricted to the key types that can name a field (symbolic terms through the
# SymbolicUtils extension), so the method is not ambiguous with array packages' index types
# (BlockArrays' `Block`, BandedMatrices' `Band`).
function Base.getindex(sol::LatticeSolution, sym::Union{Symbol, AbstractString, Number})
    return _lattice_getindex(sol, sym)
end
function _lattice_getindex(sol, sym)
    s = _field_series(sol, sym)
    s === nothing || return _grids(s)
    c = _coordinate(sol, sym)
    c === nothing || return c
    return invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, Any}, sol, sym)
end
function Base.getindex(sol::LatticeSolution, i::Int)
    return invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, Int}, sol, i)
end
function Base.getindex(sol::LatticeSolution, i::Colon)
    return invoke(getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, Colon}, sol, i)
end
function Base.getindex(sol::LatticeSolution, i::AbstractArray{Int})
    return invoke(
        getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, AbstractArray{Int}},
        sol, i
    )
end
function Base.getindex(sol::LatticeSolution, i::CartesianIndex)
    return invoke(
        getindex, Tuple{SciMLBase.AbstractTimeseriesSolution, CartesianIndex},
        sol, i
    )
end
_grids(s::FieldSeries) = [s[i, ntuple(_ -> Colon(), ndims(s) - 1)...] for i in 1:size(s, 1)]
function _coordinate(sol, sym)
    ix = _lindex(sol)
    ix isa LatticeIndex || return nothing
    sym isa Union{AbstractArray, Tuple} && return nothing
    return get(ix.coords, ix.key(sym), nothing)
end

"""
    sol(t, x, y…; idxs = nothing)

The state at time `t` (linear in time between the saves) and at the point `(x, y…)`,
multilinear between the site centers (constant past the outermost centers): the value of
field `idxs`, or with `idxs = nothing` a vector of every state field's value, in state order
(MethodOfLines' spatial interpolation).
"""
function (sol::LatticeSolution)(t::Real, x::Real, ys::Real...; idxs = nothing)
    ix = _lindex(sol)
    u = sol(t)
    pt = (x, ys...)
    cs = [c for c in ix.coordsyms]
    length(cs) == length(pt) || throw(
        ArgumentError(
            string(
                "sol(t, x…): the lattice has ", length(cs),
                " coordinates; got ", length(pt)
            )
        )
    )
    ranges = Tuple(ix.coords[ix.key(c)] for c in cs)
    function at(v)
        slot = ix.vars[ix.key(v)]
        return _multilinear(reshape(view(u, slot.range), slot.dims), ranges, pt)
    end
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
# (an ensemble's statistics: the sums; the counts of the first)
function Base.merge(a::LatticeStats, b::LatticeStats)
    return LatticeStats(
        a.nf + b.nf, a.nsolve + b.nsolve, a.counts, a.solves + b.solves,
        a.budget + b.budget, a.floor + b.floor, a.newton_budget + b.newton_budget,
        a.syncs + b.syncs, a.implicit, a.dt
    )
end
function Base.:(==)(a::LatticeStats, b::LatticeStats)
    return all(f -> getfield(a, f) == getfield(b, f), fieldnames(LatticeStats))
end
function Base.isequal(a::LatticeStats, b::LatticeStats)
    return all(f -> isequal(getfield(a, f), getfield(b, f)), fieldnames(LatticeStats))
end
function Base.hash(s::LatticeStats, h::UInt)
    return foldl(
        (h, f) -> hash(getfield(s, f), h), fieldnames(LatticeStats);
        init = hash(:LatticeStats, h)
    )
end
