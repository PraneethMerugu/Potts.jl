"""
Abstract supertype for complete Potts render frames with `N` spatial
dimensions. Downstream implementations conform through the exported accessor
protocol and [`render_frame_conformance`](@ref).
"""
abstract type AbstractPottsRenderFrame{N} end

"""Enumeration describing the semantic owner kind of one lattice site."""
@enum RenderOwnerKind::UInt8 begin
    CellSite = 0x01
    MediumSite = 0x02
    ObstacleSite = 0x03
end
@doc "A lattice site owned by a finite, generation-aware cell." CellSite
@doc "A mutable lattice site owned by a medium domain." MediumSite
@doc "An immutable lattice site owned by a medium domain." ObstacleSite

"""
    RenderOwner(kind, id)

The owner of one rendered lattice site: a cell or a medium.

Two owners are equal when kind and number are equal. Frames built by
[`renderframe`](@ref) give every medium and obstacle site the number 1.

# Arguments

  - `kind::RenderOwnerKind`: [`CellSite`](@ref), [`MediumSite`](@ref) or
    [`ObstacleSite`](@ref).
  - `id::Integer`: the cell number for `CellSite`, the medium number otherwise; in
    `1:typemax(UInt32)`. Throws an `ArgumentError` otherwise.

# Fields

  - `kind::RenderOwnerKind`, `id::UInt32`: as given.

# Examples

```jldoctest
julia> using MakiePotts

julia> RenderOwner(CellSite, 3) == RenderOwner(CellSite, 3)
true
```

See also [`owner_at`](@ref), [`RenderCellIdentity`](@ref).
"""
struct RenderOwner
    kind::RenderOwnerKind
    id::UInt32

    function RenderOwner(kind::RenderOwnerKind, id::Integer)
        0 < id <= typemax(UInt32) ||
            throw(ArgumentError("render owner identity must fit UInt32 and be positive"))
        return new(kind, UInt32(id))
    end
end
function Base.:(==)(left::RenderOwner, right::RenderOwner)
    return left.kind === right.kind && left.id == right.id
end
function Base.hash(owner::RenderOwner, seed::UInt)
    return hash(owner.id, hash(owner.kind, seed))
end

"""
    RenderCellIdentity(id, generation)

The identity of one cell: its number and the generation of that number.

A cell number is reused after its cell is gone; the generation tells the two cells apart
(`CorePotts.cell_generations`). Two identities are equal when both parts are equal.

# Arguments

  - `id::Integer`: the cell number, in `1:typemax(UInt32)`.
  - `generation::Integer`: the generation, in `0:typemax(UInt64)`.

Throws an `ArgumentError` for a value outside its range.

# Fields

  - `id::UInt32`, `generation::UInt64`: as given.

# Examples

```jldoctest
julia> using MakiePotts

julia> RenderCellIdentity(4, 2) == RenderCellIdentity(4, 1)
false
```

See also [`RenderCellMetadata`](@ref), [`CellChannelKey`](@ref).
"""
struct RenderCellIdentity
    id::UInt32
    generation::UInt64

    function RenderCellIdentity(id::Integer, generation::Integer)
        0 < id <= typemax(UInt32) ||
            throw(ArgumentError("cell identity must fit UInt32 and be positive"))
        0 <= generation <= typemax(UInt64) ||
            throw(ArgumentError("cell generation must fit UInt64 and be nonnegative"))
        return new(UInt32(id), UInt64(generation))
    end
end
function Base.:(==)(left::RenderCellIdentity, right::RenderCellIdentity)
    return left.id == right.id && left.generation == right.generation
end
function Base.hash(identity::RenderCellIdentity, seed::UInt)
    return hash(identity.generation, hash(identity.id, seed))
end

"""
    RenderCellMetadata(identity, cell_type; label = "Cell \$(identity.id)")

The metadata of one live cell in a frame: its identity, its cell type and its name.

# Arguments

  - `identity::RenderCellIdentity`: the cell.
  - `cell_type::Integer`: the cell type number, in `1:typemax(UInt32)`. Throws an
    `ArgumentError` otherwise. [`renderframe`](@ref) uses the kind number of the cell.

# Keywords

  - `label::AbstractString`: the name of the cell; `"Cell n"` for cell number `n` by
    default.

# Fields

  - `identity::RenderCellIdentity`, `cell_type::UInt32`, `label::String`: as given.

# Examples

```jldoctest
julia> using MakiePotts

julia> RenderCellMetadata(RenderCellIdentity(4, 1), 2).label
"Cell 4"
```

See also [`cell_metadata`](@ref), [`PottsRenderFrame`](@ref).
"""
struct RenderCellMetadata
    identity::RenderCellIdentity
    cell_type::UInt32
    label::String

    function RenderCellMetadata(
            identity::RenderCellIdentity, cell_type::Integer;
            label::AbstractString = "Cell $(identity.id)"
        )
        0 < cell_type <= typemax(UInt32) ||
            throw(ArgumentError("cell type must fit UInt32 and be positive"))
        return new(identity, UInt32(cell_type), String(label))
    end
end
function Base.:(==)(left::RenderCellMetadata, right::RenderCellMetadata)
    return left.identity == right.identity &&
        left.cell_type == right.cell_type &&
        left.label == right.label
end
function Base.hash(metadata::RenderCellMetadata, seed::UInt)
    return hash(
        metadata.label,
        hash(metadata.cell_type, hash(metadata.identity, seed))
    )
end

"""
    RenderGeometry(size; spacing = (1.0, …), origin = (0.0, …),
        source_axes = (1, 2, …))

The physical geometry of a 2D or 3D ownership array.

Site `i` along axis `k` covers `origin[k] + (i - 1) * spacing[k]` to
`origin[k] + i * spacing[k]`; plots center it between the two. Two geometries are equal
when all four fields are equal.

# Arguments

  - `size::NTuple{N, Integer}`: the number of sites on each axis, positive, with `N` 2
    or 3.

# Keywords

  - `spacing`: the site width on each axis, positive and finite.
  - `origin`: the lower edge of the first site on each axis, finite.
  - `source_axes`: the axis of the source array that each axis shows, positive and
    unique. An [`OrthogonalSlice`](@ref) of axis 3 gives `(1, 2)`.

Throws an `ArgumentError` for a value that breaks these rules.

# Fields

  - `size::NTuple{N, Int}`, `spacing::NTuple{N, T}`, `origin::NTuple{N, T}`,
    `source_axes::NTuple{N, Int}`, with `T` the float type of `spacing` and `origin`
    promoted together.

# Examples

```jldoctest
julia> using MakiePotts

julia> RenderGeometry((4, 3); spacing = (0.5, 0.5)).spacing
(0.5, 0.5)
```

See also [`frame_geometry`](@ref).
"""
struct RenderGeometry{N, T <: AbstractFloat}
    size::NTuple{N, Int}
    spacing::NTuple{N, T}
    origin::NTuple{N, T}
    source_axes::NTuple{N, Int}

    function RenderGeometry(
            size::NTuple{N, <:Integer};
            spacing = ntuple(_ -> 1.0, Val(N)),
            origin = ntuple(_ -> 0.0, Val(N)),
            source_axes = ntuple(identity, Val(N))
        ) where {N}
        N in (2, 3) || throw(
            ArgumentError(
                "render geometry supports two or three dimensions"
            )
        )
        normalized_size = ntuple(i -> Int(size[i]), Val(N))
        all(>(0), normalized_size) ||
            throw(ArgumentError("render geometry dimensions must be positive"))
        T = float(promote_type(map(typeof, spacing)..., map(typeof, origin)...))
        normalized_spacing = ntuple(i -> convert(T, spacing[i]), Val(N))
        normalized_origin = ntuple(i -> convert(T, origin[i]), Val(N))
        all(value -> isfinite(value) && value > zero(T), normalized_spacing) ||
            throw(ArgumentError("render spacing must be positive and finite"))
        all(isfinite, normalized_origin) ||
            throw(ArgumentError("render origin must be finite"))
        normalized_axes = ntuple(i -> Int(source_axes[i]), Val(N))
        all(>(0), normalized_axes) ||
            throw(ArgumentError("source axes must be positive"))
        length(unique(normalized_axes)) == N ||
            throw(ArgumentError("source axes must be unique"))
        return new{N, T}(
            normalized_size, normalized_spacing, normalized_origin,
            normalized_axes
        )
    end
end
function Base.:(==)(left::RenderGeometry, right::RenderGeometry)
    return left.size == right.size &&
        left.spacing == right.spacing &&
        left.origin == right.origin &&
        left.source_axes == right.source_axes
end
function Base.hash(geometry::RenderGeometry, seed::UInt)
    return hash(
        geometry.source_axes,
        hash(geometry.origin, hash(geometry.spacing, hash(geometry.size, seed)))
    )
end

"""
    RenderProvenance(source, source_type, residency, request)

Where the data of a render frame came from.

# Arguments

  - `source::Symbol`: the kind of source; `:saved_state` for a frame from
    [`renderframe`](@ref), `:manual` by default for a frame built directly.
  - `source_type`: the type of the source (stored as its `String` name).
  - `residency::Symbol`: where the source data were; `:host` for both cases above.
  - `request`: the [`RenderRequest`](@ref) used.

# Fields

  - `source::Symbol`, `source_type::String`, `residency::Symbol`, `request`.

See also [`frame_provenance`](@ref).
"""
struct RenderProvenance{R}
    source::Symbol
    source_type::String
    residency::Symbol
    request::R
end

function RenderProvenance(
        source::Symbol, source_type::Type, residency::Symbol,
        request::RenderRequest
    )
    return RenderProvenance(source, string(source_type), residency, request)
end

"""
    PottsRenderFrame(mcs, owners, cells; channels = (),
        geometry = RenderGeometry(size(owners)),
        provenance = RenderProvenance(:manual, typeof(owners), :host, RenderRequest()))

A checked snapshot of one Potts frame, ready to plot.

The constructor checks the inputs and copies the mutable ones (owners, cells and channel
values), so later changes to the inputs do not reach the frame. Treat the frame as
read-only and read it through [`frame_mcs`](@ref), [`frame_size`](@ref),
[`frame_geometry`](@ref), [`owner_at`](@ref), [`cell_metadata`](@ref),
[`available_channels`](@ref), [`frame_channel`](@ref) and [`frame_provenance`](@ref).

# Arguments

  - `mcs::Integer`: the MCS of the frame, nonnegative.
  - `owners::AbstractArray{RenderOwner, N}`: the owner of each site, with `N` 2 or 3.
  - `cells::AbstractVector{RenderCellMetadata}`: the metadata of the cells. Cell numbers
    are unique, and every cell owner in `owners` has an entry.

# Keywords

  - `channels::Tuple`: [`RenderChannel`](@ref) values with unique keys. Site values are
    of the size of `owners`, cell identities belong to `cells` with the same generation,
    and every value is of its key's value type or `missing`.
  - `geometry::RenderGeometry{N}`: of the size of `owners`.
  - `provenance`: a [`RenderProvenance`](@ref).

Throws `MakiePotts.InvalidRenderFrameError`, which lists every broken rule.

# Fields

None public. Use the accessors above.

# Examples

```jldoctest
julia> using MakiePotts

julia> c, m = RenderOwner(CellSite, 1), RenderOwner(MediumSite, 1);

julia> cell = RenderCellMetadata(RenderCellIdentity(1, 1), 1);

julia> frame = PottsRenderFrame(5, [c m; c m], [cell]);

julia> frame_mcs(frame), frame_size(frame)
(5, (2, 2))
```

See also [`renderframe`](@ref), [`render_frame_conformance`](@ref).
"""
struct PottsRenderFrame{
        N, O <: AbstractArray{RenderOwner, N},
        M <: AbstractVector{RenderCellMetadata}, C <: Tuple, G, P,
    } <:
    AbstractPottsRenderFrame{N}
    mcs::Int
    owners::O
    cells::M
    channels::C
    geometry::G
    provenance::P
    cell_lookup::Dict{UInt32, Int}
end

function _frame_errors(mcs, owners, cells, channels, geometry)
    errors = String[]
    mcs >= 0 || push!(errors, "MCS must be nonnegative")
    size(owners) == geometry.size ||
        push!(errors, "ownership size must equal geometry size")

    lookup = Dict{UInt32, RenderCellMetadata}()
    for cell in cells
        haskey(lookup, cell.identity.id) &&
            push!(errors, "finite-cell IDs must be unique within one frame")
        lookup[cell.identity.id] = cell
    end
    for owner in owners
        owner.kind === CellSite && !haskey(lookup, owner.id) &&
            push!(errors, "every finite owner must have generation-aware metadata")
    end

    all(item -> item isa RenderChannel, channels) ||
        push!(errors, "channels must be RenderChannel values")
    valid_channels = filter(item -> item isa RenderChannel, channels)
    channel_keys = map(item -> item.key, valid_channels)
    length(unique(channel_keys)) == length(channel_keys) ||
        push!(errors, "render channel keys must be unique")
    for item in valid_channels
        if item.key isa RenderChannelKey{SiteChannelScope}
            item.values isa AbstractArray ||
                push!(errors, "site-channel values must be an array")
            item.values isa AbstractArray && size(item.values) != size(owners) &&
                push!(errors, "site-channel size must equal ownership size")
        elseif item.key isa RenderChannelKey{CellChannelScope}
            item.values isa AbstractDict ||
                push!(errors, "cell-channel values must be identity-keyed")
            if item.values isa AbstractDict
                for identity in keys(item.values)
                    identity isa RenderCellIdentity ||
                        push!(errors, "cell-channel keys must be RenderCellIdentity values")
                    identity isa RenderCellIdentity && !haskey(lookup, identity.id) &&
                        push!(errors, "cell-channel identities must belong to the frame")
                    identity isa RenderCellIdentity && haskey(lookup, identity.id) &&
                        lookup[identity.id].identity != identity &&
                        push!(errors, "cell-channel identities must match cell generations")
                end
            end
        elseif item.key isa RenderChannelKey{MediumChannelScope}
            item.values isa AbstractDict ||
                push!(errors, "medium-channel values must be domain-ID-keyed")
            if item.values isa AbstractDict
                all(key -> key isa Integer && key > 0, keys(item.values)) || push!(
                    errors,
                    "medium-channel keys must be positive integer domain IDs"
                )
            end
        end
        if item.values isa AbstractArray || item.values isa AbstractDict
            expected = _channel_value_type(item.key)
            all(value -> ismissing(value) || value isa expected, values(item.values)) ||
                push!(
                errors,
                "render channel $(item.key) contains a value outside its declared type"
            )
        end
    end
    return unique(errors)
end

_channel_value_type(::RenderChannelKey{S, T}) where {S, T} = T

function PottsRenderFrame(
        mcs::Integer, owners::AbstractArray{RenderOwner, N},
        cells::AbstractVector{RenderCellMetadata};
        channels::Tuple = (),
        geometry::RenderGeometry{N} = RenderGeometry(size(owners)),
        provenance = RenderProvenance(:manual, typeof(owners), :host, RenderRequest())
    ) where {N}
    errors = _frame_errors(Int(mcs), owners, cells, channels, geometry)
    isempty(errors) || throw(InvalidRenderFrameError(errors))
    frozen_owners = copy(owners)
    frozen_cells = collect(cells)
    frozen_channels = map(channels) do item
        values = if item.values isa AbstractArray || item.values isa AbstractDict
            copy(item.values)
        else
            item.values
        end
        RenderChannel(item.key, values; label = item.label, units = item.units)
    end
    lookup = Dict(cell.identity.id => index for (index, cell) in pairs(frozen_cells))
    return PottsRenderFrame{
        N, typeof(frozen_owners), typeof(frozen_cells),
        typeof(frozen_channels), typeof(geometry), typeof(provenance),
    }(
        Int(mcs), frozen_owners, frozen_cells, frozen_channels,
        geometry, provenance, lookup
    )
end

"""
    frame_mcs(frame) -> Int

Return the MCS of a render frame.

# Arguments

  - `frame::PottsRenderFrame`: the frame.

# Returns

  - `Int`: the MCS.

See also [`frame_size`](@ref), [`PottsRenderFrame`](@ref).
"""
frame_mcs(frame::PottsRenderFrame) = frame.mcs
"""
    frame_size(frame) -> NTuple{N, Int}

Return the number of sites on each axis of a render frame. `size(frame)` is the same.

# Arguments

  - `frame::PottsRenderFrame`: the frame.

# Returns

  - `NTuple{N, Int}`: the size, with `N` 2 or 3.

See also [`frame_geometry`](@ref).
"""
frame_size(frame::PottsRenderFrame) = frame.geometry.size
"""
    frame_geometry(frame) -> RenderGeometry

Return the physical geometry of a render frame.

# Arguments

  - `frame::PottsRenderFrame`: the frame.

# Returns

  - [`RenderGeometry`](@ref): the geometry.

See also [`frame_size`](@ref).
"""
frame_geometry(frame::PottsRenderFrame) = frame.geometry
"""
    frame_provenance(frame) -> RenderProvenance

Return the record of where the data of a render frame came from.

# Arguments

  - `frame::PottsRenderFrame`: the frame.

# Returns

  - [`RenderProvenance`](@ref): the record.

See also [`renderframe`](@ref).
"""
frame_provenance(frame::PottsRenderFrame) = frame.provenance
"""
    owner_at(frame, site) -> RenderOwner

Return the owner of `site` in a render frame.

# Arguments

  - `frame::PottsRenderFrame`: the frame.
  - `site`: any index of the ownership array, for example a `CartesianIndex`.

# Returns

  - [`RenderOwner`](@ref): the owner.

See also [`cell_metadata`](@ref).
"""
owner_at(frame::PottsRenderFrame, site) = frame.owners[site]

"""
    cell_metadata(frame, identity::RenderCellIdentity) -> RenderCellMetadata
    cell_metadata(frame, owner::RenderOwner) -> RenderCellMetadata

Return the metadata of a cell in a render frame, from its identity or from a cell owner.

A frame type of another package that subtypes [`AbstractPottsRenderFrame`](@ref)
implements both methods ([`render_frame_conformance`](@ref) checks that they agree).

# Arguments

  - `frame::PottsRenderFrame`: the frame.
  - `identity::RenderCellIdentity`: the cell. Throws a `KeyError` when the frame has no
    cell with this number and generation.
  - `owner::RenderOwner`: a `CellSite` owner. Throws an `ArgumentError` for another kind
    and a `KeyError` when the frame has no cell with this number.

# Returns

  - [`RenderCellMetadata`](@ref): the metadata.

See also [`owner_at`](@ref).
"""
function cell_metadata(frame::PottsRenderFrame, identity::RenderCellIdentity)
    index = get(frame.cell_lookup, identity.id, nothing)
    index === nothing && throw(KeyError(identity))
    metadata = frame.cells[index]
    metadata.identity == identity || throw(KeyError(identity))
    return metadata
end

function cell_metadata(frame::PottsRenderFrame, owner::RenderOwner)
    owner.kind === CellSite || throw(ArgumentError("site owner is not a finite cell"))
    index = get(frame.cell_lookup, owner.id, nothing)
    index === nothing && throw(KeyError(owner.id))
    return frame.cells[index]
end

"""
    available_channels(frame) -> Tuple

Return the keys of the channels of a render frame, in the order they were given.

# Arguments

  - `frame::PottsRenderFrame`: the frame.

# Returns

  - `Tuple`: the [`RenderChannelKey`](@ref) values.

See also [`frame_channel`](@ref).
"""
available_channels(frame::PottsRenderFrame) = map(item -> item.key, frame.channels)

"""
    frame_channel(frame, key) -> RenderChannel

Return the channel of a render frame with key `key`.

# Arguments

  - `frame::PottsRenderFrame`: the frame.
  - `key::RenderChannelKey`: the key. Throws `MakiePotts.MissingRenderChannelError`,
    which lists the keys the frame has, when no channel matches.

# Returns

  - [`RenderChannel`](@ref): the channel.

See also [`available_channels`](@ref).
"""
function frame_channel(frame::PottsRenderFrame, key::RenderChannelKey)
    index = findfirst(item -> item.key == key, frame.channels)
    index === nothing && throw(
        MissingRenderChannelError(
            key, Any[available_channels(frame)...]
        )
    )
    return frame.channels[index]
end

Base.size(frame::PottsRenderFrame) = frame_size(frame)
Base.ndims(::AbstractPottsRenderFrame{N}) where {N} = N

"""
    RenderFrameConformance(valid, issues)

The result of [`render_frame_conformance`](@ref). `isvalid(report)` is `report.valid`.

# Fields

  - `valid::Bool`: `true` when no check failed.
  - `issues::Vector{String}`: one message per failed check, without repeats.

See also [`assert_render_frame_conformance`](@ref).
"""
struct RenderFrameConformance
    valid::Bool
    issues::Vector{String}
end
Base.isvalid(report::RenderFrameConformance) = report.valid

@inline function _probe_frame(issues::Vector{String}, label::AbstractString, f::F) where {F}
    try
        return true, f()
    catch error
        isfatal(error) && rethrow()
        push!(issues, "$label: $(sprint(showerror, error))")
        return false, nothing
    end
end

"""
    render_frame_conformance(frame) -> RenderFrameConformance

Check that a render frame answers the accessor functions correctly.

The check calls only the accessors (`frame_mcs`, `frame_size`, `frame_geometry`,
`owner_at` at every site, both `cell_metadata` methods for each cell site,
`available_channels`, `frame_channel` and `frame_provenance`), so it applies to a frame
type of another package that subtypes [`AbstractPottsRenderFrame`](@ref). An accessor
that throws is reported as an issue, not rethrown (except for fatal errors such as
`InterruptException`). The site loop stops at the first failing site.

# Arguments

  - `frame::AbstractPottsRenderFrame`: the frame.

# Returns

  - [`RenderFrameConformance`](@ref): the result.

# Examples

```jldoctest
julia> using MakiePotts

julia> m = RenderOwner(MediumSite, 1);

julia> frame = PottsRenderFrame(0, [m m; m m], RenderCellMetadata[]);

julia> isvalid(render_frame_conformance(frame))
true
```

See also [`assert_render_frame_conformance`](@ref).
"""
function render_frame_conformance(frame::AbstractPottsRenderFrame{N}) where {N}
    issues = String[]
    N in (2, 3) || push!(issues, "frame dimensionality must be two or three")
    _, mcs = _probe_frame(issues, "frame_mcs failed", () -> frame_mcs(frame))
    mcs isa Integer && mcs >= 0 ||
        push!(issues, "frame_mcs must return a nonnegative integer")
    _, dims = _probe_frame(issues, "frame_size failed", () -> frame_size(frame))
    dims isa NTuple{N, Int} && all(>(0), dims) ||
        push!(issues, "frame_size must return positive Int dimensions")
    _, geometry = _probe_frame(issues, "frame_geometry failed", () -> frame_geometry(frame))
    if !(geometry isa RenderGeometry{N})
        push!(issues, "frame_geometry must return RenderGeometry{$N}")
    elseif dims !== nothing && geometry.size != dims
        push!(issues, "frame geometry and ownership dimensions must agree")
    end
    if dims isa NTuple{N, Int}
        for site in CartesianIndices(dims)
            ok, owner = _probe_frame(issues, "owner_at failed", () -> owner_at(frame, site))
            ok || break
            owner isa RenderOwner || begin
                push!(issues, "owner_at must return RenderOwner")
                break
            end
            if owner.kind === CellSite
                ok, metadata = _probe_frame(
                    issues, "cell_metadata failed",
                    () -> cell_metadata(frame, owner)
                )
                ok || break
                metadata isa RenderCellMetadata || begin
                    push!(issues, "cell_metadata must return RenderCellMetadata")
                    break
                end
                metadata.identity.id == owner.id || begin
                    push!(
                        issues,
                        "cell_metadata(frame, owner) must preserve the owner ID"
                    )
                    break
                end
                ok, by_identity = _probe_frame(
                    issues, "cell_metadata(frame, identity) failed",
                    () -> cell_metadata(frame, metadata.identity)
                )
                ok || break
                by_identity == metadata || begin
                    push!(
                        issues,
                        "cell_metadata call forms must return equal metadata"
                    )
                    break
                end
            end
        end
    end
    ok, keys = _probe_frame(
        issues, "available_channels failed",
        () -> available_channels(frame)
    )
    ok || (keys = ())
    for key in keys
        key isa RenderChannelKey ||
            push!(issues, "available_channels must contain RenderChannelKey values")
        key isa RenderChannelKey || continue
        ok, item = _probe_frame(issues, "channel failed", () -> frame_channel(frame, key))
        ok || continue
        item isa RenderChannel ||
            push!(issues, "channel must return RenderChannel")
        item isa RenderChannel && item.key != key &&
            push!(issues, "channel must return the requested key")
    end
    _, provenance = _probe_frame(
        issues, "frame_provenance failed",
        () -> frame_provenance(frame)
    )
    provenance isa RenderProvenance ||
        push!(issues, "frame_provenance must return RenderProvenance")
    return RenderFrameConformance(isempty(issues), unique(issues))
end

"""
    assert_render_frame_conformance(frame) -> frame

Return `frame` when [`render_frame_conformance`](@ref) finds no issue.

The plot recipes and [`record_potts`](@ref) call this on each frame.

# Arguments

  - `frame::AbstractPottsRenderFrame`: the frame. Throws
    `MakiePotts.InvalidRenderFrameError`, which lists the issues, when a check fails.

# Returns

  - `frame`, unchanged.

See also [`PottsRenderFrame`](@ref).
"""
function assert_render_frame_conformance(frame::AbstractPottsRenderFrame)
    report = render_frame_conformance(frame)
    report.valid || throw(InvalidRenderFrameError(report.issues))
    return frame
end
