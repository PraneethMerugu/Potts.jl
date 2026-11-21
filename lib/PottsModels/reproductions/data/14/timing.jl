# The cost of the Fortuna F-actin field step against the whole MCS, at R = 15, φ_l = 0.10,
# λ_F = 150, c = 0.1 and `ExplicitEuler(substeps = 1)` (the protocol's problem). After 20
# warm MCS it prints the median of 60 calls of the field phase alone and the median of 30
# whole MCS (`step!`), in ms.
#
# The field phase is timed through internals (the integrator context's field runtimes), so
# this script may need an update when they change; the whole-MCS time uses public API only.
#
# Usage, from the checkout root:
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/14/timing.jl
using Potts, PottsModels, Printf
using Potts: CorePotts, LatticeFields

median_of(xs) = sort(xs)[cld(length(xs), 2)]
const R, φ = 15, 0.1
sys = FortunaMigration(; name = :fortuna, lattice = fortuna_lattice(R, φ))
op = [fortuna_layout(R, φ, sys); :R => Float64(R); :φ_l => φ; :λ_F => 150.0; :c => 0.1]
prob = PottsProblem(sys, op, (0, 200); seed = 1, field_solver = ExplicitEuler(substeps = 1))
integ = init(prob, SequentialCPM(); save_everystep = false, save_start = false, save_end = false)
foreach(_ -> step!(integ), 1:20)

# the field phases' runtimes (one per field group)
keys_ = [n for n in propertynames(integ.ctx) if occursin(r"^__fields\d+$", string(n))]
runtimes = [CorePotts._runtime(getfield(integ.ctx, k)) for k in keys_]
field_ms = Float64[]
for i in 1:60
    q = time_ns()
    for rt in runtimes
        LatticeFields.Problems.advance!(rt, (20.0 + i, 20 + i))
    end
    push!(field_ms, (time_ns() - q) / 1.0e6)
end
mcs_ms = Float64[]
for _ in 1:30
    q = time_ns()
    step!(integ)
    push!(mcs_ms, (time_ns() - q) / 1.0e6)
end
@printf(
    "Fortuna timing: threads = %d, field_step_ms %.3f (min %.3f), mcs_ms %.3f, groups = %d, substeps = %s\n",
    Threads.nthreads(), median_of(field_ms), minimum(field_ms), median_of(mcs_ms),
    length(runtimes), string([rt.n for rt in runtimes])
)
