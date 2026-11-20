# Printer and fingerprint (O-2: semantic IR after pass 2 plus layout). Stable under reordering
# of equivalent inputs, across sessions, and under every non-semantic choice; changed by any
# semantic or layout change.

@testsetup module LF_ir_fingerprint
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
include("../shared/ir_builder.jl")
include("../shared/ir_fingerprint.jl")
include("../shared/export_all.jl")
end

@testitem "fingerprint" setup = [LF_ir_fingerprint] tags = [:latticefields, :ir] begin
    @isdefined(FP_ONLY) || @testset "fingerprint" begin
        base = fingerprint(fp_prog())
        @test fingerprint(fp_prog(; flip = true)) == base       # reordered equivalent inputs
        @test fingerprint(fp_prog()) == base                    # deterministic
        for (what, kw) in (
                (:coefficient, (; coef = 0.5)), (:offset, (; off = 2)), (
                    :lane, (; lane = F16),
                ),
                (:boundary_value, (; dirichlet = 1.0)), (:buffers, (; wbuf = 2)),
            )
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
        include(raw"$(joinpath(@__DIR__, "..", "shared", "ir_fingerprint.jl"))")
        print(fingerprint(fp_prog()))
        """
        out = read(
            `$(Base.julia_cmd()) --project=$(dirname(@__DIR__)) -e "using Test; const FP_ONLY = true; $code"`,
            String
        )
        @test parse(UInt64, strip(out)) == base
    end
end
