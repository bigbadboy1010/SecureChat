// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PeerBoundSigningContext.swift
// Phase 2-15B: the relay's peer-bound
// request signing (Sprint 15, ADR-005)
// needs two things from the calling app:
// the long-form public peer ID and the
// Ed25519 signing private key. Both
// come from the global `IdentityManager`
// (see `Core/Security/IdentityManager.swift`)
// but the `RelayTransport` is decoupled
// from it via a small protocol so the
// transport does not have to depend on
// the broader identity stack.
//
// The protocol is intentionally tiny: a
// `currentPeerID()` and a
// `currentSigningPrivateKey()`. Both can
// be optional — when the iOS app has not
// completed the Sprint 15 wiring the
// protocol returns nil and the transport
// sends unsigned requests (the relay
// still accepts them in development, and
// counts them in the `unsignedRequests`
// counter).

import Foundation
import CryptoKit

public protocol PeerBoundSigningContext: AnyObject {
    /// The 64-hex long-form public peer ID
    /// (the SHA-256 hex of the peer's
    /// Ed25519 public key bytes). This is
    /// the value the relay's `PeerRegistry`
    /// looks up when verifying the
    /// incoming request signature.
    func currentPeerID() -> String?

    /// The peer's long-term Ed25519 signing
    /// private key. Lives in iOS Keychain
    /// only. The transport calls
    /// `signingKey.signature(for:)` once
    /// per outgoing request, in
    /// `RequestSigner.sign(...)`.
    func currentSigningPrivateKey() -> Curve25519.Signing.PrivateKey
}
