# P6.0f (ROADMAP Phase 6, step 0): `Every(n)` per lifecycle rule. Two division rules at
# different cadences fire at their own counts. Frozen (AUTONOMY §7.3).

@potts_model TwoCadences begin
    @kinds medium ka kb
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 16; 16 16 14]
        V₀[kind] = [0.0, 64.0, 64.0]
        λ = 1.0
        T = 10.0
    end
    @lattice Lattice((60, 40); neighborhood = Moore(1))
    @energy cells => λ * (volume - V₀[kind])^2
    @constraint no_extinction
    @divide cells(ka) Every(2) when = volume >= 4, along = (1.0, 0.0)
    @divide cells(kb) Every(3) when = volume >= 4, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = T)
end

# one 16×16 cell of each kind
function two_cadences_state()
    σ = zeros(Int32, 60, 40)
    σ[5:20, 10:25] .= 1
    σ[35:50, 10:25] .= 2
    return σ, [:ka, :kb]
end

function kind_counts(v)
    live = findall(>(0), Array(v.cell.volume))
    kd = Array(v.cell.kind)
    return count(c -> kd[c] == 1, live), count(c -> kd[c] == 2, live)
end

@testset "P6.0f: two division rules at different cadences" begin
    σ, kinds = two_cadences_state()
    prob = PottsProblem(TwoCadences(; name = :two), [ownership => σ, kind => kinds], (0, 6))
    @test selfcheck(remake(prob; tspan = (0, 1))) < 1e-9
    # MCS are numbered from 0 and a rule with Every(n) fires when mcs % n == 0 (as updates do):
    # ka divides at MCS 0, 2, 4 and kb at MCS 0, 3; tspan (0, n) runs MCS 0 … n − 1
    expected = Dict(1 => (2, 2), 2 => (2, 2), 3 => (4, 2), 4 => (4, 4), 5 => (8, 4), 6 => (8, 4))
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        for n in 1:6
            @test kind_counts(solve(remake(prob; tspan = (0, n)), alg).u[end]) == expected[n]
        end
    end
end

@testset "P6.0f: Every(n) on a rule needs n ≥ 1; Every(1) is the default cadence" begin
    @test_throws ArgumentError Potts.Every(0)
    σ, kinds = two_cadences_state()
    one = Potts.divide(Potts.cells(1), Potts.Every(1); when = Potts.B.volume >= 4)
    dflt = Potts.divide(Potts.cells(1); when = Potts.B.volume >= 4)
    sys(r) = Potts.PottsSystem(; name = :x, kinds = [:medium, :ka, :kb], lattice = Potts.lattice_spec((60, 40)),
        sweep = Potts.sweep_spec(:metropolis; temperature = 10.0), divisions = [r])
    count1(r) = kind_counts(solve(PottsProblem(mtkcompile(sys(r)), [ownership => σ, kind => kinds], (0, 2)),
        SequentialCPM()).u[end])
    @test count1(one) == count1(dflt) == (4, 1)
end
