import XCTest
@testable import PrivateChat

final class SecureChatProductionProfileTests: XCTestCase {
    func testCanonicalMigrationDropsOldSharedOperatorTokenButPreservesCustomRelayCredentials() {
        let token = String(repeating: "a", count: 64)
        let canonical = SecureChatProductionProfile.migratedConfiguration(.init(isEnabled: true, baseURLString: "https://securechat.team/", registrationToken: token))
        XCTAssertNil(canonical.registrationToken)
        XCTAssertTrue(canonical.isReadyForNetworkRequests)
        let custom = SecureChatProductionProfile.migratedConfiguration(.init(isEnabled: true, baseURLString: "https://owner-relay.test", registrationToken: token))
        XCTAssertEqual(custom.registrationToken, token)
    }
    func testObsoleteLanRelayMigratesToProductionURLAndDisablesWhenTokenMissing() {
        let legacy = RelayConfiguration(
            isEnabled: true,
            baseURLString: "http://192.168.178.229:8080/",
            registrationToken: nil
        )

        let migrated = SecureChatProductionProfile.migratedConfiguration(legacy)

        XCTAssertEqual(migrated.baseURLString, SecureChatProductionProfile.relayBaseURLString)
        XCTAssertFalse(migrated.isEnabled)
        XCTAssertNil(migrated.registrationToken)
    }


    func testLegacyDDNSRelayMigratesToCanonicalProductionHost() {
        let legacy = RelayConfiguration(
            isEnabled: true,
            baseURLString: "https://chatsecure.ddns.net/",
            registrationToken: String(repeating: "b", count: 64)
        )

        let migrated = SecureChatProductionProfile.migratedConfiguration(legacy)

        XCTAssertEqual(migrated.baseURLString, SecureChatProductionProfile.relayBaseURLString)
        XCTAssertTrue(migrated.isEnabled)
        XCTAssertNil(migrated.readinessIssue)
    }

    func testBrokenRelaySubdomainMigratesToCanonicalProductionHost() {
        let legacy = RelayConfiguration(
            isEnabled: true,
            baseURLString: "https://relay.securechat.team/",
            registrationToken: String(repeating: "c", count: 64)
        )

        let migrated = SecureChatProductionProfile.migratedConfiguration(legacy)

        XCTAssertEqual(migrated.baseURLString, SecureChatProductionProfile.relayBaseURLString)
        XCTAssertTrue(migrated.isEnabled)
        XCTAssertNil(migrated.readinessIssue)
    }

    func testProductionRelayIsReadyWithUsableToken() {
        let config = RelayConfiguration(
            isEnabled: true,
            baseURLString: SecureChatProductionProfile.relayBaseURLString,
            registrationToken: String(repeating: "a", count: 64)
        )

        XCTAssertNil(config.readinessIssue)
        XCTAssertTrue(config.isReadyForNetworkRequests)
    }

    func testTokenValidationRejectsEnvironmentAssignmentString() {
        XCTAssertFalse(SecureChatProductionProfile.isUsableClientToken("RELAY_AUTH_TOKEN=" + String(repeating: "a", count: 64)))
    }
}
