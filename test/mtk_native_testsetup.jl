# Shared test setups for MTK-native symbols, SciMLStructures and F2 metadata/computed parameters.

@testsetup module MTKNativeTests
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts: LatticePDE
using Potts.ModelingToolkitBase: ModelingToolkitBase as MTKB
using Potts.SymbolicUtils: iscall, operation, arguments
using Potts.Symbolics: Symbolics, unwrap

function mn_error(f)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        return e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
    end
    return nothing
end

has(msg, parts...) = msg !== nothing && all(p -> occursin(p, msg), parts)

named(xs, n) = only(filter(x -> Potts.info(x).name === n, collect(xs)))

_strip_ast(ex::Expr) = Base.remove_linenums!(deepcopy(ex))
_strip_ast(xs::Tuple) = map(_strip_ast, xs)
_strip_ast(xs::AbstractVector) = map(_strip_ast, xs)
_strip_ast(nt::NamedTuple) = NamedTuple{keys(nt)}(map(_strip_ast, values(nt)))
_strip_ast(x) = x


@potts_model MNModel begin
    @kinds medium tip stalk endothelial = (tip, stalk)
    @parameters begin
        λ = 2.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        Dk[kind] = [0.0, 0.5, 0.25]
    end
    @variables q(cell) = 0.0
    @lattice Lattice((12, 12))
    @energy begin
        cells => λ * (volume - 9)^2
        contacts => J[kind, neighbor_kind]
    end
    @equations D(q) ~ Dk[kind] - 0.1 * q
    @sweep Metropolis(; temperature = 2.0)
end


@potts_model MNScalarTable begin
    @kinds medium cell
    @parameters J[kind, kind] = 3.0
    @lattice Lattice((8, 8))
    @energy contacts => J[kind, neighbor_kind]
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model MNEnergyIn begin
    @kinds medium tip stalk endothelial = (tip, stalk)
    @lattice Lattice((12, 12))
    @energy sites => 1.0 * (kind ∈ endothelial)
    @sweep Metropolis(; temperature = 2.0)
end


@potts_model MNIsMemberCase begin
    @structural_parameters mode = :ismember
    @kinds medium tip stalk fluid endothelial = (tip, stalk)
    @variables q(cell) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9)^2
    if mode === :ismember
        @equations D(q) ~ 0.25 * ismember(kind, endothelial)
    elseif mode === :ismember_tuple
        @equations D(q) ~ 0.25 * ismember(kind, (tip, stalk))
    elseif mode === :spelled
        @equations D(q) ~ 0.25 * ((kind == tip) | (kind == stalk))
    else
        @equations D(q) ~ 0.25 * ismember(kind, (tip, fluid))
    end
    @sweep Metropolis(; temperature = 2.0)
end


# the field rates (F4-B4t): the kind set is the binding of the input `e`
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module MnPDE
    using ..FieldPDE
    @variables c(..) e(..)::Bool [input = true]
    const C, E = c(t, x, y), e(t, x, y)
    reaction(k) = pdesys([Dt(C) ~ 0.1 * laplacian(C) - k * C * E], [c(0, x, y) ~ 0.0], (12, 12), [C, E])
    diffusion() = pdesys([Dt(C) ~ 0.1 * E * laplacian(C)], [c(0, x, y) ~ 0.0], (12, 12), [C, E])
end


@potts_model MNFieldIsMemberCase begin
    @structural_parameters mode = :rx_im
    @kinds medium tip stalk endothelial = (tip, stalk)
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9)^2
    if mode === :rx_im
        @fields MnPDE.reaction(0.3) (MnPDE.e => ismember(kind, endothelial))
    elseif mode === :rx_sp
        @fields MnPDE.reaction(0.3) (MnPDE.e => (kind == tip) | (kind == stalk))
    elseif mode === :diff_im
        @fields MnPDE.diffusion() (MnPDE.e => ismember(kind, endothelial))
    elseif mode === :diff_sp
        @fields MnPDE.diffusion() (MnPDE.e => (kind == tip) | (kind == stalk))
    else
        @fields MnPDE.reaction(0.6) (MnPDE.e => ismember(kind, endothelial))
    end
    @sweep Metropolis(; temperature = 2.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end


@testsetup module PottsParametersStructures
using Potts, Test, PottsModels
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using SciMLStructures: SciMLStructures as SS
using ForwardDiff: ForwardDiff


@potts_model C9Computed begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = 2λ
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


@potts_model C9Computed3 begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = 3λ
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


module C9ModA
    using Potts.Symbolics: Symbolics, @register_symbolic
    f(x) = 2x
    @register_symbolic f(x)
end

module C9ModB
    using Potts.Symbolics: Symbolics, @register_symbolic
    f(x) = 3x
    @register_symbolic f(x)
end

@potts_model C9FA begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = C9ModA.f(λ)
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end

@potts_model C9FB begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = C9ModB.f(λ)
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


@potts_model C9Sweep begin
    @structural_parameters begin
        s = 2
    end
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = s * λ
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end


@testsetup module F2MetadataSetup
using Potts, Test, PottsModels
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using SciMLStructures: SciMLStructures as SS
using Potts.ModelingToolkitBase: ModelingToolkitBase as MTKB
using Potts.SymbolicIndexingInterface: getp, setp


@potts_model F2Meta begin
    @kinds medium cell
    @parameters begin
        T = 1.0, [tunable = false]
        λ = 2.0, [bounds = (0, 5), description = "volume strength"]
        V₀ = 9.0
    end
    @energy cells => λ * (volume - V₀)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


@potts_model F2NoMeta begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        V₀ = 9.0
    end
    @energy cells => λ * (volume - V₀)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


@potts_model F2BoundChain begin
    @kinds medium cell
    @parameters begin
        α = 0.3
        β = 2α
        γ = β + 0.05, [bounds = (0, 1)]
    end
    @energy cells => γ * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = 1.0)
end


const _MN_DEFAULT_COMP = MTKB.System(Potts.Equation[], Potts.t; name = :comp)

@potts_model F2CompRoute begin
    @structural_parameters comp_sys = _MN_DEFAULT_COMP
    @kinds medium A
    @components cells(A) comp = comp_sys
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model BindParity begin
    @structural_parameters begin
        comp_sys = _MN_DEFAULT_COMP
        with_obs = false
    end
    @kinds medium A
    @components cells(A) comp = comp_sys
    if with_obs
        @observed ok2(cell) ~ comp.k2
    end
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end


function compmodel(sys)
    σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
    return PottsProblem(F2CompRoute(; name = :cr, comp_sys = sys), [ownership => σ, kind => [:A]], (0, 2))
end

emsg(f) = try
    f(); ""
catch e
    e isa ArgumentError || return "not an ArgumentError: " * sprint(showerror, e)
    sprint(showerror, e)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
