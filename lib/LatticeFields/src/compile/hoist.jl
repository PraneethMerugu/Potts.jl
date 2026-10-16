# Pass 3 (non-semantic, after the fingerprint): POWI ≤ 4 to products, and parameter hoisting.
# A maximal subtree whose leaves are only parameters and constants (and that holds a
# parameter) becomes a derived parameter, computed on the host in Float64 per launch and
# rounded once to `T` (`D/h²`, `dt·D/h²`). The debug emission mode skips this pass.

const _NOT_HOSTABLE = (
    LOAD, INSIDE_OP, COORD, RUNTIME, TABLE, BITTEST, IDX, RESTRICT, ELEMENT_SUM)

function _powi_node!(b, k::Kernel, i, a, ctx)
    n = k.nodes[i]
    (n.op == POWI && 2 <= n.imm <= 4) || return copy_node!(b, k, i, a, ctx)
    x = a[1]
    n.imm == 4 && (x2 = node!(b, MUL, n.type, Int32[x, x]);
        return node!(b, MUL, n.type, Int32[x2, x2]))
    return node!(b, MUL, n.type, fill(x, n.imm))
end
"""
`x^n` for 2 ≤ n ≤ 4 becomes a product chain (`x^4 = (x·x)·(x·x)`, shared by interning).
"""
expand_powi(p::Program, k::Kernel) = rebuild(_powi_node!, k, buildkeys(p))

function _hostflags(k::Kernel)
    host = falses(length(k.nodes))
    hasp = falses(length(k.nodes))
    for (i, n) in enumerate(k.nodes)
        as = args(k, n)
        host[i] = !(n.op in _NOT_HOSTABLE) && n.type == REAL && all(a -> host[a], as)
        hasp[i] = n.op == PARAM || any(a -> hasp[a], as)
    end
    return host, hasp
end

# Group the parameter-only operands of a mixed n-ary ADD/MUL into one hoistable sub-node.
function _group_node!(host, hasp)
    return function (b, k, i, a, ctx)
        n = k.nodes[i]
        n.op in (ADD, MUL) && !host[i] || return copy_node!(b, k, i, a, ctx)
        old = args(k, n)
        hs = [a[j] for j in eachindex(a) if host[old[j]]]
        length(hs) >= 2 && any(j -> host[old[j]] && hasp[old[j]], eachindex(a)) ||
            return copy_node!(b, k, i, a, ctx)
        rest = [a[j] for j in eachindex(a) if !host[old[j]]]
        return node!(b, n.op, n.type, [rest; node!(b, n.op, n.type, hs)]; flatten = false)
    end
end

"""
Host Float64 expression of node `i` (parameters from the raw tuple `P`).
"""
function hostexpr(k::Kernel, i::Integer)
    n = k.nodes[i]
    n.op == CONST && return k.consts[n.imm]
    n.op == PARAM && return :(P[$(Int(n.imm))])
    return opexpr(n.op, Any[hostexpr(k, a) for a in args(k, n)], n, k, Float64)
end

"""
    hoist_params(p, k) -> (kernel, derived::Vector{Any})

Replace each maximal parameter-only subtree by `PARAM(nparams + j)`; `derived[j]` is its host
Float64 expression.
"""
function hoist_params(p::Program, k::Kernel)
    h, hp = _hostflags(k)
    k = rebuild(_group_node!(h, hp), k, buildkeys(p))
    host, hasp = _hostflags(k)
    used_by_device = falses(length(k.nodes))
    for (i, n) in enumerate(k.nodes), a in args(k, n)

        host[i] || (used_by_device[a] = true)
    end
    foreach(s -> used_by_device[s.value] = true, k.stores)
    foreach(a -> a.offset.cond != 0 && (used_by_device[a.offset.cond] = true), k.accesses)
    hoisted = [i
               for i in eachindex(k.nodes)
               if host[i] && hasp[i] && used_by_device[i] &&
                      !(k.nodes[i].op in (PARAM, CONST))]
    derived = Any[hostexpr(k, i) for i in hoisted]
    slot = Dict(i => p.nparams + j for (j, i) in enumerate(hoisted))
    k2 = rebuild(k, buildkeys(p)) do b, k, i, a, ctx
        haskey(slot, i) ? param!(b, slot[i]) : copy_node!(b, k, i, a, ctx)
    end
    return k2, derived
end
no_hoist(p::Program, k::Kernel) = (k, Any[])
