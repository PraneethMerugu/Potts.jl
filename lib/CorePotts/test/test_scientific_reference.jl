function _three_site_attempt_outcomes(mask::Int, target::Int, offset::Int)
    source = mod1(target + offset, 3)
    target_owner = (mask >> (target - 1)) & 1
    source_owner = (mask >> (source - 1)) & 1
    target_owner == source_owner && return ((mask, 1.0),)

    volume = count_ones(mask)
    allowed = source_owner == 1 ? volume < 2 : volume > 1
    allowed || return ((mask, 1.0),)
    accepted = source_owner == 1 ?
               mask | (1 << (target - 1)) :
               mask & ~(1 << (target - 1))
    probability = source_owner == 1 ? 0.5 : 1.0
    isone(probability) && return ((accepted, 1.0),)
    return ((accepted, probability), (mask, 1 - probability))
end

function _three_site_transition_matrix()
    transition = zeros(Float64, 8, 8)
    for mask in 0:7, target in 1:3, offset in (-1, 1)
        for (result, probability) in _three_site_attempt_outcomes(
                mask, target, offset
            )
            transition[mask + 1, result + 1] += probability / 6
        end
    end
    return transition
end

@testset "independent finite three-site scientific oracle" begin
    # The matrix is enumerated from the model definition, independently of the
    # Core executor: one uniformly selected directed neighbor copy, unit
    # temperature, energy log(2) per occupied site, and constraints that keep
    # the finite cell volume in 1:2.
    transition = _three_site_transition_matrix()
    @test all(>=(0), transition)
    @test vec(sum(transition; dims = 2)) ≈ ones(8) atol = 1e-15
    @test transition[1, 1] ≈ 1 atol = 1e-15
    @test transition[8, 8] ≈ 1 atol = 1e-15

    two_step = zeros(Float64, 8, 8)
    for initial in 0:7, first_target in 1:3, first_offset in (-1, 1)
        for (middle, first_probability) in _three_site_attempt_outcomes(
                initial, first_target, first_offset
            )
            for second_target in 1:3, second_offset in (-1, 1)
                for (final, second_probability) in _three_site_attempt_outcomes(
                        middle, second_target, second_offset
                    )
                    two_step[initial + 1, final + 1] +=
                        first_probability * second_probability / 36
                end
            end
        end
    end
    @test two_step ≈ transition * transition atol = 1e-15

    rotate(mask) = ((mask << 1) & 7) | ((mask >> 2) & 1)
    for initial in 0:7, final in 0:7
        @test transition[initial + 1, final + 1] ≈
              transition[rotate(initial) + 1, rotate(final) + 1]
    end

    gibbs = zeros(Float64, 8)
    for mask in 1:6
        gibbs[mask + 1] = exp(-log(2.0) * count_ones(mask))
    end
    gibbs ./= sum(gibbs)
    @test vec(permutedims(gibbs) * transition) ≈ gibbs atol = 1e-15
    for first in 1:6, second in 1:6
        @test gibbs[first + 1] * transition[first + 1, second + 1] ≈
              gibbs[second + 1] * transition[second + 1, first + 1] atol = 1e-15
    end

    # Tie the independent oracle to the shared production acceptance law
    # without using the executor's transition implementation.
    extension = CorePotts.ProposalEvaluation(
        log(2.0), 0.0, 0.0, 0.0, true
    )
    retraction = CorePotts.ProposalEvaluation(
        -log(2.0), 0.0, 0.0, 0.0, true
    )
    constrained = CorePotts.ProposalEvaluation(
        -log(2.0), 0.0, 0.0, 0.0, false
    )
    @test CorePotts.proposal_acceptance_probability(extension, 1.0) == 0.5
    @test CorePotts.proposal_acceptance_probability(retraction, 1.0) == 1.0
    @test CorePotts.proposal_acceptance_probability(constrained, 1.0) == 0.0
end
