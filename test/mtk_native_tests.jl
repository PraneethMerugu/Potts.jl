# MTK-native symbols, reads (`value_at`), `ismember` AST parity and `SciMLStructures` on `PottsParameters`.

@testitem "MTK-native: parameters are MTK parameters, kind tables array parameters" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: parameters are MTK parameters, kind tables array parameters" begin
        sys = MNModel(; name = :mn)
        ps = Potts.declared_parameters(sys)
        @test all(MTKB.isparameter, ps)
        λ, J, Dk = named(ps, :λ), named(ps, :J), named(ps, :Dk)
        @test J isa Symbolics.Arr && size(J) == (3, 3) && size(Dk) == (3,)
        @test !(λ isa Symbolics.Arr)
        @test Potts.info(J).role === :kindtable && Potts.info(λ).role === :param
        # negative control: a variable is not a parameter
        q = named(Potts.declared_variables(sys), :q)
        @test !MTKB.isparameter(q)
        # a kind table's shape is its default's: a scalar default is refused when the model is built
        @test mn_error(() -> MNScalarTable(; name = :m)) !== nothing
    end
end

@testitem "MTK-native: potts_entity metadata and input built-ins" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: potts_entity metadata and input built-ins" begin
        sys = MNModel(; name = :mn)
        q = named(Potts.declared_variables(sys), :q)
        e = Potts.get_potts_entity(q)
        @test e isa Potts.Entity && e.role === :cell && e.name === :q
        @test e === Potts.info(q)                        # one record: the metadata key is LatticePDE's
        for n in (:volume, :kind, :neighbor_kind, :source, :target, :id)
            b = unwrap(getfield(Potts.B, n))
            @test iscall(b) && isequal(only(arguments(b)), unwrap(Potts.t))      # `volume(t)`
            @test nameof(operation(b)) === n
            @test MTKB.isinput(b)
            @test Potts.get_potts_entity(b) == Potts.Builtin(n)
        end
        # negative controls: parameters and declared variables are not inputs
        @test !any(MTKB.isinput, Potts.declared_parameters(sys))
        @test !MTKB.isinput(q)
        @test Potts.get_potts_entity(Potts.t) === nothing
        # a built-in has no previous value: `Pre(w[new])` keeps `Pre` on `w` only
        w = only(MTKB.@variables w(Potts.t))
        isPre(y) = iscall(y) && operation(y) isa MTKB.Pre
        r = unwrap(Potts._pre(Potts.value_at(w, Potts.B.new)))
        @test operation(r) === LatticePDE.value_at && isPre(arguments(r)[1]) && isequal(arguments(r)[2], unwrap(Potts.B.new))
        @test isPre(arguments(unwrap(MTKB.Pre(Potts.value_at(w, Potts.B.new))))[2])     # negative control: MTK's own Pre
    end
end

@testitem "MTK-native: reads are LatticePDE's value_at" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: reads are LatticePDE's value_at" begin
        @test Potts.value_at === LatticePDE.value_at
        @test parentmodule(Potts.value_at) === LatticePDE
        sys = MNModel(; name = :mn)
        ops = Any[]
        walk(u) = (u = unwrap(u); iscall(u) && (push!(ops, operation(u)); foreach(walk, arguments(u))))
        foreach(p -> walk(p.second), Potts.hamiltonian(sys))
        @test LatticePDE.value_at in ops
        csys = mtkcompile(sys)
        osys = Potts.ode_system(csys, :cell)
        @test length(MTKB.unknowns(osys)) == 1
        σ = zeros(Int32, 12, 12)
        σ[2:4, 2:4] .= 1
        σ[8:10, 8:10] .= 2
        prob = PottsProblem(sys, [ownership => σ, kind => [:tip, :stalk]], (0, 3))
        sol = solve(prob, SequentialCPM())
        q = sol.u[end].cell.q
        @test q[1] > 0 && q[2] > 0 && isapprox(q[1], 2 * q[2]; rtol = 1.0e-6)
    end
end

@testitem "MTK-native: a kind set in @equations is `ismember`, never `∈` (D-257 item 5)" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: a kind set in @equations is `ismember`, never `∈` (D-257 item 5)" begin
        eq_check(M, eq) = mn_error(
            () -> Potts._potts_model(
                M, quote
                    @kinds medium tip stalk fluid endothelial = (tip, stalk)
                    @variables q(cell) = 0.0
                    @lattice Lattice((12, 12))
                    @energy cells => (volume - 9)^2
                    @equations $eq
                    @sweep Metropolis(; temperature = 2.0)
                end, @__MODULE__
            )
        )
        @test has(eq_check(:MNIn, :(D(q) ~ 0.25 * (kind ∈ endothelial))), "@equations", "∈", "ismember(kind, endothelial)")
        @test has(eq_check(:MNNotIn, :(D(q) ~ 0.25 * (kind ∉ endothelial))), "!ismember(kind, endothelial)")
        @test has(eq_check(:MNInTuple, :(D(q) ~ 0.25 * (kind ∈ (tip, stalk)))), "ismember(kind, (tip, stalk))")
        # controls: `∈` outside @equations builds, and `ismember(kind, g)` lowers identically to the `|` form
        @test mtkcompile(MNEnergyIn(; name = :e)) isa CompiledPottsSystem
        phases_ast(mode) = _strip_ast(generated_code(MNIsMemberCase(; name = :m, mode)).phases)
        @test phases_ast(:ismember) == phases_ast(:spelled) == phases_ast(:ismember_tuple)
        # negative control: another set gives other code
        @test phases_ast(:other) != phases_ast(:spelled)
    end
end

@testitem "MTK-native: `ismember` in a field rate is analysed as its `|` of equalities" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: `ismember` in a field rate is analysed as its `|` of equalities" begin
        field_ast(mode) = (
            g = generated_code(MNFieldIsMemberCase(; name = :m, mode); field_solver = ExplicitEuler(substeps = 2));
            (_strip_ast(g.delta_H), _strip_ast(g.commit!), _strip_ast(g.phases))
        )
        @test field_ast(:rx_im) == field_ast(:rx_sp)
        @test field_ast(:diff_im) == field_ast(:diff_sp)
        # negative control: another reaction rate changes the AST (the comparison can fail)
        @test field_ast(:rx_other) != field_ast(:rx_sp)
    end
end

@testitem "MTK-native: descriptions and errors name built-ins as written" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: descriptions and errors name built-ins as written" begin
        @test Potts._describe(Potts.divide(Potts.cells(1); when = Potts.B.volume >= 4)) == "@divide cells(1) when = volume >= 4"
        @test Potts._builtin_text("neighbor_kind(t) == 0 and cluster_volume(t) and x(t)") == "neighbor_kind == 0 and cluster_volume and x(t)"
    end
end

@testitem "SciMLStructures on PottsParameters" setup = [PottsParametersStructures] tags = [:potts, :mtk_native] begin
    @testset "SciMLStructures on PottsParameters" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1; σ[7:10, 7:10] .= 2
        prob = PottsProblem(GranerGlazier(; name = :gg, lattice = (12, 12)), [ownership => σ, kind => [1, 2]], (0, 2))
        p = prob.p
        @test p isa Potts.PottsParameters
        @test SS.isscimlstructure(p) && !SS.ismutablescimlstructure(p)
        @test SS.hasportion(SS.Tunable(), p) && SS.hasportion(SS.Constants(), p) && !SS.hasportion(SS.Caches(), p)
        nt = NamedTuple(p)
        scal = [k for k in keys(nt) if nt[k] isa Number]
        tabs = [k for k in keys(nt) if !(nt[k] isa Number)]
        @test !isempty(scal) && !isempty(tabs)
        v, repack, alias = SS.canonicalize(SS.Tunable(), p)
        @test !alias && v == [Float64(nt[k]) for k in scal]
        @test repack(v) == p && typeof(repack(v)) === typeof(p)
        w = 2 .* v
        q = SS.replace(SS.Tunable(), p, w)
        @test typeof(q) === typeof(p) && [getproperty(q, k) for k in scal] == w
        @test all(getproperty(q, k) == getproperty(p, k) for k in tabs)
        c, crepack, _ = SS.canonicalize(SS.Constants(), p)
        @test length(c) == sum(length(nt[k]) for k in tabs)
        @test crepack(c) == p
        @test_throws ArgumentError SS.replace(SS.Tunable(), p, w[1:(end - 1)])
        d = ForwardDiff.Dual.(v, 1.0)
        e = try
            SS.replace(SS.Tunable(), p, d)
        catch err
            err
        end
        @test e isa ArgumentError
        @test SS.canonicalize(SS.Caches(), p) === (nothing, nothing, nothing)
        @test SS.canonicalize(SS.Discrete(), p) === (nothing, nothing, nothing)
        r = Potts.SciMLBase.remake(prob; p = q)
        @test typeof(r.p) === typeof(p) && [getproperty(r.p, k) for k in scal] == w
        @test Symbol(solve(r, SequentialCPM()).retcode) === :Success
        asym = collect(Float64, c)
        asym[2] += 1.0
        @test_throws ArgumentError Potts.SciMLBase.remake(prob; p = crepack(asym))
    end
end

# `hash` agrees with `==` (equal parameter objects are one `Set` element and one `Dict`
# key). Control on the code before this change: `==` compares values (1 == 1.0) but `hash` was the default one.
@testitem "PottsParameters hash agrees with ==" setup = [PottsParametersStructures] tags = [:potts, :mtk_native] begin
    @testset "PottsParameters hash agrees with ==" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1; σ[7:10, 7:10] .= 2
        p = PottsProblem(GranerGlazier(; name = :gg, lattice = (12, 12)), [ownership => σ, kind => [1, 2]], (0, 2)).p
        q = PottsProblem(GranerGlazier(; name = :gg, lattice = (12, 12)), [ownership => σ, kind => [1, 2]], (0, 2)).p
        @test p == q && hash(p) == hash(q)
        for n in (0, 1, 7, 100, -3)        # property: a == b ⇒ hash(a) == hash(b), across number types
            a = Potts.PottsParameters((; λ = Float64(n), k = n))
            b = Potts.PottsParameters((; λ = n, k = Float32(n)))
            @test a == b && isequal(a, b) && hash(a) == hash(b)
            @test length(Set([a, b])) == 1 && haskey(Dict(a => 1), b)
        end
        # `-0.0 == 0.0` but they are not `isequal` (and hash apart): isequal objects hash equal
        z, nz = Potts.PottsParameters((; λ = 0.0)), Potts.PottsParameters((; λ = -0.0))
        @test z == nz && !isequal(z, nz) && length(Set([z, nz])) == 2
    end
end

@testitem "SciMLStructures: computed parameters are re-derived by replace; remake takes an object as given" setup = [PottsParametersStructures] tags = [:potts, :mtk_native] begin
    @testset "SciMLStructures: computed parameters are re-derived by replace; remake takes an object as given" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1
        prob = PottsProblem(C9Computed(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        p = prob.p
        v, repack, _ = SS.canonicalize(SS.Tunable(), p)
        @test v == [1.0, 2.0]
        q = repack([1.0, 3.0])
        @test q.λ == 3.0 && q.λ2 == 6.0
        @test SS.replace(SS.Tunable(), p, [1.0, 3.0]) == q
        r = Potts.SciMLBase.remake(prob; p = q)
        @test r.p == q && typeof(r.p) === typeof(p)
        ck = Potts.SciMLBase.remake(prob; p = [:λ => 3.0]).p
        @test ck.λ == 3.0 && ck.λ2 == 6.0
        @test Potts.SciMLBase.remake(prob; p = ck).p === ck
        hand = Potts._with_values(ck, merge(NamedTuple(ck), (λ2 = 7.0,)))
        @test Potts.SciMLBase.remake(prob; p = hand).p.λ2 == 6.0
        @test_throws ArgumentError Potts.SciMLBase.remake(prob; p = [:λ => 3.0, :λ2 => 7.0])
        p32 = PottsProblem(C9Computed(; name = :c), [ownership => σ, kind => [1]], (0, 2); T = Float32)
        _, repack32, _ = SS.canonicalize(SS.Tunable(), p32.p)
        q1, q2 = repack32([1.0, 3.0]), repack32(Float32[1, 3])
        @test q1 == q2 && typeof(q1) === typeof(q2) === typeof(p32.p) && q1.λ2 === 6.0f0
        @test Potts.SciMLBase.remake(p32; p = q).p == q1
        @test Potts.SciMLBase.remake(p32; p = ck).p.λ2 === 6.0f0
        pi_ = Potts.PottsParameters((n = 3, x = 1.0))
        @test SS.canonicalize(SS.Tunable(), pi_)[1] == [1.0] && SS.canonicalize(SS.Constants(), pi_)[1] == [3]
        e = try
            SS.replace(SS.Constants(), pi_, [2.5])
        catch err
            err
        end
        @test e isa ArgumentError
        @test SS.replace(SS.Tunable(), pi_, [big"0.1"]).x === 0.1
        prob3 = PottsProblem(C9Computed3(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        @test typeof(prob3.p) !== typeof(p)
        @test SS.canonicalize(SS.Tunable(), prob3.p)[2]([1.0, 3.0]).λ2 == 9.0
        @test SS.canonicalize(SS.Tunable(), p)[2]([1.0, 3.0]).λ2 == 6.0
        rb = Potts.SciMLBase.remake(prob; p = prob3.p)
        @test typeof(rb.p) === typeof(p) && rb.p.λ2 == 4.0 && prob3.p.λ2 == 6.0
        stray = Potts.PottsParameters((T = 1.0, λ = 2.0, λ2 = 4.0), ((:λ2,), UInt64(0x1234)))
        e = try
            SS.replace(SS.Tunable(), stray, [1.0, 3.0])
        catch err
            err
        end
        @test e isa ArgumentError
        @test typeof(PottsProblem(C9Computed(; name = :c, T = 2.0), [ownership => σ, kind => [1]], (0, 2)).p) === typeof(p)
        ps3 = Potts._p(getfield(Potts.ModelingToolkitBase.mtkcompile(C9Computed3(; name = :c)), :sys), :parameters)
        e = try
            Potts._register_derivation!(ps3, Float64, p)
        catch err
            err
        end
        @test e isa ArgumentError
        N_ = Potts.Symbolics.Num
        a13, f13 = [(:a, N_(1 // 3))], [(:a, N_(1 / 3))]
        @test Potts._canon_default(a13[1][2]) == Potts._canon_default(f13[1][2])
        @test !Potts._same_defaults(a13, f13)
        @test Potts._same_defaults(a13, [(:a, N_(1 // 3))]) && Potts._same_defaults([(:a, N_(0))], [(:a, N_(0.0))])
        pb = PottsProblem(C9FB(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        pa = try
            PottsProblem(C9FA(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        catch err
            err
        end
        rep(q) = SS.canonicalize(SS.Tunable(), q.p)[2]([1.0, 3.0]).λ2
        refused = pa isa ArgumentError
        distinct = pa isa Potts.CorePotts.PottsProblem && typeof(pa.p) !== typeof(pb.p) && rep(pa) == 6.0 && rep(pb) == 9.0
        @info "C9 A.f/B.f" refused distinct (pa isa Exception ? sprint(showerror, pa) : typeof(pa.p).parameters[2]) typeof(pb.p).parameters[2]
        @test refused || distinct
        @test rep(pb) == 9.0
        for (sv, want) in ((2, 6.0), (3, 9.0))
            ps = PottsProblem(C9Sweep(; name = :sw, s = sv), [ownership => σ, kind => [1]], (0, 2))
            @test SS.canonicalize(SS.Tunable(), ps.p)[2]([1.0, 3.0]).λ2 == want
        end
    end
end
