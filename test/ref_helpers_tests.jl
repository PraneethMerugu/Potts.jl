# Named pairs (E2) and the E7 geometry helpers (D-243): forms the frozen acceptance
# test lib/PottsModels/test/acceptance/cell_reference_helpers_tests.jl does not reach.

@testsetup module RefHelpersSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts: CorePotts

# the field models' PDESystems: the CPM terms are bound inputs
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module RhPDE
    using ..FieldPDE
    @variables qf(..) qin(..) [input = true]
    function source()
        Q = qf(t, x, y)
        return pdesys(
            [Dt(Q) ~ qin(t, x, y)], [qf(0, x, y) ~ 0.0], (20, 12),
            [Q, qin(t, x, y)]
        )
    end
end

# --- Pairs: the same generated code (fingerprint) as the written-out matrix ---------------
@potts_model RHPairs begin
    @kinds medium ka kb
    @parameters begin
        Jab = 5.0
        J[kind, kind] = Pairs(
            default = 0.0, (medium, ka) => 12, (medium, kb) => 14.0, (
                ka, kb,
            ) => Jab
        )
    end
    @lattice Lattice((10, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 6.0)^2
        contacts => J[kind, neighbor_kind]
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
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 3.0)
end

function rh_pairs_op()
    σ = zeros(Int32, 10, 10)
    σ[2:4, 2:3] .= 1
    σ[5:7, 2:3] .= 2
    return [ownership => σ, kind => [:ka, :kb]]
end

# --- the reference helpers in further forms
# -------------------------------------------------
@potts_model RHE7Case begin
    @structural_parameters begin
        hex = false
        mode = :ok
    end
    @kinds medium ka
    @variables begin
        partner(cell)::CellRef
        w(cell) = 0.0
    end
    @lattice Lattice(
        (8, 8); geometry = hex ? Hexagonal() : Square(),
        boundary = Periodic(), neighborhood = hex ? Hex(1) : Moore(1)
    )
    @energy cells => (volume - 4.0)^2
    if mode === :energy_c
        @energy cells => 0.1 * centroid(partner, 1)
    elseif mode === :con_s
        @constraint separation(partner[old], partner[new])[1] > 0.0
    elseif mode === :oncopy_c
        @on_copy w[new] ~ centroid(partner[old], 1)
    end
    if mode === :drive_c
        @drive copy => 0.1 * centroid(partner[old], 1)
    elseif mode === :drive_s
        @drive copy => 0.1 * separation(partner[old], partner[new])[1]
    elseif mode === :drive_m
        @drive copy => 0.1 * minimum_image(position[target][1] - 2.0, 1)
    else
        @drive copy => 0.0
    end
    if mode === :hex_m
        @after_mcs w ~ minimum_image(centroid(1), 1)
    elseif mode === :hex_s
        @after_mcs w ~ separation(id, partner)[2]
    elseif mode === :ok
        @after_mcs w ~ centroid(partner, 1)
    else
        @after_mcs w ~ 0.0
    end
    if mode === :ok
        @observed o(cell) ~ norm(separation(id, partner))
    end
    @sweep Metropolis(; temperature = 1.0)
end

function rh_build_error(; hex = false, mode = :ok)
    σ = zeros(Int32, 8, 8)
    σ[2, 2] = 1
    σ[5, 5] = 2
    try
        PottsProblem(
            RHE7Case(; name = :b, hex, mode),
            [ownership => σ, kind => [:ka, :ka], :partner => [2, 1]], (0, 1)
        )
        return nothing
    catch e
        return e isa LoadError ? e.error : e
    end
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

# --- on the device: the helpers inside the after-MCS kernels, square and hexagonal
# ---------
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
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 0.5, 2.0)
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
    return PottsProblem(
        RHDevice(;
            name = :dv, geom = hex ? Hexagonal() : Square(), nbh = if hex
                Hex(1)
            else
                Moore(1)
            end
        ), [
            ownership => σ, kind => [:ka, :kb, :ka], cluster => [1, 1, 3],
            :partner => [2, 1, 1],
        ],
        (0, 3);
        seed = 2,
        T
    )
end

# --- between-sweep site scope (the Fortuna model's forms): a @convert gate, a field
# equation, site updates Sketch 14c's gate Q = minimum_image(position[1] −
# centroid(sibling(owner, cytoplasm), 1), 1) (14_nucleus_migration.md) with a `separation`
# factor S. Fixture on 20 × 12, axis 1 periodic: cytoplasm 1 across the seam (x ∈ {18, 19,
# 20, 1, 2, 3}, y 3:4), centroid x 20.5; nucleus 2 at (4, 8) (or at (17, 8), the negative
# control), cluster 1. So Q(x) = −2.5, −1.5, −0.5, 0.5,
# 1.5, 2.5 for x = 18, 19, 20, 1, 2, 3 (unwrapped, x = 1, 2, 3 would give −19.5, −18.5,
# −17.5) and S = minimum_image(4 − 20.5) = 3.5 (17 − 20.5 = −3.5 for the control). The
# energy holds every volume at its target (λ = 10⁶, T = 0.01), so σ stays put through the
# sweep.
@potts_model RHConvQ begin
    @kinds medium cytoplasm nucleus lamellipodium
    @variables begin
        sub(site) = 0.0
        V_target(cell) = 0.0
        nconv(model) = 0.0
    end
    @lattice Lattice((20, 12); boundary = (Periodic(), Closed()), neighborhood = Moore(1))
    Q = minimum_image(position[1] - centroid(sibling(owner, cytoplasm), 1), 1)
    S = separation(sibling(owner, nucleus), sibling(owner, cytoplasm))[1]
    @energy begin
        cells => 1.0e6 * (volume - V_target)^2
        contacts => 1.0
    end
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = sub > 0.5
        p = ifelse(Q > 0, ifelse(S > 0, 1.0, 0.0), 0.0)
        nconv += 1
    end
    @sweep Metropolis(; temperature = 0.01)
end

@potts_model RHFieldQ begin
    @kinds medium cytoplasm nucleus
    @variables begin
        V_target(cell) = 0.0
        qs(site) = 0.0
        qc(cell) = 0.0
    end
    @lattice Lattice((20, 12); boundary = (Periodic(), Closed()), neighborhood = Moore(1))
    Q = minimum_image(position[1] - centroid(sibling(owner, cytoplasm), 1), 1)
    S = separation(sibling(owner, nucleus), sibling(owner, cytoplasm))[1]
    @energy begin
        cells => 1.0e6 * (volume - V_target)^2
        contacts => 1.0
    end
    @fields RhPDE.source() (RhPDE.qin => (Q + S) * (kind == cytoplasm))
    @after_mcs begin
        qs ~ (Q + S) * (kind == cytoplasm)
        qc ~ minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1)
    end
    @observed oq ~ (Q + S) * (kind == cytoplasm)
    @sweep Metropolis(; temperature = 0.01)
end

const RH_CYTO_X = (18, 19, 20, 1, 2, 3)

function rh_q_sigma(nx)
    σ = zeros(Int32, 20, 12)
    σ[collect(RH_CYTO_X), 3:4] .= 1
    σ[nx, 8] = 2
    return σ
end

function rh_q_op(nx)
    return [
        ownership => rh_q_sigma(nx), kind => [:cytoplasm, :nucleus],
        cluster => [1, 1], :V_target => [12.0, 1.0],
    ]
end

function rh_conv_problem(nx; T = Float64)
    return PottsProblem(
        RHConvQ(; name = :cq), [rh_q_op(nx); :sub => Float64.(rh_q_sigma(nx) .== 1)],
        (0, 1); T, capacity = 4
    )
end

function rh_field_problem(nx; T = Float64)
    return PottsProblem(
        RHFieldQ(; name = :fq), rh_q_op(nx), (0, 1); T,
        field_solver = ExplicitEuler(substeps = 1)
    )
end

# the hand oracle: (Q + S) at the cytoplasm's sites, 0 elsewhere
function rh_q_oracle(S)
    o = zeros(20, 12)
    for (x, q) in zip(RH_CYTO_X, (-2.5, -1.5, -0.5, 0.5, 1.5, 2.5)), y in 3:4
        o[x, y] = q + S
    end
    return o
end

# the converted sites: the cytoplasm's sites with Q > 0 (x = 1, 2, 3), when S > 0
function rh_conv_check(u, nx; converted)
    σ = Array(u.ownership)
    want = rh_q_sigma(nx)
    # slot 3, the allocated lamellipodium
    converted && (want[1:3, 3:4] .= 3)
    return (σ == want, Array(u.model.nconv)[1], Array(u.cell.kind)[3])
end

# --- review regressions -----------------------------------------------------------
# A model whose only cluster read is `integral(x; over = cluster)` keeps the cluster column:
# with `cluster => [1, 1]` both cells read V₁² + V₂² = 4² + 2² = 20; without it each cell is
# its own cluster (16, 4). The energy holds the volumes (λ = 10⁶, T = 0.01).
@potts_model RHOverOnly begin
    @kinds medium ka
    @variables a1(cell) = 0.0
    @lattice Lattice((10, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 1.0e6 * (volume - ifelse(id == 1, 4.0, 2.0))^2
    @after_mcs a1 ~ integral(volume; over = cluster)
    @sweep Metropolis(; temperature = 0.01)
end

function rh_over_sigma()
    σ = zeros(Int32, 10, 10)
    σ[2:3, 2:3] .= 1
    σ[7, 7:8] .= 2
    return σ
end

# axis and hexagonal refusals in every context: @convert `at`, `p` and writes, the sweep
# temperature (each built to the problem, so a refusal at either stage counts)
@potts_model RHCtxCase begin
    @structural_parameters begin
        hex = false
        mode = :ctrl_at
    end
    @kinds medium ka kb
    @variables begin
        F(site) = 1.0
        n(model) = 0.0
    end
    @lattice Lattice(
        (10, 10); geometry = hex ? Hexagonal() : Square(),
        boundary = Periodic(), neighborhood = hex ? Hex(1) : Moore(1)
    )
    @energy cells => (volume - 4.0)^2
    if mode === :ctrl_at
        @convert cv clusters(ka) begin
            to = sibling(kb)
            at = minimum_image(position[1] - 3.0, 1) > -100.0
            p = 0.0
            n += 1
        end
    elseif mode === :bad_at_axis
        @convert cv clusters(ka) begin
            to = sibling(kb)
            at = minimum_image(position[1] - 3.0, 3) > -100.0
            p = 0.0
            n += 1
        end
    elseif mode === :bad_p_mi_axis
        @convert cv clusters(ka) begin
            to = sibling(kb)
            at = F > 0.5
            p = ifelse(minimum_image(position[1], 3) > 0, 1.0, 0.0)
            n += 1
        end
    elseif mode === :bad_w_mi_axis
        @convert cv clusters(ka) begin
            to = sibling(kb)
            at = F > 0.5
            p = 0.0
            n += minimum_image(1.0, 3)
        end
    elseif mode === :bad_p_cent_axis
        @convert cv clusters(ka) begin
            to = sibling(kb)
            at = F > 0.5
            p = ifelse(centroid(from, 3) > 0, 1.0, 0.0)
            n += 1
        end
    elseif mode === :hex_p_mi
        @convert cv clusters(ka) begin
            to = sibling(kb)
            at = F > 0.5
            p = ifelse(minimum_image(position[1], 1) > 100, 1.0, 0.0)
            n += 1
        end
    elseif mode === :hex_p_sep
        @convert cv clusters(ka) begin
            to = sibling(kb)
            at = F > 0.5
            p = ifelse(separation(from, from)[1] > 100, 1.0, 0.0)
            n += 1
        end
    end
    if mode === :bad_temp_axis
        @sweep Metropolis(; temperature = 1.0 + 0.001 * minimum_image(1.0, 3))
    elseif mode === :ctrl_temp
        @sweep Metropolis(; temperature = 1.0 + 0.001 * minimum_image(1.0, 1))
    else
        @sweep Metropolis(; temperature = 1.0)
    end
end

function rh_ctx_error(; hex = false, mode = :ctrl_at, clusters = true)
    σ = zeros(Int32, 10, 10)
    σ[2:3, 2:3] .= 1
    try
        sys = RHCtxCase(; name = :c, hex, mode)
        op = Any[ownership => σ, kind => [:ka]]
        clusters && push!(op, cluster => [1])
        prob = PottsProblem(sys, op, (0, 1); capacity = 3)
        solve(prob, SequentialCPM())
        return nothing
    catch e
        return e isa LoadError ? e.error : e
    end
end

rh_msg(e, s) = e isa Potts.PottsCompileError && occursin(s, sprint(showerror, e))

@potts_model RHDefaultMI begin
    @kinds medium ka
    @variables F(site) = minimum_image(1.0, 1)
    @lattice Lattice((6, 6); boundary = Periodic(), neighborhood = Moore(1))
    @energy cells => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

# A masked condition of a coupled PDESystem (once a site mask of the removed `@boundary`
# section) is lowered in site scope at the field step: when it is the model's only centroid
# read, the moment trackers must still be allocated (re-review of 20b9a546). Two 3 × 3 cells
# held in place (λ = 10⁶, T = 0.01): cell 1 at x 5:7 (centroid 6), cell 2 at x 1:3 (centroid
# 2). The mask `centroid(owner, 1) > 4` clamps c = 7 at cell 1's sites only; `D(c) ~ -c`
# from c = 0 leaves every other site at 0.
module RHMaskPDE
    using Potts.Fields
    @variables c(..) = 0.0 m(..)::Bool [input = true]
    function sys()
        return pdesystem(
            [Differential(t)(c(t, x, y)) ~ -c(t, x, y)],
            [c(t, x, y) ~ masked(m(t, x, y), 7.0)]; name = :rhmask
        )
    end
end

@potts_model RHMaskCentroid begin
    @kinds medium ka
    @lattice Lattice((12, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 1.0e6 * (volume - 9.0)^2
    @fields RHMaskPDE.sys() (RHMaskPDE.m => (kind == ka) && (centroid(owner, 1) > 4.0))
    @sweep Metropolis(; temperature = 0.01)
end

function rh_mask_sigma()
    σ = zeros(Int32, 12, 10)
    σ[5:7, 4:6] .= 1
    σ[1:3, 4:6] .= 2
    return σ
end

function rh_mask_problem(; T = Float64)
    return PottsProblem(
        RHMaskCentroid(; name = :bm), [ownership => rh_mask_sigma(), kind => [:ka, :ka]],
        (0, 1); T, field_solver = ExplicitEuler(substeps = 1)
    )
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "Pairs: the matrix form's parameters and generated code" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers,
] begin
    @testset "Pairs: the matrix form's parameters and generated code" begin
        pp = PottsProblem(RHPairs(; name = :r), rh_pairs_op(), (0, 2))
        pm = PottsProblem(RHMatrix(; name = :r), rh_pairs_op(), (0, 2))
        @test pp.p == pm.p && typeof(pp.p) == typeof(pm.p)
        # zero cost: the same code
        @test pp.f.fingerprint == pm.f.fingerprint
        @test getp(pp, :J)(pp) == [0 12 14; 12 0 5; 14 5 0]
        # negative control: another value of the parameter entry changes the table, on both
        # sides
        pr = remake(pp; p = [:Jab => 1.5])
        @test getp(pr, :J)(pr)[2, 3] == 1.5 && getp(pr, :J)(pr)[3, 2] == 1.5 && pr.p != pp.p
    end
end

@testitem "Pairs: refusals and the runtime checks" setup = [RefHelpersSetup] tags = [
    :potts, :ref_helpers,
] begin
    @testset "Pairs: refusals and the runtime checks" begin
        # a kind class as a key, and a missing default (both open in D-243: refused at macro
        # expansion)
        e = try
            macroexpand(
                @__MODULE__, :(
                    @potts_model RHPairsClass begin
                        @kinds begin
                            medium
                            ka
                            kb
                            both = (ka, kb)
                        end
                        @parameters J[kind, kind] = Pairs(
                            default = 0.0, (medium, both) =>
                                1.0
                        )
                        @lattice Lattice(
                            (6, 6); boundary = Closed(),
                            neighborhood = Moore(1)
                        )
                        @energy contacts => J[kind, neighbor_kind]
                        @sweep Metropolis(; temperature = 1.0)
                    end
                )
            )
            nothing
        catch err
            err isa LoadError ? err.error : err
        end
        @test e isa ArgumentError
        @test_throws ArgumentError Potts.DSL.Pairs((0, 1) => 1.0)
        @test_throws ArgumentError Potts.DSL.Pairs(1.0; default = 0.0)
        # the matrix the macro lowers to: symmetric fill, the default, a repeated pair by
        # number
        t = Potts.DSL.Pairs((0, 1) => 2, (1, 1) => 3.5; default = 0.0)
        @test Potts._pairs_matrix(t, 2, :J) == [0.0 2.0; 2.0 3.5]
        @test Potts._pairs_matrix(t, 2, :J) isa Matrix{Float64}
        @test_throws ArgumentError Potts._pairs_matrix(
            Potts.DSL.Pairs((0, 1) => 1, (1, 0) => 1; default = 0), 2, :J
        )
        @test Potts._pairs_matrix(
            Potts.DSL.Pairs((0, 1) => 1, (1, 0) => 2; default = 0, symmetric = false),
            2, :J
        ) == [0 1; 2 0]
        # not a kind
        @test_throws ArgumentError Potts._pairs_matrix(
            Potts.DSL.Pairs((0, 5) => 1; default = 0), 2, :J
        )
    end
end

@testitem "E7 helpers: copy-scope and hexagonal refusals" setup = [RefHelpersSetup] tags = [
    :potts, :ref_helpers,
] begin
    @testset "E7 helpers: copy-scope and hexagonal refusals" begin
        # control: the template builds
        @test rh_build_error(; hex = false, mode = :ok) === nothing
        # a drive reads centroid(c, k) and separation before the copy
        @test rh_build_error(; hex = false, mode = :drive_c) === nothing
        @test rh_build_error(; hex = false, mode = :drive_s) === nothing
        # energies, constraints and on-copy updates do not (a copy moves the centroids)
        for mode in (:energy_c, :con_s, :oncopy_c)
            e = rh_build_error(; hex = false, mode)
            @test e isa Potts.PottsCompileError
            @test occursin(r"centroid|separation", sprint(showerror, e))
        end
        # minimum_image is a pure function: allowed in a drive (control)
        @test rh_build_error(; hex = false, mode = :drive_m) === nothing
        # on a hexagonal lattice minimum_image is refused (D-243 open: use separation),
        # separation is not
        e = rh_build_error(; hex = true, mode = :hex_m)
        @test e isa Potts.PottsCompileError
        @test rh_build_error(; hex = true, mode = :hex_s) === nothing
    end
end

@testitem "E7 helpers: a reference 0, no clusters" setup = [RefHelpersSetup] tags = [
    :potts, :ref_helpers,
] begin
    @testset "E7 helpers: a reference 0, no clusters" begin
        σ = zeros(Int32, 8, 8)
        σ[2, 2] = 1
        σ[6, 3:4] .= 2
        prob = PottsProblem(
            RHDead(; name = :d),
            [ownership => σ, kind => [:ka, :ka], :partner => [2, 0]], (0, 1)
        )
        u = prob.u0
        # an alive pair; the reference 0 reads 0
        @test observe(prob, :sx, u)[1:2] == [-4.0, 0.0]
        @test observe(prob, :cx, u)[1:2] == [6.0, 0.0]
        # without a cluster column every cell is its own cluster: over = cluster is integral
        # Σ V over own sites: 1·1, 2·2
        @test observe(prob, :iv, u)[1:2] == [1.0, 4.0]
        # control: the plain integral (cell volume)
        @test observe(prob, :ii, u)[1:2] == [1.0, 2.0]
    end
end

@testitem "minimum_image: the scalar wrap on CPU types" setup = [RefHelpersSetup] tags = [
    :potts, :ref_helpers,
] begin
    @testset "minimum_image: the scalar wrap on CPU types" begin
        lat = CorePotts.Lattice((20, 12); boundary = (Periodic(), Closed()))
        @test Potts._minimum_image_axis(Float32, lat, 13.75f0, 1) === -6.25f0
        # a tie keeps d
        @test Potts._minimum_image_axis(Float32, lat, 10.0f0, 1) === 10.0f0
        @test Potts._minimum_image_axis(Float32, lat, -10.0f0, 1) === -10.0f0
        # closed axis
        @test Potts._minimum_image_axis(Float32, lat, 13.75f0, 2) === 13.75f0
        # an integer in T
        @test Potts._minimum_image_axis(Float32, lat, 3, 1) === 3.0f0
    end
end

@testitem "E7 helpers on the device (PottsDevices)" setup = [RefHelpersSetup] tags = [
    :potts, :ref_helpers, :device,
] begin
    @testset "E7 helpers on the device (PottsDevices)" begin
        if isdefined(@__MODULE__, :PottsDevices) && PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            for hex in (false, true)
                prob = rh_device_problem(hex; T = Float32)
                sol = solve(prob, CheckerboardCPM(); backend, saveat = 1)
                @test Symbol(sol.retcode) === :Success
                u = sol.u[end]
                # the device's after-MCS writes against the host's evaluation on the same
                # state
                alive = findall(>(0), Array(u.cell.volume))
                @test length(alive) == 3
                for (col, ob) in ((:wc, :oc), (:ws, :os), (:wi, :oi))
                    @test isapprox(
                        Array(getfield(u.cell, col))[alive],
                        observe(prob, ob, u)[alive]; atol = 1.0e-3
                    )
                end
                # control: the pair is apart, the norm is read
                @test all(>(0), Array(u.cell.ws)[alive])
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "E7 helpers in a @convert gate (sketch 14c's Q)" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers,
] begin
    @testset "E7 helpers in a @convert gate (sketch 14c's Q)" begin
        sol = solve(rh_conv_problem(4), SequentialCPM())
        @test Symbol(sol.retcode) === :Success
        ok, n, k3 = rh_conv_check(sol.u[end], 4; converted = true)
        # 6 sites with Q > 0, converted to a lamellipodium
        @test ok && n == 6 && k3 == 3
        # negative control: S < 0 (the nucleus at x = 17) gates every candidate off
        sol = solve(rh_conv_problem(17), SequentialCPM())
        ok, n, _ = rh_conv_check(sol.u[end], 17; converted = false)
        @test ok && n == 0
    end
end

@testitem "E7 helpers in a field equation, a site update and a site @observed" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers,
] begin
    @testset "E7 helpers in a field equation, a site update and a site @observed" begin
        prob = rh_field_problem(4)
        u = solve(prob, SequentialCPM()).u[end]
        # control: σ held through the sweep
        @test Array(u.ownership) == rh_q_sigma(4)
        o = rh_q_oracle(3.5)
        # the after-MCS site update
        @test Array(u.site.qs) == o
        # the site-scope observed quantity
        @test observe(prob, :oq, u) == o
        # one explicit Euler step of length 1 from 0
        @test isapprox(Array(u.site.qf), o; atol = 1.0e-12)
        # the cell update (14b's Πx form): wrap(20.5 − 4)
        @test Array(u.cell.qc)[1:2] == [-3.5, 0.0]
        # negative control: another nucleus position changes S, and so every value
        u17 = solve(rh_field_problem(17), SequentialCPM()).u[end]
        @test Array(u17.site.qs) == rh_q_oracle(-3.5) && Array(u17.site.qs) != o
    end
end

@testitem "E7 helpers in a @convert gate and a field equation on the device \
    (PottsDevices)" setup = [RefHelpersSetup] tags = [
    :potts, :ref_helpers, :device,
] begin
    @testset "E7 helpers in a @convert gate and a field equation on the device \
        (PottsDevices)" begin
        if isdefined(@__MODULE__, :PottsDevices) && PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            sol = solve(rh_conv_problem(4; T = Float32), alg; backend)
            @test Symbol(sol.retcode) === :Success
            ok, n, k3 = rh_conv_check(sol.u[end], 4; converted = true)
            @test ok && n == 6 && k3 == 3
            ok, n, _ = rh_conv_check(
                solve(rh_conv_problem(17; T = Float32), alg; backend).u[end],
                17; converted = false
            )
            @test ok && n == 0
            u = solve(rh_field_problem(4; T = Float32), alg; backend).u[end]
            @test Array(u.ownership) == rh_q_sigma(4)
            # dyadic values: exact in Float32
            @test Array(u.site.qs) == Float32.(rh_q_oracle(3.5))
            @test Array(u.site.qf) == Float32.(rh_q_oracle(3.5))
            @test Array(u.cell.qc)[1:2] == Float32[-3.5, 0.0]
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "integral(x; over = cluster) as a model's only cluster read" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers,
] begin
    @testset "integral(x; over = cluster) as a model's only cluster read" begin
        p = PottsProblem(
            RHOverOnly(; name = :o),
            [ownership => rh_over_sigma(), kind => [:ka, :ka], cluster => [1, 1]], (0, 1)
        )
        @test hasproperty(p.u0.cell, :cluster)
        @test Array(solve(p, SequentialCPM()).u[end].cell.a1)[1:2] == [20.0, 20.0]
        q = PottsProblem(
            RHOverOnly(; name = :o), [
                ownership => rh_over_sigma(), kind => [:ka, :ka],
            ], (0, 1)
        )
        # control: one cluster each
        @test Array(solve(q, SequentialCPM()).u[end].cell.a1)[1:2] == [16.0, 4.0]
    end
end

@testitem "_over_cluster: a dead or out-of-range slot reads 0" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers,
] begin
    @testset "_over_cluster: a dead or out-of-range slot reads 0" begin
        cell = (; volume = Int32[2, 0, 1, 3], cluster = Int32[1, 1, 1, 4])
        col = [1.0, 5.0, 2.0, 7.0]
        # alive members 1 and 3; dead 2 left out
        @test Potts._over_cluster(cell, col, 1) == 3.0
        @test Potts._over_cluster(cell, col, 3) == 3.0
        # dead slot: 0, not its cluster's total
        @test Potts._over_cluster(cell, col, 2) == 0.0
        @test Potts._over_cluster(cell, col, 0) == 0.0 &&
            Potts._over_cluster(cell, col, 5) == 0.0
        # no clusters: the cell's own
        @test Potts._over_cluster((; volume = Int32[2, 0]), [1.5, 9.0], 1) == 1.5
    end
end

@testitem "E7 helper axes and the hexagonal refusal in every context" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers,
] begin
    @testset "E7 helper axes and the hexagonal refusal in every context" begin
        # control
        @test rh_ctx_error(; mode = :ctrl_at) === nothing
        @test rh_msg(rh_ctx_error(; mode = :bad_at_axis), "minimum_image")
        @test rh_msg(rh_ctx_error(; mode = :bad_p_mi_axis), "minimum_image")
        @test rh_msg(rh_ctx_error(; mode = :bad_w_mi_axis), "minimum_image")
        @test rh_msg(rh_ctx_error(; mode = :bad_p_cent_axis), "centroid")
        @test rh_msg(rh_ctx_error(; hex = true, mode = :hex_p_mi), "minimum_image")
        # control: separation on hex
        @test rh_ctx_error(; hex = true, mode = :hex_p_sep) === nothing
        @test rh_msg(
            rh_ctx_error(; mode = :bad_temp_axis, clusters = false),
            "minimum_image"
        )
        # control
        @test rh_ctx_error(; mode = :ctrl_temp, clusters = false) === nothing
    end
end

@testitem "centroid(c, k) in a masked condition (the only centroid read)" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers, :device,
] begin
    @testset "centroid(c, k) in a masked condition (the only centroid read)" begin
        prob = rh_mask_problem()
        # the moment trackers are allocated
        @test hasproperty(prob.u0.cell, :anchor)
        u = solve(prob, SequentialCPM()).u[end]
        @test Array(u.ownership) == rh_mask_sigma()                        # control: σ held
        # cell 1 clamped; cell 2 (centroid 2) and the medium not
        @test Array(u.site.c) == 7.0 .* (rh_mask_sigma() .== 1)
        if isdefined(@__MODULE__, :PottsDevices) && PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            ud = solve(rh_mask_problem(; T = Float32), CheckerboardCPM(); backend).u[end]
            @test Array(ud.site.c) == 7.0f0 .* (rh_mask_sigma() .== 1)
        end
    end
end

@testitem "a geometry helper in a default value is a clear ArgumentError" setup = [
    RefHelpersSetup,
] tags = [
    :potts, :ref_helpers,
] begin
    @testset "a geometry helper in a default value is a clear ArgumentError" begin
        σ = zeros(Int32, 6, 6)
        σ[2:3, 2:3] .= 1
        @test_throws ArgumentError PottsProblem(
            RHDefaultMI(; name = :d), [ownership => σ, kind => [:ka]], (0, 1)
        )
    end
end
