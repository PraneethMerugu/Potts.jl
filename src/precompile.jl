# Precompile the symbolic pipeline (macro-built system → mtkcompile → code generation) on a
# small model, so the first `PottsProblem` of a session does not compile Symbolics' paths.
# `_PrecompileModel` goes through `@potts_model` (its expansion, the generated constructor's
# build scope and `PottsSystem` keywords, the first MCS), which every user model shares.
# Its cell ODE with an algebraic equation takes the first MTK `System` and `mtkcompile` of a
# session (odes.jl): loading Potts invalidates MTK's own precompiled `mtkcompile` (≈ 1.2 s).
# Its `@initialization_equations` take the first initialization `System`, MTK
# `InitializationProblem` and solves of a session (initialization.jl; ≈ 9 s cold): a linear
# model pair (MTK's linear initialization problem) and cells with an explicit and a
# nonlinear condition (a solve from the guess); with `explicit_init = true`, explicit
# conditions only (MTK's observed values). Initialization changes no kernel, so the second
# build reuses the first one's compiled code. Its field `c` is a plain PDESystem coupled with
# `@fields` (`_precompile_fields`), whose input `src` is bound to `kind == cell`; it runs a first
# MCS with `ExplicitEuler` and with `BackwardEuler`, and prints its `field_report`.
#
# The field of the precompile models: `D(c) ~ D_c Δc + src − c` on an `N`-dimensional lattice
# (the domain is left out: each axis takes the lattice's interval)
function _precompile_fields(N::Int)
    xs = (FIELD_NAMES.x, FIELD_NAMES.y, FIELD_NAMES.z)[1:N]
    D_c = only(ModelingToolkitBase.@parameters D_c = 0.1)
    c, src = ModelingToolkitBase.@variables c(..) = 0.0 src(..)::Bool [input = true]
    C = c(t, xs...)
    return LatticePDE.pdesystem([Differential(t)(C) ~ D_c * laplacian(C) + src(t, xs...) - C]; name = :precompile_fields)
end
@potts_model _PrecompileModel begin
    @structural_parameters begin
        lattice = (16, 16)
        explicit_init = false
    end
    @kinds medium cell
    @parameters begin
        λ = 1.0
        V₀ = 20.0
        T = 10.0
        J[kind, kind] = [0.0 16.0; 16.0 2.0]
    end
    @variables begin
        V_target(cell) = V₀
        x(cell) = 1.0
        x_rate(cell) = 0.0
        s₀(cell)
        q(cell), [guess = 1.0]
        m₀(model)
        m₁(model)
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @fields c = Potts._precompile_fields(length(lattice)) (src => kind == cell)
    @energy begin
        cells(cell) => λ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @drive copy => -λ * (c[target] - c[source])
    @equations begin
        D(x) ~ -x_rate
        x_rate ~ x / T
    end
    if explicit_init
        @initialization_equations begin
            m₀ ~ 2V₀
            s₀ ~ volume / m₀ + id
        end
    else
        @initialization_equations begin
            m₀ + m₁ ~ 3V₀
            m₀ - m₁ ~ V₀
            s₀ ~ volume / m₀ + id
            q^2 ~ volume + s₀
        end
    end
    @after_mcs V_target ~ Pre(V_target) + V₀ / T
    @divide cells(cell) when = volume >= 2V₀, along = RandomPlane(), V_target => V₀
    @sweep Metropolis(; temperature = T)
end
# The workload: also run by the AMDGPU extension (PottsAMDGPUExt), since loading AMDGPU
# invalidates much of this cache (Symbolics, GPUArrays and BFloat16s methods; PG-11)
function _precompile_workload()
    (; volume, surface, kind, kind′, owner, source, target, old, new) = B
    λ = parameter(:λ, 1.0)
    V₀ = parameter(:V₀, 20.0)
    T = parameter(:T, 10.0)
    J = kind_parameter(:J, [0 16; 16 2])
    mark = variable(only(Symbolics.@variables mark(t)), :site; default = 0.0)
    host = PottsSystem(; name = :precompile, kinds = [:medium, :cell],
        lattice = lattice_spec((16, 16); neighborhood = Moore(1)), parameters = Any[λ, V₀, T, J],
        variables = Any[mark],
        energies = [energy(cells(1) => λ * (volume - V₀)^2 + λ * (surface - V₀)^2),
            energy(contacts => _index(J, kind, kind′))],
        drives = [drive(COPY => ifelse(_index(kind, new) == 1, -λ * (_index(mark, target) - _index(mark, source)), 0.0))],
        constraints = [connectivity(1)],
        updates = [update(:after_mcs, mark ~ max(Pre(mark) - 1, 0)), update(:on_copy, _index(mark, target) ~ λ)],
        sweep = sweep_spec(:metropolis; temperature = T))
    sys = couple(host, _precompile_fields(2); inputs = [:src => kind == 1])
    csys = ModelingToolkitBase.mtkcompile(sys)
    σ = zeros(Int32, 16, 16)
    σ[4:8, 4:8] .= 1
    for S in (Float64, Float32)
        generated_code(csys; T = S, field_solver = ExplicitEuler())
        PottsProblem(csys, [CorePotts.ownership => σ, B.kind => [1]], (0, 1); T = S, field_solver = ExplicitEuler())
    end
    # the coupled `@fields` model: init and a first MCS with each owned field algorithm, and
    # its field report (F4-14)
    csys2 = mtkcompile(_PrecompileModel(; name = :precompile))
    for fs in (ExplicitEuler(), BackwardEuler())
        prob = PottsProblem(csys2, [CorePotts.ownership => σ, B.kind => [:cell]], (0, 1); field_solver = fs, capacity = 8)
        integ = init(prob, CorePotts.SequentialCPM(); save_start = false)
        step!(integ)
        field_report(devnull, integ)
    end
    # Float32 on a 3D lattice under CheckerboardCPM (the device configuration, run here on
    # the host): the field compiler's 3D Float32 lowering and the checkerboard sweep
    σ3 = zeros(Int32, 8, 8, 8)
    σ3[3:5, 3:5, 3:5] .= 1
    prob3 = PottsProblem(mtkcompile(_PrecompileModel(; name = :precompile, lattice = (8, 8, 8))),
        [CorePotts.ownership => σ3, B.kind => [:cell]], (0, 1); T = Float32, field_solver = ExplicitEuler(), capacity = 8)
    step!(init(prob3, CorePotts.CheckerboardCPM(); save_start = false))
    PottsProblem(mtkcompile(_PrecompileModel(; name = :precompile, explicit_init = true)),
        [CorePotts.ownership => σ, B.kind => [:cell]], (0, 1); field_solver = ExplicitEuler(), capacity = 8)
    return nothing
end
PrecompileTools.@setup_workload begin
    PrecompileTools.@compile_workload begin
        _precompile_workload()
    end
end
