"""
    PottsModels.Analysis

Analysis of saved states and solutions: plain Julia that runs on σ arrays and
profiles after a simulation, never inside a Monte Carlo step.

- Peaks of a 1-D profile: [`find_peaks`](@ref), [`peak_prominences`](@ref),
  [`peak_widths`](@ref) (a port of SciPy 1.7's `scipy.signal` functions) and
  [`merge_peaks`](@ref).
- Profiles and areas: [`column_tops`](@ref), [`trapz`](@ref).
- Cell adjacency: [`cell_graph`](@ref), [`reachable`](@ref), [`components`](@ref),
  [`centroids`](@ref) (with periodic axes).
- Chains and relaxation curves: [`chain_centroids`](@ref), [`chain_width`](@ref),
  [`crossing_time`](@ref), [`relaxation_mse`](@ref).
- Point clouds: [`concave_hull`](@ref) (the OpenVT benchmark's Graham scan + concaveman).
- Domain guard: [`near_edge`](@ref).
- Foam observables (reproduction 04, spec 04 §2.8): [`stored_energy`](@ref) (φ, Eq. 8),
  [`side_counts`](@ref), [`topology_distribution`](@ref), [`central_moment`](@ref),
  [`topology_moments`](@ref), T1 detection with [`contact_changes`](@ref) and
  [`t1_events`](@ref), spectra with [`power_spectrum`](@ref) (Eq. 9) and
  [`spectral_exponent`](@ref), [`mean_t1`](@ref) (N̄) and [`yield_strain`](@ref).

Indices are 1-based throughout; cell ids are the values of σ (0 is the medium).
"""
module Analysis

using Potts: Closed, Lattice, NeighborOrder, Periodic, VonNeumann, contact_graph, neighbors, relation

export find_peaks, peak_prominences, peak_widths, merge_peaks, column_tops, trapz, cell_graph, reachable,
    components, centroids, chain_centroids, chain_width, crossing_time, relaxation_mse, near_edge
export concave_hull
export stored_energy, side_counts, contact_changes, t1_events, topology_distribution, central_moment,
    topology_moments, power_spectrum, spectral_exponent, mean_t1, yield_strain

include("peaks.jl")
include("profiles.jl")
include("graphs.jl")
include("chains.jl")
include("concave_hull.jl")
include("edges.jl")
include("foam.jl")

end
