# Whole-cell connectivity (P6.9a) beside the frozen acceptance file
# p6_9a_global_connectivity.jl: the build check of every shell-based quantity on a periodic
# axis of length 1 (the shell wraps onto the target), and `reinit!` clearing the
# checkerboard's deferred-refusal counter.

# in-plane relations: a z offset would itself wrap onto the origin on the thin axis
const CG_INPLANE = :(Stencil([(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)]))
const CG_THIN = :(Lattice((5, 5, 1); boundary = (Closed(), Closed(), Periodic()), neighborhood = $CG_INPLANE))
const CG_PLANE = :(Lattice((5, 5, 2); boundary = (Closed(), Closed(), Closed()), neighborhood = $CG_INPLANE))
const CG_RULES = [
    "Local" => :(@constraint connectivity(A; rule = Local())),
    "ArcOrPair" => :(@constraint connectivity(A; rule = ArcOrPair())),
    "Simple" => :(@constraint connectivity(A; rule = Simple())),
    "Global" => :(@constraint connectivity(A; rule = Global())),
    "Global" => :(@drive copy => 2.0 * !connected(old; rule = Global())),
    "pieces/largest_piece" => :(@energy cells => 0.5 * pieces + 0.25 * largest_piece),
    "local_components" => :(@drive copy => 0.5 * local_components),
    "euler" => :(@energy cells => 0.5 * euler),
]
cg_sigma(dims) = (σ = zeros(Int32, dims); σ[1:3, 2, 1] .= 1; σ)

for (i, (_, line)) in enumerate(CG_RULES), (tag, lat) in (("Thin", CG_THIN), ("Plane", CG_PLANE))
    @eval @potts_model $(Symbol("CGShell", tag, i)) begin
        @kinds medium A
        @lattice $lat
        @relations proposal = $CG_INPLANE
        @energy cells => 0.0625 * (volume - 3)^2
        $line
        @sweep Metropolis(; temperature = 2.0)
    end
end
@eval @potts_model CGNoShellThin begin
    @kinds medium A
    @lattice $CG_THIN
    @relations proposal = $CG_INPLANE
    @energy cells => 0.0625 * (volume - 3)^2
    @sweep Metropolis(; temperature = 2.0)
end

@testset "P6.9a: shell-based quantities refuse a periodic axis of length 1" begin
    for (i, (name, _)) in enumerate(CG_RULES)
        thin = getfield(@__MODULE__, Symbol("CGShellThin", i))
        err = try
            PottsProblem(thin(; name = :t), [ownership => cg_sigma((5, 5, 1)), kind => [:A]], (0, 1))
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        msg = sprint(showerror, err)
        @test occursin("`$name`", msg) && occursin("axis 3", msg) && occursin("Closed", msg)
        # the control: the same model on a lattice without a thin periodic axis builds
        plane = getfield(@__MODULE__, Symbol("CGShellPlane", i))
        @test PottsProblem(plane(; name = :p), [ownership => cg_sigma((5, 5, 2)), kind => [:A]], (0, 1)) isa PottsProblem
    end
    # a model reading no shell quantity is unaffected by the thin axis
    @test PottsProblem(CGNoShellThin(; name = :n), [ownership => cg_sigma((5, 5, 1)), kind => [:A]], (0, 1)) isa
          PottsProblem
    # the one check, in CorePotts (also `recompute_euler`'s)
    lat = Potts.CorePotts.Lattice((5, 5, 1); boundary = (Potts.CorePotts.Closed(), Potts.CorePotts.Closed(), Potts.CorePotts.Periodic()))
    @test_throws ArgumentError Potts.CorePotts.check_shell_lattice(lat, "Global")
    @test_throws ArgumentError Potts.CorePotts.recompute_euler(cg_sigma((5, 5, 1)), lat, Val(:face), 1)
    @test Potts.CorePotts.check_shell_lattice(Potts.CorePotts.Lattice((5, 5, 1); boundary = Potts.CorePotts.Closed()), "Global") === nothing
end

@potts_model CGWindow begin
    @kinds medium A
    @lattice Lattice((24, 24); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy cells => 0.0625 * (volume - 60)^2
    @constraint connectivity(A; rule = Global(; window = 1))
    @sweep Metropolis(; temperature = 4.0)
end

@testset "P6.9a: reinit! clears the deferred-refusal counter" begin
    σ = zeros(Int32, 24, 24)
    σ[5:12, 5:12] .= 1
    σ[14:20, 6:14] .= 2
    prob = PottsProblem(CGWindow(; name = :w), [ownership => σ, kind => [:A, :A]], (0, 20); seed = 4)
    integ = init(prob, CheckerboardCPM(); save_start = false, save_end = false)
    # an old run's refusals, still on the counter (not yet read)
    integ.cache.conn.gl.deferred .= UInt32(7)
    integ.cache.conn.gl.gcount .= UInt32(3)
    reinit!(integ)
    @test all(iszero, integ.cache.conn.gl.deferred)
    @test all(iszero, integ.cache.conn.gl.gcount) && all(iszero, integ.cache.conn.gl.scount)
    Potts.CorePotts.current_state(integ)
    @test integ.stats.connectivity_deferred == 0
    # and the new run counts from 0: the same as a fresh integrator with the same seed
    solve!(integ)
    fresh = init(prob, CheckerboardCPM(); save_start = false, save_end = false)
    solve!(fresh)
    @test integ.stats.connectivity_deferred == fresh.stats.connectivity_deferred
    @test fresh.stats.connectivity_deferred > 0            # the window does refuse here
end
