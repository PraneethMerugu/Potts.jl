# The solver program: one IR program per solver group with the fields of every level, the
# operator's input fields and the device scalars, and the generated kernels (§6.3): the
# fill and lift kernels from the operator spec, and per level above the bottom the Chebyshev
# steps, the fused residual + restriction and the fused prolongation + first post step;
# on the finest level the residual norm and the PCG kernels K1, K2 and the true residual.

"""
    CellOperator(dims; periodic, face, shift, mask, value, dirichlet)

A cell-centered Helmholtz operator in coefficient form, the input of a solver group:
`A u = s u + Σ_faces w (u − u_nb)` on active sites, with

  - `face[a]`: the face coefficient to `+e_a`, a number or the key of an input field;
  - `shift`: `s`, a number or an input field key;
  - `mask`: key of a `U8` input field, nonzero = masked Dirichlet node with `value` (a number
    or an input field key);
  - `dirichlet[a] = (g_low, g_high)`: face-Dirichlet values on a non-periodic axis
    (`nothing`: no flux); the ghost rule adds `2w` to the diagonal and `2w g` to the
    right-hand side, so a Dirichlet axis needs a constant `face[a]`.
    The right-hand side is the input field `"in.f"`. Masked rows are eliminated (§3.5).
"""
struct CellOperator{N}
    dims::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    face::NTuple{N, Union{Float64, String}}
    shift::Union{Float64, String}
    mask::Union{Nothing, String}
    value::Union{Float64, String}
    dirichlet::NTuple{N, NTuple{2, Union{Nothing, Float64}}}
end
function CellOperator(dims::NTuple{N, Integer}; periodic = ntuple(_ -> false, N),
        face = ntuple(_ -> 1.0, N), shift = 0.0, mask = nothing, value = 0.0,
        dirichlet = ntuple(_ -> (nothing, nothing), N)) where {N}
    num(x) = x isa Real ? Float64(x) : String(x)
    for a in 1:N
        any(!isnothing, dirichlet[a]) && (periodic[a] || !(face[a] isa Real)) &&
            irerror("axis ", a, ": a face-Dirichlet axis must be non-periodic with a ",
                "constant face coefficient")
    end
    check_coefficients(face, shift, value, dirichlet)
    return CellOperator{N}(Int.(dims), Tuple(periodic), map(num, Tuple(face)), num(shift),
        mask === nothing ? nothing : String(mask), num(value),
        map(d -> map(g -> g === nothing ? nothing : Float64(g), Tuple(d)), Tuple(dirichlet)))
end
"""
Is the group anchored by a mask or a face-Dirichlet value? An unanchored group has the
near-null constant mode (eigenvalue `s`), which PCG deflates (`unanchored`).
"""
function anchored(op::CellOperator)
    op.mask !== nothing || any(d -> any(!isnothing, d), op.dirichlet)
end
"""
Can the solve deflate the constant mode: no anchor and a constant shift (then `A·1 = s·1` and
`A` maps zero-mean vectors to zero-mean vectors)?
"""
deflatable(op::CellOperator) = !anchored(op) && op.shift isa Real
"""
Numeric coefficients must be finite and keep the operator an M-matrix: shift `s ≥ 0` (a
negative shift is indefinite and breaks the smoother bound λ = 2) and faces `> 0` (a
non-positive face runs to the budget at ‖r‖/‖b‖ = 1); the mask and Dirichlet values must be
finite. Field-valued coefficients are not checked here.
"""
function check_coefficients(face, shift, value, dirichlet)
    fin(x) = !(x isa Real) || isfinite(x)
    fin(shift) && !(shift isa Real && !(shift >= 0)) ||
        irerror("shift must be finite and ≥ 0; got ", shift)
    for (a, f) in enumerate(face)
        fin(f) && !(f isa Real && !(f > 0)) ||
            irerror("face[", a, "] must be finite and > 0; got ", f)
    end
    fin(value) || irerror("value must be finite; got ", value)
    for (a, d) in enumerate(dirichlet), g in d

        g === nothing || fin(g) ||
            irerror("dirichlet[", a, "] values must be finite; got ", g)
    end
    return nothing
end

"""
Reactions weaker than this, relative to the strongest face (`s / max(face) < FLOOR_SHIFT`),
put an unanchored group in the Float32 floor regime, where Float32 PCG cannot reach
‖r‖∞ ≤ 1e-6‖b‖∞. The floor is invariant under scaling `s` and the faces together. Measured
(C7b R5, Float32 solver, faces 0.01, 1 and 100, the same results at each scale): per256
floors at s/face ≤ 0.05 and converges at ≥ 0.1; Neumann-x/periodic-y (128×96) floors at
s/face ≤ 0.2 (best 1.0e-6–1.6e-6 at 0.2) and converges at 0.5 (5 iterations); at s/face = 1
both converge in 4 iterations. Earlier: per256 1e-4 at s = 5.5e-6, pure Neumann 3.4e-5 at s = 0.
"""
const FLOOR_SHIFT = 0.5
"""
Is the group in the Float32 floor regime: unanchored, with its weakest reaction relative to
its strongest face below `FLOOR_SHIFT`? A field-valued shift or face counts as weak (its
range is not known at build time). `solver_T = :auto` solves such groups in Float64
(provisional D-C7b).
"""
function floor_regime(op::CellOperator{N}) where {N}
    anchored(op) && return false
    (op.shift isa Real && all(f -> f isa Real, op.face)) || return true
    w = maximum((op.face[a] for a in 1:N if op.dims[a] > 1); init = 0.0)
    return op.shift < FLOOR_SHIFT * w
end
"""
Does the group have a mask, a Dirichlet face or a non-constant face coefficient (§5.6)?
"""
function jumpy(op::CellOperator)
    op.mask !== nothing ||
        any(d -> any(!isnothing, d), op.dirichlet) ||
        any(f -> f isa String, op.face)
end

"""
The runtime parameter slots of the operator's numeric coefficients (v3 §3.1, P5 C7b-2):
`(; face, shift, value, dirichlet)` with slot 0 for a coefficient that is a field key or
absent. Coefficients are parameters, not constants: a change of value never recompiles,
and the slot order is `coef_values(op)`.
"""
function coef_slots(op::CellOperator{N}) where {N}
    n = Ref(0)
    next(x) = x isa Real ? (n[] += 1) : 0
    face = ntuple(a -> next(op.face[a]), N)
    shift, value = next(op.shift), next(op.value)
    dirichlet = ntuple(a -> map(next, op.dirichlet[a]), N)
    return (; face, shift, value, dirichlet, n = n[])
end
"""
The numeric coefficients of `op` in slot order (`coef_slots`).
"""
function coef_values(op::CellOperator{N}) where {N}
    v = Float64[]
    foreach(f -> f isa Real && push!(v, f), op.face)
    op.shift isa Real && push!(v, op.shift)
    op.value isa Real && push!(v, op.value)
    for d in op.dirichlet, g in d

        g isa Real && push!(v, g)
    end
    return Tuple(v)
end

const LDS_SITES = 4096          # levels with at most this many sites run in the bottom
const SCALARS = 24              # device scalars (below); the rest are spare
# `DONE`: 0 running, 1 converged, 2 floor (stagnated at rounding level above the
# tolerance), 3 diverged; every gate reads it.
# `BEST`/`STALL`: best true residual and the count of checks without improvement.
# `MEAN`: the constant-mode coefficient `c`; `ZMEAN`/`XMEAN`/`BMEAN`: means of `z`, `x`, `b`.
# `SCALE`: the rounding scale max(|b| + |A||x|) of the last check; `PREV`/`GROW`: the last
# true residual and the count of consecutive checks that grew.
const DONE, ITER, RZ, ALPHA, BETA, RNORM, BNORM, TOL, WARN = 1:9
const BEST, STALL, MEAN, ZMEAN, XMEAN, BMEAN, SCALE, PREV, GROW = 11:19

"""
Hierarchy depth: coarsen while no axis of size > 1 would reach 0 sites (never coarsen an
axis of size 1); the bottom starts at the first level with at most `LDS_SITES` sites.
"""
function depth(dims::NTuple{N, Int}) where {N}
    big = [d for d in dims if d > 1]
    isempty(big) && irerror("a multigrid solve needs an axis with more than one site")
    L = floor(Int, log2(minimum(big)))
    L >= 1 || irerror("dims ", dims, " cannot be coarsened")
    lb = something(findfirst(l -> prod(leveldims(Level(Grid(dims), l))) <= LDS_SITES, 1:L), L)
    return L, lb
end

lkey(l, name) = string("L", lpad(l, 2, '0'), ".", name)

struct LevelFields{N}
    active::Int32
    w::NTuple{N, Int32}
    s::Int32
    sbox::Int32
    sint::Int32
    x::Int32
    b::Int32
    d::Int32
    r::Int32
end

_unit(N, a, σ) = ntuple(d -> d == a ? σ : 0, N)
_real(x::Ex) = cast(x, REAL)
_and(x::Ex, y::Ex) = Ex(x.b, node!(x.b, AND, BOOL, Int32[x.id, y.id]))
_not(x::Ex) = Ex(x.b, node!(x.b, NOT, BOOL, Int32[x.id]))
function _inside(kb::KernelBuilder{N}, f, off) where {N}
    a = Access{N}(
        Int32(f), Int8(0), Sel(Int16(1)), Sel(NTuple{N, Int16}(off)), Int8(0), INSIDE)
    return Ex(kb, node!(kb, INSIDE_OP, BOOL, Int32[], access!(kb, a)))
end
_scal(kb, t, i) = table(kb, t, F32, constant(kb, i, I32))

"""
`A x` and the diagonal at the kernel's site on level fields `F` (`lev` relative level,
−1 inside a RESTRICT); `xget(o)` is `x` at offset `o`. Flux-difference form.
"""
function _apply(kb::KernelBuilder{N}, F::LevelFields{N}, per, dims, xget; lev = 0) where {N}
    L(f; o = ntuple(_ -> 0, N), pol = IR.RESOLVE) = load(kb, f; offset = o, level = lev,
        policy = all(iszero, o) ? IR.RESOLVE : pol)
    c = L(F.s) + L(F.sbox) + L(F.sint)
    x0 = xget(ntuple(_ -> 0, N))
    D, Ax = c, c * x0
    for a in 1:N, σ in (1, -1)

        dims[a] == 1 && continue
        o = _unit(N, a, σ)
        w = σ > 0 ? L(F.w[a]) :
            L(F.w[a]; o, pol = per[a] ? IR.CLAMP : IR.ZERO)
        xj = _real(L(F.active; o, pol = IR.CLAMP)) * xget(o)
        D, Ax = D + w, Ax + w * (x0 - xj)
    end
    return Ax, D
end

"""
The rounding scale of the residual `b − A x` at the kernel's site: `|b| + (|A||x|)`, with
`aget(o)` the stored `x` at offset `o` (the floor test, `Solvers._stop!`).
"""
function _roundscale(kb::KernelBuilder{N}, F::LevelFields{N}, per, dims, b, aget) where {N}
    L(f; o = ntuple(_ -> 0, N), pol = IR.RESOLVE) = load(kb, f; offset = o,
        policy = all(iszero, o) ? IR.RESOLVE : pol)
    x0 = abs(aget(ntuple(_ -> 0, N)))
    sc = abs(b) + (L(F.s) + L(F.sbox) + L(F.sint)) * x0
    for a in 1:N, σ in (1, -1)

        dims[a] == 1 && continue
        o = _unit(N, a, σ)
        w = σ > 0 ? L(F.w[a]) :
            L(F.w[a]; o, pol = per[a] ? IR.CLAMP : IR.ZERO)
        sc = sc + w * (x0 + _real(L(F.active; o, pol = IR.CLAMP)) * abs(aget(o)))
    end
    return sc
end

"""
The solver program for operator `op`: `pcg` adds the PCG fields and kernels; `deflate` the
constant-mode deflation (needs `pcg` and `deflatable(op)`). `lane` is the solver's number
type, `state` that of the caller-facing arrays (inputs and solution): when they differ
and there is no deflated `pcg.u`, the solution is copied into `out.u` (kernel `solve.out`).
"""
function solver_program(op::CellOperator{N}, pcg::Bool; lane = F32, state = lane,
        deflate::Bool = false) where {N}
    deflate && !(pcg && deflatable(op)) &&
        irerror("deflation needs PCG on an unanchored group with a constant shift")
    L, lb = depth(op.dims)
    cs = coef_slots(op)
    pb = ProgramBuilder(Grid(op.dims); periodic = op.periodic, levels = L + 1,
        nparams = cs.n)
    lv = map(0:L) do l
        f(name; kw...) = field!(pb, lkey(l, name); levels = [l], storage = lane, kw...)
        LevelFields{N}(f("active"; storage = U8, role = :aux),
            ntuple(a -> f("w$a"; role = :aux), N), f("s"; role = :aux),
            f("sbox"; role = :aux), f("sint"; role = :aux),
            f("x"; buffers = l < lb ? 2 : 1), f("b"; role = :aux), f("d"; role = :scratch),
            l >= lb ? f("r"; role = :scratch) : Int32(0))
    end
    input(k; kw...) = field!(pb, k; role = :input, storage = state, kw...)
    inp = (; f = input("in.f"),
        mask = op.mask === nothing ? Int32(0) : input(op.mask; storage = U8),
        value = op.value isa String ? input(op.value) : Int32(0),
        shift = op.shift isa String ? input(op.shift) : Int32(0),
        face = map(f -> f isa String ? input(f) : Int32(0), op.face))
    pf = pcg ?
         (; x = field!(pb, "pcg.x"; buffers = 2, storage = lane),
        b = field!(pb, "pcg.b"; role = :aux, storage = lane),
        p = field!(pb, "pcg.p"; buffers = 2, storage = lane),
        u = deflate ? field!(pb, "pcg.u"; storage = state) : Int32(0)) :
         nothing
    tab(k) = table!(pb, k; storage = lane, oob = :none)
    tb = (; scal = tab("solve.scal"), pr = tab("solve.pr"), pb = tab("solve.pb"),
        pd = tab("solve.pd"), px = tab("solve.px"), gb = tab("solve.gb"),
        ps = deflate ? tab("solve.ps") : Int32(0),
        pq = deflate ? tab("solve.pq") : Int32(0))
    ctx = (; pb, op, cs, lv, inp, pf, tb, L, lb, lane, deflate,
        dims = [Int.(leveldims(Level(Grid(op.dims), l))) for l in 0:L])
    _fill!(ctx)
    _lift!(ctx)
    for l in 0:(lb - 1)
        for zero_ in (false, true), rz in (false, true)

            (rz && l > 0) || _step!(ctx, l; zero_, rz)
        end
        foreach(rz -> (rz && l > 0) || _prolong!(ctx, l; rz), (false, true))
        _restrict!(ctx, l + 1)
    end
    _resid!(ctx)
    pcg && _pcg!(ctx)
    _tangent!(ctx)
    if state != lane && !deflate          # the solution in the state type (ungated)
        out = field!(pb, "out.u"; storage = state)
        kb = kernel(pb)
        store(kb, out, load(kb, pcg ? ctx.pf.x : lv[1].x))
        add!(pb, kb, "solve.out")
    end
    p = check_no_time(program(pb))         # renumbers ids by key: remap the handles
    fm(i) = i == 0 ? Int32(0) : fieldid(p, pb.fields[i].key)
    lvm = [LevelFields{N}(
               fm(F.active), map(fm, F.w), fm(F.s), fm(F.sbox), fm(F.sint), fm(F.x),
               fm(F.b), fm(F.d), fm(F.r)) for F in lv]
    return p, (; L, lb, dims = ctx.dims, lv = lvm)
end

_notdone(kb, tb) = eq(_scal(kb, tb.scal, DONE), 0.0)
_masked(kb, F) = eq(load(kb, F.active), 0)
_sel(kb, F, v) = select(_masked(kb, F), 0.0, v)

function _face_in(kb::KernelBuilder{N}, ctx, a; o = ntuple(_ -> 0, N)) where {N}
    f = ctx.op.face[a]
    f isa Real && return param(kb, ctx.cs.face[a])
    pol = all(iszero, o) ? IR.RESOLVE : ctx.op.periodic[a] ? IR.CLAMP : IR.ZERO
    return load(kb, ctx.inp.face[a]; offset = o, policy = pol)
end
_num(kb, v::Real, f, slot; kw...) = param(kb, slot)
_num(kb, v::String, f, slot; kw...) = load(kb, f; kw...)

"""
Fill the finest level's coefficients from the spec (active, raw faces, shift, box absorption).
"""
function _fill!(ctx)
    op, F, pb = ctx.op, ctx.lv[1], ctx.pb
    N = length(op.dims)
    kb = kernel(pb)
    active = ctx.inp.mask == 0 ? constant(kb, 1.0) :
          select(eq(load(kb, ctx.inp.mask), 0), 1.0, 0.0)
    store(kb, F.active, cast(active, U8))
    sbox = constant(kb, 0.0)
    for a in 1:N
        w = op.dims[a] == 1 ? constant(kb, 0.0) : _face_in(kb, ctx, a)
        op.periodic[a] || (w = select(_inside(kb, ctx.inp.f, _unit(N, a, 1)), w, 0.0))
        store(kb, F.w[a], w)
        for (k, σ) in enumerate((-1, 1))
            op.dirichlet[a][k] === nothing && continue
            sbox = sbox +
                   select(_inside(kb, ctx.inp.f, _unit(N, a, σ)), 0.0,
                2 * _face_in(kb, ctx, a))
        end
    end
    store(kb, F.s, _num(kb, op.shift, ctx.inp.shift, ctx.cs.shift))
    store(kb, F.sbox, sbox)
    store(kb, F.sint, 0.0)
    add!(pb, kb, "fill")
end

"""
The eliminated right-hand side: `f` plus mask faces `w·value` plus Dirichlet faces `2w·g`.
"""
function _lift!(ctx)
    op, F, pb = ctx.op, ctx.lv[1], ctx.pb
    N = length(op.dims)
    kb = kernel(pb)
    b = load(kb, ctx.inp.f)
    for a in 1:N, (k, σ) in enumerate((-1, 1))

        op.dims[a] == 1 && continue
        o = _unit(N, a, σ)
        if ctx.inp.mask != 0
            w = σ > 0 ? _face_in(kb, ctx, a) : _face_in(kb, ctx, a; o)
            hit = Ex(kb,
                compare!(
                    kb, IR.EQ, load(kb, ctx.inp.mask; offset = o,
                        policy = IR.CLAMP).id,
                    constant!(kb, 0.0, U8)))
            hit = _not(hit)
            op.periodic[a] || (hit = _and(hit, _inside(kb, ctx.inp.f, o)))
            v = _num(kb, op.value, ctx.inp.value, ctx.cs.value; offset = o,
                policy = IR.CLAMP)
            b = b + select(hit, w * v, 0.0)
        end
        g = op.dirichlet[a][k]
        g === nothing || (b = b + select(_inside(kb, ctx.inp.f, o), 0.0,
            2 * _face_in(kb, ctx, a) * param(kb, ctx.cs.dirichlet[a][k])))
    end
    target = ctx.pf === nothing ? F.b : ctx.pf.b
    mk = ctx.inp.mask == 0 ? b : select(eq(load(kb, ctx.inp.mask), 0), b, 0.0)
    store(kb, target, mk)
    add!(pb, kb, "lift")
end

"""
The solvers' two launch-varying scalars (Chebyshev coefficients, the `tangent.rhs` flag):
runtime slots `TIME_SLOT + 1` and `TIME_SLOT + 2`. Slot `TIME_SLOT` is reserved for the
time `t` (contract item 4), which the hoisting pass computes on the host; no solver
kernel reads it (`check_no_time`).
"""
const SOLVER_RT = (TIME_SLOT + 1, TIME_SLOT + 2)
_cheb_rt(kb) = (runtime(kb, SOLVER_RT[1]), runtime(kb, SOLVER_RT[2]))

"""
Refuse a solver program with a kernel that reads the time slot: such a subtree would be
hoisted to the host and frozen at the launch's `t`.
"""
function check_no_time(p::Program)
    for k in p.kernels, n in k.nodes
        n.op == RUNTIME && n.imm == TIME_SLOT &&
            irerror("solver kernel `", k.key, "` reads the time slot G.rt[", TIME_SLOT, "]")
    end
    return p
end

"""
Chebyshev step on level `l`: `d ← c₁d + c₂D⁻¹(b − Ax)`, `x ← x + d` (`zero_`: from x = 0);
`rz` adds the partial `Σ b·x` (the preconditioner's `r·z`) on the finest level.
"""
function _step!(ctx, l; zero_ = false, rz = false)
    F, pb, N = ctx.lv[l + 1], ctx.pb, length(ctx.op.dims)
    kb = kernel(pb, Space{N}(; level = l))
    gate!(kb, _notdone(kb, ctx.tb))
    c1, c2 = _cheb_rt(kb)
    b = load(kb, F.b)
    xget = o -> load(kb, F.x; offset = o, policy = all(iszero, o) ? IR.RESOLVE : IR.CLAMP)
    Ax, D = _apply(kb, F, ctx.op.periodic, ctx.dims[l + 1], xget)
    if zero_
        dn = c2 * b / D
        xn = dn
    else
        dn = c1 * load(kb, F.d) + c2 * (b - Ax) / D
        xn = xget(ntuple(_ -> 0, N)) + dn
    end
    store(kb, F.x, _sel(kb, F, xn))
    store(kb, F.d, _sel(kb, F, dn))
    rz && _rz!(kb, ctx, b, _sel(kb, F, xn))
    add!(pb, kb, string(zero_ ? "zstep" : "step", rz ? ".rz" : "", ".", lkey(l, "")))
end

"""
The preconditioner's partial sums on the finest level: `Σ r·z`, and under deflation `Σ z`
and `Σ r` (for `r·(z − z̄)`).
"""
function _rz!(kb, ctx, r, z)
    reduce!(kb, :sum, r * z, ctx.tb.pd)
    if ctx.deflate
        reduce!(kb, :sum, z, ctx.tb.ps)
        reduce!(kb, :sum, r, ctx.tb.pq)
    end
    return nothing
end

"""
Prolongation fused with the first post-smoothing step: `x′ = x + active·e(parent)` at every
stencil point, then a fresh Chebyshev step on `x′`.
"""
function _prolong!(ctx, l; rz = false)
    F, C, pb, N = ctx.lv[l + 1], ctx.lv[l + 2], ctx.pb, length(ctx.op.dims)
    kb = kernel(pb, Space{N}(; level = l))
    gate!(kb, _notdone(kb, ctx.tb))
    _, c2 = _cheb_rt(kb)
    function xget(o)
        z = all(iszero, o)
        pol = z ? IR.RESOLVE : IR.CLAMP
        load(kb, F.x; offset = o, policy = pol) +
        _real(load(kb, F.active; offset = o, policy = pol)) *
        load(kb, C.x; offset = o, level = 1, policy = z ? IR.RESOLVE : IR.CLAMP)
    end
    b = load(kb, F.b)
    Ax, D = _apply(kb, F, ctx.op.periodic, ctx.dims[l + 1], xget)
    dn = c2 * (b - Ax) / D
    xn = xget(ntuple(_ -> 0, N)) + dn
    store(kb, F.x, _sel(kb, F, xn))
    store(kb, F.d, _sel(kb, F, dn))
    rz && _rz!(kb, ctx, b, _sel(kb, F, xn))
    add!(pb, kb, string("prolong", rz ? ".rz" : "", ".", lkey(l, "")))
end

"""
Fused residual and restriction into level `l`: `b_c = Σ_children active·(b − A x)` (R = Pᵀ).
"""
function _restrict!(ctx, l)
    F, C, pb, N = ctx.lv[l], ctx.lv[l + 1], ctx.pb, length(ctx.op.dims)
    kb = kernel(pb, Space{N}(; level = l))
    gate!(kb, _notdone(kb, ctx.tb))
    xget = o -> load(kb, F.x; offset = o, level = -1,
        policy = all(iszero, o) ? IR.RESOLVE : IR.CLAMP)
    Ax, _ = _apply(kb, F, ctx.op.periodic, ctx.dims[l], xget; lev = -1)
    r = _real(load(kb, F.active; level = -1)) * (load(kb, F.b; level = -1) - Ax)
    store(kb, C.b, restrict(r))
    add!(pb, kb, string("restrict.", lkey(l, "")))
end

"""
Finest-level residual norms: partial max |b − A x| and max |b| over active sites.
"""
function _resid!(ctx)
    F, pb = ctx.lv[1], ctx.pb
    kb = kernel(pb)
    gate!(kb, _notdone(kb, ctx.tb))
    xget = o -> load(kb, F.x; offset = o, policy = all(iszero, o) ? IR.RESOLVE : IR.CLAMP)
    Ax, _ = _apply(kb, F, ctx.op.periodic, ctx.dims[1], xget)
    b = load(kb, F.b)
    reduce!(kb, :max, abs(_sel(kb, F, b - Ax)), ctx.tb.pr)
    reduce!(kb, :max, abs(_sel(kb, F, b)), ctx.tb.pb)
    sc = _roundscale(kb, F, ctx.op.periodic, ctx.dims[1], b, xget)
    reduce!(kb, :max, _sel(kb, F, sc), ctx.tb.px)
    add!(pb, kb, "resid")
end

"""
PCG kernels (P3-mg §6): K1 (`p ← z + βp` at the stencil points, partial `p·Ap`), K2 (`x ← x

  - αp`into the other buffer, the true residual`r = b − A(x + αp)`from the stencil points, partial ‖r‖∞; N-13 on every iteration) and the setup residual`pcg.true` (`r = b − A x`, partial ‖r‖∞ and ‖b‖∞). Under deflation `z`, `x`and`b` enter minus their means.
"""
function _pcg!(ctx)
    F, pb, pf, tb, N = ctx.lv[1], ctx.pb, ctx.pf, ctx.tb, length(ctx.op.dims)
    per, dims, dfl = ctx.op.periodic, ctx.dims[1], ctx.deflate
    pol(o) = all(iszero, o) ? IR.RESOLVE : IR.CLAMP
    ld(kb, f, o) = load(kb, f; offset = o, policy = pol(o))
    o0 = ntuple(_ -> 0, N)
    kb = kernel(pb)
    gate!(kb, _notdone(kb, tb))
    β = _scal(kb, tb.scal, BETA)
    zm = dfl ? _scal(kb, tb.scal, ZMEAN) : nothing
    zget = o -> dfl ? ld(kb, F.x, o) - zm : ld(kb, F.x, o)
    pget = o -> zget(o) + β * ld(kb, pf.p, o)
    Ap, _ = _apply(kb, F, per, dims, pget)
    p0 = _sel(kb, F, pget(o0))
    store(kb, pf.p, p0)
    reduce!(kb, :sum, p0 * _sel(kb, F, Ap), tb.pd)
    add!(pb, kb, "pcg.k1")
    function residual(kb, xget, aget)     # aget: the stored x (the rounding scale)
        Ax, _ = _apply(kb, F, per, dims, xget)
        b = load(kb, pf.b)
        r = _sel(kb, F, (dfl ? b - _scal(kb, tb.scal, BMEAN) : b) - Ax)
        store(kb, F.b, r)
        reduce!(kb, :max, abs(r), tb.pr)
        reduce!(kb, :max, _sel(kb, F, _roundscale(kb, F, per, dims, b, aget)), tb.px)
        return b
    end
    kb = kernel(pb)
    gate!(kb, _notdone(kb, tb))
    α = _scal(kb, tb.scal, ALPHA)
    xm1 = dfl ? _scal(kb, tb.scal, XMEAN) : nothing
    xnew = o -> ld(kb, pf.x, o) + α * ld(kb, pf.p, o)
    store(kb, pf.x, xnew(o0))
    residual(kb, o -> dfl ? xnew(o) - xm1 : xnew(o), xnew)
    add!(pb, kb, "pcg.k2")
    kb = kernel(pb)
    gate!(kb, _notdone(kb, tb))
    xm2 = dfl ? _scal(kb, tb.scal, XMEAN) : nothing
    b = residual(kb, o -> dfl ? ld(kb, pf.x, o) - xm2 : ld(kb, pf.x, o), o -> ld(kb, pf.x, o))
    reduce!(kb, :max, abs(_sel(kb, F, b)), tb.pb)
    add!(pb, kb, "pcg.true")
    dfl || return nothing
    kb = kernel(pb)                       # the means of b and of the working x
    reduce!(kb, :sum, load(kb, pf.b), tb.ps)
    reduce!(kb, :sum, load(kb, pf.x), tb.pq)
    add!(pb, kb, "pcg.center")
    kb = kernel(pb)                       # the solution: zero-mean part plus c (ungated)
    store(kb, pf.u, load(kb, pf.x) - _scal(kb, tb.scal, XMEAN) + _scal(kb, tb.scal, MEAN))
    add!(pb, kb, "pcg.out")
end

"""
Tangent-solve kernels (`Solvers.tangent!`), on the finest level, ungated, reusing the
working field (holding `u`), the scratch `d` and the right-hand side `b` (`pcg.b` under PCG):
`tangent.r0`: `d ← b − A u`; `tangent.dr`: `d ← (b − A u) − d` (so `r(θ + 1, u) − r(θ, u)`
after a coefficient change); `tangent.rhs`: `b ← d + c·(b − f)` (`c = 0`: homogeneous
boundary values; `c = 1` keeps the primal ones, the negative control).
"""
function _tangent!(ctx)
    F, pb = ctx.lv[1], ctx.pb
    x, bt = ctx.pf === nothing ? (F.x, F.b) : (ctx.pf.x, ctx.pf.b)
    for (key, diff) in (("tangent.r0", false), ("tangent.dr", true))
        kb = kernel(pb)
        xget = o -> load(kb, x; offset = o,
            policy = all(iszero, o) ? IR.RESOLVE : IR.CLAMP)
        Ax, _ = _apply(kb, F, ctx.op.periodic, ctx.dims[1], xget)
        r = _sel(kb, F, load(kb, bt) - Ax)
        store(kb, F.d, diff ? r - load(kb, F.d) : r)
        add!(pb, kb, key)
    end
    kb = kernel(pb)
    c, _ = _cheb_rt(kb)
    store(kb, bt, _sel(kb, F, load(kb, F.d) + c * (load(kb, bt) - load(kb, ctx.inp.f))))
    add!(pb, kb, "tangent.rhs")
    return nothing
end
