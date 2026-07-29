function _add_composite_reference!(
    structure,
    records,
    request_id,
    parent::StructuralIdentity,
    definition_id,
    mount_key,
    source_fingerprint,
    new_epoch,
)
    parent_row = _identity_row(structure, parent)
    composite = _fresh_identity(records, :Composite,
        source_fingerprint, request_id, :composite)
    containment = _fresh_identity(records, :CompositeContainment,
        source_fingerprint, request_id, :containment)
    child_row = ACSets.add_part!(structure, :Composite;
        composite_id=composite.id,
        composite_definition_id=String(definition_id),
        scale_numerator=_attr(structure, parent_row, :scale_numerator),
        scale_denominator=_attr(structure, parent_row, :scale_denominator),
        scale_unit=_attr(structure, parent_row, :scale_unit))
    ACSets.add_part!(structure, :CompositeContainment;
        composite_child=child_row,
        composite_parent=parent_row,
        composite_containment_id=containment.id,
        mount_key)
    _append_identity(records, composite, new_epoch)
    _append_identity(records, containment, new_epoch)
    composite
end

function _composite_parent_row(structure, child_row::Int)
    rows = collect(ACSets.incident(structure, child_row, :composite_child))
    length(rows) == 1 ||
        _fail(:invalid_division_or_move_target,
            "division and movement require a non-root composite";
            child=String(_attr(structure, child_row, :composite_id)),
            parent_count=length(rows))
    row = only(rows)
    row, Int(_attr(structure, row, :composite_parent))
end

function _composite_closure(structure, target_row::Int)
    children = Dict{Int,Vector{Int}}()
    for row in _rows(structure, :CompositeContainment)
        parent = Int(_attr(structure, row, :composite_parent))
        child_row = Int(_attr(structure, row, :composite_child))
        push!(get!(children, parent, Int[]), child_row)
    end
    closure = Set{Int}()
    stack = [target_row]
    while !isempty(stack)
        current = pop!(stack)
        current in closure && continue
        push!(closure, current)
        append!(stack, get(children, current, Int[]))
    end
    closure
end

function _remove_rows!(structure, object::Symbol, rows)
    isempty(rows) || ACSets.rem_parts!(structure, object, sort!(collect(rows)))
end

function _remove_composite_closure!(
    structure,
    records,
    request::RemoveCompositeRequest,
    retirement_epoch::UInt64,
)
    target_row = _identity_row(structure, request.target)
    actual_rows = _composite_closure(structure, target_row)
    actual_ids = Set(String(_attr(structure, row, :composite_id))
        for row in actual_rows)
    declared_ids = Set(identity.id for identity in request.owned_closure)
    actual_ids == declared_ids ||
        _fail(:owned_closure_mismatch,
            "remove request must declare the exact composite owned closure";
            target=request.target.id,
            expected=tuple(sort!(collect(actual_ids))...),
            actual=tuple(sort!(collect(declared_ids))...))

    store_rows = Set(row for row in _rows(structure, :StoreNode)
        if Int(_attr(structure, row, :store_composite)) in actual_rows)
    actor_rows = Set(row for row in _rows(structure, :Actor)
        if Int(_attr(structure, row, :actor_composite)) in actual_rows)
    process_rows = Set(row for row in _rows(structure, :Process)
        if Int(_attr(structure, row, :process_actor)) in actor_rows)
    step_rows = Set(row for row in _rows(structure, :Step)
        if Int(_attr(structure, row, :step_actor)) in actor_rows)
    port_rows = Set(row for row in _rows(structure, :Port)
        if Int(_attr(structure, row, :port_actor)) in actor_rows)
    binding_rows = Set(row for row in _rows(structure, :Binding)
        if Int(_attr(structure, row, :binding_port)) in port_rows ||
           Int(_attr(structure, row, :binding_store)) in store_rows)
    dependency_rows = Set(row for row in _rows(structure, :StepDependency)
        if Int(_attr(structure, row, :dependency_before)) in step_rows ||
           Int(_attr(structure, row, :dependency_after)) in step_rows)
    boundary_rows = Set(row for row in _rows(structure, :BoundaryMap)
        if Int(_attr(structure, row, :boundary_map_composite)) in actual_rows ||
           Int(_attr(structure, row, :boundary_map_store)) in store_rows)
    endpoint_rows = Set(Int(_attr(structure, row, :boundary_map_endpoint))
        for row in boundary_rows)
    junction_rows = Set(row for row in _rows(structure, :Junction)
        if Int(_attr(structure, row, :junction_composite)) in actual_rows ||
           Int(_attr(structure, row, :junction_store)) in store_rows)
    junction_endpoint_rows = Set(row
        for row in _rows(structure, :JunctionEndpoint)
        if Int(_attr(structure, row, :junction_endpoint_junction)) in
                junction_rows ||
           Int(_attr(structure, row, :junction_endpoint_endpoint)) in
                endpoint_rows)
    store_containment_rows = Set(row
        for row in _rows(structure, :StoreContainment)
        if Int(_attr(structure, row, :containment_child)) in store_rows ||
           Int(_attr(structure, row, :containment_parent)) in store_rows)
    composite_containment_rows = Set(row
        for row in _rows(structure, :CompositeContainment)
        if Int(_attr(structure, row, :composite_child)) in actual_rows ||
           Int(_attr(structure, row, :composite_parent)) in actual_rows)

    removals = (
        JunctionEndpoint=junction_endpoint_rows,
        BoundaryMap=boundary_rows,
        Junction=junction_rows,
        Endpoint=endpoint_rows,
        Binding=binding_rows,
        Port=port_rows,
        StepDependency=dependency_rows,
        Process=process_rows,
        Step=step_rows,
        Actor=actor_rows,
        StoreContainment=store_containment_rows,
        StoreNode=store_rows,
        CompositeContainment=composite_containment_rows,
        Composite=actual_rows,
    )
    for (object, rows) in pairs(removals)
        layout = getproperty(_STRUCTURAL_LAYOUT, object)
        if !isnothing(layout.id)
            for row in rows
                identity = StructuralIdentity(
                    object, String(_attr(structure, row, layout.id)), 0)
                _retire_identity!(records, identity, retirement_epoch)
            end
        end
    end
    for (object, rows) in pairs(removals)
        _remove_rows!(structure, object, rows)
    end
    nothing
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::AddCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.parent)
    child_identity = _add_composite_reference!(
        structure, records, request.request_id, request.parent,
        request.definition_id, request.mount_key, source_fingerprint,
        new_epoch)
    push!(lineage, StructuralLineage(
        child_identity, nothing, request.request_id, new_epoch))
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::RemoveCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.target)
    for identity in request.owned_closure
        _require_active_identity(records, identity)
    end
    _remove_composite_closure!(structure, records, request, new_epoch)
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::DivideCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.target)
    target_row = _identity_row(structure, request.target)
    _, parent_row = _composite_parent_row(structure, target_row)
    parent_identity = StructuralIdentity(
        :Composite, String(_attr(structure, parent_row, :composite_id)), 0)
    daughter = _add_composite_reference!(
        structure, records, request.request_id, parent_identity,
        request.daughter_definition_id, request.daughter_mount_key,
        source_fingerprint, new_epoch)
    push!(lineage, StructuralLineage(
        daughter, request.target, request.request_id, new_epoch))
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::MoveCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.target)
    _require_active_identity(records, request.new_parent)
    target_row = _identity_row(structure, request.target)
    parent_row = _identity_row(structure, request.new_parent)
    target_row == parent_row &&
        _fail(:composite_cycle,
            "a composite cannot move beneath itself";
            target=request.target.id)
    parent_row in _composite_closure(structure, target_row) &&
        _fail(:composite_cycle,
            "a composite cannot move beneath its descendant";
            target=request.target.id, parent=request.new_parent.id)
    containment_row, _ = _composite_parent_row(structure, target_row)
    ACSets.set_subpart!(
        structure, containment_row, :composite_parent, parent_row)
    ACSets.set_subpart!(
        structure, containment_row, :mount_key, request.mount_key)
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::RewireBindingRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.binding)
    _require_active_identity(records, request.new_store)
    binding_row = _identity_row(structure, request.binding)
    store_row = _identity_row(structure, request.new_store)
    previous_store = Int(_attr(structure, binding_row, :binding_store))
    canonical_fingerprint(_attr(structure, previous_store, :schema_payload)) ==
        canonical_fingerprint(_attr(structure, store_row, :schema_payload)) ||
        _fail(:rewire_schema_mismatch,
            "rewire target must preserve the bound store schema";
            binding=request.binding.id, store=request.new_store.id)
    ACSets.set_subpart!(structure, binding_row, :binding_store, store_row)
end

function _dpo_replace(
    before::ConcreteProcessBigraphACSet,
    after::ConcreteProcessBigraphACSet,
)
    empty = ProcessBigraphACSet()
    category = Catlab.ACSetCategory(empty)
    rule = AlgebraicRewriting.Rule{:DPO}(
        Catlab.create[category](before),
        Catlab.create[category](after);
        cat=category,
        monic=true,
    )
    matched = Catlab.id[category](before)
    candidate = AlgebraicRewriting.rewrite_match(rule, matched; cat=category)
    structural_fingerprint(candidate) == structural_fingerprint(after) ||
        _fail(:algebraic_rewrite_differential,
            "DPO candidate differs from the independent structural reference";
            expected=structural_fingerprint(after),
            actual=structural_fingerprint(candidate))
    candidate
end

function stage_structural_transaction(
    epoch::DynamicStructuralEpoch,
    requests;
    numeric_candidate=nothing,
    inject_failure::Union{Nothing,Symbol}=nothing,
)
    inject_failure in (nothing, :selection, :reference, :rewrite,
            :validation) ||
        _fail(:invalid_structural_failure_stage,
            "unknown structural failure-injection stage";
            inject_failure)
    supplied = AbstractStructuralRequest[requests...]
    ids = String[request.request_id for request in supplied]
    length(ids) == length(unique(ids)) ||
        _fail(:duplicate_structural_request,
            "structural batch contains duplicate request identities")
    all(request -> request.source_epoch == epoch.ordinal, supplied) ||
        _fail(:stale_structural_epoch,
            "structural request source epoch is not current";
            expected=epoch.ordinal)
    for request in supplied, dependency in request.dependencies
        dependency in ids ||
            _fail(:unknown_structural_dependency,
                "structural request dependency is absent from the batch";
                request=request.request_id, dependency)
        dependency == request.request_id &&
            _fail(:structural_dependency_cycle,
                "structural request cannot depend on itself";
                request=request.request_id)
    end
    inject_failure === :selection &&
        _fail(:injected_structural_failure,
            "deterministic structural failure requested";
            stage=:selection)
    selected, dispositions = _select_requests(supplied, epoch.structure)
    ordered = _topological_requests(selected)

    structure = deepcopy(epoch.structure)
    records = collect(deepcopy(epoch.identities))
    lineage = StructuralLineage[deepcopy(epoch.lineage)...]
    new_epoch = Base.Checked.checked_add(epoch.ordinal, UInt64(1))
    for request in ordered
        reference = deepcopy(structure)
        inject_failure === :reference &&
            _fail(:injected_structural_failure,
                "deterministic structural failure requested";
                stage=:reference, request=request.request_id)
        _apply_reference!(reference, records, lineage, request,
            epoch.fingerprint, new_epoch)
        inject_failure === :rewrite &&
            _fail(:injected_structural_failure,
                "deterministic structural failure requested";
                stage=:rewrite, request=request.request_id)
        structure = _dpo_replace(structure, reference)
    end
    inject_failure === :validation &&
        _fail(:injected_structural_failure,
            "deterministic structural failure requested";
            stage=:validation)
    _validate_structure_shape(structure)
    _validate_capacity(structure, epoch.capacity)
    normalized_records = tuple(sort!(records; by=record ->
        (String(record.identity.kind), record.identity.id,
            record.identity.generation))...)
    normalized_lineage = tuple(sort!(lineage; by=record ->
        (record.birth_epoch, record.birth_event, record.child.id))...)
    candidate_fingerprint = _structural_epoch_fingerprint(
        new_epoch, structure, normalized_records, normalized_lineage,
        epoch.capacity)
    StagedStructuralTransaction(
        STRUCTURAL_TRANSACTION_VERSION,
        epoch.ordinal,
        epoch.fingerprint,
        structure,
        candidate_fingerprint,
        normalized_records,
        normalized_lineage,
        tuple(sort!(dispositions; by=value -> value.request_id)...),
        deepcopy(numeric_candidate),
    )
end

function publish_structural_transaction(
    epoch::DynamicStructuralEpoch,
    candidate::StagedStructuralTransaction;
    validate_numeric::Function=Returns(true),
    inject_failure::Bool=false,
)
    candidate.contract_version == STRUCTURAL_TRANSACTION_VERSION ||
        _fail(:structural_transaction_version_mismatch,
            "staged structural transaction uses an incompatible version";
            expected=STRUCTURAL_TRANSACTION_VERSION,
            actual=candidate.contract_version)
    candidate.source_ordinal == epoch.ordinal &&
        candidate.source_fingerprint == epoch.fingerprint ||
        _fail(:stale_structural_candidate,
            "staged structural candidate no longer matches the source epoch";
            expected_epoch=epoch.ordinal,
            candidate_epoch=candidate.source_ordinal)
    inject_failure &&
        _fail(:injected_structural_failure,
            "deterministic structural failure requested";
            stage=:publication)
    validate_numeric(candidate.numeric_candidate) === true ||
        _fail(:numeric_structural_validation_failed,
            "numeric candidate rejected the joint publication")
    new_ordinal = Base.Checked.checked_add(epoch.ordinal, UInt64(1))
    _validate_structure_shape(candidate.candidate_structure)
    _validate_capacity(candidate.candidate_structure, epoch.capacity)
    expected = _structural_epoch_fingerprint(
        new_ordinal,
        candidate.candidate_structure,
        candidate.identities,
        candidate.lineage,
        epoch.capacity,
    )
    expected == candidate.candidate_fingerprint ||
        _fail(:structural_candidate_fingerprint_mismatch,
            "staged structural candidate failed integrity validation";
            expected, actual=candidate.candidate_fingerprint)
    DynamicStructuralEpoch(
        STRUCTURAL_TRANSACTION_VERSION,
        new_ordinal,
        deepcopy(candidate.candidate_structure),
        candidate.candidate_fingerprint,
        deepcopy(candidate.identities),
        deepcopy(candidate.lineage),
        epoch.capacity,
    )
end

structural_structure(epoch::DynamicStructuralEpoch) = deepcopy(epoch.structure)
structural_fingerprint(epoch::DynamicStructuralEpoch) = epoch.fingerprint
structural_epoch(epoch::DynamicStructuralEpoch) = epoch.ordinal
structural_lineage(epoch::DynamicStructuralEpoch) = deepcopy(epoch.lineage)
