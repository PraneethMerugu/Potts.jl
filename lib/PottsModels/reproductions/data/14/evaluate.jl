# Recompute every row of a Fortuna record from its TSVs: the files, provenance, the order
# of the c calibration, the run set, seeds and cadence, the oracle, the regimes, MSDs and
# fits, and every verdict. A failing gating row passes only as a `deviations.tsv` entry
# (`@test_broken`). The protocol comes from the installed PottsModels, so a copy of this
# file inside a record directory works too.
#
# Usage, from the checkout root:
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/14/evaluate.jl <record dir>
using Potts, PottsModels, Test

length(ARGS) == 1 || error("usage: evaluate.jl <record dir>")
const DIR = abspath(ARGS[1])
isdir(DIR) || error("evaluate.jl: $DIR is not a directory")
include(joinpath(pkgdir(PottsModels), "reproductions", "data", "14", "protocol.jl"))
@testset "Fortuna record: $DIR" begin
    FortunaProtocol.check_record(DIR)
end
