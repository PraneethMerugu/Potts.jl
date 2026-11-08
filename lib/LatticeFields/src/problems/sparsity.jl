# The Jacobian of the ODE right side (F4-07; F4 design §3.7, AF-01, SX-13): its sparsity
# pattern read off the IR, a distance-2 coloring of its columns, the colored Dual Jacobian
# (`jac = true`) and the Jacobian-vector product (`jvp`). The pattern comes from the semantic
# rate program the right side runs: every load's site (offsets, the boundary rules' ghost and
# clamp reads, coarse levels and restrictions, a hexagonal lattice's axial offsets), folded
# through the aux fields the program computes from the state. No tracing: the IR knows the
# stencil (SX-14).

# a field's rows' state columns in the walk (`SparseMatrixCSC`, column = row), or nothing
const _Deps = Union{Nothing, SparseArrays.SparseMatrixCSC{Bool, Int}}

"""
    _Walk

The state of the pattern walk over one kernel's value DAG at one site: the site `x` (in the
kernel's grid), a `RESTRICT`'s child offset and depth, the node stamps of the current scope,
and the state columns found (deduplicated by a stamp per column).
"""
mutable struct _Walk{N}
    s::Program{N}
    k::IR.Kernel{N}                          # the kernel (concrete: a node visit dispatches statically)
    deps::Vector{_Deps}                      # per field: its rows' state columns (`SparseMatrixCSC`, column = row) or nothing
    tdeps::Dict{Int32, Vector{Int}}          # per table a reduction fills: the state columns of its value
    seen::Vector{Int}
    stamp::Int
    counter::Int
    mark::Vector{Int}
    mstamp::Int
    buf::Vector{Int}
    x::NTuple{N, Int}
    child::NTuple{N, Int}
    depth::Int
end

# the coordinate of access `a` along axis `d` at offset `o` before wrapping, and the level it
# is taken on (the emitted index, `Compile._fine`)
function _pcoord(w::_Walk, a, d, o)
    L = Int(w.k.space.level)
    a.level >= 0 && return w.x[d] + o, L
    lev = L + Int(a.level)
    leveldims(w.s, lev)[d] == 1 && return w.x[d] + o, lev
    m = -Int(a.level)
    ch = w.depth > m ? w.child[d] >> (w.depth - m) : w.child[d]
    return (w.x[d] - 1) * (1 << m) + 1 + ch + o, lev
end

# the linear row of field `a.field` that access `a` (offset arm `off`, component `comp`) reads
# at the walk's site, or 0 when it reads none (a `ZERO` read outside, an `INSIDE` read past the
# box, which a guard never takes); the wrap, clamp and parent maps of `Compile._target`
function _prow(w::_Walk{N}, a, off, comp) where {N}
    s = w.s
    L = Int(w.k.space.level)
    flev = L + Int(a.level)
    ns = leveldims(s, flev)
    idx = 0
    stride = 1
    for d in 1:N
        o = Int(off[d])
        y, fl = _pcoord(w, a, d, o)
        nd = Int(leveldims(s, fl)[d])
        shifted = a.offset.cond != 0 || o != 0 || a.level < 0
        if shifted && a.policy != INSIDE && s.periodic[d]
            y = mod1(y, nd)
        elseif shifted && a.policy == CLAMP
            y = clamp(y, 1, nd)
        elseif !(1 <= y <= nd)
            return 0                          # (ZERO outside reads 0; INSIDE outside is never read)
        end
        if a.level > 0 && leveldims(s, fl)[d] != 1
            y = min(((y - 1) >> Int(a.level)) + 1, Int(ns[d]))
        end
        idx += (y - 1) * stride
        stride *= Int(ns[d])
    end
    return idx + 1 + (Int(comp) - 1) * stride
end

# the inside test of access `a` at the walk's site: 1 inside, 0 outside, -1 not known
function _pinside(w::_Walk{N}, a) where {N}
    a.offset.cond != 0 && return -1
    L = Int(w.k.space.level)
    for d in 1:N
        (a.offset.a[d] != 0 || a.level < 0) && !w.s.periodic[d] || continue
        y, fl = _pcoord(w, a, d, Int(a.offset.a[d]))
        1 <= y <= leveldims(w.s, a.level < 0 ? fl : L)[d] || return 0
    end
    return 1
end

# the value of the Bool node `i` at the walk's site when it is decided by the box alone (an
# inside test, a constant, their `NOT`, `AND`, `OR`): 1, 0, or -1 (data: both arms are kept)
function _pcond(w::_Walk, i)
    n = w.k.nodes[i]
    n.op == IR.CONST && return w.k.consts[n.imm] != 0 ? 1 : 0
    n.op == IR.INSIDE_OP && return _pinside(w, w.k.accesses[n.imm])
    a = IR.args(w.k, n)
    if n.op == IR.NOT
        c = _pcond(w, a[1])
        return c < 0 ? -1 : 1 - c
    elseif n.op == IR.AND || n.op == IR.OR
        z = n.op == IR.AND ? 0 : 1           # the absorbing value
        out = 1 - z
        for j in a
            c = _pcond(w, j)
            c == z && return z
            c < 0 && (out = -1)
        end
        return out
    end
    return -1
end

function _paddcols!(w::_Walk, D, row)
    rv = SparseArrays.rowvals(D)
    for r in SparseArrays.nzrange(D, row)
        j = rv[r]
        w.mark[j] == w.mstamp && continue
        w.mark[j] = w.mstamp
        push!(w.buf, j)
    end
    return nothing
end
function _pload!(w::_Walk, a)
    D = w.deps[a.field]
    D === nothing && return nothing
    for off in (a.offset.cond == 0 ? (a.offset.a,) : (a.offset.a, a.offset.b)),
        comp in (a.comp.cond == 0 ? (a.comp.a,) : (a.comp.a, a.comp.b))
        row = _prow(w, a, off, comp)
        row == 0 || _paddcols!(w, D, row)
    end
    return nothing
end

# the state columns the float value of node `i` reads at the walk's site (a Bool or integer
# value carries no derivative: a comparison, a table index, a select's condition)
function _pwalk!(w::_Walk{N}, i) where {N}
    w.seen[i] == w.stamp && return nothing
    w.seen[i] = w.stamp
    n = w.k.nodes[i]
    isfloat(n.type) || return nothing
    op = n.op
    if op == LOAD
        _pload!(w, w.k.accesses[n.imm])
    elseif op == IR.TABLE
        d = get(w.tdeps, Int32(n.imm), nothing)
        d === nothing || isempty(d) || _dense_refusal(w.s, n.imm)
    elseif op == IR.SELECT || op == IR.COND
        a = IR.args(w.k, n)
        c = _pcond(w, a[1])
        c == 0 || _pwalk!(w, a[2])
        c == 1 || _pwalk!(w, a[3])
    elseif op == IR.RESTRICT
        _prestrict!(w, i)
    else
        for j in IR.args(w.k, n)
            _pwalk!(w, j)
        end
    end
    return nothing
end

# a `RESTRICT` at a coarse site: its operand once per child (2 per coarsened axis, a third at
# the last site of an odd axis; `2^m` per axis for an operand `m` levels below), as emitted
function _prestrict!(w::_Walk{N}, i) where {N}
    k, s = w.k, w.s
    root = IR.args(k, k.nodes[i])[1]
    depth = 1
    for j in _pcone(k, root)
        nj = k.nodes[j]
        nj.op in (LOAD, IR.INSIDE_OP) && (depth = max(depth, -Int(k.accesses[nj.imm].level)))
    end
    L = Int(k.space.level)
    ranges = ntuple(d -> leveldims(s, L - depth)[d] == 1 ? (0:0) : depth == 1 ? (0:2) : (0:((1 << depth) - 1)), N)
    saved = w.stamp
    for o in Iterators.product(ranges...)
        # the third child exists only at the last site of an odd axis
        depth == 1 && any(d -> o[d] == 2 && !(w.x[d] == leveldims(s, L)[d] && leveldims(s, L - 1)[d] > 2 * leveldims(s, L)[d]),
            1:N) && continue
        w.counter += 1
        w.stamp = w.counter
        w.child, w.depth = o, depth
        _pwalk!(w, root)
    end
    w.stamp, w.child, w.depth = saved, ntuple(_ -> 0, N), 0
    return nothing
end
function _pcone(k, i)
    seen = Set{Int32}()
    todo = Int32[i]
    while !isempty(todo)
        j = pop!(todo)
        j in seen && continue
        push!(seen, j)
        append!(todo, IR.args(k, k.nodes[j]))
    end
    return seen
end

# the sites of kernel `k`'s space (a restricted space skips its inset)
function _psites(s::Program{N}, k) where {N}
    dims = Tuple(Int.(leveldims(s, k.space.level)))
    rs = ntuple(d -> k.space.kind == IR.RESTRICTED ? ((1 + k.space.inset[d][1]):(dims[d] - k.space.inset[d][2])) : (1:dims[d]), N)
    return CartesianIndices(rs), dims
end

# one kernel's stores and reductions: the state columns of each row it writes
function _pkernel!(deps, tdeps, s::Program{N}, k, n) where {N}
    sites, dims = _psites(s, k)
    nk = prod(dims)
    lin = LinearIndices(dims)
    w = _Walk{N}(s, k, deps, tdeps, zeros(Int, length(k.nodes)), 0, 0, zeros(Int, n), 0, Int[], ntuple(_ -> 1, N),
        ntuple(_ -> 0, N), 0)
    walk!(v, x) = (w.counter += 1; w.stamp = w.counter; w.mstamp += 1; empty!(w.buf); w.x = Tuple(x); _pwalk!(w, v); w.buf)
    out = Dict{Int32, Tuple{Vector{Int}, Vector{Int}, BitVector}}()      # field => (columns, rows, rows written)
    for st in k.stores
        f = st.access.field
        nrows = nsites(s, s.fields[f].levels[1]) * ncomp(s.fields[f])
        I, J, written = get!(() -> (Int[], Int[], falses(nrows)), out, f)
        comps = st.access.comp.cond == 0 ? (st.access.comp.a,) : (st.access.comp.a, st.access.comp.b)
        for x in sites
            cols = walk!(st.value, x)
            for c in comps
                row = lin[x] + (Int(c) - 1) * nk
                st.law === :accumulate || (written[row] = true)
                append!(I, cols)
                append!(J, Iterators.repeated(row, length(cols)))
            end
        end
    end
    for r in k.reductions
        acc = get!(() -> Int[], tdeps, r.target)
        for x in sites
            append!(acc, walk!(r.value, x))
        end
        unique!(acc)
    end
    for (f, (I, J, written)) in out
        nrows = length(written)
        old = deps[f]
        if old !== nothing                         # the rows the kernel does not overwrite keep theirs
            oI, oJ, _ = SparseArrays.findnz(old)
            keep = [!written[j] for j in oJ]
            I, J = [I; oI[keep]], [J; oJ[keep]]
        end
        deps[f] = SparseArrays.sparse(I, J, true, n, nrows, |)
    end
    return nothing
end

"""
    jacobian_sparsity(prob) -> SparseMatrixCSC{Bool, Int}

The sparsity pattern of the Jacobian `∂f/∂u` of the right side of `prob` (an `ODEProblem`
`discretize` returned), read off its IR (F4-07; F4 design §3.7): entry `(i, j)` is stored when
the rate of state entry `i` reads state entry `j` at some value of the state and parameters.
It holds every load of the rate program at its site (the stencil's offsets; a face's ghost
value, which reads the site on the face; a periodic wrap; a coarse field's parent and a
restriction's children; a hexagonal lattice's axial neighbors) and the aux fields computed
from the state in between (an aux chain is folded through). A select decided by the box (a
face's inside test) keeps the arm the site takes; one decided by data (a mask, `max`) keeps
both. A masked site keeps its row, so a mask that moves with an input write stays covered.
A rate that reads a reduction of the state (a sum over the lattice) would make the rows
dense: such a system is refused, with the route `jvp`.
"""
jacobian_sparsity(prob) = _sparsity(lattice_metadata(prob)::LatticeMetadata)
function _sparsity(m::LatticeMetadata)
    fp = m.problem
    m.family == :ode || throw(ArgumentError("a map's problem (a `DiscreteProblem`) has no Jacobian"))
    s = _sem(m)
    ids = Int[fieldid(s, k) for k in fp.state]
    slots = state_layout(s, ids)
    n = isempty(ids) ? 0 : maximum(last, slots[ids])
    deps = Vector{_Deps}(nothing, length(s.fields))
    for i in ids
        r = slots[i]
        deps[i] = SparseArrays.sparse(collect(r), collect(1:length(r)), true, n, length(r))
    end
    tdeps = Dict{Int32, Vector{Int}}()
    init = Set(fp.initkeys)
    ks = [[k for k in s.kernels if k.key in init]; [k for k in s.kernels if !(k.key in init)]]
    for k in ks
        _pkernel!(deps, tdeps, s, k, n)
    end
    I, J = Int[], Int[]
    for k in fp.state
        D = deps[fieldid(s, "∂" * k)]
        D === nothing && continue
        cols, rows, _ = SparseArrays.findnz(D)
        r0 = first(slots[fieldid(s, k)]) - 1
        append!(I, rows .+ r0)
        append!(J, cols)
    end
    return SparseArrays.sparse(I, J, true, n, n, |)
end
# a rate that reads a reduction of the state: every row is dense
_dense_refusal(s, t) = throw(ArgumentError(string("the rates read a reduction (a sum over the lattice) of the state, table `",
    s.tables[t].key, "`: every rate then depends on every site, so the Jacobian is dense and `sparse = true` and ",
    "`jac = true` are refused; the Jacobian-vector product (`jvp = true`, the default) with a Krylov linear solver ",
    "(`linsolve = KrylovJL_GMRES()`) is the route")))

"""
    column_colors(S[, coords]) -> Vector{Int}

A distance-2 coloring of the columns of `S`: two columns that share a row get different
colors, so one Dual evaluation with one partial per color gives every entry of the Jacobian
(F4-07). With the lattice coordinates of the columns (`coords`, one column per entry of the
state, `N` rows) a stencil's lattice coloring `(a ⋅ x) mod m` is tried first (5 colors for a
5-point stencil, 7 for a 3D 7-point one, 9 for a 9-point one, when the box allows it: a
periodic axis needs `m` to divide its size); otherwise, or when it takes more colors, the greedy
coloring in column order (7 for a 5-point stencil).
"""
function column_colors(S::SparseArrays.SparseMatrixCSC, coords = nothing)
    St = SparseArrays.sparse(transpose(S))
    g = _greedy_colors(S, St)
    coords === nothing && return g
    best = maximum(g; init = 0)
    lo = maximum((length(SparseArrays.nzrange(St, i)) for i in axes(St, 2)); init = 1)
    N = size(coords, 1)
    for m in lo:(best - 1), a in Iterators.product(ntuple(_ -> 1:min(m - 1, 4), N)...)
        a[1] == 1 || continue                    # (a multiple of a coloring is the same partition)
        c = [mod(sum(a[d] * coords[d, j] for d in 1:N), m) + 1 for j in axes(S, 2)]
        _valid_colors(S, St, c) && return c
    end
    return g
end
function _greedy_colors(S, St)
    n = size(S, 2)
    colors = zeros(Int, n)
    forbid = zeros(Int, n + 1)
    rv, rvt = SparseArrays.rowvals(S), SparseArrays.rowvals(St)
    for j in 1:n
        for k in SparseArrays.nzrange(S, j), k2 in SparseArrays.nzrange(St, rv[k])
            c = colors[rvt[k2]]
            c > 0 && (forbid[c] = j)
        end
        c = 1
        while forbid[c] == j
            c += 1
        end
        colors[j] = c
    end
    return colors
end
# whether no row of `S` (the columns of `St`) holds two columns of one color
function _valid_colors(S, St, c)
    seen = zeros(Int, maximum(c))
    rvt = SparseArrays.rowvals(St)
    for i in axes(St, 2)
        for k in SparseArrays.nzrange(St, i)
            q = c[rvt[k]]
            seen[q] == i && return false
            seen[q] = i
        end
    end
    return true
end
# the lattice coordinates of the state's entries (a field's sites on its own grid, the same for
# each component)
function _state_coords(fp::FieldProblem)
    s = fp.program
    N = _ndims(s)
    cols = Vector{Int}[]
    for k in fp.state
        f = s.fields[fieldid(s, k)]
        dims = Tuple(Int.(leveldims(s, f.levels[1])))
        for _ in 1:ncomp(f), x in CartesianIndices(dims)
            push!(cols, collect(Tuple(x)))
        end
    end
    return isempty(cols) ? zeros(Int, N, 0) : reduce(hcat, cols)
end

"""
    LatticeJacobian(meta, pattern, colors)

`jac = true` (F4-07): `J(Jm, u, p, t)` writes the Jacobian of the right side into `Jm` (the
problem's sparse `jac_prototype`, or a dense matrix), by colored forward-mode Duals of the
right side: one evaluation per chunk of at most `chunk` colors (12 by default), each partial
seeded on the columns of one color, and the entries of `pattern` read from them. Needs
ForwardDiff (its extension); the arrays are host arrays.
"""
struct LatticeJacobian{M}
    meta::M
    pattern::SparseArrays.SparseMatrixCSC{Bool, Int}
    colors::Vector{Int}
    chunk::Int
    cache::Dict{Type, Any}
    lock::ReentrantLock
end
LatticeJacobian(meta, pattern, colors; chunk = min(maximum(colors; init = 1), 12)) =
    LatticeJacobian(meta, pattern, colors, chunk, Dict{Type, Any}(), ReentrantLock())
Base.deepcopy_internal(j::LatticeJacobian, ::IdDict) = LatticeJacobian(j.meta, j.pattern, j.colors; chunk = j.chunk)
(j::LatticeJacobian)(J, u, p, t) = colored_jacobian!(J, j, u, p, t)

"""
    LatticeJVP(meta)

The Jacobian-vector product of the right side (F4-07; F4 design §3.7): `jvp(Jv, v, u, p, t)`
sets `Jv = (∂f/∂u)(u, p, t) v` by one evaluation of the right side on Duals with one partial
(`u + ε v`), on the problem's backend. Set on every `ODEProblem` `discretize` returns; it
needs ForwardDiff (its extension, which OrdinaryDiffEq's implicit solvers load).
"""
struct LatticeJVP{M}
    meta::M
    cache::Dict{Type, Any}
    lock::ReentrantLock
    calls::Base.RefValue{Int}                # the products taken (a test reads it; shared by copies)
end
LatticeJVP(meta) = LatticeJVP(meta, Dict{Type, Any}(), ReentrantLock(), Ref(0))
Base.deepcopy_internal(j::LatticeJVP, ::IdDict) = LatticeJVP(j.meta, Dict{Type, Any}(), ReentrantLock(), j.calls)
(j::LatticeJVP)(Jv, v, u, p, t) = (j.calls[] += 1; lattice_jvp!(Jv, j, v, u, p, t))

"""
    colored_jacobian!(J, jac::LatticeJacobian, u, p, t) -> J
    lattice_jvp!(Jv, jvp::LatticeJVP, v, u, p, t) -> Jv

The colored Dual Jacobian and the Jacobian-vector product (methods in the ForwardDiff
extension).
"""
function colored_jacobian! end
function lattice_jvp! end
colored_jacobian!(J, j, u, p, t) = throw(ArgumentError("`jac = true` evaluates the right side on ForwardDiff Duals: load ForwardDiff"))
lattice_jvp!(Jv, j, v, u, p, t) = throw(ArgumentError("the Jacobian-vector product evaluates the right side on ForwardDiff Duals: load ForwardDiff"))

"""
    JacobianOperator(jvp, u, p, t)

The matrix-free Jacobian of a problem on a device (F4 design §3.10, ruling Q7): a
`SciMLOperators.FunctionOperator` whose product is [`LatticeJVP`](@ref), the `jac_prototype`
of an `ODEProblem` on a device, so an implicit OrdinaryDiffEq solver forms `W = J − M/γ` as an
operator and solves it with a Krylov method (precondition it with `LatticeMG()`).
"""
function JacobianOperator(jvp::LatticeJVP, u, p, t)
    return SciMLOperators.FunctionOperator(jvp, u, u; u, p, t, isinplace = true, outofplace = false,
        T = eltype(u), isconstant = false, islinear = true)
end

# the Jacobian keywords of `lattice_problem` (`jac`, `sparse`, `jvp`) as `ODEFunction` keywords:
# the sparse prototype (the pattern with its diagonal, which `W = J − M/γ` holds) and its
# coloring on the host; the matrix-free operator on a device (Q7)
function _jacobian_kw(meta::LatticeMetadata, U, lp; jac::Bool, sparse::Bool, jvp::Bool)
    fp = meta.problem
    host = Exec.ishost(fp.backend)
    if !host && (sparse || jac)
        throw(ArgumentError(string("`", sparse ? "sparse" : "jac", " = true` builds a sparse matrix on the host; the ",
            "problem's backend is ", nameof(typeof(fp.backend)), ", and no KernelAbstractions sparse matrix exists ",
            "(a hardware limit): on a device the Jacobian is the matrix-free product (`jvp = true`, the default), ",
            "the problem's `jac_prototype`, for a Krylov linear solver with `precs = LatticeMG()`")))
    end
    kw = (;)
    j = LatticeJVP(meta)
    jvp && (kw = (; kw..., jvp = j))
    if sparse || jac
        P = _sparsity(meta)
        n = size(P, 1)
        P = P .| SparseArrays.sparse(1:n, 1:n, true, n, n)
        proto = SparseArrays.SparseMatrixCSC{valtype(eltype(U)), Int}(P)
        fill!(SparseArrays.nonzeros(proto), zero(eltype(SparseArrays.nonzeros(proto))))
        colors = column_colors(proto, _state_coords(fp))
        sparse && (kw = (; kw..., jac_prototype = proto, colorvec = colors))
        jac && (kw = (; kw..., jac = LatticeJacobian(meta, P, colors)))
    elseif !host && jvp
        kw = (; kw..., jac_prototype = JacobianOperator(j, U, lp, fp.tspan[1]))
    end
    return kw
end
