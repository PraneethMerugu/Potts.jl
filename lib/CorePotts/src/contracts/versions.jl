"""
    ScientificContractVersions

Inspectable identities for the frozen scientific contracts. The versions are independent of
package versions. The legacy `:phase13_frozen` status is retained as a serialized protocol value.
"""
struct ScientificContractVersions
    freeze_status::Symbol
    rng::VersionNumber
    authoring_dsl::VersionNumber
    normalized_ir::VersionNumber
    checkpoint_schema::VersionNumber
    semantic_fingerprint::VersionNumber
    execution_fingerprint::VersionNumber
    result_evidence_schema::VersionNumber
    sequential_algorithm::VersionNumber
    checkerboard_scheduler::VersionNumber
    lottery_algorithm::VersionNumber
    tiled_checkerboard_experimental::VersionNumber
end

const RNG_CONTRACT_VERSION = v"1.0.0"
const AUTHORING_DSL_CONTRACT_VERSION = v"1.0.0"
const NORMALIZED_IR_CONTRACT_VERSION = v"1.0.0"
const CHECKPOINT_SCHEMA_VERSION = v"1.0.0"
const SEMANTIC_FINGERPRINT_VERSION = v"1.0.0"
const EXECUTION_FINGERPRINT_VERSION = v"1.0.0"
const RESULT_EVIDENCE_SCHEMA_VERSION = v"1.0.0"
const SEQUENTIAL_ALGORITHM_CONTRACT_VERSION = v"1.0.0"
const CHECKERBOARD_SCHEDULER_CONTRACT_VERSION = v"1.0.0"
const LOTTERY_ALGORITHM_CONTRACT_VERSION = v"1.0.0"
const TILED_CHECKERBOARD_EXPERIMENTAL_CONTRACT_VERSION = v"1.0.0"

# Coupled-dynamics additions are intentionally versioned outside
# `ScientificContractVersions`; the original value is a frozen public artifact and must remain
# byte-for-byte constructible.
const COUPLED_CONTRACT_SET_VERSION = v"2.0.0"
const COUPLED_EXECUTION_CONTRACT_VERSION = v"1.0.0"
const DYNAMIC_STATE_CONTRACT_VERSION = v"1.0.0"
const CONTINUOUS_SYSTEM_CONTRACT_VERSION = v"1.0.0"
const COUPLED_CHECKPOINT_SCHEMA_VERSION = v"1.0.0"
const BUDGETED_SEQUENTIAL_ALGORITHM_CONTRACT_VERSION = v"1.0.0"

"""Inspectable versions for the seven additive coupled semantic-kernel contracts."""
struct CoupledContractVersions
    status::Symbol
    contract_set::VersionNumber
    state::VersionNumber
    process::VersionNumber
    plan::VersionNumber
    lifecycle::VersionNumber
    observation::VersionNumber
    spatial_roles::VersionNumber
    potts_algorithm_identities::VersionNumber
end

const COUPLED_CONTRACT_VERSIONS = CoupledContractVersions(
    :wortel_cpu_reference_proven,
    COUPLED_CONTRACT_SET_VERSION,
    v"0.2.0",
    v"0.2.0",
    v"0.2.0",
    v"0.2.0",
    v"0.2.0",
    v"0.2.0",
    v"0.2.0",
)

"""Return the additive coupled-dynamics contract-version report."""
coupled_contract_versions() = COUPLED_CONTRACT_VERSIONS

const SCIENTIFIC_CONTRACT_VERSIONS = ScientificContractVersions(
    :phase13_frozen,
    RNG_CONTRACT_VERSION,
    AUTHORING_DSL_CONTRACT_VERSION,
    NORMALIZED_IR_CONTRACT_VERSION,
    CHECKPOINT_SCHEMA_VERSION,
    SEMANTIC_FINGERPRINT_VERSION,
    EXECUTION_FINGERPRINT_VERSION,
    RESULT_EVIDENCE_SCHEMA_VERSION,
    SEQUENTIAL_ALGORITHM_CONTRACT_VERSION,
    CHECKERBOARD_SCHEDULER_CONTRACT_VERSION,
    LOTTERY_ALGORITHM_CONTRACT_VERSION,
    TILED_CHECKERBOARD_EXPERIMENTAL_CONTRACT_VERSION,
)

"""Return the immutable frozen scientific-contract version report."""
scientific_contract_versions() = SCIENTIFIC_CONTRACT_VERSIONS

function Base.show(io::IO, versions::ScientificContractVersions)
    print(io, "ScientificContractVersions(", versions.freeze_status,
        ", rng=", versions.rng, ", dsl=", versions.authoring_dsl,
        ", ir=", versions.normalized_ir, ", evidence=",
        versions.result_evidence_schema, ')')
end
