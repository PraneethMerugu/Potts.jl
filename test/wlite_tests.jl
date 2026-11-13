# The W-lite LA container (v3 §7.1, C4): `PottsSystem <: AbstractSystem` wraps a complete inner
# `System`. A port of the P3-wlite probe suite (research/field-compiler/pass3/mtk/wlite/,
# 53 checks A–G) on the probe's two models, built with `Potts.wrap`, plus: the refusal matrix on
# every published model with its negative control (the refusal loop deleted, in a subprocess),
# the 15-method list, Aqua piracy, the `getfield` grep, `Potts.compose` (single and nested)
# against the raw MTK reference, (path, name) bindings, `wrap`'s checks and a PDESystem's conditions.

@testsetup module WliteSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts, Test, Aqua, PottsModels

using InteractiveUtils: methodswith

using Potts.LatticePDE: masked

using Potts.ModelingToolkitBase: ModelingToolkitBase, System, PDESystem, @variables, @parameters, compose, complete,
    mtkcompile, equations, unknowns, parameters, observed, initial_conditions, bindings, iscomplete

using Potts.Symbolics: unwrap

const WL_MTKB = ModelingToolkitBase

const WL_SII = Potts.SymbolicIndexingInterface

const WL_SB = Potts.SciMLBase

isdefined(@__MODULE__, :WLiteMatrix) || include(joinpath(@__DIR__, "shared", "wlite_matrix.jl"))


# --- the probe's models (wlitedef.jl): composed `decay`, input `volume`, a PDESystem; and an empty one
module WLiteModels
using Potts
using Potts.ModelingToolkitBase: System, PDESystem, @variables, @parameters, compose, complete
const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
const t = Potts.t
const D = Potts.ModelingToolkitBase.D_nounits
@variables xv(t) = 2.0 m(t) = 0.0 excess(t) volume(t) [input = true]
@parameters a = 0.1 V0 = 1.0
@variables yd(t) = 1.0
@parameters kd = 0.1
const decay = System([D(yd) ~ -kd * yd], t; name = :decay)
const inner_top = System([D(xv) ~ -a * xv + 0 * volume, D(m) ~ a * xv, excess ~ xv], t, [xv, m, excess, volume], [a, V0];
    name = :allparts)
const inner_all = compose(inner_top, [decay])
const inner_empty = System(Potts.Equation[], t, [volume], [V0]; name = :gg)
@parameters x y Dc = 1e-3
@variables c(..) kindₛ(..)::Int32 [input = true]
const Dx, Dy = Potts.ModelingToolkitBase.Differential(x), Potts.ModelingToolkitBase.Differential(y)
pde(name) = PDESystem([D(c(t, x, y)) ~ Dc * (Dx(Dx(c(t, x, y))) + Dy(Dy(c(t, x, y))))], [c(0.0, x, y) ~ 0.0],
    [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [c(t, x, y), kindₛ(t, x, y)],
    [Dc]; name)
part(; kw...) = Potts.PottsPart(; kinds = [:medium, :cell], lattice = Potts.lattice_spec((8, 8)),
    sweep = Potts.sweep_spec(:metropolis; temperature = 1.0), kw...)
end

using .WLiteModels: xv, a, excess, volume, decay, inner_all, inner_empty


const W_all = Potts.wrap(:allparts, complete(inner_all), WLiteModels.pde(:allparts), WLiteModels.part())

const W_empty = Potts.wrap(:gg, complete(inner_empty), nothing, WLiteModels.part())


# W and inner agree: the same value, or the same exception type
function wl_agree(f, W, I)
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


# Per published model: REFUSED 80 (every problem route), LOUD 16, BUILT 3. The design's
# LOUD 18 / BUILT 1 counts `mtkcompile(W)` loud; a PottsSystem keeps `mtkcompile` as the CPM
# compile entry (it returns a `CompiledPottsSystem`, not a problem), so it builds by design, and
# so does MTKBase's deprecated `structural_simplify(sys) = mtkcompile(sys)`. `flatten(W)` is W.
# On the probe models (a hand-built System wrapped with a payload that does not build it) the
# compile entries are loud instead: the compiler reads the payload, and lowers only subsystems
# into it (C9), so a model whose inner System holds top-level content its payload does not
# build is refused rather than compiled without it (C4 review B1).
const WL_BY_DESIGN = ["flatten(W)", "mtkcompile(W)", "structural_simplify(W)"]

const WL_BY_DESIGN_RAW = ["flatten(W)"]

const WL_LOUD_REQUIRED = ["compose(W, [System])", "compose(W, W)", "rename(W, :q)", "complete(W)", "extend(W, W)",
    "toggle_namespacing(W, false)", "mtkcompile(W; inputs)", "convert(System, W)"]

const WL_PUBLISHED = (:GranerGlazier, :WortelAct, :MerksVasculogenesis, :OpenVTGrowingMonolayer, :AkeebInvasion,
    :OpenVTChain, :OpenVTReferenceMonolayer, :Merks2006, :Merks2008, :ShearedFoam)


# WL2: compose-then-wrap, `Potts.compose` via `get_parent`, nested, S-2 bindings
module WLiteCompose
using Potts
using Potts.ModelingToolkitBase: System, @variables, @parameters
const t = Potts.t
const D = Potts.ModelingToolkitBase.D_nounits
@variables xc(t) = 0.4 cbar(t) [input = true] vol(t) [input = true] w(t) = 0.0 z(t) = 1.0
@parameters kc = 0.5 kw = 0.2 kz = 0.1
cell() = System([D(xc) ~ -kc * xc + cbar - vol], t, [xc, cbar, vol], [kc]; name = :cell)
model() = System([D(w) ~ -kw * w + vol], t, [w, vol], [kw]; name = :model)
top() = System([D(z) ~ -kz * z], t, [z], [kz]; name = :top)
end


# A condition of a coupled PDESystem (until F4-B6 front end A's `@bcs`, then checked bitwise
# against a `@boundary` site mask): stored, printed and lowered; the masked sites hold 5.0
module WLitePDE
using Potts.Fields
@parameters Dc = 1.0
@variables c(..) = 0.0 border(..)::Bool [input = true]
sys() = pdesystem([Differential(t)(c(t, x, y)) ~ Dc * Δ(c(t, x, y))], [c(t, x, y) ~ masked(border(t, x, y), 5.0)]; name = :wl)
end


# C4 review round 2: the inner-vs-payload check also compares parameters, observed and
# initialization equations and initial conditions; a model built from its payload is marked
# so the check is an identity test (no second build)
@potts_model WLiteGuard begin
    @kinds medium cell
    @parameters T = 1.0 λ = 2.0
    @variables x(model) = 1.0
    @equations D(x) ~ -λ * x
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = T)
end


# C9: components rebuilt from `Potts.compose`. A hand-built MTK System, wrapped and composed
# into a model built by `@potts_model`, compiles as a model-scope component and is advanced:
# oracle y(t) = y0·exp(−k t) (RK4, 4 substeps per MCS), and the model's own ODE alongside.
module WLiteC9
using Potts
using Potts.ModelingToolkitBase: System, @variables, @parameters
const t = Potts.t
const D = Potts.ModelingToolkitBase.D_nounits
@variables yd(t) = 2.0
@parameters kd = 0.3
decay() = System([D(yd) ~ -kd * yd], t; name = :decay)
@variables zz(t) = 1.0
@parameters kz = 0.1
inner2() = System([D(zz) ~ -kz * zz], t; name = :inner2)
end


@potts_model WLiteC9Cell begin
    @kinds medium cell
    @variables y(cell) = 1.0
    @equations D(y) ~ -y
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end


# C9 review: what a composed component cannot carry is refused by name, never dropped
module WLiteC9Neg
using Potts
using Potts.ModelingToolkitBase: System, @variables, @parameters
const t = Potts.t
const D = Potts.ModelingToolkitBase.D_nounits
@variables cy(t) = 1.0
@parameters ck = 0.5
clock() = System([D(cy) ~ -ck * cy], t; name = :clock)
xsys() = System([D(cy) ~ -ck * cy], t; name = :x)                       # named like the host's `x`
vsys() = System([D(cy) ~ -ck * cy * Potts.B.volume], t; name = :vv)      # reads `volume` (an input)
# MTK features Potts would drop: refused at the top level and in a component (review round 3)
using Potts.ModelingToolkitBase: @poissonians
@variables hy(t) = 1.0
@parameters hk = 0.1
noisy(name; kw...) = System([D(hy) ~ -hk * hy], t, [hy], [hk]; name, noise_eqs = [0.1 * hy], kw...)
constrained(name; kw...) = System([D(hy) ~ -hk * hy], t; name, constraints = [hy ~ 1.0], kw...)
costly(name; kw...) = System([D(hy) ~ -hk * hy], t; name, costs = [2.0], kw...)
poisson(name; kw...) = (P = only(@poissonians P(hk)); System([D(hy) ~ -hk * hy + P], t; name, kw...))
end


isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module WlPDE
using ..FieldPDE
@variables c(..)
diffusion() = (@parameters Dc = 0.1; C = c(t, x, y); pdesys([Dt(C) ~ Dc * Δ(C)], [c(0, x, y) ~ 0.0], (8, 8), [C], [Dc]))
end

@potts_model WLiteC9Field begin                 # a model with a field (its PDESystem built by mtkcompile)
    @kinds medium cell
    @lattice Lattice((8, 8))
    @fields WlPDE.diffusion()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model WLiteC9FoldOther begin             # kinds other than the host's, a population fold
    @kinds medium ka kb
    @variables n(model) = 0.0
    @equations D(n) ~ count(true for c in cells(kb)) - n
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model WLiteC9FoldSame begin              # the host's kinds, a population fold
    @kinds medium cell
    @variables n(model) = 0.0
    @equations D(n) ~ count(true for c in cells(cell)) - n
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model WLiteC9PerCellComp begin           # a per-cell `@components` (review B2)
    @kinds medium cell
    @components cells(cell) clock = WLiteC9Neg.clock()
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model WLiteC9ModelComp begin             # a model `@components` named `decay`
    @kinds medium cell
    @parameters T = 1.0
    @components model decay = WLiteC9.decay()
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = T)
end


@potts_model WLiteC9Table begin                 # a kind table (review S3)
    @kinds medium cell
    @parameters J[kind, kind] = [0 1; 1 0]
    @variables z(model) = 1.0
    @equations D(z) ~ -z
    @lattice Lattice((8, 8))
    @sweep Metropolis(; temperature = 1.0)
end


# F4-10 (FE-15a, V7a): `Potts.component(name, sys, model)` makes an MTK `System` a component
# of a model with an energy; the documented route before it, `Potts.wrap(name, sys, nothing,
# Potts.part(model))`, carried the model's energies into the component and was refused.
# Base (3ed05c3b, ~/lpwork/f4c/nc10-base.log): `Potts.component` is not defined (the testset
# errors on its first call); the old route is refused with "component `decay` has energies".
@potts_model WLiteF410 begin
    @kinds medium cell
    @parameters λ = 2.0
    @variables x(model) = 1.0
    @equations D(x) ~ -λ * x
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "W-lite A: read access" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite A: read access" begin
        W, I, R = W_all, Potts.inner(W_all), complete(inner_all)
        @test W isa WL_MTKB.AbstractSystem && iscomplete(I) && !iscomplete(W)    # R-1: ask the inner
        @test isequal(equations(W), equations(I))                                # A1
        @test isequal(unknowns(W), unknowns(I))                                  # A2
        @test isequal(parameters(W), parameters(I))                              # A3
        @test isequal(observed(W), observed(I))                                  # A4
        @test isequal(Dict(initial_conditions(W)), Dict(initial_conditions(I)))  # A5
        @test isequal(Dict(bindings(W)), Dict(bindings(I)))                      # A6
        @test issetequal(unknowns(W), unknowns(R))                               # A7
        @test issetequal(parameters(W), parameters(R))                           # A8
        @test string(initial_conditions(W)[unwrap(W.xv)]) == "2.0"               # A9
        @test nameof(W) === :allparts                                            # A10
    end
end

@testitem "W-lite B: show" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite B: show" begin
        s = sprint(show, MIME"text/plain"(), W_all)
        @test occursin("PottsSystem allparts", s) && occursin("fields: PDESystem", s) && occursin("decay₊yd", s)   # B1
        @test !occursin("fields:", sprint(show, MIME"text/plain"(), W_empty))
        @test !isempty(sprint(show, W_all)) && !isempty(string(W_all))                                          # B2
        @test !isempty(sprint(print, W_all))                                                                    # B3
    end
end

@testitem "W-lite C: sys.x" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite C: sys.x" begin
        W, I = W_all, Potts.inner(W_all)
        @test isequal(W.xv, xv) && isequal(W.a, a)                                       # C1, C2
        @test any(isequal(unwrap(W.decay.yd)), unknowns(W))                              # C3
        @test wl_agree(s -> getproperty(s, Symbol("decay₊yd")), W, I)                    # C4
        @test any(isequal(unwrap(W.decay.kd)), parameters(W))                            # C5
        @test_throws ArgumentError W.nope                                                # C6
        @test isequal(W.t, Potts.t)                                                      # C7
    end
end

@testitem "W-lite D: SymbolicIndexingInterface" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite D: SymbolicIndexingInterface" begin
        W, I = W_all, Potts.inner(W_all)
        uks, pps = unknowns(I), parameters(I)
        prob = WL_MTKB.ODEProblem(mtkcompile(I; inputs = [volume]), [volume => 1.0], (0.0, 1.0))
        @test WL_SII.is_time_dependent(W) === true                                                       # D1
        @test isequal(WL_SII.independent_variable_symbols(W), [unwrap(Potts.t)])                         # D2
        @test all(u -> wl_agree(s -> WL_SII.is_variable(s, u), W, I), uks) && all(u -> WL_SII.is_variable(W, u), uks)   # D3
        @test all(u -> wl_agree(s -> WL_SII.variable_index(s, u), W, I), uks)                            # D4
        @test all(p -> wl_agree(s -> WL_SII.is_parameter(s, p), W, I), pps) && all(p -> WL_SII.is_parameter(W, p), pps) # D5
        @test all(p -> wl_agree(s -> WL_SII.parameter_index(s, p), W, I), pps)                           # D6
        @test wl_agree(WL_SII.variable_symbols, W, I)                                                    # D7
        @test wl_agree(WL_SII.parameter_symbols, W, I)                                                   # D8
        @test wl_agree(s -> WL_SII.is_observed(s, unwrap(excess)), W, I)                                 # D9
        @test wl_agree(s -> Dict(WL_SII.default_values(s)), W, I)                                        # D10
        @test wl_agree(WL_SII.all_variable_symbols, W, I)                                                # D11
        @test WL_SII.is_variable(W, W.decay.yd)                                                          # D12
        @test WL_SII.is_independent_variable(W, Potts.t)                                                 # D13
        @test prob[W.xv] == 2.0 && prob.ps[W.a] == 0.1                                                   # D14
        @test prob[W.decay.yd] == 1.0                                                                    # D15
        @test wl_agree(s -> WL_SII.getu(s, W.xv)(prob), W, I)                                            # D16
        @test wl_agree(s -> WL_SII.getp(s, W.a)(prob), W, I)                                             # D17
        @test all(p -> wl_agree(s -> WL_SII.is_timeseries_parameter(s, p), W, I), pps)                   # D18
        @test wl_agree(s -> WL_SII.variable_index(s, :xv), W, I)                                         # D19
        @test wl_agree(s -> WL_SII.parameter_index(s, :a), W, I)                                         # D20
        @test wl_agree(s -> WL_SII.is_parameter(s, WL_SII.parameter_index(I, a)), W, I)                  # D21
        @test wl_agree(WL_SII.all_symbols, W, I)                                                         # D22
        @test all(p -> wl_agree(s -> WL_SII.timeseries_parameter_index(s, p), W, I), pps)                # D23
        @test wl_agree(s -> WL_SII.getu(s, W.xv + 2 * W.a)(prob), W, I)                                  # D24
        @test wl_agree(s -> WL_SII.getp(s, 2 * W.a)(prob), W, I)                                         # D25
        @test wl_agree(s -> WL_SII.getu(s, [W.xv, W.decay.yd])(prob), W, I)                              # D26
        # the five SII methods answer from the inner, not from MTKBase's `::AbstractSystem` methods:
        # the pin that fails when an MTKBase release adds an SII method the container must route (R-10)
        @test WL_SII.parameter_index(W, a) isa WL_MTKB.ParameterIndex                                    # not a plain Int
        @test WL_SII.getp(W, W.a)(prob) == 0.1
    end
end

@testitem "W-lite E: template compile on the inner" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite E: template compile on the inner" begin
        I = Potts.inner(W_all)
        function du_of(sys)
            p = WL_MTKB.ODEProblem(sys, [volume => 1.0], (0.0, 1.0))
            d = similar(p.u0)
            p.f(d, p.u0, p.p, 0.0)
            return Dict(zip(unknowns(sys), d))
        end
        @test mtkcompile(I; inputs = [volume]) isa System                                                 # E1
        @test isequal(du_of(mtkcompile(I; inputs = [volume])), du_of(mtkcompile(inner_all; inputs = [volume])))   # E2
        @test length(parameters(mtkcompile(I; inputs = [volume]); initial_parameters = true)) ==
              length(parameters(mtkcompile(inner_all; inputs = [volume]); initial_parameters = true))     # E3
    end
end

@testitem "W-lite F: refusal matrix (probe models)" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite F: refusal matrix (probe models)" begin
        for W in (W_all, W_empty)
            m = WLiteMatrix.matrix(W, decay)
            @test length(m) == 99
            @test isempty(filter(p -> occursin("Problem", first(p)) && last(p) === :BUILT, m))          # F1: no problem builds
            @test all(p -> last(p) === :REFUSED, filter(p -> occursin("Problem", first(p)) &&
                                                             !startswith(first(p), "Initialization"), m))
            @test sort(WLiteMatrix.built(m)) == sort(WL_BY_DESIGN_RAW)                                 # F2
            @test all(l -> Dict(m)[l] === :LOUD, WL_LOUD_REQUIRED)                                     # F3: no hang, loud
            @test WLiteMatrix.tally(m) == Dict(:REFUSED => 80, :LOUD => 18, :BUILT => 1)
            @test occursin("payload cannot build", sprint(showerror, try mtkcompile(W) catch e e end))
        end
    end
end

@testitem "W-lite F: names, strings and symbols after the system are refused (C4 review S1)" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite F: names, strings and symbols after the system are refused (C4 review S1)" begin
        for W in (W_all, W_empty, PottsModels.GranerGlazier(; name = :gg))
            sh = WLiteMatrix.shapes(W)
            @test length(sh) == 16 * 5 * 3 + 2
            bad = filter(p -> last(p) !== :REFUSED, sh)
            isempty(bad) || @info "W-lite shapes not refused" bad
            @test isempty(bad)
        end
    end
end

@testitem "W-lite F: refusal matrix on every published model" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite F: refusal matrix on every published model" begin
        for n in WL_PUBLISHED
            W = getfield(PottsModels, n)(; name = :m)
            m = WLiteMatrix.matrix(W, decay)
            @test WLiteMatrix.tally(m) == Dict(:REFUSED => 80, :LOUD => 16, :BUILT => 3)
            @test sort(WLiteMatrix.built(m)) == sort(WL_BY_DESIGN)
            @test mtkcompile(W) isa CompiledPottsSystem
        end
    end
end

@testitem "W-lite F: negative control (refusal loop deleted)" setup = [WliteSetup] tags = [:potts, :wlite, :subprocess] begin
    @testset "W-lite F: negative control (refusal loop deleted)" begin
        # without the 48 refusal methods exactly the 10 `{true}` routes per model build silently
        # (stderr dropped: without the refusals some plain routes overflow the stack inside SciMLBase, loud)
        out = read(pipeline(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $(joinpath(@__DIR__,
        "wlite_negctl.jl"))`, "JULIA_PKG_GC_AUTO" => "false"); stderr = devnull), String)
        lines = filter(startswith("NEGCTL "), split(out, '\n'))
        @test length(lines) == length(WL_PUBLISHED)
        expected = sort(vcat(["$n{true}" for n in (:ODEProblem, :NonlinearProblem, :SteadyStateProblem, :DiscreteProblem,
            :ImplicitDiscreteProblem, :NonlinearLeastSquaresProblem, :LinearProblem, :IntervalNonlinearProblem,
            :HomotopyProblem)], ["ODEProblem{true,FullSpecialize}"]))
        for l in lines
            _, model, nbuilt, routes... = split(l)
            @test sort(filter(r -> occursin("Problem", r), routes)) == sort(expected)
            @test parse(Int, nbuilt) == 10 + length(WL_BY_DESIGN)
        end
    end
end

@testitem "W-lite G: the 15 owned methods, piracy" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite G: the 15 owned methods, piracy" begin
        @test isempty(Aqua.Piracy.hunt(Potts))                                                          # G1
        T = PottsSystem
        owned = Method[]
        for m in methodswith(T; supertypes = false)
            f = m.sig isa UnionAll ? Base.unwrap_unionall(m.sig).parameters[1] : m.sig.parameters[1]
            home = f <: Type ? nothing : parentmodule(f.instance)
            (m.module === Potts && home !== Potts && home !== nothing) && push!(owned, m)
        end
        names = sort([string(parentmodule(Base.unwrap_unionall(m.sig).parameters[1].instance), '.', m.name, '(',
                             join(string.(Base.unwrap_unionall(m.sig).parameters[3:end]), ", "), ')') for m in owned])
        # the type's printed form carries its module when the name is not visible from the calling
        # module: Main printed `PottsSystem`, the item's module prints `Potts.PottsSystem`
        plain(s) = replace(s, "Potts." => "")
        @test plain.(names) == sort(["Base.getproperty(Symbol)", "Base.show(MIME{Symbol(\"text/plain\")}, PottsSystem)",
            "ModelingToolkitBase.equations()", "ModelingToolkitBase.unknowns()", "ModelingToolkitBase.parameters()",
            "ModelingToolkitBase.observed()", "ModelingToolkitBase.initial_conditions()", "ModelingToolkitBase.bindings()",
            "ModelingToolkitBase.independent_variables()", "SymbolicIndexingInterface.symbolic_container()",
            "SymbolicIndexingInterface.parameter_index(Any)", "SymbolicIndexingInterface.parameter_index(Symbol)",
            "SymbolicIndexingInterface.is_parameter(ModelingToolkitBase.ParameterIndex)",
            "SymbolicIndexingInterface.observed(Any)", "SymbolicIndexingInterface.parameter_observed(Any)",
            # the CPM compile entry and MTK's `extend` refused with a D-039 message (C4 review S3);
            # not among the 15, pinned here so a new owned method is never hidden
            "ModelingToolkitBase.mtkcompile()", "ModelingToolkitBase.extend(ModelingToolkitBase.AbstractSystem)",
            "ModelingToolkitBase.extend(PottsSystem)", "ModelingToolkitBase.extend(PottsSystem)",
            # the field library's accessor of the steady rows' fields (F3 batch 4 review r3 N2), no
            # MTK container method: not among the 15
            "LatticeFields.Problems.steady_fields()"])
        @test count(n -> !startswith(n, "ModelingToolkitBase.mtkcompile") && !startswith(n, "ModelingToolkitBase.extend") &&
                         !startswith(n, "LatticeFields."), names) == 15
        # `methodswith` skips `where` signatures: the MTK functions a container could reach for,
        # scanned directly (the probe's G inventory plus the old container's methods)
        M, S = WL_MTKB, WL_SII
        fs = Any[nameof, getproperty, propertynames, show, ndims, M.equations, M.unknowns, M.parameters, M.observed,
            M.initial_conditions, M.bindings, M.get_systems, M.get_eqs, M.get_unknowns, M.get_ps, M.get_observed, M.get_iv,
            M.has_eqs, M.has_ps, M.has_observed, M.independent_variable, M.independent_variables, M.complete, M.extend,
            M.compose, M.toggle_namespacing, M.getvar, M.flatten, M.mtkcompile, M.getmetadata, M.setmetadata, M.hasmetadata,
            S.is_time_dependent, S.symbolic_container, S.parameter_index, S.is_parameter, S.observed, S.parameter_observed,
            S.is_variable, S.variable_index, S.default_values]
        scanned = [m for f in fs for m in methods(f) if m.module === Potts &&
                       any(==(PottsSystem), Base.unwrap_unionall(m.sig).parameters)]
        @test length(scanned) == 19 && all(m -> m in owned || m.name === :extend, scanned)
        # the refusal loop: 16 constructors × (plain, {iip}, {iip, spec}), plus the one method that
        # settles the ambiguity with SciMLBase's `ODEProblem{iip, FunctionWrapperSpecialize}`
        @test length(WLiteMatrix.refusal_methods()) == 49
        @test isempty(filter(((a, b),) -> a.module === Potts || b.module === Potts, Test.detect_ambiguities(Potts; recursive = true)))
    end
end

@testitem "W-lite: internal access is getfield (QA grep)" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: internal access is getfield (QA grep)" begin
        src = joinpath(pkgdir(Potts), "src")
        bad = String[]
        for f in readdir(src; join = true), (i, l) in enumerate(eachline(f))
            occursin(r"\b(?!Potts\b)\w+\.(inner|part)\b|\b(sys|s|w|W|p|base|authored)\.fields\b", replace(l, r"#.*" => "")) &&
                push!(bad, "$(basename(f)):$i")
        end
        @test isempty(bad)
        # the negative control of the grep: a property read is found
        @test occursin(r"\b(?!Potts\b)\w+\.(inner|part)\b|\b(sys|s|w|W|p|base|authored)\.fields\b", "x = sys.part") && !occursin(r"\b(?!Potts\b)\w+\.(inner|part)\b", "Potts.inner(sys)")
    end
end

@testitem "W-lite: wrap checks" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: wrap checks" begin
        @test_throws ArgumentError Potts.wrap(:other, complete(inner_all), nothing, WLiteModels.part())            # name
        @test_throws ArgumentError Potts.wrap(:allparts, complete(inner_all), WLiteModels.pde(:x), WLiteModels.part())
        # P3-wlite trap 2: a completed system composed again is complete but not flat
        trap = compose(complete(WLiteModels.inner_top), [decay])
        @test iscomplete(trap) && !isempty(WL_MTKB.get_systems(trap))
        @test_throws ArgumentError Potts.wrap(:allparts, trap, nothing, WLiteModels.part())
        # an uncompleted system is completed (flattened) by wrap
        w = Potts.wrap(:allparts, inner_all, nothing, WLiteModels.part())
        @test iscomplete(Potts.inner(w)) && isempty(WL_MTKB.get_systems(Potts.inner(w))) &&
              issetequal(unknowns(w), unknowns(complete(inner_all)))
        @test Potts.fields(W_all) isa PDESystem && Potts.fields(W_empty) === nothing
        # the sweep payload is the inner System's metadata
        @test WL_MTKB.getmetadata(Potts.inner(w), Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
        @test WL_MTKB.getmetadata(inner_all, Potts.PottsSweepSpec, nothing) === nothing
    end
end

@testitem "W-lite: Potts.compose equals the raw reference" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: Potts.compose equals the raw reference" begin
        C, M_, T_ = WLiteCompose.cell(), WLiteCompose.model(), WLiteCompose.top()
        part = WLiteModels.part
        bind(n) = [Potts.FieldBinding(Symbol[], :vol, :volume)]
        wcell = Potts.wrap(:cell, C, nothing, part(; bindings = [Potts.FieldBinding(Symbol[], :cbar, :c_mean);
                                                                 bind(:cell)]))
        wmodel = Potts.wrap(:model, M_, nothing, part(; bindings = bind(:model)))
        wtop = Potts.wrap(:top, T_, nothing, part())
        function same(W, ref)
            I = Potts.inner(W)
            isequal(Set(equations(I)), Set(equations(ref))) && issetequal(unknowns(I), unknowns(ref)) &&
                issetequal(parameters(I), parameters(ref)) &&
                length(parameters(I; initial_parameters = true)) == length(parameters(ref; initial_parameters = true))
        end
        ref = complete(compose(WLiteCompose.model(), [WLiteCompose.cell()]))
        Wb = Potts.compose(wmodel, wcell)
        @test same(Wb, ref)                                                    # b7
        @test any(isequal(unwrap(Wb.cell.xc)), unknowns(Wb))
        # nested: top ∘ (model ∘ cell)
        nref = complete(compose(WLiteCompose.top(), [compose(WLiteCompose.model(), [WLiteCompose.cell()])]))
        Wn = Potts.compose(wtop, Potts.compose(wmodel, wcell))
        @test same(Wn, nref)                                                   # b8
        @test any(isequal(unwrap(Wn.model.cell.xc)), unknowns(Wn))
        # negative control: unwrapping the flattened inner (not `get_parent`) loses the hierarchy (trap 1)
        flat = Potts.wrap(:model, complete(compose(Potts.inner(wmodel), [Potts.inner(wcell)]; name = :model)), nothing, part())
        @test_throws ArgumentError flat.cell
        # S-2: (path, name) bindings, prefixed at compose, resolve to bound inputs of unknowns(W)
        bs = Potts.getfield(Potts.getfield(Wn, :part), :bindings)
        @test sort([(b.path, b.name) for b in bs]) ==
              sort([(Symbol[:model], :vol), (Symbol[:model, :cell], :cbar), (Symbol[:model, :cell], :vol)])
        for b in bs
            r = unwrap(Potts.resolve(Wn, b))
            @test any(isequal(r), unknowns(Wn)) && Potts.ModelingToolkitBase.isinput(r)
        end
        inputs = filter(Potts.ModelingToolkitBase.isinput, unknowns(Wn))
        @test issetequal(inputs, [unwrap(Potts.resolve(Wn, b)) for b in bs])     # every input is bound
        @test occursin("binding model.cell.cbar ← c_mean", sprint(show, MIME"text/plain"(), Wn))
        # the resolved terms are template-compile inputs
        @test Potts.ModelingToolkitBase.mtkcompile(Potts.inner(Wn); inputs) isa System
        # C4 review B1 / C9: subsystems are lowered into the payload as model-scope components;
        # top-level content of a hand-built System (wmodel's `D(w)`) and component inputs (wcell's
        # `cbar`, `vol`) are refused by name, never dropped
        loud(f, what) = try
            f()
            false
        catch e
            e isa ArgumentError && occursin(what, sprint(showerror, e))
        end
        refused = r"payload cannot build|has the input"     # wmodel's top level; wcell's inputs
        for W in (Wb, Wn, wcell)
            @test loud(() -> mtkcompile(W), refused)
            @test loud(() -> Potts.ModelingToolkitBase.structural_simplify(W), refused)
            @test loud(() -> PottsProblem(W, [], (0, 1)), refused)
            @test loud(() -> Potts.extend(W, wtop), refused) &&
                  loud(() -> Potts.extend(PottsModels.GranerGlazier(; name = :gg), W), refused)
        end
        gg = PottsModels.GranerGlazier(; name = :gg)
        # control: a model built from its payload compiles and extends
        gg = PottsModels.GranerGlazier(; name = :gg)
        @test mtkcompile(gg) isa CompiledPottsSystem && Potts.extend(gg, gg) isa PottsSystem
        # a component carrying CPM statements is refused
        cpm = PottsModels.GranerGlazier(; name = :gg)
        @test_throws ArgumentError Potts.compose(wtop, cpm)
    end
end

@testitem "W-lite: a PDESystem's condition is stored, printed and lowered (F1, V4; F2-11)" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: a PDESystem's condition is stored, printed and lowered (F1, V4; F2-11)" begin
        @potts_model WLiteBcs begin
            @kinds medium cell border
            @parameters T = 1.0
            @lattice Lattice((8, 8))
            @fields WLitePDE.sys() (WLitePDE.border => kind == border)
            @sweep Metropolis(; temperature = T)
        end
        sys = WLiteBcs(; name = :b)
        bcs = Potts.getfield(Potts.getfield(sys, :part), :bcs)
        @test length(bcs) == 1 && occursin("masked", string(bcs[1]))
        @test occursin("bc      ", sprint(show, MIME"text/plain"(), sys))
        # F2-11: lowered. The sites of the border cell after the last sweep (the fields step after
        # it) hold 5.0; the field spreads from them to the others
        σ = zeros(Int32, 8, 8); σ[1, :] .= 1
        op = [ownership => σ, kind => [:border]]
        u = solve(PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 1)), SequentialCPM()).u[end]
        a, own = u.site.c, Array(u.σ) .== 1
        @test any(own) && all(a[own] .== 5.0) && maximum(a) == 5.0
        @test any(!=(0.0), a[.!own]) && all(a[.!own] .!= 5.0)
        # … and `Potts.fields` carries it (base, round 0: its PDESystem dropped the condition)
        @test any(b -> occursin("masked", string(b)), getfield(Potts.fields(sys), :bcs))
        @potts_model WLiteNoBcs begin
            @kinds medium cell
            @parameters T = 1.0
            @lattice Lattice((8, 8))
            @sweep Metropolis(; temperature = T)
        end
        @test isempty(Potts.getfield(Potts.getfield(WLiteNoBcs(; name = :n), :part), :bcs))
    end
end

@testitem "W-lite: a hand-built inner System with other values or extra statements is refused" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: a hand-built inner System with other values or extra statements is refused" begin
        g = WLiteGuard(; name = :g)
        part = Potts.getfield(g, :part)
        m = WL_MTKB.getmetadata(Potts.inner(g), Potts._BuiltFrom, nothing)
        @test m[1] === part && m[2][] === Potts.inner(g)                       # the identity path
        ref = Potts._inner_system(Potts._staged(:g, part))
        x = only(filter(v -> occursin("x", string(v)), unknowns(ref)))
        λ = only(filter(v -> string(v) == "λ", parameters(ref)))
        @variables z(Potts.t)
        rebuilt(; kw...) = System(equations(ref), Potts.t, unknowns(ref), parameters(ref); name = :g,
            observed = observed(ref), initialization_eqs = WL_MTKB.initialization_equations(ref), kw...)
        c9(f) = try
            f()
            false
        catch e
            e isa ArgumentError && occursin("payload cannot build", sprint(showerror, e))
        end
        # control: the same System rebuilt by hand (no marker) passes the full comparison
        @test mtkcompile(Potts.wrap(:g, rebuilt(), nothing, part)) isa CompiledPottsSystem
        # an initialization equation only in the inner System
        @test c9(() -> mtkcompile(Potts.wrap(:g, rebuilt(; initialization_eqs = [x ~ 9.0]), nothing, part)))
        # other initial values in the inner System
        @test c9(() -> mtkcompile(Potts.wrap(:g, rebuilt(; initial_conditions = Dict(x => 7.0, λ => 5.0)), nothing, part)))
        # an observed equation only in the inner System
        @test c9(() -> mtkcompile(Potts.wrap(:g, rebuilt(; observed = [unwrap(z) ~ 2 * x]), nothing, part)))
        @test c9(() -> Potts.extend(g, Potts.wrap(:g, rebuilt(; initialization_eqs = [x ~ 9.0]), nothing, part)))
        # a System MTK derives from the marked inner one carries the marker (metadata is copied)
        # but is not the marked object: the full comparison runs (C4 review round 3)
        @variables yd(Potts.t)
        dsys = System([WL_MTKB.Differential(Potts.t)(yd) ~ -yd], Potts.t; name = :dsys)
        par = WL_MTKB.get_parent(Potts.inner(g))
        for derived in (complete(WL_MTKB.extend(dsys, par; name = :g)), complete(WL_MTKB.extend(par, dsys)))
            @test WL_MTKB.getmetadata(derived, Potts._BuiltFrom, nothing) !== nothing  # marker copied
            msg = try
                mtkcompile(Potts.wrap(:g, derived, nothing, part))
                "built"
            catch e
                sprint(showerror, e)
            end
            @test occursin("payload cannot build", msg) && occursin("yd", msg)
        end
        # C9: a subsystem composed into the marked inner one is lowered as a model-scope component
        composed = complete(WL_MTKB.compose(WL_MTKB.toggle_namespacing(par, true), [dsys]))
        @test WL_MTKB.getmetadata(composed, Potts._BuiltFrom, nothing) !== nothing
        c = mtkcompile(Potts.wrap(:g, composed, nothing, part))
        @test c isa CompiledPottsSystem && any(v -> occursin("dsys₊yd", string(v)), unknowns(c.sys))
    end
end

@testitem "W-lite C9: Potts.compose results compile, solve and extend" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite C9: Potts.compose results compile, solve and extend" begin
        part = WLiteModels.part
        wdec = Potts.wrap(:decay, WLiteC9.decay(), nothing, part())
        W = Potts.compose(WLiteGuard(; name = :g), wdec)
        @test any(isequal(unwrap(W.decay.yd)), unknowns(W))
        c = mtkcompile(W)
        @test c isa CompiledPottsSystem
        σ = zeros(Int32, 8, 8); σ[2:4, 2:4] .= 1
        p = PottsProblem(W, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
        @test :decay₊yd in propertynames(p.u0.model) && :decay₊kd in propertynames(p.p)
        rk4(h) = 1 - h + h^2 / 2 - h^3 / 6 + h^4 / 24
        u = solve(p, SequentialCPM()).u[end]
        @test u.model.decay₊yd[1] ≈ 2.0 * rk4(0.3 / 4)^40 rtol = 1e-12
        @test u.model.decay₊yd[1] ≈ 2.0 * exp(-0.3 * 10) rtol = 1e-5
        @test u.model.x[1] ≈ rk4(2.0 / 4)^40 rtol = 1e-12                      # the model's own ODE
        # negative control: without the component the quantity does not exist
        p0 = PottsProblem(WLiteGuard(; name = :g), [Potts.ownership => σ, Potts.kind => [1]], (0, 1))
        @test !(:decay₊yd in propertynames(p0.u0.model))
        # nested: (model ∘ decay) ∘ inner2, and through a wrapped compose of a composed component
        w2 = Potts.wrap(:inner2, WLiteC9.inner2(), nothing, part())
        Wn = Potts.compose(W, w2)
        pn = PottsProblem(Wn, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
        un = solve(pn, SequentialCPM()).u[end]
        @test un.model.decay₊yd[1] ≈ u.model.decay₊yd[1] rtol = 1e-12
        @test un.model.inner2₊zz[1] ≈ rk4(0.1 / 4)^40 rtol = 1e-12
        Wd = Potts.compose(WLiteGuard(; name = :g), Potts.compose(wdec, w2))
        @test any(isequal(unwrap(Wd.decay.inner2.zz)), unknowns(Wd))
        pd = PottsProblem(Wd, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
        @test solve(pd, SequentialCPM()).u[end].model.decay₊inner2₊zz[1] ≈ rk4(0.1 / 4)^40 rtol = 1e-12
        # a composed component's quantities are operating-point keys (`W.c.x`)
        pk = PottsProblem(W, [Potts.ownership => σ, Potts.kind => [1], W.decay.yd => 5.0], (0, 1))
        @test pk.u0.model.decay₊yd[1] == 5.0
        # a composed Potts model with per-cell quantities is refused by name (a composed component is
        # one instance for the model; it never silently becomes model-wide)
        @test occursin("per cell", sprint(showerror, try mtkcompile(Potts.compose(WLiteGuard(; name = :g), WLiteC9Cell(; name = :cc)))
        catch e
            e
        end))
        # extend: the composed model as base and as extension keeps the component, and solves
        for E in (Potts.extend(WLiteGuard(; name = :g), W), Potts.extend(W, WLiteGuard(; name = :g)))
            pe = PottsProblem(E, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
            @test :decay₊kd in propertynames(pe.p) && pe.p.decay₊kd == 0.3
            @test solve(pe, SequentialCPM()).u[end].model.decay₊yd[1] ≈ 2.0 * rk4(0.3 / 4)^40 rtol = 1e-12
        end
    end
end

@testitem "W-lite C9: composed content that cannot be compiled is refused by name" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite C9: composed content that cannot be compiled is refused by name" begin
        part = WLiteModels.part
        M = WL_MTKB
        msg(f) = try
            f()
            "built"
        catch e
            e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
        end
        g = WLiteGuard(; name = :g)
        wdec = Potts.wrap(:decay, WLiteC9.decay(), nothing, part())
        # B2: a per-cell component inside a composed model (it would become model-wide)
        @test occursin("@components", msg(() -> Potts.compose(g, WLiteC9PerCellComp(; name = :pc))))
        # control: the same model composes when it carries no component
        @test msg(() -> mtkcompile(Potts.compose(g, wdec))) == "built"
        # S3: a kind table in a composed Potts model
        @test occursin("kind table", msg(() -> mtkcompile(Potts.compose(g, WLiteC9Table(; name = :tab)))))
        # S3: name collisions: a second `decay`, and a composed name equal to a declared component
        W = Potts.compose(g, wdec)
        @test occursin("already has a component named `decay`", msg(() -> Potts.compose(W, wdec)))
        @test occursin("already has a component named `decay`", msg(() -> Potts.compose(WLiteC9ModelComp(; name = :mc), wdec)))
        two = msg(() -> mtkcompile(Potts.wrap(:g, complete(M.compose(M.toggle_namespacing(M.get_parent(Potts.inner(g)), true),
            [WLiteC9.decay(), WLiteC9.decay()])), nothing, Potts.getfield(g, :part))))
        @test occursin("two components named `decay`", two)
        # B1: top-level events, tstops and the like of a hand-built System are refused, not dropped
        dec = WLiteC9.decay()
        yd = dec.yd
        with(; kw...) = Potts.wrap(:h, System(Potts.Equation[], Potts.t; name = :h, systems = [WLiteC9.decay()], kw...), nothing, part())
        @test msg(() -> mtkcompile(with())) == "built"                                   # control
        @test occursin("continuous events", msg(() -> mtkcompile(with(; continuous_events = [[yd ~ 1.0] => [yd ~ M.Pre(yd) + 1.0]]))))
        @test occursin("discrete events", msg(() -> mtkcompile(with(; discrete_events = [1.0 => [yd ~ M.Pre(yd) + 1.0]]))))
        @test occursin("tstops", msg(() -> mtkcompile(with(; tstops = [0.5]))))
        par = M.get_parent(Potts.inner(g))
        xg = only(filter(v -> occursin("x", string(v)), unknowns(Potts.inner(g))))
        ev = System(Potts.Equation[], Potts.t; name = :ev, discrete_events = [1.0 => [xg ~ M.Pre(xg) + 1.0]])
        @test occursin("discrete events", msg(() -> mtkcompile(Potts.wrap(:g, complete(M.extend(ev, par; name = :g)), nothing,
            Potts.getfield(g, :part)))))
        # guard lists (review rounds 2, 3): MTK costs, constraints, noise equations and poissonians
        # are refused, not dropped, at the top level and in a composed component
        @test occursin("costs", msg(() -> mtkcompile(with(; costs = [2.0]))))
        for (f, what) in ((WLiteC9Neg.noisy, "noise equations"), (WLiteC9Neg.constrained, "constraints"),
                (WLiteC9Neg.costly, "costs"), (WLiteC9Neg.poisson, "poissonians"))
            top = msg(() -> mtkcompile(Potts.wrap(:h, f(:h; systems = [WLiteC9.decay()]), nothing, part())))
            comp = msg(() -> mtkcompile(Potts.compose(g, Potts.wrap(:hz, f(:hz), nothing, part()))))
            @test occursin(what, top)
            @test occursin(what, comp)
            occursin(what, top) && occursin(what, comp) || @info "C9 guard" what top comp
        end
        # a non-System is not wrapped
        @test_throws MethodError Potts.wrap(:x, 1.0, nothing, part())
        # B1′: a component's PDESystem and a host PDESystem that the payload does not build join the
        # model's fields (F4-11; before, both were refused); this one spans [0, 1] on an 8 × 8
        # lattice, so it is refused naming both domains
        @test occursin("the PDESystem `decay` spans `x ∈ [0, 1]`, but axis 1 of the lattice of `g` spans [0, 8]",
            msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), WLiteModels.pde(:decay), part()))))
        @test occursin("the PDESystem `h` spans `x ∈ [0, 1]`", msg(() -> mtkcompile(Potts.wrap(:h, System(Potts.Equation[], Potts.t;
            name = :h, systems = [WLiteC9.decay()]), WLiteModels.pde(:h), part()))))
        # a compiled model's `sys` (its PDESystem built from its payload) composes and compiles again
        fsys = mtkcompile(WLiteC9Field(; name = :wf)).sys
        @test Potts.fields(fsys) !== nothing
        @test msg(() -> mtkcompile(Potts.compose(fsys, Potts.wrap(:decay, WLiteC9.decay(), nothing, part())))) == "built"
        # kinds and lattice must be the model's (a fold reads kinds by number and the model's sites)
        @test occursin("has the kinds", msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), nothing,
            part(; kinds = [:medium, :ka, :kb])))))
        @test occursin("has the kinds", msg(() -> Potts.compose(g, WLiteC9FoldOther(; name = :pf))))
        @test occursin("another lattice", msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), nothing,
            part(; lattice = Potts.lattice_spec((6, 6)))))))
        # a population fold in a composed component is refused by name (it would not be lowered:
        # measured before the refusal, n(10) = 1.368 where counting the two cells gives 2.000)
        @test occursin("population fold", msg(() -> mtkcompile(Potts.compose(g, WLiteC9FoldSame(; name = :pf)))))
        # B2 through a hand-built wrap: a subsystem built from a payload with `@components`
        pc = WLiteC9PerCellComp(; name = :pc)
        hand = Potts.wrap(:g, complete(M.compose(M.toggle_namespacing(M.get_parent(Potts.inner(g)), true),
            [M.toggle_namespacing(M.get_parent(Potts.inner(pc)), true)])), nothing, Potts.getfield(g, :part))
        @test occursin("@components", msg(() -> mtkcompile(hand)))
        # a component named like a host quantity; a component reading `volume` (an input)
        @test occursin("has a quantity named `x`", msg(() -> Potts.compose(g, Potts.wrap(:x, WLiteC9Neg.xsys(), nothing, part()))))
        @test occursin("has the input", msg(() -> mtkcompile(Potts.compose(g, Potts.wrap(:vv, WLiteC9Neg.vsys(), nothing, part())))))
        @test occursin("has the input", msg(() -> mtkcompile(Potts.compose(g, Potts.wrap(:cell, WLiteCompose.cell(), nothing, part())))))
    end
end

@testitem "F4-10: Potts.component composes an MTK System into a model with an energy" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "F4-10: Potts.component composes an MTK System into a model with an energy" begin
        msg(f) = try
            f()
            "built"
        catch e
            e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
        end
        m = WLiteF410(; name = :m)
        @test !isempty(Potts.hamiltonian(m))
        comp = Potts.component(:decay, WLiteC9.decay(), m)
        @test isempty(Potts.hamiltonian(comp)) && Potts.lattice(comp) == Potts.lattice(m)
        W = Potts.compose(m, comp)
        @test any(isequal(unwrap(W.decay.yd)), unknowns(W)) && !isempty(Potts.hamiltonian(W))
        σ = zeros(Int32, 8, 8); σ[2:4, 2:4] .= 1
        p = PottsProblem(W, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4), seed = 2)
        sol = solve(p, SequentialCPM())
        rk4(h) = 1 - h + h^2 / 2 - h^3 / 6 + h^4 / 24
        @test sol.u[end].model.decay₊yd[1] ≈ 2.0 * rk4(0.3 / 4)^40 rtol = 1e-12
        @test sol.u[end].model.x[1] ≈ rk4(2.0 / 4)^40 rtol = 1e-12
        @test sol.u[end].σ != σ                                  # the energy's CPM ran
        # the route before F4-10 is refused, and the refusal names `Potts.component`
        old = msg(() -> Potts.compose(m, Potts.wrap(:decay, WLiteC9.decay(), nothing, Potts.part(m))))
        @test occursin("has energies", old) && occursin("Potts.component(:decay, system, model)", old)
        # PO74, PO75: other kinds or another lattice name `Potts.component`
        part = WLiteModels.part
        g = WLiteGuard(; name = :g)
        kinds = msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), nothing, part(; kinds = [:medium, :ka]))))
        lat = msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), nothing, part(; lattice = Potts.lattice_spec((6, 6))))))
        @test occursin("has the kinds", kinds) && occursin("Potts.component(name, system, model)", kinds)
        @test occursin("another lattice", lat) && occursin("Potts.component(name, system, model)", lat)
        # the component's name is the System's (as `Potts.wrap`)
        @test occursin("must agree", msg(() -> Potts.component(:other, WLiteC9.decay(), m)))
    end
end
