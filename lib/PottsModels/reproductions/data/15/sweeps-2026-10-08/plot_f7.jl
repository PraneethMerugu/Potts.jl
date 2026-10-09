# M Fig 7 layout ("Monolayer of 10K cells: β = 0, varying γ thresholds"; spec 15 §4.0.2 F7) from
# this record's f7/ (O5): one row of five square panels, γ = 0, γ = 10⁻⁴ and the three T1 γ
# thresholds (5×, 10×, 20×), each replicate 1 at its stop, labelled "γ=<value>, T=<MCS/775, 2 dp>".
# Consortium style (D-185; spec §4.0.2 F7): cells coloured by state from the `inhibited` flag,
# in the colours of M's Fig 7 (the TST row): growing RGB(44,123,182), inhibited RGB(253,174,97),
# with thin black cell boundaries, as every framework panel draws them.
# fig7.png: M's form, each cell a filled disc of radius radius_i at its centroid (R), with a
# thin black stroke.
# fig7_cells.png (when P615G_WORK holds the runner's serialized states): the same five final
# states as lattice stills (`PottsModels.openvt_colony_panel!(ax, frame; colour = :state)`),
# inhibited = inhibition code i > 0 at the panel's β = 0 and γ, white medium, thin black
# pixel-edge boundaries between unlike ids.
#     [P615G_OUT=<record dir>] [P615G_WORK=~/potts-ci/p6-15g-run] \
#         julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/sweeps-2026-10-08/plot_f7.jl
using CairoMakie, Serialization
using Potts, PottsModels, MakiePotts

const DIR = abspath(expanduser(get(ENV, "P615G_OUT", @__DIR__)))
const WORK = abspath(expanduser(get(ENV, "P615G_WORK", "")))
blue, orange = RGBf(44 / 255, 123 / 255, 182 / 255), RGBf(253 / 255, 174 / 255, 97 / 255)   # M Fig 7 (TST row)

# the panels, in γ order: (γ, MCS, file)
files = filter(f -> endswith(f, ".csv"), readdir(joinpath(DIR, "f7")))
panels = sort([(parse(Float64, m[1]), parse(Int, m[2]), f)
               for f in files for m in (match(r"^Potts\.jl_gamma_(.+)_(\d+)MCS\.csv$", f),) if m !== nothing])
length(panels) == 5 || @warn "expected five Fig 7 panels" panels
label(γ, mcs) = "γ=$(γ == 0 ? "0" : string(γ)), T=$(round(mcs / 775; digits = 2))"

mm = 72 / 25.4
s = 2.2
fig = Figure(; size = (5 * 40mm * s, 52mm * s), fontsize = 8 * s, backgroundcolor = :white)
for (j, (γ, mcs, f)) in enumerate(panels)
    o = read_openvt(joinpath(DIR, "f7", f), :O5)
    ax = Axis(fig[1, j]; aspect = 1, title = label(γ, mcs), titlesize = 8 * s, backgroundcolor = :white)
    hidedecorations!(ax); hidespines!(ax)
    cx, cy = sum(o.x_pos) / length(o.x_pos), sum(o.y_pos) / length(o.y_pos)
    ext = maximum(max(abs(x - cx), abs(y - cy)) for (x, y) in zip(o.x_pos, o.y_pos)) + 3
    for (flag, col) in ((0, blue), (1, orange))
        k = o.inhibited .== flag
        any(k) || continue
        scatter!(ax, o.x_pos[k], o.y_pos[k]; markersize = 2 .* o.radius_i[k], markerspace = :data, color = col,
            strokewidth = 0.25, strokecolor = :black)
    end
    limits!(ax, cx - ext, cx + ext, cy - ext, cy + ext)
    # the panel's statistics in their own row below the axes, clear of the colony
    Label(fig[2, j], "N = $(length(o.x_pos)), inhibited $(round(100 * sum(o.inhibited) / length(o.inhibited); digits = 1)) %";
        fontsize = 6.5 * s, color = (:black, 0.7), tellwidth = false, padding = (0, 0, 0, 4 * s))
end
rowgap!(fig.layout, 1, 6 * s)
Legend(fig[3, 1:5], [MarkerElement(; marker = :circle, color = c, strokewidth = 0.5, strokecolor = :black, markersize = 8 * s)
                     for c in (blue, orange)],
    ["growing (i = 0)", "inhibited (i > 0)"]; orientation = :horizontal, framevisible = false, labelsize = 7 * s)
save(joinpath(DIR, "fig7.png"), fig; px_per_unit = 1)
println("fig7.png ", filesize(joinpath(DIR, "fig7.png")))

# lattice stills, coloured by state with pixel-edge boundaries (D-185)
states = isempty(WORK) ? "" : joinpath(WORK, "states")
if isdir(states)
    runs = split.(readlines(joinpath(DIR, "runs.tsv")), '\t')
    head = runs[1]
    col(r, n) = r[findfirst(==(n), head)]
    function statefile(γ, mcs)
        sw, q = γ == 0 ? ("beta", 0) : ("gamma", round(Int, γ * 10_000))
        r = only(r for r in runs[2:end] if col(r, "sweep") == sw && col(r, "q") == string(q) && col(r, "k") == "1")
        parse(Int, col(r, "mcs")) == mcs || error("state of $(sw) $(q) does not match the record")
        return joinpath(states, "$(sw)_$(q)_1.jls")
    end
    cfig = Figure(; size = (5 * 40mm * s, 44mm * s), fontsize = 8 * s, backgroundcolor = :white)
    for (j, (γ, mcs, _)) in enumerate(panels)
        u = deserialize(statefile(γ, mcs))
        σ = Array(u.σ)
        frame = renderframe(u; mcs)
        ax = Axis(cfig[1, j]; aspect = DataAspect(), title = label(γ, mcs), titlesize = 8 * s, backgroundcolor = :white)
        hidedecorations!(ax); hidespines!(ax)
        live = findall(>(0), Array(u.cell.volume))
        code = PottsModels.openvt_frame(u; β = 0.0, γ).i
        PottsModels.openvt_colony_panel!(ax, frame; colour = :state, inhibited = Dict(c => code[j] > 0 for (j, c) in enumerate(live)),
            linewidth = 0.2)
        occ = findall(!=(0), σ)
        lo, hi = minimum(occ), maximum(occ)
        c = ((lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2)
        h = max(hi[1] - lo[1], hi[2] - lo[2]) / 2 + 10
        limits!(ax, c[1] - h, c[1] + h, c[2] - h, c[2] + h)
    end
    save(joinpath(DIR, "fig7_cells.png"), cfig; px_per_unit = 1.5)
    println("fig7_cells.png ", filesize(joinpath(DIR, "fig7_cells.png")))
end
