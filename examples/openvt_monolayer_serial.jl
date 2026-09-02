module OpenVTMonolayerSerial

using ModelingToolkitBase: @parameters
using Potts
using SciMLBase
using Symbolics

"""Bounded deterministic relaxation calibration for the OpenVT 11-cell chain."""
function calibrate_relaxation(; tolerance=0.9, stiffness=0.2, maximum_steps=200)
    positions = collect(range(0.0, 8.0; length=11))
    initial_span = positions[end] - positions[1]
    target_span = initial_span + tolerance * (10.0 - initial_span)
    for step in 1:maximum_steps
        span = positions[end] - positions[1]
        relaxed_span = span + stiffness * (10.0 - span)
        positions .= range(-relaxed_span / 2, relaxed_span / 2; length=11)
        positions[end] - positions[1] >= target_span && return step
    end
    error("OpenVT chain calibration did not reach its bounded relaxation target")
end

function free_surface_fraction(ownership, label)
    sites = findall(==(label), ownership)
    isempty(sites) && return 0.0
    exposed = 0
    total = 0
    for site in sites, offset in (CartesianIndex(-1, 0), CartesianIndex(1, 0),
            CartesianIndex(0, -1), CartesianIndex(0, 1))
        neighbor = site + offset
        total += 1
        if !checkbounds(Bool, ownership, neighbor) || ownership[neighbor] != label
            exposed += 1
        end
    end
    return exposed / total
end

"""
    run_openvt_monolayer(; mcs=2, seed=0x3306, beta=0.8, gamma=0.2)

Exercise the OpenVT monolayer workflow with current public interfaces: the
11-cell relaxation calibration, zero cell-cell adhesion, steric volume energy,
free-surface contact-inhibition classification, generation-safe division, and
a bounded serial CPU trajectory. This is not the 10,000-cell GPU campaign.
"""
function run_openvt_monolayer(; mcs::Integer=2, seed::Integer=0x3306,
        beta::Real=0.8, gamma::Real=0.2)
    mcs >= 2 || throw(ArgumentError("mcs must be at least 2 to exercise division"))
    0 <= gamma <= beta <= 1 || throw(ArgumentError("require 0 ≤ gamma ≤ beta ≤ 1"))

    @variables division_mass
    @parameters begin
        target_volume = 8.0
        volume_strength = 2.0
        temperature = 2.0
        division_threshold = 8.0
    end
    tissue = CellKind(:tissue; extinction=RetireAtZero())
    medium = MediumKind(:medium)
    division_relation = SpatialRelation(:division; neighborhood=VonNeumann())
    mass = CellState(division_mass; initial=8.0, retirement=RetireTo(0.0),
        division=SplitConservatively(0.5; rounding=:exact))
    anchor = CellBinding(:dividing_cell)
    divide = LifecycleProcess(
        :openvt_division;
        domain=cells(tissue),
        anchor,
        expression=cell_volume(anchor_value(anchor)) >= division_threshold,
        effects=(Divide(
            anchor;
            geometry=SpecifiedNormalPlane((1.0, 0.0)),
            relation=division_relation,
            side=CanonicalSide(),
            state=(mass => SplitConservatively(0.5; rounding=:exact),),
            on_inadmissible=ErrorOnInadmissible(),
        ),),
        cadence=AtMCS(1),
    )
    source = PottsSystem(
        name=:openvt_monolayer,
        statements=StatementSet((
            Lattice((12, 8); boundary=Closed(), max_cells=8,
                relations=(proposal=Moore(), contact=Moore())),
            tissue,
            medium,
            division_relation,
            mass,
            Volume(tissue; target=target_volume, strength=volume_strength),
            ContactEnergy([
                (tissue ↔ tissue) => 0.0,
                (medium ↔ tissue) => 4.0,
            ]),
            divide,
            Protocol(Sweep(; temperature); name=:main),
            Observation(:tissue_sites, occupancy(tissue, :lattice)),
        )),
        unknowns=[division_mass],
        parameters=[target_volume, volume_strength, temperature, division_threshold],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 12, 8)
    labels[5:8, 4:5] .= 1
    initial = PottsInitialState(ownership=LabelledCells(
        labels; cells=[tissue], medium), values=(division_mass => [8.0],))
    solution = solve(PottsProblem(scheduled, initial, (0, Int(mcs)); seed),
        SequentialCPM(); backend=CPUBackend(), scalar_type=Float64,
        save_everystep=true, observables=(:tissue_sites,))

    final = last(solution)
    labels_present = filter(!iszero, unique(final.ownership))
    fractions = [free_surface_fraction(final.ownership, label)
        for label in labels_present]
    inhibition = map(fractions) do fraction
        fraction >= beta ? :growing : fraction <= gamma ? :contact_inhibited : :crowded
    end
    relaxation_steps = calibrate_relaxation()
    @assert solution.retcode == SciMLBase.ReturnCode.Success
    @assert relaxation_steps > 0
    @assert final[:tissue_sites] == count(!iszero, final.ownership)
    @assert !isempty(inhibition)
    return (; source, scheduled, solution, relaxation_steps, fractions, inhibition)
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = run_openvt_monolayer()
    println("OpenVT bounded witness passed: relaxation_steps=",
        result.relaxation_steps, ", states=", result.inhibition)
end

end
