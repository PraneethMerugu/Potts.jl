#!/usr/bin/env julia

using SHA
using TOML

include(joinpath(@__DIR__, "TransitionKernelOracle.jl"))
include(joinpath(@__DIR__, "TransitionKernelAnalysis.jl"))
include(joinpath(@__DIR__, "TransitionEvidenceArchive.jl"))
include(joinpath(@__DIR__, "CheckerboardOracle.jl"))

using .TransitionKernelOracle
using .TransitionEvidenceArchive
using .CheckerboardOracle

function moore_relation(::Val{N}) where {N}
    offsets = Tuple(offset for offset in Iterators.product(
        ntuple(_ -> -1:1, Val(N))...) if any(!iszero, offset))
    return OracleRelation(offsets)
end

function source_identity()
    inputs = (
        joinpath(@__DIR__, "TransitionKernelOracle.jl"),
        joinpath(@__DIR__, "TransitionKernelAnalysis.jl"),
        joinpath(@__DIR__, "TransitionEvidenceArchive.jl"),
        @__FILE__,
    )
    payload = join((string(basename(path), '\n', read(path, String)) for path in inputs), '\n')
    return string("content-sha256:", content_fingerprint(payload))
end

function model_fingerprint(domain, relation, model)
    payload = repr((domain.dims, domain.boundaries, domain.mutable_sites,
        relation.offsets, relation.weights, model.energies,
        typeof(model.acceptance), model.temperature))
    return string("sha256:", content_fingerprint(payload))
end

function evidence_identity(fixture, state, domain, relation, model;
        topology, boundaries, components, source_revision,
        algorithm = "SequentialCPM", scheduler = "sequential_with_replacement")
    return EvidenceIdentity(
        model_fingerprint = model_fingerprint(domain, relation, model),
        initial_state_fingerprint = state_fingerprint(state),
        algorithm = algorithm,
        algorithm_semantic_version = v"1.0.0",
        scheduler = scheduler,
        scheduler_version = v"1.0.0",
        rng = "Philox4x32x10V1",
        rng_contract_version = v"1.0.0",
        semantic_seed_or_range = "exact-enumeration:no-random-draws",
        topology = topology,
        boundaries = boundaries,
        dimension = length(domain.dims),
        acceptance_law = string(nameof(typeof(model.acceptance))),
        temperature = string(model.temperature),
        components = components,
        backend = "cpu-exact-oracle",
        fixture = fixture,
        sampling_plan_version = "phase13-transition-evidence-v1",
        analysis_program = "TransitionEvidenceArchive",
        analysis_program_version = ANALYSIS_PROGRAM_VERSION,
        source_revision = source_revision,
    )
end

function archive_pair(output_directory, fixture, domain, relation, model, catalog;
        topology, boundaries, components, source_revision, force)
    primitive = primitive_kernel(catalog, domain, model)
    normalized = sequential_mcs_kernel(catalog, domain, model)
    checkerboard = checkerboard_mcs_kernel(catalog, domain, model)
    source_state = catalog.states[min(2, length(catalog.states))]
    observable = [count(owner -> owner.kind === OracleCellKind, state.owners)
                  for state in catalog.states]
    identity_base = (; topology, boundaries, components, source_revision)
    artifacts = String[]
    for (suffix, kernel, reference) in (
            ("primitive", primitive, nothing),
            ("normalized-mcs", normalized, primitive),
            ("checkerboard-normalized-mcs", checkerboard, normalized))
        checkerboard_record = startswith(suffix, "checkerboard")
        identity = evidence_identity(string(fixture, '-', suffix), source_state,
            domain, relation, model; identity_base...,
            algorithm = checkerboard_record ? "CheckerboardSweepCPM" : "SequentialCPM",
            scheduler = checkerboard_record ? "realized_graph_colored_sweep" :
                "sequential_with_replacement")
        archive = archive_kernel(kernel; identity, domain, reference_kernel = reference,
            observable,
            thresholds = Dict(
                "row_sum" => "exact",
                "nonnegative" => "exact",
                "comparison_support_tolerance" => "0",
            ),
            environment = Dict(
                "julia_version" => string(VERSION),
                "arithmetic" => "Rational{BigInt}",
                "operating_system" => string(Sys.KERNEL),
                "architecture" => string(Sys.ARCH),
            ),
            reproduction_command = string(
                "julia --project=integration integration/transition/",
                "generate_transition_evidence.jl --force"),
        )
        path = joinpath(output_directory, string(fixture, '-', suffix, ".toml"))
        write_evidence_archive(path, archive; force)
        push!(artifacts, path)
    end
    return artifacts
end

function generate(output_directory; force = false)
    source_revision = source_identity()
    artifacts = String[]

    hand = hand_derived_1d_fixture()
    append!(artifacts, archive_pair(output_directory, "hand-derived-1d-noflux-zero",
        hand.domain, hand.relation, hand.model, hand.catalog;
        topology = "von_neumann", boundaries = ["no_flux"], components = ["none"],
        source_revision, force))

    medium = oracle_medium(1)
    cell = oracle_cell(1)
    labels = (medium, cell)
    owner_types = Dict(medium => 1, cell => 2)

    domain_2d = OracleDomain((2, 2);
        boundaries = (OraclePeriodic, OraclePeriodic))
    relation_2d = von_neumann_relation(Val(2))
    zero_volume = OracleVolumeEnergy(Dict(1 => 2), Dict(1 => 0))
    zero_contact = OracleContactEnergy(zeros(Int, 2, 2), owner_types, relation_2d)
    model_2d = OracleModel(relation_2d, (zero_volume, zero_contact); temperature = 0)
    catalog_2d = enumerate_states(domain_2d, labels)
    append!(artifacts, archive_pair(output_directory, "2d-vn-periodic-zero-sparse",
        domain_2d, relation_2d, model_2d, catalog_2d;
        topology = "von_neumann", boundaries = ["periodic", "periodic"],
        components = ["adhesion", "volume"], source_revision, force))

    domain_moore = OracleDomain((2, 2);
        boundaries = (OracleNoFlux, OracleNoFlux))
    relation_moore = moore_relation(Val(2))
    volume = OracleVolumeEnergy(Dict(1 => 2), Dict(1 => 1))
    contact = OracleContactEnergy(Int[0 2; 2 0], owner_types, relation_moore)
    model_moore = OracleModel(relation_moore, (volume, contact); temperature = 0)
    catalog_moore = enumerate_states(domain_moore, labels)
    append!(artifacts, archive_pair(output_directory, "2d-moore-noflux-zero-mixed",
        domain_moore, relation_moore, model_moore, catalog_moore;
        topology = "moore", boundaries = ["no_flux", "no_flux"],
        components = ["adhesion", "volume"], source_revision, force))

    domain_3d = OracleDomain((2, 1, 1);
        boundaries = (OracleNoFlux, OracleNoFlux, OracleNoFlux))
    relation_3d = von_neumann_relation(Val(3))
    volume_3d = OracleVolumeEnergy(Dict(1 => 1), Dict(1 => 1))
    contact_3d = OracleContactEnergy(Int[0 1; 1 0], owner_types, relation_3d)
    model_3d = OracleModel(relation_3d, (volume_3d, contact_3d); temperature = 0)
    catalog_3d = enumerate_states(domain_3d, labels)
    append!(artifacts, archive_pair(output_directory, "3d-vn-noflux-zero-lowering",
        domain_3d, relation_3d, model_3d, catalog_3d;
        topology = "von_neumann", boundaries = fill("no_flux", 3),
        components = ["adhesion", "volume"], source_revision, force))

    index = Dict{String, Any}(
        "schema_version" => "1.0.0",
        "evidence_schema_version" => string(EVIDENCE_SCHEMA_VERSION),
        "analysis_program_version" => string(ANALYSIS_PROGRAM_VERSION),
        "source_revision" => source_revision,
        "fixture_manifest" => "../../../audits/phase-13-fixture-manifest.toml",
        "artifacts" => [Dict{String, Any}(
            "path" => basename(path),
            "sha256" => bytes2hex(open(sha256, path)),
        ) for path in artifacts],
    )
    index_path = joinpath(output_directory, "index.toml")
    isfile(index_path) && !force && throw(ArgumentError(
        "evidence index already exists; pass --force to replace it"))
    mkpath(output_directory)
    open(index_path, "w") do io
        TOML.print(io, index; sorted = true)
    end
    return artifacts, index_path
end

function main(args)
    force = "--force" in args
    positional = filter(!=("--force"), args)
    root = normpath(joinpath(@__DIR__, "..", ".."))
    output_directory = isempty(positional) ?
        joinpath(root, "design", "evidence", "phase-13", "exact") : abspath(first(positional))
    artifacts, index = generate(output_directory; force)
    println("wrote $(length(artifacts)) exact transition archives and $(index)")
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
