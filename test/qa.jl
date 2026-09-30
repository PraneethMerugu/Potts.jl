# Static gates on generated code: type stability (JET) of the solve loop, a warm MCS
# without allocation (AllocCheck), and package hygiene (Aqua).
using JET, AllocCheck, Aqua
using InteractiveUtils: code_llvm

@testset "QA: generated models are type stable and allocation free ($name)" for (name, make) in (
        ("graner", () -> symbolic_graner_problem(; nmcs = 5)),
        ("wortel", symbolic_wortel_problem), ("merks", symbolic_merks_problem),
        ("openvt", symbolic_openvt_problem),
        ("compartments", () -> (c = compartment_state(); PottsProblem(Compartments(; name = :comp),
            [ownership => c[1], kind => c[2], cluster => c[3]], (0, 5)))),
        ("components", () -> (σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2;
            PottsProblem(component_model(Potts.RK4(substeps = 2)), [ownership => σ, kind => [:A, :B]], (0, 5)))),
        ("persistent", () -> (σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1;
            remake(PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 5)); p = [:μ => 500.0]))),
        ("lags", () -> (σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1;
            PottsProblem(Lags(; name = :l), [ownership => σ, kind => [1]], (0, 5)))),
        ("integrals", () -> (σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1;
            PottsProblem(Integrals(; name = :i), [ownership => σ, kind => [1]], (0, 5)))),
        ("systemic", () -> (σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1;
            PottsProblem(Systemic(; name = :s), [ownership => σ, kind => [1]], (0, 5)))))
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

@testset "QA: Aqua" begin
    Aqua.test_all(Potts; ambiguities = false, deps_compat = (; check_extras = false))
end

# D-047: every PottsModels model, Float64 and Float32. JET cannot see inside
# RuntimeGeneratedFunction bodies, so the generated code is also `eval`'d into plain functions.
using PottsModels: GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTGrowingMonolayer, AkeebInvasion, akeeb_state,
    graner_glazier_state, openvt_monolayer_state

const _QA_MOD = Module(:PottsQA)
Core.eval(_QA_MOD, :(using Potts; using Potts: CorePotts))

_qa_float64_literals(ex) = (n = Ref(0); _qa_walk(x -> x isa Float64 && (n[] += 1), ex); n[])
_qa_walk(f, x) = (f(x); x isa Expr && foreach(a -> _qa_walk(f, a), x.args))
_qa_warm_allocated(integ) = (step!(integ); @allocated step!(integ))

@testset "QA: generated code of $label ($T)" for (label, make) in (
        ("Graner–Glazier", () -> (GranerGlazier(; name = :gg), (s = graner_glazier_state(); [ownership => s[1], kind => s[2]]), nothing)),
        ("Wortel", () -> (WortelAct(; name = :w, lattice = (16, 16)), [ownership => wortel_state(), kind => [:cell, :cell]], nothing)),
        ("Merks", () -> (MerksVasculogenesis(; name = :m, lattice = (8, 8)), [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s),
            kind => [:endothelial]], nothing)),
        ("OpenVT", () -> (OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24)), openvt_monolayer_state(; lattice = (24, 24)), 16)),
        ("Akeeb", () -> (AkeebInvasion(; name = :a, lattice = (99, 60)), akeeb_state(; lattice = (99, 60)), 1000))),
    T in (Float64, Float32)
    sys, op, cap = make()
    prob = PottsProblem(sys, op, (0, 3); T, capacity = cap)
    integ = init(prob, SequentialCPM(; proposal = Moore(1)); save_start = false)
    step!(integ)
    st, p, ctx = integ.state, integ.p, integ.ctx
    args = (st, integ.kf, p, ctx, integ.law, integ.key, 1)
    @test isempty(check_allocs(CorePotts.sequential_mcs!, typeof.(args)))
    N = ndims(st.σ)
    prop = CorePotts.Proposal{N}(1, 2, ntuple(_ -> 1, N), 1, Int32(1), Int32(0))
    for fn in (prob.f.delta_H, prob.f.commit!, prob.f.temperature, prob.f.constraint)
        @test isempty(check_allocs(fn, typeof.((st, p, prop, ctx))))
    end
    # a warm MCS allocates nothing: phases, the lifecycle check and checkerboard colors that
    # fit one CPU workgroup run as plain loops (`CorePotts._launch`; AUTONOMY §5)
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        wi = init(PottsProblem(sys, op, (0, 100); T, capacity = cap), alg; save_start = false, save_end = false)
        @test minimum(_qa_warm_allocated(wi) for _ in 1:5) == 0
    end
    gc = generated_code(sys; T)
    for name in (:delta_H, :commit!, :temperature, :constraint)
        ex = getproperty(gc, name)
        ex === nothing && continue
        fn = Core.eval(_QA_MOD, ex)
        types = Tuple{typeof.((st, p, prop, ctx))...}
        @test isempty(JET.get_reports(Base.invokelatest(JET.report_opt, fn, types; target_modules = (CorePotts, Potts))))
        if T === Float32                                  # device code: no Float64 (Metal)
            @test _qa_float64_literals(ex) == 0
            @test !occursin(r"\bdouble\b", sprint((io, f, t) -> Base.invokelatest(code_llvm, io, f, t), fn, types))
        end
    end
end

# P6.0k: discrete components' tick phases (kind-gated, fused with couplings, clocked, model
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

@testset "QA: discrete components ($label, $T)" for (label, make) in (
        ("scratch", () -> (QADiscreteScratch(; name = :s), [ownership => _discrete_blocks(2), kind => [1, 1]])),
        ("kinds", () -> (QADiscreteKinds(; name = :k), [ownership => _discrete_blocks(4), kind => [1, 2, 1, 2], :inp => [0, 1, 0, 1]])),
        ("hybrid", () -> (DiscreteHybrid(; name = :h), [ownership => _discrete_blocks(2), kind => [1, 1]])),
        ("model clock", () -> (discrete_counter_model(ShiftIndex(Clock(2.0)); scope = :model),
            [ownership => _discrete_blocks(3), kind => [1, 1, 1]]))),
    T in (Float64, Float32)
    sys, op = make()
    prob = PottsProblem(sys, op, (0, 100); T)
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        integ = init(prob, alg; save_start = false, save_end = false)
        @test minimum(_qa_warm_allocated(integ) for _ in 1:5) == 0
        @test_opt target_modules = (CorePotts, Potts) step!(integ)
    end
    integ = init(prob, SequentialCPM(; proposal = Moore(1)); save_start = false)
    step!(integ)
    c = mtkcompile(sys)
    for b in c.discrete
        ex = Potts._tick_expr([b], T, c.gather_names, b.scope; scratch = Potts._tick_scratch(c))
        fn = Core.eval(_QA_MOD, ex)
        args = b.scope === :cell ? (integ.state, integ.p, integ.ctx, integ.key, 1, Int32(1)) :
               (integ.state, integ.p, integ.ctx, integ.key, 1)
        types = Tuple{typeof.(args)...}
        @test isempty(JET.get_reports(Base.invokelatest(JET.report_opt, fn, types; target_modules = (CorePotts, Potts))))
        @test isempty(Base.invokelatest(check_allocs, fn, types))
        if T === Float32
            @test _qa_float64_literals(ex) == 0
            @test !occursin(r"\bdouble\b", sprint((io, f, t) -> Base.invokelatest(code_llvm, io, f, t), fn, types))
        end
    end
end

# D-051 R0: no model- or author-named code in the core packages. Identifiers, macro names,
# symbols and non-doc strings are scanned (comments and docstrings may cite sources);
# identifiers are split on `_` and camel case. Exceptions live in `privileged_allow.txt`.
const _DENY = ["merks", "wortel", "niculescu", "graner", "glazier", "akeeb", "jiang", "bauer", "zajac",
    "starruss", "myxo", "fortuna", "osborne", "chaste", "artistoo", "openvt", "cc3d", "compucell", "morpheus",
    "savill", "hogeweg", "act", "leader", "follower", "endothelial", "tumor", "tumour", "vasculo", "angiogen",
    "keratocyte", "amoeboid"]
_tokens(s) = [lowercase(t) for t in split(s, r"[^A-Za-z0-9]+|(?<=[a-z])(?=[A-Z])") if !isempty(t)]
_denied(s) = [d for d in _DENY if any(t -> t == d || (length(d) > 4 && occursin(d, t)), _tokens(s))]

const JS = Base.JuliaSyntax
function _privileged_hits(file)
    root = JS.parseall(JS.SyntaxNode, read(file, String); filename = file)
    out = Tuple{Int, String}[]
    function walk(n, indoc)
        if JS.kind(n) == JS.K"doc"
            foreach(((i, c),) -> walk(c, i == 1), enumerate(JS.children(n)))
            return
        end
        indoc && return
        if JS.is_leaf(n) && JS.kind(n) in (JS.K"Identifier", JS.K"String", JS.K"MacroName")
            s = string(n.val)
            isempty(_denied(s)) || push!(out, (JS.source_location(n)[1], s))
        end
        JS.is_leaf(n) || foreach(c -> walk(c, false), JS.children(n))
    end
    walk(root, false)
    return out
end

@testset "QA: no model-named code in the core packages" begin
    root = joinpath(@__DIR__, "..")
    allow = Set(strip(first(split(l, "   #"))) for l in eachline(joinpath(@__DIR__, "privileged_allow.txt"))
                if !startswith(l, "#") && !isempty(strip(l)))
    bad = String[]
    for d in ("src", "lib/CorePotts/src", "lib/MakiePotts/src"), (dir, _, fs) in walkdir(joinpath(root, d)), f in fs
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

# P6.0j: ExplicitImports guardrails (CLAUDE.md code rules). Every name Potts uses is
# imported explicitly and by its owner. The allowlists name each non-public access the
# package genuinely needs; add to them only by review, with the reason.
using ExplicitImports: ExplicitImports, check_no_implicit_imports, check_all_explicit_imports_are_public,
    check_no_stale_explicit_imports, check_all_qualified_accesses_via_owners, check_all_qualified_accesses_are_public

# ExplicitImports analyses a package's loaded extensions with it: load DynamicQuantities
# so that `PottsDynamicQuantitiesExt` is always checked, whatever ran before.
using DynamicQuantities: DynamicQuantities

const POTTS_NONPUBLIC_QUALIFIED = (
    # --- Potts -> CorePotts internals. CorePotts is Potts's own numerical layer (same
    # monorepo, path source, co-versioned); the symbolic layer generates code against its
    # internal hooks.
    :AbstractBoundary,    # boundary supertype, dispatch in `layouts.jl`
    :RelationSpec,        # relation dispatch in the `Around` vocabulary
    :_run_phases,         # runs the `at_init` phases when a problem is initialised
    :_snapshot,           # host copy of a device state for the adaptive ODE phase
    :adjacency_name,      # field name of a relation's adjacency store
    :always,              # the no-constraint default
    :no_claims,           # the no-claim-set default
    :no_divide_rule,      # the no-division default
    :remake_frozen,       # `remake` hooks Potts extends for symbolic problems
    :remake_parameters,
    :remake_state,
    :set_parameter,       # parameter-update hook Potts extends
    :stream_id,           # named RNG stream for `draw` in generated code
    # --- Potts -> Base: no public equivalent
    Symbol("@__doc__"),   # attaching docstrings to macro-generated components
    :setindex,            # non-mutating tuple `setindex`
    # --- Potts -> Symbolics
    :rename,              # Symbolics.rename: renames a component system (`k.x` is `k₊x`)
    # --- PottsDynamicQuantitiesExt -> Potts: the extension is part of Potts and gives
    # Potts's own symbolic operators their unit rules, so it reads Potts internals.
    :at, :at2, :history_lag, :cell_integral, :Δ, :cell_centroid, :copy_displacement,
    :random_uniform, :gather, :population,   # operators whose `get_unit` rules it defines
    :_check_units,        # the unit-check hook `mtkcompile` calls, defined by the extension
    :_describe,           # statement labels for unit error messages
    # --- PottsDynamicQuantitiesExt -> MTK
    :get_unit,            # MTK's unit-inference function the extension extends; not public
    # --- Potts -> MTKBase: discrete components (P6.0k). The clock of a compiled discrete
    # system is only available as this variable metadata; no public accessor exists.
    :VariableTimeDomain,  # metadata key holding a discrete variable's clock
    :IntegerSequence,     # the clock of `ShiftIndex(t, 0)` (one tick per step, no period)
    # --- PottsModelingToolkitExt -> MTK/MTKBase (gap G1; checked only when the extension is
    # loaded): MTK's discrete-compilation hook and the MTKBase compiler it re-enters.
    :discrete_compile_pass, :with_reversible_transformation, :UnhackSystemTransformation,
    :__mtkcompile, :AbstractSystem,
)
# Names imported with `using M: x` that are not public in `M`.
const POTTS_NONPUBLIC_EXPLICIT = (
    :Split, :info,                # ext -> Potts internals (system splitting, model info)
    :get_unit, :ValidationError,  # ext -> MTK's unit-inference API; not declared public
)

@testset "QA: ExplicitImports (Potts)" begin
    @test check_no_implicit_imports(Potts) === nothing
    @test check_all_explicit_imports_are_public(Potts; ignore = POTTS_NONPUBLIC_EXPLICIT) === nothing
    @test check_no_stale_explicit_imports(Potts) === nothing
    @test check_all_qualified_accesses_via_owners(Potts) === nothing
    @test check_all_qualified_accesses_are_public(Potts; ignore = POTTS_NONPUBLIC_QUALIFIED) === nothing
end
