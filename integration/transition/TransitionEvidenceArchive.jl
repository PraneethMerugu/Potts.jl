module TransitionEvidenceArchive

using SHA
using SparseArrays
using TOML

using ..TransitionKernelOracle
using ..TransitionKernelAnalysis

export EVIDENCE_SCHEMA_VERSION, ANALYSIS_PROGRAM_VERSION,
       EvidenceIdentity, EvidenceValidationReport,
       archive_kernel, write_evidence_archive, read_evidence_archive,
       validate_evidence_archive, validate_fixture_manifest,
       state_encoding, state_fingerprint, content_fingerprint

const EVIDENCE_SCHEMA_VERSION = v"1.0.0"
const ANALYSIS_PROGRAM_VERSION = v"1.0.0"

"""Complete semantic and execution identity attached to one evidence record."""
struct EvidenceIdentity
    model_fingerprint::String
    initial_state_fingerprint::String
    algorithm::String
    algorithm_semantic_version::VersionNumber
    scheduler::String
    scheduler_version::VersionNumber
    rng::String
    rng_contract_version::VersionNumber
    semantic_seed_or_range::String
    topology::String
    boundaries::Vector{String}
    dimension::Int
    acceptance_law::String
    temperature::String
    components::Vector{String}
    backend::String
    fixture::String
    sampling_plan_version::String
    analysis_program::String
    analysis_program_version::VersionNumber
    source_revision::String
end

function EvidenceIdentity(; model_fingerprint, initial_state_fingerprint,
        algorithm, algorithm_semantic_version, scheduler, scheduler_version,
        rng, rng_contract_version, semantic_seed_or_range, topology, boundaries,
        dimension, acceptance_law, temperature, components, backend, fixture,
        sampling_plan_version, analysis_program = "TransitionEvidenceArchive",
        analysis_program_version = ANALYSIS_PROGRAM_VERSION, source_revision)
    dimension > 0 || throw(ArgumentError("evidence dimension must be positive"))
    boundary_values = String.(collect(boundaries))
    length(boundary_values) == dimension || throw(ArgumentError(
        "evidence requires one boundary identity per dimension"))
    component_values = sort!(unique!(String.(collect(components))))
    isempty(component_values) && throw(ArgumentError(
        "evidence must identify at least one component or 'none'"))
    values = (model_fingerprint, initial_state_fingerprint, algorithm, scheduler,
        rng, semantic_seed_or_range, topology, acceptance_law, temperature,
        backend, fixture, sampling_plan_version, analysis_program, source_revision)
    all(value -> !isempty(strip(string(value))), values) || throw(ArgumentError(
        "evidence identity strings must not be empty"))
    return EvidenceIdentity(
        string(model_fingerprint), string(initial_state_fingerprint), string(algorithm),
        VersionNumber(algorithm_semantic_version), string(scheduler),
        VersionNumber(scheduler_version), string(rng), VersionNumber(rng_contract_version),
        string(semantic_seed_or_range), string(topology), boundary_values, Int(dimension),
        string(acceptance_law), string(temperature), component_values, string(backend),
        string(fixture), string(sampling_plan_version), string(analysis_program),
        VersionNumber(analysis_program_version), string(source_revision))
end

struct EvidenceValidationReport
    valid::Bool
    errors::Vector{String}
    warnings::Vector{String}
end

content_fingerprint(value::AbstractString) = bytes2hex(sha256(codeunits(value)))

function _owner_encoding(owner::OracleOwner)
    kind = owner.kind === OracleCellKind ? "cell" : "medium"
    return string(kind, ':', owner.id)
end

function state_encoding(state::OracleMicrostate)
    owners = join((_owner_encoding(owner) for owner in state.owners), ',')
    return isempty(state.discrete) ? owners : string(owners, "|discrete=", repr(state.discrete))
end

state_fingerprint(state::OracleMicrostate) = content_fingerprint(state_encoding(state))

function _identity_dict(identity::EvidenceIdentity)
    return Dict{String, Any}(
        "model_fingerprint" => identity.model_fingerprint,
        "initial_state_fingerprint" => identity.initial_state_fingerprint,
        "algorithm" => identity.algorithm,
        "algorithm_semantic_version" => string(identity.algorithm_semantic_version),
        "scheduler" => identity.scheduler,
        "scheduler_version" => string(identity.scheduler_version),
        "rng" => identity.rng,
        "rng_contract_version" => string(identity.rng_contract_version),
        "semantic_seed_or_range" => identity.semantic_seed_or_range,
        "topology" => identity.topology,
        "boundaries" => identity.boundaries,
        "dimension" => identity.dimension,
        "acceptance_law" => identity.acceptance_law,
        "temperature" => identity.temperature,
        "components" => identity.components,
        "backend" => identity.backend,
        "fixture" => identity.fixture,
        "sampling_plan_version" => identity.sampling_plan_version,
        "analysis_program" => identity.analysis_program,
        "analysis_program_version" => string(identity.analysis_program_version),
        "source_revision" => identity.source_revision,
    )
end

_number_text(value::Rational) = string(numerator(value), "//", denominator(value))
_number_text(value::Real) = string(value)

function _parse_number(value)
    value isa Real && return BigFloat(value)
    text = string(value)
    if occursin("//", text)
        parts = split(text, "//"; limit = 2)
        length(parts) == 2 || throw(ArgumentError("invalid rational encoding: $text"))
        return parse(BigInt, parts[1]) // parse(BigInt, parts[2])
    end
    return parse(BigFloat, text)
end

function _precision_dict(kernel::SparseTransitionKernel)
    record = kernel.convergence
    record === nothing && return Dict{String, Any}(
        "kind" => "exact_rational",
        "bits" => 0,
        "converged" => true,
        "maximum_absolute_difference" => "0",
        "tolerance" => "0",
    )
    return Dict{String, Any}(
        "kind" => "bounded_bigfloat",
        "bits" => record.refined_bits,
        "base_bits" => record.base_bits,
        "refined_bits" => record.refined_bits,
        "converged" => record.converged,
        "maximum_absolute_difference" => _number_text(record.maximum_absolute_difference),
        "tolerance" => _number_text(record.tolerance),
    )
end

function _matrix_entries(matrix)
    entries = Dict{String, Any}[]
    for source in axes(matrix, 1), destination in axes(matrix, 2)
        probability = matrix[source, destination]
        iszero(probability) && continue
        push!(entries, Dict{String, Any}(
            "source" => source,
            "destination" => destination,
            "probability" => _number_text(probability),
        ))
    end
    return entries
end

function _state_records(catalog::StateCatalog)
    return [Dict{String, Any}(
        "id" => index,
        "encoding" => state_encoding(state),
        "fingerprint" => state_fingerprint(state),
    ) for (index, state) in pairs(catalog.states)]
end

function _comparison_dict(reference, candidate)
    comparison = compare_kernels(reference, candidate)
    return Dict{String, Any}(
        "reference_resolution" => string(reference.resolution),
        "candidate_resolution" => string(candidate.resolution),
        "row_total_variation" => _number_text.(comparison.row_total_variation),
        "maximum_total_variation" => _number_text(comparison.maximum_total_variation),
        "maximum_row" => comparison.maximum_row,
        "maximum_absolute_residual" => _number_text(comparison.maximum_absolute_residual),
        "missing_support" => [collect(pair) for pair in comparison.missing_support],
        "added_support" => [collect(pair) for pair in comparison.added_support],
    )
end

function _analysis_dict(kernel::SparseTransitionKernel; observable = nothing)
    matrix = kernel.matrix
    stationary = stationary_analysis(matrix)
    currents = probability_currents(matrix, stationary.distribution)
    current_entries = Dict{String, Any}[]
    for source in axes(currents, 1), destination in axes(currents, 2)
        iszero(currents[source, destination]) && continue
        push!(current_entries, Dict{String, Any}(
            "source" => source,
            "destination" => destination,
            "current" => _number_text(currents[source, destination]),
        ))
    end
    spectral = spectral_analysis(matrix)
    result = Dict{String, Any}(
        "self_transition_probability" =>
            [_number_text(matrix[index, index]) for index in axes(matrix, 1)],
        "row_support_size" =>
            [count(!iszero, matrix[index, :]) for index in axes(matrix, 1)],
        "communicating_classes" => communicating_classes(matrix),
        "class_periods" => [Dict{String, Any}(
            "period" => period, "states" => states)
            for (period, states) in class_periods(matrix)],
        "irreducible" => is_irreducible(matrix),
        "aperiodic" => is_aperiodic(matrix),
        "stationary_distribution" => _number_text.(stationary.distribution),
        "stationarity_residual" => _number_text(stationary.stationarity_residual),
        "detailed_balance_residual" => _number_text(stationary.detailed_balance_residual),
        "stationary_nonnegative" => stationary.nonnegative,
        "stationary_normalized" => stationary.normalized,
        "probability_currents" => current_entries,
        "eigenvalues" => [Dict{String, Any}(
            "real" => _number_text(real(value)), "imaginary" => _number_text(imag(value)))
            for value in spectral.eigenvalues],
        "unit_eigenvalue_multiplicity" => spectral.unit_eigenvalue_multiplicity,
        "spectral_gap" => _number_text(spectral.spectral_gap),
        "relaxation_time" => isfinite(spectral.relaxation_time) ?
            _number_text(spectral.relaxation_time) : "infinity",
    )
    if observable !== nothing
        moments = observable_transition_moments(matrix, observable)
        result["observable"] = Dict{String, Any}(
            "values" => _number_text.(observable),
            "drift" => _number_text.(moments.drift),
            "diffusion" => _number_text.(moments.diffusion),
            "second_moment" => _number_text.(moments.second_moment),
        )
    end
    return result
end

"""Build a TOML-serializable, self-validating transition evidence record."""
function archive_kernel(kernel::SparseTransitionKernel;
        identity::EvidenceIdentity, domain::OracleDomain,
        reference_kernel::Union{Nothing, SparseTransitionKernel} = nothing,
        observable = nothing, raw_counts = nothing,
        thresholds::AbstractDict = Dict{String, Any}(),
        environment::AbstractDict = Dict{String, Any}(),
        reproduction_command::AbstractString = "")
    length(kernel.catalog.states[1].owners) == prod(domain.dims) || throw(ArgumentError(
        "evidence domain does not match the kernel state catalog"))
    identity.dimension == length(domain.dims) || throw(ArgumentError(
        "evidence identity dimension does not match the oracle domain"))
    validation = validate_kernel(kernel)
    validation.valid || throw(ArgumentError("cannot archive an invalid transition kernel"))
    archive = Dict{String, Any}(
        "schema" => Dict{String, Any}(
            "name" => "potts-transition-evidence",
            "version" => string(EVIDENCE_SCHEMA_VERSION),
        ),
        "identity" => _identity_dict(identity),
        "fixture" => Dict{String, Any}(
            "dimensions" => collect(domain.dims),
            "mutable_sites" => domain.mutable_sites,
        ),
        "states" => _state_records(kernel.catalog),
        "kernel" => Dict{String, Any}(
            "resolution" => string(kernel.resolution),
            "state_count" => length(kernel.catalog.states),
            "matrix_format" => "sparse-coordinate-row-source",
            "entries" => _matrix_entries(kernel.matrix),
        ),
        "precision" => _precision_dict(kernel),
        "validation" => Dict{String, Any}(
            "valid" => validation.valid,
            "nonnegative" => validation.nonnegative,
            "normalized" => validation.normalized,
            "row_sums" => _number_text.(validation.row_sums),
            "maximum_row_residual" => _number_text(validation.maximum_row_residual),
        ),
        "analysis" => _analysis_dict(kernel; observable),
        "thresholds" => Dict{String, Any}(string(key) => value
            for (key, value) in pairs(thresholds)),
        "environment" => Dict{String, Any}(string(key) => value
            for (key, value) in pairs(environment)),
        "reproduction_command" => string(reproduction_command),
    )
    reference_kernel === nothing ||
        (archive["comparison"] = _comparison_dict(reference_kernel, kernel))
    raw_counts === nothing || (archive["raw_counts"] = raw_counts)
    report = validate_evidence_archive(archive; expected_identity = identity)
    report.valid || error("generated invalid transition evidence: $(join(report.errors, "; "))")
    return archive
end

function write_evidence_archive(path::AbstractString, archive::AbstractDict; force::Bool = false)
    report = validate_evidence_archive(archive)
    report.valid || throw(ArgumentError(
        "refusing to write invalid evidence: $(join(report.errors, "; "))"))
    isfile(path) && !force && throw(ArgumentError(
        "evidence path already exists; pass force=true to replace it"))
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, archive; sorted = true)
    end
    return path
end

read_evidence_archive(path::AbstractString) = TOML.parsefile(path)

const _IDENTITY_KEYS = (
    "model_fingerprint", "initial_state_fingerprint", "algorithm",
    "algorithm_semantic_version", "scheduler", "scheduler_version", "rng",
    "rng_contract_version", "semantic_seed_or_range", "topology", "boundaries",
    "dimension", "acceptance_law", "temperature", "components", "backend",
    "fixture", "sampling_plan_version", "analysis_program",
    "analysis_program_version", "source_revision",
)

function _required_table!(errors, archive, key)
    if !haskey(archive, key)
        push!(errors, "missing required table '$key'")
        return nothing
    elseif !(archive[key] isa AbstractDict)
        push!(errors, "'$key' must be a table")
        return nothing
    end
    return archive[key]
end

"""Validate structure, probability rows, fingerprints, and semantic identity freshness."""
function validate_evidence_archive(archive::AbstractDict;
        expected_identity::Union{Nothing, EvidenceIdentity} = nothing,
        expected_schema_version::VersionNumber = EVIDENCE_SCHEMA_VERSION)
    errors = String[]
    warnings = String[]
    schema = _required_table!(errors, archive, "schema")
    identity = _required_table!(errors, archive, "identity")
    fixture = _required_table!(errors, archive, "fixture")
    kernel = _required_table!(errors, archive, "kernel")
    precision = _required_table!(errors, archive, "precision")
    _required_table!(errors, archive, "validation")
    _required_table!(errors, archive, "analysis")
    states = get(archive, "states", nothing)
    states isa AbstractVector || push!(errors, "'states' must be an array of tables")

    if schema !== nothing
        get(schema, "name", nothing) == "potts-transition-evidence" ||
            push!(errors, "unrecognized evidence schema name")
        version = try
            VersionNumber(get(schema, "version", ""))
        catch
            nothing
        end
        version === nothing && push!(errors, "invalid evidence schema version")
        version === nothing || version == expected_schema_version || push!(errors,
            "stale evidence schema version $(version); expected $(expected_schema_version)")
    end

    if identity !== nothing
        for key in _IDENTITY_KEYS
            haskey(identity, key) || push!(errors, "missing identity field '$key'")
        end
        for key in ("algorithm_semantic_version", "scheduler_version",
                    "rng_contract_version", "analysis_program_version")
            haskey(identity, key) || continue
            try
                VersionNumber(identity[key])
            catch
                push!(errors, "identity field '$key' is not a semantic version")
            end
        end
        if expected_identity !== nothing
            expected = _identity_dict(expected_identity)
            for key in _IDENTITY_KEYS
                haskey(identity, key) || continue
                identity[key] == expected[key] || push!(errors,
                    "semantic identity mismatch for '$key': archived $(repr(identity[key])), expected $(repr(expected[key]))")
            end
        end
    end

    state_count = kernel === nothing ? 0 : get(kernel, "state_count", 0)
    if states isa AbstractVector
        state_count == length(states) || push!(errors,
            "kernel state_count does not match state records")
        for (index, state) in pairs(states)
            state isa AbstractDict || (push!(errors, "state $index is not a table"); continue)
            get(state, "id", nothing) == index || push!(errors,
                "state IDs must be contiguous and ordered")
            encoding = get(state, "encoding", nothing)
            fingerprint = get(state, "fingerprint", nothing)
            encoding isa AbstractString || push!(errors, "state $index lacks an encoding")
            encoding isa AbstractString && fingerprint != content_fingerprint(encoding) &&
                push!(errors, "state $index fingerprint does not match its encoding")
        end
    end

    if fixture !== nothing && identity !== nothing && haskey(fixture, "dimensions") &&
            haskey(identity, "dimension")
        length(fixture["dimensions"]) == identity["dimension"] || push!(errors,
            "fixture dimensionality differs from identity dimensionality")
    end

    if kernel !== nothing && state_count isa Integer && state_count > 0
        entries = get(kernel, "entries", nothing)
        if !(entries isa AbstractVector)
            push!(errors, "kernel entries must be an array of tables")
        else
            exact = precision !== nothing &&
                    get(precision, "kind", nothing) == "exact_rational"
            row_sums = exact ? fill(BigInt(0) // BigInt(1), state_count) :
                               zeros(BigFloat, state_count)
            coordinates = Set{Tuple{Int, Int}}()
            for (entry_index, entry) in pairs(entries)
                entry isa AbstractDict ||
                    (push!(errors, "kernel entry $entry_index is not a table"); continue)
                source = get(entry, "source", 0)
                destination = get(entry, "destination", 0)
                source isa Integer && source in 1:state_count ||
                    push!(errors, "kernel entry $entry_index has invalid source")
                destination isa Integer && destination in 1:state_count ||
                    push!(errors, "kernel entry $entry_index has invalid destination")
                source isa Integer && destination isa Integer &&
                    (source, destination) in coordinates && push!(errors,
                        "kernel contains duplicate coordinate ($source, $destination)")
                source isa Integer && destination isa Integer &&
                    push!(coordinates, (source, destination))
                probability = try
                    _parse_number(get(entry, "probability", "invalid"))
                catch
                    push!(errors, "kernel entry $entry_index has invalid probability")
                    nothing
                end
                probability === nothing && continue
                probability >= 0 || push!(errors,
                    "kernel entry $entry_index has negative probability")
                source isa Integer && source in 1:state_count &&
                    (row_sums[source] += probability)
            end
            tolerance = if exact
                BigInt(0) // BigInt(1)
            elseif precision === nothing
                big"0"
            else
                try
                    _parse_number(get(precision, "tolerance", "0"))
                catch
                    big"0"
                end
            end
            for row in 1:state_count
                abs(row_sums[row] - 1) <= tolerance || push!(errors,
                    "kernel row $row is not normalized")
            end
        end
    elseif kernel !== nothing
        push!(errors, "kernel state_count must be a positive integer")
    end

    return EvidenceValidationReport(isempty(errors), errors, warnings)
end

function validate_evidence_archive(path::AbstractString; kwargs...)
    return validate_evidence_archive(read_evidence_archive(path); kwargs...)
end

"""Validate the preregistered empirical fixture grid and its 24-row cap."""
function validate_fixture_manifest(manifest::AbstractDict)
    errors = String[]
    get(manifest, "schema_version", nothing) == "1.0.0" ||
        push!(errors, "fixture manifest schema_version must be 1.0.0")
    fixtures = get(manifest, "fixtures", nothing)
    fixtures isa AbstractVector || return EvidenceValidationReport(false,
        ["fixture manifest requires a fixtures array"], String[])
    ids = String[]
    empirical_count = 0
    empirical = AbstractDict[]
    for (index, fixture) in pairs(fixtures)
        fixture isa AbstractDict ||
            (push!(errors, "fixture $index is not a table"); continue)
        id = string(get(fixture, "id", ""))
        isempty(id) && push!(errors, "fixture $index has no id")
        push!(ids, id)
        dimensions = get(fixture, "dimensions", Int[])
        dimension = get(fixture, "dimension", 0)
        length(dimensions) == dimension || push!(errors,
            "fixture '$id' dimensions do not match dimension")
        states = get(fixture, "empirical_source_states", Any[])
        states isa AbstractVector ||
            (push!(errors, "fixture '$id' empirical_source_states must be an array"); continue)
        empirical_count += length(states)
        !isempty(states) && push!(empirical, fixture)
    end
    length(unique(ids)) == length(ids) || push!(errors, "fixture IDs must be unique")
    maximum_rows = get(manifest, "maximum_empirical_source_states", 24)
    empirical_count <= maximum_rows || push!(errors,
        "fixture manifest registers $empirical_count empirical source states; maximum is $maximum_rows")
    empirical_count <= 24 || push!(errors,
        "fixture manifest exceeds the transition-kernel cap of 24 empirical source states")
    for required in (2, 3)
        any(fixture -> get(fixture, "dimension", 0) == required, empirical) ||
            push!(errors, "empirical fixture grid does not cover dimension $required")
    end
    for (field, required_values) in (
            ("topology", ("von_neumann", "moore")),
            ("boundary_class", ("periodic", "no_flux")),
            ("temperature_class", ("zero", "finite_low", "finite_high")),
            ("energy_scale_class", ("zero", "nominal", "strong")),
            ("occupancy_class", ("sparse", "mixed", "dense")))
        present = Set(string(get(fixture, field, "")) for fixture in empirical)
        for required in required_values
            required in present || push!(errors,
                "empirical fixture grid does not cover $field=$required")
        end
    end
    return EvidenceValidationReport(isempty(errors), errors, String[])
end

validate_fixture_manifest(path::AbstractString) =
    validate_fixture_manifest(TOML.parsefile(path))

end
