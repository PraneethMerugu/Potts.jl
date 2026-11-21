# IR data model. Plain host values; nothing here reaches the device. Every compiler
# pass is written against these types once per spatial dimension `N`.

"""
    Scalar

Element types of IR values. Storage lanes are `F16 F32 F64 U8 I32 U32`; `REAL` is
the abstract float compute type that pass 4 resolves to `T`; `BOOL` is a predicate.
An enum with the values `F16`, `F32`, `F64`, `U8`, `I32`, `U32`, `REAL` and `BOOL`.

See also [`juliatype`](@ref), [`isfloat`](@ref).
"""
@enum Scalar::UInt8 F16 F32 F64 U8 I32 U32 REAL BOOL
@doc """
    F16::Scalar

16-bit float storage lane (`Float16`).
""" F16
@doc """
    F32::Scalar

32-bit float storage lane (`Float32`).
""" F32
@doc """
    F64::Scalar

64-bit float storage lane (`Float64`).
""" F64
@doc """
    U8::Scalar

8-bit unsigned integer storage lane (`UInt8`), used by masks and flags.
""" U8
@doc """
    I32::Scalar

32-bit signed integer storage lane (`Int32`). Coordinates and table indices have this type.
""" I32
@doc """
    U32::Scalar

32-bit unsigned integer storage lane (`UInt32`).
""" U32
@doc """
    REAL::Scalar

The abstract float compute type. Pass 4 resolves it to the compute type `T`. It is not a storage lane.
""" REAL
@doc """
    BOOL::Scalar

The predicate type of comparisons and logic nodes. It is not a storage lane.
""" BOOL

const LANES = (F16, F32, F64, U8, I32, U32)
"""
    isfloat(t::Scalar) -> Bool

Whether `t` is a float type: `F16`, `F32`, `F64` or `REAL`.

# Arguments
- `t`: a [`Scalar`](@ref).

# Returns
- `true` for the float lanes and `REAL`, `false` for the integer lanes and `BOOL`.

# Examples
```jldoctest
julia> using LatticeFields.IR: isfloat, F32, U8

julia> isfloat(F32), isfloat(U8)
(true, false)
```
"""
isfloat(t::Scalar) = t in (F16, F32, F64, REAL)
isinteger_lane(t::Scalar) = t in (U8, I32, U32)
isunsigned_lane(t::Scalar) = t in (U8, U32)
"""
Storage size in bytes of one element of lane `t`.
"""
function lanebytes(t::Scalar)
    if t == U8
        return 1
    elseif t == F16
        return 2
    elseif t == F64
        return 8
    else
        return 4
    end
end
"""
    juliatype(t::Scalar) -> Type

Host Julia type of an integer or storage lane.

# Arguments
- `t`: a storage lane: `F16`, `F32`, `F64`, `U8`, `I32` or `U32`. `REAL` and `BOOL` have no
  Julia type here and throw a `BoundsError`.

# Returns
- `Float16`, `Float32`, `Float64`, `UInt8`, `Int32` or `UInt32`.

# Examples
```jldoctest
julia> using LatticeFields.IR: juliatype, F64

julia> juliatype(F64)
Float64
```
"""
juliatype(t::Scalar) = (Float16, Float32, Float64, UInt8, Int32, UInt32)[Int(t) + 1]

"""
    Geometry

Lattice geometry kind for [`Grid`](@ref): `CUBIC` (square or cubic Cartesian axes) or
`HEX` (2D hexagonal lattice in axial coordinates).
"""
@enum Geometry::UInt8 CUBIC HEX
@doc """
    CUBIC::Geometry

Square (2D) or cubic (3D) Cartesian [`Geometry`](@ref) value. The default of [`Grid`](@ref).
""" CUBIC
@doc """
    HEX::Geometry

2D hexagonal [`Geometry`](@ref) value in axial coordinates.
""" HEX
"""
    Epoch

The update class of a field or mask declaration: `STATIC`, `PERSIGMA`, `PERSTEP` or
`INNER`. The IR records the epoch and prints it (so it is part of the fingerprint text). No
compiler pass reads it.
"""
@enum Epoch::UInt8 STATIC PERSIGMA PERSTEP INNER
@doc """
    STATIC::Epoch

An [`Epoch`](@ref) value: the values never change in a run.
""" STATIC
@doc """
    PERSIGMA::Epoch

An [`Epoch`](@ref) value: the values change with the cell configuration σ. The default of masks.
""" PERSIGMA
@doc """
    PERSTEP::Epoch

An [`Epoch`](@ref) value: the values change every step. The default of fields.
""" PERSTEP
@doc """
    INNER::Epoch

An [`Epoch`](@ref) value: the values change within the inner iterations of a step.
""" INNER
"""
    Bpolicy

Boundary policy of an access: `RESOLVE` (pass 2 rewrites out-of-domain reads), `INSIDE`
(proven inside), `ZERO` (outside reads 0), `CLAMP` (nearest inside value).
"""
@enum Bpolicy::UInt8 RESOLVE INSIDE ZERO CLAMP
@doc """
    RESOLVE::Bpolicy

A [`Bpolicy`](@ref) value: pass 2 rewrites a read outside the domain by the field's boundary rules.
""" RESOLVE
@doc """
    INSIDE::Bpolicy

A [`Bpolicy`](@ref) value: the read is proven inside the domain.
""" INSIDE
@doc """
    ZERO::Bpolicy

A [`Bpolicy`](@ref) value: a read outside the domain gives 0.
""" ZERO
@doc """
    CLAMP::Bpolicy

A [`Bpolicy`](@ref) value: a read outside the domain gives the nearest inside value.
""" CLAMP
@enum SpaceKind::UInt8 FULL MASKED RESTRICTED
@doc """
    FULL

The space kind of a kernel that runs on every site of its level. The default of
[`Space`](@ref).
""" FULL

# The op set. Printing and fingerprints use the names, never the codes, so adding
# an op never changes an existing program's text.
"""
    Op

The operation of an IR node. Printing and fingerprints use the op names (lowercase), never
the codes, so adding an op never changes an existing program's text. The public values are
the arithmetic, comparison, logic, select and cast ops that front ends build with
[`arith!`](@ref), [`compare!`](@ref), [`select!`](@ref), [`cond!`](@ref) and
[`cast!`](@ref).
"""
@enum(
    Op::UInt8,
    CONST, PARAM, LOAD, TABLE, COORD, INSIDE_OP, BITTEST, RUNTIME, ADD, MUL, NEG, DIV, FMA,
    MIN, MAX, ABS, POWI, SQRT, EXP, LOG, CALL, EQ, LT, LE, AND, OR, NOT, XOR, SELECT, COND,
    CAST, IDX, RESTRICT, ELEMENT_SUM
)
@doc """
    ADD::Op

An [`Op`](@ref) value: sum of its operands (commutative; nested sums are flattened).
""" ADD
@doc """
    MUL::Op

An [`Op`](@ref) value: product of its operands (commutative; nested products are flattened).
""" MUL
@doc """
    NEG::Op

An [`Op`](@ref) value: negation of its operand.
""" NEG
@doc """
    DIV::Op

An [`Op`](@ref) value: quotient `a / b`.
""" DIV
@doc """
    FMA::Op

An [`Op`](@ref) value: fused multiply-add `fma(a, b, c)`.
""" FMA
@doc """
    MIN::Op

An [`Op`](@ref) value: minimum of its operands.
""" MIN
@doc """
    MAX::Op

An [`Op`](@ref) value: maximum of its operands.
""" MAX
@doc """
    ABS::Op

An [`Op`](@ref) value: absolute value.
""" ABS
@doc """
    POWI::Op

An [`Op`](@ref) value: integer power `x^n`, with `n` in the node's immediate (emitted with `Compile.powi`).
""" POWI
@doc """
    SQRT::Op

An [`Op`](@ref) value: square root.
""" SQRT
@doc """
    EXP::Op

An [`Op`](@ref) value: exponential.
""" EXP
@doc """
    LOG::Op

An [`Op`](@ref) value: natural logarithm.
""" LOG
@doc """
    EQ::Op

An [`Op`](@ref) value: equality test; the result is `BOOL`.
""" EQ
@doc """
    LT::Op

An [`Op`](@ref) value: less-than test; the result is `BOOL`.
""" LT
@doc """
    LE::Op

An [`Op`](@ref) value: less-or-equal test; the result is `BOOL`.
""" LE
@doc """
    AND::Op

An [`Op`](@ref) value: logical or bitwise and.
""" AND
@doc """
    OR::Op

An [`Op`](@ref) value: logical or bitwise or.
""" OR
@doc """
    NOT::Op

An [`Op`](@ref) value: logical not of a `BOOL`, bitwise not of an integer.
""" NOT
@doc """
    XOR::Op

An [`Op`](@ref) value: logical or bitwise exclusive or.
""" XOR
@doc """
    SELECT::Op

An [`Op`](@ref) value: eager select `ifelse(c, a, b)`: both arms are computed.
""" SELECT
@doc """
    COND::Op

An [`Op`](@ref) value: lazy conditional `c ? a : b`, emitted as a branch.
""" COND
@doc """
    CAST::Op

An [`Op`](@ref) value: conversion to the node's type.
""" CAST
@doc """
    INSIDE_OP::Op

An [`Op`](@ref) value: whether an access is inside the domain; the result is `BOOL`. It prints as `inside`.
""" INSIDE_OP
@doc """
    RESTRICT::Op

An [`Op`](@ref) value: combination of an operand over the children of a coarse site: the immediate is 0 for sum, 1 for max, 2 for plurality.
""" RESTRICT

# RESTRICT(x; imm = 0 sum | 1 max | 2 plurality) at a coarse site combines `x` over the
# site's children (plurality: the most frequent value, ties to the smallest nonzero value, 0
# last) (2 per coarsened axis, 3 at the last site of an odd axis): inside `x`, an access at
# level −1 is taken relative to each child in turn (offset in the fine frame).
opname(op::Op) = op == INSIDE_OP ? "inside" : lowercase(string(op))
const COMMUTATIVE = (ADD, MUL, MIN, MAX, EQ, AND, OR, XOR)
"""
    CALLS::NTuple{19, Symbol}

The functions an IR `CALL` node may apply: `sin`, `cos`, `tan`, `tanh`, `sinh`, `cosh`,
`cbrt`, `exp2`, `log2`, `log10`, `expm1`, `log1p`, `atan`, `floor`, `ceil`, `round`,
`sign`, `mod` and `rem`. [`call!`](@ref) refuses any other name.
"""
const CALLS = (
    :sin, :cos, :tan, :tanh, :sinh, :cosh, :cbrt, :exp2, :log2, :log10, :expm1, :log1p,
    :atan, :floor, :ceil, :round, :sign, :mod, :rem,
)
"""
    call_arity(f::Symbol) -> Int

The number of operands of an IR call of `f` (a name in `CALLS`): 2 for `mod(x, y)` and
`rem(x, y)`, 1 for every other call. [`call!`](@ref) checks it.

# Arguments
- `f`: the function name.

# Returns
- `2` for `:mod` and `:rem`, else `1`.

# Examples
```jldoctest
julia> using LatticeFields.IR: call_arity

julia> call_arity(:mod), call_arity(:sin)
(2, 1)
```
"""
call_arity(f::Symbol) = f in (:mod, :rem) ? 2 : 1

"""
    Grid(dims; geometry = CUBIC, domain = 0)

Lattice grid description with site counts `dims`, `geometry` (`CUBIC` or `HEX`), and
irregular domain mask id `domain` (`0` for the full box).

# Arguments
- `dims`: the number of sites per axis, an `NTuple{N, Integer}`.

# Keywords
- `geometry = CUBIC`: the [`Geometry`](@ref).
- `domain = 0`: the mask id of the irregular domain, or 0 for the full box.

# Fields
- `dims::NTuple{N, Int32}`, `geometry::Geometry`, `domain::Int32`.

# Examples
```jldoctest
julia> using LatticePDE

julia> Grid((32, 16)).dims
(32, 16)
```
"""
struct Grid{N}
    dims::NTuple{N, Int32}
    geometry::Geometry
    domain::Int32                    # mask id of the irregular domain, 0 for the full box
end
function Grid(dims::NTuple{N, Integer}; geometry = CUBIC, domain = 0) where {N}
    return Grid{N}(
        Int32.(dims), geometry, Int32(domain)
    )
end

"""
    Level(grid::Grid, shift = 0)

A grid level: `shift` coarsenings by 2 (coarse fields and multigrid levels).

Each coarsening halves an axis with floor, `n ÷ 2`; the last aggregate of an odd axis has
width 3. An axis of size 1 is never coarsened.

# Arguments
- `grid`: the finest [`Grid`](@ref).
- `shift = 0`: the number of coarsenings.

# Fields
- `grid::Grid{N}`, `shift::Int8`, and `widths`, the per-axis aggregate widths or `nothing`.

See also [`leveldims`](@ref).
"""
struct Level{N}
    grid::Grid{N}
    shift::Int8
    widths::Union{Nothing, NTuple{N, Vector{Int8}}}
end
Level(g::Grid{N}, shift = 0) where {N} = Level{N}(g, Int8(shift), nothing)
# Coarse levels: each coarsening halves an axis with floor, `n ÷ 2`; the last aggregate of
# an odd axis takes width 3 (at the high end; see contract.jl). An axis of size 1 is never
# coarsened (it stays 1, identity map); an axis that would reach 0 sites makes the level
# illegal (`coarsenable`, checked by legality).
"""
    leveldims(l::Level) -> NTuple{N, Int32}
    leveldims(p::Program, level::Integer) -> NTuple{N, Int32}

The number of sites per axis of a grid level: `max(n >> shift, 1)` for an axis of `n > 1`
sites, and 1 for an axis of one site.

# Arguments
- `l`: a [`Level`](@ref); or `p`, a [`Program`](@ref), and `level`, the level index
  (0: the lattice).

# Returns
- The site counts per axis, as `Int32`s.

# Examples
```jldoctest
julia> using LatticeFields.IR: Grid, Level, leveldims

julia> leveldims(Level(Grid((9, 1)), 1))
(4, 1)
```

See also [`nsites`](@ref).
"""
leveldims(l::Level) = map(d -> Int32(d == 1 ? 1 : max(d >> l.shift, 1)), l.grid.dims)
coarsenable(l::Level) = all(d -> d == 1 || d >> l.shift >= 1, l.grid.dims)

"""
Placement in half-integers: all zeros is a site (cell center), a 1 on axis `d` a face.
"""
struct Placement{N}
    half::NTuple{N, Int8}
end
Placement{N}() where {N} = Placement{N}(ntuple(_ -> Int8(0), N))

struct FieldDecl{N}
    key::String
    classes::Vector{Placement{N}}
    # empty: scalar; `[k]`: k components (flat, after symmetry)
    shape::Vector{Int16}
    symmetric::Bool
    storage::Scalar
    levels::Vector{Int8}
    epoch::Epoch
    buffers::Int8                    # 1, or 2 for host ping-pong
    role::Symbol                     # :state | :aux | :input | :output | :scratch
    # a declared storage (`lattice_storage`): the float lane holds its own type under `lanes
    # = :state` (`lanetype`)
    fixed::Bool
    # per axis, whether the field wraps (its accesses wrap there; a closed axis takes the
    # field's face rules)
    periodic::NTuple{N, Bool}
end
ncomp(f::FieldDecl) = isempty(f.shape) ? 1 : Int(prod(f.shape))

"""
Per-cell or per-kind array read through `TABLE`; `oob = :zero_at_0` reads 0 at index 0.
"""
struct TableDecl
    key::String
    storage::Scalar
    oob::Symbol
end

"""
    MaskDecl(key, field, epoch)

A site mask; its bytes live in the `U8` field `field` (nonzero = inside the mask).

# Fields
- `key::String`: the mask's key.
- `field::Int32`: the id of the `U8` field that holds the mask bytes.
- `epoch::Epoch`: the update class.
"""
struct MaskDecl
    key::String
    field::Int32
    epoch::Epoch
end

"""
One byte of named bits per site, generated from masks; kept with the previous byte.
"""
struct FlagDecl
    key::String
    field::Int32
    bits::Vector{Pair{Symbol, Int32}} # bit name => source mask id
    epoch::Epoch
end

"""
    Sel(a, b, cond)
    Sel(v)

An index select between two literals, decided by a Bool node (`cond = 0`: always `a`).
`Sel(v)` is the constant select `Sel(v, v, 0)`.

# Fields
- `a`, `b`: the two literals (for example a component index or an offset tuple).
- `cond::Int32`: the id of the `BOOL` node that selects `b`, or 0.
"""
struct Sel{V}
    a::V
    b::V
    cond::Int32
end
Sel(v) = Sel(v, v, Int32(0))

"""
    Access{N}(field, class, comp, offset, level, policy)

One field read or write of a kernel: which field, component, offset and level, and what
happens outside the domain.

# Fields
- `field::Int32`: the field id.
- `class::Int8`: the placement class of the field.
- `comp::Sel{Int16}`: the component index.
- `offset::Sel{NTuple{N, Int16}}`: the offset from the kernel's site.
- `level::Int8`: the relative level: +1 coarser, −1 finer.
- `policy::Bpolicy`: the boundary policy ([`Bpolicy`](@ref)).

See also [`access!`](@ref), [`load!`](@ref).
"""
struct Access{N}
    field::Int32
    class::Int8
    comp::Sel{Int16}
    offset::Sel{NTuple{N, Int16}}
    level::Int8                      # relative level: +1 coarser, -1 finer
    policy::Bpolicy
end

struct Node
    op::Op
    type::Scalar
    args::UnitRange{Int32}           # into `Kernel.operands`
    imm::Int64                       # CONST: pool id; PARAM: slot; LOAD: access id; ...
end

"""
    Space{N}(kind = FULL; level = 0, class = 0, mask = 0, inset = ((0, 0), …))

The set of sites a kernel runs on.

# Arguments
- `kind = FULL`: `FULL` (every site of the level), `MASKED` (the sites of mask `mask`) or
  `RESTRICTED` (the box with `inset` sites skipped per axis).

# Keywords
- `level = 0`: the grid level (0: the lattice).
- `class = 0`: the placement class.
- `mask = 0`: the mask id of a `MASKED` space.
- `inset`: per axis, the `(low, high)` number of sites a `RESTRICTED` space skips.

See also [`kernel`](@ref).
"""
struct Space{N}
    kind::SpaceKind
    level::Int8
    class::Int8
    mask::Int32                      # MASKED: mask id
    inset::NTuple{N, NTuple{2, Int16}} # RESTRICTED: (low, high) sites skipped per axis
end
function Space{N}(
        kind = FULL; level = 0, class = 0, mask = 0,
        inset = ntuple(_ -> (Int16(0), Int16(0)), N)
    ) where {N}
    return Space{N}(
        kind, Int8(level), Int8(class), Int32(mask), inset
    )
end

"""
A store: `law = :owned` (own site, offset 0) or `:accumulate` (adds the value to the
current one at the own site; race-free, no atomics).
"""
struct Store{N}
    access::Access{N}
    value::Int32
    law::Symbol
end

"""
A reduction of `value` over the kernel's sites, `op ∈ (:sum, :max)`, into table `target`:
entry `b` holds the partial of the 256-site block `b` (pairwise sums inside a block); a
finishing pass combines the blocks. Deterministic: block boundaries never depend on the
launch configuration.
"""
struct Reduction
    op::Symbol
    value::Int32
    target::Int32
end

"""
A kernel. `gate` is a `BOOL` node (0: none): where it is false the kernel does nothing but
the pass-through of its two-buffer outputs, like a site outside a masked space. Solvers
gate on device flags (`done`). A kernel with `reductions` runs in 256-site blocks.
"""
struct Kernel{N}
    key::String
    space::Space{N}
    nodes::Vector{Node}
    operands::Vector{Int32}
    consts::Vector{Float64}
    accesses::Vector{Access{N}}
    tables::Vector{Int32}            # TABLE imm -> table id
    calls::Vector{Symbol}            # CALL imm -> function name (whitelist `CALLS`)
    stores::Vector{Store{N}}
    reductions::Vector{Reduction}
    gate::Int32
end
args(k::Kernel, n::Node) = view(k.operands, n.args)
args(k::Kernel, i::Integer) = args(k, k.nodes[i])

# ---- boundary rules ----------------------------------------------------------
abstract type AbstractBoundaryRule end

"""
    Coef(value, param)
    Coef(value::Real)

A coefficient `value`, times parameter `param` when `param > 0` (boundary values are
runtime parameters; the rule's kind is literal). `Coef(v)` has no parameter.

# Fields
- `value::Float64`: the literal factor.
- `param::Int32`: the parameter slot, or 0.
"""
struct Coef
    value::Float64
    param::Int32
end
Coef(v::Real) = Coef(Float64(v), Int32(0))

"""
`α c + β ∂c/∂n = g` on the face (`axis`, `side = ±1`) of a cell-centered field. Dirichlet:
α = 1, β = 0. No flux: α = 0, β = 1, g = 0. `β` is in lattice units (the front end divides
by h). `gfield` (0: none) is a field holding the value at each boundary site (a value that
reads the time, the coordinates or an input): then `g` is that field's value times the
coefficient `g` (a kernel of the program computes the field at the step's time). `afield`
and `bfield` (0: none) do the same for `α` and `β`: a Robin coefficient that varies by site
or in time is that field's value at the boundary site times the coefficient.

# Fields
- `field::Int32`: the field id.
- `axis::Int8`, `side::Int8`: the face (`side = ±1`).
- `alpha::Coef`, `beta::Coef`, `g::Coef`: the coefficients `α`, `β` and `g`.
- `gfield::Int32`, `afield::Int32`, `bfield::Int32`: the value fields of `g`, `α` and `β`,
  or 0.

The constructor `FaceRule(field, axis, side, alpha, beta, g, gfield = 0)` sets `afield` and
`bfield` to 0.

See also [`sitecoefs`](@ref), [`degenerate`](@ref).
"""
struct FaceRule <: AbstractBoundaryRule
    field::Int32
    axis::Int8
    side::Int8
    alpha::Coef
    beta::Coef
    g::Coef
    gfield::Int32
    afield::Int32
    bfield::Int32
end
function FaceRule(field, axis, side, alpha::Coef, beta::Coef, g::Coef, gfield = 0)
    return FaceRule(field, axis, side, alpha, beta, g, Int32(gfield), Int32(0), Int32(0))
end

"""
    sitecoefs(r::FaceRule) -> Bool

Does the face rule `r` have a coefficient `α` or `β` that varies by site or in time (a value
field)?

# Arguments
- `r`: a [`FaceRule`](@ref).

# Returns
- `true` if `r.afield` or `r.bfield` is nonzero.
"""
sitecoefs(r::FaceRule) = r.afield != 0 || r.bfield != 0

"""
    FACE_RTOL::Float64

Relative tolerance of the degenerate-face test: `|α/2 + β| ≤ tol (|α|/2 + |β|)`. The
value is `1.0e-6`. See [`degenerate`](@ref).
"""
const FACE_RTOL = 1.0e-6

"""
    degenerate(α, β) -> Bool

Whether a face with lattice coefficients `α`, `β` has `α/2 + β` zero to a relative
[`FACE_RTOL`](@ref) (the ghost value `(g − (α/2 − β) c)/(α/2 + β)` is then undefined or
amplified past any stable step). The explicit path (`Problems.check_faces`, LatticePDE's
`discretize`) and the solvers' Robin faces (`Solvers.CellOperator`) share this test.

# Arguments
- `α`, `β`: the face coefficients in lattice units.

# Returns
- `true` if `|α/2 + β| ≤ FACE_RTOL (|α|/2 + |β|)`.

# Examples
```jldoctest
julia> using LatticeFields.IR: degenerate

julia> degenerate(2.0, -1.0), degenerate(1.0, 0.0)
(true, false)
```
"""
degenerate(a::Real, b::Real) = abs(a / 2 + b) <= FACE_RTOL * (abs(a) / 2 + abs(b))
"""
    DomainEdgeRule(field, kind, mask = 0)

The irregular domain edge (`Grid.domain`): `:mirror` (zero flux) or `:zero`. The edge is
crossed from either side: a read of a neighbor outside the domain, or any neighbor read of a
site outside it, takes the rule's value (`:mirror`: the site's own value). `mask` names the
domain's mask on the field's own level (a coarse field's: the domain folded onto its grid);
0 is `Grid.domain`.

# Fields
- `field::Int32`: the field id.
- `kind::Symbol`: `:mirror` or `:zero`.
- `mask::Int32`: the mask of the domain on the field's level, or 0.
"""
struct DomainEdgeRule <: AbstractBoundaryRule
    field::Int32
    kind::Symbol
    mask::Int32
end
DomainEdgeRule(field::Integer, kind::Symbol) = DomainEdgeRule(Int32(field), kind, Int32(0))
"""
Reads across mask `mask` (into masked sites): `:zero_flux` mirrors the center value.
"""
struct ImmersedRule <: AbstractBoundaryRule
    field::Int32
    mask::Int32
    kind::Symbol
end
"""
    NodeValueRule(field, mask, value::Coef, face::Symbol, vfield = 0)

Masked node value: stores at masked sites write `value` (identity row). `vfield` (0: none)
is a field holding the value at each site (a value that reads the time, the coordinates or
an input): the value is then that field's value times the coefficient `value` (the mask's
kernel computes the field with the mask).

# Fields
- `field::Int32`: the field id.
- `mask::Int32`: the mask id.
- `value::Coef`: the value, or the factor of `vfield`.
- `face::Symbol`: `:harmonic` or `:active`.
- `vfield::Int32`: the value field, or 0.
"""
struct NodeValueRule <: AbstractBoundaryRule
    field::Int32
    mask::Int32
    value::Coef
    face::Symbol                     # :harmonic | :active
    vfield::Int32
end
function NodeValueRule(field, mask, value::Coef, face::Symbol)
    return NodeValueRule(field, mask, value, face, Int32(0))
end

"""
    Program{N}

A complete field IR program: the grid hierarchy, the declarations, the boundary rules and
the kernels. Build one with a [`ProgramBuilder`](@ref) and [`program`](@ref); passes return
new programs and never mutate one.

# Fields
- `hierarchy::Vector{Level{N}}`: the grid levels, the lattice first.
- `fields`, `tables`, `masks`, `flags`: the declarations, sorted by key.
- `rules::Vector{AbstractBoundaryRule}`: the boundary rules.
- `kernels::Vector{Kernel{N}}`: the kernels, sorted by key.
- `periodic::NTuple{N, Bool}`: the periodic axes.
- `spacing::NTuple{N, Float64}`: the lattice spacing per axis.
- `nparams::Int`: the number of runtime parameters.

See also [`print_program`](@ref), [`fieldid`](@ref), [`nsites`](@ref).
"""
struct Program{N}
    hierarchy::Vector{Level{N}}
    fields::Vector{FieldDecl{N}}
    tables::Vector{TableDecl}
    masks::Vector{MaskDecl}
    flags::Vector{FlagDecl}
    rules::Vector{AbstractBoundaryRule}
    kernels::Vector{Kernel{N}}
    periodic::NTuple{N, Bool}
    spacing::NTuple{N, Float64}
    nparams::Int
end
leveldims(p::Program, level::Integer) = leveldims(p.hierarchy[level + 1])
"""
    nsites(p::Program, level::Integer) -> Int

The number of nodes of program `p` on grid level `level` (0: the lattice).

# Arguments
- `p`: a [`Program`](@ref).
- `level`: the level index.

# Returns
- The product of [`leveldims`](@ref)`(p, level)`, as an `Int`.
"""
nsites(p::Program, level::Integer) = Int(prod(leveldims(p, level)))
"""
    fieldid(p::Program, key::AbstractString) -> Int32

The id of the field with key `key` in program `p`.

# Arguments
- `p`: a [`Program`](@ref).
- `key`: the field key.

# Returns
- The field's index in `p.fields`, as an `Int32`. A missing key throws a `MethodError`
  (from `Int32(nothing)`).
"""
fieldid(p::Program, key::AbstractString) = Int32(findfirst(f -> f.key == key, p.fields))
