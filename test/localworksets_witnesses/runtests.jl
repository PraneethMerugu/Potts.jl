include("lbm_d2q9.jl")
include("lattice_spring.jl")
include("matrix_free_fem.jl")
include("zbuffer.jl")

reports = (
    run_lw_d2q9_witness(),
    run_lw_lattice_spring_witness(),
    run_lw_lattice_spring_witness(; force_mode = :fast),
    run_lw_matrix_free_fem_witness(),
    run_lw_zbuffer_witness(),
)

foreach(println, reports)

if haskey(ENV, "LW4_MACHINE_RESULTS")
    import Serialization
    Serialization.serialize(ENV["LW4_MACHINE_RESULTS"], reports)
end
