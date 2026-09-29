# PottsModels: every model builds, compiles and runs, and its derived ΔH matches the brute-
# force energy difference. Reference parity with the legacy implementations runs in the
# Potts test group (test/parity), which authors its problems from these sources.
using Test, Potts, PottsModels, Aqua
using Potts: CorePotts

function selfcheck(prob; n = 200)
    sol = solve(remake(prob; tspan = (0, 3)), SequentialCPM(; proposal = Moore(1)))
    lat = prob.lattice
    ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
    moore = CorePotts.relation(Moore(1), lat)
    worst = 0.0
    for u in sol.u, i in 1:n
        t = mod1(i * 7919, length(u.σ)); x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, moore.offsets[mod1(i, length(moore))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.σ[t], u.σ[s])
        a = deepcopy(u); a.σ[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx)
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u))))
    end
    return worst
end

@testset "PottsModels" begin
    σ, kinds = graner_glazier_state()
    @test size(σ) == (72, 72) && length(kinds) == 64 && size(first(graner_glazier_state(2))) == (144, 144)
    two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
    cases = [
        ("Graner–Glazier", GranerGlazier(; name = :gg), [ownership => σ, kind => kinds]),
        ("Wortel Act", WortelAct(; name = :act), [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:endothelial, :endothelial]]),
        ("Merks", MerksVasculogenesis(; name = :merks), [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]]),
        ("OpenVT", OpenVTMonolayer(; name = :openvt), [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]]),
    ]
    @testset "$label" for (label, sys, op) in cases
        prob = PottsProblem(sys, op, (0, 10))
        @test selfcheck(prob) < 1e-9
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
        @test sol.retcode == Potts.CorePotts.SciMLBase.ReturnCode.Success
        u = sol.u[end]
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
    end
    @testset "Akeeb invasion (99×60)" begin
        op = akeeb_state(; lattice = (99, 60))
        @test length(op[2].second) == 308 && count(==(:leader), op[2].second) == 77     # as in the MTK-bridge check
        prob = PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (99, 60)), op, (0, 200); capacity = 1000)
        @test selfcheck(prob) < 1e-9
        sol = solve(prob, SequentialCPM(; proposal = VonNeumann(1)))
        u = sol.u[end]
        @test sol.stats.lifecycle.divisions > 0
        @test all(>(0), u.cell.volume[1:308])                                             # no extinction
        @test all(c -> u.cell.clock[c] >= 0 || u.cell.clock[c] == -1, 1:308)
        p0 = remake(prob; u0 = akeeb_state(; lattice = (99, 60), pp = 0.0))
        @test solve(p0, SequentialCPM(; proposal = VonNeumann(1))).stats.lifecycle.divisions == 0
        @test akeeb_contacts(-2.0)[2, 3] == akeeb_contacts(-2.0)[3, 2] == -2.0
    end
    @test GranerGlazier(; name = :big, lattice = (144, 144), T = 5.0).lattice.dims == (144, 144)
    @test occursin("Graner & Glazier", string(@doc GranerGlazier))
end

@testset "Aqua" begin
    Aqua.test_all(PottsModels; deps_compat = (; check_extras = false))
end
