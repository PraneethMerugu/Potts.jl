# Program assembly. Front ends declare fields, masks, tables and rules in any order and
# build kernels against provisional ids; `program` sorts every table by key, renumbers the
# ids and rebuilds each kernel canonically, so declaration order never reaches the IR.

"""
    ProgramBuilder(grid::Grid; periodic = (false, …), spacing = (1.0, …), nparams = 0,
                   levels = 1)

The builder of a field program. Front ends declare fields, masks, tables and rules in any
order and build kernels against provisional ids; [`program`](@ref) sorts every table by key
and renumbers the ids, so declaration order never reaches the IR.

# Arguments
- `grid`: the lattice [`Grid`](@ref).

# Keywords
- `periodic = ntuple(_ -> false, N)`: the periodic axes.
- `spacing = ntuple(_ -> 1.0, N)`: the lattice spacing per axis.
- `nparams = 0`: the number of runtime parameters.
- `levels = 1`: the number of grid levels (the lattice and `levels − 1` coarsenings).

# Examples
```jldoctest
julia> using LatticeFields.IR

julia> pb = IR.ProgramBuilder(IR.Grid((4, 4)));

julia> u = IR.field!(pb, "u"; storage = IR.F32);

julia> kb = IR.kernel(pb);

julia> IR.store!(kb, u, IR.F32, IR.constant!(kb, 1.0))

julia> IR.add!(pb, kb, "init:u")

julia> length(IR.program(pb).kernels)
1
```

See also [`field!`](@ref), [`kernel`](@ref), [`add!`](@ref), [`program`](@ref).
"""
mutable struct ProgramBuilder{N}
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
function ProgramBuilder(
        grid::Grid{N}; periodic = ntuple(_ -> false, N), spacing = ntuple(_ -> 1.0, N),
        nparams = 0, levels = 1
    ) where {N}
    return ProgramBuilder{N}(
        [Level(grid, s) for s in 0:(levels - 1)], FieldDecl{N}[], TableDecl[],
        MaskDecl[], FlagDecl[], AbstractBoundaryRule[], Kernel{N}[], Tuple(periodic),
        Float64.(Tuple(spacing)), nparams
    )
end

"""
Declare a field; returns its provisional id. `fixed = true` (a declared storage): the
float lane `storage` holds its own type under `lanes = :state` too, where a lane otherwise
holds the problem's value type ([`lanetype`](@ref LatticeFields.Compile.lanetype)).
`periodic` (default: the program's) gives, per axis, whether the field wraps; on a closed
axis its accesses take its face rules.

# Arguments
- `pb`: the [`ProgramBuilder`](@ref).
- `key`: the field key, unique in the program.

# Keywords
- `storage = F32`: the storage lane.
- `shape = Int16[]`: empty for a scalar field, `[k]` for `k` components.
- `symmetric = false`: whether the components are stored after symmetry.
- `buffers = 1`: 1, or 2 for a field with two time slots.
- `role = :state`: `:state`, `:aux`, `:input`, `:output` or `:scratch`.
- `epoch = PERSTEP`: the [`Epoch`](@ref).
- `levels = Int8[0]`: the grid levels the field lives on.
- `classes`: the placement classes (default: one site class).
- `fixed = false`: the field declared its storage type.
- `periodic = pb.periodic`: per axis, whether the field wraps.

A duplicate key, an unknown role, a non-lane storage or a `periodic` of the wrong length
throws an [`IRError`](@ref).

# Returns
- The provisional field id, an `Int32`.
"""
function field!(
        pb::ProgramBuilder{N}, key; storage = F32, shape = Int16[], symmetric = false,
        buffers = 1, role = :state, epoch = PERSTEP, levels = Int8[0],
        classes = [Placement{N}()], fixed = false, periodic = pb.periodic
    ) where {N}
    length(periodic) == N ||
        irerror("field `$key`: `periodic` has ", length(periodic), " axes, not ", N)
    any(f -> f.key == key, pb.fields) && irerror("field `$key` declared twice")
    role in (:state, :aux, :input, :output, :scratch) ||
        irerror("field `$key`: unknown role `$role`")
    storage in LANES || irerror("field `$key`: `$storage` is not a storage lane")
    push!(
        pb.fields,
        FieldDecl{N}(
            String(key), classes, Int16.(shape), symmetric, storage,
            Int8.(levels), epoch, Int8(buffers), role, fixed, Tuple(Bool.(periodic))
        )
    )
    return Int32(length(pb.fields))
end

"""
Declare a mask stored in a new `U8` input field `key`; returns the mask id.
"""
function mask!(pb::ProgramBuilder, key; epoch = PERSIGMA)
    f = field!(pb, key; storage = U8, role = :input, epoch)
    push!(pb.masks, MaskDecl(String(key), f, epoch))
    return Int32(length(pb.masks))
end
function table!(pb::ProgramBuilder, key; storage = F32, oob = :zero_at_0)
    push!(pb.tables, TableDecl(String(key), storage, oob))
    return Int32(length(pb.tables))
end
"""
    rule!(pb::ProgramBuilder, r::AbstractBoundaryRule)

Add boundary rule `r` (a [`FaceRule`](@ref), [`DomainEdgeRule`](@ref),
[`NodeValueRule`](@ref) or immersed rule) to the program.

# Arguments
- `pb`: the [`ProgramBuilder`](@ref).
- `r`: the rule, with provisional field and mask ids.

# Returns
- `nothing`.
"""
rule!(pb::ProgramBuilder, r::AbstractBoundaryRule) = (push!(pb.rules, r); nothing)

"""
    kernel(pb::ProgramBuilder, space::Space = Space{N}()) -> KernelBuilder

A kernel builder for space `space` (default: the full space at level 0).

# Arguments
- `pb`: the [`ProgramBuilder`](@ref). The builder sees the fields and tables declared so
  far.
- `space`: the [`Space`](@ref) the kernel runs on.

# Returns
- A new [`KernelBuilder`](@ref).
"""
function kernel(pb::ProgramBuilder{N}, space::Space{N} = Space{N}()) where {N}
    return KernelBuilder{N}(
        [f.key for f in pb.fields], [f.storage for f in pb.fields], [
            t.key
                for t in pb.tables
        ], space
    )
end

"""
    add!(pb::ProgramBuilder, kb::KernelBuilder, key)

Finish kernel builder `kb` under `key` and add it to the program.

Finishing renumbers the nodes in a canonical depth-first order from the sorted stores and
drops unused nodes. A duplicate key throws an [`IRError`](@ref).

# Arguments
- `pb`: the [`ProgramBuilder`](@ref).
- `kb`: the kernel builder.
- `key`: the kernel key, for example `"rate:u"`.

# Returns
- `nothing`.
"""
function add!(pb::ProgramBuilder, kb::KernelBuilder, key)
    any(k -> k.key == key, pb.kernels) && irerror("kernel `$key` declared twice")
    push!(pb.kernels, finish(kb, key))
    return nothing
end

# Conveniences on handles, so front ends and tests write `load(kb, c; offset = (1, 0))`.
load(kb::KernelBuilder, f::Integer; kw...) = Ex(kb, load!(kb, f, kb.fieldlanes[f]; kw...))
param(kb::KernelBuilder, i) = Ex(kb, param!(kb, i))
runtime(kb::KernelBuilder, i) = Ex(kb, runtime!(kb, i))
coord(kb::KernelBuilder, d) = Ex(kb, coord!(kb, d))
constant(kb::KernelBuilder, v::Real, t::Scalar = REAL) = Ex(kb, constant!(kb, v, t))
cast(x::Ex, t::Scalar) = Ex(x.b, cast!(x.b, x.id, t))
bittest(x::Ex, bit::Integer) = Ex(x.b, bittest!(x.b, x.id, bit))
function table(kb::KernelBuilder, t::Integer, storage::Scalar, i::Ex)
    return Ex(kb, table!(kb, t, storage, i.id))
end
function store(kb::KernelBuilder, f::Integer, v::Ex; kw...)
    return store!(kb, f, kb.fieldlanes[f], v.id; kw...)
end
function store(kb::KernelBuilder, f::Integer, v::Real; kw...)
    return store!(kb, f, kb.fieldlanes[f], constant!(kb, v); kw...)
end

_perm(keys) = (p = sortperm(keys); inv = similar(p); inv[p] = 1:length(p); (p, inv))

function _rulemap(r::FaceRule, fm, mm)
    return FaceRule(
        fm(r.field), r.axis, r.side, r.alpha, r.beta, r.g, fm(r.gfield),
        fm(r.afield), fm(r.bfield)
    )
end
function _rulemap(r::DomainEdgeRule, fm, mm)
    return DomainEdgeRule(fm(r.field), r.kind, r.mask == 0 ? Int32(0) : mm(r.mask))
end
_rulemap(r::ImmersedRule, fm, mm) = ImmersedRule(fm(r.field), mm(r.mask), r.kind)
function _rulemap(r::NodeValueRule, fm, mm)
    return NodeValueRule(fm(r.field), mm(r.mask), r.value, r.face, fm(r.vfield))
end

"""
    program(pb::ProgramBuilder) -> Program

Sort fields, masks, tables, rules and kernels by key and rebuild every kernel canonically.

# Arguments
- `pb`: the [`ProgramBuilder`](@ref).

# Returns
- The [`Program`](@ref), with final ids.
"""
function program(pb::ProgramBuilder{N}) where {N}
    fp, finv = _perm([f.key for f in pb.fields])
    mp, minv = _perm([m.key for m in pb.masks])
    tp, tinv = _perm([t.key for t in pb.tables])
    fm(i) = i == 0 ? Int32(0) : Int32(finv[i])
    mm(i) = i == 0 ? Int32(0) : Int32(minv[i])
    tm(i) = Int32(tinv[i])
    fields = pb.fields[fp]
    tables = pb.tables[tp]
    keys = ([f.key for f in fields], [f.storage for f in fields], [t.key for t in tables])
    masks = [MaskDecl(m.key, fm(m.field), m.epoch) for m in pb.masks[mp]]
    flags = [
        FlagDecl(g.key, fm(g.field), [b => mm(s) for (b, s) in g.bits], g.epoch)
            for g in pb.flags
    ]
    kernels = map(sort(pb.kernels; by = k -> k.key)) do k
        sp = k.space
        space = Space{N}(sp.kind, sp.level, sp.class, mm(sp.mask), sp.inset)
        rebuild(copy_node!, k, keys; space, fieldmap = fm, tablemap = tm)
    end
    grid = pb.hierarchy[1].grid
    hier = [
        Level{N}(Grid{N}(grid.dims, grid.geometry, mm(grid.domain)), l.shift, l.widths)
            for l in pb.hierarchy
    ]
    rules = AbstractBoundaryRule[_rulemap(r, fm, mm) for r in pb.rules]
    p = Program{N}(
        hier, fields, tables, masks, sort(flags; by = g -> g.key), rules, kernels,
        pb.periodic, pb.spacing, pb.nparams
    )
    return Program{N}(
        hier, fields, tables, masks, p.flags,
        sort(rules; by = r -> sprint(print_rule, p, r)), kernels, pb.periodic, pb.spacing,
        pb.nparams
    )
end

"""
    fieldperiodic(p, f) -> NTuple{N, Bool}

Per axis, whether field `f` (an id) of program `p` wraps.

# Arguments
- `p`: a [`Program`](@ref).
- `f`: the field id.

# Returns
- The field's `periodic` tuple.
"""
fieldperiodic(p::Program, f::Integer) = p.fields[f].periodic

"""
Replace the kernels of `p` (passes return new programs; nothing is mutated).
"""
function with_kernels(p::Program{N}, ks) where {N}
    return Program{N}(
        p.hierarchy, p.fields, p.tables, p.masks,
        p.flags, p.rules, collect(Kernel{N}, ks), p.periodic, p.spacing, p.nparams
    )
end
function buildkeys(p::Program)
    return (
        [f.key for f in p.fields], [f.storage for f in p.fields], [t.key for t in p.tables],
    )
end
