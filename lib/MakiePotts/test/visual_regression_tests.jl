# Golden-free pixel property checks for MakiePotts.
# Replaces the old golden reference PNG with invariant visual properties and negative
# controls that reject blank, monochrome, and shifted images.

@testsetup module MP_visual
using Test
using CairoMakie
using MakiePotts
import Makie

CairoMakie.activate!(type = "png")
include("visual_reference_scene.jl")

function _rgb(pixel)
    c = Makie.RGBAf(pixel)
    return (Float64(c.r), Float64(c.g), Float64(c.b))
end

_is_white(rgb; tol = 1.0e-3) = all(x -> x >= 1.0 - tol, rgb)

function _distinct_chromatic_colors(img; sat_tol = 0.15, q = 16)
    colors = Set{NTuple{3, Int}}()
    for px in img
        r, g, b = _rgb(px)
        (max(r, g, b) - min(r, g, b)) > sat_tol || continue
        push!(colors, (round(Int, r * q), round(Int, g * q), round(Int, b * q)))
    end
    return length(colors)
end

function _border_uniform_white(img)
    h, w = size(img)
    (h >= 2 && w >= 2) || return false
    for x in 1:w
        (_is_white(_rgb(img[1, x])) && _is_white(_rgb(img[h, x]))) || return false
    end
    for y in 1:h
        (_is_white(_rgb(img[y, 1])) && _is_white(_rgb(img[y, w]))) || return false
    end
    return true
end

function _interior_nonblank_fraction(img)
    h, w = size(img)
    (h > 4 && w > 4) || return 0.0
    interior = @view img[3:(h - 2), 3:(w - 2)]
    return count(px -> !_is_white(_rgb(px)), interior) / length(interior)
end

function visual_properties_ok(img, expected_size; min_nonblank = 0.15, min_chromatic = 3)
    size(img) == expected_size || return false
    _border_uniform_white(img) || return false
    _interior_nonblank_fraction(img) >= min_nonblank || return false
    _distinct_chromatic_colors(img) >= min_chromatic || return false
    return true
end

export visual_reference_figure, visual_properties_ok, _rgb, _distinct_chromatic_colors,
    _border_uniform_white, _interior_nonblank_fraction
end

@testitem "visual properties (golden-free)" setup = [MP_visual] tags = [
    :makiepotts,
    :visual,
] begin
    using CairoMakie, MakiePotts
    import Makie
    @testset "visual properties (golden-free)" begin
        fig = visual_reference_figure()
        img = Makie.colorbuffer(fig; px_per_unit = 1)
        expected_size = (380, 920)

        @test size(img) == expected_size
        @test _border_uniform_white(img)
        @test _interior_nonblank_fraction(img) >= 0.15
        @test _distinct_chromatic_colors(img) >= 3
        @test visual_properties_ok(img, expected_size)

        # Zero stray outlines or margins on a boundary-free categorical plot
        dims = (20, 20)
        owners = fill(RenderOwner(MediumSite, 1), dims)
        owners[3:9, 3:9] .= Ref(RenderOwner(CellSite, 1))
        owners[12:18, 12:18] .= Ref(RenderOwner(CellSite, 2))
        cells = [
            RenderCellMetadata(RenderCellIdentity(1, 0), 1),
            RenderCellMetadata(RenderCellIdentity(2, 0), 2),
        ]
        frame = PottsRenderFrame(0, owners, cells)
        clean_fig = Figure(size = (200, 200), figure_padding = 0, backgroundcolor = :white)
        ax = Axis(clean_fig[1, 1]; aspect = DataAspect())
        hidedecorations!(ax)
        hidespines!(ax)
        p1 = Makie.RGBf(0.2, 0.4, 0.8)
        p2 = Makie.RGBf(0.8, 0.3, 0.2)
        med = Makie.RGBf(0.1, 0.1, 0.1)
        pottsplot!(
            ax, frame; boundaries = false, medium_color = med,
            cell_colors = Dict(1 => p1, 2 => p2)
        )
        tightlimits!(ax)
        clean_img = Makie.colorbuffer(clean_fig; px_per_unit = 1)
        @test size(clean_img) == (200, 200)
        allowed = (_rgb(p1), _rgb(p2), _rgb(med))
        exact_frac = count(
            px -> any(a -> maximum(abs.(_rgb(px) .- a)) < 0.02, allowed),
            clean_img
        ) /
            length(clean_img)
        @test exact_frac >= 0.7
        @test all(px -> maximum(_rgb(px)) >= 0.08, clean_img)  # zero black outline pixels

        # Sensitivity negative controls: reject blank, monochrome, wrong-size, and shifted
        # images
        blank = fill(Makie.RGBAf(1, 1, 1, 1), expected_size...)
        @test !visual_properties_ok(blank, expected_size)

        monochrome = fill(Makie.RGBAf(0.4, 0.4, 0.4, 1), expected_size...)
        @test !visual_properties_ok(monochrome, expected_size)

        single_chromatic = fill(Makie.RGBAf(0.2, 0.6, 0.8, 1), expected_size...)
        @test !visual_properties_ok(single_chromatic, expected_size)

        shifted = circshift(img, (25, 40))
        @test !visual_properties_ok(shifted, expected_size)
        @test !visual_properties_ok(img[1:(end - 10), :], expected_size)
    end
end
