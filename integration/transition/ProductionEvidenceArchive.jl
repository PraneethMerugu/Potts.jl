module ProductionEvidenceArchive

using SHA
using TOML
using ..TransitionEvidenceArchive
using ..TransitionEmpirical
using ..TransitionFixtures
using ..ProductionTransitionSampler

export build_production_evidence, build_limited_domain_evidence,
       validate_production_evidence, write_production_evidence

const PRODUCTION_EVIDENCE_SCHEMA_VERSION = "1.1.0"
const SUPPORTED_PRODUCTION_EVIDENCE_SCHEMA_VERSIONS = ("1.0.0", "1.1.0")

_number_strings(values) = string.(values)

function _base_record(fixture::TransitionFixture, row, algorithm, backend,
        manifest, source_revision, reproduction_command)
    fixture_data = row.fixture
    contracts = manifest["contract_versions"]
    algorithm_name = algorithm_symbol(algorithm) === :sequential ?
        "SequentialCPM" : "CheckerboardSweepCPM"
    scheduler_version = algorithm_name == "SequentialCPM" ?
        contracts["sequential_algorithm"] : contracts["checkerboard_scheduler"]
    return Dict{String, Any}(
        "schema" => Dict(
            "name" => "potts-production-transition-evidence",
            "version" => PRODUCTION_EVIDENCE_SCHEMA_VERSION),
        "identity" => Dict(
            "fixture" => String(fixture_data["id"]),
            "row_id" => String(row.row_id),
            "source_state_encoding" => fixture.source_encoding,
            "source_state_fingerprint" => state_fingerprint(fixture.oracle_state),
            "model_identity" => contracts["model"],
            "algorithm_identity" => algorithm_name,
            "algorithm_semantic_version" => scheduler_version,
            "scheduler_identity" => algorithm_name == "SequentialCPM" ?
                "sequential_with_replacement" : "realized_graph_colored_sweep",
            "scheduler_version" => scheduler_version,
            "rng_identity" => "Philox4x32x10V1",
            "rng_contract_version" => contracts["rng"],
            "analysis_program_identity" => "ProductionTransitionSampler",
            "analysis_program_version" => contracts["analysis_program"],
            "sampling_plan_version" => manifest["statistical_plan"],
            "backend_identity" => String(backend),
            "source_revision" => String(source_revision)),
        "fixture" => Dict(
            "dimensions" => fixture_data["dimensions"],
            "dimension" => fixture_data["dimension"],
            "topology" => fixture_data["topology"],
            "boundaries" => fixture_data["boundaries"],
            "temperature" => fixture_data["temperature"],
            "energy_scale" => fixture_data["energy_scale"],
            "components" => fixture_data["components"],
            "acceptance_law" => fixture_data["acceptance_law"]),
        "environment" => Dict(
            "julia_version" => string(VERSION),
            "operating_system" => string(Sys.KERNEL),
            "architecture" => string(Sys.ARCH),
            "threads" => Threads.nthreads(),
            "production_real_type" => string(typeof(fixture.production_temperature))),
        "reproduction_command" => String(reproduction_command),
    )
end

function build_limited_domain_evidence(fixture::TransitionFixture, row, algorithm;
        backend::AbstractString, manifest::AbstractDict = load_transition_manifest(),
        source_revision::AbstractString, reproduction_command::AbstractString,
        limitation = fixture.production_limitation)
    limitation === nothing && throw(ArgumentError(
        "limited-domain evidence requires an explicit limitation"))
    record = _base_record(fixture, row, algorithm, backend, manifest,
        source_revision, reproduction_command)
    record["result"] = Dict{String, Any}(
        "status" => "limited-domain",
        "qualification_passed" => false,
        "statistical_test_run" => false,
        "limitation" => String(limitation),
        "registered_disposition" => "limited-domain-unqualified")
    return record
end

function build_production_evidence(fixture::TransitionFixture, row,
        sample::ProductionRowSample; profile::Symbol,
        manifest::AbstractDict = load_transition_manifest(),
        source_revision::AbstractString, reproduction_command::AbstractString)
    fixture.production_supported || throw(ArgumentError(
        "unsupported fixtures require build_limited_domain_evidence"))
    profile in (:diagnostic, :qualification) || throw(ArgumentError(
        "profile must be :diagnostic or :qualification"))
    registered_replicas = Int(manifest["empirical_sampling"]["replicas_per_source_state"])
    profile === :qualification && sample.replicas != registered_replicas &&
        throw(ArgumentError("qualification profile requires $registered_replicas replicas"))
    plan = TransitionSamplingPlan(replicas = sample.replicas)
    oracle = oracle_probability_row(fixture, sample.algorithm)
    result = evaluate_empirical_row(oracle, sample.counts, sample.source_id; plan)
    record = _base_record(fixture, row, sample.algorithm, sample.backend, manifest,
        source_revision, reproduction_command)
    record["sampling"] = Dict{String, Any}(
        "profile" => String(profile),
        "replicas" => sample.replicas,
        "independent_replicas" => true,
        "first_seed_hex" => string("0x", string(sample.first_seed; base = 16, pad = 16)),
        "last_seed_hex" => string("0x", string(sample.last_seed; base = 16, pad = 16)),
        "source_state_id" => sample.source_id,
        "launches" => sample.launches,
        "observation_synchronizations" => sample.observation_synchronizations)
    record["oracle"] = Dict{String, Any}(
        "precision" => iszero(fixture.temperature) ? "exact_rational" : "bounded_bigfloat",
        "row" => _number_strings(oracle),
        "support" => count(>(0), oracle))
    record["raw_counts"] = sample.counts
    record["result"] = Dict{String, Any}(
        "status" => result.passed ? "statistical-pass" : "statistical-fail",
        "statistical_passed" => result.passed,
        "qualification_passed" => profile === :qualification && result.passed,
        "empirical_row" => _number_strings(result.empirical),
        "absolute_residuals" => _number_strings(result.absolute_residuals),
        "total_variation" => string(result.total_variation),
        "maximum_absolute_residual" => string(result.maximum_absolute_residual),
        "self_transition_residual" => string(result.self_transition_residual),
        "total_variation_radius" => string(result.total_variation_radius),
        "absolute_probability_radius" => string(result.absolute_probability_radius),
        "impossible_destinations" => result.impossible_destinations,
        "failed_criteria" => result.failed_criteria)
    return record
end

function validate_production_evidence(record::AbstractDict)
    errors = String[]
    get(get(record, "schema", Dict()), "name", nothing) ==
        "potts-production-transition-evidence" || push!(errors, "invalid schema name")
    schema_version = get(get(record, "schema", Dict()), "version", nothing)
    schema_version in SUPPORTED_PRODUCTION_EVIDENCE_SCHEMA_VERSIONS ||
        push!(errors, "invalid schema version")
    for table in ("identity", "fixture", "environment", "result")
        get(record, table, nothing) isa AbstractDict || push!(errors, "missing table '$table'")
    end
    identity = get(record, "identity", Dict())
    for field in ("fixture", "row_id", "source_state_encoding",
            "source_state_fingerprint", "model_identity", "algorithm_identity",
            "scheduler_identity", "rng_identity", "backend_identity", "source_revision")
        isempty(string(get(identity, field, ""))) && push!(errors,
            "missing identity field '$field'")
    end
    environment = get(record, "environment", Dict())
    schema_version == "1.1.0" &&
        !(get(environment, "production_real_type", "") in ("Float32", "Float64")) &&
        push!(errors, "missing or invalid production real type")
    result = get(record, "result", Dict())
    status = get(result, "status", "")
    status in ("limited-domain", "statistical-pass", "statistical-fail") ||
        push!(errors, "invalid result status")
    if status != "limited-domain"
        sampling = get(record, "sampling", nothing)
        oracle = get(record, "oracle", nothing)
        counts = get(record, "raw_counts", nothing)
        sampling isa AbstractDict || push!(errors, "missing sampling table")
        oracle isa AbstractDict || push!(errors, "missing oracle table")
        counts isa AbstractVector || push!(errors, "missing raw counts")
        if sampling isa AbstractDict && counts isa AbstractVector
            sum(counts) == get(sampling, "replicas", -1) || push!(errors,
                "raw counts do not sum to replicas")
        end
        get(result, "qualification_passed", false) &&
            get(sampling, "profile", "") != "qualification" && push!(errors,
                "diagnostic evidence cannot pass qualification")
    end
    return (; valid = isempty(errors), errors)
end

function write_production_evidence(path::AbstractString, record::AbstractDict;
        force::Bool = false)
    report = validate_production_evidence(record)
    report.valid || throw(ArgumentError(
        "refusing to write invalid production evidence: $(join(report.errors, "; "))"))
    isfile(path) && !force && throw(ArgumentError(
        "production evidence already exists; pass force=true to replace it"))
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, record; sorted = true)
    end
    return path
end

end
