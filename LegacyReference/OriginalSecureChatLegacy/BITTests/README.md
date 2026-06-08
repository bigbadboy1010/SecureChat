# SecureChat Test Suite

## Quick Start

### Prerequisites
- Xcode 15.0+
- iOS 14.0+ deployment target
- macOS 12.0+ for running tests

### Running Tests

**All Tests**
```bash
xcodebuild test -scheme SecureChat -enableCodeCoverage YES
```

**Specific Test Suite**
```bash
xcodebuild test -scheme SecureChat -testPlan SearchServiceTests
xcodebuild test -scheme SecureChat -testPlan OfflineServiceTests
xcodebuild test -scheme SecureChat -testPlan SecurityAuditServiceTests
xcodebuild test -scheme SecureChat -testPlan CallServiceTests
xcodebuild test -scheme SecureChat -testPlan AnalyticsServiceTests
```

**Integration Tests Only**
```bash
xcodebuild test -scheme SecureChat -testPlan IntegrationTests
```

**Performance Tests Only**
```bash
xcodebuild test -scheme SecureChat -testPlan PerformanceTests
```

**With Verbose Output**
```bash
xcodebuild test -scheme SecureChat -verbose
```

## Test Organization

```
BITTests/
├── SearchServiceTests.swift          # FTS5 search functionality
├── OfflineServiceTests.swift         # Offline-first architecture
├── SecurityAuditServiceTests.swift   # Security validation & audit logging
├── CallServiceTests.swift            # Voice/video calling framework
├── AnalyticsServiceTests.swift       # Privacy-first analytics
├── IntegrationTests.swift            # Multi-service workflows
├── PerformanceTests.swift            # Benchmarks & stress tests
├── TEST_SUITE_DOCUMENTATION.md       # Comprehensive test documentation
└── README.md                         # This file
```

## Test Coverage by Service

### 1. SearchService (13 tests)
Tests full-text search functionality, fuzzy matching, and advanced filtering.

```swift
searchService.search("query", in: "channel")
searchService.searchWithFuzzy("query", tolerance: 0.8)
searchService.advancedSearch(criteria: criteria)
```

**Key Tests**:
- FTS5 full-text search
- Fuzzy matching with Levenshtein distance
- Multi-filter search (channel, sender, date range, media type)
- Saved search functionality
- Search index management

### 2. OfflineService (15 tests)
Tests offline message queuing, sync, and conflict resolution.

```swift
offlineService.queueMessage(message, priority: .high)
offlineService.syncOfflineMessages()
offlineService.resolveConflict(local: msg1, remote: msg2)
```

**Key Tests**:
- Message/media queuing with priorities
- Queue persistence
- Exponential backoff retry (2^n seconds)
- Conflict resolution (Last-Write-Wins)
- Sync status transitions
- Queue statistics & health monitoring

### 3. SecurityAuditService (28 tests)
Tests input validation, cryptographic operations, and audit logging.

```swift
securityService.validateAndSanitizeInput(input)
securityService.validateEncryptionKeySize(key)
securityService.recordError(type: "NetworkError", message: msg)
```

**Key Tests**:
- SQL injection detection (6 patterns)
- Path traversal detection
- Encryption key validation (128/256-bit)
- Secure data erasure
- API request validation
- Nonce replay prevention
- Security scanning & compliance reporting

### 4. CallService (23 tests)
Tests voice/video calling, encryption, and call management.

```swift
callService.initiateCall(to: peerID, type: .audio)
callService.encryptCallData(data, using: key)
callService.initiateGroupCall(groupID: "group", maxParticipants: 8)
```

**Key Tests**:
- Call lifecycle (initiate, accept, reject, end)
- Audio/video mode handling
- Call encryption (256-bit AES-GCM)
- Group call management
- Call history persistence
- Codable compliance for persistence

### 5. AnalyticsService (36 tests)
Tests privacy-first analytics and event tracking.

```swift
analyticsService.trackEvent("message_sent", category: .messaging)
analyticsService.recordPerformanceMetric("db_query", duration: 0.234, success: true)
analyticsService.recordError(type: "NetworkError", message: msg)
```

**Key Tests**:
- Event tracking with categories (8 types)
- PII removal (userID, email, phone)
- Email pattern sanitization
- Path redaction in error messages
- Metrics aggregation (7 metric types)
- Session management
- Consent/opt-in/opt-out
- Report generation
- Data deletion/GDPR compliance

### 6. Integration Tests (14 tests)
Tests complete workflows across multiple services.

```swift
// Validate → Create → Persist → Search → Analytics
// Queue → Sync → Resolve conflicts
// Encrypt → Audit → Track
```

**Key Tests**:
- Secure message flow end-to-end
- Message with media encryption
- Offline queue → sync workflow
- Group chat with encryption
- Deletion with audit trail
- Error tracking with audit logs
- Performance monitoring

### 7. Performance Tests (18 tests)
Benchmarks and stress testing.

```swift
self.measure {
    // Insert 1000 messages
    // Search 5000 message database
    // Concurrent operations
}
```

**Key Tests**:
- Database insertion benchmarks (1K, 10K messages)
- Search performance on large datasets
- Concurrent operations (100 concurrent inserts, 50 concurrent searches)
- Memory usage profiling
- Batch operations
- Complex query filtering

## Test Metrics

| Metric | Value |
|--------|-------|
| Total Test Cases | 147 |
| Services Covered | 5 |
| Unit Tests | 109 |
| Integration Tests | 14 |
| Performance Tests | 18 |
| Lines of Test Code | ~4000 |
| Coverage Target | >85% |

## Code Coverage

Generate coverage report:
```bash
xcodebuild test -scheme SecureChat -enableCodeCoverage YES
```

View report in Xcode:
- Product → Scheme → Edit Scheme → Test → Options → Code Coverage: ON
- View in: Product → Perform Action → Generate Coverage Report

## Continuous Integration

### GitHub Actions Example
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: xcodebuild test -scheme SecureChat
      - name: Code coverage
        run: xcodebuild test -scheme SecureChat -enableCodeCoverage YES
```

## Test Best Practices

1. **Isolation**: Each test is independent (setUp/tearDown)
2. **Determinism**: Tests produce consistent results
3. **Speed**: Unit tests complete in <100ms, all tests in <5 minutes
4. **Coverage**: 85%+ code coverage maintained
5. **Clarity**: Descriptive test names following Given-When-Then pattern

## Debugging Tests

### Run single test
```bash
xcodebuild test -scheme SecureChat -testPlan SearchServiceTests -only-testing:SecureChat/SearchServiceTests/testBasicFullTextSearch
```

### Enable logging
```bash
xcodebuild test -scheme SecureChat -verbose -showBuildSettings
```

### Debug in Xcode
1. Open test file in Xcode
2. Click diamond icon next to test method
3. Set breakpoints
4. Run test (Cmd+U)

## Test Maintenance

### When services change:
1. Update affected tests
2. Add tests for new functionality
3. Run full test suite
4. Update code coverage

### Performance regressions:
1. Review performance test results
2. Optimize service implementation
3. Update baseline benchmarks if necessary

### Security updates:
1. Add tests for new attack vectors
2. Update input validation tests
3. Verify pattern detection tests

## Troubleshooting

### Tests timeout
- Increase timeout in test settings
- Check for blocking operations
- Optimize performance bottlenecks

### Flaky tests
- Check for timing-dependent assertions
- Ensure proper cleanup in tearDown()
- Use synchronization mechanisms

### Code coverage gaps
- Identify untested code paths
- Add tests for edge cases
- Update service implementations if needed

## References

- [Apple Testing Framework](https://developer.apple.com/documentation/xctest)
- [Test-Driven Development](https://developer.apple.com/videos/play/wwdc2021/10195/)
- [Code Coverage Best Practices](https://developer.apple.com/documentation/xctest/code-coverage)

## Test Report Template

After running tests, generate a report:

```markdown
# Test Report

Date: YYYY-MM-DD
Duration: XXm XXs
Total Tests: 147
Passed: XXX
Failed: X
Skipped: X
Code Coverage: XX%

## Services Tested
- [ ] SearchService
- [ ] OfflineService
- [ ] SecurityAuditService
- [ ] CallService
- [ ] AnalyticsService
- [ ] Integration
- [ ] Performance

## Issues Found
- Issue 1: ...
- Issue 2: ...
```

## Contributing Tests

When adding new features:
1. Write tests first (TDD)
2. Implement feature
3. Ensure all tests pass
4. Maintain >85% coverage
5. Document test approach in code

## Contact & Support

For test-related issues:
1. Check TEST_SUITE_DOCUMENTATION.md
2. Review test logs
3. Consult test maintainers
