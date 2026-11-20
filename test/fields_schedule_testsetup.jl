@testsetup module FieldsScheduleSetup
using Potts, Test

module FsSchedPDE
    using Potts
    include(joinpath(@__DIR__, "shared", "field_pde.jl"))
    using .FieldPDE
    @variables c(..) kA(..)::Bool [input = true]
    const C, KA = c(t, x, y), kA(t, x, y)
    chemo() = (@parameters Dc = 0.2; pdesys([Dt(C) ~ Dc * laplacian(C) + 0.5 * KA - 0.1 * C], [c(0, x, y) ~ 0.0], (24, 20), [C, KA], [Dc]))
    source() = (@parameters Dc = 0.2 s = 0.05; pdesys([Dt(C) ~ Dc * laplacian(C) + s * KA], [c(0, x, y) ~ 0.0], (12, 10), [C, KA], [Dc, s]))
end

const FD_THREADS_RUN = raw"""
using Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: laplacian, lattice_domain
@parameters x y Dc = 0.2
@variables c(..)
const FD_BIG = PDESystem([Differential(Potts.t)(c(Potts.t, x, y)) ~ Dc * laplacian(c(Potts.t, x, y))], [c(0, x, y) ~ 0.0],
    lattice_domain(Potts.t, (x, y), (120, 100)), [Potts.t, x, y], [c(Potts.t, x, y)], [Dc]; name = :fields)
@potts_model FdBig begin
    @kinds medium A
    @lattice Lattice((120, 100); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FD_BIG
    @sweep Metropolis(; temperature = 1.0)
end
function fd_threads_run()
    c0 = [sin(i / 7) * cos(j / 5) for i in 1:120, j in 1:100]
    prob = PottsProblem(FdBig(; name = :b), [ownership => zeros(Int32, 120, 100), kind => Symbol[], :c => c0], (0, 20);
        field_solver = ExplicitEuler())
    integ = init(prob, SequentialCPM(); save_start = false, save_end = false, save_everystep = false)
    step!(integ); step!(integ)
    a = minimum(_ -> (@allocated step!(integ)), 1:3)
    return a, hash(Array(current_state(integ).site.c))
end
a, h = fd_threads_run()
print(Threads.nthreads(), " ", a, " ", h)
"""

@potts_model FdChemo begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = FsSchedPDE.chemo() (FsSchedPDE.kA => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model _FdChemoSched begin
    @structural_parameters mode = :plain
    @extend base = FdChemo()
    if mode === :plain
        @schedule sweep, fields
    elseif mode === :split
        @schedule repeat(4, sweep(fraction = 1 // 4), after_mcs), fields
    elseif mode === :inter
        @schedule repeat(4, sweep(fraction = 1 // 4), fields)
    else
        throw(ArgumentError("unknown _FdChemoSched mode: $mode"))
    end
end

FdChemoPlain(; name = :FdChemoPlain, kw...) = _FdChemoSched(; mode = :plain, name, kw...)
FdChemoSplit(; name = :FdChemoSplit, kw...) = _FdChemoSched(; mode = :split, name, kw...)
FdChemoInter(; name = :FdChemoInter, kw...) = _FdChemoSched(; mode = :inter, name, kw...)

@potts_model _FdSourceBase begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsSchedPDE.source() (FsSchedPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdSourceInter begin
    @extend base = _FdSourceBase()
    @schedule repeat(4, sweep(fraction = 1 // 4), fields)
end

function fd_chemo_op()
    σ = zeros(Int32, 24, 20)
    σ[5:8, 5:8] .= 1
    σ[14:17, 10:13] .= 2
    return [ownership => σ, kind => [:A, :A], :c => [0.05 * i for i in 1:24, j in 1:20]]
end

@potts_model MomentVetoBase begin
    @kinds medium A
    @variables x0(cell) = 0.0
    @lattice Lattice((24, 24))
    @energy cells => (volume - 40.0)^2
    @constraint connectivity(A; rule = Global(; window = 1))
    @after_mcs x0 ~ centroid(1)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model _MomentVetoRun begin
    @structural_parameters split = false
    @extend base = MomentVetoBase()
    if split
        @schedule repeat(4, sweep(fraction = 1 // 4)), after_mcs
    else
        @schedule sweep, after_mcs
    end
end

MomentVetoPlain(; name = :MomentVetoPlain, kw...) = _MomentVetoRun(; split = false, name, kw...)
MomentVetoSplit(; name = :MomentVetoSplit, kw...) = _MomentVetoRun(; split = true, name, kw...)

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
