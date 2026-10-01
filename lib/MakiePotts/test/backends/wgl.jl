using WGLMakie
import Makie

include("common.jl")
using .MakiePottsBackendSmoke

WGLMakie.activate!()
Makie.inline!(true)
figure, _ = smoke_figure()
io = IOBuffer()
show(io, MIME"text/html"(), figure)
payload = String(take!(io))
sizeof(payload) > 1_000 ||
    error("WGLMakie produced an empty or undersized HTML payload")
occursin("<", payload) ||
    error("WGLMakie payload does not contain serialized markup")

println("WGLMakie backend smoke passed: $(sizeof(payload)) bytes")
