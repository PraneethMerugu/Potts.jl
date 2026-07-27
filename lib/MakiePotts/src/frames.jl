abstract type AbstractPottsRenderFrame{N} end

@enum RenderOwnerKind::UInt8 begin
    CellSite = 0x01
    MediumSite = 0x02
    ObstacleSite = 0x03
end

"""
Semantic owner of one rendered lattice site. `id` is a finite-cell ID for
`CellSite` and a medium-domain ID otherwise.
"""
struct RenderOwner
    kind::RenderOwnerKind
    id::UInt32

    function RenderOwner(kind::RenderOwnerKind, id::Integer)
        0 < id <= typemax(UInt32) ||
            throw(ArgumentError("render owner identity must fit UInt32 and be positive"))
        new(kind, UInt32(id))
    end
end
Base.:(==)(left::RenderOwner, right::RenderOwner) =
    left.kind === right.kind && left.id == right.id
Base.hash(owner::RenderOwner, seed::UInt) =
    hash(owner.id, hash(owner.kind, seed))

"""Generation-aware finite-cell identity."""
struct CellIdentity
    id::UInt32
    generation::UInt64

    function CellIdentity(id::Integer, generation::Integer)
        0 < id <= typemax(UInt32) ||
            throw(ArgumentError("cell identity must fit UInt32 and be positive"))
        0 <= generation <= typemax(UInt64) ||
            throw(ArgumentError("cell generation must fit UInt64 and be nonnegative"))
        new(UInt32(id), UInt64(generation))
    end
end
Base.:(==)(left::CellIdentity, right::CellIdentity) =
    left.id == right.id && left.generation == right.generation
Base.hash(identity::CellIdentity, seed::UInt) =
    hash(identity.generation, hash(identity.id, seed))

"""Semantic metadata for one live finite cell."""
struct RenderCellMetadata
    identity::CellIdentity
    cell_type::UInt32
    label::String

    function RenderCellMetadata(identity::CellIdentity, cell_type::Integer;
            label::AbstractString = "Cell $(identity.id)")
        0 < cell_type <= typemax(UInt32) ||
            throw(ArgumentError("cell type must fit UInt32 and be positive"))
        new(identity, UInt32(cell_type), String(label))
    end
end
Base.:(==)(left::RenderCellMetadata, right::RenderCellMetadata) =
    left.identity == right.identity &&
    left.cell_type == right.cell_type &&
    left.label == right.label
Base.hash(metadata::RenderCellMetadata, seed::UInt) =
    hash(metadata.label,
        hash(metadata.cell_type, hash(metadata.identity, seed)))

"""
Physical geometry of a rendered ownership array. Coordinates use cell centers;
`origin` is the lower physical edge of the first site.
"""
struct RenderGeometry{N, T <: AbstractFloat}
    size::NTuple{N, Int}
    spacing::NTuple{N, T}
    origin::NTuple{N, T}
    source_axes::NTuple{N, Int}

    function RenderGeometry(size::NTuple{N, <:Integer};
            spacing = ntuple(_ -> 1.0, Val(N)),
            origin = ntuple(_ -> 0.0, Val(N)),
            source_axes = ntuple(identity, Val(N))) where {N}
        N in (2, 3) || throw(ArgumentError(
            "render geometry supports two or three dimensions"))
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
        new{N, T}(normalized_size, normalized_spacing, normalized_origin, normalized_axes)
    end
end
Base.:(==)(left::RenderGeometry, right::RenderGeometry) =
    left.size == right.size &&
    left.spacing == right.spacing &&
    left.origin == right.origin &&
    left.source_axes == right.source_axes
Base.hash(geometry::RenderGeometry, seed::UInt) =
    hash(geometry.source_axes,
        hash(geometry.origin, hash(geometry.spacing, hash(geometry.size, seed))))

"""Data-lineage record carried by a complete render frame."""
struct RenderProvenance{R}
    source::Symbol
    source_type::String
    residency::Symbol
    request::R
end

function RenderProvenance(source::Symbol, source_type::Type, residency::Symbol,
        request::RenderRequest)
    return RenderProvenance(source, string(source_type), residency, request)
end

"""
Canonical, validated render-frame snapshot. Construction defensively copies
mutable input containers; callers consume it as logically immutable through the
accessor protocol.
"""
struct PottsRenderFrame{N, O <: AbstractArray{RenderOwner, N},
        M <: AbstractVector{RenderCellMetadata}, C <: Tuple, G, P} <:
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

    channel_keys = map(item -> item.key, channels)
    length(unique(channel_keys)) == length(channel_keys) ||
        push!(errors, "render channel keys must be unique")
    for item in channels
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
                    identity isa CellIdentity ||
                        push!(errors, "cell-channel keys must be CellIdentity values")
                    identity isa CellIdentity && !haskey(lookup, identity.id) &&
                        push!(errors, "cell-channel identities must belong to the frame")
                    identity isa CellIdentity && haskey(lookup, identity.id) &&
                        lookup[identity.id].identity != identity &&
                        push!(errors, "cell-channel identities must match cell generations")
                end
            end
        elseif item.key isa RenderChannelKey{MediumChannelScope}
            item.values isa AbstractDict ||
                push!(errors, "medium-channel values must be domain-ID-keyed")
            if item.values isa AbstractDict
                all(key -> key isa Integer && key > 0, keys(item.values)) ||
                    push!(errors,
                        "medium-channel keys must be positive integer domain IDs")
            end
        end
        if item.values isa AbstractArray || item.values isa AbstractDict
            expected = _channel_value_type(item.key)
            all(value -> ismissing(value) || value isa expected, values(item.values)) ||
                push!(errors,
                    "render channel $(item.key) contains a value outside its declared type")
        end
    end
    return unique(errors)
end

_channel_value_type(::RenderChannelKey{S, T}) where {S, T} = T

function PottsRenderFrame(mcs::Integer, owners::AbstractArray{RenderOwner, N},
        cells::AbstractVector{RenderCellMetadata};
        channels::Tuple = (),
        geometry::RenderGeometry{N} = RenderGeometry(size(owners)),
        provenance = RenderProvenance(:manual, typeof(owners), :host, RenderRequest())) where {N}
    errors = _frame_errors(Int(mcs), owners, cells, channels, geometry)
    isempty(errors) || throw(InvalidRenderFrameError(errors))
    frozen_owners = copy(owners)
    frozen_cells = collect(cells)
    frozen_channels = map(channels) do item
        values = item.values isa AbstractArray || item.values isa AbstractDict ?
                 copy(item.values) : item.values
        RenderChannel(item.key, values; label = item.label, units = item.units)
    end
    lookup = Dict(cell.identity.id => index for (index, cell) in pairs(frozen_cells))
    return PottsRenderFrame{N, typeof(frozen_owners), typeof(frozen_cells),
        typeof(frozen_channels), typeof(geometry), typeof(provenance)}(
        Int(mcs), frozen_owners, frozen_cells, frozen_channels,
        geometry, provenance, lookup)
end

frame_mcs(frame::PottsRenderFrame) = frame.mcs
frame_size(frame::PottsRenderFrame) = frame.geometry.size
frame_geometry(frame::PottsRenderFrame) = frame.geometry
frame_provenance(frame::PottsRenderFrame) = frame.provenance
owner_at(frame::PottsRenderFrame, site) = frame.owners[site]

function cell_metadata(frame::PottsRenderFrame, identity::CellIdentity)
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

available_channels(frame::PottsRenderFrame) = map(item -> item.key, frame.channels)

function channel(frame::PottsRenderFrame, key::RenderChannelKey)
    index = findfirst(item -> item.key == key, frame.channels)
    index === nothing && throw(MissingRenderChannelError(
        key, Any[available_channels(frame)...]))
    return frame.channels[index]
end

Base.size(frame::PottsRenderFrame) = frame_size(frame)
Base.ndims(::AbstractPottsRenderFrame{N}) where {N} = N

"""Reusable downstream conformance result for an open render-frame implementation."""
struct RenderFrameConformance
    valid::Bool
    issues::Vector{String}
end
Base.isvalid(report::RenderFrameConformance) = report.valid

"""
    render_frame_conformance(frame)

Exercise the stable accessor protocol without relying on physical frame fields.
"""
function render_frame_conformance(frame::AbstractPottsRenderFrame{N}) where {N}
    issues = String[]
    N in (2, 3) || push!(issues, "frame dimensionality must be two or three")
    mcs = try
        frame_mcs(frame)
    catch error
        push!(issues, "frame_mcs failed: $(sprint(showerror, error))")
        nothing
    end
    mcs isa Integer && mcs >= 0 ||
        push!(issues, "frame_mcs must return a nonnegative integer")
    dims = try
        frame_size(frame)
    catch error
        push!(issues, "frame_size failed: $(sprint(showerror, error))")
        nothing
    end
    dims isa NTuple{N, Int} && all(>(0), dims) ||
        push!(issues, "frame_size must return positive Int dimensions")
    geometry = try
        frame_geometry(frame)
    catch error
        push!(issues, "frame_geometry failed: $(sprint(showerror, error))")
        nothing
    end
    if !(geometry isa RenderGeometry{N})
        push!(issues, "frame_geometry must return RenderGeometry{$N}")
    elseif dims !== nothing && geometry.size != dims
        push!(issues, "frame geometry and ownership dimensions must agree")
    end
    if dims isa NTuple{N, Int}
        for site in CartesianIndices(dims)
            owner = try
                owner_at(frame, site)
            catch error
                push!(issues, "owner_at failed: $(sprint(showerror, error))")
                break
            end
            owner isa RenderOwner || begin
                push!(issues, "owner_at must return RenderOwner")
                break
            end
            if owner.kind === CellSite
                metadata = try
                    cell_metadata(frame, owner)
                catch error
                    push!(issues,
                        "cell_metadata failed: $(sprint(showerror, error))")
                    break
                end
                metadata isa RenderCellMetadata || begin
                    push!(issues, "cell_metadata must return RenderCellMetadata")
                    break
                end
                metadata.identity.id == owner.id || begin
                    push!(issues,
                        "cell_metadata(frame, owner) must preserve the owner ID")
                    break
                end
                by_identity = try
                    cell_metadata(frame, metadata.identity)
                catch error
                    push!(issues,
                        "cell_metadata(frame, identity) failed: " *
                        sprint(showerror, error))
                    break
                end
                by_identity == metadata || begin
                    push!(issues,
                        "cell_metadata call forms must return equal metadata")
                    break
                end
            end
        end
    end
    keys = try
        available_channels(frame)
    catch error
        push!(issues, "available_channels failed: $(sprint(showerror, error))")
        ()
    end
    for key in keys
        key isa RenderChannelKey ||
            push!(issues, "available_channels must contain RenderChannelKey values")
        key isa RenderChannelKey || continue
        item = try
            channel(frame, key)
        catch error
            push!(issues, "channel failed: $(sprint(showerror, error))")
            nothing
        end
        item === nothing && continue
        item isa RenderChannel ||
            push!(issues, "channel must return RenderChannel")
        item isa RenderChannel && item.key != key &&
            push!(issues, "channel must return the requested key")
    end
    provenance = try
        frame_provenance(frame)
    catch error
        push!(issues, "frame_provenance failed: $(sprint(showerror, error))")
        nothing
    end
    provenance isa RenderProvenance ||
        push!(issues, "frame_provenance must return RenderProvenance")
    return RenderFrameConformance(isempty(issues), unique(issues))
end

function assert_render_frame_conformance(frame::AbstractPottsRenderFrame)
    report = render_frame_conformance(frame)
    report.valid || throw(InvalidRenderFrameError(report.issues))
    return frame
end
