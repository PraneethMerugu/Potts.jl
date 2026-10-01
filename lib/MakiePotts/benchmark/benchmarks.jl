using BenchmarkTools
using MakiePotts
using TOML

function benchmark_frame(dims = (512, 512); cell_width = 16)
    owners = Array{RenderOwner}(undef, dims)
    cells_per_row = cld(dims[1], cell_width)
    identities = Dict{UInt32, CellIdentity}()
    cells = RenderCellMetadata[]
    for site in CartesianIndices(owners)
        x, y = Tuple(site)
        id = UInt32((x - 1) ÷ cell_width +
                    ((y - 1) ÷ cell_width) * cells_per_row + 1)
        owners[site] = RenderOwner(CellSite, id)
        if !haskey(identities, id)
            identity = CellIdentity(id, 0)
            identities[id] = identity
            push!(cells, RenderCellMetadata(identity, mod1(id, 6)))
        end
    end
    return PottsRenderFrame(0, owners, cells)
end

frame = benchmark_frame()

suite = BenchmarkGroup()
suite["encode"]["cell_type"] = @benchmarkable encode(
    $frame, CellTypeEncoding())
suite["encode"]["identity"] = @benchmarkable encode(
    $frame, CellIdentityEncoding())
suite["geometry"]["boundaries"] = @benchmarkable MakiePotts._boundary_segments(
    $frame)
suite["conformance"] = @benchmarkable render_frame_conformance($frame)

results = run(suite; verbose = true)
estimates = median(results)
display(estimates)

function _collect_report!(report, group, prefix = String[])
    for (name, value) in group
        path = [prefix; String(name)]
        if value isa BenchmarkGroup
            _collect_report!(report, value, path)
        else
            report[join(path, "/")] = Dict(
                "median_time_ns" => value.time,
                "gc_time_ns" => value.gctime,
                "memory_bytes" => value.memory,
                "allocations" => value.allocs,
            )
        end
    end
    return report
end

output = get(ENV, "MAKIEPOTTS_BENCHMARK_REPORT", "")
if !isempty(output)
    report = Dict(
        "schema_version" => "1.0.0",
        "frame_dimensions" => collect(frame_size(frame)),
        "operations" => _collect_report!(Dict{String, Any}(), estimates),
    )
    open(output, "w") do io
        TOML.print(io, report; sorted = true)
    end
    println("MakiePotts benchmark report written to $output")
end
