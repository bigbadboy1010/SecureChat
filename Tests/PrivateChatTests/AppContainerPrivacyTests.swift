import CryptoKit
import XCTest
@testable import PrivateChat

@MainActor
final class AppContainerPrivacyTests: XCTestCase {
    func testStartupIsLockedAndClosesTheStandaloneServiceGate() {
        let fixture = Fixture()
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertFalse(fixture.container.isUnlocking)
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertTrue(fixture.container.canUnlock)
        XCTAssertEqual(fixture.gate.requestCount, 0)
    }

    func testSuccessfulAuthenticationOpensExactlyOneUserSession() async {
        let fixture = Fixture()
        let task = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        XCTAssertTrue(fixture.container.isUnlocking)
        XCTAssertNil(fixture.service.currentUserSessionID)
        fixture.gate.complete(1)
        await task.value
        XCTAssertTrue(fixture.container.isUnlocked)
        XCTAssertFalse(fixture.container.isUnlocking)
        XCTAssertNotNil(fixture.service.currentUserSessionID)
        XCTAssertNil(fixture.container.startupErrorMessage)
        XCTAssertEqual(fixture.gate.requestCount, 1)
    }

    func testDuplicateUnlockDoesNotStartASecondAuthentication() async {
        let fixture = Fixture()
        let first = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        await fixture.container.unlock()
        XCTAssertEqual(fixture.gate.requestCount, 1)
        XCTAssertTrue(fixture.container.isUnlocking)
        fixture.gate.complete(1)
        await first.value
        XCTAssertTrue(fixture.container.isUnlocked)
    }

    func testAuthenticationFailureKeepsConversationServiceLocked() async {
        let fixture = Fixture()
        let task = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        fixture.gate.complete(1, error: PrivateChatError.biometricFailed)
        await task.value
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertFalse(fixture.container.isUnlocking)
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertNotNil(fixture.container.startupErrorMessage)
    }

    func testTemporaryAuthenticationInactivityCoversContentWithoutCancellingThePrompt() async {
        let fixture = Fixture()
        let task = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        fixture.container.becameInactive()
        XCTAssertTrue(fixture.container.isPrivacyCoverVisible)
        XCTAssertTrue(fixture.container.isUnlocking)
        XCTAssertEqual(fixture.gate.cancelCount, 0)
        fixture.gate.complete(1)
        await task.value
        XCTAssertTrue(fixture.container.isUnlocked)
        XCTAssertTrue(fixture.container.isPrivacyCoverVisible, "The inactive scene stays opaque even after authentication")
        fixture.container.becameActive()
        XCTAssertFalse(fixture.container.isPrivacyCoverVisible)
        XCTAssertNotNil(fixture.service.currentUserSessionID)
    }

    func testBackgroundInvalidatesLateAuthenticationEvenAfterReturningActive() async {
        let fixture = Fixture()
        let task = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        fixture.container.enteredBackground()
        XCTAssertTrue(fixture.container.isPrivacyCoverVisible)
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertFalse(fixture.container.isUnlocking)
        XCTAssertGreaterThanOrEqual(fixture.gate.cancelCount, 1)
        fixture.container.becameActive()
        // A deliberately uncooperative gate returns success after cancel.
        fixture.gate.complete(1)
        await task.value
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertFalse(fixture.container.isPrivacyCoverVisible)
    }

    func testOldAuthenticationCompletionCannotUnlockOrClearANewerPendingRequest() async {
        let fixture = Fixture()
        let first = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        fixture.container.enteredBackground()
        fixture.container.becameActive()
        let second = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(2)
        fixture.gate.complete(1)
        await first.value
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertTrue(fixture.container.isUnlocking)
        XCTAssertNil(fixture.service.currentUserSessionID)
        fixture.gate.complete(2)
        await second.value
        XCTAssertTrue(fixture.container.isUnlocked)
        XCTAssertFalse(fixture.container.isUnlocking)
        XCTAssertNotNil(fixture.service.currentUserSessionID)
    }

    func testExplicitLockInvalidatesTheAuthenticatedUserSession() async {
        let fixture = Fixture()
        let task = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        fixture.gate.complete(1)
        await task.value
        let authenticatedSession = fixture.service.currentUserSessionID
        fixture.container.lock()
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertFalse(fixture.service.isCurrentUserSession(authenticatedSession))
        XCTAssertThrowsError(try fixture.service.makeLocalPairingCode())
    }

    func testDisabledBiometricsStillCannotOpenAUserSessionInBackground() async {
        let fixture = Fixture(requireBiometrics: false)
        fixture.container.enteredBackground()
        await fixture.container.unlock()
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertEqual(fixture.gate.requestCount, 0)
        fixture.container.becameActive()
        await fixture.container.unlock()
        XCTAssertTrue(fixture.container.isUnlocked)
        XCTAssertNotNil(fixture.service.currentUserSessionID)
        XCTAssertEqual(fixture.gate.requestCount, 0)
        fixture.container.enteredBackground()
        XCTAssertNil(fixture.service.currentUserSessionID)
    }

    func testCriticalStartupFailureCannotBeBypassedWithAuthenticationOrLifecycleChanges() async {
        let fixture = Fixture(criticalStartupFailure: true)
        await fixture.container.unlock()
        fixture.container.becameInactive()
        fixture.container.enteredBackground()
        fixture.container.becameActive()
        await fixture.container.unlock()
        XCTAssertFalse(fixture.container.canUnlock)
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertEqual(fixture.gate.requestCount, 0)
        XCTAssertEqual(fixture.container.startupErrorMessage, "Synthetic critical startup failure")
    }

    func testCancelledAuthenticationTaskCannotPublishSuccessfulUnlock() async {
        let fixture = Fixture()
        let task = Task { await fixture.container.unlock() }
        await fixture.gate.waitForRequest(1)
        task.cancel()
        fixture.gate.complete(1)
        await task.value
        XCTAssertFalse(fixture.container.isUnlocked)
        XCTAssertFalse(fixture.container.isUnlocking)
        XCTAssertNil(fixture.service.currentUserSessionID)
    }

    @MainActor
    private final class Fixture {
        let service: ConversationService
        let gate: ControlledBiometricGate
        let container: AppContainer

        init(requireBiometrics: Bool = true, criticalStartupFailure: Bool = false) {
            let signing = Curve25519.Signing.PrivateKey()
            let crypto = CryptoService()
            let identity = LocalIdentity(id: crypto.peerID(publicKeyData: signing.publicKey.rawRepresentation),
                                         displayName: "Synthetic lifecycle tester", keyAgreementPrivateKey: .init(), signingPrivateKey: signing)
            var settings = AppSecurityState.secureDefault
            settings.requireBiometricUnlock = requireBiometrics
            let localService = ConversationService(
                localIdentity: identity, messageStore: MockMessageStore(), draftStore: MockDraftStore(),
                peerTrustStore: MockPeerTrustStore(), settingsStore: MockSecuritySettingsStore(seed: settings),
                relayPacketLedgerStore: MockRelayPacketLedgerStore(), identityManager: MockIdentityManager(localIdentity: identity),
                crypto: crypto, transportCoordinator: MockTransportCoordinator(), forwardSecretStore: InMemoryForwardSecretStore()
            )
            XCTAssertTrue(localService.load())
            let controlledGate = ControlledBiometricGate()
            service = localService
            gate = controlledGate
            container = AppContainer(conversationService: localService, biometricGate: controlledGate,
                                     startupErrorMessage: criticalStartupFailure ? "Synthetic critical startup failure" : nil,
                                     hasCriticalStartupFailure: criticalStartupFailure)
        }
    }
}

/// No LocalAuthentication, networking or user keychain operations occur.
/// Cancellation is intentionally ignored so AppContainer must reject a late
/// system callback using its own request and session generation guards.
@MainActor
private final class ControlledBiometricGate: BiometricGating {
    private(set) var requestCount = 0
    private(set) var cancelCount = 0
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func unlock(reason: String) async throws {
        requestCount += 1
        let requestID = requestCount
        try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
            let ready = waiters.filter { $0.count <= requestCount }
            waiters.removeAll { $0.count <= requestCount }
            for waiter in ready { waiter.continuation.resume() }
        }
    }

    func cancel() { cancelCount += 1 }

    func waitForRequest(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { continuation in waiters.append((count, continuation)) }
    }

    func complete(_ requestID: Int, error: Error? = nil) {
        guard let continuation = pending.removeValue(forKey: requestID) else {
            XCTFail("Missing synthetic authentication request")
            return
        }
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}
