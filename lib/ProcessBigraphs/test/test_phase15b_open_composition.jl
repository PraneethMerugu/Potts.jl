using ACSets
import Catlab

function phase15b_open(
    definition::AbstractString,
    amount::Int;
    role::Symbol=:bidirectional,
    initial::Int=0,
)
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add,
            units="count", ontology="test:shared"),
        private=LeafSchema(Int; default=amount, update_law=:add,
            units="count", ontology="test:private"),
    )
    process = ProcessDeclaration(
        "increment",
        PB0Increment(amount),
        FixedSchedule(Duration(1, scale)),
    )
    composite = StaticComposite(
        schema,
        Dict(path("state") => initial),
        scale;
        processes=(process,),
        bindings=(
            PortBinding("increment", :state, path("state")),
            PortBinding("increment", :increment, path("state")),
        ),
    )
    open_composite(
        definition,
        composite;
        endpoints=(BoundaryEndpoint(:state, path("state"); role),),
    )
end

function phase15b_pair(;
    mount_order=(:left, :right),
    endpoint_order=(:left, :right),
    grouping=:flat,
    left_initial=0,
    right_initial=0,
    overrides=Dict(),
)
    components = Dict(
        :left => CompositeMount(:left,
            phase15b_open("left_definition", 1; initial=left_initial)),
        :right => CompositeMount(:right,
            phase15b_open("right_definition", 2; initial=right_initial)),
    )
    mounts = tuple((components[key] for key in mount_order)...)
    grouped = grouping === :left ?
        mount_group(mount_group(first(mounts)), Base.tail(mounts)...) :
        grouping === :right ?
            mount_group(first(mounts), mount_group(Base.tail(mounts)...)) :
            mount_group(mounts...)
    references = tuple((EndpointRef(key, :state) for key in endpoint_order)...)
    compose_open(
        "pair_root";
        mounts=grouped,
        junctions=(JunctionSpec("shared_junction", path("shared"), references),),
        exports=(CompositeExport(:shared, "shared_junction";
            role=:bidirectional),),
        initial_values=overrides,
    )
end

function phase15b_contract_open(
    definition::AbstractString,
    leaf::LeafSchema;
    role::Symbol=:bidirectional,
    transfer=nothing,
)
    open_composite(
        definition,
        StaticComposite(
            BranchSchema(state=leaf),
            Dict(),
            TimeScale(1),
        );
        endpoints=(BoundaryEndpoint(
            :state,
            path("state");
            role,
            transfer,
        ),),
    )
end

function phase15b_payload_keywords(component)
    payloads = component.model.payloads
    (
        initial_values=payloads.initial_values,
        laws=payloads.laws,
        continuations=payloads.continuations,
    )
end

const PHASE15B_OBJECT_LAYOUT = (
    Composite=(
        attrs=(:composite_id, :composite_definition_id,
            :scale_numerator, :scale_denominator, :scale_unit),
        homs=(),
    ),
    StoreNode=(
        attrs=(:store_id, :store_path, :store_local_path,
            :schema_kind, :schema_payload),
        homs=(:store_composite,),
    ),
    StoreContainment=(
        attrs=(:containment_id,),
        homs=(:containment_child, :containment_parent),
    ),
    CompositeContainment=(
        attrs=(:composite_containment_id, :mount_key),
        homs=(:composite_child, :composite_parent),
    ),
    Actor=(
        attrs=(:actor_id, :actor_local_id, :law_type, :law_version,
            :law_parameters, :capability_payload, :actor_domain,
            :continuation_version),
        homs=(:actor_composite,),
    ),
    Process=(
        attrs=(:cadence_tick, :first_due_tick, :supports_partial),
        homs=(:process_actor,),
    ),
    Step=(attrs=(), homs=(:step_actor,)),
    Port=(
        attrs=(:port_id, :port_name, :port_value_type, :port_direction,
            :port_effect, :port_interval_behavior, :port_optional,
            :port_cardinality, :port_residency, :port_update_law),
        homs=(:port_actor,),
    ),
    Binding=(
        attrs=(:binding_id, :transfer_payload),
        homs=(:binding_port, :binding_store),
    ),
    StepDependency=(
        attrs=(:dependency_id,),
        homs=(:dependency_before, :dependency_after),
    ),
    Endpoint=(
        attrs=(:endpoint_id, :endpoint_name, :endpoint_role,
            :endpoint_origin_store_id, :endpoint_local_path,
            :endpoint_schema_payload),
        homs=(),
    ),
    BoundaryMap=(
        attrs=(:boundary_map_id,),
        homs=(:boundary_map_endpoint, :boundary_map_store,
            :boundary_map_composite),
    ),
    Junction=(
        attrs=(:junction_id,),
        homs=(:junction_store, :junction_composite),
    ),
    JunctionEndpoint=(
        attrs=(:junction_endpoint_id,),
        homs=(:junction_endpoint_junction, :junction_endpoint_endpoint),
    ),
)

const PHASE15B_HOM_TARGETS = Dict(
    :store_composite => :Composite,
    :containment_child => :StoreNode,
    :containment_parent => :StoreNode,
    :composite_child => :Composite,
    :composite_parent => :Composite,
    :actor_composite => :Composite,
    :process_actor => :Actor,
    :step_actor => :Actor,
    :port_actor => :Actor,
    :binding_port => :Port,
    :binding_store => :StoreNode,
    :dependency_before => :Step,
    :dependency_after => :Step,
    :boundary_map_endpoint => :Endpoint,
    :boundary_map_store => :StoreNode,
    :boundary_map_composite => :Composite,
    :junction_store => :StoreNode,
    :junction_composite => :Composite,
    :junction_endpoint_junction => :Junction,
    :junction_endpoint_endpoint => :Endpoint,
)

function phase15b_reverse_rows(source)
    target = ProcessBigraphACSet()
    row_maps = Dict{Symbol,Dict{Int,Int}}()
    for (object, _) in pairs(PHASE15B_OBJECT_LAYOUT)
        rows = collect(ACSets.parts(source, object))
        ACSets.add_parts!(target, object, length(rows))
        row_maps[object] = Dict(old => new
            for (old, new) in zip(rows, reverse(rows)))
    end
    for (object, layout) in pairs(PHASE15B_OBJECT_LAYOUT)
        for old in ACSets.parts(source, object)
            new = row_maps[object][old]
            for attr in layout.attrs
                ACSets.set_subpart!(
                    target, new, attr, deepcopy(ACSets.subpart(source, old, attr)))
            end
            for hom in layout.homs
                old_target = Int(ACSets.subpart(source, old, hom))
                new_target = row_maps[PHASE15B_HOM_TARGETS[hom]][old_target]
                ACSets.set_subpart!(target, new, hom, new_target)
            end
        end
    end
    target
end

@testset "Phase 15.B same-schema boundaries and Catlab structured cospans" begin
    component = phase15b_open("component", 1)
    structure = canonical_structure(component)
    @test ACSets.nparts(structure, :Composite) == 1
    @test ACSets.nparts(structure, :Endpoint) == 1
    @test ACSets.nparts(structure, :BoundaryMap) == 1
    @test ACSets.nparts(structure, :Junction) == 0
    cospan = structured_cospan(component)
    @test cospan isa Catlab.StructuredMulticospan
    @test Catlab.apex(cospan) isa ProcessBigraphACSet
    @test length(Catlab.feet(cospan)) == 2
    @test all(foot -> ACSets.nparts(foot, :Endpoint) == 1,
        Catlab.feet(cospan))
    contract = only(ACSets.subpart(structure, :endpoint_schema_payload))
    @test contract.schema isa LeafSchema{Int,0}
    @test contract.schema.units == "count"
    @test contract.schema.ontology == "test:shared"
    @test isnothing(contract.transfer)
    @test structural_fingerprint(component) ==
        structural_fingerprint(canonical_model(component))
end

@testset "Phase 15.B n-ary composition, hierarchy lowering, and runtime" begin
    composed = phase15b_pair()
    structure = canonical_structure(composed)
    @test ACSets.nparts(structure, :Composite) == 3
    @test ACSets.nparts(structure, :CompositeContainment) == 2
    @test ACSets.nparts(structure, :Endpoint) == 3
    @test ACSets.nparts(structure, :BoundaryMap) == 3
    @test ACSets.nparts(structure, :Junction) == 1
    @test ACSets.nparts(structure, :JunctionEndpoint) == 3

    compiled = compile_composite(composed)
    @test length(compiled.plan.processes) == 2
    @test Set(paths(compiled.initial)) == Set([
        path("left", "private"),
        path("right", "private"),
        path("shared"),
    ])
    @test compiled.initial[path("left", "private")] == 1
    @test compiled.initial[path("right", "private")] == 2
    @test compiled.initial[path("shared")] == 0
    runtime = initialize_runtime(compiled)
    run_until!(runtime, LogicalTime(2, TimeScale(1)))
    @test current_snapshot(runtime)[path("shared")] == 6
    @test current_snapshot(runtime)[path("left", "private")] == 1
    @test current_snapshot(runtime)[path("right", "private")] == 2

    provenance = structural_provenance(compiled).entries
    @test count(pair -> first(last(pair)) === :composite, provenance) == 3
    @test count(pair -> first(last(pair)) === :endpoint, provenance) == 3
    @test count(pair -> first(last(pair)) === :junction, provenance) == 1
    @test all(type -> !(type <: ACSets.ACSet), fieldtypes(ExecutionPlan))
end

@testset "Phase 15.B authoring, order, and grouping invariance" begin
    forward = phase15b_pair()
    reversed = phase15b_pair(
        mount_order=(:right, :left),
        endpoint_order=(:right, :left),
    )
    left_grouped = phase15b_pair(grouping=:left)
    right_grouped = phase15b_pair(grouping=:right)
    variants = (reversed, left_grouped, right_grouped)
    expected_structure = structural_fingerprint(forward)
    expected_model = model_fingerprint(compile_composite(forward))
    expected_provenance = structural_provenance(compile_composite(forward)).entries
    for variant in variants
        @test structural_fingerprint(variant) == expected_structure
        @test model_fingerprint(compile_composite(variant)) == expected_model
        @test structural_provenance(compile_composite(variant)).entries ==
            expected_provenance
    end

    payloads = forward.model.payloads
    direct = compile_composite(canonical_structure(forward);
        initial_values=payloads.initial_values,
        laws=payloads.laws,
        continuations=payloads.continuations)
    @test structural_fingerprint(direct) == expected_structure
    @test model_fingerprint(direct) == expected_model
    typed_runtime = initialize_runtime(compile_composite(forward))
    direct_runtime = initialize_runtime(direct)
    run_until!(typed_runtime, LogicalTime(2, TimeScale(1)))
    run_until!(direct_runtime, LogicalTime(2, TimeScale(1)))
    @test materialize(current_snapshot(typed_runtime)) ==
        materialize(current_snapshot(direct_runtime))

    reversed_structure = phase15b_reverse_rows(canonical_structure(forward))
    row_permuted = compile_composite(
        reversed_structure;
        phase15b_payload_keywords(forward)...,
    )
    @test structural_fingerprint(reversed_structure) == expected_structure
    @test model_fingerprint(row_permuted) == expected_model
    @test structural_provenance(row_permuted).entries == expected_provenance

    row_runtime = initialize_runtime(row_permuted)
    run_until!(row_runtime, LogicalTime(2, TimeScale(1)))
    @test materialize(current_snapshot(row_runtime)) ==
        materialize(current_snapshot(typed_runtime))
    @test checkpoint_fingerprint(checkpoint(row_runtime)) ==
        checkpoint_fingerprint(checkpoint(typed_runtime))
end

@testset "Phase 15.B annotated directed-wiring round trip" begin
    composed = phase15b_pair()
    view = annotated_wiring_diagram(composed)
    @test wiring_profile_version(view) == "1.0.0"
    @test length(diagram_fingerprint(view)) == 64
    @test structural_fingerprint(view) == structural_fingerprint(composed)
    @test model_fingerprint(compile_composite(view)) ==
        model_fingerprint(compile_composite(composed))
    @test Catlab.nboxes(wiring_diagram(view)) > 0
    @test Catlab.nwires(wiring_diagram(view)) > 0

    corrupted = deepcopy(view)
    Catlab.add_box!(corrupted.diagram, Catlab.Box(
        (kind=:corrupt,), Any[], Any[]))
    @test_throws ProcessBigraphError canonical_model(corrupted)
    @test_throws ProcessBigraphError canonical_model(Catlab.WiringDiagram([], []))
end

@testset "Phase 15.B nested immutable composition" begin
    inner = phase15b_pair()
    third = phase15b_open("third_definition", 3)
    nested = compose_open(
        "outer_root";
        mounts=(
            CompositeMount(:inner, inner),
            CompositeMount(:third, third),
        ),
        junctions=(JunctionSpec(
            "outer_shared",
            path("outer_shared"),
            (EndpointRef(:inner, :shared), EndpointRef(:third, :state)),
        ),),
        exports=(CompositeExport(:shared, "outer_shared";
            role=:bidirectional),),
    )
    structure = canonical_structure(nested)
    @test ACSets.nparts(structure, :Composite) == 5
    compiled = compile_composite(nested)
    @test length(compiled.plan.processes) == 3
    runtime = initialize_runtime(compiled)
    run_until!(runtime, LogicalTime(2, TimeScale(1)))
    @test current_snapshot(runtime)[path("outer_shared")] == 12

    current = phase15b_open("depth_zero", 1)
    for level in 1:5
        endpoint = level == 1 ? :state : :shared
        current = compose_open(
            "depth_$(level)";
            mounts=(CompositeMount(:child, current),),
            junctions=(JunctionSpec(
                "depth_junction_$(level)",
                path("shared"),
                (EndpointRef(:child, endpoint),),
            ),),
            exports=(CompositeExport(
                :shared,
                "depth_junction_$(level)";
                role=:bidirectional,
            ),),
        )
    end
    @test ACSets.nparts(canonical_structure(current), :Composite) == 6
    deep_runtime = initialize_runtime(compile_composite(current))
    run_until!(deep_runtime, LogicalTime(3, TimeScale(1)))
    @test current_snapshot(deep_runtime)[path("shared")] == 3
end

@testset "Phase 15.B endpoint roles, privacy, and repeated definitions" begin
    roles = (:import, :export, :bidirectional)
    for left_role in roles, right_role in roles,
            parent_role in (nothing, :import, :export, :bidirectional)
        mounts = (
            CompositeMount(:left,
                phase15b_open("same_definition", 1; role=left_role)),
            CompositeMount(:right,
                phase15b_open("same_definition", 2; role=right_role)),
        )
        exports = isnothing(parent_role) ? () :
            (CompositeExport(:shared, "roles"; role=parent_role),)
        declaration = CompositionSpec(
            "role_root";
            mounts,
            junctions=(JunctionSpec(
                "roles",
                path("shared"),
                (EndpointRef(:left, :state), EndpointRef(:right, :state)),
            ),),
            exports,
        )
        internal_provider =
            left_role in (:export, :bidirectional) ||
            right_role in (:export, :bidirectional)
        internal_consumer =
            left_role in (:import, :bidirectional) ||
            right_role in (:import, :bidirectional)
        external_provider = parent_role in (:import, :bidirectional)
        external_consumer = parent_role in (:export, :bidirectional)
        valid = (internal_provider || external_provider) &&
            (internal_consumer || external_consumer)
        if valid
            composed = compose_open(declaration)
            structure = canonical_structure(composed)
            root = only(setdiff(
                collect(ACSets.parts(structure, :Composite)),
                Int[ACSets.subpart(structure, row, :composite_child)
                    for row in ACSets.parts(structure, :CompositeContainment)],
            ))
            root_boundary_count = count(
                row -> ACSets.subpart(
                    structure, row, :boundary_map_composite) == root,
                ACSets.parts(structure, :BoundaryMap),
            )
            @test root_boundary_count == (isnothing(parent_role) ? 0 : 1)
            composite_ids = sort!(String[
                ACSets.subpart(structure, row, :composite_id)
                for row in ACSets.parts(structure, :Composite)
                if row != root
            ])
            @test length(composite_ids) == 2
            @test length(unique(composite_ids)) == 2
        else
            @test_throws ProcessBigraphError compose_open(declaration)
        end
    end
end

@testset "Phase 15.B n-way junctions and exact endpoint contracts" begin
    components = tuple((
        CompositeMount(Symbol("component_$(index)"),
            phase15b_open("shared_definition", index))
        for index in 1:4
    )...)
    references = tuple((
        EndpointRef(Symbol("component_$(index)"), :state)
        for index in reverse(1:4)
    )...)
    nway = compose_open(
        "nway_root";
        mounts=reverse(components),
        junctions=(JunctionSpec("nway", path("shared"), references),),
        exports=(CompositeExport(:shared, "nway"; role=:bidirectional),),
    )
    @test ACSets.nparts(canonical_structure(nway), :JunctionEndpoint) == 5
    nway_runtime = initialize_runtime(compile_composite(nway))
    run_until!(nway_runtime, LogicalTime(2, TimeScale(1)))
    @test current_snapshot(nway_runtime)[path("shared")] == 20

    baseline = LeafSchema(Int; default=0, shape=(), units="count",
        ontology="test:shared", update_law=:add, persistence=:required,
        residency=:cpu)
    incompatible = (
        LeafSchema(Float64; default=0.0, shape=(), units="count",
            ontology="test:shared", update_law=:add, persistence=:required,
            residency=:cpu),
        LeafSchema(Int; default=zeros(Int, 2), shape=(2,), units="count",
            ontology="test:shared", update_law=:add, persistence=:required,
            residency=:cpu),
        LeafSchema(Int; default=0, shape=(), units="molecule",
            ontology="test:shared", update_law=:add, persistence=:required,
            residency=:cpu),
        LeafSchema(Int; default=0, shape=(), units="count",
            ontology="test:different", update_law=:add, persistence=:required,
            residency=:cpu),
        LeafSchema(Int; default=0, shape=(), units="count",
            ontology="test:shared", update_law=:replace, persistence=:required,
            residency=:cpu),
        LeafSchema(Int; default=0, shape=(), units="count",
            ontology="test:shared", update_law=:add, persistence=:transient,
            residency=:cpu),
        LeafSchema(Int; default=0, shape=(), units="count",
            ontology="test:shared", update_law=:add, persistence=:required,
            residency=:agnostic),
    )
    left = phase15b_contract_open("contract_left", baseline)
    for (index, different) in enumerate(incompatible)
        right = phase15b_contract_open("contract_right_$(index)", different)
        @test_throws ProcessBigraphError compose_open(
            "contract_root_$(index)";
            mounts=(CompositeMount(:left, left), CompositeMount(:right, right)),
            junctions=(JunctionSpec(
                "contract_$(index)",
                path("shared"),
                (EndpointRef(:left, :state), EndpointRef(:right, :state)),
            ),),
            exports=(CompositeExport(
                :shared,
                "contract_$(index)";
                role=:bidirectional,
            ),),
        )
    end

    transfer = TransferDeclaration(
        :cpu,
        :cuda;
        max_bytes=64,
        cadence=:event,
        precision=:exact,
        synchronization=:batch_boundary,
    )
    transferred = phase15b_contract_open(
        "transferred",
        baseline;
        transfer,
    )
    @test_throws ProcessBigraphError compose_open(
        "transfer_mismatch";
        mounts=(
            CompositeMount(:left, left),
            CompositeMount(:right, transferred),
        ),
        junctions=(JunctionSpec(
            "transfer_mismatch",
            path("shared"),
            (EndpointRef(:left, :state), EndpointRef(:right, :state)),
        ),),
    )
end

@testset "Phase 15.B initialization and composition failures are atomic" begin
    left = phase15b_open("left_definition", 1; initial=1)
    right = phase15b_open("right_definition", 2; initial=2)
    left_before = structural_fingerprint(left)
    right_before = structural_fingerprint(right)
    declaration = CompositionSpec(
        "conflict_root";
        mounts=(CompositeMount(:left, left), CompositeMount(:right, right)),
        junctions=(JunctionSpec(
            "conflict",
            path("shared"),
            (EndpointRef(:left, :state), EndpointRef(:right, :state)),
        ),),
        exports=(CompositeExport(:shared, "conflict";
            role=:bidirectional),),
    )
    @test_throws ProcessBigraphError compose_open(declaration)
    @test structural_fingerprint(left) == left_before
    @test structural_fingerprint(right) == right_before

    resolved = compose_open(CompositionSpec(
        "conflict_root";
        mounts=(CompositeMount(:left, left), CompositeMount(:right, right)),
        junctions=declaration.junctions,
        exports=declaration.exports,
        initial_values=Dict(path("shared") => 7),
    ))
    @test compile_composite(resolved).initial[path("shared")] == 7

    @test_throws ProcessBigraphError compose_open(CompositionSpec(
        "duplicate";
        mounts=(CompositeMount(:same, left), CompositeMount(:same, right)),
        junctions=declaration.junctions,
    ))
    @test_throws ProcessBigraphError compose_open(CompositionSpec(
        "unknown";
        mounts=(CompositeMount(:left, left),),
        junctions=(JunctionSpec(
            "unknown",
            path("shared"),
            (EndpointRef(:left, :missing),),
        ),),
    ))

    imports = (
        CompositeMount(:left,
            phase15b_open("import_left", 1; role=:import)),
        CompositeMount(:right,
            phase15b_open("import_right", 2; role=:import)),
    )
    @test_throws ProcessBigraphError compose_open(
        "no_provider";
        mounts=imports,
        junctions=(JunctionSpec(
            "no_provider",
            path("shared"),
            (EndpointRef(:left, :state), EndpointRef(:right, :state)),
        ),),
    )

    @test_throws ProcessBigraphError CompositionSpec(
        "duplicate_exports";
        mounts=(CompositeMount(:left, left),),
        junctions=(JunctionSpec(
            "exported",
            path("shared"),
            (EndpointRef(:left, :state),),
        ),),
        exports=(
            CompositeExport(:shared, "exported"; role=:bidirectional),
            CompositeExport(:shared, "exported"; role=:bidirectional),
        ),
    ) |> compose_open
    @test_throws ProcessBigraphError compose_open(
        "duplicate_paths";
        mounts=(CompositeMount(:left, left), CompositeMount(:right, right)),
        junctions=(
            JunctionSpec(
                "one",
                path("shared"),
                (EndpointRef(:left, :state),),
            ),
            JunctionSpec(
                "two",
                path("shared"),
                (EndpointRef(:right, :state),),
            ),
        ),
    )

    incompatible = open_composite(
        "float_definition",
        StaticComposite(
            BranchSchema(state=LeafSchema(Float64; default=0.0,
                update_law=:add, units="count", ontology="test:shared")),
            Dict(),
            TimeScale(1),
        );
        endpoints=(BoundaryEndpoint(:state, path("state");
            role=:bidirectional),),
    )
    @test_throws ProcessBigraphError compose_open(
        "incompatible";
        mounts=(
            CompositeMount(:left, left),
            CompositeMount(:float, incompatible),
        ),
        junctions=(JunctionSpec(
            "incompatible",
            path("shared"),
            (EndpointRef(:left, :state), EndpointRef(:float, :state)),
        ),),
        exports=(CompositeExport(:shared, "incompatible";
            role=:bidirectional),),
    )

    malformed = canonical_structure(left)
    endpoint = only(ACSets.parts(malformed, :Endpoint))
    boundary = only(ACSets.parts(malformed, :BoundaryMap))
    ACSets.add_part!(malformed, :BoundaryMap;
        boundary_map_endpoint=endpoint,
        boundary_map_store=ACSets.subpart(malformed, boundary, :boundary_map_store),
        boundary_map_composite=
            ACSets.subpart(malformed, boundary, :boundary_map_composite),
        boundary_map_id="duplicate-boundary-map")
    @test_throws ProcessBigraphError compile_composite(
        malformed;
        phase15b_payload_keywords(left)...,
    )
end
