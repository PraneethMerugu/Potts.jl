# P6.1b2 (ROADMAP Phase 6, step 1): a paper-size Graner–Glazier initial state (PRE 47, 2128:
# one aggregate of about 1000 cells). Frozen (AUTONOMY §7.3).
#
# Surface fixed by the coordinator:
#   graner_glazier_aggregate(n = 1000; seed = 1) -> (σ, kinds)
#   one round aggregate of `n` cells of about the model's V₀ = 40 sites, randomly mixed dark (1)
#   and light (2) in equal numbers (±1), surrounded by medium on a square lattice sized to fit;
#   deterministic in `seed`.

function moore_components(mask)
    lab = zeros(Int, size(mask)); n = 0
    for s in CartesianIndices(mask)
        (mask[s] && lab[s] == 0) || continue
        n += 1; lab[s] = n; stack = [s]
        while !isempty(stack)
            p = pop!(stack)
            for d in CartesianIndices((-1:1, -1:1))
                q = p + d
                checkbounds(Bool, mask, q) && mask[q] && lab[q] == 0 && (lab[q] = n; push!(stack, q))
            end
        end
    end
    return n
end

@testset "P6.1b2: paper-size Graner–Glazier aggregate" for n in (200, 1000)
    σ, k = graner_glazier_aggregate(n; seed = 1)
    @test maximum(σ) == n && length(k) == n && all(c -> any(==(c), σ), 1:n)
    areas = [count(==(c), σ) for c in 1:n]
    @test 32 <= sum(areas) / n <= 48                                  # about V₀ = 40
    @test minimum(areas) >= 10
    @test abs(count(==(1), k) - count(==(2), k)) <= 1
    cells = σ .!= 0
    @test moore_components(cells) == 1                                 # one aggregate …
    @test !any(cells[1:5, :]) && !any(cells[(end - 4):end, :]) &&     # … with a medium margin
          !any(cells[:, 1:5]) && !any(cells[:, (end - 4):end])
    rows = findall(vec(any(cells; dims = 2))); cols = findall(vec(any(cells; dims = 1)))
    h, w = length(rows), length(cols)
    @test max(h, w) / min(h, w) <= 1.2                                 # round
    @test abs(count(cells) / (h * w) - π / 4) <= 0.08
    unlike = nall = 0                                                   # randomly mixed
    for s in CartesianIndices(σ), d in ((1, 0), (0, 1))
        t = s + CartesianIndex(d)
        checkbounds(Bool, σ, t) || continue
        a, b = σ[s], σ[t]
        (a == 0 || b == 0 || a == b) && continue
        nall += 1; unlike += k[a] != k[b]
    end
    @test unlike / nall >= 0.35
    @test graner_glazier_aggregate(n; seed = 1)[1] == σ                # deterministic
    @test graner_glazier_aggregate(n; seed = 2)[1] != σ
    prob = PottsProblem(GranerGlazier(; name = :gg, lattice = size(σ)), [ownership => σ, kind => k], (0, 2))
    @test maximum(Array(solve(prob, SequentialCPM()).u[end].σ)) == n
end
