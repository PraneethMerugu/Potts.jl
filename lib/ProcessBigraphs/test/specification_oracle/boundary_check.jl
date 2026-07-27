using TOML

const PACKAGE_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const ORACLE_ROOT = @__DIR__
const ORACLE_FILES = (
    "Oracle.jl",
    "oracle_driver.jl",
    "compare.jl",
    "runtests.jl",
)
const ALLOWED_ROOTS = Set(("Base", "Core", "Test", "TOML", "SHA"))

failures = String[]
for name in ORACLE_FILES
    source = read(joinpath(ORACLE_ROOT, name), String)
    occursin(r"(?m)^\s*(using|import)\s+ProcessBigraphs\b", source) &&
        push!(failures, "$(name) imports ProcessBigraphs")
    occursin(r"(?m)^\s*include\(.*src", source) &&
        push!(failures, "$(name) includes production source")
    for matched in eachmatch(r"(?m)^\s*(?:using|import)\s+([A-Za-z0-9_.]+)", source)
        root = first(split(matched.captures[1], '.'))
        root in ALLOWED_ROOTS ||
            startswith(matched.captures[1], ".") ||
            push!(failures, "$(name) imports disallowed root $(root)")
    end
end

for (directory, _, files) in walkdir(joinpath(PACKAGE_ROOT, "src"))
    for name in files
        endswith(name, ".jl") || continue
        source = read(joinpath(directory, name), String)
        occursin("specification_oracle", source) &&
            push!(failures, "production source depends on specification oracle: $(name)")
    end
end

ledger = TOML.parsefile(joinpath(ORACLE_ROOT, "derivations.toml"))
rules = ledger["rules"]
length(rules) == 22 ||
    push!(failures, "derivation ledger must contain exactly 22 rules")
ids = String[String(rule["id"]) for rule in rules]
length(ids) == length(unique(ids)) ||
    push!(failures, "derivation ledger contains duplicate rule ids")
required = Set((
    "id", "version", "source", "paper_section", "julia_decision",
    "truth_table", "fixture", "assertion", "limitation",
))
for rule in rules
    Set(keys(rule)) >= required ||
        push!(failures, "derivation rule $(rule["id"]) omits required fields")
end

isempty(failures) || error(join(failures, "\n"))
println("Phase 15.C oracle boundary: stdlib isolation and 22 derivations passed")
