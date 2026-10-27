# IR data model (v3 §3). Plain host values; nothing here reaches the device. Every compiler
# pass is written against these types once per spatial dimension `N`.

"""
Element types of IR values. Storage lanes are `F16 F32 F64 U8 I32 U32` (R1 F5); `REAL` is
the abstract float compute type that pass 4 resolves to `T`; `BOOL` is a predicate.
"""
@enum Scalar::UInt8 F16 F32 F64 U8 I32 U32 REAL BOOL

const LANES = (F16, F32, F64, U8, I32, U32)
isfloat(t::Scalar) = t in (F16, F32, F64, REAL)
isinteger_lane(t::Scalar) = t in (U8, I32, U32)
isunsigned_lane(t::Scalar) = t in (U8, U32)
"""
Storage size in bytes of one element of lane `t`.
"""
lanebytes(t::Scalar) = t == U8 ? 1 : t == F16 ? 2 : t == F64 ? 8 : 4
"""
Host Julia type of an integer or storage lane.
"""
juliatype(t::Scalar) = (Float16, Float32, Float64, UInt8, Int32, UInt32)[Int(t) + 1]

@enum Geometry::UInt8 CUBIC HEX
@enum Epoch::UInt8 STATIC PERSIGMA PERSTEP INNER
"""
Boundary policy of an access: `RESOLVE` (pass 2 rewrites out-of-domain reads), `INSIDE`
(proven inside), `ZERO` (outside reads 0), `CLAMP` (nearest inside value).
"""
@enum Bpolicy::UInt8 RESOLVE INSIDE ZERO CLAMP
@enum SpaceKind::UInt8 FULL MASKED RESTRICTED

# The op set of v3 §3.4. Printing and fingerprints use the names, never the codes, so adding
# an op never changes an existing program's text (O-2 additivity).
@enum Op::UInt8 CONST PARAM LOAD TABLE COORD INSIDE_OP BITTEST RUNTIME ADD MUL NEG DIV FMA MIN MAX ABS POWI SQRT EXP LOG CALL EQ LT LE AND OR NOT XOR SELECT COND CAST IDX RESTRICT ELEMENT_SUM

# RESTRICT(x; imm = 0 sum | 1 max | 2 plurality) at a coarse site combines `x` over the site's
# children (plurality: the most frequent value, ties to the smallest nonzero value, 0 last)
# (2 per coarsened axis, 3 at the last site of an odd axis): inside `x`, an access at level −1
# is taken relative to each child in turn (offset in the fine frame).
opname(op::Op) = op == INSIDE_OP ? "inside" : lowercase(string(op))
const COMMUTATIVE = (ADD, MUL, MIN, MAX, EQ, AND, OR, XOR)
const CALLS = (
    :sin, :cos, :tan, :tanh, :sinh, :cosh, :cbrt, :exp2, :log2, :log10, :expm1, :log1p,
    :atan, :floor, :ceil, :round)

struct Grid{N}
    dims::NTuple{N, Int32}
    geometry::Geometry
    domain::Int32                    # mask id of the irregular domain, 0 for the full box
end
function Grid(dims::NTuple{N, Integer}; geometry = CUBIC, domain = 0) where {N}
    Grid{N}(
        Int32.(dims), geometry, Int32(domain))
end

"""
A grid level: `shift` coarsenings by 2 (D-051 coarse fields and MG levels).
"""
struct Level{N}
    grid::Grid{N}
    shift::Int8
    widths::Union{Nothing, NTuple{N, Vector{Int8}}}
end
Level(g::Grid{N}, shift = 0) where {N} = Level{N}(g, Int8(shift), nothing)
# Coarse levels: each coarsening halves an axis with floor, `n ÷ 2`; the last aggregate of an
# odd axis takes width 3 (high end, P4-mg42; contract.jl). An axis of size 1 is never
# coarsened (it stays 1, identity map); an axis that would reach 0 sites makes the level
# illegal (`coarsenable`, checked by legality).
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
    shape::Vector{Int16}             # empty: scalar; `[k]`: k components (flat, after symmetry)
    symmetric::Bool
    storage::Scalar
    levels::Vector{Int8}
    epoch::Epoch
    buffers::Int8                    # 1, or 2 for host ping-pong
    role::Symbol                     # :state | :aux | :input | :output | :scratch
    fixed::Bool                      # a declared storage (`lattice_storage`, FE-17): the float lane
                                     # holds its own type under `lanes = :state` (`lanetype`)
end
FieldDecl{N}(key, classes, shape, symmetric, storage, levels, epoch, buffers, role) where {N} =
    FieldDecl{N}(key, classes, shape, symmetric, storage, levels, epoch, buffers, role, false)
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
A site mask; its bytes live in the `U8` field `field` (nonzero = inside the mask).
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
An index select between two literals, decided by a Bool node (`cond = 0`: always `a`).
"""
struct Sel{V}
    a::V
    b::V
    cond::Int32
end
Sel(v) = Sel(v, v, Int32(0))

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

struct Space{N}
    kind::SpaceKind
    level::Int8
    class::Int8
    mask::Int32                      # MASKED: mask id
    inset::NTuple{N, NTuple{2, Int16}} # RESTRICTED: (low, high) sites skipped per axis
end
function Space{N}(kind = FULL; level = 0, class = 0, mask = 0,
        inset = ntuple(_ -> (Int16(0), Int16(0)), N)) where {N}
    Space{N}(
        kind, Int8(level), Int8(class), Int32(mask), inset)
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

# ---- boundary rules (v3 §3.5) ----------------------------------------------------------
abstract type BRule end

"""
A coefficient `value`, times parameter `param` when `param > 0` (boundary values are
runtime parameters; the rule's kind is literal).
"""
struct Coef
    value::Float64
    param::Int32
end
Coef(v::Real) = Coef(Float64(v), Int32(0))

"""
`α c + β ∂c/∂n = g` on the face (`axis`, `side = ±1`) of a cell-centered field. Dirichlet:
α = 1, β = 0. No flux: α = 0, β = 1, g = 0. `β` is in lattice units (the front end divides by h).
`gfield` (0: none) is a field holding the value at each boundary site (a value that reads the
time, the coordinates or an input, F3-07): then `g` is that field's value times the
coefficient `g` (a kernel of the program computes the field at the step's time).
"""
struct FaceRule <: BRule
    field::Int32
    axis::Int8
    side::Int8
    alpha::Coef
    beta::Coef
    g::Coef
    gfield::Int32
end
FaceRule(field, axis, side, alpha::Coef, beta::Coef, g::Coef) = FaceRule(field, axis, side, alpha, beta, g, Int32(0))

"""Relative tolerance of the degenerate-face test: `|α/2 + β| ≤ tol (|α|/2 + |β|)`."""
const FACE_RTOL = 1e-6

"""
    degenerate(α, β) -> Bool

Whether a face with lattice coefficients `α`, `β` has `α/2 + β` zero to a relative
[`FACE_RTOL`](@ref) (the ghost value `(g − (α/2 − β) c)/(α/2 + β)` is then undefined or
amplified past any stable step). The explicit path (`Problems.check_faces`, LatticePDE's
`discretize`) and the solvers' Robin faces (`Solvers.CellOperator`) share this test.
"""
degenerate(a::Real, b::Real) = abs(a / 2 + b) <= FACE_RTOL * (abs(a) / 2 + abs(b))
"""
The irregular domain edge (`Grid.domain`): `:mirror` (zero flux) or `:zero`. The edge is
crossed from either side: a read of a neighbor outside the domain, or any neighbor read of a
site outside it, takes the rule's value (`:mirror`: the site's own value). `mask` names the
domain's mask on the field's own level (a coarse field's: the domain folded onto its grid);
0 is `Grid.domain`.
"""
struct DomainEdgeRule <: BRule
    field::Int32
    kind::Symbol
    mask::Int32
end
DomainEdgeRule(field::Integer, kind::Symbol) = DomainEdgeRule(Int32(field), kind, Int32(0))
"""
Reads across mask `mask` (into masked sites): `:zero_flux` mirrors the center value.
"""
struct ImmersedRule <: BRule
    field::Int32
    mask::Int32
    kind::Symbol
end
"""
Masked node value: stores at masked sites write `value` (identity row). `vfield` (0: none) is
a field holding the value at each site (a value that reads the time, the coordinates or an
input, F3-07): the value is then that field's value times the coefficient `value` (the mask's
kernel computes the field with the mask).
"""
struct NodeValueRule <: BRule
    field::Int32
    mask::Int32
    value::Coef
    face::Symbol                     # :harmonic | :active
    vfield::Int32
end
NodeValueRule(field, mask, value::Coef, face::Symbol) = NodeValueRule(field, mask, value, face, Int32(0))

struct Program{N}
    hierarchy::Vector{Level{N}}
    fields::Vector{FieldDecl{N}}
    tables::Vector{TableDecl}
    masks::Vector{MaskDecl}
    flags::Vector{FlagDecl}
    rules::Vector{BRule}
    kernels::Vector{Kernel{N}}
    periodic::NTuple{N, Bool}
    spacing::NTuple{N, Float64}
    nparams::Int
end
leveldims(p::Program, level::Integer) = leveldims(p.hierarchy[level + 1])
nsites(p::Program, level::Integer) = Int(prod(leveldims(p, level)))
fieldid(p::Program, key::AbstractString) = Int32(findfirst(f -> f.key == key, p.fields))
