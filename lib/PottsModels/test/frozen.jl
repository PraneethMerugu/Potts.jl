# Frozen acceptance tests (D-053): every file listed in frozen.toml has the recorded
# hash, and each entry names the DECISIONS entry that last set it.
using SHA: sha256
using TOML: TOML

@testset "frozen acceptance tests are unchanged" begin
    decisions = read(joinpath(@__DIR__, "..", "..", "..", "docs", "design", "DECISIONS.md"), String)
    for f in TOML.parsefile(joinpath(@__DIR__, "frozen.toml"))["file"]
        path = joinpath(@__DIR__, f["path"])
        @test isfile(path)
        @test bytes2hex(open(sha256, path)) == f["sha256"]
        @test occursin("## $(f["decision"]) ", decisions)
    end
end
