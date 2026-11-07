# Program assembly. Front ends declare fields, masks, tables and rules in any order and build
# kernels against provisional ids; `program` sorts every table by key, renumbers the ids and
# rebuilds each kernel canonically, so declaration order never reaches the IR.

mutable struct ProgramBuilder{N}
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
function ProgramBuilder(
        grid::Grid{N}; periodic = ntuple(_ -> false, N), spacing = ntuple(_ -> 1.0, N),
        nparams = 0, levels = 1) where {N}
    return ProgramBuilder{N}(
        [Level(grid, s) for s in 0:(levels - 1)], FieldDecl{N}[], TableDecl[],
        MaskDecl[], FlagDecl[], BRule[], Kernel{N}[], Tuple(periodic),
        Float64.(Tuple(spacing)), nparams)
end

"""
Declare a field; returns its provisional id. `fixed = true` (a declared storage, FE-17): the
float lane `storage` holds its own type under `lanes = :state` too, where a lane otherwise
holds the problem's value type ([`lanetype`](@ref LatticeFields.Compile.lanetype)).
"""
function field!(
        pb::ProgramBuilder{N}, key; storage = F32, shape = Int16[], symmetric = false,
        buffers = 1, role = :state, epoch = PERSTEP, levels = Int8[0],
        classes = [Placement{N}()], fixed = false) where {N}
    any(f -> f.key == key, pb.fields) && error("field `$key` declared twice")
    role in (:state, :aux, :input, :output, :scratch) ||
        error("field `$key`: unknown role `$role`")
    storage in LANES || error("field `$key`: `$storage` is not a storage lane")
    push!(pb.fields,
        FieldDecl{N}(String(key), classes, Int16.(shape), symmetric, storage,
            Int8.(levels), epoch, Int8(buffers), role, fixed))
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
rule!(pb::ProgramBuilder, r::BRule) = (push!(pb.rules, r); nothing)

"""
A kernel builder for space `space` (default: the full space at level 0).
"""
function kernel(pb::ProgramBuilder{N}, space::Space{N} = Space{N}()) where {N}
    KernelBuilder{N}(
        [f.key for f in pb.fields], [f.storage for f in pb.fields], [t.key
                                                                     for t in pb.tables], space)
end

"""
Finish kernel builder `kb` under `key` and add it to the program.
"""
function add!(pb::ProgramBuilder, kb::KernelBuilder, key)
    any(k -> k.key == key, pb.kernels) && error("kernel `$key` declared twice")
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
    Ex(kb, table!(kb, t, storage, i.id))
end
function store(kb::KernelBuilder, f::Integer, v::Ex; kw...)
    store!(kb, f, kb.fieldlanes[f], v.id; kw...)
end
function store(kb::KernelBuilder, f::Integer, v::Real; kw...)
    store!(kb, f, kb.fieldlanes[f], constant!(kb, v); kw...)
end

_perm(keys) = (p = sortperm(keys); inv = similar(p); inv[p] = 1:length(p); (p, inv))

_rulemap(r::FaceRule, fm, mm) = FaceRule(fm(r.field), r.axis, r.side, r.alpha, r.beta, r.g, fm(r.gfield),
    fm(r.afield), fm(r.bfield))
_rulemap(r::DomainEdgeRule, fm, mm) = DomainEdgeRule(fm(r.field), r.kind, r.mask == 0 ? Int32(0) : mm(r.mask))
_rulemap(r::ImmersedRule, fm, mm) = ImmersedRule(fm(r.field), mm(r.mask), r.kind)
_rulemap(r::NodeValueRule, fm, mm) = NodeValueRule(fm(r.field), mm(r.mask), r.value, r.face, fm(r.vfield))

"""
Sort fields, masks, tables, rules and kernels by key and rebuild every kernel canonically.
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
    flags = [FlagDecl(g.key, fm(g.field), [b => mm(s) for (b, s) in g.bits], g.epoch)
             for g in pb.flags]
    kernels = map(sort(pb.kernels; by = k -> k.key)) do k
        sp = k.space
        space = Space{N}(sp.kind, sp.level, sp.class, mm(sp.mask), sp.inset)
        rebuild(copy_node!, k, keys; space, fieldmap = fm, tablemap = tm)
    end
    grid = pb.hierarchy[1].grid
    hier = [Level{N}(Grid{N}(grid.dims, grid.geometry, mm(grid.domain)), l.shift, l.widths)
            for l in pb.hierarchy]
    rules = BRule[_rulemap(r, fm, mm) for r in pb.rules]
    p = Program{N}(
        hier, fields, tables, masks, sort(flags; by = g -> g.key), rules, kernels,
        pb.periodic, pb.spacing, pb.nparams)
    return Program{N}(hier, fields, tables, masks, p.flags,
        sort(rules; by = r -> sprint(print_rule, p, r)), kernels, pb.periodic, pb.spacing, pb.nparams)
end

"""
Replace the kernels of `p` (passes return new programs; nothing is mutated).
"""
function with_kernels(p::Program{N}, ks) where {N}
    Program{N}(p.hierarchy, p.fields, p.tables, p.masks,
        p.flags, p.rules, collect(Kernel{N}, ks), p.periodic, p.spacing, p.nparams)
end
function buildkeys(p::Program)
    ([f.key for f in p.fields], [f.storage for f in p.fields], [t.key for t in p.tables])
end
