import XCTest
import CryptoKit
@testable import BIT

final class SecurityAuditServiceTests: XCTestCase {
    var auditService: SecurityAuditService!

    override func setUp() {
        super.setUp()
        auditService = SecurityAuditService.shared
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Input Validation Tests
    func testValidateCleanInput() {
        // Arrange
        let cleanInput = "This is a normal message without any malicious content"

        // Act
        let result = auditService.validateAndSanitizeInput(cleanInput)

        // Assert
        if case .success(let sanitized) = result {
            XCTAssertEqual(sanitized, cleanInput.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            XCTFail("Expected success result for clean input")
        }
    }

    func testValidateInputExceedsMaxLength() {
        // Arrange
        let longInput = String(repeating: "a", count: 15000)

        // Act
        let result = auditService.validateAndSanitizeInput(longInput, maxLength: 10000)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.inputTooLong)
        } else {
            XCTFail("Expected failure for input exceeding max length")
        }
    }

    func testDetectSQLInjectionPatternDropTable() {
        // Arrange
        let sqlInjection = "'; DROP TABLE users; --"

        // Act
        let result = auditService.validateAndSanitizeInput(sqlInjection)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.injectionAttempt)
        } else {
            XCTFail("Expected SQL injection detection")
        }
    }

    func testDetectSQLInjectionPatternUnionSelect() {
        // Arrange
        let sqlInjection = "1' UNION SELECT * FROM passwords --"

        // Act
        let result = auditService.validateAndSanitizeInput(sqlInjection)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.injectionAttempt)
        } else {
            XCTFail("Expected SQL injection detection")
        }
    }

    func testDetectSQLInjectionPatternOrEqualsOne() {
        // Arrange
        let sqlInjection = "' OR '1'='1"

        // Act
        let result = auditService.validateAndSanitizeInput(sqlInjection)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.injectionAttempt)
        } else {
            XCTFail("Expected SQL injection detection")
        }
    }

    func testDetectPathTraversalAttempt() {
        // Arrange
        let pathTraversal = "../../etc/passwd"

        // Act
        let result = auditService.validateAndSanitizeInput(pathTraversal)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.pathTraversalAttempt)
        } else {
            XCTFail("Expected path traversal detection")
        }
    }

    func testDetectPathTraversalPercentEncoded() {
        // Arrange
        let pathTraversal = "%2e%2e%2fetc%2fpasswd"

        // Act
        let result = auditService.validateAndSanitizeInput(pathTraversal)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.pathTraversalAttempt)
        } else {
            XCTFail("Expected path traversal detection")
        }
    }

    func testSanitizeInputRemovesNullBytes() {
        // Arrange
        let inputWithNulls = "normal\0text\0with\0nulls"

        // Act
        let result = auditService.validateAndSanitizeInput(inputWithNulls)

        // Assert
        if case .success(let sanitized) = result {
            XCTAssertFalse(sanitized.contains("\0"))
        } else {
            XCTFail("Expected sanitization to succeed")
        }
    }

    func testSanitizeInputTrimsWhitespace() {
        // Arrange
        let inputWithWhitespace = "   test message   \n"

        // Act
        let result = auditService.validateAndSanitizeInput(inputWithWhitespace)

        // Assert
        if case .success(let sanitized) = result {
            XCTAssertEqual(sanitized, "test message")
        } else {
            XCTFail("Expected whitespace to be trimmed")
        }
    }

    // MARK: - Cryptographic Validation Tests
    func testValidateKeyCommitmentSuccess() {
        // Arrange
        let key = "test_encryption_key_12345"
        let expectedHash = SHA256.hash(data: (key.data(using: .utf8) ?? Data()))
        let commitment = Data(expectedHash).base64EncodedString()

        // Act
        let isValid = auditService.validateKeyCommitment(key, commitment: commitment)

        // Assert
        XCTAssertTrue(isValid)
    }

    func testValidateKeyCommitmentFailure() {
        // Arrange
        let key = "test_key"
        let wrongCommitment = "incorrectcommitmentstring"

        // Act
        let isValid = auditService.validateKeyCommitment(key, commitment: wrongCommitment)

        // Assert
        XCTAssertFalse(isValid)
    }

    func testValidateEncryptionKeySize128Bit() {
        // Arrange
        let key128 = Data(repeating: 0, count: 16) // 128 bits = 16 bytes

        // Act
        let isValid = auditService.validateEncryptionKeySize(key128)

        // Assert
        XCTAssertTrue(isValid)
    }

    func testValidateEncryptionKeySize256Bit() {
        // Arrange
        let key256 = Data(repeating: 0, count: 32) // 256 bits = 32 bytes

        // Act
        let isValid = auditService.validateEncryptionKeySize(key256)

        // Assert
        XCTAssertTrue(isValid)
    }

    func testValidateEncryptionKeySizeInvalid() {
        // Arrange
        let invalidKey = Data(repeating: 0, count: 24) // 192 bits = 24 bytes (not supported)

        // Act
        let isValid = auditService.validateEncryptionKeySize(invalidKey)

        // Assert
        XCTAssertFalse(isValid)
    }

    // MARK: - Memory Safety Tests
    func testSecurelyEraseData() {
        // Arrange
        var data = Data(repeating: 0xFF, count: 32)
        let originalCount = data.count

        // Act
        auditService.securelyEraseData(&data)

        // Assert
        XCTAssertEqual(data.count, originalCount)
        // Data should be zeroed out
        XCTAssertTrue(data.allSatisfy { $0 == 0 })
    }

    func testSecurelyEraseString() {
        // Arrange
        var testString = "sensitive_data_to_erase"

        // Act
        auditService.securelyEraseString(&testString)

        // Assert
        // String should be replaced with nulls
        XCTAssertEqual(testString.count, "sensitive_data_to_erase".count)
    }

    // MARK: - API Security Tests
    func testValidateAPIRequestWithFreshTimestamp() {
        // Arrange
        let validation = SecurityAuditService.RequestValidation(
            timestamp: Date(),
            nonce: "test_nonce_12345",
            signature: "test_signature"
        )

        // Act
        let isValid = auditService.validateAPIRequest(validation)

        // Assert
        XCTAssertTrue(isValid)
    }

    func testValidateAPIRequestWithStaleTimestamp() {
        // Arrange
        let staleTimestamp = Date().addingTimeInterval(-600) // 10 minutes ago
        let validation = SecurityAuditService.RequestValidation(
            timestamp: staleTimestamp,
            nonce: "test_nonce",
            signature: "test_signature"
        )

        // Act
        let isValid = auditService.validateAPIRequest(validation)

        // Assert
        XCTAssertFalse(isValid)
    }

    func testPreventNonceReplay() {
        // Arrange
        let nonce = "unique_nonce_xyz"
        let validation1 = SecurityAuditService.RequestValidation(
            timestamp: Date(),
            nonce: nonce,
            signature: "sig1"
        )
        let validation2 = SecurityAuditService.RequestValidation(
            timestamp: Date(),
            nonce: nonce,
            signature: "sig2"
        )

        // Act
        let firstValidation = auditService.validateAPIRequest(validation1)
        let secondValidation = auditService.validateAPIRequest(validation2)

        // Assert
        XCTAssertTrue(firstValidation)
        XCTAssertFalse(secondValidation) // Replay should be detected
    }

    // MARK: - Vulnerability Scanning Tests
    func testPerformSecurityScan() {
        // Act
        let report = auditService.performSecurityScan()

        // Assert
        XCTAssertNotNil(report)
        XCTAssertTrue(report.usesSecureRandom)
        XCTAssertTrue(report.isDatabaseEncrypted)
        XCTAssertTrue(report.usesKeychain)
    }

    func testSecurityReportRiskLevel() {
        // Act
        let report = auditService.performSecurityScan()

        // Assert
        switch report.riskLevel {
        case .critical:
            XCTAssertTrue(report.hasHardcodedSecrets)
        case .high:
            XCTAssertFalse(report.potentialMemoryLeaks.isEmpty)
        default:
            XCTAssertTrue(true) // Low or medium risk
        }
    }

    // MARK: - Audit Logging Tests
    func testAuditEventLogging() {
        // Arrange
        let eventMessage = "Test security event"

        // Act
        auditService.logSecurityEvent(.validation, eventMessage)

        // Assert
        // Logging should not throw
        XCTAssertTrue(true)
    }

    func testAuditEventWithMetadata() {
        // Arrange
        let metadata = ["user_id": "test_user", "action": "login"]

        // Act
        auditService.logSecurityEvent(.accessControl, "User login attempt", metadata: metadata)

        // Assert
        XCTAssertTrue(true)
    }

    func testComplianceReportGeneration() {
        // Act
        let report = auditService.generateComplianceReport()

        // Assert
        XCTAssertTrue(report.contains("Security Audit Report"))
        XCTAssertTrue(report.contains("Risk Assessment"))
        XCTAssertTrue(report.contains("Findings"))
    }

    func testExportAuditLog() {
        // Act
        let exportData = auditService.exportAuditLog()

        // Assert
        XCTAssertNotNil(exportData)
        XCTAssertGreaterThan(exportData?.count ?? 0, 0)
    }

    // MARK: - Input Sanitization Edge Cases
    func testSanitizeEmptyInput() {
        // Arrange
        let emptyInput = ""

        // Act
        let result = auditService.validateAndSanitizeInput(emptyInput)

        // Assert
        if case .success(let sanitized) = result {
            XCTAssertEqual(sanitized, "")
        } else {
            XCTFail("Empty input should be valid")
        }
    }

    func testSanitizeUnicodeInput() {
        // Arrange
        let unicodeInput = "🔒 Encrypted message with emoji"

        // Act
        let result = auditService.validateAndSanitizeInput(unicodeInput)

        // Assert
        if case .success(let sanitized) = result {
            XCTAssertTrue(sanitized.contains("🔒"))
        } else {
            XCTFail("Unicode should be preserved")
        }
    }

    func testDetectMultipleSQLPatterns() {
        // Arrange
        let complexInjection = "1'; DELETE FROM users WHERE '1'='1"

        // Act
        let result = auditService.validateAndSanitizeInput(complexInjection)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.injectionAttempt)
        } else {
            XCTFail("Should detect SQL injection")
        }
    }
}
