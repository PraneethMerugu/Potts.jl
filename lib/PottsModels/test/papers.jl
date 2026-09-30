# The published models reproduce their papers' results (paper-fidelity round, AUDIT §11).
# Each testset names the paper and the figure or section; negative controls are the paper's
# own contrasting regimes. Sizes are cut to keep the group quick; the paper's time unit may
# differ (see each model's docstring).
using Statistics: mean, cor, var, cov
using LinearAlgebra: Symmetric, eigen, dot

@testset "Graner & Glazier (1992, 1993): sorting regimes" begin
    σ0, k = graner_glazier_state()
    J0 = [0 16 16; 16 2 11; 16 11 14]
    sim(pars, nmcs; seed = 1, kw...) = solve(PottsProblem(GranerGlazier(; name = :gg), [ownership => σ0, kind => k, pars...],
        (0, nmcs); seed), SequentialCPM(; proposal = Moore(1)); kw...)
    # boundary classes over periodic Moore bonds, each pair once
    function bonds(σ)
        n = Dict(:dd => 0, :ll => 0, :dl => 0, :dM => 0, :lM => 0)
        nx, ny = size(σ)
        for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
            a = σ[x, y]; b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
            a == b && continue
            a == 0 && ((a, b) = (b, a))
            key = b == 0 ? (k[a] == 1 ? :dM : :lM) : k[a] == k[b] ? (k[a] == 1 ? :dd : :ll) : :dl
            n[key] += 1
        end
        return n
    end
    medium_fraction(σ, key) = (n = bonds(σ); n[key] / sum(values(n)))
    hetero(σ) = (n = bonds(σ); n[:dl] / (n[:dl] + n[:dd] + n[:ll]))
    function radius_ratio(σ)                 # mean distance to the aggregate centroid, dark / light
        sites = findall(!=(0), σ); c = (mean(i[1] for i in sites), mean(i[2] for i in sites))
        r(kk) = mean(hypot(i[1] - c[1], i[2] - c[2]) for i in sites if k[σ[i]] == kk)
        return r(1) / r(2)
    end

    # light cells engulf the dark ones: no dark–medium boundary is left (PRL Fig. 2b)
    for seed in 1:3
        σ = sim([], 10_000; seed).u[end].σ
        @test medium_fraction(σ, :dM) <= 0.01 && radius_ratio(σ) < 0.75
    end
    # partial sorting (PRE §III E: J_ll = 11, J_dl = 14, T = 5) never forms the monolayer
    σ = sim([:J => [0 16 16; 16 2 14; 16 14 11], :T => 5.0], 10_000).u[end].σ
    @test medium_fraction(σ, :dM) > 0.08 && radius_ratio(σ) > 1
    # checkerboard when heterotypic bonds are cheapest (PRE §III A, Fig. 8b)
    @test all(s -> hetero(sim([:J => [0 12 12; 12 8 6; 12 6 10]], 1000; seed = s).u[end].σ) > 0.75, 1:3)
    # sorting is logarithmic in time (PRL Fig. 2a): heterotypic fraction linear in ln t
    ts = [16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
    H = zeros(length(ts))
    for seed in 1:4
        sol = sim([], 4096; seed, saveat = ts)
        H .+= [hetero(sol.u[findfirst(==(t), sol.t)].σ) for t in ts] ./ 4
    end
    x = log.(ts)
    @test cor(x, H)^2 > 0.95 && cov(x, H) / var(x) < -0.02
    # … and frozen at T = 0 (PRE §III B4)
    sol = sim([:T => 0.0], 1000; saveat = [100, 1000])
    @test abs(hetero(sol.u[end].σ) - hetero(sol.u[1].σ)) < 0.02
    # the area constraint's strength decides survival (PRE §III B5, Table III, T = 5)
    alive(σ) = (v = [count(==(c), σ) for c in eachindex(k)]; (count(>(0), v[k .== 1]), count(>(0), v[k .== 2])))
    @test [alive(sim([:λ => λ, :T => 5.0], 1600).u[end].σ) for λ in (0.1, 0.2, 0.5)] == [(0, 0), (32, 0), (32, 32)]
    # light cells are slightly smaller (PRL p. 2014); not with symmetric self-adhesion
    Δarea(σ) = (v = [count(==(c), σ) for c in eachindex(k)]; mean(v[k .== 1]) - mean(v[k .== 2]))
    @test Δarea(sim([], 1000).u[end].σ) > 1
    @test abs(Δarea(sim([:J => [0 16 16; 16 8 11; 16 11 8]], 1000).u[end].σ)) < 0.5
    # expensive light–medium bonds reverse the layers: dark cells outside (PRE §III D, Fig. 20)
    for seed in 1:2
        σ = sim([:J => [0 16 30; 16 2 11; 30 11 14]], 1600; seed).u[end].σ
        @test medium_fraction(σ, :lM) < 0.005 && radius_ratio(σ) > 1.3
    end
end

@testset "Niculescu et al. (2015), Wortel et al. (2021): Act migration" begin
    G = 100
    base = [:λ => 50.0, :V₀ => 500.0, :λₛ => 2.0, :S₀ => 340.0, :T => 20.0, :J => [0.0 20.0; 20.0 100.0]]
    circ(σ, d) = (θ = [2π * (i[d] - 1) / G for i in findall(==(1), σ)]; mod(atan(mean(sin.(θ)), mean(cos.(θ))) * G / 2π, G))
    mi(a) = a - G * round(a / G)
    function sim(pars, nmcs; seed)
        s = zeros(Int32, G, G); s[39:61, 39:61] .= 1                      # a 23² cell (area 529)
        return solve(PottsProblem(WortelAct(; name = :w, lattice = (G, G)), vcat([ownership => s, kind => [:endothelial]],
            base, pars), (0, nmcs); seed), SequentialCPM(; proposal = Moore(1)); saveat = 0:5:nmcs)
    end
    function track(sol; burn = 20)                                      # steps every 5 MCS
        cs = [(circ(u.σ, 1), circ(u.σ, 2)) for u in sol.u]
        st = [(mi(cs[j + 1][1] - cs[j][1]), mi(cs[j + 1][2] - cs[j][2])) for j in 1:(length(cs) - 1)][(burn + 1):end]
        u = [hypot(s...) > 0 ? s ./ hypot(s...) : (0.0, 0.0) for s in st]
        speed = mean(hypot(s...) for s in st) / 5
        persistence = mean(dot(u[j], u[j + 8]) for j in 1:(length(u) - 8))       # lag 40 MCS
        return speed, persistence, hypot(sum(first, st), sum(last, st))
    end
    # speed and persistence rise together with λ_act (UCSP; Wortel 2021 Fig. 2B, C)
    runs = [(λ, track(sim([:λ_act => λ, :max_act => 20.0], 1500; seed))) for λ in (100.0, 200.0, 400.0) for seed in 1:4]
    m(λ, i) = mean(r[2][i] for r in runs if r[1] == λ)
    @test m(100.0, 1) < m(200.0, 1) < m(400.0, 1)
    @test m(100.0, 2) < m(200.0, 2) < m(400.0, 2)
    ranks(v) = invperm(sortperm(v))
    @test cor(ranks([r[2][1] for r in runs]), ranks([r[2][2] for r in runs])) > 0.7
    # without Act there is no persistence; weak Act leaves the cell stationary (Niculescu Fig. 4B)
    @test abs(mean(track(sim([:λ_act => 0.0, :max_act => 20.0], 1500; seed))[2] for seed in 1:4)) < 0.1
    @test all(seed -> track(sim([:λ_act => 10.0, :max_act => 20.0], 1500; seed))[3] < 10, 1:4)
    # amoeboid (max_act 20) moves along its long axis; keratocyte-like (max_act 80) is wider
    # than long in the direction of motion (Niculescu Figs. 4A, 5C)
    function shape(σ)
        c = (circ(σ, 1), circ(σ, 2))
        ps = [(mi(i[1] - 1 - c[1]), mi(i[2] - 1 - c[2])) for i in findall(==(1), σ)]
        M = [mean(p[1]^2 for p in ps) mean(p[1] * p[2] for p in ps); mean(p[1] * p[2] for p in ps) mean(p[2]^2 for p in ps)]
        e = eigen(Symmetric(M))
        return c, e.vectors[:, 2], sqrt(e.values[2] / max(e.values[1], 1e-9))
    end
    function orientation(sol; lag = 4, burn = 20)                       # lag 20 MCS
        sh = [shape(u.σ) for u in sol.u]
        angs = Float64[]; elong = Float64[]
        for j in burn:lag:(length(sh) - lag)
            d = (mi(sh[j + lag][1][1] - sh[j][1][1]), mi(sh[j + lag][1][2] - sh[j][1][2]))
            hypot(d...) < 1 && continue
            push!(angs, acosd(clamp(abs(dot(sh[j][2], collect(d))) / hypot(d...), 0, 1)))
            push!(elong, sh[j][3])
        end
        return mean(angs), mean(elong)
    end
    amoeboid = [orientation(sim([:λ_act => 200.0, :max_act => 20.0], 2000; seed)) for seed in 1:4]
    keratocyte = [orientation(sim([:λ_act => 200.0, :max_act => 80.0], 2000; seed)) for seed in 1:4]
    @test mean(first, amoeboid) < 40 && mean(first, keratocyte) > 50
    @test mean(last, keratocyte) > mean(last, amoeboid)
end

@testset "Akeeb, Marcus & Jiang (2026): leader/follower invasion" begin
    function sim(; μ = 30.0, jlf = 2.0, pp = 0.5, nmcs = 150, seed = 1, W = 99, H = 90, capacity = 1000)
        o = akeeb_state(; lattice = (W, H), pp, seed)
        u = solve(PottsProblem(AkeebInvasion(; name = :a, lattice = (W, H)), [o; :μ => μ; :J => akeeb_contacts(jlf)],
            (0, nmcs); capacity, seed), SequentialCPM(; proposal = VonNeumann(1))).u[end]
        return merge(akeeb_metrics(u.σ, u.cell.kind .== 1, length(o[2].second)), core_singles(u.σ))
    end
    # motility grades the invasion (the strongest correlate of invasive area in the paper)
    for seed in 1:3
        y = [sim(; μ, seed).leader_mean_y for μ in (0.0, 15.0, 30.0)]
        @test y[1] < y[2] < y[3]
    end
    # leader–follower adhesion decides collective vs single-cell escape
    s(jlf) = [sim(; jlf, seed) for seed in 1:4]
    strong, mid, weak = s(-5.0), s(2.0), s(5.0)
    @test all(m -> m.singles == 0 && m.detached == 0, strong)
    @test mean(m -> m.singles, weak) > mean(m -> m.singles, mid) >= 2
    # the published sample (500×300, J_LF = 2, μ = 24, 700 MCS): 578 divisions in the paper
    full = sim(; μ = 24.0, W = 500, H = 300, nmcs = 700, capacity = 4000)
    @test abs(full.divisions - 578) <= 50
    @test 150 <= full.singles <= 300
    @test full.leader_front == full.outer_front                         # a leader leads
end
