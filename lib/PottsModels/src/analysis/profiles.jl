# Per-column profiles of a 2-D state and the areas under them.

"""
    column_tops([pred,] σ::AbstractMatrix) -> Vector{Int}

For each column `x` (σ's first index), the largest `y` (second index) whose site belongs to a
cell `c` (not the medium) with `pred(c)`; 0 if there is none. `pred` defaults to every
cell; pass, for example, `in(S)` for a set of cells `S`.
"""
column_tops(σ::AbstractMatrix) = column_tops(Returns(true), σ)
function column_tops(pred::F, σ::AbstractMatrix) where {F}
    tops = zeros(Int, size(σ, 1))
    for (k, x) in enumerate(axes(σ, 1))
        for y in reverse(axes(σ, 2))
            c = σ[x, y]
            if c != 0 && pred(c)
                tops[k] = y
                break
            end
        end
    end
    return tops
end

"""
    trapz(x, y)

The trapezoid rule `Σᵢ (x[i+1] − x[i])·(y[i+1] + y[i])/2`, as `numpy.trapz(y, x)` (note the
argument order: sample points first). Zero for fewer than two samples. The sum runs left to
right; NumPy sums pairwise, so for non-integer data the two can differ in the last bits.
"""
function trapz(x, y)
    x, y = collect(x), collect(y)
    length(x) == length(y) ||
        throw(ArgumentError("trapz: x and y have different lengths ($(length(x)) and $(length(y)))"))
    s = 0.0
    for i in 1:(length(x) - 1)
        s += (x[i + 1] - x[i]) * (y[i + 1] + y[i]) / 2
    end
    return s
end
