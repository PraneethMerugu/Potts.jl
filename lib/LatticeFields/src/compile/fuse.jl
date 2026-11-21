# The update pass: a stepper's update fused into a rate program as an IR
# pass, so any algorithm lowers in the Symbolics-free layer (`FieldGroup`).

# a field declaration with two time slots (a stepped field)
function _two_slot(f::FieldDecl{N}) where {N}
    return FieldDecl{N}(
        f.key, f.classes, f.shape, f.symmetric, f.storage,
        f.levels, f.epoch, Int8(2), f.role, f.fixed, f.periodic
    )
end

"""
    fuse_update(rate::Program, rule) -> Program

The program that steps rate program `rate` (before the semantic passes) with the update
`rule`. Each `rate:c` kernel stores the rate `r` of field `c` into its scratch field `∂c`;
here the store goes to `c` itself, of `rule(kb, c, r)` (`kb` the kernel builder, `c` the
load of the field's current value and `r` the rate, both `Ex` handles; `rule` returns an
`Ex`). With an irregular domain the rate's `select(inside, r, 0)` becomes
`select(inside, rule(kb, c, r), c)`: a site outside keeps its value. The scratch fields are
dropped and the stepped fields get two buffers. The other kernels (`map:`, `aux:`, `mask:`),
the masks and the rules pass through, renumbered. `rule === nothing` returns `rate`.

The result is node for node the program a front end fuses symbolically
(`symbolic_discretize(…; update = rule)`): the builder interns and orders every node
structurally, and kernels are renumbered canonically (`finish`), so `fingerprint_text` of
the two is the same.

# Arguments
- `rate`: the rate program, before the semantic passes.
- `rule`: a function `rule(kb, c, r) -> Ex`, or `nothing`.

# Returns
- The stepped `Program`, or `rate` itself if `rule === nothing` or no `rate:c` kernel has
  a scratch field.

See also [`fuse_residual`](@ref).
"""
function fuse_update(p::Program{N}, rule) where {N}
    rule === nothing && return p
    keys = [f.key for f in p.fields]
    step = Dict{Int32, Int32}()                     # ∂c → c
    for k in p.kernels
        startswith(k.key, "rate:") || continue
        c = k.key[(ncodeunits("rate:") + 1):end]
        s = findfirst(==("∂" * c), keys)
        j = findfirst(==(c), keys)
        # a kernel with no scratch field stores into its field already (a program written
        # fused)
        (s === nothing || j === nothing) && continue
        step[Int32(s)] = Int32(j)
    end
    isempty(step) && return p
    keep = [i for i in eachindex(p.fields) if !haskey(step, Int32(i))]
    newid = zeros(Int32, length(p.fields))
    newid[keep] .= Int32.(1:length(keep))
    stepped = Set(values(step))
    function fm(i)
        if i == 0
            return Int32(0)
        elseif haskey(step, Int32(i))
            return newid[step[Int32(i)]]
        else
            return newid[i]
        end
    end
    fields = [
        i in stepped ? _two_slot(f) : f
            for (i, f) in enumerate(p.fields) if i in keep
    ]
    bk = ([f.key for f in fields], [f.storage for f in fields], [t.key for t in p.tables])
    dom = p.hierarchy[1].grid.domain != 0
    kernels = map(p.kernels) do k
        startswith(k.key, "rate:") || return rebuild(copy_node!, k, bk; fieldmap = fm)
        rebuild(
            copy_node!, k, bk; fieldmap = fm,
            storefn = (b, s, v) -> _fused_store(b, s, v, rule, dom)
        )
    end
    masks = [MaskDecl(m.key, fm(m.field), m.epoch) for m in p.masks]
    flags = [FlagDecl(g.key, fm(g.field), g.bits, g.epoch) for g in p.flags]
    rules = AbstractBoundaryRule[_rulemap(r, fm, identity) for r in p.rules]
    return Program{N}(
        p.hierarchy, fields, p.tables, masks, flags,
        rules, kernels, p.periodic, p.spacing, p.nparams
    )
end

# the store of a fused rate kernel: `rule(c, r)` into `c`, inside the domain when there is
# one
function _fused_store(b::KernelBuilder, s::Store, v, rule, dom::Bool)
    f = s.access.field
    lane = b.fieldlanes[f]
    x, inside = v, Int32(0)
    if dom
        n = b.nodes[v]
        a = nodeargs(b, v)
        z = n.op == SELECT ? b.nodes[a[3]] : nothing
        if z !== nothing && z.op == CONST && b.consts[z.imm] == 0.0
            inside, x = a[1], a[2]
        end
    end
    c = load!(b, f, lane)
    u = rule(b, Ex(b, c), Ex(b, x)).id
    inside == 0 || (u = select!(b, inside, u, c))
    return isfloat(lane) ? cast!(b, u, REAL) : u
end

"""
    fuse_residual(rate::Program, rule) -> Program

The residual program of an implicit stepper: the fields of
`fuse_update(rate, …)` in the same order and at the same ids (the state fields with two
buffers, no scratch `∂c`), so a runtime's store of the stepped program serves it, followed
by one residual field `res:c` and one history field `c__n` (a one-buffer input: the state at
the substep's start, `uⁿ`) per rate field `c`, in the order of the `rate:c` kernels. Each
`rate:c` kernel stores `rule(kb, c, r, cn)` into `res:c` (`c` the load of the field, the
iterate `u_k`; `r` the rate; `cn` the load of `c__n`; IR handles), and nothing into `c`: the
state is read, never written. With an irregular domain a site outside stores 0. The other
kernels and the rules pass through, renumbered (as `fuse_update`).

`widen16 = true` (the solve's residual): the residual of a field stored in
Float16 is held in the state's value type (a float lane, not fixed), the type the solver
reads, so the solve sees no Float16 rounding beyond the state's own.

# Arguments
- `rate`: the rate program, before the semantic passes.
- `rule`: a function `rule(kb, c, r, cn) -> Ex`.

# Keywords
- `widen16 = false`: hold the residual of a Float16 field in the state's value type.

# Returns
- The residual `Program`.

See also [`fuse_update`](@ref).
"""
function fuse_residual(p::Program{N}, rule; widen16::Bool = false) where {N}
    keys = [f.key for f in p.fields]
    step = Dict{Int32, Int32}()                     # ∂c → c
    order = String[]
    for k in p.kernels
        startswith(k.key, "rate:") || continue
        c = k.key[(ncodeunits("rate:") + 1):end]
        s = findfirst(==("∂" * c), keys)
        j = findfirst(==(c), keys)
        (s === nothing || j === nothing) && continue
        step[Int32(s)] = Int32(j)
        push!(order, c)
    end
    keep = [i for i in eachindex(p.fields) if !haskey(step, Int32(i))]
    newid = zeros(Int32, length(p.fields))
    newid[keep] .= Int32.(1:length(keep))
    stepped = Set(values(step))
    fields = [
        i in stepped ? _two_slot(f) : f
            for (i, f) in enumerate(p.fields) if i in keep
    ]
    nk = length(fields)
    # the residual and history fields, appended: `res:c` at `nk + j`, `c__n` at `nk + n + j`
    res = Dict{String, Int32}()
    hist = Dict{String, Int32}()
    for (j, c) in enumerate(order)
        f = p.fields[findfirst(==(c), keys)]
        wide = widen16 && f.storage == F16
        push!(
            fields, FieldDecl{N}(
                "res:" * c, f.classes, f.shape, f.symmetric, wide ? F32 : f.storage,
                f.levels, f.epoch,
                Int8(1), :scratch, wide ? false : f.fixed, f.periodic
            )
        )
        res[c] = Int32(nk + j)
    end
    for (j, c) in enumerate(order)
        f = p.fields[findfirst(==(c), keys)]
        push!(
            fields,
            FieldDecl{N}(
                c * "__n", f.classes, f.shape, f.symmetric, f.storage,
                f.levels, f.epoch, Int8(1), :input, f.fixed, f.periodic
            )
        )
        hist[c] = Int32(nk + length(order) + j)
    end
    function fm(i)
        if i == 0
            return Int32(0)
        elseif haskey(step, Int32(i))
            return res[keys[step[Int32(i)]]]
        else
            return newid[i]
        end
    end
    bk = ([f.key for f in fields], [f.storage for f in fields], [t.key for t in p.tables])
    dom = p.hierarchy[1].grid.domain != 0
    kernels = map(p.kernels) do k
        startswith(k.key, "rate:") || return rebuild(copy_node!, k, bk; fieldmap = fm)
        c = k.key[(ncodeunits("rate:") + 1):end]
        haskey(res, c) || return rebuild(copy_node!, k, bk; fieldmap = fm)
        cid, hid = newid[findfirst(==(c), keys)], hist[c]
        rebuild(
            copy_node!, k, bk; fieldmap = fm,
            storefn = (b, s, v) -> _residual_store(b, s, v, rule, dom, cid, hid)
        )
    end
    # (a rule never names a scratch field: `fm` maps the others to their new ids)
    masks = [MaskDecl(m.key, fm(m.field), m.epoch) for m in p.masks]
    flags = [FlagDecl(g.key, fm(g.field), g.bits, g.epoch) for g in p.flags]
    rules = AbstractBoundaryRule[_rulemap(r, fm, identity) for r in p.rules]
    return Program{N}(
        p.hierarchy, fields, p.tables, masks, flags,
        rules, kernels, p.periodic, p.spacing, p.nparams
    )
end

# the store of a residual kernel: `rule(c, r, cn)` into `res:c` (the store's field), 0
# outside the domain when there is one
function _residual_store(b::KernelBuilder, s::Store, v, rule, dom::Bool, cid, hid)
    lane = b.fieldlanes[s.access.field]
    x, inside = v, Int32(0)
    if dom
        n = b.nodes[v]
        a = nodeargs(b, v)
        z = n.op == SELECT ? b.nodes[a[3]] : nothing
        if z !== nothing && z.op == CONST && b.consts[z.imm] == 0.0
            inside, x = a[1], a[2]
        end
    end
    c = load!(b, cid, b.fieldlanes[cid])
    cn = load!(b, hid, b.fieldlanes[hid])
    u = rule(b, Ex(b, c), Ex(b, x), Ex(b, cn)).id
    inside == 0 || (u = select!(b, inside, u, constant!(b, 0.0)))
    return isfloat(lane) ? cast!(b, u, REAL) : u
end
