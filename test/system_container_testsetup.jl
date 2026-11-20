# Shared setup for the system container, delegation, refusal matrix and composition tests.

@testsetup module SystemContainerSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Aqua, PottsModels

using InteractiveUtils: methodswith

using Potts.LatticePDE: masked

using Potts.ModelingToolkitBase: ModelingToolkitBase, System, PDESystem, @variables,
    @parameters, compose, complete,
    mtkcompile, equations, unknowns, parameters, observed,
    initial_conditions, bindings, iscomplete

using Potts.Symbolics: unwrap

const WL_MTKB = ModelingToolkitBase

const WL_SII = Potts.SymbolicIndexingInterface

const WL_SB = Potts.SciMLBase

isdefined(@__MODULE__, :RefusalMatrix) ||
    include(joinpath(@__DIR__, "shared", "refusal_matrix.jl"))

# --- the models: composed `decay`, input `volume`, a PDESystem; and an empty one
module ContainerModels
    using Potts
    using Potts.ModelingToolkitBase: System, PDESystem, @variables, @parameters, compose,
        complete
    const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
    const t = Potts.t
    const D = Potts.ModelingToolkitBase.D_nounits
    @variables xv(t) = 2.0 m(t) = 0.0 excess(t) volume(t) [input = true]
    @parameters a = 0.1 V0 = 1.0
    @variables yd(t) = 1.0
    @parameters kd = 0.1
    const decay = System([D(yd) ~ -kd * yd], t; name = :decay)
    const inner_top = System(
        [D(xv) ~ -a * xv + 0 * volume, D(m) ~ a * xv, excess ~ xv], t,
        [xv, m, excess, volume], [
            a, V0,
        ];
        name = :allparts
    )
    const inner_all = compose(inner_top, [decay])
    const inner_empty = System(Potts.Equation[], t, [volume], [V0]; name = :gg)
    @parameters x y Dc = 1.0e-3
    @variables c(..) kindₛ(..)::Int32 [input = true]
    const Dx, Dy = Potts.ModelingToolkitBase.Differential(x),
        Potts.ModelingToolkitBase.Differential(y)
    function pde(name)
        return PDESystem(
            [D(c(t, x, y)) ~ Dc * (Dx(Dx(c(t, x, y))) + Dy(Dy(c(t, x, y))))], [
                c(0.0, x, y) ~
                    0.0,
            ],
            [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
            [t, x, y], [
                c(t, x, y), kindₛ(t, x, y),
            ],
            [Dc]; name
        )
    end
    function part(; kw...)
        return Potts.PottsPart(;
            kinds = [:medium, :cell], lattice = Potts.lattice_spec((8, 8)),
            sweep = Potts.sweep_spec(:metropolis; temperature = 1.0), kw...
        )
    end
end

using .ContainerModels: xv, a, excess, volume, decay, inner_all, inner_empty

const W_all = Potts.wrap_system(
    :allparts, complete(inner_all), ContainerModels.pde(:allparts), ContainerModels.part()
)

const W_empty = Potts.wrap_system(
    :gg, complete(inner_empty), nothing,
    ContainerModels.part()
)

# W and inner agree: the same value, or the same exception type
function container_agree(f, W, I)
    rw = try
        (:ok, f(W))
    catch e
        (:err, typeof(e))
    end
    ri = try
        (:ok, f(I))
    catch e
        (:err, typeof(e))
    end
    return isequal(rw, ri)
end

# Per published model: REFUSED 80 (every problem route), LOUD 12, BUILT 7. MTK's `complete`,
# `rename`, `compose` (with an MTK System) and `extend` (of two Potts models) answer; MTK's
# `complete` keywords are refused by name.
const WL_BY_DESIGN = [
    "flatten(W)", "mtkcompile(W)", "structural_simplify(W)", "complete(W)",
    "rename(W, :q)", "compose(W, [System])", "extend(W, W)",
]

# The hand-wrapped probe models (their inner Systems hold what no payload builds, so they do
# not compile, compose with a component of their own name or extend): by model name
const WL_BY_DESIGN_RAW = Dict(
    :allparts => ["flatten(W)", "complete(W)", "rename(W, :q)"],
    :gg => [
        "flatten(W)", "complete(W)", "rename(W, :q)", "compose(W, [System])",
        "compose(W, W)",
    ]
)

const WL_LOUD_REQUIRED = [
    "compose(W, W)", "toggle_namespacing(W, false)", "mtkcompile(W; inputs)",
    "convert(System, W)",
    "toggle_namespacing(W, false)", "mtkcompile(W; inputs)", "convert(System, W)",
    "complete(W; flatten = false)",
]

const WL_PUBLISHED = (
    :GranerGlazier, :WortelAct, :MerksVasculogenesis, :OpenVTGrowingMonolayer,
    :AkeebInvasion,
    :OpenVTChain, :OpenVTReferenceMonolayer, :Merks2006, :Merks2008, :ShearedFoam,
)

# WL2: compose-then-wrap, `compose` via `get_parent`, nested, S-2 bindings
module ContainerCompose
    using Potts
    using Potts.ModelingToolkitBase: System, @variables, @parameters
    const t = Potts.t
    const D = Potts.ModelingToolkitBase.D_nounits
    @variables xc(t) = 0.4 cbar(t) [input = true] vol(t) [input = true] w(t) = 0.0 z(
        t
    ) = 1.0
    @parameters kc = 0.5 kw = 0.2 kz = 0.1
    cell() = System([D(xc) ~ -kc * xc + cbar - vol], t, [xc, cbar, vol], [kc]; name = :cell)
    model() = System([D(w) ~ -kw * w + vol], t, [w, vol], [kw]; name = :model)
    top() = System([D(z) ~ -kz * z], t, [z], [kz]; name = :top)
end

# A condition of a coupled PDESystem (prior legacy condition form, then checked bitwise
# against a `@boundary` site mask): stored, printed and lowered; the masked sites hold 5.0
module ContainerPDE
    using Potts.Fields
    @parameters Dc = 1.0
    @variables c(..) = 0.0 border(..)::Bool [input = true]
    function sys()
        return pdesystem(
            [Differential(t)(c(t, x, y)) ~ Dc * laplacian(c(t, x, y))],
            [c(t, x, y) ~ masked(border(t, x, y), 5.0)]; name = :wl
        )
    end
end

# The inner-vs-payload check also compares parameters, observed and
# initialization equations and initial conditions; a model built from its payload is marked
# so the check is an identity test (no second build)
@potts_model ContainerGuard begin
    @kinds medium cell
    @parameters T = 1.0 λ = 2.0
    @variables x(model) = 1.0
    @equations D(x) ~ -λ * x
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = T)
end

# C9: components rebuilt from `compose`.
module ComposeSys
    using Potts
    using Potts.ModelingToolkitBase: System, @variables, @parameters
    const t = Potts.t
    const D = Potts.ModelingToolkitBase.D_nounits
    @variables yd(t) = 2.0
    @parameters kd = 0.3
    decay(; name = :decay) = System([D(yd) ~ -kd * yd], t; name)
    @variables zz(t) = 1.0
    @parameters kz = 0.1
    inner2() = System([D(zz) ~ -kz * zz], t; name = :inner2)
end

@potts_model ComposeCell begin
    @kinds medium cell
    @variables y(cell) = 1.0
    @equations D(y) ~ -y
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end

# What a composed component cannot carry is refused by name, never dropped
module ComposeNeg
    using Potts
    using Potts.ModelingToolkitBase: System, @variables, @parameters, @poissonians
    const t = Potts.t
    const D = Potts.ModelingToolkitBase.D_nounits
    @variables cy(t) = 1.0
    @parameters ck = 0.5
    clock() = System([D(cy) ~ -ck * cy], t; name = :clock)
    # named like the host's `x`
    xsys() = System([D(cy) ~ -ck * cy], t; name = :x)
    # reads `volume` (an input)
    vsys() = System([D(cy) ~ -ck * cy * Potts.B.volume], t; name = :vv)
    @variables hy(t) = 1.0
    @parameters hk = 0.1
    function noisy(name; kw...)
        return System(
            [D(hy) ~ -hk * hy], t, [hy], [hk]; name, noise_eqs = [0.1 * hy], kw...
        )
    end
    function constrained(name; kw...)
        return System(
            [D(hy) ~ -hk * hy], t; name, constraints = [hy ~ 1.0], kw...
        )
    end
    costly(name; kw...) = System([D(hy) ~ -hk * hy], t; name, costs = [2.0], kw...)
    function poisson(name; kw...)
        P = only(@poissonians P(hk))
        return System([D(hy) ~ -hk * hy + P], t; name, kw...)
    end
end

isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module ContainerFieldPDE
    using ..FieldPDE
    @variables c(..)
    function diffusion()
        @parameters Dc = 0.1
        C = c(t, x, y)
        return pdesys([Dt(C) ~ Dc * laplacian(C)], [c(0, x, y) ~ 0.0], (8, 8), [C], [Dc])
    end
end

# a model with a field (its PDESystem built by mtkcompile)
@potts_model ComposeField begin
    @kinds medium cell
    @lattice Lattice((8, 8))
    @fields ContainerFieldPDE.diffusion()
    @sweep Metropolis(; temperature = 1.0)
end

# kinds other than the host's, a population fold
@potts_model ComposeFoldOther begin
    @kinds medium ka kb
    @variables n(model) = 0.0
    @equations D(n) ~ count(true for c in cells(kb)) - n
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model ComposeFoldSame begin              # the host's kinds, a population fold
    @kinds medium cell
    @variables n(model) = 0.0
    @equations D(n) ~ count(true for c in cells(cell)) - n
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model ComposePerCellComp begin           # a per-cell `@components`
    @kinds medium cell
    @components cells(cell) clock = ComposeNeg.clock()
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model ComposeModelComp begin             # a model `@components` named `decay`
    @kinds medium cell
    @parameters T = 1.0
    @components model decay = ComposeSys.decay()
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = T)
end

@potts_model ComposeTable begin                 # a kind table
    @kinds medium cell
    @parameters J[kind, kind] = [0 1; 1 0]
    @variables z(model) = 1.0
    @equations D(z) ~ -z
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end

# `Potts.component`
@potts_model DecayWithEnergy begin
    @kinds medium cell
    @parameters λ = 2.0
    @variables x(model) = 1.0
    @equations D(x) ~ -λ * x
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

# Condition stored on part / fields, or none
@potts_model ContainerBcs begin
    @structural_parameters with_bcs = true
    @kinds medium cell border
    @parameters T = 1.0
    @lattice Lattice((8, 8))
    if with_bcs
        @fields ContainerPDE.sys() (ContainerPDE.border => kind == border)
    end
    @sweep Metropolis(; temperature = T)
end

# Behavioral negative control for getfield(sys, ...): user declares parameter `part`,
# variable `inner`, and composes component `fields` on top of a PDESystem.
@potts_model ContainerShadow begin
    @kinds medium cell
    @parameters part = 3.0
    @variables inner(model) = 2.0
    @equations D(inner) ~ -part * inner
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @fields ContainerFieldPDE.diffusion()
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
