# Ordering, fusion and step plans.

"""
    step_order(p, ids) -> Vector{Vector{Int}}

Topological order over the cross-read graph (A before B when B reads a field A writes);
strongly connected components are Jacobi groups (every member reads the old values of the
two-buffer fields). Ties break by kernel key, so the order is canonical.

A one-buffer field (an aux field `K ~ rhs`) has no old value: inside a Jacobi group its
readers run after its writer (they read the new value). The members of a group are
ordered by these reads (ties by key); only a cycle of one-buffer reads (fields that define
each other within one step) is a read cycle, refused.
"""
function step_order(p::Program, ids::Vector{Int})
    ks = p.kernels
    w = Dict{Int32, Int}()
    for i in ids, f in writes(ks[i])
        haskey(w, f) && irerror(
            "field `", p.fields[f].key, "` is written by kernels `", ks[w[f]].key,
            "` and `", ks[i].key, "` in one step"
        )
        w[f] = i
    end
    succ = Dict(
        i =>
            sort!(unique!([w[f] for f in reads(ks[i]) if haskey(w, f) && w[f] != i]))
            for i in ids
    )
    # Tarjan's strongly connected components on the reversed edges (reader -> writer).
    index, low, onstack, stack, comps = Dict{Int, Int}(),
        Dict{Int, Int}(), Set{Int}(), Int[], Vector{Int}[]
    function strong(v)
        index[v] = low[v] = length(index)
        push!(stack, v)
        push!(onstack, v)
        for u in succ[v]
            if haskey(index, u)
                u in onstack && (low[v] = min(low[v], index[u]))
            else
                (strong(u); low[v] = min(low[v], low[u]))
            end
        end
        low[v] == index[v] || return
        c = Int[]
        while true
            u = pop!(stack)
            delete!(onstack, u)
            push!(c, u)
            u == v && break
        end
        return push!(comps, sort!(c; by = i -> ks[i].key))
    end
    foreach(v -> haskey(index, v) || strong(v), sort(ids; by = i -> ks[i].key))
    for (n, c) in enumerate(comps)
        length(c) > 1 && (comps[n] = _one_buffer_order(p, c, w))
    end
    # writers precede readers: Tarjan emits sinks of reader->writer edges first
    return comps
end

# The members `c` (sorted by key) of a Jacobi group in the order of their one-buffer reads:
# a reader of a one-buffer field after its writer, ties by key (Kahn's algorithm); a cycle
# of one-buffer reads is refused, naming the fields on it
function _one_buffer_order(p::Program, c::Vector{Int}, w::Dict{Int32, Int})
    ks = p.kernels
    deps = Dict(
        i => sort!(
            unique!(
                [
                    w[f]
                        for f in reads(ks[i])
                        if haskey(w, f) && w[f] != i && w[f] in c && p.fields[f].buffers ==
                        1
                ]
            )
        ) for i in c
    )
    isempty(Iterators.flatten(values(deps))) && return c
    out, left = Int[], copy(c)
    while !isempty(left)
        j = findfirst(i -> all(d -> d in out, deps[i]), left)
        if j === nothing
            # the cycle: drop the readers no member left depends on, until none is dropped
            cyc = copy(left)
            while (k = findfirst(i -> !any(m -> i in deps[m], cyc), cyc)) !== nothing
                deleteat!(cyc, k)
            end
            f = first(
                f for i in cyc
                    for f in reads(ks[i])
                    if haskey(w, f) && w[f] in cyc && w[f] != i && p.fields[f].buffers == 1
            )
            irerror(
                "the fields ", join(
                    sort!(unique!([p.fields[g].key for j in cyc for g in writes(ks[j])])),
                    ", "
                ),
                " define each other within one step (a read cycle: each reads another's \
                    new value); an ",
                "algebraic field cannot depend on itself through other fields: break the \
                    cycle ",
                "(in the IR, field `", p.fields[f].key, "` would need buffers = 2)"
            )
        end
        push!(out, popat!(left, j))
    end
    return out
end

"""
One fusion decision, printed by the field report.
"""
struct FusionDecision
    group::Vector{String}
    candidate::String
    merged::Bool
    reason::Symbol            # :legal | :illegal | :space | :limit | :off
    detail::String
end

"""
Why `k` cannot join `group` (`nothing` if it can). `jacobi[i]` is the SCC of kernel `i`.
"""
function fusion_blocker(p::Program, group::Vector{Int}, k::Int, scc)
    ks = p.kernels
    ks[k].space == ks[group[1]].space || return (:space, "different iteration space")
    any(i -> ks[i].gate != 0 || !isempty(ks[i].reductions), [group; k]) &&
        return (:space, "a gated or reducing kernel runs alone")
    for g in group
        wg = writes(ks[g])
        for a in ks[k].accesses
            # (a one-buffer field written earlier in the same Jacobi group is read new, as
            # across groups: forwarded at offset 0, else a split)
            a.field in wg && (scc[g] != scc[k] || p.fields[a.field].buffers == 1) &&
                !(zero_offset(a) && a.comp.cond == 0) &&
                return (
                :illegal,
                string(
                    "`", ks[k].key, "` reads `", p.fields[a.field].key,
                    "` written by `", ks[g].key, "` at offset ", a.offset.a
                ),
            )
        end
        for f in writes(ks[k])
            f in wg && return (:illegal, "both write `$(p.fields[f].key)`")
            p.fields[f].buffers == 1 &&
                any(a -> a.field == f && !zero_offset(a), ks[g].accesses) &&
                return (
                :illegal,
                string(
                    "`", ks[k].key, "` writes `", p.fields[f].key,
                    "` that `", ks[g].key, "` reads at an offset"
                ),
            )
        end
    end
    return nothing
end

# A forwarded value goes through the field's lane rounding, as the store and reload would.
function _rounded!(b, p::Program, f, v)
    lane = p.fields[f].storage
    return isfloat(lane) ? cast!(b, cast!(b, v, lane), REAL) : v
end

"""
Merge kernels `ids` (in order) into one; an offset-0 read of an earlier member's output
outside its Jacobi group, or of a one-buffer output inside it, is forwarded from the stored
value (`forward = false` drops the forwarding: a fault the tests inject).
"""
function merge_kernels(p::Program{N}, ids::Vector{Int}, scc; forward::Bool = true) where {N}
    length(ids) == 1 && return p.kernels[ids[1]]
    b = KernelBuilder{N}(buildkeys(p)..., p.kernels[ids[1]].space)
    out = Dict{Tuple{Int32, Int16}, Tuple{Int32, Int}}()
    for i in ids
        k = p.kernels[i]
        new = zeros(Int32, length(k.nodes))
        for j in eachindex(k.nodes)
            n = k.nodes[j]
            a = n.op == LOAD ? k.accesses[n.imm] : nothing
            src = a === nothing ? nothing : get(out, (a.field, a.comp.a), nothing)
            new[j] = if forward && src !== nothing &&
                    (scc[src[2]] != scc[i] || p.fields[a.field].buffers == 1) &&
                    zero_offset(a) &&
                    a.comp.cond == 0
                _rounded!(b, p, a.field, src[1])
            else
                copy_node!(
                    b, k, j, Int32[new[x] for x in args(k, n)], (new, identity, identity)
                )
            end
        end
        for s in k.stores
            push!(b.stores, Store{N}(s.access, new[s.value], s.law))
            out[(s.access.field, s.access.comp.a)] = (new[s.value], i)
        end
        append!(
            b.reductions, (
                Reduction(r.op, new[r.value], r.target)
                    for r in k.reductions
            )
        )
    end
    return finish(b, join((p.kernels[i].key for i in ids), "+"))
end

"""
A launch: the compiled body, its physical buffer bindings and launch configuration.
`bind[l][j]` is `(field or table id, :cur | :next | :table)` for argument `S[l][j]`.
"""
struct LaunchSpec{N}
    kernel::CompiledKernel{N}
    members::Vector{String}
    bind::Vector{Vector{Tuple{Int32, Symbol}}}
    workgroup::Tuple
    ndrange::Tuple            # linear: (sites,); Cartesian: the space's dims
    static::Bool
end

"""
A step: launches in queue order, then host slot swaps of the two-buffer fields written.
`request` holds the arguments of the [`plan`](@ref) call, and `bound` the plans of the same
request at a kernel-argument budget, one per argument signature ([`bound_plan`](@ref)).
"""
struct StepPlan{N}
    launches::Vector{LaunchSpec{N}}
    swaps::Vector{Int32}
    decisions::Vector{FusionDecision}
    request::Any
    bound::Dict{Any, StepPlan{N}}
end

function _ndrange(p, k, strategy)
    strategy == :cartesian && return Int.(leveldims(p, k.space.level))
    n = nsites(p, k.space.level)
    return isempty(k.reductions) ? (n,) : (256 * reduction_blocks(n),)
end
"""
Workgroups of a reducing kernel over `n` sites: one per 256-site block.
"""
reduction_blocks(n::Integer) = cld(Int(n), 256)
function workgroup(N, strategy)
    if strategy == :cartesian
        if N == 3
            return (64, 2, 2)
        elseif N == 2
            return (64, 4)
        else
            return (256,)
        end
    else
        return (256,)
    end
end

"""
    plan(p::Program, ids = eachindex(p.kernels); options = CompileOptions(),
         stages = LOWERING, fuse = options.fuse && !options.debug, merge = merge_kernels,
         budget = nothing, arguments = nothing) -> StepPlan

Order the kernels of one step, fuse every kernel into the current group when that is
legal (every split is reported), lower each launch and bind buffers. With
`options.fuse = false` or the debug mode it never fuses.

A kernel joins the current group unless a fusion blocker (iteration space, a gated or
reducing kernel, a dependency at an offset, a write conflict) or the kernel-argument budget
stops it. With a budget, `arguments(spec)` gives the bytes of the arguments of the launch
`spec` as it is bound
([`Exec.launch_argument_bytes`](@ref LatticeFields.Exec.launch_argument_bytes)), and a
fusion whose launch would pass more than `budget` bytes is split. Each group is checked for
legality and compiled. A launch is static when its kernel runs at one ndrange only, and is
measured as it is bound: static or dynamic.

# Arguments
- `p`: the field program (`LatticeFields.IR.Program`).
- `ids`: the indices of the kernels of `p` to plan.

# Keywords
- `options = CompileOptions()`: the compile options of every launch.
- `stages = LOWERING`: the lowering passes given to the kernel compiler.
- `fuse = options.fuse && !options.debug`: `false` splits every kernel (reason `:off`).
- `merge = merge_kernels`: the function that merges a group into one kernel for
  compilation.
- `budget = nothing`: the kernel-argument budget in bytes; `nothing` is no budget.
- `arguments = nothing`: with a budget, the function `spec -> bytes` of a launch's
  arguments; required when `budget` is given.

# Returns
- A `StepPlan`: the launch descriptions in order, the double-buffered fields to swap after
  the step, and every fusion decision.

See also [`fusion_report`](@ref), [`bound_plan`](@ref).
"""
function plan(
        p::Program{N}, ids::Vector{Int} = collect(eachindex(p.kernels));
        options::CompileOptions = CompileOptions(), stages = LOWERING,
        fuse::Bool = options.fuse && !options.debug, merge::M = merge_kernels,
        budget::Union{Int, Nothing} = nothing, arguments::A = nothing
    ) where {N, M, A}
    budget === nothing || arguments !== nothing || throw(
        ArgumentError(
            "a plan at a kernel-argument budget needs `arguments`, the bytes of a \
                launch's arguments"
        )
    )
    comps = step_order(p, ids)
    scc = Dict(i => c for (c, comp) in enumerate(comps) for i in comp)
    seq = reduce(vcat, comps; init = Int[])
    # the kernels measured with a dynamic ndrange: none at first; a kernel that the plan
    # runs at several ndranges is dynamic, and the plan is made again with it measured so
    # (each launch is measured as it is bound)
    dynamic = Set{String}()
    specs, decisions, written = _fuse_greedy(
        p, seq, scc, fuse, budget, arguments, dynamic, options, stages, merge
    )
    nd = _ndranges(specs)
    while budget !== nothing && !issubset(_several(nd), dynamic)
        union!(dynamic, _several(nd))
        specs, decisions, written = _fuse_greedy(
            p, seq, scc, fuse, budget, arguments, dynamic, options, stages, merge
        )
        nd = _ndranges(specs)
    end
    request = (; program = p, ids, options, stages, fuse, merge)
    return _step_plan(p, specs, nd, decisions, written, request)
end

# the plan of the launches `specs`: static where a kernel runs at one ndrange (`nd`)
function _step_plan(p::Program{N}, specs, nd, decisions, written, request) where {N}
    launches = [
        LaunchSpec{N}(
            l.kernel, l.members, l.bind, l.workgroup, l.ndrange,
            length(nd[l.kernel.hash]) == 1
        ) for l in specs
    ]
    swaps = sort!([f for f in keys(written) if p.fields[f].buffers == 2])
    return StepPlan{N}(launches, swaps, decisions, request, Dict{Any, StepPlan{N}}())
end

# the ndranges each kernel (by hash) runs at in the launches `specs`
function _ndranges(specs)
    nd = Dict{String, Set{Tuple}}()
    foreach(l -> push!(get!(nd, l.kernel.hash, Set{Tuple}()), l.ndrange), specs)
    return nd
end
# the kernels that run at more than one ndrange
_several(nd) = Set(h for (h, r) in nd if length(r) > 1)

# The launches of the kernels `seq` in step order, each fused into the current group unless
# a blocker or the budget stops it, with the decisions and the step that writes each field.
# A launch is measured static unless its kernel is in `dynamic`.
function _fuse_greedy(
        p::Program{N}, seq, scc, fuse, budget, arguments::A, dynamic, options, stages,
        merge::M
    ) where {N, A, M}
    specs, decisions = LaunchSpec{N}[], FusionDecision[]
    # the step that writes each field so far (a field another component of the group
    # writes is read from its next slot)
    written = Dict{Int32, Int}()
    launch(g) = _launch_spec(p, g, scc, written, options, stages, merge, dynamic)
    function close!(g, spec)
        push!(specs, something(spec, launch(g)))
        foreach(i -> foreach(f -> written[f] = scc[i], writes(p.kernels[i])), g)
        return nothing
    end
    g, spec = Int[], nothing
    for i in seq
        if isempty(g)
            push!(g, i)
            continue
        end
        blk = if fuse
            fusion_blocker(p, g, i, scc)
        else
            (:off, "fusion off (`fuse = false` or the debug mode)")
        end
        cand = nothing
        if blk === nothing && budget !== nothing
            cand = launch([g; i])
            bytes = arguments(cand)
            bytes > budget && (
                blk = (
                    :limit,
                    string(
                        "the launch arguments take ", bytes, " B, over the backend's \
                            kernel-argument budget of ", budget, " B"
                    ),
                )
            )
        end
        push!(
            decisions, FusionDecision(
                [p.kernels[j].key for j in g], p.kernels[i].key, blk === nothing,
                something(blk, (:legal, ""))...
            )
        )
        if blk === nothing
            push!(g, i)
            spec = cand
        else
            close!(g, spec)
            g, spec = [i], nothing
        end
    end
    isempty(g) || close!(g, spec)
    return specs, decisions, written
end

# The launch of group `g`: merged, checked for legality, compiled and bound. It is static
# unless its kernel is in `dynamic` (the plan sets the flag of each launch once it knows
# every ndrange); a Cartesian launch is always static.
function _launch_spec(
        p::Program{N}, g, scc, written, options, stages, merge, dynamic
    ) where {N}
    k = merge(p, g, scc)
    legality(with_kernels(p, [k]))
    ck = compile_kernel(p, k, options; stages)
    function rebind(id, role)
        return if role == :cur && haskey(written, id) && all(i -> scc[i] != written[id], g)
            :next
        else
            role
        end
    end
    bind = [[(id, rebind(id, role)) for (id, role) in lane] for lane in ck.args]
    static = ck.strategy == :cartesian || !(ck.hash in dynamic)
    return LaunchSpec{N}(
        ck, [p.kernels[i].key for i in g], bind,
        workgroup(N, ck.strategy), _ndrange(p, k, ck.strategy), static
    )
end

const _BOUND_LOCK = ReentrantLock()

"""
    bound_plan(sp::StepPlan, budget, signature, arguments) -> StepPlan

The plan of `sp`'s request at the kernel-argument budget `budget`, with `arguments(spec)`
the bytes of a launch's arguments as the caller binds it. It is made once per `signature`
(the types that decide the argument sizes) and kept in `sp`; the call is thread-safe.

# Arguments
- `sp`: a plan from [`plan`](@ref).
- `budget::Int`: the budget in bytes.
- `signature`: the key of the argument types.
- `arguments`: the function `spec -> bytes`.

# Returns
- The `StepPlan` at the budget.
"""
function bound_plan(sp::StepPlan, budget::Int, signature, arguments::A) where {A}
    return lock(_BOUND_LOCK) do
        get!(sp.bound, (budget, signature)) do
            r = sp.request
            plan(
                r.program, r.ids; r.options, r.stages, r.fuse, r.merge, budget, arguments
            )
        end
    end
end

"""
    fusion_report(io, plan::StepPlan)

The fusion decisions of a step plan, one line per decision: `fuse` or `split`, the kernels,
the candidate, the reason and, for a split, what blocked the fusion. Part of
`Problems.field_report`, which prints it per field group.

# Arguments
- `io`: the stream to print to.
- `plan`: a step plan from [`plan`](@ref).

# Returns
- `nothing`.
"""
function fusion_report(io::IO, sp::StepPlan)
    for d in sp.decisions
        println(
            io, d.merged ? "fuse  " : "split ",
            join(d.group, "+"), " | ", d.candidate, "  ", d.reason,
            isempty(d.detail) ? "" : string(": ", d.detail)
        )
    end
    return nothing
end
