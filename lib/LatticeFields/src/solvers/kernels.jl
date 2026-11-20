# The solver program: one IR program per solver group with the fields of every level, the
# operator's input fields and the device scalars, and the generated kernels (§6.3): the
# fill and lift kernels from the operator spec, and per level above the bottom the Chebyshev
# steps, the fused residual + restriction and the fused prolongation + first post step;
# on the finest level the residual norm and the PCG kernels K1, K2 and the true residual.

"""
    CellOperator(dims; periodic, face, shift, mask, value, dirichlet, robin, name, axes)

A cell-centered Helmholtz operator in coefficient form, the input of a solver group:
`A u = s u + Σ_faces w (u − u_nb)` on active sites, with

  - `face[a]`: the face coefficient to `+e_a`, a number or the key of an input field;
  - `shift`: `s`, a number or an input field key;
  - `mask`: key of a `U8` input field, nonzero = masked Dirichlet node with `value` (a number
    or an input field key: each masked site then takes its own value, which its active
    neighbors see through the right-hand side);
  - `dirichlet[a] = (g_low, g_high)`: face-Dirichlet values on a non-periodic axis
    (`nothing`: no flux); the ghost rule adds `2w` to the diagonal and `2w g` to the
    right-hand side;
  - `robin[a] = (low, high)`: Robin faces `α u + β ∂u/∂n = g` on a non-periodic axis, each
    `nothing` or `(α, β, g)` in lattice units (`β` per lattice spacing, `n` the outward
    normal), as `IR.FaceRule`. The ghost rule gives the boundary row the diagonal `w·d` and
    the right-hand side `w·q`, with `d = α/(α/2 + β)` and `q = g/(α/2 + β)` (Dirichlet is
    `(1, 0, g)`: `d = 2`). `α/2 + β = 0` leaves the ghost value undefined and is refused.
    The sign rule: `d ≥ 0` (α and β of the same sign) enters the operator;
    a negative `d` would break the M-matrix, so it stays out of the operator and enters the
    right-hand side as `−d·w·x` at the current iterate `x` (a defect correction): each
    `lift!` takes it at the current `x`, and `steady!` iterates lift and solve until the
    full operator's residual is at the tolerance;
    With `robin_full = true` the whole `d` enters the operator, either sign (a steady solve,
    whose operator has no time-step shift to keep dominant: it stays symmetric, and it is
    positive definite exactly when the steady problem is well posed);
  - `name`: the user's field, which every message names (`nothing`: "the solver group");
    `axes`: the axis names for messages (default `"1"`, `"2"`, …);
  - `hex = true`: a hexagonal lattice in axial coordinates (2D), whose sites have six
    neighbors `±e₁`, `±e₂`, `±(e₁ − e₂)`: `face` then has three entries, the face to `+e₁`,
    to `+e₂` and to `+e₁ − e₂` (the hexagonal Laplacian `2/(3h²) Σₙ (uₙ − u)` has the three
    faces `2/(3h²)`). A diagonal face that leaves the box crosses the face of axis 1 when it
    leaves along axis 1 (a corner site's included), else that of axis 2, and takes that face's
    condition with the ghost rule above.

On an axis with a face-Dirichlet value or a Robin face, the boundary face takes the face
coefficient at the boundary site (for an input field, the field's value at that site: the
ghost term is a site value). The right-hand side is the input field `"in.f"`. Masked rows are
eliminated (§3.5). The checks refuse only input that is invalid or numerically unsafe, in the
user's words (`ArgumentError`).
"""
struct CellOperator{N}
    dims::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    face::NTuple{N, Union{Float64, String}}
    shift::Union{Float64, String}
    mask::Union{Nothing, String}
    value::Union{Float64, String}
    dirichlet::NTuple{N, NTuple{2, Union{Nothing, Float64}}}
    robin::NTuple{N, NTuple{2, Union{Nothing, NTuple{3, Float64}}}}
    name::Union{Nothing, String}
    axes::NTuple{N, String}
    robin_full::Bool
    diag::Union{Nothing, Float64, String}  # hex: the face to +e₁ − e₂ (`nothing`: Cartesian)
end
function CellOperator(dims::NTuple{N, Integer}; periodic = ntuple(_ -> false, N),
        face = nothing, shift = 0.0, mask = nothing, value = 0.0,
        dirichlet = ntuple(_ -> (nothing, nothing), N),
        robin = ntuple(_ -> (nothing, nothing), N), name = nothing,
        axes = ntuple(a -> string(a), N), robin_full::Bool = false, hex::Bool = false) where {N}
    num(x) = x isa Real ? Float64(x) : String(x)
    who = name === nothing ? "the solver group" : string("field `", name, "`")
    hex && !(N == 2 && all(>=(2), dims)) && throw(ArgumentError(string(who,
        ": a hexagonal lattice is 2D with at least two sites per axis; got the dims ", Tuple(dims))))
    face === nothing && (face = ntuple(_ -> 1.0, hex ? 3 : N))
    if length(face) != (hex ? 3 : N)
        per = hex ? "face direction of a hexagonal lattice (+e₁, +e₂, +e₁ − e₂): 3" : string("axis: ", N)
        throw(ArgumentError(string(who, ": `face` has one coefficient per ", per, "; got ", length(face))))
    end
    function rob(r)
        r === nothing && return nothing
        whose = name === nothing ? "the solver group" : string("field `", name, "`")
        length(r) == 3 || throw(ArgumentError(string(whose, ": a Robin face is `(α, β, g)` or `nothing`; got ", repr(r))))
        return map(Float64, Tuple(r))
    end
    fs = map(num, Tuple(face))
    op = CellOperator{N}(Int.(dims), Tuple(periodic), ntuple(a -> fs[a], N), num(shift),
        mask === nothing ? nothing : String(mask), num(value),
        map(d -> map(g -> g === nothing ? nothing : Float64(g), Tuple(d)), Tuple(dirichlet)),
        map(d -> map(rob, Tuple(d)), Tuple(robin)),
        name === nothing ? nothing : string(name), map(string, Tuple(axes)), robin_full,
        hex ? fs[3] : nothing)
    check_coefficients(op)
    return op
end

"""
Is `op` a hexagonal lattice (three face directions, `CellOperator(…; hex = true)`)?
"""
ishex(op::CellOperator) = op.diag !== nothing
"""
The face coefficients of `op` per face direction: one per axis, and on a hexagonal lattice the
face to `+e₁ − e₂` third.
"""
faces(op::CellOperator) = ishex(op) ? (op.face..., op.diag) : op.face
"""
The face directions of a lattice with `N` axes as offsets: the unit vectors, and with `hex`
the diagonal `e₁ − e₂` third.
"""
face_dirs(N, hex::Bool) = hex ? ((1, 0), (0, 1), (1, -1)) : ntuple(a -> _unit(N, a, 1), N)
function _facename(op::CellOperator, a)
    if a <= length(op.dims)
        return string("axis `", op.axes[a], "`")
    else
        return string("the diagonal `", op.axes[1], " − ", op.axes[2], "`")
    end
end

"""
The subject of a solver message: the user's field, or "the solver group" without a name.
"""
_who(op::CellOperator) = op.name === nothing ? "the solver group" : string("field `", op.name, "`")
_side(k) = k == 1 ? "low" : "high"
_face_words(op, a, k) = string("the ", _side(k), " face of axis `", op.axes[a], "`")
_refuse(op, msg...) = throw(ArgumentError(string(_who(op), ": ", msg...)))

"""
    robin_parts(α, β, g) -> (d⁺, d⁻, q)

The ghost rule of a Robin face `α u + β ∂u/∂n = g` (lattice units): the boundary row's
diagonal factor `d = α/(α/2 + β)` split by sign into the operator's part `d⁺ = max(d, 0)`
and the defect part `d⁻ = min(d, 0)`, and the right-hand side factor `q = g/(α/2 + β)`
(each times the face coefficient `w`).
"""
function robin_parts(α::Real, β::Real, g::Real)
    den = α / 2 + β
    d = α / den
    return (max(d, 0.0), min(d, 0.0), g / den)
end

"""
Is the group anchored by a mask, a face-Dirichlet value or a Robin face whose diagonal is
positive? An unanchored group has the near-null constant mode (eigenvalue `s`), which PCG
deflates (`unanchored`).
"""
function anchored(op::CellOperator)
    op.mask !== nothing || any(d -> any(!isnothing, d), op.dirichlet) ||
        any(d -> any(r -> r !== nothing && robin_parts(r...)[1] > 0, d), op.robin)
end
"""
Does the group have a Robin face (any sign)?
"""
has_robin(op::CellOperator) = any(d -> any(!isnothing, d), op.robin)
"""
Does a Robin face currently have a negative diagonal (the defect part, `robin_parts`)?
"""
has_defect(op::CellOperator) = !op.robin_full && any(d -> any(r -> r !== nothing && robin_parts(r...)[2] < 0, d), op.robin)
# a face's three slots: the parts of `robin_parts`, or `(d, 0, q)` with the whole `d` in the operator
_robin_slots(op::CellOperator, r) = op.robin_full ? (r[1] / (r[1] / 2 + r[2]), 0.0, r[3] / (r[1] / 2 + r[2])) : robin_parts(r...)
"""
Can the solve deflate the constant mode: no anchor, no Robin face and a constant shift (then
`A·1 = s·1` and `A` maps zero-mean vectors to zero-mean vectors)?
"""
deflatable(op::CellOperator) = !anchored(op) && !has_robin(op) && op.shift isa Real
"""
Numeric coefficients must be finite and keep the operator an M-matrix: shift `s ≥ 0` (a
negative shift is indefinite and breaks the smoother bound λ = 2) and faces `> 0` (a
non-positive face runs to the budget at ‖r‖/‖b‖ = 1); the mask, Dirichlet and Robin values
must be finite; a Robin face needs `α/2 + β ≠ 0`; face conditions sit on non-periodic axes,
one per face. Field-valued coefficients are not checked here. Errors are `ArgumentError`s
naming the user's field (`name`) and the axis.
"""
function check_coefficients(op::CellOperator{N}) where {N}
    fin(x) = !(x isa Real) || isfinite(x)
    s = op.shift
    fin(s) || _refuse(op, "the shift (the reaction coefficient `s` of `A u = s u + Σ w (u − u_nb)`) must be finite; got ", s)
    s isa Real && !(s >= 0) &&
        _refuse(op, "the shift (the reaction coefficient `s` of `A u = s u + Σ w (u − u_nb)`) must be ≥ 0; got ", s,
            ". A negative shift (growth) makes the operator indefinite, which PCG and multigrid cannot solve: ",
            "step the field with an explicit method (`ExplicitEuler`)")
    for (a, f) in enumerate(faces(op))
        fin(f) || _refuse(op, "the face coefficient of ", _facename(op, a), " must be finite; got ", f)
        f isa Real && !(f > 0) &&
            _refuse(op, "the face coefficient of ", _facename(op, a), " must be > 0; got ", f,
                ". A face ≤ 0 is anti-diffusion, which the solve cannot converge on: give a positive ",
                "diffusion coefficient (cut the lattice with a mask instead)")
    end
    fin(op.value) || _refuse(op, "the mask value must be finite; got ", op.value)
    for a in 1:N, k in 1:2
        g, r = op.dirichlet[a][k], op.robin[a][k]
        (g !== nothing || r !== nothing) && op.periodic[a] &&
            _refuse(op, "axis `", op.axes[a], "` is periodic: it has no ", _side(k),
                " face for a ", g !== nothing ? "Dirichlet value" : "Robin condition",
                "; drop the face condition or make the axis non-periodic")
        g !== nothing && r !== nothing &&
            _refuse(op, _face_words(op, a, k), " has both a Dirichlet value and a Robin condition; give one")
        g === nothing || isfinite(g) ||
            _refuse(op, "the Dirichlet value on ", _face_words(op, a, k), " must be finite; got ", g)
        r === nothing && continue
        α, β, gr = r
        all(isfinite, r) || _refuse(op, "the Robin condition `α u + β ∂u/∂n = g` on ",
            _face_words(op, a, k), " must have finite α, β and g; got (", α, ", ", β, ", ", gr, ")")
        α == 0 && β == 0 && _refuse(op, "the Robin condition on ", _face_words(op, a, k),
            " has α = β = 0, which is no condition: give α (a fixed value) or β (a flux)")
        degenerate(α, β) && _refuse(op, "the Robin condition `α u + β ∂u/∂n = g` on ",
            _face_words(op, a, k), " has α/2 + β = 0 (α = ", α, ", β = ", β,
            " per lattice spacing: 2β + αh = 0), which leaves the ghost value undefined: change α or β")
    end
    return nothing
end

"""
Reactions weaker than this, relative to the strongest face (`s / max(face) < FLOOR_SHIFT`),
put an unanchored group in the Float32 floor regime, where Float32 PCG cannot reach
‖r‖∞ ≤ 1e-6‖b‖∞. The floor is invariant under scaling `s` and the faces together. Measured
(Float32 solver, faces 0.01, 1 and 100, the same results at each scale): per256
floors at s/face ≤ 0.05 and converges at ≥ 0.1; Neumann-x/periodic-y (128×96) floors at
s/face ≤ 0.2 (best 1.0e-6–1.6e-6 at 0.2) and converges at 0.5 (5 iterations); at s/face = 1
both converge in 4 iterations. Earlier: per256 1e-4 at s = 5.5e-6, pure Neumann 3.4e-5 at s = 0.
"""
const FLOOR_SHIFT = 0.5
"""
Is the group in the Float32 floor regime: unanchored, with its weakest reaction relative to
its strongest face below `FLOOR_SHIFT`? A field-valued shift or face counts as weak (its
range is not known at build time). `solver_type = :auto` solves such groups in Float64
(a provisional rule).
"""
function floor_regime(op::CellOperator{N}) where {N}
    anchored(op) && return false
    (op.shift isa Real && all(f -> f isa Real, faces(op))) || return true
    w = maximum((f for (a, f) in enumerate(faces(op)) if a > N || op.dims[a] > 1); init = 0.0)
    return op.shift < FLOOR_SHIFT * w
end
"""
Does the group have a mask, a Dirichlet or Robin face or a non-constant face coefficient (§5.6)?
"""
function jumpy(op::CellOperator)
    op.mask !== nothing ||
        any(d -> any(!isnothing, d), op.dirichlet) || has_robin(op) ||
        any(f -> f isa String, faces(op))
end

"""
The runtime parameter slots of the operator's numeric coefficients:
`(; face, shift, value, dirichlet, robin)` with slot 0 for a coefficient that is a field key
or absent; a Robin face has three slots `(d⁺, d⁻, q)` (`robin_parts`). Coefficients are
parameters, not constants: a change of value never recompiles, and the slot order is
`coef_values(op)`.
"""
function coef_slots(op::CellOperator{N}) where {N}
    n = Ref(0)
    next(x) = x isa Real ? (n[] += 1) : 0
    fs = faces(op)
    face = ntuple(a -> next(fs[a]), length(fs))
    shift, value = next(op.shift), next(op.value)
    dirichlet = ntuple(a -> map(next, op.dirichlet[a]), N)
    robin = ntuple(a -> map(r -> r === nothing ? (0, 0, 0) : (next(0.0), next(0.0), next(0.0)),
            op.robin[a]), N)
    return (; face, shift, value, dirichlet, robin, n = n[])
end
"""
The numeric coefficients of `op` in slot order (`coef_slots`).
"""
function coef_values(op::CellOperator{N}) where {N}
    v = Float64[]
    foreach(f -> f isa Real && push!(v, f), faces(op))
    op.shift isa Real && push!(v, op.shift)
    op.value isa Real && push!(v, op.value)
    for d in op.dirichlet, g in d

        g isa Real && push!(v, g)
    end
    for d in op.robin, r in d

        r === nothing || append!(v, _robin_slots(op, r))
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
depth(op::CellOperator) = depth(op.dims; op)
function depth(dims::NTuple{N, Int}; op = nothing) where {N}
    big = [d for d in dims if d > 1]
    isempty(big) && throw(ArgumentError(string(op === nothing ? "the solver group" : _who(op),
        ": the lattice ", dims, " has one site: a multigrid solve needs an axis with more than one site")))
    L = floor(Int, log2(minimum(big)))           # ≥ 1: every axis in `big` has ≥ 2 sites
    lb = something(findfirst(l -> prod(leveldims(Level(Grid(dims), l))) <= LDS_SITES, 1:L), L)
    return L, lb
end

lkey(l, name) = string("L", lpad(l, 2, '0'), ".", name)

struct LevelFields{N, F}                  # F faces per site: N, or 3 on a hexagonal lattice
    active::Int32
    w::NTuple{F, Int32}
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
    function L(f; o = ntuple(_ -> 0, N), pol = IR.RESOLVE)
        return load(kb, f; offset = o, level = lev,
            policy = all(iszero, o) ? IR.RESOLVE : pol)
    end
    c = L(F.s) + L(F.sbox) + L(F.sint)
    x0 = xget(ntuple(_ -> 0, N))
    D, Ax = c, c * x0
    for a in 1:N, σ in (1, -1)

        dims[a] == 1 && continue
        o = _unit(N, a, σ)
        w = if σ > 0
            L(F.w[a])
        else
            L(F.w[a]; o, pol = per[a] ? IR.CLAMP : IR.ZERO)
        end
        xj = _real(L(F.active; o, pol = IR.CLAMP)) * xget(o)
        D, Ax = D + w, Ax + w * (x0 - xj)
    end
    if length(F.w) > N && all(>(1), dims)          # hexagonal: the faces to ±(e₁ − e₂)
        for σ in (1, -1)
            o = (σ, -σ)
            w = σ > 0 ? L(F.w[3]) : L(F.w[3]; o, pol = all(per) ? IR.CLAMP : IR.ZERO)
            xj = _real(L(F.active; o, pol = IR.CLAMP)) * xget(o)
            D, Ax = D + w, Ax + w * (x0 - xj)
        end
    end
    return Ax, D
end

"""
The rounding scale of the residual `b − A x` at the kernel's site: `|b| + (|A||x|)`, with
`aget(o)` the stored `x` at offset `o` (the floor test, `Solvers._stop!`).
"""
function _roundscale(kb::KernelBuilder{N}, F::LevelFields{N}, per, dims, b, aget) where {N}
    function L(f; o = ntuple(_ -> 0, N), pol = IR.RESOLVE)
        return load(kb, f; offset = o,
            policy = all(iszero, o) ? IR.RESOLVE : pol)
    end
    x0 = abs(aget(ntuple(_ -> 0, N)))
    sc = abs(b) + (L(F.s) + L(F.sbox) + L(F.sint)) * x0
    for a in 1:N, σ in (1, -1)

        dims[a] == 1 && continue
        o = _unit(N, a, σ)
        w = if σ > 0
            L(F.w[a])
        else
            L(F.w[a]; o, pol = per[a] ? IR.CLAMP : IR.ZERO)
        end
        sc = sc + w * (x0 + _real(L(F.active; o, pol = IR.CLAMP)) * abs(aget(o)))
    end
    if length(F.w) > N && all(>(1), dims)          # hexagonal: the faces to ±(e₁ − e₂)
        for σ in (1, -1)
            o = (σ, -σ)
            w = σ > 0 ? L(F.w[3]) : L(F.w[3]; o, pol = all(per) ? IR.CLAMP : IR.ZERO)
            sc = sc + w * (x0 + _real(L(F.active; o, pol = IR.CLAMP)) * abs(aget(o)))
        end
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
        _refuse(
        op, "`deflate = true` needs `LatticePCG` on a group with no mask, no Dirichlet or ",
            "Robin face and a constant shift (the constant mode is then an eigenvector); this group ",
        pcg ? "is anchored or has a field-valued shift" : "uses stationary `LatticeMultigrid`",
            ": use `deflate = :auto`")
    L, lb = depth(op)
    cs = coef_slots(op)
    pb = ProgramBuilder(Grid(op.dims); periodic = op.periodic, levels = L + 1,
        nparams = cs.n)
    nf = length(faces(op))
    lv = map(0:L) do l
        f(name; kw...) = field!(pb, lkey(l, name); levels = [l], storage = lane, kw...)
        LevelFields{N, nf}(f("active"; storage = U8, role = :aux),
            ntuple(a -> f("w$a"; role = :aux), nf), f("s"; role = :aux),
            f("sbox"; role = :aux), f("sint"; role = :aux),
            f("x"; buffers = l < lb ? 2 : 1), f("b"; role = :aux), f("d"; role = :scratch),
            l >= lb ? f("r"; role = :scratch) : Int32(0))
    end
    input(k; kw...) = field!(pb, k; role = :input, storage = state, kw...)
    inp = (; f = input("in.f"),
        mask = op.mask === nothing ? Int32(0) : input(op.mask; storage = U8),
        value = op.value isa String ? input(op.value) : Int32(0),
        shift = op.shift isa String ? input(op.shift) : Int32(0),
        face = map(f -> f isa String ? input(f) : Int32(0), faces(op)))
    pf = if pcg
        (; x = field!(pb, "pcg.x"; buffers = 2, storage = lane),
            b = field!(pb, "pcg.b"; role = :aux, storage = lane),
            p = field!(pb, "pcg.p"; buffers = 2, storage = lane),
            u = deflate ? field!(pb, "pcg.u"; storage = state) : Int32(0))
    else
        nothing
    end
    rb = has_robin(op) ? field!(pb, "robin.b"; role = :aux, storage = lane) : Int32(0)
    tab(k) = table!(pb, k; storage = lane, oob = :none)
    tb = (; scal = tab("solve.scal"), pr = tab("solve.pr"), pb = tab("solve.pb"),
        pd = tab("solve.pd"), px = tab("solve.px"), gb = tab("solve.gb"),
        ps = deflate ? tab("solve.ps") : Int32(0),
        pq = deflate ? tab("solve.pq") : Int32(0))
    ctx = (; pb, op, cs, lv, inp, pf, tb, rb, L, lb, lane, deflate,
        dims = [Int.(leveldims(Level(Grid(op.dims), l))) for l in 0:L])
    _fill!(ctx)
    _lift!(ctx)
    rb == 0 || _robin!(ctx)
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
    lvm = [LevelFields{N, nf}(
               fm(F.active), map(fm, F.w), fm(F.s), fm(F.sbox), fm(F.sint), fm(F.x),
               fm(F.b), fm(F.d), fm(F.r)) for F in lv]
    return p, (; L, lb, dims = ctx.dims, lv = lvm)
end

_notdone(kb, tb) = eq(_scal(kb, tb.scal, DONE), 0.0)
_masked(kb, F) = eq(load(kb, F.active), 0)
_sel(kb, F, v) = select(_masked(kb, F), 0.0, v)

function _face_in(kb::KernelBuilder{N}, ctx, a; o = ntuple(_ -> 0, N)) where {N}
    f = faces(ctx.op)[a]
    f isa Real && return param(kb, ctx.cs.face[a])
    per = a <= N ? ctx.op.periodic[a] : all(ctx.op.periodic)
    pol = if all(iszero, o)
        IR.RESOLVE
    elseif per
        IR.CLAMP
    else
        IR.ZERO
    end
    return load(kb, ctx.inp.face[a]; offset = o, policy = pol)
end

"""
The ghost term of the diagonal face to `σ(e₁ − e₂)` of a hexagonal lattice at a site whose
neighbor that way is outside the box: `val(a, k, w)` (the term of the condition on the face
`(a, k)` of the box, `nothing` without one) with `w` the diagonal face coefficient, of the
face of axis 1 when the neighbor is outside along axis 1, else of axis 2; 0 inside; `nothing`
when neither face has a term.
"""
function _hexghost(kb::KernelBuilder{N}, ctx, σ, val) where {N}
    w = _face_in(kb, ctx, 3)
    v1 = ctx.op.periodic[1] ? nothing : val(1, σ > 0 ? 2 : 1, w)
    v2 = ctx.op.periodic[2] ? nothing : val(2, σ > 0 ? 1 : 2, w)
    v1 === nothing && v2 === nothing && return nothing
    in1, in2 = _inside(kb, ctx.inp.f, (σ, 0)), _inside(kb, ctx.inp.f, (0, -σ))
    t2 = v2 === nothing ? constant(kb, 0.0) : select(in2, 0.0, v2)
    return v1 === nothing ? select(in1, t2, 0.0) : select(in1, t2, v1)
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
    active = if ctx.inp.mask == 0
        constant(kb, 1.0)
    else
        select(eq(load(kb, ctx.inp.mask), 0), 1.0, 0.0)
    end
    store(kb, F.active, cast(active, U8))
    sbox = constant(kb, 0.0)
    for a in 1:N
        w = op.dims[a] == 1 ? constant(kb, 0.0) : _face_in(kb, ctx, a)
        op.periodic[a] || (w = select(_inside(kb, ctx.inp.f, _unit(N, a, 1)), w, 0.0))
        store(kb, F.w[a], w)
        for (k, σ) in enumerate((-1, 1))
            diag = if op.dirichlet[a][k] !== nothing
                2 * _face_in(kb, ctx, a)
            elseif op.robin[a][k] !== nothing
                param(kb, ctx.cs.robin[a][k][1]) * _face_in(kb, ctx, a)
            else
                nothing
            end
            diag === nothing && continue                 # the ghost rule's diagonal (d⁺ w)
            sbox = sbox + select(_inside(kb, ctx.inp.f, _unit(N, a, σ)), 0.0, diag)
        end
    end
    if ishex(op)                                         # the diagonal face to +e₁ − e₂
        w = _face_in(kb, ctx, 3)
        all(op.periodic) || (w = select(_inside(kb, ctx.inp.f, (1, -1)), w, 0.0))
        store(kb, F.w[3], w)
        for σ in (1, -1)
            function ghost_diag(a, k, w)
                if op.dirichlet[a][k] !== nothing
                    return 2 * w
                elseif op.robin[a][k] !== nothing
                    return param(kb, ctx.cs.robin[a][k][1]) * w
                else
                    return nothing
                end
            end
            g = _hexghost(kb, ctx, σ, ghost_diag)
            g === nothing || (sbox = sbox + g)
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

        o = _unit(N, a, σ)
        if ctx.inp.mask != 0 && op.dims[a] > 1
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
        op.robin[a][k] === nothing || (b = b + select(_inside(kb, ctx.inp.f, o), 0.0,
            _face_in(kb, ctx, a) * param(kb, ctx.cs.robin[a][k][3])))
    end
    if ishex(op)                                         # the diagonal faces to ±(e₁ − e₂)
        for σ in (1, -1)
            o = (σ, -σ)
            if ctx.inp.mask != 0
                w = σ > 0 ? _face_in(kb, ctx, 3) : _face_in(kb, ctx, 3; o)
                hit = _not(Ex(kb, compare!(kb, IR.EQ, load(kb, ctx.inp.mask; offset = o, policy = IR.CLAMP).id,
                    constant!(kb, 0.0, U8))))
                all(op.periodic) || (hit = _and(hit, _inside(kb, ctx.inp.f, o)))
                v = _num(kb, op.value, ctx.inp.value, ctx.cs.value; offset = o, policy = IR.CLAMP)
                b = b + select(hit, w * v, 0.0)
            end
            function ghost_rhs(a, k, w)
                if op.dirichlet[a][k] !== nothing
                    return 2 * w * param(kb, ctx.cs.dirichlet[a][k])
                elseif op.robin[a][k] !== nothing
                    return w * param(kb, ctx.cs.robin[a][k][3])
                else
                    return nothing
                end
            end
            g = _hexghost(kb, ctx, σ, ghost_rhs)
            g === nothing || (b = b + g)
        end
    end
    mk = ctx.inp.mask == 0 ? b : select(eq(load(kb, ctx.inp.mask), 0), b, 0.0)
    store(kb, ctx.rb == 0 ? _rhs(ctx) : ctx.rb, mk)
    add!(pb, kb, "lift")
end

"""
The solve's right-hand side field: `pcg.b` under PCG, else the finest level's `b`.
"""
_rhs(ctx) = ctx.pf === nothing ? ctx.lv[1].b : ctx.pf.b
"""
The working field of the solve (`pcg.x` under PCG, else the finest level's `x`).
"""
_work(ctx) = ctx.pf === nothing ? ctx.lv[1].x : ctx.pf.x

"""
The Robin defect term (the sign rule, `CellOperator`): the right-hand side is the lifted
`robin.b` minus `d⁻ w x` on each Robin boundary row, `x` the current iterate (the working
field; under deflation its zero-mean part, which a Robin group never has: not deflatable).
Kernel `robin.b`, run after `lift` and after `tangent.rhs`.
"""
function _robin!(ctx)
    op, pb = ctx.op, ctx.pb
    N = length(op.dims)
    kb = kernel(pb)
    b = load(kb, ctx.rb)
    x = load(kb, _work(ctx))
    for a in 1:N, (k, σ) in enumerate((-1, 1))

        op.robin[a][k] === nothing && continue
        dneg = param(kb, ctx.cs.robin[a][k][2])
        b = b - select(_inside(kb, ctx.inp.f, _unit(N, a, σ)), 0.0,
            dneg * _face_in(kb, ctx, a) * x)
    end
    if ishex(op)                                         # the diagonal faces that leave the box
        for σ in (1, -1)
            g = _hexghost(kb, ctx, σ, (a, k, w) -> op.robin[a][k] === nothing ? nothing : param(kb, ctx.cs.robin[a][k][2]) * w * x)
            g === nothing || (b = b - g)
        end
    end
    mk = ctx.inp.mask == 0 ? b : select(eq(load(kb, ctx.inp.mask), 0), b, 0.0)
    store(kb, _rhs(ctx), mk)
    add!(pb, kb, "robin.b")
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
PCG kernels of the masked multigrid solver: K1 (`p ← z + βp` at the stencil points, partial `p·Ap`), K2 (`x ← x

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
    tb = ctx.rb == 0 ? bt : ctx.rb        # a Robin group: the right-hand side before its defect term
    store(kb, tb, _sel(kb, F, load(kb, F.d) + c * (load(kb, tb) - load(kb, ctx.inp.f))))
    add!(pb, kb, "tangent.rhs")
    return nothing
end
