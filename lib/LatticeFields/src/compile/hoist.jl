# Pass 3 (non-semantic, after the fingerprint): POWI ≤ 4 to products, and parameter
# hoisting. A maximal subtree whose leaves are only parameters, constants and the time `t`
# (and that holds a parameter or `t`) becomes a derived parameter, computed on the host in
# at least Float64 and rounded once to the compute type (`D/h²`, `sin(ω t)`). A subtree that
# reads `t` (a bare `t` included) is derived again at each launch on the host, so the device
# never holds the runtime slot of absolute time (P5 §3.3); the step `dt` stays a runtime
# value. The debug emission mode skips this pass.

const _NOT_HOSTABLE = (
    LOAD, INSIDE_OP, COORD, RUNTIME, TABLE, BITTEST, IDX, RESTRICT, ELEMENT_SUM,
)
# `G.rt[1]` is the time `t` (contract item 4); the other runtime slots stay on the device
const TIME_SLOT = 1
_istime(n::Node) = n.op == RUNTIME && n.imm == TIME_SLOT

function _powi_node!(b, k::Kernel, i, a, ctx)
    n = k.nodes[i]
    (n.op == POWI && 2 <= n.imm <= 4) || return copy_node!(b, k, i, a, ctx)
    x = a[1]
    n.imm == 4 && (
        x2 = node!(b, MUL, n.type, Int32[x, x]);
        return node!(b, MUL, n.type, Int32[x2, x2])
    )
    return node!(b, MUL, n.type, fill(x, n.imm))
end
"""
`x^n` for 2 ≤ n ≤ 4 becomes a product chain (`x^4 = (x·x)·(x·x)`, shared by interning);
other exponents, and all of them in the debug mode, emit `powi`.
"""
expand_powi(p::Program, k::Kernel) = rebuild(_powi_node!, k, buildkeys(p))

function _hostflags(k::Kernel)
    host = falses(length(k.nodes))
    hasp = falses(length(k.nodes))
    for (i, n) in enumerate(k.nodes)
        as = args(k, n)
        host[i] = (_istime(n) || !(n.op in _NOT_HOSTABLE)) && n.type == REAL &&
            all(a -> host[a], as)
        hasp[i] = n.op == PARAM || _istime(n) || any(a -> hasp[a], as)
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
Host expression of node `i`: parameters from the widened raw tuple `Q`, the time as `t`.
"""
function hostexpr(k::Kernel, i::Integer)
    n = k.nodes[i]
    n.op == CONST && return k.consts[n.imm]
    n.op == PARAM && return :(Q[$(Int(n.imm))])
    _istime(n) && return :t
    return opexpr(n.op, Any[hostexpr(k, a) for a in args(k, n)], n, k, Float64)
end

"""
    hoist_params(p, k) -> (kernel, derived::Vector{Any})

Replace each maximal subtree of parameters, constants and `t` by `PARAM(nparams + j)`;
`derived[j]` is its host expression (of `Q` and `t`).
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
    hoisted = [
        i
            for i in eachindex(k.nodes)
            if host[i] && hasp[i] && used_by_device[i] &&
            !(k.nodes[i].op in (PARAM, CONST))
    ]     # a bare `t` is hoisted too
    derived = Any[hostexpr(k, i) for i in hoisted]
    slot = Dict(i => p.nparams + j for (j, i) in enumerate(hoisted))
    k2 = rebuild(k, buildkeys(p)) do b, k, i, a, ctx
        haskey(slot, i) ? param!(b, slot[i]) : copy_node!(b, k, i, a, ctx)
    end
    return k2, derived
end
no_hoist(p::Program, k::Kernel) = (k, Any[])
