# Ordering, fusion and step plans (v3 §4.3).

"""
    step_order(p, ids) -> Vector{Vector{Int}}

Topological order over the cross-read graph (A before B when B reads a field A writes);
strongly connected components are Jacobi groups (every member reads the old values of the
two-buffer fields). Ties break by kernel key, so the order is canonical.

A one-buffer field (an aux field `K ~ rhs`) has no old value: inside a Jacobi group its
readers run after its writer (they read the new value, F3-02). The members of a group are
ordered by these reads (ties by key); only a cycle of one-buffer reads (fields that define each
other within one step) is a read cycle, refused.
"""
function step_order(p::Program, ids::Vector{Int})
    ks = p.kernels
    w = Dict{Int32, Int}()
    for i in ids, f in writes(ks[i])

        haskey(w, f) &&
            irerror("field `", p.fields[f].key, "` is written by kernels `", ks[w[f]].key,
                "` and `", ks[i].key, "` in one step")
        w[f] = i
    end
    succ = Dict(i =>
                    sort!(unique!([w[f] for f in reads(ks[i]) if haskey(w, f) && w[f] != i]))
    for i in ids)
    # Tarjan's strongly connected components on the reversed edges (reader -> writer).
    index, low, onstack, stack, comps = Dict{Int, Int}(),
    Dict{Int, Int}(), Set{Int}(), Int[], Vector{Int}[]
    function strong(v)
        index[v] = low[v] = length(index)
        push!(stack, v)
        push!(onstack, v)
        for u in succ[v]
            haskey(index, u) ? (u in onstack && (low[v] = min(low[v], index[u]))) :
            (strong(u); low[v] = min(low[v], low[u]))
        end
        low[v] == index[v] || return
        c = Int[]
        while true
            u = pop!(stack)
            delete!(onstack, u)
            push!(c, u)
            u == v && break
        end
        push!(comps, sort!(c; by = i -> ks[i].key))
    end
    foreach(v -> haskey(index, v) || strong(v), sort(ids; by = i -> ks[i].key))
    for (n, c) in enumerate(comps)
        length(c) > 1 && (comps[n] = _one_buffer_order(p, c, w))
    end
    return comps   # writers precede readers: Tarjan emits sinks of reader->writer edges first
end

# The members `c` (sorted by key) of a Jacobi group in the order of their one-buffer reads: a
# reader of a one-buffer field after its writer, ties by key (Kahn's algorithm); a cycle of
# one-buffer reads is refused, naming the fields on it
function _one_buffer_order(p::Program, c::Vector{Int}, w::Dict{Int32, Int})
    ks = p.kernels
    deps = Dict(i => sort!(unique!([w[f] for f in reads(ks[i])
                                    if haskey(w, f) && w[f] != i && w[f] in c && p.fields[f].buffers == 1])) for i in c)
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
            f = first(f for i in cyc for f in reads(ks[i])
                      if haskey(w, f) && w[f] in cyc && w[f] != i && p.fields[f].buffers == 1)
            irerror("the fields ", join(sort!(unique!([p.fields[g].key for j in cyc for g in writes(ks[j])])), ", "),
                " define each other within one step (a read cycle: each reads another's new value); an ",
                "algebraic field cannot depend on itself through other fields: break the cycle ",
                "(in the IR, field `", p.fields[f].key, "` would need buffers = 2)")
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
    reason::Symbol            # :cost | :illegal | :space | :debug
    t_fused::Float64
    t_split::Float64
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
                return (:illegal,
                    string("`", ks[k].key, "` reads `", p.fields[a.field].key,
                        "` written by `", ks[g].key, "` at offset ", a.offset.a))
        end
        for f in writes(ks[k])
            f in wg && return (:illegal, "both write `$(p.fields[f].key)`")
            p.fields[f].buffers == 1 &&
                any(a -> a.field == f && !zero_offset(a), ks[g].accesses) &&
                return (:illegal,
                    string("`", ks[k].key, "` writes `", p.fields[f].key,
                        "` that `", ks[g].key, "` reads at an offset"))
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
            new[j] = forward && src !== nothing && (scc[src[2]] != scc[i] || p.fields[a.field].buffers == 1) && zero_offset(a) &&
                     a.comp.cond == 0 ? _rounded!(b, p, a.field, src[1]) :
                     copy_node!(
                b, k, j, Int32[new[x] for x in args(k, n)], (new, identity, identity))
        end
        for s in k.stores
            push!(b.stores, Store{N}(s.access, new[s.value], s.law))
            out[(s.access.field, s.access.comp.a)] = (new[s.value], i)
        end
        append!(b.reductions, (Reduction(r.op, new[r.value], r.target)
        for r in k.reductions))
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
"""
struct StepPlan{N}
    launches::Vector{LaunchSpec{N}}
    swaps::Vector{Int32}
    decisions::Vector{FusionDecision}
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
    return strategy == :cartesian ? (N == 3 ? (64, 2, 2) : N == 2 ? (64, 4) : (256,)) :
           (256,)
end

"""
    plan(p, ids = all kernels; options, cost) -> StepPlan

Order the kernels of one step, fuse by the cost model (`t_fused < Σ t_split`; legality first,
every split reported), lower each launch and bind buffers. Debug mode never fuses.
"""
function plan(p::Program{N}, ids::Vector{Int} = collect(eachindex(p.kernels));
        options::CompileOptions = CompileOptions(), cost::CostModel = CostModel(),
        stages = LOWERING, fuse::Bool = !options.debug, merge::M = merge_kernels) where {
        N, M}
    comps = step_order(p, ids)
    scc = Dict(i => c for (c, comp) in enumerate(comps) for i in comp)
    seq = reduce(vcat, comps; init = Int[])
    ws = working_set(p, [traffic(p, p.kernels[i]) for i in seq])
    groups, decisions = Vector{Int}[], FusionDecision[]
    for i in seq
        if isempty(groups)
            push!(groups, [i])
            continue
        end
        g = groups[end]
        names = [p.kernels[j].key for j in g]
        blk = fuse ? fusion_blocker(p, g, i, scc) : (:debug, "fusion off (debug mode)")
        if blk !== nothing
            push!(decisions, FusionDecision(
                names, p.kernels[i].key, false, blk[1], NaN, NaN, blk[2]))
            push!(groups, [i])
            continue
        end
        mk = merge_kernels(p, [g; i], scc)
        tm = traffic(p, mk)
        lim = limit_blocker(cost, mk, tm)
        if lim !== nothing
            push!(decisions, FusionDecision(
                names, p.kernels[i].key, false, :limit, NaN, NaN, lim))
            push!(groups, [i])
            continue
        end
        tf = modeled_time(cost, N, tm, ws)
        ts = modeled_time(cost, N, traffic(p, merge_kernels(p, g, scc)), ws) +
             modeled_time(cost, N, traffic(p, p.kernels[i]), ws)
        push!(decisions, FusionDecision(
            names, p.kernels[i].key, tf < ts, :cost, tf, ts, ""))
        tf < ts ? push!(g, i) : push!(groups, [i])
    end
    launches = LaunchSpec{N}[]
    written = Dict{Int32, Int}()
    for g in groups
        k = merge(p, g, scc)
        legality(with_kernels(p, [k]))
        ck = compile_kernel(p, k, options; stages)
        bind = [[(id,
                     role == :cur && haskey(written, id) &&
                     all(i -> scc[i] != written[id], g) ?
                     :next : role) for (id, role) in lane] for lane in ck.args]
        push!(launches,
            LaunchSpec{N}(ck, [p.kernels[i].key for i in g], bind,
                workgroup(N, ck.strategy), _ndrange(p, k, ck.strategy), true))
        foreach(i -> foreach(f -> written[f] = scc[i], writes(p.kernels[i])), g)
    end
    nd = Dict{String, Set{Tuple}}()
    foreach(l -> push!(get!(nd, l.kernel.hash, Set{Tuple}()), l.ndrange), launches)
    launches = [LaunchSpec{N}(l.kernel, l.members, l.bind, l.workgroup, l.ndrange,
                    length(nd[l.kernel.hash]) == 1) for l in launches]
    swaps = sort!([f for f in keys(written) if p.fields[f].buffers == 2])
    return StepPlan{N}(launches, swaps, decisions)
end

"""
The field report: one line per fusion decision with its modeled times.
"""
function field_report(io::IO, sp::StepPlan)
    for d in sp.decisions
        println(io, d.merged ? "fuse  " : "split ",
            join(d.group, "+"), " | ", d.candidate, "  ",
            d.reason, d.reason == :cost ?
                      string(" fused=", round(d.t_fused * 1e6; digits = 2),
                "µs split=", round(d.t_split * 1e6; digits = 2), "µs") :
                      string(": ", d.detail))
    end
    return nothing
end
