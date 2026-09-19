import XCTest
@testable import PrivateChat

final class SecureChatProductionProfileTests: XCTestCase {
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

        XCTAssertEqual(migrated.baseURLString, "https://relay.securechat.team")
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
