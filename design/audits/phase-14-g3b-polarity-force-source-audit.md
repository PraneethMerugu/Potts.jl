# Phase 14.1 G3-B Polarity and Force Source Audit

Status: primary-source semantics frozen; isolated CPU and portable-reference implementation passing

Date: 2026-07-25

## Authority

The target is the Wang Figure 3 radial steppable at source revision
`60ebcf013aafefdff39ebe566114ee79f2a6e54d`, file
`s4_figures/Figure3/Radial/Simulation/fpp_polarity_force_Steppables.py`, SHA-256
`2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30`.

## Neighbor-polarity semantics

For every source MCS greater than 120:

1. `get_cell_neighbor_data_list(cell)` supplies every finite contact neighbor once plus Medium;
2. Medium is ignored and common surface area is not used as a weight;
3. the source stores every cell's mean neighbor `x_self_polarity` and `y_self_polarity` before
   publishing any aligned polarity, so the update is synchronous;
4. an empty finite-neighbor set contributes the zero vector;
5. `p_frac = min(lambda_fpp / 1000, 1) * 0.4`;
6. the mixed vector is `p_frac * neighbor_mean + (1-p_frac) * self_polarity`; and
7. the mixed vector is normalized, with an exactly zero norm left unchanged.

The Python source obtains `lambda_fpp` from the loop variable remaining after the neighbor pass.
All Wang cells receive the same scheduled focal strength, so the source result is identical to a
per-cell read. The normalized generic process reads each cell's declared strength property; the
Wang assembly preserves the source uniform-strength invariant.

## Contact-graph normalization

CC3D maintains `get_cell_neighbor_data_list` incrementally, but no Wang consumer observes the graph
between the completed Potts phase and polarity alignment. Potts.jl therefore materializes a
bounded symmetric Boolean adjacency matrix from the immutable post-Potts ownership snapshot and a
declared contact relation at alignment entry.

This is semantically exact for the source operation:

- a finite pair is adjacent iff at least one realized contact-relation site pair has those owners;
- repeated contact faces idempotently set the same integer matrix entry;
- Medium and self contacts do not set an entry;
- neighbor reduction visits ascending persistent cell slots and counts each adjacent cell once;
  and
- the matrix is attempt workspace, not checkpointed scientific state.

The portable builder uses only idempotent integer atomics. Floating atomics and scheduler-dependent
floating reductions are absent.

## Protrusion-force semantics

After aligned polarity is published, each cell computes

`h = rac^4 / (40^4 + rac^4)`,

then publishes:

- `f_coef = h`;
- `f = force_strength_max * h`;
- `f_x = -force_strength_max * h * x_self_polarity`;
- `f_y = -force_strength_max * h * y_self_polarity`; and
- CC3D `lambdaVecX/Y = f_x/f_y`.

The generic process exposes the half activation, positive integer exponent, maximum magnitude, and
signed direction as typed parameters. The Wang assembly fixes them to 40, 4, the scanned maximum,
and -1 respectively.

## ExternalPotential consumption

Wang loads an empty `<Plugin Name="ExternalPotential"/>` declaration. In CC3D 4.2.5,
`ExternalPotentialPlugin::update` therefore selects `BYCELLID` and, because no `Algorithm` child
requests `CenterOfMassBased`, dispatches to the pixel-based
`ExternalPotentialPlugin::changeEnergyByCellId` implementation
(`ExternalPotentialPlugin.cpp:95-130`).

That implementation (`ExternalPotentialPlugin.cpp:571-685`) visits the face-adjacent neighbors of
the recipient pixel, applies the plugin's periodic displacement correction, accumulates the old
cell's vector coefficient for faces whose neighbor is not the old cell, accumulates the new
cell's coefficient for faces whose neighbor is not the new cell, and returns
`deltaEnergyNew - deltaEnergyOld`. Therefore Wang's force must be consumed as a generic per-cell
vector boundary-potential Hamiltonian. It must not be replaced by a visually similar
donor-to-recipient displacement bias.

The relevant CC3D 4.2.5 source identities are:

- `ExternalPotentialPlugin.cpp`, SHA-256
  `7e87a6d130b6195db1da33f3743167faf081c48a66edb4053e03e2a1645324ba`;
- `Cell.h`, SHA-256
  `0601a1745b2be7fd008548137098878e1b05deeee87dd6eb5f613625bbca55a6`;
  and
- CC3D tag `4.2.5`, commit
  `4ca1f2919a5da53111d2027d2e00b626aba1cd28`.

The source's own cell-motility tutorial states the sign convention directly: negative
`lambdaVecX` drives positive-x motion. Wang's negative Hill-scaled coefficients are therefore
consistent with motion along the published polarity vector. The phase-9 publication occurs after
the current MCS Potts phase and is visible to the next MCS.

## Completed source evidence

The controlled source-derived ExternalPotential fixtures cover gaining-only, losing-only,
two-cell replacement, periodic-edge, zero-force, compiled scientific evaluation, and portable
kernel execution. The assembled runtime activates polarity, intracellular dynamics, alignment,
force, and observation only on target MCS 122:500 and fixes the radial source parameters
`focal_strength=20`, half activation 40, exponent 4, and maximum force 150.
