module CellPolarityDynamicsExample

using Potts
using StaticArrays
using Symbolics
using SciMLBase: successful_retcode

"""
Build cell-owned polarity dynamics with a held angular increment in radians.

At each boundary, `sample_turn` stores the next addressed increment while
`rotate_polarity` reads the previous increment. Both read boundary-entry state:
the initial zero turn holds polarity at the first boundary. Cell area does not
change the number of updates. Ownership is fixed here; this example does not
model migration or couple polarity to a proposal energy.
"""
function polarity_problem(; reordered = false, unrelated = false, seed = 0x00071931)
    @variables polarity[1:2] turn unrelated_signal
    tissue = CellKind(:tissue; extinction = RetireAtZero())
    spectator = CellKind(:spectator; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    rotated = SVector(
        cos(turn) * polarity[1] - sin(turn) * polarity[2],
        sin(turn) * polarity[1] + cos(turn) * polarity[2],
    )
    processes = (
        Synchronous(
            :sample_turn, Assign(turn, draw(Uniform(-0.25, 0.25), DrawKey(:angular_increment)));
            domain = cells(tissue),
        ),
        Synchronous(:rotate_polarity, Assign(polarity, rotated); domain = cells(tissue)),
    )
    extra = unrelated ? (
            ModelState(unrelated_signal; initial = 0.0),
            Synchronous(:sample_unrelated, Assign(unrelated_signal, draw(Uniform(), DrawKey(:unrelated_increment)))),
        ) : ()
    source = PottsSystem(
        name = :cell_polarity_dynamics,
        statements = StatementSet(
            (
                Lattice((4, 3); boundary = Closed(), max_cells = 4),
                tissue, spectator, medium,
                CellState(polarity; initial = SVector(1.0, 0.0), retirement = RetireTo(SVector(0.0, 0.0))),
                CellState(turn; initial = 0.0, retirement = RetireTo(0.0)),
                ProposalConstraint(:fixed_ownership, false),
                extra...,
                (reordered ? reverse(processes) : processes)...,
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = unrelated ? (polarity, turn, unrelated_signal) : (polarity, turn),
    )
    # Tissue cells have areas one and three; the spectator has area one.
    labels = [1 0 0; 2 2 0; 2 0 0; 3 0 0]
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [tissue, tissue, spectator], medium),
    )
    return PottsProblem(source, initial, (0, 4); seed)
end

if abspath(PROGRAM_FILE) == @__FILE__
    solution = solve(polarity_problem(), SequentialCPM(); scalar_type = Float32)
    successful_retcode(solution) || error("polarity dynamics did not complete: $(solution.retcode)")
    println("Final cell polarities: ", last(solution)[:polarity])
end

end
