# `PottsProblem`: operating point + compiled model → `CorePotts.CPMProblem` with generated
# functions (the analogue of MTK's `ODEProblem(sys, op, tspan)`).

# `ownership => labels` in an operating point uses CorePotts' `ownership` accessor as the key.
const ownership = CorePotts.ownership

"""
    PottsModelInfo

What a generated problem keeps about its model (`prob.f.sys`): the compiled system, the
scalar type and the generated `total_energy(st, p, ctx)`.
"""
struct PottsModelInfo{C, E, DE}
    csys::C
    T::Type
    total_energy::E
    delta_E::DE          # ΔH without drives: the energy change the self-check compares
end

"""
    PottsProblem(sys, op, tspan; T = Float64, capacity, seed = 0, replica = 0, repeat = 0,
                 expression = Val(false))

Build a `CorePotts.CPMProblem` from a `PottsSystem` (compiled with `mtkcompile` if
needed). `op` maps `ownership` to the initial labels (an integer array over the lattice),
`kind` to the kinds of the labelled cells (names or numbers), variables to initial values
(scalars or arrays) and parameters to values overriding their defaults. `T` is the scalar
type of the generated code and state (use `Float32` on Metal). With
`expression = Val(true)` the generated function expressions are returned instead.
"""
function PottsProblem(sys::PottsSystem, op, tspan; kwargs...)
    return PottsProblem(ModelingToolkitBase.mtkcompile(sys), op, tspan; kwargs...)
end

function PottsProblem(c::CompiledPottsSystem, op, tspan; T::Type = Float64, capacity = nothing,
        seed = 0, replica = 0, repeat = 0, expression = Val(false))
    sys = c.sys
    opd = Dict{Any, Any}(_opkey(k) => v for (k, v) in op)
    values = _parameter_values(c, opd)
    p = NamedTuple(info(x).name => _param_value(T, values[_unwrap(x)], info(x)) for x in sys.parameters)
    for name in _contact_tables(c)
        J = getproperty(p, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    if expression isa Val{true}
        return (; delta_H = _delta_H_expr(c, T), commit! = _commit_expr(c, T),
            constraint = _constraint_expr(c, T), temperature = _temperature_expr(c, T),
            total_energy = _total_energy_expr(c, T))
    end
    st = _initial_state(c, opd, T, capacity)
    lat = core_lattice(sys.lattice)
    ce = _constraint_expr(c, T)
    exprs = (_delta_H_expr(c, T), _commit_expr(c, T), ce, _temperature_expr(c, T))
    f = CorePotts.CPMFunction(_rgf(exprs[1]); commit! = _rgf(exprs[2]),
        constraint = ce === nothing ? CorePotts.always : _rgf(ce), temperature = _rgf(exprs[4]),
        phases = _phases(c, T, values), lifecycle = _lifecycle(c, T), acceptance = _acceptance(sys.sweep, T),
        footprint = c.footprint,
        fingerprint = hash((string.(exprs), sys.lattice, T)),
        sys = PottsModelInfo(c, T, _rgf(_total_energy_expr(c, T)), _rgf(_delta_H_expr(c, T; drives = false))))
    relations = NamedTuple(k => v for (k, v) in c.relations)
    spacing = sys.lattice.spacing === nothing ? nothing : map(T, sys.lattice.spacing)
    return CorePotts.CPMProblem(f, st, lat, tspan, p; contact = c.contact_spec, relations,
        spacing, seed, replica, repeat)
end

_acceptance(s::SweepSpec, T) = s.law === :barker ? CorePotts.Barker() :
                               s.offset == 0 ? CorePotts.Metropolis() : CorePotts.Metropolis(T(s.offset))

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
    ncell = maximum(σ; init = Int32(0))
    kkey = _unwrap(B.kind)
    kinds = haskey(opd, kkey) ? opd[kkey] : fill(1, ncell)
    kinds = Int32[k isa Symbol ? _kind_index(sys, k) : Int(k) for k in (kinds isa AbstractVector ? kinds : fill(kinds, ncell))]
    length(kinds) == ncell || throw(ArgumentError("$(length(kinds)) kinds for $ncell labelled cells"))
    lat = core_lattice(sys.lattice)
    site = Pair{Symbol, Any}[]
    cell = Pair{Symbol, Any}[]
    for x in sys.variables
        i = info(x)
        v = get(opd, _unwrap(x), i.default)
        if i.role === :site || i.role === :field
            a = v isa AbstractArray ? T.(v) : fill(T(v), sys.lattice.dims)
            push!(site, i.name => a)
            i.name in c.scratch && push!(site, Symbol(i.name, :__next) => copy(a))
        elseif i.role === :cell
            push!(cell, i.name => (v isa AbstractArray ? T.(v) : fill(T(v), ncell)))
        else
            throw(ArgumentError("model-scope variables are not supported yet"))
        end
    end
    if c.uses_surface
        push!(cell, :surface => CorePotts.recompute_surface(σ, lat, CorePotts.relation(c.relations[:surface], lat), ncell; T))
    end
    c.needs_moments && append!(cell, pairs(CorePotts.init_moments(σ, lat, ncell)))
    st = CorePotts.initial_state(σ, kinds; cell = NamedTuple(cell), site = NamedTuple(site))
    cap = capacity === nothing ? (isempty(c.divisions) ? ncell : 2ncell + 64) : capacity
    return cap > ncell ? CorePotts.with_capacity(st, cap) : st
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
    out = NamedTuple(k => get(new, k, v) for (k, v) in pairs(prob.p))
    typeof(out) === typeof(prob.p) || throw(ArgumentError("parameter types changed; kind tables keep their size"))
    for name in _contact_tables(info.csys)
        J = getproperty(out, name)
        J == transpose(J) || throw(ArgumentError("kind table `$name` is used in a contact energy and must be symmetric"))
    end
    return out
end

function CorePotts.remake_state(info::PottsModelInfo, prob, u0::_SymbolicMap)
    opd = Dict{Any, Any}(_opkey(k) => v for (k, v) in u0)
    return _initial_state(info.csys, opd, info.T, length(prob.u0.cell.kind))
end
