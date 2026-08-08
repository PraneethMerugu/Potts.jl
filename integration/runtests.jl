using Test
using PottsToolkit
using Symbolics
import DynamicQuantities
using DynamicQuantities: @u_str
import ModelingToolkit
import ModelingToolkitBase
import ModelingToolkitStandardLibrary
import Unitful
using ModelingToolkitBase:
    @independent_variables, @named, @parameters, @variables

include("test_modelingtoolkit_retention_and_structural_scheduling.jl")
include("test_modelingtoolkit_standard_library.jl")
include("test_native_runtime.jl")
include("test_native_batched_cpu.jl")
include("test_method_of_lines_field.jl")
include("test_ensemble_distributed.jl")
include("test_unitful_extension.jl")
include("test_optional_extension_loading.jl")
