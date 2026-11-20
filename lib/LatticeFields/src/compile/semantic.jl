# Semantic passes 0–2. Their output is the semantic normal form: the fingerprint
# source and the input of the schedule. Every pass returns a new verified program.

function zero_offset(a::Access{N}) where {N}
    a.offset.cond == 0 && all(iszero, a.offset.a) && a.level == 0
end
writes(k::Kernel) = unique!([s.access.field for s in k.stores])
reads(k::Kernel) = unique!([a.field for a in k.accesses])

# ---- pass 0: legality --------------------------------------------------------------------
"""
Pass 0: one write per site per field; a written single-buffer field is read only at offset 0
(a two-buffer field reads the current buffer and writes the next); no stores to inputs.
"""
function legality(p::Program{N}) where {N}
    for k in p.kernels
        seen = Set{Tuple{Int32, Int16}}()
        for s in k.stores
            f = p.fields[s.access.field]
            (s.access.field, s.access.comp.a) in seen &&
                irerror("kernel `", k.key, "`: `", f.key, "[",
                    s.access.comp.a, "]` is written twice")
            push!(seen, (s.access.field, s.access.comp.a))
            f.role == :input &&
                irerror("kernel `", k.key, "`: stores to input field `", f.key, "`")
            s.law in (:owned, :accumulate) ||
                irerror("kernel `", k.key, "`: unknown law ", s.law)
        end
        w = writes(k)
        for a in k.accesses
            f = p.fields[a.field]
            a.field in w && f.buffers == 1 && !zero_offset(a) &&
                irerror("kernel `", k.key,
                    "`: single-buffer field `", f.key, "` is written and read at offset ",
                    a.offset.a, " (declare buffers = 2)")
            k.space.level + a.level in f.levels ||
                irerror("kernel `", k.key, "`: access to `",
                    f.key, "` at level ", k.space.level + a.level,
                    ", which the field does not have")
        end
        for s in k.stores
            f = p.fields[s.access.field]
            k.space.level in f.levels || irerror("kernel `", k.key, "`: store to `", f.key,
                "` at level ", k.space.level, ", which the field does not have")
            f.buffers == 2 && ncomp(f) > 1 &&
                count(t -> t.access.field == s.access.field, k.stores) != ncomp(f) &&
                irerror("kernel `", k.key, "`: two-buffer field `", f.key,
                    "` must be written in all its components")
        end
        k.space.kind == MASKED && !(1 <= k.space.mask <= length(p.masks)) &&
            irerror("kernel `", k.key, "`: masked space without a mask")
        any(n -> n.op == RESTRICT, k.nodes) && k.space.level < 1 &&
            irerror("kernel `", k.key, "`: RESTRICT in a level-0 space")
        # an access more than one level away (a `Coarse(k)` field and its fine reads): every
        # axis it crosses divisible by 2^m, so each aggregate has 2^m children (no odd tail)
        for a in k.accesses
            m = abs(Int(a.level))
            m > 1 || continue
            lo = min(k.space.level, k.space.level + a.level)
            for (d, n) in enumerate(leveldims(p, lo))
                n == 1 || n % (1 << m) == 0 ||
                    irerror("kernel `", k.key, "`: an access to `", p.fields[a.field].key, "` shifts ", m,
                        " levels across axis ", d, " of size ", n, ", which 2^", m, " does not divide")
            end
        end
    end
    for l in p.hierarchy
        coarsenable(l) || irerror("level ", l.shift, " coarsens an axis of size 1 (dims ",
            Int.(l.grid.dims), "): an axis of size 1 is never coarsened")
    end
    any(l -> l.widths !== nothing, p.hierarchy) &&
        irerror("explicit level widths are not ",
            "supported: coarse levels follow the n ÷ 2 convention (last aggregate width 3)")
    return p
end

# ---- pass 1: fold constants and zeros (Float64, through the interning builder) ------------
_isconst(b, i) = b.nodes[i].op == CONST
_cval(b, i) = b.consts[b.nodes[i].imm]
_typed(t::Scalar, v) = t == BOOL ? v != 0 : isinteger_lane(t) ? Int64(v) : v
const _FOLD = Dict{Op, Function}(
    ADD => +, MUL => *, NEG => -, DIV => /, MIN => min, MAX => max,
    ABS => abs, SQRT => sqrt, EXP => exp, LOG => log, EQ => ==, LT => <, LE => <=,
    AND => &, OR => |, XOR => xor, NOT => !)

function _fold_node!(b::KernelBuilder, k::Kernel, i, a, ctx)
    n = k.nodes[i]
    op, t = n.op, n.type
    if op in (ADD, MUL)
        id = op == ADD ? 0.0 : 1.0
        cs = [_cval(b, x) for x in a if _isconst(b, x)]
        rest = [x for x in a if !_isconst(b, x)]
        c = isempty(cs) ? id : reduce(op == ADD ? (+) : (*), cs)
        op == MUL && c == 0 && t == REAL && return constant!(b, 0.0, t)
        isempty(rest) && return constant!(b, c, t)
        c != id && push!(rest, constant!(b, c, t))
        return length(rest) == 1 ? rest[1] : node!(b, op, t, rest)
    elseif haskey(_FOLD, op) && all(x -> _isconst(b, x), a) && !isempty(a)
        v = _FOLD[op]((_typed(b.nodes[x].type, _cval(b, x)) for x in a)...)
        return constant!(b, Float64(v), t)
    elseif op == NEG
        m = b.nodes[a[1]]
        m.op == NEG && return nodeargs(b, a[1])[1]
        if m.op == MUL && any(x -> _isconst(b, x), nodeargs(b, a[1]))
            xs = [_isconst(b, x) ? constant!(b, -_cval(b, x), t) : x
                  for x in nodeargs(b, a[1])]
            return node!(b, MUL, t, xs)
        end
    elseif op == DIV
        _isconst(b, a[2]) && _cval(b, a[2]) == 1 && return a[1]
        _isconst(b, a[1]) && _cval(b, a[1]) == 0 && return constant!(b, 0.0, t)
    elseif op in (SELECT, COND)
        _isconst(b, a[1]) && return _cval(b, a[1]) != 0 ? a[2] : a[3]
        a[2] == a[3] && return a[2]
    elseif op == POWI
        n.imm == 0 && return constant!(b, 1.0, t)
        n.imm == 1 && return a[1]
        _isconst(b, a[1]) && return constant!(b, _cval(b, a[1])^n.imm, t)
    elseif op == CAST && _isconst(b, a[1])
        return constant!(b, _cval(b, a[1]), t)
    end
    return copy_node!(b, k, i, a, ctx)
end

"""
Pass 1: fold constant subtrees in Float64 and remove zeros and identities.
"""
function fold(p::Program)
    with_kernels(p, [rebuild(_fold_node!, k, buildkeys(p)) for k in p.kernels])
end

# ---- pass 2: semantic boundary resolution --------------------------------------------------
function _coef!(b, c::Coef)
    c.param == 0 ? constant!(b, c.value) :
    node!(b, MUL, REAL, Int32[constant!(b, c.value), param!(b, c.param)])
end
function _with(a::Access{N}, off, policy) where {N}
    Access{N}(a.field, a.class, a.comp, Sel(off), a.level, policy)
end
function _loadacc!(b, p, a)
    node!(b, LOAD, loadtype(p.fields[a.field].storage), Int32[], access!(b, a))
end
_inside!(b, a) = node!(b, INSIDE_OP, BOOL, Int32[], access!(b, a))
function _ne0!(b, x)
    node!(b, NOT, BOOL, Int32[compare!(b, EQ, x, constant!(b, 0.0, b.nodes[x].type))])
end

# a rule's value: its coefficient, times the value field at access `at` when it has one (a
# face or mask value that reads the time, the coordinates or an input)
function _rulevalue!(b, p::Program{N}, c::Coef, vf::Integer, at::Access{N}) where {N}
    vf == 0 && return _coef!(b, c)
    a = Access{N}(Int32(vf), 0, Sel(Int16(1)), at.offset, at.level, all(iszero, at.offset.a) ? INSIDE : CLAMP)
    v = cast!(b, _loadacc!(b, p, a), REAL)
    c.param == 0 && c.value == 1 && return v
    return arith!(b, MUL, _coef!(b, c), v)
end

"""
Ghost value of `center` across the face (`axis`, `side`) of field `f`, from its rule; `at` is
the access of the boundary site (where a value field is read).
"""
function _ghost!(b, p::Program, f, axis, side, center, at)
    k = findfirst(r -> r isa FaceRule && r.field == f && r.axis == axis && r.side == side, p.rules)
    k === nothing &&
        irerror("field `", p.fields[f].key, "` has no boundary rule on axis ", axis,
            " side ", side > 0 ? "+" : "-", " and the axis is not periodic")
    r = p.rules[k]::FaceRule
    α, β = r.alpha, r.beta
    α.value == 0 && β.value == 0 &&
        irerror("field `", p.fields[f].key, "`: face rule on axis ",
            axis, " has α = β = 0")
    g() = _rulevalue!(b, p, r.g, r.gfield, at)
    site = sitecoefs(r)                                   # (α or β varies by site: Robin)
    if !site && α.param == 0 && β.param == 0 && β.value == 0   # Dirichlet: ghost = (2/α) g − c
        return arith!(b, ADD, arith!(b, MUL, constant!(b, 2 / α.value), g()),
            arith!(b, NEG, center))
    elseif !site && α.param == 0 && α.value == 0          # flux: ghost = c + g/β
        r.gfield == 0 && r.g.param == 0 && r.g.value == 0 && return center
        return arith!(b, ADD, center, arith!(b, DIV, g(), _coef!(b, β)))
    end                                                   # Robin: (g − (α/2 − β) c)/(α/2 + β)
    av, bv = _rulevalue!(b, p, α, r.afield, at), _rulevalue!(b, p, β, r.bfield, at)
    h = arith!(b, MUL, constant!(b, 0.5), av)
    num = arith!(b,
        ADD,
        g(),
        arith!(b, NEG,
            arith!(b, MUL, arith!(b, ADD, h, arith!(b, NEG, bv)), center)))
    return arith!(b, DIV, num, arith!(b, ADD, h, bv))
end

"""
Resolve a `RESOLVE` access: per non-periodic axis, `select(inside, value, ghost)`; then
immersed and domain-edge rules on the neighbor's mask.
"""
function _resolve!(b, p::Program{N}, a::Access{N}, axes) where {N}
    off = a.offset.a
    if isempty(axes)
        # resolved: CLAMP wraps periodic axes and clamps the others; offset 0 is inside
        return _loadacc!(b, p, _with(a, off, all(iszero, off) ? INSIDE : CLAMP))
    end
    d = axes[1]
    abs(off[d]) == 1 || irerror("field `", p.fields[a.field].key, "`: offset ", off,
        " crosses a non-periodic face by more than one layer")
    inner = _resolve!(b, p, a, axes[2:end])
    c0 = ntuple(e -> e == d ? Int16(0) : off[e], N)
    center = _resolve!(b, p, _with(a, c0, a.policy), axes[2:end])
    ghost = _ghost!(b, p, a.field, d, sign(off[d]), center, _with(a, c0, CLAMP))
    dacc = _with(a, ntuple(e -> e == d ? off[d] : Int16(0), N), INSIDE)
    return select!(b, _inside!(b, dacc), inner, ghost)
end

function _resolve_load!(b::KernelBuilder{N}, p::Program{N}, a::Access{N}) where {N}
    a.offset.cond == 0 || return _loadacc!(b, p, a)
    off = a.offset.a
    axes = [d for d in 1:N if off[d] != 0 && !p.periodic[d]]
    !isempty(axes) && a.level != 0 &&
        irerror("field `", p.fields[a.field].key,
            "`: a level-shifted access at a non-periodic offset needs policy CLAMP or ZERO")
    v = _resolve!(b, p, a, axes)
    all(iszero, off) && return v
    center = _loadacc!(b, p, _with(a, ntuple(_ -> Int16(0), N), INSIDE))
    for r in p.rules
        m = r isa ImmersedRule && r.field == a.field ? r.mask :
            r isa DomainEdgeRule && r.field == a.field ? (r.mask == 0 ? p.hierarchy[1].grid.domain : r.mask) : 0
        m == 0 && continue
        r isa ImmersedRule && r.kind != :zero_flux &&
            irerror("immersed rule kind `", r.kind,
                "` is not lowered yet (only :zero_flux)")
        ma = Access{N}(p.masks[m].field, 0, Sel(Int16(1)), Sel(off),
            0, CLAMP)
        hit = _ne0!(b, _loadacc!(b, p, ma))
        if r isa DomainEdgeRule
            # across the domain edge, from either side: a neighbor outside, or a site outside
            # (which then exchanges nothing; the CPM's pairs need both sites in the domain)
            mc = Access{N}(p.masks[m].field, 0, Sel(Int16(1)), Sel(ntuple(_ -> Int16(0), N)), 0, INSIDE)
            hit = node!(b, NOT, BOOL, Int32[node!(b, AND, BOOL, Int32[hit, _ne0!(b, _loadacc!(b, p, mc))])])
        end
        isempty(axes) ||
            (hit = node!(b, AND, BOOL, Int32[_inside!(b, _with(a, off, INSIDE)), hit]))
        alt = r isa DomainEdgeRule && r.kind == :zero ? constant!(b, 0.0) : center
        v = select!(b, hit, alt, v)
    end
    return v
end

function _boundary_node!(p::Program)
    return function (b, k, i, a, ctx)
        n = k.nodes[i]
        n.op == LOAD && k.accesses[n.imm].policy == RESOLVE ||
            return copy_node!(b, k, i, a, ctx)
        return _resolve_load!(b, p, remap_access(k.accesses[n.imm], ctx[1], identity))
    end
end

"""
Store-side rules: `NodeValueRule` makes masked sites store the rule's value (identity row).
"""
function _node_values(p::Program{N}, k::Kernel{N}) where {N}
    rs = [r for r in p.rules if r isa NodeValueRule && r.field in writes(k)]
    isempty(rs) && return k
    return rebuild(copy_node!,
        k,
        buildkeys(p);
        storefn = function (b, s, v)
            for r in rs
                r.field == s.access.field || continue
                ma = Access{N}(p.masks[r.mask].field, 0, Sel(Int16(1)),
                    Sel(ntuple(_ -> Int16(0), N)), 0, INSIDE)
                v = select!(b, _ne0!(b, _loadacc!(b, p, ma)), _rulevalue!(b, p, r.value, r.vfield, ma), v)
            end
            return v
        end)
end

"""
Pass 2: ghost and flux queries become explicit expressions; no `RESOLVE` access remains
on a non-periodic axis.
"""
function boundary(p::Program)
    ks = [_node_values(p, rebuild(_boundary_node!(p), k, buildkeys(p))) for k in p.kernels]
    return with_kernels(p, ks)
end

const SEMANTIC_PASSES = (legality, fold, boundary, fold)

"""
Run passes 0–2 (each result verified). `passes` may be replaced for fault injection.
"""
function semantic(p::Program; passes = SEMANTIC_PASSES)
    verify(p)
    for pass in passes
        p = verify(pass(p))
    end
    return legality(p)
end
