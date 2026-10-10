# The OpenVT growing-monolayer benchmark's analysis (spec 15 §3, D-147, D-149): a port of
# the consortium's `metrics.cpp`, the inhibition fractions (A3) and the O1–O6 files.
#
# Floating point: the metrics are summed in metrics.cpp's order with plain `*`, `+`, `-`,
# `/` (no fused or reassociated arithmetic; spec D11), so the output lines are the
# reference build's (`-ffp-contract=off`) byte for byte.

const _OPENVT_METRICS = (:N, :r, :A, :C, :w, :g, :C_rel, :w_rel)

"""
    openvt_metrics(path::AbstractString)
    openvt_metrics(x, y, g)

The OpenVT monolayer metrics of one saved colony, as the consortium's `metrics.cpp`
computes them: a `NamedTuple` `(; N, r, A, C, w, g, C_rel, w_rel)`, all `Float64` except
the cell count `N`.

The boundary is [`Analysis.concave_hull`](@ref PottsModels.Analysis.concave_hull) of the
cell centroids `(x, y)` with concavity 1.5. With `B` boundary vertices, `B > 2`:

- `r`: the mean distance of the vertices from their mean `c`;
- `A`: the area enclosed (shoelace formula);
- `C`: the perimeter of the closed boundary;
- `w`: ``\\sqrt{\\sum (|v - c| - r)^2 / (B - 1)}``, the spread of the vertex radii;

and `r`, `A`, `C`, `w` are `NaN` for `B ≤ 2` (fewer than three cells, or collinear ones).
`g` is the fraction of growing cells (`Σg/N`, `g` a 0/1 flag per cell),
`C_rel = C/(2√(πA))` and `w_rel = w/r`.

The file method reads a headed CSV as `metrics.cpp` does: the header is split on `,` and
`"` and `'` are removed from the names; the columns `x`, `y` and `g` are found by name (the
last one of each name; other columns are ignored), and empty lines are skipped. A field is
read as C++'s `std::stod`/`std::stoi` read it: leading spaces are skipped and the longest
numeric prefix is taken, so `1.5abc` reads as 1.5 and a `g` of `1.0` as 1. CRLF line ends
are accepted (`metrics.cpp` would keep the `\r` in the last header name). A file without
`g` but with an `i` column (an O1 file, see [`write_openvt`](@ref)) takes `g = (i == 0)`
(spec C8). A missing `x` or `y`, neither `g` nor `i`, a data row with too few fields, or a
field that is not a number or overflows `Float64` (where `std::stod` throws) is an
`ArgumentError`. Unlike `metrics.cpp`, an `n` column is not required. No cells (an empty
file or empty vectors) and, in the vector method, a non-integer `g` are `ArgumentError`s.

The sums run in `metrics.cpp`'s order with no fused multiply-adds, and the boundary is
[`Analysis.concave_hull`](@ref PottsModels.Analysis.concave_hull)'s. The output of
[`openvt_metrics_line`](@ref) is identical to `metrics.cpp -ffp-contract=off` on the 25
OpenVT parameter-plane colonies and on fuzzed clouds without ties. It departs from the
reference on purpose where the reference's boundary depends on luck: its Graham order for
points collinear with the pivot (spec defect D12), and its R-tree pruning next to
near-parallel edges (D13). In both, this boundary is the correct hull. Exact ties between
hull candidates are broken differently from the C++ R-tree, and everything is `Float64`:
the reference is the arm64 build, where `long double` is `double`.

See also [`openvt_neighbor_histogram`](@ref) for `metrics.cpp`'s third output.
"""
function openvt_metrics(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, g::AbstractVector{<:Real})
    length(x) == length(y) == length(g) ||
        throw(DimensionMismatch("openvt_metrics: x, y and g have lengths $(length(x)), $(length(y)) and $(length(g))"))
    N = length(x)
    N > 0 || throw(ArgumentError("openvt_metrics: no cells"))
    b = Analysis.concave_hull(zip(x, y); concavity = 1.5)
    B = length(b)
    r = A = C = w = NaN
    if B > 2
        cx = 0.0
        cy = 0.0
        for p in b
            cx += p[1]
            cy += p[2]
        end
        cx /= B
        cy /= B
        r = 0.0
        A = 0.0
        C = 0.0
        w = 0.0
        i = B
        for j in 1:B
            dx, dy = b[i][1] - cx, b[i][2] - cy
            r += sqrt(dx * dx + dy * dy)
            A += b[i][1] * b[j][2] - b[i][2] * b[j][1]
            ex, ey = b[i][1] - b[j][1], b[i][2] - b[j][2]
            C += sqrt(ex * ex + ey * ey)
            i = j
        end
        r /= B
        A = abs(A) / 2
        for p in b
            dx, dy = p[1] - cx, p[2] - cy
            thisr = sqrt(dx * dx + dy * dy)
            w += (thisr - r) * (thisr - r)
        end
        w = sqrt(w / (B - 1))
    end
    ng = 0
    for v in g
        isinteger(v) || throw(ArgumentError("openvt_metrics: g must hold integers (0/1 flags), got $v"))
        ng += Int(v)
    end
    gfrac = ng / N
    return NamedTuple{_OPENVT_METRICS}((N, r, A, C, w, gfrac, C / (2 * sqrt(pi * A)), w / r))
end

function openvt_metrics(path::AbstractString)
    names, rows = _cpp_csv(path)
    col(s) = findlast(==(s), names)
    xi, yi, gi, ii = col("x"), col("y"), col("g"), col("i")
    xi === nothing && throw(ArgumentError("openvt_metrics: $path: missing column x"))
    yi === nothing && throw(ArgumentError("openvt_metrics: $path: missing column y"))
    gi === nothing && ii === nothing && throw(ArgumentError("openvt_metrics: $path: missing column g (or i)"))
    last = max(xi, yi, something(gi, ii))
    for (k, row) in enumerate(rows)
        length(row) >= last || throw(ArgumentError("openvt_metrics: $path: ill-formatted data row $k"))
    end
    x = [_stod(row[xi], "x") for row in rows]
    y = [_stod(row[yi], "y") for row in rows]
    g = gi === nothing ? [Int(_stoi(row[ii]) == 0) for row in rows] : [_stoi(row[gi]) for row in rows]
    return openvt_metrics(x, y, g)
end

"""
    openvt_metrics_line(m) -> String

The line `metrics.cpp` prints for the metrics `m` of [`openvt_metrics`](@ref):
`N,r,A,C,w,g,C_rel,w_rel` and a newline, each value as C++'s `ostream <<` writes it (C's
`%g`, six significant digits; `NaN` as `nan`).
"""
openvt_metrics_line(m::NamedTuple) = join((_cpp_g(m[k]) for k in _OPENVT_METRICS), ',') * "\n"

"""
    openvt_neighbor_histogram(n) -> (; n, p)

The neighbour-number distribution `metrics.cpp` writes: for `n = 0:maximum(n)` (as a
`Vector{Int}`), the percentage `p = (100·count)/N` of the `N` cells with that many
neighbours, computed in that order. Write it with `write_openvt(dest, :O6_neighbors, h)`.
No cells or a negative neighbour count is an `ArgumentError`.
"""
function openvt_neighbor_histogram(n::AbstractVector{<:Integer})
    isempty(n) && throw(ArgumentError("openvt_neighbor_histogram: no cells"))
    any(<(0), n) && throw(ArgumentError("openvt_neighbor_histogram: negative neighbour count"))
    nmax = Int(maximum(n; init = 0))
    counts = zeros(Int, nmax + 1)
    for k in n
        counts[k + 1] += 1
    end
    N = length(n)
    return (n = collect(0:nmax), p = [100 * Float64(c) / N for c in counts])
end

"""
    openvt_inhibition_code(a, f; β, γ) -> Int

The benchmark's per-cell inhibition code (the `i` of an O1 file): 0 growing, 1 inhibited by
type 1 only, 2 by type 2 only, 3 by both. Type 1 (area) inhibits a cell with relative area
`a` unless `a ≥ β`; type 2 (free surface) inhibits a cell with free-surface fraction `f`
unless `f ≥ γ`. The comparisons are the benchmark text's `≥` (spec C9), so `a = β` grows.
"""
openvt_inhibition_code(a::Real, f::Real; β::Real, γ::Real) = (a >= β ? 0 : 1) + (f >= γ ? 0 : 2)

"""
    openvt_inhibition_fractions(i) -> (; uninhibited, type1, type2, both)

The shares of the inhibition codes 0, 1, 2 and 3 (see [`openvt_inhibition_code`](@ref))
among the cells of one save (spec A3). A code outside `0:3`, or no cells, is an
`ArgumentError`.
"""
function openvt_inhibition_fractions(i::AbstractVector{<:Integer})
    isempty(i) && throw(ArgumentError("openvt_inhibition_fractions: no cells"))
    counts = zeros(Int, 4)
    for c in i
        0 <= c <= 3 || throw(ArgumentError("openvt_inhibition_fractions: inhibition code $c is not in 0:3"))
        counts[c + 1] += 1
    end
    N = length(i)
    return (uninhibited = counts[1] / N, type1 = counts[2] / N, type2 = counts[3] / N, both = counts[4] / N)
end

# ── C++ reading and printing ───────────────────────────────────────────────────────────────

# std::getline(is, field, ','): a trailing separator adds no empty field
function _cpp_split(line::AbstractString)
    fields = split(line, ',')
    length(fields) > 1 && isempty(fields[end]) && pop!(fields)
    return fields
end

function _cpp_csv(path::AbstractString)
    lines = readlines(path)
    isempty(lines) && return String[], Vector{SubString{String}}[]
    names = [replace(s, '"' => "", '\'' => "") for s in _cpp_split(lines[1])]
    rows = [_cpp_split(l) for l in lines[2:end] if !isempty(l)]
    return names, rows
end

# std::stod / std::stoi: leading space, the longest numeric prefix; std::stod throws
# std::out_of_range on overflow
function _stod(s::AbstractString, name::AbstractString)
    v = tryparse(Float64, s)
    if v === nothing
        m = match(r"^\s*[+-]?(?:inf(?:inity)?|nan|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)"i, s)
        m === nothing && throw(ArgumentError("openvt_metrics: column $name: not a number: \"$s\""))
        v = parse(Float64, strip(m.match))
    end
    isinf(v) && !occursin(r"inf"i, s) &&
        throw(ArgumentError("openvt_metrics: column $name: \"$s\" overflows Float64"))
    return v
end

function _stoi(s::AbstractString)
    m = match(r"^\s*[+-]?\d+", s)
    m === nothing && throw(ArgumentError("openvt_metrics: not an integer: \"$s\""))
    return parse(Int, strip(m.match))
end

# C++ `ostream << double` (C `%g`, precision 6)
_cpp_g(x::Integer) = string(x)
function _cpp_g(x::Real)
    isnan(x) && return "nan"
    isinf(x) && return x > 0 ? "inf" : "-inf"
    return @sprintf("%g", x)
end

# ── O1–O6 files (spec §3.1) ────────────────────────────────────────────────────────────────

# columns of the per-cell formats; the integer columns are listed separately
const _OPENVT_COLUMNS = (O1 = (:x, :y, :i, :n), O2 = (:x, :y, :r, :f, :a), O5 = (:x_pos, :y_pos, :radius_i, :inhibited))
const _OPENVT_INTCOLS = (O1 = (:i, :n), O2 = (), O5 = (:inhibited,))
const _OPENVT_O6 = (:t, :N, :r, :A, :C, :w, :g, :C_rel, :w_rel)

# a float that `parse(Float64, ·)` returns unchanged; integral values without a fraction
function _openvt_float(x::Real)
    v = Float64(x)
    isnan(v) && return "nan"
    isinf(v) && return v > 0 ? "inf" : "-inf"
    isinteger(v) && abs(v) < 1.0e15 && return string(Int(v))
    return string(v)
end

_openvt_int(x::Real) = (isinteger(x) || throw(ArgumentError("write_openvt: $x is not an integer")); string(Int(x)))

function _openvt_lengths(name, cols...)
    n = length(first(cols))
    all(c -> length(c) == n, cols) ||
        throw(DimensionMismatch("write_openvt: the columns of $name have different lengths $(map(length, cols))"))
    return n
end

_openvt_format(format::Symbol) =
    format in (:O1, :O2, :O3, :O4, :O5, :O6, :O6_neighbors) ||
    throw(ArgumentError("unknown OpenVT format $format; use :O1–:O6 or :O6_neighbors"))

function _openvt_keys(format, data, want)
    keys(data) == want || throw(ArgumentError("write_openvt: $format takes the fields $want, got $(keys(data))"))
    return nothing
end

"""
    write_openvt(dest, format::Symbol, data::NamedTuple)

Write `data` as the OpenVT benchmark file `format` (spec 15 §3.1) to `dest`, a path
(returned) or an `IO`. Every file has a header line, `,` separators, `\\n` line ends
(including the last line) and no index column. In O1–O5, floats are written so that
`parse(Float64, field)` returns them exactly (integral values without a fraction, `NaN` as
`nan`, infinities as `inf`/`-inf`), and integer columns as integers.

| `format` | `data` | header |
|:--|:--|:--|
| `:O1` | `(; x, y, i, n)`: centroid, inhibition code in `0:3`, neighbour count | `x,y,i,n` |
| `:O2` | `(; x, y, r, f, a)` | `x,y,r,f,a` |
| `:O3` | `(; beta, mcs)` or `(; gamma, mcs)`; `mcs = NaN` for a run that never reached 10⁴ cells | `beta,Time to 10k (MCS),Time to 10k (5T)`; the 5T column is `mcs/775` |
| `:O4` | `(; t, widths)`, `widths[k, rep]` in cell diameters | `Normalized time (T),Tissue width rep1 (CD),…,Mean Tissue width (CD),STD Tissue width (CD)`; the mean and the population SD (divisor = replicates) of each row, from sequential sums |
| `:O5` | `(; x_pos, y_pos, radius_i, inhibited)`, `inhibited` 0 or 1 | `x_pos,y_pos,radius_i,inhibited` |
| `:O6` | `(; t, metrics)`, `metrics[k]` from [`openvt_metrics`](@ref) | `t,N,r,A,C,w,g,C_rel,w_rel`; a row is `t` as `run_metrics.sh` prints it (`%.15g`), `,`, and [`openvt_metrics_line`](@ref) |
| `:O6_neighbors` | `(; n, p)` from [`openvt_neighbor_histogram`](@ref) | `n,p`; `p` as `metrics.cpp` prints it |

The O4 mean and SD are summed left to right; NumPy sums pairwise, so with 8 or more
replicates they can differ from `numpy.mean`/`numpy.std` in the last bit. The O6 values
have `metrics.cpp`'s six significant digits. Other fields, an unknown
format, an O1 code outside `0:3` or an O5 flag other than 0/1 is an `ArgumentError`;
columns of different lengths are a `DimensionMismatch`. Read a file back with
[`read_openvt`](@ref); name it with [`openvt_filename`](@ref).
"""
function write_openvt(path::AbstractString, format::Symbol, data::NamedTuple)
    text = sprint(io -> write_openvt(io, format, data))   # validate before touching the file
    write(path, text)
    return path
end

function write_openvt(io::IO, format::Symbol, data::NamedTuple)
    _openvt_format(format)
    if format in (:O1, :O2, :O5)
        cols = _OPENVT_COLUMNS[format]
        ints = _OPENVT_INTCOLS[format]
        _openvt_keys(format, data, cols)
        n = _openvt_lengths(format, values(data)...)
        format === :O1 && (all(in(0:3), data.i) || throw(ArgumentError("write_openvt: O1 inhibition codes must be in 0:3")))
        format === :O5 && (all(in(0:1), data.inhibited) || throw(ArgumentError("write_openvt: O5 `inhibited` must be 0 or 1")))
        print(io, join(cols, ','), '\n')
        for k in 1:n
            print(io, join((c in ints ? _openvt_int(data[c][k]) : _openvt_float(data[c][k]) for c in cols), ','), '\n')
        end
    elseif format === :O3
        (length(data) == 2 && keys(data)[1] in (:beta, :gamma) && keys(data)[2] === :mcs) ||
            throw(ArgumentError("write_openvt: O3 takes the fields (beta, mcs) or (gamma, mcs), got $(keys(data))"))
        n = _openvt_lengths(format, data[1], data.mcs)
        print(io, keys(data)[1], ",Time to 10k (MCS),Time to 10k (5T)\n")
        for k in 1:n
            mcs = Float64(data.mcs[k])
            print(io, _openvt_float(data[1][k]), ',', _openvt_float(mcs), ',', _openvt_float(mcs / 775), '\n')
        end
    elseif format === :O4
        _openvt_keys(format, data, (:t, :widths))
        W = data.widths
        ndims(W) == 2 && size(W, 1) == length(data.t) ||
            throw(DimensionMismatch("write_openvt: O4 widths must be a length(t) × replicates matrix"))
        R = size(W, 2)
        print(io, "Normalized time (T),", join(("Tissue width rep$k (CD)" for k in 1:R), ','),
            R > 0 ? "," : "", "Mean Tissue width (CD),STD Tissue width (CD)\n")
        for (k, row) in enumerate(eachrow(W))
            s = 0.0
            for v in row
                s += v
            end
            m = s / R
            ss = 0.0
            for v in row
                ss += (v - m) * (v - m)
            end
            print(io, _openvt_float(data.t[k]), ',')
            for v in row
                print(io, _openvt_float(v), ',')
            end
            print(io, _openvt_float(m), ',', _openvt_float(sqrt(ss / R)), '\n')
        end
    elseif format === :O6
        _openvt_keys(format, data, (:t, :metrics))
        n = _openvt_lengths(format, data.t, data.metrics)
        print(io, join(_OPENVT_O6, ','), '\n')
        for k in 1:n
            print(io, _perl_g15(data.t[k]), ',', openvt_metrics_line(data.metrics[k]))
        end
    else # :O6_neighbors
        _openvt_keys(format, data, (:n, :p))
        n = _openvt_lengths(format, data.n, data.p)
        print(io, "n,p\n")
        for k in 1:n
            print(io, _openvt_int(data.n[k]), ',', _cpp_g(Float64(data.p[k])), '\n')
        end
    end
    return nothing
end

# perl `print $i*$dt` (`%.15g`)
function _perl_g15(t::Real)
    v = Float64(t)
    isnan(v) && return "NaN"
    isinf(v) && return v > 0 ? "Inf" : "-Inf"
    return @sprintf("%.15g", v)
end

"""
    read_openvt(path, format::Symbol) -> NamedTuple

Read an OpenVT benchmark file written by [`write_openvt`](@ref), returning the columns as
vectors: the `data` given to `write_openvt` for O1–O5 (for O3 under the parameter's name;
for O4 the widths matrix, without the mean and SD columns) and O6 neighbours, and
`(; t, N, r, A, C, w, g, C_rel, w_rel)` for O6. Integer columns (`i`, `n`, `inhibited`, `N`)
are `Vector{Int}`, the others `Vector{Float64}`; `nan` reads as `NaN`. O1–O5 round-trip
exactly; O6 values carry `metrics.cpp`'s six significant digits. An unknown format is an
`ArgumentError`.
"""
function read_openvt(path::AbstractString, format::Symbol)
    _openvt_format(format)
    lines = filter(!isempty, readlines(path))
    isempty(lines) && throw(ArgumentError("read_openvt: $path is empty"))
    header = split(lines[1], ',')
    rows = [split(l, ',') for l in lines[2:end]]
    width = length(header)
    for (k, row) in enumerate(rows)
        length(row) == width || throw(ArgumentError("read_openvt: $path: row $k has $(length(row)) fields, the header $width"))
    end
    fcol(c) = Float64[parse(Float64, r[c]) for r in rows]
    icol(c) = Int[parse(Int, r[c]) for r in rows]
    if format in (:O1, :O2, :O5)
        cols = _OPENVT_COLUMNS[format]
        _openvt_header(path, format, header, cols)
        return NamedTuple{cols}(Tuple(c in _OPENVT_INTCOLS[format] ? icol(k) : fcol(k) for (k, c) in enumerate(cols)))
    elseif format === :O3
        p = Symbol(header[1])
        p in (:beta, :gamma) && width == 3 || throw(ArgumentError("read_openvt: $path is not an O3 file"))
        return NamedTuple{(p, :mcs)}((fcol(1), fcol(2)))
    elseif format === :O4
        (width >= 3 && header[1] == "Normalized time (T)") || throw(ArgumentError("read_openvt: $path is not an O4 file"))
        R = width - 3
        return (t = fcol(1), widths = Float64[parse(Float64, rows[k][1 + j]) for k in eachindex(rows), j in 1:R])
    elseif format === :O6
        _openvt_header(path, format, header, _OPENVT_O6)
        return NamedTuple{_OPENVT_O6}(Tuple(c === :N ? icol(k) : fcol(k) for (k, c) in enumerate(_OPENVT_O6)))
    else # :O6_neighbors
        _openvt_header(path, format, header, (:n, :p))
        return (n = icol(1), p = fcol(2))
    end
end

function _openvt_header(path, format, header, cols)
    Tuple(Symbol.(header)) == cols ||
        throw(ArgumentError("read_openvt: $path: expected the $format header $(join(cols, ',')), got $(join(header, ','))"))
    return nothing
end

"""
    openvt_filename(format::Symbol; …) -> String

The file name the OpenVT benchmark expects for `format` (spec 15 §3.1):

- `openvt_filename(:O1; case, seed, mcs)`: `"potts_<case>_s<seed>_<mcs:06d>.csv"`;
- `openvt_filename(:O2; k)`: `"Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv"`
  (joined with the platform's separator);
- `openvt_filename(:O3; parameter)`, `parameter` `:beta` or `:gamma`:
  `"Potts.jl_time_to_10k_vs_<parameter>.csv"`;
- `openvt_filename(:O5; gamma, mcs)`: `"Potts.jl_gamma_<gamma>_<mcs>MCS.csv"`, with `gamma`
  as `string` writes it (the Fig 7 colonies, β = 0);
- `openvt_filename(:O5; beta, mcs)`: `"Potts.jl_beta_<beta>_<mcs>MCS.csv"`, with `beta` as
  `string` writes it (the Fig 8 colonies, γ = 0; D-211).

O4 and O6 have no fixed names. Another format or an O3 `parameter` other than `:beta` and
`:gamma` is an `ArgumentError`, and so is an O5 call with both or neither of `gamma` and
`beta`.
"""
function openvt_filename(format::Symbol; kw...)
    if format === :O1
        return string("potts_", kw[:case], "_s", kw[:seed], "_", lpad(Int(kw[:mcs]), 6, '0'), ".csv")
    elseif format === :O2
        return joinpath("Potts.jl_5T_MonolayerGrowth_1000_Data", string("cell_data_no_inhibition_", kw[:k], ".csv"))
    elseif format === :O3
        p = Symbol(kw[:parameter])
        p in (:beta, :gamma) || throw(ArgumentError("openvt_filename: O3 parameter must be :beta or :gamma, got $p"))
        return string("Potts.jl_time_to_10k_vs_", p, ".csv")
    elseif format === :O5
        (haskey(kw, :gamma) ⊻ haskey(kw, :beta)) ||
            throw(ArgumentError("openvt_filename: O5 takes exactly one of `gamma` and `beta`"))
        p = haskey(kw, :gamma) ? :gamma : :beta
        return string("Potts.jl_", p, "_", kw[p], "_", kw[:mcs], "MCS.csv")
    end
    throw(ArgumentError("openvt_filename: no file name for format $format; use :O1, :O2, :O3 or :O5"))
end
