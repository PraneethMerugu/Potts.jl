# F3-18 (F3 design §5, v3 §7.3 (b)): a Jiang-like integration test. The structure of Jiang et
# al. 2005 (spec 06 §2.5): five fields on the lattice coarsened by 4 (paper p. 10), O₂ and
# glucose consumed above their thresholds by the viable cells (the switch `max(u − u_T, 0)`),
# lactate produced from both consumptions (it reads O₂ and glucose), a growth factor consumed
# and an inhibitor produced by kind, each field held at its medium value on the medium (the
# moving masked Dirichlet: the tumor-medium interface), BackwardEuler, and four field windows
# per MCS between quarter sweeps (Fig. 3: `repeat(4, sweep(fraction = 1//4), fields)`). The
# rates are the paper's ratios in lattice units, with O₂'s diffusion scaled so that its shift
# `h²/(D dt)` on the coarse grid is about 0.022 (v3 §6.3). The cell average of O₂ is read through
# `integral(o) / volume`. With σ frozen the model equals B (`Potts.fields` → `discretize`) bitwise.
# Base 392dd404 (~/lpwork/f3b6-nc-a.log): `lattice_level` is not an option of `variable`.

@testsetup module FieldsJiangSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
isdefined(@__MODULE__, :JiangLike) || include(joinpath(@__DIR__, "fields_jiang_model.jl"))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "F3-18: a Jiang-like model equals B bitwise (σ frozen, CPU)" setup = [FieldsJiangSetup] tags = [:potts, :fields_jiang] begin
    @testset "F3-18: a Jiang-like model equals B bitwise (σ frozen, CPU)" begin
        σ, kinds = jiang_state(JG_DIMS)
        @test Set(kinds) == Set([:N, :Q, :P])
        k = 2
        integ = init(PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, k);
            field_solver = BackwardEuler()), SequentialCPM(); save_start = false)
        names = (:o, :g, :l, :gf, :inh)
        a = [(step!(integ); st = current_state(integ); (; (n => copy(Array(getproperty(st.site, n))) for n in names)...,
                                                         ocell = copy(st.cell.ocell))) for _ in 1:k]
        @test integ.retcode in (Potts.SciMLBase.ReturnCode.Default, Potts.SciMLBase.ReturnCode.Success)
        @test size(a[1].o) == JG_DIMS .÷ 4
        # B: the same fields at the same window (a quarter MCS), the kind map of the frozen cells
        kmap = Int32[s == 0 ? 0 : findfirst(==(kinds[s]), [:P, :Q, :N]) for s in σ]
        bp = Potts.LatticePDE.discretize(Potts.fields(JiangLike(; name = :j)),
            Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(JG_DIMS); T = Float64);
            u0 = [n => zeros(JG_DIMS .÷ 4) for n in names], tspan = (0, k), inputs = [:kind => kmap])
        sb = Potts.LatticePDE.solve(bp, BackwardEuler(); dt = 0.25, saveat = 1.0)
        for n in names
            @test [x[n] for x in a] == [sb[n, i] for i in 2:length(sb.t)]
        end
        # the fields are not trivial: O₂ falls from the medium value into the spheroid; lactate is
        # produced; the inhibitor grows in the core
        o = a[end].o
        @info "F3-18 (CPU, 32³ lattice, 8³ fields): O₂ $(extrema(o)), lactate max $(maximum(a[end].l)), inhibitor max $(maximum(a[end].inh))"
        @test maximum(o) == 0.08 && minimum(o) < 0.04
        @test maximum(a[end].l) > 0 && maximum(a[end].inh) > 0
        # the cell average of O₂ through the coarse read (`after_mcs` runs after the MCS's field windows)
        o1 = a[2].o
        hand = [sum(o1[((Tuple(I) .- 1) .÷ 4 .+ 1)...] for I in CartesianIndices(σ) if σ[I] == n) / count(==(n), σ)
                for n in 1:length(kinds)]
        @test a[2].ocell ≈ hand rtol = 1e-13
    end
end

# F4-15 (user ruling 2026-11-11): the coupled model equals its own PDESystem (`JgPDE.jiang`)
# solved by LatticePDE with `Potts.field_inputs(integ, pdesys)`. The kind bindings (`pq =>
# ismember(kind, (P, Q))`, `kQ => kind == Q`, ...) and the PDESystem's Bool inputs fold by one rule
# on the Coarse(4) grid, the block mean, so the two agree on the spheroid's rim, where blocks are
# covered in part. This replaces the F2 guard's digests of this model (D-274).
# Base 5e972579 (~/lpwork/f4F15/nc.log): the bindings are read at the block's owner.
@testitem "F4-15: the Jiang-like model equals its PDESystem with field_inputs (blocks covered in part)" setup = [FieldsJiangSetup] tags = [:potts, :fields_jiang] begin
    @testset "F4-15: the Jiang-like model equals its PDESystem with field_inputs (blocks covered in part)" begin
        σ, kinds = jiang_state(JG_DIMS)
        names = (:o, :g, :l, :gf, :inh)
        integ = init(PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, 3);
            field_solver = BackwardEuler()), SequentialCPM(); save_start = false)
        step!(integ)
        pde = JgPDE.jiang(JG_DIMS)
        fi = Potts.field_inputs(integ, pde)
        # (the rim: 4×4×4 blocks the cells cover in part)
        blk = [fi[:pq][(4i - 3):(4i), (4j - 3):(4j), (4k - 3):(4k)] for i in 1:8, j in 1:8, k in 1:8]
        @test count(b -> any(b) && !all(b), blk) > 50
        prob = Potts.LatticePDE.discretize(pde, Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(JG_DIMS); T = Float64);
            inputs = collect(fi), u0 = [n => copy(Array(getproperty(current_state(integ).site, n))) for n in names], tspan = (0.0, 1.0)
        )
        s = Potts.LatticePDE.solve(prob, BackwardEuler(); dt = 0.25)
        # F4-15 review should-fix 2 and F4-15b: an oracle independent of the lowering. The inhibitor's
        # rate at u = 0 is its source 3 (Q + 2N), folded over each block's free children (the
        # mask is the medium), so the free volume times the rate, summed over the nodes, is 3 times
        # the exact count of Q + 2N sites off the medium (every such site: 1593, from σ and the
        # kinds; 1592 at 7d101740, where the Majority mask held a block with one Q site). One
        # ExplicitEuler window of h = 1e-6 from 0 gives h times the rate (to O(h Di/H²))
        nq = count(s -> s != 0 && kinds[s] == :Q, σ) + 2 * count(s -> s != 0 && kinds[s] == :N, σ)
        @test nq == 1593
        nfree = [count(!, fi[:med][(4i - 3):(4i), (4j - 3):(4j), (4k - 3):(4k)]) for i in 1:8, j in 1:8, k in 1:8]
        p0 = Potts.LatticePDE.discretize(pde, Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(JG_DIMS); T = Float64);
            inputs = collect(fi), u0 = [n => zeros(JG_DIMS .÷ 4) for n in names], tspan = (0.0, 1e-6))
        # (one window: the bound cannot see the `max(· − ·, 0)` switches, so the count is explicit)
        s0 = Potts.LatticePDE.solve(p0, ExplicitEuler(; substeps = 1); dt = 1.0e-6)
        @test sum(nfree .* s0[:inh, length(s0.t)]) / 1e-6 ≈ 3 * nq rtol = 1e-8
        step!(integ)
        for n in names
            got, want = s[n, length(s.t)], Array(getproperty(current_state(integ).site, n))
            @test maximum(abs, got .- want) <= 1e-14 * max(1.0, maximum(abs, want)) ||
                  (println("F4-15 Jiang $n: ", maximum(abs, got .- want)); false)
        end
    end
end

# Review r1 M3: lactate's source reads O₂ and glucose (switches of other rows' fields) and no
# lactate, so it is known when lactate is solved after them: the default BackwardEuler operator
# is exact, newton = 2 (the switch rows) with no warning, and equals newton = 12 (base cb20be97:
# the term is unseen, newton = 4 and the warning; ~/lpwork/f3b6r-nc-m3.log)
@testitem "F3-18: the Jiang-like default BackwardEuler is exact (newton = 2, no warning)" setup = [FieldsJiangSetup] tags = [:potts, :fields_jiang] begin
    @testset "F3-18: the Jiang-like default BackwardEuler is exact (newton = 2, no warning)" begin
        σ, kinds = jiang_state(JG_DIMS)
        @test_logs min_level = Base.CoreLogging.Warn init(PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, 1);
            field_solver = BackwardEuler()), SequentialCPM(); save_start = false)
        # F3-22 review r1: lactate reads O₂ and glucose one way (they do not read it back), so the
        # default ExplicitEuler count is bounded (D-C7a item 2 amended; base 9afaac05: refused with
        # the route `field_solver = BackwardEuler()`, now checked on a loop in audit.jl)
        m = try
            PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, 1)); ""
        catch err
            sprint(showerror, err)
        end
        @test m == ""
        kmap = Int32[s == 0 ? 0 : findfirst(==(kinds[s]), [:P, :Q, :N]) for s in σ]
        names = (:o, :g, :l, :gf, :inh)
        bp = Potts.LatticePDE.discretize(Potts.fields(JiangLike(; name = :j)),
            Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(JG_DIMS); T = Float64);
            u0 = [n => zeros(JG_DIMS .÷ 4) for n in names], tspan = (0, 2), inputs = [:kind => kmap])
        shifted = [circshift(kmap, (s, 0, 0)) for s in 0:3]
        function run(alg)
            ig = init(bp, alg; dt = 0.25)
            for w in 1:8
                ig[:kind] = shifted[mod1(w, 4)]
                step!(ig)
            end
            return ig
        end
        a = @test_logs min_level = Base.CoreLogging.Warn run(BackwardEuler())
        c = only(a.runtimes).cache
        @test c.newton == 2 && c.exact && !c.cyclic
        @test Potts.LatticeFields.Problems.field_stats(a).newton_budget == 0
        # the two Newton steps are the accepted BE step: the policy accepts a step within
        # NEWTON_EPS relative to the field's scale, so the tight-inner two-step solve and the
        # 12-step reference agree to that accepted defect (the assertion and its derivation are
        # below; the measured residual is ~1e-15 on 1.12.6, 6.4e-8 under 1.13.3)
        tight = Potts.LatticePDE.LatticePCG(; reltol = 1.0e-12, maxiters = 64)
        a2 = @test_logs min_level = Base.CoreLogging.Warn run(BackwardEuler(; linsolve = tight))
        @test only(a2.runtimes).cache.newton == 2
        @test Potts.SciMLBase.check_error(a2) == Potts.SciMLBase.ReturnCode.Success   # healthy, in progress
        @test Potts.LatticeFields.Problems.field_stats(a2).newton_budget == 0
        b = run(BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 12), linsolve = tight))
        # F4-15b (review; user ruling 2026-11-13): the acceptance is
        # `dk <= NEWTON_EPS * ||u_k - u^n|| + 10 eps(T) ||u_k||` (implicit.jl), relative to the step
        # increment; the distance from the two-step iterate to the 12-step reference is the remaining
        # convergence error, not the accepted update. The bound 1e-5 * max(1, |b|) is the user's policy
        # scale for that error: the measured values are 6.4e-8 under 1.13.3 and ~1e-15 on 1.12.6, so
        # the 12-step comparison stays the real check and the scale keeps a red run visible without
        # pinning the toolchain.
        for n in names
            @test maximum(abs, a2[n] .- b[n]) <= 1e-5 * max(1.0, maximum(abs, b[n]))
        end
    end
end

# F4-15b containment (coordinator ruling 2026-11-12, replacing the withdrawn value-level
# containment inside the 86 partial blocks). The fold acts on each node's row and on the node
# values the operator reads, so a fully free node one stencil step from a node the majority rule
# held must move: its Laplacian reads that neighbour's value (v under the majority rule, the free
# part w here). The exact closure is the 86 partial blocks plus the free nodes within one in-box
# stencil step of a majority-held node; nothing in the 35 fully free blocks beyond that closure
# and nothing in the 391 fully masked blocks may differ.
@testitem "F4-15b: the fold differs on partial blocks; one step moves the one-hop closure" setup = [FieldsJiangSetup] tags = [:potts, :fields_jiang] begin
    @testset "F4-15b: the fold differs on partial blocks; one step moves the one-hop closure" begin
        σ, kinds = jiang_state(JG_DIMS)
        names = (:o, :g, :l, :gf, :inh)
        integ = init(PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, 3);
            field_solver = BackwardEuler()), SequentialCPM(); save_start = false)
        step!(integ)
        pde = JgPDE.jiang(JG_DIMS)
        fi = Potts.field_inputs(integ, pde)
        k = 4; nb = size(fi[:med]) .÷ k; nt = k^3
        sl(J) = (k * (J[1] - 1) + 1):(k * J[1]), (k * (J[2] - 1) + 1):(k * J[2]), (k * (J[3] - 1) + 1):(k * J[3])
        nm = [count(fi[:med][sl(J)...]) for J in CartesianIndices(nb)]
        cls(n) = n == 0 ? 1 : n <= nt ÷ 2 ? 2 : n < nt ? 3 : 4
        # the census: 35 fully free, 39 partial free (1..32 medium), 47 partial held (33..63),
        # 391 fully masked (64)
        @test [count(i -> cls(nm[i]) == c, 1:length(nm)) for c in 1:4] == [35, 39, 47, 391]
        partial = [cls(n) in (2, 3) for n in nm]
        held = [cls(n) == 3 for n in nm]
        n8 = JG_DIMS .÷ 4
        # a shared state distinct from the mask values (o0 = 0.08, g0 = 5.5, l = 0, gf = 1, inh = 0),
        # so a held node and a free node differ in both runs too
        u0 = [n => (n === :o ? fill(0.05, n8) : n === :g ? fill(4.0, n8) : n === :gf ? fill(0.5, n8) : fill(1.0, n8)) for n in names]
        disc = Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(JG_DIMS); T = Float64)
        pnew = Potts.LatticePDE.discretize(pde, disc; inputs = collect(fi), u0 = u0, tspan = (0.0, 1e-6))
        # the majority twin: the same model with the mask at the coarse node (no fine read), so every
        # fold is the whole-block mean and a node the majority rule holds (more than half medium) is
        # held at v. This is the D-F4-15 semantics, built from the same fine inputs.
        medm = [nm[I] > nt ÷ 2 for I in CartesianIndices(nb)]
        pmaj = Potts.LatticePDE.discretize(JgPDE.jiang(JG_DIMS; coarsemask = true), disc;
            inputs = vcat([k2 => v2 for (k2, v2) in collect(fi) if k2 != :med], [:medc => medm]),
            u0 = u0, tspan = (0.0, 1e-6))
        inew = init(pnew, ExplicitEuler(; substeps = 1); dt = 1.0e-6); step!(inew)
        imaj = init(pmaj, ExplicitEuler(; substeps = 1); dt = 1.0e-6); step!(imaj)
        # (one explicit step: its value difference is the support of the rate difference; no diffusion
        # solve spreads it, and h = 1e-6 keeps Do, Dg and Dl stable)
        function nbhd(J)
            d = (CartesianIndex(1, 0, 0), CartesianIndex(-1, 0, 0), CartesianIndex(0, 1, 0),
                 CartesianIndex(0, -1, 0), CartesianIndex(0, 0, 1), CartesianIndex(0, 0, -1))
            return [J + x for x in d if all(1 .<= Tuple(J + x) .<= Tuple(nb))]
        end
        closure = [nm[I] == 0 && any(held[K] for K in nbhd(I)) for I in CartesianIndices(nb)]
        @test count(closure) == 12
        want = findall(partial .|| closure)
        for n in names
            a, b = Array(inew[n]), Array(imaj[n])
            d = abs.(b .- a)
            idx = findall(!iszero, d)
            @test idx == want
        end
        # the enumeration (printed, not re-derived: `closure` is by construction the free nodes with a
        # held neighbour, so an assertion that each has one would be tautological)
        @info "F4-15b one-step closure" [Tuple(I) for I in findall(closure)]
    end
end
