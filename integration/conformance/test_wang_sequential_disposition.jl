using SHA
using TOML

include("wang_model_fixture.jl")

@testset "Wang model Wang sequential CPU disposition" begin
    # Raw closure captures are immutable binary evidence, not prose to
    # normalize. Check the exact files that contain terminal-preserved
    # whitespace before CI exempts the content-addressed archive directory
    # from its source-text whitespace policy.
    repository = normpath(joinpath(@__DIR__, "..", ".."))
    g3b_manifest = TOML.parsefile(joinpath(
        repository, "design", "evidence", "phase-14",
        "g3b-closure", "manifest-v1.toml"))
    raw_capture_ids = Set([
        "command-corepotts-full",
        "command-pottstoolkit-full",
        "environment",
    ])
    checked_capture_ids = Set{String}()
    for artifact in g3b_manifest["artifact"]
        artifact["id"] in raw_capture_ids || continue
        artifact_path = joinpath(repository, artifact["path"])
        @test isfile(artifact_path)
        @test filesize(artifact_path) == artifact["bytes"]
        @test bytes2hex(SHA.sha256(read(artifact_path))) ==
              artifact["sha256"]
        push!(checked_capture_ids, artifact["id"])
    end
    @test checked_capture_ids == raw_capture_ids

    fixture = _wang_runtime_fixture(32)
    coupled = fixture.coupled
    cpu_report = CorePotts.coupled_backend_report(
        coupled.plan, coupled.state,
        coupled.potts.plan.capabilities;
        potts = coupled.potts)
    @test cpu_report.executable
    @test all(row ->
        row.status === :qualified_reference,
        cpu_report.rows)

    # A family label cannot qualify CPU storage as a GPU runtime. This
    # proves the paper-faithful sequential CPU model has no assembled GPU
    # promotion even when every advertised capability bit is otherwise
    # present.
    alleged_metal = CorePotts.BackendCapabilities(
        CorePotts.MetalFamily,
        CorePotts.QualifiedBackend,
        true, true, false, true, (v"1.0.0",))
    alleged_report = CorePotts.coupled_backend_report(
        coupled.plan, coupled.state, alleged_metal;
        potts = coupled.potts)
    @test !alleged_report.executable
    @test all(row -> row.status === :unsupported,
        alleged_report.rows)
    @test_throws CorePotts.UnsupportedCoupledCapabilities CorePotts.preflight_coupled(
            coupled.plan, coupled.state,
            alleged_metal; potts = coupled.potts)

    @test CorePotts.SciMLBase.step!(coupled) ===
        coupled
    @test coupled.mcs == 1
    @test fixture.field.time == 1.0f0
    @test CorePotts.capture_checkpoint(coupled).mcs == 1
    coupled.checkpoint_stable = false
    @test_throws ArgumentError CorePotts.capture_checkpoint(coupled)
end
