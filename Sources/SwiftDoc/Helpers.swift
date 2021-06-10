import Foundation

public func route(for symbol: Symbol) -> String {
    return route(for: symbol.id)
}

public func route(for name: CustomStringConvertible) -> String {
    return name.description.replacingOccurrences(of: " ", with: "-")
}

public func path(for symbol: Symbol, with baseURL: String) -> String {
    return path(for: route(for: symbol), with: baseURL)
}

public func path(for identifier: CustomStringConvertible, with baseURL: String) -> String {
    let tail: String = path(for: "\(identifier)")
    let url = URL(string: baseURL)?.appendingPathComponent(tail) ?? URL(string: tail)
    guard let string = url?.absoluteString else {
        fatalError("Unable to construct path for \(identifier) with baseURL \(baseURL)")
    }
    // Let's for convenience remove underscores from all types except the ones we need:
    let omittedTypesWithUnderscore = [
        "_Button",
        "_View", 
        "_Control",
        "_CollectionReusableView", 
        "_CollectionViewCell",
        "_NavigationBar",
        "_ViewController"
    ]

    if !omittedTypesWithUnderscore.contains(where: string.contains) {
        return string.replacingOccurrences(of: "_", with: "")
    }
    return string
}

private let reservedCharacters: CharacterSet = [
    // Windows Reserved Characters
    "<", ">", ":", "\"", "/", "\\", "|", "?", "*",
]

public func path(for identifier: String) -> String {
    return identifier.components(separatedBy: reservedCharacters).joined(separator: "_")
}
