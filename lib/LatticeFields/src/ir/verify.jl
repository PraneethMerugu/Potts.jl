# Structural verifier. Run on every program a pass returns, so a pass that leaves a dangling
# operand, a non-topological order, an ill-typed node or a bad store is caught at that pass.

"""
    IRError(msg)

Exception thrown when field IR construction or verification fails.

# Fields
- `msg::String`: the message. `showerror` prints it after `IRError: `.
"""
struct IRError <: Exception
    msg::String
end
Base.showerror(io::IO, e::IRError) = print(io, "IRError: ", e.msg)
irerror(msg...) = throw(IRError(string(msg...)))

const _SAMETYPE = (ADD, MUL, NEG, DIV, FMA, MIN, MAX, ABS, SQRT, EXP, LOG, CALL, RESTRICT)

function _verify_node(p::Program, k::Kernel, i::Int, n::Node)
    as = args(k, n)
    where_ = () -> string("kernel `", k.key, "` v", i, " (", opname(n.op), ")")
    all(a -> 0 < a < i, as) ||
        irerror(where_(), ": operand out of order or dangling ", collect(as))
    ts = [k.nodes[a].type for a in as]
    if n.op == CONST
        1 <= n.imm <= length(k.consts) || irerror(where_(), ": constant id ", n.imm)
    elseif n.op in (LOAD, INSIDE_OP)
        1 <= n.imm <= length(k.accesses) || irerror(where_(), ": access id ", n.imm)
        a = k.accesses[n.imm]
        1 <= a.field <= length(p.fields) || irerror(where_(), ": field id ", a.field)
        for c in (a.comp.cond, a.offset.cond)
            0 <= c < i || irerror(where_(), ": select condition v", c, " after its use")
            c == 0 || k.nodes[c].type == BOOL ||
                irerror(where_(), ": select condition is not Bool")
        end
        f = p.fields[a.field]
        n.op == LOAD && n.type != loadtype(f.storage) && irerror(
            where_(), ": type ", n.type,
            " for a load of lane ", f.storage
        )
        1 <= a.comp.a <= ncomp(f) && 1 <= a.comp.b <= ncomp(f) ||
            irerror(where_(), ": component out of range for `", f.key, "`")
    elseif n.op == PARAM
        1 <= n.imm || irerror(where_(), ": parameter slot ", n.imm)
    elseif n.op == TABLE
        1 <= n.imm <= length(p.tables) || irerror(where_(), ": table id ", n.imm)
    elseif n.op == COORD
        1 <= n.imm <= length(p.periodic) || irerror(where_(), ": axis ", n.imm)
    elseif n.op in _SAMETYPE
        all(==(n.type), ts) ||
            irerror(where_(), ": operand types ", ts, " for result ", n.type)
    elseif n.op in (EQ, LT, LE)
        n.type == BOOL && length(ts) == 2 && ts[1] == ts[2] ||
            irerror(where_(), ": comparison types ", ts)
    elseif n.op in (SELECT, COND)
        ts[1] == BOOL && ts[2] == ts[3] == n.type ||
            irerror(where_(), ": select types ", ts)
    elseif n.op == BITTEST
        isunsigned_lane(ts[1]) || irerror(where_(), ": BITTEST on ", ts[1])
    elseif n.op in (AND, OR, XOR, NOT)
        all(==(n.type), ts) && n.type != REAL || irerror(where_(), ": logic types ", ts)
    end
    return nothing
end

"""
Verify every kernel of `p`; throws `IRError` naming the kernel and node.
"""
function verify(p::Program)
    for k in p.kernels
        for (i, n) in enumerate(k.nodes)
            _verify_node(p, k, i, n)
        end
        for s in k.stores
            f = p.fields[s.access.field]
            0 < s.value <= length(k.nodes) ||
                irerror("kernel `", k.key, "`: store of `", f.key, "` dangles")
            t = k.nodes[s.value].type
            ok = isfloat(f.storage) ? t == REAL : t == f.storage
            ok || irerror(
                "kernel `", k.key, "`: store of a ", t, " value into lane ", f.storage,
                " of `", f.key, "` (add an explicit cast)"
            )
        end
        for r in k.reductions
            0 < r.value <= length(k.nodes) && k.nodes[r.value].type == REAL &&
                1 <= r.target <= length(p.tables) || irerror(
                "kernel `", k.key, "`: bad reduction (value v", r.value,
                ", target #", r.target, ")"
            )
        end
        k.gate == 0 || 0 < k.gate <= length(k.nodes) && k.nodes[k.gate].type == BOOL ||
            irerror("kernel `", k.key, "`: the gate v", k.gate, " is not a Bool node")
    end
    return p
end
