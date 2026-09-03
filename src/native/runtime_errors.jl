"""Supertype of source-aware native-component runtime failures."""
abstract type AbstractNativeRuntimeError <: Exception end

"""Invalid or incomplete late native solve profile."""
struct NativeProfileError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    message::String
end

"""Native component failed a required structural or numerical capability check."""
struct NativeCapabilityError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    capability::Symbol
    message::String
end

"""Native execution failed during the reported coupled phase."""
struct NativeExecutionError <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    phase::Symbol
    cause::Any
end

"""Native solver failed to reach a required coupled time boundary."""
struct NativeSolveFailure <: AbstractNativeRuntimeError
    path::Tuple{Vararg{Symbol}}
    retcode::SciMLBase.ReturnCode.T
    reached_time::Any
    required_time::Any
end

_native_path_string(path) = join(path, '₊')

_native_components_have_ports(components) = any(
    component -> !isempty(native_coupling_endpoints(component)), components
)

Base.showerror(io::IO, error::NativeProfileError) = print(
    io, "native profile `", _native_path_string(error.path), "`: ", error.message
)
Base.showerror(io::IO, error::NativeCapabilityError) = print(
    io,
    "native component `", _native_path_string(error.path),
    "` lacks ", error.capability, ": ", error.message,
)
function Base.showerror(io::IO, error::NativeExecutionError)
    print(
        io,
        "native component `", _native_path_string(error.path),
        "` failed during ", error.phase, ": ",
    )
    showerror(io, error.cause)
end
Base.showerror(io::IO, error::NativeSolveFailure) = print(
    io,
    "native component `", _native_path_string(error.path),
    "` returned ", error.retcode, " at ", error.reached_time,
    "; required coupled boundary ", error.required_time,
)
