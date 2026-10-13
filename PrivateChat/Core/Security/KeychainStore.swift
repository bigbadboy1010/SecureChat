import Foundation
import Security

protocol KeychainStoring {
    func readData(account: String) throws -> Data?
    func writeData(_ data: Data, account: String) throws
    func deleteData(account: String) throws
}

/// Injectable Security.framework boundary. Tests can exercise failed
/// writes without touching the user's actual keychain or identity.
struct KeychainSecurityAPI {
    let copyMatching: (CFDictionary) -> (OSStatus, CFTypeRef?)
    let update: (CFDictionary, CFDictionary) -> OSStatus
    let add: (CFDictionary) -> OSStatus
    let delete: (CFDictionary) -> OSStatus

    static let system = KeychainSecurityAPI(
        copyMatching: { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query, &result)
            return (status, result)
        },
        update: { SecItemUpdate($0, $1) },
        add: { SecItemAdd($0, nil) },
        delete: { SecItemDelete($0) }
    )
}

final class KeychainStore: KeychainStoring {
    private let service: String
    private let security: KeychainSecurityAPI
    private let lock = NSLock()

    init(
        service: String = "org.francois.PrivateChat.keychain",
        security: KeychainSecurityAPI = .system
    ) {
        self.service = service
        self.security = security
    }

    func readData(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery(account: account)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        let (status, result) = security.copyMatching(query as CFDictionary)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw PrivateChatError.keychainReadFailed(status: status)
        }

        guard let data = result as? Data else {
            throw PrivateChatError.keychainReadFailed(status: errSecDecode)
        }
        return data
    }

    func writeData(_ data: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let query = baseQuery(account: account)
        let attributes: [CFString: CFTypeRef] = [
            kSecValueData: data as CFData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = security.update(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            // Preserve the previous value on every failed update. In
            // particular, never delete a database or identity key first.
            throw PrivateChatError.keychainWriteFailed(status: updateStatus)
        }

        var addition = query
        for (key, value) in attributes {
            addition[key] = value
        }

        let addStatus = security.add(addition as CFDictionary)
        // Another writer may add the item after our item-not-found
        // result. Update that item rather than removing it or silently
        // leaving a stale value.
        let status = addStatus == errSecDuplicateItem
            ? security.update(query as CFDictionary, attributes as CFDictionary)
            : addStatus
        guard status == errSecSuccess else {
            throw PrivateChatError.keychainWriteFailed(status: status)
        }
    }

    func deleteData(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let status = security.delete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PrivateChatError.keychainDeleteFailed(status: status)
        }
    }

    private func baseQuery(account: String) -> [CFString: CFTypeRef] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString
        ]
    }
}
