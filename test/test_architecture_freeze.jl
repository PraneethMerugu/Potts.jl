module ArchitectureFreezeFixtures

using PottsToolkit
using Symbolics
import CorePotts
import PottsToolkit: operation_transfer

function role_locked_operation end
Symbolics.@register_symbolic role_locked_operation(x)::Real

struct RoleLockedCallable end
@inline (::RoleLockedCallable)(x) = x

operation_transfer(::typeof(role_locked_operation), ::Int) =
    PottsToolkit._transfer(
        :architecture_role_locked,
        1,
        :preserve_numeric,
        :unary;
        operand_rule = :numeric,
        allowed_roles = (:hamiltonian,),
        allowed_phases = (:Proposal,),
        required_context = :hamiltonian,
        owner = :ArchitectureFreezeFixtures,
    )

CorePotts.operation_callable(
    ::Val{:architecture_role_locked}, ::VersionNumber
) = RoleLockedCallable()

function frozen_external_operation end
Symbolics.@register_symbolic frozen_external_operation(x)::Real

struct FrozenExternalCallableV1 end
struct FrozenExternalCallableV2 end
@inline (::FrozenExternalCallableV1)(x) = x
@inline (::FrozenExternalCallableV2)(x) = x + zero(x)

const frozen_generation = Ref(1)

function operation_transfer(::typeof(frozen_external_operation), ::Int)
    generation = frozen_generation[]
    return PottsToolkit._transfer(
        :architecture_frozen_external,
        1,
        :preserve_numeric,
        :unary;
        serialization_identity = "architecture-frozen-external-v$generation",
        operand_rule = :numeric,
        owner = :ArchitectureFreezeFixtures,
        callable_identity = "ArchitectureFreezeFixtures.FrozenExternalCallableV$generation",
    )
end

CorePotts.operation_callable(
    ::Val{:architecture_frozen_external}, ::VersionNumber
) = frozen_generation[] == 1 ? FrozenExternalCallableV1() :
    FrozenExternalCallableV2()

end

using .ArchitectureFreezeFixtures

@testset "architecture-freeze acceptance" begin
    @testset "closed normalized payload grammar" begin
        malformed = PottsToolkit._potts_token(
            :__potts_field__missing_architecture_state
        )
        cell = CellKind(:closed_leaf_cell)
        @named closed_leaf_model = PottsSystem(statements = StatementSet((
            Lattice((2, 2); relations = (proposal = VonNeumann(),)),
            cell,
            ProposalDrive(:malformed_leaf, malformed),
            Protocol(Sweep(); name = :main),
        )))
        error = try
            complete(closed_leaf_model)
            nothing
        catch caught
            caught
        end
        @test error isa PottsToolkit.PottsValidationError
        @test error.stage === :normalization
        @test any(
            diagnostic -> diagnostic.kind === :unresolved_symbolic_leaf,
            error.diagnostics,
        )
    end

    @testset "operation legality precedes lowering" begin
        cell = CellKind(:role_cell)
        proposal = ProposalContext(:copy)
        expression = ArchitectureFreezeFixtures.role_locked_operation(
            proposal.source_site
        )
        @named illegal_role_model = PottsSystem(statements = StatementSet((
            Lattice((2, 2); relations = (proposal = VonNeumann(),)),
            cell,
            ProposalDrive(:illegal_role, expression),
            Protocol(Sweep(); name = :main),
        )))
        completed = complete(illegal_role_model)
        error = try
            PottsToolkit._analyze_completed_system(completed)
            nothing
        catch caught
            caught
        end
        @test error isa PottsToolkit.PottsValidationError
        @test error.stage === :analysis
        diagnostic = only(error.diagnostics)
        @test diagnostic.kind === :illegal_operation_use
        @test diagnostic.identity ==
              PottsToolkit.QualifiedStatementID(
                  (:illegal_role_model,), StatementID(:illegal_role)
              )

        @variables invalid_stage_state
        stage_copy = ProposalContext(:stage_copy)
        @named illegal_context_model = PottsSystem(
            statements = StatementSet((
                Lattice((2, 2); relations = (proposal = VonNeumann(),)),
                cell,
                SiteState(
                    invalid_stage_state;
                    name = :invalid_stage_state,
                    owner = cell,
                    initial = 0.0,
                ),
                Synchronous(
                    :illegal_context,
                    Assign(invalid_stage_state, stage_copy.source_site),
                ),
                Protocol(Sweep(); name = :main),
            )),
            unknowns = [invalid_stage_state],
        )
        context_error = try
            PottsToolkit._analyze_completed_system(
                complete(illegal_context_model)
            )
            nothing
        catch caught
            caught
        end
        @test context_error isa PottsToolkit.PottsValidationError
        @test context_error.stage === :analysis
        @test only(context_error.diagnostics).kind === :illegal_operation_use
        @test occursin("AfterMCS", only(context_error.diagnostics).actual)
    end

    @testset "qualified resource identity is authoritative" begin
        function completed_connectivity(name)
            cell = CellKind(:cell)
            system = PottsSystem(
                name = name,
                statements = StatementSet((
                    Lattice(
                        (3, 3);
                        relations = (
                            proposal = VonNeumann(),
                            connectivity = Moore(),
                            connectivity_background = VonNeumann(),
                        ),
                    ),
                    cell,
                    LocalConnectivity(cell),
                    Protocol(Sweep(); name = :main),
                )),
            )
            return complete(system)
        end
        alpha = completed_connectivity(:alpha_scope)
        beta = completed_connectivity(:beta_scope)
        alpha_graph = PottsToolkit._completion_data(alpha).normalized_graph
        beta_graph = PottsToolkit._completion_data(beta).normalized_graph
        alpha_resources = [
            node.payload.identity for node in alpha_graph.nodes
            if node.payload isa PottsToolkit.ResourceBindingPayload
        ]
        beta_resources = [
            node.payload.identity for node in beta_graph.nodes
            if node.payload isa PottsToolkit.ResourceBindingPayload
        ]
        @test !isempty(alpha_resources)
        @test getfield.(alpha_resources, :local_id) ==
              getfield.(beta_resources, :local_id)
        @test all(identity -> identity.path == (:alpha_scope,), alpha_resources)
        @test all(identity -> identity.path == (:beta_scope,), beta_resources)
        alpha_ir = PottsToolkit._analyze_completed_system(alpha)
        @test alpha_ir.graph === alpha_graph
        @test [
            node.payload.identity for node in alpha_ir.graph.nodes
            if node.payload isa PottsToolkit.ResourceBindingPayload
        ] == alpha_resources
        closure_identities = Set(
            schema.transfer.identity for schema in alpha_graph.operation_snapshot
        )
        @test :explicit_field_euler ∉ closure_identities
        @test :relationship_endpoint_kinds ∉ closure_identities
        @test :square_root ∉ closure_identities
        @test :act_energy ∉ closure_identities

        invalid_cell = CellKind(:invalid_cell)
        invalid_relations = PottsSystem(
            name = :invalid_scientific_requirements,
            statements = StatementSet((
                Lattice(
                    (3, 3);
                    relations = (
                        proposal = VonNeumann(),
                        connectivity = VonNeumann(),
                        connectivity_background = VonNeumann(),
                    ),
                ),
                invalid_cell,
                LocalConnectivity(invalid_cell),
                Protocol(Sweep(); name = :main),
            )),
        )
        requirement_error = try
            PottsToolkit._analyze_completed_system(
                complete(invalid_relations)
            )
            nothing
        catch caught
            caught
        end
        @test requirement_error isa PottsToolkit.PottsValidationError
        @test requirement_error.stage === :analysis
        @test only(requirement_error.diagnostics).kind ===
              :illegal_operation_use
        @test occursin("moore radius 1", only(requirement_error.diagnostics).actual)
    end

    @testset "per-model operation closure is dependency-derived" begin
        cell = CellKind(:closure_cell)
        medium = MediumKind(:closure_medium)
        @named volume_only = PottsSystem(statements = StatementSet((
            Lattice((2, 2)),
            cell,
            medium,
            Volume(cell; target = 1.0, strength = 1.0),
            Protocol(Sweep(); name = :main),
        )))
        volume_graph = PottsToolkit._completion_data(
            complete(volume_only)
        ).normalized_graph
        volume_operations = Set(
            schema.transfer.identity for schema in volume_graph.operation_snapshot
        )
        @test :explicit_field_euler ∉ volume_operations
        @test :relationship_endpoint_kinds ∉ volume_operations
        @test :draw ∉ volume_operations
        @test :less ∉ volume_operations
        @test :greater ∉ volume_operations
        complete(volume_only)
        GC.gc()
        steady_state_allocations = @allocated complete(volume_only)
        @test steady_state_allocations < 2_000_000

        links = RelationshipState(
            :closure_links;
            endpoints = Undirected(cell, cell),
            capacity = 4,
        )
        copy = ProposalContext(:copy)
        @named relationship_create = PottsSystem(statements = StatementSet((
            Lattice((2, 2)),
            cell,
            medium,
            links,
            AcceptedCopy(
                :create_link,
                Create(links, copy.source_cell, copy.target_cell),
            ),
            Protocol(Sweep(); name = :main),
        )))
        relationship_operations = Set(
            schema.transfer.identity for schema in
            PottsToolkit._completion_data(
                complete(relationship_create)
            ).normalized_graph.operation_snapshot
        )
        @test :relationship_endpoint_kinds in relationship_operations
        @test :and in relationship_operations
        @test :explicit_field_euler ∉ relationship_operations

        function draw_operations(expression, name)
            model = PottsSystem(
                name = name,
                statements = StatementSet((
                    Lattice((2, 2)),
                    cell,
                    medium,
                    ProposalDrive(:noise, expression),
                    Protocol(Sweep(); name = :main),
                )),
            )
            graph = PottsToolkit._completion_data(complete(model)).normalized_graph
            return Set(
                schema.transfer.identity for schema in graph.operation_snapshot
            )
        end
        bernoulli_operations = draw_operations(
            draw(Bernoulli(0.5), DrawKey(:bernoulli)), :bernoulli_closure
        )
        uniform_operations = draw_operations(
            draw(Uniform(0.0, 1.0), DrawKey(:uniform)), :uniform_closure
        )
        normal_operations = draw_operations(
            draw(Normal(0.0, 1.0), DrawKey(:normal)), :normal_closure
        )
        @test Set((:greater_equal, :less_equal)) ⊆ bernoulli_operations
        @test isempty(
            Set((:less, :greater)) ∩ bernoulli_operations
        )
        @test :less in uniform_operations
        @test isempty(
            Set((:greater_equal, :less_equal, :greater)) ∩ uniform_operations
        )
        @test :greater in normal_operations
        @test isempty(
            Set((:greater_equal, :less_equal, :less)) ∩ normal_operations
        )
    end

    @testset "affected-anchor plans consume first-class facts" begin
        cell = CellKind(:proof_cell)
        medium = MediumKind(:proof_medium)
        site = SiteBinding(:site)
        relationship = RelationshipState(
            :proof_edges;
            endpoints = Undirected(cell, cell),
            capacity = 8,
            maximum_degree = 2,
            payload = (strength = 1.0,),
        )
        edge = RelationshipBinding(:edge, relationship)
        @named proof_model = PottsSystem(statements = StatementSet((
            Lattice(
                (3, 3);
                relations = (
                    proposal = VonNeumann(),
                    contact = Moore(),
                ),
            ),
            cell,
            medium,
            relationship,
            HamiltonianTerm(
                :site_energy;
                domain = sites(:lattice),
                anchor = site,
                expression = occupancy(cell, site),
            ),
            Volume(cell; target = 2.0, strength = 1.0),
            ContactEnergy([(cell ↔ medium) => 2.0]),
            RelationshipEnergy(:edge_energy, edge, edge.strength),
            Protocol(Sweep(); name = :main),
        )))
        ir = PottsToolkit._analyze_completed_system(complete(proof_model))
        energies = filter(
            candidate -> candidate.category === :hamiltonian,
            ir.candidates,
        )
        @test Set(candidate.energy_domain.kind for candidate in energies) ==
              Set((:sites, :cells, :contacts, :edges))
        for candidate in energies
            proof = candidate.affected_proof
            @test proof isa PottsToolkit.AffectedAnchorProof
            @test proof.transition == PottsToolkit.CopyProposalTransition()
            @test proof.domain === candidate.energy_domain
            @test proof.bound_anchor.kind === candidate.energy_domain.anchor_kind
            @test proof.bound_anchor.name === candidate.energy_domain.anchor_name
            @test proof.footprint == PottsToolkit._footprint_union(Tuple(
                ir.facts.footprint[Int(root)] for root in candidate.roots
            ))
        end
    end

    @testset "named operations use admitted ownership layers" begin
        @variables t activity field(t)
        cell = CellKind(:operation_cell)
        medium = MediumKind(:operation_medium)
        activity_state = SiteState(
            activity;
            name = :activity,
            initial = 0.0,
            owner = cell,
            lifecycle = PreserveOnOwnershipChange(),
        )
        field_state = FieldState(
            field;
            name = :field,
            initial = 0.0,
            diffusion = 0.1,
            secretion = 0.0,
            decay = 0.0,
            source_kind = cell,
            stencil = :field_stencil,
        )
        equation = Differential(t)(field) ~ 0.1 * field
        @named operation_model = PottsSystem(
            statements = StatementSet((
                Lattice(
                    (3, 3);
                    relations = (
                        proposal = VonNeumann(),
                        activity_neighborhood = Moore(),
                        connectivity = Moore(),
                        connectivity_background = VonNeumann(),
                        field_stencil = VonNeumann(),
                    ),
                ),
                cell,
                medium,
                activity_state,
                field_state,
                ActEnergy(
                    cell,
                    activity;
                    maximum = 2.0,
                    strength = 1.0,
                    reduction = :activity_neighborhood,
                ),
                LocalConnectivity(cell),
                EquationProcess(
                    :field_step,
                    [equation];
                    writes = [field],
                    solver = ExplicitDiffusion(),
                    cadence = EveryMCS(),
                    duration_per_mcs = 1.0,
                    substeps = 1,
                ),
                Protocol(Sweep(); name = :main),
            )),
            equations = [equation],
            unknowns = [activity, field],
            independent_variables = [t],
            initial_conditions = Dict(activity => 0.0, field => 0.0),
        )
        completed = complete(operation_model)
        executable = compile(
            completed;
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        )
        @test executable isa PottsExecutable
        inventory = PottsToolkit._v1_operation_inventory(
            PottsToolkit._completion_data(completed).normalized_graph
        )
        rows = Dict(row.identity => row for row in inventory)
        @test rows[:merks_local_connectivity].owner ===
              :PottsToolkitScientificOperations
        @test rows[:act_energy].owner === :PottsToolkitScientificOperations
        @test rows[:explicit_field_euler].owner === :PottsToolkitNumerics
        @test rows[:merks_local_connectivity].allowed_roles == (:constraint,)
        @test rows[:act_energy].allowed_roles == (:drive,)
        @test rows[:explicit_field_euler].allowed_phases == (:AfterMCS,)
        @test :explicit_field_euler in keys(rows)

        root = pkgdir(PottsToolkit)
        central_sources = join((read(joinpath(root, path), String) for path in (
            "src/compiler/host/coverage.jl",
            "src/compiler/host/operation_closure.jl",
            "src/compiler/lowering/after_mcs_descriptors.jl",
            "src/compiler/compile.jl",
        )), "\n")
        for forbidden in (
                "_potts_merks_local_connectivity",
                "_potts_act_energy",
                "_potts_explicit_field_euler",
                "mechanism) === :activity",
                "mechanism) === :local_connectivity",
                "ExplicitDiffusion",
            )
            @test !occursin(forbidden, central_sources)
        end
        symbolic_surface = read(
            joinpath(root, "src/symbolics/operations.jl"), String
        )
        @test !occursin("struct MerksLocalConnectivityCallable", symbolic_surface)
        @test !occursin("struct ActEnergyCallable", symbolic_surface)
        @test !occursin("struct ExplicitFieldEulerCallable", symbolic_surface)
    end

    @testset "external operation and completion snapshot are equal citizens" begin
        ArchitectureFreezeFixtures.frozen_generation[] = 1
        proposal = ProposalContext(:copy)
        expression = ArchitectureFreezeFixtures.frozen_external_operation(
            proposal.source_site
        )
        @named frozen_external_model = PottsSystem(statements = StatementSet((
            Lattice((2, 2); relations = (proposal = VonNeumann(),)),
            CellKind(:external_cell),
            MediumKind(:external_medium),
            ProposalDrive(:external_drive, expression),
            Protocol(Sweep(); name = :main),
        )))
        completed = complete(frozen_external_model)
        frozen_graph = PottsToolkit._completion_data(completed).normalized_graph
        frozen_node = only(filter(
            node -> node.transfer !== nothing &&
                node.transfer.identity === :architecture_frozen_external,
            frozen_graph.nodes,
        ))
        @test frozen_node.callable isa
              ArchitectureFreezeFixtures.FrozenExternalCallableV1
        @test frozen_node.transfer.serialization_identity ==
              "architecture-frozen-external-v1"
        closure_identities = Set(
            schema.transfer.identity for schema in frozen_graph.operation_snapshot
        )
        @test :architecture_frozen_external in closure_identities
        @test :square_root ∉ closure_identities

        ArchitectureFreezeFixtures.frozen_generation[] = 2
        ir = @inferred PottsToolkit._analyze_completed_system(completed)
        analyzed_node = only(filter(
            node -> node.transfer !== nothing &&
                node.transfer.identity === :architecture_frozen_external,
            ir.graph.nodes,
        ))
        @test analyzed_node.callable isa
              ArchitectureFreezeFixtures.FrozenExternalCallableV1
        @test analyzed_node.transfer.serialization_identity ==
              "architecture-frozen-external-v1"
        @test ir.facts.backend_admission[Int(analyzed_node.identity)].cpu
        @test ir.facts.backend_admission[Int(analyzed_node.identity)].gpu
        executable = compile(
            completed;
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float32,
        )
        @test executable isa PottsExecutable
        ArchitectureFreezeFixtures.frozen_generation[] = 1
    end

    @testset "literal V1 inventory is complete and unique" begin
        declarations = PottsToolkit._v1_builtin_operation_declarations()
        surface_keys = [(nameof(operation), arity)
            for (operation, arity) in declarations]
        @test length(declarations) == 65
        @test length(surface_keys) == length(unique(surface_keys))
        @test all(
            declaration -> hasmethod(
                PottsToolkit.operation_transfer,
                Tuple{typeof(first(declaration)), Int},
            ),
            declarations,
        )
    end

    @testset "large ranges serialize structurally" begin
        range = 1:typemax(Int)
        encoded = PottsToolkit._canonical_value(range)
        @test encoded ==
              "Range(UnitRange,first=1,step=1,last=$(typemax(Int)))"
        PottsToolkit._canonical_value(range)
        allocations = @allocated PottsToolkit._canonical_value(range)
        @test allocations < 16_384
        @test ncodeunits(encoded) < 96
        digest = PottsToolkit._sha256_hex(:arity, range)
        @test ncodeunits(digest) == 64
    end
end
