using CairoMakie
using MakiePotts

CairoMakie.activate!(type = "png")

frame = PottsRenderFrame(
    0,
    fill(RenderOwner(MediumSite, 1), 2, 2),
    RenderCellMetadata[],
)
frame_size(frame) == (2, 2) ||
    error("MakiePotts clean frame exercise failed")

figure, axis, plot = CairoMakie.plot(frame; boundaries = true)
plot isa PottsPlot ||
    error("MakiePotts clean recipe exercise failed")
axis isa CairoMakie.Axis ||
    error("MakiePotts clean axis exercise failed")
potts_legend(figure[1, 2], plot)

buffer = CairoMakie.colorbuffer(figure)
size(buffer, 1) > 100 && size(buffer, 2) > 100 ||
    error("MakiePotts clean framebuffer exercise failed")

mktempdir() do directory
    output = joinpath(directory, "makiepotts-clean-install.png")
    CairoMakie.save(output, figure)
    filesize(output) > 1_000 ||
        error("MakiePotts clean PNG exercise failed")
end

println("MakiePotts clean install-to-PNG journey passed")
