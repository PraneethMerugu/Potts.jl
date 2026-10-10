# P6.15l: the D-215 post-processing of the P6.15j O1/O2 record (`../o1-2026-10-09/`). No
# simulation runs here: the P6.15j files are rewritten into the form the consortium
# repository's scripts read (spec 15 §3.1 O1/O2; D-215 (1), (3), (5); D-217).
#
# - O1. Every P6.15j O1 file gains a last column `g` (g = 1 if i == 0, else 0), because
#   `metrics.cpp` exits without it: the header `x,y,i,n` becomes `x,y,i,n,g` and every row
#   gets ",0" or ",1", so each file grows by exactly 2 (rows + 1) bytes. The files are packed
#   per case into a descriptively named zip, members `<stem>/s<seed>/potts_<case>_s<seed>_<MCS:06d>.csv`:
#   (a) `Potts.jl_beta0.0_gamma0.0`, (b) `Potts.jl_No_CI_stochastic`,
#   (e) `Potts.jl_beta0.8_gamma0.0`, (f) `Potts.jl_No_CI_deterministic`.
# - O2. The 100 case (b) files are renumbered k = 0…99 (P6.15j file k + 1, bytes unchanged,
#   as the Fig 5 notebook's `range(0,100)` reads them) and zipped with their folder inside,
#   `Potts.jl_5T_MonolayerGrowth_1000_Data.zip`.
#
# Every P6.15j file is checked against the P6.15j manifests (sha256) before it is used, and
# every new zip's member list against the new manifest after it is written.
#
# Reads and writes the bulk directory `OPENVT_PACKAGE_BULK` (outside git): it reads the
# P6.15j zips and O2 files there and writes the new zips next to them. Nothing is deleted.
# An existing new zip is kept when its bytes are already the ones built here, and refused
# otherwise unless `OPENVT_O1G_OVERWRITE=true`.
#
# Deterministic: members are written in byte order (`LC_ALL=C sort`), every file gets the
# mtime 1980-01-01 00:00 UTC (the zip epoch) and zip runs with TZ=UTC and `-X -D -9` (no
# extra attributes, no directory entries), so the same input gives the same zip bytes on
# any machine with Info-ZIP zip 3.0.
#
# Writes into this directory: o1_manifest.tsv, archives.tsv, o2_manifest.tsv (the P6.15j
# headers) and provenance.toml. README.md is written by hand.
#
# Needs Info-ZIP `zip` and `unzip` on PATH. Light I/O only (about 100 s). From the
# repository root, at a commit with no tracked changes:
#
#     OPENVT_PACKAGE_BULK=<bulk dir> julia --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/o1g-2026-10-10/post_o1.jl
using Dates, TOML, SHA

const started = now()
const DIR = @__DIR__
const DATA = normpath(joinpath(DIR, ".."))
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const SOURCE = "o1-2026-10-09"                     # the P6.15j record mapped here
const RAW = joinpath(DATA, SOURCE)
const FW = "Potts.jl"                              # the framework token (D-215 (9))
const STEM = Dict("a" => "$(FW)_beta0.0_gamma0.0", "b" => "$(FW)_No_CI_stochastic",
    "e" => "$(FW)_beta0.8_gamma0.0", "f" => "$(FW)_No_CI_deterministic")
const O2_DIR = "$(FW)_5T_MonolayerGrowth_1000_Data"
const O2_DIR_RAW = "Potts.jl_5T_MonolayerGrowth_1000_Data"
raw_zip(case) = "Potts.jl_centroids_$(case).zip"
const H_O1M = "case\tseed\tmcs\tfile\trows\tbytes\ti0\ti1\ti2\ti3\tsha256"
const H_ARCH = "case\tarchive\tmembers\tbytes\tsha256"
const H_O2M = "k\tfile\trows\tbytes\tsha256"
const OVERWRITE = get(ENV, "OPENVT_O1G_OVERWRITE", "false") == "true"

function tsv(path)
    ls = filter(!isempty, split(read(path, String), '\n'))
    head = split(ls[1], '\t')
    return [Dict(zip(head, String.(split(l, '\t')))) for l in ls[2:end]]
end
sha(path) = bytes2hex(open(sha256, path))
function in_git(path)
    d = realpath(path)
    while true
        ispath(joinpath(d, ".git")) && return true
        dirname(d) == d && return false
        d = dirname(d)
    end
end

const BULK = let b = get(ENV, "OPENVT_PACKAGE_BULK", "")
    (isempty(b) || !isdir(b)) && error("post_o1: set OPENVT_PACKAGE_BULK to the bulk directory")
    in_git(b) && error("post_o1: the bulk directory is inside a git checkout")
    abspath(b)
end

# ---- the P6.15j inputs, checked before anything is written ---------------------------------
const MAN = sort(tsv(joinpath(RAW, "o1_manifest.tsv")); by = r -> r["file"])
const ARCH = Dict(r["case"] => r for r in tsv(joinpath(RAW, "archives.tsv")))
const O2M = sort(tsv(joinpath(RAW, "o2_manifest.tsv")); by = r -> parse(Int, r["k"]))
const CASES = sort(collect(keys(ARCH)))
CASES == sort(unique(r["case"] for r in MAN)) || error("post_o1: the P6.15j manifests disagree on the cases")
all(c -> haskey(STEM, c), CASES) || error("post_o1: a case without a D-215 stem")
for c in CASES
    p = joinpath(BULK, raw_zip(c))
    (isfile(p) && string(filesize(p)) == ARCH[c]["bytes"] && sha(p) == ARCH[c]["sha256"]) ||
        error("post_o1: $(raw_zip(c)) in the bulk directory differs from the P6.15j record")
end
[parse(Int, r["k"]) for r in O2M] == 1:100 || error("post_o1: the P6.15j O2 manifest is not k = 1…100")
for r in O2M
    p = joinpath(BULK, split(r["file"], '/')...)
    (isfile(p) && sha(p) == r["sha256"]) || error("post_o1: $(r["file"]) in the bulk directory differs from the P6.15j record")
end

# ---- zip a staged tree deterministically --------------------------------------------------
function zip_tree!(stage, z)
    sh = "find . -type f -exec touch -t 198001010000.00 {} + && " *
         "find . -type f | sed 's|^\\./||' | LC_ALL=C sort | zip -X -D -9 -q -@ " * Base.shell_escape(z)
    run(setenv(Cmd(`sh -c $sh`; dir = stage), merge(ENV, Dict("TZ" => "UTC", "LC_ALL" => "C"))))
    return z
end

# build into a temporary name, then keep an identical existing zip or move the new one in
function place!(tmp, name)
    dst = joinpath(BULK, name)
    if isfile(dst)
        if sha(dst) == sha(tmp)
            rm(tmp)
            return dst
        end
        OVERWRITE || error("post_o1: $name exists in the bulk directory with other bytes (OPENVT_O1G_OVERWRITE=true replaces it)")
    end
    mv(tmp, dst; force = true)
    return dst
end

# ---- O1: add g, rename, zip per case ------------------------------------------------------
o1rows = String[]
arows = String[]
for case in CASES
    rows = filter(r -> r["case"] == case, MAN)
    unz, stage = mktempdir(), mktempdir()
    run(`unzip -q $(joinpath(BULK, raw_zip(case))) -d $unz`)
    members = String[]
    for r in rows
        buf = read(joinpath(unz, split(r["file"], '/')...))
        bytes2hex(sha256(buf)) == r["sha256"] || error("post_o1: $(r["file"]) differs from the P6.15j manifest")
        ls = split(String(buf), '\n')
        (isempty(last(ls)) && !any(l -> occursin('\r', l), ls)) || error("post_o1: $(r["file"]): unexpected line ends")
        pop!(ls)
        ls[1] == "x,y,i,n" || error("post_o1: $(r["file"]): header $(ls[1])")
        length(ls) - 1 == parse(Int, r["rows"]) || error("post_o1: $(r["file"]): row count")
        io = IOBuffer()
        print(io, "x,y,i,n,g\n")
        for l in @view ls[2:end]
            f = split(l, ',')
            (length(f) == 4 && f[3] in ("0", "1", "2", "3")) || error("post_o1: $(r["file"]): row $l")
            print(io, l, f[3] == "0" ? ",1\n" : ",0\n")
        end
        out = take!(io)
        length(out) == length(buf) + 2 * (parse(Int, r["rows"]) + 1) || error("post_o1: $(r["file"]): size")
        rel = "$(STEM[case])/s$(r["seed"])/$(basename(r["file"]))"
        mkpath(dirname(joinpath(stage, rel)))
        write(joinpath(stage, rel), out)
        push!(members, rel)
        push!(o1rows, join((case, r["seed"], r["mcs"], rel, r["rows"], string(length(out)),
            r["i0"], r["i1"], r["i2"], r["i3"], bytes2hex(sha256(out))), '\t'))
    end
    sort!(members)
    name = STEM[case] * ".zip"
    tmp = zip_tree!(stage, joinpath(BULK, "." * name * ".part"))
    readlines(`unzip -Z1 $tmp`) == members || error("post_o1: $name: members differ from the manifest")
    success(`unzip -tq $tmp`) || error("post_o1: $name fails unzip -t")
    z = place!(tmp, name)
    push!(arows, join((case, name, string(length(members)), string(filesize(z)), sha(z)), '\t'))
    rm(unz; recursive = true)
    rm(stage; recursive = true)
    @info "post_o1: case $case" name members = length(members) bytes = filesize(z)
end

# ---- O2: k = 0…99, one zip with its folder ------------------------------------------------
o2rows = String[]
stage = mktempdir()
mkpath(joinpath(stage, O2_DIR))
o2members = String[]
for r in O2M
    k = parse(Int, r["k"]) - 1
    rel = "$(O2_DIR)/cell_data_no_inhibition_$(k).csv"
    cp(joinpath(BULK, split(r["file"], '/')...), joinpath(stage, rel))
    push!(o2members, rel)
    push!(o2rows, join((string(k), rel, r["rows"], r["bytes"], r["sha256"]), '\t'))
end
sort!(o2members)
const O2_ZIP = O2_DIR * ".zip"
tmp = zip_tree!(stage, joinpath(BULK, "." * O2_ZIP * ".part"))
readlines(`unzip -Z1 $tmp`) == o2members || error("post_o1: $O2_ZIP: members differ")
success(`unzip -tq $tmp`) || error("post_o1: $O2_ZIP fails unzip -t")
z2 = place!(tmp, O2_ZIP)
push!(arows, join(("O2", O2_ZIP, string(length(o2members)), string(filesize(z2)), sha(z2)), '\t'))
rm(stage; recursive = true)

# ---- the record --------------------------------------------------------------------------
sort!(o1rows; by = l -> split(l, '\t')[4])
write(joinpath(DIR, "o1_manifest.tsv"), H_O1M * "\n" * join(o1rows .* "\n"))
write(joinpath(DIR, "archives.tsv"), H_ARCH * "\n" * join(arows .* "\n"))
write(joinpath(DIR, "o2_manifest.tsv"), H_O2M * "\n" * join(o2rows .* "\n"))

git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
const commit = git("rev-parse", "HEAD")
const finished = now()
const RUNNER = relpath(@__FILE__, ROOT)
prov = Dict{String, Any}(
    "item" => "P6.15l",
    "source" => SOURCE,
    "commit" => commit,
    "commit_date" => git("show", "-s", "--format=%cs", commit),
    "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
    "decisions" => ["D-213", "D-215", "D-217"],
    "runner" => replace(RUNNER, '\\' => '/'),
    "runner_sha256" => sha(@__FILE__),
    "julia" => string(VERSION),
    "machine" => Sys.MACHINE,
    "cpu" => String(strip(Sys.cpu_info()[1].model)),
    "threads" => Threads.nthreads(),
    "zip" => (v = filter(l -> occursin(r"^This is Zip", l), readlines(`zip -v`)); isempty(v) ? "" : String(strip(v[1]))),
    "o1_files" => length(o1rows),
    "o1_bytes" => sum(l -> parse(Int, split(l, '\t')[6]), o1rows),
    "o1_zip_bytes" => sum(l -> parse(Int, split(l, '\t')[4]), arows[1:(end - 1)]),
    "o2_zip_bytes" => filesize(z2),
    "started" => string(started),
    "finished" => string(finished),
    "wall_s" => round((finished - started).value / 1000; digits = 1),
)
open(io -> TOML.print(io, prov; sorted = true), joinpath(DIR, "provenance.toml"), "w")
@info "post_o1: done" wall_s = prov["wall_s"] archives = arows
