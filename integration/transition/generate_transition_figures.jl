#!/usr/bin/env julia

using SHA
using Statistics
using TOML

function parse_number(value)
    text = string(value)
    if occursin("//", text)
        parts = split(text, "//"; limit = 2)
        return Float64(parse(BigInt, parts[1]) // parse(BigInt, parts[2]))
    end
    text == "infinity" && return Inf
    return parse(Float64, text)
end

function maximum_current(record)
    currents = record["analysis"]["probability_currents"]
    isempty(currents) && return 0.0
    return maximum(abs(parse_number(item["current"])) for item in currents)
end

function maximum_drift(record)
    observable = get(record["analysis"], "observable", Dict{String, Any}())
    values = get(observable, "drift", String[])
    isempty(values) && return 0.0
    return maximum(abs(parse_number(value)) for value in values)
end

function svg_bar_chart(path, title, labels, series; y_label)
    width, height = 920, 520
    left, right, top, bottom = 90, 30, 55, 130
    plot_width = width - left - right
    plot_height = height - top - bottom
    maximum_value = maximum((value for (_, values) in series for value in values);
        init = 0.0)
    scale_max = maximum_value > 0 ? maximum_value * 1.1 : 1.0
    groups = length(labels)
    series_count = length(series)
    group_width = plot_width / max(groups, 1)
    bar_width = 0.72group_width / max(series_count, 1)
    colors = ("#36558f", "#e07a5f", "#3d9970", "#7d5ba6")
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width/2)\" y=\"30\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"20\">$title</text>")
        println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top+plot_height)\" stroke=\"#222\"/>")
        println(io, "<line x1=\"$left\" y1=\"$(top+plot_height)\" x2=\"$(left+plot_width)\" y2=\"$(top+plot_height)\" stroke=\"#222\"/>")
        println(io, "<text transform=\"translate(22 $(top+plot_height/2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">$y_label</text>")
        for tick in 0:4
            value = scale_max * tick / 4
            y = top + plot_height * (1 - tick / 4)
            println(io, "<line x1=\"$left\" y1=\"$y\" x2=\"$(left+plot_width)\" y2=\"$y\" stroke=\"#ddd\"/>")
            println(io, "<text x=\"$(left-8)\" y=\"$(y+4)\" text-anchor=\"end\" font-family=\"monospace\" font-size=\"11\">$(round(value; sigdigits=3))</text>")
        end
        for (group, label) in pairs(labels)
            center = left + (group - 0.5) * group_width
            for (series_index, (_, values)) in pairs(series)
                value = values[group]
                bar_height = plot_height * value / scale_max
                x = center - 0.36group_width + (series_index - 1) * bar_width
                y = top + plot_height - bar_height
                println(io, "<rect x=\"$x\" y=\"$y\" width=\"$(0.9bar_width)\" height=\"$bar_height\" fill=\"$(colors[series_index])\"><title>$label: $value</title></rect>")
            end
            println(io, "<text transform=\"translate($center $(top+plot_height+12)) rotate(35)\" text-anchor=\"start\" font-family=\"sans-serif\" font-size=\"11\">$label</text>")
        end
        for (index, (name, _)) in pairs(series)
            x = left + (index - 1) * 180
            println(io, "<rect x=\"$x\" y=\"$(height-28)\" width=\"14\" height=\"14\" fill=\"$(colors[index])\"/>")
            println(io, "<text x=\"$(x+20)\" y=\"$(height-16)\" font-family=\"sans-serif\" font-size=\"12\">$name</text>")
        end
        println(io, "</svg>")
    end
    return path
end

function pending_speed_fidelity(path)
    open(path, "w") do io
        print(io, """<svg xmlns="http://www.w3.org/2000/svg" width="920" height="300" viewBox="0 0 920 300">
<rect width="100%" height="100%" fill="white"/>
<text x="460" y="55" text-anchor="middle" font-family="sans-serif" font-size="20">transition-kernel speed–fidelity evidence</text>
<rect x="110" y="95" width="700" height="105" rx="8" fill="#f4f1de" stroke="#d6c98d"/>
<text x="460" y="135" text-anchor="middle" font-family="sans-serif" font-size="16">Pending registered realistic-scale real-hardware runs</text>
<text x="460" y="168" text-anchor="middle" font-family="sans-serif" font-size="13">No speed or fidelity equivalence claim is inferred from tiny-state matrices.</text>
<text x="460" y="235" text-anchor="middle" font-family="sans-serif" font-size="12">This explicit pending panel prevents absent performance evidence from appearing as a pass.</text>
</svg>
""")
    end
    return path
end

function realistic_speed_fidelity(path, realistic_directory, timing_directory)
    workloads = (
        "adhesion_volume_relaxation",
        "differential_adhesion_sorting",
        "single_cell_migration",
    )
    analysis_path = joinpath(realistic_directory, "algorithm-family-analysis.toml")
    all(isfile(joinpath(timing_directory, string(workload, "-", algorithm, ".toml")))
        for workload in workloads
        for algorithm in ("SequentialCPM", "CheckerboardSweepCPM")) &&
        isfile(analysis_path) || return (
            pending_speed_fidelity(path), Any[],
            "pending-registered-real-hardware-evidence")
    analysis = TOML.parsefile(analysis_path)
    points = Dict{String, Any}[]
    for workload in workloads
        sequential = TOML.parsefile(joinpath(
            timing_directory, string(workload, "-SequentialCPM.toml")))
        checkerboard = TOML.parsefile(joinpath(
            timing_directory, string(workload, "-CheckerboardSweepCPM.toml")))
        for record in (sequential, checkerboard)
            record["sampling"]["profile"] == "diagnostic" || error(
                "speed-fidelity timing records must use the diagnostic profile")
            record["sampling"]["replicas"] == 8 || error(
                "speed-fidelity timing records require exactly eight isolated replicas")
        end
        sequential_rate = median(getindex.(
            sequential["replica_primary_summaries"], "measured_mcs_per_second"))
        checkerboard_rate = median(getindex.(
            checkerboard["replica_primary_summaries"], "measured_mcs_per_second"))
        endpoints = filter(endpoint -> endpoint["workload"] == workload,
            analysis["endpoints"])
        push!(points, Dict(
            "workload" => workload,
            "checkerboard_to_sequential_median_throughput" =>
                checkerboard_rate / sequential_rate,
            "timing_replicas_per_algorithm" => 8,
            "equivalent_endpoints" => count(endpoint -> endpoint["passed"], endpoints),
            "registered_endpoints" => length(endpoints),
            "equivalent_endpoint_fraction" =>
                count(endpoint -> endpoint["passed"], endpoints) / length(endpoints)))
    end
    width, height = 920, 520
    left, right, top, bottom = 95, 35, 65, 90
    plot_width, plot_height = width - left - right, height - top - bottom
    logarithmic_speed = log2.(
        getindex.(points, "checkerboard_to_sequential_median_throughput"))
    x_min = floor(minimum(vcat(logarithmic_speed, [-1.0])))
    x_max = ceil(maximum(vcat(logarithmic_speed, [1.0])))
    x_max == x_min && (x_max = x_min + 1)
    colors = ("#36558f", "#e07a5f", "#3d9970")
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width/2)\" y=\"30\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"20\">transition-kernel CPU speed–fidelity evidence</text>")
        println(io, "<text x=\"$(width/2)\" y=\"50\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">Isolated eight-replica diagnostic timing; fidelity uses the registered 512-replica Holm-adjusted v4 battery</text>")
        println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top+plot_height)\" stroke=\"#222\"/>")
        println(io, "<line x1=\"$left\" y1=\"$(top+plot_height)\" x2=\"$(left+plot_width)\" y2=\"$(top+plot_height)\" stroke=\"#222\"/>")
        println(io, "<text x=\"$(left+plot_width/2)\" y=\"$(height-20)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">checkerboard / sequential median measured MCS/s</text>")
        println(io, "<text transform=\"translate(24 $(top+plot_height/2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">fraction of registered endpoints equivalent</text>")
        for value in 0:4
            fraction = value / 4
            y = top + plot_height * (1 - fraction)
            println(io, "<line x1=\"$left\" y1=\"$y\" x2=\"$(left+plot_width)\" y2=\"$y\" stroke=\"#ddd\"/>")
            println(io, "<text x=\"$(left-8)\" y=\"$(y+4)\" text-anchor=\"end\" font-family=\"monospace\" font-size=\"11\">$fraction</text>")
        end
        for exponent in Int(x_min):Int(x_max)
            x = left + plot_width * (exponent - x_min) / (x_max - x_min)
            println(io, "<line x1=\"$x\" y1=\"$top\" x2=\"$x\" y2=\"$(top+plot_height)\" stroke=\"$(exponent == 0 ? "#999" : "#eee")\"/>")
            println(io, "<text x=\"$x\" y=\"$(top+plot_height+18)\" text-anchor=\"middle\" font-family=\"monospace\" font-size=\"11\">$(2.0^exponent)x</text>")
        end
        for (index, point) in pairs(points)
            x = left + plot_width * (logarithmic_speed[index] - x_min) / (x_max - x_min)
            y = top + plot_height * (1 - point["equivalent_endpoint_fraction"])
            label = replace(point["workload"], '_' => ' ')
            println(io, "<circle cx=\"$x\" cy=\"$y\" r=\"8\" fill=\"$(colors[index])\"><title>$label: $(point["checkerboard_to_sequential_median_throughput"])x, $(point["equivalent_endpoints"])/$(point["registered_endpoints"]) endpoints</title></circle>")
            println(io, "<text x=\"$(x+11)\" y=\"$(y-10+18(index-1))\" font-family=\"sans-serif\" font-size=\"11\">$label</text>")
        end
        status = analysis["result"]["status"]
        println(io, "<text x=\"$(left+plot_width)\" y=\"$(top+15)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">family result: $status</text>")
        println(io, "</svg>")
    end
    return path, points, analysis["result"]["status"]
end

function generate(exact_directory, output_directory;
        realistic_directory = normpath(joinpath(exact_directory, "..", "realistic", "cpu")),
        timing_directory = normpath(joinpath(
            exact_directory, "..", "realistic", "diagnostic", "cpu-speed")))
    mkpath(output_directory)
    paths = sort(filter(path -> endswith(path, "checkerboard-normalized-mcs.toml"),
        readdir(exact_directory; join = true)))
    records = TOML.parsefile.(paths)
    labels = [replace(basename(path), "-checkerboard-normalized-mcs.toml" => "")
        for path in paths]
    sequential_records = [TOML.parsefile(replace(path,
        "checkerboard-normalized-mcs.toml" => "normalized-mcs.toml")) for path in paths]
    tv = [parse_number(record["comparison"]["maximum_total_variation"])
        for record in records]
    currents = maximum_current.(records)
    checkerboard_gaps = [parse_number(record["analysis"]["spectral_gap"])
        for record in records]
    sequential_gaps = [parse_number(record["analysis"]["spectral_gap"])
        for record in sequential_records]
    checkerboard_drift = maximum_drift.(records)
    sequential_drift = maximum_drift.(sequential_records)

    figures = String[]
    push!(figures, svg_bar_chart(joinpath(output_directory, "transition-difference.svg"),
        "Sequential–checkerboard transition difference", labels,
        [("maximum row TV", tv)]; y_label = "total variation"))
    push!(figures, svg_bar_chart(joinpath(output_directory, "probability-current.svg"),
        "Checkerboard stationary probability currents", labels,
        [("maximum |current|", currents)]; y_label = "probability current"))
    push!(figures, svg_bar_chart(joinpath(output_directory, "relaxation-gap.svg"),
        "Normalized-MCS spectral gaps", labels,
        [("sequential", sequential_gaps), ("checkerboard", checkerboard_gaps)];
        y_label = "spectral gap"))
    push!(figures, svg_bar_chart(joinpath(output_directory, "observable-drift.svg"),
        "Maximum one-MCS cell-count drift", labels,
        [("sequential", sequential_drift), ("checkerboard", checkerboard_drift)];
        y_label = "maximum absolute drift"))
    speed_path, speed_points, speed_status = realistic_speed_fidelity(
        joinpath(output_directory, "speed-fidelity.svg"),
        realistic_directory, timing_directory)
    push!(figures, speed_path)

    data = Dict{String, Any}(
        "schema_version" => "1.0.0",
        "source_evidence" => relpath(exact_directory, output_directory),
        "realistic_source_evidence" => relpath(realistic_directory, output_directory),
        "speed_timing_source_evidence" => relpath(timing_directory, output_directory),
        "fixtures" => [Dict(
            "id" => labels[index],
            "maximum_total_variation" => tv[index],
            "maximum_probability_current" => currents[index],
            "sequential_spectral_gap" => sequential_gaps[index],
            "checkerboard_spectral_gap" => checkerboard_gaps[index],
            "sequential_maximum_observable_drift" => sequential_drift[index],
            "checkerboard_maximum_observable_drift" => checkerboard_drift[index])
            for index in eachindex(labels)],
        "speed_fidelity_status" => speed_status,
        "speed_fidelity_points" => speed_points,
        "figures" => [Dict(
            "path" => basename(path),
            "sha256" => bytes2hex(open(SHA.sha256, path))) for path in figures])
    index_path = joinpath(output_directory, "index.toml")
    open(index_path, "w") do io
        TOML.print(io, data; sorted = true)
    end
    return figures, index_path
end

function main(args)
    root = normpath(joinpath(@__DIR__, "..", ".."))
    exact = length(args) >= 1 ? abspath(args[1]) :
        joinpath(root, "design", "evidence", "phase-13", "exact")
    output = length(args) >= 2 ? abspath(args[2]) :
        joinpath(root, "design", "evidence", "phase-13", "figures")
    realistic = length(args) >= 3 ? abspath(args[3]) :
        joinpath(root, "design", "evidence", "phase-13", "realistic", "cpu")
    timing = length(args) >= 4 ? abspath(args[4]) :
        joinpath(root, "design", "evidence", "phase-13", "realistic",
            "diagnostic", "cpu-speed")
    figures, index = generate(exact, output;
        realistic_directory = realistic, timing_directory = timing)
    println("wrote $(length(figures)) transition-kernel figures and $index")
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
