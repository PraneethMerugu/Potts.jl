using TOML
using SHA

@testset "transition-kernel ROCm device-code inspection archive" begin
    directory = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "device-code", "rocm"))
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    @test index["status"] ==
        "phase13-algorithms-have-nonempty-native-gcn-and-captured-perfetto-traces"
    @test index["source_revision"] ==
        "7ed1473df38873f03247572fe94382e36f642a00"
    @test index["julia_version"] == "1.12.6"
    @test index["backend"] == "amdgpu"
    @test index["trace_status"] == "captured"

    profile_path = joinpath(directory, index["profile_record"])
    @test bytes2hex(sha256(read(profile_path))) ==
        index["profile_record_sha256"]
    profile = TOML.parsefile(profile_path)
    @test profile["provenance"]["git_commit"] == index["source_revision"]
    @test !profile["provenance"]["git_dirty"]
    @test profile["comparison_identity"]["julia_version"] == index["julia_version"]
    @test profile["backend_package"]["name"] == index["backend_package"]
    @test profile["backend_package"]["version"] == index["backend_package_version"]
    @test profile["measurement_contract"]["trace_status"] == index["trace_status"]

    @test Set(getindex.(index["algorithms"], "name")) ==
        Set(("SequentialCPM", "CheckerboardSweepCPM"))
    for algorithm in index["algorithms"]
        code = profile["profiles"][algorithm["name"]]["code"]
        @test code["native_compilation_job_count"] ==
            algorithm["native_compilation_jobs"]
        @test code["native_code_bytes"] == algorithm["native_code_bytes"]
        @test algorithm["native_compilation_jobs"] > 0
        @test algorithm["native_code_bytes"] > 0
        @test algorithm["profiled_mcs"] > 0
        @test algorithm["profiled_wall_seconds"] > 0
    end

    @test length(index["native_files"]) == 9
    for artifact in index["native_files"]
        path = joinpath(directory, artifact["path"])
        @test isfile(path)
        @test filesize(path) == artifact["bytes"]
        @test bytes2hex(sha256(read(path))) == artifact["sha256"]
    end
    @test count(artifact -> artifact["algorithm"] == "SequentialCPM",
        index["native_files"]) == 1
    @test count(artifact -> artifact["algorithm"] == "CheckerboardSweepCPM",
        index["native_files"]) == 8

    @test length(index["traces"]) == 2
    for artifact in index["traces"]
        path = joinpath(directory, artifact["path"])
        @test isfile(path)
        @test filesize(path) == artifact["bytes"] > 0
        @test bytes2hex(sha256(read(path))) == artifact["sha256"]
    end
end
