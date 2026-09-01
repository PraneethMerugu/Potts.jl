@testset "curated public API" begin
    exported = Set(filter(
        name -> Base.isexported(LocalMath, name),
        names(LocalMath; all = true),
    ))
    @test exported == Set((
        :LocalMath, Symbol("@localmath"), Symbol("@prepare"),
        :Space, :Field, :Relation, :Collection, :LocalLaw,
        :IdentityRelation, :AffineRelation, :FixedRelation, :ProductRelation,
        :BoundaryRelation, :RuntimeRelation, :MaskedRelation, :SelectedRelation,
        :IndexRelation,
        :StrictBoundary, :PeriodicBoundary, :ExteriorBoundary, :MaskedBoundary,
        :GhostBoundary,
        :InverseRelation, :PackedRelation, :compose,
        :prepare, :execute!, :waitall, :workspace_requirements,
    ))

    qualified = Set((
        :Plan, :PreparedPlan, :ExecutionReceipt, :LocalMathValidationError,
        :bind, :plan, :Allocate, :Temporary, :MutableRelationStorage,
        :storage, :inspect,
        :compilation_report,
        :execution_contract, :lowering_identity,
        :Stage, :Publication, :Access, :Control, :SourceOrigin,
        :Parameter, :ParameterSchema,
        :Evaluator, :FieldPublication, :CollectionPublication,
        :FoldPublication, :PublicationValue,
        :CollectionAccess, :CollectionCount, :BoundedGroup,
        :SourcePositionAccess, :sequence, :allocate_workspace,
        :submission_capacity, :ispending, :success_gate,
        :one_group, :group_by, :source_order, :canonical_by,
        :persistent_source_position,
        :CompactedStorage, :BoundedGroupView,
        :Unique, :Reduce, :Resolve, :Collect, :OrderedFold,
        :TotalCoverage, :PartialCoverage, :UnreachableEmpty, :PreserveEmpty,
        :FillEmpty, :IdentitySeed, :ExistingSeed, :CanonicalLeftFold,
        :RelaxedAtomic, :ArgMin, :ArgMax, :CanonicalSourceLaneTie,
        :TieMin, :TieMax, :RejectOverflow, :EmptyCollection,
        :FoldComponent, :InitializedState, :initialized_state,
        :BoundedWrites, :FoldStep,
        :BoundedFold, :bounded_fold, :Where,
        :RejectInvalid, :SkipInvalid, :FillInvalid, :RejectEmpty,
        :RelaxedAssociative, :BoundedFoldOutcome, :evaluate_bounded,
        :UniqueValue, :ConditionalUniqueValue, :RoutedUniqueValue,
        :ConditionalRoutedUniqueValue, :Contribution, :RoutedContribution,
        :ResolutionValue, :RoutedResolutionValue, :CollectedValue,
        :GroupedCollectedValue, :FoldValue,
    ))
    public_qualified = Set(filter(
        name -> Base.ispublic(LocalMath, name) &&
            !Base.isexported(LocalMath, name),
        names(LocalMath; all = true),
    ))
    @test public_qualified == qualified
    @test all(name -> Base.ispublic(LocalMath, name), qualified)
    @test all(name -> !Base.isexported(LocalMath, name), qualified)
    @test !isdefined(LocalMath, :emit)
    @test !isdefined(LocalMath, :candidate)
    @test isempty(Base.Docs.undocumented_names(LocalMath; private = false))

    space = LocalMath.Space(2)
    product_space = LocalMath.Space((space, space))
    identity = LocalMath.IdentityRelation(space)
    product = LocalMath.ProductRelation(
        product_space => product_space, (identity, identity))
    mask = LocalMath.Field(space, Bool)
    ghost_space = LocalMath.Space(2)

    @test size(product_space) == (4,)
    empty_space_error = try
        LocalMath.Space(())
        nothing
    catch caught
        caught
    end
    @test empty_space_error isa LocalMath.LocalMathValidationError
    @test empty_space_error.contract == :space_dimension
    @test product isa LocalMath.Relation
    @test LocalMath.FixedRelation(space => space; degree=1) isa LocalMath.Relation
    @test LocalMath.RuntimeRelation(space => space;
        degree_bound=1, key_type=Int32) isa LocalMath.Relation
    @test LocalMath.InverseRelation(identity; degree_bound=1) isa LocalMath.Relation
    @test LocalMath.PackedRelation(space => space;
        degree_bound=1, capacity=2) isa LocalMath.Relation
    @test LocalMath.MaskedBoundary(mask, LocalMath.StrictBoundary()) isa
        LocalMath.MaskedBoundary
    @test LocalMath.GhostBoundary((1,), (1,), ghost_space) isa
        LocalMath.GhostBoundary
    @test LocalMath.FoldValue(Int32(3)).value == Int32(3)
    @test LocalMath.Collect(Int32; maximum=1) isa LocalMath.Collect
    collection = LocalMath.Collection(Int32, 2)
    @test LocalMath.SourcePositionAccess(collection) isa LocalMath.CollectionAccess
    @test LocalMath.SourcePositionAccess(collection, 2) isa LocalMath.CollectionAccess
    @test !applicable(LocalMath.SourcePositionAccess, collection, Val(1))
    origin = LocalMath.SourceOrigin(:model_file, 7; label=:update)
    @test (origin.source, origin.line, origin.label) ==
        ("model_file", 7, :update)
    @test !applicable(LocalMath.SourceOrigin)
end
