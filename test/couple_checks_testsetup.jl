@testsetup module CoupleChecksSetup
using Potts, Test
using Potts: CorePotts

using Potts: LatticePDE

function check_msg(f, E::Type{<:Exception} = ArgumentError)
    return try
        f()
        "built"
    catch e
        e isa E ? sprint(showerror, e) : "wrong exception $(typeof(e)), expected $E"
    end
end

function check_build_err(ex, E::Type{<:Exception} = ArgumentError)
    mod = Module(:CheckBuildErr)
    Core.eval(mod, :(using Potts, Potts.Fields))
    Core.eval(mod, :(const Check = $Check))
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

check_tol(::ExplicitEuler) = 0.0
check_tol(::BackwardEuler) = 1.0e-9

module Check
    using Potts: Potts
    using Potts.Fields
    @parameters Dc = 0.2 s = 0.5 kd = 0.1 ra = 1.5 rb = -0.5 g = 0.2
    @variables c(..) = 0.0 L(..) = 0.0 u(..) = 0.0 sec(..)::Bool [input = true] vol(..) [
        input = true,
    ] w(..) [input = true]
    @variables cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)] v(..) [input = true]
    const C, CC = c(t, x, y), cc(t, x, y)
    function att()
        return pdesystem(
            [
                Differential(t)(C) ~
                    Dc * laplacian(C) + s * sec(t, x, y) * vol(t, x, y) / 16 - kd * C,
            ];
            name = :att
        )
    end
    function scaled()
        return pdesystem(
            [Differential(t)(C) ~ Dc * laplacian(C) + s * w(t, x, y) - kd * C];
            name = :scaled
        )
    end
    function coarse()
        return pdesystem(
            [
                Differential(t)(CC) ~
                    Dc * laplacian(CC) + s * sec(t, x, y) - kd * CC,
            ]; name = :crs
        )
    end
    function conserve()
        return pdesystem(
            [Differential(t)(CC) ~ Dc * laplacian(CC) + s * sec(t, x, y)];
            name = :cons
        )
    end
    function lapin()
        return pdesystem(
            [
                Differential(t)(C) ~
                    0.1 * laplacian(C) + 0.1 * laplacian(sec(t, x, y)),
            ]; name = :lapin
        )
    end
    function lapsite()
        return pdesystem(
            [
                Differential(t)(C) ~
                    0.1 * laplacian(C) + 0.1 * laplacian(v(t, x, y)),
            ]; name = :lapsite
        )
    end
    function faces()
        return pdesystem(
            [Differential(t)(C) ~ 0.3 * laplacian(C) - 0.2 * C + 0.05 * x],
            [
                c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) +
                    rb * Differential(y)(c(t, x, 0)) ~ g,
            ]; name = :faces
        )
    end
    function faces_owned()
        return pdesystem(
            [Differential(t)(C) ~ 0.3 * laplacian(C) - 0.2 * C + 0.05 * x],
            [
                c(0, x, y) ~ 1.0, c(t, 0, y) ~ 0.0, ra * c(t, x, 0) +
                    rb * Differential(y)(c(t, x, 0)) ~ g,
            ]; name = :faces,
            domain = lattice_domain(t, (x, y), (8, 8))
        )
    end
    function xflux()
        return pdesystem(
            [
                Differential(t)(C) ~
                    0.1 * Differential(x)(Differential(x)(C)) + 0.01 * x,
            ]; name = :xflux
        )
    end
    function zflux()
        return pdesystem(
            [Differential(t)(C) ~ 0.1 * Differential(z)(Differential(z)(C))];
            name = :zflux
        )
    end
    function auxlap()
        return pdesystem(
            [
                Differential(t)(C) ~ Dc * laplacian(C) - 0.1 * C + 0.1,
                L(t, x, y) ~ laplacian(C),
            ];
            name = :auxlap
        )
    end
    function plain()
        return pdesystem(
            [Differential(t)(C) ~ Dc * laplacian(C) - 0.1 * C + 0.1];
            name = :plain
        )
    end
    function robinu(a = u(t, x, y))
        return pdesystem(
            [
                Differential(t)(C) ~ Dc * laplacian(C), Differential(t)(u(t, x, y)) ~
                    -0.1 * u(t, x, y),
            ],
            [(1 + a) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 0.3]; name = :fac
        )
    end
    function nonlin()
        return pdesystem(
            [Differential(t)(C) ~ Dc * laplacian(C) - 0.1 * C^3];
            name = :nonlin
        )
    end
end

function check_op(dims = (24, 20))
    σ = zeros(Int32, dims)
    σ[5:8, 5:8] .= 1
    σ[14:17, 10:13] .= 2
    return [ownership => σ, kind => [:A, :A]]
end

@potts_model _CheckFrozen begin
    @structural_parameters variant = :fine
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    if variant === :fine
        @fields Check.att() (Check.sec => kind == A, Check.vol => volume[owner])
    elseif variant === :scaled
        @fields Check.scaled() (Check.w => 0.5 * volume[owner])
    elseif variant === :coarse
        @fields Check.coarse() (Check.sec => kind == A)
    elseif variant === :conserve
        @fields Check.conserve() (Check.sec => kind == A)
    else
        throw(ArgumentError("unknown frozen variant: $variant"))
    end
    @sweep Metropolis(; temperature = 4.0)
end

CheckFine(; name = :CheckFine, kw...) = _CheckFrozen(; variant = :fine, name, kw...)
CheckScaled(; name = :CheckScaled, kw...) = _CheckFrozen(; variant = :scaled, name, kw...)
CheckCoarse(; name = :CheckCoarse, kw...) = _CheckFrozen(; variant = :coarse, name, kw...)
function CheckConserve(; name = :CheckConserve, kw...)
    return _CheckFrozen(;
        variant = :conserve, name,
        kw...
    )
end

@potts_model _CheckLapSite begin
    @structural_parameters y_periodic = false
    @kinds medium A[frozen]
    @variables v(site) = 0.0
    @lattice Lattice((8, 8); boundary = y_periodic ? (Closed(), Periodic()) : Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = Check.lapsite()
    @after_mcs v ~ kind == A
    @sweep Metropolis(; temperature = 1.0)
end

function CheckLapSite(; name = :CheckLapSite, kw...)
    return _CheckLapSite(;
        y_periodic = false, name,
        kw...
    )
end
CheckLapMix(; name = :CheckLapMix, kw...) = _CheckLapSite(; y_periodic = true, name, kw...)

@potts_model CheckOde begin
    @kinds medium A
    @variables g(cell) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(g) ~ -0.1 * g
    @fields c = Check.plain()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _CheckSimple begin
    @structural_parameters variant = :hex
    @kinds medium A
    @lattice Lattice(
        (8, 8); geometry = variant === :hex ? Hexagonal() : CorePotts.Square(),
        boundary = Closed()
    )
    @energy cells(A) => (volume - 4.0)^2
    @fields c = variant === :hex ? Check.faces() : Check.xflux()
    @sweep Metropolis(; temperature = 1.0)
end

CheckHex(; name = :CheckHex, kw...) = _CheckSimple(; variant = :hex, name, kw...)
CheckNoX(; name = :CheckNoX, kw...) = _CheckSimple(; variant = :nox, name, kw...)

@potts_model CheckX begin
    @kinds medium A
    @variables x(cell) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields c = Check.xflux()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CheckAux begin
    @kinds medium A
    @lattice Lattice((20, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, L = Check.auxlap()
    @drive copy => -1.0 * (L[target] - L[source])
    @sweep Metropolis(; temperature = 4.0)
end

function check_round_trip(m, fs, f)
    integ = init(
        PottsProblem(m, check_op(), (0, 5); field_solver = fs, seed = 3),
        SequentialCPM()
    )
    for _ in 1:3
        step!(integ)
    end
    F = Potts.fields(m)
    prob = LatticePDE.discretize(
        F, LatticePDE.LatticeDiscretization(LatticePDE.Grid((24, 20)); T = Float64);
        inputs = collect(Potts.field_inputs(integ))
    )
    u0 = vec(Array(getproperty(current_state(integ).site, f)))
    o = LatticePDE.solve(
        LatticePDE.remake(prob; u0, tspan = (0.0, 1.0)), fs;
        dt = 1.0
    ).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(current_state(integ).site, f)))), integ
end

function check_names(m)
    return sort!(
        [
            String(Potts.LatticePDE.get_lattice_input_name(Potts.Symbolics.unwrap(d)))
                for d in Potts.fields(m).dvs
                if Potts.ModelingToolkitBase.isinput(Potts.Symbolics.unwrap(d))
        ]
    )
end

function check_owned(f)
    un = Potts.Symbolics.unwrap
    ics = [
        Potts.SymbolicUtils.operation(un(d))(0, Check.x, Check.y) ~ 0.0
            for d in f.dvs if !Potts.ModelingToolkitBase.isinput(un(d))
    ]
    return Potts.ModelingToolkitBase.PDESystem(
        f.eqs, [f.bcs; ics],
        LatticePDE.lattice_domain(Potts.t, (Check.x, Check.y), (24, 20)), f.ivs, f.dvs,
        f.ps; name = nameof(f)
    )
end

function check_pde_round_trip(m, pde, fs, f; op = check_op())
    integ = init(PottsProblem(m, op, (0, 5); field_solver = fs, seed = 3), SequentialCPM())
    for _ in 1:3
        step!(integ)
    end
    fi = Potts.field_inputs(integ, pde)
    prob = LatticePDE.discretize(
        check_owned(pde),
        LatticePDE.LatticeDiscretization(LatticePDE.Grid((24, 20)); T = Float64);
        inputs = collect(fi),
        u0 = [f => Array(getproperty(current_state(integ).site, f))], tspan = (0.0, 1.0)
    )
    o = LatticePDE.solve(prob, fs; dt = 1.0).u[end]
    step!(integ)
    return maximum(abs, o .- vec(Array(getproperty(current_state(integ).site, f)))), fi,
        integ
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
