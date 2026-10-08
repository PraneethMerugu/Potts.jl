# Whether a state comes near the lattice edge (a domain guard for "unbounded" colonies).

"""
    near_edge(σ, margin) -> Bool

Whether some site of a cell (`σ ≠ 0`) lies within `margin` sites of the lattice edge: its
index `i_d ≤ margin` or `i_d ≥ size(σ, d) − margin + 1` on some axis `d`. `margin ≤ 0` is
never near. Works on device arrays too (one reduction per face).
"""
function near_edge(σ::AbstractArray, margin::Integer)
    margin <= 0 && return false
    for d in 1:ndims(σ)
        n = size(σ, d)
        k = min(Int(margin), n)
        any(!=(0), selectdim(σ, d, 1:k)) && return true
        any(!=(0), selectdim(σ, d, (n - k + 1):n)) && return true
    end
    return false
end
