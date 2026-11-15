# Direct determinism properties (TS-R2 §5):
# D1 same-session fingerprints and CPU solves, D2 fresh subprocess parity,
# D3 model definition order (A,B vs B,A + unrelated model), and
# D5 structural scan for objectid / hex-address / gensym / build-path leaks.

@testsetup module DetSetup
using Potts, PottsModels, Test
using Potts: CorePotts
include(joinpath(@__DIR__, "shared", "props.jl"))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "determinism D1: same-session fingerprints and CPU solves" setup = [DetSetup] tags = [:potts, :determinism] begin
@testset "determinism D1: same-session fingerprints and CPU solves" begin
    two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
    cases = (
        ("GranerGlazier", () -> (s = graner_glazier_state();
            PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 5); seed = 11))),
        ("WortelAct", () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)),
            [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 5); seed = 11)),
        ("MerksVasculogenesis", () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
            [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 5);
            seed = 11, field_solver = ExplicitEuler(substeps = 2, lower = 0.0))),
        ("OpenVTGrowingMonolayer", () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
            openvt_monolayer_state(; lattice = (24, 24)), (0, 5); capacity = 64, seed = 11)),
    )
    for (label, build) in cases
        p1 = build()
        p2 = build()
        @test p1.f.fingerprint == p2.f.fingerprint
        for alg in (SequentialCPM(), CheckerboardCPM())
            s1 = solve(p1, alg; save_start = false)
            s2 = solve(p2, alg; save_start = false)
            u1, u2 = s1.u[end], s2.u[end]
            @test u1.σ == u2.σ
            for col in propertynames(u1.cell)
                @test getproperty(u1.cell, col) == getproperty(u2.cell, col)
            end
        end
    end
end
end

@testitem "determinism D2 & D3: fresh subprocess and model definition order" setup = [DetSetup] tags = [:potts, :determinism, :subprocess] begin
@testset "determinism D2 & D3: fresh subprocess and model definition order" begin
    proj = @__DIR__
    s_gg = graner_glazier_state()
    p_gg = PottsProblem(GranerGlazier(; name = :gg), [ownership => s_gg[1], kind => s_gg[2]], (0, 3); seed = 5)
    sol_gg = solve(p_gg, SequentialCPM(); save_start = false)
    parent_gg_fp = p_gg.f.fingerprint
    parent_gg_digest = hash(sol_gg.u[end].σ)

    # D2: fresh subprocess computes identical fingerprint and CPU run digest
    d2_code = """
    using Potts, PottsModels
    s = graner_glazier_state()
    p = PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 3); seed = 5)
    sol = solve(p, SequentialCPM(); save_start = false)
    println(repr(p.f.fingerprint), " ", repr(hash(sol.u[end].σ)))
    """
    out = strip(read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -e $d2_code`, String))
    parts = split(out)
    @test length(parts) == 2
    @test parse(UInt64, parts[1]) == parent_gg_fp
    @test parse(UInt64, parts[2]) == parent_gg_digest

    # D3: model definition order A,B vs B,A vs unrelated model first
    def_A = """
    @potts_model DetModelA begin
        @kinds medium cell
        @parameters λ = 1.0 V₀ = 9.0 T = 1.0
        @variables q(site) = 0.0
        @lattice Lattice((10, 10))
        @energy cells => λ * (volume - V₀)^2 + 0.01 * count(q[n] == 1.0 for n in Moore(1)(40))
        @sweep Metropolis(; temperature = T)
    end
    """
    def_B = """
    @potts_model DetModelB begin
        @kinds medium alpha beta
        @parameters J[3, 3] = [0.0 4.0 6.0; 4.0 2.0 8.0; 6.0 8.0 2.0] λ = 1.0 V₀ = 9.0 T = 1.0
        @lattice Lattice((10, 10))
        @energy begin
            contacts => J[kind, kind′]
            cells => λ * (volume - V₀)^2
        end
        @sweep Metropolis(; temperature = T)
    end
    """
    def_U = """
    @potts_model DetModelUnrelated begin
        @kinds medium x
        @parameters k = 0.5 T = 1.0
        @variables y(cell) = 1.0
        @lattice Lattice((8, 8))
        @energy cells => (volume - 4.0)^2
        @equations D(y) ~ -k * y
        @sweep Metropolis(; temperature = T)
    end
    """
    eval_tail = """
    σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
    fpA = PottsProblem(DetModelA(; name = :a), [ownership => σ, kind => [:cell]], (0, 2)).f.fingerprint
    fpB = PottsProblem(DetModelB(; name = :b), [ownership => σ, kind => [:alpha]], (0, 2)).f.fingerprint
    println(repr(fpA), " ", repr(fpB))
    """
    run_order(defs) = split(strip(read(
        `$(Base.julia_cmd()) --startup-file=no --project=$proj -e $("using Potts\n" * defs * eval_tail)`,
        String)))
    ab = run_order(def_A * def_B)
    ba = run_order(def_B * def_A)
    uab = run_order(def_U * def_A * def_B)
    @test ab == ba
    @test ab == uab
end
end

@testitem "determinism D5: structural scan for session/path/objectid leaks" setup = [DetSetup] tags = [:potts, :determinism] begin
@testset "determinism D5: structural scan for session/path/objectid leaks" begin
    leak_patterns = (
        r"objectid",
        r"@0x[0-9a-fA-F]+",
        r"#\d+#",
        r"##",
        r"/home/|/Users/|PottsWorktrees",
    )
    has_leak(txt::AbstractString) = any(pat -> occursin(pat, txt), leak_patterns)

    # Canonical solver strings must be free of session/address/gensym/path leaks
    solvers = (
        ExplicitEuler(substeps = 2, lower = 0.0),
        RK4(; substeps = 4),
        Potts.BackwardEuler(),
        Potts.CrankNicolson(),
    )
    for s in solvers
        cs = Potts._canonical(s)
        @test !has_leak(cs)
    end

    # Generated problem canonical/IR text for published models must be leak-free
    s_gg = graner_glazier_state()
    probs = (
        PottsProblem(GranerGlazier(; name = :gg), [ownership => s_gg[1], kind => s_gg[2]], (0, 2)),
        PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
            [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 2);
            field_solver = ExplicitEuler(substeps = 2, lower = 0.0)),
    )
    for p in probs
        @test !has_leak(string(p.f.sys.csys.sys))
        @test !has_leak(p.f.sys.solvers.canonical)
    end

    # Negative control: explicit session-bound / leaking strings are caught by the scanner
    @test has_leak("closure_##123#45")
    @test has_leak("Ptr{Nothing} @0x00007f1234567890")
    @test has_leak("objectid(fn)=12345")
    @test has_leak(joinpath(@__DIR__, "determinism_tests.jl"))
end
end
