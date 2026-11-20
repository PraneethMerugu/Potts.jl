# Definitions of exec_tests.jl that other test files use.

# The Schedule contract (lp/c5 `schedule/contract.jl`): linear `body(s, S, P, G)` guarded by
# `s <= G.n`, Cartesian `body(x, S, P, G)` guarding each axis, tuple ndranges
# s ≤ G.n ≤ length
lin_body(s, S, P, G) = (@inbounds S[1][s] = P[1] * s; nothing)
function cart_body(x, S, P, G)
    (x[1] <= G.dims[1] && x[2] <= G.dims[2]) || return nothing
    s = x[1] + (x[2] - 1) * G.dims[1]
    # s ≤ prod(dims)
    @inbounds S[1][s] = P[1] * s
    return nothing
end
