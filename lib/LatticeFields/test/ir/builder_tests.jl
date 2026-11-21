# Builder self-tests: hash-consing, flattening, structural operand order, canonical finish,
# typing, and the refusals of the verifier and the legality pass.

@testsetup module LF_ir_builder
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
include("../shared/ir_builder.jl")
include("../shared/export_all.jl")
end

@testitem "interning and canonical order" setup = [LF_ir_builder] tags = [
    :latticefields,
    :ir,
] begin
    @testset "interning and canonical order" begin
        pb = ProgramBuilder(Grid((4, 4)); periodic = (true, true), nparams = 2)
        u = field!(pb, "u")
        v = field!(pb, "v")
        kb = kernel(pb)
        a, b = load(kb, u; offset = (1, 0)), load(kb, u; offset = (-1, 0))
        @test (a + b).id == (b + a).id                        # commutative operands sorted
        @test load(kb, u; offset = (1, 0)).id == a.id          # loads deduplicated
        # n-ary flattening
        @test ((a + b) + param(kb, 1)).id == (a + (b + param(kb, 1))).id
        s3 = a + b + param(kb, 1)
        @test kb.nodes[s3.id].op == ADD && length(nodeargs(kb, s3.id)) == 3
        # (-1,0) before (+1,0): structural
        @test scmp(kb, b.id, a.id) < 0
        # identities wait for the fold pass
        @test (2 * a).id != (2.0f0 * a + 0).id
        # constants interned by bit pattern
        @test IR.constant!(kb, 0.0) != IR.constant!(kb, -0.0)
        @test kb.nodes[(a < b).id].type == IR.BOOL
        # finish: the same expression built in two orders gives identical kernels
        function build_once(order)
            q = ProgramBuilder(Grid((4, 4)); periodic = (true, true), nparams = 2)
            fs = if order
                (field!(q, "u"), field!(q, "v"))
            else
                reverse((field!(q, "v"), field!(q, "u")))
            end
            k = kernel(q)
            terms = [load(k, fs[1]; offset = o) * param(k, 1) for o in OFFS2]
            order || reverse!(terms)
            store(k, fs[2], sum(terms) - param(k, 2) * load(k, fs[1]))
            add!(q, k, "k")
            return program(q)
        end
        p1, p2 = build_once(true), build_once(false)
        @test sprint(IR.print_program, p1) == sprint(IR.print_program, p2)
        @test p1.kernels[1].nodes == p2.kernels[1].nodes
    end
end

@testitem "typing: integer lanes and casts" setup = [LF_ir_builder] tags = [
    :latticefields,
    :ir,
] begin
    @testset "typing: integer lanes and casts" begin
        pb = ProgramBuilder(Grid((3, 3)))
        k8 = field!(pb, "k"; storage = U8, role = :input)
        x = field!(pb, "x")
        kb = kernel(pb)
        m = load(kb, k8)
        @test kb.nodes[m.id].type == U8
        # integer operand cast to REAL
        @test kb.nodes[(m + 1.5).id].type == REAL
        @test kb.nodes[(m + IR.constant(kb, 2, U8)).id].type == U8
        @test_throws IRError IR.bittest(load(kb, x), 1)
        @test_throws IRError IR.call!(kb, :evalfile, m.id)
        # `mod` and `rem` take two operands, every other call one
        @test kb.nodes[IR.call!(kb, :mod, m.id, load(kb, x).id)].type == REAL
        @test_throws IRError IR.call!(kb, :rem, m.id)
        @test_throws IRError IR.call!(kb, :sign, m.id, m.id)
        neg_exp = -1
        @test_throws IRError m^neg_exp
        @test_throws IRError IR.restrict(m; op = :bad)
        @test_throws IRError IR.reduce!(kb, :bad, m, 1)
        @test_throws IRError IR.field!(pb, "x")
        @test_throws IRError IR.field!(pb, "y"; role = :bad)
        @test_throws IRError IR.field!(pb, "y"; storage = IR.REAL)
        IR.add!(pb, kb, "k")
        @test_throws IRError IR.add!(pb, kb, "k")
    end
end

@testitem "legality and verifier refusals" setup = [LF_ir_builder] tags = [
    :latticefields,
    :ir,
] begin
    @testset "legality and verifier refusals" begin
        function msg(f)
            return try
                f()
                ""
            catch e
                e isa IRError ? e.msg : rethrow()
            end
        end
        # two writes of one field
        p = tiny([("a", (;))], (kb, a) -> (store(kb, a, 1.0); store(kb, a, param(kb, 1))))
        @test occursin("written twice", msg(() -> semantic(p)))
        # a written single-buffer field read at an offset
        p = tiny([("a", (;))], (kb, a) -> store(kb, a, load(kb, a; offset = (1, 0))))
        @test occursin("buffers = 2", msg(() -> semantic(p)))
        p = tiny(
            [("a", (; buffers = 2))], (kb, a) -> store(
                kb, a, load(
                    kb, a; offset = (
                        1, 0,
                    )
                )
            )
        )
        @test semantic(p) isa IR.Program                        # two buffers: legal
        # a store to an input field
        p = tiny(
            [("a", (; role = :input)), ("b", (;))],
            (kb, a, b) -> store(kb, a, load(kb, b))
        )
        @test occursin("input field", msg(() -> semantic(p)))
        # a REAL value into an integer lane needs an explicit cast
        p = tiny(
            [("n", (; storage = I32)), ("x", (;))], (kb, n, x) -> store(
                kb, n, load(kb, x) *
                    2
            )
        )
        @test occursin("lane I32", msg(() -> verify(p)))
        p = tiny(
            [("n", (; storage = I32)), ("x", (;))],
            (kb, n, x) -> store(kb, n, IR.cast(load(kb, x), I32))
        )
        @test verify(p) isa IR.Program
        # a non-periodic axis without a boundary rule names the field and the face
        p = tiny(
            [("u", (; buffers = 2))], (kb, u) -> store(kb, u, load(kb, u; offset = (0, 1)));
            periodic = (true, false)
        )
        @test occursin("`u` has no boundary rule on axis 2 side +", msg(() -> semantic(p)))
        # Float64 on a backend without Float64 names the field
        p = semantic(
            tiny(
                [("d", (; storage = F64)), ("x", (;))],
                (kb, d, x) -> store(kb, x, load(kb, d))
            )
        )
        @test occursin(
            "field `d` has lane F64",
            msg(
                () -> check_types(
                    p, p.kernels[1],
                    CompileOptions(; float64_ok = false)
                )
            )
        )
        @test check_types(p, p.kernels[1], CompileOptions()) === nothing
    end
end
