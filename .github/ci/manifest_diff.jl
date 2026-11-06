# Prints the packages whose version differs between two Manifests (CI dependency lock,
# D-272): `julia manifest_diff.jl <old> <new>`. Prints nothing when they agree.
using TOML

versions(path) = Dict(name => get(first(entries), "version", "stdlib")
                      for (name, entries) in TOML.parsefile(path)["deps"])

old, new = versions(ARGS[1]), versions(ARGS[2])
for name in sort!(collect(union(keys(old), keys(new))))
    a, b = get(old, name, "-"), get(new, name, "-")
    a == b || println(rpad(name, 32), a, " => ", b)
end
