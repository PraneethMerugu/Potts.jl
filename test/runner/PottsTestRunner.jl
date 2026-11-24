"""
    PottsTestRunner

The one test runner of the monorepo. Every package's `test/runtests.jl` calls
[`run_tests`](@ref) with its own test directory, and so do people at a REPL
(`test/runner/session.jl`) and agents. What runs is chosen by environment variables, with
one exception: `runtests.jl` reads its one command-line argument, when given, as the
item-name pattern (see [`name_pattern`](@ref)).

| Variable | Meaning | Default |
|---|---|---|
| `GROUP` | a group of the package's `test_groups.toml` | `All` |
| `POTTS_TEST_NAME` | regex on item names | all items |
| `POTTS_TEST_TAGS` | comma list; items with any of these tags | all items |
| `POTTS_TEST_QA` | `false` skips the `:qa` items, except in a qa group named in `GROUP` | `true` |
| `POTTS_TEST_WORKERS` | worker processes; `0` runs the items in this process | the package's `workers` |
| `POTTS_TEST_SHARD` | `k/n`: the k-th of n shards of the test files | `1/1` |
| `POTTS_GPU` | device backend: `rocm`, `metal` or empty | empty |

Tooling variables: `POTTS_TEST_ORDER` (`default`, `reverse` or `random[:seed]`, the order of
the test files), `POTTS_TEST_PASSLOG` (a file that gets one line per top-level testset) and
`POTTS_TEST_END_EXPR_FILE` (a file whose expression runs after every item).

`GROUP` takes the groups of the package's own table. At the root it also takes
`<Package>_<group>`, a group of a package that the root runs; a package's runner does not.

Kaimon's `run_tests` tool is a supported route: it runs `runtests.jl` with the pattern as
the argument (test/README.md).

test/README.md describes the `test_groups.toml` schema and the rules below in full.
"""
module PottsTestRunner

using ReTestItems: ReTestItems
using Pkg: Pkg
using TOML: TOML

export run_tests

# ---------------------------------------------------------------------------------------
# Settings from the environment

envstr(key) = String(strip(get(ENV, key, "")))

env_group() = (g = envstr("GROUP"); isempty(g) ? "All" : g)
env_name() = (n = envstr("POTTS_TEST_NAME"); isempty(n) ? nothing : Regex(n))

"""
    name_pattern(args) -> Union{Regex, Nothing}

The item-name pattern of a `runtests.jl` run: `POTTS_TEST_NAME`, or the one command-line
argument (the form in which `Pkg.test(; test_args)` and Kaimon's `run_tests` pass a
pattern). An argument selects names only: `GROUP` and the other selections stay environment
variables. Setting both the argument and `POTTS_TEST_NAME` throws an `ArgumentError`, so
that neither silently wins.
"""
function name_pattern(args)
    length(args) <= 1 || throw(
        ArgumentError(
            "runtests.jl takes at most one argument, an item-name pattern; got \
            $(length(args)): $(join(args, ' ')). GROUP and the other selections are \
            environment variables (test/README.md)"
        )
    )
    arg = isempty(args) ? "" : String(strip(only(args)))
    env = envstr("POTTS_TEST_NAME")
    (isempty(arg) || isempty(env)) || throw(
        ArgumentError(
            "both POTTS_TEST_NAME (\"$env\") and the argument (\"$arg\") set the \
            item-name pattern; set one of them"
        )
    )
    pattern = isempty(arg) ? env : arg
    return isempty(pattern) ? nothing : Regex(pattern)
end
env_tags() = Symbol.(filter!(!isempty, strip.(split(envstr("POTTS_TEST_TAGS"), ','))))
env_qa() = parse_bool("POTTS_TEST_QA", true)
env_workers() = (w = envstr("POTTS_TEST_WORKERS"); isempty(w) ? nothing : parse(Int, w))
env_shard() = (s = envstr("POTTS_TEST_SHARD"); isempty(s) ? (1, 1) : parse_shard(s))

# the one rule for POTTS_GPU, shared with the test fixtures (test/shared/devices.jl)
include(joinpath(@__DIR__, "..", "shared", "device_select.jl"))
requested_device() = PottsDeviceSelect.requested()
platform_device() = Sys.isapple() ? "metal" : "rocm"

function parse_bool(key, default)
    v = lowercase(envstr(key))
    isempty(v) && return default
    v in ("true", "1") && return true
    v in ("false", "0") && return false
    throw(ArgumentError("$key must be true or false; got \"$v\""))
end

function parse_shard(s::AbstractString)
    parts = split(s, '/')
    length(parts) == 2 || throw(ArgumentError("POTTS_TEST_SHARD must be k/n; got \"$s\""))
    k, n = tryparse.(Int, parts)
    (k === nothing || n === nothing) &&
        throw(ArgumentError("POTTS_TEST_SHARD must be k/n with integers k, n; got \"$s\""))
    return (k, n)
end

# `shard` is a tuple `(k, n)` of integers with 1 ≤ k ≤ n; the one check of both the keyword
# and POTTS_TEST_SHARD
function as_shard(s)
    s isa Tuple{Integer, Integer} || throw(
        ArgumentError("shard must be a tuple (k, n) of integers; got $(repr(s))")
    )
    k, n = Int(s[1]), Int(s[2])
    1 <= k <= n || throw(ArgumentError("shard = ($k, $n): need 1 ≤ k ≤ n"))
    return (k, n)
end

function as_workers(w)
    w === nothing && return nothing
    (w isa Integer && w >= 0) ||
        throw(ArgumentError("workers must be an integer ≥ 0 or nothing; got $(repr(w))"))
    return Int(w)
end

as_regex(::Nothing) = nothing
as_regex(r::Regex) = r
as_regex(s::AbstractString) = Regex(s)
function as_regex(x)
    throw(ArgumentError("name must be a Regex, a string or nothing; got $(repr(x))"))
end

"""
    inline_pattern(r::Regex) -> String

The pattern of `r` with its flags written inline (`r"abc"i` gives `"(?i)abc"`), so that a
package's subprocess that reads it from `POTTS_TEST_NAME` matches the same names. Only the
flags `i`, `m`, `s` and `x` can be written inline; another throws an `ArgumentError`.
"""
function inline_pattern(r::Regex)
    flags = match(r"\"([a-z]*)\z", repr(r))
    f = flags === nothing ? "" : flags[1]
    all(in("imsx"), f) || throw(
        ArgumentError(
            "the name pattern $(repr(r)) has a flag that cannot be written inline \
            (only i, m, s and x can); pass the pattern as a string"
        )
    )
    return isempty(f) ? r.pattern : "(?$f)" * r.pattern
end

as_tags(t::Symbol) = [t]
as_tags(t::AbstractString) = Symbol.(filter!(!isempty, strip.(split(t, ','))))
as_tags(t) = Symbol[Symbol(x) for x in t]

# ---------------------------------------------------------------------------------------
# test_groups.toml

"""
The test groups of one package: the settings at the top of its `test_groups.toml` and one
table per group.
"""
struct GroupTable
    testdir::String
    settings::Dict{String, Any}
    groups::Dict{String, Dict{String, Any}}
end

const SETTING_KEYS = (
    "all", "workers", "worker_threads", "testitem_timeout", "memory_threshold", "logs",
)
const GROUP_KEYS = (
    "tags", "exclude_tags", "dirs", "files", "exclude_files", "package", "groups",
    "device", "workers", "min_threads", "qa", "rocm_check",
)

"""
    load_groups(testdir) -> GroupTable

The groups of `testdir/test_groups.toml`. An unknown key or setting, a missing `all` list,
or an `all` entry that is not a group throws an `ArgumentError`.
"""
function load_groups(testdir::AbstractString)
    path = joinpath(testdir, "test_groups.toml")
    isfile(path) || throw(ArgumentError("no test_groups.toml in $testdir"))
    raw = TOML.parsefile(path)
    settings = Dict{String, Any}()
    groups = Dict{String, Dict{String, Any}}()
    for (key, val) in raw
        if val isa AbstractDict
            for k in keys(val)
                k in GROUP_KEYS ||
                    throw(ArgumentError("$path: unknown key \"$k\" in group \"$key\""))
            end
            groups[key] = Dict{String, Any}(val)
        else
            key in SETTING_KEYS || throw(ArgumentError("$path: unknown setting \"$key\""))
            settings[key] = val
        end
    end
    haskey(settings, "all") || throw(ArgumentError("$path: missing the `all` list"))
    for g in settings["all"]
        haskey(groups, g) || throw(ArgumentError("$path: `all` names unknown group \"$g\""))
    end
    return GroupTable(abspath(testdir), settings, groups)
end

function valid_groups(t::GroupTable)
    return join(["All"; sort!(collect(keys(t.groups)))], ", ")
end

# The group of a warm session (runner/session.jl): `All` when it runs only this package's
# items, else the one group of `all` that does (at the root: Potts, not every package).
function session_group(testdir::AbstractString)
    t = load_groups(testdir)
    local_groups = filter(g -> is_item_group(t.groups[g]), t.settings["all"])
    length(local_groups) == length(t.settings["all"]) && return "All"
    length(local_groups) == 1 && return only(local_groups)
    return "All"
end

# a group of this package's items (not another package's suite, not a group of groups)
is_item_group(opts) = !haskey(opts, "package") && !haskey(opts, "groups")

# a group whose tags name `qa`: its `:qa` items run whatever `qa` says when it is named
is_qa_group(opts) = "qa" in get(opts, "tags", String[])

"""
    all_groups(t, qa) -> Vector{String}

The groups of `GROUP=All`: the `all` list of the table, without the qa groups (groups whose
`tags` name `qa`) when `qa` is false.
"""
function all_groups(t::GroupTable, qa::Bool)
    return [g for g in t.settings["all"] if qa || !is_qa_group(t.groups[g])]
end

package_dir(t::GroupTable, pkg) = joinpath(dirname(t.testdir), "lib", pkg, "test")

# GROUP = "<Package>_<group>" for a package that a group of this table runs
function split_package_group(t::GroupTable, name::AbstractString)
    for opts in values(t.groups)
        pkg = get(opts, "package", nothing)
        pkg === nothing && continue
        prefix = pkg * "_"
        startswith(name, prefix) && return (pkg, name[(lastindex(prefix) + 1):end])
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# The selection of one run

"""What the caller asked for: the keywords of `run_tests`."""
struct Selection
    name::Union{Regex, Nothing}
    tags::Vector{Symbol}
    file::Union{String, Nothing}
    qa::Bool
    workers::Union{Int, Nothing}
    shard::Tuple{Int, Int}
end

"""
    run_tests(testdir = <the active test project's directory>;
              group, name, tags, file, qa, workers, shard)

Run the test items of the package whose test directory is `testdir`. Each keyword's default
comes from the environment (see [`PottsTestRunner`](@ref)), so CI, the gates, a REPL and an
agent differ only in the variables they set.

- `group`: a group of `testdir/test_groups.toml` or `"All"`. At the root, also
  `"<Package>_<group>"`: a group of a package that a group of the root table runs.
- `name`: a `Regex` or a regex string on item names. A `Regex` passes to a package's
  subprocess with its flags inline (`r"x"i` as `"(?i)x"`).
- `tags`: items that carry any of these tags (`Symbol`s, or a comma list).
- `file`: a test file, relative to `testdir`: every item of that file. `group` and `shard`
  are not used.
- `qa`: `false` skips the `:qa` items and drops the qa groups (groups whose `tags` name
  `qa`) from `All`. A qa group named in `group` runs its items either way.
- `workers`: worker processes (an integer ≥ 0); `0` runs the items in this process.
- `shard`: a tuple `(k, n)` of integers, 1 ≤ k ≤ n: only the k-th of n shards of the test
  files.

Kaimon's `run_tests` tool runs `runtests.jl` with its pattern as the one argument (see
[`name_pattern`](@ref)), so it is a supported route too.
"""
function run_tests(
        testdir::AbstractString = dirname(Base.active_project());
        group::AbstractString = env_group(), name = env_name(), tags = env_tags(),
        file::Union{AbstractString, Nothing} = nothing, qa::Bool = env_qa(),
        workers = env_workers(), shard = env_shard()
    )
    sel = Selection(
        as_regex(name), as_tags(tags), file === nothing ? nothing : String(file), qa,
        as_workers(workers), as_shard(shard),
    )
    t = load_groups(testdir)
    if sel.file !== nothing
        path = joinpath(t.testdir, sel.file)
        isfile(path) || throw(ArgumentError("no test file $path"))
        return run_items(t, Dict{String, Any}[], sel; paths = [path])
    end
    return run_group(t, String(group), sel)
end

# the test files are included into `Main`, which must know the macros
function ensure_testitem_macros()
    isdefined(Main, Symbol("@testitem")) ||
        Core.eval(Main, :(using ReTestItems: @testitem, @testsetup))
    return nothing
end

function run_group(t::GroupTable, name::String, sel::Selection)
    if name == "All"
        return run_sequence(t, all_groups(t, sel.qa), sel)
    elseif haskey(t.groups, name)
        return run_sequence(t, [name], sel)
    end
    split = split_package_group(t, name)
    if split === nothing
        packages = sort!([o["package"] for o in values(t.groups) if haskey(o, "package")])
        more = isempty(packages) ? "" :
            ", or <Package>_<group> for a group of $(join(packages, ", "))"
        throw(
            ArgumentError(
                "Unknown test GROUP = \"$name\" in $(t.testdir). Valid groups: \
                $(valid_groups(t))$more."
            )
        )
    end
    return run_package(t, split[1], split[2], sel)
end

# Groups in order; consecutive groups of items run as one ReTestItems run, except that a
# group with file rules runs alone.
function run_sequence(t::GroupTable, names, sel::Selection)
    shard = shard_files(t, names, sel)
    batch = Dict{String, Any}[]
    function flush()
        isempty(batch) || run_items(t, batch, sel; paths = run_paths(t, batch, shard))
        return empty!(batch)
    end
    for n in names
        opts = t.groups[n]
        if haskey(opts, "package")
            flush()
            run_package(t, opts["package"], "All", sel)
        elseif haskey(opts, "groups")
            flush()
            run_composite(t, n, opts, sel)
        else
            has_file_rules(opts) && flush()
            push!(batch, merge(opts, Dict{String, Any}("name" => n)))
            has_file_rules(opts) && flush()
        end
    end
    flush()
    return nothing
end

# A group of groups (GROUP=GPU): its members run in turn, on one device, then its check.
function run_composite(t::GroupTable, name, opts, sel::Selection)
    device = get(opts, "device", false) == true
    gpu = requested_device()
    device && isempty(gpu) && (gpu = platform_device())
    irdir = envstr("POTTS_DEVICE_IR_DIR")
    isempty(irdir) ? (irdir = mktempdir()) : mkpath(irdir)
    qa = sel.qa && get(opts, "qa", true) == true
    sub = Selection(sel.name, sel.tags, nothing, qa, sel.workers, sel.shard)
    @info "GROUP=$name" device = gpu
    withenv("POTTS_GPU" => gpu, "POTTS_DEVICE_IR_DIR" => irdir) do
        for member in opts["groups"]
            run_group(t, member, sub)
        end
        check = get(opts, "rocm_check", nothing)
        if check !== nothing && gpu == "rocm"
            run_julia(t.testdir, joinpath(t.testdir, check), sub)
        end
    end
    return nothing
end

# another package's suite, in its own test environment, in a subprocess
function run_package(t::GroupTable, pkg, group, sel::Selection)
    dir = package_dir(t, pkg)
    isdir(dir) || throw(ArgumentError("no test directory $dir for package $pkg"))
    return withenv("GROUP" => group) do
        run_julia(dir, joinpath(dir, "runtests.jl"), sel)
    end
end

function run_julia(project, script, sel::Selection)
    bounds = Base.JLOptions().check_bounds == 0 ? ["--check-bounds=auto"] : String[]
    cmd = `$(Base.julia_cmd()) --startup-file=no $bounds --project=$project $script`
    @info "Running $script" GROUP = get(ENV, "GROUP", "")
    return run(addenv(cmd, selection_env(sel)...))
end

# the selection, passed on to a subprocess as its environment
function selection_env(sel::Selection)
    env = Pair{String, String}[
        "POTTS_TEST_NAME" => sel.name === nothing ? "" : inline_pattern(sel.name),
        "POTTS_TEST_TAGS" => join(sel.tags, ','),
        "POTTS_TEST_QA" => string(sel.qa),
        "POTTS_TEST_SHARD" => "$(sel.shard[1])/$(sel.shard[2])",
    ]
    sel.workers === nothing || push!(env, "POTTS_TEST_WORKERS" => string(sel.workers))
    return env
end

# ---------------------------------------------------------------------------------------
# One ReTestItems run over the items of some groups

has_tag(ti, tag) = tag in ti.tags
tagset(opts, key) = Symbol.(get(opts, key, String[]))

function file_rules(opts)
    return (
        get(opts, "dirs", String[]), get(opts, "files", String[]),
        get(opts, "exclude_files", String[]),
    )
end
has_file_rules(opts) = any(!isempty, file_rules(opts))

function file_in_group(opts, rel::AbstractString)
    dirs, files, excl = file_rules(opts)
    rel in excl && return false
    (isempty(dirs) && isempty(files)) && return true
    return any(d -> startswith(rel, d * "/"), dirs) || rel in files
end

# ReTestItems shows a filter only an item's name and tags: a group's files are chosen by the
# paths of its run (`run_paths`), so a group with file rules runs on its own
function item_in_group(opts, tags)
    want = tagset(opts, "tags")
    (isempty(want) || any(in(tags), want)) || return false
    any(in(tags), tagset(opts, "exclude_tags")) && return false
    # items that need the process's threads run only in a group that names them
    return !(:multithreaded in tags) || :multithreaded in want
end

"""Every test file under `testdir`, relative to it, in a fixed order."""
function test_files(testdir)
    out = String[]
    for (root, _, files) in walkdir(testdir), f in files
        is_test_file(f) && push!(out, relpath(joinpath(root, f), testdir))
    end
    return sort!(replace.(out, '\\' => '/'))
end

function is_test_file(f)
    return endswith(f, "_tests.jl") || endswith(f, "_test.jl") ||
        endswith(f, "-tests.jl") || endswith(f, "-test.jl")
end

"""Deal `files` to `n` shards, longest first by the weights of `shard_weights.toml`."""
function shards(testdir, files, n)
    p = joinpath(testdir, "shard_weights.toml")
    weights = if isfile(p)
        Dict{String, Float64}(k => Float64(v) for (k, v) in TOML.parsefile(p)["seconds"])
    else
        Dict{String, Float64}()
    end
    known = [weights[f] for f in files if haskey(weights, f)]
    fallback = isempty(known) ? 1.0 : sort(known)[cld(length(known), 2)]
    w(f) = get(weights, f, fallback)
    load = zeros(n)
    shard = Dict{String, Int}()
    for f in sort(files; by = f -> (-w(f), f))                # longest first, ties by name
        j = argmin(load)
        shard[f] = j
        load[j] += w(f)
    end
    return [[f for f in files if shard[f] == j] for j in 1:n]
end

# the paths of a run: the test directory, or its files when a group picks files or the
# files are sharded
function run_paths(t::GroupTable, batch, shard)
    (shard === nothing && !any(has_file_rules, batch)) && return [t.testdir]
    in_batch(f) = any(g -> file_in_group(g, f), batch)
    in_shard(f) = shard === nothing || f in shard
    files = filter(f -> in_batch(f) && in_shard(f), test_files(t.testdir))
    return [joinpath(t.testdir, f) for f in files]
end

# The files of this shard (`nothing` when the run is not sharded). The files of all the item
# groups of the run are dealt together, so that every file runs in exactly one shard.
function shard_files(t::GroupTable, names, sel::Selection)
    k, n = sel.shard
    n == 1 && return nothing
    local_groups = [t.groups[g] for g in names if is_item_group(t.groups[g])]
    files = filter(f -> any(g -> file_in_group(g, f), local_groups), test_files(t.testdir))
    mine = shards(t.testdir, files, n)[k]
    @info "Shard $k/$n: $(length(mine)) of $(length(files)) files" mine
    return Set(mine)
end

function run_items(t::GroupTable, batch, sel::Selection; paths)
    isempty(paths) && return nothing
    names = [g["name"] for g in batch]
    device = any(g -> get(g, "device", false) == true, batch)
    gpu = requested_device()
    device && isempty(gpu) && (gpu = platform_device())
    for g in batch
        need = get(g, "min_threads", 1)
        Threads.nthreads() >= need || error(
            "GROUP=$(g["name"]) needs at least $need Julia threads (got \
            $(Threads.nthreads())); run with `julia -t $need`"
        )
    end
    fixed = [g["workers"] for g in batch if haskey(g, "workers")]
    workers = if device
        0                            # a device group: one process on the device
    elseif !isempty(fixed)
        first(fixed)                 # the group needs this process (its threads)
    else
        something(sel.workers, get(t.settings, "workers", 0))
    end
    keep(ti) = selected(batch, ti.tags; qa = sel.qa, tags = sel.tags, gpu)
    on_device(ti) = !isempty(gpu) && device_item(ti.tags)
    isempty(names) ||
        @info "Running $(join(names, ", ")) in $(t.testdir)" device = gpu workers
    return withenv("POTTS_GPU" => (isempty(gpu) ? nothing : gpu)) do
        run_passes(t, keep, on_device, workers, paths, sel)
    end
end

# an item that uses the device when one is selected
device_item(tags) = any(in(tags), (:gpu, :gpu_only, :device, :device_scan))

"""
    selected(batch, item_tags; qa = true, tags = Symbol[], gpu = "") -> Bool

Whether an item with the tags `item_tags` runs in a run of the item groups `batch` (the
group tables; empty for a `file` run), with the selection `qa` and `tags` and the device
`gpu` (`""` for none). A `:qa` item runs when `qa` is true, or in a qa group: `GROUP=All`
drops the qa groups when `qa` is false (see [`all_groups`](@ref)), so a qa group in a run
was named explicitly.
"""
function selected(batch, item_tags; qa::Bool = true, tags = Symbol[], gpu = "")
    # items for the device run only when a device is selected; `:rocm` ones on ROCm only
    (:gpu in item_tags || :gpu_only in item_tags) && isempty(gpu) && return false
    :rocm in item_tags && gpu != "rocm" && return false
    qa_ok(g) = qa || !(:qa in item_tags) || (g !== nothing && is_qa_group(g))
    if isempty(batch)
        qa_ok(nothing) || return false
    else
        any(g -> item_in_group(g, item_tags) && qa_ok(g), batch) || return false
    end
    return isempty(tags) || any(in(item_tags), tags)
end

# With a device selected, the items that use it (`device_item`) run in this process, after
# the host items. Items that time code in-process (`:timing`) or start Julia subprocesses
# (`:subprocess`) run after the others of their kind (host or device), one at a time, on
# uncontended cores. The scan of the device code (`:device_scan`) reads the kernel cache of
# the process that compiled the device items, so it runs last, in this process too.
serial(ti) = has_tag(ti, :timing) || has_tag(ti, :subprocess)
scan(ti) = has_tag(ti, :device_scan)

function run_passes(t::GroupTable, keep, on_device, workers, paths, sel::Selection)
    host(ti) = keep(ti) && !on_device(ti) && !scan(ti)
    device(ti) = keep(ti) && on_device(ti) && !scan(ti)
    passes = (
        (ti -> host(ti) && !serial(ti), workers),
        (ti -> host(ti) && serial(ti), min(workers, 1)),
        (ti -> device(ti) && !serial(ti), 0),
        (ti -> device(ti) && serial(ti), 0),
        (ti -> keep(ti) && scan(ti), 0),
    )
    errs = Tuple{Any, Any}[]                     # (exception, backtrace), in pass order
    empty_passes = 0
    for (pred, n) in passes
        try
            retestitems(t, pred, ordered_paths(paths), n, sel)
        catch e
            e isa ReTestItems.NoTestException && (empty_passes += 1; continue)
            push!(errs, (e, catch_backtrace()))
        end
    end
    # a selection that matches nothing is a result (0 items), not a failure
    if empty_passes == length(passes)
        @info "0 test items match the selection in $(t.testdir)"
    end
    # report every pass that failed, and fail the run with the first one (its stack is the
    # cause; a later pass's error is usually the same failure seen again)
    for (e, bt) in errs[2:end]
        @error "a later pass failed too" exception = (e, bt)
    end
    isempty(errs) && return nothing
    e, bt = first(errs)
    @error "the run failed" exception = (e, bt)
    throw(e)
end

# `ReTestItems.runtests` in the active test environment. ReTestItems refuses to activate the
# test environment of an unnamed project; ours is the workspace's test project, already
# active, and ReTestItems treats a run as `Pkg.test`'s (in the current environment) when the
# task-local `SOURCE_PATH` is that project's `runtests.jl`. `Pkg.Operations.testfile` is an
# internal Pkg API: check it on dependency updates.
function retestitems(t::GroupTable, pred, paths, nworkers, sel::Selection)
    s = t.settings
    kw = (;
        nworkers, name = sel.name, retries = 0,
        testitem_timeout = get(s, "testitem_timeout", 3600),
        nworker_threads = string(get(s, "worker_threads", Threads.nthreads())),
        test_end_expr = end_expr(),
    )
    if haskey(s, "memory_threshold")
        kw = (; kw..., memory_threshold = s["memory_threshold"])
    end
    haskey(s, "logs") && (kw = (; kw..., logs = Symbol(s["logs"])))
    ensure_testitem_macros()
    proj = ReTestItems.identify_project(t.testdir)
    return task_local_storage(:SOURCE_PATH, Pkg.Operations.testfile(dirname(proj))) do
        ReTestItems.runtests(pred, paths...; kw...)
    end
end

# ---------------------------------------------------------------------------------------
# Tooling: file order, per-testset pass log, end expression

function shuffle!(v::AbstractVector, seed::Integer)
    state = UInt64(seed) == 0 ? UInt64(0x9e3779b97f4a7c15) : UInt64(seed)
    for i in length(v):-1:2
        state ⊻= state >> 12
        state ⊻= state << 25
        state ⊻= state >> 27
        r = (state * UInt64(0x2545f4914f6cdd1d)) % UInt64(i)
        j = Int(r) + 1
        v[i], v[j] = v[j], v[i]
    end
    return v
end

"""The paths in the order that `POTTS_TEST_ORDER` asks for (`default`: as given)."""
function ordered_paths(
        paths, spec::AbstractString = get(ENV, "POTTS_TEST_ORDER", "default")
    )
    s = lowercase(strip(String(spec)))
    (isempty(s) || s == "default") && return paths
    files = String[]
    for p in paths
        isdir(p) ? append!(files, joinpath.(p, test_files(p))) : push!(files, String(p))
    end
    if s == "reverse"
        reverse!(files)
    elseif s == "random" || startswith(s, "random:")
        seed = if s == "random"
            Int(time_ns() & 0x7fffffff)
        else
            parse(Int, s[(length("random:") + 1):end])
        end
        @info "test file order" order = "random" seed
        shuffle!(files, seed)
    else
        throw(
            ArgumentError(
                "Unknown POTTS_TEST_ORDER=$(repr(spec)); expected default, reverse, or \
                random[:seed]"
            )
        )
    end
    return files
end

"""The expression that runs after every item: the pass log and the end-expression file."""
function end_expr()
    ex = Expr(:block)
    append!(ex.args, passlog_expr().args)
    file = envstr("POTTS_TEST_END_EXPR_FILE")
    isempty(file) || push!(ex.args, Meta.parse("begin\n" * read(file, String) * "\nend"))
    return ex
end

# POTTS_TEST_PASSLOG=<file>: after each item, one line per top-level testset of the item
# (item, testset, pass, fail, error, broken). Each process writes `<file>.<pid>`; the gate
# script concatenates them into `<file>`.
#
# The expression is evaluated in the item's module in a *worker process*, and ReTestItems
# serializes it there: it must be code with only literals in it. Interpolating a function
# of this module makes the payload a reference to a module the worker does not have, and
# the worker dies while deserializing its first item (the coordinator then fails with
# ECONNRESET on the next write).
function passlog_expr()
    path = envstr("POTTS_TEST_PASSLOG")
    isempty(path) && return Expr(:block)
    return quote
        let ts = Test.get_testset()
            # the counts of a testset's subtree: its passes are cumulative, its failures
            # are direct
            function counts(results, n_passed)
                p, f, e, b = n_passed, 0, 0, 0
                for r in results
                    if r isa Test.AbstractTestSet
                        q = counts(r.results, r.n_passed)
                        p += q[1]
                        f += q[2]
                        e += q[3]
                        b += q[4]
                    elseif r isa Test.Fail
                        f += 1
                    elseif r isa Test.Error
                        e += 1
                    elseif r isa Test.Broken
                        b += 1
                    end
                end
                return (p, f, e, b)
            end
            # one file per process (the coordinator and each worker), merged after the
            # run: two processes appending to one file split a row when a write lands in
            # two pieces
            emit(parts...) = open(string($path, ".", getpid()), "a") do io
                write(io, join(parts, '\t'), '\n')
            end
            for r in ts.results
                r isa Test.AbstractTestSet || continue
                emit(ts.description, r.description, counts(r.results, r.n_passed)...)
            end
            # results outside any testset of the item (a bare @test, an error): one row
            d = (
                0, count(r -> r isa Test.Fail, ts.results),
                count(r -> r isa Test.Error, ts.results),
                count(r -> r isa Test.Broken, ts.results),
            )
            d[2] + d[3] + d[4] > 0 && emit(ts.description, "(item level)", d...)
        end
    end
end

end # module PottsTestRunner
