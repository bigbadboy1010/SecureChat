// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RequestSignerTests.swift
// Phase 2-15C: unit tests for the
// peer-bound request signing layer.
// These tests are intentionally
// self-contained — they do not touch
// the network, the keychain, or the
// relay. They verify the canonical
// string, the body hash, the
// canonical query string, the
// signature round-trip, and the
// nonce/timestamp helpers.

import XCTest
import CryptoKit
@testable import PrivateChat

final class RequestSignerTests: XCTestCase {
    // MARK: - canonicalString

    func testCanonicalStringHasSevenLines() {
        let canonical = RequestSigner.canonicalString(
            method: "post",
            path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc",
            body: Data("hello".utf8),
            timestamp: "1700000000",
            nonce: "abcd",
            peerID: "peer"
        )
        let lines = canonical.split(separator: "\n")
        XCTAssertEqual(lines.count, 7, "canonical string must have exactly 7 lines")
        XCTAssertEqual(lines[0], "POST")
        XCTAssertEqual(lines[1], "/v1/relay/messages")
        XCTAssertEqual(lines[2], "recipientID=abc")
        XCTAssertEqual(lines[3], "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "body sha256 should be the SHA-256 of 'hello'")
        XCTAssertEqual(lines[4], "1700000000")
        XCTAssertEqual(lines[5], "abcd")
        XCTAssertEqual(lines[6], "peer")
    }

    func testMethodIsUppercased() {
        let canonical = RequestSigner.canonicalString(
            method: "delete",
            path: "/v1/relay/messages/abc",
            queryStringCanonicalized: "",
            body: nil,
            timestamp: "1700000000",
            nonce: "abcd",
            peerID: "peer"
        )
        XCTAssertTrue(canonical.hasPrefix("DELETE\n"))
    }

    func testEmptyBodyHashesToSHA256Empty() {
        let canonical = RequestSigner.canonicalString(
            method: "GET",
            path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc",
            body: nil,
            timestamp: "1700000000",
            nonce: "abcd",
            peerID: "peer"
        )
        // SHA-256 of the empty string
        XCTAssertTrue(
            canonical.contains(
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
        )
    }

    // MARK: - canonicalQueryString

    func testCanonicalQueryStringSortsByName() {
        let items = [
            URLQueryItem(name: "z", value: "1"),
            URLQueryItem(name: "a", value: "2")
        ]
        let canonical = RequestSigner.canonicalQueryString(from: items)
        XCTAssertEqual(canonical, "a=2&z=1")
    }

    func testCanonicalQueryStringSortsByValueWhenNameEqual() {
        let items = [
            URLQueryItem(name: "tag", value: "z"),
            URLQueryItem(name: "tag", value: "a")
        ]
        let canonical = RequestSigner.canonicalQueryString(from: items)
        XCTAssertEqual(canonical, "tag=a&tag=z")
    }

    func testCanonicalQueryStringPercentEncodesValues() {
        let items = [
            URLQueryItem(name: "q", value: "hello world")
        ]
        let canonical = RequestSigner.canonicalQueryString(from: items)
        XCTAssertEqual(canonical, "q=hello%20world")
    }

    func testCanonicalQueryStringNilValueTreatedAsEmpty() {
        let items = [
            URLQueryItem(name: "flag", value: nil)
        ]
        let canonical = RequestSigner.canonicalQueryString(from: items)
        XCTAssertEqual(canonical, "flag=")
    }

    // MARK: - sign

    func testSignProducesVerifiableSignature() {
        let signingKey = Curve25519.Signing.PrivateKey()
        let peerID = "peer-\(UUID().uuidString)"
        let signed = RequestSigner.sign(
            method: "POST",
            path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc",
            body: Data("hello world".utf8),
            timestamp: "1700000000",
            nonce: "abcd",
            peerID: peerID,
            signingKey: signingKey
        )
        let canonical = RequestSigner.canonicalString(
            method: "POST",
            path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc",
            body: Data("hello world".utf8),
            timestamp: "1700000000",
            nonce: "abcd",
            peerID: peerID
        )
        // Decode the hex-encoded signature
        // and verify it against the public
        // key — this is exactly what the
        // relay does server-side.
        guard let signatureBytes = Data(hexString: signed.signature) else {
            XCTFail("signature is not valid hex")
            return
        }
        let isValid = signingKey.publicKey.isValidSignature(
            signatureBytes,
            for: Data(canonical.utf8)
        )
        XCTAssertTrue(isValid, "the signature produced by sign() must verify under the public key")
    }

    func testSignedHeadersDifferAcrossCalls() {
        // CryptoKit's Ed25519 implementation
        // is non-deterministic: each call to
        // `signingKey.signature(for:)`
        // generates a fresh random nonce.
        // Two calls with the exact same
        // inputs must therefore produce
        // *different* signature bytes, even
        // though both are valid. The relay
        // does not depend on the signature
        // being deterministic — it depends
        // on the signature being verifiable
        // by the registered public key
        // (covered by
        // `testSignProducesVerifiableSignature`).
        let signingKey = Curve25519.Signing.PrivateKey()
        let peerID = "peer-1"
        let body = Data("body".utf8)
        let a = RequestSigner.sign(
            method: "GET", path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc", body: body,
            timestamp: "1700000000", nonce: "n1", peerID: peerID,
            signingKey: signingKey
        )
        let b = RequestSigner.sign(
            method: "GET", path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc", body: body,
            timestamp: "1700000000", nonce: "n1", peerID: peerID,
            signingKey: signingKey
        )
        XCTAssertNotEqual(a, b, "CryptoKit Ed25519 is non-deterministic; the nonce cache on the relay side prevents replay")
    }

    func testSignedHeadersDifferForDifferentNonces() {
        let signingKey = Curve25519.Signing.PrivateKey()
        let peerID = "peer-1"
        let body = Data("body".utf8)
        let a = RequestSigner.sign(
            method: "GET", path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc", body: body,
            timestamp: "1700000000", nonce: "n1", peerID: peerID,
            signingKey: signingKey
        )
        let b = RequestSigner.sign(
            method: "GET", path: "/v1/relay/messages",
            queryStringCanonicalized: "recipientID=abc", body: body,
            timestamp: "1700000001", nonce: "n2", peerID: peerID,
            signingKey: signingKey
        )
        XCTAssertNotEqual(a, b, "different nonce or timestamp should change the signature")
    }

    // MARK: - nonce + timestamp

    func testMakeNonceIs64HexChars() {
        let nonce = RequestSigner.makeNonce()
        XCTAssertEqual(nonce.count, 64, "nonce should be 32 random bytes hex-encoded (64 chars)")
        // must be lowercase hex
        let lowerHex = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(
            nonce.unicodeScalars.allSatisfy { lowerHex.contains($0) },
            "nonce should be lowercase hex"
        )
    }

    func testCurrentTimestampIsTenDigits() {
        let timestamp = RequestSigner.currentTimestamp()
        XCTAssertEqual(timestamp.count, 10, "unix seconds fit in 10 digits (until year 2286)")
        XCTAssertTrue(
            Int(timestamp) != nil,
            "currentTimestamp must be a parseable integer"
        )
    }
}

// MARK: - Data hex-decoding helper (test-only)

private extension Data {
    /// Decode a hex string ("2cf2...") into
    /// a `Data` blob. Returns nil if the
    /// string is not valid hex.
    init?(hexString: String) {
        let length = hexString.count
        guard length % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(length / 2)
        var index = hexString.startIndex
        for _ in 0 ..< (length / 2) {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index ..< next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
