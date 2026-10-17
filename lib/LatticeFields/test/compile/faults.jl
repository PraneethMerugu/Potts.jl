# Fault injection (D-048): each deliberately wrong pass is caught by the mechanism meant to
# catch it, and the clean pipeline passes the same check.
#
# | injected fault                          | caught by                          |
# | wrong derived parameter (hoist)          | debug differential                 |
# | lost forwarding in a fused kernel        | debug differential (no fusion)     |
# | off-by-one target index                  | debug differential (LinearIndices) |
# | wrong Dirichlet ghost (semantic, shared) | hand-loop oracle, not the differential |
# | dangling / non-topological node          | verifier                           |
# | loads not before stores                  | hand-loop oracle                   |
# (missing pass-through: lanes_masks.jl)

using LatticeFields.Compile: hoist_params, linear_index, zero_offset, boundary, legality,
                             fold
using LatticeFields.IR: IRError, Program, with_kernels, Kernel

"""
Optimized (with `stages`/`merge` faults) vs debug emission on random inputs.
"""
function differential(pb, P; stages = LOWERING, kw...)
    s, sp = build(pb; stages, kw...)
    sd, spd = build(pb; options = debug_options())
    rng = Xoshiro(11)
    init = (k, A) -> (A .= rand(rng, eltype(A), length(A)))
    st, std = HostStore(s; init), HostStore(sd)
    for f in keys(st.bufs), j in eachindex(st.bufs[f])

        copyto!(std.bufs[f][j], st.bufs[f][j])
    end
    run_step!(s, sp, st, P)
    run_step!(sd, spd, std, P)
    return all(f -> isapprox(array(st, f, :cur), array(std, f, :cur); rtol = 1e-5), keys(st.bufs))
end

"""
Two kernels on one space: `w ← 2u + p1` then `v ← w·u + w` (offset-0 read of `w`).
"""
function chain2()
    pb = ProgramBuilder(Grid((7, 6)); periodic = (true, true), nparams = 1)
    u = field!(pb, "u")
    w = field!(pb, "w"; role = :aux)
    v = field!(pb, "v"; role = :output)
    ka = kernel(pb)
    store(ka, w, 2 * load(ka, u; offset = (1, 0)) + param(ka, 1))
    add!(pb, ka, "a_make_w")
    kb = kernel(pb)
    store(kb, v, load(kb, w) * load(kb, u) + load(kb, w))
    add!(pb, kb, "b_use_w")
    return pb
end

@testset "fault: wrong derived parameter" begin
    P = (0.1, 0.7, 1.3, 0.25, 2.0)
    @test differential(diffusion3(), P)
    bad = (p, k) -> ((k2, d) = hoist_params(p, k); (k2, Any[:(2 * $(x)) for x in d]))
    @test !differential(diffusion3(), P; stages = merge(LOWERING, (; hoist = bad)))
end

@testset "fault: lost forwarding in a fused kernel" begin
    s, sp = build(chain2())
    @test length(sp.launches) == 1                     # fused, so forwarding matters
    @test differential(chain2(), (0.5,))
    noforward = (p, ids, scc) -> Schedule.merge_kernels(p, ids, Dict(k => 1
    for k in keys(scc)))
    @test !differential(chain2(), (0.5,); merge = noforward)
end

@testset "fault: off-by-one target index" begin
    P = (0.1, 0.7, 1.3, 0.25, 2.0)
    shifted = (c, a) -> (
        e = linear_index(c, a); zero_offset(a) ? e : :(min($e + one($e), G.n)))
    @test !differential(diffusion3(), P; stages = merge(LOWERING, (; target = shifted)))
end

@testset "fault: wrong Dirichlet ghost is invisible to the differential, caught by the oracle" begin
    function bad_boundary(p::Program)
        rules = IR.BRule[r isa FaceRule && r.beta.value == 0 ?
                         FaceRule(r.field, r.axis, r.side, Coef(2.0),
                             r.beta, r.g) : r for r in p.rules]
        q = Program(p.hierarchy, p.fields, p.tables, p.masks, p.flags, rules, p.kernels,
            p.periodic, p.spacing, p.nparams)
        return boundary(q)                             # ghost g − c instead of 2g − c
    end
    passes = (legality, fold, bad_boundary, fold)
    P = (0.05, 0.9, 1.1, 0.25, 2.0)
    u0 = rand(Xoshiro(12), Float32, 6, 5, 4)
    ref = hand3!(similar(u0), u0, P)
    s, sp = build(diffusion3(); passes)
    sd, spd = build(diffusion3(); passes, options = debug_options())
    bad = run_field(s, sp, u0, P)
    @test bad ≈ run_field(sd, spd, u0, P) rtol = 1e-5   # the differential agrees...
    @test bad != ref                                    # ...the oracle does not
    sc, spc = build(diffusion3())
    @test run_field(sc, spc, u0, P) == ref
end

@testset "fault: dangling and non-topological nodes" begin
    function scramble(p::Program{N}) where {N}
        ks = map(p.kernels) do k
            Kernel{N}(k.key, k.space, reverse(k.nodes),
                k.operands, k.consts, k.accesses, k.tables,
                k.calls, k.stores, k.reductions, k.gate)
        end
        return with_kernels(p, ks)
    end
    @test_throws IRError semantic(program(diffusion2()); passes = (legality, scramble))
    @test semantic(program(diffusion2())) isa Program
end

@testset "fault: loads not ordered before stores" begin
    pb = ProgramBuilder(Grid((5, 3)))
    a = field!(pb, "a"; role = :aux)
    b = field!(pb, "b"; role = :aux)
    kb = kernel(pb)
    store(kb, a, 5.0)
    store(kb, b, load(kb, a) * 2)
    add!(pb, kb, "overwrite")
    a0 = rand(Xoshiro(13), Float32, 15)
    function go(stages)
        s, sp = build(pb; stages)
        st = HostStore(s)
        copyto!(current(st, s, "a"), a0)
        run_step!(s, sp, st, ())
        return copy(current(st, s, "b"))
    end
    @test go(LOWERING) == 2 .* a0
    @test go(merge(LOWERING, (; order = c -> Int32[]))) == fill(10.0f0, 15)
end
