# Static gates on generated code: type stability (JET) of the solve loop, a warm MCS
# without allocation (AllocCheck), and package hygiene (Aqua).

@testsetup module QaSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts.ModelingToolkitBase: ShiftIndex, Clock
using JET, AllocCheck, Aqua

using InteractiveUtils: code_llvm

# the discrete-component fixtures (`xcell`, `toggle`, `sampler`, `DiscreteHybrid`,
# `discrete_counter_model`, `_discrete_blocks`): shared with test/symbolic_tests.jl
isdefined(@__MODULE__, :discrete_counter_model) ||
    include(joinpath(@__DIR__, "shared", "discrete_fixtures.jl"))

# D-047: every PottsModels model, Float64 and Float32. JET cannot see inside
# RuntimeGeneratedFunction bodies, so the generated code is also `eval`'d into plain
# functions.
using PottsModels: GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTGrowingMonolayer,
    AkeebInvasion, akeeb_state,
    graner_glazier_state, openvt_monolayer_state

const _QA_MOD = Module(:PottsQA)

Core.eval(_QA_MOD, :(using Potts; using Potts: CorePotts))

_qa_float64_literals(ex) = (n = Ref(0); _qa_walk(x -> x isa Float64 && (n[] += 1), ex); n[])

_qa_walk(f, x) = (f(x); x isa Expr && foreach(a -> _qa_walk(f, a), x.args))

const _CLOSURE_HEADS = (
    :->, :function, :do, :generator, :comprehension, :typed_comprehension,
)

function _qa_closure_heads(ex)
    ex isa Expr || return 0
    # the outer `(args...) -> body` is the generated function itself: scan its body
    body = ex.head === :-> ? ex.args[2] : ex
    n = Ref(0)
    _qa_walk(x -> x isa Expr && x.head in _CLOSURE_HEADS && (n[] += 1), body)
    return n[]
end

function _qa_generated_exprs(gc)
    exs = Any[]
    for k in (:delta_H, :commit!, :temperature, :constraint, :total_energy, :delta_E)
        ex = getproperty(gc, k)
        ex === nothing || push!(exs, ex)
    end
    append!(exs, gc.phases)
    if gc.lifecycle !== nothing
        push!(exs, gc.lifecycle.trigger)
        gc.lifecycle.before === nothing || push!(exs, gc.lifecycle.before)
    end
    return exs
end

@potts_model QAEdgeModel begin
    @kinds medium blob
    @parameters s = 0.5
    @variables begin
        rest(bond) = 12.0
        age(bond) = 0.0
    end
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 16.0)^2
        edges(bond) => 0.01 * (distance - rest)^2
    end
    @divide cells(blob) when = volume >= 34
    @after_mcs begin
        rest ~ Pre(rest) + Pre(age) + s
        age ~ Pre(age) + 1
    end
    @sweep Metropolis(; temperature = 1.0)
end

_qa_warm_allocated(integ) = (step!(integ); @allocated step!(integ))

# Discrete components' tick phases (kind-gated, fused with couplings, clocked, model
# scope) are type stable, allocation free and, in Float32, free of Float64.
@potts_model QADiscreteKinds begin
    @kinds medium A B
    @variables inp(cell) = 0.0
    @components cells(A) tg = toggle
    @components cells(B) smp = sampler
    @equations smp.dsig ~ inp > 0.5
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model QADiscreteScratch begin
    @kinds medium A
    @components cells(A) cc = xcell
    @components model mm = mmodel
    @components cells(A) zz = zslow
    @equations begin
        cc.ds ~ mm.dM > 0.5
        mm.dq ~ 1.0 + count(true for c in cells)
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

# D-051 R0: no model- or author-named code in the core packages. Identifiers, macro names,
# symbols and non-doc strings are scanned (comments and docstrings may cite sources);
# identifiers are split on `_` and camel case. Exceptions live in `privileged_allow.txt`.
const _DENY = [
    "merks", "wortel", "niculescu", "graner", "glazier", "akeeb", "jiang", "bauer", "zajac",
    "starruss", "myxo", "fortuna", "osborne", "chaste", "artistoo",
    "openvt", "cc3d", "compucell", "morpheus",
    "savill", "hogeweg", "act", "leader", "follower", "endothelial",
    "tumor", "tumour", "vasculo", "angiogen",
    "keratocyte", "amoeboid",
]

function _tokens(s)
    return [
        lowercase(t)
            for t in split(s, r"[^A-Za-z0-9]+|(?<=[a-z])(?=[A-Z])") if !isempty(t)
    ]
end

function _denied(s)
    return [
        d
            for d in _DENY
            if any(t -> t == d || (length(d) > 4 && occursin(d, t)), _tokens(s))
    ]
end

const JS = Base.JuliaSyntax
# The kind names are resolved at run time: Julia 1.13 removed `K"MacroName"` and spells a
# macro name as a `macro_name` node around a plain `Identifier` leaf (value `:name`), where
# 1.12 and earlier have one `MacroName` leaf whose value is `Symbol("@name")`. A macro name
# keeps the `@` its allowlist key has always had, either way (`_macro_text`), so both
# versions report the same hits on the same lines.
function _js_kind(name)
    return try
        JS.Kind(name)
    catch
        nothing
    end
end
const _K_IDENT = _js_kind("Identifier")
const _K_STRING = _js_kind("String")
const _K_MACRO = _js_kind("MacroName")        # 1.12 and earlier
const _K_MACRO_NODE = _js_kind("macro_name")  # 1.13 and later
const _K_DOC = _js_kind("doc")
_macro_text(s) = startswith(s, '@') ? s : "@" * s

function _privileged_hits(file)
    root = JS.parseall(JS.SyntaxNode, read(file, String); filename = file)
    out = Tuple{Int, String}[]
    function walk(n, indoc, inmacro)
        k = JS.kind(n)
        if k == _K_DOC
            foreach(((i, c),) -> walk(c, i == 1, false), enumerate(JS.children(n)))
            return
        end
        indoc && return
        if JS.is_leaf(n)
            if k == _K_IDENT || k == _K_STRING || (_K_MACRO !== nothing && k == _K_MACRO)
                s = string(n.val)
                inmacro && (s = _macro_text(s))
                isempty(_denied(s)) || push!(out, (JS.source_location(n)[1], s))
            end
        else
            m = inmacro || (_K_MACRO_NODE !== nothing && k == _K_MACRO_NODE)
            foreach(c -> walk(c, false, m), JS.children(n))
        end
    end
    walk(root, false, false)
    return out
end

# ExplicitImports guardrails (CLAUDE.md code rules). Every name Potts uses is
# imported explicitly and by its owner. The allowlists name each non-public access the
# package genuinely needs; add to them only by review, with the reason.
using ExplicitImports: ExplicitImports, check_no_implicit_imports,
    check_all_explicit_imports_are_public,
    check_no_stale_explicit_imports,
    check_all_qualified_accesses_via_owners,
    check_all_qualified_accesses_are_public

# ExplicitImports analyses a package's loaded extensions with it: load DynamicQuantities
# so that `PottsDynamicQuantitiesExt` is always checked, whatever ran before.
using DynamicQuantities: DynamicQuantities

const POTTS_NONPUBLIC_QUALIFIED = (
    # (Potts -> CorePotts: the interface Potts generates code against is public,
    # `CorePotts.MODEL_COMPILER_INTERFACE`)
    # --- Potts -> Base: no public equivalent
    Symbol("@__doc__"),   # attaching docstrings to macro-generated components
    :setindex,            # non-mutating tuple `setindex`
    Symbol("@nospecializeinfer"),  # the remake hooks inferred once for every model
    # --- Potts -> Symbolics
    :rename,              # Symbolics.rename: renames a component system (`k.x` is `k₊x`)
    # what `Potts.kind ∈ (1, 2)` builds: a binding of it is refused by name
    :VarDomainPairing,
    # --- PottsDynamicQuantitiesExt -> Potts: the extension is part of Potts and gives
    # Potts's own symbolic operators their unit rules, so it reads Potts internals.
    :at, :at2, :history_lag, :cell_integral, :Δ, :cell_centroid, :copy_displacement,
    :random_uniform, :gather, :population,   # operators whose `get_unit` rules it defines
    :_check_units,        # the unit-check hook `mtkcompile` calls, defined by the extension
    :_describe,           # statement labels for unit error messages
    :_p,                  # reads a PottsSystem's payload field (its `part`)
    # --- PottsDynamicQuantitiesExt -> MTK
    :get_unit,            # MTK's unit-inference function the extension extends; not public
    # --- Potts -> MTKBase: discrete components. The clock of a compiled discrete
    # system is only available as this variable metadata; no public accessor exists.
    :VariableTimeDomain,  # metadata key holding a discrete variable's clock
    :IntegerSequence,     # the clock of `ShiftIndex(t, 0)` (one tick per step, no period)
    # --- Potts -> MTKBase: the container around System. MTKBase's
    # `is_parameter(::AbstractSystem, ::ParameterIndex)` answers `is_split` of the
    # container, which has no index cache; the owned method forwards it to the inner System
    # instead.
    :ParameterIndex,
    # --- Potts -> MTKBase: `description(sys)` is MTK's documented accessor of a system's
    # description (`@description`); MTKBase does not declare it public. Potts forwards it.
    :description,
    # --- Potts -> SciMLBase: the error `CheckInit()` throws, as SciML's own initializations
    # do; SciMLBase does not declare it public
    :CheckInitFailureError,
)

# Names imported with `using M: x` that are not public in `M`.
const POTTS_NONPUBLIC_EXPLICIT = (
    :Split, :info,                # ext -> Potts internals (system splitting, model info)
    :get_unit, :ValidationError,  # ext -> MTK's unit-inference API; not declared public
)

# D-085: every synchronize and host↔device copy of the step path goes through the
# counted helpers in `lib/CorePotts/src/transfers.jl`. A raw call anywhere else must be in
# this allowlist, with the reason it is not in the step path (or not a transfer).
const RAW_TRANSFER_ALLOW = Dict(
    # Lattice `==` and `hash` (host utilities, 79-80); `Array{Bool}` of host masks: the
    # domain (66, construction), `mobility` (366, construction), `_set_mobility!` (392,
    # converts the host mask; its device copy is the counted `counted_copy!`)
    "lib/CorePotts/src/lattice.jl" => 6,
    # `initial_state` builds host arrays (53 `Vector{Int32}`, 66 `Array{Int32}`; setup)
    "lib/CorePotts/src/model.jl" => 2,
    # `_standard_frozen` on a host state (problem construction, remake, reinit!,
    # `frozen_sites`; 122-123); `_set_state_array!` converts the user's host value (650; the
    # copy is counted); `Base.Array(::PottsSolution)` refuses (D-287 X9: no transfer)
    "lib/CorePotts/src/problem.jl" => 4,
    # the boundary set's shadow copies of σ and the frozen mask (120, 125) under
    # `SequentialCPM(; skip_interior = true)`: host arrays only, the algorithm is CPU-only
    # (D-177)
    "lib/CorePotts/src/boundary_site.jl" => 2,
    # `reinit!`'s `_copy_state!` (setup; the counters are reset after it)
    "lib/CorePotts/src/checkpoint.jl" => 1,
    # `_bind_copy!`: a field phase's kind tables to the backend when it binds, and at a
    # rebind its tables and status word (setup and rebinding, never per MCS)
    "lib/CorePotts/src/fields.jl" => 1,
    # `_device_copy!` on the CPU backend (host arrays); on a device it is a kernel, since
    # Metal.jl's device→device `copyto!` waits for the GPU twice (D-101)
    "lib/CorePotts/src/phases.jl" => 1,
    # initial layouts on host arrays (setup; Frame masks)
    "src/layouts.jl" => 2
)

# `synchronize` of any module, `Array(`/`Base.Array(`/`Array{…}(`, `Vector(`/`Vector{…}(`,
# `Adapt.adapt(Array`, `convert(Array`, `copyto!(`, `unsafe_copyto!(`. `collect` and `copy`
# are left to the runtime wait-identity test (test/transfer_counts.jl).
const RAW_TRANSFER =
    r"\w+\.synchronize\(|(?<![\w.])Array\(|Base\.Array\(|(?<![\w.])Array\{[^{}]*\}\(|(?<![\w.])Vector(\{[^{}]*\})?\(|Adapt\.adapt\(Array|convert\(Array|(?<![\w!])copyto!\(|(?<![\w!])unsafe_copyto!\("

function _raw_transfer_hits(path)
    n = 0
    for line in eachline(path)
        # no comments, no doc code
        code = replace(first(split(line, '#'; limit = 2)), r"`[^`]*`" => "")
        n += length(collect(eachmatch(RAW_TRANSFER, code)))
    end
    return n
end
include(joinpath(@__DIR__, "shared", "qa_common.jl"))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "QA: generated models are type stable and allocation free (name)" setup = [
    QaSetup, PortsSetup, SymbolicSetup,
] tags = [:potts, :qa] begin
    @testset "QA: generated models are type stable and allocation free ($name)" for (
            name,
            make,
        ) in (
            ("graner", () -> symbolic_graner_problem(; nmcs = 5)),
            ("wortel", symbolic_wortel_problem), ("merks", symbolic_merks_problem),
            ("openvt", symbolic_openvt_problem),
            (
                "compartments", () -> (
                    c = compartment_state(); PottsProblem(
                        Compartments(; name = :comp),
                        [ownership => c[1], kind => c[2], cluster => c[3]], (0, 5)
                    )
                ),
            ),
            (
                "components", () -> (
                    σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2;
                    PottsProblem(
                        component_model(), [ownership => σ, kind => [:A, :B]],
                        (0, 5); ode_solver = Potts.RK4(substeps = 2)
                    )
                ),
            ),
            (
                "persistent", () -> (
                    σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1;
                    remake(
                        PottsProblem(
                            Persistent(; name = :p), [ownership => σ, kind => [1]], (
                                0, 5,
                            )
                        );
                        p = [:μ => 500.0]
                    )
                ),
            ),
            (
                "lags", () -> (
                    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1;
                    PottsProblem(Lags(; name = :l), [ownership => σ, kind => [1]], (0, 5))
                ),
            ),
            (
                "integrals", () -> (
                    σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1;
                    PottsProblem(
                        Integrals(; name = :i), [ownership => σ, kind => [1]],
                        (0, 5)
                    )
                ),
            ),
            (
                "systemic", () -> (
                    σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1;
                    PottsProblem(
                        Systemic(; name = :s), [ownership => σ, kind => [1]],
                        (0, 5); ode_solver = Potts.RK4(substeps = 4)
                    )
                ),
            ),
        )
        prob = make()
        integ = init(prob, SequentialCPM(; proposal = Moore(1)); save_start = false)
        step!(integ)
        @test_opt target_modules = (CorePotts, Potts) step!(integ)
        args = (integ.state, integ.kf, integ.p, integ.ctx, integ.law, integ.key, 1)
        @test isempty(check_allocs(CorePotts.sequential_mcs!, typeof.(args)))
        cinteg = init(prob, CheckerboardCPM(; proposal = Moore(1)); save_start = false)
        step!(cinteg)
        @test_opt target_modules = (CorePotts, Potts) step!(cinteg)
    end
end

@testitem "QA: Aqua" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: Aqua" begin
        # `check_extras = false`: workspace test-only deps live in test/Project.toml, not
        # [extras].
        qa_aqua(Potts; deps_compat = (; check_extras = false))
        # the piracy check inside each loaded extension (the DynamicQuantities one at least)
        @eval using DynamicQuantities: DynamicQuantities
        exts = qa_extension_piracies(Potts)
        @test Base.get_extension(Potts, :PottsDynamicQuantitiesExt) in exts
        # CorePotts' DiffEqBase extension: its own test environment does not load DiffEqBase
        @test Base.get_extension(CorePotts, :CorePottsDiffEqBaseExt) in
            qa_extension_piracies(CorePotts)
    end
end

@testitem "QA: the extension piracy check flags a planted pirate" setup = [QaSetup] tags = [
    :potts, :qa,
] begin
    @testset "QA: the extension piracy check flags a planted pirate" begin
        qa_piracy_control()
    end
end

@testitem "QA: generated code of label (T)" setup = [QaSetup, PortsSetup] tags = [
    :potts,
    :qa,
] begin
    @testset "QA: generated code of $label ($T)" for (label, make) in (
                (
                    "Graner–Glazier",
                    () -> (
                        GranerGlazier(; name = :gg),
                        (s = graner_glazier_state(); [ownership => s[1], kind => s[2]]),
                        nothing,
                    ),
                ),
                (
                    "Wortel",
                    () -> (
                        WortelAct(; name = :w, lattice = (16, 16)),
                        [ownership => wortel_state(), kind => [:cell, :cell]], nothing,
                    ),
                ),
                (
                    "Merks", () -> (
                        MerksVasculogenesis(; name = :m, lattice = (8, 8)), [
                            ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s),
                            kind => [:endothelial],
                        ],
                        nothing,
                        (; field_solver = MERKS_SOLVER),
                    ),
                ),
                (
                    "OpenVT",
                    () -> (
                        OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24)),
                        openvt_monolayer_state(; lattice = (24, 24)), 16,
                    ),
                ),
                (
                    "Akeeb",
                    () -> (
                        AkeebInvasion(; name = :a, lattice = (99, 60)),
                        akeeb_state(; lattice = (99, 60)), 1000,
                    ),
                ),
            ),
            T in (Float64, Float32)

        sys, op, cap, kw... = make()
        skw = get(kw, 1, (;))      # solver keywords (D-075)
        prob = PottsProblem(sys, op, (0, 3); T, capacity = cap, skw...)
        integ = init(prob, SequentialCPM(; proposal = Moore(1)); save_start = false)
        step!(integ)
        st, p, ctx = integ.state, integ.p, integ.ctx
        args = (st, integ.kf, p, ctx, integ.law, integ.key, 1)
        @test isempty(check_allocs(CorePotts.sequential_mcs!, typeof.(args)))
        N = ndims(st.ownership)
        prop = CorePotts.Proposal{N}(1, 2, ntuple(_ -> 1, N), 1, Int32(1), Int32(0))
        for fn in (prob.f.delta_H, prob.f.commit!, prob.f.temperature, prob.f.constraint)
            @test isempty(check_allocs(fn, typeof.((st, p, prop, ctx))))
        end
        # a warm MCS allocates nothing: phases, the lifecycle check and checkerboard colors
        # that fit one CPU workgroup run as plain loops (`CorePotts._launch`)
        for alg in (
                SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(;
                    proposal = Moore(1)
                ),
            )
            wi = init(
                PottsProblem(sys, op, (0, 100); T, capacity = cap, skw...), alg;
                save_start = false, save_end = false, save_everystep = false
            )
            @test minimum(_qa_warm_allocated(wi) for _ in 1:5) == 0
        end
        gc = generated_code(sys; T, skw...)
        @test all(ex -> _qa_closure_heads(ex) == 0, _qa_generated_exprs(gc))
        for name in (:delta_H, :commit!, :temperature, :constraint)
            ex = getproperty(gc, name)
            ex === nothing && continue
            fn = Core.eval(_QA_MOD, ex)
            types = Tuple{typeof.((st, p, prop, ctx))...}
            @test isempty(
                JET.get_reports(
                    Base.invokelatest(
                        JET.report_opt, fn, types; target_modules = (CorePotts, Potts)
                    )
                )
            )
            # device code: no Float64 (Metal)
            if T === Float32
                @test _qa_float64_literals(ex) == 0
                @test !occursin(
                    r"\bdouble\b",
                    sprint((io, f, t) -> Base.invokelatest(code_llvm, io, f, t), fn, types)
                )
            end
        end
    end
end

@testitem "QA: generated edge and lifecycle code has no closure heads" setup = [
    QaSetup,
] tags = [
    :potts, :qa,
] begin
    @testset "QA: generated edge and lifecycle code has no closure heads ($T)" for T in (
            Float64, Float32,
        )
        gc = generated_code(QAEdgeModel(; name = :qe); T)
        @test all(ex -> _qa_closure_heads(ex) == 0, _qa_generated_exprs(gc))
    end
end

@testitem "QA: discrete components (label, T)" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: discrete components ($label, $T)" for (label, make) in (
                (
                    "scratch",
                    () -> (
                        QADiscreteScratch(; name = :s),
                        [ownership => _discrete_blocks(2), kind => [1, 1]],
                    ),
                ),
                (
                    "kinds",
                    () -> (
                        QADiscreteKinds(; name = :k),
                        [
                            ownership => _discrete_blocks(4), kind => [1, 2, 1, 2], :inp =>
                            [0, 1, 0, 1],
                        ],
                    ),
                ),
                (
                    "hybrid",
                    () -> (
                        DiscreteHybrid(; name = :h),
                        [ownership => _discrete_blocks(2), kind => [1, 1]],
                    ),
                ),
                (
                    "model clock", () -> (
                        discrete_counter_model(ShiftIndex(Clock(2.0)); scope = :model),
                        [ownership => _discrete_blocks(3), kind => [1, 1, 1]],
                    ),
                ),
            ),
            T in (Float64, Float32)

        sys, op = make()
        prob = PottsProblem(sys, op, (0, 100); T)
        for alg in (
                SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(;
                    proposal = Moore(1)
                ),
            )
            integ = init(
                prob, alg; save_start = false, save_end = false, save_everystep = false
            )
            @test minimum(_qa_warm_allocated(integ) for _ in 1:5) == 0
            @test_opt target_modules = (CorePotts, Potts) step!(integ)
        end
        integ = init(prob, SequentialCPM(; proposal = Moore(1)); save_start = false)
        step!(integ)
        c = mtkcompile(sys)
        for b in getfield(c, :discrete)
            ex = Potts._tick_expr(
                [b], T, getfield(c, :gather_names),
                b.scope; scratch = Potts._tick_scratch(c)
            )
            @test _qa_closure_heads(ex) == 0
            fn = Core.eval(_QA_MOD, ex)
            args = if b.scope === :cell
                (integ.state, integ.p, integ.ctx, integ.key, 1, Int32(1))
            else
                (integ.state, integ.p, integ.ctx, integ.key, 1)
            end
            types = Tuple{typeof.(args)...}
            @test isempty(
                JET.get_reports(
                    Base.invokelatest(
                        JET.report_opt, fn, types; target_modules = (CorePotts, Potts)
                    )
                )
            )
            @test isempty(Base.invokelatest(check_allocs, fn, types))
            if T === Float32
                @test _qa_float64_literals(ex) == 0
                @test !occursin(
                    r"\bdouble\b",
                    sprint((io, f, t) -> Base.invokelatest(code_llvm, io, f, t), fn, types)
                )
            end
        end
    end
end

@testitem "QA: no model-named code in the core packages" setup = [QaSetup] tags = [
    :potts,
    :qa,
] begin
    @testset "QA: no model-named code in the core packages" begin
        root = joinpath(@__DIR__, "..")
        allow = Set(
            strip(first(split(l, "   #")))
                for l in eachline(joinpath(@__DIR__, "privileged_allow.txt"))
                if !startswith(l, "#") && !isempty(strip(l))
        )
        bad = String[]
        for d in (
                    "src", "lib/CorePotts/src", "lib/LatticeFields/src",
                    "lib/MakiePotts/src",
                ),
                (dir, _, fs) in walkdir(joinpath(root, d)), f in fs

            endswith(f, ".jl") || continue
            rel = relpath(joinpath(dir, f), root)
            for (line, s) in _privileged_hits(joinpath(dir, f))
                "$rel:$s" in allow || push!(bad, "$rel:$line $s")
            end
        end
        isempty(bad) || @error "model-named code in core packages" bad
        @test isempty(bad)
        # and none among the names a model or hand-written problem can reach
        for ns in (names(Potts), names(CorePotts), collect(keys(Potts.DSL)))
            @test all(n -> isempty(_denied(string(n))), ns)
        end
    end
end

@testitem "QA: no development-process IDs in names, titles, comments or messages" setup = [
    QaSetup,
] tags = [
    :potts, :qa,
] begin
    @testset "QA: no development-process IDs in names, titles, comments or messages" begin
        # Positive controls, built by concatenation so that this file does not match itself.
        for (s, tok) in (
                ("see " * "P6" * ".0as here", "P6" * ".0as"), (
                    "p6" * "_0as_x.jl", "p6" * "_0as",
                ),
                ("P60" * "AS_NAMED", "P60" * "AS_"), ("p64" * "r_rate", "p64" * "r_"),
                ("F4" * "-E15", "F4" * "-E15"), ("F3" * "-21b", "F3" * "-21b"), (
                    "TS" * "1b", "TS" * "1b",
                ),
                ("review" * " r1", "review" * " r1"), ("r3" * " S1", "r3" * " S1"),
                ("front " * "end A", "front " * "end A"), ("W-" * "lite", "W-" * "lite"),
                ("cutover " * "C8", "cutover " * "C8"), (
                    "F3 " * "design §3.4", "F3 " * "design",
                ),
                ("v3 " * "§7.1", "v3 " * "§"), ("D-" * "F2" * "-1", "D-" * "F2" * "-1"),
                ("P60" * "ccDevice", "P60" * "ccD"), ("review" * " M2", "review" * " M2"),
                ("review" * " 4", "review" * " 4"), ("review" * " B1 #1", "review" * " B1"),
                ("gating (B" * "1)", "(B" * "1)"), ("P3" * "-mg §6", "P3" * "-mg"),
            )
            @test qa_phase_tokens(s) == [tok]
        end
        # Negative controls: domain names of the same shape.
        for s in (
                "before_mcs", "frozen_kinds", "Float64", "RK4", "BDF2", "F1-F4", "V-C12",
                "O5",
                "C12(curve, k)", "T1 transition", "## Step 1: the lattice", "paired A/B",
                "D-" *
                    "157",
                "50 Eden rounds", "round 1", "review the code", "PRE §III B4", "p53 levels",
            )
            @test isempty(qa_phase_tokens(s))
        end
        # Plain decision IDs: allowed in code comments only.
        @test qa_decision_ids("msg = \"see D-" * "123\"") == ["D-" * "123"]
        @test isempty(qa_decision_ids("x = 1   # D-" * "123"))
        @test qa_decision_ids("# D-" * "123"; prose = true) == ["D-" * "123"]
        @test isempty(qa_decision_ids("D-12, D-1234, VD-123"))
        # Scratch-directory control: a planted ID fails, and an allowlist entry lets it
        # pass.
        mktempdir() do tmp
            mkpath(joinpath(tmp, "src"))
            write(joinpath(tmp, "src", "planted.jl"), "# see " * "P6" * ".0as\nx = 1\n")
            write(joinpath(tmp, "src", "clean.jl"), "# the copy sweep, D-" * "157\n")
            @test qa_no_phase_names(tmp) == ["src/planted.jl:1: " * "P6" * ".0as"]
            mkpath(joinpath(tmp, "docs", "src"))
            write(joinpath(tmp, "docs", "src", "page.md"), "The sweep (D-" * "157).\n")
            @test qa_no_phase_names(tmp) ==
                ["docs/src/page.md:1: D-" * "157", "src/planted.jl:1: " * "P6" * ".0as"]
            rm(joinpath(tmp, "docs"); recursive = true)
            allow = joinpath(tmp, "allow.txt")
            write(allow, "src/planted.jl\t" * "P6" * ".0as\ta planted control\n")
            @test isempty(qa_no_phase_names(tmp; allow = qa_phase_allowlist(allow)))
            write(allow, "src/planted.jl\t" * "P6" * ".0as\n")
            @test_throws ArgumentError qa_phase_allowlist(allow)
        end
        # The repository: every hit not in test/phase_names_allow.txt.
        bad = qa_no_phase_names(joinpath(@__DIR__, ".."))
        isempty(bad) ||
            @error "development-process IDs (rename them, or add an allowlist entry with \
                a reason)" bad
        @test isempty(bad)
    end
end

@testitem "QA: lines fit in 92 columns" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: lines fit in 92 columns" begin
        # Scratch-directory control: a planted long line fails; a long URL line, a long line
        # under docs/design/ and a short line pass; an allowlist entry lets the planted line
        # pass, and an entry that matches nothing is reported.
        mktempdir() do tmp
            long = "x = " * repeat("1 + ", 25) * "1"
            mkpath(joinpath(tmp, "src"))
            write(joinpath(tmp, "src", "planted.jl"), "y = 1\n" * long * "\n")
            write(
                joinpath(tmp, "src", "url.jl"),
                "# https://example.org/" * repeat("a", 100) * "\n"
            )
            mkpath(joinpath(tmp, "docs", "design"))
            write(joinpath(tmp, "docs", "design", "notes.jl"), long * "\n")
            # by kind: a table row in a comment and a line made long by its regex pass;
            # code that builds a table row and long code holding a short regex fail
            cells = repeat("| \$a ", 30) * "|"
            build = "push!(rows, \"" * cells * "\")"
            regex = "m = match(r\"" * repeat("[0-9]", 30) * "\", s)"
            code = long * " + f(r\"a\")"
            write(
                joinpath(tmp, "src", "kinds.jl"),
                join(["# " * cells, build, regex, code], "\n") * "\n"
            )
            @test qa_long_lines(tmp) == [
                "src/kinds.jl:2: $(textwidth(build))",
                "src/kinds.jl:4: $(textwidth(code))",
                "src/planted.jl:2: $(textwidth(long))",
            ]
            rm(joinpath(tmp, "src", "kinds.jl"))
            @test qa_long_lines(tmp) == ["src/planted.jl:2: $(textwidth(long))"]
            @test isempty(qa_long_lines(tmp; limit = textwidth(long)))
            allow = joinpath(tmp, "allow.txt")
            write(allow, "src/planted.jl\t1 + 1\ta planted control\n")
            @test isempty(qa_long_lines(tmp; allow = qa_line_allowlist(allow)))
            write(allow, "src/planted.jl\t*\ta planted control, whole file\n")
            @test isempty(qa_long_lines(tmp; allow = qa_line_allowlist(allow)))
            write(allow, "src/planted.jl\t1 + 1\ta planted control\nsrc/url.jl\tz\tstale\n")
            @test qa_long_lines(tmp; allow = qa_line_allowlist(allow)) ==
                ["allowlist: src/url.jl: z"]
            write(allow, "src/planted.jl\t1 + 1\n")
            @test_throws ArgumentError qa_line_allowlist(allow)
        end
        # The repository: every long line not exempt and not in test/line_length_allow.txt.
        bad = qa_long_lines(joinpath(@__DIR__, ".."))
        isempty(bad) ||
            @error "lines over 92 columns (wrap them, or add an allowlist entry with a \
                reason)" bad
        @test isempty(bad)
    end
end

@testitem "QA: ExplicitImports (Potts)" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: ExplicitImports (Potts)" begin
        qa_explicit_imports(
            Potts;
            nonpublic_explicit = POTTS_NONPUBLIC_EXPLICIT,
            nonpublic_qualified = POTTS_NONPUBLIC_QUALIFIED
        )
    end
end

@testitem "QA: Docs and extensions (Potts)" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: Docs and extensions (Potts)" begin
        qa_api_docs(
            Potts;
            submodules = (Potts.Fields,),
            docs_dir = joinpath(@__DIR__, "..", "docs")
        )
        root = joinpath(@__DIR__, "..")
        qa_error_rules(
            root;
            allowed_bcs_files = [
                joinpath(root, "src", "macro.jl"),
                joinpath(root, "test", "fields_couple_checks_tests.jl"),
            ]
        )
        @test Base.get_extension(Potts, :PottsDynamicQuantitiesExt) !== nothing
        if PottsDevices.device_name() == "rocm"
            @test Base.get_extension(Potts, :PottsAMDGPUExt) !== nothing
        end
    end
end

@testitem "QA: no raw host transfer outside the counted helpers" setup = [QaSetup] tags = [
    :potts, :qa,
] begin
    @testset "QA: no raw host transfer outside the counted helpers" begin
        root = joinpath(@__DIR__, "..")
        hits = Dict{String, Int}()
        for d in ("lib/CorePotts/src", "src"), f in readdir(joinpath(root, d))
            (endswith(f, ".jl") && f != "transfers.jl") || continue
            n = _raw_transfer_hits(joinpath(root, d, f))
            n > 0 && (hits["$d/$f"] = n)
        end
        hits == RAW_TRANSFER_ALLOW ||
            @error "raw synchronize/Array/adapt/copyto! outside \
                transfers.jl" hits RAW_TRANSFER_ALLOW
        @test hits == RAW_TRANSFER_ALLOW
    end
end

# D-138: the Voronoi layer (tessellation, Lloyd, repair) and shape regions are type
# stable on square, hexagonal and 3D lattices (host-side, but `graner_glazier_aggregate`
# runs it at paper size for every replicate).
@testitem "QA: Voronoi and shape regions are type stable (label)" setup = [QaSetup] tags = [
    :potts, :qa,
] begin
    using Potts.Layouts
    @testset "QA: Voronoi and shape regions are type stable ($label)" for (label, L) in (
            ("hex periodic", Lattice((30, 30); geometry = Hexagonal())), (
                "square closed", Lattice((30, 30); boundary = Closed()),
            ),
            ("3D", Lattice((12, 12, 12); boundary = Closed())),
        )
        lat = Potts._layout_spec(L)
        N = length(lat.dims)
        S = HyperSphere{N, Float64}
        @test_opt target_modules = (
            Potts,
        ) Potts._region_sites(S(Point(ntuple(_ -> 6.0, N)), 4.0), lat, "")
        @test_opt target_modules = (Potts,) Potts.paint!(
            Potts.LayoutState(lat.dims),
            Voronoi(
                RandomPoints(10; region = S(Point(ntuple(_ -> 6.0, N)), 4.0), seed = 1);
                lloyd = 3, kinds = [:a]
            ), lat
        )
    end
end

# D-141: Eden's growth and the Splits passes are type stable on square, hexagonal and
# 3D lattices (host-side; the growth loop runs once per round over the frontier).
@testitem "QA: Eden and Splits are type stable (label)" setup = [QaSetup] tags = [
    :potts,
    :qa,
] begin
    using Potts.Layouts
    @testset "QA: Eden and Splits are type stable ($label)" for (label, L) in (
            ("hex periodic", Lattice((30, 30); geometry = Hexagonal())), (
                "square closed", Lattice((30, 30); boundary = Closed()),
            ),
            ("3D", Lattice((12, 12, 12); boundary = Closed())),
        )
        lat = Potts._layout_spec(L)
        e = Eden(
            RandomPoints(5; replace = true, seed = 1); rounds = 3,
            kinds = [:a], seed = 1, shortfall = :allow
        )
        @test_opt target_modules = (Potts,) Potts.paint!(
            Potts.LayoutState(lat.dims), e,
            lat
        )
        @test_opt target_modules = (Potts,) Potts.paint!(
            Potts.LayoutState(lat.dims),
            Splits(e, 2; shortfall = :allow, splits = :allow), lat
        )
    end
end

# JET's error analysis of the whole package: undefined names and fields (D-298)
@testitem "QA: JET package analysis (Potts)" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: JET package analysis (Potts)" begin
        qa_jet_package(
            Potts;
            locals = [
                # the build closure assigns `phases` and `lifecycle`, which the enclosing
                # function assigns again after it: a boxed capture, read after its
                # assignment
                r"`(phases|lifecycle)` is not defined \(problem\.jl\)" => "boxed capture",
            ]
        )
    end
end

@testitem "QA: the JET analysis flags an undefined name and field" setup = [
    QaSetup,
] tags = [
    :potts, :qa,
] begin
    @testset "QA: the JET analysis flags an undefined name and field" begin
        qa_jet_control()
    end
end

# the check-bounds lane: an out-of-bounds read under `@inbounds` is caught (D-298)
@testitem "QA: check-bounds lane control" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: check-bounds lane control" begin
        qa_check_bounds_control()
    end
end

# every external dependency of a workspace test project has a compat bound (D-298)
@testitem "QA: test projects bound their external dependencies" setup = [QaSetup] tags = [
    :potts, :qa,
] begin
    @testset "QA: test projects bound their external dependencies" begin
        root = pkgdir(Potts)
        workspace = Base.parsed_toml(joinpath(root, "Project.toml"))["workspace"][
            "projects",
        ]
        own = [
            Base.parsed_toml(joinpath(root, p, "Project.toml"))["name"]
                for p in workspace
                if !endswith(p, "test") && p != "benchmark" && p != "docs"
        ]
        push!(own, "Potts")
        for p in filter(endswith("test"), workspace)
            @test isempty(qa_missing_compat(joinpath(root, p, "Project.toml"); own))
        end
        qa_missing_compat_control()
    end
end

# our exported names do not clash with each other or with the upstream packages users load
# alongside: Makie, Symbolics, ModelingToolkitBase (ModelingToolkit re-exports it) and the
# OrdinaryDiffEq solver libraries with SciMLBase and DiffEqBase, which OrdinaryDiffEq
# re-exports (D-298)
@testitem "QA: exported names do not clash" setup = [QaSetup] tags = [:potts, :qa] begin
    @testset "QA: exported names do not clash" begin
        pkg(name, uuid) = Base.require(Base.PkgId(Base.UUID(uuid), name))
        ours = (
            Potts, CorePotts,
            pkg("LatticeFields", "27141c10-c94d-4a11-8a68-94c33ddb5bc4"),
            pkg("LatticePDE", "8c13e429-a5cc-4e77-8f91-d2d1c866aeb6"),
            pkg("MakiePotts", "95794c00-c762-4965-bf31-de18bcca2bc9"),
            pkg("PottsModels", "7ddeed3b-134f-4313-a104-79862f0bd557"),
        )
        upstream = (
            pkg("Makie", "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"),
            pkg("Symbolics", "0c5d862f-8b57-4792-8d23-62f2024744c7"),
            pkg("ModelingToolkitBase", "7771a370-6774-4173-bd38-47e70ca0b839"),
            pkg("OrdinaryDiffEqTsit5", "b1df2697-797e-41e3-8120-5422d3b24e4a"),
            pkg("OrdinaryDiffEqRosenbrock", "43230ef6-c299-4910-a778-202eb28ce4ce"),
            pkg("OrdinaryDiffEqBDF", "6ad6398a-0878-4a85-9266-38940aa047c8"),
            pkg("OrdinaryDiffEqSDIRK", "2d112036-d095-4a1e-ab9a-08536f3ecdbf"),
            pkg("DiffEqBase", "2b5f629d-d688-5b77-993f-72d75c75574e"),
            pkg("SciMLBase", "0bca4576-84f4-4d90-8ffe-ffa030f20462"),
        )
        @test isempty(Base.invokelatest(qa_export_clashes, ours, upstream))
        qa_export_clash_control()
    end
end
