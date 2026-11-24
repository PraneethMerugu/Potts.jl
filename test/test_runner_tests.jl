# The test runner itself (test/runner/PottsTestRunner.jl): its group tables and their
# errors, the qa rule, shards, the item-name pattern and its flags. Nothing here runs test
# items: every check stops before ReTestItems runs.

@testsetup module TestRunnerSetup
using Test
include(joinpath(@__DIR__, "runner", "PottsTestRunner.jl"))

const ROOT = dirname(@__DIR__)
const TESTDIRS = Dict(
    "Potts" => joinpath(ROOT, "test"),
    (
        p => joinpath(ROOT, "lib", p, "test") for p in
            ("CorePotts", "LatticeFields", "LatticePDE", "MakiePotts", "PottsModels")
    )...,
)

# a test directory with this test_groups.toml and nothing else
function table_dir(toml::AbstractString)
    dir = mktempdir()
    write(joinpath(dir, "test_groups.toml"), toml)
    return dir
end

# the ArgumentError that `f` throws, as text
function argument_error(f)
    try
        f()
    catch e
        e isa ArgumentError && return sprint(showerror, e)
        rethrow()
    end
    return error("no ArgumentError was thrown")
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "test runner: every package's group table loads" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    for (pkg, dir) in TESTDIRS
        t = PottsTestRunner.load_groups(dir)
        @test !isempty(t.settings["all"])
        @test all(in(keys(t.groups)), t.settings["all"])
    end
end

@testitem "test runner: a group table with an error throws" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    load(toml) = argument_error(() -> PottsTestRunner.load_groups(table_dir(toml)))
    @test occursin("unknown key \"tag\"", load("all = [\"a\"]\n[a]\ntag = [\"x\"]\n"))
    @test occursin("unknown setting \"worker\"", load("all = [\"a\"]\nworker = 2\n[a]\n"))
    @test occursin("missing the `all` list", load("[a]\ntags = [\"x\"]\n"))
    @test occursin("unknown group \"b\"", load("all = [\"b\"]\n[a]\n"))
    nodir = mktempdir()
    @test occursin(
        "no test_groups.toml", argument_error(() -> PottsTestRunner.load_groups(nodir))
    )
end

@testitem "test runner: an unknown GROUP lists the groups of its runner" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    # a package's runner takes plain group names only
    unknown(pkg) =
        argument_error(() -> PottsTestRunner.run_tests(TESTDIRS[pkg]; group = "nope"))
    lib = unknown("CorePotts")
    @test occursin("Unknown test GROUP = \"nope\"", lib)
    @test occursin("core", lib) && occursin("qa", lib)
    @test !occursin("<Package>_<group>", lib)
    # the root also takes <Package>_<group>
    root = unknown("Potts")
    @test occursin("<Package>_<group>", root) && occursin("CorePotts", root)
end

@testitem "test runner: qa = false drops the qa groups from All" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    for pkg in ("CorePotts", "LatticeFields", "LatticePDE", "MakiePotts", "PottsModels")
        t = PottsTestRunner.load_groups(TESTDIRS[pkg])
        @test "qa" in PottsTestRunner.all_groups(t, true)
        @test !("qa" in PottsTestRunner.all_groups(t, false))
        @test PottsTestRunner.is_qa_group(t.groups["qa"])
    end
    # the root's All runs the packages, which drop their own qa groups
    root = PottsTestRunner.load_groups(TESTDIRS["Potts"])
    @test PottsTestRunner.all_groups(root, false) == root.settings["all"]
end

@testitem "test runner: a named qa group runs its items whatever qa says" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    selected = PottsTestRunner.selected
    core = PottsTestRunner.load_groups(TESTDIRS["CorePotts"])
    models = PottsTestRunner.load_groups(TESTDIRS["PottsModels"])
    root = PottsTestRunner.load_groups(TESTDIRS["Potts"])
    for (t, item) in ((core, [:corepotts, :qa]), (models, [:pottsmodels, :qa]))
        @test selected([t.groups["qa"]], item; qa = false)
        @test selected([t.groups["qa"]], item; qa = true)
    end
    # a group that does not name qa skips its :qa items when qa is false
    @test !selected([root.groups["Potts"]], [:potts, :qa]; qa = false)
    @test selected([root.groups["Potts"]], [:potts, :qa]; qa = true)
    @test selected([root.groups["Potts"]], [:potts, :units]; qa = false)
    # a file run (no group) follows qa
    @test !selected([], [:potts, :qa]; qa = false)
    @test selected([], [:potts, :qa]; qa = true)
end

@testitem "test runner: device items need a device" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    selected = PottsTestRunner.selected
    g = [Dict{String, Any}()]                      # a group of every item
    @test !selected(g, [:gpu_only])
    @test selected(g, [:gpu_only]; gpu = "rocm")
    @test !selected(g, [:rocm]; gpu = "metal")
    @test selected(g, [:device])                   # names a device, runs on the CPU too
    @test !selected(g, [:x, :multithreaded])       # only in a group that names it
    @test selected(g, [:a, :b]; tags = [:b]) && !selected(g, [:a]; tags = [:b])
end

@testitem "test runner: shards deal every file exactly once" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    dir = mktempdir()
    files = ["f$(i)_tests.jl" for i in 1:11]
    write(
        joinpath(dir, "shard_weights.toml"),
        "[seconds]\n" * join(("\"$f\" = $(12 - i)" for (i, f) in enumerate(files)), '\n'),
    )
    for n in (1, 2, 3, 11, 13)
        parts = PottsTestRunner.shards(dir, files, n)
        @test length(parts) == n
        @test sort(reduce(vcat, parts)) == sort(files)
    end
    # longest first, each to the least loaded shard
    parts = PottsTestRunner.shards(dir, files, 2)
    @test "f1_tests.jl" in parts[1] && "f2_tests.jl" in parts[2]
end

@testitem "test runner: shard, workers and name are checked before anything runs" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    dir = TESTDIRS["CorePotts"]
    check(; kw...) = argument_error(() -> PottsTestRunner.run_tests(dir; kw...))
    @test occursin("need 1 ≤ k ≤ n", check(shard = (3, 2)))
    @test occursin("need 1 ≤ k ≤ n", check(shard = (0, 2)))
    @test occursin("tuple (k, n) of integers", check(shard = "2/3"))
    @test occursin("tuple (k, n) of integers", check(shard = (1.0, 2.0)))
    @test occursin("integer ≥ 0", check(workers = -1))
    @test occursin("Regex, a string or nothing", check(name = 3))
    withenv("POTTS_TEST_SHARD" => "2/x") do
        @test occursin("k/n with integers", check())
    end
    withenv("POTTS_TEST_SHARD" => "3/2") do
        @test occursin("need 1 ≤ k ≤ n", check())
    end
end

@testitem "test runner: the item-name pattern of runtests.jl" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    name_pattern = PottsTestRunner.name_pattern
    withenv("POTTS_TEST_NAME" => nothing) do
        @test name_pattern(String[]) === nothing
        @test name_pattern(["geometry"]) == r"geometry"
        two = argument_error(() -> name_pattern(["a", "b"]))
        @test occursin("at most one argument", two)
    end
    withenv("POTTS_TEST_NAME" => "units") do
        @test name_pattern(String[]) == r"units"
        @test occursin("set one of them", argument_error(() -> name_pattern(["geometry"])))
    end
end

@testitem "test runner: a Regex keeps its flags in a subprocess" setup = [
    TestRunnerSetup,
] tags = [:potts, :test_runner] begin
    inline = PottsTestRunner.inline_pattern
    @test inline(r"geometry") == "geometry"
    @test inline(r"Geo.Metry"i) == "(?i)Geo.Metry"
    # the subprocess reads the string back with Regex: the same names match
    r = r"^a.b$"ims
    back = Regex(inline(r))
    for s in ("A\nB", "a-b", "x\na\nb", "ab")
        @test occursin(r, s) == occursin(back, s)
    end
    @test occursin("cannot be written inline", argument_error(() -> inline(r"x"a)))
end
