# Lower typed Cartesian face and obstacle declarations to Core's sole owner authority.

function _cartesian_owner_identity(
        lattice_identity::QualifiedStatementID, id::StatementID
    )
    digest = _sha256_hex(
        "potts-cartesian-domain-owner-v1",
        _manifest_identity(lattice_identity),
        Symbol(id),
    )
    return parse(UInt64, first(digest, 16); base = 16)
end

function _resolved_domain_owner(
        source::FrozenSourceGraph,
        reference_owner::QualifiedStatement,
        declaring_domain::QualifiedStatement,
        owner::AbstractDomainOwner,
        kinds,
    )
    declaration = _resource_record(
        source, reference_owner, :MediumKind, owner.kind
    )
    declaration === nothing && throw(
        ArgumentError(
            "Cartesian domain owner `$(Symbol(owner.id))` must reference a declared MediumKind"
        )
    )
    kind = get(kinds, declaration.identity, nothing)
    kind === nothing && error(
        "resolved Cartesian domain-owner kind is absent from the kind manifest"
    )
    return (
        id = owner.id,
        kind_identity = declaration.identity,
        metadata = CorePotts.CompilerSPI.DomainOwnerMetadata(
            _cartesian_owner_identity(declaring_domain.identity, owner.id),
            _domain_owner_category(owner),
            kind,
        ),
    )
end

function _same_domain_owner(left, right)
    return left.id == right.id &&
        left.kind_identity == right.kind_identity &&
        left.metadata.category === right.metadata.category
end

function _domain_owner_category(owner::AbstractDomainOwner)
    owner isa MediumDomainOwner &&
        return CorePotts.CompilerSPI.MediumDomainOwnerCategory
    owner isa WallDomainOwner &&
        return CorePotts.CompilerSPI.WallDomainOwnerCategory
    throw(ArgumentError("unsupported Cartesian domain-owner category"))
end

function _domain_owner_kind_matches_manifest(owner, entry)
    authored = Symbol(statement_id(owner.kind))
    return authored == Symbol(entry.kind_identity.local_id) ||
        authored == _qualified_public_name(entry.kind_identity)
end

"""
Resolve an authored domain owner through the sole lattice-owned manifest.

The manifest key is the qualified lattice identity together with the owner's
local id. Consumer scope is deliberately not part of this identity: lifecycle
and initialization references may originate in sibling components, while the
registered C10 metadata remains the authority for category and interaction
kind.
"""
function _registered_domain_owner(owner_manifest, owner::AbstractDomainOwner)
    isempty(owner_manifest) && throw(
        ArgumentError(
            "domain owner `$(Symbol(owner.id))` is not declared by the lattice"
        )
    )
    lattice_identity = first(owner_manifest).identity.lattice
    all(entry -> entry.identity.lattice == lattice_identity, owner_manifest) ||
        error("domain-owner manifest contains more than one declaring lattice")
    matches = filter(
        entry -> entry.identity.lattice == lattice_identity &&
            entry.identity.local_id == Symbol(owner.id),
        owner_manifest,
    )
    length(matches) == 1 || throw(
        ArgumentError(
            "domain owner `$(Symbol(owner.id))` is not declared by the lattice"
        )
    )
    entry = only(matches)
    entry.metadata.category === _domain_owner_category(owner) &&
        _domain_owner_kind_matches_manifest(owner, entry) || throw(
        ArgumentError(
            "Cartesian domain-owner metadata does not match its registered identity"
        )
    )
    return entry
end

function _cartesian_axis_boundaries(boundary, dimensions::Int)
    axes = if boundary isa Tuple
        boundary
    elseif boundary isa AbstractBoundaryPolicy
        ntuple(_ -> AxisBoundary(boundary), dimensions)
    else
        throw(
            ArgumentError(
                "lattice boundary must be one face policy or one AxisBoundary per axis"
            )
        )
    end
    length(axes) == dimensions || throw(
        ArgumentError(
            "lattice axis-boundary count must match lattice dimensions"
        )
    )
    all(value -> value isa AxisBoundary, axes) || throw(
        ArgumentError(
            "lattice axis boundaries must contain only AxisBoundary values"
        )
    )
    for (axis, value) in pairs(axes)
        negative_periodic = value.negative isa Periodic
        positive_periodic = value.positive isa Periodic
        negative_periodic == positive_periodic || throw(
            ArgumentError(
                "periodic Cartesian faces must occur as a pair on axis $axis"
            )
        )
    end
    return axes
end

function _cartesian_face_kind(face)
    face isa Periodic && return CorePotts.CompilerSPI.PeriodicCartesianFace
    face isa Closed && return CorePotts.CompilerSPI.ClosedCartesianFace
    face isa FixedExterior &&
        return CorePotts.CompilerSPI.FixedExteriorCartesianFace
    throw(
        ArgumentError(
            "a Cartesian face must be Periodic, Closed, or FixedExterior"
        )
    )
end

function _lower_cartesian_domain(
        source::FrozenSourceGraph,
        domain::QualifiedStatement,
        shape,
        declarations,
        kinds,
    )
    dimensions = length(shape)
    axes = _cartesian_axis_boundaries(
        _statement_option(domain, :boundary, Periodic()), dimensions
    )
    media = filter(record -> record.kind === :MediumKind, declarations)
    isempty(media) && throw(
        ArgumentError(
            "compilation requires at least one MediumKind"
        )
    )

    authored_default = _statement_option(domain, :default_owner, nothing)
    default = if authored_default === nothing
        declaration = first(media)
        CorePotts.CompilerSPI.DomainOwnerMetadata(
            UInt64(0),
            CorePotts.CompilerSPI.MediumDomainOwnerCategory,
            kinds[declaration.identity],
        )
    else
        authored_default isa MediumDomainOwner || throw(
            ArgumentError(
                "lattice default_owner must be a MediumDomainOwner"
            )
        )
        _resolved_domain_owner(
            source, domain, domain, authored_default, kinds
        ).metadata
    end

    resolved = Dict{StatementID, Any}()
    function register(owner)
        candidate = _resolved_domain_owner(
            source, domain, domain, owner, kinds
        )
        prior = get(resolved, candidate.id, nothing)
        prior === nothing || _same_domain_owner(prior, candidate) || throw(
            ArgumentError(
                "Cartesian domain-owner identity `$(Symbol(candidate.id))` " *
                    "has conflicting category or kind"
            )
        )
        resolved[candidate.id] = candidate
        return candidate
    end
    authored_default === nothing || register(authored_default)
    declared_owners = _statement_option(domain, :domain_owners, ())
    all(value -> value isa AbstractDomainOwner, declared_owners) || throw(
        ArgumentError(
            "lattice domain_owners must contain only medium- or wall-domain owners"
        )
    )
    foreach(register, declared_owners)
    for axis in axes, face in (axis.negative, axis.positive)
        face isa FixedExterior && register(face.owner)
    end
    obstacles = _statement_option(domain, :obstacles, ())
    all(value -> value isa Obstacle, obstacles) || throw(
        ArgumentError(
            "lattice obstacles must contain only Obstacle values"
        )
    )
    for obstacle in obstacles
        size(obstacle.mask) == shape || throw(
            ArgumentError(
                "every obstacle mask must match the lattice shape"
            )
        )
        register(obstacle.owner)
    end

    default_id = authored_default === nothing ? nothing : authored_default.id
    ids = sort!(collect(keys(resolved)); by = id -> String(Symbol(id)))
    filter!(id -> id != default_id, ids)
    owners = CorePotts.CompilerSPI.DomainOwnerMetadata[
        resolved[id].metadata for id in ids
    ]
    handles = Dict{StatementID, Int32}(
        id => Int32(index) for (index, id) in enumerate(ids)
    )
    default_id === nothing || (handles[default_id] = Int32(0))

    face_kinds = ntuple(2 * dimensions) do index
        axis = axes[div(index + 1, 2)]
        face = isodd(index) ? axis.negative : axis.positive
        _cartesian_face_kind(face)
    end
    face_owner_handles = ntuple(2 * dimensions) do index
        axis = axes[div(index + 1, 2)]
        face = isodd(index) ? axis.negative : axis.positive
        face isa FixedExterior ? handles[face.owner.id] : Int32(0)
    end

    obstacle_mask = falses(shape)
    obstacle_handles = zeros(Int32, shape)
    for obstacle in obstacles
        handle = handles[obstacle.owner.id]
        for site in eachindex(obstacle.mask)
            obstacle.mask[site] || continue
            obstacle_mask[site] && throw(
                ArgumentError(
                    "Cartesian obstacle masks overlap at site $site"
                )
            )
            obstacle_mask[site] = true
            obstacle_handles[site] = handle
        end
    end
    cartesian_domain = CorePotts.CompilerSPI.CartesianOwnershipDomain(
        shape,
        default,
        owners;
        face_kinds,
        face_owner_handles,
        obstacle_owner_handles = obstacle_handles,
        obstacle_mask,
    )
    owner_manifest = CompiledDomainOwner[
        CompiledDomainOwner(
            CompiledDomainOwnerIdentity(domain.identity, Symbol(id)),
            resolved[id].kind_identity,
            resolved[id].metadata,
        ) for id in sort!(collect(keys(resolved)); by = id -> String(Symbol(id)))
    ]
    return (; domain = cartesian_domain, owner_manifest)
end

function _lower_cartesian_domain(ir::AnalyzedTermIR)
    records = ir.source.records
    domains = filter(record -> record.kind === :LatticeDomain, records)
    length(domains) == 1 || throw(
        ArgumentError(
            "compilation requires exactly one LatticeDomain"
        )
    )
    domain = only(domains)
    shape = _statement_option(domain, :shape)
    shape isa Tuple{Vararg{Int}} || throw(
        ArgumentError(
            "lattice shape must be resolved to integer dimensions"
        )
    )
    declarations = _ordered_kind_records(records)
    kinds = Dict(
        declaration.identity => index
            for (index, declaration) in enumerate(declarations)
    )
    return _lower_cartesian_domain(
        ir.source, domain, shape, declarations, kinds
    )
end
