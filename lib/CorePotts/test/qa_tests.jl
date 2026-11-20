# Static gates: type stability (JET) and allocation freedom (AllocCheck) of the hot paths.

@testsetup module CP_qa
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates,
    linear_index, shift
# imports an earlier file made in the old single Main
using CorePotts: Proposal
include("shared/gg_model.jl")
include("shared/phases.jl")
using JET, AllocCheck, Aqua

# ExplicitImports guardrails (CLAUDE.md code rules). Every name CorePotts uses is
# imported explicitly and by its owner. The allowlist names each non-public access the
# package genuinely needs; add to it only by review, with the reason.
using ExplicitImports: ExplicitImports, check_no_implicit_imports,
    check_all_explicit_imports_are_public,
    check_no_stale_explicit_imports,
    check_all_qualified_accesses_via_owners,
    check_all_qualified_accesses_are_public

const COREPOTTS_NONPUBLIC_QUALIFIED = (
    # Adapt's documented struct-adaptor macro; Adapt declares no public API
    Symbol("@adapt_structure"),
    # Atomix's documented atomics (GPU-portable); not declared public
    Symbol("@atomic"),
    Symbol("@atomicreplace"),
    # KernelAbstractions.zeros(backend, T, dims): KA's documented device allocator; KA
    # declares no public API
    :zeros,
    # Base.RefValue: concrete `Ref` type for type-stable fields
    :RefValue,
    # Base.typename(A).wrapper: the unparameterised device array type for Adapt
    :typename,
    # Base.afoldl: unrolled fold over the MCS-order tuple; public `foldl` and `sum` allocate
    # there on SequentialCPM
    :afoldl,
    # Base.@nospecializeinfer (documented, not declared public): the host setup of `init`,
    # `remake` and `PottsProblem` inferred once for every model
    Symbol("@nospecializeinfer"),
)
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "qa_common.jl"))
include("shared/export_all.jl")
end

@testitem "QA" setup = [CP_qa] tags = [:corepotts, :qa] begin
    @testset "QA" begin
        σ0, kinds0 = blocks((36, 36), 5)
        prob = PottsProblem(
            GG, initial_state(σ0, kinds0), Lattice((36, 36)), (0, 20), gg_params()
        )
        integ = init(prob, SequentialCPM(); save_start = false)
        args = (integ.state, integ.kf, integ.p, integ.ctx, integ.law, integ.key, 0)
        @test_opt target_modules = (CorePotts,) CorePotts.sequential_mcs!(args...)
        @test_opt target_modules = (CorePotts,) step!(integ)
        @test isempty(check_allocs(CorePotts.sequential_mcs!, typeof.(args)))

        # SequentialCPM(; skip_interior = true) (D-177, D-198): the sweep, with the boundary
        # set's upkeep
        binteg = init(prob, SequentialCPM(; skip_interior = true); save_start = false)
        bargs = (
            binteg.state, binteg.kf, binteg.p, binteg.ctx,
            binteg.law, binteg.key, 0, binteg.cache,
        )
        @test_opt target_modules = (CorePotts,) CorePotts.boundary_site_mcs!(bargs...)
        @test_opt target_modules = (CorePotts,) step!(binteg)
        @test isempty(check_allocs(CorePotts.boundary_site_mcs!, typeof.(bargs)))

        cinteg = init(prob, CheckerboardCPM(); save_start = false)
        cargs = (
            cinteg.state, cinteg.cache, cinteg.kf, cinteg.p, cinteg.ctx, cinteg.law,
            cinteg.key, 0,
        )
        @test_opt target_modules = (CorePotts,) CorePotts.checkerboard_mcs!(cargs...)
        @test_opt target_modules = (CorePotts,) step!(cinteg)
        # `checkerboard_mcs!` branches on the runtime `Bool` `cache.inline`, so `AllocCheck`
        # analyzes the `cache.kernel(...)` KernelAbstractions CPU launch (`Threads.@threads`
        # / `sync_end`). Verify the CorePotts per-phase and kernel helpers directly for zero
        # allocations, and verify every frame reported on `checkerboard_mcs!` is inside the
        # KA/Threads launch scheduler rather than `CorePotts` or unexpected `Base` calls.
        @test isempty(
            check_allocs(
                CorePotts._phase_conflict!,
                typeof.(
                    (
                        cinteg.state, cinteg.cache, cinteg.ctx.lattice,
                        cinteg.cache.layout, (0, 0),
                    )
                )
            )
        )
        for serial_flag in (Val(true), Val(false))
            bs_args = (
                (0, 0), cinteg.state, cinteg.kf, cinteg.p, cinteg.ctx, cinteg.law,
                cinteg.key,
                0, cinteg.cache.layout, (0, 0), cinteg.cache.switches, 1,
                cinteg.cache.track,
                cinteg.cache.cnt, cinteg.cache.status, cinteg.cache.serial, serial_flag,
            )
            @test isempty(check_allocs(CorePotts.block_stay!, typeof.(bs_args)))
        end
        # `AllocCheck` collapses shared runtime callees (`sync_end`, `wait`, `enq_work`,
        # locks, channels) at `multiple call sites @ unknown`, so every reported allocation
        # must either pass through `KernelAbstractions` or stay inside Base's task-scheduler
        # files with no `CorePotts` frames.
        cb_allocs = check_allocs(CorePotts.checkerboard_mcs!, typeof.(cargs))
        ka_sched_files = (
            "cpu.jl", "threadingconstructs.jl", "task.jl", "channels.jl",
            "condition.jl", "lock.jl", "locks-mt.jl", "linked_list.jl", "partr.jl",
            "gcutils.jl", "Base_compiler.jl", "libuv.jl", "boot.jl", "array.jl",
            "baseext.jl",
        )
        @test isempty(
            filter(cb_allocs) do a
                top_file = basename(string(a.backtrace[1].file))
                any(sf -> occursin("CorePotts", string(sf.file)), a.backtrace) &&
                    !(top_file in ka_sched_files)
            end
        )
        @test all(cb_allocs) do a
            top_ok = basename(string(a.backtrace[1].file)) in ka_sched_files
            has_ka = any(sf -> occursin("KernelAbstractions", string(sf.file)), a.backtrace)
            has_cp = any(sf -> occursin("CorePotts", string(sf.file)), a.backtrace)
            tail = a.backtrace[end]
            collapsed_sched = !has_cp && tail.file === :unknown &&
                string(tail.func) == "multiple call sites" && all(
                sf -> basename(string(sf.file)) in ka_sched_files,
                a.backtrace[1:(end - 1)]
            )
            top_ok && (has_ka || collapsed_sched)
        end
        # `init` is not gated: resolving a relation fixes its length K at run time, which is
        # a deliberate one-time function barrier before the (gated) hot loop.

        # with phases
        u0 = zeros(36, 36)
        ph = Phases(
            after_mcs = (
                SitePhase(jacobi!), CopyPhase((:site, :u) => (:site, :u_next)),
            )
        )
        pprob = PottsProblem(
            CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph),
            initial_state(σ0, kinds0; site = (; u = u0, u_next = copy(u0))), Lattice(
                (
                    36, 36,
                )
            ),
            (0, 5), merge(gg_params(), (; D = 0.1))
        )
        pinteg = init(pprob, CheckerboardCPM(); save_start = false)
        @test_opt target_modules = (CorePotts,) step!(pinteg)

        # the energy primitives are allocation free on their own
        prop = Proposal(1, 2, (1, 1), 1, Int32(1), Int32(0))
        @test isempty(
            check_allocs(
                gg_delta_H, typeof.(
                    (
                        integ.state, integ.p, prop, integ.ctx,
                    )
                )
            )
        )
    end
end

@testitem "QA: Aqua (CorePotts)" setup = [CP_qa] tags = [:corepotts, :qa] begin
    @testset "QA: Aqua (CorePotts)" begin
        qa_aqua(CorePotts)
        # inside the GPU extensions, when loaded
        qa_extension_piracies(CorePotts)
    end
end

# No `@generated` in CorePotts' source (repo rule); the run context's tangent switch
# `tangent_on` is a plain method whose `Val` is still inferred, so a primal run compiles no
# tangent path
@testitem "QA: no @generated; tangent_on is inferred" setup = [CP_qa] tags = [
    :corepotts,
    :qa,
] begin
    @testset "QA: no @generated; tangent_on is inferred" begin
        # (the `@generated` scan only)
        qa_source_rules(pkgdir(CorePotts); banned_pattern = r"(?!)")
        primal = (; a = 1, b = 2.0f0)
        @test @inferred(CorePotts.tangent_on(primal)) === Val(false)
        @test @inferred(CorePotts.tangent_on(merge(primal, (; __tangent = nothing)))) ===
            Val(true)
        # past tuple unrolling
        wide = NamedTuple{ntuple(i -> Symbol(:k, i), 40)}(ntuple(identity, 40))
        @test @inferred(CorePotts.tangent_on(wide)) === Val(false)
    end
end

@testitem "QA: error and message rules" setup = [CP_qa] tags = [:corepotts, :qa] begin
    @testset "QA: error and message rules" begin
        qa_error_rules(pkgdir(CorePotts); reviewed_invariants = ["src/fields.jl"])
    end
end

@testitem "QA: ExplicitImports (CorePotts)" setup = [CP_qa] tags = [:corepotts, :qa] begin
    @testset "QA: ExplicitImports (CorePotts)" begin
        qa_explicit_imports(CorePotts; nonpublic_qualified = COREPOTTS_NONPUBLIC_QUALIFIED)
    end
end

@testitem "QA: Docs and extensions (CorePotts)" setup = [CP_qa] tags = [
    :corepotts,
    :qa,
] begin
    @testset "QA: Docs and extensions (CorePotts)" begin
        qa_api_docs(CorePotts; docs_dir = joinpath(@__DIR__, "..", "..", "..", "docs"))
        for (ext_sym, trigger) in (
                (:CorePottsAMDGPUExt, "AMDGPU"), (
                    :CorePottsMetalExt, "Metal",
                ),
            )
            if any(k -> k.name == trigger, keys(Base.loaded_modules))
                @test Base.get_extension(CorePotts, ext_sym) !== nothing
            end
        end
    end
end

# JET's error analysis of the whole package: undefined names and fields (D-298)
@testitem "QA: JET package analysis (CorePotts)" setup = [CP_qa] tags = [
    :corepotts,
    :qa,
] begin
    @testset "QA: JET package analysis (CorePotts)" begin
        qa_jet_package(
            CorePotts;
            locals = [
                # assigned when the state has clusters, read only then (or when a cluster
                # root was found, which needs clusters)
                r"`(members|cl)` may be undefined \(lifecycle\.jl\)" =>
                    "assigned under the condition of its use",
            ]
        )
    end
end

# the check-bounds lane: an out-of-bounds read under `@inbounds` is caught (D-298)
@testitem "QA: check-bounds lane control (CorePotts)" setup = [CP_qa] tags = [
    :corepotts,
    :qa,
] begin
    @testset "QA: check-bounds lane control (CorePotts)" begin
        qa_check_bounds_control()
    end
end
