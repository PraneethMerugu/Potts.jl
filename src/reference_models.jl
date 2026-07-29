module ReferenceModels

using ..Authoring
import CorePotts

export chemotaxis_model, chemotaxis_problem, single_cell_biased_migration_problem
export differential_adhesion_model, differential_adhesion_problem
export monolayer_growth_model, monolayer_growth_problem
export elongation_driven_angiogenesis_model, elongation_driven_angiogenesis_problem
export single_cell_fluctuation_problem, droplet_problem
export merks2006_initial_labels, merks2006_composite,
       merks2006_native_composite, merks2006_ambiguity_profile,
       merks2006_observation_plan
export cnv2012_initial_state, cnv2012_composite,
       cnv2012_native_composite, cnv2012_ambiguity_profile,
       cnv2012_observation_plan

merks2006_ambiguity_profile(; kwargs...) =
    CorePotts.Merks2006AmbiguityProfile(; kwargs...)
merks2006_initial_labels(; kwargs...) =
    CorePotts.merks2006_initial_labels(; kwargs...)
merks2006_composite(args...; kwargs...) =
    CorePotts.merks2006_composite(args...; kwargs...)
merks2006_native_composite(args...; kwargs...) =
    CorePotts.merks2006_native_composite(args...; kwargs...)
merks2006_observation_plan(args...; kwargs...) =
    CorePotts.merks2006_observation_plan(args...; kwargs...)
cnv2012_ambiguity_profile(; kwargs...) =
    CorePotts.CNV2012AmbiguityProfile(; kwargs...)
cnv2012_initial_state(; kwargs...) =
    CorePotts.cnv2012_initial_state(; kwargs...)
cnv2012_composite(args...; kwargs...) =
    CorePotts.cnv2012_composite(args...; kwargs...)
cnv2012_native_composite(args...; kwargs...) =
    CorePotts.cnv2012_native_composite(args...; kwargs...)
cnv2012_observation_plan(args...; kwargs...) =
    CorePotts.cnv2012_observation_plan(args...; kwargs...)

function _ball_mask(shape::NTuple{N, <:Integer}, target_volume::Real) where {N}
    center = ntuple(axis -> (Int(shape[axis]) + 1) / 2, Val(N))
    radius = N == 2 ? sqrt(float(target_volume) / pi) :
             cbrt(float(target_volume) / (4pi / 3))
    return map(CartesianIndices(shape)) do site
        sum((Float64(site[axis]) - center[axis])^2 for axis in 1:N) <= radius^2
    end
end

function _gradient_values(shape::NTuple{N, <:Integer}, profile::Symbol;
        axis::Integer = 1, steepness::Real = 4) where {N}
    1 <= axis <= N || throw(ArgumentError("gradient axis lies outside the lattice"))
    profile in (:linear, :half_normal, :exponential) || throw(ArgumentError(
        "gradient profile must be :linear, :half_normal, or :exponential"))
    T = Float32
    extent = max(Int(shape[axis]) - 1, 1)
    values = Array{T, N}(undef, shape)
    rate = T(steepness)
    isfinite(rate) && rate > 0 || throw(ArgumentError(
        "gradient steepness must be finite and positive"))
    denominator = exp(rate) - one(T)
    for site in CartesianIndices(values)
        coordinate = T(site[axis] - 1) / T(extent)
        values[site] = profile === :linear ? coordinate :
                       profile === :half_normal ? exp(-T(0.5) * (rate * (one(T) - coordinate))^2) :
                       (exp(rate * coordinate) - one(T)) / denominator
    end
    return values
end

"""Reusable Level 1 single-cell chemotaxis model independent of realized field values."""
function chemotaxis_model(;
        sensitivity::Real = 4,
        target_volume::Real = 32, volume_strength::Real = 2,
        adhesion_to_medium::Real = 8,
        response::CorePotts.AbstractFieldResponse = CorePotts.LinearResponse(),
        mode::CorePotts.AbstractChemotaxisMode = CorePotts.ExtensionChemotaxis())
    medium = Medium(:Medium)
    cell = CellType(:MigratingCell)
    field = Field(:chemo_gradient;
        placement = CellCentered(), boundary = NoFlux(),
        interpolation = Multilinear())
    volume = Volume(
        cell => (target = target_volume, strength = volume_strength))
    contact_energy = PairwiseLaw(:contact_energy,
        (medium, medium) => 0,
        (medium, cell) => adhesion_to_medium,
        (cell, cell) => 0)
    adhesion = Adhesion(contact_energy)
    drive = Chemotaxis(field, cell => sensitivity; response, mode)
    return PottsModel(medium, cell, volume, adhesion, field, drive)
end

function _chemotaxis_field_binding(model::PottsModel,
        shape::NTuple{N, <:Integer}, profile::Symbol) where {N}
    field = only(value for value in model.declarations if value isa Field)
    return field => _gradient_values(shape, profile)
end

"""Construct an executable fixed-gradient chemotaxis reference problem."""
function chemotaxis_problem(shape::NTuple{N, <:Integer} = ntuple(_ -> 48, 2);
        profile::Symbol = :linear, target_volume::Real = 32,
        capacity::Integer = 4, tspan = (0, 20), seed::Integer = 0,
        kwargs...) where {N}
    model = chemotaxis_model(; target_volume, kwargs...)
    cell = only(value for value in model.declarations if value isa CellType)
    layout = Layout(Place(cell, _ball_mask(shape, target_volume); identity = 1))
    domain = CartesianDomain(shape)
    return PottsProblem(model, domain, layout;
        fields = (_chemotaxis_field_binding(model, shape, profile),),
        capacity, tspan, seed)
end

single_cell_biased_migration_problem(args...; kwargs...) =
    chemotaxis_problem(args...; profile = :linear, kwargs...)

"""Reusable two-population differential-adhesion Level 1 model."""
function differential_adhesion_model(;
        target_volume::Real = 20, volume_strength::Real = 2,
        within_a::Real = 2, within_b::Real = 2, between::Real = 15,
        medium_contact::Real = 8)
    medium = Medium(:Medium)
    first_population = CellType(:PopulationA)
    second_population = CellType(:PopulationB)
    volume = Volume(
        first_population => (target = target_volume, strength = volume_strength),
        second_population => (target = target_volume, strength = volume_strength))
    contact_energy = PairwiseLaw(:contact_energy,
        (medium, medium) => 0,
        (medium, first_population) => medium_contact,
        (medium, second_population) => medium_contact,
        (first_population, first_population) => within_a,
        (second_population, second_population) => within_b,
        (first_population, second_population) => between)
    adhesion = Adhesion(contact_energy)
    return PottsModel(medium, first_population, second_population, volume, adhesion)
end

function _maximin_seed_centers(shape::NTuple{N, <:Integer}, count::Integer) where {N}
    count > 0 || throw(ArgumentError("a sorting problem requires finite cells"))
    candidates = collect(CartesianIndices(shape))
    count <= length(candidates) || throw(ArgumentError(
        "the requested initial cell count exceeds the lattice site count"))
    centers = CartesianIndex{N}[CartesianIndex(ntuple(axis -> cld(shape[axis], 2), Val(N)))]
    while length(centers) < count
        best = nothing
        best_distance = -1
        for candidate in candidates
            candidate in centers && continue
            distance = minimum(sum((candidate[axis] - center[axis])^2
                for axis in 1:N) for center in centers)
            if distance > best_distance
                best = candidate
                best_distance = distance
            end
        end
        push!(centers, best::CartesianIndex{N})
    end
    return centers
end

function _seed_label_layout(shape::NTuple{N, <:Integer}, count::Integer,
        target_volume::Real, cell_type_at) where {N}
    sites_per_cell = round(Int, target_volume)
    sites_per_cell > 0 || throw(ArgumentError(
        "initial target volume must round to at least one lattice site"))
    count * sites_per_cell <= prod(shape) || throw(ArgumentError(
        "the requested cells and target volume exceed lattice capacity"))
    centers = _maximin_seed_centers(shape, count)
    regions = [CartesianIndex{N}[] for _ in 1:count]
    for site in CartesianIndices(shape)
        owner = argmin(Tuple(sum((site[axis] - center[axis])^2
            for axis in 1:N) for center in centers))
        push!(regions[owner], site)
    end
    labels = zeros(UInt64, shape)
    declarations = Pair{UInt64, CellType}[]
    for index in 1:count
        center = centers[index]
        sort!(regions[index]; by = site -> (
            sum((site[axis] - center[axis])^2 for axis in 1:N), Tuple(site)))
        length(regions[index]) >= sites_per_cell || throw(ArgumentError(
            "lattice is too small to place every connected target-volume seed"))
        for site in @view regions[index][1:sites_per_cell]
            labels[site] = UInt64(index)
        end
        push!(declarations, UInt64(index) => cell_type_at(index))
    end
    return LabelledCells(labels, declarations)
end

function _mixed_seed_labels(shape::NTuple{N, <:Integer}, count::Integer,
        target_volume::Real, first_population::CellType,
        second_population::CellType) where {N}
    return _seed_label_layout(shape, count, target_volume,
        index -> isodd(index) ? first_population : second_population)
end

"""Construct a deterministic mixed two-population differential-adhesion problem."""
function differential_adhesion_problem(shape::NTuple{N, <:Integer} = ntuple(_ -> 32, 2);
        cells_per_population::Integer = 8, target_volume::Real = 20,
        capacity::Integer = 64,
        tspan = (0, 50), seed::Integer = 0, kwargs...) where {N}
    cells_per_population > 0 || throw(ArgumentError(
        "cells_per_population must be positive"))
    model = differential_adhesion_model(; target_volume, kwargs...)
    populations = Tuple(value for value in model.declarations if value isa CellType)
    layout = _mixed_seed_labels(
        shape, 2cells_per_population, target_volume, populations...)
    capacity >= 2cells_per_population || throw(ArgumentError(
        "cell capacity must contain every initial sorting cell"))
    return PottsProblem(model, CartesianDomain(shape), Layout(layout);
        capacity, tspan, seed)
end

"""Reusable growth/division/repulsion model for a one-cell monolayer seed."""
function monolayer_growth_model(;
        target_volume::Real = 8, division_target::Real = 16,
        volume_strength::Real = 2, growth_rate::Real = 1,
        cell_repulsion::Real = 10, medium_contact::Real = 4)
    division_target > target_volume || throw(ArgumentError(
        "division_target must exceed the initial target volume"))
    medium = Medium(:Medium)
    cell = CellType(:MonolayerCell)
    volume = Volume(
        cell => (target = target_volume, strength = volume_strength))
    contact_energy = PairwiseLaw(:contact_energy,
        (medium, medium) => 0,
        (medium, cell) => medium_contact,
        (cell, cell) => cell_repulsion)
    adhesion = Adhesion(contact_energy)
    growth = Growth(volume, cell; rate = growth_rate)
    division = Division(cell;
        geometry = RandomOrientationSplit(),
        trigger = PropertyAtLeast(:volume__target, Float32(division_target)))
    return PottsModel(medium, cell, volume, adhesion, growth, division)
end

"""Construct an executable growth/division/repulsion monolayer problem."""
function monolayer_growth_problem(shape::NTuple{N, <:Integer} = ntuple(_ -> 48, 2);
        target_volume::Real = 8, capacity::Integer = 128,
        tspan = (0, 50), seed::Integer = 0, kwargs...) where {N}
    model = monolayer_growth_model(; target_volume, kwargs...)
    cell = only(value for value in model.declarations if value isa CellType)
    layout = Layout(Place(cell, _ball_mask(shape, target_volume); identity = 1))
    return PottsProblem(model, CartesianDomain(shape), layout;
        capacity, tspan, seed)
end

"""
Reusable elongation-driven endothelial-network model.

The elongation term is the exact conservative major-axis RMS Hamiltonian. Connectivity is an
independent optional constraint: disabling it makes fragmentation valid model behavior.
"""
function elongation_driven_angiogenesis_model(;
        target_volume::Real = 16, volume_strength::Real = 2,
        target_elongation::Real = 3, elongation_strength::Real = 8,
        endothelial_contact::Real = 4, medium_contact::Real = 10,
        preserve_connectivity::Bool = true,
        target_division::CorePotts.AbstractDivisionPolicy = CloneOnDivision())
    medium = Medium(:Medium)
    endothelial = CellType(:EndothelialCell)
    volume = Volume(endothelial =>
        (target = target_volume, strength = volume_strength))
    elongation = Elongation(endothelial =>
        (target = target_elongation, strength = elongation_strength);
        target_division)
    contact_energy = PairwiseLaw(:contact_energy,
        (medium, medium) => 0,
        (medium, endothelial) => medium_contact,
        (endothelial, endothelial) => endothelial_contact)
    adhesion = Adhesion(contact_energy)
    declarations = preserve_connectivity ?
        (medium, endothelial, volume, elongation, adhesion, PreserveConnectivity()) :
        (medium, endothelial, volume, elongation, adhesion)
    return PottsModel(declarations...)
end

"""Construct a deterministic sparse endothelial seed problem in two or three dimensions."""
function elongation_driven_angiogenesis_problem(
        shape::NTuple{N, <:Integer} = ntuple(_ -> 48, 2);
        cells::Integer = 12, target_volume::Real = 16,
        capacity::Integer = 64,
        tspan = (0, 50), seed::Integer = 0, kwargs...) where {N}
    cells > 0 || throw(ArgumentError("an angiogenesis problem requires finite cells"))
    capacity >= cells || throw(ArgumentError(
        "cell capacity must contain every initial endothelial cell"))
    model = elongation_driven_angiogenesis_model(; target_volume, kwargs...)
    endothelial = only(value for value in model.declarations if value isa CellType)
    layout = _seed_label_layout(
        shape, cells, target_volume, _ -> endothelial)
    return PottsProblem(model, CartesianDomain(shape), Layout(layout);
        capacity, tspan, seed)
end

"""Modern fluctuating-volume reference used by thermodynamic verification."""
function single_cell_fluctuation_problem(shape::NTuple{N, <:Integer} = ntuple(_ -> 48, 2);
        target_volume::Real = 64, volume_strength::Real = 2, eta::Real = 1,
        capacity::Integer = 2, tspan = (0, 100), seed::Integer = 0) where {N}
    medium = Medium(:Medium)
    cell = CellType(:Cell)
    volume = FluctuatingVolumePressure(
        cell => (target = target_volume, strength = volume_strength);
        eta, noise = AcceptanceTemperature())
    model = PottsModel(medium, cell, volume)
    layout = Layout(Place(cell, _ball_mask(shape, target_volume); identity = 1))
    return PottsProblem(model, CartesianDomain(shape), layout;
        capacity, tspan, seed)
end

"""Modern 2D/3D fluctuating droplet with explicit contact energy."""
function droplet_problem(shape::NTuple{N, <:Integer} = ntuple(_ -> 64, 2);
        target_volume::Real = N == 2 ? 256 : 512,
        volume_strength::Real = 1, eta::Real = 0.1,
        contact_energy::Real = 10, capacity::Integer = 2,
        tspan = (0, 50), seed::Integer = 0) where {N}
    medium = Medium(:Medium)
    cell = CellType(:Droplet)
    volume = FluctuatingVolumePressure(
        cell => (target = target_volume, strength = volume_strength);
        eta, noise = AcceptanceTemperature())
    law = PairwiseLaw(:contact_energy,
        (medium, medium) => 0,
        (medium, cell) => contact_energy,
        (cell, cell) => 0)
    adhesion = Adhesion(law)
    model = PottsModel(medium, cell, volume, adhesion)
    layout = Layout(Place(cell, _ball_mask(shape, target_volume); identity = 1))
    return PottsProblem(model, CartesianDomain(shape), layout;
        capacity, tspan, seed)
end

end
