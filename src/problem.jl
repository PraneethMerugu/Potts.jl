# `PottsProblem`: operating point + compiled model → `CorePotts.CPMProblem` with generated
# functions (the analogue of MTK's `ODEProblem(sys, op, tspan)`).

# `ownership => labels` in an operating point uses CorePotts' `ownership` accessor as the key.
const ownership = CorePotts.ownership

"""
    PottsModelInfo

What a generated problem keeps about its model (`prob.f.sys`): the compiled system, the
scalar type and the generated `total_energy(st, p, ctx)`.
"""
struct PottsModelInfo{C, E, DE, X}
    csys::C
    T::Type
    total_energy::E
    delta_E::DE          # ΔH without drives: the energy change the self-check compares
    ctx::X               # host context (lattice, relations) for observed quantities
    cache::Dict{Any, Any}    # compiled observed functions, by expression
end

"""
    PottsProblem(sys, op, tspan; T = Float64, capacity, seed = 0, replica = 0, repeat = 0,
                 expression = Val(false))

Build a `CorePotts.CPMProblem` from a `PottsSystem` (compiled with `mtkcompile` if
needed). `op` maps `ownership` to the initial labels (an integer array over the lattice),
`kind` to the kinds of the labelled cells (names or numbers), `cluster` to their
compartment groups (any ids; equal ids form one cluster; default: every cell alone), variables to initial values
(scalars or arrays), parameters to values overriding their defaults, and a relationship's
name to its initial links (`:bond => [(1, 2)]`). `T` is the scalar
type of the generated code and state (use `Float32` on Metal). With
`expression = Val(true)` the generated function expressions are returned instead.
"""
function PottsProblem(sys::PottsSystem, op, tspan; kwargs...)
    return PottsProblem(ModelingToolkitBase.mtkcompile(sys), op, tspan; kwargs...)
end

function PottsProblem(c::CompiledPottsSystem, op, tspan; T::Type = Float64, capacity = nothing,
        seed = 0, replica = 0, repeat = 0, expression = Val(false))
    sys = c.sys
    opd = _operating_point(sys, op)
    values = _parameter_values(c, opd)
    p = PottsParameters(NamedTuple(info(x).name => _param_value(T, values[_unwrap(x)], info(x)) for x in sys.parameters))
    for name in _contact_tables(c)
        J = getproperty(p, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    _check_kind_tables(sys, p)
    if expression isa Val{true}
        return (; delta_H = _delta_H_expr(c, T), commit! = _commit_expr(c, T),
            constraint = _constraint_expr(c, T), temperature = _temperature_expr(c, T),
            total_energy = _total_energy_expr(c, T))
    end
    st = _initial_state(c, opd, T, capacity)
    lat = core_lattice(sys.lattice)
    relations = NamedTuple(k => v for (k, v) in _sorted(c.relations))
    spacing = sys.lattice.spacing === nothing ? nothing : map(T, sys.lattice.spacing)
    hctx = (; lattice = lat, contact = CorePotts.relation(c.contact_spec, lat),
        map(r -> CorePotts.relation(r, lat), relations)...,
        (spacing === nothing ? (;) : (; spacing))...)
    ce = _constraint_expr(c, T)
    exprs = (_delta_H_expr(c, T), _commit_expr(c, T), ce, _temperature_expr(c, T))
    f = CorePotts.CPMFunction(_rgf(exprs[1]); commit! = _rgf(exprs[2]),
        constraint = ce === nothing ? CorePotts.always : _rgf(ce), temperature = _rgf(exprs[4]),
        claims = _claims(c),
        phases = _phases(c, T, values), lifecycle = _lifecycle(c, T), acceptance = _acceptance(sys.sweep, T),
        footprint = c.footprint,
        fingerprint = hash((string.(exprs), core_lattice(sys.lattice), sys.lattice.spacing, sys.lattice.neighborhood, T)),
        sys = PottsModelInfo(c, T, _rgf(_total_energy_expr(c, T)), _rgf(_delta_H_expr(c, T; drives = false)),
            hctx, Dict{Any, Any}()))
    frozen = _frozen_mask(sys, st)
    _host_init!(f, st, p, hctx, seed, replica, repeat)
    return CorePotts.CPMProblem(f, st, lat, tspan, p; contact = c.contact_spec, relations,
        spacing, frozen, seed, replica, repeat)
end

# Checkerboard claims beyond old/new: link partners (link energies read their centroids) and
# the clusters of old/new (cluster energies read cluster trackers).
function _claims(c::CompiledPottsSystem)
    parts = Any[]
    c.relationship === nothing ||
        push!(parts, :(CorePotts.link_claims(st.cell, prop, Val($(c.relationship.capacity)))...))
    isempty(c.cluster_terms) || push!(parts, :(CorePotts.cluster_claims(st.cell, prop)...))
    isempty(parts) && return CorePotts.no_claims
    return _rgf(:((st, p, prop, ctx) -> $(Expr(:tuple, parts...))))
end

# Kind tables are indexed by kind (medium first) along every axis.
function _check_kind_tables(sys::PottsSystem, p)
    nk = length(sys.kinds)
    for x in sys.parameters
        i = info(x)
        i.role === :kindtable || continue
        v = getproperty(p, i.name)
        all(==(nk), size(v)) || throw(ArgumentError("kind table `$(i.name)` has size $(size(v)); the model has $nk kinds " *
                                                    "($(join(sys.kinds, ", "))), so it needs $nk entries per axis"))
    end
    return nothing
end

_acceptance(s::SweepSpec, T) = s.law === :barker ? CorePotts.Barker() :
                               s.offset == 0 ? CorePotts.Metropolis() : CorePotts.Metropolis(T(s.offset))

# Keys may be symbolic quantities or their names (`:λ`, `Symbol("clock₊τ")`); relationship
# names (`:bond => [(1, 2)]`) stay symbols.
function _operating_point(sys::PottsSystem, op)
    op = _expand_vectors(sys, op)
    byname = Dict{Symbol, Any}(info(x).name => _unwrap(x) for x in Iterators.flatten((sys.parameters, sys.variables)))
    byname[:kind] = _unwrap(B.kind)
    byname[:cluster] = _unwrap(B.cluster)
    byname[:ownership] = CorePotts.ownership
    rels = Set(r.name for r in sys.relationships)
    known = Set{Any}(values(byname))
    opd = Dict{Any, Any}()
    for (k, v) in op
        key = k isa Symbol ? get(byname, k, k) : _opkey(k)
        (key in known || (key isa Symbol && key in rels)) || throw(ArgumentError(
            "operating-point key `$k` names nothing in model `$(nameof(sys))`; it has parameters " *
            "$(join((info(x).name for x in sys.parameters), ", ")), variables " *
            "$(join((info(x).name for x in sys.variables), ", ")), and `ownership`, `kind`, `cluster`" *
            (isempty(rels) ? "" : ", $(join(rels, ", "))")))
        opd[key] = v
    end
    return opd
end

"""
Operating-point entries for vector quantities (`p => …`, `:p => …`) split into their
components: a number applies to every component; a parameter takes a length-`n` vector; a
variable takes per-cell/site vectors (`[(x, y), …]`) or an array whose last dimension is `n`.
"""
function _expand_vectors(sys::PottsSystem, op)
    vecs = Dict{Symbol, Vector{Any}}()
    for x in Iterators.flatten((sys.parameters, sys.variables))
        o = info(x).options
        haskey(o, :vector) || continue
        v = get!(vecs, o.vector, Any[])
        length(v) < o.index && resize!(v, o.index)
        v[o.index] = x
    end
    isempty(vecs) && return op
    out = Pair{Any, Any}[]
    for (k, v) in (op isa AbstractDict ? pairs(op) : op)
        name = k isa QuantityVector ? k.name : k isa Symbol ? k : nothing
        if name !== nothing && haskey(vecs, name)
            comps = vecs[name]
            append!(out, [c => _vector_entry(name, v, i, length(comps), info(c).role) for (i, c) in enumerate(comps)])
        else
            push!(out, k => v)
        end
    end
    return out
end
function _vector_entry(name, v, i, n, role)
    v isa Number && return v
    # a flat numeric vector is the vector itself (for every cell/site); per-entry data are
    # vectors of tuples/vectors or arrays whose last dimension is `n`
    if v isa AbstractVector && eltype(v) <: Number
        length(v) == n || throw(ArgumentError("`$name` has $n components; got $(length(v)) numbers " *
                                              "(per-cell/site values: a vector of $n-tuples or an array whose last dimension is $n)"))
        return v[i]
    end
    role === :param && throw(ArgumentError("`$name` takes $n numbers"))
    v isa AbstractVector && all(e -> e isa Union{AbstractVector, Tuple}, v) && return [e[i] for e in v]
    v isa AbstractArray && size(v, ndims(v)) == n && return copy(selectdim(v, ndims(v), i))
    throw(ArgumentError("values for the $n-component `$name`: a number, per-entry vectors, or an array whose last dimension is $n"))
end

_opkey(k::typeof(CorePotts.ownership)) = k
_opkey(k) = (u = _unwrap(k); u)

function _parameter_values(c::CompiledPottsSystem, opd)
    values = Dict{Any, Any}()
    for x in c.sys.parameters
        u = _unwrap(x)
        v = haskey(opd, u) ? opd[u] : info(x).default
        v === nothing && throw(ArgumentError("parameter `$(info(x).name)` has no default; give it in the operating point"))
        values[u] = v
    end
    # parameters may default to expressions of other parameters
    for _ in 1:length(values)
        done = true
        for (k, v) in values
            if v isa Num || v isa SymbolicUtils.BasicSymbolic
                w = _unwrap(Symbolics.substitute(v, values))
                values[k] = SymbolicUtils.isconst(w) ? SymbolicUtils.unwrap_const(w) : w
                done &= SymbolicUtils.isconst(w) || !(w isa SymbolicUtils.BasicSymbolic)
            end
        end
        done && break
    end
    return values
end

function _param_value(T, v, i::Info)
    if i.role === :kindtable
        A = Matrix(v isa AbstractVector ? reshape(v, :, 1) : v)
        v isa AbstractVector && return SVector{length(v), T}(T.(v))
        return SMatrix{size(A, 1), size(A, 2), T}(T.(A))
    end
    return T(v)
end

function _initial_state(c::CompiledPottsSystem, opd, T, capacity)
    sys = c.sys
    haskey(opd, ownership) || throw(ArgumentError("the operating point needs `ownership => labels`"))
    σ = Int32.(opd[ownership])
    size(σ) == sys.lattice.dims || throw(ArgumentError("labels have size $(size(σ)); the lattice is $(sys.lattice.dims)"))
    all(>=(0), σ) || throw(ArgumentError("labels must be ≥ 0 (0 is medium); got $(minimum(σ))"))
    ncell = maximum(σ; init = Int32(0))
    kkey = _unwrap(B.kind)
    kinds = haskey(opd, kkey) ? opd[kkey] : fill(1, ncell)
    kinds = Int32[k isa Symbol ? _kind_index(sys, k) : Int(k) for k in (kinds isa AbstractVector ? kinds : fill(kinds, ncell))]
    length(kinds) == ncell || throw(ArgumentError("$(length(kinds)) kinds for $ncell labelled cells"))
    nk = length(sys.kinds) - 1
    for k in kinds
        1 <= k <= nk || throw(ArgumentError("kind number $k is out of range: cell kinds are 1:$nk " *
                                            "($(join(sys.kinds[2:end], ", ")))"))
    end
    lat = core_lattice(sys.lattice)
    site = Pair{Symbol, Any}[]
    cell = Pair{Symbol, Any}[]
    model = Pair{Symbol, Any}[]
    for x in sys.variables
        i = info(x)
        v = get(opd, _unwrap(x), i.default)
        if i.role === :site || i.role === :field
            a = v isa AbstractArray ? T.(v) : fill(T(v), sys.lattice.dims)
            push!(site, i.name => a)
            i.name in c.scratch && push!(site, Symbol(i.name, :__next) => copy(a))
        elseif i.role === :cell
            v === nothing && throw(ArgumentError("cell variable `$(i.name)` has no initial value; give it in the operating point"))
            push!(cell, i.name => (v isa AbstractArray ? T.(v) : fill(T(v), ncell)))
        elseif i.role === :edge
            continue                                   # link payloads, below
        elseif i.role === :model
            v === nothing && throw(ArgumentError("model variable `$(i.name)` has no initial value; give it in the operating point"))
            push!(model, i.name => fill(T(v), 1))
        end
    end
    for x in _integrals(sys)
        push!(cell, _integral_name(x) => zeros(T, ncell))
    end
    if c.uses_surface
        push!(cell, :surface => CorePotts.recompute_surface(σ, lat, CorePotts.relation(c.relations[:surface], lat), ncell; T))
    end
    c.needs_moments && append!(cell, pairs(CorePotts.init_moments(σ, lat, ncell)))
    ckey = _unwrap(B.cluster)
    if c.uses_clusters
        ids = haskey(opd, ckey) ? opd[ckey] : 1:ncell
        length(ids) == ncell || throw(ArgumentError("$(length(ids)) cluster ids for $ncell labelled cells"))
        rel = c.uses_cluster_surface ? c.relations[:surface] : nothing
        append!(cell, pairs(CorePotts.init_clusters(σ, ids, lat; relation = rel, T, kind = kinds,
            prefer = _cluster_kinds(c))))
    elseif haskey(opd, ckey)
        throw(ArgumentError("`cluster` in the operating point, but the model uses no compartments"))
    end
    if c.relationship !== nothing
        payloads = [info(x).name => T for x in sys.variables if info(x).role === :edge]
        links = CorePotts.empty_links(c.relationship.capacity, ncell; payloads...)
        defaults = (; (info(x).name => T(info(x).default) for x in sys.variables if info(x).role === :edge)...)
        for (x, y) in get(opd, c.relationship.name, ())
            CorePotts.add_link!(links, x, y; defaults...) ||
                throw(ArgumentError("cannot link cells $x and $y (full row or duplicate)"))
        end
        append!(cell, pairs(links))
    end
    # previous-value snapshots and population slots (D-041, D-042)
    for (scope, n) in unique(Iterators.flatten(values(c.pre_snapshots)))
        dst = scope === :site ? site : scope === :cell ? cell : model
        push!(dst, Symbol(n, :__pre) => copy(last(dst[findfirst(q -> q.first === n, dst)])))
    end
    for (n, _) in Iterators.flatten((c.update_pops, c.energy_snapshots, c.cell_ode_pops))
        push!(model, n => zeros(T, 1))
    end
    sitent, modelnt = NamedTuple(site), NamedTuple(model)
    history = (; (n => CorePotts.history_buffer(haskey(sitent, n) ? sitent[n] : modelnt[n], d)
                  for (n, d) in sort!(collect(_history_depths(sys)); by = first))...)
    st = CorePotts.initial_state(σ, kinds; cell = NamedTuple(cell), site = sitent, model = modelnt, history)
    cap = capacity === nothing ? (isempty(c.divisions) ? ncell : 2ncell + 64) : capacity
    return cap > ncell ? CorePotts.with_capacity(st, cap) : st
end

# The at-init phases (integrals, energy snapshots) on a host state, so a problem's `u0` is
# consistent before `init` (e.g. `total_energy(prob)`).
function _host_init!(f, st, p, ctx, seed, replica, repeat)
    key = CorePotts.RNGKey(seed, replica, repeat)
    CorePotts._run_phases(f.phases.at_init, st, p, ctx, key, 0, CorePotts.CPU())
    return st
end

# Kinds that name clusters (`clusters(k)` terms and divisions): a cluster's root is chosen
# among its members of these kinds, so the filters select it.
_cluster_kinds(c::CompiledPottsSystem) = Tuple(unique(Iterators.flatten((first.(c.cluster_terms)...,
    (d.domain.kinds for d in c.divisions if d.domain isa ClusterDomain)...))))

# Sites of cells of frozen kinds never change owner (walls, obstacles).
function _frozen_mask(sys::PottsSystem, st)
    isempty(sys.frozen_kinds) && return nothing
    kinds = st.cell.kind
    return map(s -> s != 0 && Int(kinds[s]) in sys.frozen_kinds, st.σ)
end

function _kind_index(sys::PottsSystem, k::Symbol)
    j = findfirst(==(k), sys.kinds)
    j === nothing && throw(ArgumentError("unknown kind `$k`; kinds are $(sys.kinds)"))
    j == 1 && throw(ArgumentError("cells cannot have the medium kind `$k`"))
    return j - 1
end

_host_ctx(prob) = (; lattice = prob.lattice, contact = prob.contact, prob.relations...,
    (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...)

"""
    energy_change(prob, u, prop)

The authored energy change of proposal `prop` in state `u` (the model's ΔH without drives).
"""
energy_change(prob::CorePotts.CPMProblem, u, prop) = prob.f.sys.delta_E(u, prob.p, prop, _host_ctx(prob))

"""
    total_energy(prob, u = prob.u0)

The authored Hamiltonian `H` of state `u` (brute force, host). Generated from the same
terms as the model's ΔH, so `ΔH == H(after) − H(before)` is a self-check. Cell terms sum
over every cell slot: an emptied cell keeps contributing `E(volume = 0)`, as in the ΔH of
the copy that emptied it (legacy and CompuCell3D semantics).
"""
function total_energy(prob::CorePotts.CPMProblem, u = prob.u0)
    info = prob.f.sys
    info isa PottsModelInfo || throw(ArgumentError("not a PottsProblem"))
    return info.total_energy(u, prob.p, _host_ctx(prob))
end

# `remake(prob; p = [λ => 2.0])` and `remake(prob; u0 = [ownership => σ, kind => kinds])`:
# symbolic maps are translated with the problem's scalar type, so the parameter object keeps
# its type and nothing recompiles.
const _SymbolicMap = Union{AbstractVector{<:Pair}, AbstractDict}

function CorePotts.remake_parameters(info::PottsModelInfo, prob, p::_SymbolicMap)
    p = _expand_vectors(info.csys.sys, p)
    names = Dict{Any, Info}()
    for x in info.csys.sys.parameters
        i = Potts.info(x)
        names[_unwrap(x)] = i
        names[i.name] = i
    end
    new = Dict{Symbol, Any}()
    for (k, v) in p
        key = k isa Symbol ? k : _unwrap(k)
        haskey(names, key) || throw(ArgumentError("`$k` is not a parameter of $(nameof(info.csys))"))
        i = names[key]
        new[i.name] = _param_value(info.T, v, i)
    end
    out = PottsParameters(NamedTuple(k => get(new, k, v) for (k, v) in pairs(NamedTuple(prob.p))))
    typeof(out) === typeof(prob.p) || throw(ArgumentError("parameter types changed; kind tables keep their size"))
    _check_kind_tables(info.csys.sys, out)
    for name in _contact_tables(info.csys)
        J = getproperty(out, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    return out
end

CorePotts.remake_frozen(info::PottsModelInfo, prob, u0) = _frozen_mask(info.csys.sys, u0)

function CorePotts.remake_state(info::PottsModelInfo, prob, u0::_SymbolicMap)
    opd = _operating_point(info.csys.sys, u0)
    # keep the old capacity and the old number of free slots (room for divisions)
    old = length(prob.u0.cell.kind)
    free = count(iszero, prob.u0.cell.volume)
    ncell = maximum(Int32.(get(opd, ownership, Int32[])); init = Int32(0))
    st = _initial_state(info.csys, opd, info.T, max(old, ncell + free))
    return _host_init!(prob.f, st, prob.p, info.ctx, prob.seed, prob.replica, prob.repeat)
end
