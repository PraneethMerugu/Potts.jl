module PottsMetalExt

using Potts
using Metal

import CorePotts
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

end
