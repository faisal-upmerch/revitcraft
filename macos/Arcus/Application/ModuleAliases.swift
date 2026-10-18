import ArcusDomain
import ArcusCalc

// Disambiguate Domain names that collide with Foundation/ObjectiveC types (ObjectiveC.Category, Foundation.Dimension).
public typealias Category = ArcusDomain.Category
public typealias QuantityDimension = ArcusCalc.Dimension
