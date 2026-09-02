module PottsUnitfulExt

using Potts
import DynamicQuantities
import Unitful

function Potts.to_dynamic_quantity(value::Unitful.AbstractQuantity)
    return convert(DynamicQuantities.Quantity, value)
end

function Potts.to_dynamic_quantity(
        values::AbstractArray{<:Unitful.AbstractQuantity}
    )
    return DynamicQuantities.QuantityArray(
        Potts.to_dynamic_quantity.(values)
    )
end

function Potts.to_unitful_quantity(
        value::DynamicQuantities.UnionAbstractQuantity
    )
    return convert(Unitful.Quantity, value)
end

function Potts.to_unitful_quantity(
        values::DynamicQuantities.QuantityArray
    )
    return Potts.to_unitful_quantity.(values)
end

end
