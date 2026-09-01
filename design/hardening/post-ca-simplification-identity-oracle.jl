using SHA
using Test
import CorePotts
import LocalWorksets

const REPOSITORY = normpath(joinpath(@__DIR__, "..", ".."))
include(joinpath(REPOSITORY, "lib", "CorePotts", "test", "test_program_v1_support.jl"))
include(joinpath(REPOSITORY, "lib", "CorePotts", "test", "lw5b2_proposal_bridge_support.jl"))

function simplification_claim_runtime()
    ownership = zeros(Int32, 6, 6)
    ownership[2:3, 2:3] .= 1
    ownership[4:5, 4:5] .= 2
    initial = CorePotts.ProgramInitialState(
        ownership, Int16[2, 2]; scalar_type = Float64
    )
    program = test_program(
        CorePotts.CheckerboardProgramEngine();
        descriptor_plan = empty_descriptor_plan(),
        stage_plan = CorePotts.StageExecutionPlan(),
    )
    runtime = CorePotts._materialize_program(
        program,
        initial,
        Float64[],
        UInt64(0x51a7),
        UInt32(3);
        repeat = UInt32(2),
    )
    return CorePotts._select_checkerboard_execution(
        runtime, CorePotts._DirectCheckerboardExecutionSelection()
    )
end

# Reproduction of the frozen dirty-worktree pre-S2 report serializer. Profile
# extraction is deliberately supplied by the current centrally validated
# extractor; static review owns extraction-equivalence evidence.
function legacy_localworksets_report(
        direct, maturity, profile, qualification::Symbol
    )
    source = direct.key
    base = source.mechanisms
    mechanism_identity = profile.mechanism_identity
    lowering_identity = profile.lowering_identity
    provider = profile.provider
    provider_compiler = profile.provider_compiler
    if qualification === :candidate
        suite = maturity === CorePotts.Functional ?
            profile.functional_suite : profile.replay_suite
        status = CorePotts.Experimental
        profile_identity = :localworksets_experimental_v1
        reason = maturity === CorePotts.Functional ?
            "Private bounded LocalWorksets $(profile.reason_subject) have functional CPU/Metal evidence; replay and performance qualification are not claimed." :
            "Private bounded LocalWorksets $(profile.reason_subject) have exact continuation and direct-path parity evidence; performance qualification is not claimed."
    elseif qualification === :promoted
        suite = maturity === CorePotts.PerformanceQualified ?
            :lw5d_localworksets_performance_v1 :
            :lw5d_localworksets_replay_v1
        status = CorePotts.Supported
        profile_identity = :corepotts_localworksets_k02_k03_v1
        reason = "The bounded LocalWorksets K02/K03 checkerboard proposal profile has exact CPU/Metal science, replay, failure, lifetime, and performance qualification; other backends and operation families remain unclaimed."
    else
        throw(ArgumentError("unknown legacy qualification"))
    end
    authority = (authority = :CorePotts, suite, revision = v"1.0.0")
    mechanisms = CorePotts.CapabilityMechanismProfile(
        base.proposal_fingerprint,
        base.descriptor_fingerprint,
        base.stage_fingerprint,
        base.relationship_fingerprint,
        base.tracker_fingerprint,
        CorePotts._capability_digest((
            direct = base.checkerboard_fingerprint,
            mechanism_identity,
            lowering_identity,
            provider,
            provider_compiler,
        )),
        base.rng_contract_version,
        base.rng_lowering_identity,
        (base.code_identities..., (
            identity = mechanism_identity,
            lowering = lowering_identity,
            provider,
        )),
        authority,
        profile_identity,
    )
    key = CorePotts.ProgramCapabilityKey(
        source.engine,
        source.backend,
        source.device,
        source.topology,
        source.scalar_type,
        source.math_policy,
        source.lifecycle,
        source.component_state,
        mechanisms,
        source.replay;
        environment = source.environment,
    )
    evidence_profile = (
        capability_fingerprint = CorePotts._capability_key_fingerprint(key),
        authority,
        mechanism_identity,
        lowering_identity,
        provider_compiler,
        maturity,
    )
    evidence = CorePotts.CapabilityEvidenceIdentity(
        :CorePotts,
        authority.suite,
        authority.revision,
        bytes2hex(SHA.sha256(repr(evidence_profile))),
    )
    return CorePotts.ProgramCapabilityReport(
        key,
        status,
        maturity,
        reason,
        evidence,
        direct.state_domains,
        direct.stage_effects,
        direct.relationships,
        direct.trackers,
        direct.checkerboard_plan,
    )
end

function legacy_checkpoint_block(runtime, execution)
    profile = (
        schema = v"1.0.0",
        mechanism_identity = execution.mechanism_identity,
        lowering_identity = execution.lowering_identity,
        wrapper_identity = execution.wrapper_identity,
        provider = :KernelAbstractions,
        provider_compiler = execution.provider_compiler,
        queue_mcs_capacity = execution.queue_mcs_capacity,
        capability_status = runtime.capability_report.status,
        capability_maturity = runtime.capability_report.maturity,
        capability_fingerprint = CorePotts._capability_key_fingerprint(
            runtime.capability_report.key
        ),
        capability_evidence = (
            authority = runtime.capability_report.evidence.authority,
            suite = runtime.capability_report.evidence.suite,
            revision = runtime.capability_report.evidence.revision,
            profile_fingerprint =
                runtime.capability_report.evidence.profile_fingerprint,
        ),
    )
    return merge(profile, (
        evidence_fingerprint = bytes2hex(SHA.sha256(repr(profile))),
    ))
end

function report_identity(runtime)
    report = runtime.capability_report
    block = CorePotts._checkpoint_execution_block(runtime)
    return (
        mechanism = block.mechanism_identity,
        reason = report.reason,
        capability_fingerprint =
            CorePotts._capability_key_fingerprint(report.key),
        profile_fingerprint = report.evidence.profile_fingerprint,
        checkpoint_fingerprint = block.evidence_fingerprint,
    )
end

@testset "pre-S2 report and checkpoint serializer oracle" begin
    claim_base = simplification_claim_runtime()
    claim = CorePotts._localworksets_replay_candidate_runtime(claim_base)
    claim_profile = CorePotts._localworksets_claim_execution_profile(
        claim.engine_workspace.claims
    )
    legacy_claim = legacy_localworksets_report(
        claim_base.capability_report,
        CorePotts.ReplayQualified,
        (;
            claim_profile.mechanism_identity,
            claim_profile.lowering_identity,
            claim_profile.provider,
            claim_profile.provider_compiler,
            functional_suite = :lw2_localworksets_functional_v1,
            replay_suite = :lw3_localworksets_replay_v1,
            reason_subject = "claim lowering",
        ),
        :candidate,
    )
    @test legacy_claim == claim.capability_report
    @test legacy_checkpoint_block(claim, (
        mechanism_identity = claim_profile.mechanism_identity,
        lowering_identity = claim_profile.lowering_identity,
        wrapper_identity = :corepotts_private_claim_block_v1,
        provider_compiler = claim_profile.provider_compiler,
        queue_mcs_capacity = 12,
    )) == CorePotts._checkpoint_execution_block(claim)

    _, promoted = lw5b2_runtime(; production_default = true)
    proposal_profile = CorePotts._localworksets_proposal_execution_profile(
        promoted.engine_workspace.proposal_stages
    )
    direct_report = CorePotts._checkerboard_core(
        promoted.engine_workspace
    ).capability_report
    legacy_promoted = legacy_localworksets_report(
        direct_report,
        CorePotts.PerformanceQualified,
        (;
            proposal_profile.mechanism_identity,
            proposal_profile.lowering_identity,
            proposal_profile.provider,
            proposal_profile.provider_compiler,
            functional_suite = :lw5c_localworksets_functional_v1,
            replay_suite = :lw5c_localworksets_replay_v1,
            reason_subject =
                "candidate-generation/proposal-evaluation lowering",
        ),
        :promoted,
    )
    @test legacy_promoted == promoted.capability_report
    @test legacy_checkpoint_block(promoted, (
        mechanism_identity = proposal_profile.mechanism_identity,
        lowering_identity = proposal_profile.lowering_identity,
        wrapper_identity =
            :corepotts_localworksets_proposal_stages_v1,
        provider_compiler = proposal_profile.provider_compiler,
        queue_mcs_capacity = 12,
    )) == CorePotts._checkpoint_execution_block(promoted)

    expected_keys = (
        :schema,
        :mechanism_identity,
        :lowering_identity,
        :wrapper_identity,
        :provider,
        :provider_compiler,
        :queue_mcs_capacity,
        :capability_status,
        :capability_maturity,
        :capability_fingerprint,
        :capability_evidence,
        :evidence_fingerprint,
    )
    @test keys(CorePotts._checkpoint_execution_block(claim)) == expected_keys
    @test keys(CorePotts._checkpoint_execution_block(promoted)) == expected_keys
    claim_identity = report_identity(claim)
    promoted_identity = report_identity(promoted)
    @test (
        claim_identity.capability_fingerprint,
        claim_identity.profile_fingerprint,
        claim_identity.checkpoint_fingerprint,
    ) == (
        "e331353c1e8a081a735c6665ffa9d3cc8dcc3086c90e23b8b38b889f9db82fb9",
        "c0e6910a8774fe1e7b423e7bad3154834415b5b5609cc92f2b9b8881dfe237a9",
        "13120ccaeb1fe2e651d63974d97ffb67f3e92b23c6e6b351c039b8286bb7d864",
    )
    @test (
        promoted_identity.capability_fingerprint,
        promoted_identity.profile_fingerprint,
        promoted_identity.checkpoint_fingerprint,
    ) == (
        "8fad5ac74658b1434722688ba70acd6d53e6858897b0ecdd81bed1a6184cf018",
        "cb811e1adba4fb0ff628cbb33ac16ba2594a0a95e573f7be7b9b2403ab7e7933",
        "1f960ceebe08e8fa5c35751238dfa25e73e8b5ca2a1325b9dcc3bea73989b9d7",
    )
    println(claim_identity)
    println(promoted_identity)
end
