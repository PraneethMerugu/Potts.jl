@testitem "fields: two solver groups; a later group reads the earlier field's array" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: two solver groups; a later group reads the earlier field's array" begin
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        cvar = only(filter(x -> string(x) in ("c", "c(t)"), Potts.declared_variables(sys)))
        uvar = only(filter(x -> string(x) in ("u", "u(t)"), Potts.declared_variables(sys)))
        prob = PottsProblem(
            sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 2),
            solvers = [uvar => ExplicitEuler(substeps = 3)]
        )
        @test count(x -> x isa CorePotts.FieldPhase, prob.f.phases.after_mcs) == 2
        sol = solve(prob, SequentialCPM())
        src = op[1].second .== 1
        c, u = zeros(12, 10), zeros(12, 10)
        for _ in 1:2
            c = fd_ftcs(c, 0.2, (1, 1), 1.0, 2; periodic = false, rate = (q, i, j) -> 0.05 * src[i, j])
            cc = c
            u = fd_ftcs(u, 0.1, (1, 1), 1.0, 3; periodic = false, rate = (q, i, j) -> 0.5 * cc[i, j])
        end
        @test maximum(abs.(sol.u[end].site.c .- c)) < 1.0e-15
        @test maximum(abs.(sol.u[end].site.u .- u)) < 1.0e-14
        # one group (both fields with the same solver): Jacobi inside the substep, a different result
        one = solve(PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 3)), SequentialCPM())
        @test count(
            x -> x isa CorePotts.FieldPhase, PottsProblem(
                sys, op, (0, 2);
                field_solver = ExplicitEuler(substeps = 3)
            ).f.phases.after_mcs
        ) == 1
        @test maximum(abs.(one.u[end].site.u .- u)) > 1.0e-6
    end
end

@testitem "fields: the coupling between solver groups is bounded (F2-06 review, K-unsafe)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: the coupling between solver groups is bounded (F2-06 review, K-unsafe)" begin
        sys = FdRot(; name = :r)
        ovar = only(filter(x -> string(x) in ("o", "o(t)"), Potts.declared_variables(sys)))
        two(k; n = 1) = PottsProblem(
            sys, [fd_empty((6, 6)); :k => k], (0, 4); field_solver = ExplicitEuler(substeps = n),
            solvers = [ovar => ExplicitEuler(substeps = 2)]
        )
        # k · window = 3 in two groups: refused, explicit counts or not (base: built and run)
        for n in (1, 40)
            e = try
                two(3.0; n); ""
            catch err
                err isa ArgumentError || rethrow()
                sprint(showerror, err)
            end
            @test !isempty(e)
        end
        # weak coupling (k = 0.5, read through the parameter): the groups step one after the other
        sol = solve(two(0.5), SequentialCPM())
        c, o = 1.0, 0.0
        for _ in 1:4
            c = c - 0.5 * o                                           # the c group: o held over the MCS
            for _ in 1:2
                o = o + 0.5 * c / 2                                   # the o group (2 substeps) reads the new c
            end
        end
        @test all(≈(c; rtol = 1.0e-12), sol.u[end].site.c) && all(≈(o; rtol = 1.0e-12), sol.u[end].site.o)
        @test abs(c - cos(2.0)) < 0.5 && abs(o - sin(2.0)) < 0.5      # the splitting's truncation at k dt = 0.5
        # `FieldGroups` as A's `field_solver` (F3-03): the same two groups as the `solvers` spelling
        fg = FieldGroups(ovar => ExplicitEuler(substeps = 2); default = ExplicitEuler(substeps = 1))
        sg = solve(PottsProblem(sys, [fd_empty((6, 6)); :k => 0.5], (0, 4); field_solver = fg), SequentialCPM())
        @test sg.u[end].site.c == sol.u[end].site.c && sg.u[end].site.o == sol.u[end].site.o
    end
end

@testitem "fields: a one-way chain of solver groups is not limited (F2-06 round 2)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: a one-way chain of solver groups is not limited (F2-06 round 2)" begin
        sys = FdOneWay(; name = :w)
        # the values at 2c91f854, before the coupling check (u at k = 3 and 30)
        base = Dict(3.0 => 0.4039093699527255, 30.0 => 4.039093699527256)
        for k in (3.0, 30.0)                                          # window · k = 3 and 30
            sol = solve(
                PottsProblem(
                    sys, [fd_empty((6, 6)); :k => k], (0, 20); field_solver = ExplicitEuler(substeps = 2),
                    solvers = [fdvar(sys, "u") => ExplicitEuler(substeps = 3)]
                ), SequentialCPM()
            )
            @test Symbol(sol.retcode) === :Success
            c, u = 1.0, 0.0
            for _ in 1:20
                for _ in 1:2
                    c -= 0.5 * 0.1 * c
                end                 # the c group (2 substeps)
                for _ in 1:3
                    u += (k * c - u) / 3
                end               # the u group reads the new c (3 substeps)
            end
            @test all(≈(c; rtol = 1.0e-12), sol.u[end].site.c) && all(≈(u; rtol = 1.0e-12), sol.u[end].site.u)
            @test sol.u[end].site.u[1] ≈ base[k] rtol = 1.0e-12
            @test sol.u[end].site.c[1] ≈ 0.12851215656510334 rtol = 1.0e-12
        end
    end
end

@testitem "fields: loops of solver groups are limited, chains next to them are not (F2-06 round 2)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: loops of solver groups are limited, chains next to them are not (F2-06 round 2)" begin
        s3 = FdLoop3(; name = :l3)
        three(k) = PottsProblem(
            s3, [fd_empty((6, 6)); :k => k], (0, 2); field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(s3, "o") => ExplicitEuler(substeps = 2), fdvar(s3, "v") => ExplicitEuler(substeps = 3)]
        )
        e = fdargerr(() -> three(3.0))
        @test occursin("the fields `c`, `o`, `v` are in solver groups that read one another in a loop", e) &&
            occursin("window · Σ max|coefficient| = 3.0 > 1", e)
        @test Symbol(solve(three(0.5), SequentialCPM()).retcode) === :Success
        sc = FdLoopChain(; name = :lc)
        lc(; k, r) = PottsProblem(
            sc, [fd_empty((6, 6)); :k => k; :r => r], (0, 2); field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(sc, "o") => ExplicitEuler(substeps = 2), fdvar(sc, "u") => ExplicitEuler(substeps = 3)]
        )
        # u's window · k = 30 (u is in no loop), the loop's 0.5: accepted
        @test Symbol(solve(lc(; k = 30.0, r = 0.5), SequentialCPM()).retcode) === :Success
        # the loop past the limit: refused, naming the loop's fields only
        e = fdargerr(() -> lc(; k = 30.0, r = 3.0))
        @test occursin("the fields `c`, `o` are in solver groups", e) && !occursin("`u`", e)
    end
end

@testitem "fields: an unseen term that reads another field counts as reading every group (F2-06 round 3)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: an unseen term that reads another field counts as reading every group (F2-06 round 3)" begin
        sys = FdUnseenChain(; name = :uc)
        three(k) = PottsProblem(
            sys, [fd_empty((6, 6)); :k => k], (0, 2); field_solver = ExplicitEuler(substeps = 2),
            solvers = [fdvar(sys, "u") => ExplicitEuler(substeps = 3), fdvar(sys, "z") => ExplicitEuler(substeps = 1)]
        )
        e = fdargerr(() -> three(3.0))
        @test occursin("the fields `c`, `u` are in solver groups that read one another in a loop", e) &&
            occursin("window · Σ max|coefficient| = 3.0", e) &&
            occursin("the terms of `c` that the stability bound cannot see and that read another field count as reading every other group", e)
        @test Symbol(solve(three(0.5), SequentialCPM()).retcode) === :Success
    end
end

@testitem "fields: an unseen term on its own field couples no group (F2-06 round 3)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: an unseen term on its own field couples no group (F2-06 round 3)" begin
        sys = FdSelfSrc(; name = :ss)
        sol = solve(
            PottsProblem(
                sys, fd_empty((6, 6)), (0, 10); field_solver = ExplicitEuler(substeps = 2),
                solvers = [fdvar(sys, "u") => ExplicitEuler(substeps = 3)]
            ), SequentialCPM()
        )
        @test Symbol(sol.retcode) === :Success
        @test sol.u[end].site.u[1] ≈ 1.5079357331026704 rtol = 1.0e-12          # the value at 2c91f854
    end
end

@testitem "fields: a loop of solver groups counts only the reads inside it (F2-06 round 3)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: a loop of solver groups counts only the reads inside it (F2-06 round 3)" begin
        sys = FdChainLoop(; name = :cl)
        cl(w) = PottsProblem(
            sys, [fd_empty((6, 6)); :w => w], (0, 10); field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(sys, "s2") => ExplicitEuler(substeps = 2), fdvar(sys, "c") => ExplicitEuler(substeps = 3)]
        )
        sol = solve(cl(0.05), SequentialCPM())                        # s1 → weak loop (0.05): accepted
        @test Symbol(sol.retcode) === :Success
        @test sol.u[end].site.s2[1] ≈ 16.438457412956836 rtol = 1.0e-12 # the values at 2c91f854
        @test sol.u[end].site.c[1] ≈ 5.8773343382071435 rtol = 1.0e-12
        e = fdargerr(() -> cl(3.0))                                   # a strong loop: refused, s1 not named
        @test occursin("the fields `s2`, `c` are in solver groups", e) && occursin("window · Σ max|coefficient| = 3.0 >", e) &&
            !occursin("s1", e)
    end
end

@testitem "fields: following the printed window limit is accepted (F2-06 round 2)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "fields: following the printed window limit is accepted (F2-06 round 2)" begin
        sys = FdRot(; name = :r)
        for k in (150.0, 1 / 0.0033335, 300.0, 7.0e3 / 3, 1234.5)
            e = fdargerr(
                () -> PottsProblem(
                    sys, [fd_empty((6, 6)); :k => k], (0, 1); field_solver = ExplicitEuler(substeps = 1),
                    solvers = [fdvar(sys, "o") => ExplicitEuler(substeps = 2)]
                )
            )
            @test occursin("> 1", e)
            # the window limit, verbatim (rounded down)
            lim = parse(Float64, match(r"window ≤ ([0-9.eE+-]+)\)", e).captures[1])
            @test lim * k <= 1
            sm = fd_rot_md(lim)
            prob = PottsProblem(
                sm, [fd_empty((6, 6)); :k => k], (0, 2); field_solver = ExplicitEuler(substeps = 1),
                solvers = [fdvar(sm, "o") => ExplicitEuler(substeps = 2)]
            )
            @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
            # route 1: one solver with an explicit count (the rotation's rows are not dominant)
            @test occursin("one solver with an explicit count", e)
            @test PottsProblem(sys, [fd_empty((6, 6)); :k => k], (0, 1); field_solver = ExplicitEuler(substeps = 4000)) isa
                PottsProblem
        end
    end
end

# R-F2b (2026-10-20): the filled inputs take one canonical order, whatever order the converter
# meets the CPM reads in (the hash order of a term's arguments): `kind__in` first, the CPM
# reads by expression text (`field1__in`, `field2__in`, … in that order), `domain__in` last
@testitem "R-F2b: the filled inputs take a canonical order" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "R-F2b: the filled inputs take a canonical order" begin
        raw = Tuple{Symbol, Any, Type}[
            (:kind__in, :kind, Int32), (:field1__in, :zz, Float64),
            (:field2__in, :aa, Float64), (:domain__in, :dom, Bool),
        ]
        a, b = Potts._canonical_filled(raw), Potts._canonical_filled(reverse(raw))
        @test a == b                                                   # the met order does not matter
        @test first.(a) == [:kind__in, :field1__in, :field2__in, :domain__in] && a[2][2] === :aa && a[3][2] === :zz
    end
end

# F2-07: standalone `FieldGroups` steps FdTwo's field system as the model's two solver groups do
# (c with 2 substeps, then u with 3, reading the new c): σ is frozen (`A[frozen]`), so the
# kind input is the same at every MCS
@testitem "F2-07: B FieldGroups equals a model's two groups (FdTwo, σ frozen)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-07: B FieldGroups equals a model's two groups (FdTwo, σ frozen)" begin
        LP, Sy, SU, MTKB = Potts.LatticePDE, Potts.Symbolics, Potts.SymbolicUtils, Potts.ModelingToolkitBase
        sys = FdTwo(; name = :t)
        op = fd_source_op((12, 10))
        σ0 = copy(last(op[1]))
        prob = PottsProblem(
            sys, op, (0, 3); field_solver = ExplicitEuler(substeps = 2),
            solvers = [:u => ExplicitEuler(substeps = 3)]
        )
        integ = init(prob, SequentialCPM())
        foreach(_ -> step!(integ), 1:3)
        st = current_state(integ)
        @test Array(st.ownership) == σ0 && fd_n(integ, 1) == 2 && fd_n(integ, 2) == 3
        # the model's field system in standalone LatticePDE: zero initial values, the time span of 3 MCS
        pdesys, _ = Potts._field_system(sys; T = Float64)
        ivs = pdesys.ivs
        isin(v) = MTKB.isinput(Sy.unwrap(v))
        states = [v for v in pdesys.dvs if !isin(v)]
        ics = [Sy.wrap(SU.operation(Sy.unwrap(v))(0.0, Sy.unwrap.(ivs[2:end])...)) ~ 0.0 for v in states]
        dom = [
            isequal(Sy.unwrap(d.variables), Sy.unwrap(ivs[1])) ? (ivs[1] ∈ LP.Interval(0.0, 3.0)) : d
                for d in getfield(pdesys, :domain)
        ]
        bsys = MTKB.PDESystem(pdesys.eqs, [pdesys.bcs; ics], dom, ivs, pdesys.dvs, pdesys.ps; name = :b)
        kin = only(v for v in pdesys.dvs if isin(v))
        bp = LP.discretize(
            bsys, LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64);
            inputs = [kin => Int32.(σ0 .!= 0)]
        )
        groups = LP.FieldGroups(:c => ExplicitEuler(; substeps = 2), :u => ExplicitEuler(; substeps = 3))
        bi = init(bp, groups; dt = 1.0)
        @test [r.n for r in bi.runtimes] == [2, 3]
        s = solve!(bi)
        @test isapprox(s[:c, end], Array(st.site.c); rtol = 1.0e-12) && isapprox(s[:u, end], Array(st.site.u); rtol = 1.0e-12)
        @test maximum(Array(st.site.u)) > 0                                     # u has grown from c
        # control: one group steps c and u together (u reads the old c)
        one = solve(bp, ExplicitEuler(; substeps = 3); dt = 1.0)
        @test !(one[:u, end] ≈ Array(st.site.u))
    end
end

@testitem "F2-08a: a refused parameter write changes nothing (S1)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08a: a refused parameter write changes nothing (S1)" begin
        sys = FdRotCells(; name = :r)
        σ = zeros(Int32, 6, 6); σ[2:3, 2:3] .= 1
        pw = PottsProblem(
            sys, [ownership => σ, kind => [:A]], (0, 40); seed = 3, field_solver = ExplicitEuler(substeps = 1),
            solvers = [fdvar(sys, "o") => ExplicitEuler(substeps = 2)]
        )
        ig = init(pw, SequentialCPM())
        step!(ig)
        snap(i) = (i.t, copy(Array(current_state(i).ownership)), copy(Array(current_state(i).site.c)), copy(Array(current_state(i).site.o)))
        s1, p1 = snap(ig), ig.p
        for (what, write) in (
                ("setp", () -> setp(ig, :k)(ig, 3.0)), ("integ.ps", () -> (ig.ps[:k] = 3.0)),
                ("setp of two", () -> setp(ig, [:k, :Dc])(ig, [3.0, 0.1])),
            )
            e = fdargerr(write)
            @test !isempty(e)
            @test ig.p === p1 && getp(ig, :k)(ig) == 0.5 && snap(ig) == s1        # nothing changed
        end
        @test !isempty(fdargerr(() -> setp(ig, :Dc)(ig, -1.0)))                   # the other refusal, the same way
        @test getp(ig, :Dc)(ig) == 0.1 && snap(ig) == s1
        # a kind table past the limit (kind A's entry 5: the coupling 5.5), by setp and by `ps`
        for write in (() -> setp(ig, :κ)(ig, [0.0, 5.0]), () -> (ig.ps[:κ] = [0.0, 5.0]))
            @test !isempty(fdargerr(write))
            @test ig.p === p1 && getp(ig, :κ)(ig) == [0.0, 0.0] && snap(ig) == s1
        end
        @test !isempty(fdargerr(() -> remake(pw; p = [:k => 3.0])))
        # the run goes on, and a write the check accepts takes effect (control)
        step!(ig)
        @test ig.t == s1[1] + 1 && Array(current_state(ig).site.c) != s1[3]
        setp(ig, :k)(ig, 0.4)
        step!(ig)
        @test getp(ig, :k)(ig) == 0.4 && ig.t == s1[1] + 2
    end
end

# F2-13 (F2 design §2.13): `integ.ps[x] = v` writes a scalar or a kind table of a Potts
# integrator, with the checks of `setp`; `integ[p]` and `integ[p] = v` of a parameter are
# errors with the `integ.ps` route (base: SciMLBase's "Indexing with parameters is deprecated"
# ErrorException); states index as before
@testitem "F2-13: integ.ps in a model; integ[p] gives the route" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-13: integ.ps in a model; integ[p] gives the route" begin
        sys = FdRotCells(; name = :r)
        σ = zeros(Int32, 6, 6); σ[2:3, 2:3] .= 1
        ig = init(
            PottsProblem(sys, [ownership => σ, kind => [:A]], (0, 4); seed = 3, field_solver = ExplicitEuler(substeps = 2)),
            SequentialCPM()
        )
        ig.ps[:κ] = [0.0, 0.25]
        ig.ps[:k] = 0.4
        @test ig.ps[:κ] == [0.0, 0.25] && getp(ig, :κ)(ig) == [0.0, 0.25] && ig.ps[:k] == 0.4
        # the run reads the new values: equal to a problem built with them
        ref = init(
            PottsProblem(
                sys, [ownership => σ, kind => [:A], :κ => [0.0, 0.25], :k => 0.4], (0, 4); seed = 3,
                field_solver = ExplicitEuler(substeps = 2)
            ), SequentialCPM()
        )
        step!(ig); step!(ref)
        @test Array(current_state(ig).site.o) == Array(current_state(ref).site.o)
        for (f, want) in (
                (() -> ig[:κ], "`κ`"),
                (() -> (ig[:κ] = [0.0, 1.0]), "`κ`"),
                (() -> ig[:k], "`k`"), (() -> (ig[:k] = 1.0), "`k`"),
                (() -> ig[[:c, :k]], "`k`"),
            )
            err = fdargerr(f)
            @test occursin(want, err)
        end
        @test ig.ps[:κ] == [0.0, 0.25] && ig.ps[:k] == 0.4              # nothing was set
        # a field reads and writes as before
        ig[:c] = fill(2.0, 6, 6)
        @test all(==(2.0), Array(ig[:c]))
    end
end

# F2-08a: the substep count of each field group of a Potts problem or integrator, in group
# order (as LatticePDE's `substep_counts`; base: only the internal `CorePotts._runtime(…).n`)
@testitem "F2-08a: substep_counts per field group in a model" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08a: substep_counts per field group in a model" begin
        sys = FdTwo(; name = :t)
        prob = PottsProblem(
            sys, fd_source_op((12, 10)), (0, 3); field_solver = ExplicitEuler(substeps = 2),
            solvers = [:u => ExplicitEuler(substeps = 3)]
        )
        integ = init(prob, SequentialCPM())
        @test substep_counts(integ) == [fd_n(integ, 1), fd_n(integ, 2)] == [2, 3]
        @test substep_counts(prob) == [2, 3]
        @test Potts.substep_counts === Potts.LatticePDE.substep_counts                # one shared function
        # it follows a parameter write: diffusion 4× raises the automatic part of the count
        p1 = PottsProblem(FdClosed(; name = :c), fd_empty((12, 10)), (0, 2); field_solver = ExplicitEuler())
        i1 = init(p1, SequentialCPM())
        n1 = only(substep_counts(i1))
        setp(i1, :Dc)(i1, 4.0)
        # right after the write, before any step: the count of a fresh integrator at the new value
        # (review M2 of batch 3; base: the last step's count until the next step)
        fresh = substep_counts(init(remake(p1; p = [:Dc => 4.0]), SequentialCPM()))
        @test substep_counts(i1) == fresh && only(fresh) > n1
        step!(i1)
        @test only(substep_counts(i1)) == fd_n(i1) > n1
    end
end

# F2-08a: the field groups of a model are lowered by `LatticePDE.lower_group`, and
# `mtkcompile`'s lowering of the group of all fields is reused by a one-group `PottsProblem`
# (one `lower_group` call for the model); another state type or a split lowers again
@testitem "F2-08a: mtkcompile's GroupSpec is reused (one lower_group call)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08a: mtkcompile's GroupSpec is reused (one lower_group call)" begin
        calls() = Potts._LOWER_GROUP_CALLS[]
        n0 = calls()
        c = mtkcompile(FdClosed(; name = :c))
        @test calls() == n0 + 1
        prob = PottsProblem(c, fd_empty((12, 10)), (0, 2); field_solver = ExplicitEuler())
        @test calls() == n0 + 1                                       # reused
        @test only(substep_counts(init(prob, SequentialCPM()))) >= 1
        PottsProblem(c, fd_empty((12, 10)), (0, 2); field_solver = ExplicitEuler(substeps = 4))
        @test calls() == n0 + 1                                       # another algorithm: the same group
        PottsProblem(c, fd_empty((12, 10)), (0, 2); T = Float32, field_solver = ExplicitEuler())
        @test calls() == n0 + 2                                       # control: Float32 lowers once more
        sys2 = FdTwo(; name = :t)
        c2 = mtkcompile(sys2)
        m0 = calls()
        PottsProblem(
            c2, fd_source_op((12, 10)), (0, 2); field_solver = ExplicitEuler(substeps = 2),
            solvers = [:u => ExplicitEuler(substeps = 3)]
        )
        @test calls() == m0 + 2                                       # a split: one per group (the whole group is cached)
    end
end

@testitem "F2-08b: a moving mask is clamped at the step start (in a model)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08b: a moving mask is clamped at the step start (in a model)" begin
        σ = zeros(Int32, 12, 12); σ[5:7, 5:7] .= 1
        prob = PottsProblem(
            FdMovingMask(; name = :m), [ownership => σ, kind => [:A]], (0, 40); seed = 5,
            field_solver = ExplicitEuler(substeps = 1)
        )
        integ = init(prob, SequentialCPM())
        c0, m, moved = nothing, nothing, false
        for _ in 1:30                                   # until the cell reaches a site that does not hold `v`
            c0 = copy(Array(current_state(integ).site.c))
            step!(integ)
            m = Array(current_state(integ).ownership) .!= 0
            moved = any(m .& (c0 .!= 1.0))
            moved && break
        end
        @test moved
        c1 = Array(current_state(integ).site.c)
        clamped = copy(c0); clamped[m] .= 1.0
        hand = fd_ftcs(clamped, 0.2, (1, 1), 1.0, 1; periodic = false); hand[m] .= 1.0
        @test maximum(abs.(c1 .- hand)) < 1.0e-14
        late = fd_ftcs(c0, 0.2, (1, 1), 1.0, 1; periodic = false); late[m] .= 1.0     # control: not clamped first
        @test maximum(abs.(c1 .- late)) > 1.0e-3
    end
end

@testitem "F2-08c: REAL forms of mcs over several MCS (in a model)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: REAL forms of mcs over several MCS (in a model)" begin
        # `η mcs` is hoisted into a derived parameter: derived again at each launch with the MCS number
        integ = init(
            PottsProblem(FdMcsSource(; name = :s), fd_empty((6, 6)), (0, 4); field_solver = ExplicitEuler(substeps = 4)),
            SequentialCPM()
        )
        hand = 1.0
        for k in 0:3
            step!(integ)
            for _ in 1:4
                hand += 0.25 * (-hand + 0.5 * k)
            end
            @test all(v -> isapprox(v, hand; rtol = 1.0e-13), Array(current_state(integ).site.c))
        end
        # `(1 + ε mcs)` multiplies the diffusion (a term the bound cannot see: an explicit count);
        # a slow Fourier mode, so each MCS's factor shows
        c0 = [1.0 + cos(π * (i - 1) / 3) for i in 1:6, j in 1:6]
        prob = PottsProblem(FdMcsDiff(; name = :d), [fd_empty((6, 6)); :c => c0], (0, 3); field_solver = ExplicitEuler(substeps = 16))
        integ = init(prob, SequentialCPM())
        want = copy(c0)
        for k in 0:2
            step!(integ)
            want = fd_ftcs(want, 1 + 0.5 * k, (1, 1), 1.0, 16; periodic = true)
            @test isapprox(Array(current_state(integ).site.c), want; rtol = 1.0e-12)
        end
    end
end

@testitem "F2-08c: repeat(4, fields): one step index per MCS, windows mcs_duration/4 apart (in a model)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: repeat(4, fields): one step index per MCS, windows mcs_duration/4 apart (in a model)" begin
        sol = solve(
            PottsProblem(FdClockRepeat(; name = :r), fd_empty((4, 4)), (0, 3); field_solver = ExplicitEuler(substeps = 1)),
            SequentialCPM()
        )
        u = sol.u[end]
        @test all(≈(0 + 1 + 2), u.site.c)                                  # four passes of 1/4 at k = 0, 1, 2
        @test all(≈(0.25 * sum(0.25 * i for i in 0:11)), u.site.u)          # windows at t0 = 0, 0.25, …, 2.75
    end
end

@testitem "F2-08c: time in a field reads t0 + j h per substep (in a model)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: time in a field reads t0 + j h per substep (in a model)" begin
        integ = init(
            PottsProblem(FdTimeRead(; name = :t), fd_empty((4, 4)), (0, 3); field_solver = ExplicitEuler(substeps = 4)),
            SequentialCPM()
        )
        hand = 0.3
        for m in 0:2
            step!(integ)
            for j in 0:3
                hand += 0.25 * (-hand + sin(m + 0.25 * j))
            end
            @test all(v -> isapprox(v, hand; atol = 1.0e-13), Array(current_state(integ).site.c))
        end
    end
end

@testitem "F2-08c: repeat(4, fields) with mcs_duration = 0.5 from MCS 2 (in a model)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: repeat(4, fields) with mcs_duration = 0.5 from MCS 2 (in a model)" begin
        u = solve(
            PottsProblem(FdClockHalf(; name = :h), fd_empty((4, 4)), (2, 5); field_solver = ExplicitEuler(substeps = 1)),
            SequentialCPM()
        ).u[end]
        c, uu, w = 0.0, 0.0, 1.0
        for m in 2:4, r in 0:3
            c += 0.125 * m
            uu += 0.125 * (m + r / 4) * 0.5
            w += 0.125 * (-w + 0.5 * m)
        end
        @test all(≈(c; rtol = 1.0e-13), u.site.c) && all(≈(uu; rtol = 1.0e-13), u.site.u) && all(≈(w; rtol = 1.0e-13), u.site.w)
    end
end

# F3-02 (F2 design §2.2): the group's inputs are specs. A model's CPM inputs are filled (the
# model writes them on the device every MCS), another group's field read from its array is not.
@testitem "F3-02: InputSpec.filled: a model's CPM inputs are filled, another group's field is not" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F3-02: InputSpec.filled: a model's CPM inputs are filled, another group's field is not" begin
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        uvar = only(filter(x -> string(x) in ("u", "u(t)"), Potts.declared_variables(sys)))
        prob = PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 2), solvers = [uvar => ExplicitEuler(substeps = 3)])
        phs = [ph for ph in prob.f.phases.after_mcs if ph isa CorePotts.FieldPhase]
        cin, uin = (ph.group.spec.inputs for ph in phs)
        @test all(i -> i isa Potts.LatticeFields.Problems.InputSpec, [cin; uin])
        @test !isempty(cin) && all(i -> i.filled, cin) && any(i -> occursin("kind", i.key), cin)   # `kind == A`
        @test [(i.key, i.filled) for i in uin] == [("c", false)]                                     # c's array
    end
end

# F3-03 (F3 design §3.7): `FieldGroups` is a model's `field_solver` too (its pairs as `solvers`
# entries of fields, its `default` the other fields' solver), so it resolves and fingerprints
# as the `solvers` spelling; both coupled and standalone routes print an algorithm by LatticeFields' one canonical
# text (`Problems.canonical`). Base (eb2efb60): `field_solver = FieldGroups(…)` was an
# ArgumentError ("`FieldGroups` in a `PottsProblem` is planned").
@testitem "F3-03: FieldGroups in a model; one canonical text" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F3-03: FieldGroups in a model; one canonical text" begin
        LFP, LP = Potts.LatticeFields.Problems, Potts.LatticePDE
        msg(f) = try
            f(); ""
        catch e
            e isa ArgumentError || rethrow()
            sprint(showerror, e)
        end
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        cvar = only(filter(x -> string(x) in ("c", "c(t)"), Potts.declared_variables(sys)))
        uvar = only(filter(x -> string(x) in ("u", "u(t)"), Potts.declared_variables(sys)))
        fg = PottsProblem(sys, op, (0, 2); field_solver = FieldGroups(uvar => ExplicitEuler(substeps = 3); default = ExplicitEuler(substeps = 2)))
        sp = PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 2), solvers = [uvar => ExplicitEuler(substeps = 3)])
        @test fg.f.fingerprint == sp.f.fingerprint
        s1, s2 = solve(fg, SequentialCPM()), solve(sp, SequentialCPM())
        @test s1.u[end].site.c == s2.u[end].site.c && s1.u[end].site.u == s2.u[end].site.u
        # no `default`: the others take the default solver; a name key works as in `solvers`
        nd = PottsProblem(sys, op, (0, 2); field_solver = FieldGroups(:u => ExplicitEuler(substeps = 3)))
        @test nd.f.fingerprint == PottsProblem(sys, op, (0, 2); solvers = [uvar => ExplicitEuler(substeps = 3)]).f.fingerprint
        # control: another count is another fingerprint
        @test PottsProblem(
            sys, op, (0, 2); field_solver = FieldGroups(
                uvar => ExplicitEuler(substeps = 4);
                default = ExplicitEuler(substeps = 2)
            )
        ).f.fingerprint != sp.f.fingerprint
        # refusals in the user's words: a field given twice, a key that is not a field
        e = msg(
            () -> PottsProblem(
                sys, op, (0, 2); field_solver = FieldGroups(uvar => ExplicitEuler(substeps = 3)),
                solvers = [uvar => ExplicitEuler(substeps = 2)]
            )
        )
        @test occursin("`u` is given twice (once in `field_solver = FieldGroups(…)`)", e)
        # at `remake` the problem's `solvers` are kept, and the clash says so with the route (review r1
        # nit); the route works
        e = msg(() -> remake(sp; field_solver = FieldGroups(:u => ExplicitEuler(substeps = 3))))
        @test occursin("`u` is given twice (once in `field_solver = FieldGroups(…)`; `solvers` is kept from the problem: pass `solvers = []`)", e)
        @test remake(
            sp; field_solver = FieldGroups(:u => ExplicitEuler(substeps = 3); default = ExplicitEuler(substeps = 2)),
            solvers = []
        ).f.fingerprint == sp.f.fingerprint
        @test occursin(
            "`FieldGroups`: `zz` is not a field", msg(
                () -> PottsProblem(
                    sys, op, (0, 2);
                    field_solver = FieldGroups(:zz => ExplicitEuler())
                )
            )
        )
        @test occursin(
            "give it as `field_solver = FieldGroups(", msg(
                () -> PottsProblem(
                    sys, op, (0, 2);
                    solvers = [cvar => FieldGroups(uvar => ExplicitEuler())]
                )
            )
        )
        # one canonical text across both routes (byte for byte)
        @test LFP.canonical(ExplicitEuler(substeps = 15, lower_bound = 0.0)) ==
            Potts._canonical(ExplicitEuler(substeps = 15, lower_bound = 0.0))
        # the same objects: every algorithm LatticePDE exports is Potts' own
        algs = [n for n in names(LP) if (v = getfield(LP, n); v isa Type && v <: LFP.AbstractFieldAlgorithm)]
        @test Set(algs) ⊇ Set([:ExplicitEuler, :ExplicitMap, :FieldGroups])
        @test all(n -> isdefined(Potts, n) && Base.isexported(Potts, n) && getfield(Potts, n) === getfield(LP, n), algs)
    end
end

# the solvers' inner algorithms are the same objects across both routes
# (`LatticeFields.Solvers`, made public): `LatticePCG` and `LatticeMultigrid` exported, `VCycle` public.
# Base (1079c4ff): neither Potts nor LatticePDE binds them (`UndefVarError: DevicePCG`).
@testitem "the inner solvers in a model and in B" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "the inner solvers in a model and in B" begin
        S, LP = Potts.LatticeFields.Solvers, Potts.LatticePDE
        for n in (:LatticePCG, :LatticeMultigrid)
            @test getfield(Potts, n) === getfield(LP, n) === getfield(S, n)
            @test Base.isexported(Potts, n) && Base.isexported(LP, n) && Base.ispublic(S, n)
        end
        @test Potts.VCycle === LP.VCycle === S.VCycle && Base.ispublic(Potts, :VCycle) && Base.ispublic(LP, :VCycle) && !Base.isexported(Potts, :VCycle)
        for n in (:CellOperator, :FieldSolver, :steady!, :solve!, :rebuild!, :lift!, :tangent!, :set_coefficients!)
            @test Base.ispublic(S, n)
        end
    end
end

# a linear solver given as A's `field_solver`, in `solvers` or in
# `FieldGroups` is refused in A's words (a linear solver, the `linsolve` of an implicit field
# solver) with a route that works when followed. Base (9db10886, ~/lpwork/f3b2r1-nc-a.log, 4 of 7 fail;
# the 3 that pass are the followed routes):
# "`field_solver` takes a field solver (…); got DevicePCG(Multigrid(LatticeFields.Solvers.V(2,
# 2), nothing, 1.0e-6, nothing, 1.0e-6), 8, 1.0e-6)", the same positional text for `solvers`,
# "is not a field algorithm" for `FieldGroups`, and a MethodError for `ExplicitEuler(; inner)`.
@testitem "a linear solver where a model takes a field solver" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "a linear solver where a model takes a field solver" begin
        op = [fd_empty((16, 8)); :c => zeros(16, 8)]
        mk(; kw...) = PottsProblem(FdPeriodic(; name = :f), op, (0, 1); kw...)
        e(f) = try
            f(); ""
        catch err
            err isa ArgumentError ? err.msg : sprint(showerror, err)
        end
        @test_throws ArgumentError mk(; field_solver = LatticePCG())
        @test solve(mk(; field_solver = ExplicitEuler()), SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
        @test_throws ArgumentError mk(; solvers = [:c => LatticeMultigrid()])
        @test solve(mk(; solvers = [:c => ExplicitEuler()]), SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
        @test_throws ArgumentError mk(; field_solver = FieldGroups(:c => LatticePCG()))
        @test solve(mk(; field_solver = FieldGroups(:c => ExplicitEuler())), SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
        @test_throws ArgumentError ExplicitEuler(; linsolve = LatticePCG())
    end
end

@testitem "F3-04: a model reads the status word (host: after every window)" setup = [FieldsSetup, FieldsGroupsSetup] tags = [:potts, :fields] begin
    @testset "F3-04: a model reads the status word (host: after every window)" begin
        RC = Potts.SciMLBase.ReturnCode
        op = fd_source_op((12, 10))
        sys = FdTwo(; name = :t)
        prob(alg) = PottsProblem(sys, op, (0, 6); field_solver = alg)
        integ = init(prob(AStub(; code = 2, at = 3)), SequentialCPM())
        s = @test_logs (:warn, r"fields `c`, `u`: the solve failed in the field step of MCS 3 \(t = 2\.0\) \(the Newton iteration diverged\).*ConvergenceFailure") solve!(integ)
        @test s.retcode == RC.ConvergenceFailure && integ.t == 3 && integ.stats.fields.solves == 3
        @test s.t[end] == 3                                   # the state it stopped at is saved
        # `reinit!` starts a clean run (review r1 M2): the word, the totals, the code and the counters
        # are cleared; the stub fails at its 3rd step only, so the new run succeeds. Control: without
        # the clearing the word's failure is read again at the first window and the run stops at MCS 1
        reinit!(integ)
        @test integ.stats.fields.code == RC.Success && integ.stats.fields.solves == 0
        s = @test_logs solve!(integ)
        @test s.retcode == RC.Success && integ.t == 6 && integ.stats.fields.solves == 6
        @test startswith(repr(integ.stats.fields), "FieldStats(solves = 6, budget = 0, floor = 0, newton_budget = 0, code = ")
        # a rounding floor survives to the end
        s = solve(prob(AStub(; code = 1, at = 3)), SequentialCPM())
        @test s.retcode == RC.StalledSuccess && s.t[end] == 6
        # a budget count warns once with the route and stays `Success`; the route removes it
        integ = init(prob(AStub(; need = 10, budget = 8)), SequentialCPM())
        s = @test_logs (:warn, r"fields `c`, `u`: the linear solve reached its budget 1 time so far.*maxiters = n") solve!(integ)
        @test s.retcode == RC.Success && integ.stats.fields.budget == 6
        integ = init(prob(AStub(; need = 10, budget = 16)), SequentialCPM())
        s = @test_logs solve!(integ)
        @test s.retcode == RC.Success && integ.stats.fields.budget == 0 && integ.stats.fields.solves == 6
        # explicit groups read nothing: no counters; a warm MCS allocates nothing (above)
        integ = init(prob(ExplicitEuler(substeps = 2)), SequentialCPM(); save_start = false, save_end = false, save_everystep = false)
        step!(integ)
        @test (@allocated step!(integ)) == 0 && integ.stats.fields.solves == 0
    end
end
