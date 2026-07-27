module ProcessBigraphsSciMLExt

import CommonSolve
import ProcessBigraphs
import SciMLBase

# Phase 16.A establishes only the dependency and extension boundary. The bounded
# field adapter methods are introduced and qualified in Phase 16.F; keeping the
# extension method-free here prevents SciML types from entering ProcessBigraphs core.
const CONTRACT_VERSION = "process-bigraphs-sciml-extension-v1"

end
