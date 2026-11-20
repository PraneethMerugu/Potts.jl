# The field report: each field group's policy and a run's counters, read
# from what a problem, an integrator or a solution already holds. Nothing here runs in `step!`.

"""
    field_report([io::IO = stdout], x)
    field_report([io::IO = stdout], prob, alg; dt = nothing)

Print the policy of every field group of `x` and the counters of its run. `x` is a lattice
problem (what `LatticePDE.discretize` returns, or a `FieldProblem`), an owned integrator
(`init(prob, alg)` with a field algorithm), the integrator of a SciML solver (OrdinaryDiffEq's
`init(prob, Tsit5())`), or a solution of either. `field_report(prob, alg)` prints the policy of
`prob`'s groups under the field algorithm `alg` without binding anything, over the window `dt` (as given to `solve`; `nothing`: the clock's
period).

One block per group, about ten lines:

- the fields and the algorithm in its keyword form;
- the window `dt`, the substep count and its cause: the bound (`⌈dt ρ / 1.8⌉` for
  `ExplicitEuler`; the growth and convergence rules for the implicit algorithms), the user
  minimum (`substeps = m`), both, or the least count; for an `ExplicitEuler` group whose bound
  sets more than 20 substeps, the count `BackwardEuler()` takes when it is smaller (`route`);
- the stability bound `ρ` of the group's rows ([`bound_report`](@ref)) and the parts of the
  row that gives it (diffusion, advection, reaction, cross terms), with the terms it cannot see,
  the declared intervals it used ([`declared_intervals`](@ref)) and any part that refuses the
  parameters;
- the number types: the state, the compute type of the kernels ([`compute_type`](@ref)) and, for
  the implicit groups, the solver's;
- for the implicit groups: `linsolve` as resolved and its multigrid levels, the Newton count and
  the rule that set it, and whether the operator `J̃` is exact (the terms it leaves out and their
  bound `ρ_in`);
- the run counters of the group's status word ([`field_stats`](@ref) sums them), the launches
  per substep and the fusion decisions of the step plan
  ([`fusion_report`](@ref LatticeFields.Schedule.fusion_report)).

Then the coupling between groups: for each group in a loop of the group read graph, `κ = dt ·
rate` ([`lagged_coupling`](@ref), [`check_coupling`](@ref)); with a term the bound cannot see,
`κ` covers the cross terms it sees only. A solution's blocks give the policy at the solution's
parameters, the counts its run used and the implicit facts resolved at its bind
(`sol.stats.implicit`, [`implicit_facts`](@ref)). A bound that reads the time is recounted at
every window: the report of an integrator gives the current window's count, the others the
first window's. A SciML solve prints its solver, its statistics (`sol.stats`), its return code,
the right side's builds, the Jacobian keywords, the mass matrix, the built-in callbacks and the
stability bound of the field system.

On a device the report reads the groups' status words first (one copy per group, as
`field_stats` does) and the inputs that the bound reads. It allocates on the host and may
synchronize, so call it outside a timed loop; it changes nothing in the run.
"""
function field_report end
field_report(x) = field_report(stdout, x)
field_report(prob::SciMLBase.AbstractSciMLProblem, alg::AbstractFieldAlgorithm; dt = nothing) =
    field_report(stdout, prob, alg; dt)

# --- text helpers ---
_rtext(x::Real) = isfinite(x) ? string(_num(Float64(x))) : string(x)
_keystext(ks) = join(ks, ", ")
_backendtext(b) = string(nameof(typeof(b)))
_plural(n, w) = string(n, " ", w, n == 1 ? "" : "s")
_line(io, label, text) = println(io, "  ", rpad(label, 11), text)
# an algorithm in the report's headers: `FieldGroups` by field name, a map as its canonical text
_headtext(a) = _algtext(a)
_headtext(m::ExplicitMap) = canonical(m)
_headtext(g::FieldGroups) = string("FieldGroups(", join((string(_symtext(k), " => ", _headtext(a)) for (k, a) in g.pairs), ", "),
    g.default === nothing ? "" : string("; default = ", _headtext(g.default)), ")")
# the clauses of a line that hold something (`"name: a, b"`), joined by `; `
_clauses(ps...) = join((p for p in ps if !isempty(p)), "; ")
_clause(name, xs) = isempty(xs) ? "" : string(name, ": ", join(xs, ", "))

# --- the substep count and its cause (the one policy, `substeps`, worded) ---
"""
    substep_cause(spec, alg, dt, pp; fields = spec.state, stability = spec.stability) -> (; n, cause, text)

The substep count of the group `spec` (its fields `fields`) stepped by `alg` over a window `dt`
at the raw parameters `pp` (with the tables and the bound's inputs), and why: `cause` is
`:bound` (the bound set it: `⌈dt ρ / 1.8⌉`, or an implicit rule), `:user` (the user minimum
`substeps = m`), `:both` (the two agree), `:least` (an implicit group's least count, 1, or 2 for
Crank–Nicolson on data that jump), `:map`, `:steady` (one `QuasiSteady` solve per window),
`:aux` (aux fields only) or `:refused` (`init` refuses the group: an explicit group with no
count whose bound is not finite). `text` words it with the numbers. The same rules as
[`substeps`](@ref), read through [`seen_bound`](@ref), the stability bound and the implicit
rules; it warns nothing and refuses nothing.
"""
function substep_cause(spec::GroupSpec, alg, dt::Real, pp; fields = spec.state, stability = spec.stability)
    dt = Float64(dt)
    alg isa ExplicitMap && return (; n = 1, cause = :map, text = "one map step per window")
    isempty(fields) && return (; n = 0, cause = :aux, text = "aux fields only: one evaluation per window")
    alg isa QuasiSteady && return (; n = 1, cause = :steady, text = "one steady solve per window")
    alg isa ExplicitEuler && return _explicit_cause(spec, alg, dt, pp, stability)
    alg isa AbstractImplicitFieldAlgorithm && return _implicit_cause(spec, alg, dt, pp, fields)
    return (; n = 0, cause = :unknown, text = string("no substep rule for ", _algtext(alg)))
end
function _explicit_cause(spec::GroupSpec, alg::ExplicitEuler, dt::Float64, pp, stability)
    m = alg.substeps
    ρ = Float64(m === nothing ? stability(pp) : seen_bound(stability, pp))
    if !(isfinite(ρ) && ρ >= 0)
        if m === nothing
            why = unbounded_reason(stability, pp)
            return (; n = 0, cause = :refused, text = string("`init` refuses this group: the bound is not finite",
                why === nothing ? "" : string(" (", _termtext(why), ")"), "; give a count, `", spec.texts.route, "`"))
        end
        return (; n = m, cause = :user, text = string("the user minimum `substeps = ", m,
            "` (the bound over the terms it sees is not finite)"))
    end
    b = _bound_count(dt, ρ)
    bt = string("⌈dt ρ / 1.8⌉ = ⌈", _rtext(dt), " × ", _rtext(ρ), " / 1.8⌉ = ", b)
    m === nothing && return (; n = max(1, b), cause = :bound, text = string("the bound, ", bt, b < 1 ? " (at least 1)" : ""))
    n = max(m, b)
    b > m && return (; n, cause = :bound, text = string("the bound, ", bt, ", above the user minimum `substeps = ", m, "`"))
    b < m && return (; n, cause = :user, text = string("the user minimum `substeps = ", m, "` (the bound needs ", bt, ")"))
    return (; n, cause = :both, text = string("both the user minimum `substeps = ", m, "` and the bound, ", bt))
end
function _implicit_cause(spec::GroupSpec, alg::AbstractImplicitFieldAlgorithm, dt::Float64, pp, fields)
    r = _implicit_rules(spec, alg, dt, pp, fields)
    n = max(r.m, r.n1, r.n2)
    rules = string("the growth rule ⌈2γ dt g⌉ = ", r.n1, ", the convergence rule ⌈2γ dt ρ_in / (1 − θ)⌉ = ", r.n2)
    least = alg.substeps === nothing ? string("the least count ", r.m) : string("the user minimum `substeps = ", r.m, "`")
    if max(r.n1, r.n2) > r.m
        return (; n, cause = :bound, text = string(r.n2 >= r.n1 ? "the convergence rule" : "the growth rule", " (", rules,
            "), above ", least))
    end
    cause = if alg.substeps === nothing
        :least
    elseif max(r.n1, r.n2) == r.m
        :both
    else
        :user
    end
    return (; n, cause, text = string(cause == :both ? "both " : "", least, cause == :both ? " and a rule" : "", " (", rules, ")"))
end

# a bound that reads the time, taken over the window `[t0, t0 + dt]` for `f()` and restored after
# (as `_check_span` does); any other bound as it is
function _at_window(f::F, stability, t0, dt::Float64) where {F}
    (t0 === nothing || !reads_time(stability)) && return f()
    w0 = bound_window(stability)
    try
        bound_window!(stability, t0, t0 + dt)
        return f()
    finally
        w0 === nothing || bound_window!(stability, w0[1], w0[2])
    end
end

# --- the stability bound of a group's rows: one line, the clauses that hold something ---
function _bound_line(io, stability, pp)
    r = bound_report(stability, pp)
    ρ = Float64(stability(pp))
    seen = hasproperty(r, :seen) ? Float64(r.seen) : Float64(seen_bound(stability, pp))
    head = isfinite(ρ) ? string("ρ = ", _rtext(ρ), _partstext(r)) : string("ρ not finite; over the terms it sees ", _rtext(seen))
    nf = [string(k, ": ", _termtext(c), " (", w isa Symbol ? w : "not finite at some entries", ")") for (k, c, w) in r.nonfinite]
    # (the warning key only when it says more than the unseen terms)
    key = unbounded_key(stability, pp)
    extra = key === nothing ? String[] : [p for p in split(key, "; ") if !startswith(p, "unseen: ")]
    decl, used = declared_intervals(stability), used_intervals(stability)
    _line(io, "bound", _clauses(head, _clause("unseen", _termtext.(r.terms)), _clause("negative diffusion", r.negative),
        _clause("coupled rows not dominant", r.coupled), _clause("no finite bound", nf),
        _clause("declared", [string(k, " ∈ ", iv, k in used ? " (used)" : "") for (k, iv) in decl]),
        isempty(extra) ? "" : string("warning key \"", join(extra, "; "), "\"")))
    return nothing
end

# an explicit group whose count the bound sets past 20 substeps: the count an
# implicit step takes, when it is smaller (the implicit rules at these parameters). A group the
# implicit rules cannot count (an error building its operator) gets no route line: the report
# never fails for want of it
function _route_line(io, spec, alg, dt::Float64, pp, fields, n)
    (alg isa ExplicitEuler && n > 20) || return nothing
    be = BackwardEuler()
    # _implicit_cause only supports linear or recognized nonlinear forms; unsupported
    # forms fall back to the default route summary instead of crashing the report
    k = try
        _implicit_cause(spec, be, dt, pp, fields).n
    catch e
        isfatal(e) && rethrow()
        return nothing
    end
    k < n && _line(io, "route", string(_algtext(be), " steps this group in ", _plural(k, "substep")))
    return nothing
end

# the parts of the row that gives ρ (`bound_report`'s `worst`, when the bound gives it): the parts
# that are not zero, `(row c: diffusion 400.0, reaction 0.05)`
function _partstext(r)
    w = hasproperty(r, :worst) ? r.worst : nothing
    w === nothing && return ""
    ps = [string(n, " ", _rtext(v)) for (n, v) in (("diffusion", w.diffusion), ("advection", w.advection),
        ("reaction", w.reaction), ("cross terms", w.cross)) if v != 0]
    return isempty(ps) ? "" : string(" (row ", w.key, ": ", join(ps, ", "), ")")
end

# --- the implicit facts of a bound runtime (`ImplicitFacts`: data; the report words them) ---
"""
    implicit_facts(rt::GroupRuntime) -> Union{Nothing, ImplicitFacts}

The resolved implicit facts of a bound group (an implicit algorithm's cache), or `nothing` for
an explicit group: its fields, its solvers (`linsolve` as resolved, the coupled solve's Krylov
solver), their multigrid levels and `solver_type`, the Newton count and what set it, whether the
operator `J̃` is exact and the terms it leaves out with their bound `ρ_in`. `LatticeStats`
keeps them per group when a solution is built (`sol.stats.implicit`); [`field_report`](@ref)
words them.
"""
implicit_facts(rt::GroupRuntime) = rt.alg isa AbstractImplicitFieldAlgorithm ? _implicit_facts(rt.alg, rt.cache, rt.keys) : nothing
function _implicit_facts(alg, c, keys)
    c = _primal_cache(c)
    c isa ImplicitCache || return nothing
    sv = [r.solver for r in c.rows if r.solver !== nothing]
    algs = unique(Any[r.solver !== nothing ? Solvers.public_form(r.solver.alg) : r.lin.alg for r in c.rows if r.solver !== nothing || r.lin !== nothing])
    rows = [r for r in c.op.rows if r.key in c.keys]
    return ImplicitFacts(
        (
            collect(String, keys), algs, c.cs === nothing ? nothing : _krylov(alg.linsolve),
            unique([length(s.prog.hierarchy) for s in sv]), unique(Type[s.T for s in sv]), c.newton, !c.auto,
        c.cs !== nothing, c.cs !== nothing && c.cs.linear, c.exact, c.exact0, c.switch, c.iterate, c.seen, c.cyclic, c.h,
        c.ρin, c.θ, c.smin, unique([t for r in rows for t in r.inexact]), unique([t for r in rows for t in r.unseen])))
end
function _newton_text(alg, f)
    f.given && return string(f.newton, ": given (`nlsolve = ", repr(alg.nlsolve), "`)")
    w = string(f.newton, ", automatic: ")
    if f.coupled
        kind = if f.linear
            "linear: one solve"
        elseif alg isa QuasiSteady
            "nonlinear steady: $QS_NEWTON checked"
        else
            "nonlinear"
        end
        return string(w, "the coupled solve's operator is the whole Jacobian (", kind, ")")
    end
    unseen = isempty(f.unseen) ? "" : string(": ", join(_termtext.(f.unseen), ", "))
    if alg isa QuasiSteady
        f.exact && return string(w, f.switch || f.iterate ? "nonlinear or switched rows ($QS_NEWTON checked)" : "the operator is exact")
        f.seen || return string(w, "ρ_in unknown (no bound sees a term out of the operator", unseen, "): the cap $QS_NEWTON_CAP")
        return string(w, "the contraction ρ_in / s_min + θ of the terms out of the operator, ρ_in = ", _rtext(f.ρin),
            ", s_min = ", _rtext(f.smin), ", θ = ", _rtext(f.θ))
    end
    f.exact && return string(w, f.switch ? "the operator is exact, and a switch takes a flip pass" : "the operator is exact")
    f.seen || return string(w, "ρ_in unknown (no bound sees a term out of the operator", unseen, ")")
    ρc = _gamma_count(alg) * f.h * f.ρin + f.θ
    return string(w, "the contraction γ h ρ_in + θ = ", _rtext(ρc), " of the terms out of the operator (ρ_in = ", _rtext(f.ρin),
        ", h = ", _rtext(f.h), f.θ > 0 ? string(", θ = ", _rtext(f.θ)) : "", ")")
end
function _operator_text(f)
    f.coupled && return "J̃ the whole Jacobian (coupled solve: exact)"
    f.exact && return "J̃ exact"
    terms = String[_termtext(t) for t in f.terms]
    f.cyclic && push!(terms, "the cycle among the group's fields")
    f.exact0 && push!(terms, "a Robin face or a diffusion multiplier whose sign is negative at these parameters")
    ρ = if f.seen
        string("ρ_in = ", _rtext(f.ρin))
    else
        string("ρ_in unknown (no bound sees ", isempty(f.unseen) ? "a term out of the operator" : join(_termtext.(f.unseen), ", "), ")")
    end
    return string("J̃ inexact: ", isempty(terms) ? "terms out of the operator" : join(terms, ", "), "; ", ρ,
        ", corrected by the Newton iterations")
end
function _fact_lines(io, alg, f)
    auto = alg.linsolve === :auto ? " (`linsolve = :auto`)" : ""
    inner = if f.coupled
        precs = isempty(f.linsolve) ? "" : string(", each field preconditioned by ", join(repr.(f.linsolve), ", "))
        string("coupled solve ", repr(f.krylov), precs)
    elseif isempty(f.linsolve)
        "none: every row is local (solved site by site)"
    else
        join(repr.(f.linsolve), ", ")
    end
    _line(io, "linsolve", string(inner, auto, isempty(f.levels) ? "" : string(", multigrid levels ", join(f.levels, ", "))))
    _line(io, "newton", _newton_text(alg, f))
    _line(io, "operator", _operator_text(f))
    return nothing
end
function _solvertext(alg, f)
    if f === nothing || isempty(f.solver_type)
        return string("solver ", canonical(alg.solver_type), " (set when bound)")
    else
        return string("solver ", join(f.solver_type, ", "), alg.solver_type === :auto ? " (`solver_type = :auto`)" : "")
    end
end
# … and an implicit group with no bound runtime (`field_report(prob, alg)`): as given
function _given_lines(io, spec::GroupSpec, g::FieldGroup, alg::AbstractImplicitFieldAlgorithm, keys)
    op = _operator(spec, alg)
    coupled = coupled_solve(alg, op, group_program(g, alg), keys)
    rows = [r for r in op.rows if r.key in keys]
    inner = if coupled
        string("coupled solve ", repr(_krylov(alg.linsolve)))
    elseif all(r -> r.local_only, rows)
        "none: every row is local (solved site by site)"
    elseif alg.linsolve === :auto
        string(repr(Solvers.LatticePCG()), " (`linsolve = :auto`)")
    else
        repr(alg.linsolve)
    end
    _line(io, "linsolve", inner)
    _line(io, "newton", alg.nlsolve === nothing ? "automatic (set when the group is bound)" : string(alg.nlsolve.max_iter, ": given (`nlsolve = ", repr(alg.nlsolve), "`)"))
    return nothing
end

function _fusion_lines(io, sp)
    sp isa StepPlan || return nothing
    if isempty(sp.decisions)
        return _line(io, "launches", string(length(sp.launches), " per substep; no fusion decision (one kernel)"))
    end
    _line(io, "launches", string(length(sp.launches), " per substep"))
    for (i, l) in enumerate(split(chomp(sprint(fusion_report, sp)), '\n'))
        _line(io, i == 1 ? "fusion" : "", l)
    end
    return nothing
end

_runtext(t::StatusTotals, status) = _clauses(_plural(t.windows, "window"), t.solves > 0 ? _plural(t.solves, "solve") : "",
    t.budget > 0 ? string(t.budget, " linear budget hits") : "", t.floor > 0 ? string(t.floor, " floors") : "",
    t.newton_budget > 0 ? string(t.newton_budget, " Newton budget hits") : "", string("status ", status))

"""
    group_report(io, rt::GroupRuntime, pp; title = "group", dt = rt.dt, spec, stability = rt.stability, E)

The block of one bound field group (a [`GroupRuntime`](@ref)) in [`field_report`](@ref): its
policy at the raw parameters `pp` (with the tables and the bound's inputs, as the policy reads
them; `spec` the group's [`GroupSpec`](@ref), `dt` the window the policy counts), its resolved
implicit facts, its run counters and its fusion decisions. `E` is the state's element type
(by default the runtime's compute zero's type, else its first field's buffer's). Each front
end calls it per group.
"""
function group_report(io::IO, rt::GroupRuntime, pp; title = "group", dt::Real = rt.dt, spec::GroupSpec,
        stability = rt.stability, E::Type = _state_type(rt))
    alg = rt.alg
    f = alg isa AbstractImplicitFieldAlgorithm ? _implicit_facts(alg, rt.cache, rt.keys) : nothing
    _policy_lines(io, title, spec, alg, Float64(dt), rt.n, pp, rt.keys, stability, E, f; current = true)
    f === nothing || _fact_lines(io, alg, f)
    _line(io, "run", _runtext(rt.totals, rt.status))
    _fusion_lines(io, rt.step)
    return nothing
end

function _state_type(rt::GroupRuntime)
    if rt.c !== nothing
        return typeof(rt.c)
    elseif isempty(rt.keys)
        return Float64
    else
        return eltype(rt.store.bufs[fieldid(rt.program, rt.keys[1])][1])
    end
end
# the policy lines of a group (bound or not): the header, window, count and cause, bound,
# numbers. `n` the count the run used (`nothing`: the policy's); `t0` the start of the first
# window, over which a bound that reads the time is counted (`current`: the bound's own window,
# a bound runtime's current one)
function _policy_lines(io, title, spec, alg, dt::Float64, n, pp, fields, stability, ::Type{E}, f = nothing; t0 = nothing,
        current::Bool = false) where {E}
    println(io, title, ": ", _keystext(fields), " (", _headtext(alg), ")")
    timed = !(alg isa ExplicitMap) && reads_time(stability)
    _at_window(stability, current ? nothing : t0, dt) do
        c = substep_cause(spec, alg, dt, pp; fields, stability)
        n = something(n, c.n)
        win = if timed
            (w = bound_window(stability); if w === nothing
                ""
            else
                string("; the bound reads the time: each window is recounted, this count is ",
                    current ? "the current" : "the first", " window's, [", _rtext(w[1]), ", ", _rtext(w[2]), "]")
            end)
        else
            ""
        end
        if c.cause in (:map, :steady, :aux)
            _line(io, "window", string("dt = ", _rtext(dt), ", ", c.text))
        elseif c.cause == :refused
            _line(io, "window", string("dt = ", _rtext(dt), ", no count"))
            _line(io, "substeps", string(c.text, " [refused]"))
        else
            # (a bound that reads the time, not a runtime: the window line gives the first window's
            # count, which its text names; the substeps line gives the run's last)
            nw = timed && !current ? c.n : n
            _line(io, "window", string("dt = ", _rtext(dt), ", ", _plural(nw, "substep"), nw > 0 ? string(" (h = ", _rtext(dt / nw), ")") : "",
                win))
            pre = if c.n == n
                ""
            elseif current
                string("now ", n, "; the policy at these parameters gives ", c.n, ": ")
            else
                string("the run's last window took ", n, "; ", c.n, " by ")
            end
            _line(io, "substeps", string(pre, c.text, " [", c.cause, "]"))
            c.cause in (:bound, :both) && _route_line(io, spec, alg, dt, pp, fields, n)
        end
        alg isa Union{ExplicitMap, QuasiSteady} || _bound_line(io, stability, pp)
        return nothing
    end
    V = value_type(E)
    _line(io, "numbers", _clauses(string("state ", _typetext(E), ", compute ", compute_type(alg, V),
                hasproperty(alg, :compute_type) && alg.compute_type !== :auto ? " (`compute_type`)" : "",
                alg isa AbstractImplicitFieldAlgorithm ? string(", ", _solvertext(alg, f)) : ""
            )
        )
    )
    starts_steady(alg) && _line(io, "steady", "steady start (`init = :steady`): solved once by QuasiSteady before the first window")
    return nothing
end

"""
    group_report(io, g::FieldGroup, alg, pp; title = "group", dt, n = nothing, facts = nothing, fields = g.spec.state,
                 stability = g.spec.stability, E = Float64, t0 = nothing)

The block of a field group that no runtime holds (a problem's group, or the group of a
finished run) in [`field_report`](@ref): its policy under `alg` over the window `dt` at the
raw parameters `pp` (with the tables and the bound's inputs), counted over the first window
from `t0` when the bound reads the time; `n` is the count the run used (`nothing`: the
policy's). For an implicit algorithm, the facts resolved when the group was bound (`facts`,
an [`ImplicitFacts`](@ref)), or else `linsolve` and the Newton count as given. `fields` are the
group's state keys and `E` the state's element type. Each front end calls it per group.
"""
function group_report(io::IO, g::FieldGroup, alg, pp; title = "group", dt::Real, n = nothing, facts = nothing,
        fields = g.spec.state, stability = g.spec.stability, E::Type = Float64, t0 = nothing)
    _policy_lines(io, title, g.spec, alg, Float64(dt), n, pp, fields, stability, E, facts; t0)
    if facts !== nothing
        _fact_lines(io, alg, facts)                 # (resolved when the run's group was bound)
    elseif alg isa AbstractImplicitFieldAlgorithm
        _given_lines(io, g.spec, g, alg, fields)
    end
    return nothing
end

"""
    coupling_report(io, stability, keys, algs, pp, dt)

The coupling lines of [`field_report`](@ref) for field groups with state keys `keys` (one
vector per group) stepped by `algs` over the window `dt`: for each group in a loop of the group
read graph, the coupling rule's `κ = dt · rate` ([`lagged_coupling`](@ref),
[`check_coupling`](@ref)) of the whole system's bound `stability` at its raw parameters `pp`.
Nothing for one group.
"""
coupling_report(io::IO, stability, keys::Vector{Vector{String}}, algs, pp, dt::Real) =
    _coupling_lines(io, stability, keys, algs, pp, Float64(dt))

# the coupling rule's κ per group in a loop of the group read graph (`check_coupling`)
function _coupling_lines(io, stability, keys::Vector{Vector{String}}, algs, pp, dt::Float64)
    length(keys) > 1 || return nothing
    parts = lagged_coupling(stability, keys, pp)
    parts === nothing && return println(io, "coupling: the bound does not know the cross terms between the groups")
    loops = group_loops(parts)
    if all(isempty, loops)
        return println(io, "coupling: no loop between the groups (each reads the others' arrays one way, held over its window)")
    end
    steady = [a isa QuasiSteady for a in algs]
    within = lagged_coupling(stability, keys, pp; within = loops)
    sr = if any(g -> !isempty(loops[g]) && any(h -> steady[h], loops[g]), eachindex(keys))
        steady_loop_rates(stability, keys, pp, steady, loops)
    else
        nothing
    end
    println(io, "coupling:")
    for g in eachindex(keys)
        isempty(loops[g]) && continue
        qs = any(h -> steady[h], loops[g])
        q = if qs
            sr === nothing ? nothing : sr[g]
        else
            within[g]
        end
        if q === nothing
            println(io, "  group ", g, ": loop ", loops[g], " with a QuasiSteady group: the rule has no bound for its gain")
        elseif steady[g]
            println(io, "  group ", g, ": QuasiSteady, in loop ", loops[g], " (checked through the groups that read it)")
        else
            κ = dt * q.rate
            # (a term the bound cannot see that reads another field: κ covers the cross terms it sees
            # only; the words of the coupling rule's warning)
            ul = !qs && any(h -> within[h].unseen, loops[g]) ? unseen_loop(stability, pp, keys, within, loops[g]) : nothing
            unseen = ul !== nothing && ul.kind !== :none
            side = if !isfinite(κ)
                ""
            elseif κ <= 1 + _COUPLING_RTOL
                " (≤ 1)"
            else
                " (> 1)"
            end
            println(io, "  group ", g, ": loop ", loops[g], ", κ = dt · rate = ", _rtext(dt), " × ", _rtext(q.rate), " = ",
                _rtext(κ), side,
                q.row === nothing || q.row == "" ? "" : string("; worst row ", q.row, " reads ", q.other, " through ", q.text),
                unseen ? string("; ", cover_text(ul.terms)) : "")
        end
    end
    return nothing
end

# --- the field system of a problem ---
function _problem_lines(io, fp::FieldProblem)
    s = fp.program
    E = eltype(fp)
    dims(lv) = join(Int.(leveldims(s, lv)), "×")
    own = [string(k, " ", dims(s.fields[fieldid(s, k)].levels[1]), " (coarse)") for k in fp.state if s.fields[fieldid(s, k)].levels[1] != 0]
    println(io, "  problem    ", _clauses(string(fp.kind == :map ? "maps" : "rates", ", ", _plural(length(fp.state), "state field"),
            " (", _keystext(fp.state), ")"), string("grid ", dims(0), _ishex(s) ? " (hexagonal)" : ""), _clause("own grids", own),
        string("backend ", _backendtext(fp.backend))))
    store = unique([npartials(E) > 0 ? E : juliatype(s.fields[fieldid(s, k)].storage) for k in fp.state])
    st = store == [E] ? "" : string(", storage ", join(store, ", "))
    println(io, "  types      state ", _typetext(E), npartials(E) > 0 ? string(" (", E, ")") : "", ", parameters ",
        isempty(fp.p) ? "none" : eltype(fp.p), st)
    rows = _clauses(_clause("steady (0 ~ rhs)", fp.group.spec.steady), _has_masks(fp) ? "masked" : "",
        fp.group.spec.clock === nothing ? "" : string("clock ", _rtext(fp.group.spec.clock)), _clause("aux", _aux_keys(s)),
        _clause("inputs", [k for (k, _) in fp.inputs]))
    isempty(rows) || _line(io, "rows", rows)
    return nothing
end
_raw_params(fp::FieldProblem) = with_tables(map(primal, fp.p), fp.tables; inputs = _bound_inputs(fp))

const _NO_ALG = "  algorithm  none yet: `field_report(prob, alg)` gives the policy under `alg`"
"""
    field_report(io, prob)

The field system of a problem, its stability bound at the problem's parameters and, for a
SciML problem, its function's Jacobian keywords, mass matrix and built-in callbacks. A problem
holds no algorithm: `field_report(prob, alg)` prints the group policy under `alg`.
"""
function field_report(io::IO, fp::FieldProblem)
    println(io, "Field report: problem (owned FieldProblem)")
    _problem_lines(io, fp)
    _system_bound(io, fp)
    println(io, _NO_ALG)
    return nothing
end
function _system_bound(io, fp::FieldProblem)
    fp.kind == :map && return nothing
    _at_window(fp.stability, fp.tspan[1], 0.0) do
        _bound_line(io, fp.stability, _raw_params(fp))
    end
    return nothing
end
function field_report(io::IO, prob::SciMLBase.AbstractSciMLProblem)
    m = lattice_metadata(prob)
    m === nothing && throw(ArgumentError("field_report: this problem was not built by `LatticePDE.discretize` (it has no field groups)"))
    println(io, "Field report: problem (", nameof(typeof(prob)), ", family ", m.family, ")")
    fp = field_problem(prob)
    _problem_lines(io, fp)
    _function_lines(io, prob, m)
    _system_bound(io, fp)
    println(io, _NO_ALG)
    return nothing
end

"""
    field_report(io, prob, alg)

The policy of each field group of `prob` under the field algorithm `alg`, at the problem's
parameters, without binding anything (no store, no plan, no solver): per group the algorithm,
the window, the substep count and its cause (a bound that reads the time over the first
window), the bound, the number types, and for the implicit groups `linsolve` and the Newton count
as given (an `:auto` or automatic one is resolved when a group is bound); then the coupling
rule's κ. The policy's refusals hold (a window that does not divide the clock, an algorithm of
the wrong family); an explicit group that `init` would refuse says so. No warning is given.
"""
function field_report(io::IO, prob::SciMLBase.AbstractSciMLProblem, alg::AbstractFieldAlgorithm; dt = nothing)
    fp = prob isa FieldProblem ? prob : field_problem(prob)
    println(io, "Field report: problem under ", _headtext(alg), " (the policy at the problem's parameters; nothing bound)")
    _problem_lines(io, fp)
    for (a, _) in _groups(fp, alg)
        if alg_family(a) != fp.kind
            route = fp.kind == :map ? "map program is stepped by ExplicitMap()" : "rate program is stepped by a rate algorithm"
            throw(ArgumentError(string("field_report: a ", route, "; got ", _algtext(a))))
        end
    end
    _groups_lines(io, fp, alg, nothing; dt)
    return nothing
end

# the SciML function's keywords of a lattice problem: the Jacobian, the mass matrix, the
# built-in callbacks, the right side's builds
function _function_lines(io, prob, m::LatticeMetadata)
    f = hasproperty(prob, :f) ? prob.f : nothing
    prop(x, k) = x !== nothing && hasproperty(x, k) ? getproperty(x, k) : nothing
    jac, jp, cv, jvp, mm = prop(f, :jac), prop(f, :jac_prototype), prop(f, :colorvec), prop(f, :jvp), prop(f, :mass_matrix)
    # (a function by its name: an operator prototype sets `jac` to its `update_coefficients!`)
    tname(x) = x isa Function && !(x isa Union{LatticeJVP, LatticeJacobian}) ? string(nameof(x)) : string(nameof(typeof(x)))
    mmt = if mm === nothing || mm === LinearAlgebra.I
        "I"
    elseif mm isa LinearAlgebra.Diagonal
        string("Diagonal (", count(iszero, Array(mm.diag)), " steady slots)")
    else
        tname(mm)
    end
    _line(io, "function", _clauses(string("right side built ", _plural(m.builds[], "time")),
        jac === nothing ? "" : string("jac ", tname(jac)),
        jp === nothing ? "" : string("jac_prototype ", tname(jp), cv === nothing ? "" : string(" (", maximum(cv; init = 0), " colors)")),
        jvp === nothing ? "" : string("jvp ", tname(jvp)), string("mass matrix ", mmt)))
    # (the family's built-ins: a problem with no time has none)
    names = if m.problem.group.spec.timefree || m.family == :map
        String[]
    else
        [string(nameof(typeof(c))) for c in _builtin_specs(m.problem)]
    end
    isempty(names) || _line(io, "callbacks", string("built-in: ", _keystext(names)))
    return nothing
end

# --- integrators ---
_raw_params(integ::FieldIntegrator) = with_tables(map(primal, integ.pgood), integ.tables; inputs = _bound_inputs(integ))
_namedcounts(keys, counts) = join((string(_keystext(k), " ", n) for (k, n) in zip(keys, counts)), ", ")
_countertext(f) = _clauses(f.solves > 0 ? _plural(f.solves, "solve") : "", f.budget > 0 ? string(f.budget, " linear budget hits") : "",
    f.floor > 0 ? string(f.floor, " floors") : "", f.newton_budget > 0 ? string(f.newton_budget, " Newton budget hits") : "")
function field_report(io::IO, integ::FieldIntegrator)
    prob = integ.prob
    f = field_stats(integ)                          # (a device reads the status words first)
    rts = integ.runtimes
    println(io, "Field report: owned integrator, ", _headtext(integ.alg))
    _line(io, "time", string("t = ", _rtext(_time(integ)), " of ", prob.tspan, ", ", _plural(integ.windows, "window"), " of dt = ",
        _rtext(integ.dt), ", retcode ", integ.retcode))
    _line(io, "counters", _clauses(string("substep counts ", _namedcounts([rt.keys for rt in rts], substep_counts(integ))),
        _countertext(f), integ.syncs > 0 ? string(integ.syncs, " host syncs") : ""))
    _problem_lines(io, prob)
    pp = _raw_params(integ)
    one = length(rts) == 1
    for (i, rt) in enumerate(rts)
        group_report(
            io, rt, pp; title = string("group ", i, " of ", length(rts)), dt = _iwindow(integ),
            spec = prob.group.spec, stability = one ? prob.stability : rt.stability)
    end
    for rt in integ.starts
        group_report(io, rt, pp; title = "steady start", dt = rt.dt, spec = prob.group.spec)
    end
    prob.kind == :map || _coupling_lines(io, prob.stability, [rt.keys for rt in rts], [rt.alg for rt in rts], pp, Float64(integ.dt))
    return nothing
end

# the integrator of a SciML solver on a lattice problem (OrdinaryDiffEq's `ODEIntegrator`)
function field_report(io::IO, integ::SciMLBase.DEIntegrator)
    sol = integ.sol
    prob = sol.prob
    m = lattice_metadata(prob)
    m === nothing && throw(ArgumentError("field_report: this integrator's problem was not built by `LatticePDE.discretize`"))
    println(io, "Field report: SciML integrator, ", nameof(typeof(integ.alg)))
    _line(io, "time", string("t = ", _rtext(integ.t), " of ", prob.tspan, ", dt = ", _rtext(integ.dt), ", retcode ", sol.retcode))
    hasproperty(integ, :stats) && _stats_lines(io, integ.stats, prob)
    _sciml_tail(io, prob, m)
    return nothing
end

# --- solutions ---
function field_report(io::IO, sol::SciMLBase.AbstractODESolution)
    prob = sol.prob
    m = lattice_metadata(prob)
    m === nothing && throw(ArgumentError("field_report: this solution's problem was not built by `LatticePDE.discretize`"))
    sol.stats isa LatticeStats && return _owned_solution(io, sol, m)
    println(io, "Field report: SciML solve, ", nameof(typeof(sol.alg)), ", retcode ", sol.retcode)
    _line(io, "saves", string(length(sol.t), " over ", prob.tspan))
    sol.stats === nothing || _stats_lines(io, sol.stats, prob)
    _sciml_tail(io, prob, m)
    return nothing
end
function _stats_lines(io, st, prob)
    fs = fieldnames(typeof(st))
    _line(io, "stats", join((string(k, " ", getfield(st, k)) for k in fs if !iszero(getfield(st, k))), ", "))
    if :naccept in fs && getfield(st, :naccept) > 0 && hasproperty(prob, :tspan)
        _line(io, "steps", string(getfield(st, :naccept), " accepted", :nreject in fs ? string(", ", getfield(st, :nreject), " rejected") : "",
            "; mean dt ", _rtext((prob.tspan[2] - prob.tspan[1]) / getfield(st, :naccept))))
    end
    return nothing
end
function _sciml_tail(io, prob, m::LatticeMetadata)
    fp = field_problem(prob)
    _problem_lines(io, fp)
    _function_lines(io, prob, m)
    _system_bound(io, fp)
    return nothing
end
function _owned_solution(io, sol, m::LatticeMetadata)
    st = sol.stats::LatticeStats
    fp = field_problem(sol.prob)
    println(io, "Field report: owned solve, ", _headtext(sol.alg), ", retcode ", sol.retcode)
    _line(io, "saves", _clauses(string(length(sol.t), " over ", fp.tspan), _plural(st.nf, "window"),
        st.syncs > 0 ? string(st.syncs, " host syncs") : ""))
    _line(io, "counters", _clauses(string("substep counts ", _namedcounts([ks for (_, ks) in _groups(fp, sol.alg)], st.counts)),
        _countertext(st)))
    _problem_lines(io, fp)
    _groups_lines(io, fp, sol.alg, st.counts; facts = st.implicit, dt = st.dt)
    return nothing
end
function field_report(io::IO, sol::FieldSolution)
    fp = sol.prob
    println(io, "Field report: owned solve of a FieldProblem, retcode ", sol.retcode)
    _line(io, "saves", string(length(sol.t), " over ", fp.tspan))
    _line(io, "counters", _clauses(string("substep counts ", sol.counts), _countertext(sol.stats)))
    _problem_lines(io, fp)
    _system_bound(io, fp)
    return nothing
end
# group `i`'s substep count in a report: `nothing` before a run, 0 for a group without one
function _group_count(counts, i)
    counts === nothing && return nothing
    return i <= length(counts) ? counts[i] : 0
end
# the groups of a solution or of a problem under an algorithm: the policy at its parameters
# (a bound that reads the time over the first window), the counts its run used (`counts`, or
# `nothing`: the policy's) and the facts resolved at its bind (`facts`, or `nothing`: as given)
function _groups_lines(io, fp::FieldProblem, alg, counts; facts = nothing, dt = nothing)
    groups = _groups(fp, alg)
    pp = _raw_params(fp)
    clock = _clock(fp)
    one = length(groups) == 1
    E = eltype(fp)
    for (i, (a, ks)) in enumerate(groups)
        stab = one ? fp.stability : restrict_bound(fp.stability, ks)
        w = _window(a, dt, clock)
        f = facts === nothing || i > length(facts) ? nothing : facts[i]
        group_report(
            io, fp.group, a, pp; title = string("group ", i, " of ", length(groups)), dt = w,
            n = _group_count(counts, i), facts = f, fields = ks, stability = stab, E,
            t0 = fp.tspan[1])
    end
    fp.kind == :map || _coupling_lines(io, fp.stability, [collect(String, ks) for (_, ks) in groups], [a for (a, _) in groups], pp,
        _window(first(groups[1]), dt, clock)
    )
    return nothing
end
