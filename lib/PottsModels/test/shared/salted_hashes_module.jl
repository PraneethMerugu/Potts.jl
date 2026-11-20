# The body of `Main.SaltedHashes` (see salted_hashes.jl).
using Potts
export SALT, SALTED, POTTS_OPS, BASE_OPS, salted
const SALT = Ref{UInt}(0)
const SALTED = Ref{Tuple}(())
const POTTS_OPS = (Potts.population, Potts.gather, Potts.value_at)
const BASE_OPS = (sin, cos, exp)
for f in (POTTS_OPS..., BASE_OPS...)
    @eval function Base.hash(g::typeof($f), h::UInt)
        (SALT[] == 0 || !any(x -> x === g, SALTED[])) &&
            return invoke(hash, Tuple{Function, UInt}, g, h)
        return hash(SALT[], hash(:canonical_salt, h))
    end
end
"""Run `f()` with the hashes of `ops` salted by `s` (0: the ordinary hashes)."""
function salted(f, ops, s)
    SALTED[] = ops
    SALT[] = s
    try
        return f()
    finally
        SALT[] = 0
        SALTED[] = ()
    end
end
