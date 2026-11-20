# Top-level definitions for solvers test suites (`solvers_tests.jl`,
# `solvers_canonical_tests.jl`, `solvers_validation_tests.jl`).

@testsetup module SolversSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using PottsModels: GranerGlazier, OpenVTGrowingMonolayer
using OrdinaryDiffEqTsit5: Tsit5

# y' = −s, s' = y − s, listed in both orders. With `s => Potts.RK4()` and y under explicit
# Euler the two run in separate groups; Jacobi means each step reads (y, s) at its start.
@potts_model SolverPairYS begin
    @kinds medium A
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -s
        D(s) ~ y - s
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model SolverPairSY begin
    @kinds medium A
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(s) ~ y - s
        D(y) ~ -s
    end
    @sweep Metropolis(; temperature = 1.0)
end

# three groups in the cell scope (Euler, RK4, adaptive) and two in the model scope
@potts_model SolverTriple begin
    @kinds medium A
    @variables begin
        y(cell) = 1.0
        s(cell) = 0.0
        w(cell) = 0.5
        g(model) = 1.0
        h(model) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -s
        D(s) ~ y - s
        D(w) ~ -0.2 * w + 0.1 * y
        D(g) ~ -h
        D(h) ~ g - h
    end
    @sweep Metropolis(; temperature = 1.0)
end

isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module SvPDE
    using ..FieldPDE
    @variables c(..)
    const C = c(t, x, y)
    function decay(dims, k, c0 = 0.0; D = 0.1)
        return pdesys(
            [Dt(C) ~ D * laplacian(C) - k * C], [
                c(0, x, y) ~
                    c0,
            ], dims, [C]
        )
    end
    function field()
        @parameters Dc = 0.1
        return pdesys(
            [Dt(C) ~ Dc * laplacian(C) - 0.05 * C], [c(0, x, y) ~ 0.0], (16, 16), [C],
            [Dc]
        )
    end
end

@potts_model SolverField begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @fields SvPDE.field()
    @sweep Metropolis(; temperature = 1.0)
end

solver_sigma() = (σ = zeros(Int32, 16, 16); σ[5:8, 5:8] .= 1; σ)
solver_op() = [ownership => solver_sigma(), kind => [:A]]
function solver_var(sys, n)
    return only(
        filter(
            x -> string(x) in (string(n), string(n, "(t)")), Potts.declared_variables(sys)
        )
    )
end

function solver_err(f)
    return try
        f()
        nothing
    catch e
        e
    end
end

function sv_throws(T, pats, f)
    err = try
        f()
        nothing
    catch e
        e
    end
    @test err isa T
    return err
end

const RK4_DECAY = 1 - 1 + 1 / 2 - 1 / 6 + 1 / 24

function pair_oracle(n)
    y, s = 1.0, 0.0
    for _ in 1:n
        y, s = y - s, y + (s - y) * RK4_DECAY
    end
    return y, s
end

solver_warm(integ) = (step!(integ); @allocated step!(integ))

@enum SolverPredictor SolverTrivial SolverLinear

struct SolverFakeAlg{P, F, K}
    predictor::P
    limiter::F
    knobs::K
end

solver_limiter(c) = (u, i, p, t) -> (u .= max.(u, c); nothing)

two_cells() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)

@potts_model _OwnUnknown begin
    @structural_parameters begin
        by_id = true
    end
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    if by_id
        @equations D(y) ~ -y[id]
    else
        @equations D(y) ~ -y
    end
    @sweep Metropolis(; temperature = 1.0e-6)
end

OwnUnknownIndex(; name = :OwnUnknownIndex, kw...) = _OwnUnknown(; by_id = true, name, kw...)
function OwnUnknownPlain(; name = :OwnUnknownPlain, kw...)
    return _OwnUnknown(;
        by_id = false, name,
        kw...
    )
end

@potts_model JacobiGather begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ maximum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - y
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model IndexLocal begin
    @kinds medium A
    @variables begin
        y(cell) = 0.0
        w(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ w[ifelse(y > 0.5, id, 3 - id)]
    @sweep Metropolis(; temperature = 1.0e-6)
end

# D-118: `mcs_duration` models parameterized cleanly without function-local `@potts_model`
@potts_model MdODE begin
    @structural_parameters begin
        md = 1.0
    end
    @kinds medium A
    @variables y(cell) = 1.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations D(y) ~ -y
    @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
end
md_ode_model(md) = MdODE(; name = :ad, md)

@potts_model MdField begin
    @structural_parameters begin
        md = 1.0
    end
    @kinds medium A
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @fields SvPDE.decay((12, 12), 0.05)
    @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
end
md_field_model(md) = MdField(; name = :fd, md)

# D-122: thin periodic lattices parameterized via `@structural_parameters`
@potts_model ThinStrip begin
    @structural_parameters begin
        dims = (2, 12)
        contact = Moore(1)
        nbhd = VonNeumann(1)
    end
    @kinds medium A
    @lattice Lattice(dims; neighborhood = nbhd)
    @relations begin
        proposal = Stencil([[0, 1], [0, -1]])
        contact = contact
    end
    @energy cells => (volume - 4.0)^2
    @energy contacts => 1.0
    @sweep Metropolis(; temperature = 2.0)
end
thin_model(dims, contact, nbhd) = ThinStrip(; name = :t, dims, contact, nbhd)

include(joinpath(@__DIR__, "shared", "solver_types.jl"))

struct SolverDeep
    a::Any
end

solver_nest(k) = k == 0 ? 1.0 : SolverDeep(solver_nest(k - 1))

@potts_model SolverDeepRel begin
    @structural_parameters begin
        rel = Moore(1)
    end
    @kinds medium A
    @variables q(site) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2 + 0.1 * volume * sum(q[n] for n in rel(40))
    @sweep Metropolis(; temperature = 1.0)
end

"""A model with an inline gather relation whose weight closure captures `solver_nest(k)`,
compiled; returns the compiled system or the unwrapped exception."""
function solver_deep_relation(k)
    R = let d = solver_nest(k)
        Weighted(Moore(1), o -> d isa SolverDeep ? 1.0 : 2.0)
    end
    compiled = Ref{Any}(nothing)
    e = solver_err() do
        compiled[] = mtkcompile(SolverDeepRel(; name = :x, rel = R))
    end
    e === nothing && return compiled[]
    while e isa LoadError
        e = e.error
    end
    return e
end

@potts_model ReachBoundaryFar begin
    @kinds medium A
    @variables z(cell) = 0.0
    @lattice Lattice((12, 12))
    @relations far = EuclideanBall(2.0)
    @energy cells => (volume - 9.0)^2
    @after_mcs z ~ count(owner[n] == id for n in far(40))
    @sweep Metropolis(; temperature = 2.0)
end

@potts_model SolverOneField begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells(A) => (volume - 9)^2
    @fields SvPDE.decay((8, 8), 0.5, 1.0)
    @sweep Metropolis(; temperature = 1.0)
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
