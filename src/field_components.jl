# A plain `PDESystem` as fields of a model (F4-11, FE-15b). `Potts.component(name, pdesys,
# model)` carries it, and `Potts.compose` moves it into the model's payload: each dependent
# variable becomes a field variable, each parameter a model parameter, each equation an
# `@equations` entry and each condition a `@bcs` entry. The fields then compile, group and run
# exactly as fields declared in `@potts_model`. A component's quantities are namespaced,
# `name₊c` and `name₊k`, as those of an MTK component are. A model wrapped with its own
# PDESystem (`Potts.wrap(name, sys, pdesys, part)`) has its fields moved the same way at
# `mtkcompile`, under their own names.

# the built-ins a field equation of front end A reads bare at a site (a cell property such as
# `volume` is read through the owner, `volume[owner]`, which a PDESystem cannot write)
const _SITE_WORDS = (:owner, :kind, :position, :site, :mcs, :time)
# the word an input of the PDESystem is filled by: a built-in a field equation reads at a site
# (`_SITE_WORDS`) or a field or site variable of the model (`nothing`: neither)
function _input_target(sys::PottsSystem, w::Symbol)
    w in _SITE_WORDS && return getproperty(B, w)
    for x in _p(sys, :variables)
        i = info(x)
        i !== nothing && i.name === w && i.role in (:field, :site) && return x
    end
    return nothing
end

# MTK's metadata of the dependent variable `u` or of its callable `op`
_dv_meta(u, op, key) = (v = SymbolicUtils.getmetadata(u, key, nothing); v === nothing ? SymbolicUtils.getmetadata(op, key, nothing) : v)

"""
    _pde_content(sys, f, prefix, what) -> (; variables, parameters, equations, bcs)

The payload entries of the PDESystem `f` as fields of model `sys`: its quantities named
`prefix₊n` (`prefix === nothing`: `n`). An `ArgumentError` names what does not fit the model
(another domain than the lattice's, an input the CPM does not fill, a kind table).
"""
function _pde_content(sys::PottsSystem, f::ModelingToolkitBase.PDESystem, prefix, what::AbstractString)
    M = ModelingToolkitBase
    pname = "the PDESystem `$(nameof(f))`"
    isempty(getfield(f, :systems)) && getfield(f, :analytic) === nothing && getfield(f, :analytic_func) === nothing ||
        throw(ArgumentError("$what: $pname has subsystems or analytic solutions, which the fields of a model do not " *
                            "carry; leave them out"))
    qname(n) = prefix === nothing ? Symbol(n) : Symbol(prefix, :₊, n)
    lat = _p(sys, :lattice)
    N = length(lat.dims)
    h = something(lat.spacing, ntuple(_ -> 1.0, N))
    ext = ntuple(d -> lat.dims[d] * Float64(h[d]), N)
    ivs = Any[_unwrap(v) for v in getfield(f, :ivs)]
    length(ivs) in (N, N + 1) || throw(ArgumentError(string(what, ": ", pname, " has the independent variables ",
        join(("`$v`" for v in ivs), ", "), "; the lattice of `", nameof(sys), "` has ", N, " axes: give the time and one ",
        "coordinate per axis, in the order of the lattice's axes")))
    tc = length(ivs) == N + 1 ? ivs[1] : nothing
    xc = ivs[(end - N + 1):end]
    # the time is the first independent variable (as in front end B): the variable of each rate
    # `D(c) ~ …` and map `Shift(t, 1)(c) ~ …`
    for eq in getfield(f, :eqs)
        l = _unwrap(eq.lhs)
        iscall(l) && (operation(l) isa Differential || operation(l) isa ModelingToolkitBase.Shift) || continue
        v = _unwrap(operation(l) isa Differential ? operation(l).x : operation(l).t)
        (tc !== nothing && isequal(v, tc)) && continue
        k = findfirst(w -> isequal(w, v), ivs)
        throw(ArgumentError(string(what, ": ", pname, " has the rate `", eq.lhs, "`, a time rate along `", v, "`, ",
            k === nothing ? "which is not one of its independent variables" :
            "its independent variable $k; the time is the first independent variable: give `[$(v), " *
            join((string(w) for w in ivs if !isequal(w, v)), ", ") * "]`")))
    end
    # the spatial domain is the lattice's in the model's length unit (ruling Q8): axis `d` spans
    # `[0, dims[d] · spacing[d]]`, which is also the domain `Potts.fields` gives
    dom = getfield(f, :domain)
    for d in 1:N
        k = findfirst(e -> isequal(_unwrap(e.variables), xc[d]), dom)
        k === nothing && throw(ArgumentError("$what: $pname gives no interval for `$(xc[d])`; give " *
                                             "`$(xc[d]) ∈ Interval(0, $(_extent_text(ext[d])))`, axis $d of the lattice"))
        lo, hi = Float64(minimum(dom[k].domain)), Float64(maximum(dom[k].domain))
        iszero(lo) && isapprox(hi, ext[d]; rtol = 1e-12) || throw(ArgumentError(string(what, ": ", pname, " spans `",
            xc[d], " ∈ [", _extent_text(lo), ", ", _extent_text(hi), "]`, but axis ", d, " of the lattice of `", nameof(sys),
            "` spans [0, ", _extent_text(ext[d]), "] (", lat.dims[d], " sites of spacing ", _extent_text(Float64(h[d])),
            "); a model has one length unit: give `", xc[d], " ∈ Interval(0, ", _extent_text(ext[d]), ")`, or set the ",
            "lattice's `spacing` so that its extent is ", _extent_text(hi))))
    end
    ic = Dict{Any, Any}(_unwrap(k) => v for (k, v) in getfield(f, :initial_conditions))
    # a name the model has already: refused (the second declaration would hide or shadow the first)
    taken = Dict{Symbol, String}()
    for x in _p(sys, :parameters)
        i = info(x)
        i === nothing || (taken[i.name] = "a parameter")
    end
    for x in _p(sys, :variables)
        i = info(x)
        i === nothing || (taken[i.name] = i.role === :field ? "a field" : "a $(i.role) variable")
    end
    function fresh(n, what2)
        q = qname(n)
        haskey(taken, q) && throw(ArgumentError(string(what, ": ", pname, " declares ", what2, " `", n, "`, and `",
            nameof(sys), "` already has ", taken[q], " `", q, "`; give one of them another name, or compose the PDESystem ",
            "as a component, `Potts.compose(model, Potts.component(:name, pdesys, model))`, whose quantities are ",
            "namespaced (`name₊", n, "`)")))
        return q
    end
    # the parameters: model parameters with the same values and metadata; a computed value
    # (`k2 = 2k`) is made after the parameters it reads
    raw = getfield(f, :ps)
    raw = raw isa SciMLBase.NullParameters ? Any[] : collect(Any, raw)
    k = findfirst(q -> q isa Pair, raw)
    k === nothing || throw(ArgumentError(string(what, ": ", pname, " declares its parameters natively, `@parameters ",
        "Dc = 1e-3`; the `ps` entry `", raw[k], "` is a `Pair`")))
    raw = Any[_unwrap(q) for q in raw]
    for u in raw
        SymbolicUtils.symtype(u) <: AbstractArray && throw(ArgumentError(string(what, ": ", pname, " has the table `", u,
            "`; a kind table is the model's: declare it in the model (`@parameters ", u, "[kind] = …`) and read it there")))
    end
    pmap = Dict{Any, Any}()
    value(u) = haskey(ic, u) ? ic[u] : M.hasdefault(u) ? M.getdefault(u) : nothing
    symbolic(v) = v isa Union{Num, SymbolicUtils.BasicSymbolic} && !SymbolicUtils.isconst(_unwrap(v))
    reads(v) = symbolic(v) ? [w for w in Symbolics.get_variables(_unwrap(v)) if any(q -> isequal(q, w), raw)] : Any[]
    pending = copy(raw)
    while !isempty(pending)
        k = findfirst(u -> all(w -> haskey(pmap, w), reads(value(u))), pending)
        k === nothing && throw(ArgumentError("$what: the values of the parameters " *
                                             join(("`$u`" for u in pending), ", ") * " of $pname read each other"))
        u = popat!(pending, k)
        v = value(u)
        symbolic(v) && (v = Symbolics.substitute(_unwrap(v), pmap; fold = Val(false)))
        v isa Union{Num, SymbolicUtils.BasicSymbolic} && SymbolicUtils.isconst(_unwrap(v)) && (v = SymbolicUtils.unwrap_const(_unwrap(v)))
        b = SymbolicUtils.getmetadata(u, M.VariableBounds, nothing)
        pmap[u] = _unwrap(parameter(fresh(nameof(u), "the parameter"), v; tunable = M.istunable(u, true), bounds = b))
    end
    # the dependent variables: fields, and inputs the CPM fills by their word
    fmap, imap = Dict{Any, Any}(), Dict{Any, Any}()
    fields = Any[]
    for dv in getfield(f, :dvs)
        u = _unwrap(dv)
        (iscall(u) && length(arguments(u)) == length(ivs) && all(i -> isequal(arguments(u)[i], ivs[i]), eachindex(ivs))) ||
            throw(ArgumentError(string(what, ": the dependent variable `", u, "` of ", pname, " is not applied to its ",
                "independent variables (", join(ivs, ", "), ")")))
        op = operation(u)
        if M.isinput(u)
            w = something(LatticePDE.get_lattice_input_name(u), string(nameof(op)))
            target = _input_target(sys, Symbol(w))
            target === nothing && throw(ArgumentError(string(what, ": ", pname, " has the input `", u, "`, named `", w,
                "`, which the CPM of `", nameof(sys), "` does not fill at a site; name it by a word the CPM fills (`[input = ",
                "true, lattice_input_name = \"kind\"]` for the kind of each site; the words are ",
                join(("`$x`" for x in _SITE_WORDS), ", "), "), or by a field or site variable of the model",
                Symbol(w) in BUILTIN_NAMES ? string(" (`", w, "` is a cell property: hold it in a site variable, `@variables ",
                "s(site)`, `@after_mcs s ~ ", w, "[owner]`, and name the input `s`)") : "")))
            imap[op] = _unwrap(target)
        else
            push!(fields, (u, op))
        end
    end
    m = (; ivs, tc, xc, fmap, imap, pmap, face = false, what = "$what: $pname")
    # the conditions: a value at the start time (`c(0, x, y) ~ v`) is the field's initial value;
    # every other one is a `@bcs` condition
    start = Dict{Any, Any}()
    conds = Any[]
    k = tc === nothing ? nothing : findfirst(e -> isequal(_unwrap(e.variables), tc), dom)
    t0 = k === nothing ? 0.0 : Float64(minimum(dom[k].domain))
    for b in getfield(f, :bcs)
        l = _unwrap(b.lhs)
        a = iscall(l) ? arguments(l) : Any[]
        if tc !== nothing && iscall(l) && any(p -> isequal(p[2], operation(l)), fields) && length(a) == length(ivs) &&
           _unwrap_number(a[1]) isa Real && all(i -> isequal(a[i], ivs[i]), 2:length(a))
            _unwrap_number(a[1]) == t0 || throw(ArgumentError(string(what, ": ", pname, " gives `", b.lhs, " ~ ", b.rhs,
                "`, a value at the time ", a[1], "; a condition at a fixed time is the initial value, at the start of ",
                "the time interval, ", _extent_text(t0), " (write `", operation(l), "(", _extent_text(t0), ", …) ~ v`)")))
            haskey(start, operation(l)) && throw(ArgumentError("$what: $pname gives `$l` two initial values"))
            start[operation(l)] = b.rhs
        else
            push!(conds, b)
        end
    end
    variables = Any[]
    for (u, op) in fields
        v = haskey(ic, u) ? ic[u] : haskey(ic, op) ? ic[op] : haskey(start, op) ? start[op] :
            M.hasdefault(u) ? M.getdefault(u) : nothing
        if v !== nothing
            v = _pde_term(v, m)
            for w in (symbolic(v) ? Symbolics.get_variables(v) : ())
                i = info(w)
                i !== nothing && i.role === :param || throw(ArgumentError(string(what, ": the initial value of `", u,
                    "` in ", pname, " reads `", w, "`; a field's initial value is a number or an expression of parameters ",
                    "(give site values in the operating point, `:", qname(nameof(op)), " => values`)")))
            end
            SymbolicUtils.isconst(_unwrap(v)) && (v = SymbolicUtils.unwrap_const(_unwrap(v)))
        end
        opts = Pair{Symbol, Any}[]
        S = _dv_meta(u, op, LatticePDE.LatticeStorage)
        S === nothing || push!(opts, :lattice_storage => S)
        bd = _dv_meta(u, op, M.VariableBounds)
        bd === nothing || push!(opts, :bounds => bd)
        L = _dv_meta(u, op, LatticePDE.LatticeLevel)
        L === nothing || push!(opts, :lattice_level => L)
        n = fresh(nameof(op), "the field")
        x = only(Symbolics.@variables $n(t))
        fv = v === nothing ? variable(x, :field; opts...) : variable(x, :field; default = v, opts...)
        fmap[op] = _unwrap(fv)
        push!(variables, fv)
    end
    equations = Equation[Symbolics.wrap(_pde_term(eq.lhs, m)) ~ Symbolics.wrap(_pde_term(eq.rhs, m)) for eq in getfield(f, :eqs)]
    mf = (; m..., face = true)
    bcs = Equation[Symbolics.wrap(_pde_term(b.lhs, mf)) ~ Symbolics.wrap(_pde_term(b.rhs, mf)) for b in conds]
    return (; variables, parameters = Any[Symbolics.wrap(pmap[u]) for u in raw], equations, bcs)
end
_unwrap_number(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic && SymbolicUtils.isconst(u) ? SymbolicUtils.unwrap_const(u) : u)

# The model form of a term of the PDESystem (map `m` of `_pde_content`): its time is the model's
# `time` (`mcs` for `step_index(t)`), its coordinates the lattice's `x`, `y`, `z`, its fields
# and parameters the model's, its inputs the CPM words. In a condition (`m.face`), a field read
# at a face, `c(t, 0, y)`, is the `@bcs` read of the model's field.
function _pde_term(x, m)
    u = _unwrap(x)
    u isa SymbolicUtils.BasicSymbolic || return u
    SymbolicUtils.isconst(u) && return u
    m.tc !== nothing && isequal(u, m.tc) && return _unwrap(B.time)
    k = findfirst(v -> isequal(v, u), m.xc)
    k === nothing || return _FIELD_X[k]
    haskey(m.pmap, u) && return m.pmap[u]
    iscall(u) || throw(ArgumentError(string(m.what, " reads `", u, "`, which is not one of its dependent variables, ",
        "parameters or independent variables")))
    f, a = operation(u), arguments(u)
    if haskey(m.fmap, f) || haskey(m.imap, f)
        all(i -> isequal(a[i], m.ivs[i]), eachindex(a)) && return haskey(m.fmap, f) ? m.fmap[f] : m.imap[f]
        (haskey(m.fmap, f) && m.face) || throw(ArgumentError(string(m.what, " reads `", u, "` at a point; ",
            haskey(m.fmap, f) ? "an equation reads a field at its site (a condition reads it at a face)" :
            "an input is read at its site")))
        args = map(a) do y
            w = _unwrap(y)
            m.tc !== nothing && isequal(w, m.tc) && return _unwrap(t)
            j = findfirst(v -> isequal(v, w), m.xc)
            return j === nothing ? _unwrap_number(w) : _FIELD_X[j]
        end
        return _unwrap(_bcs_call(Symbolics.wrap(m.fmap[f]), args...))
    end
    if f isa Differential
        v = _unwrap(f.x)
        j = findfirst(w -> isequal(w, v), m.xc)
        nx = m.tc !== nothing && isequal(v, m.tc) ? _unwrap(t) : j === nothing ? throw(ArgumentError(string(m.what,
            " differentiates along `", v, "`, which is not one of its independent variables"))) : _FIELD_X[j]
        return _unwrap(Differential(nx, f.order)(Symbolics.wrap(_pde_term(only(a), m))))
    elseif f isa ModelingToolkitBase.Shift
        return _unwrap(ModelingToolkitBase.Shift(_unwrap(t), f.steps)(Symbolics.wrap(_pde_term(only(a), m))))
    elseif f === LatticePDE.step_index
        return _unwrap(B.mcs)
    end
    return _unwrap(f(map(y -> Symbolics.wrap(_pde_term(y, m)), a)...))
end

# `part` with the PDESystem `f` as fields, its quantities named `prefix₊n`
function _with_pde(sys::PottsSystem, part::PottsPart, f, prefix, what)
    c = _pde_content(_staged(nameof(sys), part), f, prefix, what)
    return getfield(_replace(_staged(nameof(sys), part); variables = Any[part.variables; c.variables],
        parameters = Any[part.parameters; c.parameters], equations = Equation[part.equations; c.equations],
        bcs = Equation[part.bcs; c.bcs]), :part)
end
