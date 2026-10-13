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

@MainActor
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

    func testCanonicalQueryStringCombinesRepeatedValuesLikeRelay() {
        let items = [
            URLQueryItem(name: "tag", value: "z"),
            URLQueryItem(name: "tag", value: "a")
        ]
        let canonical = RequestSigner.canonicalQueryString(from: items)
        XCTAssertEqual(canonical, "tag=z%2Ca")
    }

    func testCanonicalQueryStringPercentEncodesValues() {
        let items = [
            URLQueryItem(name: "q&scope", value: "hello world/+?")
        ]
        let canonical = RequestSigner.canonicalQueryString(from: items)
        XCTAssertEqual(canonical, "q%26scope=hello%20world%2F%2B%3F")
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
        // Decode the unpadded Base64URL signature and verify it against the
        // public key exactly as the production relay does server-side.
        guard let signatureBytes = Data(base64URLEncoded: signed.signature) else {
            XCTFail("signature is not valid Base64URL")
            return
        }
        let isValid = signingKey.publicKey.isValidSignature(
            signatureBytes,
            for: Data(canonical.utf8)
        )
        XCTAssertTrue(isValid, "the signature produced by sign() must verify under the public key")
    }

    func testSignMatchesProductionRelayWireVector() throws {
        let signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data((0..<32).map { UInt8($0) })
        )
        let peerID = RequestSigner.sha256Hex(signingKey.publicKey.rawRepresentation)
        XCTAssertEqual(
            peerID,
            "56475aa75463474c0285df5dbf2bcab73da651358839e9b77481b2eab107708c"
        )

        let signed = RequestSigner.sign(
            method: "POST",
            path: "/v1/relay/messages",
            queryStringCanonicalized: "",
            body: Data("{\"a\":\"////\",\"z\":1}".utf8),
            timestamp: "2026-09-19T14:00:00Z",
            nonce: "AAECAwQFBgcICQoLDA0ODw",
            peerID: peerID,
            signingKey: signingKey
        )

        let canonical = RequestSigner.canonicalString(method: "POST", path: "/v1/relay/messages", queryStringCanonicalized: "", body: Data("{\"a\":\"////\",\"z\":1}".utf8), timestamp: "2026-09-19T14:00:00Z", nonce: "AAECAwQFBgcICQoLDA0ODw", peerID: peerID)
        // Validate the independent Node/RFC-compatible known signature, and
        // the generated Apple signature. CryptoKit documents randomization
        // against side-channel attacks; generated bytes need not be identical.
        let knownSignature = try XCTUnwrap(Data(base64URLEncoded: "_70CaBdgtnjqhXPIFwl6h5XW_nqaJGJXQGM91yoJb9b4gHOGcq8J2w2gqaJY-Lx809bscKQYl8Qxn1LDcAonCQ"))
        XCTAssertTrue(signingKey.publicKey.isValidSignature(knownSignature, for: Data(canonical.utf8)))
        XCTAssertTrue(signingKey.publicKey.isValidSignature(try XCTUnwrap(Data(base64URLEncoded: signed.signature)), for: Data(canonical.utf8)))
    }

    func testRepeatedSigningVerifiesTheSameCanonicalInput() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let body = Data("body".utf8)
        let canonical = RequestSigner.canonicalString(method: "GET", path: "/v1/relay/messages", queryStringCanonicalized: "recipientID=abc", body: body, timestamp: "1700000000", nonce: "n1", peerID: "peer-1")
        for _ in 0..<2 {
            let headers = RequestSigner.sign(method: "GET", path: "/v1/relay/messages", queryStringCanonicalized: "recipientID=abc", body: body, timestamp: "1700000000", nonce: "n1", peerID: "peer-1", signingKey: signingKey)
            XCTAssertEqual(headers.peerID, "peer-1")
            XCTAssertEqual(headers.nonce, "n1")
            let signature = try XCTUnwrap(Data(base64URLEncoded: headers.signature))
            XCTAssertTrue(signingKey.publicKey.isValidSignature(signature, for: Data(canonical.utf8)))
            XCTAssertFalse(signingKey.publicKey.isValidSignature(signature, for: Data((canonical + "tampered").utf8)))
        }
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

    func testMakeNonceIsUnpaddedBase64URLOf16RandomBytes() throws {
        let nonce = RequestSigner.makeNonce()
        XCTAssertEqual(nonce.count, 22)
        XCTAssertFalse(nonce.contains("="))
        XCTAssertFalse(nonce.contains("+"))
        XCTAssertFalse(nonce.contains("/"))
        let decoded = try XCTUnwrap(Data(base64URLEncoded: nonce))
        XCTAssertEqual(decoded.count, 16)
    }

    func testCurrentTimestampIsCurrentRFC3339() throws {
        let timestamp = RequestSigner.currentTimestamp()
        let parsed = try XCTUnwrap(DateCoding.iso8601Formatter.date(from: timestamp))
        XCTAssertLessThan(abs(parsed.timeIntervalSinceNow), 2)
    }
}

// MARK: - Base64URL decoding helper (test-only)

private extension Data {
    init?(base64URLEncoded value: String) {
        let normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}
