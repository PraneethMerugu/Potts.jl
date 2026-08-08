# Lower closed analyzed footprint facts into concrete CorePotts descriptors.

function _minkowski_offsets(left::Tuple, right::Tuple)
    isempty(left) && return ()
    isempty(right) && return ()
    dimensions = length(first(left))
    all(offset -> length(offset) == dimensions, (left..., right...)) ||
        throw(ArgumentError("Minkowski footprints have inconsistent dimensions"))
    values = Tuple(
        ntuple(dimension -> a[dimension] + b[dimension], dimensions)
        for a in left for b in right
    )
    return Tuple(sort!(unique!(collect(values))))
end

_materialize_footprint(fact::EmptyAnalyzedFootprint) = fact
_materialize_footprint(fact::SpatialFootprintFact) = fact
_materialize_footprint(fact::OwnerFootprintFact) = fact
_materialize_footprint(fact::ContactFootprintFact) = fact
_materialize_footprint(fact::IncidentRelationshipFootprintFact) = fact

function _materialize_footprint(fact::FootprintMinkowskiFact)
    left = _materialize_footprint(fact.left)
    right = fact.right
    left isa SpatialFootprintFact || throw(ArgumentError(
        "a spatial Minkowski footprint requires a spatial anchor"
    ))
    right isa SpatialRelationFootprintFact || throw(ArgumentError(
        "a spatial Minkowski footprint requires a finite relation"
    ))
    return SpatialFootprintFact(
        left.anchor,
        _minkowski_offsets(left.offsets, right.offsets),
    )
end

function _materialize_footprint(fact::FootprintUnionFact)
    return _footprint_union(Tuple(
        _materialize_footprint(member) for member in fact.footprints
    ))
end

_core_footprint_anchor(::ProposalSourceAnchor) =
    CorePotts.CompilerSPI.ProposalSourceFootprintAnchor()
_core_footprint_anchor(::ProposalTargetAnchor) =
    CorePotts.CompilerSPI.ProposalTargetFootprintAnchor()
_core_footprint_anchor(::IterationSiteAnchor) =
    CorePotts.CompilerSPI.IterationSiteFootprintAnchor()
_core_footprint_anchor(::BoundSiteAnchor, bound_slot::Integer) =
    CorePotts.CompilerSPI.BoundSiteFootprintAnchor(bound_slot)
_core_footprint_anchor(anchor, bound_slot::Integer) =
    _core_footprint_anchor(anchor)

_lower_footprint_fact(::EmptyAnalyzedFootprint, bound_slot = 0) =
    CorePotts.CompilerSPI.EmptyFootprint()
_lower_footprint_fact(::OwnerFootprintFact, bound_slot = 0) =
    CorePotts.CompilerSPI.OwnerFootprint()
_lower_footprint_fact(::ContactFootprintFact, bound_slot = 0) =
    CorePotts.CompilerSPI.ContactFootprint()
_lower_footprint_fact(fact::SpatialFootprintFact, bound_slot = 0) =
    CorePotts.CompilerSPI.FiniteSpatialFootprint(
        _core_footprint_anchor(fact.anchor, bound_slot), fact.offsets
    )
_lower_footprint_fact(fact::IncidentRelationshipFootprintFact, bound_slot = 0) =
    CorePotts.CompilerSPI.IncidentRelationshipFootprint(fact.maximum_degree)
_lower_footprint_fact(fact::FootprintUnionFact, bound_slot = 0) =
    CorePotts.CompilerSPI.FootprintUnion(
    Tuple(
        _lower_footprint_fact(member, bound_slot)
        for member in fact.footprints
    )
)

function _descriptor_footprint(ir::AnalyzedTermIR, root::Int32)
    fact = ir.facts.footprint[Int(root)]
    _footprint_has_unresolved_reference(fact) && throw(ArgumentError(
        "descriptor footprint retains an unresolved compiler reference"
    ))
    bound_slot = ir.graph.nodes[Int(root)].record
    return _lower_footprint_fact(_materialize_footprint(fact), bound_slot)
end

function _record_read_footprint(ir::AnalyzedTermIR, record_index::Integer)
    roots = Int32[
        root.node for root in ir.graph.roots if root.record == record_index
    ]
    isempty(roots) && return CorePotts.CompilerSPI.EmptyFootprint()
    fact = _footprint_union(Tuple(
        ir.facts.footprint[Int(root)] for root in roots
    ))
    _footprint_has_unresolved_reference(fact) && throw(ArgumentError(
        "record footprint retains an unresolved compiler reference"
    ))
    return _lower_footprint_fact(
        _materialize_footprint(fact), Int32(record_index)
    )
end

function _site_write_footprint(ir::AnalyzedTermIR, stage)
    anchor = stage isa CorePotts.CompilerSPI.AcceptedCopyStage ?
             CorePotts.CompilerSPI.ProposalTargetFootprintAnchor() :
             CorePotts.CompilerSPI.IterationSiteFootprintAnchor()
    dimensions = length(_lattice_shape(ir))
    return CorePotts.CompilerSPI.FiniteSpatialFootprint(
        anchor, (ntuple(_ -> 0, dimensions),)
    )
end

function _descriptor_support(
        ir::AnalyzedTermIR,
        candidate::DescriptorCandidate,
    )
    roots = Int.(candidate.roots)
    sequential = all(roots) do root
        any(admission ->
            admission.engine === :sequential && admission.admitted,
            ir.facts.engine_admission[root])
    end
    checkerboard = all(roots) do root
        any(admission ->
            admission.engine === :checkerboard && admission.admitted,
            ir.facts.engine_admission[root])
    end
    cpu = all(root -> ir.facts.backend_admission[root].cpu, roots)
    gpu = all(root -> ir.facts.backend_admission[root].gpu, roots)
    reason_code = UInt16(
        (!sequential ? 0x01 : 0x00) |
        (!checkerboard ? 0x02 : 0x00) |
        (!cpu ? 0x04 : 0x00) |
        (!gpu ? 0x08 : 0x00)
    )
    return CorePotts.CompilerSPI.DescriptorSupport(
        sequential,
        checkerboard,
        cpu,
        gpu,
        reason_code,
    )
end

_qualified_resource_identity(identity::QualifiedStatementID) =
    CorePotts.CompilerSPI.QualifiedResourceIdentity(
        identity.path, Symbol(identity.local_id)
    )
