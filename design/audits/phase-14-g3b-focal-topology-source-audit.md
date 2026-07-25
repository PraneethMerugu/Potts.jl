# Phase 14.1 G3-B Focal-Topology Source Audit

Status: primary-source semantics frozen; implementation and live-runtime oracle in progress

Date: 2026-07-25

## Authority

The implementation target is CompuCell3D tag `4.2.5`, commit
`4ca1f2919a5da53111d2027d2e00b626aba1cd28`, not current plugin behavior.

Primary files:

- `FocalPointPlasticityPlugin.cpp`, SHA-256
  `900adcfcc6559aa1ff897b100689ef00014f9482fb955057b9fc87c7c0c4a94f`;
- `FocalPointPlasticityTracker.h`, SHA-256
  `eae7fc6184660f277bec5f397885fdfcadbd5f4c749b3e67599ffc47d2d3b804`;
- Wang Figure 3 radial XML, SHA-256
  `50f2c66d58ff85532bad671d90e6a247a101444a86324cca2b486f5ff98a6ee9`;
  and
- Wang Figure 3 radial steppables, SHA-256
  `2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30`.

The first two files are available from the
[CompuCell3D 4.2.5 source tree](https://github.com/CompuCell3D/CompuCell3D/tree/4.2.5/CompuCell3D/core/CompuCell3D/plugins/FocalPointPlasticity).
The Wang source is pinned by the G3-B source revision and local source archive.

## Exact proposal semantics

For an actionable ownership-copy proposal:

1. only the finite gaining cell can initiate a new external junction;
2. the plugin scans the configured `NeighborOrder=3` sites around the recipient;
3. ordinary runs apply `std::random_shuffle` to direction indices, while CC3D test/generate mode
   keeps the native direction order;
4. Medium, self, same-cluster, unsupported type pairs, degree-saturated endpoints, and existing
   pairs are skipped;
5. the first eligible neighbor is selected;
6. the candidate contributes activation energy `-50` and returns immediately, without adding the
   existing-link spring terms for that proposal; and
7. only the accepted field change creates the link.

The XML admits at most four cell--cell junctions per endpoint/type pair. The accepted link initially
inherits the XML tracker defaults: strength 0, target length 0, and maximum length 100000. The
later Python retune on `source_mcs % 10 == 0` changes every existing link to the current focal
strength, target 8, and maximum 12.

## Accepted-copy removal semantics

The accepted field-change callback:

- removes every incident link when the losing endpoint becomes extinct;
- otherwise checks the gaining endpoint and then the losing endpoint;
- for each affected endpoint, removes at most one external link whose centroid distance exceeds
  that link's stored maximum length; and
- performs removal after any newly initiated link has been created.

This is proposal/accepted-copy behavior, not an end-of-MCS graph reconstruction.

## RNG normalization

`std::random_shuffle` is an implicit mutable C-runtime RNG and therefore cannot be a portable
backend contract. Revision 4 separates two claims:

- the source-faithful CPU oracle records ordinary shuffled behavior, test-mode unshuffled behavior,
  and the pinned runtime seed behavior; and
- the portable profile assigns neighbor permutation to
  `wang/focal-topology/neighbor-permutation` in the semantic Philox RNG contract.

Portable results must match the exact eligible set, degree/capacity rules, acceptance visibility,
and selection distribution. They do not claim bitwise replay of `std::rand`.

## Remaining oracle

Static source inspection is sufficient to freeze implementation semantics but not to close the
runtime row. The G3-B Potts/FPP oracle must still emit controlled traces for selection order,
activation energy, accepted/rejected/no-op proposals, initial payload, degree rejection,
overlength removal order, and endpoint extinction.
