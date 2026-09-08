# [Model library](@id model-library)

PottsModels.jl owns complete scientific model factories, initializers,
model-building tutorials and model-level tests. Potts owns the authoring
interface and its minimal behavioral examples, not a duplicate model library.

The sibling `PottsModels.jl` checkout contains executable activity-migration,
field-coupled vasculogenesis and monolayer-division tutorials in its `tutorials/`
directory; its manual starts at `docs/src/index.md` and is built with
`docs/make.jl`. These are bounded sequential CPU demonstrations, not calibrated
paper reproductions or generic backend guarantees.

Each factory returns ordinary `system`, `initial` and symbolic `quantities`.
The caller chooses the problem duration, seed, algorithm, precision, backend and
saving policy through public Potts/SciML interfaces. Models does not supply a
second compiler or numerical executor, and it is not a runtime dependency of
Potts or CorePotts.

For the authoring interface itself, start with [Build a custom model](@ref
custom-model). Its complete executable example stays in Potts alongside
the tests defending its API and continuation behavior.
