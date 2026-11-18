# Property-based tests for `prob.f.fingerprint` (TS-R2 §2.1, R2):
# sensitivity across every semantic input, invariance under cosmetic changes, coverage of
# published PottsModels and fixtures, and negative controls for P6.0aq, P6.0ar, P6.0p,
# P6.0c2, and F4-E15.

@testsetup module FPPropsSetup
using Potts, PottsModels, Test
using Potts: CorePotts
isdefined(@__MODULE__, :SingleDivisionFixture) ||
    include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "fixtures.jl"))
include(joinpath(@__DIR__, "shared", "props.jl"))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "fingerprint sensitivity and invariance across semantic inputs" setup = [FPPropsSetup] tags = [:potts, :fingerprint] begin
    @testset "fingerprint sensitivity and invariance across semantic inputs" begin
        @potts_model FPBase begin
            @structural_parameters begin
                dims = (12, 12)
                boundary = Periodic()
                energy_scale = 1.0
                divide_every = 1
                sched_order = :sweep_first
                mcs_dur = 1.0
                law = :metropolis
                offset = 0.0
                proposal_rel = VonNeumann(1)
                contact_rel = nothing
            end
            @kinds medium cell
            @parameters begin
                J[2, 2] = [0.0 4.0; 4.0 2.0]
                λ = 1.0
                V₀ = 9.0
                k = 0.3
                Dcoef = 0.1
                T = 1.0
            end
            @variables begin
                y(cell) = 1.0
                u(site) = 0.0
            end
            @lattice Lattice(dims; boundary)
            @energy begin
                contacts => J[kind, neighbor_kind]
                cells => energy_scale * λ * (volume - V₀)^2
            end
            @equations begin
                D(y) ~ -k * y
            end
            @after_mcs y ~ y + 0.01
            @divide cells when = volume >= 100, every = divide_every
            if sched_order === :sweep_first
                @schedule sweep, fields
            else
                @schedule fields, sweep
            end
            @relations proposal = proposal_rel
            if contact_rel !== nothing
                @relations contact = contact_rel
            end
            if law === :barker
                @sweep Barker(; temperature = T, mcs_duration = mcs_dur, offset)
            else
                @sweep Metropolis(; temperature = T, mcs_duration = mcs_dur, offset)
            end
        end

        @potts_model FPEqTermOrder begin
            @kinds medium cell
            @parameters begin
                k = 0.3
                Dcoef = 0.1
                T = 1.0
                J[2, 2] = [0.0 4.0; 4.0 2.0]
                V₀ = 9.0
                λ = 1.0
            end
            @variables begin
                y(cell) = 1.0
                u(site) = 0.0
            end
            @lattice Lattice((12, 12); boundary = Periodic())
            @energy begin
                cells => λ * (volume - V₀)^2
                contacts => J[kind, neighbor_kind]
            end
            @equations begin
                D(y) ~ -k * y
            end
            @after_mcs y ~ y + 0.01
            @divide cells when = volume >= 100, every = 1
            @relations proposal = VonNeumann(1)
            @sweep Metropolis(; temperature = T, mcs_duration = 1.0)
        end

        function base_state(dims = (12, 12))
            σ = zeros(Int32, dims)
            σ[3:5, 3:5] .= 1
            return [ownership => σ, kind => [:cell]]
        end

        make_base(; sys = FPBase(; name = :fp), dims = (12, 12), kw...) =
            PottsProblem(
            sys, base_state(dims), (0, 4);
            ode_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0), kw...
        )

        res = fp_props(
            make_base;
            variants = (
                (:lattice_dims, () -> make_base(; sys = FPBase(; name = :fp, dims = (14, 14)), dims = (14, 14))),
                (:lattice_boundary, () -> make_base(; sys = FPBase(; name = :fp, boundary = Closed()))),
                (:compute_type, () -> make_base(; T = Float32)),
                (:ode_solver, () -> make_base(; ode_solver = Potts.RK4())),
                (:phase_cadence_every, () -> make_base(; sys = FPBase(; name = :fp, divide_every = 2))),
                (:schedule_order, () -> make_base(; sys = FPBase(; name = :fp, sched_order = :fields_first))),
                (:mcs_duration, () -> make_base(; sys = FPBase(; name = :fp, mcs_dur = 2.0))),
                (:acceptance_law, () -> make_base(; sys = FPBase(; name = :fp, law = :barker))),
                (:acceptance_offset, () -> make_base(; sys = FPBase(; name = :fp, offset = 0.5))),
                (:proposal_relation, () -> make_base(; sys = FPBase(; name = :fp, proposal_rel = Moore(1)))),
                (:contact_relation, () -> make_base(; sys = FPBase(; name = :fp, contact_rel = VonNeumann(1)))),
                (:track_references, () -> make_base(; track = (:references,))),
                (:generated_code, () -> make_base(; sys = FPBase(; name = :fp, energy_scale = 2.0))),
            ),
            invariants = (
                (:model_name, () -> make_base(; sys = FPBase(; name = :renamed))),
                (
                    :parameter_value, () -> PottsProblem(
                        FPBase(; name = :fp),
                        vcat(base_state(), Any[:k => 0.7]), (0, 4);
                        ode_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)
                    ),
                ),
                (:term_and_param_order_and_omitted_default_schedule, () -> make_base(; sys = FPEqTermOrder(; name = :fp))),
                (:metropolis_explicit_zero_offset, () -> make_base(; sys = FPBase(; name = :fp, offset = -0.0))),
                (
                    :solver_kw_order, () -> PottsProblem(
                        FPBase(; name = :fp), base_state(), (0, 4);
                        ode_solver = ExplicitEuler(lower_bound = 0.0, substeps = 2)
                    ),
                ),
            ),
            check_checkpoint = true,
            check_algorithms = true
        )
        @test res.sensitivity == 13
        @test res.invariance == 5

        # Field solver substeps sensitivity on MerksVasculogenesis (has PDE field)
        let s_m = zeros(Int32, 8, 8)
            s_m[3:5, 3:5] .= 1
            m_sys = MerksVasculogenesis(; name = :m, lattice = (8, 8))
            p_fs2 = PottsProblem(
                m_sys, [ownership => s_m, kind => [:endothelial]], (0, 2);
                field_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)
            )
            p_fs4 = PottsProblem(
                m_sys, [ownership => s_m, kind => [:endothelial]], (0, 2);
                field_solver = ExplicitEuler(substeps = 4, lower_bound = 0.0)
            )
            @test p_fs2.f.fingerprint != p_fs4.f.fingerprint
        end

        # Gather relation sensitivity (separate model with gather expression)
        @potts_model FPGatherA begin
            @kinds medium cell
            @parameters λ = 1.0 V₀ = 9.0 T = 1.0
            @variables q(site) = 1.0
            @lattice Lattice((12, 12); boundary = Periodic())
            @energy cells => λ * (volume - V₀)^2 + 0.01 * count(q[n] == id for n in VonNeumann(1)(40))
            @sweep Metropolis(; temperature = T)
        end
        @potts_model FPGatherB begin
            @kinds medium cell
            @parameters λ = 1.0 V₀ = 9.0 T = 1.0
            @variables q(site) = 1.0
            @lattice Lattice((12, 12); boundary = Periodic())
            @energy cells => λ * (volume - V₀)^2 + 0.01 * count(q[n] == id for n in Moore(1)(40))
            @sweep Metropolis(; temperature = T)
        end
        @test PottsProblem(FPGatherA(; name = :ga), base_state(), (0, 2)).f.fingerprint !=
            PottsProblem(FPGatherB(; name = :gb), base_state(), (0, 2)).f.fingerprint
    end
end

@testitem "fingerprint invariance across published PottsModels and fixtures" setup = [FPPropsSetup] tags = [:potts, :fingerprint] begin
    using Potts.Layouts
    @testset "fingerprint invariance across published PottsModels and fixtures" begin
        two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
        models = (
            (
                "GranerGlazier", name -> (
                    s = graner_glazier_state();
                    PottsProblem(GranerGlazier(; name), [ownership => s[1], kind => s[2]], (0, 2))
                ),
            ),
            (
                "WortelAct", name -> PottsProblem(
                    WortelAct(; name, lattice = (8, 8)),
                    [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 2)
                ),
            ),
            (
                "WortelAct(connected)", name -> PottsProblem(
                    WortelAct(; name, lattice = (8, 8), connected = true),
                    [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 2)
                ),
            ),
            (
                "MerksVasculogenesis", name -> PottsProblem(
                    MerksVasculogenesis(; name, lattice = (8, 8)),
                    [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 2);
                    field_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)
                ),
            ),
            (
                "Merks2006", name -> PottsProblem(
                    Merks2006(; name, lattice = (16, 16)),
                    layout(merks2006_layout(; lattice = (16, 16), n = 3, side = 4), (16, 16)), (0, 2);
                    field_solver = ExplicitEuler(substeps = 15)
                ),
            ),
            (
                "Merks2008", name -> PottsProblem(
                    Merks2008(; name, lattice = (16, 16)),
                    [layout(merks2008_denovo(; lattice = (16, 16), n = 4, rounds = 2), (16, 16)); :t_relax => 0.0], (0, 2);
                    field_solver = ExplicitEuler(substeps = 15)
                ),
            ),
            (
                "OpenVTGrowingMonolayer", name -> PottsProblem(
                    OpenVTGrowingMonolayer(; name, lattice = (24, 24)),
                    openvt_monolayer_state(; lattice = (24, 24)), (0, 2); capacity = 64
                ),
            ),
            (
                "OpenVTReferenceMonolayer", name -> PottsProblem(
                    OpenVTReferenceMonolayer(; name, lattice = (24, 24)),
                    openvt_reference_state(; lattice = (24, 24)), (0, 2); capacity = 64
                ),
            ),
            (
                "OpenVTChain", name -> PottsProblem(
                    OpenVTChain(; name, lattice = (150, 5)),
                    openvt_chain(11), (0, 2)
                ),
            ),
            (
                "AkeebInvasion", name -> PottsProblem(
                    AkeebInvasion(; name, lattice = (60, 40)),
                    akeeb_state(; lattice = (60, 40)), (0, 2); capacity = 256
                ),
            ),
            (
                "ShearedFoam", name -> PottsProblem(
                    ShearedFoam(; name, lattice = (32, 32)),
                    [sheared_foam_state(; lattice = (32, 32)); :ytop => 32.0; :ymid => 16.5; :γ0 => 2.0; :T => 1.0], (0, 2)
                ),
            ),
            (
                "SingleDivisionFixture", name -> PottsProblem(
                    SingleDivisionFixture(; name),
                    [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 2)
                ),
            ),
        )
        @testset "$label" for (label, build) in models
            p1 = build(:m1)
            p2 = build(:m2)
            @test p1.f.fingerprint == build(:m1).f.fingerprint
            @test p1.f.fingerprint == p2.f.fingerprint
            tracked = remake(p1; track = (:references,))
            @test tracked.f.fingerprint != p1.f.fingerprint
            ck = checkpoint(init(p1, SequentialCPM(); save_start = false))
            @test_throws ArgumentError init(tracked, SequentialCPM(); checkpoint = ck)
        end
    end
end

@testitem "fingerprint negative controls (P6.0aq, P6.0ar, P6.0p, P6.0c2, F4-E15)" setup = [FPPropsSetup] tags = [:potts, :fingerprint] begin
    @testset "fingerprint negative controls (P6.0aq, P6.0ar, P6.0p, P6.0c2, F4-E15)" begin
        σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
        op = [ownership => σ, kind => [:cell]]

        @potts_model NCBase begin
            @structural_parameters begin
                law = :metropolis
                proposal_rel = nothing
                contact_rel = nothing
                divide_every = nothing
            end
            @kinds medium cell
            @parameters λ = 1.0 V₀ = 9.0 T = 1.0
            @lattice Lattice((10, 10))
            if proposal_rel !== nothing
                @relations proposal = proposal_rel
            end
            if contact_rel !== nothing
                @relations contact = contact_rel
            end
            @energy cells => λ * (volume - V₀)^2
            if divide_every !== nothing
                @divide cells when = volume >= 100, every = divide_every
            end
            if law === :barker
                @sweep Barker(; temperature = T)
            else
                @sweep Metropolis(; temperature = T)
            end
        end

        # P6.0aq: acceptance law must enter the fingerprint (a naive hash omitting law fails)
        sys_m = NCBase(; name = :m, law = :metropolis)
        sys_b = NCBase(; name = :m, law = :barker)
        fp_m = PottsProblem(sys_m, op, (0, 2)).f.fingerprint
        fp_b = PottsProblem(sys_b, op, (0, 2)).f.fingerprint
        @test fp_m != fp_b
        naive_no_law(sys) = hash(
            (
                nameof(sys),
                string.(Potts.declared_parameters(sys)),
                Potts.part(sys).kinds,
                string(Potts.part(sys).lattice),
                string.(Potts.part(sys).energies),
                string(Potts.part(sys).relations),
            )
        )
        @test naive_no_law(sys_m) == naive_no_law(sys_b)   # negative control: omitting law collides

        # P6.0ar: non-default proposal relation must enter the fingerprint
        sys_vn = NCBase(; name = :m, proposal_rel = VonNeumann(1))
        sys_mo = NCBase(; name = :m, proposal_rel = Moore(1))
        @test PottsProblem(sys_vn, op, (0, 2)).f.fingerprint !=
            PottsProblem(sys_mo, op, (0, 2)).f.fingerprint
        naive_no_prop(sys) = hash(
            (
                nameof(sys),
                string.(Potts.declared_parameters(sys)),
                Potts.part(sys).kinds,
                string(Potts.part(sys).lattice),
                string.(Potts.part(sys).energies),
                string(Potts.part(sys).sweep),
            )
        )
        @test naive_no_prop(sys_vn) == naive_no_prop(sys_mo)  # negative control: omitting proposal collides

        # P6.0p: phase cadence (every = 1 vs every = 2) must enter the fingerprint
        @test PottsProblem(NCBase(; name = :a, divide_every = 1), op, (0, 2)).f.fingerprint !=
            PottsProblem(NCBase(; name = :b, divide_every = 2), op, (0, 2)).f.fingerprint

        # P6.0c2: closure session token binding (distinct closure values get distinct fingerprints)
        f1 = x -> x + 1.0
        f2 = x -> x + 2.0
        c1 = Potts._canonical(Adaptive(Potts.RK4(); fn = f1))
        c2 = Potts._canonical(Adaptive(Potts.RK4(); fn = f2))
        @test c1 != c2
        @test occursin("var\"#", c1)
        # Two anonymous closures capturing different constants must not produce identical
        # PottsProblem fingerprints
        @potts_model NCAdapt begin
            @kinds medium cell
            @parameters λ = 1.0 V₀ = 9.0 T = 1.0
            @variables y(cell) = 1.0
            @lattice Lattice((10, 10))
            @energy cells => λ * (volume - V₀)^2
            @equations D(y) ~ -y
            @sweep Metropolis(; temperature = T)
        end
        make_biased(c) = (u -> u + c)
        b1, b2 = make_biased(1.0), make_biased(2.0)
        @test hash(b1) != hash(b2)
        @test string(typeof(b1).name.name) == string(typeof(b2).name.name)  # negative control: type name alone drops captured state
        fp_a1 = PottsProblem(NCAdapt(; name = :m), op, (0, 2); ode_solver = Adaptive(Potts.RK4(); fn = b1)).f.fingerprint
        fp_a2 = PottsProblem(NCAdapt(; name = :m), op, (0, 2); ode_solver = Adaptive(Potts.RK4(); fn = b2)).f.fingerprint
        @test fp_a1 != fp_a2

        # F4-E15: anonymous neighborhood weight functions with different bodies produce distinct
        # fingerprints, and identical bodies produce equal fingerprints
        w1 = o -> 1.0 / sum(abs2, o)
        w1b = o -> 1.0 / sum(abs2, o)
        w2 = o -> 2.0 / sum(abs2, o)
        p_w1 = PottsProblem(NCBase(; name = :w, contact_rel = CorePotts.Weighted(Moore(1), w1)), op, (0, 2))
        p_w1b = PottsProblem(NCBase(; name = :w, contact_rel = CorePotts.Weighted(Moore(1), w1b)), op, (0, 2))
        p_w2 = PottsProblem(NCBase(; name = :w, contact_rel = CorePotts.Weighted(Moore(1), w2)), op, (0, 2))
        @test p_w1.f.fingerprint == p_w1b.f.fingerprint
        @test p_w1.f.fingerprint != p_w2.f.fingerprint
    end
end
