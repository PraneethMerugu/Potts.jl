# The hard resource limit of a fused kernel: the backend's kernel-argument budget. It blocks
# a fusion like a legality rule; it is not a cost.

"""
The distinct arrays kernel `k` binds, as `(field, component, absolute level, role)` with
role `:r`, `:w` or `:rw` (a one-buffer field read and written in place is one array).
"""
function kernel_arrays(p::Program, k::Kernel)
    arr = Set{Tuple{Int32, Int16, Int8, Symbol}}()
    add!(f, comp, rel, rw) = push!(arr, (f, comp, Int8(k.space.level + rel), rw))
    foreach(
        a -> add!(a.field, a.comp.a, a.level, :r),
        (k.accesses[x.imm] for x in k.nodes if x.op == LOAD)
    )
    k.space.kind == MASKED && add!(p.masks[k.space.mask].field, Int16(1), 0, :r)
    for s in k.stores
        f = p.fields[s.access.field]
        key = (s.access.field, s.access.comp.a, Int8(k.space.level), :r)
        if f.buffers == 1 && key in arr
            delete!(arr, key)
            push!(arr, (key[1], key[2], key[3], :rw))
        else
            add!(s.access.field, s.access.comp.a, 0, :w)
        end
        f.buffers == 2 && k.space.kind != FULL &&
            add!(s.access.field, s.access.comp.a, 0, :r)
    end
    return arr
end

"""
The array arguments of a merged kernel: its arrays and its tables.
"""
array_arguments(p::Program, k::Kernel) = length(kernel_arrays(p, k)) + length(k.tables)

"""
The kernel-argument limit of a backend: its budget in bytes (`nothing`: none) and the size
of one array argument.
"""
function argument_limit(backend)
    budget = Exec.kernel_argument_bytes(backend)
    return budget === nothing ? (nothing, 0) : (budget, Exec.array_argument_bytes(backend))
end

"""
Why a merged kernel breaks the argument budget `(budget, per_array)` (`nothing` if it does
not).
"""
function limit_blocker(p::Program, k::Kernel, (budget, per_array))
    budget === nothing && return nothing
    na = array_arguments(p, k)
    na * per_array > budget || return nothing
    return string(
        na, " array arguments of ", per_array, " B exceed the backend's kernel-argument \
            budget of ", budget, " B"
    )
end
