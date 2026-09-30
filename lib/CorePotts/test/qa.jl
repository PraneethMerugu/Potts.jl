# Static gates: type stability (JET) and allocation freedom (AllocCheck) of the hot paths.
using JET, AllocCheck

@testset "QA" begin
    σ0, kinds0 = blocks((36, 36), 5)
    prob = CPMProblem(GG, initial_state(σ0, kinds0), Lattice((36, 36)), (0, 20), gg_params())
    integ = init(prob, SequentialCPM(); save_start = false)
    args = (integ.state, integ.kf, integ.p, integ.ctx, integ.law, integ.key, 0)
    @test_opt target_modules = (CorePotts,) CorePotts.sequential_mcs!(args...)
    @test_opt target_modules = (CorePotts,) step!(integ)
    @test isempty(check_allocs(CorePotts.sequential_mcs!, typeof.(args)))

    cinteg = init(prob, CheckerboardCPM(); save_start = false)
    cargs = (cinteg.state, cinteg.cache, cinteg.kf, cinteg.p, cinteg.ctx, cinteg.law,
        cinteg.key, 0)
    @test_opt target_modules = (CorePotts,) CorePotts.checkerboard_mcs!(cargs...)
    @test_opt target_modules = (CorePotts,) step!(cinteg)
    # `init` is not gated: resolving a relation fixes its length K at run time, which is a
    # deliberate one-time function barrier before the (gated) hot loop.

    # with phases
    u0 = zeros(36, 36)
    ph = Phases(after_mcs = (SitePhase(jacobi!), CopyPhase((:site, :u) => (:site, :u_next))))
    pprob = CPMProblem(CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph),
        initial_state(σ0, kinds0; site = (; u = u0, u_next = copy(u0))), Lattice((36, 36)),
        (0, 5), merge(gg_params(), (; D = 0.1)))
    pinteg = init(pprob, CheckerboardCPM(); save_start = false)
    @test_opt target_modules = (CorePotts,) step!(pinteg)

    # the energy primitives are allocation free on their own
    prop = Proposal(1, 2, (1, 1), 1, Int32(1), Int32(0))
    @test isempty(check_allocs(gg_delta_H, typeof.((integ.state, integ.p, prop, integ.ctx))))
end

# P6.0j: ExplicitImports guardrails (CLAUDE.md code rules). Every name CorePotts uses is
# imported explicitly and by its owner. The allowlist names each non-public access the
# package genuinely needs; add to it only by review, with the reason.
using ExplicitImports: ExplicitImports, check_no_implicit_imports, check_all_explicit_imports_are_public,
    check_no_stale_explicit_imports, check_all_qualified_accesses_via_owners, check_all_qualified_accesses_are_public

const COREPOTTS_NONPUBLIC_QUALIFIED = (
    Symbol("@adapt_structure"), # Adapt's documented struct-adaptor macro; Adapt declares no public API
    Symbol("@atomic"),          # Atomix's documented atomics (GPU-portable); not declared public
    Symbol("@atomicreplace"),
    :zeros,                     # KernelAbstractions.zeros(backend, T, dims): KA's documented
                                # device allocator; KA declares no public API
    :RefValue,                  # Base.RefValue: concrete `Ref` type for type-stable fields
    :typename,                  # Base.typename(A).wrapper: the unparameterised device array type for Adapt
)

@testset "QA: ExplicitImports (CorePotts)" begin
    @test check_no_implicit_imports(CorePotts) === nothing
    @test check_all_explicit_imports_are_public(CorePotts) === nothing
    @test check_no_stale_explicit_imports(CorePotts) === nothing
    @test check_all_qualified_accesses_via_owners(CorePotts) === nothing
    @test check_all_qualified_accesses_are_public(CorePotts; ignore = COREPOTTS_NONPUBLIC_QUALIFIED) === nothing
end
