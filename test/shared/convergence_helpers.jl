# Lightweight empirical convergence-order helpers for packages whose test
# Project.toml does not depend on `Statistics`.

"""
    observed_orders(hs, errs) -> Vector{Float64}

Pairwise empirical convergence orders `log(errs[i] / errs[i+1]) / log(hs[i] / hs[i+1])`.
"""
function observed_orders(hs::AbstractVector{<:Real}, errs::AbstractVector{<:Real})
    length(hs) == length(errs) || throw(DimensionMismatch("hs and errs must have equal length"))
    length(hs) >= 2 || throw(ArgumentError("at least 2 grid levels required"))
    return [
        log(Float64(errs[i]) / Float64(errs[i + 1])) / log(Float64(hs[i]) / Float64(hs[i + 1]))
            for i in 1:(length(hs) - 1)
    ]
end

"""
    observed_order(hs, errs) -> Float64

Least-squares log-log slope of `errs` against `hs`.
"""
function observed_order(hs::AbstractVector{<:Real}, errs::AbstractVector{<:Real})
    length(hs) == length(errs) || throw(DimensionMismatch("hs and errs must have equal length"))
    length(hs) >= 2 || throw(ArgumentError("at least 2 grid levels required"))
    lx = log.(Float64.(hs))
    ly = log.(Float64.(errs))
    mx = sum(lx) / length(lx)
    my = sum(ly) / length(ly)
    return sum((lx .- mx) .* (ly .- my)) / sum((lx .- mx) .^ 2)
end
