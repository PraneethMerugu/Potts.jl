module CompartmentExchangeExample

using Potts
using Symbolics
using ModelingToolkitBase: @parameters

"""
Two model-owned reservoirs exchange a fraction of the stored amount each MCS.
Both assignments read the same boundary-entry amounts, preserving their sum.
Amounts are dimensionless here; this is a discrete exchange law, not an ODE.
"""
function exchange_problem(; fraction_value = 0.25, seed = 17)
    0 <= fraction_value <= 1 || throw(ArgumentError("exchange fraction must lie in [0, 1]"))
    @variables stored released
    @parameters fraction = fraction_value
    declarations = @statements begin
        Lattice((2, 2); boundary = Closed())
        carrier = CellKind(:carrier; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        ModelState(stored; initial = 8.0)
        ModelState(released; initial = 0.0)
        Synchronous(
            :exchange,
            Assign(stored, (1 - fraction) * stored),
            Assign(released, released + fraction * stored),
        )
        ProposalConstraint(:fixed_ownership, false)
        Protocol(Sweep(; temperature = 0.0); name = :main)
    end
    source = PottsSystem(declarations; name = :compartment_exchange)
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 2, 2); cells = [carrier], medium),
    )
    return PottsProblem(source, initial, (0, 3); seed)
end

if abspath(PROGRAM_FILE) == @__FILE__
    solution = solve(exchange_problem(), SequentialCPM(); scalar_type = Float32)
    println("Final reservoirs: ", (last(solution)[:stored], last(solution)[:released]))
end

end
