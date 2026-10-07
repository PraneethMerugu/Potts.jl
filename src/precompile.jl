# Precompile the symbolic pipeline (macro-built system → mtkcompile → code generation) on a
# small model, so the first `PottsProblem` of a session does not compile Symbolics' paths.
# `_PrecompileModel` goes through `@potts_model` (its expansion, the generated constructor's
# build scope and `PottsSystem` keywords, the first MCS), which every user model shares.
# Its cell ODE with an algebraic equation takes the first MTK `System` and `mtkcompile` of a
# session (odes.jl): loading Potts invalidates MTK's own precompiled `mtkcompile` (≈ 1.2 s).
@potts_model _PrecompileModel begin
    @structural_parameters begin
        lattice = (16, 16)
    end
    @kinds medium cell
    @parameters begin
        λ = 1.0
        V₀ = 20.0
        D_c = 0.1
        T = 10.0
        J[kind, kind] = [0.0 16.0; 16.0 2.0]
    end
    @variables begin
        V_target(cell) = V₀
        c(field) = 0.0
        x(cell) = 1.0
        x_rate(cell) = 0.0
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cell) => λ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @drive copy => -λ * (c[target] - c[source])
    @equations begin
        D(c) ~ D_c * Δ(c) + (kind == cell) - c
        D(x) ~ -x_rate
        x_rate ~ x / T
    end
    @after_mcs V_target ~ Pre(V_target) + V₀ / T
    @divide cells(cell) when = volume >= 2V₀, along = RandomPlane(), V_target => V₀
    @sweep Metropolis(; temperature = T)
end
PrecompileTools.@setup_workload begin
    PrecompileTools.@compile_workload begin
        (; volume, surface, kind, kind′, owner, source, target, old, new) = B
        λ = parameter(:λ, 1.0)
        V₀ = parameter(:V₀, 20.0)
        T = parameter(:T, 10.0)
        J = kind_parameter(:J, [0 16; 16 2])
        c = variable(only(Symbolics.@variables c(t)), :field; default = 0.0)
        mark = variable(only(Symbolics.@variables mark(t)), :site; default = 0.0)
        sys = PottsSystem(; name = :precompile, kinds = [:medium, :cell],
            lattice = lattice_spec((16, 16); neighborhood = Moore(1)), parameters = Any[λ, V₀, T, J],
            variables = Any[c, mark],
            energies = [energy(cells(1) => λ * (volume - V₀)^2 + λ * (surface - V₀)^2),
                energy(contacts => _index(J, kind, kind′))],
            drives = [drive(COPY => ifelse(_index(kind, new) == 1, -λ * (_index(c, target) - _index(c, source)), 0.0))],
            constraints = [connectivity(1)],
            updates = [update(:after_mcs, mark ~ max(Pre(mark) - 1, 0)), update(:on_copy, _index(mark, target) ~ λ)],
            equations = [D(c) ~ λ * Δ(c) - λ * c],
            sweep = sweep_spec(:metropolis; temperature = T))
        csys = ModelingToolkitBase.mtkcompile(sys)
        σ = zeros(Int32, 16, 16)
        σ[4:8, 4:8] .= 1
        for S in (Float64, Float32)
            generated_code(csys; T = S, field_solver = ExplicitEuler())
            PottsProblem(csys, [CorePotts.ownership => σ, B.kind => [1]], (0, 1); T = S, field_solver = ExplicitEuler())
        end
        prob = PottsProblem(mtkcompile(_PrecompileModel(; name = :precompile)), [CorePotts.ownership => σ, B.kind => [:cell]],
            (0, 1); field_solver = ExplicitEuler(), capacity = 8)
        step!(init(prob, CorePotts.SequentialCPM(); save_start = false))
    end
end
