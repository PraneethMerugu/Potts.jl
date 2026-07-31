using Test
using PottsToolkit
using Symbolics
import DynamicQuantities
using DynamicQuantities: @u_str
import ModelingToolkit
import ModelingToolkitBase
import ModelingToolkitStandardLibrary
import ProcessBigraphs
import Unitful
using ModelingToolkitBase:
    @independent_variables, @named, @parameters, @variables

include("test_modelingtoolkit_assimilation.jl")
include("test_modelingtoolkit_standard_library.jl")
include("test_process_bigraph_bridge.jl")
include("test_unitful_extension.jl")
include("test_optional_extension_loading.jl")
