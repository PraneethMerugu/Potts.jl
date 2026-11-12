# Definitions of ir/fingerprint_tests.jl that other test files use (moved here by TS1b).
using LatticeFields.Compile: fingerprint_text, IR_FORMAT

"""
A two-kernel program; `flip` reverses every declaration and operand order.
"""
function fp_prog(;
        flip = false, coef = 0.25, off = 1, lane = F32, dirichlet = 0.0, wbuf = 1)
    pb = ProgramBuilder(Grid((8, 6)); periodic = (true, false), nparams = 2)
    decl = [("u", (; buffers = 2, storage = lane)), ("w", (; role = :aux, buffers = wbuf))]
    flip && reverse!(decl)
    ids = Dict(k => field!(pb, k; kw...) for (k, kw) in decl)
    u, w = ids["u"], ids["w"]
    rules = [FaceRule(u, 2, -1, Coef(1), Coef(0), Coef(dirichlet)),
        FaceRule(u, 2, 1, Coef(0), Coef(1), Coef(0))]
    foreach(r -> rule!(pb, r), flip ? reverse(rules) : rules)
    function k1()
        kb = kernel(pb)
        ts = [load(kb, u; offset = o) for o in ((off, 0), (-off, 0), (0, 1), (0, -1))]
        flip && reverse!(ts)
        c = load(kb, u)
        store(kb,
            u,
            flip ? (param(kb, 1) * coef) * (sum(ts) - 4c) + c :
            c + coef * param(kb, 1) * (sum(ts) - 4c))
        add!(pb, kb, "diffuse")
    end
    function k2()
        kb = kernel(pb)
        store(kb, w, flip ? param(kb, 2) * load(kb, u) : load(kb, u) * param(kb, 2))
        add!(pb, kb, "observe")
    end
    flip ? (k2(); k1()) : (k1(); k2())
    return program(pb)
end
