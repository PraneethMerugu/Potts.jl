# Per-column profiles of a 2-D state and the areas under them.

"""
    column_tops([pred,] σ::AbstractMatrix) -> Vector{Int}

Return, for each column `x` (σ's first index), the largest `y` (second index) whose site
belongs to a cell `c` (not the medium) with `pred(c)`, or 0 if there is none.

# Arguments
- `pred`: a predicate on cell numbers. By default every cell; pass, for example, `in(S)`
  for a set of cells `S`.
- `σ::AbstractMatrix`: the ownership.

# Returns
- `Vector{Int}`: one top per column.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> σ = [0 1 1; 2 2 0; 0 0 0];

julia> column_tops(σ), column_tops(==(2), σ)
([3, 2, 0], [0, 2, 0])
```

See also [`trapezoid_integral`](@ref).
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
    trapezoid_integral(x, y) -> Float64

Return the trapezoid rule `Σᵢ (x[i+1] − x[i])·(y[i+1] + y[i])/2`, as `numpy.trapz(y, x)`.

The argument order is sample points first. The result is zero for fewer than two samples.
The sum runs left to right; NumPy sums pairwise, so for non-integer data the two can differ
in the last bits.

# Arguments
- `x`: the sample points.
- `y`: the values, as many as `x`. Throws an `ArgumentError` otherwise.

# Returns
- `Float64`: the integral.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> trapezoid_integral([0, 1, 3], [0, 2, 2])
5.0
```

See also [`column_tops`](@ref).
"""
function trapezoid_integral(x, y)
    x, y = collect(x), collect(y)
    length(x) == length(y) ||
        throw(ArgumentError("trapezoid_integral: x and y have different lengths \
            ($(length(x)) and $(length(y)))"))
    s = 0.0
    for i in 1:(length(x) - 1)
        s += (x[i + 1] - x[i]) * (y[i + 1] + y[i]) / 2
    end
    return s
end
