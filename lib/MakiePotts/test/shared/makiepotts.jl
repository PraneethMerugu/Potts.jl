# Definitions of makiepotts_tests.jl that other test files use (moved here by TS1b).
using Test
using Aqua
using CairoMakie
using MakiePotts
using Random
import Makie
import CorePotts

include(joinpath(dirname(dirname(@__DIR__)), "dev", "ci_telemetry.jl"))
using .CITelemetry: record_duration

include("../downstream_fixture.jl")
include("../allocation_fixture.jl")

const MAKIEPOTTS_TEST_FILES = Set((
    "test_adversarial_tests.jl",
    "test_allocations_tests.jl",
    "test_downstream_conformance_tests.jl",
    "test_saved_state_channels_tests.jl",
))

function render_fixture(; dimensions = 2)
    dims = dimensions == 2 ? (5, 4) : (5, 4, 3)
    labels = zeros(Int, dims)
    if dimensions == 2
        fill!(view(labels, 2:3, 2:3), 1)
        fill!(view(labels, 4:5, 2:3), 2)
    else
        fill!(view(labels, 2:3, 2:3, 2), 1)
        fill!(view(labels, 4:5, 2:3, 2), 2)
    end
    kinds = [1, 2]
    lattice = CorePotts.Lattice(dims)
    temperature(st, p, prop, ctx) = p.T
    energy(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> (v - 4.0)^2)
    f = CorePotts.CPMFunction(energy; temperature)
    problem = CorePotts.PottsProblem(f, CorePotts.initial_state(labels, kinds), lattice, (0, 0),
        (; T = 2.0); seed = 1)
    state = dimensions == 2 ?
            only(CorePotts.solve(problem, CorePotts.SequentialCPM()).u) :
            CorePotts.initial_state(labels, kinds)
    return (; state, problem)
end

# P6.0j: ExplicitImports guardrails (CLAUDE.md code rules). Every name MakiePotts uses is
# imported explicitly and by its owner. The allowlist names each non-public access the
# package genuinely needs; add to it only by review, with the reason.
using ExplicitImports: ExplicitImports, check_no_implicit_imports, check_all_explicit_imports_are_public,
    check_no_stale_explicit_imports, check_all_qualified_accesses_via_owners, check_all_qualified_accesses_are_public

const MAKIEPOTTS_NONPUBLIC_QUALIFIED = (
    # Makie's recipe interface: methods a recipe package extends, not declared public by Makie
    :plottype,                   # default plot type for `plot(::PottsSavedState)`
    :preferred_axis_type,        # axis choice for the recipe
    :preferred_axis_attributes,  # axis attributes for the recipe
    :automatic,                  # Makie's `automatic` attribute sentinel
    :apply_transform_and_model,  # `boundingbox` of the recipe: data limits through the plot transform
    :extract_colormap,           # extended so colorbars read the child plot colormap
    :RefValue,                   # Base.RefValue: concrete `Ref` type for type-stable fields
)
