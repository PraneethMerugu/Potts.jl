using TOML

length(ARGS) == 2 || error("usage: compare.jl PRODUCTION ORACLE")
production = TOML.parsefile(ARGS[1])
oracle = TOML.parsefile(ARGS[2])
production["schema_version"] == oracle["schema_version"] ||
    error("oracle result schema mismatch")
production_results = production["results"]
oracle_results = oracle["results"]
Set(keys(production_results)) == Set(keys(oracle_results)) ||
    error("oracle feature coverage mismatch")
for id in sort!(collect(keys(oracle_results)))
    production_results[id] == oracle_results[id] ||
        error("oracle mismatch for $(id): production=$(repr(production_results[id])) oracle=$(repr(oracle_results[id]))")
end
println("Phase 15.C independent oracle: $(length(oracle_results)) exact rows passed")
