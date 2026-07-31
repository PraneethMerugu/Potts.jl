include("fixtures/NeutralExternalTerms.jl")
using .NeutralExternalTerms

function invalid_transfer_operation end
Symbolics.@register_symbolic invalid_transfer_operation(x)::Real

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
        :scalar,
        true,
        true,
    )
end

@testset "G1 host compiler facts" begin
    @parameters site_weight = 2.0 pair_weight = 3.0
    endothelial = CellKind(:endothelial)
    extracellular = MediumKind(:extracellular)
    proposal = ProposalContext(:copy)
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
        NeutralExternalTerms.ExternalWeightedSiteTerm(
            :external_weighted_site,
            site_weight,
            proposal,
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
    @test candidates[site_id].category === :proposal
    @test candidates[pair_id].category === :proposal

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
        ProposalEnergy(
            :invalid_external_operation,
            unsupported_host_operation(site_weight),
        ),
    )), parameters = [site_weight])
    invalid_completed = complete(invalid_transfer)
    error = try
        PottsToolkit._analyze_completed_system(invalid_completed)
        nothing
    catch caught
        caught
    end
    @test error isa PottsToolkit.PottsValidationError
    @test error.stage === :normalization
    @test only(error.diagnostics).kind === :missing_operation_transfer

    @named malformed_transfer = PottsSystem(statements = StatementSet((
        ProposalEnergy(
            :malformed_external_operation,
            invalid_transfer_operation(site_weight),
        ),
    )), parameters = [site_weight])
    malformed_completed = complete(malformed_transfer)
    malformed_error = try
        PottsToolkit._analyze_completed_system(malformed_completed)
        nothing
    catch caught
        caught
    end
    @test malformed_error isa PottsToolkit.PottsValidationError
    @test malformed_error.stage === :analysis
    @test only(malformed_error.diagnostics).kind ===
          :invalid_operation_transfer
end
