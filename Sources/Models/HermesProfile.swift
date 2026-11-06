import Foundation

struct HermesProfile: Identifiable, Sendable, Equatable {
    var name: String
    var displayName: String
    var path: String
    var isDefault: Bool

    var id: String { name }
    var title: String { displayName.isEmpty ? name : displayName }

    /// Decode only the roster metadata needed by the picker, never session previews.
    static func decodeRoster(_ value: JSONValue) throws -> [HermesProfile] {
        guard let rows = value["profiles"].array else {
            throw GatewayError.invalidResponse("Hermes returned an invalid profile list. Try again.")
        }
        var seen = Set<String>()
        return try rows.map { row in
            guard let name = row["name"].string, !name.isEmpty,
                  name == name.trimmingCharacters(in: .whitespacesAndNewlines),
                  let path = row["path"].string, !path.isEmpty,
                  seen.insert(name).inserted else {
                throw GatewayError.invalidResponse("Hermes returned a profile without a unique name and home.")
            }
            if let display = row.object?["display_name"], display != .null, display.string == nil {
                throw GatewayError.invalidResponse("Hermes returned an invalid profile display name.")
            }
            if let flag = row.object?["is_default"], flag.bool == nil {
                throw GatewayError.invalidResponse("Hermes returned an invalid default profile flag.")
            }
            return HermesProfile(name: name, displayName: row["display_name"].string ?? "",
                                 path: path, isDefault: row["is_default"].bool ?? false)
        }
    }

    static func normalizedName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    /// config.get(profile) is answered by the routed authority, including for an empty profile.
    static func verifiedHome(_ value: JSONValue, expectedPath: String? = nil) throws -> String {
        guard let home = value["home"].string, !home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expectedPath == nil || home == expectedPath else {
            throw GatewayError.invalidResponse("Hermes could not verify the selected profile. Choose it again; no other profile was opened.")
        }
        return home
    }
}
