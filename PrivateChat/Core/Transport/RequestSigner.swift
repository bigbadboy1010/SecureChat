// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RequestSigner.swift
// Phase 2-15A: iOS canonical request
// signing for the relay's peer-bound auth
// layer (see Docs/ADR-005-peer-bound-relay-auth.md
// and Docs/RELAY_API_CONTRACT.md §6).
//
// The relay accepts a peer-bound Ed25519
// signature over a canonical string built
// from the HTTP method, request path, the
// canonicalized query string, a SHA-256 of
// the body, the request timestamp, the
// request nonce, and the peer's long-form
// public peer id.
//
// This file is **pure** (no UI, no I/O)
// and **fully testable**: the only
// dependency is the Swift CryptoKit
// `Curve25519.Signing.PrivateKey` and
// `SHA256`.

import Foundation
import CryptoKit

/// Builds the canonical-string input for the
/// relay's peer-bound request signing
/// (see `RELAY_API_CONTRACT.md` §6) and
/// signs it with the peer's long-term
/// Ed25519 signing key.
public enum RequestSigner {
    /// The four header values returned for a
    /// given request. The relay will verify
    /// them on the server side against the
    /// registered peer public key, the
    /// timestamp, and a nonce cache.
    public struct SignedHeaders: Equatable, Sendable {
        public let peerID: String
        public let timestamp: String
        public let nonce: String
        public let signature: String

        public init(
            peerID: String,
            timestamp: String,
            nonce: String,
            signature: String
        ) {
            self.peerID = peerID
            self.timestamp = timestamp
            self.nonce = nonce
            self.signature = signature
        }
    }

    /// Build the canonical string input for
    /// a request. Format (newlines `\n`, no
    /// trailing newline):
    ///
    ///     <HTTP-METHOD>\n
    ///     <request-path>\n
    ///     <query-string-canonicalized>\n
    ///     <body-sha256-hex>\n
    ///     <timestamp>\n
    ///     <nonce>\n
    ///     <peer-id>
    ///
    /// The `queryStringCanonicalized`
    /// argument MUST be the already
    /// sorted, percent-encoded,
    /// `&`-joined query string that
    /// matches what the server will see on
    /// the wire (the relay canonicalizes
    /// the query before computing the
    /// body hash). See `canonicalQueryString`
    /// for the helper that does this.
    public static func canonicalString(
        method: String,
        path: String,
        queryStringCanonicalized: String,
        body: Data?,
        timestamp: String,
        nonce: String,
        peerID: String
    ) -> String {
        let bodyHash = sha256Hex(body ?? Data())
        return [
            method.uppercased(),
            path,
            queryStringCanonicalized,
            bodyHash,
            timestamp,
            nonce,
            peerID
        ].joined(separator: "\n")
    }

    /// Build the canonical query string from a `[URLQueryItem]` array.
    /// The relay sorts parameters by name and applies JavaScript's
    /// `encodeURIComponent` character set before joining them with `&`.
    public static func canonicalQueryString(
        from items: [URLQueryItem]
    ) -> String {
        let groupedItems = Dictionary(grouping: items, by: \URLQueryItem.name)
        let pairs = groupedItems.compactMap { name, grouped -> (String, String)? in
            guard let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: encodeURIComponentAllowedCharacters
            ) else {
                return nil
            }
            let combinedValue = grouped.map { $0.value ?? "" }.joined(separator: ",")
            let encodedValue = combinedValue.addingPercentEncoding(
                withAllowedCharacters: encodeURIComponentAllowedCharacters
            ) ?? ""
            return (encodedName, encodedValue)
        }
        .sorted { $0.0 < $1.0 }
        return pairs
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    /// Sign a request and produce the four
    /// peer-bound headers. The `timestamp`
    /// and `nonce` are passed in by the
    /// caller; the production `RelayTransport`
    /// pipeline generates them per request
    /// (timestamp = RFC3339 now, nonce = Base64URL of 16 random bytes).
    public static func sign(
        method: String,
        path: String,
        queryStringCanonicalized: String,
        body: Data?,
        timestamp: String,
        nonce: String,
        peerID: String,
        signingKey: Curve25519.Signing.PrivateKey
    ) -> SignedHeaders {
        let canonical = canonicalString(
            method: method,
            path: path,
            queryStringCanonicalized: queryStringCanonicalized,
            body: body,
            timestamp: timestamp,
            nonce: nonce,
            peerID: peerID
        )
        let signature = try? signingKey.signature(
            for: Data(canonical.utf8)
        )
        let signatureBase64URL = signature.map { base64URLEncoded($0) } ?? ""
        return SignedHeaders(
            peerID: peerID,
            timestamp: timestamp,
            nonce: nonce,
            signature: signatureBase64URL
        )
    }

    /// SHA-256 over a `Data` blob, hex
    /// encoded (lowercase, no separator).
    /// Equivalent to `crypto.createHash
    /// ("sha256").update(...).digest("hex")`
    /// in Node.
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// 16 random bytes, unpadded Base64URL encoded. This is the exact
    /// wire format consumed by `RelayServer/src/peerAuth.ts`.
    public static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        )
        // `SecRandomCopyBytes` only fails on
        // programmer error (e.g. asking for
        // a negative count); in production
        // we will never see a non-zero
        // status. Fall back to SystemRandom
        // so the request is not rejected
        // outright on a buggy host.
        if status != errSecSuccess {
            var fallback = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(
                    in: UInt8.min ... UInt8.max,
                    using: &fallback
                )
            }
        }
        return base64URLEncoded(Data(bytes))
    }

    /// Current RFC3339 timestamp. The relay parses this value with
    /// JavaScript `Date.parse` and requires it to be within ±5 minutes.
    public static func currentTimestamp() -> String {
        DateCoding.string(from: Date())
    }

    nonisolated static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let encodeURIComponentAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )
}
