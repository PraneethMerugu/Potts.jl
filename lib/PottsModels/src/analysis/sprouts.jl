# Sprout length and thickness of a mask grown along an axis.

"""
    sprout_length(mask::AbstractArray{Bool}; axis = 1, from = 0) -> Int

Return how far the sites of `mask` reach along `axis` past the slice `from`.

The result is the largest index along `axis` of a set site minus `from`, or 0 when no set
site lies past `from`. With `from` the last slice of a tissue or of a wall, it is the
length of the longest sprout grown from it, in sites.

# Arguments
- `mask::AbstractArray{Bool}`: the sites of the sprouts.

# Keywords
- `axis::Integer = 1`: the growth axis.
- `from::Integer = 0`: the base slice.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> m = falses(10, 4); m[1:7, 2] .= true;

julia> sprout_length(m; from = 3)
4
```

See also [`sprout_thickness`](@ref), [`width_profile`](@ref).
"""
function sprout_length(mask::AbstractArray{Bool, N}; axis::Integer = 1, from::Integer = 0) where {N}
    1 <= axis <= N || throw(ArgumentError("sprout_length: `axis` must be in 1:$N, got $axis"))
    far = maximum((x[axis] for x in CartesianIndices(mask) if mask[x]); init = 0)
    return max(0, far - from)
end

"""
    width_profile(mask::AbstractMatrix{Bool}; axis = 1) -> Vector{Float64}

Return the mean sprout width in each slice of a 2D mask across `axis`.

Entry `k` is the mean length of the runs of set sites in slice `k` along `axis` (a row
for `axis = 1`), so two sprouts of widths 2 and 4 in one slice give 3. A slice with no set
site gives `NaN`.

# Arguments
- `mask::AbstractMatrix{Bool}`: the sites of the sprouts.

# Keywords
- `axis::Integer = 1`: the growth axis (1 or 2).

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> width_profile(Bool[1 1 0 1 1 1 1; 0 0 0 0 0 0 0])
2-element Vector{Float64}:
   3.0
 NaN
```

See also [`sprout_thickness`](@ref).
"""
function width_profile(mask::AbstractMatrix{Bool}; axis::Integer = 1)
    axis in (1, 2) || throw(ArgumentError("width_profile: `axis` must be 1 or 2, got $axis"))
    m = axis == 1 ? mask : permutedims(mask)
    out = fill(NaN, size(m, 1))
    for k in axes(m, 1)
        runs = total = 0
        prev = false
        for j in axes(m, 2)
            v = m[k, j]
            v && (total += 1)
            v && !prev && (runs += 1)
            prev = v
        end
        runs > 0 && (out[k] = total / runs)
    end
    return out
end

"""
    sprout_thickness(mask::AbstractMatrix{Bool}; axis = 1, slices = nothing) -> Float64

Return the mean sprout width of a 2D mask: the mean of [`width_profile`](@ref) over the
slices that hold a set site.

`slices` limits the mean to some slices, for example those past the base of the sprouts.
The result is `NaN` when no slice in range holds a set site.

# Arguments
- `mask::AbstractMatrix{Bool}`: the sites of the sprouts.

# Keywords
- `axis::Integer = 1`: the growth axis (1 or 2).
- `slices = nothing`: the slice indices to average over; `nothing` is all.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> m = falses(10, 8); m[1:6, 2:3] .= true; m[1:9, 6:8] .= true;

julia> sprout_thickness(m), sprout_thickness(m; slices = 7:10)
(2.6666666666666665, 3.0)
```

See also [`width_profile`](@ref), [`sprout_length`](@ref).
"""
function sprout_thickness(mask::AbstractMatrix{Bool}; axis::Integer = 1, slices = nothing)
    w = width_profile(mask; axis)
    v = filter(!isnan, slices === nothing ? w : w[slices])
    return isempty(v) ? NaN : sum(v) / length(v)
end
