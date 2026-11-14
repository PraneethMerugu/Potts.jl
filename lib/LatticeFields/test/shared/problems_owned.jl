# Definitions of problems/owned_tests.jl that other test files use (moved here by TS1b).
using LatticeFields.Problems: FieldProblem, ExplicitEuler, BoundStep, LatticeIndex,
                              FieldSlot,
                              ode_problem, face_checks, check_faces, degenerate_face
using LatticeFields.IR: runtime
using CommonSolve: solve, init, step!
using SciMLBase: SciMLBase

"""
2D periodic diffusion stepped with `dt = G.rt[2]` (the owned stepper form).
"""
function euler2(dims; rate = false, storage = F32)
    pb = ProgramBuilder(Grid(dims); periodic = (true, true), nparams = 1)
    u = field!(pb, "u"; buffers = rate ? 1 : 2, storage)
    g = rate ? field!(pb, "∂u"; role = :scratch, storage) : u
    kb = kernel(pb)
    c = load(kb, u)
    r = param(kb, 1) * (sum(load(kb, u; offset = o) for o in OFFS2) - 4c)
    store(kb, g, rate ? r : c + runtime(kb, 2) * r)
    add!(pb, kb, "diffuse")
    return program(pb)
end
