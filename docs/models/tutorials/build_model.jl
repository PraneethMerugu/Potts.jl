using PottsToolkit

medium = Medium(:medium)
first_population = CellType(:first_population)
second_population = CellType(:second_population)
model = PottsModel(
    medium,
    first_population,
    second_population,
    Volume(
        first_population => (target = 16, strength = 2),
        second_population => (target = 16, strength = 2),
    ),
    Adhesion(
        (medium, medium) => 0,
        (medium, first_population) => 8,
        (medium, second_population) => 8,
        (first_population, first_population) => 2,
        (second_population, second_population) => 2,
        (first_population, second_population) => 15,
    ),
)
normalized = normalize(model)
fingerprint = semantic_fingerprint(normalized)

@assert isvalid(model)
@assert semantic_fingerprint(model) == fingerprint
result = (; model, normalized, fingerprint, report = validate(model))
