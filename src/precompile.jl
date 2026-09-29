# Precompile the symbolic pipeline (macro-built system → mtkcompile → code generation) on a
# small model, so the first `PottsProblem` of a session does not compile Symbolics' paths.
PrecompileTools.@setup_workload begin
    PrecompileTools.@compile_workload begin
        (; volume, surface, kind, kind′, owner, source, target, old, new) = B
        λ = parameter(:λ, 1.0)
        V₀ = parameter(:V₀, 20.0)
        T = parameter(:T, 10.0)
        J = kind_parameter(:J, [0 16; 16 2])
        c = variable(only(Symbolics.@variables c(t)), :field; default = 0.0)
        a = variable(only(Symbolics.@variables a(t)), :site; default = 0.0)
        sys = PottsSystem(; name = :precompile, kinds = [:medium, :cell],
            lattice = lattice_spec((16, 16); neighborhood = Moore(1)), parameters = Any[λ, V₀, T, J],
            variables = Any[c, a],
            energies = [energy(cells(1) => λ * (volume - V₀)^2 + λ * (surface - V₀)^2),
                energy(contacts => _index(J, kind, kind′))],
            drives = [drive(COPY => ifelse(_index(kind, new) == 1, -λ * (_index(c, target) - _index(c, source)), 0.0))],
            constraints = [connectivity(1)],
            updates = [update(:after_mcs, a ~ max(Pre(a) - 1, 0)), update(:on_copy, _index(a, target) ~ λ)],
            equations = [D(c) ~ λ * Δ(c) - λ * c],
            sweep = sweep_spec(:metropolis; temperature = T))
        csys = ModelingToolkitBase.mtkcompile(sys)
        σ = zeros(Int32, 16, 16)
        σ[4:8, 4:8] .= 1
        for S in (Float64, Float32)
            PottsProblem(csys, [CorePotts.ownership => σ, B.kind => [1]], (0, 1); T = S, expression = Val(true))
        end
    end
end
