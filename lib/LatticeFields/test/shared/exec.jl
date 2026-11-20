# Definitions of exec_tests.jl that other test files use.

# The Schedule contract (lp/c5 `schedule/contract.jl`): linear `body(s, S, P, G)` guarded by
# `s <= G.n`, Cartesian `body(x, S, P, G)` guarding each axis, tuple ndranges
lin_body(s, S, P, G) = (@inbounds S[1][s] = P[1] * s; nothing)                     # s ≤ G.n ≤ length
function cart_body(x, S, P, G)
    (x[1] <= G.dims[1] && x[2] <= G.dims[2]) || return nothing
    s = x[1] + (x[2] - 1) * G.dims[1]
    @inbounds S[1][s] = P[1] * s                                                     # s ≤ prod(dims)
    return nothing
end
