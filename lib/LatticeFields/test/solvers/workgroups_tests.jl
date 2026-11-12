# Workgroup launches (contract item 5): reductions, the finishing pass, the bottom and the
# Gershgorin pass are races-free (items run backwards give the same bits) and the device
# wrapper (KernelAbstractions, run here on its CPU backend as a cross-check only) gives the
# same bits as the host form.

const KA = LatticeFields.Schedule.KernelAbstractions

"""
A test executor: workgroup launches through the device wrapper on the KA CPU backend.
"""
struct KAExec end
Solvers.alloc(::KAExec, ::Type{T}, n) where {T} = zeros(T, n)
Solvers.fetch(::KAExec, A) = (KA.synchronize(KA.CPU()); copy(A))
Schedule.supports(::KAExec, ::Type{Float64}) = true
function Solvers.launch!(::KAExec, l::Solvers.Launch)
    if l.wg == 0
        _hostrun(l.body, l.n, l.S, l.P, l.G)
    else
        KA.synchronize(KA.CPU())
        Schedule.workgroups!(KA.CPU(), l.body, l.n, l.wg, l.phases, eltype(l.lds),
            l.ldslen, l.S, l.P, l.G)
        KA.synchronize(KA.CPU())
    end
    return nothing
end

function solved(case, exec; kw...)
    op, inputs = case
    sv = FieldSolver(exec, op; T = Float32, kw...)
    foreach(((k, v),) -> copyto!(field(sv, k), v), inputs)
    k = steady!(sv)
    return k, copy(field(sv, Solvers.solution_key(sv))), scalars(sv)
end

@testset "workgroup launches: reversed items give the same bits" begin
    for (case, kw) in ((named_case("sphere42", 0.022), (;)),
        (named_case("per256", 0.022), (;)),
        (named_case("disk128", 1.9e-3), (; inner = Multigrid())))
        a = solved(case, HostExec(); kw...)
        HOST_REVERSE[] = true
        b = try
            solved(case, HostExec(); kw...)
        finally
            HOST_REVERSE[] = false
        end
        @test a[1] == b[1] && a[2] == b[2]
    end
end

@testset "device wrapper on the KA CPU backend equals the host form" begin
    for (case, kw) in ((named_case("disk128", 0.022), (;)),
        (named_case("per128", 0.022), (;)))
        a, b = solved(case, HostExec(); kw...), solved(case, KAExec(); kw...)
        @test a[1] == b[1] && a[2] == b[2] && a[3] == b[3]
    end
end

@testset "Exec runs the solvers: the KA CPU backend as executor equals the host form" begin
    # the production executor protocol (alloc, fetch, launch!, supports on a KA backend)
    for (case, kw) in ((named_case("disk128", 0.022), (;)), (named_case("per128", 0.022), (;)))
        a, b = solved(case, HostExec(); kw...), solved(case, KA.CPU(); kw...)
        @test a[1] == b[1] && a[2] == b[2] && a[3] == b[3]
    end
    # capability: the host executor has Float64, so `:auto` takes it for an unanchored weak group
    @test Schedule.supports(KA.CPU(), Float64)
    @test FieldSolver(KA.CPU(), named_case("per256", 5.5e-6)[1]; T = Float32).T == Float64
end
