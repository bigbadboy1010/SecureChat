import XCTest
@testable import PrivateChat

/// Tests for the Privacy-Sentinel findings
/// derived from the v2 / v1 envelope routing
/// observations. The findings are surfaced in the
/// `SecurityAISentinel` dashboard; the tests cover
/// the build step in isolation.
final class RatchetSentinelFindingsTests: XCTestCase {

    func testEmptyObservationsProduceNoFindings() {
        let findings = RatchetSentinelFindings.build(observations: [])
        XCTAssertEqual(findings, [])
    }

    func testSingleV1ObservationProducesWarning() {
        let obs = RatchetSentinelObservation(
            peerID: "alice",
            isV2: false,
            sessionID: nil
        )
        let findings = RatchetSentinelFindings.build(observations: [obs])
        XCTAssertEqual(findings.count, 1)
        let finding = try? XCTUnwrap(findings.first)
        XCTAssertEqual(finding?.severity, .warning)
        XCTAssertTrue(finding?.title.contains("v1") ?? false)
        XCTAssertTrue(finding?.detail.contains("alice") ?? false)
    }

    func testSingleV2ObservationProducesInfo() {
        let obs = RatchetSentinelObservation(
            peerID: "bob",
            isV2: true,
            sessionID: "sc-deadbeef"
        )
        let findings = RatchetSentinelFindings.build(observations: [obs])
        XCTAssertEqual(findings.count, 1)
        let finding = try? XCTUnwrap(findings.first)
        XCTAssertEqual(finding?.severity, .info)
        XCTAssertTrue(finding?.title.contains("v2") ?? false)
        XCTAssertTrue(finding?.detail.contains("bob") ?? false)
    }

    func testMixedObservationsProduceTwoFindings() {
        let observations = [
            RatchetSentinelObservation(peerID: "alice", isV2: false, sessionID: nil),
            RatchetSentinelObservation(peerID: "bob", isV2: true, sessionID: "sc-1234"),
            RatchetSentinelObservation(peerID: "charlie", isV2: false, sessionID: nil)
        ]
        let findings = RatchetSentinelFindings.build(observations: observations)
        XCTAssertEqual(findings.count, 2)
        // The v1-warning must list both
        // alice and charlie (sorted).
        let warning = try? XCTUnwrap(
            findings.first(where: { $0.severity == .warning })
        )
        XCTAssertTrue(warning?.detail.contains("alice") ?? false)
        XCTAssertTrue(warning?.detail.contains("charlie") ?? false)
        // The v2-info must list bob.
        let info = try? XCTUnwrap(
            findings.first(where: { $0.severity == .info })
        )
        XCTAssertTrue(info?.detail.contains("bob") ?? false)
    }

    func testManyV1ObservationsCollapseToSingleWarning() {
        let observations = (1...5).map { i in
            RatchetSentinelObservation(
                peerID: "peer-\(i)",
                isV2: false,
                sessionID: nil
            )
        }
        let findings = RatchetSentinelFindings.build(observations: observations)
        let v1Warnings = findings.filter { $0.severity == .warning }
        XCTAssertEqual(v1Warnings.count, 1, "v1 warnings must be collapsed into one")
    }
}
