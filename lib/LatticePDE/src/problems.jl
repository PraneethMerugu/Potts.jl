# `discretize`: a `PDESystem` on a lattice becomes a problem (v3 §5, §7.4, §8).
#   :owned  FieldProblem: the fused rate + Euler update kernels (`c + dt · rhs`), stepped by
#           ExplicitEuler (rates) or ExplicitMap (maps) through prebuilt launches.
#   :ode    ODEProblem: the rate kernels (`∂c = rhs`) as `LatticeRHS`, for SciML solvers.
#   :auto   ODEProblem for transient FV, FieldProblem when a discrete map is present.
#   :linear LinearProblem for steady systems: the solvers commit (C7b).

"""The explicit Euler update `c + dt · r` of the owned stepper (`dt = G.rt[2]`)."""
euler_update(kb, c, r) = c + Ex(kb, runtime!(kb, RT_DT)) * r

# symbol table keys: a `Symbol` or string names a field or parameter; any other symbol is
# looked up as its unwrapped term
_symkey(x::Union{Symbol, AbstractString}) = Symbol(x)
_symkey(x) = unwrap(x)

function _domain_ends(sys::PDESystem)
    return map(unwrap.(sys.ivs)) do v
        k = findfirst(d -> isequal(unwrap(d.variables), v), sys.domain)
        Float64.((leftendpoint(sys.domain[k].domain), rightendpoint(sys.domain[k].domain)))
    end
end

# a coefficient expression as a function of the raw parameter vector, over every 0/1
# assignment of its indicator terms (kind sets, comparisons): an indicator is 0 or 1 at each
# site, and the coefficient is not monotone in it (`k (1 − χ)` is largest at χ = 0), so each
# assignment is evaluated. `c(p)` is the largest magnitude, `_hi`/`_lo` the largest and
# smallest signed values. `nothing` when the expression reads anything but scalar parameters
# (array elements such as `Dk[2]` included), keeps a call that is not plain arithmetic (a
# registered operator such as `Δ`), or has more than `_MAXIND` distinct indicators.
struct CoefBound
    fs::Vector{Any}                     # one compiled function of the parameters per assignment
end
(c::CoefBound)(p) = maximum(f -> abs(Float64(f(p...))), c.fs)
_hi(c::CoefBound, p) = maximum(f -> Float64(f(p...)), c.fs)
_lo(c::CoefBound, p) = minimum(f -> Float64(f(p...)), c.fs)
const _MAXIND = 6
const _PLAIN = (+, -, *, /, ^, inv, abs, sqrt, cbrt, exp, log, sin, cos, tan, tanh, min, max)
_plainop(f) = any(g -> f === g, _PLAIN)
function _coef_bound(x, params)
    u0 = unwrap(x)
    inds = Any[]
    walk(y) = iscall(y) && ((operation(y) === ismember || operation(y) in (==, <, <=, >, >=)) ?
                            (any(z -> isequal(z, y), inds) || push!(inds, y)) : foreach(walk, arguments(y)))
    walk(u0)
    length(inds) <= _MAXIND || return nothing
    plain(y) = !iscall(y) || (_plainop(operation(y)) && all(plain, arguments(y)))
    fs = Any[]
    for bits in Iterators.product(ntuple(_ -> (0, 1), length(inds))...)
        u = isempty(inds) ? u0 : unwrap(substitute(u0, Dict{Any, Any}(zip(inds, bits)); fold = Val(true)))
        plain(u) || return nothing
        all(v -> any(q -> isequal(q, v), params), Symbolics.get_variables(u)) || return nothing
        push!(fs, Symbolics.build_function(u, params...; expression = Val(false)))
    end
    return CoefBound(fs)
end

# the multiplier of a diffusion term: the operator call replaced by its coefficient (1 for
# Δ and Dx(Dx(c)), K for DivKGrad(K, c) and Dx(K Dx(c)))
function _diffusion_coefficient(term)
    reps = Dict{Any, Any}()
    walk(y) = iscall(y) && (f = operation(y);
                            f === Δ ? (reps[y] = 1) :
                            f isa DivKGrad ? (reps[y] = arguments(y)[1]) :
                            f isa Differential ? (r = _raw_flux(y); reps[y] = r === nothing || r[1] === nothing ? 1 : r[1]) :
                            foreach(walk, arguments(y)))
    walk(unwrap(term))
    return substitute(term, reps; fold = Val(false))
end

"""
    StabilityBound

`ρ(p)`: a bound on the spectral radius of the rate Jacobian at raw parameters `p` (v3 §6.2,
the Gershgorin bound; for one diffusing field `D Σ 4/h² + |k|`), built from the linearity
table. Per rate field (one Jacobian row):
- `Diffusion` terms give `D = Σ D_i(p)` times `Σ_d 4/h_d²`, plus `|D| max(0, |r| − 1)/h_d²`
  for a parameter-dependent Robin face on axis `d` (the ghost value's cell coefficient
  `r = (α/2 − β)/(α/2 + β)` stiffens the boundary row);
- `LinearLocal` terms (`k c`) add `|k|`;
- `CrossLinear` terms add their off-diagonal row sum: `|k|` for `k o`, and
  `|D₂| (Σ_d 4/h_d² + Robin terms of o)` for cross-diffusion `D₂ Δ(o)`.
A coefficient with kind sets or comparisons (indicators, 0 or 1 per site) is evaluated at
every 0/1 assignment of them: the largest magnitude enters `ρ`, the largest signed value
the diagonal.
A switch `ifelse(cond, a, b)` (class `Other`) whose condition reads no unknown field (a
gate such as `t ≥ t_relax`) is bounded arm by arm: each choice of a row's switch arms is a
row of its own (at most 64 per row), the bound is the worst, and the dominance test below
holds for every choice (listed in `expanded`).

`NaN` (no bound) when:
- a field has a term the bound cannot see (`unbounded`: `Other`, `Advection`,
  `LaggedSwitch`, or a coefficient that reads more than scalar parameters, such as an array
  element `Dk[2] * Δ(c)` or a table `at(Dk, kind)`, or a coefficient with more than 6
  distinct kind sets and comparisons, whose 2⁶ indicator assignments are the evaluation cap);
- a needed parameter has no value;
- a row with `CrossLinear` terms is not diagonally dominant with a nonpositive diagonal. The
  step limit `dt ρ ≤ 1.8` holds for real, dissipative spectra only; coupled rows such as
  `c' = a o, o' = −a c` have imaginary eigenvalues, which forward Euler amplifies at any
  step. Until the disk test of v3 §6.2 lands (C7c), such systems are refused instead of
  given the §6.2 warning fallback (a provisional decision).

With no bound, `ExplicitEuler` requires a user substep count. Until the IR tangent and
interval evaluator replace it (C7c), this is the stability analysis of the explicit steppers.
"""
# The terms of one row of the Jacobian under one choice of the arms of its `ifelse` switches
struct RowTerms
    diffusion::Vector{CoefBound}
    linear::Vector{CoefBound}
    crosslinear::Vector{CoefBound}
    crossdiffusion::Vector{Tuple{CoefBound, Int}}   # coefficient, index of the other field
end
RowTerms() = RowTerms(CoefBound[], CoefBound[], CoefBound[], Tuple{CoefBound, Int}[])
Base.copy(r::RowTerms) = RowTerms(copy(r.diffusion), copy(r.linear), copy(r.crosslinear), copy(r.crossdiffusion))
const _MAXARMS = 64                       # row alternatives (arm choices) before giving up

struct StabilityBound
    invh2::Vector{Float64}
    keys::Vector{String}
    rows::Vector{Vector{RowTerms}}        # per row, one entry per choice of its switches' arms
    faces::Vector{Vector{Tuple{Int, Coef, Coef}}}
    unbounded::Vector{String}
    terms::Vector{String}                 # the terms it cannot see, as `"key: term"`
    expanded::Vector{String}              # the `ifelse` terms bounded arm by arm
end
_cv(c::Coef, p) = c.param == 0 ? c.value : c.value * Float64(p[c.param])
# Σ_d max(0, |r| − 1)/h_d², the worst Robin face of each axis of field `i`
function _face_excess(b::StabilityBound, i, p)
    return sum(eachindex(b.invh2); init = 0.0) do d
        b.invh2[d] * maximum((max(0.0, abs(Problems.face_ratio(_cv(α, p), _cv(β, p))) - 1)
                              for (ax, α, β) in b.faces[i] if ax == d); init = 0.0)
    end
end
function (b::StabilityBound)(p)
    isempty(b.unbounded) || return NaN
    r = bound_parts(b, p)
    return isempty(r.coupled) ? r.ρ : NaN
end

"""
    bound_parts(b::StabilityBound, p) -> (; ρ, coupled, negative)

The parts of `b(p)`: `ρ`, the Gershgorin bound over the terms `b` sees (a term in
`b.terms` is left out); `coupled`, the keys of the rows with cross terms that are not
diagonally dominant with a nonpositive diagonal (`b(p)` is `NaN` for them); `negative`, the
keys of the rows with a diffusion coefficient below zero at `p` (at some indicator
assignment). `b(p) == ρ` when `b.unbounded` and `coupled` are empty.
"""
function bound_parts(b::StabilityBound, p)
    s4 = 4 * sum(b.invh2)
    ρ = 0.0
    coupled, negative = String[], String[]
    for i in eachindex(b.keys)
        # each choice of the row's switch arms is a row of its own: the bound is the worst,
        # and the row is coupled when any choice is not diagonally dominant
        for r in b.rows[i]
            any(f -> _lo(f, p) < 0, r.diffusion) && push!(negative, b.keys[i])
            Dmag = sum(f(p) for f in r.diffusion; init = 0.0)
            own = Dmag * (s4 + _face_excess(b, i, p))
            lin = sum(f(p) for f in r.linear; init = 0.0)
            cross = sum(f(p) for f in r.crosslinear; init = 0.0) +
                    sum(f(p) * (s4 + _face_excess(b, j, p)) for (f, j) in r.crossdiffusion; init = 0.0)
            if !isempty(r.crosslinear) || !isempty(r.crossdiffusion)
                # the diagonal at its largest over the indicator assignments
                diag = -2 * sum(b.invh2) * sum(_lo(f, p) for f in r.diffusion; init = 0.0) +
                       sum(_hi(f, p) for f in r.linear; init = 0.0)
                offd = Dmag * (s4 / 2 + _face_excess(b, i, p)) + cross
                diag <= 0 && -diag >= offd || push!(coupled, b.keys[i])
            end
            ρ = max(ρ, own + lin + cross)
        end
    end
    return (; ρ, coupled = unique!(coupled), negative = unique!(negative))
end

"""
    stability_bound(cf::CompiledField, sys) -> StabilityBound

The [`StabilityBound`](@ref) of the rate fields of `cf`; call it with a parameter vector.
"""
function stability_bound(cf::CompiledField{N}, sys::PDESystem) where {N}
    ks = sort!(collect(keys(cf.linearity)))
    states = Set(_states(cf.program))
    dvs = Dict{String, Any}()            # state key → its term (inputs and aux are not rows)
    for v in sys.dvs, (op, kk) in cf.keys
        isequal(_opof(v), op) || continue
        u = unwrap(v)
        for (i, k) in enumerate(kk)
            k in states && (dvs[k] = length(kk) == 1 ? u : unwrap(Symbolics.wrap(u)[i]))
        end
    end
    stateops = unique([_opof(v) for v in values(dvs)])
    others = [v for v in unwrap.(sys.dvs) if !any(o -> isequal(o, _opof(v)), stateops)]
    inputops = unique([_opof(v) for v in others if ModelingToolkitBase.isinput(v)])
    auxops = unique([_opof(v) for v in others if !ModelingToolkitBase.isinput(v)])   # `K ~ expr` fields
    unknownops = [stateops; auxops]
    rows = Vector{RowTerms}[]
    faces, unbounded, terms, expanded = Vector{Tuple{Int, Coef, Coef}}[], String[], String[], String[]
    for k in ks
        # one term added to every alternative of the row: `false` when the bound cannot see
        # it. A switch `ifelse(cond, a, b)` whose condition reads no unknown field (a gate
        # such as `t ≥ t_relax`) doubles the alternatives: one with the terms of `a`, one with
        # those of `b` (each choice checked on its own: a decaying arm never certifies a
        # rotation in the other)
        function add!(alts, term, class, depth)
            fs = [kk for (kk, v) in dvs if _reads(term, (_opof(v),))]
            if class == :Diffusion
                c = _coef_bound(_diffusion_coefficient(term), cf.params)
                c === nothing && return false
                foreach(r -> push!(r.diffusion, c), alts)
            elseif class == :LinearLocal || class == :CrossLinear
                length(fs) == 1 || return false
                if class == :CrossLinear &&
                   _linclass(unwrap(term), _opof(dvs[fs[1]]), stateops, inputops) == :Diffusion
                    j = findfirst(==(fs[1]), ks)
                    c = j === nothing ? nothing : _coef_bound(_diffusion_coefficient(term), cf.params)
                    c === nothing && return false
                    foreach(r -> push!(r.crossdiffusion, (c, j)), alts)
                else
                    c = _coef_bound(substitute(term, Dict(dvs[fs[1]] => 1); fold = Val(false)), cf.params)
                    c === nothing && return false
                    foreach(r -> push!(class == :CrossLinear ? r.crosslinear : r.linear, c), alts)
                end
            elseif class == :Source
                return true
            else
                u = unwrap(term)
                # the condition reads no unknown (a state or an aux field of the states)
                (depth < 4 && iscall(u) && operation(u) === ifelse && !_reads(arguments(u)[1], unknownops)) || return false
                out = RowTerms[]
                for arm in arguments(u)[2:3]
                    branch = map(copy, alts)
                    # classified as the rate's own terms: a term reading an aux field is Other
                    for (t2, c2) in linearity(arm, _opof(dvs[k]), unknownops; inputs = inputops, aux = auxops)
                        add!(branch, t2, c2, depth + 1) || return false
                    end
                    append!(out, branch)
                end
                length(out) <= _MAXARMS || return false
                empty!(alts); append!(alts, out)
                push!(expanded, "$k: $(term)")
            end
            return true
        end
        alts = [RowTerms()]
        for (term, class) in cf.linearity[k]
            # a term the bound cannot see leaves the alternatives as they were
            trial = map(copy, alts)
            if add!(trial, term, class, 0)
                alts = trial
            else
                push!(unbounded, k); push!(terms, "$k: $(term)")
            end
        end
        push!(rows, alts)
        push!(faces, [(Int(r.axis), r.alpha, r.beta) for r in cf.program.rules
                      if r isa FaceRule && cf.program.fields[r.field].key == k])
    end
    return StabilityBound([1 / h^2 for h in cf.program.spacing], ks, rows, faces,
        sort!(unique!(unbounded)), unique!(terms), unique!(expanded))
end

# initial values of the state fields, flat in `state` order, evaluated at cell centers in
# the state type `T`
function _initial(cf::CompiledField{N}, sys::PDESystem, state, ::Type{T}) where {N, T}
    ends = _domain_ends(sys)
    ivs = unwrap.(sys.ivs)
    h = cf.program.spacing
    dims = Int.(cf.program.hierarchy[1].grid.dims)
    vals = Dict{Any, Any}(p => d for (p, d) in zip(cf.params, cf.defaults) if !isnan(d))
    vals[ivs[1]] = ends[1][1]
    out = T[]
    for k in state
        haskey(cf.initial, k) || _dverr("field `$k` has no initial condition `$k(0, …) ~ value`")
        v = cf.initial[k]
        if v isa Number
            append!(out, fill(T(v), prod(dims)))
            continue
        end
        e = substitute(v, vals; fold = Val(true))
        xs = ivs[2:end]
        free = [u for u in Symbolics.get_variables(e) if !any(x -> isequal(x, u), xs)]
        isempty(free) || _dverr("the initial value of `$k` does not reduce to a number: `$v` reads $(join(free, ", "))")
        f = Symbolics.build_function(e, xs...; expression = Val(false))   # compiled once, not per site
        centers = ntuple(d -> T(ends[d + 1][1]) .+ (T.(1:dims[d]) .- T(1) / 2) .*
                              ((T(ends[d + 1][2]) - T(ends[d + 1][1])) / dims[d]), N)
        append!(out, vec([T(f(Tuple(I)...)) for I in Iterators.product(centers...)]))
    end
    return out
end

function _index(cf::CompiledField, sys::PDESystem, s, state)
    slots = Problems.state_layout(s, [fieldid(s, k) for k in state])
    dims = Int.(cf.program.hierarchy[1].grid.dims)
    vars = Pair[]
    for v in sys.dvs, (op, ks) in cf.keys
        isequal(_opof(v), op) || continue
        for (i, k) in enumerate(ks)
            k in state || continue
            term = length(ks) == 1 ? unwrap(v) : unwrap(Symbolics.wrap(unwrap(v))[i])
            push!(vars, (term, Symbol(k)) => FieldSlot(slots[fieldid(s, k)], dims))
        end
    end
    params = [(p, Symbol(string(p))) => i for (i, p) in enumerate(cf.params)]
    defaults = Dict{Any, Any}(p => d for (p, d) in zip(cf.params, cf.defaults))
    return LatticeIndex(; key = _symkey, variables = vars, parameters = params,
        independent_variables = [unwrap(sys.ivs[1])], defaults)
end

_states(p) = [f.key for f in p.fields if f.role == :state]

"""
    discretize(pdesys, disc::LatticeDiscretization)

The problem of `pdesys` on the lattice (`disc.problem`):
- `:owned`: a `FieldProblem` (the owned fast path), solved with `ExplicitEuler(; dt,
  substeps)` for rate equations or `ExplicitMap()` for maps;
- `:ode`: an `ODEProblem` whose function is the compiled right side (`LatticeRHS`) with the
  symbol table as `sys`, for SciML solvers;
- `:auto`: `:ode` for rate equations, `:owned` when a discrete map is present;
- `:linear`: not in this version (the steady solvers).

The time span is the domain of the first variable. Fields index solutions and integrators
by symbol (`sol[c(t, x, y)]`, `sol[:c]`) as grid-shaped arrays.
"""
function discretize(sys::PDESystem, disc::LatticeDiscretization{N}) where {N}
    kind = disc.problem
    kind == :linear && _dverr("problem = :linear (steady systems) needs the solvers of the next commit (C7b)")
    hasmap = any(eq -> iscall(unwrap(eq.lhs)) && operation(unwrap(eq.lhs)) isa Shift, sys.eqs)
    kind == :auto && (kind = hasmap ? :owned : :ode)
    kind == :ode && hasmap && _dverr("discrete maps have no ODE form; use problem = :owned")
    backend = disc.backend === nothing ? KernelAbstractions.CPU() : disc.backend
    T = _statetype(disc)
    options = CompileOptions(; T)
    tspan = _domain_ends(sys)[1]
    cf = symbolic_discretize(sys, disc; update = kind == :owned ? euler_update : nothing)
    s = cf.program
    state = _states(s)
    init = [k.key for k in s.kernels if startswith(k.key, "mask:")]
    u0 = _initial(cf, sys, state, T)
    index = _index(cf, sys, s, state)
    if kind == :owned
        stab = hasmap ? (p -> NaN) : stability_bound(cf, sys)
        return FieldProblem(s, u0, tspan, cf.defaults; state, kind = hasmap ? :map : :rate,
            init, index, tables = cf.tables, backend, options, stability = stab)
    end
    isempty(init) || _dverr("masked conditions (`c ~ masked(pred, v)`) need problem = :owned in this version")
    rates = Dict(k => "∂$k" for k in state)
    return ode_problem(s, u0, tspan, cf.defaults; state, rates, init, index,
        tables = cf.tables, backend, options)
end
