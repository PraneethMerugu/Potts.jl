# The shared group layer (F2 design §2.2, §2.6). A field group is described once, by its
# `GroupSpec` (the IR boundary: plain data and compiled functions, no Symbolics), made
# numerical by a `FieldGroup` (its semantic program and its plans, by update and value type),
# and stepped by a `GroupRuntime` bound to a store's arrays (`bind_group`, `advance!`).
# Both front ends step through it: B's `FieldProblem` and A's `CorePotts.FieldPhase`.

"""
    GroupSpec

The description of one field group, the same for both front ends (F2 design §2.2):

- `rate`: the group's rate program before the semantic passes (`rate:c` kernels store the
  rate in a scratch field `∂c`; `map:`, `aux:` and `mask:` kernels as written): a
  [`FieldGroup`](@ref) fuses each algorithm's update into it
  ([`fuse_update`](@ref LatticeFields.Compile.fuse_update));
- `state`: the keys of the group's state fields, in the PDESystem's dvs order;
- `external`: the fields of other groups the group reads (from their arrays);
- `params`, `tables`, `inputs`: the names of the parameter slots, the table keys and the
  input keys of the program;
- `init`: the kernels that run at a step's start (the masks of masked conditions);
- `kind`: `:rate` or `:map`;
- `clock`: the period of the discretization's clock, or `nothing` (F2-08c);
- `stability`: the front end's stability bound (a function of the raw parameters);
- `texts`: `route`, how to give a count in this front end, and `terms`, the terms the bound
  does not see in the user's words;
- `linearity`: the front end's linearity classes, carried for operator extraction (F3).
"""
struct GroupSpec{N}
    rate::Program{N}
    state::Vector{String}
    external::Vector{String}
    params::Vector{String}
    tables::Vector{String}
    inputs::Vector{String}
    init::Vector{String}
    kind::Symbol
    clock::Union{Nothing, Float64}
    stability::Any
    texts::@NamedTuple{route::String, terms::Vector{String}}
    linearity::Any
end
function GroupSpec(rate::Program{N}; state, external = String[], params = String[], tables = String[],
        inputs = String[], init = String[], kind::Symbol, clock = nothing, stability = p -> NaN,
        route = "ExplicitEuler(; dt, substeps = n)", terms = String[], linearity = nothing) where {N}
    kind in (:rate, :map) || throw(ArgumentError("kind must be :rate or :map; got $(repr(kind))"))
    return GroupSpec{N}(rate, collect(String, state), collect(String, external), collect(String, params),
        collect(String, tables), collect(String, inputs), collect(String, init), kind,
        clock === nothing ? nothing : Float64(clock), stability, (; route = String(route), terms = collect(String, terms)),
        linearity)
end

"""
    FieldGroup(spec; alg)

The numerical group of `spec`: for each algorithm, the semantic program of its update fused
into `spec.rate` ([`group_program`](@ref): `fuse_update(spec.rate, update_rule(alg))`, an IR
pass with no symbolic step, made once per [`update_key`](@ref)), and its plans, planned and
emitted once per `(update_key(alg), value type, kernels)` and shared by every problem and
runtime made from it (the plans of `ExplicitEuler(; dt = 0.1)` and `ExplicitEuler(; dt = 0.2)`
are one). `program` is the program of `alg` (the default algorithm of the group's kind:
`ExplicitEuler()` for rates, `ExplicitMap()` for maps); every algorithm's program has the
same fields, kernels and rules, so one store serves them all.
"""
struct FieldGroup{N}
    spec::GroupSpec{N}
    program::Program{N}
    programs::Dict{Any, Program{N}}
    plans::Dict{Tuple{Any, Type, Vector{Int}, Vector{Int}}, Tuple{StepPlan{N}, StepPlan{N}}}
end
function FieldGroup(spec::GroupSpec{N}; alg = spec.kind == :map ? ExplicitMap() : ExplicitEuler(),
        program::Program{N} = semantic(fuse_update(spec.rate, update_rule(alg)))) where {N}
    s = program
    return FieldGroup{N}(spec, s, Dict{Any, Program{N}}(update_key(alg) => s),
        Dict{Tuple{Any, Type, Vector{Int}, Vector{Int}}, Tuple{StepPlan{N}, StepPlan{N}}}())
end

"""
    group_program(g, alg) -> Program

The semantic program of group `g` stepped by `alg`: its update fused into the rate program,
once per `update_key(alg)` (thread-safe).
"""
group_program(g::FieldGroup, alg) =
    lock(() -> get!(() -> semantic(fuse_update(g.spec.rate, update_rule(alg))), g.programs, update_key(alg)),
        _PLANS_LOCK)

# the kernels of the group fields `ids` (field ids of state fields), `(init, step)`: the step
# kernels that write one of them, and those that write no state field (auxiliary values, read
# by every group: each group computes them from the current values); the masks of the
# group's own masked conditions (`NodeValueRule`s); every kernel when `ids` holds every state
# field
function _group_kernels(g::FieldGroup, ids)
    s = g.program
    keys = [k.key for k in s.kernels]
    initids = [i for (i, k) in enumerate(keys) if k in g.spec.init]
    stepids = [i for (i, k) in enumerate(keys) if !(k in g.spec.init)]
    stateids = Set(fieldid(s, k) for k in g.spec.state)
    issubset(stateids, ids) && return initids, stepids
    maskfields = Set(s.masks[r.mask].field for r in s.rules if r isa NodeValueRule && r.field in ids)
    return [i for i in initids if any(f -> f in maskfields, writes(s.kernels[i]))],
           [i for i in stepids if (w = writes(s.kernels[i]); any(f -> f in ids, w) || !any(f -> f in stateids, w))]
end

"""
    group_plans(g, alg, V, backend, options; kernels) -> (init plan, step plan)

The plans of group `g` for algorithm `alg` at value type `V` (once per update, value type and
kernel set; thread-safe).
"""
function group_plans(g::FieldGroup, alg, ::Type{V}, backend, o::CompileOptions;
        kernels = _group_kernels(g, Set(fieldid(g.program, k) for k in g.spec.state))) where {V}
    s = group_program(g, alg)
    initids, stepids = kernels
    return lock(_PLANS_LOCK) do
        get!(g.plans, (update_key(alg), V, initids, stepids)) do
            opts = _options(o, V, backend)
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
    group_loops(parts) -> Vector{Vector{Int}}

The loops of the group read graph of `parts` (from [`lagged_coupling`](@ref)): per group, the
groups of its strongly connected component, itself included, when that holds more than one
group; else empty (the group is in no loop). Group `g` reads group `h` when a term of `g` that
the bound sees reads a field of `h`; a group with a term the bound cannot see that reads another
field (`unseen`) reads every other group. Groups outside every loop are block triangular to the others: each is
stable under its own count, and the lag between groups only adds an O(window) source error.
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

"""
    GroupRuntime

One group bound to a store's arrays at parameters `p` (F2 design §2.6): the mask launches
and the step launches at both slot parities, the clamps of its masked fields, the copies that
bring its fields back to slot 1 (`ends_in = :slot1`), its substep count `n` and window `dt`,
the algorithm's cache (`alg_cache`) and the status of its last step. Made by
[`bind_group`](@ref), stepped by [`advance!`](@ref).

`pending` is the host task that compiles the launches on a device (`nothing` when there is
none): a front end awaits it before the first step. `host` is the front end's own record of
the binding (front end A: the parameter object and the state arrays it was bound from).
"""
mutable struct GroupRuntime{ST <: FieldStore, A, B, M, CL, CP, PV, S, H}
    store::ST
    alg::A
    init::Any                           # the init plan (masks), for `rebind!`
    step::Any                           # the step plan, for `rebind!`
    steps::NTuple{2, B}
    masks::M                            # the mask launches at both slot parities, or nothing
    clamps::CL                          # the masked fields' arrays and values (`_clamps`)
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
    clamp_at_start::Bool                # F2-08a: front end A keeps its step without the clamp
    fixed_time::Bool                    # F2-08a: front end A holds `t` over its substeps
end

# the current slots a launch of the group binds at slot parity `parity`: the group's fields
# at `parity`, every other field at its own slot (slot 1 for the fields of other groups)
_cur(st::FieldStore, swaps, parity, all_state::Bool) =
    all_state ? fill(parity, length(st.cur)) : [f in swaps ? parity : st.cur[f] for f in eachindex(st.cur)]

function _bind_steps(backend, prog, sp::StepPlan, st, p, swaps, all_state, c)
    return (BoundStep(backend, prog, sp, st, p; cur = _cur(st, swaps, 1, all_state), c),
        BoundStep(backend, prog, sp, st, p; cur = _cur(st, swaps, 2, all_state), c))
end
_bind_masks(backend, prog, ip::StepPlan, st, p, swaps, all_state, c) =
    isempty(ip.launches) ? nothing : _bind_steps(backend, prog, ip, st, p, swaps, all_state, c)

"""
    bind_group(g, alg, store, p; fields = g.spec.state, n, dt, c, ends_in = :parity, backend,
               options) -> GroupRuntime

Bind the fields `fields` of group `g` (all of its state by default) to the arrays of `store`
at parameters `p` (the vector is shared: the driver updates it in place before `rebind!`), to
step with algorithm `alg` in `n` substeps per window `dt`. `ends_in = :parity` leaves the
fields in the slot their last substep wrote (one group: the slots alternate); `:slot1` copies
them back to slot 1 after an odd count, so a group that runs after it reads current values.
"""
function bind_group(g::FieldGroup, alg, st::FieldStore, p; fields = g.spec.state, n::Integer, dt::Real,
        c, ends_in::Symbol = :parity, backend, options::CompileOptions, V::Type, host = nothing,
        clamp_at_start::Bool = true, fixed_time::Bool = false)
    ends_in in (:parity, :slot1) || throw(ArgumentError("ends_in must be :parity or :slot1; got $(repr(ends_in))"))
    prog = group_program(g, alg)
    ids = Set(fieldid(prog, k) for k in fields)
    all_state = issubset(Set(fieldid(prog, k) for k in g.spec.state), ids)
    ip, sp = group_plans(g, alg, V, backend, options; kernels = _group_kernels(g, ids))
    swaps = all_state ? copy(sp.swaps) : Int32[f for f in sp.swaps if f in ids]
    steps = _bind_steps(backend, prog, sp, st, p, swaps, all_state, c)
    masks = _bind_masks(backend, prog, ip, st, p, swaps, all_state, c)
    clamps = _clamps(prog, st, ids)
    copies = Tuple((st.bufs[f][1], st.bufs[f][2]) for f in swaps)
    stab = all_state ? g.spec.stability : restrict_bound(g.spec.stability, collect(String, fields))
    return GroupRuntime(st, alg, ip, sp, steps, masks, clamps, swaps, copies, ends_in, all_state, collect(String, fields), Int(n),
        Float64(dt), stab, p, c, prog, backend, alg_cache(alg, g, st), SciMLBase.ReturnCode.Success, nothing, host,
        clamp_at_start, fixed_time)
end

"""
    rebind!(rt, p)

Bind the runtime's launches to the parameter values `p` (the derived parameters are launch
arguments; nothing recompiles), and drop the algorithm's history ([`reset!`](@ref)). In two
parts for an atomic update of several groups: `rebind_launches(rt, p)` binds (and may throw),
`install_launches!(rt, launches)` installs.
"""
rebind!(rt::GroupRuntime, p) = install_launches!(rt, rebind_launches(rt, p))
rebind_launches(rt::GroupRuntime, p) =
    (_bind_steps(rt.backend, rt.program, rt.step, rt.store, p, rt.swaps, rt.all_state, rt.c),
     _bind_masks(rt.backend, rt.program, rt.init, rt.store, p, rt.swaps, rt.all_state, rt.c))
function install_launches!(rt::GroupRuntime, (steps, masks))
    rt.steps, rt.masks = steps, masks
    reset!(rt)
    return rt
end

"""
    reset!(rt)

Drop the algorithm's history ([`reset_cache!`](@ref) of its cache): called after a state
write (`integ[c] = values`, an input or table write, `reinit!`) and after a rebind.
"""
reset!(rt::GroupRuntime) = (reset_cache!(rt.cache); rt.status = SciMLBase.ReturnCode.Success; nothing)

_parity(rt::GroupRuntime) = isempty(rt.swaps) ? 1 : rt.store.cur[rt.swaps[1]]

# the masked values now, at the parameters the launches are bound to
clamp_now!(rt::GroupRuntime) = (_clamp!(rt.clamps, rt.store, rt.p); nothing)

"""
    advance!(rt, clock, n = rt.n, window = rt.dt) -> ReturnCode.T

One window of the group: with `clock = (t0, k)` (the window's start time and step index),
the masks and the clamp at the window's start (when the group has masked conditions), then
`n` substeps of `h = window / n` at `t0 + j h`, alternating the slot parity; with
`ends_in = :slot1` the fields go back to slot 1 after an odd count. Returns the algorithm's
code for the step (`ReturnCode.Success` for the explicit algorithms), also kept in
`rt.status`. No allocation on the host executor.
"""
function advance!(rt::GroupRuntime, clock::Tuple{Real, Integer}, n::Integer = rt.n, window::Real = rt.dt)
    t = Float64(clock[1])
    h = Float64(window) / n
    st = rt.store
    if rt.masks !== nothing
        rt.masks[_parity(rt)]((t, h))
        rt.clamp_at_start && clamp_now!(rt)     # the values the masks set now (the bound parameters)
    end
    for j in 0:(n - 1)
        rt.steps[_parity(rt)]((rt.fixed_time ? t : t + j * h, h))
        _swap!(st.cur, rt.swaps)
    end
    rt.ends_in === :slot1 && _slot1!(rt.copies, st.cur, rt.swaps, 1)
    rt.status = step_retcode!(rt.cache, rt)
    return rt.status
end
_swap!(cur, swaps) = (foreach(f -> cur[f] = 3 - cur[f], swaps); nothing)
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
    length(d) == length(s) || throw(DimensionMismatch("slot 1 has $(length(d)) values, slot 2 $(length(s))"))
    Exec.launch!(KA.get_backend(d), _copy_body!, length(s), (d, s))
    return d
end
function _copy!(d::Union{Array, SubArray{<:Any, 1, <:Array}}, s::Union{Array, SubArray{<:Any, 1, <:Array}})
    @inbounds for i in eachindex(d, s)
        d[i] = s[i]
    end
    return d
end

# The node-value clamp, now: each masked field (`NodeValueRule`) takes its value at the sites
# its mask marks, `u = ifelse(mask, v, u)` on the current slot, and nothing else changes (no
# launch of the step plan, no slot swap). It runs after init (before the t0 save), after every
# input write and parameter change, and after the masks at the start of every step, so a
# step's first fluxes read the clamped values, for rate and map programs alike (F1). The step
# kernels still store the value at masked sites (the store-side rule).
# The masked fields of program `prog` among the field ids `ids` on store `st`, as a tuple (one
# entry per `NodeValueRule`: the field's buffers, its id, its mask array and the value), so the
# clamp is type-stable and allocation-free on the host (the store's own arrays are untyped)
function _clamps(prog::Program, st::FieldStore, ids = Set(eachindex(prog.fields)))
    return Tuple((Tuple(st.bufs[r.field]), Int(r.field), array(st, prog.masks[r.mask].field, :cur), r.value)
                 for r in prog.rules if r isa NodeValueRule && r.field in ids)
end
_clamp!(clamps::Tuple, st::FieldStore, p) = (foreach(c -> _clamp_one!(c, st, p), clamps); nothing)
function _clamp_one!((bufs, id, m, c), st::FieldStore, p)
    u = length(bufs) == 1 ? bufs[1] : bufs[st.cur[id]]
    v = convert(eltype(u), c.param == 0 ? c.value : c.value * p[c.param])
    KA.get_backend(u) isa KA.CPU ? _clamp_host!(u, m, v) : _clamp_device!(u, m, v)
    return nothing
end
function _clamp_host!(u, m, v)                        # host: a loop, no allocation
    n = length(m)
    length(u) % n == 0 || throw(DimensionMismatch("a masked field has $(length(u)) values for $n mask sites"))
    for j in 0:(div(length(u), n) - 1), i in 1:n
        m[i] != 0 && (u[j * n + i] = v)
    end
    return nothing
end
function _clamp_device!(u, m, v)                      # a device: one broadcast per field
    if length(u) == length(m)
        u .= ifelse.(m .!= 0, v, u)
    else                                        # components: the mask holds for each one
        U = reshape(u, length(m), :)
        U .= ifelse.(m .!= 0, v, U)
    end
    return nothing
end
