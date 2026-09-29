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
using PottsModels: GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTMonolayer, AkeebInvasion, akeeb_state,
    graner_glazier_state

const _QA_MOD = Module(:PottsQA)
Core.eval(_QA_MOD, :(using Potts; using Potts: CorePotts))

_qa_float64_literals(ex) = (n = Ref(0); _qa_walk(x -> x isa Float64 && (n[] += 1), ex); n[])
_qa_walk(f, x) = (f(x); x isa Expr && foreach(a -> _qa_walk(f, a), x.args))

@testset "QA: generated code of $label ($T)" for (label, make) in (
        ("Graner–Glazier", () -> (GranerGlazier(; name = :gg), (s = graner_glazier_state(); [ownership => s[1], kind => s[2]]), nothing)),
        ("Wortel", () -> (WortelAct(; name = :w), [ownership => (s = zeros(Int32, 8, 8); s[2:3, 2:3] .= 1; s[6:7, 6:7] .= 2; s),
            kind => [:endothelial, :endothelial]], nothing)),
        ("Merks", () -> (MerksVasculogenesis(; name = :m), [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s),
            kind => [:endothelial]], nothing)),
        ("OpenVT", () -> (OpenVTMonolayer(; name = :o), [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s),
            kind => [:epithelial]], nothing)),
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
