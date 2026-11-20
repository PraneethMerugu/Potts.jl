# The precompile workload: a hand-written two-cell model (contact energy from a kind table, a
# quadratic volume energy, a constant temperature) on a 12×12 lattice, built into a
# `PottsProblem` and solved for 2 MCS with `SequentialCPM`. A user's first hand-written
# `CPMFunction` then does not compile the problem setup, the state and the solution in the
# session. (A user turns the workload off with PrecompileTools' preference
# `precompile_workload = false`.) The tests call it too.

_workload_kind(st, c) = c == 0 ? 1 : Int(st.cell.kind[c]) + 1
function _workload_delta_H(st, p, prop, ctx)
    J(a, b) = p.J[_workload_kind(st, a), _workload_kind(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
_workload_temperature(st, p, prop, ctx) = p.T

function _precompile_workload()
    f = CPMFunction(_workload_delta_H; temperature = _workload_temperature)
    σ = zeros(Int32, 12, 12)
    σ[2:5, 2:5] .= 1
    σ[6:9, 2:5] .= 2
    J = SMatrix{3, 3, Float64}(0, 16, 16, 16, 2, 11, 16, 11, 14)
    p = (; J, λ = 1.0, V0 = 16.0, T = 10.0)
    prob = PottsProblem(f, initial_state(σ, Int32[1, 2]), Lattice((12, 12)), (0, 2), p; seed = 1)
    solve(prob, SequentialCPM())
    return nothing
end

@setup_workload begin
    @compile_workload begin
        _precompile_workload()
    end
end
