# Printer and fingerprint (O-2: semantic IR after pass 2 plus layout). Stable under reordering
# of equivalent inputs, across sessions, and under every non-semantic choice; changed by any
# semantic or layout change.

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

@isdefined(FP_ONLY) || @testset "fingerprint" begin
    base = fingerprint(fp_prog())
    @test fingerprint(fp_prog(; flip = true)) == base       # reordered equivalent inputs
    @test fingerprint(fp_prog()) == base                    # deterministic
    for (what, kw) in ((:coefficient, (; coef = 0.5)), (:offset, (; off = 2)), (
        :lane, (; lane = F16)),
        (:boundary_value, (; dirichlet = 1.0)), (:buffers, (; wbuf = 2)))
        @test fingerprint(fp_prog(; kw...)) != base
    end
    @test fingerprint(fp_prog(); T = Float64) != base       # compute type is part of the layout
    # the semantic form: identities folded, so x·1 + 0 hashes like x
    one_(e) = tiny([("u", (;)), ("w", (;))], (kb, u, w) -> store(kb, w, e(load(kb, u))))
    @test fingerprint(one_(x -> x * 1 + 0)) == fingerprint(one_(x -> x))
    @test fingerprint(one_(x -> x * 2)) != fingerprint(one_(x -> x))
    p = fp_prog()
    # names, never enum codes: the text holds op names and the format line
    txt = fingerprint_text(p)
    @test startswith(txt, "LatticeFields IR format $IR_FORMAT\n")
    @test occursin(" = load u[1] @(", txt) && occursin(" = select ", txt) &&
          !occursin("Op(", txt)
    # session independence: a fresh process computes the same value
    code = """
    include(raw"$(joinpath(@__DIR__, "..", "host_runner.jl"))")
    include(raw"$(joinpath(@__DIR__, "..", "fixtures.jl"))")
    include(raw"$(@__FILE__)")
    print(fingerprint(fp_prog()))
    """
    out = read(
        `$(Base.julia_cmd()) --project=$(dirname(@__DIR__)) -e "using Test; const FP_ONLY = true; $code"`,
        String)
    @test parse(UInt64, strip(out)) == base
end
