# Sources: D-159, D-160, D-162, D-164, D-165, D-170; research/mtk-native-plan.md §5, §6, §9.
# every ModelingToolkit claim the paper and the
# docs make, each checked against the code, and the wording itself checked against the docs.
# The point is that the claim can never drift from the code: if a sentence below stops being
# true, this file fails; if the docs (or an in-repo paper source) say more than is true, or
# stop saying what is approved, this file fails.
#
# The claims and their checks (public API only; one testset per claim):
#  C1. "Potts.jl is built on ModelingToolkit. Every Potts model is a ModelingToolkit
#      `AbstractSystem`" (D-137, D-159). `PottsSystem <: ModelingToolkitBase.AbstractSystem`;
#      every published model and the fixture is one and wraps a complete MTK `System`
#      (`Potts.inner(sys)`, D-256); none is itself a `ModelingToolkitBase.System`
#      (the forbidden "models are MTK `System`s").
#  C2. "... whose parameters, state variables, equations, observables ... are Symbolics
#      expressions that ModelingToolkit's generic tools can inspect and index" (plan §5; since
#      C4 "complete" holds through the complete System a model wraps, `Potts.inner(sys)`: MTK's
#      `complete` of the container itself is refused). On every published model MTK's own
#      `equations`, `unknowns`, `parameters`, `observed`, `nameof` work and return Symbolics
#      objects and equal the inner System's; `extend` merges two models;
#      SymbolicIndexingInterface `getu` (an observed algebraic variable included), `getp` and
#      `setp` work on a fixture's problem, solution and integrator.
#  C3. The Hamiltonian, drives and constraints are Symbolics expressions readable through
#      MTK's metadata API (D-160): `Potts.hamiltonian`, `Potts.drives`, the payload's
#      `constraints`, and `getmetadata(Potts.inner(sys), Potts.PottsSweepSpec,
#      nothing)` on every published model (authored and compiled); a plain `System` has no
#      payload (negative control).
#  C4. "The continuous parts of a model, its cell- and model-scale ODEs, are ModelingToolkit
#      systems compiled by `mtkcompile`; Potts.jl lowers the simplified equations into its
#      batched kernels" (D-165). `Potts.ode_system(csys, :cell | :model)` is a scheduled
#      `System` (MTK's mark of an `mtkcompile` result); the algebraic variables are its
#      `observed` equations and not unknowns; they are not stored in the problem's state
#      (Potts lowers the *simplified* system); the run matches the exact explicit-Euler
#      oracle in every cell. Negative control: the same alias in a plain `System` under
#      `complete` stays an unknown and is not scheduled.
#  C5. "Existing ModelingToolkit models plug in as components", compiled by `mtkcompile`,
#      clocked ones through MTK's discrete pass (plan §5, D-038, `boolean_network_tests.jl`). A continuous
#      component's alias is eliminated (only `mtkcompile`'s unknowns become cell variables)
#      and the component runs as its Euler oracle; a `ShiftIndex` Boolean network ticks as
#      its hand recurrence.
#  C6. "update rules", not events (D-162, D-164). `Potts.updates(sys)` lists each update as a
#      Symbolics `Equation` in MTK's `Pre` form; `ModelingToolkitBase.discrete_events` and
#      `continuous_events` of `Potts.inner(sys)` are empty on every published model and the fixture, so
#      nothing may claim that events are MTK callbacks or compiled by MTK.
#  C7. "Entity-local initialization equations are ModelingToolkit initialization systems,
#      solved per cell by MTK's `InitializationProblem`" (D-170).
#      `Potts.initialization_system(csys, :cell)` is a complete `System` whose
#      `initialization_equations` are the authored ones; the per-cell values Potts puts in
#      `u0` equal, cell by cell, what MTK's own `InitializationProblem` of that system gives
#      with the cell's inputs (oracle 2: the hand value √volume), and differ between cells of
#      different volume.
#  C8. Fields are not compiled by MTK (D-165; D-159 did not adopt MTK field compilation). A field PDE is
#      listed by MTK's `equations`, but no `ode_system` or `initialization_system` holds the
#      field variable, `ode_system(csys, :field)` is an `ArgumentError`, and Merks (field PDEs
#      only) has no ODE system in either scope.
#  C9. "The stochastic lattice dynamics ... are compiled from the symbolic Hamiltonian by
#      Potts.jl's own code generator" (plan §5): `mtkcompile` of a `PottsSystem` is Potts'
#      method and returns a `CompiledPottsSystem` (not an MTK `System`); MTK's `ODEProblem`
#      and `JumpProblem` refuse every published model, plain and compiled, naming
#      `PottsProblem` (D-137 rule 5: the forbidden "MTK simulates the CPM").
#  W.  Wording. In the docs (`docs/src/**/*.md`; and in a paper source, `paper/` or
#      `docs/paper/`, if one is in the repo) each approved sentence appears (whitespace-
#      normalized); and in everything a reader sees (`docs/` except `docs/design/`, the
#      READMEs, and the docstrings and comments of `src/`, `ext/` and `lib/*/src/`) no
#      forbidden claim appears. The design notes (`docs/design/`) quote the forbidden
#      phrases on purpose and are not scanned.
#  N.  Negative controls: each forbidden pattern matches the sentence it was written against
#      (from D-159, D-162 and plan §5) and none matches the true sentences the docs use; each
#      approved pattern matches its decision's sentence and not a weakened one.
#
# On 07757b51 (the Hamiltonian metadata, initialization and update-rule work merged; Mac): 821 pass and 8 fail of 829. Every C, N and
# forbidden-wording check passes; the 8 failures are the W approved sentences, which no docs
# page carries yet (there is no "Relation to ModelingToolkit" page: plan §6), and
# writing it is the implementer's work. A stub page with the eight sentences passes 829/829;
# adding "the fields are compiled by MTK" to it fails exactly that pattern. No check here may
# be weakened to make the code pass (D-156).

@testsetup module ModelingToolkitClaimsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "fixtures.jl"))
using Potts: CorePotts
const CLAIMS_M = Potts.ModelingToolkitBase
const CLAIMS_S = Potts.Symbolics
const SII = Potts.SymbolicIndexingInterface
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
claims_name(x) = SII.getname(x)
claims_names(xs) = Set{Symbol}(claims_name(x) for x in xs)
byname(xs, n) = only(x for x in xs if claims_name(x) === n)
claims_symbolic(e) = CLAIMS_S.unwrap(e) isa Potts.SymbolicUtils.BasicSymbolic
clear(f, words...) = try
    f()
    false
catch err
    ok = err isa ArgumentError && (isempty(words) || occursin(first(words), sprint(showerror, err)))
    ok || @info "expected an ArgumentError" exception = err
    ok
end
# ---------------------------------------------------------------------------------------
# Fixtures

# a continuous MTK component with an algebraic alias (only `mtkcompile` removes `yal`)
const CLAIMS_DC = let t = Potts.t
    CLAIMS_M.@variables y(t) = 1.0 yal(t)
    CLAIMS_M.@parameters kc = 0.1
    CLAIMS_M.System([Potts.D(y) ~ -kc * yal, yal ~ y], t; name = :dc)
end
# a clocked Boolean network (the docs' tutorial 5 network, with the input fixed on)
const GRN = let t = Potts.t, k = CLAIMS_M.ShiftIndex(Potts.t, 0)
    CLAIMS_M.@variables A(t)::Bool = false B(t)::Bool = true
    CLAIMS_M.@parameters on::Bool = true
    CLAIMS_M.System([A(k) ~ on & !B(k - 1), B(k) ~ A(k - 1)], t; name = :grn)
end
# every construct a claim is about, in one model: cell and model ODEs with algebraic
# variables, a field PDE, an update, an initialization equation, two components
# the field `c`, a plain MTK PDESystem coupled with `@fields`
function field_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y Dc = 0.1
    Potts.ModelingToolkitBase.@variables c(..)
    C = c(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem(
        [Potts.D(C) ~ Dc * L.laplacian(C) - 0.1 * C], [c(0, x, y) ~ 0.0],
        L.lattice_domain(t, (x, y), (12, 8)), [t, x, y], [C], [Dc]; name = :claims_field
    )
end
@potts_model All begin
    @kinds medium A
    @parameters begin
        k = 0.1
        r = 0.2
    end
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
        m(model) = 0.0
        gap(model) = 0.0
        acc(cell) = 0.0
    end
    @components cells(A) dc = CLAIMS_DC
    @components cells(A) grn = GRN
    @lattice Lattice((12, 8))
    @fields field_pde()
    @variables rt(cell), [guess = 1.0]
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -k * xalias
        xalias ~ x
        D(m) ~ r * gap
        gap ~ 1 - m
    end
    @initialization_equations rt^2 ~ volume
    @after_mcs acc ~ Pre(acc) + xalias
    @sweep Metropolis(; temperature = 1.0)
end
# for `extend`
@potts_model Extra begin
    @kinds medium A
    @parameters κ = 0.75
    @lattice Lattice((12, 8))
    @energy cells => κ * volume
    @sweep Metropolis(; temperature = 1.0)
end
# two cells: 16 sites (id 1) and 12 sites (id 2)
const Claimsσ = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:5] .= 2; s)
const CLAIMS_N = 5
claims_prob() = PottsProblem(
    All(; name = :all), [ownership => Claimsσ, kind => [:A, :A]], (0, CLAIMS_N);
    seed = 3, field_solver = ExplicitEuler(substeps = 2)
)
# every published model (construction only)
const MODELS = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg)),
    ("WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8))),
    ("WortelAct connected", () -> WortelAct(; name = :act, lattice = (8, 8), connected = true)),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8))),
    (
        "MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true),
    ),
    ("Merks2006", () -> Merks2006(; name = :m6, lattice = (16, 16))),
    ("Merks2006 hard", () -> Merks2006(; name = :m6, lattice = (16, 16), rule = :hard)),
    ("Merks2008", () -> Merks2008(; name = :m8, lattice = (16, 16))),
    ("Merks2008 extension only", () -> Merks2008(; name = :m8, lattice = (16, 16), mode = :extension_only)),
    ("SingleDivisionFixture", () -> SingleDivisionFixture(; name = :fixture)),
    ("OpenVTGrowingMonolayer", () -> OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24))),
    ("AkeebInvasion", () -> AkeebInvasion(; name = :akeeb, lattice = (60, 40))),
    ("OpenVTChain", () -> OpenVTChain(; name = :chain)),
    ("OpenVTReferenceMonolayer", () -> OpenVTReferenceMonolayer(; name = :ref, lattice = (24, 24))),
]
const ALL = [MODELS; ("All fixture", () -> All(; name = :all))]
# ---------------------------------------------------------------------------------------
# W. Wording: approved sentences present, forbidden claims absent
claims_norm(s) = replace(s, r"\s+" => " ")
claims_files(dir, exts) = isdir(dir) ? String[joinpath(r, f) for (r, _, fs) in walkdir(dir) for f in fs if any(e -> endswith(f, e), exts)] : String[]
# The approved sentences (D-159 / plan §5 as amended by D-162, D-165, D-170). Each must
# appear in the docs (and in an in-repo paper source), whitespace-normalized.
const APPROVED = [
    ("built on ModelingToolkit (D-159)", r"Potts\.jl is built on ModelingToolkit"),
    (
        "every model an AbstractSystem (D-137, D-159)",
        r"[Ee]very Potts model is a(?:n MTK| ModelingToolkit)(?: system:? an)? `AbstractSystem`",
    ),
    ("Hamiltonian as Symbolics (D-160)", r"Hamiltonian are Symbolics expressions that ModelingToolkit's generic tools can inspect"),
    (
        "ODEs through mtkcompile (D-165)",
        r"The continuous parts of a model, its cell- and model-scale ODEs, are ModelingToolkit systems compiled by `mtkcompile`; Potts\.jl lowers the simplified equations into its batched kernels",
    ),
    ("components (plan §5)", r"ModelingToolkit models plug in as components"),
    ("update rules (D-162)", r"update rules are Symbolics equations in ModelingToolkit's `Pre` form"),
    (
        "initialization (D-170)",
        r"Entity-local initialization equations are ModelingToolkit initialization systems, solved per cell by MTK's `InitializationProblem`",
    ),
    ("the sweep is Potts.jl's (plan §5)", r"compiled from the symbolic Hamiltonian by Potts\.jl's own code generator"),
]
# The forbidden claims (D-159 "do not claim", D-162, D-165, plan §5). Case-insensitive.
const FORBIDDEN = [
    ("fully MTK-native (D-159)", r"fully (?:MTK|ModelingToolkit)[- ]native"i),
    ("native as a whole (D-159)", r"(?:MTK|ModelingToolkit)[- ]native as a whole"i),
    ("events compiled by MTK (D-162)", r"events,? (?:are )?compiled by (?:MTK|ModelingToolkit|`?mtkcompile`?)"i),
    ("event parts (D-159 superseded by D-162)", r"\bevent parts\b"i),
    ("events in the Symbolics list (plan §5 superseded by D-162)", r"\bevents,? and (?:the )?Hamiltonian"i),
    (
        "events as MTK callbacks before symbolic events (D-162)",
        r"events (?:are|as) (?:MTK|ModelingToolkit)(?:'s)? `?Symbolic(?:Discrete|Continuous)Callback"i,
    ),
    (
        "fields compiled by MTK (D-165)",
        r"\bfields? (?:are |is )?(?:compiled|simulated|solved|integrated|stepped|discretized) by (?:MTK|ModelingToolkit|`?mtkcompile`?)"i,
    ),
    # "fields are written as `PDESystem`s" was forbidden here (MTK field compilation not adopted, D-159); it is
    # true under the field front-end ruling and is allowed. The rule above, that MTK
    # does not compile, solve or step the fields, stays.
    (
        "MTK simulates the CPM (D-159)",
        r"(?:MTK|ModelingToolkit) (?:compiles|simulates|runs|solves) the (?:CPM|lattice|sweep|cellular Potts|Potts model)"i,
    ),
    (
        "models are MTK Systems (D-159)",
        r"(?:Potts(?:\.jl)? models?|every (?:Potts )?model) (?:is|are) (?:an? )?(?:MTK|ModelingToolkit) `System`"i,
    ),
]
# where a reader sees text: the docs (not the design notes), the READMEs, and source
# docstrings and comments
function reader_files()
    files = String[]
    docs = joinpath(ROOT, "docs")
    for f in claims_files(docs, (".md", ".jl"))
        startswith(f, joinpath(docs, "design")) && continue
        push!(files, f)
    end
    libs = readdir(joinpath(ROOT, "lib"))
    readmes = vcat(joinpath(ROOT, "README.md"), [joinpath(ROOT, "lib", d, "README.md") for d in libs])
    append!(files, filter(isfile, readmes))
    srcs = vcat(joinpath(ROOT, "src"), joinpath(ROOT, "ext"), [joinpath(ROOT, "lib", d, "src") for d in libs])
    for d in srcs
        append!(files, claims_files(d, (".jl",)))
    end
    for d in ("paper", joinpath("docs", "paper"))
        append!(files, claims_files(joinpath(ROOT, d), (".md", ".tex", ".jl", ".txt")))
    end
    return unique(files)
end
const DOCS_SRC = joinpath(ROOT, "docs", "src")
const PAPER_DIRS = filter(isdir, [joinpath(ROOT, "paper"), joinpath(ROOT, "docs", "paper")])
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "modelingtoolkit claims C1: every Potts model is a ModelingToolkit AbstractSystem, not a System" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C1. Built on ModelingToolkit: every model is an MTK `AbstractSystem`, not a `System`
    @testset "modelingtoolkit claims C1: every Potts model is a ModelingToolkit AbstractSystem, not a System" begin
        @test PottsSystem <: CLAIMS_M.AbstractSystem
        @test !(PottsSystem <: CLAIMS_M.System)
        @testset "$label" for (label, build) in ALL
            sys = build()
            @test sys isa CLAIMS_M.AbstractSystem && sys isa PottsSystem
            @test !(sys isa CLAIMS_M.System)
            cs = Potts.inner(sys)
            @test cs isa CLAIMS_M.System && CLAIMS_M.iscomplete(cs)
        end
        # control: an MTK System is both, so the detector can tell them apart
        @test CLAIMS_DC isa CLAIMS_M.System && CLAIMS_DC isa CLAIMS_M.AbstractSystem
    end
end

@testitem "modelingtoolkit claims C2: MTK's generic accessors on every published model" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C2. MTK's generic tools inspect and index a Potts model (and complete its inner System)
    @testset "modelingtoolkit claims C2: MTK's generic accessors on every published model" begin
        @testset "$label" for (label, build) in ALL
            sys = build()
            @test CLAIMS_M.equations(sys) isa AbstractVector{<:CLAIMS_S.Equation}
            @test CLAIMS_M.observed(sys) isa AbstractVector{<:CLAIMS_S.Equation}
            u = CLAIMS_M.unknowns(sys)
            p = CLAIMS_M.parameters(sys)
            @test !isempty(p) || !isempty(u)
            @test all(claims_symbolic, u) && all(claims_symbolic, p)
            @test nameof(sys) isa Symbol
            @test claims_names(CLAIMS_M.unknowns(Potts.inner(sys))) == claims_names(u)
            @test claims_names(CLAIMS_M.parameters(Potts.inner(sys))) == claims_names(p)
        end
        sys = All(; name = :all)
        @test Set([:x, :xalias, :m, :gap, :acc, :rt]) ⊆ claims_names(CLAIMS_M.unknowns(sys))
        # the field `c` is in the PDESystem, not among the System's unknowns; `sys.c` names it
        @test !(:c in claims_names(CLAIMS_M.unknowns(sys))) && Potts.info(sys.c).name === :c
        @test Set([:k, :r, :Dc]) ⊆ claims_names(CLAIMS_M.parameters(sys))
        # `extend` merges two models
        ext = extend(Extra(; name = :extra), sys)
        @test ext isa PottsSystem
        @test :κ in claims_names(CLAIMS_M.parameters(ext)) && :k in claims_names(CLAIMS_M.parameters(ext))
        @test length(Potts.hamiltonian(ext)) == 2
    end
end

@testitem "modelingtoolkit claims C2: SymbolicIndexingInterface on a problem, a solution and an integrator" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "modelingtoolkit claims C2: SymbolicIndexingInterface on a problem, a solution and an integrator" begin
        prob = claims_prob()
        @test SII.getp(prob, :k)(prob) == 0.1
        sol = solve(prob, SequentialCPM(); saveat = 1)
        xs = SII.getu(sol, :x)(sol)
        @test length(xs) == CLAIMS_N + 1 && all(v -> length(v) == 2, xs)
        # an observed (algebraic) variable is indexed like a stored one
        @test SII.getu(sol, :xalias)(sol) == xs
        @test sol[:xalias] == sol[:x]
        integ = Potts.SciMLBase.init(prob, SequentialCPM())
        SII.setp(integ, :k)(integ, 0.3)
        @test SII.getp(integ, :k)(integ) == 0.3
    end
end

@testitem "modelingtoolkit claims C3: hamiltonian, drives, constraints and PottsSweepSpec metadata" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C3. The Hamiltonian as Symbolics expressions, read through MTK's metadata API
    @testset "modelingtoolkit claims C3: hamiltonian, drives, constraints and PottsSweepSpec metadata" begin
        @testset "$label" for (label, build) in ALL
            sys = build()
            H = Potts.hamiltonian(sys)
            @test H isa AbstractVector && !isempty(H)
            @test all(t -> t isa Pair && claims_symbolic(last(t)), H)
            @test all(claims_symbolic, Potts.drives(sys))
            @test CLAIMS_M.getmetadata(Potts.inner(sys), Potts.PottsSweepSpec, nothing).constraints isa AbstractVector
            for s in (Potts.inner(sys), mtkcompile(sys), Potts.inner(getfield(mtkcompile(sys), :sys)))
                @test CLAIMS_M.hasmetadata(s, Potts.PottsSweepSpec)
                spec = CLAIMS_M.getmetadata(s, Potts.PottsSweepSpec, nothing)
                @test spec isa Potts.PottsSweepSpec
                @test length(spec.hamiltonian) == length(H)
                @test all(isequal(last(a), last(b)) for (a, b) in zip(spec.hamiltonian, H))
            end
        end
        sys = All(; name = :all)
        @test claims_names(CLAIMS_S.get_variables(last(only(Potts.hamiltonian(sys))))) == Set([:volume])
        # N: a plain MTK System carries no sweep payload
        @test !CLAIMS_M.hasmetadata(CLAIMS_DC, Potts.PottsSweepSpec)
        @test CLAIMS_M.getmetadata(CLAIMS_DC, Potts.PottsSweepSpec, nothing) === nothing
        @test !CLAIMS_M.hasmetadata(CLAIMS_M.mtkcompile(CLAIMS_DC), Potts.PottsSweepSpec)
    end
end

@testitem "modelingtoolkit claims C4: cell and model ODEs through mtkcompile" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C4. Cell and model ODEs are MTK systems compiled by `mtkcompile`; Potts lowers the result
    @testset "modelingtoolkit claims C4: cell and model ODEs through mtkcompile" begin
        cs = mtkcompile(All(; name = :all))
        for (scope, diff, alg, par) in ((:cell, :x, :xalias, :k), (:model, :m, :gap, :r))
            o = Potts.ode_system(cs, scope)
            @test o isa CLAIMS_M.System
            @test CLAIMS_M.iscomplete(o) && CLAIMS_M.isscheduled(o)   # an `mtkcompile` result
            @test claims_names(CLAIMS_M.unknowns(o)) == Set([diff])
            @test alg in claims_names(o.lhs for o in CLAIMS_M.observed(o))
            @test !(alg in claims_names(CLAIMS_M.unknowns(o)))
            @test par in claims_names(CLAIMS_M.parameters(o))
            @test length(CLAIMS_M.equations(o)) == 1
        end
        # Potts lowers the simplified system: the eliminated variables are not stored
        prob = claims_prob()
        @test :x in propertynames(prob.u0.cell) && !(:xalias in propertynames(prob.u0.cell))
        @test :m in propertynames(prob.u0.model) && !(:gap in propertynames(prob.u0.model))
        # and the run is the exact explicit-Euler oracle in every cell: x₀·0.9^N, 1 − 0.8^N
        sol = solve(prob, SequentialCPM(); saveat = 1)
        @test all(n -> isapprox(sol[:x][n + 1], fill(2.0 * 0.9^n, 2); rtol = 1.0e-12), 0:CLAIMS_N)
        @test all(n -> isapprox(sol[:m][n + 1], 1 - 0.8^n; rtol = 1.0e-12, atol = 1.0e-15), 0:CLAIMS_N)
        # N: the oracle can fail (a wrong rate does not match)
        @test !isapprox(sol[:x][end], fill(2.0 * 0.8^CLAIMS_N, 2); rtol = 1.0e-6)
        # N: the scheduled detector can fail: `complete` alone keeps the alias and is not scheduled
        plain = CLAIMS_M.complete(CLAIMS_DC)
        @test !CLAIMS_M.isscheduled(plain) && :yal in claims_names(CLAIMS_M.unknowns(plain))
        @test CLAIMS_M.isscheduled(CLAIMS_M.mtkcompile(CLAIMS_DC))
        # an uncompiled model has no ODE system (the message names mtkcompile)
        @test clear(() -> Potts.ode_system(All(; name = :all), :cell), "mtkcompile")
    end
end

@testitem "modelingtoolkit claims C5: components, continuous and clocked" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C5. MTK models plug in as components, compiled by `mtkcompile` (continuous and clocked)
    @testset "modelingtoolkit claims C5: components, continuous and clocked" begin
        prob = claims_prob()
        names = propertynames(prob.u0.cell)
        # only `mtkcompile(dc)`'s unknowns become cell variables: the alias `yal` is eliminated
        @test claims_names(CLAIMS_M.unknowns(CLAIMS_M.mtkcompile(CLAIMS_DC))) == Set([:y])
        @test :dc₊y in names && !(:dc₊yal in names)
        @test Set([:grn₊A, :grn₊B]) ⊆ Set(names)
        sol = solve(prob, SequentialCPM(); saveat = 1)
        # the continuous component: y₀·(1 − kc)^N under explicit Euler
        @test all(n -> isapprox(sol[:dc₊y][n + 1], fill(0.9^n, 2); rtol = 1.0e-12), 0:CLAIMS_N)
        # the clocked network: Aₙ = on ∧ ¬Bₙ₋₁, Bₙ = Aₙ₋₁, one tick per MCS (hand recurrence)
        A, B = false, true
        want = [(A, B)]
        for _ in 1:CLAIMS_N
            A, B = true & !B, A
            push!(want, (A, B))
        end
        @test [Bool.(a) for a in sol[:grn₊A]] == [fill(w[1], 2) for w in want]
        @test [Bool.(b) for b in sol[:grn₊B]] == [fill(w[2], 2) for w in want]
        @test any(w -> w[1], want) && any(w -> !w[1], want)       # N: the sequence is not constant
        # the equations of both components are listed by MTK's `equations`, namespaced
        eqnames = string.(CLAIMS_M.equations(All(; name = :all)))
        @test any(e -> occursin("dc₊y", e), eqnames) && any(e -> occursin("grn₊A", e), eqnames)
    end
end

@testitem "modelingtoolkit claims C6: update rules, not events" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C6. Update rules in MTK's `Pre` form; no event callbacks
    @testset "modelingtoolkit claims C6: update rules, not events" begin
        sys = All(; name = :all)
        for s in (sys, mtkcompile(sys))
            us = Potts.updates(s)
            @test length(us) == 1
            u = only(us)
            @test u.phase === :after_mcs && u.scope === :cell && u.every == Potts.Every(1)
            @test u.eq isa CLAIMS_S.Equation
            @test claims_name(u.eq.lhs) === :acc
            r = CLAIMS_S.unwrap(u.eq.rhs)
            # `Pre(acc)` appears in MTK's own operator
            found = Ref(false)
            walk(e) = (
                Potts.SymbolicUtils.iscall(e) &&
                    (
                    Potts.SymbolicUtils.operation(e) isa CLAIMS_M.Pre && (found[] = true);
                    foreach(walk, Potts.SymbolicUtils.arguments(e))
                ); nothing
            )
            walk(r)
            @test found[]
        end
        @testset "$label" for (label, build) in ALL
            s = build()
            @test Potts.updates(s) isa AbstractVector
            @test all(u -> u.eq isa CLAIMS_S.Equation, Potts.updates(s))
            @test isempty(CLAIMS_M.discrete_events(Potts.inner(s)))
            @test isempty(CLAIMS_M.continuous_events(Potts.inner(s)))
        end
    end
end

@testitem "modelingtoolkit claims C7: initialization through InitializationProblem, per cell" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C7. Entity-local initialization: MTK initialization systems, solved per cell by MTK's
    # `InitializationProblem`
    @testset "modelingtoolkit claims C7: initialization through InitializationProblem, per cell" begin
        cs = mtkcompile(All(; name = :all))
        isys = Potts.initialization_system(cs, :cell)
        @test isys isa CLAIMS_M.System && CLAIMS_M.iscomplete(isys)
        ieqs = CLAIMS_M.initialization_equations(isys)
        @test length(ieqs) == 1
        @test :rt in claims_names(CLAIMS_M.unknowns(isys))
        @test Potts.initialization_system(cs, :model) === nothing
        # Potts' per-cell values
        prob = claims_prob()
        vol = [16.0, 12.0]
        got = Vector{Float64}(Array(prob.u0.cell.rt))
        @test isapprox(got, sqrt.(vol); rtol = 1.0e-9)                 # oracle 2: by hand
        @test got[1] != got[2]                                      # per cell, not one value
        # oracle 1: MTK's own InitializationProblem of the same system, given each cell's input
        rt = byname(CLAIMS_M.unknowns(isys), :rt)
        inputs = CLAIMS_M.parameters(isys)
        @test length(inputs) == 1                                   # the cell's volume
        for (i, V) in enumerate(vol)
            ip = CLAIMS_M.InitializationProblem(isys, 0.0, Dict(only(inputs) => V); guesses = Dict(rt => 1.0))
            s = Potts.SciMLBase.solve(ip, Potts.SimpleNonlinearSolve.SimpleNewtonRaphson())
            @test Potts.SciMLBase.successful_retcode(s)
            @test isapprox(s[rt], got[i]; rtol = 1.0e-9)
        end
        # N: a plain System lists no initialization equations, so the detector can fail
        @test isempty(CLAIMS_M.initialization_equations(CLAIMS_DC))
        @test clear(() -> Potts.initialization_system(All(; name = :all), :cell), "mtkcompile")
    end
end

@testitem "modelingtoolkit claims C8: fields are Potts' own step, not MTK systems" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C8. Fields are not compiled by MTK
    @testset "modelingtoolkit claims C8: fields are Potts' own step, not MTK systems" begin
        sys = All(; name = :all)
        # the field PDE is an equation of the model's PDESystem (`Potts.fields`), not of the System
        # MTK's `equations` reads (a System has one independent variable) ...
        @test any(e -> claims_symbolic(e.lhs) && occursin("c(t", string(e.lhs)), CLAIMS_M.equations(Potts.fields(sys)))
        @test !any(e -> occursin("c(t", string(e.lhs)), CLAIMS_M.equations(sys))
        cs = mtkcompile(sys)
        # ... but no MTK system Potts builds holds the field variable
        for scope in (:cell, :model)
            o = Potts.ode_system(cs, scope)
            @test !(:c in claims_names(CLAIMS_M.unknowns(o)))
            @test !(:c in claims_names(CLAIMS_M.parameters(o)))
            @test !any(e -> occursin("Δ", string(e)), CLAIMS_M.equations(o))
        end
        @test !(:c in claims_names(CLAIMS_M.unknowns(Potts.initialization_system(cs, :cell))))
        @test clear(() -> Potts.ode_system(cs, :field), "field")
        @test clear(() -> Potts.ode_system(cs, :site))
        # Merks: field PDEs only, so no ODE system in either scope
        for build in (() -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)), () -> Merks2006(; name = :m6, lattice = (16, 16)))
            s = build()
            @test any(e -> occursin("laplacian", string(e)), CLAIMS_M.equations(Potts.fields(s)))
            c = mtkcompile(s)
            @test Potts.ode_system(c, :cell) === nothing && Potts.ode_system(c, :model) === nothing
        end
    end
end

@testitem "modelingtoolkit claims C9: the sweep is Potts.jl's; ODEProblem and JumpProblem refuse" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # C9. The lattice sweep is compiled by Potts.jl, not simulated by MTK
    @testset "modelingtoolkit claims C9: the sweep is Potts.jl's; ODEProblem and JumpProblem refuse" begin
        @test which(CLAIMS_M.mtkcompile, Tuple{PottsSystem}).module === Potts
        @testset "$label" for (label, build) in ALL
            sys = build()
            c = mtkcompile(sys)
            @test c isa CompiledPottsSystem && !(c isa CLAIMS_M.System)
            for s in (sys, c)
                @test clear(() -> CLAIMS_M.ODEProblem(s, [], (0.0, 1.0)), "PottsProblem")
                @test clear(() -> CLAIMS_M.JumpProblem(s, [], (0.0, 1.0)), "PottsProblem")
            end
        end
        # N: the refusal detector passes on a real MTK problem (it can fail)
        @test !clear(() -> CLAIMS_M.ODEProblem(CLAIMS_M.mtkcompile(CLAIMS_DC), [], (0.0, 1.0)), "PottsProblem")
    end
end

@testitem "modelingtoolkit claims W: the docs carry each approved sentence" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "modelingtoolkit claims W: the docs carry each approved sentence" begin
        docs = join((claims_norm(read(f, String)) for f in claims_files(DOCS_SRC, (".md",))), " ")
        @test !isempty(docs)
        @testset "$label" for (label, re) in APPROVED
            ok = occursin(re, docs)
            ok || @info "modelingtoolkit claims W: no docs page under docs/src says: $(re.pattern)"
            @test ok
        end
        # an in-repo paper source, if there is one, carries them too
        for d in PAPER_DIRS
            paper = join((claims_norm(read(f, String)) for f in claims_files(d, (".md", ".tex", ".txt"))), " ")
            @testset "paper ($d): $label" for (label, re) in APPROVED
                @test occursin(re, paper)
            end
        end
    end
end

@testitem "modelingtoolkit claims W: no forbidden claim where a reader sees it" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "modelingtoolkit claims W: no forbidden claim where a reader sees it" begin
        files = reader_files()
        @test length(files) > 20
        @test any(f -> startswith(f, DOCS_SRC), files) && any(f -> endswith(f, joinpath("src", "odes.jl")), files)
        @test !any(f -> occursin(joinpath("docs", "design"), f), files)
        @testset "$label" for (label, re) in FORBIDDEN
            hits = String[]
            for f in files
                for m in eachmatch(re, claims_norm(read(f, String)))
                    push!(hits, "$(relpath(f, ROOT)): \"$(m.match)\"")
                end
            end
            isempty(hits) || @info "modelingtoolkit claims W: forbidden claim ($label)" hits
            @test isempty(hits)
        end
    end
end

@testitem "modelingtoolkit claims N: the wording patterns catch what they are for, and nothing true" setup = [ModelingToolkitClaimsSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # N. Controls for the wording patterns
    @testset "modelingtoolkit claims N: the wording patterns catch what they are for, and nothing true" begin
        bad = [
            "fully MTK-native" => 1,
            "Potts.jl is fully ModelingToolkit-native." => 1,
            "MTK-native as a whole" => 2,
            "its events are compiled by MTK" => 3,
            "Events compiled by `mtkcompile`" => 3,
            # D-159's ruling before D-162 amended it
            "its ODE, initialization and event parts are compiled by MTK" => 4,
            # plan §5 before D-162
            "whose parameters, state variables, equations, observables, events and Hamiltonian are Symbolics expressions" => 5,
            "its events are MTK `SymbolicDiscreteCallback`s" => 6,
            "fields are compiled by MTK" => 7,
            "the field is solved by ModelingToolkit" => 7,
            # the field front-end ruling: a field written as a `PDESystem` is still not stepped by MTK
            "The fields are written as `PDESystem`s; the fields are stepped by ModelingToolkit." => 7,
            "ModelingToolkit compiles the CPM" => 8,
            "MTK simulates the lattice" => 8,
            "Potts.jl models are ModelingToolkit `System`s" => 9,
            "Every model is an MTK `System`" => 9,
        ]
        for (s, i) in bad
            @test occursin(FORBIDDEN[i][2], claims_norm(s))
        end
        good = [
            "Potts compiles and runs these rules in its sweep; they are not ModelingToolkit events, so `ModelingToolkitBase.discrete_events(sys)` is empty.",
            "route A2 of the MTK-native plan",
            "Fields are not compiled by MTK.",
            "field equations are stepped by Potts on the lattice and are not an ODE system",
            # the field front-end ruling: true now, so allowed
            "and diffusing fields are written as ModelingToolkit `PDESystem`s",
            "The cell equations of a model are one ModelingToolkit `System`, the template of one cell",
            "Every Potts model is a ModelingToolkit system: an `AbstractSystem` whose parameters",
            "A model's cell and model ODEs are ModelingToolkit systems compiled by `mtkcompile`.",
            "It returns the `ModelingToolkitBase.System` that `mtkcompile` produced",
            "Potts.jl is built on ModelingToolkit.",
            "MakiePotts v0.3 turns explicit Potts observations into native Makie recipes.",
        ]
        for s in good, (label, re) in FORBIDDEN
            @test !occursin(re, claims_norm(s))
        end
        # the approved patterns match their decisions' sentences, across a line wrap ...
        src = [
            "Potts.jl is built on\nModelingToolkit.",
            "Every Potts model is a ModelingToolkit system: an `AbstractSystem` whose",
            "observables, update rules and Hamiltonian are Symbolics expressions that ModelingToolkit's generic tools can inspect",
            "The continuous parts of a model, its cell- and model-scale ODEs, are ModelingToolkit systems compiled by\n`mtkcompile`; Potts.jl lowers the simplified equations into its batched kernels.",
            "existing ModelingToolkit models plug in as components",
            "A model's update rules are Symbolics equations in ModelingToolkit's `Pre` form that MTK's generic tools can inspect.",
            "Entity-local initialization equations are ModelingToolkit initialization systems, solved per cell by MTK's `InitializationProblem`.",
            "are compiled from the symbolic Hamiltonian by Potts.jl's own code generator into fused CPU and GPU kernels",
        ]
        for ((label, re), s) in zip(APPROVED, src)
            @test occursin(re, claims_norm(s))
        end
        # ... and not weakened ones
        weak = [
            "Potts.jl follows the conventions of ModelingToolkit.",
            "Every Potts model is a ModelingToolkit `System`",
            "Hamiltonian is a Julia expression",
            "The continuous parts of a model, its cell- and model-scale ODEs, are lowered by Potts.jl into its batched kernels",
            "ModelingToolkit models can be translated into components",
            "update rules are Julia closures",
            "Entity-local initialization equations are solved by Potts",
            "compiled from the symbolic Hamiltonian by ModelingToolkit",
        ]
        for ((label, re), s) in zip(APPROVED, weak)
            @test !occursin(re, claims_norm(s))
        end
    end
end
