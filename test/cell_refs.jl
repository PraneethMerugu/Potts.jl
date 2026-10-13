# Cell references (R6, P6.5a): regressions found in review of the D-231 implementation. The
# specification is the frozen acceptance test lib/PottsModels/test/acceptance/p6_5a_cell_refs.jl;
# these cover forms it does not reach.
using Potts: CorePotts

cr_ctx(prob) = Potts._host_ctx(prob)

# every Moore(1) copy of state `u` (target t takes source s's owner)
function cr_props(prob, u)
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    σ = Array(u.σ)
    out = CorePotts.Proposal{2}[]
    for t in eachindex(σ)
        x = CorePotts.coordinates(lat, t)
        for kk in 1:length(moore)
            ins, y = CorePotts.shift(lat, x, moore.offsets[kk])
            ins || continue
            s = CorePotts.linear_index(lat, y)
            σ[t] == σ[s] && continue
            push!(out, CorePotts.Proposal(t, s, x, 1, σ[t], σ[s]))
        end
    end
    return out
end
function cr_apply(prob, u, prop)
    a = deepcopy(u)
    a.σ[prop.target] = prop.new
    prob.f.commit!(a, prob.p, prop, cr_ctx(prob))
    return a
end
# the largest self-check gap over every copy of `u`: ΔH − (H(a) − H(u)) − credit
function cr_worst_gap(prob, u)
    worst = 0.0
    for prop in cr_props(prob, u)
        a = cr_apply(prob, u, prop)
        g = energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u)) -
            Potts._killing_credit(prob, u, prop, a)
        worst = max(worst, abs(g))
    end
    return worst
end
cr_claimed(prob, u, prop) = (c = cr_ctx(prob);
    Set(filter(>(0), vcat(Int[Int(x) for x in prob.f.reads(u, prob.p, prop, c)],
        Int[Int(x) for x in prob.f.claims(u, prob.p, prop, c)]))))

# 1. an on-copy update writes the gainer's reference, which the energy dereferences
@potts_model CROnCopy begin
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
        q(cell) = 5.0
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 6.0 - q[partner])^2
        contacts => 2.0
    end
    @on_copy partner[new] ~ old
    @sweep Metropolis(; temperature = 10.0)
end

# 2. references chosen with `ifelse`
@potts_model CRIfelse begin
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
        other(cell)::CellRef
        q(cell) = 5.0
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 9.0)^2
    @drive copy => 0.1 * volume[ifelse(mcs > 3, partner[old], other[old])]
    @observed viaif(cell) ~ q[ifelse(mcs >= 0, partner, id)]
    @sweep Metropolis(; temperature = 10.0)
end

# 3. a population fold over references in a drive
@potts_model CRFold begin
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
        q(cell) = 5.0
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 9.0)^2
    @drive copy => 0.1 * sum(q[partner[c]] for c in cells(ka))
    @sweep Metropolis(; temperature = 10.0)
end

@potts_model CRFoldBad begin
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
        q(cell) = 5.0
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy contacts => 0.1 * sum(q[partner[c]] for c in cells(ka))
    @sweep Metropolis(; temperature = 10.0)
end

# 4. a literal reference beyond the capacity
@potts_model CRLiteral begin
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 9.0)^2
    @drive copy => 0.1 * volume[partner[old]]
    @after_mcs partner ~ 50
    @sweep Metropolis(; temperature = 10.0)
end

# 5. an update reading its own variable through a reference (a previous-value snapshot)
@potts_model CRSnapshot begin
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
        q(cell) = 0.0
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 9.0)^2
    @after_mcs q ~ q[partner] + 1.0
    @sweep Metropolis(; temperature = 0.0001)
end

# 7. a dividing model (birth serials)
@potts_model CRDivide begin
    @kinds medium blob
    @variables begin
        partner(cell)::CellRef
    end
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 36.0)^2
    @divide cells(blob) when = mcs == 2, along = (1.0, 0.0)
    @observed bth(cell) ~ birth
    @sweep Metropolis(; temperature = 4.0)
end

const CR_σ = let σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1; σ[8:10, 8:10] .= 2; σ[2:3, 9:10] .= 3
    σ
end

@testset "references written on copy are dereferenced exactly (ΔH = H(a) − H(u) + credit)" begin
    σ = zeros(Int32, 12, 12); σ[3:5, 3:5] .= 1; σ[3:5, 6:8] .= 2; σ[9, 9] = 3
    p = PottsProblem(CROnCopy(; name = :rb), [ownership => σ, :partner => [2, 3, 1], :q => [1.0, 2.0, 3.0]],
        (0, 2); capacity = 4)
    u = p.u0
    # medium → 1: partner[1] becomes 0, which reads q's default 5.0, as H does
    pr = first(filter(x -> x.old == 0 && x.new == 1, cr_props(p, u)))
    a = cr_apply(p, u, pr)
    @test a.cell.partner[1] == 0
    @test energy_change(p, u, pr) ≈ total_energy(p, a) - total_energy(p, u) atol = 1e-9
    @test cr_worst_gap(p, u) < 1e-9                       # every copy, kills (cell 3) included
    @test 1 in cr_claimed(p, u, first(filter(x -> x.old == 1 && x.new == 2, cr_props(p, u))))   # the written referent
    sol = solve(p, SequentialCPM(); saveat = 1)
    @test cr_worst_gap(p, sol.u[end]) < 1e-9
end

@testset "a reference chosen with ifelse is claimed and guarded" begin
    p = PottsProblem(CRIfelse(; name = :c1), [ownership => CR_σ, :partner => [2, 0, 0], :other => [3, 0, 0]],
        (0, 2); capacity = 4)
    u = p.u0
    @test CorePotts.has_reads(p.f)
    @test cr_claimed(p, u, first(filter(x -> x.old == 1 && x.new == 0, cr_props(p, u)))) ⊇ Set([2, 3])  # both branches
    p7 = PottsProblem(CRIfelse(; name = :c7), [ownership => CR_σ, :partner => [3, 3, 1], :q => [1.0, 2.0, 7.0]],
        (0, 1); capacity = 4)
    v = deepcopy(p7.u0); v.σ[v.σ .== 3] .= 0; v.cell.volume[3] = 0
    @test observe(p7, :viaif, v)[1:2] == [5.0, 5.0]       # a dead referent reads the default
    @test observe(p7, :viaif, p7.u0)[1:2] == [7.0, 7.0]
end

@testset "a fold over references in a drive runs on every solver" begin
    p = PottsProblem(CRFold(; name = :c2), [ownership => CR_σ, :partner => [2, 3, 1]], (0, 2); capacity = 4)
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test Symbol(solve(p, alg).retcode) === :Success
    end
    # an energy of another domain still may not read through a reference, even in a fold
    err = try
        PottsProblem(CRFoldBad(; name = :bad), [ownership => CR_σ, :partner => [2, 3, 1]], (0, 2); capacity = 4)
        nothing
    catch e
        e
    end
    @test err isa Exception && occursin("reference", sprint(showerror, err))
end

@testset "a reference beyond the capacity claims nothing" begin
    p = PottsProblem(CRLiteral(; name = :c5), [ownership => CR_σ, :partner => [2, 3, 1]], (0, 3); capacity = 4)
    sol = solve(p, CheckerboardCPM(); saveat = 1)
    @test Symbol(sol.retcode) === :Success
    u = sol.u[end]
    @test all(==(50), u.cell.partner[1:3])
    for pr in filter(x -> x.old == 1, cr_props(p, u))
        @test isempty(cr_claimed(p, u, pr))
    end
end

@testset "an update reads its own variable through a reference (snapshot default)" begin
    σ = zeros(Int32, 12, 12); σ[2:4, 2:4] .= 1; σ[8:10, 8:10] .= 2
    p = PottsProblem(CRSnapshot(; name = :eu), [ownership => σ, :partner => [2, 1], :q => [1.0, 10.0]], (0, 1))
    @test solve(p, SequentialCPM(); saveat = 1).u[end].cell.q[1:2] == [11.0, 2.0]       # previous values
    p0 = PottsProblem(CRSnapshot(; name = :eu), [ownership => σ, :partner => [0, 1], :q => [1.0, 10.0]], (0, 1))
    @test solve(p0, SequentialCPM(); saveat = 1).u[end].cell.q[1:2] == [1.0, 2.0]        # ref 0: default 0.0
end

# a state of the dividing model as saved before cell serials existed
cr_old_layout(st) = CorePotts.CPMState(st.σ, Base.structdiff(st.cell, NamedTuple{(:birth,)}),
    st.site, Base.structdiff(st.model, NamedTuple{(CorePotts.NEXT_BIRTH,)}), st.history)

@testset "a pre-serial state of a dividing model gets birth = slot and a fresh counter" begin
    σ = zeros(Int32, 24, 24); σ[4:9, 4:9] .= 1; σ[15:20, 15:20] .= 2
    p = PottsProblem(CRDivide(; name = :d), [ownership => σ, kind => [:blob, :blob], :partner => [2, 1]], (0, 4);
        capacity = 8)
    old = cr_old_layout(p.u0)
    @test !haskey(old.cell, :birth)
    q = remake(p; u0 = old)
    @test q.u0.cell.birth == Int32.(1:8)
    @test q.u0.model[CorePotts.NEXT_BIRTH] == Int32[9]
    @test keys(q.u0.cell) == keys(p.u0.cell) && keys(q.u0.model) == keys(p.u0.model)
    u = solve(q, SequentialCPM()).u[end]
    alive = findall(>(0), u.cell.volume)
    @test length(alive) == 4
    @test sort(observe(q, :bth, u)[alive]) == [1, 2, 9, 10]          # no serial reused
    # a checkpoint saved before serials
    integ = init(p, SequentialCPM())
    step!(integ)
    ck = CorePotts.checkpoint(integ)
    ck0 = CorePotts.PottsCheckpoint(cr_old_layout(ck.state), ck.t, ck.seed, ck.replica, ck.repeat, ck.p,
        ck.fingerprint, ck.stats)
    u2 = solve(p, SequentialCPM(); checkpoint = ck0).u[end]
    @test sort(Array(u2.cell.birth)[findall(>(0), u2.cell.volume)]) == [1, 2, 9, 10]
    # reinit! with an old-layout state
    integ2 = init(p, SequentialCPM())
    reinit!(integ2, old)
    @test integ2.state.cell.birth == Int32.(1:8)
    solve!(integ2)
    @test Symbol(integ2.retcode) === :Success
end

# E4/E5/E8 (ergonomics review): the reference debug mode `track = (:references,)`, the
# `sibling` rule with several members, and the refusal message naming the alternatives

@potts_model CRSibling begin
    @kinds medium cyto nucleus
    @parameters begin
        V₀[kind] = [0.0, 30.0, 4.0]
    end
    @variables begin
        nuc(cell)::CellRef
        q(cell) = 5.0
    end
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => 4.0 * (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 0.5, 1.0)
    end
    @after_mcs nuc ~ sibling(nucleus)
    @divide cells(cyto) when = mcs == 100000, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 0.01)
end

@potts_model CRBadVolume begin
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - volume[partner])^2
    @sweep Metropolis(; temperature = 10.0)
end

function cr_dead_problem(; track = ())
    σ = zeros(Int32, 12, 12); σ[3:5, 3:5] .= 1; σ[3:5, 6:8] .= 2; σ[9, 9] = 3
    p = PottsProblem(CROnCopy(; name = :rb), [ownership => σ, :partner => [3, 3, 0], :q => [1.0, 2.0, 3.0]],
        (0, 2); capacity = 4, track)
    u = deepcopy(p.u0); u.σ[9, 9] = 0; u.cell.volume[3] = 0        # cell 3 is dead: 1 and 2 read it
    return remake(p; u0 = u)
end

@testset "track = (:references,) counts dereferences of dead referents (E4)" begin
    plain = cr_dead_problem()
    tracked = cr_dead_problem(; track = (:references,))
    # off: no counters, no counting code, no warning
    @test !haskey(plain.u0.model, Potts.REF_COUNTS)
    σ0 = copy(plain.u0.σ); σ0[9, 9] = 3
    @test plain.f.fingerprint == PottsProblem(CROnCopy(; name = :rb), [ownership => σ0, :partner => [3, 3, 0]],
        (0, 2); capacity = 4).f.fingerprint
    @test tracked.f.fingerprint != plain.f.fingerprint
    @test_logs solve(plain, SequentialCPM())
    # on: one warning naming the energy term
    @test haskey(tracked.u0.model, Potts.REF_COUNTS)
    @test_logs (:warn, r"@energy cells read a dead referent \d+ time") solve(tracked, SequentialCPM())
    @test_logs (:warn, r"@energy cells read a dead referent") solve(tracked, CheckerboardCPM())
    # the debug mode changes nothing in the run
    a = solve(plain, SequentialCPM()).u[end]
    b = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        solve(tracked, SequentialCPM()).u[end]
    end
    @test a.σ == b.σ
    # `remake` switches it, and a state of the untracked problem fits the tracked one
    @test haskey(remake(plain; track = (:references,)).u0.model, Potts.REF_COUNTS)
    @test !haskey(remake(tracked; track = ()).u0.model, Potts.REF_COUNTS)
    @test haskey(remake(tracked; u0 = plain.u0).u0.model, Potts.REF_COUNTS)
end

@testset "sibling(k) with several members: the lowest birth, reported in the debug mode (E5)" begin
    σ = zeros(Int32, 16, 16); σ[3:9, 3:9] .= 1; σ[4:5, 4:5] .= 2; σ[7:8, 7:8] .= 3
    mk(track) = PottsProblem(CRSibling(; name = :s), [ownership => σ, kind => [:cyto, :nucleus, :nucleus],
            cluster => [1, 1, 1]], (0, 1); capacity = 6, track)
    p = mk(())
    @test solve(p, SequentialCPM()).u[end].cell.nuc[1] == 2                  # birth = slot: 2 is older
    u = deepcopy(p.u0); u.cell.birth[1:3] .= Int32[1, 7, 3]                   # now 3 is older
    @test solve(remake(p; u0 = u), SequentialCPM()).u[end].cell.nuc[1] == 3
    t = mk((:references,))
    @test_logs (:warn, r"sibling\(k\) found several alive members") solve(t, SequentialCPM())
    @test_logs solve(p, SequentialCPM())                                       # untracked: silent
end

@testset "the D-209 refusal through a reference names the alternatives (E8)" begin
    err = try
        PottsProblem(CRBadVolume(; name = :bv), [ownership => CR_σ, :partner => [2, 3, 1]], (0, 1))
        nothing
    catch e
        e
    end
    @test err isa Exception
    msg = sprint(showerror, err)
    @test occursin("a copy changes", msg)
    @test occursin("Read it in a `@drive` (evaluated per copy", msg)
    @test occursin("snapshot it with `@after_mcs`", msg)
end
