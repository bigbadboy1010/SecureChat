import Foundation
import PrivateRoomOlm

/// This bridge owns no cryptographic construction: vodozemac performs 3DH,
/// chain advancement, skipped-key handling, authentication, and key erasure.
enum OlmBridge {
    struct Result {
        let state: String
        let identity: String?
        let keys: [String: String]?
        let sessionID: String?
        let message: OlmWireMessage?
        let plaintext: String?
    }
    static func execute(_ action: String, state: String? = nil, parameters: [String: Any] = [:]) throws -> Result {
        var request = parameters
        request["action"] = action
        if let state { request["state"] = try JSONSerialization.jsonObject(with: Data(state.utf8)) }
        let bytes = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        let pointer = bytes.withUnsafeBytes { buffer in pr_olm_execute(buffer.bindMemory(to: UInt8.self).baseAddress, bytes.count) }
        guard let pointer else { throw ForwardSecretError.engine("unavailable") }
        defer { pr_olm_free(pointer) }
        let response = Data(bytes: pointer, count: strlen(pointer))
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw ForwardSecretError.engine("response") }
        if let code = object["error"] as? String { throw ForwardSecretError.engine(code) }
        guard let newState = object["state"] else { throw ForwardSecretError.engine("missing_state") }
        let stateBytes = try JSONSerialization.data(withJSONObject: newState, options: [.sortedKeys])
        var message: OlmWireMessage?
        if let value = object["message"] { message = try JSONDecoder().decode(OlmWireMessage.self, from: JSONSerialization.data(withJSONObject: value)) }
        return Result(state: String(decoding: stateBytes, as: UTF8.self), identity: object["identity"] as? String,
                      keys: object["keys"] as? [String: String], sessionID: object["session_id"] as? String,
                      message: message, plaintext: object["plaintext"] as? String)
    }
}

enum ForwardSecretError: LocalizedError {
    case engine(String), unavailable, identityChanged, invalidBundle, persistence
    var errorDescription: String? {
        switch self {
        case .engine: return "Die geschützte Sitzung konnte die Nachricht nicht verarbeiten. Es wird keine schwächere Verschlüsselung verwendet."
        case .unavailable: return "Der Kontakt muss die neue PrivateRoom-Version installieren und einmal online entsperren, damit Einmalschlüssel verfügbar sind."
        case .identityChanged: return "Der Sitzungsschlüssel des Kontakts hat sich geändert. Senden wurde zum Schutz deiner Nachrichten gestoppt."
        case .invalidBundle: return "Die Einmalschlüssel des Kontakts konnten nicht authentifiziert werden."
        case .persistence: return "Der geschützte Sitzungszustand konnte nicht dauerhaft gespeichert werden. PrivateRoom bleibt gesperrt."
        }
    }
}
struct OlmWireMessage: Codable, Equatable { let type: Int; let body: String }
struct OlmWireEnvelope: Codable { let version: Int; let identity: String; let sessionID: String; let message: OlmWireMessage }
struct OlmPrekey: Codable, Equatable { let id: String; let key: String; let expiresAt: String; let signatureBase64: String }
struct OlmPrekeyStatus: Codable { let identity: String?; let sequence: Int; let available: Int }
struct OlmPrekeyBatch: Codable { let identity: String; let identitySignatureBase64: String; let sequence: Int; let keys: [OlmPrekey] }
struct OlmPrekeyClaim: Codable { let requester: String; let recipientID: String; let claimID: UUID; let identity: String; let identitySignatureBase64: String; let prekey: OlmPrekey }

enum OlmCommitment {
    static func data(_ fields: [String]) -> Data {
        var bytes = Data()
        for field in fields {
            let value = Data(field.utf8)
            var size = UInt32(value.count).bigEndian
            withUnsafeBytes(of: &size) { bytes.append(contentsOf: $0) }
            bytes.append(value)
        }
        return bytes
    }
}
