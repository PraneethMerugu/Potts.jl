module SourceTraversalAuthorityFixtures

using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts

struct TraversalNativeSystem <: ModelingToolkitBase.AbstractSystem
    name::Symbol
end

Base.nameof(system::TraversalNativeSystem) = getfield(system, :name)

function PottsToolkit.native_source_fingerprint(source::TraversalNativeSystem)
    return PottsToolkit.NativeSourceFingerprint(PottsToolkit._sha256_hex(
        "source-traversal-native-fixture-v1", nameof(source)
    ))
end

function PottsToolkit.mtkcompile_native(
        component::PottsToolkit.CompletedNativeComponent{C},
    ) where {C <: PottsToolkit.NativeComponent{TraversalNativeSystem}}
    source = PottsToolkit.native_source(component.declaration)
    scheduled_fingerprint = PottsToolkit.NativeSourceFingerprint(
        PottsToolkit._sha256_hex(
            "source-traversal-native-scheduled-fixture-v1",
            component.source_fingerprint,
        )
    )
    return PottsToolkit.ScheduledNativeComponent(
        component.path,
        component.declaration,
        source,
        source,
        component.endpoints,
        component.source_fingerprint,
        scheduled_fingerprint,
    )
end

function PottsToolkit.registered_statement_lowering(
        ::Val{:lower_source_traversal_observation},
        id::StatementID,
        arguments::Tuple,
        options::NamedTuple,
        source,
    )
    isempty(options) || error("source-traversal fixture accepts no options")
    return Observation(id, only(arguments); source)
end

function registry()
    contract = (
        argument_types = (Any,),
        result_type = Real,
        unit_constraints = :dimensionless,
        namespace_traversal = :map_symbolics,
        access = (reads = (1,), writes = ()),
        effect = :pure_read,
        rng = (),
        boundedness = (maximum = 0, basis = :read_only),
        phase = nothing,
        capabilities = (
            sequential = true,
            checkerboard = true,
            reason = "",
        ),
        scientific_category = :observation,
        energy_domain = nothing,
        affected_region = nothing,
        reference_semantics = :dimensionless,
        descriptor_payload_type = CorePotts.CompilerSPI.EmptyDescriptorPayload,
        serialization_identity = "source-traversal-observation-v1",
        lowering_identity = :lower_source_traversal_observation,
    )
    return register_statement(
        default_statement_registry(),
        :source_traversal_observation,
        v"1.0.0",
        contract,
    )
end

function model()
    @variables potts_to_native native_to_potts
    @variables native_input native_output
    @parameters relationship_capacity = 4
    input_state = ModelState(
        potts_to_native; name = :potts_to_native, initial = 1.0
    )
    output_state = ModelState(
        native_to_potts; name = :native_to_potts, initial = 0.0
    )
    component = NativeComponent(
        TraversalNativeSystem(:native_source);
        name = :native_component,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 1.0),
        inputs = (NativeInput(
            native_input, input_state; value_type = Float64
        ),),
        outputs = (NativeOutput(
            native_output, output_state; value_type = Float64
        ),),
    )
    child = PottsSystem(
        name = :coupled_child,
        statements = StatementSet((
            input_state,
            output_state,
            RegisteredStatement(
                :registered_observation,
                :source_traversal_observation,
                v"1.0.0",
                potts_to_native,
            ),
        )),
        unknowns = [potts_to_native, native_to_potts],
        native_components = (component,),
    )
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    links = RelationshipState(
        :links;
        endpoints = Undirected(cell, cell),
        capacity = relationship_capacity,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    root = PottsSystem(
        name = :traversal_root,
        statements = StatementSet((
            Lattice((4, 4)),
            cell,
            medium,
            links,
            Volume(cell; target = 4.0, strength = 1.0),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        systems = (child,),
        parameters = [relationship_capacity],
    )
    return root
end

function visit_key(kind, path, value)
    if kind === :system || kind === :native_component
        return (kind, path)
    elseif kind === :statement
        return (
            kind, path, PottsToolkit.statement_kind(value), statement_id(value)
        )
    end
    return (kind, path, PottsToolkit._canonical_value(value))
end

end

using .SourceTraversalAuthorityFixtures

@testset "single source-traversal authority" begin
    fixture_registry = SourceTraversalAuthorityFixtures.registry()

    complete_visits = Dict{Any, Int}()
    source = SourceTraversalAuthorityFixtures.model()
    completed = PottsToolkit._with_source_traversal_witness(
        (kind, path, value) -> begin
            key = SourceTraversalAuthorityFixtures.visit_key(kind, path, value)
            complete_visits[key] = get(complete_visits, key, 0) + 1
        end,
    ) do
        complete(source; registry = fixture_registry)
    end
    @test !isempty(complete_visits)
    @test all(==(1), values(complete_visits))
    @test count(key -> first(key) === :system, keys(complete_visits)) == 2
    @test count(key -> first(key) === :statement, keys(complete_visits)) == 9
    @test count(
        key -> first(key) === :native_component, keys(complete_visits)
    ) == 1
    registered = only(filter(
        record -> record.identity.local_id == StatementID(:registered_observation),
        inspect(completed, Statements()),
    ))
    @test registered.kind === :Observation
    @test registered.provenance.schema === :source_traversal_observation
    @test only(PottsToolkit._completion_data(completed).parameter_roles.structural) ==
          (name = :relationship_capacity, value = 4)
    @test ModelingToolkitBase.iscomplete(only(
        ModelingToolkitBase.get_systems(completed)
    ))

    idempotent_complete_visits = Ref(0)
    same_completed = PottsToolkit._with_source_traversal_witness(
        (_, _, _) -> (idempotent_complete_visits[] += 1),
    ) do
        complete(completed; registry = fixture_registry)
    end
    @test same_completed === completed
    @test iszero(idempotent_complete_visits[])

    compile_visits = Dict{Any, Int}()
    scheduled = PottsToolkit._with_source_traversal_witness(
        (kind, path, value) -> begin
            key = SourceTraversalAuthorityFixtures.visit_key(kind, path, value)
            compile_visits[key] = get(compile_visits, key, 0) + 1
        end,
    ) do
        mtkcompile(complete(
            SourceTraversalAuthorityFixtures.model(); registry = fixture_registry
        ))
    end
    @test all(==(1), values(compile_visits))
    @test Set(keys(compile_visits)) == Set(keys(complete_visits))
    native = only(scheduled_native_components(scheduled))
    @test native_component_path(native) ==
          (:traversal_root, :coupled_child, :native_component)
    @test Set(PottsToolkit.potts_endpoint.(
        PottsToolkit.native_coupling_endpoints(native)
    )) == Set((
        PottsToolkit.QualifiedStatementID(
            (:traversal_root, :coupled_child), StatementID(:potts_to_native)
        ),
        PottsToolkit.QualifiedStatementID(
            (:traversal_root, :coupled_child), StatementID(:native_to_potts)
        ),
    ))

    idempotent_schedule_visits = Ref(0)
    same_scheduled = PottsToolkit._with_source_traversal_witness(
        (_, _, _) -> (idempotent_schedule_visits[] += 1),
    ) do
        mtkcompile(scheduled)
    end
    @test same_scheduled === scheduled
    @test iszero(idempotent_schedule_visits[])
end
