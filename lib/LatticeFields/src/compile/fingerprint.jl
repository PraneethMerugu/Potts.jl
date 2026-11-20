# Fingerprint: SHA-1 of the semantic IR after pass 2 plus the storage layout,
# truncated to UInt64. Not hashed: the schedule, fusion, index strategy, hoisting, emission
# and the debug flag. The text names ops and keys, never codes or ids, so adding an op, a
# kernel class or a solver never changes an existing program's fingerprint and never bumps
# `IR_FORMAT`. Only a change of the text format itself bumps it.

const IR_FORMAT = 1

"""
The fingerprint source text: format version, compute type `T`, then the semantic program.
"""
function fingerprint_text(p::Program; T::Type = Float32, passes = SEMANTIC_PASSES)
    s = semantic(p; passes)
    return string(
        "LatticeFields IR format ", IR_FORMAT, "\nT=", T, "\n", sprint(print_program, s))
end

"""
`UInt64` fingerprint of program `p` (session- and Julia-version-independent).
"""
function fingerprint(p::Program; kw...)
    d = sha1(fingerprint_text(p; kw...))
    return reduce((h, x) -> (h << 8) | x, d[1:8]; init = UInt64(0))
end
