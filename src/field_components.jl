# A plain `PDESystem` as fields of a model (F4-11, FE-15b). `Potts.component(name, pdesys,
# model)` carries it, and `Potts.compose` moves it into the model's payload: each dependent
# variable becomes a field variable, each parameter a model parameter, each equation a field
# equation and each condition a condition of the payload (`bcs`). The fields then compile,
# group and run as the fields of `@fields` in `@potts_model`. A component's quantities are namespaced,
# `name₊c` and `name₊k`, as those of an MTK component are. A model wrapped with its own
# PDESystem (`Potts.wrap(name, sys, pdesys, part)`) has its fields moved the same way at
# `mtkcompile`, under their own names.

# The model a PDESystem's fields join: a `PottsSystem`, or (for `@fields`, while the model is
# being built) a NamedTuple `(; name, lattice, parameters, variables)` of what is declared so far
_hostname(sys::PottsSystem) = nameof(sys)
_hostname(h::NamedTuple) = h.name
_p(h::NamedTuple, f::Symbol) = getfield(h, f)

# the built-ins a field equation reads bare at a site (a cell property such as
# `volume` is read through the owner, `volume[owner]`, which a PDESystem cannot write)
const _SITE_WORDS = (:owner, :kind, :position, :site, :mcs, :time)
# the word an input of the PDESystem is filled by: a built-in a field equation reads at a site
# (`_SITE_WORDS`) or a field or site variable of the model (`nothing`: neither)
function _input_target(sys, w::Symbol)
    w in _SITE_WORDS && return getproperty(B, w)
    for x in _p(sys, :variables)
        i = info(x)
        i !== nothing && i.name === w && i.role in (:field, :site) && return x
    end
    return nothing
end

# MTK's metadata of the dependent variable `u` or of its callable `op`
_dv_meta(u, op, key) = (v = SymbolicUtils.getmetadata(u, key, nothing); v === nothing ? SymbolicUtils.getmetadata(op, key, nothing) : v)

# a quantity of the CPM (`kind`, `volume`, `owner`) read in a PDESystem: a PDESystem holds only
# its own fields, inputs and parameters, and a CPM value reaches it through a bound input; the
# model's clock (`time`, `mcs`) is the PDESystem's own time `t`, which is the model's `time` once
# coupled (`_pde_term`), and `step_index(t)` its MCS number
function _cell_quantity_text(n::Symbol, k = :cell)
    n === :time && return "`time`, the model's time; a PDESystem reads its own time: write its independent variable " *
           "`t` (`Potts.t`), which is the model's `time` where the PDESystem is coupled"
    n === :mcs && return "`mcs`, the model's MCS number; a PDESystem reads it from its own time: write " *
           "`step_index(t)` of its independent variable `t` (`Potts.t`), which is the model's `mcs` where the " *
           "PDESystem is coupled"
    return string("`", n, "`, a quantity of the CPM; a PDESystem cannot read cell quantities (`kind`, `volume`, ",
        "`owner`, …): declare an input, `@variables src(..)::Bool [input = true]`, read `src(t, x, y)` in the ",
        "equation, and bind it where the PDESystem is coupled, `@fields c = sys (src => kind == ", k,
        ")` or `Potts.couple(model, sys; inputs = [src => Potts.is_kind(model, :", k, ")])`")
end
# `LatticePDE.pdesystem` refuses a built-in of a model (its `potts_entity` is a Potts `Entity`)
LatticePDE.pdesystem_refusal(i::Entity, x) = i.role === :builtin ? "the equations read " * _cell_quantity_text(i.name) : nothing

"""
    _pde_content(sys, f, prefix, what) -> (; variables, parameters, equations, bcs)

The payload entries of the PDESystem `f` as fields of model `sys`: its quantities named
`prefix₊n` (`prefix === nothing`: `n`). An `ArgumentError` names what does not fit the model
(another domain than the lattice's, an input the CPM does not fill, a kind table).
"""
function _pde_content(sys, f::ModelingToolkitBase.PDESystem, prefix, what::AbstractString; inputs = (), values = nothing)
    M = ModelingToolkitBase
    pname = "the PDESystem `$(nameof(f))`"
    bound = _input_bindings(sys, f, inputs, what, pname)
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
        join(("`$v`" for v in ivs), ", "), "; the lattice of `", _hostname(sys), "` has ", N, " axes: give the time and one ",
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
    # `[0, dims[d] · spacing[d]]`, which is also the domain `Potts.fields` gives. An axis the
    # PDESystem gives no interval for takes the lattice's (F4-E5); a given one must match it.
    dom = getfield(f, :domain)
    for e in dom
        v = _unwrap(e.variables)
        any(w -> isequal(w, v), ivs) || throw(ArgumentError(string(what, ": ", pname, " gives the domain `", e.variables,
            " ∈ ", e.domain, "`, but `", e.variables, "` is not one of its independent variables (", join(ivs, ", "),
            "); give an interval only for an independent variable, or leave the spatial domain out (each axis then ",
            "takes the lattice's interval)")))
    end
    for d in 1:N
        k = findfirst(e -> isequal(_unwrap(e.variables), xc[d]), dom)
        k === nothing && continue
        lo, hi = Float64(minimum(dom[k].domain)), Float64(maximum(dom[k].domain))
        iszero(lo) && isapprox(hi, ext[d]; rtol = 1e-12) || throw(ArgumentError(string(what, ": ", pname, " spans `",
            xc[d], " ∈ [", _extent_text(lo), ", ", _extent_text(hi), "]`, but axis ", d, " of the lattice of `", _hostname(sys),
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
            _hostname(sys), "` already has ", taken[q], " `", q, "`; give one of them another name, or compose the PDESystem ",
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
        # a value given by the model's constructor keyword (`Model(; Dc = 1.0)`, `@fields`)
        v = values !== nothing && haskey(values, qname(nameof(u))) ? pop!(values, qname(nameof(u))) : value(u)
        symbolic(v) && (v = Symbolics.substitute(_unwrap(v), pmap; fold = Val(false)))
        v isa Union{Num, SymbolicUtils.BasicSymbolic} && SymbolicUtils.isconst(_unwrap(v)) && (v = SymbolicUtils.unwrap_const(_unwrap(v)))
        b = SymbolicUtils.getmetadata(u, M.VariableBounds, nothing)
        pmap[u] = _unwrap(parameter(fresh(nameof(u), "the parameter"), v; tunable = M.istunable(u, true), bounds = b))
    end
    # the dependent variables: fields, and inputs the CPM fills by their word
    fmap, imap = Dict{Any, Any}(), Dict{Any, Any}()
    fields = Any[]
    filled = Tuple{Symbol, Any, Type}[]         # (input name, CPM expression, element type), for `Potts.field_inputs`
    for dv in getfield(f, :dvs)
        u = _unwrap(dv)
        i = info(u)
        i !== nothing && i.role === :builtin &&
            throw(ArgumentError(string(what, ": ", pname, " lists ", _cell_quantity_text(i.name, _example_kind(sys)))))
        (iscall(u) && length(arguments(u)) == length(ivs) && all(i -> isequal(arguments(u)[i], ivs[i]), eachindex(ivs))) ||
            throw(ArgumentError(string(what, ": the dependent variable `", u, "` of ", pname, " is not applied to its ",
                "independent variables (", join(ivs, ", "), ")")))
        op = operation(u)
        if haskey(bound, op)
            # an input bound by the coupling (`Potts.couple(…; inputs)`, `@fields`): the CPM
            # expression, filled per site by the field compiler as any CPM read of a field equation
            imap[op] = bound[op]
            push!(filled, (Symbol(_input_key(u, op)), bound[op], _input_eltype(u, op)))
        elseif M.isinput(u)
            w = something(LatticePDE.get_lattice_input_name(u), string(nameof(op)))
            target = _input_target(sys, Symbol(w))
            k = _example_kind(sys)
            target === nothing && throw(ArgumentError(string(what, ": ", pname, " has the input `", u, "`, named `", w,
                "`, which no binding fills and the CPM of `", _hostname(sys), "` does not fill at a site; bind it to a CPM ",
                "expression, `@fields … (", nameof(op), " => kind == ", k, ")` in the model, or `inputs = [", nameof(op),
                " => Potts.is_kind(model, :", k, ")]` in `Potts.couple`; or name it by a word the CPM fills (`[input = ",
                "true, lattice_input_name = \"kind\"]` for the kind of each site; the words are ",
                join(("`$x`" for x in _SITE_WORDS), ", "), "), or by a field or site variable of the model",
                Symbol(w) in BUILTIN_NAMES ? string(" (`", w, "` is a cell property: hold it in a site variable, `@variables ",
                "s(site)`, `@after_mcs s ~ ", w, "[owner]`, and name the input `s`)") : "")))
            if _input_eltype(u, op) === Bool && !(SymbolicUtils.symtype(_unwrap(target)) <: Bool)
                # a word that is not a truth value (`kind` is the kind number) would reach the
                # equations as the number itself
                k = _example_kind(sys)
                route = what == "@fields" ? "$(nameof(op)) => $w == $k" : "$(nameof(op)) => Potts.$w == :$k"
                throw(ArgumentError(string(what, ": ", pname, " has the `Bool` input `", _input_key(u, op), "`, filled by ",
                    "the CPM word `", w, "`, which is not a truth value (", w == "kind" ? "the kind number of each site" :
                    "a number", "); bind it: `", route, "`, or declare the input without `::Bool`")))
            end
            imap[op] = _unwrap(target)
            push!(filled, (Symbol(_input_key(u, op)), _unwrap(target), _input_eltype(u, op)))
        else
            push!(fields, (u, op))
        end
    end
    # an input listed but read by no equation or condition: a term `src(t, x, y) ∈ Set(…)` is
    # Julia's `false` and deletes itself (`α * false` is 0), so the input is silently unused
    for (op, _) in imap
        any(eq -> _reads_op(eq.lhs, op) || _reads_op(eq.rhs, op), Iterators.flatten((getfield(f, :eqs), getfield(f, :bcs)))) &&
            continue
        @warn string(what, ": ", pname, " lists the input `", nameof(op), "`, which no equation or condition reads; a ",
            "membership test `", nameof(op), "(t, x, y) ∈ Set(…)` is Julia's `false`, which deletes its term: write ",
            "`ismember(", nameof(op), "(t, x, y), (1, 2))`, or leave the input out") maxlog = 1 _id = (nameof(f), nameof(op))
    end
    m = (; ivs, tc, xc, fmap, imap, pmap, face = false, what = "$what: $pname", kind = _example_kind(sys),
         noparams = isempty(raw))
    # the conditions: a value at the start time (`c(0, x, y) ~ v`) is the field's initial value;
    # every other one is a condition of the payload
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
        if SymbolicUtils.symtype(u) <: AbstractArray
            # an array field `u(..)[1:n]` (F4-E11): its components `u_1, …, u_n`, as `@variables
            # u(field)[1:n]` declares them; `u[i]` reads component `i`
            _pde_components!(variables, fmap, u, op, v, m, fresh, what, pname)
            continue
        end
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
    return (; variables, parameters = Any[Symbolics.wrap(pmap[u]) for u in raw], equations, bcs, inputs = filled)
end

# The components of the array field `u` (operation `op`) of a PDESystem as model fields (F4-E11):
# `vector_variable(name, 1:n, :field)`, the components `name_i` that `@variables name(field)[1:n]`
# declares, with the field's default (one value for every component, or one per component)
function _pde_components!(variables, fmap, u, op, v, m, fresh, what, pname)
    M = ModelingToolkitBase
    sz = size(u)
    length(sz) == 1 || throw(ArgumentError(string(what, ": the array field `", u, "` of ", pname, " has the shape ", sz,
        "; a field with components is a vector, `", nameof(op), "(..)[1:n]`")))
    n = sz[1]
    if v !== nothing
        v = v isa AbstractArray ? collect(v) : v
        v = v isa AbstractArray ? map(w -> _unwrap_number(_pde_term(w, m)), v) : _unwrap_number(_pde_term(v, m))
        all(w -> w isa Real, v isa AbstractArray ? v : (v,)) || throw(ArgumentError(string(what, ": the initial value of the ",
            "array field `", u, "` of ", pname, " is `", v, "`; give numbers (one for every component, or one per component)")))
    end
    opts = Pair{Symbol, Any}[]
    for (k, key) in ((:lattice_storage, LatticePDE.LatticeStorage), (:bounds, M.VariableBounds), (:lattice_level, LatticePDE.LatticeLevel))
        w = _dv_meta(u, op, key)
        w === nothing || push!(opts, k => w)
    end
    name = fresh(nameof(op), "the field")
    vv = v === nothing ? vector_variable(name, 1:n, :field; opts...) : vector_variable(name, 1:n, :field; default = v, opts...)
    fmap[op] = Any[_unwrap(c) for c in vv.components]
    append!(variables, vv.components)
    return nothing
end

# the name an input of a PDESystem goes by: its `lattice_input_name`, else its own name (the
# key `discretize(…; inputs)` takes)
_input_key(u, op) = something(LatticePDE.get_lattice_input_name(u), string(nameof(op)))
# the element type of an input's values: `Bool` (`endo(..)::Bool`), an integer type, else Real
function _input_eltype(u, op)
    S = SymbolicUtils.symtype(u)
    return S <: Bool ? Bool : S <: Integer ? S : Real
end

"""
    _input_bindings(sys, f, inputs, what, pname) -> Dict(op => CPM expression)

The bindings `inputs` (`endo => kind == A`, `vol => volume[owner]`) of the inputs of
the PDESystem `f` to CPM expressions of model `sys`, by the operation of each input. A key is
an input variable (`endo`, `endo(t, x, y)`) or its name (`:endo`, or its `lattice_input_name`).
An `ArgumentError` names a key that is not an input of `f`, an input bound twice, an
expression that reads something other than the model's quantities, and a `Bool` input bound
to a value that is not a truth value.
"""
function _input_bindings(sys, f, inputs, what, pname)
    out = Dict{Any, Any}()
    isempty(inputs) && return out
    M = ModelingToolkitBase
    dvs = Any[_unwrap(dv) for dv in getfield(f, :dvs)]
    ops = [(u, iscall(u) ? operation(u) : nothing) for u in dvs]
    names = join(("`$(_input_key(u, op))`" for (u, op) in ops if op !== nothing && M.isinput(u)), ", ")
    for b in inputs
        b isa Pair || throw(ArgumentError("$what: the inputs are pairs `input => expression`; got `$b`"))
        key, ex = b
        if key isa _NamedKey
            # `@fields … (cell => …)`: the name of an input first, then the local value (F4-E2)
            k = _binding_target(key.name, ops)
            k === nothing && (key = _key_value(key); k = _binding_target(key, ops))
        else
            k = _binding_target(key, ops)
        end
        k === nothing && throw(ArgumentError(string(what, ": `", _key_text(key), "` is not a dependent variable of ", pname,
            "; its inputs are ", isempty(names) ? "none" : names, _declared_input(key, getfield(f, :ivs)) ?
            string(". `", _key_text(key), "` is declared `[input = true]`, but no equation of ", pname, " reads it: a ",
            "membership test `", _key_text(key), "(t, x, y) ∈ Set(…)` is Julia's `false`, so its term is deleted before ",
            "the PDESystem is built; write `ismember(", _key_text(key), "(t, x, y), (1, 2))`") : "")))
        u, op = ops[k]
        M.isinput(u) || throw(ArgumentError(string(what, ": `", _key_text(key), "` is a dependent variable of ", pname,
            " but not an input; declare it `[input = true]` to bind it to a CPM expression")))
        haskey(out, op) && throw(ArgumentError("$what: the input `$(_input_key(u, op))` is bound twice"))
        # a constant term is its value: in a vector that also holds a symbolic binding, Julia
        # promotes `false` to `Num(false)` (F4-E1), which must meet the same check as `false`
        e = _unwrap_number(ex)
        # `Potts.kind == :A` is Julia's `==` of a symbol and a Symbol: the constant `false`, built
        # before any symbolic term exists, so the kind name cannot be recovered here
        k = _example_kind(sys)
        e isa Bool && throw(ArgumentError(string(what, ": the input `", _input_key(u, op), "` is bound to the constant `", e,
            "`; a binding to a constant is the same at every site: bind a test of a cell property (`kind == 1`, ",
            "`volume[owner] > v`), or write the constant in the equation", e ? "" : string(". Two tests are `false` in ",
            "Julia (no symbolic term is built): `kind` against a kind name, `Potts.kind == :", k, "`, and a membership ",
            "test, `Potts.kind ∈ Set(…)`; write `Potts.is_kind(model, :", k, ")` (several kinds: `Potts.is_kind(model, :",
            k, ", …)`)", what == "@fields" ? string(", or in `@fields`, `kind == ", k, "` and `ismember(kind, (a, b))`") : ""))))
        # `Potts.kind ∈ (a, b)`: Symbolics builds an interval pairing, not a membership test
        ex isa Symbolics.VarDomainPairing && throw(ArgumentError(string(what, ": the input `", _input_key(u, op),
            "` is bound to `", _builtin_text(string(ex.variables)), " ∈ ", ex.domain, "`, which Symbolics builds as an ",
            "interval pairing (a domain), not a membership test; write `Potts.is_kind(model, :", k, ", …)` for kinds, or ",
            "`ismember(", _builtin_text(string(ex.variables)), ", (a, b))`")))
        e isa Union{Real, SymbolicUtils.BasicSymbolic} ||
            throw(ArgumentError("$what: the input `$(_input_key(u, op))` is bound to `$ex`, which is not an expression"))
        for v in (e isa SymbolicUtils.BasicSymbolic ? Symbolics.get_variables(e) : ())
            info(v) === nothing && !_coordinate(v) && throw(ArgumentError(string(what, ": the input `", _input_key(u, op),
                "` is bound to `", ex, "`, which reads `", v, "`, not a quantity of `", _hostname(sys), "`; bind an input to ",
                "an expression of the model's quantities at a site (`kind == k`, `volume[owner]`, a parameter, a site ",
                "variable)")))
        end
        for n in (e isa SymbolicUtils.BasicSymbolic ? _bare_cell_reads(e) : ())
            throw(ArgumentError(string(what, ": the input `", _input_key(u, op), "` is bound to `", _builtin_text(string(ex)),
                "`, which reads the cell property `", n, "` bare; an input is a value at each site: read it at the site's ",
                "owner, `", n, "[owner]`")))
        end
        if _input_eltype(u, op) === Bool
            _truth_valued(e) || throw(ArgumentError(string(what, ": the input `", _input_key(u, op), "` is a `Bool`, and `",
                _builtin_text(string(ex)), "` is not a truth value; bind it to a test (`kind == k`, `volume[owner] > v`, ",
                "`any(kind[n] == k for n in R(site))`) or declare the input without `::Bool`")))
        end
        out[op] = e
    end
    return out
end
# whether `x` applies the callable `op` (`src(t, x, y)`) anywhere
function _reads_op(x, op)
    x isa AbstractArray && return any(y -> _reads_op(y, op), x)
    u = _unwrap(x)
    u isa SymbolicUtils.BasicSymbolic && !SymbolicUtils.isconst(u) && iscall(u) || return false
    return isequal(operation(u), op) || any(a -> _reads_op(a, op), arguments(u))
end
# whether a binding key that names no input of the PDESystem is a variable declared `[input =
# true]` (applied at the PDESystem's independent variables `ivs` when it is a callable)
function _declared_input(key, ivs)
    key isa Union{Symbol, AbstractString, _NamedKey} && return false
    if key isa Union{Num, SymbolicUtils.BasicSymbolic}
        u = _unwrap(key)
    else
        applicable(key, ivs...) || return false
        u = _unwrap(key(ivs...))
    end
    return u isa SymbolicUtils.BasicSymbolic && ModelingToolkitBase.isinput(u)
end
# whether a binding is a truth value (F4-E9): of type `Bool`, a comparison, `ismember`, `!`,
# `&`, `|` or `xor` of truth values, an `ifelse` of two, or an `any`/`all` fold over a relation or
# a population (`any(kind[n] == k for n in R(site))`, whose symbolic type is not `Bool`)
const _TRUTH_OPS = (==, !=, <, <=, >, >=, isequal)
function _truth_valued(e)
    e isa Bool && return true
    e isa SymbolicUtils.BasicSymbolic || return false
    SymbolicUtils.isconst(e) && return SymbolicUtils.unwrap_const(e) isa Bool
    SymbolicUtils.symtype(e) <: Bool && return true
    iscall(e) || return false
    f, a = operation(e), arguments(e)
    (f in _TRUTH_OPS || f === LatticePDE.ismember) && return true
    f in (!, ~, &, |, xor) && return all(_truth_valued, a)
    f === ifelse && return _truth_valued(a[2]) && _truth_valued(a[3])
    if f === gather || f === population
        i = info(a[1])
        return i !== nothing && get(i.options, :op, nothing) in (:any, :all)
    end
    return false
end

# the bare built-ins of `e` that are cell properties, not values at a site (`volume`, not
# `volume[owner]`): a field equation reads only the site words bare (`kind`, `owner`, …)
function _bare_cell_reads(e)
    out = Symbol[]
    walk(x) = begin
        x isa SymbolicUtils.BasicSymbolic || return
        SymbolicUtils.isconst(x) && return
        i = info(x)
        if i !== nothing
            i.role === :builtin && !(i.name in _SITE_WORDS) && push!(out, i.name)
            return
        end
        iscall(x) || return
        a = arguments(x)
        if operation(x) === at && length(a) == 2
            walk(a[2])                       # `volume[owner]`: the property read at a cell
        else
            foreach(walk, a)
        end
    end
    walk(e)
    return unique!(out)
end

# the right side `X` of `kind == X` in an `@fields` binding (`f() = X`): a kind number, else an
# `ArgumentError` listing the model's kinds (`kind == cells` reads Potts' `cells` and is `false`)
function _binding_kind(f, name::Symbol, kinds)
    v = try
        f()
    catch err
        err isa UndefVarError && err.var === name || rethrow()
        nothing
    end
    v isa Union{Integer, Num, SymbolicUtils.BasicSymbolic} && !(v isa Bool) && return v
    throw(ArgumentError(string("@fields: the binding `kind == ", name, "` compares the kind with `", name, "`, which is ",
        "not a kind of the model", v === nothing ? "" : string(" (it is ", v isa Function ? "the function " : "", "`", v, "`)"),
        "; its kinds are ", join(("`$k`" for k in kinds), ", "))))
end
# a kind name of model `sys` for messages (its second kind, else its first, else `A`)
_example_kind(sys) = (ks = _p(sys, :kinds); length(ks) >= 2 ? ks[2] : isempty(ks) ? :A : ks[1])

# a bare-symbol key of an `@fields` binding (`cell => kind == cell`): its name, matched against
# the inputs of the PDESystem first, and its value in the constructor (a closure), read only when
# no input has that name (F4-E2: so a kind `cell` does not shadow the input `cell`)
struct _NamedKey{F}
    name::Symbol
    value::F
end
Base.show(io::IO, k::_NamedKey) = print(io, k.name)
# the local value of `key`; its name when no local or global of that name is defined
function _key_value(key::_NamedKey)
    return try
        key.value()
    catch err
        err isa UndefVarError && err.var === key.name || rethrow()
        key.name
    end
end

# a binding key as the user wrote it: a callable variable (`@variables endo(..)`) prints as
# `endo⋆` (Symbolics' `CallAndWrap`)
_key_text(key) = rstrip(string(key), '⋆')
# the entry of `ops` (dependent variables and their operations) that `key` names
function _binding_target(key, ops)
    if key isa Union{Symbol, AbstractString}
        return findfirst(((u, op),) -> op !== nothing && (Symbol(key) === nameof(op) || string(key) == _input_key(u, op)), ops)
    end
    k = key isa Union{Num, SymbolicUtils.BasicSymbolic} ? _unwrap(key) : key
    if k isa SymbolicUtils.BasicSymbolic && iscall(k)
        j = findfirst(((u, _),) -> isequal(u, k), ops)
        j === nothing || return j
        k = operation(k)
    end
    j = findfirst(((_, op),) -> op !== nothing && isequal(op, k), ops)
    j === nothing || return j
    # a callable variable (`@variables endo(..)`) by its name
    n = Symbol(_key_text(key))
    return findfirst(((u, op),) -> op !== nothing && nameof(op) === n, ops)
end
_unwrap_number(x) = (u = _unwrap(x); u isa SymbolicUtils.BasicSymbolic && SymbolicUtils.isconst(u) ? SymbolicUtils.unwrap_const(u) : u)

# The model form of a term of the PDESystem (map `m` of `_pde_content`): its time is the model's
# `time` (`mcs` for `step_index(t)`), its coordinates the lattice's `x`, `y`, `z`, its fields
# and parameters the model's, its inputs the CPM words. In a condition (`m.face`), a field read
# at a face, `c(t, 0, y)`, is the face read of the model's field (`_bcs_call`).
function _pde_term(x, m)
    u = _unwrap(x)
    u isa SymbolicUtils.BasicSymbolic || return u
    SymbolicUtils.isconst(u) && return u
    m.tc !== nothing && isequal(u, m.tc) && return _unwrap(B.time)
    k = findfirst(v -> isequal(v, u), m.xc)
    k === nothing || return _FIELD_X[k]
    haskey(m.pmap, u) && return m.pmap[u]
    i = info(u)
    i !== nothing && i.role === :builtin && throw(ArgumentError(string(m.what, " reads ", _cell_quantity_text(i.name, m.kind))))
    iscall(u) || throw(ArgumentError(string(m.what, " reads `", u, "`, which is not one of its dependent variables, ",
        "parameters or independent variables", m.noparams ? "; list it in the 6th argument of `PDESystem` (its " *
        "parameters, empty here), or build the system with `pdesystem`, which lists them" : "")))
    f, a = operation(u), arguments(u)
    # `u[i]` of an array field (F4-E11): component `i`, at its site or a face
    if f === getindex && length(a) == 2 && iscall(_unwrap(a[1])) && (g = operation(_unwrap(a[1])); haskey(m.fmap, g)) &&
       m.fmap[g] isa AbstractVector
        i = _unwrap_number(a[2])
        i isa Integer && 1 <= i <= length(m.fmap[g]) || throw(ArgumentError(string(m.what, " reads `", u, "`; a component ",
            "is read by its number, 1 to ", length(m.fmap[g]))))
        return _pde_read(_unwrap(a[1]), m.fmap[g][i], m)
    end
    # an array literal (`Advect(…)([ux, 0.0], c)`, F4-E12): its shape stays, its elements map
    if f === SymbolicUtils.array_literal
        return reshape(Base.vect((Symbolics.wrap(_pde_term(y, m)) for y in a[2:end])...), _unwrap_number(a[1]))
    end
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

# a read of a component `comp` of an array field, `r = u(t, x, y)` at its site (the component) or
# `u(t, 0, y)` at a face in a condition (the face read of the component)
function _pde_read(r, comp, m)
    a = arguments(r)
    all(i -> isequal(a[i], m.ivs[i]), eachindex(a)) && return comp
    m.face || throw(ArgumentError(string(m.what, " reads `", r, "` at a point; an equation reads a field at its site ",
        "(a condition reads it at a face)")))
    args = map(a) do y
        w = _unwrap(y)
        m.tc !== nothing && isequal(w, m.tc) && return _unwrap(t)
        j = findfirst(v -> isequal(v, w), m.xc)
        return j === nothing ? _unwrap_number(w) : _FIELD_X[j]
    end
    return _unwrap(_bcs_call(Symbolics.wrap(comp), args...))
end

# `part` with the PDESystem `f` as fields, its quantities named `prefix₊n`
function _with_pde(sys::PottsSystem, part::PottsPart, f, prefix, what; inputs = ())
    c = _pde_content(_staged(nameof(sys), part), f, prefix, what; inputs)
    # the inputs of the moved fields by name, kept for `Potts.field_inputs` (never in code or
    # fingerprint)
    md = part.metadata
    isempty(c.inputs) || (md = Base.ImmutableDict(md, _FieldInputs => [get(md, _FieldInputs, Tuple{Symbol, Any, Type}[]); c.inputs]))
    md = _with_bcs_origins(md, Pair{Any, Symbol}[b => nameof(f) for b in [c.bcs; c.equations]])
    md = _with_coupled(md, _coupled_names(c.variables))
    return getfield(_replace(_staged(nameof(sys), part); variables = Any[part.variables; c.variables],
        parameters = Any[part.parameters; c.parameters], equations = Equation[part.equations; c.equations],
        bcs = Equation[part.bcs; c.bcs], metadata = md), :part)
end
# payload metadata key: the inputs of the PDESystems moved into the payload, `(name, CPM
# expression, element type)`, by the names their PDESystems give them
struct _FieldInputs end

# `@fields [names =] pdesys (bindings…)` in `@potts_model` (F4-B2): the content of the PDESystem
# `f` as fields of the model being built, from what it declares before the `@fields` line (its
# lattice, or that of its first `@extend` base)
function _fields_content(name::Symbol, lattice, kinds, bases, params, vars, f, inputs, values)
    lattice === nothing && !isempty(bases) && (lattice = _p(first(bases), :lattice))
    lattice === nothing && throw(ArgumentError("@fields: model `$name` has no lattice yet; write `@fields` after `@lattice`"))
    isempty(kinds) && !isempty(bases) && (kinds = _p(first(bases), :kinds))
    f isa ModelingToolkitBase.PDESystem ||
        throw(ArgumentError("@fields takes a `PDESystem`; got a `$(typeof(f))`"))
    host = (; name, lattice, kinds, parameters = params, variables = vars)
    return _pde_content(host, f, nothing, "@fields"; inputs = collect(Any, inputs), values)
end
# The constructor keywords of a model with `@fields` that no declaration took: the values of
# the PDESystems' parameters (`Model(; Dc = 1.0)`), taken by `_pde_content`; any left over is
# a keyword the model does not have
function _fields_keywords_left(name, kw)
    isempty(kw) && return nothing
    throw(ArgumentError(string("model `", name, "` has no keyword ", join(("`$k`" for k in keys(kw)), ", "),
        " (its keywords are its structural parameters, its parameters and those of its `@fields` PDESystems)")))
end
# a parameter or field that `@fields` brought in and the model declares again after the line
function _check_fields_names(params, vars, brought::Dict{Symbol, String})
    seen = Dict{Symbol, Int}()
    for x in Iterators.flatten((params, vars))
        i = info(x)
        i === nothing && continue
        seen[i.name] = get(seen, i.name, 0) + 1
    end
    for (n, k) in seen
        k > 1 && haskey(brought, n) && throw(ArgumentError(string("`", n, "` is already declared by `@fields` (", brought[n],
            "); give the model's declaration another name, or set the value of the PDESystem's `", n,
            "` with the constructor keyword or the operating point")))
    end
    return nothing
end
# the field or parameter named `n` of the content `c` of the PDESystem `f` (`@fields c, Dc = f`;
# F4-E8: a parameter too, so a later statement reads it by name)
function _fields_name(c, n::Symbol, f)
    for x in Iterators.flatten((c.variables, c.parameters))
        info(x).name === n && return x
    end
    comps = [x for x in c.variables if get(info(x).options, :vector, nothing) === n]      # an array field (F4-E11)
    isempty(comps) || return QuantityVector(n, Num[Symbolics.wrap(x) for x in comps])
    throw(ArgumentError(string("@fields ", n, " = ", nameof(f), ": `", n, "` is not a field of the PDESystem `", nameof(f),
        "`; its fields are ", join(("`$(info(x).name)`" for x in c.variables), ", "), isempty(c.parameters) ? "" :
        string(", and its parameters (a name may be one too) ", join(("`$(info(x).name)`" for x in c.parameters), ", ")))))
end
# the build record of a model with the inputs of its `@fields` PDESystems (`Potts.field_inputs`),
# the PDESystem each of its conditions came from (F4-E10) and the fields they brought
_with_field_inputs(md, ins, origins = (), coupled = ()) =
    _with_coupled(_with_bcs_origins(isempty(ins) ? md : Base.ImmutableDict(md, _FieldInputs => collect(Tuple{Symbol, Any, Type}, ins)),
            origins), coupled)

# payload metadata key (F4-B6): the names of the fields that coupled PDESystems brought (`@fields`,
# `Potts.couple`, `Potts.compose`, `Potts.wrap`). Their equations are the model's field equations;
# any other equation of a field is refused (`_check_field_lines`). An extension keeps its bases'
# entries (`_merged_metadata`).
struct _CoupledFields end
_coupled_names(vars) = Symbol[info(x).name for x in vars]
_with_coupled(md, names) = isempty(names) ? md : Base.ImmutableDict(md, _CoupledFields => collect(Symbol, names))
_coupled_fields(part) = Set{Symbol}(n for (k, v) in part.metadata if k === _CoupledFields for n in v)

# The fields an equation writes: its left side's field (`D(c) ~ …`, `Shift(t, 1)(m) ~ …`, an aux
# `K ~ …`), or the fields a steady row `0 ~ …` reads; empty for a cell or model equation
function _field_line_names(eq)
    f = _field_lhs(eq)
    f === nothing && return Symbol[]
    f[1] === nothing || return Symbol[info(f[1]).name]
    return Symbol[info(x).name for x in _steady_reads(eq).all]
end
_field_names_text(ns) = join(("`$n`" for n in ns), ", ")
# An `@equations` line that writes a field (F4-B6): a model's fields are coupled PDESystems
# (`text`: the line as written in the model body, when the macro has it)
_no_field_line(x::AbstractVector, text = nothing) = (foreach(e -> _no_field_line(e, text), x); x)
_no_field_line(x, text = nothing) = x
function _no_field_line(eq::Equation, text = nothing)
    ns = _field_line_names(eq)
    isempty(ns) && return eq
    throw(ArgumentError(string("@equations: `", text === nothing ? _builtin_text(string(eq)) : text, "` is an equation of the field",
        length(ns) == 1 ? " " : "s ", _field_names_text(ns), "; `@equations` holds cell and model equations. Write the ",
        "field as a PDESystem (`using Potts.Fields`) and couple it into the model with `@fields ", first(ns),
        " = pdesys (input => expression)`")))
end
# The equations of the payload `part` (`PottsSystem(; equations)`) that write a field no coupled
# PDESystem brought (F4-B6): refused, with the route `Potts.couple`
function _check_field_lines(part::PottsPart)
    coupled = nothing
    for eq in part.equations
        ns = _field_line_names(eq)
        isempty(ns) && continue
        coupled === nothing && (coupled = _coupled_fields(part))
        all(n -> n in coupled, ns) && continue
        throw(ArgumentError(string("PottsSystem: the equation `", _builtin_text(string(eq)), "` is an equation of the field",
            length(ns) == 1 ? " " : "s ", _field_names_text(ns), ", which no coupled PDESystem brought; a model's fields are ",
            "a PDESystem coupled into it: `Potts.couple(model, pdesys; inputs = [input => expression])`")))
    end
    return part
end

# payload metadata key (F4-E10): `condition => PDESystem name` for the conditions and the field
# equations a PDESystem brought (`@fields`, `Potts.couple`), so a refusal of one names the
# PDESystem (the equations since the batch-end review (d)). An
# extension keeps its bases' entries (`_merged_metadata` keeps every entry; this reads them all).
struct _BcsOrigins end
_with_bcs_origins(md, origins) = isempty(origins) ? md : Base.ImmutableDict(md, _BcsOrigins => collect(Pair{Any, Symbol}, origins))
function _bcs_origin(sys, eq)
    for (k, v) in _p(sys, :metadata)
        k === _BcsOrigins || continue
        for (b, n) in v
            (b === eq || isequal(b, eq)) && return n
        end
    end
    return nothing
end
