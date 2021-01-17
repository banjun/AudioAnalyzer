import Combine

// https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Sources/Optional.swift
/// An optional protocol for use in type constraints.
protocol OptionalProtocol: ExpressibleByNilLiteral {
    /// The type contained in the optional.
    associatedtype Wrapped
    /// Extracts an optional from the receiver.
    var optional: Wrapped? { get }
}
extension Optional: OptionalProtocol {
    var optional: Wrapped? { self }
}
extension Publisher where Output: OptionalProtocol {
    func skipNil() -> Publishers.CompactMap<Self, Output.Wrapped> {
        compactMap {$0.optional}
    }
}

extension Publisher {
    func combinePrevious(_ initialValue: Output) -> Publishers.Scan<Self, (Output, Output)> {
        scan((initialValue, initialValue)) {($0.1, $1)}
    }

    func combinePrevious() -> Publishers.FlatMap<Publishers.Scan<Self, (Output, Output)>, Publishers.Output<Self>> {
        prefix(1).flatMap {self.combinePrevious($0)}
    }
}
