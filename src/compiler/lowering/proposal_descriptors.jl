# Universal proposal-descriptor construction and occurrence grouping.

function _registered_record(record::QualifiedStatement)
    provenance = record.provenance
    return provenance isa NamedTuple &&
           haskey(provenance, :registered_lowering_identity)
end

function _construct_descriptor(
        record::QualifiedStatement,
        evaluator::CorePotts.StaticEvaluator,
        context::DescriptorConstructionContext,
    )
    payload = if _registered_record(record)
        try
            registered_descriptor_payload(
                Val(_effective_descriptor_identity(record)), context
            )
        catch error
            if error isa MethodError &&
                    error.f === registered_descriptor_payload
                throw(PottsValidationError(
                    :descriptor_lowering,
                    (PottsDiagnostic(
                        :registered_descriptor_payload_missing,
                        record.identity,
                        String(_effective_descriptor_identity(record)),
                        record.identity.path,
                        "a public registered_descriptor_payload implementation",
                        string(_effective_descriptor_identity(record)),
                        (),
                        record.source,
                    ),),
                ))
            end
            rethrow(error)
        end
    else
        CorePotts.EmptyDescriptorPayload()
    end
    _validate_descriptor_payload(payload, record)
    if _registered_record(record)
        expected = record.provenance.registered_descriptor_payload_type
        typeof(payload) === expected || throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :descriptor_payload_type_mismatch,
                record.identity,
                string(typeof(payload)),
                record.identity.path,
                "the fixed registered descriptor payload type $(expected)",
                string(typeof(payload)),
                (),
                record.source,
            ),),
        ))
    end
    return CorePotts.ProposalDescriptor(
        evaluator,
        context.access,
        context.support,
        context.state_handles,
        context.workspace_handles,
        context.role,
        context.source_handle,
        payload,
    )
end

function _validate_descriptor_payload(
        payload,
        record::QualifiedStatement,
    )
    isbits(payload) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_descriptor_payload,
            record.identity,
            string(typeof(payload)),
            record.identity.path,
            "inert isbits descriptor metadata",
            string(typeof(payload)),
            (),
            record.source,
        ),),
    ))
    stack = Any[payload]
    while !isempty(stack)
        value = pop!(stack)
        if value isa Union{
                Function,
                CorePotts.AbstractStaticExpression,
                CorePotts.StaticEvaluator,
                CorePotts.AbstractContextualOperation,
            }
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :executable_descriptor_payload,
                    record.identity,
                    string(typeof(value)),
                    record.identity.path,
                    "inert descriptor metadata with no evaluator or callable",
                    string(typeof(value)),
                    (),
                    record.source,
                ),),
            ))
        end
        value isa Union{
            Number, Symbol, String, Bool, Type, VersionNumber,
        } && continue
        if value isa Tuple || value isa NamedTuple
            append!(stack, value)
        elseif isstructtype(typeof(value))
            append!(
                stack,
                (
                    getfield(value, field)
                    for field in fieldnames(typeof(value))
                ),
            )
        end
    end
    return nothing
end

function _descriptor_protocol_error(
        record::QualifiedStatement,
        descriptor,
        detail,
    )
    return PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :invalid_descriptor_protocol,
            record.identity,
            string(typeof(descriptor)),
            record.identity.path,
            "the complete public CorePotts descriptor protocol",
            String(detail),
            (),
            record.source,
        ),),
    )
end

function _validate_descriptor_protocol(
        descriptor,
        record::QualifiedStatement,
        expected_source_handle::Integer,
    )
    facts = try
        payload = CorePotts.descriptor_checkpoint_encode(descriptor)
        reconstructed = CorePotts.descriptor_checkpoint_reconstruct(
            descriptor, payload
        )
        (
            states = CorePotts.descriptor_state_requirements(descriptor),
            workspaces =
                CorePotts.descriptor_workspace_requirements(descriptor),
            access = CorePotts.descriptor_resource_access(descriptor),
            stage = CorePotts.descriptor_stage(descriptor),
            role = CorePotts.descriptor_role(descriptor),
            dependencies = CorePotts.descriptor_dependencies(descriptor),
            support = CorePotts.descriptor_support(descriptor),
            adapted = CorePotts.descriptor_adapt(nothing, descriptor),
            nodes = CorePotts.descriptor_evaluator_node_count(descriptor),
            source_handle = CorePotts.descriptor_source_handle(descriptor),
            checkpoint_policy =
                CorePotts.descriptor_checkpoint_policy(descriptor),
            reconstructed,
            inspection = CorePotts.descriptor_inspection(descriptor),
        )
    catch error
        throw(_descriptor_protocol_error(
            record, descriptor, sprint(showerror, error)
        ))
    end
    facts.states isa Tuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "state requirements must be a tuple"
        ))
    facts.workspaces isa Tuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "workspace requirements must be a tuple"
        ))
    facts.access isa CorePotts.ResourceAccess ||
        throw(_descriptor_protocol_error(
            record, descriptor, "resource access must be ResourceAccess"
        ))
    facts.stage isa Symbol ||
        throw(_descriptor_protocol_error(
            record, descriptor, "stage must be a Symbol"
        ))
    facts.role isa CorePotts.AbstractProposalRole ||
        throw(_descriptor_protocol_error(
            record, descriptor, "proposal role is invalid"
        ))
    facts.dependencies isa Tuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "dependencies must be a tuple"
        ))
    facts.support isa CorePotts.DescriptorSupport ||
        throw(_descriptor_protocol_error(
            record, descriptor, "support must be DescriptorSupport"
        ))
    typeof(facts.adapted) === typeof(descriptor) &&
        isbits(facts.adapted) ||
        throw(_descriptor_protocol_error(
            record,
            descriptor,
            "host adaptation must preserve an isbits descriptor type",
        ))
    facts.nodes isa Integer && facts.nodes > 0 ||
        throw(_descriptor_protocol_error(
            record, descriptor, "evaluator node count must be positive"
        ))
    facts.source_handle == expected_source_handle ||
        throw(_descriptor_protocol_error(
            record, descriptor, "source handle does not identify its record"
        ))
    facts.checkpoint_policy in (
        :persist_logical_state,
        :reconstruct_from_executable,
        :workspace_only,
    ) || throw(_descriptor_protocol_error(
        record, descriptor, "checkpoint policy is not closed"
    ))
    typeof(facts.reconstructed) === typeof(descriptor) ||
        throw(_descriptor_protocol_error(
            record, descriptor, "checkpoint reconstruction changed type"
        ))
    facts.inspection isa NamedTuple ||
        throw(_descriptor_protocol_error(
            record, descriptor, "inspection must be a NamedTuple"
        ))
    return nothing
end

function _proposal_descriptor(
        ir::AnalyzedTermIR,
        candidate::DescriptorCandidate,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        workspace_layout,
        workspace_handles,
    ) where {T <: AbstractFloat}
    length(candidate.roots) == 1 || throw(ArgumentError(
        "a proposal descriptor requires exactly one expression root"
    ))
    root = only(candidate.roots)
    cache = Dict{Int32, CorePotts.AbstractStaticExpression}()
    expression = _lower_static_node(
        ir.graph,
        ir,
        root,
        manifest,
        T,
        state_handles,
        cache,
    )
    evaluator = CorePotts.StaticEvaluator(expression)
    record = ir.source.records[candidate.record]
    resolved_states = _record_state_handles(ir, record, state_handles)
    resolved_workspaces = _record_workspace_handles(
        record, workspace_layout, workspace_handles
    )
    access = CorePotts.ResourceAccess(
        resolved_states,
        isempty(record.writes) ? () : resolved_states,
        _descriptor_footprint(ir.facts.locality[root]),
    )
    context = DescriptorConstructionContext(
        access,
        _descriptor_support(ir, candidate),
        resolved_states,
        resolved_workspaces,
        _proposal_role(record),
        candidate.record,
        _descriptor_source(record),
    )
    descriptor = _construct_descriptor(record, evaluator, context)
    _validate_descriptor_protocol(
        descriptor, record, candidate.record
    )
    isbits(descriptor) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_descriptor,
            record.identity,
            string(typeof(descriptor)),
            record.identity.path,
            "an isbits concrete descriptor",
            string(typeof(descriptor)),
            (),
            record.source,
        ),),
    ))
    return descriptor
end

function _descriptor_group_key(descriptor::CorePotts.ProposalDescriptor)
    return (
        descriptor_type = typeof(descriptor),
        evaluator_type = typeof(descriptor.evaluator.expression),
        footprint_type = typeof(descriptor.access.footprint),
        role_type = typeof(descriptor.role),
        stage = CorePotts.descriptor_stage(descriptor),
    )
end

function _descriptor_groups(descriptors)
    keys = Any[]
    grouped = Vector{Vector{Any}}()
    for descriptor in descriptors
        key = _descriptor_group_key(descriptor)
        index = findfirst(isequal(key), keys)
        if index === nothing
            push!(keys, key)
            push!(grouped, Any[descriptor])
        else
            push!(grouped[index], descriptor)
        end
    end
    groups = ()
    for (key, instances) in zip(keys, grouped)
        descriptor_type = key.descriptor_type
        typed_instances = descriptor_type[
            instance for instance in instances
        ]
        state_handles = Tuple(sort!(unique!(
            CorePotts.StateHandle[
                handle
                for descriptor in instances
                for handle in
                    CorePotts.descriptor_state_requirements(descriptor)
            ]
        ); by = handle -> (
            CorePotts.handle_bank(handle),
            CorePotts.handle_slot(handle),
        )))
        workspace_handles = Tuple(sort!(unique!(
            CorePotts.WorkspaceHandle[
                handle
                for descriptor in instances
                for handle in
                    CorePotts.descriptor_workspace_requirements(descriptor)
            ]
        ); by = handle -> (
            CorePotts.handle_bank(handle),
            CorePotts.handle_slot(handle),
        )))
        strategy = CorePotts.DescriptorKernelStrategy{
            descriptor_type,
            key.evaluator_type,
            key.footprint_type,
            key.role_type,
            Val{:proposal},
        }()
        launch = CorePotts.DescriptorLaunch(
            strategy,
            typed_instances,
            state_handles,
            workspace_handles,
        )
        split = (
            descriptor = nameof(descriptor_type),
            evaluator = nameof(key.evaluator_type),
            footprint = nameof(key.footprint_type),
            role = nameof(key.role_type),
            stage = key.stage,
        )
        groups = (groups..., CorePotts.DescriptorGroup(launch, split))
    end
    return groups
end
