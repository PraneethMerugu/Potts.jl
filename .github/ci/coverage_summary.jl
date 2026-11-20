# Summarize Julia `--code-coverage` `.cov` files across the workspace (non-gating).
# Usage: julia --startup-file=no .github/ci/coverage_summary.jl [--clean] [--root=DIR]
#
# Merges per-worker `*.jl.<pid>.cov` (and `*.jl.cov`) files per source line without external
# dependencies. Writes a plain-text table to stdout and appends a Markdown table to
# `$GITHUB_STEP_SUMMARY` when set. `PottsModels` and `GPU` are excluded by design
# (`PottsModels` exceeds 9000 s under `--code-coverage`).
using Printf: @sprintf

const PACKAGES = [
    ("Potts", ["src", "ext"]),
    ("CorePotts", ["lib/CorePotts/src", "lib/CorePotts/ext"]),
    ("LatticeFields", ["lib/LatticeFields/src", "lib/LatticeFields/ext"]),
    ("LatticePDE", ["lib/LatticePDE/src"]),
    ("MakiePotts", ["lib/MakiePotts/src"]),
]

function find_cov_files(jl_path::AbstractString)
    dir = dirname(jl_path)
    base = basename(jl_path)
    prefix = base * "."
    out = String[]
    for f in readdir(dir)
        if f == base * ".cov"
            push!(out, joinpath(dir, f))
        elseif startswith(f, prefix) && endswith(f, ".cov")
            mid = chop(f; head = length(prefix), tail = 4)
            !isempty(mid) && all(isdigit, mid) && push!(out, joinpath(dir, f))
        end
    end
    return sort!(out)
end

function merge_cov(cov_paths::Vector{String})
    tracked = Bool[]
    hits = Int64[]
    for p in cov_paths
        lines = readlines(p)
        if length(lines) > length(tracked)
            old_len = length(tracked)
            resize!(tracked, length(lines))
            resize!(hits, length(lines))
            tracked[(old_len + 1):end] .= false
            hits[(old_len + 1):end] .= 0
        end
        for (i, line) in enumerate(lines)
            m = match(r"^\s*(-|\d+)(?:\s|$)", line)
            m === nothing && continue
            tok = m.captures[1]
            tok == "-" && continue
            tracked[i] = true
            hits[i] += parse(Int64, tok)
        end
    end
    n_tracked = count(tracked)
    n_covered = count(i -> tracked[i] && hits[i] > 0, eachindex(tracked))
    return n_covered, n_tracked
end

function collect_package(root::AbstractString, rel_dirs::Vector{String})
    covered, tracked = 0, 0
    files_cov, files_total = 0, 0
    for rel in rel_dirs
        d = joinpath(root, rel)
        isdir(d) || continue
        for (cur, _, fs) in walkdir(d), f in fs
            endswith(f, ".jl") || continue
            files_total += 1
            covs = find_cov_files(joinpath(cur, f))
            isempty(covs) && continue
            files_cov += 1
            c, t = merge_cov(covs)
            covered += c
            tracked += t
        end
    end
    return (; covered, tracked, files_cov, files_total)
end

function clean_cov(root::AbstractString)
    removed = 0
    for rel in ("src", "ext", "lib", "test")
        d = joinpath(root, rel)
        isdir(d) || continue
        for (cur, _, fs) in walkdir(d), f in fs
            endswith(f, ".cov") || continue
            rm(joinpath(cur, f); force = true)
            removed += 1
        end
    end
    return removed
end

fmt_pct(c::Int, t::Int) = t == 0 ? "-" : @sprintf("%.1f%%", 100.0 * c / t)

function main(args)
    clean = false
    root = abspath(joinpath(@__DIR__, "..", ".."))
    for a in args
        if a == "--clean"
            clean = true
        elseif startswith(a, "--root=")
            root = abspath(chop(a; head = 7, tail = 0))
        else
            error("Unknown argument: $a")
        end
    end

    rows = [(name, collect_package(root, dirs)) for (name, dirs) in PACKAGES]
    tot_cov = sum(r -> r[2].covered, rows)
    tot_trk = sum(r -> r[2].tracked, rows)
    tot_fcov = sum(r -> r[2].files_cov, rows)
    tot_ftot = sum(r -> r[2].files_total, rows)

    println("Code coverage summary (non-gating, CPU fast/compile suites):")
    println(@sprintf("  %-15s %9s %9s %8s  %s", "Package", "Covered", "Tracked", "Pct", "Files (.cov/.jl)"))
    for (name, s) in rows
        println(@sprintf("  %-15s %9d %9d %8s  %d/%d", name, s.covered, s.tracked, fmt_pct(s.covered, s.tracked), s.files_cov, s.files_total))
    end
    println(@sprintf("  %-15s %9d %9d %8s  %d/%d", "Total", tot_cov, tot_trk, fmt_pct(tot_cov, tot_trk), tot_fcov, tot_ftot))
    println("  Note: PottsModels and GPU are excluded from --code-coverage (PottsModels takes over 9000 s under coverage).")

    summary_path = get(ENV, "GITHUB_STEP_SUMMARY", "")
    if !isempty(summary_path)
        open(summary_path, "a") do io
            println(io, "### Code coverage (non-gating, CPU fast/compile suites)\n")
            println(io, "| Package | Covered | Tracked | Coverage | Files (`.cov`/`.jl`) |")
            println(io, "| --- | ---: | ---: | ---: | ---: |")
            for (name, s) in rows
                println(io, "| `$name` | $(s.covered) | $(s.tracked) | $(fmt_pct(s.covered, s.tracked)) | $(s.files_cov)/$(s.files_total) |")
            end
            println(io, "| **Total** | **$(tot_cov)** | **$(tot_trk)** | **$(fmt_pct(tot_cov, tot_trk))** | **$(tot_fcov)/$(tot_ftot)** |\n")
            println(io, "> `PottsModels` and `GPU` are excluded from `--code-coverage` (`PottsModels` exceeds 9000 s under coverage).")
        end
    end

    if clean
        n = clean_cov(root)
        println("Cleaned $n .cov file(s).")
    end
end

main(ARGS)
