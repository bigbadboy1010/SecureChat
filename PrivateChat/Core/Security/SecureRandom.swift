import Foundation
import Security

enum SecureRandom {
    static func data(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw PrivateChatError.invalidKeyMaterial
        }
        return Data(bytes)
    }
}
