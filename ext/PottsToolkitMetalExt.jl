module PottsToolkitMetalExt

using PottsToolkit
using Metal
using SHA

import CorePotts
import CorePotts.BackendSPI: adapted_device_capability_disposition

const _G5H4_TESTED_METAL_CORE_ENVIRONMENT_1_12_1 = (
    Metal = (
        package = "Metal",
        uuid = "dde4c033-4e86-420c-a63e-0dd931031962",
        version = v"1.10.0",
    ),
    Julia = (
        version = v"1.12.1",
        kernel = :Darwin,
        architecture = :aarch64,
        word_size = 64,
        machine = "arm64-apple-darwin24.0.0",
    ),
)

const _G5H4_TESTED_METAL_CORE_ENVIRONMENT = merge(
    _G5H4_TESTED_METAL_CORE_ENVIRONMENT_1_12_1,
    (Julia = (
        version = v"1.12.6",
        kernel = :Darwin,
        architecture = :aarch64,
        word_size = 64,
        machine = "arm64-apple-darwin24.0.0",
    ),),
)

const _G5H4_TESTED_METAL_CORE_ENVIRONMENTS = (
    _G5H4_TESTED_METAL_CORE_ENVIRONMENT_1_12_1,
    _G5H4_TESTED_METAL_CORE_ENVIRONMENT,
)

const _G5H4_TESTED_CORE_ENVIRONMENT_DIGESTS = (
    "c869ed68289ea1a641d8ed8c05e684693b08b2bb0b90fc2cc211e0b9da48a969",
    "281cfbf41f362e63ec7005a8b5b9f536b67cd51d1d79a6847d60e63069f1f38b",
)

_core_environment_digest(key) =
    bytes2hex(SHA.sha256(codeunits(repr(key.environment))))

function _metal_core_environment_identity()
    package = PottsToolkit._native_package_identity(Metal)
    return (
        Metal = (
            package = package.name,
            uuid = package.uuid,
            version = package.version,
        ),
        Julia = (
            version = VERSION,
            kernel = Sys.KERNEL,
            architecture = Sys.ARCH,
            word_size = Sys.WORD_SIZE,
            machine = Sys.MACHINE,
        ),
    )
end

function PottsToolkit._validate_backend_available(::PottsToolkit.MetalBackend)
    Metal.functional() || throw(ArgumentError(
        "MetalBackend() was requested, but Metal is not functional"
    ))
    return nothing
end

function PottsToolkit._adapt_runtime_backend(
        ::CorePotts.BackendSPI.AdaptedProgramBackend{:MetalBackend}, runtime
    )
    return CorePotts.BackendSPI.adapt_program_runtime(Metal.MtlArray, runtime)
end

function _metal_capability_disposition(
        key::CorePotts.BackendSPI.ProgramCapabilityKey
    )
    rng_identity = CorePotts.BackendSPI.rng_contract_identity()
    admitted =
        key.engine === CorePotts.BackendSPI.CheckerboardEngine &&
        key.backend === CorePotts.BackendSPI.AdaptedBackend &&
        key.device in (:MetalBackend, :MtlArray) &&
        key.dimension == 2 &&
        all(boundary -> boundary in (
            CorePotts.BackendSPI.ClosedBoundary,
            CorePotts.BackendSPI.PeriodicBoundary,
        ), key.topology) &&
        key.scalar_type === Float32 &&
        key.math_policy == CorePotts.BackendSPI.CapabilityMathPolicy(
            :accurate, :deterministic, :checked
        ) &&
        key.lifecycle.family in (:none, :core_lifecycle_v1) &&
        key.component_state.scope in (:none, :core_auxiliary_state) &&
        key.mechanisms.qualification_family in (
            :core_execution_protocol_v1,
            :evidenced_execution_protocol_v1,
        ) &&
        key.mechanisms.rng_contract_version ==
            rng_identity.contract_version &&
        key.mechanisms.rng_lowering_identity ===
            rng_identity.lowering_identity &&
        key.replay === CorePotts.BackendSPI.ExactConfigurationReplay &&
        _core_environment_digest(key) in
            _G5H4_TESTED_CORE_ENVIRONMENT_DIGESTS &&
        _metal_core_environment_identity() in
            _G5H4_TESTED_METAL_CORE_ENVIRONMENTS
    admitted || return (
        CorePotts.BackendSPI.Unsupported,
        CorePotts.BackendSPI.Compiles,
        "the Metal extension is loaded, but this exact CorePotts profile lies outside its reviewed real-device conjunction",
        nothing,
    )
    evidence = CorePotts.BackendSPI.CapabilityEvidenceIdentity(
        :PottsToolkit,
        :lw0_core_checkerboard_random_color_metal_exact_replay,
        v"1.0.0",
        PottsToolkit._sha256_hex(
            "lw0-core-checkerboard-random-color-metal-evidence-v1",
            CorePotts.BackendSPI.capability_key_fingerprint(key),
            _metal_core_environment_identity(),
        ),
    )
    return (
        CorePotts.BackendSPI.Supported,
        CorePotts.BackendSPI.ReplayQualified,
        "the PottsToolkit Metal extension supplies bounded real-device checkerboard execution and exact logical-continuation evidence for this profile",
        evidence,
    )
end


adapted_device_capability_disposition(
    ::Val{:MetalBackend}, key::CorePotts.BackendSPI.ProgramCapabilityKey
) = _metal_capability_disposition(key)

adapted_device_capability_disposition(
    ::Val{:MtlArray}, key::CorePotts.BackendSPI.ProgramCapabilityKey
) = _metal_capability_disposition(key)

end
