@testsetup module CoupleB6Setup
using Potts, Test
using Potts: CorePotts

const B6_LP = Potts.LatticePDE

b6_msg(f) =
try
    f()
    "built"
catch e
    e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
end

function b6_build_err(ex)
    mod = Module(:B6BuildErr)
    Core.eval(mod, :(using Potts, Potts.Fields))
    Core.eval(mod, :(const B6 = $B6))
    return try
        Core.eval(mod, ex)
        "built"
    catch err
        while err isa LoadError
            err = err.error
        end
        sprint(showerror, err)
    end
end

b6_own(fs) = typeof(fs)((n === :dt ? 1.0 : getfield(fs, n) for n in fieldnames(typeof(fs)))...)
b6_tol(::ExplicitEuler) = 0.0
b6_tol(::BackwardEuler) = 1.0e-9

module B6
    using Potts: Potts
    using Potts.Fields
    @parameters Dc = 0.2 s = 0.5 kd = 0.1 ra = 1.5 rb = -0.5 g = 0.2
    @variables c(..) = 0.0 L(..) = 0.0 u(..) = 0.0 sec(..)::Bool [input = true] vol(..) [input = true] w(..) [input = true]
    @variables cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)] v(..) [input = true]
    const C, CC = c(t, x, y), cc(t, x, y)
    att() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sec(t, x, y) * vol(t, x, y) / 16 - kd * C]; name = :att)
    scaled() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * w(t, x, y) - kd * C]; name = :scaled)
    coarse() = pdesystem([Differential(t)(CC) ~ Dc * Δ(CC) + s * sec(t, x, y) - kd * CC]; name = :crs)
    conserve() = pdesystem([Differential(t)(CC) ~ Dc * Δ(CC) + s * sec(t, x, y)]; name = :cons)
    lapin() = pdesystem([Differential(t)(C) ~ 0.1 * Δ(C) + 0.1 * Δ(sec(t, x, y))]; name = :lapin)
    lapsite() = pdesystem([Differential(t)(C) ~ 0.1 * Δ(C) + 0.1 * Δ(v(t, x, y))]; name = :lapsite)
    faces() = pdesystem(
        [Differential(t)(C) ~ 0.3 * Δ(C) - 0.2 * C + 0.05 * x],
        [c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) + rb * Differential(y)(c(t, x, 0)) ~ g]; name = :faces
    )
    faces_owned() = pdesystem(
        [Differential(t)(C) ~ 0.3 * Δ(C) - 0.2 * C + 0.05 * x],
        [c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) + rb * Differential(y)(c(t, x, 0)) ~ g]; name = :faces,
        domain = lattice_domain(t, (x, y), (8, 8))
    )
    xflux() = pdesystem([Differential(t)(C) ~ 0.1 * Differential(x)(Differential(x)(C)) + 0.01 * x]; name = :xflux)
    zflux() = pdesystem([Differential(t)(C) ~ 0.1 * Differential(z)(Differential(z)(C))]; name = :zflux)
    auxlap() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) - 0.1 * C + 0.1, L(t, x, y) ~ Δ(C)]; name = :auxlap)
    plain() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) - 0.1 * C + 0.1]; name = :plain)
    robinu(a = u(t, x, y)) = pdesystem(
        [Differential(t)(C) ~ Dc * Δ(C), Differential(t)(u(t, x, y)) ~ -0.1 * u(t, x, y)],
        [(1 + a) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 0.3]; name = :fac
    )
    nonlin() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) - 0.1 * C^3]; name = :nonlin)
end

b6_op(dims = (24, 20)) = (σ = zeros(Int32, dims); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])

@potts_model _B6Frozen begin
    @structural_parameters variant = :fine
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    if variant === :fine
        @fields B6.att() (B6.sec => kind == A, B6.vol => volume[owner])
    elseif variant === :scaled
        @fields B6.scaled() (B6.w => 0.5 * volume[owner])
    elseif variant === :coarse
        @fields B6.coarse() (B6.sec => kind == A)
    elseif variant === :conserve
        @fields B6.conserve() (B6.sec => kind == A)
    else
        throw(ArgumentError("unknown B6 frozen variant: $variant"))
    end
    @sweep Metropolis(; temperature = 4.0)
end

B6Fine(; name = :B6Fine, kw...) = _B6Frozen(; variant = :fine, name, kw...)
B6Scaled(; name = :B6Scaled, kw...) = _B6Frozen(; variant = :scaled, name, kw...)
B6Coarse(; name = :B6Coarse, kw...) = _B6Frozen(; variant = :coarse, name, kw...)
B6Conserve(; name = :B6Conserve, kw...) = _B6Frozen(; variant = :conserve, name, kw...)

@potts_model _B6LapSite begin
    @structural_parameters y_periodic = false
    @kinds medium A[frozen]
    @variables v(site) = 0.0
    @lattice Lattice((8, 8); boundary = y_periodic ? (Closed(), Periodic()) : Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = B6.lapsite()
    @after_mcs v ~ kind == A
    @sweep Metropolis(; temperature = 1.0)
end

B6LapSite(; name = :B6LapSite, kw...) = _B6LapSite(; y_periodic = false, name, kw...)
B6LapMix(; name = :B6LapMix, kw...) = _B6LapSite(; y_periodic = true, name, kw...)

@potts_model B6Ode begin
    @kinds medium A
    @variables g(cell) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(g) ~ -0.1 * g
    @fields c = B6.plain()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _B6Simple begin
    @structural_parameters variant = :hex
    @kinds medium A
    @lattice Lattice((8, 8); geometry = variant === :hex ? Hexagonal() : CorePotts.Square(), boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = variant === :hex ? B6.faces() : B6.xflux()
    @sweep Metropolis(; temperature = 1.0)
end

B6Hex(; name = :B6Hex, kw...) = _B6Simple(; variant = :hex, name, kw...)
B6NoX(; name = :B6NoX, kw...) = _B6Simple(; variant = :nox, name, kw...)

@potts_model B6X begin
    @kinds medium A
    @variables x(cell) = 1.0
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

function b6_round_trip(m, fs, f)
    integ = init(PottsProblem(m, b6_op(), (0, 5); field_solver = fs, seed = 3), SequentialCPM())
    for _ in 1:3
        step!(integ)
    end
    F = Potts.fields(m)
    prob = B6_LP.discretize(F, B6_LP.LatticeDiscretization(B6_LP.Grid((24, 20)); T = Float64); inputs = collect(Potts.field_inputs(integ)))
    u0 = vec(Array(getproperty(current_state(integ).site, f)))
    o = B6_LP.solve(B6_LP.remake(prob; u0, tspan = (0.0, 1.0)), b6_own(fs)).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(current_state(integ).site, f)))), integ
end

b6_names(m) = sort!(
    [
        String(Potts.LatticePDE.get_lattice_input_name(Potts.Symbolics.unwrap(d)))
            for d in Potts.fields(m).dvs if Potts.ModelingToolkitBase.isinput(Potts.Symbolics.unwrap(d))
    ]
)

function b6_owned(f)
    un = Potts.Symbolics.unwrap
    ics = [Potts.SymbolicUtils.operation(un(d))(0, B6.x, B6.y) ~ 0.0 for d in f.dvs if !Potts.ModelingToolkitBase.isinput(un(d))]
    return Potts.ModelingToolkitBase.PDESystem(
        f.eqs, [f.bcs; ics], B6_LP.lattice_domain(Potts.t, (B6.x, B6.y), (24, 20)), f.ivs, f.dvs,
        f.ps; name = nameof(f)
    )
end

function b6_pde_round_trip(m, pde, fs, f; op = b6_op())
    integ = init(PottsProblem(m, op, (0, 5); field_solver = fs, seed = 3), SequentialCPM())
    for _ in 1:3
        step!(integ)
    end
    fi = Potts.field_inputs(integ, pde)
    prob = B6_LP.discretize(
        b6_owned(pde), B6_LP.LatticeDiscretization(B6_LP.Grid((24, 20)); T = Float64); inputs = collect(fi),
        u0 = [f => Array(getproperty(current_state(integ).site, f))], tspan = (0.0, 1.0)
    )
    o = B6_LP.solve(prob, b6_own(fs)).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(current_state(integ).site, f)))), fi, integ
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
