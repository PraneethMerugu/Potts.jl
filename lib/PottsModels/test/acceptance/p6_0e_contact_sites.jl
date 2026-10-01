# P6.0e (ROADMAP Phase 6, step 0): contact energies read site values `x` (at s) and `x′`
# (at s′), as AUTHORING §3 promises. Frozen (AUTONOMY §7.3).
using Potts: CorePotts
using Statistics: mean

# adhesion that depends on a static site field: heterotypic contacts cost extra only where
# the cue is high, so the two kinds sort in the right half and mix in the left half
@potts_model CueGatedSorting begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 16.0
        T = 6.0
        β = 12.0
        J[kind, kind] = [0 12 12; 12 4 4; 12 4 4]
    end
    @variables cue(site) = 0.0
    @lattice Lattice((48, 24); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′] + β * (kind != kind′) * (owner != 0) * (owner′ != 0) * (cue + cue′) / 2
    end
    @sweep Metropolis(; temperature = T)
end

# a confluent 48×24 sheet of 4×4 cells in a checkerboard of kinds; the cue is 1 on the right half
function cue_gated_problem(tspan)
    σ = zeros(Int32, 48, 24)
    n = 0
    for i in 1:4:45, j in 1:4:21
        n += 1
        σ[i:(i + 3), j:(j + 3)] .= n
    end
    kinds = [isodd((c - 1) ÷ 6 + (c - 1) % 6) ? :light : :dark for c in 1:n]
    cue = [i > 24 ? 1.0 : 0.0 for i in 1:48, j in 1:24]
    return PottsProblem(CueGatedSorting(; name = :cg), [ownership => σ, kind => kinds, :cue => cue], tspan)
end

# fraction of unlike cell–cell bonds (von Neumann) among cell–cell bonds, per half
function unlike_fraction(σ, kd, cols)
    unlike = all = 0
    for i in cols, j in 1:24, (di, dj) in ((1, 0), (0, 1))
        a, b = σ[i, j], σ[mod1(i + di, 48), mod1(j + dj, 24)]
        (a == 0 || b == 0 || a == b) && continue
        all += 1
        unlike += kd[a] != kd[b]
    end
    return unlike / all
end

@testset "P6.0e: contact energies read site values" begin
    prob = cue_gated_problem((0, 400))
    @test selfcheck(prob) < 1e-9
    for alg in (SequentialCPM(), CheckerboardCPM())
        f = map(1:3) do seed
            u = solve(remake(prob; seed), alg).u[end]
            σ, kd = Array(u.σ), Array(u.cell.kind)
            (unlike_fraction(σ, kd, 1:24), unlike_fraction(σ, kd, 25:48))
        end
        left, right = mean(first.(f)), mean(last.(f))
        @test right < left - 0.1          # the cue-high half sorts; the cue-free half does not
    end
end
