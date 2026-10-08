# Edge-scope `@before_mcs`/`@after_mcs` updates (D-169), beside the frozen acceptance file
# p6_0bv_edge_after_mcs.jl: several relationships in one stage, `Pre` reads of another edge
# variable, model and parameter reads, the refusals the frozen file leaves to the implementer,
# and zero warm allocations.

const EU_CP = Potts.CorePotts
eu_error(f, words...) = try
    f()
    false
catch err
    err isa ArgumentError && all(w -> occursin(w, sprint(showerror, err)), words)
end

# three frozen 4×4 blobs (every copy costs ≥ ~990 at T = 1): centroids 4.5, 12.5, 22.5 on x
function eu_state()
    σ = zeros(Int32, 30, 12)
    σ[3:6, 5:8] .= 1; σ[11:14, 5:8] .= 2; σ[21:24, 5:8] .= 3
    return σ
end
eu_payload(cell, r, x, a, b) = (k = EU_CP.link_slot(EU_CP.link_store(cell, r), a, b);
                                k == 0 ? nothing : Float64(Array(getproperty(cell, Symbol(:link_, x)))[k, a]))

# two relationships updated in one stage (one cadence): each from its own links and payload;
# `rest` reads `age` (same stage) through `Pre`, and a model variable and a parameter
@potts_model EUTwo begin
    @kinds medium blob
    @parameters begin
        T = 1.0
        s = 0.5
    end
    @variables begin
        rest(bond) = 12.0
        age(bond) = 0.0
        len(tether) = 3.0
        m(model) = 1.0
    end
    @relationship bond(cell, cell) capacity = 2
    @relationship tether(cell, cell) capacity = 2
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => 1000.0 * (volume - 16.0)^2
        contacts => 1.0
        edges(bond) => 0.01 * (distance - rest)^2
        edges(tether) => 0.01 * (distance - len)^2
    end
    @after_mcs begin
        rest ~ Pre(rest) + Pre(age) + s * m
        age ~ Pre(age) + 1
        len ~ Pre(len) + distance
    end
    @sweep Metropolis(; temperature = T)
end
eu_two_op() = Any[ownership => eu_state(), kind => [:blob, :blob, :blob], :bond => [(1, 2)], :tether => [(2, 3), (1, 3)]]

@testset "edge updates: two relationships in one stage, Pre reads, model reads" begin
    prob = PottsProblem(EUTwo(; name = :two), eu_two_op(), (0, 5))
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(prob, alg; saveat = 1)
        @test all(u -> u.σ == eu_state(), sol.u)
        for (i, t) in enumerate(sol.t)
            c = sol.u[i].cell
            # rest gains Pre(age) = t′ at step t′ (0, 1, …, t − 1) and s·m = 0.5 each MCS
            @test eu_payload(c, :bond, :rest, 1, 2) == 12.0 + t * (t - 1) / 2 + 0.5t
            @test eu_payload(c, :bond, :rest, 2, 1) == eu_payload(c, :bond, :rest, 1, 2)
            @test eu_payload(c, :bond, :age, 2, 1) == t
            # each tether link its own centroid distance (10, and 12 across the periodic x axis), at both ends
            @test eu_payload(c, :tether, :len, 2, 3) == 3.0 + 10.0t == eu_payload(c, :tether, :len, 3, 2)
            @test eu_payload(c, :tether, :len, 3, 1) == 3.0 + 12.0t == eu_payload(c, :tether, :len, 1, 3)
            @test eu_payload(c, :bond, :rest, 2, 3) === nothing          # (2,3) is a tether only
        end
    end
    # Float32
    c = solve(PottsProblem(EUTwo(; name = :two), eu_two_op(), (0, 5); T = Float32), SequentialCPM()).u[end].cell
    @test eltype(c.link_len) === Float32
    @test eu_payload(c, :tether, :len, 1, 3) ≈ 63.0 rtol = 1e-6
end

@testset "edge updates: zero warm allocations" begin
    for alg in (SequentialCPM(), CheckerboardCPM())
        integ = init(PottsProblem(EUTwo(; name = :two), eu_two_op(), (0, 100)), alg)
        step!(integ); step!(integ)
        @test (@allocated step!(integ)) == 0
    end
end

# refusals: what an edge update cannot read
eu_model(stmts...) = eval(quote
    @potts_model EURefuse begin
        @kinds medium blob
        @parameters T = 1.0
        @variables begin
            rest(bond) = 12.0
            age(bond) = 0.0
            g(cell) = 0.0
        end
        @relationship bond(cell, cell) capacity = 2
        @lattice Lattice((30, 12); neighborhood = Moore(1))
        @energy begin
            cells(blob) => (volume - 16.0)^2
            edges(bond) => (distance - rest)^2
        end
        $(stmts...)
        @sweep Metropolis(; temperature = T)
    end
    EURefuse(; name = :r)
end)

@testset "edge updates: refusals" begin
    # another edge variable of the block, bare (a new value) or at another cadence
    @test eu_error(() -> mtkcompile(eu_model(:(@after_mcs begin
        rest ~ Pre(rest) + age
        age ~ Pre(age) + 1
    end))), "rest", "age", "Pre")
    @test eu_error(() -> mtkcompile(eu_model(:(@after_mcs rest ~ Pre(rest) + Pre(age)),
        :(@after_mcs Every(2) age ~ Pre(age) + 1))), "rest", "age", "another cadence")
    @test eu_error(() -> mtkcompile(eu_model(:(@after_mcs begin
        rest ~ Pre(rest) + Pre(age)
        age ~ Pre(age) + 1
    end), :(@after_mcs Every(2) age ~ Pre(age) * 2))), "rest", "age", "another cadence")
    # an edge variable not written in the block reads its stored value (no refusal)
    @test mtkcompile(eu_model(:(@after_mcs rest ~ Pre(rest) + age))) isa Potts.CompiledPottsSystem
    # the vocabulary is that of `edges(rel)` and `@unlink`: no bare cell quantities
    @test eu_error(() -> mtkcompile(eu_model(:(@after_mcs rest ~ Pre(rest) + volume))), "volume", "edge update")
    @test eu_error(() -> mtkcompile(eu_model(:(@after_mcs rest ~ Pre(rest) + g))), "g")
end

# the review probe (D-169): a model update, then two edge updates of one cadence, `rest`
# reading `age` through `Pre` and the model's new value bare: one edge stage, after `m`
@potts_model EUProbe begin
    @kinds medium blob
    @parameters T = 1.0
    @variables begin
        rest(bond) = 12.0
        age(bond) = 0.0
        m(model) = 0.0
    end
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => 1000.0 * (volume - 16.0)^2
        contacts => 1.0
        edges(bond) => 0.01 * (distance - rest)^2
    end
    @after_mcs begin
        m ~ Pre(m) + 1
        rest ~ Pre(rest) + Pre(age) + m
        age ~ Pre(age) + 1
    end
    @sweep Metropolis(; temperature = T)
end

# endpoint reads through the macro: `volume[a]`, `kind[b]`
@potts_model EUEnds begin
    @kinds medium blob
    @parameters T = 1.0
    @variables rest(bond) = 12.0
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => 1000.0 * (volume - 16.0)^2
        contacts => 1.0
        edges(bond) => 0.01 * (distance - rest)^2
    end
    @after_mcs rest ~ Pre(rest) + volume[a] + (kind[b] == blob) + 0.5 * a
    @sweep Metropolis(; temperature = T)
end

@testset "edge updates: Pre reads at one cadence beside other updates; endpoint reads" begin
    op = Any[ownership => eu_state(), kind => [:blob, :blob, :blob], :bond => [(1, 2), (2, 3)]]
    sol = solve(PottsProblem(EUProbe(; name = :probe), op, (0, 5)), SequentialCPM(); saveat = 1)
    for (i, t) in enumerate(sol.t), (a, b) in ((1, 2), (2, 3))
        c = sol.u[i].cell
        @test eu_payload(c, :bond, :rest, a, b) == 12.0 + t^2 == eu_payload(c, :bond, :rest, b, a)   # Σ (t′ + t′ + 1)
        @test eu_payload(c, :bond, :age, a, b) == t
    end
    sol = solve(PottsProblem(EUEnds(; name = :ends), op, (0, 3)), SequentialCPM(); saveat = 1)
    c = sol.u[end].cell
    @test eu_payload(c, :bond, :rest, 1, 2) == 12.0 + 3 * (16 + 1 + 0.5) == eu_payload(c, :bond, :rest, 2, 1)   # a = 1
    @test eu_payload(c, :bond, :rest, 2, 3) == 12.0 + 3 * (16 + 1 + 1.0)                                       # a = 2
end

# a cell squeezed out by copies (volume 0) keeps its links; an edge update leaves them as they are
@potts_model EUDead begin
    @kinds medium blob tiny
    @parameters T = 1.0
    @variables rest(bond) = 12.0
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => 1000.0 * (volume - 16.0)^2
        cells(tiny) => 1000.0 * volume
        contacts => 1.0
        edges(bond) => 0.01 * (distance - rest)^2
    end
    @after_mcs rest ~ Pre(rest) + 1
    @sweep Metropolis(; temperature = T)
end

@testset "edge updates: links of a cell squeezed out keep their value" begin
    σ = zeros(Int32, 30, 12)
    σ[3:6, 5:8] .= 1; σ[11:14, 5:8] .= 2; σ[22, 6] = 3
    op = Any[ownership => σ, kind => [:blob, :blob, :tiny], :bond => [(1, 2), (2, 3)]]
    sol = solve(PottsProblem(EUDead(; name = :dead), op, (0, 20); seed = 3), SequentialCPM(); saveat = 1)
    vols = [Array(u.cell.volume)[3] for u in sol.u]
    k = findfirst(iszero, vols)
    @test k !== nothing && k > 1                       # cell 3 dies in the run, not at the start
    for (i, t) in enumerate(sol.t)
        c = sol.u[i].cell
        @test eu_payload(c, :bond, :rest, 1, 2) == 12.0 + t                     # the live link updates
        @test eu_payload(c, :bond, :rest, 3, 2) == eu_payload(c, :bond, :rest, 2, 3)   # both ends
        # the dead link: updated after each MCS cell 3 survived, then left as it is
        @test eu_payload(c, :bond, :rest, 2, 3) == 12.0 + min(t, sol.t[k] - 1)
    end
    @test eu_payload(sol.u[end].cell, :bond, :rest, 2, 3) !== nothing          # still linked
end

@testset "edge updates: rand() names the edge update" begin
    @test eu_error(() -> mtkcompile(eu_model(:(@after_mcs rest ~ Pre(rest) + rand()))), "rand()", "an edge update")
end
