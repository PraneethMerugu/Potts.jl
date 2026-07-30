module PottsToolkitUnitfulExt

using PottsToolkit
import DynamicQuantities
import Unitful

function PottsToolkit.to_dynamic_quantity(value::Unitful.AbstractQuantity)
    return convert(DynamicQuantities.Quantity, value)
end

function PottsToolkit.to_dynamic_quantity(
        values::AbstractArray{<:Unitful.AbstractQuantity}
    )
    return DynamicQuantities.QuantityArray(
        PottsToolkit.to_dynamic_quantity.(values)
    )
end

function PottsToolkit.to_unitful_quantity(
        value::DynamicQuantities.UnionAbstractQuantity
    )
    return convert(Unitful.Quantity, value)
end

function PottsToolkit.to_unitful_quantity(
        values::DynamicQuantities.QuantityArray
    )
    return PottsToolkit.to_unitful_quantity.(values)
end

end
