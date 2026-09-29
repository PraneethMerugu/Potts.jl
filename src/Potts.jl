"""
Symbolic cellular Potts modeling on ModelingToolkit and SciML.

The symbolic front end (`@potts_model`, `PottsSystem`, `mtkcompile`, `PottsProblem`) is
specified in `docs/design/AUTHORING.md` and built in roadmap Phase 3. Until then this
package re-exports the numerical layer.
"""
module Potts

using CorePotts
for name in names(CorePotts)
    name === :CorePotts || @eval export $name
end

end
