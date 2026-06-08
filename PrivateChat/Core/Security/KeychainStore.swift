import Foundation
import Security

protocol KeychainStoring {
    func readData(account: String) throws -> Data?
    func writeData(_ data: Data, account: String) throws
    func deleteData(account: String) throws
}

final class KeychainStore: KeychainStoring {
    private let service: String

    init(service: String = "org.francois.PrivateChat.keychain") {
        self.service = service
    }

    func readData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw PrivateChatError.keychainReadFailed(status: status)
        }

        return result as? Data
    }

    func writeData(_ data: Data, account: String) throws {
        try deleteDataIfExists(account: account)

        var query = baseQuery(account: account)
        query[kSecValueData] = data as CFData
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PrivateChatError.keychainWriteFailed(status: status)
        }
    }

    func deleteData(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PrivateChatError.keychainDeleteFailed(status: status)
        }
    }

    private func deleteDataIfExists(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
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
