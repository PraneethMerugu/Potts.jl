# F2 guard (F2 design §4 F2-01, §5): the behavior and the fingerprints of the field pipeline,
# recorded on lp/f1 bda31989 (F1 accepted) and checked at every commit of the F2 series.
#
# - Hard set (`GD_HARD`): per model, at Float64 and Float32, the canonical solver string, each
#   `:field_program` entry of the generated code (fingerprint text, arrays, parameters, tables,
#   least count, bounded flag), the problem fingerprint, the substep count `n` of every field
#   group at the default parameters, and a CPU digest of every site array and σ after 5 MCS
#   (SequentialCPM, seed 7). The behavior records (`n`, digests) are hard for every model; the
#   fingerprint records are hard for the pinned models (`pinned = true`: the frozen pins of
#   p6_0o and p6_0g, asserted below as well). A fingerprint move of an unpinned hard model
#   (Merks2006, Merks2008, FdTwo) is allowed only when the commit's plan lists it; the commit
#   then updates the record here, with its cause.
# - Soft set (`GD_SOFT`): the `test/fields.jl` models, the `test/audit.jl` field models (copies,
#   prefixed `Gd`) and the p6_5c Fortuna-like model (a copy), at Float64: the route (automatic
#   count or explicit), the problem fingerprint, the `:field_program` entries and `n`. A move
#   must be listed by the commit that makes it, which updates the record with its cause.
# - Front end B (`GD_B`, F2 batch 2): owned `FieldProblem`s and an ODE right side, Float64:
#   a digest of the final state and the substep count. Hard, as the hard set's behavior.
# - ROCm (F2 batch 2, with `POTTS_GPU=rocm`): the hard set on the device against the CPU run.
#
# `POTTS_GUARD_RECORD=<path>` writes the computed records to `<path>` (one `"key" => "value",`
# per line) for a new recording; the checks run as well.

@testitem "F2 guard: the field pipeline's behavior and fingerprints" setup = [FieldsSetup] tags = [:potts, :fields_identity] begin
    @testset "F2 guard: the field pipeline's behavior and fingerprints" begin
        got = gd_jiang!(gd_implicit!(gd_b!(gd_soft!(gd_hard!(Dict{String, String}())))))
        path = get(ENV, "POTTS_GUARD_RECORD", "")
        isempty(path) || open(path, "w") do io
            for k in sort!(collect(keys(got)))
                println(io, "    ", repr(k), " => ", repr(got[k]), ",")
            end
        end
        # the copies reproduce the frozen pins
        for (k, v) in GD_PINS
            @test got["$k|fingerprint"] == repr(v)
        end
        hk = [k for k in keys(GD_RECORDS) if gd_label(k) in [first.(GD_HARD); GD_B] && !(k in GD_UNPINNED)]
        sk = setdiff(collect(keys(GD_RECORDS)), hk, GD_UNPINNED)
        behavior = [k for k in hk if occursin("|n", k) || occursin("|digest|", k)]
        pinned = [k for k in setdiff(hk, behavior) if gd_pinned(k)]
        unpinned = setdiff(hk, behavior, pinned)
        for (what, ks) in (("behavior (hard)", behavior), ("pinned fingerprints (hard)", pinned),
                ("unpinned fingerprints (listed moves only)", unpinned), ("soft set (listed moves only)", sk))
            bad = gd_compare(got, GD_RECORDS, sort!(ks))
            isempty(bad) || @error "F2 guard: $what moved: $(length(bad)) records"
            foreach(b -> println(stderr, "  GUARD MOVED ($what) ", b), bad)
            @test isempty(bad)
        end
        # no record appears or disappears unlisted
        @test sort!(collect(keys(got))) == sort!(collect(keys(GD_RECORDS)))
    end
end

@testitem "F3-01 guard: the canonical fill order of every guard model" setup = [FieldsSetup] tags = [:potts, :fields_identity] begin
    @testset "F3-01 guard: the canonical fill order of every guard model" begin
        models = Any[[(label, build) for (label, build, _...) in GD_HARD];
                     [(string(n), () -> getfield(@__MODULE__, n)(; name = :g)) for n in GD_SOFT]]
        got = Dict{String, Any}()
        for (label, build) in models
            f = try
                Potts._field_inputs(build(), Float64)
            catch e
                e isa ArgumentError || rethrow()
                nothing
            end
            got[label] = f === nothing ? nothing : join(("$(e[1]) = $(e[2])" for e in f), "; ")
        end
        bad = [k for k in keys(got) if !isequal(got[k], get(GD_FILL, k, missing))]
        foreach(k -> println(stderr, "  FILL ORDER MOVED ", k, ": recorded ", repr(get(GD_FILL, k, missing)), ", now ", repr(got[k])), bad)
        @test isempty(bad) && sort!(collect(keys(got))) == sort!(collect(keys(GD_FILL)))
    end
end

@testitem "F2 guard (ROCm): the hard set on the device matches the CPU" setup = [FieldsSetup] tags = [:potts, :fields_identity, :device] begin
    if PottsDevices.on_device() && PottsDevices.device_name() == "rocm"
        @testset "F2 guard (ROCm): the hard set on the device matches the CPU" begin
            backend = PottsDevices.device_backend()
            # Float32 only: the Potts device suite ends with a scan that no kernel it compiled holds
            # a `double` (D-157, Metal stands in), and a Float64 problem's kernels do
            for (label, build, op, kw, _) in GD_HARD, T in (Float32,)
                prob = PottsProblem(build(), op, (0, 5); T, seed = 7, kw...)
                cpu = solve(prob, CheckerboardCPM()).u[end]
                dev = solve(prob, CheckerboardCPM(); backend).u[end]
                ok = Array(dev.σ) == Array(cpu.σ)
                tol = T === Float32 ? 1e-5 : 1e-12
                for k in keys(cpu.site)
                    a, b = Float64.(Array(getproperty(cpu.site, k))), Float64.(Array(getproperty(dev.site, k)))
                    ok &= maximum(abs, a .- b; init = 0.0) <= tol * max(1.0, maximum(abs, a; init = 0.0))
                end
                ok || println(stderr, "  GUARD ROCm differs: $label|$T")
                @test ok
            end
        end
    end
end

# F2-07: the byte-identity gate of the update pass. For every guard model's field system (all
# its fields, and each field alone with the others read from their arrays), the rate program
# with the Euler update fused by the IR pass (`fuse_update`) prints the same semantic program
# as A's symbolic fusion (`_EulerUpdate`), with and without a clip, at Float64 and Float32
@testitem "F2-07 gate: the update pass equals A's symbolic fusion" setup = [FieldsSetup] tags = [:potts, :fields_identity] begin
    @testset "F2-07 gate: the update pass equals A's symbolic fusion" begin
        LP, LF = Potts.LatticePDE, Potts.LatticeFields
        models = Any[[(label, build) for (label, build, _...) in GD_HARD];
                     [(string(n), () -> getfield(@__MODULE__, n)(; name = :g)) for n in GD_SOFT]]
        bad, checked = String[], Ref(0)
        for (label, build) in models, T in (Float64, Float32)
            sys = build()
            names = Symbol[Potts.info(x).name for (x, _) in Potts._field_equations(sys)]
            isempty(names) && continue
            known = try
                Potts._field_inputs(sys, T)
            catch e
                e isa ArgumentError || rethrow()
                continue                                    # a model `@equations` refuses
            end
            for ns in unique([[names]; length(names) > 1 ? [[n] for n in names] : Vector{Symbol}[]])
                pdesys, _ = Potts._field_system(sys, ns; T, known)
                disc = Potts._field_disc(sys, T)
                rate = LP.symbolic_discretize(pdesys, disc).program
                for lower in (nothing, 0.0)
                    sym = LP.symbolic_discretize(pdesys, disc; update = Potts._EulerUpdate(lower)).program
                    pass = LF.Compile.fuse_update(rate, LF.Problems.update_rule(ExplicitEuler(; lower)))
                    checked[] += 1
                    LF.Compile.fingerprint_text(pass; T) == LF.Compile.fingerprint_text(sym; T) ||
                        push!(bad, "$label|$T|$(join(ns, ","))|lower=$lower")
                end
            end
        end
        foreach(b -> println(stderr, "  FUSION GATE differs: ", b), bad)
        @test isempty(bad) && checked[] > 100
    end
end

@testitem "F2-08a: 20 MCS of the Merks models equal the parent bitwise (CPU)" setup = [FieldsSetup] tags = [:potts, :fields_identity] begin
    @testset "F2-08a: 20 MCS of the Merks models equal the parent bitwise (CPU)" begin
        got = gd_m20()
        foreach(((g, w),) -> g == w || println(stderr, "  M20 MOVED (CPU): ", w, " → ", g), zip(got, GD_M20_CPU))
        @test got == GD_M20_CPU
    end
end

@testitem "F2-08a: 20 MCS of the Merks models equal the parent bitwise (ROCm)" setup = [FieldsSetup] tags = [:potts, :fields_identity, :device] begin
    if PottsDevices.on_device() && PottsDevices.device_name() == "rocm"
        @testset "F2-08a: 20 MCS of the Merks models equal the parent bitwise (ROCm)" begin
            got = gd_m20(; backend = PottsDevices.device_backend(), types = (Float32,))
            foreach(((g, w),) -> g == w || println(stderr, "  M20 MOVED (ROCm): ", w, " → ", g), zip(got, GD_M20_ROCM))
            @test got == GD_M20_ROCM
        end
    end
end

@testitem "F2-08a: the Merks 500² warm MCS allocates nothing (CPU)" setup = [FieldsSetup] tags = [:potts, :fields_identity] begin
    @testset "F2-08a: the Merks 500² warm MCS allocates nothing (CPU)" begin
        σ = zeros(Int32, 500, 500); σ[200:215, 200:215] .= 1; σ[300:312, 280:300] .= 2
        prob = PottsProblem(MerksVasculogenesis(; name = :m, lattice = (500, 500)), [ownership => σ, kind => [:endothelial, :endothelial]],
            (0, 100); field_solver = ExplicitEuler(substeps = 15, lower = 0.0))
        integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
        @test gd_warm(integ) == 0
    end
end

# F2-08b: Merks2006 has a masked field (its `kind == border` frame): the clamp at the step start
# runs every MCS, and a warm MCS at 500² still allocates nothing on the CPU (a `foreach` closure
# over the clamps allocated 176 B per MCS on front end A's runtime)
@testitem "F2-08b: the Merks2006 500² warm MCS (masked, clamped) allocates nothing (CPU)" setup = [FieldsSetup] tags = [:potts, :fields_identity] begin
    @testset "F2-08b: the Merks2006 500² warm MCS (masked, clamped) allocates nothing (CPU)" begin
        σ = zeros(Int32, 500, 500); σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
        σ[200:215, 200:215] .= 2; σ[300:312, 280:300] .= 3
        prob = PottsProblem(Merks2006(; name = :m, lattice = (500, 500)), [ownership => σ, kind => [:border, :endothelial, :endothelial]],
            (0, 100); field_solver = ExplicitEuler(substeps = 15))
        integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
        @test gd_warm(integ) == 0
    end
end

# F2-08c: Merks2008 reads `mcs` (its `mcs ≥ t_relax` gate) through the clock's slot, whose
# launches derive their parameters at each launch with the MCS number: a warm MCS at 500²
# still allocates nothing on the CPU
@testitem "F2-08c: the Merks2008 500² warm MCS (mcs read) allocates nothing (CPU)" setup = [FieldsSetup] tags = [:potts, :fields_identity] begin
    @testset "F2-08c: the Merks2008 500² warm MCS (mcs read) allocates nothing (CPU)" begin
        σ = zeros(Int32, 500, 500); σ[1:2, :] .= 1; σ[(end - 1):end, :] .= 1; σ[:, 1:2] .= 1; σ[:, (end - 1):end] .= 1
        σ[200:215, 200:215] .= 2; σ[300:312, 280:300] .= 3
        prob = PottsProblem(Merks2008(; name = :m, lattice = (500, 500)), [ownership => σ, kind => [:border, :endothelial, :endothelial],
            :t_relax => 1.0], (0, 100); field_solver = ExplicitEuler(substeps = 15))
        integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
        @test gd_warm(integ) == 0
    end
end
