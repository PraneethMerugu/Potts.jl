# The top-level definitions of fields_couple.jl, fields_couple_e.jl, fields_short.jl, fields_couple_e8.jl, fields_couple_e11.jl, fields_couple_w2.jl, fields_couple_b6.jl (converted from the include-into-Main suite, TS1a).

@testsetup module CoupleSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

# ---- from fields_couple.jl --------------------------------------------------------------------------
using Potts, Test

using ForwardDiff: ForwardDiff

using OrdinaryDiffEqTsit5: Tsit5


module CpPDE
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
const t = Potts.t
const Dt = Differential(t)
const Δ = Potts.LatticePDE.Δ
@parameters x y Dc = 0.2 s = 0.5 kd = 0.1 av = 0.01
@variables c(..) u(..) endo(..)::Bool [input = true] vol(..) [input = true] med(..)::Bool [input = true]
const DOM = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 24.0), y ∈ Interval(0.0, 20.0)]
# `D(c) ~ Dc Δc + s·endo − kd·c + av·vol`: endo is 0/1 and vol a number, both plain inputs
sys(; name = :fields, dom = DOM) = PDESystem(
    [Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y) + av * vol(t, x, y)],
    [c(0, x, y) ~ 0.0], dom, [t, x, y], [c(t, x, y), endo(t, x, y), vol(t, x, y)], [Dc, s, kd, av]; name)
# two fields: `u` reads `c`
sys3(; name = :fields) = PDESystem([Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y),
        Dt(u(t, x, y)) ~ 0.3 * Δ(u(t, x, y)) + 0.2 * c(t, x, y) - 0.2 * u(t, x, y)],
    [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], DOM, [t, x, y], [c(t, x, y), u(t, x, y), endo(t, x, y)], [Dc, s, kd]; name)
# the same without `vol` (for the derivative and ODE-path checks)
sys2(; name = :fields) = PDESystem([Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y)],
    [c(0, x, y) ~ 0.0], DOM, [t, x, y], [c(t, x, y), endo(t, x, y)], [Dc, s, kd]; name)
end


@potts_model CpHost begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 4.0)
end

# `@fields` in the model body: the bindings read the model's own words (`kind == A`, `volume[owner]`)
@potts_model CpFields begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys() (CpPDE.endo => kind == A, CpPDE.vol => volume[owner])
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CpFields2 begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys2() (CpPDE.endo => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

# a model that extends the coupled one reads its field `c` by name in a drive
@potts_model CpDrive begin
    @extend c, A = base = CpFields2()
    @parameters χ = 400.0
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
end

# the field named in `@fields` and read by a drive in the same body (user ruling 2026-11-10)
@potts_model CpSame begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

# a list of names; and one name, the other field reached by name
@potts_model CpList begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, u = CpPDE.sys3() (CpPDE.endo => kind == A)
    @drive Chemotaxis(u; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CpOne begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CpPDE.sys3() (CpPDE.endo => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

# a wrong binding (the medium, not `A`): the in-file control of the oracles
@potts_model CpWrong begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys() (CpPDE.endo => kind == medium, CpPDE.vol => volume[owner])
    @sweep Metropolis(; temperature = 4.0)
end

# frozen cells (σ fixed: the ODE-path oracle)
@potts_model CpFrozen begin
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys2() (CpPDE.endo => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end


cp_op() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])

cp_run(m, fs, k = 12; op = cp_op(), kw...) =
    solve(PottsProblem(m, op, (0, k); field_solver = fs, seed = 3, kw...), SequentialCPM(); saveat = 0:3:k)

cp_msg(f) = try
    f()
    "built"
catch e
    e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
end

const CP_W = [0.01 * (i + 2j) for i in 1:24, j in 1:20]

cp_q(sol) = sum(CP_W .* sol.u[end].site.c)

# the ODE-path tolerance: the owned explicit run's time error at 400 substeps (first order in
# the substep). Measured 4.05e-5 on the CPU (2026-11-10); the bound leaves 1.5x room
const CP_ODE_TOL = 6e-5

# The owned oracle: step the coupled run one MCS at a time; over each window, run LatticePDE's
# own discretization of `sys` from the coupled field before the window, with the inputs `ins(σ,
# kind)` computed by hand from the state after the sweep (the fields step after the sweep), and
# return the largest difference to the coupled field after the window and the number of windows
# compared. `skip(σ0, σ)` leaves a window out (a division in it: the fields read σ before it).
# `fields`: the fields of `sys`, in its order (the owned state is their values one after the other).
const LP = Potts.LatticePDE

cp_hand(σ, kind) = [:endo => [s != 0 && kind[s] == 1 for s in σ],
                    :vol => [s == 0 ? 0.0 : Float64(count(==(s), σ)) for s in σ]]

cp_hand2(σ, kind) = cp_hand(σ, kind)[1:1]

function cp_replay(m, sys, ins, alg; op = cp_op(), k = 12, seed = 3, fs = ExplicitEuler(), fields = (:c,),
                   skip = (σ0, σ) -> false, p = nothing)
    integ = init(PottsProblem(m, op, (0, k); field_solver = fs, seed), SequentialCPM())
    σ = Array(integ.u.σ)
    prob = LP.discretize(sys, LP.LatticeDiscretization(LP.Grid(size(σ)); T = Float64); inputs = ins(σ, Array(integ.u.cell.kind)))
    p === nothing || (prob = LP.remake(prob; p))
    state() = reduce(vcat, (vec(Array(getproperty(integ.u.site, f))) for f in fields))
    err, n = 0.0, 0
    for _ in 1:k
        σ0, u0 = Array(integ.u.σ), state()
        step!(integ)
        σ = Array(integ.u.σ)
        skip(σ0, σ) && continue
        o = LP.solve(LP.remake(prob; u0, tspan = (0.0, 1.0), inputs = ins(σ, Array(integ.u.cell.kind))), alg).u[end]
        err, n = max(err, maximum(abs, o .- state())), n + 1
    end
    return err, n
end

# the owned algorithm of a field solver of the coupled run: the same settings, `dt = 1` (one MCS)
cp_own(fs) = typeof(fs)((n === :dt ? 1.0 : getfield(fs, n) for n in fieldnames(typeof(fs)))...)

# the coupled implicit solve and the owned one agree to the inner solver's tolerance, not bitwise
cp_tol(::ExplicitEuler) = 0.0

cp_tol(::BackwardEuler) = 1e-9


cp_same(r, a) = all(r.u[i].σ == a.u[i].σ for i in eachindex(r.u)) &&
                all(r.u[i].site == a.u[i].site for i in eachindex(r.u))

cp_build_err(ex) = try
    Core.eval(@__MODULE__, ex)
    "built"
catch err
    sprint(showerror, err)
end


# ---------------------------------------------------------------------------------------------
# F4-B2 review (2026-11-10, probes ~/lpwork/f4w1-rev/b1.jl, b2.jl, u1.jl): richer models
# against the owned oracle (`cp_replay`; until F4-B6, bitwise against `@equations`), and the
# regressions M1 (an unbound `Bool` input filled by a non-Bool word), M2 (a parameter declared
# again after `@fields`) and M3 (`kind == :A` in `Potts.couple`, always false: refused with the
# route). Each M testset fails at 5d86cc6e (~/lpwork/f4B2/nc-rev.log).
module CpRev
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
const t = Potts.t
const Dt = Differential(t)
const Δ = Potts.LatticePDE.Δ
const masked = Potts.LatticePDE.masked
@parameters x y Dc = 0.2 s = 0.5 kd = 0.1 kq = 1.0
@variables c(..) q(..) w(..) cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)]
@variables endo(..)::Bool [input = true] isB(..)::Bool [input = true] vol(..) [input = true] cin(..) [input = true]
@variables cnm(..) [input = true, lattice_input_name = "c"]
@variables kb(..)::Bool [input = true, lattice_input_name = "kind"] kr(..) [input = true, lattice_input_name = "kind"]
const DOM = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 24.0), y ∈ Interval(0.0, 20.0)]
C, Q, W = c(t, x, y), q(t, x, y), w(t, x, y)
# a Dirichlet face, a Neumann face, a mask on the B cells and a steady companion `q`
rich() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C + 0.01 * vol(t, x, y), 0 ~ 0.5 * Δ(Q) - kq * Q + C],
    [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 0.5, Differential(x)(c(t, 24, y)) ~ 0.0, C ~ masked(isB(t, x, y) == 1, 1.0)],
    DOM, [t, x, y], [C, Q, endo(t, x, y), isB(t, x, y), vol(t, x, y)], [Dc, s, kd, kq]; name = :rich)
first_sys() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, endo(t, x, y)], [Dc, s, kd]; name = :one)
second_unbound() = PDESystem([Dt(W) ~ 0.3 * Δ(W) - W + 0.7 * cnm(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
    [W, cnm(t, x, y)], Any[]; name = :two)
second_bound() = PDESystem([Dt(W) ~ 0.3 * Δ(W) - W + 0.7 * cin(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
    [W, cin(t, x, y)], Any[]; name = :twob)
coarse_sys() = PDESystem([Dt(cc(t, x, y)) ~ Dc * Δ(cc(t, x, y)) + s * endo(t, x, y) - kd * cc(t, x, y)], [cc(0, x, y) ~ 0.0],
    DOM, [t, x, y], [cc(t, x, y), endo(t, x, y)], [Dc, s, kd]; name = :crs)
# an unbound input filled by the word `kind`: a `Bool` one (refused) and a number
kind_bool() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * kb(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, kb(t, x, y)], [Dc, s, kd]; name = :kbs)
kind_real() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * kr(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, kr(t, x, y)], [Dc, s, kd]; name = :krs)
end


@potts_model CrLife begin
    @kinds medium A B
    @variables V_target(cell) = 40.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy begin
        cells => 4.0 * (volume - V_target)^2
        contacts => 2.0 * (kind != kind′)
    end
    @fields CpRev.rich() (CpRev.endo => kind == A, CpRev.isB => kind == B, CpRev.vol => volume[owner])
    @divide cells(A) when = volume >= 30
    @after_mcs V_target ~ ifelse((mcs >= 2) && (id == 2), 0.0, 40.0)
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model CrTwoU begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields CpRev.first_sys() (CpRev.endo => kind == A)
    @fields CpRev.second_unbound()
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CrTwoB begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields c = CpRev.first_sys() (CpRev.endo => kind == A)
    @fields CpRev.second_bound() (CpRev.cin => c)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CrCrs begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields CpRev.coarse_sys() (CpRev.endo => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CrKindReal begin
    @kinds medium A B
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields CpRev.kind_real()
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CrHost2 begin
    @kinds medium A B
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 4.0)
end


cr_rich_op() = (σ = zeros(Int32, 24, 20); σ[3:7, 3:7] .= 1; σ[12:16, 4:8] .= 2; σ[6:10, 12:16] .= 3; σ[16:20, 13:17] .= 4;
                [ownership => σ, kind => [:A, :B, :A, :A]])

cr_kop() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :B]])

cr_run(m, fs, k = 10; op = cp_op(), seed = 5) =
    solve(PottsProblem(m, op, (0, k); field_solver = fs, seed), SequentialCPM(); saveat = 0:2:k)

# the inputs of `rich` by hand; a window with a division in it is left out (the cell count changes)
cr_hand(σ, kind) = [:endo => [s != 0 && kind[s] == 1 for s in σ], :isB => [s != 0 && kind[s] == 2 for s in σ],
                    :vol => [s == 0 ? 0.0 : Float64(count(==(s), σ)) for s in σ]]

cr_divided(σ0, σ) = maximum(σ) != maximum(σ0)

# the `k × k` blocks of `σ` that a cell covers in part (some sites in it, some not)
cr_partial(σ, k) = count(((I, J),) -> (b = σ[I:(I + k - 1), J:(J + k - 1)]; any(!=(0), b) && any(==(0), b)),
                         Iterators.product(1:k:size(σ, 1), 1:k:size(σ, 2)))


# ---------------------------------------------------------------------------------------------
# F4-B6 (F4 design §11, D-F4-B6): front end A's field surface is gone. Each of its spellings is an
# ordinary error that names the route: a field line in `@equations` points to `@fields`; a name of
# a field's PDESystem (`Δ`, `masked`, `Differential`, …) that the model's module does not define
# points to `using Potts.Fields` and `@fields`; a field equation given to `PottsSystem(; equations)`
# points to `Potts.couple`. Each is checked in a fresh module, so no name another test file
# brought into `Main` is read. Negative control: at 866ea0e9 (A present) every A spelling below
# builds and no refusal is raised (~/lpwork/f4B6/nc-b6.log).
function cp_fresh_err(ex)
    m = Module(:CpFresh)
    Core.eval(m, :(using Potts))
    return try
        Core.eval(m, ex)
        "built"
    catch err
        while err isa LoadError
            err = err.error
        end
        err isa ArgumentError ? sprint(showerror, err) : "not an ArgumentError: " * sprint(showerror, err)
    end
end

cp_a_model(lines...) = quote
    @potts_model CpA begin
        @kinds medium A
        @variables begin
            c(field) = 0.0
            x(cell) = 1.0
        end
        @lattice Lattice((8, 8); boundary = Closed())
        @energy cells(A) => (volume - 9.0)^2
        $(lines...)
        @sweep Metropolis(; temperature = 1.0)
    end
    CpA(; name = :m)
end

# ---- from fields_couple_e.jl ------------------------------------------------------------------------


# a model whose kind has the name of the PDESystem's input; and a global that holds an input
# under another name (the value fallback)
@potts_model CeKindNamed begin
    @kinds medium endo
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(endo) => (volume - 16.0)^2
    @fields CpPDE.sys2() (endo => kind == endo)
    @sweep Metropolis(; temperature = 4.0)
end

const CE_ALIAS = CpPDE.endo

@potts_model CeAlias begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys2() (CE_ALIAS => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

# ---- from fields_short.jl ---------------------------------------------------------------------------
module FsMerks
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: Δ, lattice_domain
const t = Potts.t
@parameters x y Dc = 0.75 σc = 5.4e-3 δc = 5.4e-3
@variables c(..) cell(..)::Bool [input = true] ecm(..)::Bool [input = true]
const C = c(t, x, y)
eq() = Differential(t)(C) ~ Dc * Δ(C) + σc * cell(t, x, y) - δc * C * ecm(t, x, y)
# the current form: a function of the lattice
chemoattractant(lattice) = PDESystem([eq()], [c(0, x, y) ~ 0.0], lattice_domain(t, (x, y), lattice), [t, x, y],
    [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc]; name = :merks_field)
# the short form: no domain (and `pdesystem` works out the lists)
const SHORT = Potts.LatticePDE.pdesystem([eq()], [c(0, x, y) ~ 0.0]; name = :merks_field)
const NODOM = PDESystem([eq()], [c(0, x, y) ~ 0.0], [], [t, x, y], [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc];
    name = :merks_field)
end


# the short vocabulary end to end: `using Potts.Fields`, `pdesystem` with no domain, Potts' own `x, y`
module FsShort
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2 s = 0.5 kd = 0.1
@variables c(..) = 0.0 endo(..)::Bool [input = true]
const C = c(t, x, y)
const SYS = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C]; name = :fields)
end


for (nm, sys) in ((:FsMerksLong, :(FsMerks.chemoattractant(lattice))), (:FsMerksShort, :(FsMerks.SHORT)),
                  (:FsMerksNoDom, :(FsMerks.NODOM)))
    @eval @potts_model $nm begin
        @structural_parameters lattice = (40, 30)
        @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
        @kinds medium endothelial
        @parameters begin
            λ = 50.0
            V₀ = 25.0
            χ = 1000.0
            T = 50.0
        end
        @fields c = $sys (cell => kind == endothelial, ecm => kind == medium)
        @energy cells(endothelial) => λ * (volume - V₀)^2
        @drive copy => -χ * (c[target] - c[source])
        @sweep Metropolis(; temperature = T)
    end
end

fs_op(dims = (40, 30)) = (σ = zeros(Int32, dims...); σ[5:9, 5:9] .= 1; σ[20:24, 12:16] .= 2; σ[30:34, 20:24] .= 3;
    [ownership => σ, kind => fill(:endothelial, 3)])

fs_run(m; op = fs_op(Potts._p(m, :lattice).dims), k = 20) = solve(PottsProblem(m, op, (0, k); seed = 5), SequentialCPM(); saveat = 0:5:k)

# ---- from fields_couple_e8.jl -----------------------------------------------------------------------
module CeS
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2 s = 0.5 kd = 0.1
@variables c(..) = 0.0 a(..)::Bool [input = true] sv(..) [input = true]
const C = c(t, x, y)
named() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * a(t, x, y) - kd * C]; name = :fields)
# the same on the 24 × 20 lattice's domain, for LatticePDE's own run (`cp_replay`)
named_owned() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * a(t, x, y) - kd * C]; name = :fields,
    domain = lattice_domain(t, (x, y), (24, 20)))
# the workaround: `s` an input, bound to a model parameter
work() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + sv(t, x, y) * a(t, x, y) - kd * C]; name = :fields)
end


@potts_model CeNamed begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, s = CeS.named() (a => kind == A)
    @drive copy => -400.0 * s * (c[target] - c[source])
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CeWork begin
    @kinds medium A
    @parameters s = 0.5
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CeS.work() (a => kind == A, sv => s)
    @drive copy => -400.0 * s * (c[target] - c[source])
    @sweep Metropolis(; temperature = 4.0)
end


# E9: a `::Bool` input takes any truth-valued expression: a comparison, `ismember`, `!`, `&`,
# `|`, and an `any`/`all` fold over a relation, whose symbolic type is not `Bool`. A numeric
# expression is still refused. Oracles: the input against the hand-computed sites, and the field
# against LatticePDE's own run with those inputs over each MCS (`cp_replay`; until F4-B6, the
# same term in `@equations`, bitwise). Negative control at the E8 commit: "is not a truth value"
# for the `any` binding (~/lpwork/f4E/nc-e8e10.log).
@potts_model CeAny begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CeS.named() (a => any(kind[n] == A for n in VonNeumann(1)(site)))
    @sweep Metropolis(; temperature = 4.0)
end


# E10: a refusal of a condition that a PDESystem brought names the PDESystem and the condition,
# not `@bcs`. Negative control at the E9 commit: the messages start "@bcs:" and end "in @bcs …"
# (~/lpwork/f4E/nc-e8e10.log).
module CeB
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2
@variables c(..) = 0.0
const C = c(t, x, y)
face() = pdesystem([Differential(t)(C) ~ Dc * Δ(C)], [c(t, 0, y) ~ 1.0]; name = :faced)
end

@potts_model CePeriodic begin
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy cells => (volume - 16.0)^2
    @fields CeB.face()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CePeriodicHost begin
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

# ---- from fields_couple_e11.jl ----------------------------------------------------------------------
ce_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])

# every site field after each of `k` MCS
function ce_steps(m, op, k; kw...)
    integ = init(PottsProblem(m, op, (0, k); kw...), SequentialCPM(); save_start = false)
    return [(step!(integ); st = current_state(integ).site;
             [n => copy(Array(getproperty(st, n))) for n in sort!(collect(propertynames(st)))]) for _ in 1:k]
end


# --- E11: array (component) fields -----------------------------------------------------------
# `couple` failed with `getindex(::Num, ::Num)`: `u[i]` of an array dependent variable. Now the
# components are the fields `u_1, u_2` that `@variables u(field)[1:2]` declares.
module CeArr
using Potts: Potts
using Potts.Fields
@variables u(..)[1:2] = [0.5, 0.5] w(..)[1:2] = [0.0, 0.0] k(..)::Bool [input = true]
const U, W = u(t, x, y), w(t, x, y)
fi() = pdesystem([Differential(t)(U[1]) ~ 0.5 * Δ(U[1]) - 40 * U[1] / (0.025 + U[1]) + 20,
    Differential(t)(U[2]) ~ 0.5 * Δ(U[2]) - U[2] + U[1]]; name = :fi)
fc() = pdesystem([0 ~ 0.1 * Δ(W[1]) - 0.1 * W[1] + 5.0 * W[2] + 0.5 * k(t, x, y), 0 ~ 0.1 * Δ(W[2]) - W[2] - 5.0 * W[1]];
    name = :fc)
@variables q(..)[1:2, 1:2] = 0.0
const Q = q(t, x, y)
mat() = pdesystem([Differential(t)(Q[i, j]) ~ -Q[i, j] for i in 1:2 for j in 1:2]; name = :mat)
# the same fields as scalars: `ua, ub` for `u`, `wa, wb` for `w`
@variables ua(..) = 0.5 ub(..) = 0.5 wa(..) = 0.0 wb(..) = 0.0
const UA, UB, WA, WB = ua(t, x, y), ub(t, x, y), wa(t, x, y), wb(t, x, y)
sfi() = pdesystem([Differential(t)(UA) ~ 0.5 * Δ(UA) - 40 * UA / (0.025 + UA) + 20, Differential(t)(UB) ~ 0.5 * Δ(UB) - UB + UA];
    name = :sfi)
sfc() = pdesystem([0 ~ 0.1 * Δ(WA) - 0.1 * WA + 5.0 * WB + 0.5 * k(t, x, y), 0 ~ 0.1 * Δ(WB) - WB - 5.0 * WA]; name = :sfc)
end

@potts_model CeHostArr begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CeFiCompB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields u = CeArr.fi()
    @sweep Metropolis(; temperature = 1.0)
end

# a later statement reads a component through the name `@fields u = …` binds
@potts_model CeFiDriveB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields u = CeArr.fi()
    @drive copy => -10.0 * (u[2][target] - u[2][source])
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CeFcCompB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields w = CeArr.fc() (k => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

# the scalar spellings
@potts_model CeFiScal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields CeArr.sfi()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CeFiDriveScal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields ua, ub = CeArr.sfi()
    @drive copy => -10.0 * (ub[target] - ub[source])
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CeFcScal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields CeArr.sfc() (k => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

# the values of each MCS, by position (the names differ)
ce_values(r) = [last.(filter(p -> !endswith(string(first(p)), "__next"), step)) for step in r]


# a face condition on a component, `u(t, 0, y)[1] ~ 1.0`: bitwise the same system in two
# scalar fields `a, b` with `a(t, 0, y) ~ 1.0`
module CeArrF
using Potts: Potts
using Potts.Fields
@variables u(..)[1:2] = [0.0, 0.0] a(..) = 0.0 b(..) = 0.0
const U, A, B = u(t, x, y), a(t, x, y), b(t, x, y)
arr() = pdesystem([Differential(t)(U[1]) ~ 0.5 * Δ(U[1]) - 0.1 * U[1], Differential(t)(U[2]) ~ 0.5 * Δ(U[2]) + 0.1 * U[1] - 0.2 * U[2]],
    [u(t, 0, y)[1] ~ 1.0]; name = :arrf)
sca() = pdesystem([Differential(t)(A) ~ 0.5 * Δ(A) - 0.1 * A, Differential(t)(B) ~ 0.5 * Δ(B) + 0.1 * A - 0.2 * B],
    [a(t, 0, y) ~ 1.0]; name = :scaf)
end


# --- E12: `Advect` with a velocity vector ------------------------------------------------------
# `_pde_term` sent the shape argument of `SymbolicUtils.array_literal` (`[ux, 0.0]`) through the
# generic path (a MethodError); now the shape is kept and the elements are mapped.
module CeAdv
using Potts: Potts
using Potts.Fields
@parameters ux = 0.3 s = 0.01
@variables c(..) = 0.0 cb(..) = 0.5 [bounds = (0, 1)] ci(..) = 0.5
const C, CB, CI = c(t, x, y), cb(t, x, y), ci(t, x, y)
# (`dims`: the lattice's domain, for LatticePDE's own run of the same system)
dom(dims) = dims === nothing ? Any[] : lattice_domain(t, (x, y), dims)
adv(dims = nothing) = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([ux, 0.0], C) + s * y]; name = :adv, domain = dom(dims))
advconst(dims = nothing) = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([0.3, 0.0], C) + s * y]; name = :advc,
    domain = dom(dims))
# (the model's lattice is periodic: LatticePDE's run takes it as periodic conditions)
burgers(dims = nothing) = pdesystem([Differential(t)(CB) ~ -Advect(Upwind1())([CB, 0.0], CB)],
    dims === nothing ? Any[] : [cb(t, 0, y) ~ cb(t, dims[1], y), cb(t, x, 0) ~ cb(t, x, dims[2])]; name = :burgers, domain = dom(dims))
ivadv(dims = nothing) = pdesystem([Differential(t)(CI) ~ 0.1 * Δ(CI) - Advect(Upwind1())([0.05 * (1 + x), 0.0], CI)]; name = :ivadv,
    domain = dom(dims))
end

for (nm, dims, bnd, sys) in ((:CeAdvB, (8, 6), :(Closed()), :(CeAdv.adv())), (:CeAdvConstB, (8, 6), :(Closed()), :(CeAdv.advconst())),
                             (:CeBurgersB, (32, 32), :(Periodic()), :(CeAdv.burgers())), (:CeIvAdvB, (16, 16), :(Closed()), :(CeAdv.ivadv())))
    @eval @potts_model $nm begin
        @kinds medium A
        @lattice Lattice($dims; boundary = $bnd)
        @energy cells(A) => (volume - 9.0)^2
        @fields $sys
        @sweep Metropolis(; temperature = 1.0)
    end
end


# --- E13: a centroid-reading mask in a condition ---------------------------------------------
# The moment trackers were allocated for `@boundary` masks only: a masked condition (a
# PDESystem's) that reads `centroid(owner, 1)` met no trackers. The RHMaskCentroid oracle
# (test/ref_helpers.jl): cell 1 (centroid 6) is clamped to 7, cell 2 (centroid 2) and the
# medium stay 0.
module CeMask
using Potts: Potts
using Potts.Fields
@variables c(..) = 0.0 m(..)::Bool [input = true]
const C = c(t, x, y)
sys() = pdesystem([Differential(t)(C) ~ -C], [C ~ masked(m(t, x, y), 7.0)]; name = :mask)
end

@potts_model CeMaskB begin
    @kinds medium ka
    @lattice Lattice((12, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 1.0e6 * (volume - 9.0)^2
    @fields CeMask.sys() (m => (kind == ka) & (centroid(owner, 1) > 4.0))
    @sweep Metropolis(; temperature = 0.01)
end

function ce_mask_sigma()
    σ = zeros(Int32, 12, 10)
    σ[5:7, 4:6] .= 1
    σ[1:3, 4:6] .= 2
    return σ
end


# --- E14: a face condition on a field with no spatial operator ---------------------------------
# A face sets the ghost values of a spatial operator; on `D(c) ~ 0.1 - 0.01c` it would do
# nothing. `@boundary` refused it; a condition (a PDESystem's) built.
module CeFace
using Potts: Potts
using Potts.Fields
@variables c(..) = 0.0
const C = c(t, x, y)
nolap() = pdesystem([Differential(t)(C) ~ 0.1 - 0.01 * C], [c(t, 0, y) ~ 1.0]; name = :nolap)
lap() = pdesystem([Differential(t)(C) ~ 0.1 * Δ(C) + 0.1 - 0.01 * C], [c(t, 0, y) ~ 1.0]; name = :lap)
end

@potts_model CeFaceB begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields CeFace.nolap()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CeFaceLapB begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields CeFace.lap()
    @sweep Metropolis(; temperature = 1.0)
end


# --- E15: a fingerprint that depends on the session -----------------------------------------
# A neighbourhood with an anonymous weight printed its compiler-generated type name
# (`Main.var"#24#25"`) into the fingerprint seed; the number depends on what was defined before
# it in the session (the B4t pad tests: CsWComp and CsWSurf in cell_sums_models.jl). Two
# closures with the same body have two such names: the fingerprints must agree.
const CE_W1 = Potts.CorePotts.Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))

const CE_W2 = Potts.CorePotts.Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))

for (nm, w) in ((:CeW1, :CE_W1), (:CeW2, :CE_W2))
    @eval @potts_model $nm begin
        @kinds medium A
        @lattice Lattice((20, 20); boundary = Periodic(), neighborhood = $w)
        @energy cells => (volume - 16.0)^2
        @sweep Metropolis(; temperature = 10.0)
    end
end

# ---- from fields_couple_w2.jl -----------------------------------------------------------------------
module W2
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.5 s = 0.4 k = 0.05
@variables c(..) = 0.0 u(..) = 0.0 K(..) = 0.0 secreting(..)::Bool [input = true] kin(..)::Int32 [input = true]
@variables kinl(..)::Int32 [input = true, lattice_input_name = "kind"]
const C, U, KK = c(t, x, y), u(t, x, y), K(t, x, y)
# E14: the condition on `c` sets the ghosts that `Δ(c)` in the equation of `u` reads (p14.jl)
withbc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U], [c(t, 0, y) ~ 1.0];
    name = :wbc)
nobc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U]; name = :nbc)
# … and through an aux field `K ~ Δ(c)` that `u` reads
auxbc(bcs = [c(t, 0, y) ~ 1.0]) = pdesystem([Differential(t)(C) ~ -0.1 * C, KK ~ Δ(C), Differential(t)(U) ~ 0.5 * KK - 0.1 * U],
    bcs; name = :abc)
auxnobc() = auxbc([])
sec() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * secreting(t, x, y) - k * C]; name = :sec)
# m5: `∈ Set(…)` is Julia's `false`; the source term is gone before `pdesystem` sees it
inset() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kin(t, x, y) ∈ Set([1, 2])) - k * C]; name = :sec)
# m5d: the long form that lists the input (it is filled by `kind`, but no equation reads it)
insetlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kinl(t, x, y) ∈ Set([1, 2])) - k * C], [], [], [t, x, y],
    [C, kinl(t, x, y)], [Dc, s, k]; name = :sec)
# m4: a test of Potts' `kind` (or `volume`) inside the equation
cellread(q) = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (q == 1) - k * C]; name = :sec)
# m4c: the long form that reads Potts' `kind` in its equation
kindlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (Potts.kind == 1) - k * C], [], [], [t, x, y], [C], [Dc, s, k];
    name = :sec)
# a read of Potts' clock built-ins (`Potts.B.time`, `Potts.B.mcs`), and the route: the system's own `t`
clockread(q) = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(q) - k * C]; name = :clk)
clocklong(q) = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(q) - k * C], [], [], [t, x, y], [C], [Dc, s, k]; name = :clk)
timeroute() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(t) - k * C]; name = :clk)
mcsroute() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(step_index(t)) - k * C]; name = :clk)
# m7: the long form with an empty parameter list
nops() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) - k * C], [], [], [t, x, y], [C], []; name = :sys)
# E5: a domain entry for a variable that is not an independent variable
@parameters zz
zdom() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) - k * C], [], [zz ∈ Interval(0.0, 1.0)], [t, x, y], [C], [Dc, k];
    name = :sys)
end


@potts_model W2Host begin
    @kinds medium cell other
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

w2_op() = (σ = zeros(Int32, 12, 10); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:cell]])

w2_model(fields; kinds = :(@kinds medium cell other)) = :(@potts_model W2M begin
    $kinds
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells => (volume - 9.0)^2
    $fields
    @sweep Metropolis(; temperature = 1.0)
end)

w2_new(ex) = cp_msg(() -> (Core.eval(@__MODULE__, ex); Base.invokelatest(() -> W2M(; name = :m))))


# --- E14: a face condition read through another field's operator ------------------------------
# At 11523b0b the condition on `c` was refused although `Δ(c)` in the equation of `u` reads its
# ghost values (with E14 bypassed, the runs with and without it differ: p1415.log).
@potts_model W2FaceW begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.withbc()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model W2FaceN begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.nobc()
    @sweep Metropolis(; temperature = 1.0)
end

w2_face_op() = (σ = zeros(Int32, 8, 6); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])

w2_u(m; kw...) = (pr = PottsProblem(m(; name = :m), w2_face_op(), (0, 3); seed = 1, kw...); Array(solve(pr, SequentialCPM()).u[end].site.u))

# the hand value of `u` after 3 MCS of 4 explicit Euler substeps (h = 1/4): `c` has no spatial
# operator in its own equation, so it stays 0, and `Δ(c)` is 2 on the column beside the face
# `c = 1` (the ghost value 2 · 1 − 0, h = 1) and 0 elsewhere. There `u' = 1 − 0.1 u`, so
# `u = 10 (1 − (1 − 0.025)^12)`; elsewhere `u` stays 0
w2_hand() = (u = zeros(8, 6); u[1, :] .= 10 * (1 - (1 - 0.1 / 4)^12); u)


# --- E14: a face condition read through an aux field ------------------------------------------
# At a3bccd89 the condition on `c` was refused when `Δ(c)` sits in an aux definition `K ~ Δ(c)`
# that `u` reads (review probe ~/lpwork/rev-w2v-jobs/aux_probe.jl); the inlined model ran.
@potts_model W2AuxBcs begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.auxbc()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model W2AuxNo begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.auxnobc()
    @sweep Metropolis(; temperature = 1.0)
end

# ---- from fields_couple_b6.jl -----------------------------------------------------------------------
module B6
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2 s = 0.5 kd = 0.1 ra = 1.5 rb = -0.5 g = 0.2
@variables c(..) = 0.0 L(..) = 0.0 u(..) = 0.0 sec(..)::Bool [input = true] vol(..) [input = true] w(..) [input = true]
@variables cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)] v(..) [input = true]
const C, CC = c(t, x, y), cc(t, x, y)
# the round trip: a kind binding, a bare CPM read (`vol`) and a CPM read inside arithmetic (`w`)
att() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sec(t, x, y) * vol(t, x, y) / 16 - kd * C]; name = :att)
scaled() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * w(t, x, y) - kd * C]; name = :scaled)
coarse() = pdesystem([Differential(t)(CC) ~ Dc * Δ(CC) + s * sec(t, x, y) - kd * CC]; name = :crs)
# a coarse source with no decay (F4-15): the total over the lattice is the source's fine total
conserve() = pdesystem([Differential(t)(CC) ~ Dc * Δ(CC) + s * sec(t, x, y)]; name = :cons)
# Δ of a bound input; the route (a site variable read as an unbound input)
lapin() = pdesystem([Differential(t)(C) ~ 0.1 * Δ(C) + 0.1 * Δ(sec(t, x, y))]; name = :lapin)
lapsite() = pdesystem([Differential(t)(C) ~ 0.1 * Δ(C) + 0.1 * Δ(v(t, x, y))]; name = :lapsite)
# hex faces: Dirichlet on the low face of `x`, Robin on the low face of `y` (rb6/p2.jl lane 2)
faces() = pdesystem([Differential(t)(C) ~ 0.3 * Δ(C) - 0.2 * C + 0.05 * x],
    [c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) + rb * Differential(y)(c(t, x, 0)) ~ g]; name = :faces)
faces_owned() = pdesystem([Differential(t)(C) ~ 0.3 * Δ(C) - 0.2 * C + 0.05 * x],
    [c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) + rb * Differential(y)(c(t, x, 0)) ~ g]; name = :faces,
    domain = lattice_domain(t, (x, y), (8, 8)))
# a raw derivative along `x` (rb6/p2.jl lane 3)
xflux() = pdesystem([Differential(t)(C) ~ 0.1 * Differential(x)(Differential(x)(C)) + 0.01 * x]; name = :xflux)
zflux() = pdesystem([Differential(t)(C) ~ 0.1 * Differential(z)(Differential(z)(C))]; name = :zflux)
# an aux field `L ~ Δ(c)`, read by a drive (the route for `Δ(c)[target]` in a model line)
auxlap() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) - 0.1 * C + 0.1, L(t, x, y) ~ Δ(C)]; name = :auxlap)
plain() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) - 0.1 * C + 0.1]; name = :plain)
# wording: a Robin coefficient that reads another field; a condition on a field with no equation
robinu(a = u(t, x, y)) = pdesystem([Differential(t)(C) ~ Dc * Δ(C), Differential(t)(u(t, x, y)) ~ -0.1 * u(t, x, y)],
    [(1 + a) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 0.3]; name = :fac)
nonlin() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) - 0.1 * C^3]; name = :nonlin)
end


b6_op(dims = (24, 20)) = (σ = zeros(Int32, dims); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])


@potts_model B6Fine begin
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = B6.att() (B6.sec => kind == A, B6.vol => volume[owner])
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model B6Scaled begin
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = B6.scaled() (B6.w => 0.5 * volume[owner])
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model B6Coarse begin
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields cc = B6.coarse() (B6.sec => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model B6Conserve begin
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields cc = B6.conserve() (B6.sec => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

# the round trip `Potts.fields(model)` → `discretize(…; inputs = collect(Potts.field_inputs(integ)))`,
# σ frozen: one MCS from the coupled field at MCS 3, against the coupled run's MCS 4
function b6_round_trip(m, fs, f)
    integ = init(PottsProblem(m, b6_op(), (0, 5); field_solver = fs, seed = 3), SequentialCPM())
    for _ in 1:3
        step!(integ)
    end
    F = Potts.fields(m)
    prob = LP.discretize(F, LP.LatticeDiscretization(LP.Grid((24, 20)); T = Float64); inputs = collect(Potts.field_inputs(integ)))
    u0 = vec(Array(getproperty(integ.u.site, f)))
    o = LP.solve(LP.remake(prob; u0, tspan = (0.0, 1.0)), cp_own(fs)).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(integ.u.site, f)))), integ
end

b6_names(m) = sort!([String(Potts.LatticePDE.get_lattice_input_name(Potts.Symbolics.unwrap(d)))
                     for d in Potts.fields(m).dvs if Potts.ModelingToolkitBase.isinput(Potts.Symbolics.unwrap(d))])


# batch-end review (a): the same route on a mixed lattice, `x` closed and `y` periodic. The site
# variable `v` under `Δ` has a zero-flux face on each end of `x` and wraps along `y`: hand oracle
# with the cell on the low face of `x` and across the `y` wrap (the reviewer's probe,
# ~/lpwork/f4rbe/probe/probe.log; it passes at ab34e226 too: the docs sentence's case)
@potts_model B6LapMix begin
    @kinds medium A[frozen]
    @variables v(site) = 0.0
    @lattice Lattice((8, 8); boundary = (Closed(), Periodic()))
    @energy cells(A) => (volume - 4.0)^2
    @fields c = B6.lapsite()
    @after_mcs v ~ kind == A
    @sweep Metropolis(; temperature = 1.0)
end


# batch-end review (d): with no field named, a refusal names the model's one field equation (or the
# fields' PDESystem), never its first equation, which may be a cell ODE (base ab34e226: `D(g) ~ …`)
@potts_model B6Ode begin
    @kinds medium A
    @variables g(cell) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(g) ~ -0.1 * g
    @fields c = B6.plain()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model B6Hex begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed(), geometry = Hexagonal())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = B6.faces()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model B6X begin
    @kinds medium A
    @variables x(cell) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = B6.xflux()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model B6NoX begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = B6.xflux()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model B6Aux begin
    @kinds medium A
    @lattice Lattice((20, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, L = B6.auxlap()
    @drive copy => -1.0 * (L[target] - L[source])
    @sweep Metropolis(; temperature = 4.0)
end


# batch-end review (b), S2, S3: `Potts.field_inputs(integ, pdesys)` gives exactly the inputs of
# `pdesys`: the user's own coupled PDESystem (its names; `sec => kind == A` as a site array of
# truth values) or `Potts.fields(model)` (its own names). `Potts.fields` names a bound read by its
# binding in the equations too (`vol(t, x, y)`, not `field1__in`), and `discretize` given the
# inputs of the other PDESystem names the route. Both round trips, σ frozen, against the coupled
# run's next MCS, fine and Coarse(2). Base ab34e226 (~/lpwork/f4BE/nc.log): no method
# `field_inputs(integ, pdesys)`; the equation reads `field1__in(t, x, y)`; no route.
# (the PDESystem on the lattice's domain, with a start value per field: `discretize` takes the
# field at MCS 3 as `u0`)
function b6_owned(f)
    un = Potts.Symbolics.unwrap
    ics = [Potts.SymbolicUtils.operation(un(d))(0, B6.x, B6.y) ~ 0.0 for d in f.dvs if !Potts.ModelingToolkitBase.isinput(un(d))]
    return Potts.ModelingToolkitBase.PDESystem(f.eqs, [f.bcs; ics], LP.lattice_domain(Potts.t, (B6.x, B6.y), (24, 20)), f.ivs, f.dvs,
        f.ps; name = nameof(f))
end

function b6_pde_round_trip(m, pde, fs, f; op = b6_op())
    integ = init(PottsProblem(m, op, (0, 5); field_solver = fs, seed = 3), SequentialCPM())
    for _ in 1:3
        step!(integ)
    end
    fi = Potts.field_inputs(integ, pde)
    prob = LP.discretize(b6_owned(pde), LP.LatticeDiscretization(LP.Grid((24, 20)); T = Float64); inputs = collect(fi),
        u0 = [f => Array(getproperty(integ.u.site, f))], tspan = (0.0, 1.0))
    o = LP.solve(prob, cp_own(fs)).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(integ.u.site, f)))), fi, integ
end

# The lapped-site input model of the B6 items (it was defined inside one of their testsets in the
# include-into-Main runner, where a later testset read it; here both items declare this setup).
@eval @potts_model B6LapSite begin
    @kinds medium A[frozen]
    @variables v(site) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = B6.lapsite()
    @after_mcs v ~ kind == A                                # (the form the message gives)
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end