import Foundation

struct StoredTranscriptPage: Sendable {
    /// The server's physical continuation, never a canonical conversation identity.
    let sessionID: String
    let profile: String
    let messages: [ChatMessage]
    let rawCount: Int
    let nextOffset: Int
    let hasOlder: Bool

    init(_ result: JSONValue, expectedProfile: String, expectedOffset: Int) throws {
        guard !expectedProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, expectedOffset >= 0,
              let sessionID = result["session_id"].string, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let profile = result["profile"].string, profile == expectedProfile,
              let rows = result["messages"].array,
              let limit = result["pagination"]["limit"].int, (1...500).contains(limit),
              result["pagination"]["offset"].int == Int64(expectedOffset),
              result["pagination"]["order"].string == "latest",
              result["pagination"]["returned"].int == Int64(rows.count), rows.count <= Int(limit),
              expectedOffset <= Int.max - rows.count else {
            throw GatewayError.invalidResponse("Hermes returned an invalid stored conversation page or a different profile. Reload the conversation in its original profile.")
        }
        var messages: [ChatMessage] = []
        for (index, row) in rows.enumerated() {
            guard var projected = row.object else {
                throw GatewayError.invalidResponse("Hermes returned an invalid stored message. Try loading the conversation again.")
            }
            if row["display_kind"].string == "hidden" || row["display_metadata"]["model_only"].bool == true { continue }
            if let displayContent = projected["display_content"] {
                switch displayContent {
                case .string, .array, .null: break
                default: throw GatewayError.invalidResponse("Hermes returned invalid stored message display content. Try loading the conversation again.")
                }
                projected["content"] = displayContent
                // Null or empty display content must not fall back to raw alternate text.
                projected.removeValue(forKey: "text")
            }
            if row["role"].string == "tool", projected["name"]?.string == nil {
                projected["name"] = projected["tool_name"]
            }
            if let message = HermesStore.message(.object(projected), fallbackID: "stored:\(sessionID):\(expectedOffset + index)") {
                messages.append(message)
            }
        }
        self.sessionID = sessionID
        self.profile = profile
        self.messages = messages
        rawCount = rows.count
        nextOffset = expectedOffset + rows.count
        hasOlder = rows.count >= Int(limit)
    }
}
