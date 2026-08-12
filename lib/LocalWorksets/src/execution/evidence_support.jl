# Shared construction of the fixed determinism-report schema. Lowerings must
# still supply every qualified guarantee explicitly; this helper supplies no
# semantic defaults and never participates in execution selection.

function _determinism_report(
        qualifier::NamedTuple,
        guarantees::NTuple{8, Symbol},
    )
    return NamedTuple{_DETERMINISM_DIMENSIONS}(
        map(guarantee -> merge(qualifier, (; guarantee)), guarantees)
    )
end

# Every executable output family reports this semantic envelope. Callers must
# supply every field; family-specific evidence may only add, never replace,
# facts in the common contract.
function _port_evidence(
        family::Symbol,
        route,
        destination_count::Int,
        maximum_emissions::Int,
        coverage::Symbol,
        law::NamedTuple,
        publication_phase::Symbol,
        post_launch_failure_visibility::Symbol,
        empty_destination,
        determinism::NamedTuple,
        extra::NamedTuple = (;),
    )
    common_names = (
        :family,
        :route,
        :destination_count,
        :maximum_emissions,
        :coverage,
        :law,
        :publication_phase,
        :post_launch_failure_visibility,
        :empty_destination,
        :determinism,
    )
    isempty(intersect(Set(common_names), Set(keys(extra)))) || throw(
        LocalWorkValidationError(
            "family-specific port evidence cannot replace required semantic fields"
        )
    )
    return merge((;
        family,
        route,
        destination_count,
        maximum_emissions,
        coverage,
        law,
        publication_phase,
        post_launch_failure_visibility,
        empty_destination,
        determinism,
    ), extra)
end

function _winner_workspace_evidence(
        spec::Tuple,
        destination_count::Int,
        rank_name::Symbol,
        identity_name::Symbol,
    )
    rank_leaf = invoke(
        _workspace_leaf_by_name,
        Tuple{Tuple, Symbol},
        spec,
        rank_name,
    )
    identity_leaf = invoke(
        _workspace_leaf_by_name,
        Tuple{Tuple, Symbol},
        spec,
        identity_name,
    )
    rank_type = typeof(rank_leaf).parameters[1]
    identity_type = typeof(identity_leaf).parameters[1]
    return (
        destination_count,
        rank = (
            element_type = rank_type,
            length = destination_count,
            alignment = Base.datatype_alignment(rank_type),
            bytes = invoke(
                _workspace_leaf_bytes,
                Tuple{_WorkspaceLeaf},
                rank_leaf,
            ),
        ),
        identity = (
            element_type = identity_type,
            length = destination_count,
            alignment = Base.datatype_alignment(identity_type),
            bytes = invoke(
                _workspace_leaf_bytes,
                Tuple{_WorkspaceLeaf},
                identity_leaf,
            ),
        ),
        total_bytes = invoke(_workspace_spec_bytes, Tuple{Tuple}, spec),
    )
end

function _winner_workspace_inspection(
        workspace,
        spec::Tuple,
        rank_name::Symbol,
        identity_name::Symbol,
    )
    rank_leaf = invoke(
        _workspace_leaf_by_name,
        Tuple{Tuple, Symbol},
        spec,
        rank_name,
    )
    identity_leaf = invoke(
        _workspace_leaf_by_name,
        Tuple{Tuple, Symbol},
        spec,
        identity_name,
    )
    rank_array = invoke(
        _workspace_leaf_value,
        Tuple{Any, _WorkspaceLeaf},
        workspace,
        rank_leaf,
    )
    identity_array = invoke(
        _workspace_leaf_value,
        Tuple{Any, _WorkspaceLeaf},
        workspace,
        identity_leaf,
    )
    return (
        rank_identity = objectid(rank_array),
        identity_identity = objectid(identity_array),
        rank_bytes = invoke(
            _workspace_leaf_bytes,
            Tuple{_WorkspaceLeaf},
            rank_leaf,
        ),
        identity_bytes = invoke(
            _workspace_leaf_bytes,
            Tuple{_WorkspaceLeaf},
            identity_leaf,
        ),
    )
end
