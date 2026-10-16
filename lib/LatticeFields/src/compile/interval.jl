# Interval coefficient evaluator (R3 §3.1, v3 §4.5), emitted as host code: given parameter
# bounds it returns enclosures of chosen nodes with no allocation, which is what stability
# bounds and stage counts need. A load takes its field's declared state interval; a load with
# no declared interval is a build error naming the field. Bounds are widened outward by one
# ulp per operation, so they enclose the Float64 values.

const Iv = Tuple{Float64, Float64}
_out(lo, hi) = (prevfloat(Float64(lo)), nextfloat(Float64(hi)))
iv_add(a::Iv, b::Iv) = _out(a[1] + b[1], a[2] + b[2])
function iv_mul(a::Iv, b::Iv)
    p = (a[1] * b[1], a[1] * b[2], a[2] * b[1], a[2] * b[2])
    return _out(minimum(p), maximum(p))
end
iv_neg(a::Iv) = (-a[2], -a[1])
iv_div(a::Iv, b::Iv) = b[1] <= 0 <= b[2] ? (-Inf, Inf) :
                       iv_mul(a, _out(1 / b[2], 1 / b[1]))
iv_min(a::Iv, b::Iv) = (min(a[1], b[1]), min(a[2], b[2]))
iv_max(a::Iv, b::Iv) = (max(a[1], b[1]), max(a[2], b[2]))
iv_abs(a::Iv) = a[1] >= 0 ? a : a[2] <= 0 ? iv_neg(a) : (0.0, max(-a[1], a[2]))
function iv_powi(a::Iv, n::Int)
    n == 0 && return (1.0, 1.0)
    n < 0 && return iv_div((1.0, 1.0), iv_powi(a, -n))
    iseven(n) && return (b = iv_abs(a); _out(b[1]^n, b[2]^n))
    return _out(a[1]^n, a[2]^n)
end
iv_mono(f::F, a::Iv) where {F} = _out(f(a[1]), f(a[2]))
iv_sqrt(a::Iv) = iv_mono(sqrt, (max(a[1], 0.0), max(a[2], 0.0)))
function iv_log(a::Iv)
    a[1] <= 0 ? (-Inf, a[2] <= 0 ? -Inf : nextfloat(log(a[2]))) : iv_mono(log, a)
end
iv_hull(a::Iv, b::Iv) = (min(a[1], b[1]), max(a[2], b[2]))
const _MONO_CALLS = (:tanh, :sinh, :cbrt, :exp2, :expm1, :atan, :floor, :ceil, :round)

function _ivexpr(k::Kernel, i, p::Program, bounds, a)
    n = k.nodes[i]
    op = n.op
    op == CONST && return (k.consts[n.imm], k.consts[n.imm])
    op == PARAM && return :((Plo[$(Int(n.imm))], Phi[$(Int(n.imm))]))
    if op in (LOAD, TABLE, RUNTIME)
        key = op == LOAD ? p.fields[k.accesses[n.imm].field].key :
              op == TABLE ? p.tables[n.imm].key : "runtime#$(n.imm)"
        haskey(bounds, key) ||
            irerror("interval evaluator: `", key, "` has no declared interval",
                " (kernel `", k.key, "`, node v", i, ")")
        return Float64.(bounds[key])
    end
    op == COORD && return (1.0, Float64(maximum(leveldims(p, k.space.level))))
    op in (EQ, LT, LE, AND, OR, XOR, NOT, INSIDE_OP, BITTEST) && return (0.0, 1.0)
    op == ADD && return foldl((x, y) -> :(iv_add($x, $y)), a)
    op == MUL && return foldl((x, y) -> :(iv_mul($x, $y)), a)
    op == MIN && return foldl((x, y) -> :(iv_min($x, $y)), a)
    op == MAX && return foldl((x, y) -> :(iv_max($x, $y)), a)
    op == NEG && return :(iv_neg($(a[1])))
    op == DIV && return :(iv_div($(a[1]), $(a[2])))
    op == ABS && return :(iv_abs($(a[1])))
    op == POWI && return :(iv_powi($(a[1]), $(Int(n.imm))))
    op == SQRT && return :(iv_sqrt($(a[1])))
    op == EXP && return :(iv_mono(exp, $(a[1])))
    op == LOG && return :(iv_log($(a[1])))
    op == CAST && return a[1]
    op in (SELECT, COND) && return :(iv_hull($(a[2]), $(a[3])))
    op == FMA && return :(iv_add(iv_mul($(a[1]), $(a[2])), $(a[3])))
    if op == CALL
        f = k.calls[n.imm]
        f in (:sin, :cos) && return (-1.0, 1.0)
        f in _MONO_CALLS && return :(iv_mono($f, $(a[1])))
    end
    irerror("interval evaluator: op `", opname(op),
        "` has no interval rule (kernel `", k.key, "`)")
end

"""
    interval_expr(p, k, nodes; bounds) -> Expr

Host function `(Plo, Phi) -> (iv₁, iv₂, …)` enclosing nodes `nodes` of kernel `k` over the
parameter box; `bounds` maps field (or table) keys to declared `(lo, hi)` state intervals.
"""
function interval_expr(p::Program, k::Kernel, nodes; bounds = Dict{String, Iv}())
    body = Any[]
    need = falses(length(k.nodes))
    mark(i) = (need[i] && return; need[i] = true; foreach(mark, args(k, i)))
    foreach(mark, nodes)
    for i in eachindex(k.nodes)
        need[i] || continue
        a = Any[Symbol(:w, j) for j in args(k, i)]
        push!(body, :($(Symbol(:w, i)) = $(_ivexpr(k, i, p, bounds, a))))
    end
    ret = Expr(:tuple, [Symbol(:w, i) for i in nodes]...)
    return Expr(:->, Expr(:tuple, :Plo, :Phi), Expr(:block, body..., ret))
end
function interval_function(p::Program, k::Kernel, nodes; kw...)
    rgf(interval_expr(p, k, nodes; kw...))
end
