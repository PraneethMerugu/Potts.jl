# `initial_state_tests.jl`, part B of 3: a
# PDE source on a site predicate (R5).
# Part A, `initial_state_tests.jl`: the initial-state vocabulary. Part C,
# `mean_squared_displacement_tests.jl`: MSD and the modified Fürth fits.
#
# Spec: docs/design/research/p6-5c-brief.md §1.B, §3.B, §4.B. Spec 14 Eq. 6 (l.73) with the
# code's source (§2.9.2, l.166): F-actin is produced only at lamellipodium sites with a face
# neighbour in the substrate. Decisions: D-145 (fields after `after_mcs`, `@schedule`
# placement), D-233 (`@convert`, its default place before `lifecycle`), D-085 (the device
# transfer counters), D-016 (fingerprints), D-048 (oracles and negative controls), D-242
# (no A/B unless field codegen changes).
#
# ROADMAP (`initial_state_tests.jl` row): "R5 predicate-sourced PDE".
#
# =========================================================================================
# THE CONTRACT THESE TESTS PIN (brief §3.B; no new API, no new DSL name or keyword)
# =========================================================================================
#
# - A field rate may multiply any term by a site predicate built from `kind`, neighbour
#   folds over a relation of `site` (`any(… for n in R(site))`, `count(… for n in R(site)
#   if …) > 0`), site variables, `position`, and model-local helper functions of `site`. The
#   field is a plain MTK PDESystem whose 0/1 inputs the `@fields` line binds to the predicate
#   (formerly the field line of `@equations`):
#       D(F) ~ D_F * laplacian(F) - k_d * F + k_s * lam * src            (the PDESystem)
#       @fields pde() (:lam => kind == lam,
#                            :src => any(kind[n] == substrate for n in VonNeumann(1)(site)))
# - The predicate is evaluated on the σ the field phase sees at each substep (σ does not
#   change between substeps: fields run between sweeps).
# - Out-of-lattice neighbours on closed axes are skipped; periodic axes wrap (as for every
#   gather).
# - The source is not confined: diffusion and decay act on the whole lattice.
# - Explicit Euler, n substeps of dt/n; n = max(requested, stable_substeps(D, dt, h, k)),
#   k the bound on |∂rate/∂F|. With one substep F ← F + D·ΔF − k_d·F + k_s·[pred], so
#   F → k_s/k_d at a persistent source. A closed axis without a face condition is zero flux.
# - Phase order: fields run after `after_mcs` and before every `@convert` (default schedule):
#   sweep, then the PDE, then conversion (spec 14 §2.9.6).
# - Device: the same rate runs in the generated field kernel on Metal (Float32) and ROCm, no
#   host round trip in a quiet MCS, bitwise equal to the CPU Float32 run on an exact-binary
#   fixture.
#
# Status on the base commit 588ad407 (the brief's [probe], re-run by the test author): every
# CPU testset passes (they are controls that pin the behaviour), and so does the device
# testset on Metal (POTTS_GPU=metal, this Mac, run under tools/exclusive.sh). ROCm is
# unverified (the PC); off a device the testset is `@test_skip`. The only DEFECT CHECK is the
# docs paragraph (section 10).
#
# Fixture P (exact binary arithmetic, so CPU Float64, CPU Float32 and the device agree
# bitwise): 6×6×4, boundary (Periodic, Periodic, Closed), `VonNeumann(1)`; kinds `medium
# substrate[frozen] lam`; σ: substrate (cell 1) all of z = 1 (36 sites), `lam` (cell 2) the
# box (2:3, 2:3, 2:3) (8 sites, 4 at z = 2, the 4 SOURCE sites); copies are blocked by
# `@constraint mobile > 0.5` with `mobile = 0` (the `convert_tests.jl` trick), so σ is constant;
# k_d = k_s = 1/2, F₀ = 0, `ExplicitEuler(substeps = 1)`.
#
# Sections: 1 the fixtures build; 2 gating (B1); 3 mass balance and the stencil oracle (B2);
# 4 negative controls (B3); 5 spellings (B4); 6 Fortuna's values (B5); 7 phase order with
# `@convert` (B6); 8 the device (B7); 9 fingerprints (B8); 10 docs.

@testsetup module PredicateSourceSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: CorePotts
const ON_DEVICE = PottsDevices.on_device()
const DEVICE = ON_DEVICE ? Symbol(PottsDevices.device_name()) : :none
# ---------------------------------------------------------------------------------------
# 0. Helpers and fixtures
const DEFINE_ERRORS = Dict{Symbol, Any}()
function define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
    catch e
        DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
model(name::Symbol) = isdefined(@__MODULE__, name) ? getfield(@__MODULE__, name) :
    error("initial state fixture $name did not build: $(get(DEFINE_ERRORS, name, "unknown"))")
system(name::Symbol) = Base.invokelatest(model(name); name = :pb)
const ANY = :(any(kind[n] == substrate for n in VonNeumann(1)(site)))
# The field `F` of Fixture P as a plain MTK PDESystem on the 6 × 6 × 4 lattice:
# `D_F ΔF − k_d F + k_s [lam] [src]` (`diffusion = false`: no `D_F ΔF`; `source = false`: no
# `[src]`). Its inputs `lam` (0/1) and `src` are bound at `@fields`, `lam` to `kind == lam` and
# `src` to the site predicate, so the source term is `k_s * (kind == lam) * predicate`. `src`
# is not declared `::Bool`: the coupling does not take the neighbor fold `any(… for n in …)` as
# a truth value.
function pde(; diffusion = true, source = true)
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y z D_F = 0.0 k_d = 0.5 k_s = 0.5
    Potts.ModelingToolkitBase.@variables F(..) lam(..)::Bool [input = true] src(..) [input = true]
    X, LAM, SRC = F(t, x, y, z), lam(t, x, y, z), src(t, x, y, z)
    rate = -k_d * X + (source ? k_s * LAM * SRC : k_s * LAM)
    diffusion && (rate = D_F * L.laplacian(X) + rate)
    return Potts.ModelingToolkitBase.PDESystem(
        [Potts.D(X) ~ rate], [F(0, x, y, z) ~ 0.0],
        L.lattice_domain(t, (x, y, z), (6, 6, 4)), [t, x, y, z], source ? [X, LAM, SRC] : [X, LAM],
        diffusion ? [D_F, k_d, k_s] : [k_d, k_s]; name = :predicate_field
    )
end
# a model of Fixture P's shape; `source` the site predicate of the source term (`nothing`:
# the kind test alone), `zb` the z boundary, `field = false` drops the field (the fingerprint
# control)
function predicate_src(name; source = ANY, zb = :(Closed()), field = true)
    lat = :(@lattice Lattice((6, 6, 4); boundary = (Periodic(), Periodic(), $zb), neighborhood = VonNeumann(1)))
    helper = :(touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0)
    tail = [:(@energy cells(lam) => (volume - 8.0)^2), :(@constraint mobile > 0.5), :(@sweep Metropolis(; temperature = 1.0))]
    stmts = if field
        fields = source === nothing ? :(@fields pde(; source = false) (:lam => kind == lam)) :
            :(@fields pde() (:lam => kind == lam, :src => $source))
        Any[:(@kinds medium substrate[frozen] lam), lat, helper, fields, :(@parameters mobile = 0.0), tail...]
    else
        Any[
            :(@kinds medium substrate[frozen] lam),
            :(
                @parameters begin
                    D_F = 0.0
                    k_d = 0.5
                    k_s = 0.5
                    mobile = 0.0
                end
            ), lat, helper, tail...,
        ]
    end
    return Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :predicate), name, Expr(:block, stmts...))
end
define(:PredicateAny, predicate_src(:PredicateAny))
define(:Helper, predicate_src(:Helper; source = :(touches_substrate(site))))
define(:KindOnly, predicate_src(:KindOnly; source = nothing))
define(:Position, predicate_src(:Position; source = :(position[3] == 2)))
define(:PeriodicZ, predicate_src(:PeriodicZ; zb = :(Periodic())))
define(:NoField, predicate_src(:NoField; field = false))
# σ of Fixture P: substrate (1) on z = 1, `lam` (2) on (2:3, 2:3, lamz)
function sigma(; lamz = 2:3, lamxy = (2:3, 2:3))
    σ = zeros(Int32, 6, 6, 4)
    σ[:, :, 1] .= 1
    σ[lamxy..., lamz] .= 2
    return σ
end
function problem(name = :PredicateAny; σ = sigma(), tspan = (0, 5), T = Float64, solver = ExplicitEuler(substeps = 1), p = ())
    prob = PottsProblem(system(name), [ownership => σ, kind => [:substrate, :lam]], tspan; T, field_solver = solver)
    return isempty(p) ? prob : remake(prob; p = collect(p))
end
predicate_fields(sol) = [Array(u.site.F) for u in sol.u]
predicate_run(args...; alg = SequentialCPM(), kw...) = predicate_fields(solve(problem(args...; kw...), alg; saveat = 1))
# the substep count of the field step of a running integrator with the automatic count
# (`ExplicitEuler()`), at parameters `p` (the field-compiler switch: LatticePDE's stability bound)
live_n(; p = ()) = CorePotts._runtime(
    getfield(
        init(problem(; p, solver = ExplicitEuler()), SequentialCPM()).ctx,
        :__fields1
    )
).n
# The source sites of a σ: `lam` sites with a VonNeumann(1) neighbour in the substrate,
# x, y periodic, z closed unless `zper` (independent of the code under test)
function sources(σ; zper = false)
    dims = size(σ)
    src = falses(dims)
    for I in CartesianIndices(σ)
        σ[I] == 2 || continue
        for d in 1:3, s in (-1, 1)
            y = collect(Tuple(I))
            y[d] += s
            if d < 3 || zper
                y[d] = mod1(y[d], dims[d])
            elseif !(1 <= y[d] <= dims[d])
                continue
            end
            σ[y...] == 1 && (src[I] = true)
        end
    end
    return src
end
# The hand-rolled 7-point explicit Euler oracle (one substep, dt = h = 1): F ← F + D·ΔF −
# k_d·F + k_s·[src], ΔF = Σ over the in-lattice face neighbours of (F[n] − F[x]) (x, y wrap;
# z closed: an out-of-lattice neighbour is skipped, i.e. zero flux).
function predicate_oracle(src, nsteps; D, kd = 0.5, ks = 0.5, T = Float64)
    dims = size(src)
    F = zeros(T, dims)
    out = [copy(F)]
    for _ in 1:nsteps
        G = similar(F)
        for I in CartesianIndices(F)
            x = Tuple(I)
            lap = zero(T)
            for d in 1:3, s in (-1, 1)
                y = collect(x)
                y[d] += s
                if d < 3
                    y[d] = mod1(y[d], dims[d])
                elseif !(1 <= y[d] <= dims[d])
                    continue
                end
                lap += F[y...] - F[I]
            end
            G[I] = F[I] + T(D) * lap - T(kd) * F[I] + (src[I] ? T(ks) : zero(T))
        end
        F = G
        push!(out, copy(F))
    end
    return out
end
# ---------------------------------------------------------------------------------------
# 7. Phase order with `@convert` (B6): fields run before the conversion pass
const CONVERT_BODY = quote
    @kinds medium substrate[frozen] cyto lam
    @lattice Lattice((6, 6, 4); boundary = (Periodic(), Periodic(), Closed()), neighborhood = VonNeumann(1))
    touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0
    @fields pde(; diffusion = false) (:lam => kind == lam, :src => touches_substrate(site))
    @parameters mobile = 0.0
    @energy begin
        cells(cyto, lam) => (volume - 8.0)^2
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 1.0, 3.0)
    end
    @constraint mobile > 0.5
    @convert protrusion clusters(cyto) begin
        to = sibling(lam)
        at = touches_substrate(site)
    end
    @sweep Metropolis(; temperature = 1.0)
end
define(:Convert, Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :predicate), :Convert, CONVERT_BODY))
let body = Base.deepcopy(CONVERT_BODY)
    i = findfirst(a -> a isa Expr && a.head === :macrocall && a.args[1] === Symbol("@sweep"), body.args)
    insert!(body.args, i, :(@schedule sweep, protrusion, fields))        # the convert before the fields
    define(:ConvertFirst, Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :predicate), :ConvertFirst, body))
end
# substrate 1 (z = 1); cyto 2 (4:5, 2:3, 2:3), the cluster root (lowest id); lam 3 (2:3,
# 2:3, 2:3). The 4 cyto sites at z = 2 touch the substrate and convert (p = 1) in MCS 1.
function convert_run(name)
    σ = sigma()
    σ[σ .== 2] .= 3
    σ[4:5, 2:3, 2:3] .= 2
    prob = PottsProblem(
        system(name), [ownership => σ, kind => [:substrate, :cyto, :lam], cluster => [1, 2, 2]], (0, 3);
        field_solver = ExplicitEuler(substeps = 1)
    )
    return solve(prob, SequentialCPM(); saveat = 1)
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "initial state predicate source: the fixtures build" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. The fixtures build
    @testset "initial state predicate source: the fixtures build" begin
        for name in (:PredicateAny, :Helper, :KindOnly, :Position, :PeriodicZ, :NoField)
            @test isdefined(@__MODULE__, name)                       # control
        end
        @test mtkcompile(system(:PredicateAny)) isa CompiledPottsSystem               # control
        # the oracle's source set: the 4 `lam` sites at z = 2
        src = sources(sigma())
        @test count(src) == 4 && all(src[2:3, 2:3, 2])               # control (oracle)
    end
end

@testitem "initial state predicate source: the source is gated by the predicate (D_F = 0)" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Gating, D_F = 0 (B1)
    @testset "initial state predicate source: the source is gated by the predicate (D_F = 0)" begin
        Fs = predicate_run()
        σ = sigma()
        src = sources(σ)
        for n in 0:5
            F = Fs[n + 1]
            @test all(F[src] .== 1 - 0.5^n)                          # control: 0, 0.5, 0.75, 0.875, …
            @test all(iszero, F[.!src])                              # control: the other lam sites, medium, substrate
            @test sum(F) == 4 * (1 - 0.5^n)                          # control
        end
        @test all(iszero, Fs[end][σ .== 2 .&& .!src])                # control: the 4 lam sites at z = 3
    end
end

@testitem "initial state predicate source: mass balance and the 7-point oracle (D_F = 1/16)" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. Mass balance with diffusion, and the stencil oracle (B2)
    @testset "initial state predicate source: mass balance and the 7-point oracle (D_F = 1/16)" begin
        D = 0.0625
        # the automatic count is 1: ceil((D·12 + k_d)/1.8) = ceil(1.25/1.8) = 1
        @test live_n(; p = (:D_F => D,)) == 1                                    # control (the live count, the field-compiler switch)
        Fs = predicate_run(; p = (:D_F => D,))
        auto = predicate_run(; p = (:D_F => D,), solver = ExplicitEuler())
        @test auto == Fs                                             # control: the automatic count is the requested 1
        src = sources(sigma())
        want = predicate_oracle(src, 5; D)
        for n in 0:5
            # diffusion conserves mass and the closed z faces are zero flux:
            # ΣF_{n+1} = (1 − k_d)ΣF_n + k_s·4
            @test sum(Fs[n + 1]) == 4 * (1 - 0.5^n)                  # control
            @test Fs[n + 1] == want[n + 1]                           # control: bitwise (exact binary values)
        end
        # not confined: the field spreads beyond the lam box, into the medium and the substrate
        lam = sigma() .== 2
        @test count(>(0), Fs[end][.!lam]) > 0                        # control
        @test Fs[end][2, 2, 1] > 0 && Fs[end][2, 2, 4] > 0           # control
        # negative control: the oracle with D = 0 differs (diffusion acted)
        @test predicate_oracle(src, 5; D = 0.0)[end] != Fs[end]
    end
end

@testitem "initial state predicate source: negative controls (no contact, kind-only, wrap)" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. Negative controls (B3)
    @testset "initial state predicate source: negative controls (no contact, kind-only, wrap)" begin
        # (a) lam lifted to (2:3, 2:3, 3:4): no site touches the substrate, ΣF ≡ 0
        σa = sigma(; lamz = 3:4)
        @test count(sources(σa)) == 0                          # control (oracle)
        @test all(F -> all(iszero, F), predicate_run(; σ = σa))          # control
        @test all(F -> all(iszero, F), predicate_run(; σ = σa, p = (:D_F => 0.0625,)))
        # (b) the kind-only source: every lam site, ΣF = 8(1 − 0.5ⁿ); the predicate matters
        Fb = predicate_run(:KindOnly)
        @test [sum(F) for F in Fb] == [8 * (1 - 0.5^n) for n in 0:5]                      # control
        @test [sum(F) for F in predicate_run()] != [sum(F) for F in Fb]
        # (c) lam at z = 4 only: through the periodic z wrap it touches the substrate (4 sources);
        # with closed z it does not
        σc = sigma(; lamz = 4:4)
        @test count(sources(σc; zper = true)) == 4 && count(sources(σc)) == 0   # control (oracle)
        @test [sum(F) for F in predicate_run(:PeriodicZ; σ = σc)] == [4 * (1 - 0.5^n) for n in 0:5]   # control
        @test all(F -> all(iszero, F), predicate_run(; σ = σc))          # control
    end
end

@testitem "initial state predicate source: the helper and position spellings agree" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 5. Spellings (B4)
    @testset "initial state predicate source: the helper and position spellings agree" begin
        base = predicate_run(; p = (:D_F => 0.0625,))
        @test predicate_run(:Helper; p = (:D_F => 0.0625,)) == base                    # control: `count(…) > 0` helper
        # on Fixture P the source sites are exactly the lam sites at z = 2
        @test predicate_run(:Position; p = (:D_F => 0.0625,)) == base                  # control: `position[3] == 2`
        # and the spellings differ where the predicates do: lam moved to (2:3, 2:3, 3:4)
        σ = sigma(; lamz = 3:4)
        @test all(F -> all(iszero, F), predicate_run(:Helper; σ))   # control
        @test all(F -> all(iszero, F), predicate_run(:Position; σ)) # control: no lam site at z = 2 either
        σ2 = sigma(; lamz = 2:2, lamxy = (1:6, 1:6))           # a full sheet at z = 2: position and contact agree
        @test predicate_run(:Position; σ = σ2) == predicate_run(; σ = σ2)                   # control
    end
end

@testitem "initial state predicate source: Fortuna's values (one substep, F → 0.9, 0.99, 0.999)" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 6. Fortuna's values (B5): D_F = 1e-4, k_d = k_s = 0.9, 3D, h = 1, dt = 1
    @testset "initial state predicate source: Fortuna's values (one substep, F → 0.9, 0.99, 0.999)" begin
        # the automatic count with the reaction bound: ceil((1e-4·12 + 0.9)/1.8) = 1
        @test live_n(; p = (:D_F => 1.0e-4, :k_d => 0.9, :k_s => 0.9)) == 1        # control (the live count, the field-compiler switch)
        fortuna = (:k_d => 0.9, :k_s => 0.9)
        # a site that becomes a source with all-zero neighbours holds 0.9 after one MCS (two
        # substeps would give 1 − 0.55² = 0.6975): the requested `substeps = 1` is honoured
        Fs = predicate_run(; p = (fortuna..., :D_F => 0.0), tspan = (0, 3))
        src = sources(sigma())
        @test all(F -> isapprox(F, 0.9; rtol = 1.0e-14), Fs[2][src])             # control
        @test all(F -> isapprox(F, 0.99; rtol = 1.0e-14), Fs[3][src])            # control
        @test all(F -> isapprox(F, 0.999; rtol = 1.0e-14), Fs[4][src])           # control
        @test all(F -> isapprox(F, 0.9; rtol = 1.0e-14), predicate_run(; p = (fortuna..., :D_F => 1.0e-4), tspan = (0, 1))[2][src])   # control
        @test predicate_run(; p = (fortuna..., :D_F => 1.0e-4), tspan = (0, 1), solver = ExplicitEuler())[2] ==
            predicate_run(; p = (fortuna..., :D_F => 1.0e-4), tspan = (0, 1))[2]                # control: auto = 1
        # a source sheet (lam on all of z = 2): an interior source site has k = 2 non-source
        # face neighbours (the substrate below, the medium above), so F → 0.9/(0.9 + 2·D_F)
        # (spec l.174: 0.99978)
        σs = sigma(; lamz = 2:2, lamxy = (1:6, 1:6))
        Fsh = predicate_run(; σ = σs, p = (fortuna..., :D_F => 1.0e-4), tspan = (0, 40))
        target = 0.9 / (0.9 + 2 * 1.0e-4)
        @test target ≈ 0.99978 atol = 1.0e-5                           # control (arithmetic)
        @test all(F -> abs(F - target) < 1.0e-3, Fsh[end][:, :, 2])     # control
        # negative control: without diffusion the sheet tends to k_s/k_d = 1, outside the band
        @test all(F -> abs(F - 1.0) < 1.0e-12, predicate_run(; σ = σs, p = (fortuna..., :D_F => 0.0), tspan = (0, 40))[end][:, :, 2])
        @test abs(1.0 - target) > 1.0e-4
    end
end

@testitem "initial state predicate source: fields run before @convert (default schedule)" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "initial state predicate source: fields run before @convert (default schedule)" begin
        sol = convert_run(:Convert)
        conv = [CartesianIndex(x, y, 2) for x in 4:5, y in 2:3]
        @test all(I -> Array(sol.u[1].ownership)[I] == 2, conv)              # control: cyto at t = 0
        @test all(I -> Array(sol.u[2].ownership)[I] == 3, conv)              # control: converted to lam in MCS 1
        @test Array(sol.u[2].cell.volume)[2:3] == [4, 12]            # control
        F1, F2 = Array(sol.u[2].site.F), Array(sol.u[3].site.F)
        # in the converting MCS the field ran on the old σ (the sites were cyto): F = 0 there
        @test all(I -> F1[I] == 0.0, conv)                           # control
        # after the next MCS they are sources: 0.5
        @test all(I -> F2[I] == 0.5, conv)                           # control
        # the original lam sources: 0.5 then 0.75
        @test F1[2, 2, 2] == 0.5 && F2[2, 2, 2] == 0.75              # control
        # negative control: the convert listed before `fields` (D-145 placement) gives 0.5 in
        # the converting MCS
        early = convert_run(:ConvertFirst)
        @test all(I -> Array(early.u[2].ownership)[I] == 3, conv)            # control
        @test all(I -> Array(early.u[2].site.F)[I] == 0.5, conv)     # control
    end
end

@testitem "initial state predicate source: on the device, Float32, bitwise" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 8. The device (B7)
    @testset "initial state predicate source: on the device ($(DEVICE)), Float32, bitwise" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            cases = [
                ("B1 gating", (; p = ())),
                ("B2 diffusion", (; p = (:D_F => 0.0625,))),
                ("B3(a) no contact", (; σ = sigma(; lamz = 3:4), p = (:D_F => 0.0625,))),
            ]
            for (label, kw) in cases
                cpu = solve(problem(; T = Float32, kw...), SequentialCPM(); saveat = 1)
                dev = solve(problem(; T = Float32, kw...), alg; backend, saveat = 1)
                @test Symbol(dev.retcode) === :Success
                @test length(dev.u) == 6
                @test all(i -> Array(cpu.u[i].site.F) == Array(dev.u[i].site.F), eachindex(cpu.u))   # control on Metal (base commit); ROCm unverified
                @test all(i -> Array(cpu.u[i].ownership) == Array(dev.u[i].ownership), eachindex(cpu.u))
            end
            # the CPU Float32 run equals the Float32 oracle (exact binary values)
            cpu = predicate_fields(solve(problem(; T = Float32, p = (:D_F => 0.0625,)), SequentialCPM(); saveat = 1))
            @test cpu == predicate_oracle(sources(sigma()), 5; D = 0.0625, T = Float32)
            # no host round trip in a quiet MCS (the field kernel gathers `kind` on the device)
            integ = init(
                problem(; T = Float32, tspan = (0, 8), p = (:D_F => 0.0625,)), alg; backend, save_start = false,
                save_end = false
            )
            step!(integ)
            counts = NTuple{3, Int}[]
            for _ in 1:4
                c0 = (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes)
                step!(integ)
                push!(counts, (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes) .- c0)
            end
            @test all(==((0, 0, 0)), counts)
            u = current_state(integ)                                              # a read point
            @test sum(Array(u.site.F)) > 0                           # control: the source ran
            @test integ.stats.transfers > 0                          # control: the counters are live
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "initial state predicate source: the equations manual shows a source on a site predicate" setup = [PredicateSourceSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 10. Docs (brief §1.B item 2)
    @testset "initial state predicate source: the equations manual shows a source on a site predicate" begin
        md = read(joinpath(@__DIR__, "..", "..", "..", "..", "docs", "src", "manual", "equations.md"), String)
        @test occursin("@equations", md)                             # control: the page exists
        # any `kind[n] ==` test in an `any(… for n in …)` neighbourhood comprehension (D-244)
        @test occursin(r"any\([^\n]*kind\[n\]\s*==\s*\w+[^\n]*\bfor\s+n\s+in\s+[^\n]+\)", md)   # DEFECT CHECK
    end
end
