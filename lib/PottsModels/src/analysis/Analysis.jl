"""
    PottsModels.Analysis

Analysis of saved states and solutions: plain Julia that runs on σ arrays and
profiles after a simulation, never inside a Monte Carlo step.

- Peaks of a 1-D profile: [`find_peaks`](@ref), [`peak_prominences`](@ref),
  [`peak_widths`](@ref) (a port of SciPy 1.7's `scipy.signal` functions) and
  [`merge_peaks`](@ref).
- Profiles and areas: [`column_tops`](@ref), [`trapezoid_integral`](@ref).
- Cell adjacency: [`cell_graph`](@ref), [`reachable`](@ref), [`components`](@ref),
  [`centroids`](@ref) (with periodic axes).
- Chains and relaxation curves: [`chain_centroids`](@ref), [`chain_width`](@ref),
  [`crossing_time`](@ref), [`relaxation_mse`](@ref).
- Point clouds: [`concave_hull`](@ref) (the OpenVT benchmark's Graham scan + concaveman).
- Edge guard: [`near_edge`](@ref).
- Foam observables (Jiang et al. 1999): [`stored_energy`](@ref) (φ, Eq. 8),
  [`side_counts`](@ref), [`topology_distribution`](@ref), [`central_moment`](@ref),
  [`topology_moments`](@ref), T1 detection with [`contact_changes`](@ref) and
  [`t1_events`](@ref), spectra with [`power_spectrum`](@ref) (Eq. 9) and
  [`spectral_exponent`](@ref), [`mean_t1`](@ref) (N̄) and [`yield_strain`](@ref).
- Motility (Fortuna et al. 2020): [`unwrap_track`](@ref),
  [`mean_squared_displacement`](@ref), the modified Fürth model
  [`furth_mean_squared_displacement`](@ref), its fits [`furth_fit`](@ref) and
  [`natural_units`](@ref).
- Skeletons of 2D masks: [`skeletonize`](@ref), [`skeleton_graph`](@ref) and
  [`skeleton_counts`](@ref) (tips, junctions, branches, loops).
- Clusters: percolation with [`spanning_cluster`](@ref) and [`percolates`](@ref), and the
  graph of a pairwise predicate [`pair_graph`](@ref) (clusters by [`components`](@ref)).
- Sprouts: [`sprout_length`](@ref), [`width_profile`](@ref), [`sprout_thickness`](@ref).
- Lineage trees from birth records: [`lineage`](@ref), [`clone_sizes`](@ref).
- Polarization (Thomas et al. 2022): the MSD slope [`furth_exponent`](@ref), its maximum
  [`optimal_interval`](@ref), the fit-free [`max_slope_interval`](@ref),
  [`mean_velocity`](@ref) and [`polarization_statistics`](@ref) (ξ, ε, σθ, u_∥).

Indices are 1-based throughout; cell numbers are the values of σ (0 is the medium).
"""
module Analysis

using FFTW: R2HC, r2r
using LinearAlgebra: qr
using Potts: Closed, Lattice, NeighborOrder, Periodic, VonNeumann, contact_graph,
    contact_neighbors, relation

export find_peaks, peak_prominences, peak_widths, merge_peaks, column_tops,
    trapezoid_integral, cell_graph, reachable,
    components, centroids, chain_centroids, chain_width, crossing_time, relaxation_mse,
    near_edge
export concave_hull
export stored_energy, side_counts, contact_changes, t1_events, topology_distribution,
    central_moment,
    topology_moments, power_spectrum, spectral_exponent, mean_t1, yield_strain
export unwrap_track, mean_squared_displacement, furth_mean_squared_displacement, furth_fit,
    natural_units
export furth_exponent, optimal_interval, max_slope_interval, mean_velocity,
    polarization_statistics
export skeletonize, skeleton_graph, skeleton_counts
export spanning_cluster, percolates, pair_graph
export sprout_length, width_profile, sprout_thickness
export lineage, clone_sizes

include("peaks.jl")
include("profiles.jl")
include("graphs.jl")
include("chains.jl")
include("concave_hull.jl")
include("edges.jl")
include("foam.jl")
include("motility.jl")
include("polarization.jl")
include("skeleton.jl")
include("clusters.jl")
include("sprouts.jl")
include("lineage.jl")

end
