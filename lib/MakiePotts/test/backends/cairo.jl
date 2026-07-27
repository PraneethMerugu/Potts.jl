using CairoMakie
import Makie

include("common.jl")
using .MakiePottsBackendSmoke

CairoMakie.activate!(type = "png")
figure, _ = smoke_figure()
buffer = CairoMakie.colorbuffer(figure)
size(buffer, 1) > 100 && size(buffer, 2) > 100 ||
    error("CairoMakie produced an empty or undersized framebuffer")

output = isempty(ARGS) ? tempname() * ".png" : only(ARGS)
Makie.save(output, figure)
isfile(output) && filesize(output) > 1_000 ||
    error("CairoMakie did not save a nonempty PNG")

println("CairoMakie backend smoke passed: $(size(buffer)), $(filesize(output)) bytes")
