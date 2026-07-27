using CairoMakie
using FileIO
import Makie

CairoMakie.activate!(type = "png")
include("visual_reference_scene.jl")

const MATERIAL_CHANNEL_DELTA = 8 / 255
const MAX_CHANGED_FRACTION = 0.035
const MAX_MEAN_CHANNEL_ERROR = 0.006

function _rgba(pixel)
    color = Makie.RGBAf(pixel)
    return (Float64(color.r), Float64(color.g),
        Float64(color.b), Float64(color.alpha))
end

function comparison_metrics(expected, actual)
    size(expected) == size(actual) ||
        return (; same_size = false, changed_fraction = 1.0,
            mean_channel_error = Inf)
    changed = 0
    total_error = 0.0
    for index in eachindex(expected, actual)
        left = _rgba(expected[index])
        right = _rgba(actual[index])
        deltas = ntuple(channel -> abs(left[channel] - right[channel]), Val(4))
        maximum(deltas) > MATERIAL_CHANNEL_DELTA && (changed += 1)
        total_error += sum(deltas)
    end
    return (
        same_size = true,
        changed_fraction = changed / length(expected),
        mean_channel_error = total_error / (4length(expected)),
    )
end

comparison_passes(metrics) =
    metrics.same_size &&
    metrics.changed_fraction <= MAX_CHANGED_FRACTION &&
    metrics.mean_channel_error <= MAX_MEAN_CHANNEL_ERROR

function difference_image(expected, actual)
    size(expected) == size(actual) ||
        return fill(Makie.RGBAf(1, 0, 1, 1), size(actual))
    return map(expected, actual) do left_pixel, right_pixel
        left = _rgba(left_pixel)
        right = _rgba(right_pixel)
        deltas = ntuple(
            channel -> min(8abs(left[channel] - right[channel]), 1.0),
            Val(3))
        Makie.RGBAf(deltas..., 1)
    end
end

function sensitivity_check(actual)
    perturbed = copy(actual)
    affected_rows = max(1, cld(size(perturbed, 1), 10))
    for column in axes(perturbed, 2), row in 1:affected_rows
        perturbed[row, column] = Makie.RGBAf(1, 0, 1, 1)
    end
    comparison_passes(comparison_metrics(actual, perturbed)) &&
        error("visual-regression tolerances accepted a 10% image perturbation")
end

reference = joinpath(@__DIR__, "reference", "makiepotts-v02.png")
artifact_directory = get(ENV, "MAKIEPOTTS_VISUAL_ARTIFACT_DIR",
    joinpath(tempdir(), "makiepotts-visual-regression"))
mkpath(artifact_directory)
actual_path = joinpath(artifact_directory, "actual.png")
expected_path = joinpath(artifact_directory, "expected.png")
difference_path = joinpath(artifact_directory, "difference.png")

figure = visual_reference_figure()
save(actual_path, figure; px_per_unit = 1)
actual = FileIO.load(actual_path)
sensitivity_check(actual)

if get(ENV, "MAKIEPOTTS_ACCEPT_VISUAL_REFERENCE", "false") == "true"
    mkpath(dirname(reference))
    cp(actual_path, reference; force = true)
    println("Accepted MakiePotts visual reference at $reference")
    exit()
end

isfile(reference) || error(
    "visual reference is missing; maintainers must explicitly set " *
    "MAKIEPOTTS_ACCEPT_VISUAL_REFERENCE=true to create it")
cp(reference, expected_path; force = true)
expected = FileIO.load(reference)
metrics = comparison_metrics(expected, actual)
FileIO.save(difference_path, difference_image(expected, actual))

comparison_passes(metrics) || error(
    "MakiePotts visual regression failed: " *
    "same_size=$(metrics.same_size), " *
    "changed_fraction=$(round(metrics.changed_fraction; digits = 6)) " *
    "(limit $MAX_CHANGED_FRACTION), " *
    "mean_channel_error=$(round(metrics.mean_channel_error; digits = 6)) " *
    "(limit $MAX_MEAN_CHANNEL_ERROR); " *
    "expected/actual/difference evidence is in $artifact_directory")

println(
    "MakiePotts visual regression passed: " *
    "changed_fraction=$(round(metrics.changed_fraction; digits = 6)), " *
    "mean_channel_error=$(round(metrics.mean_channel_error; digits = 6))")
