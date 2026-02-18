import Foundation

struct LayoutConfig: Codable {
    let defaultPair: String
    let pairs: [LayoutPair]

    struct LayoutPair: Codable {
        let id: String
        let name: String
        let left: LayoutSide
        let right: LayoutSide
    }

    struct LayoutSide: Codable {
        let id: String
        let name: String
        let script: String
        let map: [String: String]?
    }
}
