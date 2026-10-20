# Fields after the field-compiler cutover (C8): `@equations D(c) ~ …` of a field is lowered by
# the field compiler (LatticePDE → LatticeFields) and stepped by explicit Euler over each MCS.
# Oracles: the discrete Fourier factor of FTCS, mass conservation, a hand FTCS stepper; each
# with a negative control (D-048).
using Potts: CorePotts
using StableRNGs: StableRNG

# Hand FTCS on a 2D box: `n` substeps of `dt/n`; periodic or zero-flux faces; `rate(c, i, j)`
# the reaction; the update clipped below at `lower`
function fd_ftcs(c0, D, h, dt, n; periodic, rate = (c, i, j) -> 0.0, lower = nothing)
    c = copy(c0)
    nx, ny = size(c)
    for _ in 1:n
        new = similar(c)
        for j in 1:ny, i in 1:nx
            lap = 0.0
            for (di, dj, hd) in ((1, 0, h[1]), (-1, 0, h[1]), (0, 1, h[2]), (0, -1, h[2]))
                a, b = i + di, j + dj
                if periodic
                    a, b = mod1(a, nx), mod1(b, ny)
                elseif !(1 <= a <= nx && 1 <= b <= ny)
                    continue                                       # zero flux: the ghost is the site
                end
                lap += (c[a, b] - c[i, j]) / hd^2
            end
            v = c[i, j] + dt / n * (D * lap + rate(c, i, j))
            new[i, j] = lower === nothing ? v : max(v, lower)
        end
        c = new
    end
    return c
end

@potts_model FdPeriodic begin
    @kinds medium A
    @parameters Dc = 1.0
    @variables c(field) = 0.0
    @lattice Lattice((16, 8); boundary = Periodic(), spacing = (2.0, 2.0))
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdClosed begin
    @kinds medium A
    @parameters begin
        Dc = 1.0
        k = 0.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c) - k * c
    @sweep Metropolis(; temperature = 1.0)
end
# defaults that are not zero, for the PDESystem of `Potts.fields` (F1, V13)
@potts_model FdDefaults begin
    @kinds medium A
    @parameters begin
        Dc = 1.0
        k = 0.5
    end
    @variables c(field) = 2.0
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c) - k * c
    @sweep Metropolis(; temperature = 1.0)
end
# a computed parameter, read through `Potts.fields` (F1)
@potts_model FdComputedRate begin
    @kinds medium A
    @parameters begin
        Dc = 1.0
        k = 0.5
        k2 = 2k
    end
    @variables c(field) = 1.0
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c) - k2 * c
    @sweep Metropolis(; temperature = 1.0)
end
# a CPM read other than `kind` in a field equation (an input named `volume`, F1)
@potts_model FdVolumeRead begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.01 * volume
    @sweep Metropolis(; temperature = 1.0)
end
# a frozen kind is a fixed source: σ never moves, so the field has an exact hand oracle
@potts_model FdSource begin
    @kinds medium A[frozen]
    @parameters begin
        Dc = 0.2
        s = 0.05
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c) + s * (kind == A)
    @sweep Metropolis(; temperature = 1.0)
end
# two fields in two solver groups; `u` reads `c` from its own array
@potts_model FdTwo begin
    @kinds medium A[frozen]
    @variables begin
        c(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(c) ~ 0.2 * Δ(c) + 0.05 * (kind == A)
        D(u) ~ 0.1 * Δ(u) + 0.5 * c
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdDecay begin
    @kinds medium A
    @variables c(field) = 1.0
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ -2.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdMask begin
    @kinds medium A wall[frozen]
    @parameters v = 3.0
    @variables c(field) = 0.0
    @lattice Lattice((10, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.2 * Δ(c)
    @boundary c begin
        sites(kind == wall) => Dirichlet(v)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdHex begin
    @structural_parameters begin
        boundary = Periodic()
        dims = (8, 6)
    end
    @kinds medium A
    @parameters Dc = 0.1
    @variables c(field) = 0.0
    @lattice Lattice(dims; geometry = Hexagonal(), boundary)
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdHalf begin
    @kinds medium A
    @parameters Dc = 1.0
    @variables c(field) = 0.0, [lattice_storage = Float16]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdDomain begin
    @structural_parameters begin
        dims = (40, 40)
        domain = x -> (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2
    end
    @kinds medium A
    @parameters Dc = 0.2
    @variables c(field) = 0.0
    @lattice Lattice(dims; boundary = Closed(), domain)
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdStripe begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((9, 9); boundary = Closed(), domain = x -> 3 <= x[1] <= 7)
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.1 * Δ(c)
    @boundary c begin
        x => (Dirichlet(0.0), Dirichlet(100.0))
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdRand begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.1 * Δ(c) + 0.01 * rand()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdDomainWord begin
    @kinds medium A
    @variables domain(field) = 0.0
    @lattice Lattice((9, 9); boundary = Closed(), domain = x -> 3 <= x[1] <= 7)
    @energy cells(A) => (volume - 4.0)^2
    @equations D(domain) ~ 0.1 * Δ(domain)
    @sweep Metropolis(; temperature = 1.0)
end

fd_empty(dims) = [ownership => zeros(Int32, dims...), kind => Symbol[]]
fd_rand(dims) = rand(StableRNG(7), dims...)
# the field `c` after each of `n` MCS
fd_mcs(prob, n; alg = SequentialCPM()) = (integ = init(prob, alg; save_start = false);
                                          [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:n])
fd_source_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])
fd_err(f) = try
    f(); nothing
catch e
    sprint(showerror, e)
end
fd_n(integ, j = 1) = CorePotts._runtime(getfield(integ.ctx, Symbol(:__fields, j))).n
# The old field path's Laplacian (CorePotts.laplacian before C8), as a hand oracle: square, the
# missing neighbor across a closed face is the face ghost (`2v − c` for Dirichlet `v`, else
# `c`) and across the domain edge `c`; hexagonal, `2/(3h²) Σ (cₙ − c)` over the six axial
# neighbors, a missing one reading `c`. `n` explicit substeps of `1/n` (clipped at `lower`).
const FD_HEX6 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
function fd_oldpath(c0, lat, D, n; h = 1.0, bc = nothing, lower = nothing)
    c = copy(c0)
    N = ndims(lat)
    hex = lat.geometry isa CorePotts.Hexagonal
    for _ in 1:n
        new = similar(c)
        for i in eachindex(c)
            x = CorePotts.coordinates(lat, i)
            ci = c[i]
            CorePotts.in_domain(lat, i) || (new[i] = ci; continue)        # outside: kept
            lap = 0.0
            if hex
                for o in FD_HEX6
                    inside, y = CorePotts.shift(lat, x, Int32.(o))
                    lap += (inside ? c[CorePotts.linear_index(lat, y)] : ci) - ci
                end
                lap *= 2 / (3 * h^2)
            else
                for d in 1:N, (s, side) in ((1, 2), (-1, 1))
                    o = ntuple(k -> Int32(k == d ? s : 0), N)
                    inside, y = CorePotts.shift(lat, x, o)
                    v = bc === nothing ? nothing : bc[d][side]
                    nb = inside ? c[CorePotts.linear_index(lat, y)] :
                         CorePotts._within_faces(lat, x, o) || v === nothing ? ci : 2v - ci
                    lap += (nb - ci) / h^2
                end
            end
            v = ci + D * lap / n
            new[i] = lower === nothing ? v : max(v, lower)
        end
        c = new
    end
    return c
end

@testset "fields: the Fourier factor of FTCS, with spacing (periodic)" begin
    dims, h = (16, 8), (2.0, 2.0)
    c0 = [cos(2π * (i - 1) / 16) for i in 1:16, j in 1:8]
    for (Dc, nexp) in ((1.0, 2), (4.0, 5))           # ρ = Dc·Σ 4/h² = 2Dc: n = ceil(2Dc/1.8)
        prob = PottsProblem(FdPeriodic(; name = :f), [fd_empty(dims); :c => c0; :Dc => Dc], (0, 1);
            field_solver = ExplicitEuler())
        integ = init(prob, SequentialCPM())
        @test fd_n(integ) == nexp
        step!(integ)
        c = Array(current_state(integ).site.c)
        g = 1 - (1 / nexp) * Dc * (4 / h[1]^2) * sin(π / 16)^2      # the per-substep factor of mode 1
        @test maximum(abs.(c .- g^nexp .* c0)) < 1e-13
        @test maximum(abs.(c .- (1 - (1 / (nexp + 1)) * Dc * sin(π / 16)^2)^(nexp + 1) .* c0)) > 1e-6   # control: n + 1
    end
end

@testset "fields: auto substep counts, odd and even counts, the hand stepper" begin
    dims = (12, 10)
    c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
    # ρ = Dc·8 + k: 5 at Dc = 1; 2 at Dc = 0.45; 3 with a reaction of 0.2
    for (Dc, k, nexp) in ((1.0, 0.0, 5), (0.45, 0.0, 2), (0.45, 0.2, 3))
        prob = PottsProblem(FdClosed(; name = :f), [fd_empty(dims); :c => c0; :Dc => Dc; :k => k], (0, 2);
            field_solver = ExplicitEuler())
        integ = init(prob, SequentialCPM())
        @test fd_n(integ) == nexp
        step!(integ); step!(integ)
        hand = fd_ftcs(fd_ftcs(c0, Dc, (1, 1), 1.0, nexp; periodic = false, rate = (c, i, j) -> -k * c[i, j]),
            Dc, (1, 1), 1.0, nexp; periodic = false, rate = (c, i, j) -> -k * c[i, j])
        @test maximum(abs.(Array(current_state(integ).site.c) .- hand)) < 1e-14
    end
    # an explicit count is a minimum: 3 (odd: the scratch is copied back) and 4 (even)
    for n in (3, 4)
        prob = PottsProblem(FdClosed(; name = :f), [fd_empty(dims); :c => c0; :Dc => 0.1], (0, 1);
            field_solver = ExplicitEuler(substeps = n))
        integ = init(prob, SequentialCPM())
        @test fd_n(integ) == n
        step!(integ)
        c = Array(current_state(integ).site.c)
        @test maximum(abs.(c .- fd_ftcs(c0, 0.1, (1, 1), 1.0, n; periodic = false))) < 1e-15
        @test maximum(abs.(c .- fd_ftcs(c0, 0.1, (1, 1), 1.0, n + 1; periodic = false))) > 1e-8   # control
    end
end

@testset "fields: mass conservation (periodic and closed), a sink as control" begin
    c0 = [1.0 + sin(i) * cos(2j) for i in 1:16, j in 1:8]
    sol = solve(PottsProblem(FdPeriodic(; name = :f), [fd_empty((16, 8)); :c => c0], (0, 5);
        field_solver = ExplicitEuler()), SequentialCPM())
    @test abs(sum(sol.u[end].site.c) - sum(c0)) < 1e-11 * sum(c0)
    @test maximum(abs.(sol.u[end].site.c .- c0)) > 1e-3                              # the field moved
    c1 = [1.0 + sin(i) * cos(2j) for i in 1:12, j in 1:10]
    closed(k) = solve(PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :c => c1; :k => k], (0, 5);
        field_solver = ExplicitEuler()), SequentialCPM()).u[end].site.c
    @test abs(sum(closed(0.0)) - sum(c1)) < 1e-11 * sum(c1)
    @test sum(closed(0.05)) < 0.9 * sum(c1)                                          # control: a sink
end

@testset "fields: CPM terms are filled inputs (a frozen source, hand oracle)" begin
    op = fd_source_op((12, 10))
    prob = PottsProblem(FdSource(; name = :f), op, (0, 3); field_solver = ExplicitEuler(substeps = 2))
    sol = solve(prob, SequentialCPM())
    src = op[1].second .== 1
    hand = zeros(12, 10)
    for _ in 1:3
        hand = fd_ftcs(hand, 0.2, (1, 1), 1.0, 2; periodic = false, rate = (c, i, j) -> 0.05 * src[i, j])
    end
    @test maximum(abs.(sol.u[end].site.c .- hand)) < 1e-15
    @test maximum(abs.(sol.u[end].site.c .- 2 .* hand)) > 1e-3                      # control
    # the filled input is a site array of the state
    @test any(k -> endswith(string(k), "__in"), keys(prob.u0.site))
end

@testset "fields: two solver groups; a later group reads the earlier field's array" begin
    op = fd_source_op((12, 10))
    sys = FdTwo(; name = :t)
    cvar = only(filter(x -> string(x) in ("c", "c(t)"), Potts.variables(sys)))
    uvar = only(filter(x -> string(x) in ("u", "u(t)"), Potts.variables(sys)))
    prob = PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 2),
        solvers = [uvar => ExplicitEuler(substeps = 3)])
    @test count(x -> x isa CorePotts.FieldPhase, prob.f.phases.after_mcs) == 2
    sol = solve(prob, SequentialCPM())
    src = op[1].second .== 1
    c, u = zeros(12, 10), zeros(12, 10)
    for _ in 1:2
        c = fd_ftcs(c, 0.2, (1, 1), 1.0, 2; periodic = false, rate = (q, i, j) -> 0.05 * src[i, j])
        cc = c
        u = fd_ftcs(u, 0.1, (1, 1), 1.0, 3; periodic = false, rate = (q, i, j) -> 0.5 * cc[i, j])
    end
    @test maximum(abs.(sol.u[end].site.c .- c)) < 1e-15
    @test maximum(abs.(sol.u[end].site.u .- u)) < 1e-14
    # one group (both fields with the same solver): Jacobi inside the substep, a different result
    one = solve(PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 3)), SequentialCPM())
    @test count(x -> x isa CorePotts.FieldPhase, PottsProblem(sys, op, (0, 2);
        field_solver = ExplicitEuler(substeps = 3)).f.phases.after_mcs) == 1
    @test maximum(abs.(one.u[end].site.u .- u)) > 1e-6
end

@testset "fields: lower clip, also at init" begin
    op = fd_empty((6, 6))
    clip = solve(PottsProblem(FdDecay(; name = :d), op, (0, 1); field_solver = ExplicitEuler(substeps = 1, lower = 0.0)),
        SequentialCPM()).u[end].site.c
    free = solve(PottsProblem(FdDecay(; name = :d), op, (0, 1); field_solver = ExplicitEuler(substeps = 1)),
        SequentialCPM()).u[end].site.c
    @test all(==(0.0), clip)
    @test all(≈(-1.0), free)                                                          # control
end

@testset "fields: masked conditions, the at-init clamp on fresh states only" begin
    σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
    op = [ownership => σ, kind => [:wall]]
    wall = σ .== 1
    prob = PottsProblem(FdMask(; name = :m), op, (0, 4); field_solver = ExplicitEuler(substeps = 2))
    integ = init(prob, SequentialCPM())
    @test all(==(3.0), Array(current_state(integ).site.c)[wall])                      # clamped at init
    @test all(==(0.0), Array(current_state(integ).site.c)[.!wall])
    foreach(_ -> step!(integ), 1:2)
    u = current_state(integ)
    @test all(==(3.0), Array(u.site.c)[wall]) && sum(u.site.c[.!wall]) > 0
    # a restored state is not fresh: the clamp does not run at init
    ck = checkpoint(integ)
    ck.state.site.c[wall] .= 5.0
    again = init(prob, SequentialCPM(); checkpoint = ck)
    @test all(==(5.0), Array(current_state(again).site.c)[wall])
    step!(again)
    @test all(==(3.0), Array(current_state(again).site.c)[wall])                      # the mask of the next MCS
    # checkpoint continuation is exact
    whole = solve(prob, SequentialCPM()).u[end]
    integ = init(prob, SequentialCPM()); foreach(_ -> step!(integ), 1:2)
    rest = solve!(init(prob, SequentialCPM(); checkpoint = checkpoint(integ))).u[end]
    @test rest.σ == whole.σ && rest.site.c == whole.site.c
    # a new value through `remake` rebinds the mask value
    @test all(==(7.0), solve(remake(prob; p = [:v => 7.0]), SequentialCPM()).u[end].site.c[wall])
end

@testset "fields: a parameter change rebinds the substep count and the rates" begin
    c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
    prob = PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :c => c0], (0, 1); field_solver = ExplicitEuler())
    a = init(prob, SequentialCPM())
    b = init(remake(prob; p = [:Dc => 0.45]), SequentialCPM())
    @test fd_n(a) == 5 && fd_n(b) == 2
    step!(b)
    @test maximum(abs.(Array(current_state(b).site.c) .- fd_ftcs(c0, 0.45, (1, 1), 1.0, 2; periodic = false))) < 1e-15
    # in a running integrator: new parameter values are rebound at the next field phase
    a.p = remake(prob; p = [:Dc => 0.45]).p
    step!(a)
    @test fd_n(a) == 2
    @test maximum(abs.(Array(current_state(a).site.c) .- fd_ftcs(c0, 0.45, (1, 1), 1.0, 2; periodic = false))) < 1e-15
end

@testset "fields: setp, then reinit!, keeps the step's substeps (masked model)" begin
    σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
    op = [ownership => σ, kind => [:wall]]
    prob = PottsProblem(FdMask(; name = :m), op, (0, 4); field_solver = ExplicitEuler(substeps = 2))
    fresh = init(remake(prob; p = [:v => 7.0]), SequentialCPM()); foreach(_ -> step!(fresh), 1:3)
    integ = init(prob, SequentialCPM()); step!(integ)
    setp(integ, :v)(integ, 7.0)                          # a parameter change, then a new start
    reinit!(integ, prob.u0)                              # the at-init clamp runs with the new parameters
    @test fd_n(integ) == 2                               # the step's count, not the clamp's one substep
    foreach(_ -> step!(integ), 1:3)
    u, w = current_state(integ), current_state(fresh)
    @test Array(u.σ) == Array(w.σ) && Array(u.site.c) == Array(w.site.c)
    @test sum(u.site.c[σ .== 0]) > 0                     # control: the field evolves
end

@potts_model FdTab begin
    @kinds medium A
    @parameters begin
        Dc = 0.2
        δ[kind] = [0.5, 0.0]
    end
    @variables c(field) = 1.0
    @lattice Lattice((10, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c) - δ[kind] * c
    @sweep Metropolis(; temperature = 1.0)
end
@testset "fields: only the field's own parameters and tables (by value) rebind its launches" begin
    σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
    prob = PottsProblem(FdMask(; name = :m), [ownership => σ, kind => [:wall]], (0, 4); field_solver = ExplicitEuler(substeps = 2))
    integ = init(prob, SequentialCPM()); step!(integ)
    rt = CorePotts._runtime(integ.ctx.__fields1)
    even = rt.even
    setp(integ, :v)(integ, 3.0)                          # a new parameter object, equal values
    step!(integ)
    @test rt.even === even && rt.p === integ.p           # kept: nothing the field reads changed
    setp(integ, :v)(integ, 4.0)
    step!(integ)
    @test rt.even !== even                               # control: the mask value changed, rebound
    @test all(==(4.0), Array(current_state(integ).site.c)[σ .== 1])
    # a kind table: an equal table keeps the launches, a new one rebinds and is read
    tp = PottsProblem(FdTab(; name = :t), [ownership => σ, kind => [:A]], (0, 2); field_solver = ExplicitEuler(substeps = 1))
    a = init(tp, SequentialCPM()); step!(a)
    rt = CorePotts._runtime(a.ctx.__fields1); even = rt.even
    setp(a, :δ)(a, [0.5, 0.0])
    step!(a)
    @test rt.even === even
    s1 = deepcopy(current_state(a))
    setp(a, :δ)(a, [2.0, 0.0])
    step!(a)
    @test rt.even !== even
    b = init(remake(tp; u0 = s1, tspan = (2, 3), p = [:δ => [2.0, 0.0]]), SequentialCPM()); step!(b)
    @test Array(current_state(a).site.c) == Array(current_state(b).site.c)
    @test Array(current_state(a).site.c) != Array(s1.site.c)              # control
end

# a rate behind an `ifelse` gate that reads no field (Merks' `t ≥ t_relax`): bounded through
# its arms, so an explicit count stays a minimum over the diffusion (no warning)
@potts_model FdGate begin
    @kinds medium A
    @parameters begin
        Dc = 1.0
        t0 = 1.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ ifelse(mcs >= t0, Dc * Δ(c), 0.0)
    @sweep Metropolis(; temperature = 1.0)
end
@testset "fields: an ifelse gate is bounded through its arms" begin
    op = [fd_empty((12, 10)); :c => fd_rand((12, 10))]
    auto = PottsProblem(FdGate(; name = :g), op, (0, 3); field_solver = ExplicitEuler())
    @test fd_n(init(auto, SequentialCPM())) == 5                         # ceil(1.0·8 / 1.8)
    one = @test_logs PottsProblem(FdGate(; name = :g), op, (0, 3); field_solver = ExplicitEuler(substeps = 1))
    integ = init(one, SequentialCPM())
    @test fd_n(integ) == 5                                               # the request 1 is a minimum
    setp(integ, :Dc)(integ, 2.0)
    step!(integ)
    @test fd_n(integ) == 9                                               # ceil(2.0·8 / 1.8)
    @test all(isfinite, Array(current_state(integ).site.c))
end

# The threaded host Cartesian loop (above HOST_GRAIN sites, more than one thread): the same
# field as one thread, and a warm MCS allocates nothing (two fresh processes)
const FD_THREADS_RUN = raw"""
using Potts
@potts_model FdBig begin
    @kinds medium A
    @parameters Dc = 0.2
    @variables c(field) = 0.0
    @lattice Lattice((120, 100); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 1.0)
end
function fd_threads_run()
    c0 = [sin(i / 7) * cos(j / 5) for i in 1:120, j in 1:100]
    prob = PottsProblem(FdBig(; name = :b), [ownership => zeros(Int32, 120, 100), kind => Symbol[], :c => c0], (0, 20);
        field_solver = ExplicitEuler())
    integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
    step!(integ); step!(integ)
    a = minimum(_ -> (@allocated step!(integ)), 1:3)
    return a, hash(Array(current_state(integ).site.c))
end
a, h = fd_threads_run()
print(Threads.nthreads(), " ", a, " ", h)
"""
@testset "fields: the threaded host loop equals one thread and allocates nothing" begin
    @test 120 * 100 > Potts.CorePotts.Exec.HOST_GRAIN
    run(t) = split(strip(read(`$(Base.julia_cmd()) --startup-file=no -t $t --project=$(Base.active_project()) -e $FD_THREADS_RUN`,
        String)))
    one, three = run(1), run(3)
    @test parse(Int, one[1]) == 1 && parse(Int, three[1]) == 3
    @test parse(Int, three[2]) == 0 && parse(Int, one[2]) == 0
    @test three[3] == one[3]
end

@testset "fields: hexagonal lattices (the old path's six-point Laplacian)" begin
    for boundary in (Periodic(), Closed())
        prob = PottsProblem(FdHex(; name = :h, boundary), [fd_empty((8, 6)); :c => fd_rand((8, 6))], (0, 3);
            field_solver = ExplicitEuler(substeps = 3))
        u = fd_mcs(prob, 3)
        c = prob.u0.site.c
        for m in 1:3
            c = fd_oldpath(c, prob.lattice, 0.1, 3)
            @test maximum(abs.(u[m] .- c)) < 1e-14
        end
        @test sum(u[end]) ≈ sum(prob.u0.site.c)                                 # zero-sum stencil
        # negative control: the square 4-point stencil is a different field
        sq = fd_ftcs(prob.u0.site.c, 0.1, (1, 1), 1.0, 3; periodic = boundary isa Periodic)
        @test maximum(abs.(u[1] .- sq)) > 1e-3
    end
    # the stencil is exact for a quadratic: Δ|x|² = 4 (Euclidean positions of the axial sites)
    L = (24, 24)
    hl = CorePotts.Lattice(L; geometry = CorePotts.Hexagonal(), boundary = Closed())
    pos(x) = CorePotts.embed(hl, Float64.(Tuple(x)))
    f = [sum(abs2, pos(x)) for x in CartesianIndices(L)]
    prob = PottsProblem(FdHex(; name = :h, boundary = Closed(), dims = L), [fd_empty(L); :c => f], (0, 1);
        field_solver = ExplicitEuler(substeps = 1))
    c1 = solve(prob, SequentialCPM(); save_start = false).u[1].site.c
    @test (c1[10, 12] - f[10, 12]) / 0.1 ≈ 4.0
    # the program reads the six axial neighbors, and only those (the IR's hexagonal offsets)
    prog = first(ph for t in prob.f.phases.mcs if t isa Tuple for ph in t if ph isa CorePotts.FieldPhase).program
    offs = Set(Tuple(Int.(a.offset.a)) for k in prog.kernels for a in k.accesses if any(!iszero, a.offset.a))
    @test offs == Set(FD_HEX6)
end

@testset "fields: an irregular domain (zero flux at its edge, as the old path)" begin
    prob0 = PottsProblem(FdDomain(; name = :d), fd_empty((40, 40)), (0, 1); field_solver = ExplicitEuler(substeps = 2))
    lat = prob0.lattice
    inmask = [CorePotts.in_domain(lat, i) for i in 1:(40 * 40)]
    c0 = zeros(40, 40); c0[18:23, 18:23] .= 1.0; c0[1, 1] = 7.0                 # (1, 1) is outside
    prob = PottsProblem(FdDomain(; name = :d), [fd_empty((40, 40)); :c => c0], (0, 200); field_solver = ExplicitEuler(substeps = 2))
    u = solve(prob, SequentialCPM(); save_start = false).u
    @test sum(u[end].site.c[inmask]) ≈ 36.0                                   # conserved inside
    @test u[end].site.c[1, 1] == 7.0                                          # outside: no exchange
    @test maximum(u[end].site.c[inmask]) - minimum(u[end].site.c[inmask]) < 0.05  # equilibrates inside
    # the old path's numerics, MCS by MCS, on a random field (outside sites too)
    r = fd_rand((40, 40))
    pr = PottsProblem(FdDomain(; name = :d), [fd_empty((40, 40)); :c => r], (0, 3); field_solver = ExplicitEuler(substeps = 2))
    ur = fd_mcs(pr, 3)
    c = r
    for m in 1:3
        c = fd_oldpath(c, lat, 0.2, 2)
        @test maximum(abs.(ur[m] .- c)) < 1e-14
    end
    # negative control: the full box exchanges across the disk's edge
    full = PottsProblem(FdDomain(; name = :f, domain = x -> true), [fd_empty((40, 40)); :c => r], (0, 1);
        field_solver = ExplicitEuler(substeps = 2))
    @test maximum(abs.(fd_mcs(full, 1)[1] .- ur[1])) > 1e-3
    # faces against the domain edge: the face value applies at the box face, not at the edge
    st = PottsProblem(FdStripe(; name = :s), fd_empty((9, 9)), (0, 1); field_solver = ExplicitEuler(substeps = 1))
    us = solve(st, SequentialCPM(); save_start = false).u[1].site.c
    @test us == fd_oldpath(zeros(9, 9), st.lattice, 0.1, 1; bc = ((0.0, 100.0), (nothing, nothing)))
    @test all(iszero, us)                                                     # x = 7 is the edge: zero flux
    # control: on the full box the same face drives the edge site
    @test fd_oldpath(zeros(9, 9), Potts.CorePotts.Lattice((9, 9); boundary = Closed()), 0.1, 1;
        bc = ((0.0, 100.0), (nothing, nothing)))[9, 5] ≈ 0.1 * 200.0
end

@testset "fields: refusals name the reason" begin
    @test occursin("rand()", something(fd_err(() -> PottsProblem(FdRand(; name = :r), fd_empty((8, 6)), (0, 1);
        field_solver = ExplicitEuler(substeps = 1))), ""))
    @test occursin("field solver", something(fd_err(() -> PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1);
        field_solver = RK4())), ""))
end

@testset "fields: a warm MCS allocates nothing on the CPU" begin
    op = fd_source_op((12, 10))
    integ = init(PottsProblem(FdSource(; name = :f), op, (0, 100); field_solver = ExplicitEuler(substeps = 3)), SequentialCPM();
        save_start = false, save_end = false)
    step!(integ)
    @test (@allocated step!(integ)) == 0
end

# P5 C3/4-1: a parameter that does not convert to the problem's scalar type is a named error.
# F1 (PO41): the field parameter `Dc` is not told the CPM reason (on f9a77dd3 the message said
# "CPM parameters are plain numbers … derivative is zero almost everywhere" for `Dc`)
struct FdNotANumber <: Real end
@testset "parameters: a value that does not convert is named, with a role-neutral reason" begin
    err = fd_err(() -> PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :Dc => FdNotANumber()], (0, 1);
        field_solver = ExplicitEuler()))
    @test occursin("`Dc`", something(err, "")) && occursin("scalar type", something(err, ""))
    @test occursin("field and ODE parameters are planned", something(err, ""))
    @test !occursin("CPM parameters are plain numbers", something(err, ""))
end

# ---------------------------------------------------------------------------------------
# The sub-MCS interleave: `@schedule repeat(n, sweep(fraction = 1//n), …)`
@potts_model FdChemo begin
    @kinds medium A
    @parameters begin
        χ = 400.0
        Dc = 0.2
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @equations D(c) ~ Dc * Δ(c) + 0.5 * (kind == A) - 0.1 * c
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model FdChemoPlain begin
    @extend base = FdChemo()
    @schedule sweep, fields
end
@potts_model FdChemoSplit begin                    # the sweep split, nothing between the passes
    @extend base = FdChemo()
    @schedule repeat(4, sweep(fraction = 1//4), after_mcs), fields
end
@potts_model FdChemoInter begin                    # the field stepped between the passes
    @extend base = FdChemo()
    @schedule repeat(4, sweep(fraction = 1//4), fields)
end
@potts_model FdSourceInter begin
    @extend base = FdSource()
    @schedule repeat(4, sweep(fraction = 1//4), fields)
end

fd_chemo_op() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2;
    [ownership => σ, kind => [:A, :A], :c => [0.05 * i for i in 1:24, j in 1:20]])

@testset "@schedule repeat: n passes of 1/n sweeps" begin
    sys = FdChemoInter(; name = :i)
    @test Potts._p(sys, :schedule) == Any[Potts.ScheduleRepeat(4, [:sweep, :fields])]
    @test occursin("repeat(4, sweep(fraction = 1//4), fields)", sprint(show, MIME"text/plain"(), sys))
    for alg in (SequentialCPM(), CheckerboardCPM())
        run(M) = solve(PottsProblem(M(; name = :m), fd_chemo_op(), (0, 3); field_solver = ExplicitEuler(substeps = 2)), alg)
        plain, split, inter = run(FdChemoPlain), run(FdChemoSplit), run(FdChemoInter)
        # oracle: with nothing between the passes the copies are exactly one sweep's
        @test split.u[end].σ == plain.u[end].σ && split.u[end].site.c == plain.u[end].site.c
        @test split.stats.attempts == plain.stats.attempts
        # control: the field stepped between the passes changes the copies
        @test inter.u[end].σ != plain.u[end].σ
    end
    p = PottsProblem(FdChemoSplit(; name = :m), fd_chemo_op(), (0, 1); field_solver = ExplicitEuler(substeps = 2))
    @test any(e -> e isa CorePotts.Repeat && e.n == 4, p.f.phases.mcs)
    @test p.f.fingerprint != PottsProblem(FdChemoPlain(; name = :m), fd_chemo_op(), (0, 1);
        field_solver = ExplicitEuler(substeps = 2)).f.fingerprint
    # a sweep that cannot split is refused at `init`
    @test occursin("skip_interior", something(fd_err(() -> init(p, SequentialCPM(; skip_interior = true))), ""))
end

@testset "@schedule repeat: fields inside step 1/n of the MCS per pass (hand oracle)" begin
    op = fd_source_op((12, 10))
    prob = PottsProblem(FdSourceInter(; name = :f), op, (0, 2); field_solver = ExplicitEuler(substeps = 2))
    integ = init(prob, SequentialCPM())
    @test fd_n(integ) == 2
    sol = solve(prob, SequentialCPM())
    src = op[1].second .== 1
    hand = zeros(12, 10)
    for _ in 1:(2 * 4)
        hand = fd_ftcs(hand, 0.2, (1, 1), 0.25, 2; periodic = false, rate = (c, i, j) -> 0.05 * src[i, j])
    end
    @test maximum(abs.(sol.u[end].site.c .- hand)) < 1e-15
    whole = solve(PottsProblem(FdSource(; name = :f), op, (0, 2); field_solver = ExplicitEuler(substeps = 2)), SequentialCPM())
    @test maximum(abs.(whole.u[end].site.c .- hand)) > 1e-6                          # control: one step of the MCS
end

@testset "@schedule repeat: errors name the offender" begin
    bad(ex) = fd_err(() -> Potts.schedule_repeat(ex))
    @test occursin("sweep(fraction = 1//4)", something(bad(:(repeat(4, sweep(fraction = 1 // 2), fields))), ""))
    @test occursin("sweep(fraction = 1//4)", something(bad(:(repeat(4, sweep, fields))), ""))
    @test occursin("cannot be repeated", something(bad(:(repeat(4, sweep(fraction = 1 // 4), components))), ""))
    @test occursin("holds the sweep", something(bad(:(repeat(4, fields))), ""))
    @test occursin("count n ≥ 2", something(bad(:(repeat(1, sweep(fraction = 1 // 1)))), ""))
    @test bad(:(repeat(4, sweep(; fraction = 1 // 4), fields, after_mcs))) === nothing
end

@testset "fields: the field state is never lost (checkpoints, reinit!, remake, copies, ensembles)" begin
    for (M, alg) in ((FdChemo, SequentialCPM()), (FdChemo, CheckerboardCPM()), (FdChemoInter, SequentialCPM()))
        prob = PottsProblem(M(; name = :c), fd_chemo_op(), (0, 6); field_solver = ExplicitEuler())
        whole = solve(prob, alg).u[end]
        same(u) = Array(u.σ) == Array(whole.σ) && Array(u.site.c) == Array(whole.site.c)
        # a checkpoint taken mid-run, written, read back and continued: the uninterrupted run
        a = init(prob, alg); foreach(_ -> step!(a), 1:3)
        path = tempname()
        save_checkpoint(path, checkpoint(a))
        @test same(solve!(init(prob, alg; checkpoint = load_checkpoint(path))).u[end])
        # the original integrator continues unchanged by the checkpoint
        @test same(solve!(a).u[end])
        # a state written into another integrator (`reinit!` at MCS 3), then continued
        b = init(prob, alg); foreach(_ -> step!(b), 1:3)
        s3 = deepcopy(current_state(b))
        c = init(prob, alg); step!(c)
        reinit!(c, s3; t0 = 3)
        @test same(solve!(c).u[end])
        # `remake` from the MCS-3 state (fields included)
        @test same(solve(remake(prob; u0 = s3, tspan = (3, 6)), alg).u[end])
        # a copy of a running integrator steps on its own copy of the fields
        d = init(prob, alg); foreach(_ -> step!(d), 1:3)
        e = deepcopy(d)
        step!(e)
        @test Array(current_state(d).site.c) == Array(s3.site.c)                   # d untouched
        @test same(solve!(e).u[end]) && same(solve!(d).u[end])
        # negative control: a run missing its field state differs
        z = deepcopy(s3); z.site.c .= 0
        @test !same(solve(remake(prob; u0 = z, tspan = (3, 6)), alg).u[end])
    end
    # ensembles: each trajectory carries its own field, equal to its single run
    prob = PottsProblem(FdChemo(; name = :c), fd_chemo_op(), (0, 4); field_solver = ExplicitEuler())
    sim = solve(EnsembleProblem(prob), SequentialCPM(); trajectories = 3)
    for i in 1:3
        one = solve(remake(prob; replica = prob.replica + UInt32(i)), SequentialCPM()).u[end]
        @test sim.u[i].u[end].σ == one.σ && sim.u[i].u[end].site.c == one.site.c
    end
    @test sim.u[1].u[end].site.c != sim.u[2].u[end].site.c                         # independent trajectories
end

@testset "fields: number types per role (lattice_storage, the backend's default T)" begin
    c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
    for T in (Float64, Float32)
        prob = PottsProblem(FdHalf(; name = :h), [fd_empty((12, 10)); :c => c0], (0, 3); T,
            field_solver = ExplicitEuler(substeps = 8))
        @test eltype(prob.u0.site.c) == Float16 && eltype(prob.u0.site.c__next) == Float16
        u = fd_mcs(prob, 3)
        @test eltype(u[end]) == Float16
        ref = fd_ftcs(Float64.(Float16.(c0)), 1.0, (1, 1), 3.0, 8 * 3; periodic = false)
        @test maximum(abs.(u[end] .- ref)) < 5e-3                     # Float16 rounding per substep
        # control: the same model stored in T differs by the rounding
        full = PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :c => c0], (0, 3); T,
            field_solver = ExplicitEuler(substeps = 8))
        @test eltype(full.u0.site.c) == T && fd_mcs(full, 3)[end] != u[end]
    end
    @test_throws ArgumentError Potts.variable(only(Potts.Symbolics.@variables q), :site; lattice_storage = Float16)
    # the default state type follows the backend (host: Float64)
    @test eltype(PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1);
        backend = CorePotts.KernelAbstractions.CPU(), field_solver = ExplicitEuler()).u0.site.c) == Float64
end

# ---------------------------------------------------------------------------------------
# F1: no silent wrongs, and messages in the model's words (refusal inventory)
using Potts.LatticePDE: DivKGrad
@potts_model FdExprFace begin
    @kinds medium A
    @parameters begin
        Dc = 0.2
        g1 = 1.0
        g2 = 2.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @boundary c begin
        x => (Dirichlet(g1 + g2), NoFlux())
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdComputedFace begin
    @kinds medium A
    @parameters begin
        Dc = 0.2
        g1 = 1.0
        g2 = 2.0
        g = g1 + g2
    end
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @boundary c begin
        x => (Dirichlet(g), NoFlux())
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdKindNonlinear begin
    @kinds medium A
    @parameters Dc = 0.2
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ Dc * Δ(c) - c^2 * ifelse(kind == 1, 1.0, 0.0)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FdDivK begin
    @kinds medium A
    @parameters Dc = 0.2
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ DivKGrad(:harmonic)(Dc, c)
    @sweep Metropolis(; temperature = 1.0)
end

@testset "F1 SD-14: a boundary value is a number, a parameter or a number times one" begin
    # base: accepted by `@boundary`, then refused by LatticePDE in its own words ("the boundary
    # value `g1 + g2` must be a number, …"); now one message at the model, with the route
    err = fd_err(() -> FdExprFace(; name = :f))
    @test occursin("@boundary c", something(err, "")) && occursin("@parameters g = g1 + g2", something(err, ""))
    # the route: a computed parameter runs, and follows its parameters
    prob = PottsProblem(FdComputedFace(; name = :f), fd_empty((8, 8)), (0, 2); field_solver = ExplicitEuler())
    a = solve(prob).u[end].site.c
    b = solve(Potts.remake(prob; p = [:g1 => 3.0])).u[end].site.c
    @test maximum(a) > 0 && maximum(b) > maximum(a)
end

@testset "F1 V13: Potts.fields returns the model's PDESystem" begin
    # base: `Potts.fields(model) === nothing` on a model with fields
    @test Potts.fields(FdClosed(; name = :f)) isa Potts.ModelingToolkitBase.PDESystem
    @test Potts.fields(mtkcompile(FdClosed(; name = :f))) isa Potts.ModelingToolkitBase.PDESystem
    @test isequal(Potts.ModelingToolkitBase.equations(Potts.fields(FdClosed(; name = :f))),
                  Potts.ModelingToolkitBase.equations(Potts.fields(mtkcompile(FdClosed(; name = :f)))))
    # … with the model's defaults, so `discretize` takes it as it is (base, round 0: the field
    # and the parameters had no value, "no initial condition" / NaN): c(1) = 2 (1 − 0.05)^10
    LP = Potts.LatticePDE
    for m in (FdDefaults(; name = :f), mtkcompile(FdDefaults(; name = :f)))
        prob = LP.discretize(Potts.fields(m), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64, problem = :owned))
        s = LP.solve(prob, LP.ExplicitEuler(; dt = 0.1, substeps = 1))
        @test s.retcode == Potts.SciMLBase.ReturnCode.Success && all(≈(2 * 0.95^10), s[:c][end])
        o = LP.discretize(Potts.fields(m), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64))
        @test o isa Potts.SciMLBase.ODEProblem && o.p == [1.0, 0.5] && all(==(2.0), o.u0)
    end
    # a computed parameter folds and reads (round 1: reading threw): c(1) = (1 − 0.1)^10
    prob = LP.discretize(Potts.fields(FdComputedRate(; name = :f)), LP.LatticeDiscretization(LP.Grid((6, 4));
        T = Float64, problem = :owned))
    @test LP.getp(prob, :k2)(prob) == 1.0
    @test all(≈(0.9^10), LP.solve(prob, LP.ExplicitEuler(; dt = 0.1, substeps = 1))[:c][end])
    @test LP.getp(LP.remake(prob; p = [:k => 1.0]), :k2)(LP.remake(prob; p = [:k => 1.0])) == 2.0
    # a kind table on the ODE path is the table (round 2: the right side read the state for
    # it); c = 1 on medium sites: dc/dt = −δ[medium] = −0.5
    o = LP.discretize(Potts.fields(FdTab(; name = :f)), LP.LatticeDiscretization(LP.Grid((10, 8)); T = Float64);
        inputs = [:kind => zeros(Int32, 10, 8)])
    du = similar(o.u0)
    o.f(du, o.u0, o.p, 0.0)
    @test all(≈(-0.5), du)
    # a field named like a generated input is refused in the model's words (round 4 via A:
    # "the input field `domain__in` has the name `domain`")
    err = something(fd_err(() -> Potts.fields(FdDomainWord(; name = :f))), "(no error)")
    @test occursin("`domain` (the lattice's domain mask)", err) && occursin("also a field", err) && !occursin("__in", err)
    # … and reads back on the owned path (round 3: "`:δ` names nothing of this problem")
    po = LP.discretize(Potts.fields(FdTab(; name = :f)), LP.LatticeDiscretization(LP.Grid((10, 8)); T = Float64,
        problem = :owned); inputs = [:kind => zeros(Int32, 10, 8)])
    ig = LP.init(po, LP.ExplicitEuler(; dt = 0.1, substeps = 1))
    @test ig[:δ] == [0.5, 0.0] && LP.getp(po, :δ)(po) == [0.5, 0.0]
    @test occursin("`δ` is a table", something(fd_err(() -> LP.setp(ig, :δ)(ig, [1.0, 0.0])), ""))
    # a CPM coupling is an input given by its key: one step of `s · (kind == A)` from c = 0
    K = zeros(Int32, 12, 10); K[3:5, 4:6] .= 1
    prob = LP.discretize(Potts.fields(FdSource(; name = :f)), LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64,
        problem = :owned); inputs = [:kind => K])
    s = LP.solve(prob, LP.ExplicitEuler(; dt = 0.1, substeps = 1); saveat = 0.1)
    @test s[:c][2] ≈ 0.1 * 0.05 .* (K .== 1)
    # … by the model's word (round 1: only the generated key "kind__in"); "kind" too, and the
    # messages print routes that run, never `__in`
    fe(f) = something(fd_err(f), "(no error)")
    fsrc = Potts.fields(FdSource(; name = :f))
    disc = LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64, problem = :owned)
    @test LP.discretize(fsrc, disc; inputs = ["kind" => K]).inputs == prob.inputs
    err = fe(() -> LP.solve(LP.discretize(fsrc, disc), LP.ExplicitEuler(; dt = 0.1)))
    @test occursin("`kind`", err) && occursin(":kind => values", err) && !occursin("__in", err)
    err = fe(() -> LP.discretize(fsrc, LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64)))
    @test occursin(":kind => values", err) && !occursin("__in", err)
    err = fe(() -> LP.discretize(fsrc, disc; inputs = [:kd => K]))
    @test occursin("`kind`", err) && !occursin("__in", err)
    fvol = Potts.fields(FdVolumeRead(; name = :f))
    V = fill(2.0, 6, 4)
    s = LP.solve(LP.discretize(fvol, LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64, problem = :owned);
        inputs = [:volume => V]), LP.ExplicitEuler(; dt = 0.1, substeps = 1); saveat = 0.1)
    @test all(≈(0.1 * 0.01 * 2.0), s[:c][2])
    err = fe(() -> LP.solve(LP.discretize(fvol, LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64,
        problem = :owned)), LP.ExplicitEuler(; dt = 0.1)))
    @test occursin("`volume`", err) && occursin(":volume => values", err) && !occursin("__in", err)
end

@testset "F1 messages: field terms in the model's words (PO02, PO06)" begin
    # PO06: the substep refusal names `kind`, not the generated input `kind__in(t, x, y)`
    err = something(fd_err(() -> PottsProblem(FdKindNonlinear(; name = :f), fd_empty((8, 8)), (0, 1);
        field_solver = ExplicitEuler())), "")
    @test occursin("kind", err) && !occursin("kind__in", err) && occursin("substeps = n", err)
    # PO02: a LatticePDE operator `@equations` does not lower is named as such (base: "reads a
    # field or site variable inside a CPM read")
    err = something(fd_err(() -> mtkcompile(FdDivK(; name = :f))), "")
    @test occursin("does not lower", err) && !occursin("inside a CPM read", err)
    @test occursin("DivKGrad", err) && !occursin("LatticePDE.DivKGrad", err)          # (round 0: the package prefix)
end

struct FdFakeDevice <: Potts.KernelAbstractions.GPU end
@testset "F1 V11: a Float64 problem on a device backend gives a notice" begin
    prob = PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1); field_solver = ExplicitEuler())
    @test_logs (:warn, r"built in Float64") CorePotts._device_float_notice(prob, FdFakeDevice())
    # controls: the host backend, and a Float32 problem (base: no notice anywhere)
    @test_logs CorePotts._device_float_notice(prob, Potts.KernelAbstractions.CPU()) == false
    p32 = PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1); field_solver = ExplicitEuler(), T = Float32)
    @test_logs CorePotts._device_float_notice(p32, FdFakeDevice()) == false
end

# R-F2b (2026-10-20): the filled inputs take one canonical order, whatever order the converter
# meets the CPM reads in (the hash order of a term's arguments): `kind__in` first, the CPM
# reads by expression text (`field1__in`, `field2__in`, … in that order), `domain__in` last
@testset "R-F2b: the filled inputs take a canonical order" begin
    raw = Tuple{Symbol, Any, Type}[(:kind__in, :kind, Int32), (:field1__in, :zz, Float64),
        (:field2__in, :aa, Float64), (:domain__in, :dom, Bool)]
    a, b = Potts._canonical_filled(raw), Potts._canonical_filled(reverse(raw))
    @test a == b                                                   # the met order does not matter
    @test first.(a) == [:kind__in, :field1__in, :field2__in, :domain__in] && a[2][2] === :aa && a[3][2] === :zz
end
