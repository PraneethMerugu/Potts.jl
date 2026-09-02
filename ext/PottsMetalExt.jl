module PottsMetalExt

using Potts
using Metal

import CorePotts
import CorePotts.BackendSPI: adapted_device_capability_disposition
import CorePotts.BackendSPI: adapted_device_environment

function _metal_core_environment_identity()
    package = Potts._native_package_identity(Metal)
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

adapted_device_environment(
    ::Val{:MetalBackend}, ::CorePotts.BackendSPI.ProgramCapabilityKey
) = _metal_core_environment_identity()

adapted_device_environment(
    ::Val{:MtlArray}, ::CorePotts.BackendSPI.ProgramCapabilityKey
) = _metal_core_environment_identity()

function Potts._validate_backend_available(::Potts.MetalBackend)
    Metal.functional() || throw(ArgumentError(
        "MetalBackend() was requested, but Metal is not functional"
    ))
    return nothing
end

function Potts._adapt_runtime_backend(
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
        key.mechanisms.support_family in (
            :core_execution_protocol_v1,
            :external_execution_protocol_v1,
        ) &&
        key.mechanisms.rng_contract_version ==
            rng_identity.contract_version &&
        key.mechanisms.rng_lowering_identity ===
            rng_identity.lowering_identity &&
        key.replay === CorePotts.BackendSPI.ExactConfigurationReplay
    admitted || return (
        CorePotts.BackendSPI.Unsupported,
        "the Metal extension does not support this CorePotts execution contract",
        false,
    )
    return (
        CorePotts.BackendSPI.Supported,
        "the Metal extension supports this typed CorePotts checkerboard contract",
        key.mechanisms.exact_replay,
    )
end


adapted_device_capability_disposition(
    ::Val{:MetalBackend}, key::CorePotts.BackendSPI.ProgramCapabilityKey
) = _metal_capability_disposition(key)

adapted_device_capability_disposition(
    ::Val{:MtlArray}, key::CorePotts.BackendSPI.ProgramCapabilityKey
) = _metal_capability_disposition(key)

end
