# P6.15d (ROADMAP Step 3b; spec research/model-specs/15_openvt_monolayer.md v3 §3, §4.0 A3,
# §6 G8; D-147, D-146, D-048): the OpenVT monolayer analysis port. A concaveman port, a
# byte-faithful port of the consortium's `metrics.cpp`, the M Category 3 inhibition fractions
# (A3) and the O1–O6 writers. Decision: D-149. Frozen (AUTONOMY §7.3).
#
# ── Surface fixed here (names are qualified in this file, so export is the implementer's call)
#
#   PottsModels.Analysis.concave_hull(points; concavity = 2.0, length_threshold = 0.0)
#       General primitive. `points`: a vector of 2-tuples of reals (converted to Float64; the
#       input is not mutated). Returns `Vector{NTuple{2,Float64}}`: the closed boundary,
#       without repeating the first vertex, exactly as `metrics.cpp` builds it (§3.2 step 3):
#         - convex hull by Graham scan, collinear points excluded (metrics.cpp:33-63): pivot
#           p0 = the point with the least (y, x); the others sorted by orientation about p0
#           (clockwise first, ties by squared distance); a two-vertex hull of equal points
#           drops one;
#         - then concaveman (concaveman.h, the Adaszewski port of mapbox/concaveman) with
#           this `concavity` and `length_threshold`: hull already holding every point →
#           returned as is; otherwise edges are processed FIFO; for edge (b, c) with
#           |bc|² ≥ length_threshold², the interior candidates are taken in increasing
#           squared segment distance d (only d ≤ |bc|²/concavity²); the first with
#           d < sqSegDist(p, a, b) and d < sqSegDist(p, c, d′) whose edges b–p, c–p cross no
#           current edge (concaveman.h `intersects`, bounding-box prefilter) is inserted when
#           min(|pb|², |pc|²) ≤ |bc|²/concavity²; an inserted point and its duplicates leave
#           the candidate set;
#         - vertex order: clockwise from p0 in Graham order, the output starting at the
#           successor of the LAST convex-hull vertex (concaveman.h `last->next()`), so points
#           carved into the closing edge come first.
#       Empty input: ArgumentError. No `fma`, `muladd`, `@fastmath`, `@simd` in the kernels
#       (spec D11; ROADMAP Accept).
#
#   PottsModels.openvt_metrics(path::AbstractString) / openvt_metrics(x, y, g)
#       → (; N::Int, r, A, C, w, g, C_rel, w_rel), Float64 except N. `metrics.cpp` §3.2:
#       the header is split on ',' and `"`/`'` stripped; columns x, y, g, n located by name
#       (last match; extra columns ignored; empty lines skipped). For Potts' own O1 files a
#       missing `g` is derived from an `i` column, g = (i == 0) (spec C8). Missing x or y, or
#       neither g nor i: ArgumentError. A data row with too few fields: ArgumentError.
#       Boundary = concave_hull(points; concavity = 1.5). B > 2: c = vertex mean, r = mean |v−c|,
#       A = |shoelace|/2, C = closed perimeter, w = √(Σ(|v−c| − r)²/(B − 1)); else NaN.
#       g = Σg/N, C_rel = C/(2√(πA)), w_rel = w/r. Sums in metrics.cpp's order (r, A, C in
#       one loop over (i, j) = (B, 1), (1, 2), …; w in a second loop), Float64 throughout
#       (the arm64 reference has long double == double).
#   PottsModels.openvt_metrics_line(m)::String
#       exactly metrics.cpp's stdout: `N,r,A,C,w,g,C_rel,w_rel\n`, each value as C++
#       `ostream <<` prints it (C `%g`, precision 6; NaN → `nan`).
#   PottsModels.openvt_neighbor_histogram(n) → (; n = 0:nmax as a Vector{Int}, p)
#       p = (100·count)/N, in percent, as metrics.cpp:225-246.
#   PottsModels.openvt_inhibition_code(a, f; β, γ)::Int
#       M p.2 code: 0 growing, 1 type 1 only, 2 type 2 only, 3 both. Type 1 inhibited iff
#       NOT a ≥ β; type 2 inhibited iff NOT f ≥ γ (spec C9: M's ≥ wins over the schema's >).
#   PottsModels.openvt_inhibition_fractions(i) → (; uninhibited, type1, type2, both)
#       the shares of codes 0, 1, 2, 3 (spec A3); a code outside 0:3 is an ArgumentError.
#   PottsModels.write_openvt(dest, format::Symbol, data::NamedTuple)   dest: path or IO
#   PottsModels.read_openvt(path, format::Symbol)::NamedTuple
#       Formats (spec §3.1). Every file: header line first, ',' separators, '\n' line ends,
#       a trailing '\n', no index column. Floats in O1–O5 are written so that
#       `parse(Float64, field)` gives back the same Float64 (spelling otherwise free);
#       non-finite as `nan`/`inf`/`-inf` (the consortium precedent); integer columns as
#       plain integers. `read_openvt(write_openvt(…))` returns the input (isequal).
#         :O1  (; x, y, i, n)                 header `x,y,i,n`; i ∈ 0:3, else ArgumentError
#         :O2  (; x, y, r, f, a)              header `x,y,r,f,a`
#         :O3  (; beta | gamma, mcs)          header `beta,Time to 10k (MCS),Time to 10k (5T)`
#                                             (resp. gamma); 5T column = mcs/775; unreached
#                                             runs are mcs = NaN → `nan,nan`
#         :O4  (; t, widths)                  widths[k, rep] in CD; header
#                                             `Normalized time (T),Tissue width rep1 (CD),…,
#                                             Mean Tissue width (CD),STD Tissue width (CD)`;
#                                             mean and population SD (np.std) per row
#         :O5  (; x_pos, y_pos, radius_i, inhibited)  same header; inhibited 0/1
#         :O6  (; t, metrics)                 header `t,N,r,A,C,w,g,C_rel,w_rel`; a row is t
#                                             as run_metrics.sh's perl prints it (%.15g),
#                                             ',', then openvt_metrics_line(m); read_openvt
#                                             returns (; t, N, r, A, C, w, g, C_rel, w_rel)
#         :O6_neighbors (; n, p)              header `n,p`; p as metrics.cpp prints it
#       Wrong keys or an unknown format: ArgumentError; columns of unequal length:
#       DimensionMismatch or ArgumentError.
#   PottsModels.openvt_filename(format; …)   spec §3.1 names
#         :O1 (case, seed, mcs) → "potts_<case>_s<seed>_<mcs:06d>.csv"
#         :O2 (k)               → joinpath("Potts.jl_5T_MonolayerGrowth_1000_Data",
#                                          "cell_data_no_inhibition_<k>.csv")
#         :O3 (parameter ∈ (:beta, :gamma)) → "Potts.jl_time_to_10k_vs_<parameter>.csv"
#         :O5 (gamma, mcs)      → "Potts.jl_gamma_<string(gamma)>_<mcs>MCS.csv"
#
# ── Oracles
#
#   - Hand-derived hulls (square, square + centre, L at concavity 1.5 / 1 / 2, notch,
#     collinear, duplicates, all-duplicates, single point, two points) and hand-derived
#     metrics (square, triangle, notch, degenerate B ≤ 2); every expected value was also
#     reproduced by the reference builds below (clang and gcc agree on all of them).
#   - The headline (gated on ENV["OPENVT_MONOLAYER_REPO"], the consortium repo G at 54f375f;
#     never copied into git): the 25 Morpheus parameter-plane centroid files
#     (`results/Morpheus/Monolayer/Parameter_Plane_Centroid_Data/Parameter_Plane_Morpheus_Centroids.zip`,
#     unzipped to a temp dir with the `unzip` tool) give the committed `metrics.csv` byte for
#     byte: header `file,N,r,A,C,w,g`, then `<file>,` and the first six fields of the
#     metrics line, files in byte order (the committed file was made by the older 6-field
#     binary, run_metrics.sh in that directory). The two trailing fields (C_rel, w_rel) are
#     checked against P15D_TAIL, recorded from the reference build.
#   - FMA guard (ungated): three jittered point clouds generated here from an integer LCG
#     (no floating-point in the generator, so every platform writes the same bytes) must
#     give the `-ffp-contract=off` reference lines. On all three, the default-contraction
#     clang build AND a scratch Julia port with `muladd` in the orientation and distance
#     kernels give different lines (recorded below as negative controls), and clang and
#     gcc agree with contraction off. Perfect (unjittered) lattices were rejected as
#     fixtures: their exact ties make the result depend on the C++ standard library.
#     Plus a source scan of the files defining the port for fma/muladd/@fastmath/@simd.
#   - Writers: exact headers, integer spellings, round trips, hand-computed mean/SD, and
#     the O6 `t` spelling taken from the consortium's measurements_morpheus.csv row 3
#     (t = 5/97 → 0.0515463917525773).
#
# ── Reference build (2026-10-05, this Mac, arm64; scratch only)
#
#   G=$OPENVT_MONOLAYER_REPO/results/postprocessing
#   c++ -std=c++17 -O2 -ffp-contract=off -I$G -o metrics_off $G/metrics.cpp       # Apple clang 17.0.0
#   g++-15 -std=c++17 -O2 -ffp-contract=off -I$G -o metrics_gcc_off $G/metrics.cpp  # GCC 15.2.0
#   c++ -std=c++17 -O2 -I$G -o metrics_on $G/metrics.cpp                           # default contraction
#   cd <unzipped centroids>; { echo "file,N,r,A,C,w,g"; for f in *.csv; do echo -n "$f,";
#     ./metrics_off $f | cut -d, -f1-6; done; } | cmp - <dir>/metrics.csv          # identical
#   metrics_on differs from the committed file on all 25 rows. A brute-force Julia port
#   (scratch, no R-tree) reproduced all 25 rows, all 8 fields, byte for byte in ≈ 7 s.
#   Before freezing, this whole file ran green against that scratch port (184 passes with
#   the repo set; 128 + 1 broken without), and the port's `muladd` variant failed the FMA
#   guard (AUTONOMY §7.2 stub run; the port itself is not committed).

using Test

const P15D = PottsModels
const P15D_AN = PottsModels.Analysis

# ── helpers ────────────────────────────────────────────────────────────────────────────────

p15d_csv(dir, name, text) = (path = joinpath(dir, name); write(path, text); path)

# an integer-only LCG cloud: a hexagonal lattice (spacing 1, rows √3/2 ≈ 0.8660254 apart)
# inside a disc of radius ρ, each coordinate jittered by an integer in ±jit (units of 1e-7)
# and shifted by 100; written with exactly 7 decimals; g ~ Bernoulli(0.3), n ∈ 3:7
function p15d_cloud(seed::Integer, ρ::Integer, jit::Integer)
    s = UInt64(seed)
    draw(m) = (s = s * 0x5851f42d4c957f2d + 0x14057b7ef767814f; Int((s >> 33) % UInt64(m)))
    dec(v) = string(div(v, 10^7), ".", lpad(rem(v, 10^7), 7, '0'))
    rows = String["x,y,g,n"]
    for j in -ρ:ρ, i in (-ρ - 1):(ρ + 1)
        xi = i * 10^7 + (isodd(j) ? 5 * 10^6 : 0)
        yi = j * 8660254
        xi^2 + yi^2 <= (ρ * 10^7)^2 || continue
        xi += draw(2jit + 1) - jit
        yi += draw(2jit + 1) - jit
        g = draw(10) < 3 ? 1 : 0
        n = 3 + draw(5)
        push!(rows, string(dec(10^9 + xi), ",", dec(10^9 + yi), ",", g, ",", n))
    end
    return join(rows, "\n") * "\n"
end

# an independent minimal reader for the headline negative control (x, y, g by name)
function p15d_xyg(path)
    lines = filter(!isempty, readlines(path))
    names = [replace(s, '"' => "", '\'' => "") for s in split(lines[1], ',')]
    ix, iy, ig = (findlast(==(c), names) for c in ("x", "y", "g"))
    rows = [split(l, ',') for l in lines[2:end]]
    return [parse(Float64, r[ix]) for r in rows], [parse(Float64, r[iy]) for r in rows], [parse(Int, r[ig]) for r in rows]
end

p15d_hull(pts; kw...) = P15D_AN.concave_hull(NTuple{2,Float64}[Float64.(p) for p in pts]; kw...)

# ── concave hull: hand-built point sets ───────────────────────────────────────────────────

@testset "P6.15d: concave_hull on hand-built point sets" begin
    sq = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    # Graham: p0 = (0,0); clockwise (decreasing angle) order (0,1), (1,1), (1,0); every point
    # is on the hull, so concaveman returns it unchanged
    @test p15d_hull(sq; concavity = 1.5) == [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
    @test p15d_hull(reverse(sq); concavity = 1.5) == [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
    @test P15D_AN.concave_hull(sq) == [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]   # default concavity
    @test P15D_AN.concave_hull([(0, 0), (1, 0), (1, 1), (0, 1)]) == [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]  # Int input
    @test eltype(P15D_AN.concave_hull(sq)) == NTuple{2,Float64}
    # square + centre: the centre is d = 0.25 from every edge (≤ 1/2.25) but exactly as close
    # to the adjacent edges, and `d < d0` is strict → never inserted
    @test p15d_hull([sq; (0.5, 0.5)]; concavity = 1.5) == [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
    # the input is not mutated (metrics.cpp sorts its own vector in place)
    pts = [(0.5, 0.5), (1.0, 1.0), (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    keep = copy(pts)
    P15D_AN.concave_hull(pts; concavity = 1.5)
    @test pts == keep

    # L of six points; convex hull (0,0),(0,2),(1,2),(2,1),(2,0); (1,1) lies d = 0.5 from the
    # edge (1,2)–(2,1) (|bc|² = 2), 1 from both adjacent edges, and 1 from both endpoints.
    # Inserted iff min endpoint distance 1 ≤ 2/concavity²: concavity 1 yes; 1.5 (0.889) and
    # 2 (0.5) no. Earlier edges reject it: edge (0,0)–(0,2) has d = 1 = d0 (strict <).
    L6 = [(0.0, 0.0), (2.0, 0.0), (2.0, 1.0), (1.0, 1.0), (1.0, 2.0), (0.0, 2.0)]
    convexL = [(0.0, 0.0), (0.0, 2.0), (1.0, 2.0), (2.0, 1.0), (2.0, 0.0)]
    @test p15d_hull(L6; concavity = 1.5) == convexL
    @test p15d_hull(L6; concavity = 2.0) == convexL
    @test p15d_hull(L6; concavity = 1.0) == [(0.0, 0.0), (0.0, 2.0), (1.0, 2.0), (1.0, 1.0), (2.0, 1.0), (2.0, 0.0)]
    # length_threshold: an edge shorter than it is never drilled (|bc|² = 2 < 1.5²)
    @test p15d_hull(L6; concavity = 1.0, length_threshold = 1.5) == convexL

    # notch: (2, 3.2) is d = 0.64 below the top edge (|bc|² = 16, limit 16/2.25 = 7.11),
    # 4 from both side edges, min endpoint distance 4 + 0.64 = 4.64 ≤ 7.11 → inserted
    # between (0,4) and (4,4)
    @test p15d_hull([(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (2.0, 3.2)]; concavity = 1.5) ==
        [(0.0, 0.0), (0.0, 4.0), (2.0, 3.2), (4.0, 4.0), (4.0, 0.0)]
    # with a huge concavity nothing is carved: the convex hull
    @test p15d_hull([(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (2.0, 3.2)]; concavity = 1e300) ==
        [(0.0, 0.0), (0.0, 4.0), (4.0, 4.0), (4.0, 0.0)]

    # big L: the 18 lattice points {0:5}×{0:1} ∪ {0:1}×{2:4}. Convex hull (0,0),(0,4),(1,4),
    # (5,1),(5,0); every lattice point on a hull edge is carved in (d = 0); the notch edge
    # (1,4)–(5,1) takes (4,1) (d = 0.36 on 3x + 4y = 19), then (3,1), (2,1), (1,2), (1,3);
    # (1,1) is the only interior point: d = 0.5 from (1,2)–(2,1) but both endpoints are 1
    # away (> 2/2.25). The output starts after the last hull vertex (5,0), so the points
    # carved into the closing edge (5,0)→(0,0) come first.
    Lbig = [(Float64(i), Float64(j)) for i in 0:5 for j in 0:1]
    append!(Lbig, [(Float64(i), Float64(j)) for i in 0:1 for j in 2:4])
    @test p15d_hull(Lbig; concavity = 1.5) ==
        [(4.0, 0.0), (3.0, 0.0), (2.0, 0.0), (1.0, 0.0), (0.0, 0.0), (0.0, 1.0), (0.0, 2.0), (0.0, 3.0),
         (0.0, 4.0), (1.0, 4.0), (1.0, 3.0), (1.0, 2.0), (2.0, 1.0), (3.0, 1.0), (4.0, 1.0), (5.0, 1.0), (5.0, 0.0)]

    # collinear: Graham keeps the two ends; the inner points are 0 from the edge but also
    # 0 from the adjacent (reverse) edge → rejected (strict <)
    @test p15d_hull([(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)]; concavity = 1.5) == [(0.0, 0.0), (3.0, 0.0)]
    @test p15d_hull([(2.0, 0.0), (0.0, 0.0), (3.0, 0.0), (1.0, 0.0)]; concavity = 1.5) == [(0.0, 0.0), (3.0, 0.0)]
    # duplicates: a duplicated hull vertex appears once (its copy leaves the candidate set
    # with it)
    @test p15d_hull([sq; (1.0, 1.0)]; concavity = 1.5) == [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
    @test p15d_hull([(2.0, 3.0), (2.0, 3.0), (2.0, 3.0)]; concavity = 1.5) == [(2.0, 3.0)]
    @test p15d_hull([(3.0, 4.0), (3.0, 4.0)]; concavity = 1.5) == [(3.0, 4.0)]
    # a single point; two points (pivot = least y first)
    @test p15d_hull([(5.0, 7.0)]; concavity = 1.5) == [(5.0, 7.0)]
    @test p15d_hull([(3.0, 4.0), (0.0, 0.0)]; concavity = 1.5) == [(0.0, 0.0), (3.0, 4.0)]
    @test_throws ArgumentError P15D_AN.concave_hull(NTuple{2,Float64}[])
end

# ── metrics.cpp port: hand-built centroid files ───────────────────────────────────────────

@testset "P6.15d: openvt_metrics on hand-built files" begin
    mktempdir() do dir
        # notch, with quoted names, an extra column, odd column order and a trailing blank line
        notch = p15d_csv(dir, "notch.csv", """
            "cell.id",'n',"y",extra,"x","g"
            1,2,0,a,0,1
            2,3,4,b,0,0
            3,3,3.2,c,2,1
            4,4,4,d,4,1
            5,2,0,e,4,0

            """)
        m = P15D.openvt_metrics(notch)
        @test keys(m) == (:N, :r, :A, :C, :w, :g, :C_rel, :w_rel)
        @test m.N === 5
        # boundary (0,0),(0,4),(2,3.2),(4,4),(4,0): area 16 − ½·4·0.8, perimeter 12 + 2√4.64,
        # centre (2, 2.24)
        v = [(0.0, 0.0), (0.0, 4.0), (2.0, 3.2), (4.0, 4.0), (4.0, 0.0)]
        d = [hypot(p[1] - 2.0, p[2] - 2.24) for p in v]
        r = sum(d) / 5
        @test m.A ≈ 14.4 rtol = 1e-14
        @test m.C ≈ 12 + 2sqrt(4.64) rtol = 1e-14
        @test m.r ≈ r rtol = 1e-14
        @test m.w ≈ sqrt(sum((d .- r) .^ 2) / 4) rtol = 1e-12
        @test m.g == 0.6
        @test m.C_rel ≈ m.C / (2sqrt(pi * m.A)) rtol = 1e-15
        @test m.w_rel ≈ m.w / m.r rtol = 1e-15
        @test P15D.openvt_metrics_line(m) == "5,2.45883,14.4,16.3081,0.854822,0.6,1.21232,0.347655\n"

        # square + centre: B = 4, r = √½, A = 1, C = 4, w = 0, C_rel = 2/√π
        sqc = p15d_csv(dir, "sq.csv", "x,y,g,n\n0,0,1,3\n1,0,0,5\n1,1,1,5\n0,1,1,6\n0.5,0.5,0,0\n")
        m = P15D.openvt_metrics(sqc)
        @test m.N == 5 && m.A == 1 && m.C == 4 && m.w == 0 && m.w_rel == 0 && m.g == 0.6
        @test m.r ≈ sqrt(0.5) rtol = 1e-15
        @test m.C_rel ≈ 2 / sqrt(pi) rtol = 1e-15
        @test P15D.openvt_metrics_line(m) == "5,0.707107,1,4,0,0.6,1.12838,0\n"

        # triangle (B = 3): centre (⅓, ⅓), radii √2/3, √5/3, √5/3
        tri = p15d_csv(dir, "tri.csv", "x,y,g,n\n0,0,1,1\n1,0,0,1\n0,1,1,2\n")
        m = P15D.openvt_metrics(tri)
        r = (sqrt(2) + 2sqrt(5)) / 9
        @test m.r ≈ r rtol = 1e-14
        @test m.A == 0.5
        @test m.C ≈ 2 + sqrt(2) rtol = 1e-15
        @test m.w ≈ sqrt(((sqrt(2) / 3 - r)^2 + 2 * (sqrt(5) / 3 - r)^2) / 2) rtol = 1e-12
        @test m.g ≈ 2 / 3 rtol = 1e-15
        @test P15D.openvt_metrics_line(m) == "3,0.654039,0.5,3.41421,0.158166,0.666667,1.36207,0.24183\n"

        # B ≤ 2: r, A, C, w and the ratios are NaN (the measurement files' leading `nan`s)
        m_one = P15D.openvt_metrics(p15d_csv(dir, "one.csv", "x,y,g,n\n5,7,1,0\n"))
        @test m_one.N == 1 && m_one.g == 1 && all(isnan, (m_one.r, m_one.A, m_one.C, m_one.w, m_one.C_rel, m_one.w_rel))
        @test P15D.openvt_metrics_line(m_one) == "1,nan,nan,nan,nan,1,nan,nan\n"
        m_col = P15D.openvt_metrics(p15d_csv(dir, "col.csv", "x,y,g,n\n0,0,1,1\n1,0,0,2\n2,0,0,2\n3,0,1,1\n"))
        @test P15D.openvt_metrics_line(m_col) == "4,nan,nan,nan,nan,0.5,nan,nan\n"
        m_two = P15D.openvt_metrics(p15d_csv(dir, "two.csv", "x,y,g,n\n3,4,0,1\n0,0,0,1\n"))
        @test P15D.openvt_metrics_line(m_two) == "2,nan,nan,nan,nan,0,nan,nan\n"

        # the vector method agrees with the file method
        @test P15D.openvt_metrics([0.0, 0.0, 2.0, 4.0, 4.0], [0.0, 4.0, 3.2, 4.0, 0.0], [1, 0, 1, 1, 0]) ==
            P15D.openvt_metrics(notch)

        # C8: an O1 file (i, no g) gives g = (i == 0); same boundary as the notch
        o1 = joinpath(dir, "o1.csv")
        P15D.write_openvt(o1, :O1, (x = [0.0, 0.0, 2.0, 4.0, 4.0], y = [0.0, 4.0, 3.2, 4.0, 0.0], i = [0, 1, 0, 0, 3], n = [2, 3, 3, 4, 2]))
        @test P15D.openvt_metrics_line(P15D.openvt_metrics(o1)) == "5,2.45883,14.4,16.3081,0.854822,0.6,1.21232,0.347655\n"

        # metrics.cpp's fatal errors
        @test_throws ArgumentError P15D.openvt_metrics(p15d_csv(dir, "nox.csv", "\"cell.center.x\",y,g,n\n1,2,1,3\n"))
        @test_throws ArgumentError P15D.openvt_metrics(p15d_csv(dir, "noy.csv", "x,g,n\n1,1,3\n"))
        @test_throws ArgumentError P15D.openvt_metrics(p15d_csv(dir, "nog.csv", "x,y,n\n1,2,3\n"))
        @test_throws ArgumentError P15D.openvt_metrics(p15d_csv(dir, "short.csv", "x,y,g,n\n1,2,1,3\n4,5\n"))
    end
end

@testset "P6.15d: neighbour histogram (metrics.cpp n,p)" begin
    h = P15D.openvt_neighbor_histogram([3, 5, 5, 6, 0])
    @test h.n == 0:6 && h.p == [20.0, 0.0, 0.0, 20.0, 0.0, 40.0, 20.0]
    h = P15D.openvt_neighbor_histogram([1, 1, 2])
    @test h.n == 0:2 && h.p == [0.0, 200 / 3, 100 / 3]
    io = IOBuffer()
    P15D.write_openvt(io, :O6_neighbors, h)
    @test String(take!(io)) == "n,p\n0,0\n1,66.6667\n2,33.3333\n"
    io = IOBuffer()
    P15D.write_openvt(io, :O6_neighbors, P15D.openvt_neighbor_histogram([3, 5, 5, 6, 0]))
    @test String(take!(io)) == "n,p\n0,20\n1,0\n2,0\n3,20\n4,0\n5,40\n6,20\n"
end

# ── FMA guard ───────────────────────────────────────────────────────────────────────────────

# (seed, ρ, jit) => (the -ffp-contract=off line, the default-contraction clang line,
#                    a scratch Julia port with `muladd` in orient/orient2d/sqDist/sqSegDist)
const P15D_CLOUDS = [
    (1, 8, 2_000_000) => ("233,7.55168,178.275,54.7386,0.40303,0.248927,1.15649,0.0533695\n",
        "233,7.46981,176.015,56.6684,0.542144,0.248927,1.20493,0.072578\n",
        "233,7.50372,179.384,70.7162,0.541793,0.248927,1.48944,0.0722033\n"),
    (2, 12, 2_000_000) => ("501,11.3297,401.517,78.765,0.474074,0.321357,1.10886,0.0418437\n",
        "501,9.75389,404.763,124.934,3.4425,0.321357,1.75177,0.352936\n",
        "501,10.9093,398.055,123.16,1.5178,0.321357,1.74138,0.139129\n"),
    (4, 10, 3_000_000) => ("355,9.40448,278.75,67.3056,0.512754,0.253521,1.13721,0.0545224\n",
        "355,9.20766,286.32,93.0189,0.913898,0.253521,1.55075,0.0992541\n",
        "355,8.5659,285.366,103.202,2.39258,0.253521,1.72338,0.279315\n"),
]

@testset "P6.15d: geometry kernels avoid fused multiply-adds (spec D11)" begin
    mktempdir() do dir
        for ((seed, ρ, jit), (off, on, jlfma)) in P15D_CLOUDS
            path = p15d_csv(dir, "cloud_$seed.csv", p15d_cloud(seed, ρ, jit))
            line = P15D.openvt_metrics_line(P15D.openvt_metrics(path))
            @test line == off
            # negative controls: the fixture is sensitive to contraction
            @test off != on && off != jlfma && line != jlfma
        end
    end
    # source scan: the files that define the port contain no fused/reassociating arithmetic
    files = Set{String}()
    adir = normpath(joinpath(@__DIR__, "..", "..", "src", "analysis"))
    for f in readdir(adir; join = true)
        endswith(f, ".jl") && push!(files, f)
    end
    for fn in (P15D_AN.concave_hull, P15D.openvt_metrics, P15D.openvt_metrics_line)
        for mt in methods(fn)
            f = String(mt.file)
            isfile(f) && push!(files, f)
        end
    end
    @test !isempty(files)
    bad = r"\bfma\b|\bmuladd\b|@fastmath|@simd|@turbo|evalpoly"
    for f in sort!(collect(files))
        code = read(f, String)
        code = replace(code, r"\"\"\"(?s:.*?)\"\"\"" => "")     # docstrings
        code = replace(code, r"#=(?s:.*?)=#" => "")              # block comments
        code = replace(code, r"#[^\n]*" => "")                   # line comments
        @test !occursin(bad, code)
        occursin(bad, code) && @info "P6.15d: fused arithmetic in" f
    end
end

# ── headline: the committed parameter-plane metrics.csv, byte for byte ──────────────────────

const P15D_TAIL = Dict(   # C_rel,w_rel from the -ffp-contract=off reference build
    "Centroids_Morpheus_beta0.0_gamma0.0_replicate4458.csv" => "1.18433,0.0112518",
    "Centroids_Morpheus_beta0.0_gamma0.3_replicate4422.csv" => "1.38554,0.0486836",
    "Centroids_Morpheus_beta0.0_gamma0.45_replicate4439.csv" => "1.83003,0.079426",
    "Centroids_Morpheus_beta0.0_gamma0.4_replicate4428.csv" => "1.69033,0.0666557",
    "Centroids_Morpheus_beta0.0_gamma0.5_replicate4432.csv" => "1.87944,0.0883471",
    "Centroids_Morpheus_beta0.95_gamma0.0_replicate4461.csv" => "1.11034,0.0127057",
    "Centroids_Morpheus_beta0.95_gamma0.3_replicate4462.csv" => "1.39213,0.0503537",
    "Centroids_Morpheus_beta0.95_gamma0.45_replicate4472.csv" => "1.95053,0.106196",
    "Centroids_Morpheus_beta0.95_gamma0.4_replicate4463.csv" => "1.67041,0.084226",
    "Centroids_Morpheus_beta0.95_gamma0.5_replicate4465.csv" => "2.04335,0.129278",
    "Centroids_Morpheus_beta0.99_gamma0.0_replicate4466.csv" => "1.09639,0.00854003",
    "Centroids_Morpheus_beta0.99_gamma0.3_replicate4467.csv" => "1.31746,0.0396452",
    "Centroids_Morpheus_beta0.99_gamma0.45_replicate4469.csv" => "1.87656,0.0815215",
    "Centroids_Morpheus_beta0.99_gamma0.4_replicate4473.csv" => "1.5951,0.0723294",
    "Centroids_Morpheus_beta0.99_gamma0.5_replicate4470.csv" => "1.99814,0.143274",
    "Centroids_Morpheus_beta0.9_gamma0.0_replicate4443.csv" => "1.10229,0.0121672",
    "Centroids_Morpheus_beta0.9_gamma0.3_replicate4444.csv" => "1.42478,0.0386743",
    "Centroids_Morpheus_beta0.9_gamma0.45_replicate4446.csv" => "1.94072,0.0828633",
    "Centroids_Morpheus_beta0.9_gamma0.4_replicate4445.csv" => "1.74246,0.063203",
    "Centroids_Morpheus_beta0.9_gamma0.5_replicate4447.csv" => "1.92214,0.137531",
    "Centroids_Morpheus_beta1.0_gamma0.0_replicate4421.csv" => "1.11058,0.00628749",
    "Centroids_Morpheus_beta1.0_gamma0.3_replicate4426.csv" => "1.28956,0.0565742",
    "Centroids_Morpheus_beta1.0_gamma0.45_replicate4448.csv" => "1.59477,0.103692",
    "Centroids_Morpheus_beta1.0_gamma0.4_replicate4431.csv" => "1.56256,0.104281",
    "Centroids_Morpheus_beta1.0_gamma0.5_replicate4481.csv" => "2.07075,0.290948",
)

@testset "P6.15d: consortium parameter-plane metrics.csv, byte for byte (OPENVT_MONOLAYER_REPO)" begin
    repo = get(ENV, "OPENVT_MONOLAYER_REPO", "")
    dir = joinpath(repo, "results", "Morpheus", "Monolayer", "Parameter_Plane_Centroid_Data")
    zipf = joinpath(dir, "Parameter_Plane_Morpheus_Centroids.zip")
    if isempty(repo) || !isfile(zipf) || Sys.which("unzip") === nothing
        @test_broken !isempty(repo) && isfile(zipf) && Sys.which("unzip") !== nothing
    else
        committed = read(joinpath(dir, "metrics.csv"), String)
        mktempdir() do tmp
            run(`unzip -q $zipf -d $tmp`)
            files = sort(filter(endswith(".csv"), readdir(tmp)))
            @test length(files) == 25 && Set(files) == Set(keys(P15D_TAIL))
            io = IOBuffer()
            print(io, "file,N,r,A,C,w,g\n")
            rows = Dict{String,String}()
            for f in files
                line = P15D.openvt_metrics_line(P15D.openvt_metrics(joinpath(tmp, f)))
                fields = split(chomp(line), ',')
                @test endswith(line, "\n") && length(fields) == 8
                @test join(fields[7:8], ",") == P15D_TAIL[f]
                rows[f] = string(f, ",", join(fields[1:6], ","))
                print(io, rows[f], "\n")
            end
            ours = String(take!(io))
            @test ours == committed
            if ours != committed   # per-row diagnostics
                want = Dict(split(l, ',')[1] => l for l in split(chomp(committed), '\n')[2:end])
                for f in files
                    rows[f] == get(want, f, "") || @info "P6.15d metrics.csv row differs" f ours = rows[f] committed = get(want, f, "")
                end
            end

            # negative control: move the right-most cell of the most ragged colony 1 R
            # outward; same N and g, a different boundary, a different row
            f = "Centroids_Morpheus_beta1.0_gamma0.5_replicate4481.csv"
            x, y, g = p15d_xyg(joinpath(tmp, f))
            m0 = P15D.openvt_metrics(x, y, g)
            @test m0 == P15D.openvt_metrics(joinpath(tmp, f))
            k = argmax(x)
            x[k] += 1.0
            m1 = P15D.openvt_metrics(x, y, g)
            @test m1.N == m0.N && m1.g == m0.g
            @test m1.r != m0.r && m1.A != m0.A && m1.C != m0.C
            @test string(f, ",", join(split(chomp(P15D.openvt_metrics_line(m1)), ',')[1:6], ",")) != rows[f]
        end
    end
end

# ── A3: inhibition codes and fractions (M p.2–3, spec C9) ───────────────────────────────────

@testset "P6.15d: A3 inhibition codes and fractions" begin
    code = P15D.openvt_inhibition_code
    @test code(0.9, 0.2; β = 0.9, γ = 0.2) == 0      # a = β and f = γ grow (≥, spec C9)
    @test code(0.89, 0.5; β = 0.9, γ = 0.2) == 1     # type 1 only
    @test code(1.0, 0.19; β = 0.9, γ = 0.2) == 2     # type 2 only
    @test code(0.5, 0.0; β = 0.9, γ = 0.2) == 3      # both
    @test code(prevfloat(0.9), 0.2; β = 0.9, γ = 0.2) == 1   # one ulp below β inhibits
    @test code(0.9, prevfloat(0.2); β = 0.9, γ = 0.2) == 2
    # β = γ = 0 (case a): nothing is ever inhibited, even a = f = 0
    @test all(code(a, f; β = 0.0, γ = 0.0) == 0 for a in (0.0, 0.3, 1.2), f in (0.0, 0.4, 1.0))
    # negative control on C9: the schema's strict `>` would make a = β inhibited; M's ≥ does not
    @test code(0.8, 1.0; β = 0.8, γ = 0.0) == 0 && code(0.8 - 1e-12, 1.0; β = 0.8, γ = 0.0) == 1

    fr = P15D.openvt_inhibition_fractions([0, 0, 1, 2, 3, 3, 3, 0])
    @test keys(fr) == (:uninhibited, :type1, :type2, :both)
    @test fr == (uninhibited = 3 / 8, type1 = 1 / 8, type2 = 1 / 8, both = 3 / 8)
    @test sum(values(fr)) == 1
    @test P15D.openvt_inhibition_fractions(fill(2, 5)) == (uninhibited = 0.0, type1 = 0.0, type2 = 1.0, both = 0.0)
    @test_throws ArgumentError P15D.openvt_inhibition_fractions([0, 4])
    @test_throws ArgumentError P15D.openvt_inhibition_fractions([-1, 0])
    # codes → fractions from per-cell (a, f), one save of an O1 series
    a = [1.0, 0.95, 0.7, 0.85, 0.99, 0.6]
    f = [0.0, 0.3, 0.5, 0.0, 0.25, 0.1]
    i = [code(a[k], f[k]; β = 0.9, γ = 0.25) for k in eachindex(a)]
    @test i == [2, 0, 1, 3, 0, 3]
    @test P15D.openvt_inhibition_fractions(i) == (uninhibited = 2 / 6, type1 = 1 / 6, type2 = 1 / 6, both = 2 / 6)
end

# ── O1–O6 writers ───────────────────────────────────────────────────────────────────────────

function p15d_text(fmt, data)
    io = IOBuffer()
    P15D.write_openvt(io, fmt, data)
    return String(take!(io))
end
p15d_fields(text) = [split(l, ',') for l in split(chomp(text), '\n')]

@testset "P6.15d: O1–O6 writers" begin
    mktempdir() do dir
        rt(fmt, data) = (path = joinpath(dir, "rt_$fmt.csv"); P15D.write_openvt(path, fmt, data); P15D.read_openvt(path, fmt))

        # O1: x,y,i,n
        o1 = (x = [0.1, -2.5, 1 / 3, 1e-5], y = [3.0, 0.2, -7.25, 2 / 7], i = [0, 1, 2, 3], n = [6, 0, 5, 12])
        t = p15d_text(:O1, o1)
        @test startswith(t, "x,y,i,n\n") && endswith(t, "\n") && !occursin("\r", t)
        rows = p15d_fields(t)[2:end]
        @test length(rows) == 4 && all(length(r) == 4 for r in rows)
        @test [r[3] for r in rows] == ["0", "1", "2", "3"] && [r[4] for r in rows] == ["6", "0", "5", "12"]
        @test [parse(Float64, r[1]) for r in rows] == o1.x && [parse(Float64, r[2]) for r in rows] == o1.y
        @test isequal(rt(:O1, o1), o1)
        @test_throws ArgumentError p15d_text(:O1, (x = [1.0], y = [1.0], i = [4], n = [1]))
        @test_throws ArgumentError p15d_text(:O1, (x = [1.0], y = [1.0], i = [0]))
        @test_throws Union{ArgumentError,DimensionMismatch} p15d_text(:O1, (x = [1.0, 2.0], y = [1.0], i = [0], n = [1]))

        # O2: x,y,r,f,a
        o2 = (x = [1.5, -0.25], y = [0.0, 9.875], r = [1.0, 0.9128709291752769], f = [0.0, 0.3125], a = [0.85, 1.1])
        t = p15d_text(:O2, o2)
        @test startswith(t, "x,y,r,f,a\n") && length(p15d_fields(t)) == 3 && all(length(r) == 5 for r in p15d_fields(t))
        @test isequal(rt(:O2, o2), o2)

        # O3: time to 10⁴ cells; 5T = MCS/775; unreached → nan,nan
        o3 = (beta = [0.0, 0.7037, 1.02], mcs = [NaN, 11424.0, 213288.0])
        t = p15d_text(:O3, o3)
        rows = p15d_fields(t)
        @test rows[1] == ["beta", "Time to 10k (MCS)", "Time to 10k (5T)"]
        @test rows[2][2:3] == ["nan", "nan"]
        @test rows[3][2] == "11424" && rows[4][2] == "213288"
        @test parse(Float64, rows[3][3]) == 11424 / 775 && parse(Float64, rows[4][3]) == 213288 / 775
        @test [parse(Float64, r[1]) for r in rows[2:end]] == o3.beta
        @test isequal(rt(:O3, o3), o3)
        o3g = (gamma = [0.0195, 0.5], mcs = [856.0, 1.0e5])
        @test p15d_fields(p15d_text(:O3, o3g))[1] == ["gamma", "Time to 10k (MCS)", "Time to 10k (5T)"]
        @test isequal(rt(:O3, o3g), o3g)
        @test_throws ArgumentError p15d_text(:O3, (delta = [0.1], mcs = [1.0]))

        # O4: relaxation widths, mean and population SD per row
        o4 = (t = [0.0, 0.5, 1.0], widths = [5.0 5.5 6.0; 7.0 7.0 7.0; 8.75 9.0 9.25])
        rows = p15d_fields(p15d_text(:O4, o4))
        @test rows[1] == ["Normalized time (T)", "Tissue width rep1 (CD)", "Tissue width rep2 (CD)",
            "Tissue width rep3 (CD)", "Mean Tissue width (CD)", "STD Tissue width (CD)"]
        @test length(rows) == 4 && all(length(r) == 6 for r in rows)
        @test [parse(Float64, r[5]) for r in rows[2:end]] ≈ [5.5, 7.0, 9.0] rtol = 1e-15
        @test [parse(Float64, r[6]) for r in rows[2:end]] ≈ [sqrt(1 / 6), 0.0, sqrt(1 / 24)] rtol = 1e-14 atol = 1e-15
        @test parse(Float64, rows[3][6]) == 0
        @test isequal(rt(:O4, o4), o4)

        # O5: final snapshots
        o5 = (x_pos = [197.233, -3.5], y_pos = [187.925, 0.0], radius_i = [1.01602, 1.19135], inhibited = [1, 0])
        t = p15d_text(:O5, o5)
        @test startswith(t, "x_pos,y_pos,radius_i,inhibited\n")
        @test [r[4] for r in p15d_fields(t)[2:end]] == ["1", "0"]
        @test isequal(rt(:O5, o5), o5)

        # O6: t (perl %.15g) + the metrics.cpp line
        ms = [P15D.openvt_metrics([5.0], [7.0], [1]),
            P15D.openvt_metrics([0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [1, 0, 1]),
            P15D.openvt_metrics([0.0, 1.0, 1.0, 0.0, 0.5], [0.0, 0.0, 1.0, 1.0, 0.5], [1, 0, 1, 1, 0])]
        o6 = (t = [0.0, 5 / 97, 1.0], metrics = ms)
        @test p15d_text(:O6, o6) == "t,N,r,A,C,w,g,C_rel,w_rel\n" *
            "0,1,nan,nan,nan,nan,1,nan,nan\n" *
            "0.0515463917525773,3,0.654039,0.5,3.41421,0.158166,0.666667,1.36207,0.24183\n" *
            "1,5,0.707107,1,4,0,0.6,1.12838,0\n"
        back = rt(:O6, o6)
        @test keys(back) == (:t, :N, :r, :A, :C, :w, :g, :C_rel, :w_rel)
        @test back.N == [1, 3, 5]
        @test back.t ≈ o6.t rtol = 1e-14
        @test isnan(back.r[1]) && isnan(back.w_rel[1])
        @test back.r[2:3] ≈ [ms[2].r, ms[3].r] rtol = 1e-5
        @test back.g ≈ [1, 2 / 3, 0.6] rtol = 1e-5
        nb = P15D.openvt_neighbor_histogram([1, 1, 2])
        @test isequal(rt(:O6_neighbors, nb), (n = [0, 1, 2], p = [0.0, 66.6667, 33.3333]))

        @test_throws ArgumentError p15d_text(:O7, o1)
    end

    # file names (spec §3.1)
    @test P15D.openvt_filename(:O1; case = "a", seed = 3, mcs = 780) == "potts_a_s3_000780.csv"
    @test P15D.openvt_filename(:O1; case = :b, seed = 12, mcs = 10517) == "potts_b_s12_010517.csv"
    @test P15D.openvt_filename(:O2; k = 7) == joinpath("Potts.jl_5T_MonolayerGrowth_1000_Data", "cell_data_no_inhibition_7.csv")
    @test P15D.openvt_filename(:O3; parameter = :beta) == "Potts.jl_time_to_10k_vs_beta.csv"
    @test P15D.openvt_filename(:O3; parameter = :gamma) == "Potts.jl_time_to_10k_vs_gamma.csv"
    @test P15D.openvt_filename(:O5; gamma = 0.12, mcs = 52965) == "Potts.jl_gamma_0.12_52965MCS.csv"
    @test_throws ArgumentError P15D.openvt_filename(:O3; parameter = :delta)
end
