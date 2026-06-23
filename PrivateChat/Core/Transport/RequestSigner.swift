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

    /// Build the canonical query string
    /// from a `[URLQueryItem]` array:
    /// pairs are sorted by name, then by
    /// value, joined with `&`, each
    /// pair formatted as `name=value`
    /// (percent-encoded). This matches
    /// the relay's `canonical-query-string`
    /// helper (see
    /// `RelayServer/src/peerAuth.ts`).
    public static func canonicalQueryString(
        from items: [URLQueryItem]
    ) -> String {
        let pairs = items
            .compactMap { item -> (String, String)? in
                guard
                    let name = item.name.addingPercentEncoding(
                        withAllowedCharacters: .urlQueryAllowed
                    )
                else { return nil }
                let value = item.value ?? ""
                let encodedValue = value.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ) ?? ""
                return (name, encodedValue)
            }
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
        return pairs
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    /// Sign a request and produce the four
    /// peer-bound headers. The `timestamp`
    /// and `nonce` are passed in by the
    /// caller; the production `RelayTransport`
    /// pipeline generates them per request
    /// (timestamp = now, nonce = 32 random
    /// bytes).
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
        let signatureHex = signature?
            .map { String(format: "%02x", $0) }
            .joined() ?? ""
        return SignedHeaders(
            peerID: peerID,
            timestamp: timestamp,
            nonce: nonce,
            signature: signatureHex
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

    /// 32 random bytes, hex encoded. Used
    /// for the `X-Securechat-Nonce` value
    /// (the relay caches seen nonces for
    /// ~10 minutes).
    public static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
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
        return bytes
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Current unix epoch in seconds,
    /// as a string. The relay requires the
    /// timestamp to be within
    /// ±`maxClockSkewSeconds` (default 300s).
    public static func currentTimestamp() -> String {
        let seconds = Int(Date().timeIntervalSince1970)
        return String(seconds)
    }
}
