# P6.5a3: a dividing model that never reads `birth` keeps no cell serials (D-066 item 3), so
# neither lifecycle planner runs the serial pass. Decided when the model is compiled
# (`CompiledPottsSystem.uses_birth`: `birth`, `birth[ref]`, `sibling`, `@convert`); the state
# then has no `birth` column or `NEXT_BIRTH` counter and the planners take `births = nothing`.
#
# Oracle (D-048): the same problem with the serial column and counter installed by hand (built
# through CorePotts, since `remake_state` refuses a state of another layout) runs the pass;
# serials are not an RNG input, so σ and every other cell column must match bitwise.
# Negative control: a model that reads `birth` through `sibling` keeps the pass, and its
# serials follow the D-066 rule (each round's daughters take the next serials in slot order).
using Potts: CorePotts
using PottsModels: AkeebInvasion, akeeb_state, OpenVTGrowingMonolayer, openvt_monolayer_state, OpenVTReferenceMonolayer,
    GranerGlazier
isdefined(Main, :SingleDivisionFixture) ||
    include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "fixtures.jl"))   # test-only models (D-254)

# the problem `prob` with the serial layout (initial cells 1:n, the counter at n + 1)
function bs_with_serials(prob)
    st = prob.u0
    n = Int(maximum(Array(st.σ)))
    birth = zeros(Int32, length(st.cell.kind))
    birth[1:n] .= Int32.(1:n)
    stb = CorePotts.CPMState(st.σ, merge(st.cell, (; birth)), st.site,
        merge(st.model, NamedTuple{(CorePotts.NEXT_BIRTH,)}((Int32[n + 1],))), st.history)
    return CorePotts.PottsProblem(prob.f, stb, prob.lattice, prob.tspan, prob.p; prob.contact, prob.proposal,
        prob.relations, prob.spacing, prob.frozen, prob.seed, prob.replica, prob.repeat)
end

# Akeeb on 24 × 30 with early divisions (clock threshold 10–20 MCS, V_max = 5): ~50 in 60 MCS
bs_akeeb(; T = Float64, tspan = (0, 60), seed = 0) = PottsProblem(AkeebInvasion(; name = :a, lattice = (24, 30)),
    [akeeb_state(; lattice = (24, 30)); :clock_min => 10.0; :clock_spread => 10.0; :V_max => 5.0], tspan;
    T, seed, capacity = 200)
# the growing OpenVT monolayer on 24² with τ = 4 (divisions within 60 MCS)
bs_openvt(; T = Float64, tspan = (0, 60), seed = 0) = PottsProblem(
    OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24), τ = 4.0), openvt_monolayer_state(; lattice = (24, 24)),
    tspan; T, seed, capacity = 64)

# σ and every cell column but `birth` of two trajectories, bitwise
function bs_same(a, b)
    length(a.u) == length(b.u) || return false
    for (x, y) in zip(a.u, b.u)
        Array(x.σ) == Array(y.σ) || return false
        for k in keys(x.cell)
            k === :birth && continue
            Array(getfield(x.cell, k)) == Array(getfield(y.cell, k)) || return false
        end
    end
    return true
end
bs_divisions(sol) = sol.stats.lifecycle.divisions

# the D-066 serial rule over a saved trajectory: the slots whose generation rose since the
# last save (this MCS's daughters, in slot order) took the counter's next serials, the
# counter advanced past them, and no serial was issued twice
function bs_serial_rule(sol)
    ok = true
    issued = Set{Int32}()
    u0 = sol.u[1]
    for c in findall(>(0), Array(u0.cell.volume))
        push!(issued, Array(u0.cell.birth)[c])
    end
    for i in 2:length(sol.u)
        a, b = sol.u[i - 1], sol.u[i]
        next = Array(a.model[CorePotts.NEXT_BIRTH])[1]
        born = findall(Array(b.cell.generation) .> Array(a.cell.generation))
        want = next .+ Int32.(0:(length(born) - 1))
        ok &= Array(b.cell.birth)[born] == want
        ok &= Array(b.model[CorePotts.NEXT_BIRTH])[1] == next + length(born)
        ok &= isempty(intersect(issued, want))
        union!(issued, want)
    end
    return ok
end

# readers and non-readers of `birth` (the compile-time decision)
@potts_model BSSibling begin
    @kinds medium blob
    @parameters T = 4.0
    @variables sib(cell)::CellRef
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => 2.0 * (volume - 16)^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 0.5, 1.0)
    end
    @after_mcs sib ~ sibling(blob)
    @divide cells(blob) when = volume >= 14, along = RandomPlane()
    @sweep Metropolis(; temperature = T)
end
@potts_model BSPlain begin
    @kinds medium blob
    @parameters T = 4.0
    @variables q(cell) = 0.0
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => 2.0 * (volume - 16)^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 0.5, 1.0)
    end
    @after_mcs q ~ sum(volume[m] for m in members(cluster)) + kind[root(cluster)]
    @divide cells(blob) when = volume >= 14, along = RandomPlane()
    @sweep Metropolis(; temperature = T)
end
@potts_model BSObserved begin
    @kinds medium blob
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 2.0 * (volume - 16)^2
    @divide cells(blob) when = volume >= 14, along = RandomPlane()
    @observed bth(cell) ~ birth
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model BSDeref begin
    @kinds medium blob
    @variables begin
        partner(cell)::CellRef
        pb(cell) = 0.0
    end
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 2.0 * (volume - 16)^2
    @after_mcs pb ~ birth[partner]
    @divide cells(blob) when = volume >= 14, along = RandomPlane()
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model BSDivideRule begin
    @kinds medium blob
    @variables b0(cell) = 0.0
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 2.0 * (volume - 16)^2
    @divide cells(blob) when = volume >= 14, along = RandomPlane(), b0 => birth
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model BSAlong begin             # reads `birth` only in the division plane
    @kinds medium blob
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 2.0 * (volume - 16)^2
    @divide cells(blob) when = volume >= 14, along = (birth, 1.0)
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model BSStatic begin            # reads `birth` but never divides: `birth ≡ slot`, no column
    @kinds medium blob
    @variables b0(cell) = 0.0
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 2.0 * (volume - 16)^2
    @after_mcs b0 ~ birth
    @sweep Metropolis(; temperature = 4.0)
end

bs_sigma() = (σ = zeros(Int32, 24, 24); σ[3:6, 3:6] .= 1; σ[12:15, 12:15] .= 2; σ[3:6, 16:19] .= 3; σ)
bs_blob(model; tspan = (0, 30), seed = 1, kw...) = PottsProblem(model, [ownership => bs_sigma(), kind => fill(:blob, 3)],
    tspan; seed, capacity = 64, kw...)

@testset "P6.5a3: the serial pass is kept exactly when the model reads `birth`" begin
    cases = [
        ("AkeebInvasion", AkeebInvasion(; name = :a, lattice = (24, 30)), true, false),
        ("OpenVTGrowingMonolayer", OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24)), true, false),
        ("OpenVTReferenceMonolayer", OpenVTReferenceMonolayer(; name = :r, lattice = (24, 24)), true, false),
        ("SingleDivisionFixture", SingleDivisionFixture(; name = :s), true, false),
        ("GranerGlazier (no lifecycle)", GranerGlazier(; name = :g), false, false),
        ("members and root only", BSPlain(; name = :p), true, false),
        ("sibling(k)", BSSibling(; name = :s), true, true),
        ("@observed birth", BSObserved(; name = :o), true, true),
        ("birth[ref] in an update", BSDeref(; name = :d), true, true),
        ("birth in a division rule", BSDivideRule(; name = :r), true, true),
        ("birth in the division plane", BSAlong(; name = :l), true, true),
        ("birth without divisions", BSStatic(; name = :t), false, true),
    ]
    for (label, model, divides, reads) in cases
        c = mtkcompile(model)
        @test Potts._numbers_cells(c) == divides
        @test c.uses_birth == reads
        @test Potts._tracks_births(c) == (divides && reads)
    end
    # the state layout follows: a column and a counter only when the serials are kept
    for (model, keep) in ((BSSibling(; name = :s), true), (BSPlain(; name = :p), false), (BSStatic(; name = :t), false))
        u0 = bs_blob(model).u0
        @test haskey(u0.cell, :birth) == keep
        @test haskey(u0.model, CorePotts.NEXT_BIRTH) == keep
    end
    @test !haskey(bs_akeeb().u0.cell, :birth) && !haskey(bs_akeeb().u0.model, CorePotts.NEXT_BIRTH)
    # a @convert pass keeps them (its `from`/`to` default to `sibling(k)`; frozen P6.5b fixtures)
    @test mtkcompile(CVDevice(; name = :cv)).uses_birth
end

@testset "P6.5a3: a birth-free dividing model's trajectory is unchanged by the skip (CPU)" begin
    for (label, mk) in (("Akeeb", bs_akeeb), ("OpenVT growing", bs_openvt), ("members/root", (; kw...) -> bs_blob(BSPlain(; name = :p))))
        prob = mk()
        with = bs_with_serials(prob)
        @test haskey(with.u0.cell, :birth)
        for alg in (SequentialCPM(), CheckerboardCPM())
            a = solve(prob, alg; saveat = 1)
            b = solve(with, alg; saveat = 1)
            @test Symbol(a.retcode) === :Success && Symbol(b.retcode) === :Success
            @test bs_divisions(a) > 0                                # the fixture divides
            @test bs_divisions(a) == bs_divisions(b)
            @test bs_same(a, b)
            @test !haskey(a.u[end].cell, :birth)
            @test bs_serial_rule(b)                                  # the pass ran on the oracle arm
        end
        # the device planner on the CPU backend (its fused, staged and host forms)
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = true
        try
            for form in (CorePotts._FORM_FUSED, CorePotts._FORM_STAGED, CorePotts._FORM_HOST)
                go(p) = (integ = init(p, CheckerboardCPM(); saveat = 1); integ.lcache.device.form[] = form; solve!(integ))
                a, b = go(prob), go(with)
                @test bs_divisions(a) > 0 && bs_divisions(a) == bs_divisions(b)
                @test bs_same(a, b)
                @test bs_serial_rule(b)
            end
        finally
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
        end
    end
end

@testset "P6.5a3: the oracles are not vacuous" begin
    prob = bs_akeeb(; tspan = (0, 30))
    a = solve(prob, SequentialCPM(); saveat = 1)
    @test !bs_same(a, solve(remake(prob; seed = 1), SequentialCPM(); saveat = 1))    # another seed differs
    b = solve(bs_with_serials(prob), SequentialCPM(); saveat = 1)
    @test bs_serial_rule(b)
    i = findfirst(k -> any(Array(b.u[k].cell.generation) .> Array(b.u[k - 1].cell.generation)), 2:length(b.u)) + 1
    d = findfirst(Array(b.u[i].cell.generation) .> Array(b.u[i - 1].cell.generation))
    b.u[i].cell.birth[d] += Int32(1)                     # one daughter off by one: the rule fails
    @test !bs_serial_rule(b)
end

@testset "P6.5a3: a model reading `birth` (sibling) keeps the pass (negative control)" begin
    prob = bs_blob(BSSibling(; name = :s))
    @test prob.u0.cell.birth[1:3] == Int32[1, 2, 3] && prob.u0.model[CorePotts.NEXT_BIRTH] == Int32[4]
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(prob, alg; saveat = 1)
        @test bs_divisions(sol) > 0
        @test bs_serial_rule(sol)
        @test sol.u[end].model[CorePotts.NEXT_BIRTH][1] == 4 + bs_divisions(sol)
    end
end

@testset "P6.5a3: post-run reads of `birth` on a birth-free dividing model are refused" begin
    prob = bs_akeeb(; tspan = (0, 3))
    sol = solve(prob, SequentialCPM())
    @test_throws ArgumentError sol[Potts.B.birth]
    err = try
        sol[Potts.B.birth]
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("model `a`", err.msg) && occursin("never reads `birth`", err.msg) &&
          occursin("@observed bth(cell) ~ birth", err.msg)
    @test_throws ArgumentError sol[Potts.B.birth + 1]
    @test length(sol[Potts.B.volume][end]) == length(sol.u[end].cell.kind)           # other quantities still read
    # a state with the serial layout is a state of another model: an ArgumentError naming the model
    with = bs_with_serials(prob)
    err = try
        remake(prob; u0 = with.u0)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("model `a`", err.msg) && occursin("`birth` cell column", err.msg)
    integ = init(prob, SequentialCPM())
    @test_throws ArgumentError reinit!(integ, with.u0)
    lone = CorePotts.CPMState(with.u0.σ, prob.u0.cell, with.u0.site, with.u0.model, with.u0.history)
    @test haskey(lone.model, CorePotts.NEXT_BIRTH)
    @test_throws ArgumentError remake(prob; u0 = lone)                 # the counter alone
    @test keys(remake(prob; u0 = deepcopy(prob.u0)).u0.cell) == keys(prob.u0.cell)   # control: its own layout
end

@testset "P6.5a3: the skip on the device (PottsDevices; device planner forms)" begin
    if isdefined(Main, :PottsDevices) && PottsDevices.on_device()
        backend = PottsDevices.device_backend()
        alg = CheckerboardCPM()
        for mk in (bs_akeeb, bs_openvt)
            prob = mk(; T = Float32)
            with = bs_with_serials(prob)
            for form in (CorePotts._FORM_FUSED, CorePotts._FORM_STAGED, CorePotts._FORM_HOST)
                go(p) = (integ = init(p, alg; backend, saveat = 1); integ.lcache.device.form[] = form; solve!(integ))
                a, b = go(prob), go(with)
                @test Symbol(a.retcode) === :Success && Symbol(b.retcode) === :Success
                @test bs_divisions(a) > 0 && bs_divisions(a) == bs_divisions(b)
                @test bs_same(a, b)
                @test bs_serial_rule(b)
            end
        end
        # the negative control on the device: serials kept, by the rule
        sol = solve(bs_blob(BSSibling(; name = :s); T = Float32), alg; backend, saveat = 1)
        @test bs_divisions(sol) > 0 && bs_serial_rule(sol)
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
