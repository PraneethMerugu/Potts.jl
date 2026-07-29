struct _CPUOnlyFragmentFixture
    name::Symbol
end

CorePotts.component_identity(value::_CPUOnlyFragmentFixture) =
    CorePotts.ComponentIdentity(value.name, v"1.0.0", :fixture_state)
CorePotts.component_semantic_data(value::_CPUOnlyFragmentFixture) =
    (name = value.name,)
CorePotts.capabilities(::_CPUOnlyFragmentFixture) =
    CorePotts.ScientificCapabilities(portable = false)

@testset "generic hierarchical fragment ports" begin
    tumor = PottsToolkit.CellType(:fragment14_tumor)
    medium = PottsToolkit.Medium(:fragment14_medium)
    cells = PottsToolkit.CellRole(:fragment14_cells)

    signal = CorePotts.SiteProperty(:fragment14_signal;
        initial = 0.0f0, ownership = CorePotts.PreserveAtSite())
    field_advance = CorePotts.SiteDynamics(
        :fragment14_field_advance, signal;
        update = CorePotts.SetSiteValue(0.0f0))
    secretome = PottsToolkit.ModelFragment(
        :fragment14_secretome, signal, field_advance;
        requires = (cells = cells, medium = medium),
        exports = (signal = signal, advance = field_advance))
    secretome = PottsToolkit.bind(secretome, secretome.cells => tumor)

    rac_advance = CorePotts.SiteDynamics(
        :fragment14_rac_advance, :fragment14_signal;
        update = CorePotts.SetSiteValue(1.0f0))
    signaling = PottsToolkit.ModelFragment(
        :fragment14_signaling, rac_advance;
        requires = (signal = secretome.signal,),
        exports = (advance = rac_advance,))

    coupled = PottsToolkit.ModelFragment(
        :fragment14_coupled, secretome, signaling;
        exports = (
            signal = secretome.signal,
            field_advance = secretome.advance,
            rac_advance = signaling.advance,
        ))
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(:fragment14_field,
            CorePotts.Advance(coupled.field_advance;
                interval = CorePotts.OneMCS())),
        CorePotts.CoupledPhase(:fragment14_rac,
            CorePotts.Advance(coupled.rac_advance;
                interval = CorePotts.OneMCS())),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(),
    )
    nested_model = PottsToolkit.PottsModel(tumor, medium, coupled, plan)
    @test Base.isvalid(nested_model)
    @test PottsToolkit.required_backends(nested_model) == (:cpu, :metal, :rocm)
    @test propertynames(coupled) == (
        :name, :declarations, :requirements, :exports,
        :signal, :field_advance, :rac_advance)
    @test_throws ArgumentError getproperty(coupled, :private_leaf)

    explicit_model = PottsToolkit.PottsModel(
        tumor, medium, signal, field_advance, rac_advance, plan)
    @test PottsToolkit.semantic_fingerprint(nested_model) ==
          PottsToolkit.semantic_fingerprint(explicit_model)
    @test PottsToolkit.required_backends(nested_model) ==
          PottsToolkit.required_backends(explicit_model)

    replacement = CorePotts.SiteDynamics(
        :fragment14_rac_advance_replacement, :fragment14_signal;
        update = CorePotts.SetSiteValue(2.0f0))
    replacement_fragment = PottsToolkit.ModelFragment(
        :fragment14_signaling, replacement;
        requires = (signal = secretome.signal,),
        exports = (advance = replacement,))
    substituted = PottsToolkit.ModelFragment(
        :fragment14_coupled, secretome, replacement_fragment;
        exports = (
            signal = secretome.signal,
            field_advance = secretome.advance,
            rac_advance = replacement_fragment.advance,
        ))
    replacement_plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(:fragment14_field,
            CorePotts.Advance(substituted.field_advance;
                interval = CorePotts.OneMCS())),
        CorePotts.CoupledPhase(:fragment14_rac,
            CorePotts.Advance(substituted.rac_advance;
                interval = CorePotts.OneMCS())),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(),
    )
    substituted_model =
        PottsToolkit.PottsModel(tumor, medium, substituted, replacement_plan)
    @test Base.isvalid(substituted_model)
    original_ids = Set(PottsToolkit.semantic_identity(value)
        for value in PottsToolkit.normalize(nested_model).components)
    substituted_ids = Set(PottsToolkit.semantic_identity(value)
        for value in PottsToolkit.normalize(substituted_model).components)
    @test setdiff(original_ids, substituted_ids) ==
          Set((PottsToolkit.SemanticName(:fragment14_rac_advance),))
    @test setdiff(substituted_ids, original_ids) ==
          Set((PottsToolkit.SemanticName(:fragment14_rac_advance_replacement),))

    private_process = CorePotts.SiteDynamics(
        :fragment14_private_process, :fragment14_signal;
        update = CorePotts.SetSiteValue(0.0f0))
    private_fragment = PottsToolkit.ModelFragment(
        :fragment14_private, private_process)
    private_plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(:fragment14_private_phase,
            CorePotts.Update(private_process)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(),
    )
    private_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        tumor, medium, private_fragment, private_plan))
    @test any(item -> item.code === :private_fragment_reference,
        private_report)

    nested_private_process = CorePotts.SiteDynamics(
        :fragment14_nested_private_process, :fragment14_signal;
        update = CorePotts.SetSiteValue(0.0f0))
    leaf = PottsToolkit.ModelFragment(
        :fragment14_leaf, nested_private_process)
    outer = PottsToolkit.ModelFragment(:fragment14_outer, leaf)
    qualified = PottsToolkit.normalize(PottsToolkit.PottsModel(
        tumor, medium, outer))
    @test PottsToolkit.semantic_identity(only(qualified.components)) ==
          PottsToolkit.SemanticName(
              PottsToolkit.Namespace((:fragment14_outer, :fragment14_leaf)),
              :fragment14_nested_private_process)
    nested_private_plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(:fragment14_nested_private_phase,
            CorePotts.Update(nested_private_process)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(),
    )
    nested_private_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        tumor, medium, outer, nested_private_plan))
    @test any(item -> item.code === :private_fragment_reference,
        nested_private_report)

    local_plan_fragment = PottsToolkit.ModelFragment(
        :fragment14_illegal_scheduler, plan; exports = (plan = plan,))
    local_plan_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        tumor, medium, local_plan_fragment))
    @test any(item -> item.code === :fragment_local_execution_plan,
        local_plan_report)

    multiple_plan_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        tumor, medium, plan,
        CorePotts.MCSPlan(
            CorePotts.PottsAttempts(),
            CorePotts.LifecyclePhase(),
            CorePotts.ObservationPhase())))
    @test any(item -> item.code === :multiple_root_execution_plans,
        multiple_plan_report)

    category_mismatch = PottsToolkit.ModelFragment(
        :fragment14_category_mismatch;
        requires = (input = PottsToolkit.FragmentRequirement(signal;
            category = :relationship_set),))
    category_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        tumor, medium, signal, category_mismatch))
    @test any(item ->
        item.code === :fragment_requirement_contract_mismatch, category_report)

    schema_mismatch = PottsToolkit.ModelFragment(
        :fragment14_schema_mismatch;
        requires = (input = PottsToolkit.FragmentRequirement(signal;
            schema = :vector_concentration),))
    schema_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        tumor, medium, signal, schema_mismatch))
    @test any(item ->
        item.code === :fragment_requirement_contract_mismatch, schema_report)

    mismatch_contracts = (
        PottsToolkit.FragmentRequirement(signal; owner = :cell),
        PottsToolkit.FragmentRequirement(signal; units = :millimolar),
        PottsToolkit.FragmentRequirement(signal; operation = :invoke),
        PottsToolkit.FragmentRequirement(signal; lifecycle = (:divide,)),
        PottsToolkit.FragmentRequirement(signal;
            capabilities = CorePotts.ScientificCapabilities(dimensions = (1,))),
    )
    for (index, requirement) in enumerate(mismatch_contracts)
        fragment = PottsToolkit.ModelFragment(
            Symbol(:fragment14_contract_mismatch_, index);
            requires = (input = requirement,))
        report = PottsToolkit.validate(PottsToolkit.PottsModel(
            tumor, medium, signal, fragment))
        @test any(item ->
            item.code === :fragment_requirement_contract_mismatch, report)
    end

    typed_signal = CorePotts.SiteProperty(:fragment14_typed_signal;
        initial = 0.0f0, ownership = CorePotts.PreserveAtSite())
    typed_source = PottsToolkit.ModelFragment(
        :fragment14_typed_source, typed_signal;
        exports = (signal = PottsToolkit.FragmentExport(typed_signal;
            schema = :scalar_concentration, units = :millimolar,
            backends = (:cpu, :metal, :rocm)),))
    typed_consumer = PottsToolkit.ModelFragment(
        :fragment14_typed_consumer;
        requires = (signal = PottsToolkit.FragmentRequirement(
            typed_source.signal; schema = :scalar_concentration,
            units = :millimolar, backends = (:cpu, :metal, :rocm)),))
    @test Base.isvalid(PottsToolkit.PottsModel(
        tumor, medium, typed_source, typed_consumer))

    cpu_only = _CPUOnlyFragmentFixture(:fragment14_cpu_only)
    backend_mismatch = PottsToolkit.ModelFragment(
        :fragment14_backend_mismatch;
        requires = (input = PottsToolkit.FragmentRequirement(cpu_only;
            backends = (:cpu, :metal)),))
    backend_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        tumor, medium, cpu_only, backend_mismatch))
    @test any(item ->
        item.code === :fragment_requirement_contract_mismatch, backend_report)

    unbound = PottsToolkit.ModelFragment(
        :fragment14_generic_requirement;
        requires = (input = PottsToolkit.FragmentRequirement(
            category = :site_property, owner = :site),))
    @test_throws ArgumentError PottsToolkit.bind(unbound,
        unbound.input => medium)
    bound = PottsToolkit.bind(unbound, unbound.input => signal)
    @test isempty(bound.requirements)
end

@testset "generic coupled model process cadence belongs to the root plan" begin
    process = CorePotts.SiteDynamics(:fragment14_periodic, :fragment14_signal;
        update = CorePotts.SetSiteValue(0.0f0))
    cadence = CorePotts.PeriodicMCS(10, 10)
    invocation = CorePotts.Update(process; active = cadence)
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(:fragment14_retune, invocation),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(),
    )
    active = only((entry for entry in plan.entries
        if entry isa CorePotts.CoupledPhase)).invocations[1].active
    @test CorePotts.is_due(active, 10)
    @test CorePotts.is_due(active, 120)
    @test CorePotts.is_due(active, 210)
    @test !CorePotts.is_due(active, 211)
    @test_throws ArgumentError CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(:fragment14_invalid_activation,
            CorePotts.Update(process; active = :hidden_scheduler)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(),
    )
end
