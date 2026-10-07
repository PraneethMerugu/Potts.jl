# An in-process A/B (`ab.jl --inprocess`): the akeeb_99x60 gate case at μ = 30 (base) and
# μ = 24 (candidate), the P6.2b parameter A/B. Evaluated after `gate.jl` in the checkout's
# environment; `T` is the float type (Float64 on the CPU, Float32 on a device).
#
#     julia benchmark/ab.jl --inprocess <checkout> benchmark/ab_variants_akeeb_mu.jl cpu
const AB_VARIANTS = [
    "mu30" => T -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60), μ = 30.0),
        akeeb_state(; lattice = (99, 60)), (0, 10^6); T, capacity = 1000),
    "mu24" => T -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60), μ = 24.0),
        akeeb_state(; lattice = (99, 60)), (0, 10^6); T, capacity = 1000),
]
