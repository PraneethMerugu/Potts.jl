# The update pass (F2 design §2.5): a stepper's update fused into a rate program as an IR
# pass, so any algorithm lowers in the Symbolics-free layer (`FieldGroup`).

"""
    fuse_update(rate::Program, rule) -> Program

The program that steps rate program `rate` (before the semantic passes) with the update
`rule`. Each `rate:c` kernel stores the rate `r` of field `c` into its scratch field `∂c`;
here the store goes to `c` itself, of `rule(kb, c, r)` (`kb` the kernel builder, `c` the load
of the field's current value and `r` the rate, both `Ex` handles; `rule` returns an `Ex`).
With an irregular domain the rate's `select(inside, r, 0)` becomes
`select(inside, rule(kb, c, r), c)`: a site outside keeps its value. The scratch fields are
dropped and the stepped fields get two buffers. The other kernels (`map:`, `aux:`, `mask:`),
the masks and the rules pass through, renumbered. `rule === nothing` returns `rate`.

The result is node for node the program a front end fuses symbolically
(`symbolic_discretize(…; update = rule)`): the builder interns and orders every node
structurally, and kernels are renumbered canonically (`finish`), so `fingerprint_text` of the
two is the same (the F2-07 gate).
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
        # a kernel with no scratch field stores into its field already (a program written fused)
        (s === nothing || j === nothing) && continue
        step[Int32(s)] = Int32(j)
    end
    isempty(step) && return p
    keep = [i for i in eachindex(p.fields) if !haskey(step, Int32(i))]
    newid = zeros(Int32, length(p.fields))
    newid[keep] .= Int32.(1:length(keep))
    stepped = Set(values(step))
    fm(i) = i == 0 ? Int32(0) : haskey(step, Int32(i)) ? newid[step[Int32(i)]] : newid[i]
    fields = [i in stepped ? FieldDecl{N}(f.key, f.classes, f.shape, f.symmetric, f.storage, f.levels, f.epoch,
                                             Int8(2), f.role) : f
              for (i, f) in enumerate(p.fields) if i in keep]
    bk = ([f.key for f in fields], [f.storage for f in fields], [t.key for t in p.tables])
    dom = p.hierarchy[1].grid.domain != 0
    kernels = map(p.kernels) do k
        startswith(k.key, "rate:") || return rebuild(copy_node!, k, bk; fieldmap = fm)
        rebuild(copy_node!, k, bk; fieldmap = fm, storefn = (b, s, v) -> _fused_store(b, s, v, rule, dom))
    end
    masks = [MaskDecl(m.key, fm(m.field), m.epoch) for m in p.masks]
    flags = [FlagDecl(g.key, fm(g.field), g.bits, g.epoch) for g in p.flags]
    rules = BRule[_rulemap(r, fm, identity) for r in p.rules]
    return Program{N}(p.hierarchy, fields, p.tables, masks, flags, rules, kernels, p.periodic, p.spacing, p.nparams)
end

# the store of a fused rate kernel: `rule(c, r)` into `c`, inside the domain when there is one
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
