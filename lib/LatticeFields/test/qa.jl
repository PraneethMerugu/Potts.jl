# Static gates: imports, type stability.
using ExplicitImports: check_no_implicit_imports, check_no_stale_explicit_imports,
    check_all_qualified_accesses_are_public, check_all_explicit_imports_are_public
using JET: @test_opt

@testset "QA" begin
    for m in (LatticeFields, LatticeFields.Exec)
        @test check_no_implicit_imports(m) === nothing
        @test check_no_stale_explicit_imports(m) === nothing
        @test check_all_qualified_accesses_are_public(m) === nothing
        @test check_all_explicit_imports_are_public(m) === nothing
    end
    a = zeros(Float32, 64)
    @test_opt target_modules = (LatticeFields.Exec,) Exec.host_launch!(AddK{1}(), 64, (a,))
    @test_opt target_modules = (LatticeFields.Exec,) Exec.launch!(KA.CPU(), AddK{1}(), 64, (a,))
    ls, _, _ = host_plan(40)
    plan = Exec.Plan(ls)
    @test_opt target_modules = (LatticeFields.Exec,) plan()
end
