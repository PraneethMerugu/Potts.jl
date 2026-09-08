# PROPOSED END-STATE API — DESIGN EXAMPLE, NOT CURRENTLY RUNNABLE.
# A complete small model, initial conditions, solve, and analysis in one file.
# See ../authoring-api-overview.md for current-versus-proposed API status.

module CellSortingExample

using Potts
using ModelingToolkit
using SciMLBase
using Test

function cell_sorting(; mcs = 500, seed = 42)
    @parameters temperature = 2.0 target_volume = 40.0
    @parameters volume_strength = 2.0 unlike_contact = 12.0

    a = CellKind(:a; extinction = ForbidExtinction())
    b = CellKind(:b; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    lattice = Lattice((64, 64);
        boundary = Periodic(), max_cells = 64,
        relations = (proposal = VonNeumann(), contact = VonNeumann()))

    system = PottsSystem(;
        name = :sorting,
        statements = (@statements begin
            lattice
            a
            b
            medium
            Volume(a; target = target_volume, strength = volume_strength)
            Volume(b; target = target_volume, strength = volume_strength)
            ContactEnergy(
                [0.0 16.0 16.0; 16.0 4.0 unlike_contact; 16.0 unlike_contact 4.0];
                kinds = (medium, a, b), relation = :contact)
            Protocol(Sweep(; temperature); name = :main)
        end),
    )

    # Sixteen non-overlapping disks. Labels identify cells, not cell kinds.
    labels = zeros(Int32, 64, 64)
    centers = [(x, y) for y in (12, 25, 38, 51) for x in (12, 25, 38, 51)]
    for (id, (cx, cy)) in enumerate(centers)
        for y in 1:64, x in 1:64
            (x - cx)^2 + (y - cy)^2 <= 3^2 && (labels[x, y] = id)
        end
    end
    kinds = [isodd(id) ? a : b for id in eachindex(centers)]
    initial = PottsInitialState(;
        ownership = LabelledCells(labels; cells = kinds, medium))

    problem = PottsProblem(system, initial, (0, mcs); seed)
    solution = solve(problem, CheckerboardSweepCPM();
        backend = CPUBackend(), scalar_type = Float64,
        saveat = unique(sort([collect(0:10:mcs); mcs])))
    @test solution.retcode == SciMLBase.ReturnCode.Success

    # Scientific parameters are distinct from lattice/capacity structure.
    # Construct an experiment without touching compiler objects or cell buffers.
    stronger_separation = remake(problem; p = (unlike_contact => 20.0,))

    return (; system, initial, problem, solution, stronger_separation)
end

# After this proposed API exists:
# include("cell_sorting.jl")
# result = CellSortingExample.cell_sorting()
# display(result.solution[end])
# display(explain(result.system))

end # module
