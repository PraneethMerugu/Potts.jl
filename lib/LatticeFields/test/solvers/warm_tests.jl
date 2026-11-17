# F3-06 (F3 design §1.2 items 4–5, §2.5, §3.4 S15): the warm solve on the CPU.
#   - The host reduction fast path (`Schedule.host_reduce!`: the tree's idle items skipped,
#     blocks in chunks on threads) equals the emulated workgroups (`host_workgroups!`, the
#     HostExec of these tests) bitwise on every solver test case, at Float32 and Float64, and
#     whatever the chunk count.
#   - Plans are held per kind, budget and rotation: a warm rebuild + lift + solve allocates
#     0 B, and a sweep over 100 coefficient values keeps `sv.plans` at a constant size.
# Base (1079c4ff, ~/lpwork/f3b2-06nc-base.log): the warm rebuild + lift + solve allocates
# 11–12 KB (disk128 PCG 12,208 B; the plan key alone 3,520 B per lookup); the sweep keeps
# `sv.plans` at 8–11 (every value write drops all plans); no fast path exists, so the bitwise
# test passes trivially there. Negative controls on this tree: a tree that skips half of
# the first halving step fails the bitwise test; plans keyed by values and never dropped
# grow over the sweep.

@testsetup module LF_solvers_warm
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
include("../shared/solvers_coefficients.jl")
include("../shared/solvers_hierarchy.jl")
using LatticeFields.Solvers: set_coefficients!, tangent!
using LinearAlgebra: norm

"""
A test executor that runs every tree launch through `Schedule.host_reduce!` with `k`
chunks (serially at one thread, the region logic of the threaded path), the others as
HostExec.
"""
struct ChunkExec
    k::Int
end
Solvers.alloc(::ChunkExec, ::Type{T}, n) where {T} = zeros(T, n)
Solvers.to_host(::ChunkExec, A) = copy(A)
Schedule.supports(::ChunkExec, ::Type{Float64}) = true
Solvers.lds_regions(e::ChunkExec) = e.k
function Solvers.launch!(e::ChunkExec, l::Solvers.Launch)
    if l.wg == 0
        _hostrun(l.body, l.n, l.S, l.P, l.G)
    elseif l.tree
        Schedule.host_reduce!(l.body, l.n, l.wg, l.lds, l.ldslen, l.S, l.P, l.G; chunks = min(e.k, l.n))
    else
        Schedule.host_workgroups!(l.body, l.n, l.wg, l.phases, l.lds, l.S, l.P, l.G)
    end
    return nothing
end

function solved_on(exec, case, T; kw...)
    op, inputs = case
    sv = FieldSolver(exec, op; T, kw...)
    foreach(((k, v),) -> copyto!(field(sv, k), v), inputs)
    k = steady!(sv)
    return k, copy(field(sv, solution_key(sv))), scalars(sv), copy(field(sv, Solvers.working_key(sv)))
end

const KA_ = LatticeFields.Schedule.KernelAbstractions

warm!(sv) = (rebuild!(sv); lift!(sv); solve!(sv); nothing)
include("../shared/export_all.jl")
end

@testitem "the host reduction fast path equals the emulated workgroups bitwise" setup = [LF_solvers_warm] tags = [:latticefields, :solvers] begin
using .LF_solvers_warm: fd
@testset "the host reduction fast path equals the emulated workgroups bitwise" begin
    rng = Xoshiro(21)
    extra = (                                             # F3-05 operators
        "robin" => (CellOperator((40, 24); shift = 0.05, robin = (((0.4, 0.25, 0.3), (0.1, -1.0, 0.4)), (nothing, (1.0, 0.6, 0.2)))),
            ("in.f" => rand(rng, 960),)),
        "fieldface" => (CellOperator((40, 24); shift = 0.02, face = ("in.wx", "in.wy"), mask = "in.mask", value = "in.v",
                dirichlet = ((0.2, 1.0), (nothing, nothing))),
            ("in.f" => rand(rng, 960), "in.wx" => 0.5 .+ rand(rng, 960), "in.wy" => 0.5 .+ rand(rng, 960),
                "in.mask" => UInt8.(rand(rng, 960) .< 0.15), "in.v" => rand(rng, 960))))
    names = sort(unique(first.(collect(keys(REFERENCE)))))
    cases = [(n, named_case(n, (n, 0.022) in keys(REFERENCE) ? 0.022 : 5.5e-6)) for n in names]
    append!(cases, [(n, c) for (n, c) in extra])
    for (name, case) in cases, T in (Float32, Float64)
        n = prod(case[1].dims)
        inners = n <= 300 * 192 ? (:auto, Multigrid()) : (:auto,)
        for inner in inners
            inp = (case[1], Tuple(k => (k == case[1].mask ? v : T.(v)) for (k, v) in case[2]))
            ref = solved_on(HostExec(), inp, T; inner)
            for exec in (KA_.CPU(), ChunkExec(3))
                got = solved_on(exec, inp, T; inner)
                ok = got[1] == ref[1] && got[2] == ref[2] && got[3] == ref[3] && got[4] == ref[4]
                @test ok || (println("not bitwise: ", name, " ", T, " ", inner, " ", exec); false)
            end
        end
    end
end
end

@testitem "a warm rebuild + lift + solve allocates nothing" setup = [LF_solvers_warm] tags = [:latticefields, :solvers] begin
using .LF_solvers_warm: fd
@testset "a warm rebuild + lift + solve allocates nothing" begin
    for (case, kw) in ((named_case("disk128", 0.022), (;)), (named_case("disk128", 0.022), (; inner = Multigrid())),
        (named_case("sphere42", 0.022), (;)), (named_case("per128", 0.022), (;)),
        ((CellOperator((64, 64); shift = 0.05, robin = (((0.1, -1.0, 0.4), nothing), (nothing, nothing))), ()), (;)))
        for exec in (KA_.CPU(), HostExec())
            sv = FieldSolver(exec, case[1]; T = Float32, kw...)
            foreach(((k, v),) -> copyto!(field(sv, k), v), case[2])
            warm!(sv)
            warm!(sv)
            @test (@allocated warm!(sv)) == 0
            @test (@allocated Solvers._plan(Solvers.rebuild_plan, sv, :rebuild)) == 0
        end
    end
end
end

@testitem "a sweep over 100 coefficient values keeps sv.plans at a constant size" setup = [LF_solvers_warm] tags = [:latticefields, :solvers] begin
using .LF_solvers_warm: fd
@testset "a sweep over 100 coefficient values keeps sv.plans at a constant size" begin
    op, inputs = box_case(64, 32; s = 0.01, islands = 0.1)
    sv = case_solver((op, inputs), Float64; inner = DevicePCG(; maxiters = 64, reltol = 1e-10))
    sizes = Int[]
    for (i, s) in enumerate(range(0.005, 0.05; length = 100))
        set_coefficients!(sv, CellOperator(op.dims; periodic = op.periodic, shift = s, mask = op.mask,
            value = op.value, dirichlet = ((0.0, 1.0 + s), (nothing, nothing))))
        steady!(sv)
        warm!(sv)
        u = Solvers.solver_solution(sv)
        tangent!(sv, u, :shift)
        push!(sizes, length(sv.plans))
    end
    # one plan per kind, budget and rotation: the rotation a solve ends in varies with its
    # iteration count, so the size takes a few values, bounded and not growing
    @test maximum(sizes[51:end]) <= maximum(sizes[1:50]) <= 6 || (println("sv.plans sizes: ", sizes); false)
end
end

# F3-05/06 review r1 S4: the values are not in the plan key, so a coefficient write must drop
# the held plans (`empty!` in `_set_raw!`). After `set_coefficients!`, `steady!` and a tangent
# equal a solver built fresh at the new values, bitwise. Negative control (~/lpwork/f3b2r1-nc-s4.log):
# without the `empty!`, the written solver solves with its first values: 30 of the 48 checks fail
# (`steady!` off by up to 0.14 in 14, both executors; all 16 tangents miss the difference quotient);
# base 9db10886 passes (no test of it existed).
@testitem "a coefficient write takes effect: steady! and tangent! equal a fresh solver bitwise" setup = [LF_solvers_warm] tags = [:latticefields, :solvers] begin
using .LF_solvers_warm: fd
@testset "a coefficient write takes effect: steady! and tangent! equal a fresh solver bitwise" begin
    op0, inputs = box_case(64, 32; s = 0.01, islands = 0.1)
    mk(s, d = 1.0 + s) = CellOperator(op0.dims; periodic = op0.periodic, shift = s, mask = op0.mask, value = op0.value,
        dirichlet = ((0.0, d), (nothing, nothing)))
    rob(β, _ = nothing) = CellOperator((40, 24); shift = 0.05, robin = (((0.4, β, 0.3), (0.1, -1.0, 0.4)), (nothing, nothing)))
    for exec in (HostExec(), KA_.CPU()), inner in (:auto, Multigrid()),
        (make, vals, coef) in ((mk, (0.01, 0.035, 0.02), :shift), (rob, (0.25, 0.6, 0.4), (:robin, 1, 1, :beta)))
        inp = make === mk ? inputs : ()
        function built(o)
            s = FieldSolver(exec, o; T = Float64, inner)
            foreach(((k, v),) -> copyto!(field(s, k), v), inp)
            return s
        end
        sv = built(make(vals[1]))
        steady!(sv)
        for b in vals[2:end]                       # two writes: the second after a tangent
            set_coefficients!(sv, make(b))
            fresh = built(make(b))
            k, kf = steady!(sv), steady!(fresh)
            u, uf = copy(Solvers.solver_solution(sv)), copy(Solvers.solver_solution(fresh))
            @test sv !== fresh && (k == kf && u == uf) ||
                  (println("steady! differs: ", make, " ", b, " ", exec, " ", inner, " ", maximum(abs.(u .- uf))); false)
            du, duf = copy(tangent!(sv, u, coef)), copy(tangent!(fresh, uf, coef))
            @test du == duf ||
                  (println("tangent! differs: ", make, " ", b, " ", exec, " ", inner, " ", maximum(abs.(du .- duf))); false)
            # and both are the derivative: a central difference of two tight fresh solves (a
            # stale perturbed plan gives du = 0 in both)
            function tight(o)                      # only `coef` moves: the face value stays 1 + b
                ft = FieldSolver(exec, o; T = Float64, inner = DevicePCG(; reltol = 1e-12, maxiters = 256))
                foreach(((k, v),) -> copyto!(field(ft, k), v), inp)
                steady!(ft)
                return copy(Solvers.solver_solution(ft))
            end
            ε = 1e-4 * b
            fd = (tight(make(b + ε, 1.0 + b)) .- tight(make(b - ε, 1.0 + b))) ./ (2ε)
            @test norm(du .- fd) <= 1e-3 * norm(fd) || (println("tangent! is not the derivative: ", make, " ", b, " ", exec,
                " ", inner, " ", norm(du .- fd) / norm(fd)); false)
        end
    end
end
end
