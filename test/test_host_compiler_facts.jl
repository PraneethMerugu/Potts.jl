include("fixtures/NeutralExternalTerms.jl")
using .NeutralExternalTerms
import CorePotts

function invalid_transfer_operation end
Symbolics.@register_symbolic invalid_transfer_operation(x)::Real
struct InvalidTransferCallable <: CorePotts.AbstractContextualOperation end
CorePotts.operation_callable(
    ::Val{:invalid_transfer_operation}, ::VersionNumber
) = InvalidTransferCallable()

function PottsToolkit.operation_transfer(
        ::typeof(invalid_transfer_operation), ::Int
    )
    return PottsToolkit.OperationTransfer(
        :invalid_transfer_operation,
        v"1.0.0",
        1:1,
        :trust_me,
        :dimensionless,
        :pure,
        :total,
        PottsToolkit.InheritFootprintRule(),
        true,
        true,
    )
end

@testset "host compiler facts" begin
    @variables external_site_state
    @parameters site_weight = 2.0 pair_weight = 3.0
    endothelial = CellKind(:endothelial; extinction = RetireAtZero())
    extracellular = MediumKind(:extracellular)
    proposal = ProposalContext(:copy)
    site = SiteBinding(:site)
    fixture_registry = NeutralExternalTerms.registry()

    external_terms = StatementSet((
        Lattice(
            (6, 6);
            relations = (
                proposal = VonNeumann(),
                contact = Moore(),
            ),
        ),
        endothelial,
        extracellular,
        SiteState(
            external_site_state;
            name = :external_site_state,
            initial = 1.0,
            owner = endothelial,
            lifecycle = PreserveOnOwnershipChange(),
        ),
        NeutralExternalTerms.ExternalWeightedSiteTerm(
            :external_weighted_site,
            site_weight,
            external_site_state,
            endothelial,
            site,
        ),
        NeutralExternalTerms.bounded_pair_fixture(
            endothelial,
            pair_weight,
            proposal,
        ),
        Protocol(Sweep(); name = :main),
    ))
    @named neutral_extensions = PottsSystem(
        statements = external_terms,
        unknowns = [external_site_state],
        parameters = [site_weight, pair_weight],
    )
    completed = complete(neutral_extensions; registry = fixture_registry)
    @test complete(completed; registry = fixture_registry) === completed

    data = PottsToolkit._completion_data(completed)
    source = data.source_graph
    @test length(source.systems) == 1
    @test length(source.statements) == length(statements(completed))
    @test source.structural_key ==
          PottsToolkit._completion_data(
              complete(neutral_extensions; registry = fixture_registry)
          ).source_graph.structural_key
    @test issorted(getfield.(source.statements, :source_order))
    @test length(source.registry_snapshot) == 2
    @test any(reference -> reference.kind === :relation, source.references)
    @test any(reference -> reference.kind === :state, source.references)
    @test any(reference -> reference.kind === :protocol, source.references)

    first_ir = PottsToolkit._analyze_completed_system(completed)
    second_ir = PottsToolkit._analyze_completed_system(completed)
    @test first_ir.graph.structural_key == second_ir.graph.structural_key
    @test first_ir.structural_key == second_ir.structural_key
    @test all(node -> node.identity > 0, first_ir.graph.nodes)
    @test all(node -> issorted(node.operands), filter(
        node -> length(node.operands) <= 1, first_ir.graph.nodes
    ))

    candidates = Dict(
        candidate.source.local_id => candidate
        for candidate in first_ir.candidates
    )
    site_id = StatementID(:external_weighted_site)
    pair_id = StatementID(:external_bounded_pair)
    @test haskey(candidates, site_id)
    @test haskey(candidates, pair_id)
    @test candidates[site_id].provenance.schema ===
          NeutralExternalTerms.SITE_SCHEMA
    @test candidates[pair_id].provenance.schema ===
          NeutralExternalTerms.PAIR_SCHEMA
    @test candidates[site_id].category === :hamiltonian
    @test candidates[pair_id].category === :hamiltonian
    @test candidates[site_id].energy_domain.kind === :sites
    @test candidates[site_id].affected_anchors.kind === :target_site
    @test candidates[pair_id].energy_domain.kind === :edges
    @test candidates[pair_id].affected_anchors.kind ===
          :incident_relationships

    pair_root = only(candidates[pair_id].roots)
    @test first_ir.facts.locality[pair_root] === :bounded_relationship
    @test first_ir.facts.backend_admission[pair_root].gpu
    @test first_ir.facts.purity[pair_root] === :pure
    @test first_ir.facts.stage[pair_root] isa Proposal
    @test first_ir.facts.source_chain[pair_root].provenance.schema ===
          NeutralExternalTerms.PAIR_SCHEMA

    report = PottsToolkit._compiler_analysis_report(first_ir)
    @test report.source_graph.statements == length(statements(completed))
    @test report.normalized.nodes == length(first_ir.graph.nodes)
    @test report.analyzed.candidates == length(first_ir.candidates)

    function unsupported_host_operation end
    Symbolics.@register_symbolic unsupported_host_operation(x)::Real
    @named invalid_transfer = PottsSystem(statements = StatementSet((
        HamiltonianTerm(
            :invalid_external_operation;
            domain = sites(:lattice),
            anchor = site,
            expression = unsupported_host_operation(site_weight),
        ),
    )), parameters = [site_weight])
    error = try
        complete(invalid_transfer)
        nothing
    catch caught
        caught
    end
    @test error isa PottsToolkit.PottsValidationError
    @test error.stage === :normalization
    @test only(error.diagnostics).kind === :missing_operation_transfer

    @named malformed_transfer = PottsSystem(statements = StatementSet((
        HamiltonianTerm(
            :malformed_external_operation;
            domain = sites(:lattice),
            anchor = site,
            expression = invalid_transfer_operation(site_weight),
        ),
    )), parameters = [site_weight])
    malformed_error = try
        complete(malformed_transfer)
        nothing
    catch caught
        caught
    end
    @test malformed_error isa PottsToolkit.PottsValidationError
    @test malformed_error.stage === :analysis
    @test only(malformed_error.diagnostics).kind ===
          :invalid_operation_transfer

    @test !isdefined(PottsToolkit, :ProposalEnergy)
    @test_throws MethodError HamiltonianTerm(:positional_energy, 1.0)
    @test_throws UndefKeywordError HamiltonianTerm(
        :missing_domain;
        anchor = site,
        expression = 1.0,
    )

    relationship = RelationshipState(
        :energy_links;
        endpoints = Undirected(endothelial, endothelial),
        capacity = 16,
        maximum_degree = 3,
    )
    edge = RelationshipBinding(:energy_edge, relationship)
    built_in_terms = StatementSet((
        Lattice(
            (5, 5);
            relations = (
                proposal = VonNeumann(),
                contact = Moore(),
                activity_neighborhood = Moore(),
                connectivity = Moore(),
                connectivity_background = VonNeumann(),
            ),
        ),
        endothelial,
        extracellular,
        relationship,
        Volume(endothelial; target = 4.0, strength = 2.0),
        Elongation(endothelial; target = 2.0, strength = 1.0),
        ContactEnergy([(endothelial ↔ extracellular) => 6.0]),
        RelationshipEnergy(
            :elastic_links,
            edge,
            edge.strength * (
                distance(
                    unwrapped_center(edge.a),
                    unwrapped_center(edge.b),
                ) - edge.target
            )^2,
        ),
        Chemotaxis(
            endothelial,
            FieldState(:signal; initial = 0.0);
            strength = 1.0,
        ),
        ActEnergy(
            endothelial,
            external_site_state;
            maximum = 2.0,
            strength = 1.0,
            reduction = :activity_neighborhood,
        ),
        LocalConnectivity(endothelial),
        Protocol(Sweep(); name = :built_in_protocol),
    ))
    @named built_in_categories = PottsSystem(statements = built_in_terms)
    built_in_ir = PottsToolkit._analyze_completed_system(
        complete(built_in_categories)
    )
    built_in_candidates = Dict(
        Symbol(candidate.source.local_id) => candidate
        for candidate in built_in_ir.candidates
    )
    @test built_in_candidates[:volume_endothelial].category === :hamiltonian
    @test built_in_candidates[:elongation_endothelial].category === :hamiltonian
    @test built_in_candidates[:contact_energy].category === :hamiltonian
    @test built_in_candidates[:elastic_links].category === :hamiltonian
    @test built_in_candidates[:chemotaxis_endothelial].category === :drive
    @test built_in_candidates[:activity_endothelial].category === :drive
    @test built_in_candidates[:connectivity_endothelial].category === :constraint
    activity_footprints = map(
        built_in_candidates[:activity_endothelial].roots,
    ) do root
        PottsToolkit._materialize_footprint(
            built_in_ir.facts.footprint[Int(root)]
        )
    end
    activity_spatial = reduce(vcat, map(activity_footprints) do footprint
        collect(PottsToolkit._collect_footprints(
            footprint, PottsToolkit.SpatialFootprintFact
        ))
    end; init = PottsToolkit.SpatialFootprintFact[])
    expected_moore = Tuple(sort([
        (row, column)
        for row in -1:1 for column in -1:1
        if (row, column) != (0, 0)
    ]))
    @test any(
        footprint -> footprint.anchor isa PottsToolkit.ProposalSourceAnchor &&
                     footprint.offsets == expected_moore,
        activity_spatial,
    )
    @test any(
        footprint -> footprint.anchor isa PottsToolkit.ProposalTargetAnchor &&
                     footprint.offsets == expected_moore,
        activity_spatial,
    )
    @test built_in_candidates[:contact_energy].affected_anchors ==
          PottsToolkit.AffectedAnchorFact(:incident_contacts, :contact_local, 8)
    @test built_in_candidates[:elastic_links].affected_anchors ==
          PottsToolkit.AffectedAnchorFact(
              :incident_relationships,
              :bounded_relationship,
              6,
          )

    function analysis_failure(statement; declarations = ())
        @named rejected_hamiltonian = PottsSystem(statements = StatementSet((
            Lattice(
                (4, 4);
                relations = (contact = Moore(),),
            ),
            endothelial,
            extracellular,
            declarations...,
            statement,
            Protocol(Sweep(); name = :rejected_protocol),
        )))
        return try
            PottsToolkit._analyze_completed_system(
                complete(rejected_hamiltonian)
            )
            nothing
        catch caught
            caught
        end
    end

    proposal_energy = HamiltonianTerm(
        :proposal_dependent;
        domain = sites(:lattice),
        anchor = site,
        expression = ifelse(proposal.is_extension, 1.0, 0.0),
    )
    proposal_error = analysis_failure(proposal_energy)
    @test proposal_error isa PottsToolkit.PottsValidationError
    @test only(proposal_error.diagnostics).kind === :illegal_operation_use

    stochastic_energy = HamiltonianTerm(
        :stochastic_energy;
        domain = sites(:lattice),
        anchor = site,
        expression = draw(
            Normal(0.0, 1.0),
            DrawKey(:forbidden_energy_draw),
        ),
    )
    stochastic_error = analysis_failure(stochastic_energy)
    @test stochastic_error isa PottsToolkit.PottsValidationError
    @test any(
        diagnostic -> diagnostic.kind === :stochastic_hamiltonian,
        stochastic_error.diagnostics,
    )

    foreign_site = SiteBinding(:foreign_site)
    foreign_anchor_error = analysis_failure(HamiltonianTerm(
        :foreign_anchor;
        domain = sites(:lattice),
        anchor = site,
        expression = occupancy(endothelial, foreign_site),
    ))
    @test foreign_anchor_error isa PottsToolkit.PottsValidationError
    @test only(foreign_anchor_error.diagnostics).kind ===
          :invalid_hamiltonian_domain

    unbounded_error = analysis_failure(HamiltonianTerm(
        :unbounded_site_energy;
        domain = sites(:lattice),
        anchor = site,
        expression = neighbor_sum(
            anchor_value(site),
            occupancy(endothelial, site),
        ),
    ))
    @test unbounded_error isa PottsToolkit.PottsValidationError
    @test only(unbounded_error.diagnostics).kind ===
          :illegal_operation_use

    mismatched_domain_error = analysis_failure(HamiltonianTerm(
        :mismatched_domain;
        domain = cells(endothelial),
        anchor = site,
        expression = 1.0,
    ))
    @test mismatched_domain_error isa PottsToolkit.PottsValidationError
    @test only(mismatched_domain_error.diagnostics).kind ===
          :invalid_hamiltonian_domain

    mutated_core = PottsToolkit.StatementCore(
        StatementID(:mutating_hamiltonian),
        (
            domain = sites(:lattice),
            anchor = site,
            expression = 1.0,
            effects = (Assign(external_site_state, 2.0),),
        ),
        NamedTuple(),
        UnknownSource(),
    )
    mutation_error = analysis_failure(HamiltonianTerm(mutated_core))
    @test mutation_error isa PottsToolkit.PottsValidationError

    false_registry = NeutralExternalTerms.registry(
        site_affected_region = :incident_contacts,
    )
    false_declaration_error = try
        false_completed = complete(
            neutral_extensions;
            registry = false_registry,
        )
        PottsToolkit._analyze_completed_system(false_completed)
        nothing
    catch caught
        caught
    end
    @test false_declaration_error isa PottsToolkit.PottsValidationError
    @test only(false_declaration_error.diagnostics).kind ===
          :invalid_hamiltonian_domain
end
