import Foundation
import Security

struct KeychainCredentials {
    private let service = "cc.wyderka.hermes-pocket.gateway"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "connection"]
    }

    func read() throws -> GatewayCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GatewayError.storage("Cannot read the saved connection from Keychain (\(status)).")
        }
        return try JSONDecoder().decode(GatewayCredentials.self, from: data)
    }

    func save(_ credentials: GatewayCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw GatewayError.storage("Cannot save the connection in Keychain (\(status)).") }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GatewayError.storage("Cannot remove the connection from Keychain (\(status)).")
        }
    }
}
