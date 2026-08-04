module PottsToolkitMetalExt

using PottsToolkit
using Metal

import CorePotts

function PottsToolkit._validate_backend_available(::PottsToolkit.MetalBackend)
    Metal.functional() || throw(ArgumentError(
        "MetalBackend() was requested, but Metal is not functional"
    ))
    return nothing
end

function PottsToolkit._adapt_runtime_backend(
        ::CorePotts.AdaptedProgramBackend{:MetalBackend}, runtime
    )
    return CorePotts.adapt_program_runtime(Metal.MtlArray, runtime)
end

end
