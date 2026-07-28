module RenderGalleryAssets

using Printf
using SHA
using TOML
import CorePotts

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const EXAMPLE_ROOT = joinpath(@__DIR__, "examples")
const OUTPUT_ROOT = joinpath(ROOT, "docs", "src", "assets", "gallery")
const COMMAND =
    "julia --project=docs --startup-file=no docs/models/render_gallery_assets.jl"
const CELL_PALETTE = (
    "#5b8ff9", "#f6bd16", "#5ad8a6", "#e8684a",
    "#9270ca", "#6dc8ec", "#ff9d4d", "#269a99",
    "#945fb9", "#6f5ef9", "#5d7092", "#ed64a6",
)

function load_example(filename)
    sandbox = Module(gensym(:GalleryExample))
    Base.include(sandbox, joinpath(EXAMPLE_ROOT, filename))
    return Core.eval(sandbox, :result)
end

function escape_xml(value)
    replace(string(value),
        '&' => "&amp;", '<' => "&lt;", '>' => "&gt;", '"' => "&quot;")
end

function plot_svg(title, subtitle, values;
        ylabel, color = "#5b8ff9", animated = false)
    samples = Float64.(collect(values))
    isempty(samples) && error("a gallery plot requires data")
    width, height = 640, 360
    left, right, top, bottom = 72, 28, 72, 62
    plot_width = width - left - right
    plot_height = height - top - bottom
    minimum_value, maximum_value = extrema(samples)
    padding = maximum_value == minimum_value ? max(abs(maximum_value) * 0.1, 1.0) :
              0.1 * (maximum_value - minimum_value)
    lower = minimum_value >= 0 ? max(0.0, minimum_value - padding) :
            minimum_value - padding
    upper = maximum_value + padding
    upper == lower && (upper = lower + 1)
    x_at(index) = left + (length(samples) == 1 ? plot_width / 2 :
                   (index - 1) * plot_width / (length(samples) - 1))
    y_at(value) = top + (upper - value) * plot_height / (upper - lower)
    points = [(x_at(index), y_at(value)) for (index, value) in enumerate(samples)]
    point_text = join((@sprintf("%.2f,%.2f", point...) for point in points), " ")
    x_values = join((@sprintf("%.2f", point[1]) for point in points), ";")
    y_values = join((@sprintf("%.2f", point[2]) for point in points), ";")
    tick_values = if all(isinteger, samples) && upper - lower <= 8
        collect(floor(Int, lower):ceil(Int, upper))
    else
        collect(range(lower, upper; length = 5))
    end
    ticks = join([
        """<text x="$(left - 12)" y="$(@sprintf("%.2f", y_at(value) + 5))"
        text-anchor="end" class="tick">$(escape_xml(round(value; digits=2)))</text>"""
        for value in tick_values
    ], "\n")
    motion = animated && length(points) > 1 ?
        """<circle cx="$(points[1][1])" cy="$(points[1][2])" r="7"
          fill="#f6bd16" stroke="#17243b" stroke-width="2">
        <animate attributeName="cx" values="$x_values" dur="3s"
          repeatCount="indefinite"/>
        <animate attributeName="cy" values="$y_values" dur="3s"
          repeatCount="indefinite"/>
        </circle>""" : ""
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height"
      viewBox="0 0 $width $height" role="img"
      aria-labelledby="title description">
      <title id="title">$(escape_xml(title))</title>
      <desc id="description">$(escape_xml(subtitle))</desc>
      <style>
        .title { font: 700 24px system-ui, sans-serif; fill: #17243b; }
        .subtitle { font: 14px system-ui, sans-serif; fill: #52627a; }
        .axis { stroke: #738197; stroke-width: 1.5; }
        .grid { stroke: #dce2ea; stroke-width: 1; }
        .tick { font: 12px system-ui, sans-serif; fill: #52627a; }
        .label { font: 600 13px system-ui, sans-serif; fill: #344258; }
      </style>
      <rect width="100%" height="100%" rx="16" fill="#f7f9fc"/>
      <text x="$left" y="34" class="title">$(escape_xml(title))</text>
      <text x="$left" y="56" class="subtitle">$(escape_xml(subtitle))</text>
      $([join([
          """<line x1="$left" x2="$(width - right)"
          y1="$(@sprintf("%.2f", top + fraction * plot_height))"
          y2="$(@sprintf("%.2f", top + fraction * plot_height))" class="grid"/>"""
          for fraction in range(0, 1; length = 5)
      ], "\n")][1])
      <line x1="$left" x2="$left" y1="$top" y2="$(height - bottom)" class="axis"/>
      <line x1="$left" x2="$(width - right)" y1="$(height - bottom)"
        y2="$(height - bottom)" class="axis"/>
      $ticks
      <polyline points="$point_text" fill="none" stroke="$color"
        stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/>
$motion
      <text x="$(left + plot_width / 2)" y="$(height - 20)"
        text-anchor="middle" class="label">saved sample</text>
      <text x="20" y="$(top + plot_height / 2)" text-anchor="middle"
        transform="rotate(-90 20 $(top + plot_height / 2))"
        class="label">$(escape_xml(ylabel))</text>
    </svg>
    """
end

function frame_animation_css(frame_count)
    frame_count > 1 || return ""
    rules = String[]
    for index in 1:frame_count
        start = 100 * (index - 1) / frame_count
        stop = 100 * index / frame_count
        keyframes = if index == 1
            """
            @keyframes gallery-frame-$index {
              0%, $(@sprintf("%.3f", stop))% { opacity: 1; }
              $(@sprintf("%.3f", stop + 0.01))%, 100% { opacity: 0; }
            }
            """
        elseif index == frame_count
            """
            @keyframes gallery-frame-$index {
              0%, $(@sprintf("%.3f", start - 0.01))% { opacity: 0; }
              $(@sprintf("%.3f", start))%, 100% { opacity: 1; }
            }
            """
        else
            """
            @keyframes gallery-frame-$index {
              0%, $(@sprintf("%.3f", start - 0.01))% { opacity: 0; }
              $(@sprintf("%.3f", start))%, $(@sprintf("%.3f", stop))% { opacity: 1; }
              $(@sprintf("%.3f", stop + 0.01))%, 100% { opacity: 0; }
            }
            """
        end
        push!(rules, keyframes)
        push!(rules,
            ".frame-$index { animation: gallery-frame-$index 7.2s steps(1, end) infinite; }")
    end
    return """
    $(join(rules, "\n"))
    @media (prefers-reduced-motion: reduce) {
      .frame { animation: none !important; opacity: 0; }
      .frame-final { opacity: 1; }
    }
    """
end

function lattice_animation_svg(title, subtitle, solution, metric_values;
        metric_label, color_mode = :identity, field_gradient = false,
        interpretation)
    states = CorePotts.snapshot_state.(solution.u)
    times = collect(solution.t)
    metrics = Float64.(collect(metric_values))
    length(states) == length(times) == length(metrics) ||
        error("lattice animation state, time, and metric counts must agree")
    length(states) > 1 || error("lattice animation requires multiple frames")

    shape = CorePotts.lattice_size(first(states))
    length(shape) == 2 || error("gallery lattice animations currently require 2D states")
    width, height = 720, 400
    lattice_box = 264.0
    site_size = min(lattice_box / shape[1], lattice_box / shape[2])
    lattice_width = site_size * shape[1]
    lattice_height = site_size * shape[2]
    lattice_x = 48 + (lattice_box - lattice_width) / 2
    lattice_y = 88 + (lattice_box - lattice_height) / 2

    key_for(state, cell_id) = color_mode == :type ?
        string(CorePotts.cell_type(state, cell_id)) :
        color_mode == :single ? "finite cell" : string(cell_id)
    color_keys = sort!(unique([
        key_for(state, CorePotts.cell_id(owner))
        for state in states
        for site in CartesianIndices(CorePotts.lattice_size(state))
        for owner in (CorePotts.owner_at(state, site),)
        if CorePotts.is_cell_owner(owner)
    ]))
    colors = Dict(key => CELL_PALETTE[mod1(index, length(CELL_PALETTE))]
        for (index, key) in enumerate(color_keys))

    minimum_metric, maximum_metric = extrema(metrics)
    metric_padding = maximum_metric == minimum_metric ?
        max(abs(maximum_metric) * 0.1, 1.0) : 0.12 * (maximum_metric - minimum_metric)
    metric_lower = minimum_metric >= 0 ? max(0.0, minimum_metric - metric_padding) :
                   minimum_metric - metric_padding
    metric_upper = maximum_metric + metric_padding
    metric_upper == metric_lower && (metric_upper = metric_lower + 1)
    chart_left, chart_right = 398.0, 682.0
    chart_top, chart_bottom = 205.0, 312.0
    chart_x(index) = chart_left + (index - 1) * (chart_right - chart_left) /
                                  (length(metrics) - 1)
    chart_y(value) = chart_top + (metric_upper - value) *
                                 (chart_bottom - chart_top) /
                                 (metric_upper - metric_lower)
    metric_points = [(chart_x(index), chart_y(value))
                     for (index, value) in enumerate(metrics)]
    metric_polyline = join((@sprintf("%.2f,%.2f", point...) for point in metric_points), " ")

    frames = String[]
    for (frame_index, (state, time, metric)) in
            enumerate(zip(states, times, metrics))
        sites = String[]
        for site in CartesianIndices(shape)
            owner = CorePotts.owner_at(state, site)
            CorePotts.is_cell_owner(owner) || continue
            cell_id = CorePotts.cell_id(owner)
            color = colors[key_for(state, cell_id)]
            x = lattice_x + (site[1] - 1) * site_size
            y = lattice_y + (site[2] - 1) * site_size
            push!(sites,
                """<rect x="$(@sprintf("%.2f", x))" y="$(@sprintf("%.2f", y))"
                width="$(@sprintf("%.2f", site_size + 0.05))"
                height="$(@sprintf("%.2f", site_size + 0.05))"
                fill="$color" stroke="#ffffff" stroke-opacity="0.12"
                stroke-width="0.35"/>""")
        end
        metric_text = isinteger(metric) ?
            string(round(Int, metric)) : string(round(metric; digits = 2))
        final_class = frame_index == length(states) ? " frame-final" : ""
        point = metric_points[frame_index]
        push!(frames, """
        <g class="frame frame-$frame_index$final_class">
          $(join(sites, "\n"))
          <text x="$(lattice_x)" y="374" class="frame-label">
            MCS $(escape_xml(time))
          </text>
          <circle cx="$(@sprintf("%.2f", point[1]))"
            cy="$(@sprintf("%.2f", point[2]))" r="7"
            fill="#f6bd16" stroke="#17243b" stroke-width="2"/>
          <text x="$chart_left" y="350" class="metric-value">
            $(escape_xml(metric_label)): $(escape_xml(metric_text))
          </text>
        </g>
        """)
    end

    legend = if color_mode == :type
        join([
            """<g transform="translate($(398 + 118 * (index - 1)) 126)">
              <rect width="15" height="15" rx="3" fill="$(colors[key])"/>
              <text x="22" y="13" class="legend">population $index</text>
            </g>"""
            for (index, key) in enumerate(color_keys)
        ], "\n")
    elseif color_mode == :identity
        """<text x="398" y="137" class="legend">Color tracks durable cell identity</text>"""
    else
        """<text x="398" y="137" class="legend">Blue marks the finite cell</text>"""
    end

    lattice_background = field_gradient ?
        """<defs>
          <linearGradient id="field-gradient" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stop-color="#eef3fb"/>
            <stop offset="1" stop-color="#b8e4cf"/>
          </linearGradient>
        </defs>
        <rect x="$lattice_x" y="$lattice_y" width="$lattice_width"
          height="$lattice_height" fill="url(#field-gradient)"/>""" :
        """<rect x="$lattice_x" y="$lattice_y" width="$lattice_width"
          height="$lattice_height" fill="#e8edf4"/>"""
    gradient_label = field_gradient ?
        """<text x="$(lattice_x + lattice_width / 2)" y="78"
          text-anchor="middle" class="field-label">prescribed field increases →</text>""" : ""

    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height"
      viewBox="0 0 $width $height" role="img"
      aria-labelledby="title description">
      <title id="title">$(escape_xml(title))</title>
      <desc id="description">$(escape_xml(subtitle)).
        The animation pairs saved lattice states with $(escape_xml(metric_label));
        reduced-motion readers see the final frame.</desc>
      <style>
        .title { font: 700 24px system-ui, sans-serif; fill: #17243b; }
        .subtitle { font: 14px system-ui, sans-serif; fill: #52627a; }
        .section { font: 700 13px system-ui, sans-serif; fill: #344258;
          letter-spacing: .04em; text-transform: uppercase; }
        .legend, .field-label { font: 12px system-ui, sans-serif; fill: #52627a; }
        .frame-label, .metric-value {
          font: 650 13px system-ui, sans-serif; fill: #344258;
        }
        .axis { stroke: #738197; stroke-width: 1.5; }
        .grid { stroke: #dce2ea; stroke-width: 1; }
        .trace { fill: none; stroke: #5b8ff9; stroke-width: 4;
          stroke-linejoin: round; stroke-linecap: round; }
        .interpretation { font: 13px system-ui, sans-serif; fill: #52627a; }
        .frame { opacity: 0; }
        .frame-1 { opacity: 1; }
        $(frame_animation_css(length(states)))
      </style>
      <rect width="100%" height="100%" rx="16" fill="#f7f9fc"/>
      <text x="48" y="34" class="title">$(escape_xml(title))</text>
      <text x="48" y="56" class="subtitle">$(escape_xml(subtitle))</text>
      $lattice_background
$gradient_label
      <rect x="$lattice_x" y="$lattice_y" width="$lattice_width"
        height="$lattice_height" fill="none" stroke="#738197" stroke-width="1.5"/>
      <text x="398" y="96" class="section">What changes</text>
      <text x="398" y="116" class="interpretation">$(escape_xml(interpretation))</text>
      $legend
      <text x="398" y="180" class="section">Quantitative trace</text>
      <line x1="$chart_left" x2="$chart_left" y1="$chart_top"
        y2="$chart_bottom" class="axis"/>
      <line x1="$chart_left" x2="$chart_right" y1="$chart_bottom"
        y2="$chart_bottom" class="axis"/>
      <line x1="$chart_left" x2="$chart_right" y1="$chart_top"
        y2="$chart_top" class="grid"/>
      <line x1="$chart_left" x2="$chart_right"
        y1="$((chart_top + chart_bottom) / 2)"
        y2="$((chart_top + chart_bottom) / 2)" class="grid"/>
      <polyline points="$metric_polyline" class="trace"/>
      <text x="$(chart_left - 8)" y="$(chart_top + 5)"
        text-anchor="end" class="legend">$(round(metric_upper; digits=2))</text>
      <text x="$(chart_left - 8)" y="$(chart_bottom + 5)"
        text-anchor="end" class="legend">$(round(metric_lower; digits=2))</text>
      $(join(frames, "\n"))
    </svg>
    """
end

function write_asset(record, svg)
    path = joinpath(ROOT, record["path"])
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, strip(svg), '\n')
    end
    record["sha256"] = bytes2hex(sha256(read(path)))
    return record
end

function main()
    relaxation = load_example("relaxing_cell.jl")
    sorting = load_example("two_populations_sort.jl")
    migration = load_example("follow_the_gradient.jl")
    lifecycle = load_example("grow_divide_retire.jl")
    network = load_example("elongated_network.jl")
    droplet = load_example("fluctuating_droplet.jl")
    obstacles = load_example("boundaries_and_obstacles.jl")
    dimensional = load_example("same_model_2d_3d.jl")
    continuation = load_example("stop_and_resume.jl")
    ensemble = load_example("reproducible_ensemble.jl")

    specifications = [
        ("relaxing-cell", "relaxing_cell.jl", "static",
            "Relaxing Cell", "Absolute target-volume error over saved samples",
            relaxation.absolute_error, "absolute volume error", "#5b8ff9", false),
        ("two-populations-sort", "two_populations_sort.jl", "animation",
            "Two Populations Sort",
            "Saved lattice states and heterotypic contacts for two cell populations",
            sorting.contact_trace, "heterotypic contacts", "#5ad8a6", true),
        ("follow-the-gradient", "follow_the_gradient.jl", "animation",
            "Follow the Gradient",
            "Saved cell shapes and centroid motion along the positive field axis",
            migration.centroid_x, "centroid x", "#5b8ff9", true),
        ("grow-divide-retire", "grow_divide_retire.jl", "animation",
            "Grow, Divide, Retire",
            "Saved cell identities show division and scheduled retirement",
            lifecycle.cell_counts, "live cells", "#f6bd16", true),
        ("elongated-network", "elongated_network.jl", "animation",
            "Elongated Network",
            "Saved connected shapes and mean bounding-box elongation",
            network.elongation_trace,
            "mean elongation", "#e8684a", true),
        ("fluctuating-droplet", "fluctuating_droplet.jl", "static",
            "Fluctuating Droplet", "Realized droplet volume over saved samples",
            droplet.volume_trace, "volume", "#9270ca", false),
        ("boundaries-and-obstacles", "boundaries_and_obstacles.jl", "static",
            "Boundaries and Obstacles", "All declared obstacle owners remain immutable",
            [0, obstacles.obstacle_count], "verified obstacles", "#6dc8ec", false),
        ("same-model-2d-3d", "same_model_2d_3d.jl", "static",
            "Same Model in 2D and 3D", "Both dimension-specific problems complete the smoke",
            [solution.stats.completed_mcs for solution in dimensional.solutions],
            "completed MCS", "#5d7092", false),
        ("stop-and-resume", "stop_and_resume.jl", "static",
            "Stop and Resume", "Checkpoint and final continuation boundaries",
            [continuation.checkpoint.mcs, continuation.resumed_mcs],
            "MCS", "#269a99", false),
        ("reproducible-ensemble", "reproducible_ensemble.jl", "static",
            "Reproducible Ensemble", "Final volume for each semantic trajectory seed",
            ensemble.final_volumes, "final volume", "#ff9d4d", false),
    ]

    animation_svgs = Dict(
        "two-populations-sort" => lattice_animation_svg(
            "Two Populations Sort",
            "Actual lattice states paired with the heterotypic-contact statistic",
            sorting.solution, sorting.contact_trace;
            metric_label = "heterotypic contacts",
            color_mode = :type,
            interpretation = "Unlike contact is the sorting statistic"),
        "follow-the-gradient" => lattice_animation_svg(
            "Follow the Gradient",
            "Actual cell shape and centroid displacement in a prescribed field",
            migration.solution, migration.centroid_x;
            metric_label = "centroid x",
            color_mode = :single,
            field_gradient = true,
            interpretation = "The saved centroid advances along the field axis"),
        "grow-divide-retire" => lattice_animation_svg(
            "Grow, Divide, Retire",
            "Saved lattice states paired with the live finite-cell count",
            lifecycle.solution, lifecycle.cell_counts;
            metric_label = "live cells",
            color_mode = :identity,
            interpretation = "Daughters appear; one seed retires at MCS 4"),
        "elongated-network" => lattice_animation_svg(
            "Elongated Network",
            "Saved connected shapes paired with mean bounding-box elongation",
            network.solution, network.elongation_trace;
            metric_label = "mean elongation",
            color_mode = :identity,
            interpretation = "Cells elongate without fragmenting"),
    )

    records = Dict{String, Any}[]
    for (id, source, kind, title, subtitle, values, ylabel, color, animated) in
            specifications
        record = Dict{String, Any}(
            "id" => id,
            "path" => "docs/src/assets/gallery/$id.svg",
            "source" => "docs/models/examples/$source",
            "kind" => kind,
            "alt" => subtitle,
            "command" => COMMAND,
        )
        svg = haskey(animation_svgs, id) ? animation_svgs[id] :
              plot_svg(title, subtitle, values; ylabel, color, animated)
        push!(records, write_asset(record, svg))
    end

    manifest_path = joinpath(OUTPUT_ROOT, "manifest.toml")
    open(manifest_path, "w") do io
        TOML.print(io, Dict(
            "schema_version" => "1.0.0",
            "generator" => "docs/models/render_gallery_assets.jl",
            "command" => COMMAND,
            "assets" => records,
        ); sorted = true)
    end
    println("Rendered $(length(records)) gallery assets and manifest")
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    RenderGalleryAssets.main()
end
