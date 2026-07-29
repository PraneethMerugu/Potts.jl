function spawn(
    template::TemplateHandle,
    request_id::AbstractString,
    source_epoch::Integer,
    parent::StructuralIdentity,
    mount_key::Symbol;
    dependencies=(),
    priority::Integer=0,
)
    AddCompositeRequest(
        request_id, source_epoch, parent, template.definition_id, mount_key;
        dependencies, priority)
end

function divide(
    template::TemplateHandle,
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity,
    daughter_mount_key::Symbol;
    policies::CompositeDivisionPolicy=CompositeDivisionPolicy(),
    dependencies=(),
    priority::Integer=0,
)
    DivideCompositeRequest(
        request_id, source_epoch, target, template.definition_id,
        daughter_mount_key;
        policies, dependencies, priority)
end

remove(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity,
    owned_closure=();
    dependencies=(),
    priority::Integer=0,
) = RemoveCompositeRequest(
    request_id, source_epoch, target;
    owned_closure, dependencies, priority)

move(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity,
    new_parent::StructuralIdentity,
    mount_key::Symbol;
    dependencies=(),
    priority::Integer=0,
) = MoveCompositeRequest(
    request_id, source_epoch, target, new_parent, mount_key;
    dependencies, priority)
