"""
    PottsModels.Analysis

Analysis of saved states and solutions: plain Julia that runs on σ arrays and
profiles after a simulation, never inside a Monte Carlo step.

- Peaks of a 1-D profile: [`find_peaks`](@ref), [`peak_prominences`](@ref),
  [`peak_widths`](@ref) (a port of SciPy 1.7's `scipy.signal` functions) and
  [`merge_peaks`](@ref).
- Profiles and areas: [`column_tops`](@ref), [`trapz`](@ref).
- Cell adjacency: [`cell_graph`](@ref), [`reachable`](@ref), [`components`](@ref),
  [`centroids`](@ref).
- Point clouds: [`concave_hull`](@ref) (the OpenVT benchmark's Graham scan + concaveman).

Indices are 1-based throughout; cell ids are the values of σ (0 is the medium).
"""
module Analysis

using Potts: Closed, Lattice, Periodic, VonNeumann, contact_graph, neighbors, relation

export find_peaks, peak_prominences, peak_widths, merge_peaks, column_tops, trapz, cell_graph, reachable,
    components, centroids
export concave_hull

include("peaks.jl")
include("profiles.jl")
include("graphs.jl")
include("concave_hull.jl")

end
