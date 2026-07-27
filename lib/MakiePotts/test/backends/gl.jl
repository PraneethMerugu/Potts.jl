using GLMakie
import Makie

include("common.jl")
using .MakiePottsBackendSmoke

GLMakie.activate!()
figure, _ = smoke_figure()
buffer = Makie.colorbuffer(figure)
size(buffer, 1) > 100 && size(buffer, 2) > 100 ||
    error("GLMakie produced an empty or undersized framebuffer")

GLMakie.closeall()
isempty(figure.scene.current_screens) ||
    all(screen -> !isopen(screen), figure.scene.current_screens) ||
    error("GLMakie screen remained open after closeall")

println("GLMakie backend smoke passed: $(size(buffer))")
