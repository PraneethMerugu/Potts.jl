# The printer (v3 §4.5): one stable text form, used for `inspect`, error messages and as the
# fingerprint source. It prints op and enum *names*, never codes, and keys, never ids, so a new
# op or a new declaration elsewhere never changes an existing program's text.

_lc(x) = lowercase(string(x))
_fmt(x::Float64) = repr(x)
_fmt(c::Coef) = c.param == 0 ? _fmt(c.value) : string(_fmt(c.value), "*p", c.param)
_off(t::Tuple) = string("(", join((v > 0 ? "+$v" : "$v" for v in t), ","), ")")

function print_rule(io::IO, p::Program, r::FaceRule)
    print(io, "rule face ", p.fields[r.field].key, " axis=",
        r.axis, " side=", r.side > 0 ? "+" : "-",
        " alpha=", _fmt(r.alpha), " beta=", _fmt(r.beta), " g=", _fmt(r.g))
    r.gfield == 0 || print(io, " gfield=", p.fields[r.gfield].key)      # (printed only when set)
end
function print_rule(io::IO, p::Program, r::DomainEdgeRule)
    print(io, "rule domain_edge ",
        p.fields[r.field].key, " kind=", r.kind)
    r.mask == 0 || print(io, " mask=", p.masks[r.mask].key)              # (printed only when set)
end
function print_rule(io::IO, p::Program, r::ImmersedRule)
    print(io, "rule immersed ", p.fields[r.field].key,
        " mask=", p.masks[r.mask].key, " kind=", r.kind)
end
function print_rule(io::IO, p::Program, r::NodeValueRule)
    print(io, "rule node_value ", p.fields[r.field].key,
        " mask=", p.masks[r.mask].key, " value=", _fmt(r.value), " face=", r.face)
    r.vfield == 0 || print(io, " vfield=", p.fields[r.vfield].key)      # (printed only when set)
end

"""
The storage layout and lattice: what a checkpoint's meaning depends on besides the kernels.
"""
function print_layout(io::IO, p::Program{N}) where {N}
    g = p.hierarchy[1].grid
    println(io, "lattice N=", N, " dims=", Int.(g.dims),
        " geometry=", _lc(g.geometry), " periodic=",
        p.periodic, " spacing=", p.spacing, " domain=", g.domain == 0 ? "box" :
                                                        p.masks[g.domain].key,
        " params=", p.nparams)
    for l in p.hierarchy
        println(
            io, "level shift=", l.shift, " widths=", l.widths === nothing ? "-" : l.widths)
    end
    for f in p.fields
        println(io, "field ", f.key, " lane=", f.storage,
            " shape=[", join(f.shape, ","), "]", " symmetric=",
            f.symmetric, " buffers=", f.buffers, " role=", f.role, " epoch=", _lc(f.epoch),
            " classes=", [Int.(c.half) for c in f.classes], " levels=[", join(f.levels, ","), "]",
            f.fixed ? " fixed" : "")
    end
    for t in p.tables
        println(io, "table ", t.key, " lane=", t.storage, " oob=", t.oob)
    end
    for m in p.masks
        println(
            io, "mask ", m.key, " field=", p.fields[m.field].key, " epoch=", _lc(m.epoch))
    end
    for g in p.flags
        println(io, "flag ", g.key, " field=", p.fields[g.field].key, " bits=",
            join(("$b:" * p.masks[s].key for (b, s) in g.bits), ","))
    end
    return nothing
end

function _access(io::IO, p::Program, a::Access)
    print(io, p.fields[a.field].key, "[", a.comp.a)
    a.comp.cond != 0 && print(io, "|", a.comp.b, "?v", a.comp.cond)
    print(io, "] @", _off(a.offset.a))
    a.offset.cond != 0 && print(io, "|", _off(a.offset.b), "?v", a.offset.cond)
    print(io, " L", a.level, " c", a.class, " ", _lc(a.policy))
end

function print_kernel(io::IO, p::Program, k::Kernel)
    sp = k.space
    print(io, "kernel ", k.key, " space=", _lc(sp.kind), " L", sp.level, " c", sp.class)
    sp.kind == MASKED && print(io, " mask=", p.masks[sp.mask].key)
    sp.kind == RESTRICTED && print(io, " inset=", sp.inset)
    println(io)
    for (i, n) in enumerate(k.nodes)
        print(io, "  v", i, " = ", opname(n.op))
        if n.op == CONST
            print(io, " ", _fmt(k.consts[n.imm]))
        elseif n.op in (LOAD, INSIDE_OP)
            print(io, " ")
            _access(io, p, k.accesses[n.imm])
        elseif n.op == TABLE
            print(io, " ", p.tables[n.imm].key)
        elseif n.op == CALL
            print(io, " ", k.calls[n.imm])
        elseif n.op in (PARAM, RUNTIME, COORD, POWI, BITTEST, IDX, RESTRICT)
            print(io, " #", n.imm)
        end
        foreach(a -> print(io, " v", a), args(k, n))
        println(io, " :: ", _lc(n.type))
    end
    for s in k.stores
        print(io, "  store ")
        _access(io, p, s.access)
        println(io, " <- v", s.value, " ", s.law)
    end
    for r in k.reductions
        println(io, "  reduce ", r.op, " v", r.value, " -> ", p.tables[r.target].key)
    end
    k.gate != 0 && println(io, "  gate v", k.gate)
    return nothing
end

"""
Print the whole program: layout, then rules, then kernels in key order.
"""
function print_program(io::IO, p::Program)
    print_layout(io, p)
    for r in p.rules
        print_rule(io, p, r)
        println(io)
    end
    foreach(k -> print_kernel(io, p, k), p.kernels)
    return nothing
end
Base.show(io::IO, ::MIME"text/plain", p::Program) = print_program(io, p)
