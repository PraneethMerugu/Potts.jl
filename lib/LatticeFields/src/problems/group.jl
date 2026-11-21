# The shared group layer. A field group is described once, by its
# `GroupSpec` (the IR boundary: plain data and compiled functions, no Symbolics), made
# numerical by a `FieldGroup` (its semantic program and its plans, by update and value
# type), and stepped by a `GroupRuntime` bound to a store's arrays (`bind_group`,
# `advance!`). Coupled `PottsProblem`s and standalone `FieldProblem`s both step through it
# (`CorePotts.FieldPhase` and `FieldProblem`).

"""
    ParamSlot(name; text = name, default = nothing, role = :base, derivation = nothing)

A parameter slot of a group: its `name` (the slot's key), the parameter as
the user wrote it (`text`), its default as given (any `Real`, or `nothing` when the front
end binds the values itself), its `role` (`:base`, `:computed`, or `:clock` for
[`CLOCK_KEY`](@ref)) and, for `:computed`, its `derivation`: the expression of the base
parameters as written (the compiled derivation of a problem's computed slots is its index's,
`LatticeIndex.derive`). `string(slot)` is its name.
"""
struct ParamSlot
    name::String
    text::String
    default::Any
    role::Symbol
    derivation::Any
end
function ParamSlot(
        name::AbstractString; text = name, default = nothing, role::Symbol = if name ==
                CLOCK_KEY
            :clock
        else
            :base
        end,
        derivation = nothing
    )
    role in (:base, :computed, :clock) ||
        throw(ArgumentError("a parameter slot's role must be :base, :computed or :clock; \
            got $(repr(role))"))
    return ParamSlot(String(name), String(text), default, role, derivation)
end
ParamSlot(s::ParamSlot) = s
Base.string(s::ParamSlot) = s.name
Base.show(io::IO, s::ParamSlot) = print(io, s.name)

"""
    TableSpec(key; name = key, values = nothing)

A table of a group: its `key`, its user `name` and its values as given (the
element type kept), or `nothing` when the front end binds them itself. `string(t)` is its
key.
"""
struct TableSpec
    key::String
    name::String
    values::Any
end
function TableSpec(key::AbstractString; name = key, values = nothing)
    return TableSpec(String(key), String(name), values)
end
TableSpec(t::TableSpec) = t
Base.string(t::TableSpec) = t.key
Base.show(io::IO, t::TableSpec) = print(io, t.key)

"""
    InputSpec(key; name = key, eltype = Real, bounds = (-Inf, Inf), default = nothing,
        filled = false)

An input field of a group: its `key`, its user `name`, its element type
(`Bool`, `Int32` or a real type), its declared `bounds`, its `default` (or `nothing`) and
whether it is `filled`: a caller writes it on the device at every step (coupled
`PottsProblem`'s CPM reads), so no host check of its values runs between steps and an
implicit algorithm treats it as moving data. The fields of other groups (`spec.external`)
are inputs too, not filled. `string(i)` is its key.
"""
struct InputSpec
    key::String
    name::String
    eltype::Type
    bounds::Tuple{Float64, Float64}
    default::Any
    filled::Bool
end
function InputSpec(
        key::AbstractString; name = key, eltype::Type = Real, bounds = (-Inf, Inf),
        default = nothing,
        filled::Bool = false
    )
    return InputSpec(
        String(key), String(name), eltype,
        (Float64(bounds[1]), Float64(bounds[2])), default, filled
    )
end
InputSpec(i::InputSpec) = i
Base.string(i::InputSpec) = i.key
Base.show(io::IO, i::InputSpec) = print(io, i.key)

"""
    GroupSpec

The description of one field group, shared by coupled and standalone routes:

- `rate`: the group's rate program before the semantic passes (`rate:c` kernels store the
  rate in a scratch field `∂c`; `map:`, `aux:` and `mask:` kernels as written): a
  [`FieldGroup`](@ref) fuses each algorithm's update into it
  ([`fuse_update`](@ref LatticeFields.Compile.fuse_update));
- `state`: the keys of the group's state fields, in the PDESystem's dvs order;
- `external`: the fields of other groups the group reads (from their arrays);
- `params`, `tables`, `inputs`: the parameter slots ([`ParamSlot`](@ref)), the tables
  ([`TableSpec`](@ref)) and the inputs ([`InputSpec`](@ref)) of the program, in its order
  (`string(slot)` is the slot's name, so `string.(spec.params)` are the names of the slots);
- `init`: the kernels that run at a step's start (the masks of masked conditions);
- `kind`: `:rate` or `:map`;
- `clock`: the period of the discretization's clock, or `nothing`;
- `stability`: the front end's stability bound (a function of the raw parameters);
- `texts`: `route`, how to give a count in this front end, and `terms`, the terms the bound
  does not see in the user's words;
- `linearity`: the front end's linearity classes, carried for operator extraction;
- `operator`: the front end's builder of the group's [`OperatorSpec`](@ref) for the implicit
  algorithms (`operator_spec(spec)` builds it once, at the first implicit use; `nothing`:
  the front end extracts no operator, and an implicit algorithm is refused);
- `steady`: the state fields written as steady rows `0 ~ rhs` (their rate rows hold `rhs`):
  their groups take [`QuasiSteady`](@ref) only;
- `timefree`: the system has no time (every row steady): a problem of it is solved once.
"""
struct GroupSpec{N}
    rate::Program{N}
    state::Vector{String}
    external::Vector{String}
    params::Vector{ParamSlot}
    tables::Vector{TableSpec}
    inputs::Vector{InputSpec}
    init::Vector{String}
    kind::Symbol
    clock::Union{Nothing, Float64}
    stability::Any
    texts::@NamedTuple{route::String, terms::Vector{String}}
    linearity::Any
    operator::Any
    steady::Vector{String}
    timefree::Bool
end
function GroupSpec(
        rate::Program{N}; state, external = String[], params = String[], tables = String[],
        inputs = String[], init = String[], kind::Symbol, clock = nothing,
        stability = p -> NaN,
        route = "ExplicitEuler(; substeps = n)", terms = String[], linearity = nothing,
        operator = nothing,
        steady = String[], timefree::Bool = false
    ) where {N}
    kind in (:rate, :map) ||
        throw(ArgumentError("kind must be :rate or :map; got $(repr(kind))"))
    return GroupSpec{N}(
        rate, collect(String, state), collect(String, external),
        ParamSlot[ParamSlot(q) for q in params],
        TableSpec[TableSpec(q) for q in tables], InputSpec[InputSpec(q) for q in inputs],
        collect(String, init), kind,
        clock === nothing ? nothing : Float64(clock), stability, (;
            route = String(route), terms = collect(String, terms),
        ),
        linearity, operator, collect(String, steady), timefree
    )
end

"""
    FieldGroup(spec; alg)

The numerical group of `spec`: for each algorithm, the semantic program of its update fused
into `spec.rate` ([`group_program`](@ref): `fuse_update(spec.rate, update_rule(alg))`, an IR
pass with no symbolic step, made once per [`update_key`](@ref)), and its plans, planned and
emitted once per `(update_key(alg), value type, kernels)` and shared by every problem and
runtime made from it (the plans of `ExplicitEuler()` at `dt = 0.1` and at `dt = 0.2`
are one). `program` is the program of `alg` (the default algorithm of the group's kind:
`ExplicitEuler()` for rates, `ExplicitMap()` for maps); every algorithm's program has the
same fields, kernels and rules, so one store serves them all.
"""
struct FieldGroup{N}
    spec::GroupSpec{N}
    program::Program{N}
    programs::Dict{Any, Program{N}}
    plans::Dict{
        Tuple{Any, Type, Type, Vector{Int}, Vector{Int}}, Tuple{StepPlan{N}, StepPlan{N}},
    }
end
function FieldGroup(
        spec::GroupSpec{N}; alg = spec.kind == :map ? ExplicitMap() : ExplicitEuler(),
        program::Program{N} = semantic(fuse_update(spec.rate, update_rule(alg)))
    ) where {N}
    s = program
    return FieldGroup{N}(
        spec, s, Dict{Any, Program{N}}(update_key(alg) => s),
        Dict{
            Tuple{Any, Type, Type, Vector{Int}, Vector{Int}}, Tuple{
                StepPlan{N}, StepPlan{N},
            },
        }()
    )
end

"""
    CLOCK_KEY

The name of the clock's parameter slot, `"clock__tick"`: a group whose
kernels read the clock's step index (`mcs` in a coupled `PottsProblem`,
`LatticePDE.step_index(t)` in a standalone `FieldProblem`) has this slot among its
parameters, and its launches write the step index into it at every launch. The `__tick`
suffix is reserved, so no user parameter takes the name.
"""
const CLOCK_KEY = "clock__tick"

"""
    clock_slot(spec) -> Int

The parameter slot of the clock in group `spec` ([`CLOCK_KEY`](@ref)), or 0 when its kernels
do not read the step index.
"""
clock_slot(spec::GroupSpec) = something(findfirst(q -> q.name == CLOCK_KEY, spec.params), 0)

"""
    group_program(g, alg) -> Program

The semantic program of group `g` stepped by `alg`: its update fused into the rate program,
once per `update_key(alg)` (thread-safe).
"""
function group_program(g::FieldGroup, alg)
    return lock(
        () -> get!(
            () -> semantic(fuse_update(g.spec.rate, update_rule(alg))), g.programs,
            update_key(alg)
        ),
        _PLANS_LOCK
    )
end

# the kernels of the group fields `ids` (field ids of state fields), `(init, step)`: the
# step kernels that write one of them, and those that write no state field (auxiliary
# values, read by every group: each group computes them from the current values); the masks
# of the group's own masked conditions (`NodeValueRule`s); every kernel when `ids` holds
# every state field
function _group_kernels(g::FieldGroup, ids)
    s = g.program
    keys = [k.key for k in s.kernels]
    initids = [i for (i, k) in enumerate(keys) if k in g.spec.init]
    stepids = [i for (i, k) in enumerate(keys) if !(k in g.spec.init)]
    stateids = Set(fieldid(s, k) for k in g.spec.state)
    issubset(stateids, ids) && return initids, stepids
    maskfields = Set(
        s.masks[r.mask].field
            for r in s.rules if r isa NodeValueRule && r.field in ids
    )
    # (and the domain folded onto a coarse field's level)
    union!(
        maskfields,
        (
            s.masks[r.mask].field
                for r in s.rules if r isa DomainEdgeRule && r.mask != 0 && r.field in ids
        )
    )
    return [i for i in initids if any(f -> f in maskfields, writes(s.kernels[i]))],
        [
            i
            for i in stepids
            if (
                w = writes(s.kernels[i]);
                any(f -> f in ids, w) || !any(f -> f in stateids, w)
            )
        ]
end

"""
    group_plans(g, alg, V, backend, options; kernels) -> (init plan, step plan)

The plans of group `g` for algorithm `alg` at value type `V` (once per update, value type
and kernel set; thread-safe).
"""
function group_plans(
        g::FieldGroup, alg, ::Type{V}, backend, o::CompileOptions;
        kernels = _group_kernels(g, Set(fieldid(g.program, k) for k in g.spec.state))
    ) where {V}
    s = group_program(g, alg)
    initids, stepids = kernels
    return lock(_PLANS_LOCK) do
        get!(g.plans, (update_key(alg), V, compute_type(alg, V), initids, stepids)) do
            opts = _options(
                o, V, backend; clock = clock_slot(g.spec), C = compute_type(alg, V), s
            )
            (plan(s, initids; options = opts), plan(s, stepids; options = opts))
        end
    end
end

"""
    restrict_bound(stability, keys) -> stability

The stability bound of the rows `keys` alone, for a group of those fields: a front end's
bound defines it (LatticePDE's `StabilityBound` drops the cross terms that read fields
outside the group, which the group reads from their arrays). Any other bound is kept whole
(conservative: the bound of every row).
"""
restrict_bound(stability, keys) = stability

"""
    lagged_coupling(stability, groups, p; within = nothing) -> Union{Nothing, Vector}

For the field groups `groups` (vectors of state keys, in stepping order) at parameters `p`,
per group `(; rate, row, other, text, raw, reads, unseen)`:
- `rate`: the largest over the group's rows of the sum of the largest magnitudes of the
  coefficients of the terms that read fields of other groups (a group reads them from their
  arrays, held over its window; `Inf` or `NaN` when a coefficient has no finite bound); with
  `within` (per group, a collection of group indices: its loop, from [`group_loops`](@ref)),
  only the terms that read those groups count;
- for the worst row: its key `row`, the other field `other`, and the coefficient as the user
  wrote it, `text` (`raw`: the bound's own text);
- `reads`: the groups whose fields the terms the bound sees read (the group read graph; the
  structure, whatever the coefficients' values);
- `unseen`: a row of the group has a term the bound cannot see that reads another field (of
  another row, or an aux field, which may carry any state): it may read any group. A term on
  the row's own field alone (`-a^3`) does not count.

A front end's bound defines it (LatticePDE's `StabilityBound`). `nothing` (the default): the
bound does not know the cross terms.
"""
lagged_coupling(stability, groups, p; within = nothing) = nothing

"""
    steady_loop_rates(stability, groups, p, steady, loops) -> Union{Nothing, Vector}

The QuasiSteady gain in the coupling rule: for the field groups
`groups` at parameters `p`, with `steady[g]` (group `g` is solved by `QuasiSteady`) and the
loops of the read graph (`group_loops`), per group
`(; rate, row, other, text, raw, gain, kout, qs,
why)`. A steady group answers its lagged inputs at once with gain `G` (a bound on the norm
of its steady solve, from its smallest decay and its Dirichlet and Robin faces; a mask does
not count) times `kout`, the largest row sum of its reads of the loop's other groups. For a
group of a loop with a steady group that is not steady itself, `rate` is the largest over
its rows of `Σ k_in · G · kout` over its reads of steady groups plus `Σ |a|` over its reads
of the loop's other groups (`κ_QS = dt · Σ k_in · k_out / s_min` when the decay sets the
gain), with the worst term (`row`, `other`, `text`, `raw`, and `qs`, `gain`, `kout` when it
reads a steady field). `why` is `nothing` or why the rule has no bound: `(:island, k, _)` no
decay and no face anchor, `(:robin, k, _)` a Robin face with a negative diagonal,
`(:steady, k, o)` a steady row that reads a steady field of the loop, `(:unseen, k, _)` a
term the bound cannot see, `(:coef, k, o)` a coefficient with no finite bound,
`(:steady_only, _, _)` a loop of steady groups only. `nothing` (the default): the bound does
not know the gain (every such loop is refused).
"""
steady_loop_rates(stability, groups, p, steady, loops) = nothing

"""
    group_loops(parts) -> Vector{Vector{Int}}

The loops of the group read graph of `parts` (from [`lagged_coupling`](@ref)): per group,
the groups of its strongly connected component, itself included, when that holds more than
one group; else empty (the group is in no loop). Group `g` reads group `h` when a term of
`g` that the bound sees reads a field of `h`; a group with a term the bound cannot see that
reads another field (`unseen`) reads every other group. Groups outside every loop are block
triangular to the others: each is stable under its own count, and the lag between groups
only adds an O(window) source error.
"""
function group_loops(parts)
    n = length(parts)
    reach = falses(n, n)
    for g in 1:n
        for h in (parts[g].unseen ? (1:n) : parts[g].reads)
            h == g || (reach[g, h] = true)
        end
    end
    for m in 1:n, g in 1:n                          # the transitive closure (Warshall)
        reach[g, m] || continue
        for h in 1:n
            reach[m, h] && (reach[g, h] = true)
        end
    end
    return map(1:n) do g
        l = [h for h in 1:n if h == g || (reach[g, h] && reach[h, g])]
        length(l) > 1 ? l : Int[]
    end
end

# ---------------------------------------------------------------------------------------
# The substep policy: one function for both front
# ends. Its decisions (the count, when a count is refused or warned, the coupling limit
# between groups, the once-keys of the warnings) are made here; the front end gives only the
# words of its messages (`AbstractPolicyTexts`: its route and how it prints a term), so each
# front end keeps its messages.

"""
    AbstractPolicyTexts

The words of a route's substep and coupling messages. The policy
([`substeps`](@ref), [`check_coupling`](@ref)) decides; the texts word the decision
in the user's terms: standalone `FieldProblem`s use [`ProblemTexts`](@ref), coupled
`PottsProblem`s give their own. A subtype defines `unbounded_text`, `uncovered_text`,
`refuse_parameters`, `coupling_unknown_text`, `coupling_unbounded_text`, `loop_text` and
`steady_loop_text`, each of a context `NamedTuple` of the decision's facts.
"""
abstract type AbstractPolicyTexts end

"""
    ProblemTexts(route = "ExplicitEuler(; substeps = n)")

Standalone `FieldProblem` words: `route` is how a count is given.
"""
struct ProblemTexts <: AbstractPolicyTexts
    route::String
end
ProblemTexts() = ProblemTexts("ExplicitEuler(; substeps = n)")

# the warnings of the policy, once per key in a session (the key holds no value: a sweep
# warns once), for both coupled and standalone routes; none while precompiling (Julia has no
# public query for that: `Base.generating_output` is internal, so the runtime's ccall; an
# upstream gap, D-294)
const _SEEN_WARNED = Set{String}()
const _SEEN_WARNED_LOCK = ReentrantLock()
function _warn_once(key)
    return Exec.VERBOSE[] && ccall(:jl_generating_output, Cint, ()) == 0 &&
        lock(
        () -> key in _SEEN_WARNED ? false : (push!(_SEEN_WARNED, key); true),
        _SEEN_WARNED_LOCK
    )
end

"""
    substeps(spec::GroupSpec, alg::ExplicitEuler, dt, pp; fields = spec.state,
        stability = spec.stability,
             key = identity, texts = ProblemTexts(spec.texts.route)) -> Int

The substep count of the group `spec` (its fields `fields`, whose rows' bound is
`stability`) stepped by `alg` over a window `dt` at the raw parameters `pp` (with the tables
and the bound's inputs: [`with_tables`](@ref), primal values). The shared substep policy:

- a diffusion coefficient below zero, or a coefficient that is not finite at an entry the
  inputs reach, is refused at any count (`refuse_parameters`);
- with no count, `n = max(1, ⌈dt ρ / 1.8⌉)` with `ρ = stability(pp)`; an unknown bound (a
  term it cannot see, coupled rows that are not diagonally dominant, a coefficient past the
  evaluation cap) is refused, naming why (`unbounded_text`);
- with a count `m`, `n = max(m, ⌈dt ρₛ / 1.8⌉)` with `ρₛ` the bound over the terms it sees
  ([`seen_bound`](@ref); `m` when that is not finite); when the full bound is unknown, a
  warning names what it does not cover (`uncovered_text`), once per `key(why)` in a session
  (`why`: [`unbounded_key`](@ref), no value);
- a group with no field (aux fields only) takes 0.

`key` makes the warning's once-key from the value-free reason (standalone `FieldProblem`:
the program's text, hashed; coupled `PottsProblem`: the group's fingerprint text); `texts`
words the messages.
"""
function substeps(
        spec::GroupSpec, alg::ExplicitEuler, dt::Real, pp; fields = spec.state,
        stability = spec.stability,
        key = identity, texts::AbstractPolicyTexts = ProblemTexts(spec.texts.route),
        span = nothing
    )
    # aux fields only: one evaluation per window
    isempty(fields) && return 0
    dt = Float64(dt)
    # (a bound that reads the time: its windows are counted again at these parameters,
    # tables and inputs; with the run's time span, the automatic count is checked over it
    # now)
    if reads_time(stability)
        bound_params!(stability, pp)
        span === nothing || alg.substeps !== nothing ||
            _check_span(stability, pp, dt, span, texts, (; spec, fields, dt))
    end
    r = bound_report(stability, pp)
    check_declared(stability, pp)
    ctx = (; stability, pp, r, fields = collect(String, fields), dt, least = alg.substeps)
    (isempty(r.negative) && !any(x -> x[3] isa Tuple, r.nonfinite)) ||
        refuse_parameters(texts, ctx)
    full = Float64(stability(pp))
    if alg.substeps !== nothing
        ρ = seen_bound(stability, pp)
        n = isfinite(ρ) && ρ >= 0 ? max(alg.substeps, _bound_count(dt, ρ)) : alg.substeps
        if !(isfinite(full) && full >= 0)
            why = unbounded_key(stability, pp)
            why === nothing || !_warn_once(key(why)) ||
                @warn uncovered_text(texts, (; ctx..., n))
        end
        return n
    end
    isfinite(full) && full >= 0 && return max(1, _bound_count(dt, full))
    throw(ArgumentError(unbounded_text(texts, ctx)))
end
function substeps(g::FieldGroup, alg::ExplicitEuler, dt::Real, pp; kw...)
    return substeps(g.spec, alg, dt, pp; kw...)
end
# the explicit count of the bound `ρ` over a window `dt`: `⌈dt ρ / 1.8⌉` (`substeps`,
# `field_report`)
_bound_count(dt::Float64, ρ::Float64) = ceil(Int, dt * ρ / 1.8)

# a new substep count of a runtime (`_set_counts!`): an algorithm's cache may follow it (the
# implicit one's step and Newton count)
_count_set!(::Any, rt) = nothing

const _COUPLING_RTOL = 1.0e-12
_explicit_count(a) = hasproperty(a, :substeps) && getproperty(a, :substeps) !== nothing

"""
    check_coupling(stability, groups, explicit, pp, dt; check = eachindex(groups),
        key = identity,
                   texts = ProblemTexts(), span = nothing)

The coupling between field groups: one rule for both coupled and standalone routes. `groups`
are the groups' state keys in stepping order, `explicit[g]` whether group `g` has an
explicit count, `stability` the bound of the whole field system at the raw parameters `pp`,
`dt` the window. Each group in `check` that is in a
loop of the group read graph ([`group_loops`](@ref)) needs `κ = dt · rate ≤ 1` over the
reads of groups in its loop ([`lagged_coupling`](@ref)); past it the problem is refused with
the routes (`loop_text`). A cross coefficient in a loop with no finite bound is refused with
an automatic count and warns once (`key(why)`) with an explicit one; a bound that does not
know the cross terms is the same for every group. `span` is the time span (standalone
`FieldProblem` route). `steady[g]`: group `g` is solved by `QuasiSteady`. A loop with such a
group takes its gain ([`steady_loop_rates`](@ref)): each group of the loop that is not
steady needs `κ = dt · rate ≤ 1` with the steady reads through the gain (`steady_gain_text`
past it), and a loop whose gain the rule does not bound is refused (`steady_loop_text`).
"""
function check_coupling(
        stability, groups, explicit, pp, dt::Real; check = eachindex(groups),
        key = identity,
        texts::AbstractPolicyTexts = ProblemTexts(), span = nothing, steady = nothing,
        rows0 = String[]
    )
    length(groups) > 1 || return nothing
    keys = [collect(String, ks) for ks in groups]
    parts = lagged_coupling(stability, keys, pp)
    ctx = (; stability, pp, keys, dt = Float64(dt), span, rows0)
    if parts === nothing
        all(g -> explicit[g], check) ||
            throw(ArgumentError(coupling_unknown_text(texts, ctx; refuse = true)))
        _warn_once(key("coupling#unknown")) &&
            @warn coupling_unknown_text(texts, ctx; refuse = false)
        return nothing
    end
    loops = group_loops(parts)
    all(g -> isempty(loops[g]), check) && return nothing
    # a QuasiSteady group answers its inputs at once, with the gain of its steady solve: its
    # loop takes that gain, `κ_QS = dt · Σ k_in · G · k_out`, and
    # is refused when the rule has no bound for it
    withqs(g) = steady !== nothing && !isempty(loops[g]) && any(h -> steady[h], loops[g])
    if any(withqs, check)
        sr = steady_loop_rates(stability, keys, pp, steady, loops)
        for g in check
            withqs(g) || continue
            l = loops[g]
            c = (;
                ctx..., loops, g, lf = reduce(vcat, keys[l]),
                qs = reduce(vcat, keys[[h for h in l if steady[h]]]),
            )
            sr === nothing && throw(
                ArgumentError(
                    steady_loop_text(
                        texts, (;
                            c..., why = (:unknown, "", ""),
                        )
                    )
                )
            )
            x = sr[g]
            x.why === nothing ||
                throw(ArgumentError(steady_loop_text(texts, (; c..., why = x.why))))
            # (checked through the groups that read it)
            steady[g] && continue
            κ = dt * x.rate
            κ > 1 + _COUPLING_RTOL &&
                throw(ArgumentError(steady_gain_text(texts, (; c..., x, κ))))
        end
    end
    # the rates over the reads inside each group's loop: a read of a group outside it is a
    # one-way source of the loop, which cannot feed growth back
    parts = lagged_coupling(stability, keys, pp; within = loops)
    for g in check
        (isempty(loops[g]) || withqs(g)) && continue
        q = parts[g]
        κ = dt * q.rate
        c = (; ctx..., parts, loops, g, q, κ, lf = reduce(vcat, keys[loops[g]]))
        if !isfinite(κ)
            explicit[g] ||
                throw(ArgumentError(coupling_unbounded_text(texts, c; refuse = true)))
            _warn_once(
                key(
                    string(
                        "coupling#", join(keys[g], ","), "#", q.row, "#", q.raw
                    )
                )
            ) &&
                @warn coupling_unbounded_text(texts, c; refuse = false)
        elseif κ > 1 + _COUPLING_RTOL
            throw(ArgumentError(loop_text(texts, c)))
        end
        # a loop coupled through terms the bound cannot see (user ruling 2026-11-10 (a)):
        # κ covers the seen cross terms only, so the lag through the unseen ones is not
        # checked; warned once per loop (its fields; by its first group, as `PottsProblem`
        # checks each group on its own, with its own once-key), never refused. Only the
        # warning reads the unseen terms' own reads: the loops stay the conservative rule's
        # (`group_loops`)
        if g == minimum(loops[g]) && any(h -> parts[h].unseen, loops[g])
            u = unseen_loop(stability, pp, keys, parts, loops[g])
            u.kind === :none || (
                _warn_once(key(string("coupling#unseen#", join(sort(c.lf), ",")))) &&
                    @warn coupling_unseen_text(texts, (; c..., u.kind, u.terms, u.fields))
            )
        end
    end
    return nothing
end

"""
    unseen_reads(stability) -> Union{Nothing, Vector{Tuple{String, String, Vector{String}}}}

Each term the bound cannot see with the state fields it reads, structurally: `(row key,
"key: term", state
keys)` (its own field included; an aux field read through its definition). A front end's
bound defines it (LatticePDE's `StabilityBound`); `nothing` (the default): the bound does
not record them.
"""
unseen_reads(stability) = nothing

"""
    unseen_loop(stability, pp, keys, parts, loop) -> (; kind, terms, fields)

How the loop `loop` of the group read graph (`group_loops` of `parts`,
[`lagged_coupling`](@ref)) meets the terms the bound cannot see, from each unseen term's
reads ([`unseen_reads`](@ref)): `kind` is `:direct` (an unseen term of a group of the loop
reads a field of another group of the loop: the loop runs through it), `:conservative` (the
loop exists only because the rule counts an unseen term that reads another field as reading
every group), or `:none` (the loop is closed by seen reads and its unseen terms read outside
it, or only their own field). `terms` the unseen terms that read another field, as the user
wrote them; `fields` the state fields they read (the fields whose declared intervals let the
bound see them).
"""
function unseen_loop(stability, pp, keys, parts, loop)
    gof = Dict{String, Int}(k => h for (h, ks) in enumerate(keys) for k in ks)
    ur = unseen_reads(stability)
    if ur === nothing                           # (a bound that does not record the reads)
        ks = [k for h in loop if parts[h].unseen for k in keys[h]]
        ts = String[
            _termtext(t)
                for t in bound_report(stability, pp).terms
                if any(k -> startswith(t, k * ": "), ks)
        ]
        return (; kind = :conservative, terms = ts, fields = String[])
    end
    # the unseen terms that read another field (a term on its own field alone couples
    # nothing)
    cross = [(k, t, r) for (k, t, r) in ur if haskey(gof, k) && any(!=(k), r)]
    mine = [x for x in cross if gof[x[1]] in loop]
    isempty(mine) && return (; kind = :none, terms = String[], fields = String[])
    texts(xs) = String[_termtext(x[2]) for x in xs]
    fields(xs) = sort!(unique!(String[f for x in xs for f in x[3]]))
    direct = [
        x
            for x in mine
            if any(f -> haskey(gof, f) && gof[f] != gof[x[1]] && gof[f] in loop, x[3])
    ]
    isempty(direct) ||
        return (; kind = :direct, terms = texts(direct), fields = fields(direct))
    # the loop without the conservative rule: the seen reads and each unseen term's own
    # reads
    reads = [
        unique!(
            [
                parts[h].reads;
                [
                    gof[f] for x in cross if gof[x[1]] == h
                        for f in x[3] if haskey(gof, f) && gof[f] != h
                ]
            ]
        )
            for h in eachindex(keys)
    ]
    l2 = group_loops([(; reads = reads[h], unseen = false) for h in eachindex(keys)])
    g = minimum(loop)
    Set(l2[g]) == Set(loop) && return (; kind = :none, terms = String[], fields = String[])
    return (; kind = :conservative, terms = texts(mine), fields = fields(mine))
end
# a bound's term as the user wrote it (`u: -u*(v^2)`, not `u: -u(t, x, y)*(v(t, x, y)^2)`)
_termtext(t) = replace(string(t), r"\(t(, \w+)*\)" => "", "LatticePDE." => "")
# what κ covers when a loop meets unseen terms (the warning and `field_report` say it alike)
function cover_text(terms)
    return string(
        "κ covers only the cross terms the bound sees (unseen: ",
        isempty(terms) ? "a term that reads another field" : join(terms, ", "), ")"
    )
end

"""
    coupling_unseen_text(texts, c) -> String

The warning of a loop of groups that meets terms the stability bound cannot see,
`c.kind` from [`unseen_loop`](@ref): `:direct`, the loop runs through them; `:conservative`,
the loop is checked as one only because an unseen term counts as reading every group. It
names the loop's fields, the unseen terms (`c.terms`), what κ covers, and the routes (the
loop's fields in one group; declared intervals for the state fields the terms read,
`c.fields`). One text for both routes (an `AbstractPolicyTexts` may define its own).
"""
function coupling_unseen_text(::AbstractPolicyTexts, c)
    head = if c.kind === :conservative
        string(
            "a term the bound cannot see (", join(c.terms, ", "),
            ") counts as reading every group, so ", _fieldlist(c.lf),
            " are checked as a loop; κ = dt · rate = ", _num(c.κ),
            " covers only the seen terms"
        )
    else
        string(
            "the groups of ", _fieldlist(c.lf),
            " read one another in a loop through terms the stability bound cannot see: ",
            "κ = dt · rate = ", _num(c.κ), "; ", cover_text(c.terms)
        )
    end
    return string(
        head, ", so the lag between the groups (each reads the others' fields held over \
            each window dt = ",
        _num(c.dt),
        ") is not checked, and a large dt can make the run inaccurate without making it \
            unstable. Step ", _fieldlist(c.lf),
        " in one group, or declare intervals (`bounds = (lo, hi)`) for ",
        isempty(c.fields) ? "the fields these terms read" : _fieldlist(c.fields),
        ", so the bound sees them"
    )
end

"""
    GroupSubsteps(spec, alg, dt; key, texts, coupling = nothing)

The substep rule of one group, a callable of the raw parameters (with the tables, as
[`with_tables`](@ref) gives them): `rule(pp)` is [`substeps`](@ref)`(spec, alg, dt, pp; key,
texts)`, then, with `coupling = (; stability, groups, explicit, index, whole,
steady)`, the coupling check of group `index` ([`check_coupling`](@ref)) at `whole(pp)`, the
parameters of the whole field system. Coupled `PottsProblem` field phases hold one (a host
function, evaluated at build and when the parameters change, never per MCS). `key` is the
group's once-key text.
"""
struct GroupSubsteps{S, A <: AbstractFieldAlgorithm, T, C}
    spec::S
    alg::A
    dt::Float64
    key::String
    texts::T
    coupling::C
end
function GroupSubsteps(
        spec::GroupSpec, alg::AbstractFieldAlgorithm, dt::Real;
        key::AbstractString, texts::AbstractPolicyTexts, coupling = nothing
    )
    return GroupSubsteps(spec, alg, Float64(dt), String(key), texts, coupling)
end
# a group's once-key for one cause `why` (a type, not a closure per call)
struct _OnceKey
    key::String
end
(k::_OnceKey)(why) = string(k.key, "#", why)
function (s::GroupSubsteps)(pp; span = nothing)
    key = _OnceKey(s.key)
    n = if s.alg isa ExplicitEuler
        substeps(s.spec, s.alg, s.dt, pp; key, texts = s.texts, span)
    else
        substeps(s.spec, s.alg, s.dt, pp; key, texts = s.texts)
    end
    c = s.coupling
    c === nothing || check_coupling(
        c.stability, c.groups, c.explicit, c.whole(pp), s.dt; check = (c.index,),
        key, texts = s.texts, steady = c.steady,
        rows0 = hasproperty(c, :rows0) ? c.rows0 : String[]
    )
    return n
end

# --- standalone `FieldProblem` words (`ProblemTexts`) ---
_fieldlist(ks) = join(("`$k`" for k in ks), ", ")
_num(x) = round(x; sigdigits = 6)                  # a value in a message (`dt = 0.003334`)
function unbounded_text(t::ProblemTexts, c)
    why = something(
        unbounded_reason(c.stability, c.pp),
        string(
            "a rate term the bound cannot see, such as advection, a nonlinear rate, ",
            "or a coefficient with more than 6 kind sets and ",
            "comparisons; a parameter without a value; or coupled rows that ",
            "are not diagonally dominant, whose spectrum may be complex"
        )
    )
    return string(
        "no automatic substeps: no stability bound for these parameters (", why,
        "). Give an explicit count: ", t.route, " (a minimum; the bound over ",
        "the terms it sees can raise it)"
    )
end
function uncovered_text(::ProblemTexts, c)
    return string(
        "ExplicitEuler(substeps = ", c.least, "): ", c.n,
        " substeps (the request, or more for ",
        "the terms the bound sees); the stability bound does not cover ",
        unbounded_reason(c.stability, c.pp),
        ": the count is the user's"
    )
end
# the parameter check of the bound (LatticePDE: negative diffusion, a coefficient not finite
# at an entry), with its own words
function refuse_parameters(::ProblemTexts, c)
    check_parameters(c.stability, c.pp)
    why = if isempty(c.r.negative)
        "a coefficient is not finite where the inputs reach"
    else
        string("the diffusion coefficient of ", _fieldlist(c.r.negative), " is negative")
    end
    throw(
        ArgumentError(
            string(
                "the stability bound of ", _fieldlist(c.fields),
                " refuses these parameters: ", why
            )
        )
    )
end
function coupling_unknown_text(t::ProblemTexts, c; refuse::Bool)
    if refuse
        return string(
            "FieldGroups: the problem's stability bound does not see the terms that \
                couple its groups (each group ",
            "reads the fields of the others from their arrays, held over the window); \
                step the fields in one group, ",
            "or give every group an explicit count (`", t.route, "`)"
        )
    else
        return string(
            "FieldGroups: the stability bound does not see the coupling between the \
                groups ",
            join((_fieldlist(k) for k in c.keys), " and "), ": the counts are the user's"
        )
    end
end
function coupling_unbounded_text(t::ProblemTexts, c; refuse::Bool)
    ks, q, lf = c.keys[c.g], c.q, c.lf
    refuse && return string(
        "FieldGroups: the group of ", _fieldlist(ks),
        " is in a loop of groups that read one another (", _fieldlist(lf),
        "), and its coupling to the ",
        "other groups has no bound at these parameters (the coefficient `", q.text,
        "` of `", q.other,
        "` in the rate of `", q.row,
        "` reads more table entries than the bound evaluates); step ",
        _fieldlist(lf), " in one group, or give the group an explicit count (`", t.route,
        "`)"
    )
    return string(
        "FieldGroups: the coupling of the group of ", _fieldlist(ks), " in the loop of ",
        _fieldlist(lf),
        " has no bound (the coefficient `", q.text, "` of `", q.other, "` in the rate of `",
        q.row,
        "`): the count is the user's"
    )
end
# why the coupling rule has no bound for a loop with a QuasiSteady group
# (`steady_loop_rates`'s `why`), in words both routes share
function steady_why_text(why)
    w, k, o = why
    w === :island && return string(
        "`", k,
        "` has no decay and no Dirichlet or Robin face, so its steady solve has no ",
        "bounded gain (a mask's fixed value moves with the inputs, so it does not bound it)"
    )
    w === :robin && return string(
        "`", k,
        "` has a Robin face whose α and β have opposite signs, whose gain the rule ",
        "does not bound"
    )
    w === :advection && return string(
        "the steady row of `", k, "` has advection with no decay or with a velocity that ",
        "varies by site, whose gain the rule does not bound"
    )
    w === :steady && return string(
        "the steady row of `", k, "` reads the steady field `", o,
        "` of another steady group ",
        "of the loop, and the rule bounds the gain of a steady group that reads only \
            fields that step"
    )
    w === :coupled && return string(
        "the steady fields `", o,
        "` of one group read one another, and the rule's bound on ",
        "their joint gain does not hold: it sums the magnitudes of their couplings times \
            their gains, which reach 1 or more ",
        "around their loop (it cannot see that a loop of opposite signs damps itself)"
    )
    w === :unseen && return string(
        "the rate of `", k, "` has a term the stability bound cannot see, so the gain of ",
        "the loop has no bound"
    )
    w === :coef &&
        return string("a coefficient in the rate of `", k, "` has no finite bound at \
            these parameters")
    w === :steady_only &&
        return "every group of the loop is steady, so no window damps the lag between them"
    return "the stability bound does not know the gain of a steady solve"
end
# the refusal of a loop with a QuasiSteady group whose gain the rule does not bound, with
# its routes: steady groups that read one another take one `QuasiSteady` (one group: solved
# together)
function steady_loop_text(t::ProblemTexts, c)
    w = c.why[1]
    one = if w === :steady_only
        string(
            "Give ", _fieldlist(c.qs),
            " one `QuasiSteady` (the same keywords: one group, whose ",
            "steady rows are solved together), or step "
        )
    elseif w === :steady
        string(
            "Give ", _fieldlist(c.qs),
            " one `QuasiSteady` (one group, solved together), or step "
        )
    else
        "Step "
    end
    return string(
        "FieldGroups: the QuasiSteady group", length(c.qs) == 1 ? " of " : "s of ",
        _fieldlist(c.qs),
        length(c.qs) == 1 ? " is" : " are", " in a loop of groups that read one another (",
        _fieldlist(c.lf), "): a steady field answers its inputs at ",
        "once, with the gain of its steady solve, so the lag of one window between the \
            groups can grow without bound, ",
        "and here the coupling rule has no bound for that gain: ", steady_why_text(c.why),
        ". ", one, _fieldlist(c.lf),
        " in one `BackwardEuler` group, or step ", _fieldlist(c.qs),
        " with `BackwardEuler` (a fast field relaxes to its ",
        "steady state within a few windows)", rows0_route(c)
    )
end
# the `BackwardEuler` routes' condition when steady fields of the loop have steady rows `0 ~
# rhs` (which take only `QuasiSteady`): written as rates first (both routes)
function rows0_route(c)
    z = [k for k in c.qs if k in (hasproperty(c, :rows0) ? c.rows0 : String[])]
    isempty(z) && return ""
    return string(
        "; for a `BackwardEuler` route, write the steady row", if length(z) == 1
            " of "
        else
            "s of "
        end, _fieldlist(z),
        " as ", length(z) == 1 ? "a rate" : "rates",
        " `D(c) ~ rhs` (a steady row `0 ~ rhs` takes only `QuasiSteady`)"
    )
end
# the gain of a loop with a QuasiSteady group in words: the worst term and the gain it reads
# through
function steady_gain_words(c)
    x = c.x
    via = if isempty(x.qs)
        ""
    else
        string(
            " (`", x.qs, "` answers at once with a gain up to ", _num(x.gain),
            ", from its smallest decay and its faces, times ", _num(x.kout),
            ", the sum of its reads of the loop)"
        )
    end
    return string(
        "the terms in the rate of `", x.row,
        "` that read other groups of the loop (the largest: the ",
        "coefficient `", x.text, "` of `", x.other, "`", via,
        ") give κ = dt · Σ k_in · gain · k_out = ",
        round(c.κ; sigdigits = 4), " > 1"
    )
end
# the refusal of a loop with a QuasiSteady group past the limit, with its routes
function steady_gain_text(t::ProblemTexts, c)
    lim = floor(1 / c.x.rate; sigdigits = 4)
    span = c.span
    n = span === nothing ? 0 : max(1, ceil(Int, span * c.x.rate * (1 - _COUPLING_RTOL)))
    return string(
        "FieldGroups: the QuasiSteady group", length(c.qs) == 1 ? " of " : "s of ",
        _fieldlist(c.qs),
        length(c.qs) == 1 ? " is" : " are", " in a loop of groups that read one another (",
        _fieldlist(c.lf), "), each from the others' arrays, held ",
        "over each window dt = ", _num(c.dt), ": ", steady_gain_words(c),
        ", and the loop can then grow without bound. ",
        "Step ", _fieldlist(c.lf), " in one `BackwardEuler` group, or step ",
        _fieldlist(c.qs), " with `BackwardEuler`, ",
        "or use a smaller dt", if span === nothing
            ""
        else
            string(" that divides the time span ", _num(span))
        end,
        ": dt ≤ ", lim,
        span === nothing ? "" : string(", such as dt = ", _num(span), "/", n),
        rows0_route(c)
    )
end
# the refusal of a loop past the limit, with its routes
function loop_text(t::ProblemTexts, c)
    q, κ, lf, dt, pp = c.q, c.κ, c.lf, c.dt, c.pp
    unseen = [k for h in c.loops[c.g] if c.parts[h].unseen for k in c.keys[h]]
    # route 1: the loop's fields in one group; an automatic count needs dominant rows
    ρ = Float64(restrict_bound(c.stability, lf)(pp))
    one = if isfinite(ρ) && ρ >= 0
        string(
            "Step ", _fieldlist(lf),
            " in one group (one algorithm; its count can be automatic)"
        )
    else
        string(
            "Step ", _fieldlist(lf), " in one group with an explicit count (`", t.route,
            "`: ",
            "their rows are not diagonally dominant, so no automatic count bounds them)"
        )
    end
    # route 2: a dt that divides the time span (`init` refuses any other)
    span = c.span
    lim = floor(1 / q.rate; sigdigits = 4)
    n = max(1, ceil(Int, span * q.rate * (1 - _COUPLING_RTOL)))
    note = if isempty(unseen)
        ""
    else
        string(
            " (the terms of ", _fieldlist(unseen),
            " that the bound cannot see and that read ",
            "another field count as reading every other group)"
        )
    end
    return string(
        "FieldGroups: the groups of ", _fieldlist(lf),
        " read one another in a loop, each from the ",
        "others' arrays, held over each window dt = ", _num(dt),
        ": the terms in the rate of `", q.row,
        "` that read other groups of the loop (the largest: the coefficient `",
        q.text,
        "` of `", q.other, "`) give dt · Σ max|coefficient| = ",
        round(κ; sigdigits = 4), " > 1, and the loop can then ",
        "grow without bound at any substep count", note,
        ". ", one, ", or use a smaller dt that divides the time span ",
        _num(span), ": dt ≤ ", lim,
        ", such as dt = ", _num(span), "/", n
    )
end

# The status word: an algorithm with a solve keeps a sticky device word
# `UInt32[8]` in its cache, and the drivers read it where they synchronize anyway.

"""
    STATUS_CODE

Entry [1] of the status word (`UInt32[8]`), the worst code: 0 `Success`,
1 `StalledSuccess`, 2 `ConvergenceFailure`. Sticky. The other entries are
[`STATUS_WINDOW`](@ref), [`STATUS_CAUSE`](@ref), [`STATUS_SOLVES`](@ref),
[`STATUS_BUDGET`](@ref), [`STATUS_FLOOR`](@ref) and [`STATUS_NEWTON_BUDGET`](@ref), and [8],
the rows that met the Newton tolerance in the last iteration (a host executor reads it to
stop early). A read ([`check_status!`](@ref)) adds [4]-[7] to the runtime's host totals and
zeroes them on the device; [1]-[3] are sticky.
"""
const STATUS_CODE = 1

"""
    STATUS_WINDOW

Entry [2] of the status word: the first failing window (1-based: the `rt.totals.windows`-th
window since the bind or `clear_status!`, which a cache reads when it writes the word).
Sticky.
"""
const STATUS_WINDOW = 2

"""
    STATUS_CAUSE

Entry [3] of the status word: the cause bits ([`STATUS_CAUSES`](@ref)). Sticky.
"""
const STATUS_CAUSE = 3

"""
    STATUS_SOLVES

Entry [4] of the status word: the solves since the last read ([`check_status!`](@ref)).
"""
const STATUS_SOLVES = 4

"""
    STATUS_BUDGET

Entry [5] of the status word: the linear budget hits since the last read.
"""
const STATUS_BUDGET = 5

"""
    STATUS_FLOOR

Entry [6] of the status word: the floors hit since the last read.
"""
const STATUS_FLOOR = 6

"""
    STATUS_NEWTON_BUDGET

Entry [7] of the status word: the Newton budget hits since the last read.
"""
const STATUS_NEWTON_BUDGET = 7

"""
    STATUS_CAUSES

The cause bits of the status word's entry [3], in words: 1 the linear solve diverged, 2 the
Newton iteration diverged, 4 a residual was not finite, 8 the shift was clamped, 16 a steady
solve's budget hit made no real reduction (`QuasiSteady`: a singular region), 32 a steady
linear solve diverged (an indefinite steady problem, or an island), 64 a coupled steady
solve
 diverged or made no real reduction (the coupled system has no unique steady state, or
its budget is short), 128 a coupled solve broke down (its operator is singular on its Krylov
steps).
"""
const STATUS_CAUSES = (
    0x00000001 => "the linear solve diverged",
    0x00000002 => "the Newton iteration diverged",
    0x00000004 => "a residual was not finite", 0x00000008 => "the shift was clamped",
    0x00000010 => "the steady solve made no real reduction: a region has no decay and no \
        fixed value, so its steady state is not unique",
    0x00000020 =>
        "the steady solve diverged: the steady problem may be indefinite (a growth, or a " *
        "Robin face whose α and β have opposite signs) or have an island (a region with no \
            decay and no fixed value)",
    0x00000040 =>
        "the coupled steady solve of the fields that read one another made no real " *
        "reduction: their coupled system may have no unique steady state (a mode of the " *
        "coupling that grows or stays, or a region with no decay and no fixed value), or \
            the solve's budget is short",
    0x00000080 =>
        "the coupled solve broke down: its operator is singular on the steps it built, " *
        "so the coupled system may have no unique solution (a mode of the coupling that \
            stays, or a region with no decay and no fixed value)",
)

"""
    status_word(cache) -> word or nothing

The device status word of an algorithm's cache ([`STATUS_CODE`](@ref)), or `nothing` for an
algorithm with no solve (`ExplicitEuler`, `ExplicitMap`): then [`check_status!`](@ref) reads
nothing and costs nothing.
"""
status_word(::Any) = nothing
# the Newton count of an algorithm's cache (its budget warning names it), or nothing
newton_count(::Any) = nothing

"""
    status_route(alg, which, cause = 0; coupled = false) -> String

The route a warning or failure of `alg`'s status word names: `which` is `:budget` (the
linear solve reached its budget), `:newton_budget` (the Newton iteration did) or `:failure`,
whose route follows its `cause` bits ([`STATUS_CAUSES`](@ref)): a linear divergence takes
more substeps or a larger linear budget; a Newton divergence or a residual that is not
finite takes more substeps only (a smaller step brings the iteration into its contraction;
neither more iterations nor a larger linear budget does). `coupled`: the group is solved
together (a `QuasiSteady` group only), so its linear budget is the `LatticeGMRES`'s.
"""
function status_route(alg, which::Symbol, cause::Integer = 0; coupled::Bool = false)
    which === :budget &&
        return "a larger linear budget (`linsolve = LatticePCG(; maxiters = n)`)"
    which === :newton_budget &&
        return "more Newton iterations (a larger `nlsolve = LatticeNewton(; max_iter = \
            k)`) or more substeps (`substeps = n`)"
    cause & 0x01 != 0 &&
        return "more substeps (`substeps = n`) or a larger linear budget (`linsolve = \
            LatticePCG(; maxiters = n)`)"
    cause & 0x06 != 0 &&
        return "more substeps (`substeps = n`): a smaller step brings the Newton \
            iteration into its contraction"
    return "more substeps (`substeps = n`) or a larger linear budget (`linsolve = \
        LatticePCG(; maxiters = n)`)"
end
# a steady solve has no substeps: its routes are the budgets, a fixed value or decay, or a
# transient solver
function status_route(
        ::QuasiSteady, which::Symbol, cause::Integer = 0;
        coupled::Bool = false
    )
    if which === :budget
        solver = coupled ? "LatticeGMRES" : "LatticePCG"
        return "a larger linear budget (`linsolve = $solver(; maxiters = n)`)"
    end
    which === :newton_budget &&
        return "more Newton iterations (a larger `nlsolve = LatticeNewton(; max_iter = k)`)"
    cause & 0xc0 != 0 && return string(
        "step the fields with `BackwardEuler` (a transient solve needs no unique steady ",
        "state), or give the coupled solve a larger budget (`linsolve = LatticeGMRES(; \
            maxiters = n)`)"
    )
    cause & 0x20 != 0 &&
        return "step the field with `BackwardEuler`, or give each region a decay or a \
            fixed value"
    cause & 0x10 != 0 &&
        return "give that region a decay or a fixed value, or step the field with \
            `BackwardEuler`"
    cause & 0x01 != 0 &&
        return "a larger linear budget (`linsolve = LatticePCG(; maxiters = n)`), or step \
            the field with `BackwardEuler`"
    return "step the field with `BackwardEuler` (a transient solve converges where the \
        steady Newton iteration does not)"
end

"""
    StatusTotals

The host totals of a runtime's status word: `solves`, `budget` (linear
budget hits), `floor` (rounding floors), `newton_budget` (Newton budget hits), the first
failing `window` (0: none), the `cause` bits seen so far (a failure's, and the shift
clamp's, which is not one), and whether the budget warning was given (once per runtime).
`windows` counts the windows [`advance!`](@ref) has run since the bind or the last
[`clear_status!`](@ref) (a window of length 0, the at-init clamp, is not counted), and `t1`
is the first one's start time: entry [2] of the word is a window of this count, so window
`w` starts at `t1 + (w - 1) dt`. `where` words a window in a front end's terms
(`(w, t) -> "the field step of MCS n (t = …)"` in Potts), or `nothing`: "window w (t = …)".
"""
Base.@kwdef mutable struct StatusTotals
    solves::Int64 = 0
    budget::Int64 = 0
    floor::Int64 = 0
    newton_budget::Int64 = 0
    window::Int64 = 0
    cause::UInt32 = 0
    warned::Bool = false
    clamped::Bool = false               # the shift clamp's warning was given
    # a field left its declared bounds (`check_declared!`)
    leaked::Bool = false
    # the windows advanced since the bind or `clear_status!`
    windows::Int64 = 0
    t1::Float64 = NaN                   # … the start time of the first of them
    # a front end's `(window, t1) -> text` for messages, or nothing
    where::Any = nothing
end

"""
    GroupRuntime

One group bound to a store's arrays at parameters `p`: the mask launches
and the step launches at both slot parities, the clamps of its masked fields, the copies
that bring its fields back to slot 1 (`ends_in = :slot1`), its substep count `n` and window
`dt`, the algorithm's cache (`alg_cache`) and the status of its last step. Made by
[`bind_group`](@ref), stepped by [`advance!`](@ref).

`pending` is the host task that compiles the launches on a device (`nothing` when there is
none): a caller awaits it before the first step. `host` is the caller's own record of
the binding (`PottsProblem`: the parameter object and the state arrays it was bound from).
"""
mutable struct GroupRuntime{ST <: FieldStore, A, B, M, CL, SC, CP, PV, S, H, DC}
    store::ST
    alg::A
    init::Any                           # the init plan (masks), for `rebind!`
    step::Any                           # the step plan, for `rebind!`
    steps::NTuple{2, B}
    # the mask launches at both slot parities, or nothing
    masks::M
    clamps::CL                          # the masked fields' arrays and values (`_clamps`)
    stepclamps::SC                      # those a step runs after its masks (on a device the
    # mask launches clamp themselves: `_mask_fuse`)
    swaps::Vector{Int32}                # the group's two-buffer fields
    copies::CP                          # (slot 1, slot 2) of each, for `ends_in = :slot1`
    ends_in::Symbol
    all_state::Bool                     # the group holds every state field (one group)
    keys::Vector{String}                # the group's state keys
    n::Int
    dt::Float64
    stability::Any                      # the bound of the group's rows (`restrict_bound`)
    p::PV                               # the parameters the launches are bound to (shared)
    c::Any                              # the compute element type's zero
    program::Any
    backend::Any
    cache::S
    status::SciMLBase.ReturnCode.T
    pending::Union{Nothing, Task}
    host::H
    totals::StatusTotals                # the status word's host totals (`check_status!`)
    # the fields whose declared interval the bound used, with their buffers
    # (`check_declared!`)
    declared::DC
    recount::Any                        # an explicit group whose bound reads the time:
    # its group spec, the count re-bounded each window; or nothing
end

# the current slots a launch of the group binds at slot parity `parity`: the group's fields
# at `parity`, every other field at its own slot (slot 1 for the fields of other groups)
function _cur(st::FieldStore, swaps, parity, all_state::Bool)
    return if all_state
        fill(parity, length(st.cur))
    else
        [f in swaps ? parity : st.cur[f] for f in eachindex(st.cur)]
    end
end

function _bind_steps(backend, prog, sp::StepPlan, st, p, swaps, all_state, c)
    return (
        BoundStep(backend, prog, sp, st, p; cur = _cur(st, swaps, 1, all_state), c),
        BoundStep(backend, prog, sp, st, p; cur = _cur(st, swaps, 2, all_state), c),
    )
end
function _bind_masks(backend, prog, ip::StepPlan, st, p, swaps, all_state, c, ids)
    isempty(ip.launches) && return nothing
    fuse = Exec.ishost(backend) ? nothing : _mask_fuse(prog, st, p, ids)
    return (
        BoundStep(backend, prog, ip, st, p; cur = _cur(st, swaps, 1, all_state), c, fuse),
        BoundStep(backend, prog, ip, st, p; cur = _cur(st, swaps, 2, all_state), c, fuse),
    )
end

"""
    bind_group(g, alg, store, p; fields = g.spec.state, n, dt, c, ends_in = :parity,
        backend,
               options, kernels = nothing) -> GroupRuntime

Bind the fields `fields` of group `g` (all of its state by default) to the arrays of `store`
at parameters `p` (the vector is shared: the driver updates it in place before `rebind!`),
to step with algorithm `alg` in `n` substeps per window `dt`. `ends_in = :parity` leaves the
fields in the slot their last substep wrote (one group: the slots alternate); `:slot1`
copies them back to slot 1 after an odd count, so a group that runs after it reads current
values. `kernels = (initids, stepids)` binds those kernels of the group's program alone
(coupled `PottsProblem`'s at-init evaluation of the `aux:` kernels, `n = 0`); by default the
fields' own kernels.
"""
function bind_group(
        g::FieldGroup, alg, st::FieldStore, p; fields = g.spec.state, n::Integer, dt::Real,
        c, ends_in::Symbol = :parity, backend, options::CompileOptions,
        V::Type, host = nothing, kernels = nothing,
        shared = nothing, abstol = 1 // 10^6, reltol = 1 // 10^3
    )
    ends_in in (:parity, :slot1) ||
        throw(ArgumentError("ends_in must be :parity or :slot1; got $(repr(ends_in))"))
    prog = group_program(g, alg)
    check_backend_float64(prog, alg, backend, V; fields)
    ids = Set(fieldid(prog, k) for k in fields)
    all_state = issubset(Set(fieldid(prog, k) for k in g.spec.state), ids)
    # (`kernels = (initids, stepids)`: those kernels alone, e.g. a group's `aux:` kernels)
    ip, sp = group_plans(
        g, alg, V, backend, options; kernels = something(kernels, _group_kernels(g, ids))
    )
    swaps = all_state ? copy(sp.swaps) : Int32[f for f in sp.swaps if f in ids]
    steps = _bind_steps(backend, prog, sp, st, p, swaps, all_state, c)
    masks = _bind_masks(backend, prog, ip, st, p, swaps, all_state, c, ids)
    clamps = _clamps(prog, st, ids)
    fused = if masks === nothing || Exec.ishost(backend)
        Int[]
    else
        _fused_rules(prog, ip, st, ids)
    end
    stepclamps = Tuple(cl for (j, cl) in enumerate(clamps) if !(j in fused))
    copies = Tuple((st.bufs[f][1], st.bufs[f][2]) for f in swaps)
    stab = if all_state
        g.spec.stability
    else
        restrict_bound(g.spec.stability, collect(String, fields))
    end
    return GroupRuntime(
        st, alg, ip, sp, steps, masks, clamps, stepclamps, swaps,
        copies, ends_in, all_state, collect(String, fields), Int(n),
        Float64(dt), stab, p, c, prog, backend,
        bind_cache(
            alg, g, st, p; fields = collect(String, fields), n, dt, c, backend, options, V,
            abstol, reltol, (shared === nothing ? (;) : (; shared))...
        ), SciMLBase.ReturnCode.Success,
        nothing, host,
        StatusTotals(), _declared_checks(stab, st, prog, fields),
        alg isa ExplicitEuler && reads_time(stab) ? g.spec : nothing
    )
end
"""
    check_backend_float64(prog, alg, backend, V; fields)

A group that declares Float64 on a backend without it (`Exec.supports(backend, Float64)`
false: Metal) is refused at the bind, in the user's words: a `compute_type` or `solver_type`
of Float64, or a field of its program declared `lattice_storage = Float64` (the group's own,
or one it reads). Without the check the kernel compiler would refuse it in its own group's
own terms. A Float64 state type `V` is the caller's own check.
"""
function check_backend_float64(prog, alg, backend, V::Type; fields = String[])
    Exec.supports(backend, Float64) && return nothing
    fs = join(("`$k`" for k in fields), ", ")
    head = string("field", length(fields) == 1 ? " " : "s ", fs, ": ")
    tail = " needs Float64 on the device, and this backend has no Float64 \
        (`supports_float64` is false: Metal)"
    compute_type(alg, V) <: Float64 && !(value_type(V) <: Float64) && throw(
        ArgumentError(
            string(
                head, _algtext(alg),
                ": `compute_type = Float64`", tail,
                "; leave `compute_type` out (`:auto`, the problem's type) or give \
                    `compute_type = Float32`"
            )
        )
    )
    hasfield(typeof(alg), :solver_type) && getfield(alg, :solver_type) === Float64 &&
        value_type(V) !== Float64 && throw(
        ArgumentError(
            string(
                head, _algtext(alg), ": `solver_type = Float64`",
                tail, "; leave `solver_type` out (`:auto`) ",
                "or give `solver_type = Float32`"
            )
        )
    )
    for f in prog.fields
        f.fixed && f.storage == F64 || continue
        throw(
            ArgumentError(
                string(
                    head, "the field `", f.key,
                    "` is declared `lattice_storage = Float64`, which", tail,
                    "; declare it `lattice_storage = Float32`, or run on a backend with \
                        Float64 (the CPU, ROCm, CUDA)"
                )
            )
        )
    end
    return nothing
end

# The fields of a runtime whose declared interval a coefficient bound read:
# its state fields and the aux fields of its program, each with its buffers and interval
function _declared_checks(stab, st::FieldStore, prog, fields)
    used = used_intervals(stab)
    isempty(used) && return ()
    out = Any[]
    for (k, (lo, hi)) in declared_intervals(stab)
        k in used || continue
        f = findfirst(x -> x.key == k, prog.fields)
        f === nothing && continue
        (k in fields || prog.fields[f].role == :aux) || continue
        push!(
            out,
            (;
                bufs = Tuple(st.bufs[f]), fid = Int(f),
                lo = Float64(lo), hi = Float64(hi), key = String(k),
            )
        )
    end
    return Tuple(out)
end

"""
    check_declared!(rt) -> ReturnCode.T

Whether the fields of runtime `rt` whose declared `bounds = (lo, hi)` the stability bound
used are still inside them: the bound, and so the substep count, holds only there. Read
where the status is read (coupled `PottsProblem`: after each window on the host, at the
saves on a device; standalone `FieldProblem`: at the saves and at the end): one pass over
each such field (no allocation on the host). A value outside warns once, naming the field,
the value, the site and the routes. An explicit group then makes `rt.status`
`ReturnCode.Unstable` (the run stops: its count holds only inside the interval). An implicit
group goes on: there the interval sets only the counts (substeps, Newton iterations), and a
growth past what they saw is caught by the solve's own checks. With `newton > 1` the Newton
check of every substep (the host stop, the device check) counts an iteration that does not
converge (a budget hit, warned and counted in `field_stats`) or a divergence
(`ConvergenceFailure`); with one Newton step (an exact local Jacobian) the shift clamp
records a growth above `1/(2h)` in the status word and warns. Its warning leads with
`lower_bound = lo`, since CrankNicolson and BDF2 undershoot by a few percent near a bound. A
value that is not finite stops every group. Returns `rt.status`.
"""
function check_declared!(rt::GroupRuntime)
    (isempty(rt.declared) || rt.totals.leaked) && return rt.status
    j = _first_leak(rt.declared, rt.store.cur)
    j == 0 && return rt.status
    _leak_warn(rt, j) && return rt.status
    rt.status = _worse(rt.status, SciMLBase.ReturnCode.Unstable)
    return rt.status
end
# the first declared field outside its interval (0: none); one flag per field, unrolled over
# the tuple's length (no recursion over the heterogeneous tuple)
function _first_leak(d::Tuple, cur)
    out = ntuple(
        i -> _outside(d[i].bufs[min(cur[d[i].fid], length(d[i].bufs))], d[i].lo, d[i].hi),
        Val(length(d))
    )
    j = findfirst(out)
    return j === nothing ? 0 : j
end
function _outside(a::Array, lo::Float64, hi::Float64)
    @inbounds for i in eachindex(a)                    # (the array's own indices)
        lo <= a[i] <= hi || return true
    end
    return false
end
# a device array: one reduction in the array's own type (no Float64 on the device, D-157)
function _outside(a::AbstractArray, lo::Float64, hi::Float64)
    E = eltype(a)
    l, h = convert(E, lo), convert(E, hi)
    return mapreduce(v -> !(l <= v <= h), |, a; init = false)
end
@noinline function _leak_warn(@nospecialize(rt), j)
    rt.totals.leaked = true
    x = rt.declared[j]
    a = Array(x.bufs[min(rt.store.cur[x.fid], length(x.bufs))])
    i = something(findfirst(v -> !(x.lo <= v <= x.hi), a), 1)
    f = rt.program.fields[x.fid]
    site = Tuple(CartesianIndices(Tuple(leveldims(rt.program, f.levels[1])))[i])
    w = max(rt.totals.windows, 1)
    v = primal(a[i])
    head = string(
        "field `", x.key, "` left its declared bounds (", x.lo,
        ", ", x.hi, "): it holds ", v, " at site ",
        site, " by the end of ", window_text(rt, w), ". "
    )
    # an implicit group goes on: the interval sets only its Newton count, which the Newton
    # check verifies
    if rt.alg isa AbstractImplicitFieldAlgorithm && isfinite(v)
        below = v < x.lo
        route = if below && !(rt.alg isa QuasiSteady)
            string(
                "Give `lower_bound = ", x.lo,
                "` to the algorithm (it clips each substep at ", x.lo, ": ",
                _algname(rt.alg), " does not keep the values inside the bounds by \
                    itself), or widen `bounds`"
            )
        else
            "Widen `bounds` in the field's declaration to the range the field takes"
        end
        Exec.VERBOSE[] && @warn string(
            head, route,
            ". The interval sets only the implicit solve's counts, and the solve checks \
                its own ",
            "steps (the Newton check when it iterates, the shift clamp when it takes one \
                step; both warn), so the run goes on"
        )
        return true
    end
    Exec.VERBOSE[] && @warn string(
        head, "The stability bound takes that interval for the coefficients ",
        "that read `", x.key,
        "`, so the substep count does not cover the run past it: `ReturnCode.Unstable`, \
            the run ",
        "stops. Give more substeps (`substeps = n`), or widen `bounds` in the field's \
            declaration to the range the field ",
        "takes (a source, a boundary flux or an overshoot can carry it out)"
    )
    return false
end

"""
    rebind!(rt, p)

Bind the runtime's launches to the parameter values `p` (the derived parameters are launch
arguments; nothing recompiles), and drop the algorithm's history ([`reset!`](@ref)). In two
parts for an atomic update of several groups: `rebind_launches(rt, p)` binds (and may
throw), `install_launches!(rt, launches)` installs.
"""
rebind!(rt::GroupRuntime, p) = install_launches!(rt, rebind_launches(rt, p))

"""
    rebind_launches(rt::GroupRuntime, p) -> launches

The first part of [`rebind!`](@ref): the runtime's launches bound to the parameter values
`p`, returned and not installed. It may throw (a parameter refused); the runtime is then
unchanged. Install the result with [`install_launches!`](@ref).
"""
function rebind_launches(rt::GroupRuntime, p)
    return (
        _bind_steps(
            rt.backend, rt.program, rt.step, rt.store, p, rt.swaps, rt.all_state, rt.c
        ),
        _bind_masks(
            rt.backend, rt.program, rt.init, rt.store, p, rt.swaps, rt.all_state, rt.c,
            Set(fieldid(rt.program, k) for k in rt.keys)
        ),
    )
end
"""
    install_launches!(rt::GroupRuntime, launches)

The second part of [`rebind!`](@ref): installs `launches` from [`rebind_launches`](@ref)
and drops the algorithm's history. It does not throw, so several groups can be updated
together after all of their `rebind_launches` calls succeeded.
"""
function install_launches!(rt::GroupRuntime, (steps, masks))
    rt.steps, rt.masks = steps, masks
    reset!(rt)
    return rt
end

"""
    reset!(rt)

Drop the algorithm's history ([`reset_cache!`](@ref) of its cache): called after a state
write (`integ[c] = values`, an input or table write, `reinit!`) and after a rebind. A stored
status (`rt.status`, the word) is kept: a failure ends the run; `reinit!` clears it
([`clear_status!`](@ref)).
"""
reset!(rt::GroupRuntime) = (reset_cache!(rt.cache); nothing)

"""
    clear_status!(rt)

Start a new run of runtime `rt` (`reinit!`): its status word is zeroed, its totals
(counters, the failing window and causes, the warning flag, the window count) and
`rt.status` cleared. A [`reset!`](@ref) (a write, a rebind) keeps them: a failure ends its
run.
"""
function clear_status!(rt::GroupRuntime)
    w = status_word(rt.cache)
    w === nothing || fill!(w, zero(eltype(w)))
    where = rt.totals.where
    rt.totals = StatusTotals(; where)
    rt.status = SciMLBase.ReturnCode.Success
    return nothing
end

_parity(rt::GroupRuntime) = isempty(rt.swaps) ? 1 : rt.store.cur[rt.swaps[1]]

# the masked values now, at the parameters the launches are bound to
clamp_now!(rt::GroupRuntime) = (_clamp!(rt.clamps, rt.store, rt.p); nothing)

"""
    advance!(rt, clock, n = rt.n, window = rt.dt) -> ReturnCode.T

One window of the group: with `clock = (t0, k)` (the window's start time and the clock's
step index), the masks and the clamp at the window's start (when the group has masked
conditions), then `n` substeps of `h = window / n` at `t0 + j h`, alternating the slot
parity; with `ends_in = :slot1` the fields go back to slot 1 after an odd count. A kernel
that reads the clock slot (`clock__tick`: `mcs` in a coupled `PottsProblem`,
`LatticePDE.step_index(t)` in a standalone `FieldProblem`) reads `k` at every substep.
Returns the algorithm's code for the step (`ReturnCode.Success` for the explicit
algorithms); `rt.status` keeps the worst code since the bind or the last
[`clear_status!`](@ref) (a [`reset!`](@ref) keeps it). No allocation on the host executor.

A group with no state (aux fields `K ~ rhs` only) takes `n = 0`: its kernels
run once, at the window's start `(t0, k)`, with the window as their step length.
"""
function advance!(
        rt::GroupRuntime, clock::Tuple{Real, Integer}, n::Integer = rt.n,
        window::Real = rt.dt
    )
    t = Float64(clock[1])
    k = Int(clock[2])
    # (an explicit group whose bound reads the time: the window's count)
    # (behind a barrier: a group whose bound does not read the time compiles none of it)
    m = if rt.recount === nothing
        Int(n)
    else
        Base.inferencebarrier(_recount!)(rt, Int(n), t, Float64(window))::Int
    end
    h = m == 0 ? Float64(window) : Float64(window) / m
    st = rt.store
    # the window count of the status word's entry [2] (a window of length 0 is not one)
    if window > 0
        tot = rt.totals
        tot.windows += 1
        tot.windows == 1 && (tot.t1 = t)
    end
    if rt.masks !== nothing
        rt.masks[_parity(rt)]((t, h, k))
        # the values the masks set now (the bound parameters): on a device the mask launches
        # clamp the sites they mark themselves (one launch, `_mask_fuse`), so none is left
        # here
        _clamp!(rt.stepclamps, rt.store, rt.p)
    end
    _substeps!(rt.cache, rt, t, h, k, m)
    rt.ends_in === :slot1 && _slot1!(rt.copies, st.cur, rt.swaps, 1)
    code = step_retcode!(rt.cache, rt)
    # (sticky: the worst so far, until `clear_status!`)
    rt.status = _worse(rt.status, code)
    return code
end

# The substep count of explicit runtime `rt` over the window `[t, t + window]`: its bound
# reads the time (a Robin coefficient of the time), so the count is the policy's at the
# bound over this window, at the parameters the steps are bound to (primal values; a bound
# that reads tables sees none here, so it has no finite bound and the policy refuses or
# warns as at the bind). Allocates (once per window, only for such groups) (a count given to
# `advance!` other than the runtime's own, or a window of length 0, is kept)
function _recount!(rt::GroupRuntime, n::Int, t::Float64, window::Float64)::Int
    (n == rt.n && window > 0) || return n
    bound_window!(rt.stability, t, t + window)
    pp = something(bound_params(rt.stability), Float64[primal(v) for v in rt.p])
    m = substeps(
        rt.recount::GroupSpec, rt.alg, window, pp;
        fields = rt.keys, stability = rt.stability
    )::Int
    rt.n = m
    return m
end

# The automatic count over the run's time span `span` of a bound that reads the time: the
# bound over the whole span; when it has none, the first window `[t, t + dt]` (bisection to
# one window) where it fails is named, so the run is refused at the bind, not partway
# through. The window goes back to what it was
function _check_span(stability, pp, dt::Float64, span, texts, ctx)
    t0, t1 = Float64(span[1]), Float64(span[2])
    w0 = bound_window(stability)
    function ok(t)
        bound_window!(stability, t0, t)
        r = Float64(stability(pp))
        return isfinite(r) && r >= 0
    end
    return try
        (t1 <= t0 || ok(t1)) && return nothing
        lo, hi = t0, t1                             # ok over [t0, lo], not over [t0, hi]
        ok(min(t0 + dt, t1)) || (hi = min(t0 + dt, t1))
        while hi - lo > dt
            m = (lo + hi) / 2
            ok(m) ? (lo = m) : (hi = m)
        end
        bound_window!(stability, max(t0, hi - dt), hi)
        why = unbounded_reason(stability, pp)
        throw(
            ArgumentError(
                string(
                    unbounded_text(
                        texts, (;
                            ctx..., stability, pp, r = bound_report(stability, pp),
                            least = nothing,
                        )
                    ), " (the bound holds from the start time ", t0,
                    " and fails in the window ending at t = ",
                    round(hi; sigdigits = 6), why === nothing ? "" : string(": ", why), ")"
                )
            )
        )
    finally
        w0 === nothing || bound_window!(stability, w0[1], w0[2])
    end
end

"""
    bound_params!(stability, pp), bound_params(stability)

The parameters (with their tables and inputs) a bound that [`reads_time`](@ref) was last
counted at, for the count of each window; a front end's bound keeps them (nothing by
default).
"""
bound_params!(stability, pp) = nothing
bound_params(stability) = nothing
# the time span a bound is taken over now, `(t0, t1)`, or nothing (a front end's bound
# defines it)
bound_window(stability) = nothing

"""
    reads_time(stability) -> Bool

Whether a stability bound depends on the time (a Robin coefficient of the time): an
explicit group then takes its count again at each window, over the window's span
([`bound_window!`](@ref)). A front end's bound defines it; `false` by default.
"""
reads_time(stability) = false
"""
    bound_window!(stability, t0, t1)

Set the time span a bound that [`reads_time`](@ref) is taken over (a front end's bound
defines it; nothing by default).
"""
bound_window!(stability, t0, t1) = nothing

"""
    check_status!(rt, acc = nothing) -> ReturnCode.T

Read the status word of runtime `rt`'s algorithm ([`status_word`](@ref); a synchronization
on a device, a plain read on the host) and return the worst code so far, also kept in
`rt.status`: `ConvergenceFailure` (the first failing window and its causes are kept, and a
warning names the fields, the window, the causes and the route, once), `StalledSuccess` (a
rounding floor: the run goes on) or `Success`. The counters [4]–[7] go to `rt.totals` (and
to `acc`, a front end's counters with the same fields, when given) and are zeroed on the
device; a linear or Newton budget hit warns once per runtime, naming the fields, the count
and the route, and stays `Success`. An algorithm with no word reads nothing (no launch, no
copy).
"""
function check_status!(rt::GroupRuntime, acc = nothing)
    return _check_status!(status_word(rt.cache), rt, acc)
end
_check_status!(::Nothing, rt::GroupRuntime, acc) = rt.status
function _check_status!(w, rt::GroupRuntime, acc)
    h = w isa Array ? w : Array(w)
    tot = rt.totals
    d = (h[STATUS_SOLVES], h[STATUS_BUDGET], h[STATUS_FLOOR], h[STATUS_NEWTON_BUDGET])
    if any(!iszero, d)
        _add_counts!(tot, d)
        acc === nothing || _add_counts!(acc, d)
        if w isa Array
            w[STATUS_SOLVES:STATUS_NEWTON_BUDGET] .= 0
        else
            view(w, STATUS_SOLVES:STATUS_NEWTON_BUDGET) .= 0
        end
    end
    # (the causes so far: a clamp is recorded, not a failure)
    tot.cause |= h[STATUS_CAUSE]
    # a clamped shift with one Newton step and no check: the step is not the Backward Euler
    # step, and nothing else tells
    !tot.clamped && h[STATUS_CAUSE] & 0x08 != 0 && newton_count(rt.cache) == 1 &&
        _clamp_warn(rt, h)
    code = if h[STATUS_CODE] == 0
        SciMLBase.ReturnCode.Success
    elseif h[STATUS_CODE] == 1
        SciMLBase.ReturnCode.StalledSuccess
    else
        SciMLBase.ReturnCode.ConvergenceFailure
    end
    if (!tot.warned && (tot.budget > 0 || tot.newton_budget > 0)) ||
            (code == SciMLBase.ReturnCode.ConvergenceFailure && tot.window == 0)
        _status_warn(rt, h[STATUS_WINDOW], h[STATUS_CAUSE], code)
    end
    rt.status = _worse(rt.status, code)
    return rt.status
end
function _add_counts!(acc, d)
    acc.solves += d[1]
    acc.budget += d[2]
    acc.floor += d[3]
    acc.newton_budget += d[4]
    return nothing
end
@noinline function _clamp_warn(@nospecialize(rt), h)
    tot = rt.totals
    tot.clamped = true
    Exec.VERBOSE[] || return nothing
    s = length(rt.keys) == 1 ? "" : "s"
    w = length(h) >= 9 && h[9] != 0 ? Int(h[9]) : tot.windows
    rt.alg isa QuasiSteady && return @warn string(
        "field", s, " ", join(("`$k`" for k in rt.keys), ", "),
        ": a local growth `∂f/∂c > 0` in ", window_text(rt, max(w, 1)),
        " makes the steady solve indefinite, so it was ",
        "left out of the operator; a growing field's steady state is unstable or not \
            unique: step it with `BackwardEuler`"
    )
    @warn string(
        "field", s, " ", join(("`$k`" for k in rt.keys), ", "),
        ": the implicit shift was clamped in ",
        window_text(rt, max(w, 1)), " (a local growth `∂f/∂c` above `1/(2h)` that the \
            substep count did not see), so ",
        "its one Newton step is not the ", _stepname(rt.alg),
        " step; a larger `nlsolve = LatticeNewton(; max_iter = k)` checks the step at \
            every substep, or ",
        "more substeps (`substeps = n`) keep the growth below the shift"
    )
    return nothing
end
# the method's step in messages ("Backward Euler", "Crank–Nicolson"; another by its name)
function _stepname(a)
    if a isa BackwardEuler
        return "Backward Euler"
    elseif a isa CrankNicolson
        return "Crank–Nicolson"
    else
        return string(nameof(typeof(a)))
    end
end
# the warnings of a read (cold: once per runtime and run); a function barrier, compiled once
# for every runtime type
@noinline function _status_warn(@nospecialize(rt), window, cause, code)
    tot = rt.totals
    fs = join(("`$k`" for k in rt.keys), ", ")
    s = length(rt.keys) == 1 ? "" : "s"
    if code != SciMLBase.ReturnCode.ConvergenceFailure && !tot.warned &&
            (tot.budget > 0 || tot.newton_budget > 0)
        tot.warned = true
        what = if tot.budget > 0
            (
                "the linear solve reached its budget $(tot.budget) \
                    time$(tot.budget == 1 ? "" : "s")",
                status_route(rt.alg, :budget; coupled = coupled_solve(rt.cache)),
            )
        else
            (
                string(
                    "the Newton iteration", if (k = newton_count(rt.cache)) === nothing
                        ""
                    else
                        " (`max_iter = $k`)"
                    end,
                    " reached its budget $(tot.newton_budget) \
                        time$(tot.newton_budget == 1 ? "" : "s")"
                ),
                status_route(rt.alg, :newton_budget),
            )
        end
        Exec.VERBOSE[] &&
            @warn "field$s $fs: $(what[1]) so far (the result is accepted, " *
            "`ReturnCode.Success`, and counted in `stats`); $(what[2]) removes this warning"
    end
    if code == SciMLBase.ReturnCode.ConvergenceFailure && tot.window == 0
        tot.window = max(Int64(window), 1)
        why = [r for (bit, r) in STATUS_CAUSES if tot.cause & bit != 0]
        if isempty(why) && tot.newton_budget > 0
            k = newton_count(rt.cache)
            push!(
                why,
                string(
                    "the Newton iteration",
                    k === nothing ? "" : " (`nlsolve = LatticeNewton(; max_iter = $k)`)",
                    " reached its budget"
                )
            )
            route = status_route(rt.alg, :newton_budget)
        else
            route = status_route(
                rt.alg, :failure, tot.cause;
                coupled = coupled_solve(rt.cache)
            )
        end
        Exec.VERBOSE[] &&
            @warn "field$s $fs: the solve failed in $(window_text(rt, tot.window))" *
            "$(isempty(why) ? "" : " (" * join(why, "; ") * ")"), " *
            "`ReturnCode.ConvergenceFailure`: the run stops; $route"
    end
    return nothing
end
"""
    window_text(rt, w) -> String

Window `w` of runtime `rt` (the status word's entry [2]: the `w`-th window since the bind or
the last [`clear_status!`](@ref)) in words: `rt.totals.where(w, t1)` when the front end set
it (`t1` the start time of the first window), else "window w (t = …)", `t` the window's
start time.
"""
function window_text(rt::GroupRuntime, w::Integer)
    rt.totals.where === nothing || return rt.totals.where(w, rt.totals.t1)
    t = rt.totals.t1 + (w - 1) * rt.dt
    return string("window ", w, " (t = ", round(t; sigdigits = 6), ")")
end

# the worse of two codes: a failure over `StalledSuccess` over `Success`
function _rank(c::SciMLBase.ReturnCode.T)
    if c == SciMLBase.ReturnCode.Success
        return 0
    elseif c == SciMLBase.ReturnCode.StalledSuccess
        return 1
    else
        return 2
    end
end
_worse(a::SciMLBase.ReturnCode.T, b::SciMLBase.ReturnCode.T) = _rank(b) > _rank(a) ? b : a

# the substeps of a window: the explicit step launches, one per substep (a group with no
# state: its aux kernels once, no slot to swap); an implicit cache runs its own
# (implicit.jl)
function _substeps!(::Any, rt::GroupRuntime, t::Float64, h::Float64, k::Int, n::Integer)
    st = rt.store
    n == 0 && rt.steps[_parity(rt)]((t, h, k))
    for j in 0:(n - 1)
        rt.steps[_parity(rt)]((t + j * h, h, k))
        _swap!(st.cur, rt.swaps)
    end
    return nothing
end
function _swap!(cur, swaps)
    for f in swaps
        cur[f] = 3 - cur[f]
    end
    return nothing
end
_slot1!(::Tuple{}, cur, swaps, i) = nothing
function _slot1!(copies::Tuple, cur, swaps, i)
    f = swaps[i]
    if cur[f] == 2
        _copy!(copies[1][1], copies[1][2])
        cur[f] = 1
    end
    return _slot1!(Base.tail(copies), cur, swaps, i + 1)
end
# slot 2 into slot 1: the two slots of a field never alias, so a host copy is a loop (Base's
# `copyto!` of a view checks aliasing and may copy the source first); a device copy is one
# kernel (a device `copyto!` may wait for the device)
_copy_body!(i, d, s) = (@inbounds d[i] = s[i]; nothing)       # i ≤ length(s) == length(d)
function _copy!(d::AbstractArray, s::AbstractArray)
    length(d) == length(s) ||
        throw(DimensionMismatch("slot 1 has $(length(d)) values, slot 2 $(length(s))"))
    Exec.launch!(KA.get_backend(d), _copy_body!, length(s), (d, s))
    return d
end
function _copy!(
        d::Union{Array, SubArray{<:Any, 1, <:Array}}, s::Union{
            Array, SubArray{<:Any, 1, <:Array},
        }
    )
    # bounds: i ∈ eachindex(d, s), which checks that both have the same axes
    @inbounds for i in eachindex(d, s)
        d[i] = s[i]
    end
    return d
end

# The node-value clamp, now: each masked field (`NodeValueRule`) takes its value at the
# sites its mask marks, `u = ifelse(mask, v, u)` on the current slot, and nothing else
# changes (no launch of the step plan, no slot swap). It runs after init (before the t0
# save), after every input write and parameter change, and after the masks at the start of
# every step, so a step's first fluxes read the clamped values, for rate and map programs
# alike. The step kernels still store the value at masked sites (the store-side rule). The
# masked fields of program `prog` among the field ids `ids` on store `st`, as a tuple (one
# entry per `NodeValueRule`: the field's buffers, its id, its mask array and the value), so
# the clamp is type-stable and allocation-free on the host (the store's own arrays are
# untyped) (a rule whose value is a field, `vfield`, carries that field's array: each masked
# site takes its own value)
function _clamps(prog::Program, st::FieldStore, ids = Set(eachindex(prog.fields)))
    return Tuple(
        (
            Tuple(st.bufs[r.field]), Int(r.field),
            array(st, prog.masks[r.mask].field, :cur), r.value,
            r.vfield == 0 ? nothing : array(st, r.vfield, :cur),
        )
            for r in prog.rules if r isa NodeValueRule && r.field in ids
    )
end
function _clamp!(clamps::Tuple, st::FieldStore, p)
    # (a homogeneous tuple: one masked field type)
    for c in clamps
        _clamp_one!(c, st, p)
    end
    return nothing
end
function _clamp_one!((bufs, id, m, c, vf), st::FieldStore, p)
    u = length(bufs) == 1 ? bufs[1] : bufs[st.cur[id]]
    v = convert(eltype(u), c.param == 0 ? c.value : c.value * p[c.param])
    if vf === nothing
        KA.get_backend(u) isa KA.CPU ? _clamp_host!(u, m, v) : _clamp_device!(u, m, v)
    else
        if KA.get_backend(u) isa KA.CPU
            _clamp_host!(u, m, v, vf)
        else
            _clamp_device!(u, m, v, vf)
        end
    end
    return nothing
end
function _clamp_host!(u, m, v)                        # host: a loop, no allocation
    n = length(m)
    length(u) % n == 0 ||
        throw(DimensionMismatch("a masked field has $(length(u)) values for $n mask sites"))
    for j in 0:(div(length(u), n) - 1), i in 1:n
        m[i] != 0 && (u[j * n + i] = v)
    end
    return nothing
end
# a value field: each masked site takes `v` times its own value (one value per site)
function _clamp_host!(u, m, v, vf)
    n = length(m)
    length(u) % n == 0 && length(vf) == n ||
        throw(DimensionMismatch("a masked field has $(length(u)) values for $n mask sites"))
    for j in 0:(div(length(u), n) - 1), i in 1:n
        m[i] != 0 && (u[j * n + i] = v * vf[i])
    end
    return nothing
end
# The clamp fused into the mask launch on a device: a separate clamp kernel was one more
# launch per step, about 4 % of a warm Merks2006 MCS at 100² on ROCm (paired A/B). A mask
# launch that writes the mask of a masked field gets the field's current buffer and the mask
# as an extra lane of its arrays, and its body, after it has stored the masks of a site,
# stores the masked value at that site where the mask holds (`_MaskClamp`): the same values
# as the separate clamp (the mask kernels read neither field, and each work item clamps only
# its own site), with no launch and no IR change.
struct _MaskClamp{F, V}
    body::F
    # the masked value of each fused clamp, in its field's element type
    vals::V
end
function (w::_MaskClamp)(x, S, P, G)
    w.body(x, S, P, G)
    i = _site(x, G.dims[1])
    i == 0 || _clamp_site!(last(S), w.vals, i)
    return nothing
end
# the site of a work item: a linear item is its site (the linear wrapper guards `i ≤ n`); a
# Cartesian item `x` (1-based) is its site in column-major order, 0 past an axis (padding)
_site(x::Integer, dims) = Int(x)
function _site(x::NTuple{N, Int}, dims) where {N}
    i, s = 0, 1
    for d in 1:N
        x[d] > dims[d] && return 0
        i += (x[d] - 1) * s
        s *= Int(dims[d])
    end
    return i + 1
end
# the fused clamps at site `i` (one masked value per clamp; each component of a field)
function _clamp_site!(lane, vals, i)
    for j in 1:length(lane)
        u, m = lane[j]
        n = length(m)
        # i ≤ n = length(m) (the launch covers the sites)
        @inbounds if m[i] != 0
            for q in 0:(div(length(u), n) - 1)
                u[q * n + i] = vals[j]          # q * n + i ≤ length(u)
            end
        end
    end
    return nothing
end
# The masked-field rules of the group's fields `ids` (the order of `_clamps`), with the mask
# launch of plan `ip` that writes each one's mask (0: none)
# (a rule with a value field is not fused: its clamp reads the value field, a kernel of its
# own)
function _mask_rules(prog::Program, ip::StepPlan, ids)
    rs = [r for r in prog.rules if r isa NodeValueRule && r.field in ids]
    return [
        (
            r,
            something(
                findfirst(
                    l -> prog.masks[r.mask].field in
                        writes(l.kernel.kernel), ip.launches
                ), 0
            ),
        )
            for r in rs
    ]
end
# the rules a device fuses: those whose mask a launch of the plan writes over the site
# space, when every clamp of that launch has the same array and value types (a homogeneous
# lane)
function _fused_rules(prog::Program, ip::StepPlan, st::FieldStore, ids)
    rl = _mask_rules(prog, ip, ids)
    out = Int[]
    for (li, l) in enumerate(ip.launches)
        js = [j for (j, (r, w)) in enumerate(rl) if w == li && r.vfield == 0]
        isempty(js) && continue
        m1 = array(st, prog.masks[rl[js[1]][1].mask].field, :cur)
        prod(leveldims(prog, l.kernel.space.level)) == length(m1) || continue
        function typ(j)
            return (
                typeof(st.bufs[rl[j][1].field][1]),
                typeof(array(st, prog.masks[rl[j][1].mask].field, :cur)),
            )
        end
        all(j -> typ(j) == typ(js[1]), js) && append!(out, js)
    end
    return out
end
# `fuse(spec, cur)` of `BoundStep` for the mask plan: the lane and the body wrapper of a
# launch that writes fused masks, at the slots `cur` and the masked values at parameters `p`
function _mask_fuse(prog::Program, st::FieldStore, p, ids)
    return function (l, cur)
        rs = [
            r
                for r in prog.rules
                if r isa NodeValueRule && r.field in ids && r.vfield == 0 &&
                prog.masks[r.mask].field in writes(l.kernel.kernel)
        ]
        isempty(rs) && return nothing
        m1 = array(st, prog.masks[rs[1].mask].field, :cur)
        prod(leveldims(prog, l.kernel.space.level)) == length(m1) || return nothing
        function cell(r)
            b = st.bufs[r.field]
            return (
                length(b) == 1 ? b[1] : b[cur[r.field]],
                array(st, prog.masks[r.mask].field, :cur),
            )
        end
        lane = Tuple(cell(r) for r in rs)
        all(c -> typeof(c) == typeof(lane[1]), lane) || return nothing
        vals = Tuple(
            convert(
                eltype(c[1]), if r.value.param == 0
                    r.value.value
                else
                    r.value.value * p[r.value.param]
                end
            )
                for (c, r) in zip(lane, rs)
        )
        return (lane, f -> _MaskClamp(f, vals))
    end
end

# a device: one kernel per field (components: the mask holds for each one), compiled with
# the group's launches (`compile!` of the runtime: a caller that compiles on a host task, as
# `PottsProblem` does on a device, compiles it there, not at the first step)
function _clamp_body!(i, u, m, v, n)
    # i ≤ length(u), and (i - 1) % n + 1 ≤ n = length(m)
    @inbounds if m[(i - 1) % n + 1] != 0
        u[i] = v
    end
    return nothing
end
function _clamp_device!(u, m, v)
    length(u) % length(m) == 0 ||
        throw(DimensionMismatch("a masked field has $(length(u)) values for $(length(m)) \
            mask sites"))
    Exec.launch!(KA.get_backend(u), _clamp_body!, length(u), (u, m, v, length(m)))
    return nothing
end
function _clamp_field_body!(i, u, m, v, vf, n)
    j = (i - 1) % n + 1
    # i ≤ length(u), and j ≤ n = length(m) = length(vf)
    @inbounds if m[j] != 0
        u[i] = v * vf[j]
    end
    return nothing
end
function _clamp_device!(u, m, v, vf)
    length(u) % length(m) == 0 && length(vf) == length(m) ||
        throw(DimensionMismatch("a masked field has $(length(u)) values for $(length(m)) \
            mask sites"))
    Exec.launch!(KA.get_backend(u), _clamp_field_body!, length(u), (u, m, v, vf, length(m)))
    return nothing
end

"""
    compile!(backend, rt::GroupRuntime)

Compile every device kernel a step of `rt` launches before its first step: the step
launches, the mask launches, the clamp of each masked field and the slot-1 copies
(`Exec.compile!`: compile-only launches, which write nothing), and an implicit runtime's
launches (the operator program, the residuals, the shift, update, status and Newton-check
bodies, the right sides and history copies, and the solver's rebuild, lift and solve plans,
by `compile_cache!` in compile mode). Nothing on the host executor.
"""
function compile!(backend, rt::GroupRuntime)
    Exec.ishost(backend) && return nothing
    # one parallel set (a host task per kernel, `Exec.compile_all!`): the launches, then the
    # clamps and the copies as compile jobs
    jobs = Any[x.launch for x in rt.steps[1].launches]
    rt.masks === nothing || append!(jobs, Any[x.launch for x in rt.masks[1].launches])
    for (bufs, _, m, c, vf) in rt.stepclamps
        u = bufs[1]
        v = convert(eltype(u), c.param == 0 ? c.value : c.value * rt.p[c.param])
        if vf === nothing
            push!(jobs, () -> Exec.compile!(backend, _clamp_body!, (u, m, v, length(m))))
        else
            push!(
                jobs, () -> Exec.compile!(
                    backend, _clamp_field_body!, (
                        u, m, v, vf, length(m),
                    )
                )
            )
        end
    end
    for (d, s) in rt.copies
        push!(jobs, () -> Exec.compile!(backend, _copy_body!, (d, s)))
    end
    rt.cache isa ImplicitCache && push!(jobs, () -> compile_cache!(rt.cache, rt))
    Exec.compile_all!(backend, jobs)
    return nothing
end
