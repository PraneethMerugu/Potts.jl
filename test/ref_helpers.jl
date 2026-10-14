# Named pairs (E2) and the E7 geometry helpers (P6.5a2, D-243): forms the frozen acceptance
# test lib/PottsModels/test/acceptance/p6_5a2_ref_helpers.jl does not reach.
using Potts: CorePotts

# --- Pairs: the same generated code (fingerprint) as the written-out matrix ---------------
@potts_model RHPairs begin
    @kinds medium ka kb
    @parameters begin
        Jab = 5.0
        J[kind, kind] = Pairs(default = 0.0, (medium, ka) => 12, (medium, kb) => 14.0, (ka, kb) => Jab)
    end
    @lattice Lattice((10, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 6.0)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 3.0)
end
@potts_model RHMatrix begin
    @kinds medium ka kb
    @parameters begin
        Jab = 5.0
        J[kind, kind] = [0 12 14.0; 12 0 Jab; 14.0 Jab 0]
    end
    @lattice Lattice((10, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 6.0)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 3.0)
end
function rh_pairs_op()
    σ = zeros(Int32, 10, 10)
    σ[2:4, 2:3] .= 1
    σ[5:7, 2:3] .= 2
    return [ownership => σ, kind => [:ka, :kb]]
end

@testset "Pairs: the matrix form's parameters and generated code" begin
    pp = PottsProblem(RHPairs(; name = :r), rh_pairs_op(), (0, 2))
    pm = PottsProblem(RHMatrix(; name = :r), rh_pairs_op(), (0, 2))
    @test pp.p == pm.p && typeof(pp.p) == typeof(pm.p)
    @test pp.f.fingerprint == pm.f.fingerprint                 # zero cost: the same code
    @test getp(pp, :J)(pp) == [0 12 14; 12 0 5; 14 5 0]
    # negative control: another value of the parameter entry changes the table, on both sides
    pr = remake(pp; p = [:Jab => 1.5])
    @test getp(pr, :J)(pr)[2, 3] == 1.5 && getp(pr, :J)(pr)[3, 2] == 1.5 && pr.p != pp.p
end

rh_bad(ex) = try
    Core.eval(@__MODULE__, ex)
    nothing
catch e
    e isa LoadError ? e.error : e
end

@testset "Pairs: refusals and the runtime checks" begin
    # a kind class as a key, and a missing default (both open in D-243: refused)
    e = rh_bad(:(@potts_model RHPairsClass begin
        @kinds begin
            medium
            ka
            kb
            both = (ka, kb)
        end
        @parameters J[kind, kind] = Pairs(default = 0.0, (medium, both) => 1.0)
        @lattice Lattice((6, 6); boundary = Closed(), neighborhood = Moore(1))
        @energy contacts => J[kind, kind′]
        @sweep Metropolis(; temperature = 1.0)
    end))
    @test e isa ArgumentError && occursin("kind class", sprint(showerror, e))
    @test_throws ArgumentError Potts.DSL.Pairs((0, 1) => 1.0)
    @test_throws ArgumentError Potts.DSL.Pairs(1.0; default = 0.0)
    # the matrix the macro lowers to: symmetric fill, the default, a repeated pair by number
    t = Potts.DSL.Pairs((0, 1) => 2, (1, 1) => 3.5; default = 0.0)
    @test Potts._pairs_matrix(t, 2, :J) == [0.0 2.0; 2.0 3.5]
    @test Potts._pairs_matrix(t, 2, :J) isa Matrix{Float64}
    @test_throws ArgumentError Potts._pairs_matrix(Potts.DSL.Pairs((0, 1) => 1, (1, 0) => 1; default = 0), 2, :J)
    @test Potts._pairs_matrix(Potts.DSL.Pairs((0, 1) => 1, (1, 0) => 2; default = 0, symmetric = false), 2, :J) == [0 1; 2 0]
    @test_throws ArgumentError Potts._pairs_matrix(Potts.DSL.Pairs((0, 5) => 1; default = 0), 2, :J)   # not a kind
end

# --- the E7 helpers in forms the frozen file leaves out ------------------------------------
function rh_build_error(name, lattice, drive, update, observed)
    e = rh_bad(:(@potts_model $name begin
        @kinds medium ka
        @variables begin
            partner(cell)::CellRef
            w(cell) = 0.0
        end
        @lattice $lattice
        @energy cells => (volume - 4.0)^2
        @drive copy => $drive
        @after_mcs w ~ $update
        @observed o(cell) ~ $observed
        @sweep Metropolis(; temperature = 1.0)
    end))
    e === nothing || return e
    σ = zeros(Int32, 8, 8)
    σ[2, 2] = 1
    σ[5, 5] = 2
    try
        Base.invokelatest(getfield(@__MODULE__, name); name = :b) |>
        sys -> Base.invokelatest(PottsProblem, sys, [ownership => σ, kind => [:ka, :ka], :partner => [2, 1]], (0, 1))
        return nothing
    catch e
        return e isa LoadError ? e.error : e
    end
end
const RH_SQ = :(Lattice((8, 8); boundary = Periodic(), neighborhood = Moore(1)))
const RH_HEX = :(Lattice((8, 8); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1)))

@testset "E7 helpers: copy-scope and hexagonal refusals" begin
    # control: the template builds
    @test rh_build_error(:RHOk, RH_SQ, :(0.0), :(centroid(partner, 1)), :(norm(separation(id, partner)))) === nothing
    # centroid(c, k) and separation read centroids a copy moves: not in drives
    e = rh_build_error(:RHDriveC, RH_SQ, :(0.1 * centroid(partner[old], 1)), :(0.0), :(0.0))
    @test e isa ArgumentError && occursin("centroid", sprint(showerror, e))
    e = rh_build_error(:RHDriveS, RH_SQ, :(0.1 * separation(partner[old], partner[new])[1]), :(0.0), :(0.0))
    @test e isa ArgumentError && occursin("separation", sprint(showerror, e))
    # minimum_image is a pure function: allowed in a drive (control)
    @test rh_build_error(:RHDriveM, RH_SQ, :(0.1 * minimum_image(position[target][1] - 2.0, 1)), :(0.0), :(0.0)) === nothing
    # on a hexagonal lattice minimum_image is refused (D-243 open: use separation), separation is not
    e = rh_build_error(:RHHexM, RH_HEX, :(0.0), :(minimum_image(centroid(1), 1)), :(0.0))
    @test e isa ArgumentError && occursin("minimum_image", sprint(showerror, e))
    @test rh_build_error(:RHHexS, RH_HEX, :(0.0), :(separation(id, partner)[2]), :(0.0)) === nothing
end

@potts_model RHDead begin
    @kinds medium ka
    @variables partner(cell)::CellRef
    @lattice Lattice((8, 8); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 1.0)^2
    @observed begin
        sx(cell) ~ separation(id, partner)[1]
        cx(cell) ~ centroid(partner, 1)
        iv(cell) ~ integral(volume; over = cluster)
        ii(cell) ~ integral(1.0)
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "E7 helpers: a reference 0, no clusters" begin
    σ = zeros(Int32, 8, 8)
    σ[2, 2] = 1
    σ[6, 3:4] .= 2
    prob = PottsProblem(RHDead(; name = :d), [ownership => σ, kind => [:ka, :ka], :partner => [2, 0]], (0, 1))
    u = prob.u0
    @test observe(prob, :sx, u)[1:2] == [-4.0, 0.0]            # an alive pair; the reference 0 reads 0
    @test observe(prob, :cx, u)[1:2] == [6.0, 0.0]
    # without a cluster column every cell is its own cluster: over = cluster is integral
    @test observe(prob, :iv, u)[1:2] == [1.0, 4.0]             # Σ V over own sites: 1·1, 2·2
    @test observe(prob, :ii, u)[1:2] == [1.0, 2.0]             # control: the plain integral (cell volume)
end

@testset "minimum_image: the scalar wrap on CPU types" begin
    lat = CorePotts.Lattice((20, 12); boundary = (Periodic(), Closed()))
    @test Potts._minimum_image_axis(Float32, lat, 13.75f0, 1) === -6.25f0
    @test Potts._minimum_image_axis(Float32, lat, 10.0f0, 1) === 10.0f0             # a tie keeps d
    @test Potts._minimum_image_axis(Float32, lat, -10.0f0, 1) === -10.0f0
    @test Potts._minimum_image_axis(Float32, lat, 13.75f0, 2) === 13.75f0           # closed axis
    @test Potts._minimum_image_axis(Float32, lat, 3, 1) === 3.0f0                   # an integer in T
end

# --- on the device: the helpers inside the after-MCS kernels, square and hexagonal ---------
@potts_model RHDevice begin
    @kinds medium ka kb
    @variables begin
        partner(cell)::CellRef
        F(site) = 1.0
        wc(cell) = 0.0
        ws(cell) = 0.0
        wi(cell) = 0.0
    end
    @structural_parameters begin
        geom = Square()
        nbh = Moore(1)
    end
    @lattice Lattice((16, 16); geometry = geom, boundary = Periodic(), neighborhood = nbh)
    @energy begin
        cells => 5.0 * (volume - 6.0)^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 0.5, 2.0)
    end
    @after_mcs begin
        wc ~ centroid(sibling(kb), 1)
        ws ~ norm(separation(id, partner))
        wi ~ integral(volume * F; over = cluster)
    end
    @observed begin
        oc(cell) ~ centroid(sibling(kb), 1)
        os(cell) ~ norm(separation(id, partner))
        oi(cell) ~ integral(volume * F; over = cluster)
    end
    @sweep Metropolis(; temperature = 1.0)
end
function rh_device_problem(hex; T = Float64)
    σ = zeros(Int32, 16, 16)
    σ[[15, 16, 1], 2:3] .= 1
    σ[2:3, 1:3] .= 2
    σ[8:9, 8:10] .= 3
    return PottsProblem(RHDevice(; name = :dv, geom = hex ? Hexagonal() : Square(), nbh = hex ? Hex(1) : Moore(1)), [ownership => σ, kind => [:ka, :kb, :ka], cluster => [1, 1, 3],
            :partner => [2, 1, 1]], (0, 3); seed = 2, T)
end

@testset "E7 helpers on the device (PottsDevices)" begin
    if isdefined(Main, :PottsDevices) && PottsDevices.on_device()
        backend = PottsDevices.device_backend()
        for hex in (false, true)
            prob = rh_device_problem(hex; T = Float32)
            sol = solve(prob, CheckerboardCPM(); backend, saveat = 1)
            @test Symbol(sol.retcode) === :Success
            u = sol.u[end]
            # the device's after-MCS writes against the host's evaluation on the same state
            alive = findall(>(0), Array(u.cell.volume))
            @test length(alive) == 3
            for (col, ob) in ((:wc, :oc), (:ws, :os), (:wi, :oi))
                @test isapprox(Array(getfield(u.cell, col))[alive], observe(prob, ob, u)[alive]; atol = 1e-3)
            end
            @test all(>(0), Array(u.cell.ws)[alive])           # control: the pair is apart, the norm is read
        end
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
