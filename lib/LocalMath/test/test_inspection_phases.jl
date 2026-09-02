using Test

# Reuse the four-law scientific witness; phase expectations come only from
# source-owned inspection, not from a benchmark-side schedule reconstruction.
include(joinpath(@__DIR__, "..", "benchmark", "compiler_scaling", "stage_scaling.jl"))

@testset "canonical inspection owns complete physical launch evidence" begin
    workload = _compiler_workload(4, 16)
    bound = _compiler_bound(workload, Array)
    plan = LocalMath.plan(bound; backend = KernelAbstractions.CPU())
    prepared = LocalMath.prepare(plan)
    planned = LocalMath.inspect(plan)
    realized = LocalMath.inspect(prepared)

    @test map(phases -> LocalMath._phase_count(phases),
        planned.planning.stage_phases) == (1, 6, 6, 6)
    @test planned.planning.stage_local_launch_count == 19
    @test planned.planning.program_reset_count == 1
    @test planned.planning.base_provider_launch_count == 20
    @test realized.planning.stage_phases == planned.planning.stage_phases
    @test realized.planning.stage_local_launch_count == 19
    @test realized.planning.base_provider_launch_count == 20
    @test realized.planning.physical_segments ==
        planned.planning.physical_segments
end

@testset "inspection levels are canonical projections" begin
    workload = _compiler_workload(4, 16)
    bound = _compiler_bound(workload, Array)
    plan = LocalMath.plan(bound; backend = KernelAbstractions.CPU())
    prepared = LocalMath.prepare(plan)

    full = LocalMath.inspect(prepared)
    relations = LocalMath.inspect(prepared; level = :relations)
    numerics = LocalMath.inspect(prepared; level = :numerics)
    memory = LocalMath.inspect(prepared; level = :memory)
    kernels = LocalMath.inspect(prepared; level = :kernels)

    @test relations.relations === full.relations
    @test relations.equivalence === full.equivalence
    @test numerics.equivalence === full.equivalence
    @test map(stage -> stage.publications, numerics.stages) ==
        map(stage -> stage.publications, full.stages)
    @test memory.workspace === full.planning.workspace
    @test memory.bindings === full.realized.bindings
    @test kernels.stage_phases === full.planning.stage_phases
    @test kernels.provider_launch_count == 20
    @test kernels.physical_segments === full.planning.physical_segments
    @test kernels.prepared_launch_types === full.realized.prepared_launch_types

    law = plan.bound.law
    @test LocalMath.inspect(law; level = :relations).relations ==
        LocalMath.inspect(law).relations
    @test LocalMath.inspect(law; level = :numerics).stages ==
        map(LocalMath._semantic_stage_projection,
            LocalMath.inspect(law).stages)
    @test_throws LocalMath.LocalMathValidationError LocalMath.inspect(
        law; level = :memory)
    @test_throws LocalMath.LocalMathValidationError LocalMath.inspect(
        law; level = :kernels)
    @test_throws LocalMath.LocalMathValidationError LocalMath.inspect(
        plan; level = :unknown)

    planned_compilation = LocalMath.compilation_report(plan)
    realized_compilation = LocalMath.compilation_report(prepared)
    @test planned_compilation.lifecycle === :PlanCompilationReport
    @test planned_compilation.stage_count == 4
    @test planned_compilation.provider_launch_count == 20
    @test 1 <= planned_compilation.specialization_family_count <= 4
    @test !isempty(planned_compilation.callable_admissions)
    @test all(fact -> fact.admission_contract isa Symbol,
        planned_compilation.callable_admissions)
    @test all(fact -> fact.analyzed_signature <: Tuple,
        planned_compilation.callable_admissions)
    @test realized_compilation.lifecycle === :PreparedCompilationReport
    @test realized_compilation.specialization_signatures ===
        planned_compilation.specialization_signatures
    @test realized_compilation.prepared_launch_types ===
        full.realized.prepared_launch_types

    receipt = LocalMath.execute!(prepared)
    @test_throws LocalMath.LocalMathValidationError LocalMath.inspect(
        receipt; level = :kernels)
    wait(receipt)
end
