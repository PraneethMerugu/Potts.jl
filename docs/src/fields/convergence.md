# [Convergence](@id fields-convergence)

This page gives the observed order of each LatticePDE time stepper and spatial operator.
Each case solves a problem with a known or reference solution at three or four time
steps or grid sizes, and fits the slope of the error against the step on a log-log scale.

## How the orders are measured

- **Steppers.** The time error of a stepper is measured against a reference solution of
  the same discretized system by `Tsit5` at a tolerance of ``10^{-12}``. So the error
  holds no spatial part.
- **Operators.** The error of a steady problem is measured against its exact solution at
  the site centers. The linear system is solved by `LatticePCG` to a relative tolerance of
  ``10^{-12}``, or by a direct sparse solve for the nonsymmetric upwind case.
- **Norm.** Every error is the largest absolute error over all sites (the max norm).
- **Observed order.** The least-squares slope of ``\log(\text{error})`` against
  ``\log(\Delta t)`` or ``\log(h)``.

## Results

```@eval
using TOML, Markdown, LatticePDE
file = joinpath(pkgdir(LatticePDE), "..", "..", "docs", "src", "fields", "convergence.toml")
cases = TOML.parsefile(file)["case"]
steps(c) = join(string.(c["variable"] == "h" ? c["sizes"] : c["steps"]), ", ")
errs(c) = join(string.(round.(c["errors"]; sigdigits = 3)), ", ")
rows = map(cases) do c
    levels = c["variable"] == "h" ? "grid ``N`` = " : "``Δt`` = "
    order = round(c["observed_order"]; digits = 2)
    "| $(c["method"]) | $(c["problem"]) | $levels$(steps(c)) | $(errs(c)) | " *
        "$order | $(Int(c["expected_order"])) |"
end
Markdown.parse(
    "| Method | Problem | Levels | Max-norm error | Observed order | Expected order |\n" *
        "|---|---|---|---|---|---|\n" * join(rows, "\n")
)
```

The spatial cases use the spacing ``h = 1/N`` on the unit square.

```@example fconv
using TOML, LatticePDE, CairoMakie
file = joinpath(pkgdir(LatticePDE), "..", "..", "docs", "src", "fields", "convergence.toml")
cases = TOML.parsefile(file)["case"]
colors = Makie.wong_colors()[1:6]      # colorblind-safe (Okabe-Ito)
markers = [:circle, :rect, :utriangle, :diamond, :dtriangle, :star5]
panels = (
    ("solver", "Time steppers", "time step Δt", string),
    ("operator", "Spatial operators", "grid spacing h", h -> "1/$(round(Int, 1 / h))"),
)
fig = Figure(; size = (900, 560))
for (j, (kind, title, xlabel, fmt)) in enumerate(panels)
    sel = filter(c -> c["kind"] == kind, cases)
    ticks = sort(unique(reduce(vcat, [c["steps"] for c in sel])))  # the levels in the file
    lo, hi = extrema(reduce(vcat, [c["errors"] for c in sel]))
    decades = floor(Int, log10(lo) - 0.5):ceil(Int, log10(hi))   # room for the guide lines
    ax = Axis(
        fig[1, j]; xscale = log10, yscale = log10, title, xlabel,
        ylabel = "max-norm error", xticks = (ticks, fmt.(ticks)),
        yticks = (10.0 .^ decades, [rich("10", superscript("$e")) for e in decades])
    )
    for (i, c) in enumerate(sel)
        scatterlines!(
            ax, c["steps"], c["errors"]; color = colors[i], marker = markers[i],
            markersize = 10, linewidth = 2, label = c["method"]
        )
    end
    # reference slopes 1 and 2, starting at half the coarsest error of the first case
    for (p, style) in ((1, :dash), (2, :dot))
        x = sel[1]["steps"]
        y = 0.5 * sel[1]["errors"][1] .* (x ./ x[1]) .^ p
        lines!(ax, x, y; color = :gray40, linestyle = style, label = "slope $p")
    end
    Legend(
        fig[2, j], ax; framevisible = false, nbanks = 2, labelsize = 12,
        tellheight = true, tellwidth = false
    )
end
fig
```

## Regenerate the data

The table and the plot read the committed file `docs/src/fields/convergence.toml`. The docs
build runs no solver for this page. The LatticePDE convergence tests write the same cases,
and they fail when the file no longer agrees with what they compute (relative tolerance
``10^{-4}``). After a change that moves an error, run this command from the repository root
and commit the file:

```sh
julia --project=lib/LatticePDE/test -e 'using Pkg; Pkg.instantiate()'
julia --project=lib/LatticePDE/test lib/LatticePDE/test/write_convergence_data.jl
```

It takes about 80 s on the reference machine (Ryzen AI Max+ 395).
