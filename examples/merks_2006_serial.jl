module Merks2006Serial

using Potts
using SciMLBase
using Symbolics
using ModelingToolkitBase: @parameters

"""
    run_merks_2006(; mcs = 2, seed = 0x3303)

Build and execute the serial CPU integration witness for the field-coupled
vasculogenesis mechanisms described by Merks et al. (2006). This checks the
final API and field-coupled CPM execution; scientific reproduction remains a
later review.
"""
function run_merks_2006(; mcs::Integer=2, seed::Integer=0x3303)
    mcs >= 1 || throw(ArgumentError("mcs must be positive"))

    @variables concentration
    @parameters begin
        target_volume = 6.0
        volume_strength = 1.0
        chemotaxis_strength = 2.0
        diffusion = 0.08
        secretion = 0.02
        decay = 0.01
        temperature = 6.0
    end

    endothelial = CellKind(:endothelial; extinction=RetireAtZero())
    extracellular = MediumKind(:extracellular)
    field = FieldState(
        concentration;
        name=:concentration,
        initial=0.0,
        evolution=DiscreteFieldEuler(),
        diffusion,
        secretion,
        decay,
        substeps=2,
        duration_per_mcs=1.0,
        source_kind=endothelial,
        stencil=:field_stencil,
    )
    source = PottsSystem(
        name=:merks_2006,
        statements=StatementSet((
            Lattice(
                (8, 8);
                boundary=Closed(),
                relations=(
                    proposal=Moore(),
                    connectivity=Moore(),
                    connectivity_background=VonNeumann(),
                    field_stencil=VonNeumann(),
                ),
            ),
            endothelial,
            extracellular,
            field,
            Volume(endothelial; target=target_volume, strength=volume_strength),
            Chemotaxis(
                endothelial,
                field;
                strength=chemotaxis_strength,
                mode=ExtensionsOnly(),
                sample=Nearest(),
            ),
            LocalConnectivity(endothelial),
            Protocol(Sweep(; temperature); name=:main),
            Observation(:field_snapshot, concentration),
        )),
        unknowns=[concentration],
        parameters=[
            target_volume,
            volume_strength,
            chemotaxis_strength,
            diffusion,
            secretion,
            decay,
            temperature,
        ],
    )
    scheduled = mtkcompile(source)

    labels = zeros(Int32, 8, 8)
    labels[3:5, 3:5] .= 1
    initial = PottsInitialState(
        ownership=LabelledCells(
            labels;
            cells=[endothelial],
            medium=extracellular,
        ),
        values=(concentration => zeros(Float64, 8, 8),),
    )
    problem = PottsProblem(scheduled, initial, (0, Int(mcs)); seed)
    solution = solve(
        problem,
        SequentialCPM();
        backend=CPUBackend(),
        scalar_type=Float64,
        save_everystep=true,
        observables=(:field_snapshot,),
    )

    final = last(solution)
    @assert solution.retcode == SciMLBase.ReturnCode.Success
    @assert all(isfinite, final[:concentration])
    @assert sum(final[:concentration]) > 0
    @assert final[:field_snapshot] == final[:concentration]

    return (; source, scheduled, problem, solution, concentration)
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = run_merks_2006()
    println(
        "Merks serial witness passed: mcs=",
        last(result.solution).mcs,
        ", field_total=",
        sum(last(result.solution)[:concentration]),
    )
end

end
