# Salted operator hashes (another build's hashes, in this process), for the canonical-order
# tests: `Base.hash(::typeof(op), h)` for the Potts operators `population`, `gather` and
# `value_at` and for `sin`, `cos` and `exp` returns the ordinary hash while `SALT[] == 0`,
# and a salted one inside `salted(f, ops, s)`. The methods are defined once per process, in
# `Main.SaltedHashes` (two definitions would replace each other), and every setup that needs
# them uses that module.
if !isdefined(Main, :SaltedHashes)
    Core.eval(Main, :(module SaltedHashes end))
    Base.include(Main.SaltedHashes, joinpath(@__DIR__, "salted_hashes_module.jl"))
end
using Main.SaltedHashes
