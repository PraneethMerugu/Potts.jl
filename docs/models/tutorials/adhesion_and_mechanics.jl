using PottsToolkit

model = PottsToolkit.ReferenceModels.elongation_driven_angiogenesis_model(
    target_volume = 8,
    target_elongation = 2,
    elongation_strength = 4,
    preserve_connectivity = true,
)
problem = PottsToolkit.ReferenceModels.elongation_driven_angiogenesis_problem(
    (12, 12);
    cells = 2,
    target_volume = 8,
    target_elongation = 2,
    elongation_strength = 4,
    capacity = 4,
    tspan = (0, 1),
    seed = 5,
)

@assert isvalid(model)
@assert backend_report(problem, SequentialCPM()).qualified
result = (; model, problem, declarations = length(model.declarations),
    capabilities = capabilities(model))
