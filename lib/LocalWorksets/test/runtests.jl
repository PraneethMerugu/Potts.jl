using Aqua
using ExplicitImports
using Test
import LocalWorksets

@testset "LocalWorksets package quality" begin
    Aqua.test_all(LocalWorksets; ambiguities = false)
    # These qualified non-public accesses implement the reviewed central
    # admission, compiler-identity, storage-alias, and backend-validation
    # boundaries. Keep the allowlist exact so new private reliance still fails.
    qualified_internal_boundary = (
        Symbol("@atomic"),
        :Compiler,
        :PkgId,
        :Typeof,
        :apply_type,
        :datatype_alignment,
        :device,
        :functional,
        :get_world_counter,
        :invoke_in_world,
        :loaded_modules,
        :mightalias,
        :return_type,
    )
    ExplicitImports.test_explicit_imports(
        LocalWorksets;
        all_qualified_accesses_are_public =
            (; ignore = qualified_internal_boundary),
    )
    @test isempty(Test.detect_ambiguities(
        LocalWorksets, Base; recursive = true
    ))
end

include("support.jl")
include("test_api.jl")
include("test_mechanisms.jl")
include("test_generic.jl")
include("test_consolidation.jl")
include("test_runtime.jl")

# These tests deliberately install hostile external methods. Keep them last so
# their irreversible world changes cannot contaminate functional checks.
include("test_admission.jl")
