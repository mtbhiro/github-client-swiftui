import Foundation

nonisolated enum DTOMappingError: Error, Equatable {
    case invalidURL(field: String, value: String)
    case invalidDate(field: String, value: String)
}
