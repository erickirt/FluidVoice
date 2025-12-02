import Foundation
import Security

enum KeychainServiceError: Error, LocalizedError {
    case invalidData
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Failed to convert key data."
        case .unhandled(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Unhandled Keychain status: \(status)"
        }
    }
}

/// Lightweight helper for storing provider API keys in the system Keychain.
/// Keys are stored as generic passwords scoped to the FluidVoice service.
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.fluidvoice.provider-api-keys"

    private init() {}

    func storeKey(_ key: String, for providerID: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainServiceError.invalidData
        }

        var attributes = baseQuery(for: providerID)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(baseQuery(for: providerID) as CFDictionary,
                                             [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainServiceError.unhandled(updateStatus)
            }
        default:
            throw KeychainServiceError.unhandled(status)
        }
    }

    func fetchKey(for providerID: String) throws -> String? {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw KeychainServiceError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainServiceError.unhandled(status)
        }
    }

    func deleteKey(for providerID: String) throws {
        let status = SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unhandled(status)
        }
    }

    func containsKey(for providerID: String) -> Bool {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = kCFBooleanFalse
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func allProviderIDs() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        switch status {
        case errSecSuccess:
            guard let attributesArray = items as? [[String: Any]] else { return [] }
            return attributesArray.compactMap { $0[kSecAttrAccount as String] as? String }
        case errSecItemNotFound:
            return []
        default:
            throw KeychainServiceError.unhandled(status)
        }
    }

    private func baseQuery(for providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID
        ]
    }
}

