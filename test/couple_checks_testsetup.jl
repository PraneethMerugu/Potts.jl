@testsetup module CoupleChecksSetup
using Potts, Test
using Potts: CorePotts

const CHK_LP = Potts.LatticePDE

chk_msg(f, E::Type{<:Exception} = ArgumentError) =
try
    f()
    "built"
catch e
    e isa E ? sprint(showerror, e) : "wrong exception $(typeof(e)), expected $E"
end

function chk_build_err(ex, E::Type{<:Exception} = ArgumentError)
    mod = Module(:ChkBuildErr)
    Core.eval(mod, :(using Potts, Potts.Fields))
    Core.eval(mod, :(const Chk = $Chk))
    return try
        Core.eval(mod, ex)
        "built"
    catch err
        while err isa LoadError
            err = err.error
        end
        err isa E ? sprint(showerror, err) : "wrong exception $(typeof(err)), expected $E"
    end
end

chk_tol(::ExplicitEuler) = 0.0
chk_tol(::BackwardEuler) = 1.0e-9

module Chk
    using Potts: Potts
    using Potts.Fields
    @parameters Dc = 0.2 s = 0.5 kd = 0.1 ra = 1.5 rb = -0.5 g = 0.2
    @variables c(..) = 0.0 L(..) = 0.0 u(..) = 0.0 sec(..)::Bool [input = true] vol(..) [input = true] w(..) [input = true]
    @variables cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)] v(..) [input = true]
    const C, CC = c(t, x, y), cc(t, x, y)
    att() = pdesystem([Differential(t)(C) ~ Dc * laplacian(C) + s * sec(t, x, y) * vol(t, x, y) / 16 - kd * C]; name = :att)
    scaled() = pdesystem([Differential(t)(C) ~ Dc * laplacian(C) + s * w(t, x, y) - kd * C]; name = :scaled)
    coarse() = pdesystem([Differential(t)(CC) ~ Dc * laplacian(CC) + s * sec(t, x, y) - kd * CC]; name = :crs)
    conserve() = pdesystem([Differential(t)(CC) ~ Dc * laplacian(CC) + s * sec(t, x, y)]; name = :cons)
    lapin() = pdesystem([Differential(t)(C) ~ 0.1 * laplacian(C) + 0.1 * laplacian(sec(t, x, y))]; name = :lapin)
    lapsite() = pdesystem([Differential(t)(C) ~ 0.1 * laplacian(C) + 0.1 * laplacian(v(t, x, y))]; name = :lapsite)
    faces() = pdesystem(
        [Differential(t)(C) ~ 0.3 * laplacian(C) - 0.2 * C + 0.05 * x],
        [c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) + rb * Differential(y)(c(t, x, 0)) ~ g]; name = :faces
    )
    faces_owned() = pdesystem(
        [Differential(t)(C) ~ 0.3 * laplacian(C) - 0.2 * C + 0.05 * x],
        [c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) + rb * Differential(y)(c(t, x, 0)) ~ g]; name = :faces,
        domain = lattice_domain(t, (x, y), (8, 8))
    )
    xflux() = pdesystem([Differential(t)(C) ~ 0.1 * Differential(x)(Differential(x)(C)) + 0.01 * x]; name = :xflux)
    zflux() = pdesystem([Differential(t)(C) ~ 0.1 * Differential(z)(Differential(z)(C))]; name = :zflux)
    auxlap() = pdesystem([Differential(t)(C) ~ Dc * laplacian(C) - 0.1 * C + 0.1, L(t, x, y) ~ laplacian(C)]; name = :auxlap)
    plain() = pdesystem([Differential(t)(C) ~ Dc * laplacian(C) - 0.1 * C + 0.1]; name = :plain)
    robinu(a = u(t, x, y)) = pdesystem(
        [Differential(t)(C) ~ Dc * laplacian(C), Differential(t)(u(t, x, y)) ~ -0.1 * u(t, x, y)],
        [(1 + a) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 0.3]; name = :fac
    )
    nonlin() = pdesystem([Differential(t)(C) ~ Dc * laplacian(C) - 0.1 * C^3]; name = :nonlin)
end

chk_op(dims = (24, 20)) = (σ = zeros(Int32, dims); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])

@potts_model _ChkFrozen begin
    @structural_parameters variant = :fine
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    if variant === :fine
        @fields Chk.att() (Chk.sec => kind == A, Chk.vol => volume[owner])
    elseif variant === :scaled
        @fields Chk.scaled() (Chk.w => 0.5 * volume[owner])
    elseif variant === :coarse
        @fields Chk.coarse() (Chk.sec => kind == A)
    elseif variant === :conserve
        @fields Chk.conserve() (Chk.sec => kind == A)
    else
        throw(ArgumentError("unknown frozen variant: $variant"))
    end
    @sweep Metropolis(; temperature = 4.0)
end

ChkFine(; name = :ChkFine, kw...) = _ChkFrozen(; variant = :fine, name, kw...)
ChkScaled(; name = :ChkScaled, kw...) = _ChkFrozen(; variant = :scaled, name, kw...)
ChkCoarse(; name = :ChkCoarse, kw...) = _ChkFrozen(; variant = :coarse, name, kw...)
ChkConserve(; name = :ChkConserve, kw...) = _ChkFrozen(; variant = :conserve, name, kw...)

@potts_model _ChkLapSite begin
    @structural_parameters y_periodic = false
    @kinds medium A[frozen]
    @variables v(site) = 0.0
    @lattice Lattice((8, 8); boundary = y_periodic ? (Closed(), Periodic()) : Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = Chk.lapsite()
    @after_mcs v ~ kind == A
    @sweep Metropolis(; temperature = 1.0)
end

ChkLapSite(; name = :ChkLapSite, kw...) = _ChkLapSite(; y_periodic = false, name, kw...)
ChkLapMix(; name = :ChkLapMix, kw...) = _ChkLapSite(; y_periodic = true, name, kw...)

@potts_model ChkOde begin
    @kinds medium A
    @variables g(cell) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(g) ~ -0.1 * g
    @fields c = Chk.plain()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _ChkSimple begin
    @structural_parameters variant = :hex
    @kinds medium A
    @lattice Lattice((8, 8); geometry = variant === :hex ? Hexagonal() : CorePotts.Square(), boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = variant === :hex ? Chk.faces() : Chk.xflux()
    @sweep Metropolis(; temperature = 1.0)
end

ChkHex(; name = :ChkHex, kw...) = _ChkSimple(; variant = :hex, name, kw...)
ChkNoX(; name = :ChkNoX, kw...) = _ChkSimple(; variant = :nox, name, kw...)

@potts_model ChkX begin
    @kinds medium A
    @variables x(cell) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = Chk.xflux()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model ChkAux begin
    @kinds medium A
    @lattice Lattice((20, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, L = Chk.auxlap()
    @drive copy => -1.0 * (L[target] - L[source])
    @sweep Metropolis(; temperature = 4.0)
end

function chk_round_trip(m, fs, f)
    integ = init(PottsProblem(m, chk_op(), (0, 5); field_solver = fs, seed = 3), SequentialCPM())
    for _ in 1:3
        step!(integ)
    end
    F = Potts.fields(m)
    prob = CHK_LP.discretize(F, CHK_LP.LatticeDiscretization(CHK_LP.Grid((24, 20)); T = Float64); inputs = collect(Potts.field_inputs(integ)))
    u0 = vec(Array(getproperty(current_state(integ).site, f)))
    o = CHK_LP.solve(CHK_LP.remake(prob; u0, tspan = (0.0, 1.0)), fs; dt = 1.0).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(current_state(integ).site, f)))), integ
end

chk_names(m) = sort!(
    [
        String(Potts.LatticePDE.get_lattice_input_name(Potts.Symbolics.unwrap(d)))
            for d in Potts.fields(m).dvs if Potts.ModelingToolkitBase.isinput(Potts.Symbolics.unwrap(d))
    ]
)

function chk_owned(f)
    un = Potts.Symbolics.unwrap
    ics = [Potts.SymbolicUtils.operation(un(d))(0, Chk.x, Chk.y) ~ 0.0 for d in f.dvs if !Potts.ModelingToolkitBase.isinput(un(d))]
    return Potts.ModelingToolkitBase.PDESystem(
        f.eqs, [f.bcs; ics], CHK_LP.lattice_domain(Potts.t, (Chk.x, Chk.y), (24, 20)), f.ivs, f.dvs,
        f.ps; name = nameof(f)
    )
end

function chk_pde_round_trip(m, pde, fs, f; op = chk_op())
    integ = init(PottsProblem(m, op, (0, 5); field_solver = fs, seed = 3), SequentialCPM())
    for _ in 1:3
        step!(integ)
    end
    fi = Potts.field_inputs(integ, pde)
    prob = CHK_LP.discretize(
        chk_owned(pde), CHK_LP.LatticeDiscretization(CHK_LP.Grid((24, 20)); T = Float64); inputs = collect(fi),
        u0 = [f => Array(getproperty(current_state(integ).site, f))], tspan = (0.0, 1.0)
    )
    o = CHK_LP.solve(prob, fs; dt = 1.0).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(current_state(integ).site, f)))), fi, integ
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
