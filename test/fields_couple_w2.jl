# F4 wave 2 review fixes (the reviewers' programs ~/lpwork/rev-w2-probes/p14.jl and
# ~/lpwork/rev-w2u-progs/m*.jl, p2_array.jl). Uses `cp_msg` and `cp_build_err` of
# fields_couple.jl and `CeFiCompB`, `ce_op` of fields_couple_e11.jl. Negative controls (the
# tests at the src of 11523b0b): ~/lpwork/f4W2r/nc.log (there F4-E16 was named E17 to E19, and
# F4-E17 was E16).

module W2
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.5 s = 0.4 k = 0.05
@variables c(..) = 0.0 u(..) = 0.0 secreting(..)::Bool [input = true] kin(..)::Int32 [input = true]
@variables kinl(..)::Int32 [input = true, lattice_input_name = "kind"]
const C, U = c(t, x, y), u(t, x, y)
# E14: the condition on `c` sets the ghosts that `Δ(c)` in the equation of `u` reads (p14.jl)
withbc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U], [c(t, 0, y) ~ 1.0];
    name = :wbc)
nobc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U]; name = :nbc)
sec() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * secreting(t, x, y) - k * C]; name = :sec)
# m5: `∈ Set(…)` is Julia's `false`; the source term is gone before `pdesystem` sees it
inset() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kin(t, x, y) ∈ Set([1, 2])) - k * C]; name = :sec)
# m5d: the long form that lists the input (it is filled by `kind`, but no equation reads it)
insetlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kinl(t, x, y) ∈ Set([1, 2])) - k * C], [], [], [t, x, y],
    [C, kinl(t, x, y)], [Dc, s, k]; name = :sec)
# m4: a test of Potts' `kind` (or `volume`) inside the equation
cellread(q) = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (q == 1) - k * C]; name = :sec)
# m4c: the long form that reads Potts' `kind` in its equation
kindlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (Potts.kind == 1) - k * C], [], [], [t, x, y], [C], [Dc, s, k];
    name = :sec)
# m7: the long form with an empty parameter list
nops() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) - k * C], [], [], [t, x, y], [C], []; name = :sys)
# E5: a domain entry for a variable that is not an independent variable
@parameters zz
zdom() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) - k * C], [], [zz ∈ Interval(0.0, 1.0)], [t, x, y], [C], [Dc, k];
    name = :sys)
end

@potts_model W2Host begin
    @kinds medium cell other
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
w2_op() = (σ = zeros(Int32, 12, 10); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:cell]])
w2_model(fields; kinds = :(@kinds medium cell other)) = :(@potts_model W2M begin
    $kinds
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells => (volume - 9.0)^2
    $fields
    @sweep Metropolis(; temperature = 1.0)
end)
w2_new(ex) = cp_msg(() -> (Core.eval(Main, ex); Base.invokelatest(() -> Main.W2M(; name = :m))))

# --- E14: a face condition read through another field's operator ------------------------------
# At 11523b0b the condition on `c` was refused although `Δ(c)` in the equation of `u` reads its
# ghost values (with E14 bypassed, the runs with and without it differ: p1415.log).
@potts_model W2FaceW begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.withbc()
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model W2FaceN begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.nobc()
    @sweep Metropolis(; temperature = 1.0)
end
# the same through `@boundary` (`_check_boundaries`) and `@bcs` in an `@potts_model`
@potts_model W2FaceBnd begin
    @kinds medium A
    @variables c(field) = 0.0 u(field) = 0.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations begin
        D(c) ~ -0.1 * c
        D(u) ~ 0.5 * Δ(c) - 0.1 * u
    end
    @boundary c begin
        x => (Dirichlet(1.0), NoFlux())
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model W2FaceBcs begin
    @kinds medium A
    @variables c(field) = 0.0 u(field) = 0.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations begin
        D(c) ~ -0.1 * c
        D(u) ~ 0.5 * Δ(c) - 0.1 * u
    end
    @bcs c(t, 0, y) ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end
w2_face_op() = (σ = zeros(Int32, 8, 6); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])
w2_u(m) = (pr = PottsProblem(m(; name = :m), w2_face_op(), (0, 3); seed = 1); Array(solve(pr, SequentialCPM()).u[end].site.u))

@testset "F4-E14 review: a face condition that another field's operator reads runs" begin
    uw, un = w2_u(W2FaceW), w2_u(W2FaceN)
    @test maximum(abs, uw .- un) > 1e-3
    # `@boundary` and `@bcs` give the same run as the PDESystem's condition
    @test w2_u(W2FaceBnd) == uw
    @test w2_u(W2FaceBcs) == uw
end
