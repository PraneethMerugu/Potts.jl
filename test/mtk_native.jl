# MTK-native symbols (field-compiler cutover C3; v3 §5.1, §7.2; D-257 item 5): parameters are
# MTK parameters and kind tables array parameters, built-ins are MTK inputs `x(t)`, every
# model quantity carries its `potts_entity`, table and site reads are LatticePDE's `at`/`at2`,
# and a kind set in `@equations` is `ismember`, never `∈`.

module MTKNativeTests
using Potts, Test
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
mn_build(ex::Expr, M::Symbol) = mn_error(() -> (Core.eval(@__MODULE__, ex);
                                                Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m))))
has(msg, parts...) = msg !== nothing && all(p -> occursin(p, msg), parts)
named(xs, n) = only(filter(x -> Potts.info(x).name === n, collect(xs)))

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
        contacts => J[kind, kind′]
    end
    @equations D(q) ~ Dk[kind] - 0.1 * q
    @sweep Metropolis(; temperature = 2.0)
end

@testset "MTK-native: parameters are MTK parameters, kind tables array parameters" begin
    sys = MNModel(; name = :mn)
    ps = Potts.parameters(sys)
    @test all(MTKB.isparameter, ps)
    λ, J, Dk = named(ps, :λ), named(ps, :J), named(ps, :Dk)
    @test J isa Symbolics.Arr && size(J) == (3, 3) && size(Dk) == (3,)
    @test !(λ isa Symbolics.Arr)
    @test Potts.info(J).role === :kindtable && Potts.info(λ).role === :param
    # negative control: a variable is not a parameter
    q = named(Potts.variables(sys), :q)
    @test !MTKB.isparameter(q)
    # a kind table's shape is its default's: a scalar default is refused when the model is built
    @test has(mn_build(:(@potts_model MNScalarTable begin
        @kinds medium cell
        @parameters J[kind, kind] = 3.0
        @lattice Lattice((8, 8))
        @energy contacts => J[kind, kind′]
        @sweep Metropolis(; temperature = 1.0)
    end), :MNScalarTable), "kind table `J` takes a vector", "or a matrix")
end

@testset "MTK-native: potts_entity metadata and input built-ins" begin
    sys = MNModel(; name = :mn)
    q = named(Potts.variables(sys), :q)
    e = LatticePDE.get_potts_entity(q)
    @test e isa Potts.Entity && e.role === :cell && e.name === :q
    @test e === Potts.info(q)                        # one record: the metadata key is LatticePDE's
    for n in (:volume, :kind, :kind′, :source, :target, :id)
        b = unwrap(getfield(Potts.B, n))
        @test iscall(b) && isequal(only(arguments(b)), unwrap(Potts.t))      # `volume(t)`
        @test nameof(operation(b)) === n
        @test MTKB.isinput(b)
        @test LatticePDE.get_potts_entity(b) == Potts.Builtin(n)
    end
    # negative controls: parameters and declared variables are not inputs
    @test !any(MTKB.isinput, Potts.parameters(sys))
    @test !MTKB.isinput(q)
    @test LatticePDE.get_potts_entity(Potts.t) === nothing
    # a built-in has no previous value: `Pre(w[new])` keeps `Pre` on `w` only (MTK's `Pre`
    # distributes over the read's arguments and would keep `Pre(new(t))`)
    w = only(MTKB.@variables w(Potts.t))
    isPre(y) = iscall(y) && operation(y) isa MTKB.Pre
    r = unwrap(Potts._pre(Potts.at(w, Potts.B.new)))
    @test operation(r) === LatticePDE.at && isPre(arguments(r)[1]) && isequal(arguments(r)[2], unwrap(Potts.B.new))
    @test isPre(arguments(unwrap(MTKB.Pre(Potts.at(w, Potts.B.new))))[2])     # negative control: MTK's own Pre
end

@testset "MTK-native: reads are LatticePDE's at/at2" begin
    @test Potts.at === LatticePDE.at && Potts.at2 === LatticePDE.at2
    @test parentmodule(Potts.at) === LatticePDE
    sys = MNModel(; name = :mn)
    ops = Any[]
    walk(u) = (u = unwrap(u); iscall(u) && (push!(ops, operation(u)); foreach(walk, arguments(u))))
    foreach(p -> walk(p.second), Potts.hamiltonian(sys))
    @test LatticePDE.at2 in ops
    # the cell ODE reads its kind-table entry through `at` (S-4): its template compiles with the
    # kind as an input, and the rate the problem steps is Dk[kind] - 0.1q
    csys = mtkcompile(sys)
    osys = Potts.ode_system(csys, :cell)
    @test length(MTKB.unknowns(osys)) == 1
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[8:10, 8:10] .= 2
    prob = PottsProblem(sys, [ownership => σ, kind => [:tip, :stalk]], (0, 3))
    sol = solve(prob, SequentialCPM())
    q = sol.u[end].cell.q
    # q' = Dk[kind] - 0.1q from 0: a tip (Dk = 0.5) rises twice as fast as a stalk (0.25)
    @test q[1] > 0 && q[2] > 0 && isapprox(q[1], 2 * q[2]; rtol = 1e-6)
end

@testset "MTK-native: a kind set in @equations is `ismember`, never `∈` (D-257 item 5)" begin
    model(M, eq) = :(@potts_model $M begin
        @kinds medium tip stalk fluid endothelial = (tip, stalk)
        @variables q(cell) = 0.0
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9)^2
        @equations $eq
        @sweep Metropolis(; temperature = 2.0)
    end)
    msg = mn_build(model(:MNIn, :(D(q) ~ 0.25 * (kind ∈ endothelial))), :MNIn)
    @test has(msg, "@equations", "∈", "ismember(kind, endothelial)")
    @test has(mn_build(model(:MNNotIn, :(D(q) ~ 0.25 * (kind ∉ endothelial))), :MNNotIn), "!ismember(kind, endothelial)")
    @test has(mn_build(model(:MNInTuple, :(D(q) ~ 0.25 * (kind ∈ (tip, stalk)))), :MNInTuple), "ismember(kind, (tip, stalk))")
    # controls: `∈` outside @equations builds, and so does the `ismember` form
    @test mn_build(:(@potts_model MNEnergyIn begin
        @kinds medium tip stalk endothelial = (tip, stalk)
        @lattice Lattice((12, 12))
        @energy sites => 1.0 * (kind ∈ endothelial)
        @sweep Metropolis(; temperature = 2.0)
    end), :MNEnergyIn) === nothing
    @test mn_build(model(:MNIsMember, :(D(q) ~ 0.25 * ismember(kind, endothelial))), :MNIsMember) === nothing
    @test mn_build(model(:MNIsMemberTuple, :(D(q) ~ 0.25 * ismember(kind, (tip, stalk)))), :MNIsMemberTuple) === nothing
    @test mn_build(model(:MNSpelled, :(D(q) ~ 0.25 * ((kind == tip) | (kind == stalk)))), :MNSpelled) === nothing
    # `ismember(kind, g)` is the spelled-out `|` of equalities: the same generated code
    code(M) = string(generated_code(Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m))).phases)
    @test code(:MNIsMember) == code(:MNSpelled) == code(:MNIsMemberTuple)
    # negative control: another set gives other code
    @test mn_build(model(:MNOther, :(D(q) ~ 0.25 * ismember(kind, (tip, fluid)))), :MNOther) === nothing
    @test code(:MNOther) != code(:MNSpelled)
end

@testset "MTK-native: `ismember` in a field rate is analysed as its `|` of equalities" begin
    # host-side analysis (the stable substep count, ∂f/∂x) reads the spelled-out form: an opaque
    # `ismember` term would bound nothing (a reaction bound of 0, or a refused diffusion bound)
    fieldmodel(M, eq) = :(@potts_model $M begin
        @kinds medium tip stalk endothelial = (tip, stalk)
        @variables c(field) = 0.0
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9)^2
        @equations $eq
        @sweep Metropolis(; temperature = 2.0)
    end)
    code(M) = (g = generated_code(Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m)); field_solver = ExplicitEuler());
               string(Base.remove_linenums!(deepcopy(Any[g.delta_H, g.commit!, g.phases...]))))
    for (tag, im, sp) in (("reaction", :(D(c) ~ 0.1 * Δ(c) - 0.3 * c * ismember(kind, endothelial)),
                                       :(D(c) ~ 0.1 * Δ(c) - 0.3 * c * ((kind == tip) | (kind == stalk)))),
                          ("diffusion", :(D(c) ~ 0.1 * ismember(kind, endothelial) * Δ(c)),
                                        :(D(c) ~ 0.1 * ((kind == tip) | (kind == stalk)) * Δ(c))))
        A, Bm = Symbol(:MNField_im_, tag), Symbol(:MNField_sp_, tag)
        @test mn_build(fieldmodel(A, im), A) === nothing
        @test mn_build(fieldmodel(Bm, sp), Bm) === nothing
        @test code(A) == code(Bm)
    end
    # negative control: another reaction rate changes the code (the comparison can fail)
    @test mn_build(fieldmodel(:MNField_other, :(D(c) ~ 0.1 * Δ(c) - 0.6 * c * ismember(kind, endothelial))), :MNField_other) === nothing
    @test code(:MNField_other) != code(:MNField_sp_reaction)
end

@testset "MTK-native: descriptions and errors name built-ins as written" begin
    @test Potts._describe(Potts.divide(Potts.cells(1); when = Potts.B.volume >= 4)) == "@divide cells(1) when = volume >= 4"
    @test Potts._builtin_text("kind′(t) == 0 and cluster_volume(t) and x(t)") == "kind′ == 0 and cluster_volume and x(t)"
end
end
