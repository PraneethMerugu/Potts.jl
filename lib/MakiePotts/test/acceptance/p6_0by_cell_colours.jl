# Frozen acceptance test for P6.0by (D-172): automatic per-cell colours separate
# neighbouring ids. Run alone with
#     julia --project=lib/MakiePotts/test lib/MakiePotts/test/acceptance/p6_0by_cell_colours.jl
# or include it from `lib/MakiePotts/test/runtests.jl`.
#
# The defect (AUDIT A-80). `CellIdentityEncoding` keys a cell by
# `(UInt64(id) << 32) ⊻ generation`, and the automatic palette maps a key to the hue
# `frac(key · φ⁻¹)`. Since frac(2³² · φ⁻¹) ≈ 0.497, hues alternate between about 0.5 and
# about 1.0 and drift −0.005 per id: ids two apart get nearly the same colour. Cells born
# together are neighbours and we never draw cell outlines, so a colony looks like two
# colours. From id 2²⁰ up the product exceeds Float64's integer range and hue resolution
# collapses; near id 4·10⁹ every cell gets the same colour.
#
# Pinned at the colour level (no rendering), through the path every recipe and legend
# uses: a `PottsRenderFrame` → `encode(frame, CellIdentityEncoding())` → the automatic
# palette (`MakiePotts._categorical_colors(entries, Makie.automatic, medium)`). The colour
# key, hash and palette are free: the measure is perceptual (CIE Lab ΔE*76 from the sRGB
# colour), so any saturation, value or palette works.
#
# (a) neighbour separation: ids at distance 1..8 are confusable (ΔE < 10) for at most 12 %
#     of pairs, at each distance, for generations 0 and 1, for ids 1..2000 and for two
#     high-id windows (a random hue gives about 5 %; the current formula gives 100 % at
#     even distances);
# (b) determinism and stability: a cell's colour is a function of its identity only — the
#     same across calls, frames, MCS, site layout and which other cells are present;
# (c) generation distinguishes: the same id at another generation gets another colour
#     (≤ 12 % confusable), as the key and legend are generation-aware;
# (d) spread: the hues of ids 1..2000 cover every twelfth of the hue circle, and ≥ 95 % of
#     16-id windows of consecutive ids touch ≥ 6 of the 12 hue bins;
# (e) negative control: the metric run on a local copy of the old formula fails (a), (d)
#     and the high-id case, and passes on a local good reference (splitmix64, then hue);
# (f) regression guard: `CellTypeEncoding` colours for types 1..8 stay pairwise distinct
#     (ΔE ≥ 15; the current palette gives ≥ 23).
using Test
using MakiePotts
import Makie

const CONFUSABLE_DE = 10.0     # ΔE*76 below this reads as "the same colour" at cell scale
const MAX_CONFUSABLE = 0.12    # per distance; a uniform random hue gives ≈ 0.05
const DISTANCES = 1:8

# --- colour measure (implementation-independent) ---------------------------------------

_linear(c) = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)^2.4
_labf(t) = t > 216 / 24389 ? cbrt(t) : (24389 / 27 * t + 16) / 116

"""sRGB triple → CIE Lab (D65)."""
function _lab(rgb::NTuple{3, Float64})
    r, g, b = map(_linear, rgb)
    x = 0.4124564r + 0.3575761g + 0.1804375b
    y = 0.2126729r + 0.7151522g + 0.0721750b
    z = 0.0193339r + 0.1191920g + 0.9503041b
    fx, fy, fz = _labf(x / 0.95047), _labf(y), _labf(z / 1.08883)
    return (116fy - 16, 500(fx - fy), 200(fy - fz))
end
_delta_e(a, b) = sqrt(sum(abs2, a .- b))

function _hue(rgb::NTuple{3, Float64})
    r, g, b = rgb
    hi, lo = max(r, g, b), min(r, g, b)
    chroma = hi - lo
    chroma == 0 && return NaN
    h = hi == r ? mod((g - b) / chroma, 6) : hi == g ? (b - r) / chroma + 2 : (r - g) / chroma + 4
    return h / 6
end

function _triple(colour)
    c = convert(Makie.RGBf, Makie.to_color(colour))
    return (Float64(c.r), Float64(c.g), Float64(c.b))
end

"""Fraction of pairs (i, i + d) in a colour sequence that are confusable, for each d."""
confusable_fractions(colours) = map(DISTANCES) do d
    labs = map(_lab, colours)
    n = length(labs) - d
    count(i -> _delta_e(labs[i], labs[i + d]) < CONFUSABLE_DE, 1:n) / n
end

hue_bins(colours) = Set(floor(Int, 12 * h) for h in map(_hue, colours) if isfinite(h))

function window_bin_counts(colours; width = 16)
    return [length(hue_bins(colours[s:(s + width - 1)])) for s in 1:width:(length(colours) - width + 1)]
end

# --- the package path: frame → encoding → automatic palette ---------------------------

"""A single-row frame owned entirely by the given cells, in the given site order."""
function identity_frame(identities; mcs = 0)
    owners = reshape([RenderOwner(CellSite, x.id) for x in identities], :, 1)
    cells = [RenderCellMetadata(x, 1) for x in identities]
    return PottsRenderFrame(mcs, owners, cells)
end

"""Automatic colours of each identity, as sRGB triples, keyed by identity."""
function package_colours(frame, encoding = CellIdentityEncoding())
    entries = legend_entries(frame, encoding)
    colours = MakiePotts._categorical_colors(entries, Makie.automatic, :black)
    @assert length(colours) == length(entries)
    return Dict(entries[k].value => _triple(colours[k]) for k in 2:length(entries))
end

"""Automatic colours of ids `ids` at one generation, in id order."""
function package_sequence(ids, generation)
    identities = [RenderCellIdentity(id, generation) for id in ids]
    table = package_colours(identity_frame(identities))
    return [table[x] for x in identities]
end

# --- local references: the old formula (negative control) and a good hash -------------

function _ref_hsv(h, s = 0.62, v = 0.88)
    sector = 6h
    i = floor(Int, sector)
    f = sector - i
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    m = mod(i, 6)
    return m == 0 ? (v, t, p) : m == 1 ? (q, v, p) : m == 2 ? (p, v, t) :
           m == 3 ? (p, q, v) : m == 4 ? (t, p, v) : (v, p, q)
end
_ref_key(id, generation) = (UInt64(id) << 32) ⊻ UInt64(generation)
"""The formula on the base (bba4d963): golden-ratio hue of the raw key."""
old_colour(id, generation) = _ref_hsv(mod(Float64(_ref_key(id, generation)) * 0.6180339887498949, 1.0))

function _splitmix64(x::UInt64)
    x += 0x9e3779b97f4a7c15
    x = (x ⊻ (x >> 30)) * 0xbf58476d1ce4e5b9
    x = (x ⊻ (x >> 27)) * 0x94d049bb133111eb
    return x ⊻ (x >> 31)
end
"""A good reference: splitmix64 of the key, its top 53 bits as the hue."""
good_colour(id, generation) = _ref_hsv(Float64(_splitmix64(_ref_key(id, generation)) >> 11) * 2.0^-53)

passes_separation(colours) = all(<=(MAX_CONFUSABLE), confusable_fractions(colours))

const LOW_IDS = 1:2000
const HIGH_WINDOWS = (2^20:(2^20 + 2000), 4_000_000_000:4_000_002_000)

@testset "P6.0by per-cell colours separate neighbouring ids (D-172)" begin
    @testset "(e) negative control: the metric catches the old formula" begin
        for generation in (0, 1)
            old = [old_colour(id, generation) for id in LOW_IDS]
            fractions = confusable_fractions(old)
            @test fractions[2] > 0.9 && fractions[4] > 0.9     # ids two and four apart
            @test !passes_separation(old)
            @test count(<(6), window_bin_counts(old)) > 0.9 * length(window_bin_counts(old))
            good = [good_colour(id, generation) for id in LOW_IDS]
            @test passes_separation(good)
            @test length(hue_bins(good)) == 12
            @test count(>=(6), window_bin_counts(good)) >= 0.95 * length(window_bin_counts(good))
        end
        far = [old_colour(id, 1) for id in last(HIGH_WINDOWS)]
        @test all(==(1.0), confusable_fractions(far))          # one colour for every cell
        @test passes_separation([good_colour(id, 1) for id in last(HIGH_WINDOWS)])
        # Old type colours pass the guard (f), so (f) only forbids regressions.
        old_types = [_lab(_ref_hsv(mod(t * 0.6180339887498949, 1.0))) for t in 1:8]
        @test minimum(_delta_e(old_types[i], old_types[j]) for i in 1:8 for j in (i + 1):8) >= 15
    end

    @testset "(a) neighbouring ids get clearly different colours" begin
        for generation in (0, 1)
            fractions = confusable_fractions(package_sequence(LOW_IDS, generation))
            for (d, fraction) in zip(DISTANCES, fractions)
                @test fraction <= MAX_CONFUSABLE
            end
        end
        for window in HIGH_WINDOWS
            fractions = confusable_fractions(package_sequence(window, 1))
            @test all(<=(MAX_CONFUSABLE), fractions)
        end
    end

    @testset "(b) a cell's colour depends only on its identity" begin
        ids = 1:80
        whole = package_colours(identity_frame([RenderCellIdentity(id, 1) for id in ids]))
        again = package_colours(identity_frame([RenderCellIdentity(id, 1) for id in ids]))
        @test whole == again
        # Another frame: other MCS, another subset, reversed and shuffled site order,
        # 2D layout. Every shared cell keeps its colour.
        subset = [RenderCellIdentity(id, 1) for id in reverse(25:80)]
        shuffled = subset[[mod1(5k, length(subset)) for k in eachindex(subset)]]
        @test allunique(shuffled)
        later = package_colours(identity_frame(shuffled; mcs = 500))
        @test all(later[x] == whole[x] for x in subset)
        owners = fill(RenderOwner(MediumSite, 1), 6, 4)
        owners[2, 2] = RenderOwner(CellSite, 30)
        owners[5, 3] = RenderOwner(CellSite, 31)
        sparse = PottsRenderFrame(7, owners,
            [RenderCellMetadata(RenderCellIdentity(30, 1), 2),
             RenderCellMetadata(RenderCellIdentity(31, 1), 3)])
        sparse_colours = package_colours(sparse)
        @test sparse_colours[RenderCellIdentity(30, 1)] == whole[RenderCellIdentity(30, 1)]
        @test sparse_colours[RenderCellIdentity(31, 1)] == whole[RenderCellIdentity(31, 1)]
    end

    @testset "(c) another generation of the same id gets another colour" begin
        ids = 1:500
        first_generation = package_sequence(ids, 1)
        second_generation = package_sequence(ids, 2)
        @test all(first_generation .!= second_generation)
        confusable = count(i -> _delta_e(_lab(first_generation[i]), _lab(second_generation[i])) <
                               CONFUSABLE_DE, eachindex(ids))
        @test confusable <= MAX_CONFUSABLE * length(ids)
    end

    @testset "(d) colours spread over the hue circle" begin
        for generation in (0, 1)
            colours = package_sequence(LOW_IDS, generation)
            @test length(hue_bins(colours)) == 12
            windows = window_bin_counts(colours)
            @test count(>=(6), windows) >= 0.95 * length(windows)
        end
    end

    @testset "(f) cell-type colours stay distinct" begin
        owners = reshape([RenderOwner(CellSite, t) for t in 1:8], :, 1)
        cells = [RenderCellMetadata(RenderCellIdentity(t, 1), t) for t in 1:8]
        types = package_colours(PottsRenderFrame(0, owners, cells), CellTypeEncoding())
        labs = [_lab(types[t]) for t in UInt32(1):UInt32(8)]
        @test minimum(_delta_e(labs[i], labs[j]) for i in 1:8 for j in (i + 1):8) >= 15
    end
end
