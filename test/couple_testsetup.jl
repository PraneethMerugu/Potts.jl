# The top-level definitions of fields_couple.jl, fields_couple_e.jl, fields_short.jl, fields_couple_e8.jl, fields_couple_e11.jl, fields_couple_w2.jl (converted from the include-into-Main suite, TS1a).

@testsetup module CoupleSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

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
sys(; name = :fields, dom = DOM) = PDESystem(
    [Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y) + av * vol(t, x, y)],
        [c(0, x, y) ~ 0.0], dom, [t, x, y], [c(t, x, y), endo(t, x, y), vol(t, x, y)], [Dc, s, kd, av]; name
    )
sys3(; name = :fields) = PDESystem([Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y),
        Dt(u(t, x, y)) ~ 0.3 * Δ(u(t, x, y)) + 0.2 * c(t, x, y) - 0.2 * u(t, x, y)],
        [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], DOM, [t, x, y], [c(t, x, y), u(t, x, y), endo(t, x, y)], [Dc, s, kd]; name
    )
sys2(; name = :fields) = PDESystem([Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y)],
    [c(0, x, y) ~ 0.0], DOM, [t, x, y], [c(t, x, y), endo(t, x, y)], [Dc, s, kd]; name)
end

const CE_ALIAS = CpPDE.endo

@potts_model CpHost begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model _Cp24x20 begin
    @structural_parameters variant = :fields
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    if variant === :fields
        @fields CpPDE.sys() (CpPDE.endo => kind == A, CpPDE.vol => volume[owner])
    elseif variant === :fields2
        @fields CpPDE.sys2() (CpPDE.endo => kind == A)
    elseif variant === :wrong
        @fields CpPDE.sys() (CpPDE.endo => kind == medium, CpPDE.vol => volume[owner])
    elseif variant === :alias
        @fields CpPDE.sys2() (CE_ALIAS => kind == A)
    else
        throw(ArgumentError("unknown _Cp24x20 variant: $variant"))
    end
    @sweep Metropolis(; temperature = 4.0)
end

CpFields(; name = :CpFields, kw...) = _Cp24x20(; variant = :fields, name, kw...)
CpFields2(; name = :CpFields2, kw...) = _Cp24x20(; variant = :fields2, name, kw...)
CpWrong(; name = :CpWrong, kw...) = _Cp24x20(; variant = :wrong, name, kw...)
CeAlias(; name = :CeAlias, kw...) = _Cp24x20(; variant = :alias, name, kw...)

@potts_model CpDrive begin
    @extend c, A = base = CpFields2()
    @parameters χ = 400.0
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
end

@potts_model CpSame begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model _CpDriveSys3 begin
    @structural_parameters drive_u = true
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, u = CpPDE.sys3() (CpPDE.endo => kind == A)
    if drive_u
        @drive Chemotaxis(u; strength = χ, kinds = (A,))
    else
        @drive Chemotaxis(c; strength = χ, kinds = (A,))
    end
    @sweep Metropolis(; temperature = 4.0)
end

CpList(; name = :CpList, kw...) = _CpDriveSys3(; drive_u = true, name, kw...)
CpOne(; name = :CpOne, kw...) = _CpDriveSys3(; drive_u = false, name, kw...)

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

const CP_ODE_TOL = 6e-5

const LP = Potts.LatticePDE

cp_hand(σ, kind) = [:endo => [s != 0 && kind[s] == 1 for s in σ],
                    :vol => [s == 0 ? 0.0 : Float64(count(==(s), σ)) for s in σ]]

cp_hand2(σ, kind) = cp_hand(σ, kind)[1:1]

function cp_replay(m, sys, ins, alg; op = cp_op(), k = 12, seed = 3, fs = ExplicitEuler(), fields = (:c,),
                   skip = (σ0, σ) -> false, p = nothing)
    integ = init(PottsProblem(m, op, (0, k); field_solver = fs, seed), SequentialCPM())
    σ = Array(current_state(integ).σ)
    prob = LP.discretize(sys, LP.LatticeDiscretization(LP.Grid(size(σ)); T = Float64); inputs = ins(σ, Array(current_state(integ).cell.kind)))
    p === nothing || (prob = LP.remake(prob; p))
    state() = reduce(vcat, (vec(Array(getproperty(current_state(integ).site, f))) for f in fields))
    err, n = 0.0, 0
    for _ in 1:k
        σ0, u0 = Array(current_state(integ).σ), state()
        step!(integ)
        σ = Array(current_state(integ).σ)
        skip(σ0, σ) && continue
        o = LP.solve(LP.remake(prob; u0, tspan = (0.0, 1.0), inputs = ins(σ, Array(current_state(integ).cell.kind))), alg; dt = 1.0).u[end]
        err, n = max(err, maximum(abs, o .- state())), n + 1
    end
    return err, n
end

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
        DOM, [t, x, y], [cc(t, x, y), endo(t, x, y)], [Dc, s, kd]; name = :crs
    )
kind_bool() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * kb(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, kb(t, x, y)], [Dc, s, kd]; name = :kbs)
kind_real() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * kr(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, kr(t, x, y)], [Dc, s, kd]; name = :krs)
end

@potts_model CrHost2 begin
    @kinds medium A B
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 4.0)
end

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

@potts_model CeKindNamed begin
    @kinds medium endo
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(endo) => (volume - 16.0)^2
    @fields CpPDE.sys2() (endo => kind == endo)
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
chemoattractant(lattice) = PDESystem([eq()], [c(0, x, y) ~ 0.0], lattice_domain(t, (x, y), lattice), [t, x, y],
        [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc]; name = :merks_field
    )
const SHORT = Potts.LatticePDE.pdesystem([eq()], [c(0, x, y) ~ 0.0]; name = :merks_field)
const NODOM = PDESystem([eq()], [c(0, x, y) ~ 0.0], [], [t, x, y], [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc];
    name = :merks_field)
end

module FsShort
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2 s = 0.5 kd = 0.1
@variables c(..) = 0.0 endo(..)::Bool [input = true]
const C = c(t, x, y)
const SYS = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C]; name = :fields)
end

@potts_model _FsMerksBase begin
    @structural_parameters begin
        lattice = (40, 30)
        mode = :long
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @kinds medium endothelial
    @parameters begin
        λ = 50.0
        V₀ = 25.0
        χ = 1000.0
        T = 50.0
    end
    @fields c = (
        mode === :long ? FsMerks.chemoattractant(lattice) :
            mode === :short ? FsMerks.SHORT : FsMerks.NODOM
    ) (cell => kind == endothelial, ecm => kind == medium)
    @energy cells(endothelial) => λ * (volume - V₀)^2
    @drive copy => -χ * (c[target] - c[source])
    @sweep Metropolis(; temperature = T)
end

FsMerksLong(; mode = :long, lattice = (40, 30), name = :FsMerksLong, kw...) = _FsMerksBase(; mode, lattice, name, kw...)
FsMerksShort(; mode = :short, lattice = (40, 30), name = :FsMerksShort, kw...) = _FsMerksBase(; mode, lattice, name, kw...)
FsMerksNoDom(; mode = :nodom, lattice = (40, 30), name = :FsMerksNoDom, kw...) = _FsMerksBase(; mode, lattice, name, kw...)

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
named_owned() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * a(t, x, y) - kd * C]; name = :fields,
        domain = lattice_domain(t, (x, y), (24, 20))
    )
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

@potts_model CeAny begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CeS.named() (a => any(kind[n] == A for n in VonNeumann(1)(site)))
    @sweep Metropolis(; temperature = 4.0)
end

module CeB
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2
@variables c(..) = 0.0
const C = c(t, x, y)
face() = pdesystem([Differential(t)(C) ~ Dc * Δ(C)], [c(t, 0, y) ~ 1.0]; name = :faced)
end

@potts_model _CePer12 begin
    @structural_parameters with_field = true
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy cells => (volume - 16.0)^2
    if with_field
        @fields CeB.face()
    end
    @sweep Metropolis(; temperature = 1.0)
end

CePeriodic(; name = :CePeriodic, kw...) = _CePer12(; with_field = true, name, kw...)
CePeriodicHost(; name = :CePeriodicHost, kw...) = _CePer12(; with_field = false, name, kw...)

# ---- from fields_couple_e11.jl ----------------------------------------------------------------------
ce_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])

function ce_steps(m, op, k; kw...)
    integ = init(PottsProblem(m, op, (0, k); kw...), SequentialCPM(); save_start = false)
    return [(step!(integ); st = current_state(integ).site;
             [n => copy(Array(getproperty(st, n))) for n in sort!(collect(propertynames(st)))]) for _ in 1:k]
end

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
@variables ua(..) = 0.5 ub(..) = 0.5 wa(..) = 0.0 wb(..) = 0.0
const UA, UB, WA, WB = ua(t, x, y), ub(t, x, y), wa(t, x, y), wb(t, x, y)
sfi() = pdesystem([Differential(t)(UA) ~ 0.5 * Δ(UA) - 40 * UA / (0.025 + UA) + 20, Differential(t)(UB) ~ 0.5 * Δ(UB) - UB + UA];
    name = :sfi)
sfc() = pdesystem([0 ~ 0.1 * Δ(WA) - 0.1 * WA + 5.0 * WB + 0.5 * k(t, x, y), 0 ~ 0.1 * Δ(WB) - WB - 5.0 * WA]; name = :sfc)
end

@potts_model _CeArrBase begin
    @structural_parameters variant = :host
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    if variant === :fi_comp
        @fields CeArr.fi()
    elseif variant === :fi_drive
        @fields u = CeArr.fi()
        @drive copy => -10.0 * (u[2][target] - u[2][source])
    elseif variant === :fc_comp
        @fields CeArr.fc() (k => kind == A)
    elseif variant === :fi_scal
        @fields CeArr.sfi()
    elseif variant === :fi_drive_scal
        @fields ua, ub = CeArr.sfi()
        @drive copy => -10.0 * (ub[target] - ub[source])
    elseif variant === :fc_scal
        @fields CeArr.sfc() (k => kind == A)
    elseif variant !== :host
        throw(ArgumentError("unknown CeArr variant: $variant"))
    end
    @sweep Metropolis(; temperature = 1.0)
end

CeHostArr(; name = :CeHostArr, kw...) = _CeArrBase(; variant = :host, name, kw...)
CeFiCompB(; name = :CeFiCompB, kw...) = _CeArrBase(; variant = :fi_comp, name, kw...)
CeFiDriveB(; name = :CeFiDriveB, kw...) = _CeArrBase(; variant = :fi_drive, name, kw...)
CeFcCompB(; name = :CeFcCompB, kw...) = _CeArrBase(; variant = :fc_comp, name, kw...)
CeFiScal(; name = :CeFiScal, kw...) = _CeArrBase(; variant = :fi_scal, name, kw...)
CeFiDriveScal(; name = :CeFiDriveScal, kw...) = _CeArrBase(; variant = :fi_drive_scal, name, kw...)
CeFcScal(; name = :CeFcScal, kw...) = _CeArrBase(; variant = :fc_scal, name, kw...)

ce_values(r) = [last.(filter(p -> !endswith(string(first(p)), "__next"), step)) for step in r]

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

module CeAdv
using Potts: Potts
using Potts.Fields
@parameters ux = 0.3 s = 0.01
@variables c(..) = 0.0 cb(..) = 0.5 [bounds = (0, 1)] ci(..) = 0.5
    const C, CB, CI = c(t, x, y), cb(t, x, y), ci(t, x, y)
dom(dims) = dims === nothing ? Any[] : lattice_domain(t, (x, y), dims)
adv(dims = nothing) = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([ux, 0.0], C) + s * y]; name = :adv, domain = dom(dims))
advconst(dims = nothing) = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([0.3, 0.0], C) + s * y]; name = :advc,
        domain = dom(dims)
    )
burgers(dims = nothing) = pdesystem([Differential(t)(CB) ~ -Advect(Upwind1())([CB, 0.0], CB)],
    dims === nothing ? Any[] : [cb(t, 0, y) ~ cb(t, dims[1], y), cb(t, x, 0) ~ cb(t, x, dims[2])]; name = :burgers, domain = dom(dims))
ivadv(dims = nothing) = pdesystem([Differential(t)(CI) ~ 0.1 * Δ(CI) - Advect(Upwind1())([0.05 * (1 + x), 0.0], CI)]; name = :ivadv,
    domain = dom(dims))
end

@potts_model _CeAdvBase begin
    @structural_parameters begin
        dims = (8, 6)
        periodic = false
        sys_fn = CeAdv.adv
    end
    @kinds medium A
    @lattice Lattice(dims; boundary = periodic ? Periodic() : Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

CeAdvB(; name = :CeAdvB, kw...) = _CeAdvBase(; dims = (8, 6), periodic = false, sys_fn = CeAdv.adv, name, kw...)
CeAdvConstB(; name = :CeAdvConstB, kw...) = _CeAdvBase(; dims = (8, 6), periodic = false, sys_fn = CeAdv.advconst, name, kw...)
CeBurgersB(; name = :CeBurgersB, kw...) = _CeAdvBase(; dims = (32, 32), periodic = true, sys_fn = CeAdv.burgers, name, kw...)
CeIvAdvB(; name = :CeIvAdvB, kw...) = _CeAdvBase(; dims = (16, 16), periodic = false, sys_fn = CeAdv.ivadv, name, kw...)

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

module CeFace
using Potts: Potts
using Potts.Fields
@variables c(..) = 0.0
const C = c(t, x, y)
nolap() = pdesystem([Differential(t)(C) ~ 0.1 - 0.01 * C], [c(t, 0, y) ~ 1.0]; name = :nolap)
lap() = pdesystem([Differential(t)(C) ~ 0.1 * Δ(C) + 0.1 - 0.01 * C], [c(t, 0, y) ~ 1.0]; name = :lap)
end

const CE_W1 = Potts.CorePotts.Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
const CE_W2 = Potts.CorePotts.Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))

@potts_model _CeWBase begin
    @structural_parameters w = CE_W1
    @kinds medium A
    @lattice Lattice((20, 20); boundary = Periodic(), neighborhood = w)
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 10.0)
end

CeW1(; name = :CeW1, kw...) = _CeWBase(; w = CE_W1, name, kw...)
CeW2(; name = :CeW2, kw...) = _CeWBase(; w = CE_W2, name, kw...)

# ---- from fields_couple_w2.jl -----------------------------------------------------------------------
module W2
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.5 s = 0.4 k = 0.05
@variables c(..) = 0.0 u(..) = 0.0 K(..) = 0.0 secreting(..)::Bool [input = true] kin(..)::Int32 [input = true]
@variables kinl(..)::Int32 [input = true, lattice_input_name = "kind"]
    const C, U, KK = c(t, x, y), u(t, x, y), K(t, x, y)
withbc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U], [c(t, 0, y) ~ 1.0];
    name = :wbc)
    nobc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U]; name = :nbc)
auxbc(bcs = [c(t, 0, y) ~ 1.0]) = pdesystem([Differential(t)(C) ~ -0.1 * C, KK ~ Δ(C), Differential(t)(U) ~ 0.5 * KK - 0.1 * U],
    bcs; name = :abc)
auxnobc() = auxbc([])
    sec() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * secreting(t, x, y) - k * C]; name = :sec)
    inset() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kin(t, x, y) ∈ Set([1, 2])) - k * C]; name = :sec)
insetlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kinl(t, x, y) ∈ Set([1, 2])) - k * C], [], [], [t, x, y],
        [C, kinl(t, x, y)], [Dc, s, k]; name = :sec
    )
    cellread(q) = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (q == 1) - k * C]; name = :sec)
kindlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (Potts.kind == 1) - k * C], [], [], [t, x, y], [C], [Dc, s, k];
        name = :sec
    )
clockread(q) = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(q) - k * C]; name = :clk)
clocklong(q) = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(q) - k * C], [], [], [t, x, y], [C], [Dc, s, k]; name = :clk)
timeroute() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(t) - k * C]; name = :clk)
    mcsroute() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(step_index(t)) - k * C]; name = :clk)
    nops() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) - k * C], [], [], [t, x, y], [C], []; name = :sys)
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

@potts_model _FaceOnly8x6 begin
    @structural_parameters sys_fn = CeFace.nolap
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

CeFaceB(; name = :CeFaceB, kw...) = _FaceOnly8x6(; sys_fn = CeFace.nolap, name, kw...)
CeFaceLapB(; name = :CeFaceLapB, kw...) = _FaceOnly8x6(; sys_fn = CeFace.lap, name, kw...)
W2FaceW(; name = :W2FaceW, kw...) = _FaceOnly8x6(; sys_fn = W2.withbc, name, kw...)
W2FaceN(; name = :W2FaceN, kw...) = _FaceOnly8x6(; sys_fn = W2.nobc, name, kw...)
W2AuxBcs(; name = :W2AuxBcs, kw...) = _FaceOnly8x6(; sys_fn = W2.auxbc, name, kw...)
W2AuxNo(; name = :W2AuxNo, kw...) = _FaceOnly8x6(; sys_fn = W2.auxnobc, name, kw...)

w2_face_op() = (σ = zeros(Int32, 8, 6); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])
w2_u(m; kw...) = (pr = PottsProblem(m(; name = :m), w2_face_op(), (0, 3); seed = 1, kw...); Array(solve(pr, SequentialCPM()).u[end].site.u))
w2_hand() = (u = zeros(8, 6); u[1, :] .= 10 * (1 - (1 - 0.1 / 4)^12); u)

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
