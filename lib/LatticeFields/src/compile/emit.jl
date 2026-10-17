# Passes 4–6: types, index lowering and emission of `body(s, S, P, G)` (linear) or
# `body(x, S, P, G)` (Cartesian; Exec launches both, contract.jl), stores interleaved in
# canonical order. The debug mode is a flag here: Float64, no hoisting, coordinates from
# `CartesianIndices` and targets from bounds-checked `LinearIndices`, no `@inbounds`. It
# shares no index arithmetic with the optimized path, so it is the oracle for optimized
# emission.

"""
Compile options. `T`: compute value type; `I`: site index type (switched to Int64
automatically when an array has more than 2³¹ − 1 elements);
`index`: `:auto | :linear | :cartesian`; `float64_ok = false` on Metal; `lanes`: what a float
lane holds ([`lanetype`](@ref)): `:fixed` (its own type) or `:state` (problems: the F32/F64
lanes hold `T`). `T = nothing` (the default) compiles raw IR in Float32; problems take the
value type from their state (`eltype(u0)`) and refuse an explicit `T` that differs.
"""
Base.@kwdef struct CompileOptions
    T::Union{Type, Nothing} = nothing
    I::Type = Int32
    float64_ok::Bool = true
    debug::Bool = false
    index::Symbol = :auto
    lanes::Symbol = :fixed
end
debug_options() = CompileOptions(; T = Float64, I = Int, debug = true)

# ---- pass 4: types ------------------------------------------------------------------------
jtype(t::Scalar, T::Type) = t == REAL ? T : t == BOOL ? Bool : juliatype(t)

"""
Pass 4: a Float64 compute value type (`Float64`, a Dual over Float64, or anything wider) or
a Float64 lane is a build error naming the fields when the backend has no Float64.
"""
function check_types(p::Program, k::Kernel, o::CompileOptions)
    o.float64_ok && return nothing
    V = valtype(something(o.T, Float32))
    V <: Union{Float16, Float32} || irerror("kernel `", k.key, "` (fields ",
        join(unique(p.fields[s.access.field].key for s in k.stores), ", "), "): compute value type ",
        V, " (from ", o.T, ") on a backend without Float64")
    for a in k.accesses
        p.fields[a.field].storage == F64 && irerror("field `", p.fields[a.field].key,
            "` has lane F64, which this backend does not support")
    end
    return nothing
end

# ---- shared op table (device emission and host derived parameters) ------------------------
const _BINOPS = Dict(ADD => :+, MUL => :*, MIN => :min, MAX => :max)
const _UNOPS = Dict(NEG => :-, ABS => :abs, EXP => :exp)
# Domain-restricted functions return NaN outside their domain instead of throwing (no throw
# in bodies; the host executor runs the same bodies as the device).
const _DOMAIN = Dict(:sqrt => 0, :log => 0, :log2 => 0, :log10 => 0, :log1p => -1)
function _guarded(f::Symbol, x, T::Type)
    haskey(_DOMAIN, f) || return Expr(:call, f, x)
    lo = T(_DOMAIN[f])
    return :(ifelse($x < $lo, oftype($x, $(T(NaN))), $f(max($x, $lo))))
end
const _CMPOPS = Dict(EQ => :(==), LT => :<, LE => :<=, AND => :&, OR => :|, XOR => :xor)

"""
Julia expression of a value node from its operand expressions (`T`: compute type).
"""
function opexpr(op::Op, a::Vector{Any}, n::Node, k::Kernel, T::Type)
    haskey(_BINOPS, op) && return foldl((x, y) -> Expr(:call, _BINOPS[op], x, y), a)
    haskey(_UNOPS, op) && return Expr(:call, _UNOPS[op], a[1])
    haskey(_CMPOPS, op) && return Expr(:call, _CMPOPS[op], a[1], a[2])
    op == DIV && return :($(a[1]) / $(a[2]))
    op == FMA && return :(fma($(a[1]), $(a[2]), $(a[3])))
    op == NOT && return n.type == BOOL ? :(!$(a[1])) : :(~$(a[1]))
    op == SELECT && return :(ifelse($(a[1]), promote($(a[2]), $(a[3]))...))
    op == SQRT && return _guarded(:sqrt, a[1], T)
    op == LOG && return _guarded(:log, a[1], T)
    op == POWI && return :($(a[1])^$(Int(n.imm)))
    op == CALL && return _guarded(k.calls[n.imm], a[1], T)
    op == BITTEST && return :((($(a[1]) >> $(Int(n.imm))) & one($(a[1]))) != zero($(a[1])))
    if op == CAST
        t = jtype(n.type, T)
        src = k.nodes[args(k, n)[1]].type
        isfloat(n.type) && return :(lanecast($t, $(a[1])))
        return isfloat(src) ? :(unsafe_trunc($t, primal($(a[1])))) : :($(a[1]) % $t)
    end
    irerror("kernel `", k.key, "`: op `", opname(op), "` has no lowering in this compiler")
end

# ---- pass 5: index lowering ---------------------------------------------------------------
struct Lowered
    strategy::Symbol
    levels::Vector{Int8}
    lanes::Vector{Scalar}
    args::Vector{Vector{Tuple{Int32, Symbol}}}
end

"""
Arguments a kernel needs: `(field, :cur | :next)` per array and `(table, :table)`.
"""
function kernel_args(p::Program, k::Kernel)
    s = Set{Tuple{Scalar, String, Int32, Symbol}}()
    f(id, role) = push!(s, (p.fields[id].storage, p.fields[id].key, id, role))
    foreach(a -> f(a.field, :cur), (a for (n, a) in _loads(k)))
    for st in k.stores
        b2 = p.fields[st.access.field].buffers == 2
        f(st.access.field, b2 ? :next : :cur)
        b2 && k.space.kind != FULL && f(st.access.field, :cur)
    end
    k.space.kind == MASKED && f(p.masks[k.space.mask].field, :cur)
    for t in k.tables
        push!(s, (p.tables[t].storage, p.tables[t].key, t, :table))
    end
    lanes = sort!(unique!([x[1] for x in s]))
    return lanes,
    [[(x[3], x[4]) for x in sort!([x for x in s if x[1] == l]; by = x -> (x[2], x[4]))]
     for l in lanes]
end
_loads(k::Kernel) = ((n, k.accesses[n.imm]) for n in k.nodes if n.op == LOAD)

function lower_index(p::Program{N}, k::Kernel{N}, o::CompileOptions) where {N}
    box = any(a -> count(!iszero, a.offset.a) >= 2, k.accesses)
    strategy = o.debug ? :linear : o.index == :auto ? (box ? :cartesian : :linear) : o.index
    levels = Int8[k.space.level]
    foreach(a -> push!(levels, k.space.level + a.level), k.accesses)
    lanes, as = kernel_args(p, k)
    return Lowered(strategy, unique!(levels), lanes, as)
end

# Emission context.
struct Ctx{N, X}
    p::Program{N}
    k::Kernel{N}
    o::CompileOptions
    L::Lowered
    names::Dict{Tuple{Int32, Symbol}, Symbol}
    index::X                         # access -> linear index expression (a lowering stage)
end

_dim(c::Ctx, level, d) = (j = findfirst(==(level), c.L.levels); :($(c.o.I)(G.dims[$j][$d])))
_I(c::Ctx, v) = c.o.I(v)

"""
Target coordinate along axis `d` before the boundary policy, with the level shift. Coarse
level convention (contract.jl): a coarse axis has `n ÷ 2` sites; fine sites pair up, and the
last aggregate of an odd axis takes width 3. So a fine `x` maps to coarse
`min((x − 1) ÷ 2 + 1, nc)`, and a coarse `x` has its children at `2(x − 1) + 1 + o`.
"""
function _coord(c::Ctx, a::Access, d, lev)
    o = a.offset.cond == 0 ? _I(c, a.offset.a[d]) :
        :(ifelse($(Symbol(:v, a.offset.cond)), $(_I(c, a.offset.b[d])), $(_I(c, a.offset.a[d]))))
    x = Symbol(:x, d)
    a.level == 0 && return :($x + $o)
    nc = _dim(c, lev, d)
    c.o.debug &&
        return a.level > 0 ? :(min(fld($x - 1, 2) + 1, $nc) + $o) : :(2 * ($x - 1) + 1 + $o)
    one_ = _I(c, 1)
    return a.level > 0 ? :(min((($x - $one_) >> 1) + $one_, $nc) + $o) :
           :(($x - $one_) * $(_I(c, 2)) + $one_ + $o)
end

"""
Largest |offset| of an access along axis `d` (both `Sel` arms).
"""
_maxoff(a::Access, d) = max(abs(Int(a.offset.a[d])), abs(Int(a.offset.b[d])))

"""
Target coordinates of an access. Periodic axes wrap: one conditional fold when every offset
is smaller than the axis (checked at compile time against the program's dims), else
`mod1`. With `bounded = true`, CLAMP and ZERO clamp non-periodic axes into range; the
inside test of ZERO reads the unclamped coordinates (`bounded = false`).
"""
function _target(c::Ctx{N}, a::Access{N}; bounded::Bool = true) where {N}
    lev = c.k.space.level + a.level
    ys = Any[]
    dims = leveldims(c.p, lev)
    for d in 1:N
        y, n = _coord(c, a, d, lev), _dim(c, lev, d)
        shifted = a.offset.cond != 0 || a.offset.a[d] != 0 || a.level != 0
        if shifted && a.policy != INSIDE && c.p.periodic[d]
            y = c.o.debug || _maxoff(a, d) >= dims[d] ? :(mod1($y, $n)) :
                :((y = $y; ifelse(y < $(_I(c, 1)), y + $n, ifelse(y > $n, y - $n, y))))
        elseif bounded && shifted && a.policy in (CLAMP, ZERO)
            y = c.o.debug ? :(clamp($y, 1, $n)) : :(min(max($y, $(_I(c, 1))), $n))
        end
        push!(ys, y)
    end
    return ys, lev
end

"""
Linear index of an access (plane offset for multi-component fields). Every index is in
range: offsets are wrapped (periodic), clamped (CLAMP, ZERO) or proven inside (INSIDE, and
offset 0 after pass 2), which is the bounds argument for the `@inbounds` emitted with it.
"""
function linear_index(c::Ctx{N}, a::Access{N}) where {N}
    comp = a.comp.cond == 0 ? _I(c, a.comp.a) :
           :(ifelse($(Symbol(:v, a.comp.cond)), $(_I(c, a.comp.b)), $(_I(c, a.comp.a))))
    own = zero_offset(a) && !c.o.debug
    ys, lev = _target(c, a)
    ns = [_dim(c, lev, d) for d in 1:N]
    if c.o.debug
        idx = :(LinearIndices(($([:(Int($n)) for n in ns]...),))[$(ys...)])
    elseif own
        idx = :s
    else
        idx = :($(ys[N]) - $(_I(c, 1)))
        for d in (N - 1):-1:1
            idx = :($(ys[d]) - $(_I(c, 1)) + $(ns[d]) * ($idx))
        end
        idx = :($idx + $(_I(c, 1)))
    end
    ncomp(c.p.fields[a.field]) == 1 && return idx
    return :($idx + ($comp - $(_I(c, 1))) * $(foldl((x, y) -> :($x * $y), ns)))
end

"""
Inside test of an INSIDE access: every non-periodic axis with a nonzero offset.
"""
function _inside(c::Ctx{N}, a::Access{N}) where {N}
    ys, lev = _target(c, a; bounded = false)
    ts = [:(($(_I(c, 1)) <= $(ys[d])) & ($(ys[d]) <= $(_dim(c, lev, d))))
          for d in 1:N
          if (a.offset.cond != 0 || a.offset.a[d] != 0 || a.level != 0) && !c.p.periodic[d]]
    return isempty(ts) ? true : foldl((x, y) -> :($x & $y), ts)
end

_ref(c::Ctx, A, idx) = c.o.debug ? :($A[$idx]) : :(@inbounds $A[$idx])

# ---- pass 6: emission ---------------------------------------------------------------------
"""
Expression of node `i` (operands already bound to `v<j>`).
"""
function _nodeexpr(c::Ctx, i)
    k, n, T = c.k, c.k.nodes[i], c.o.T
    a = Any[Symbol(:v, j) for j in args(k, n)]
    if n.op == CONST
        v = k.consts[n.imm]
        return n.type == BOOL ? v != 0 : jtype(n.type, T)(v)
    elseif n.op == PARAM
        return :(P[$(Int(n.imm))])
    elseif n.op == RUNTIME
        return :(G.rt[$(Int(n.imm))])
    elseif n.op == COORD
        return :($(Symbol(:x, n.imm)) % Int32)
    elseif n.op == LOAD
        acc = k.accesses[n.imm]
        f = c.p.fields[acc.field]
        x = _ref(c, c.names[(acc.field, :cur)], c.index(c, acc))
        isfloat(f.storage) && lanetype(f.storage, T, c.o.lanes) != T && (x = :(lanecast($T, $x)))
        acc.policy == ZERO && (x = :(let y = $x
            ifelse($(_inside(c, acc)), y, zero(y))
        end))
        return x
    elseif n.op == INSIDE_OP
        return _inside(c, k.accesses[n.imm])
    elseif n.op == TABLE
        t = c.p.tables[n.imm]
        A = c.names[(n.imm, :table)]
        i = a[1]                              # clamped into 1:length: the bounds argument
        x = _ref(c, A, :(clamp($i, one($i), length($A) % typeof($i))))
        isfloat(t.storage) && (x = :(lanecast($T, $x)))
        t.oob == :zero_at_0 &&
            (x = :(ifelse($(a[1]) == zero($(a[1])), zero($(jtype(n.type, T))), $x)))
        return x
    end
    return opexpr(n.op, a, n, k, T)
end

"""
Emit node `i` and its operands into `out` once per scope; COND arms get their own scopes.
"""
function _emit!(out, c::Ctx, i, done::Set{Int32})
    i in done && return nothing
    n = c.k.nodes[i]
    for j in deps_k(c.k, i)
        n.op == COND && j != args(c.k, n)[1] && continue
        _emit!(out, c, j, done)
    end
    v = Symbol(:v, i)
    if n.op == COND
        cnd, x, y = args(c.k, n)
        arms = map((x, y)) do j
            blk = Any[]
            _emit!(blk, c, j, copy(done))
            push!(blk, Symbol(:v, j))
            Expr(:block, blk...)
        end
        push!(out, :($v = if $(Symbol(:v, cnd))
            $(arms[1])
        else
            $(arms[2])
        end))
    else
        push!(out, :($v = $(_nodeexpr(c, i))))
    end
    push!(done, i)
    return nothing
end
function deps_k(k::Kernel, i)
    (n = k.nodes[i]; a = collect(Int32, args(k, n));
        n.op in (LOAD, INSIDE_OP) && (acc = k.accesses[n.imm];
            acc.comp.cond != 0 && push!(a, acc.comp.cond);
            acc.offset.cond != 0 && push!(a, acc.offset.cond)); a)
end

function _store(c::Ctx, s::Store)
    f = c.p.fields[s.access.field]
    A = c.names[(s.access.field, f.buffers == 2 ? :next : :cur)]
    v = Symbol(:v, s.value)
    L = lanetype(f.storage, c.o.T, c.o.lanes)
    isfloat(f.storage) && L != c.o.T && (v = :(lanecast($L, $v)))
    idx = c.index(c, s.access)
    return c.o.debug ? :($A[$idx] = $v) : :(@inbounds $A[$idx] = $v)
end

"""
Loads of single-buffer fields this kernel also writes; emitted before any store
(loads-before-stores ordering), so no thread reads its own new value.
"""
function loads_first(c::Ctx)
    w = Set(s.access.field for s in c.k.stores if c.p.fields[s.access.field].buffers == 1)
    return Int32[i
                 for (i, n) in enumerate(c.k.nodes)
                 if n.op == LOAD && c.k.accesses[n.imm].field in w]
end

"""
Masked and restricted spaces are write-complete: outside the space, two-buffer outputs
store the current value (pass-through).
"""
function passthrough(c::Ctx)
    out = Any[]
    for s in c.k.stores
        f = c.p.fields[s.access.field]
        f.buffers == 2 || continue
        idx = c.index(c, s.access)
        src = _ref(c, c.names[(s.access.field, :cur)], idx)
        push!(out,
            c.o.debug ? :($(c.names[(s.access.field, :next)])[$idx] = $src) :
            :(@inbounds $(c.names[(s.access.field, :next)])[$idx] = $src))
    end
    return out
end

function _coords(c::Ctx{N}) where {N}
    ns = [_dim(c, c.k.space.level, d) for d in 1:N]
    if c.L.strategy == :cartesian         # s from x; padded threads are guarded in `emit`
        lin = :($(Symbol(:x, N)) - $(_I(c, 1)))
        for d in (N - 1):-1:1
            lin = :($(Symbol(:x, d)) - $(_I(c, 1)) + $(ns[d]) * ($lin))
        end
        return Any[[:($(Symbol(:x, d)) = x[$d] % $(c.o.I)) for d in 1:N]...;
                   :(s = $lin + $(_I(c, 1)))]
    end
    c.o.debug && return Any[:(ci = CartesianIndices(($([:(Int($n)) for n in ns]...),))[s]);
               [:($(Symbol(:x, d)) = ci[$d]) for d in 1:N]...]
    out = Any[:(t = s - $(_I(c, 1)))]
    for d in 1:N
        push!(out, d < N ? :((t, r) = divrem(t, $(ns[d]))) : :(r = t))
        push!(out, :($(Symbol(:x, d)) = r + $(_I(c, 1))))
    end
    return out
end

function _guard(c::Ctx{N}) where {N}
    sp = c.k.space
    sp.kind == MASKED &&
        return :($(_ref(c, c.names[(c.p.masks[sp.mask].field, :cur)], :s)) != 0)
    ts = [:(($(Symbol(:x, d)) > $(_I(c, sp.inset[d][1]))) &
            ($(Symbol(:x, d)) <= $(_dim(c, sp.level, d)) - $(_I(c, sp.inset[d][2]))))
          for d in 1:N]
    return foldl((x, y) -> :($x & $y), ts)
end

"""
Remove every line-number node, also the ones macro calls carry, so the body text (and
its content hash) does not depend on source paths.
"""
function _strip!(ex)
    ex isa Expr || return ex
    filter!(x -> !(x isa LineNumberNode) || ex.head == :macrocall, ex.args)
    ex.head == :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode &&
        (ex.args[2] = nothing)
    foreach(_strip!, ex.args)
    return ex
end

"""
    emit(p, k, o; stages) -> (Expr, Lowered)

Pass 6: the body expression. Stores follow their values (interleaved) in canonical order;
`stages.order(ctx)` lists nodes emitted before any store.
"""
function emit(p::Program{N}, k::Kernel{N}, o::CompileOptions; stages = LOWERING) where {N}
    lower, order = stages.index, stages.order
    L = lower(p, k, o)
    names = Dict{Tuple{Int32, Symbol}, Symbol}()
    head = Any[]
    for (l, as) in enumerate(L.args), (j, a) in enumerate(as)

        names[a] = Symbol(:a, l, :_, j)
        push!(head, :($(names[a]) = S[$l][$j]))
    end
    c = Ctx(p, k, o, L, names, stages.target)
    body = Any[]
    done = Set{Int32}()
    foreach(i -> _emit!(body, c, i, done), order(c))
    for s in k.stores
        _emit!(body, c, s.value, done)
        push!(body, _store(c, s))
    end
    needx = c.L.strategy == :cartesian || o.debug || k.space.kind == RESTRICTED ||
            any(n -> n.op in (COORD, INSIDE_OP), k.nodes) ||
            any(a -> !zero_offset(a), k.accesses)
    pre = needx ? _coords(c) : Any[]
    if k.space.kind != FULL
        body = Any[Expr(:if, _guard(c), Expr(:block, body...), Expr(:block, stages.passthrough(c)...))]
    end
    if L.strategy == :cartesian
        inb = foldl((x, y) -> :($x & $y),
            [:($(Symbol(:x, d)) <= $(_dim(c, k.space.level, d))) for d in 1:N])
        body = Any[Expr(:if, inb, Expr(:block, body...))]
    end
    sig = L.strategy == :cartesian ? (:x, :S, :P, :G) : (:s, :S, :P, :G)
    # Exec passes the site as `Int` (`@index` and the host loop); the body computes in `I`
    L.strategy == :cartesian || pushfirst!(head, :(s = s % $(o.I)))
    ex = Expr(:->, Expr(:tuple, sig...), Expr(
        :block, head..., pre..., body..., :(return nothing)))
    return _strip!(ex), L
end
