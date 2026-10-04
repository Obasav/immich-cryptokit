import Foundation

private func expectTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
  precondition(value(), "Expected true", file: file, line: line)
}

private func expectFalse(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
  precondition(!value(), "Expected false", file: file, line: line)
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
  precondition(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line)
}

final class ClientCertificatePolicyTests {
  private let server = "https://immich.example/api"

  private func challenge(_ host: String = "immich.example", port: Int = 443, scheme: String = "https") -> URLProtectionSpace {
    URLProtectionSpace(host: host, port: port, protocol: scheme, realm: nil,
                       authenticationMethod: NSURLAuthenticationMethodClientCertificate)
  }

  func testExactApprovedHTTPSOrigin() {
    let policy = ClientCertificateOriginPolicy()
    expectTrue(policy.allows(challenge(), configuredServerURLs: [server]))
    expectTrue(policy.allows(challenge("IMMICH.EXAMPLE."), configuredServerURLs: [server]))
    expectTrue(policy.allows(challenge(port: 8443), configuredServerURLs: ["https://immich.example:8443"]))
  }

  func testRejectsRedirectHostsAndPortChanges() {
    let policy = ClientCertificateOriginPolicy()
    expectFalse(policy.allows(challenge("other.example"), configuredServerURLs: [server]))
    expectFalse(policy.allows(challenge("immich.example.attacker.test"), configuredServerURLs: [server]))
    expectFalse(policy.allows(challenge(port: 8443), configuredServerURLs: [server]))
  }

  func testRejectsInsecureAndUnconfiguredOrigins() {
    let policy = ClientCertificateOriginPolicy()
    expectFalse(policy.allows(challenge(scheme: "http"), configuredServerURLs: [server]))
    expectFalse(policy.allows(challenge(scheme: "wss"), configuredServerURLs: [server]))
    expectFalse(policy.allows(challenge(), configuredServerURLs: []))
    expectFalse(policy.allows(challenge(), configuredServerURLs: ["http://immich.example", "/api"]))
    expectFalse(policy.allows(challenge(port: 0), configuredServerURLs: [server]))
  }

  func testRejectsProxyChallenges() {
    let proxy = URLProtectionSpace(proxyHost: "immich.example", port: 443,
                                  type: NSURLProtectionSpaceHTTPSProxy, realm: nil,
                                  authenticationMethod: NSURLAuthenticationMethodClientCertificate)
    expectFalse(ClientCertificateOriginPolicy().allows(proxy, configuredServerURLs: [server]))
  }

  func testLocalAndExternalEndpointsAreExplicitApprovals() {
    let urls = [server, "https://immich.internal:8443"]
    let policy = ClientCertificateOriginPolicy()
    expectTrue(policy.allows(challenge(), configuredServerURLs: urls))
    expectTrue(policy.allows(challenge("immich.internal", port: 8443), configuredServerURLs: urls))
    expectFalse(policy.allows(challenge("immich.internal"), configuredServerURLs: urls))
  }

  func testIPv6Origin() {
    expectTrue(ClientCertificateOriginPolicy().allows(
      challenge("::1"), configuredServerURLs: ["https://[::1]:443/api"]
    ))
  }

  func testFirstLoginApprovalEndsWithValidation() {
    let policy = ClientCertificateOriginPolicy()
    expectFalse(policy.allows(challenge(), configuredServerURLs: []))
    let lease = policy.beginValidation(serverURL: server)
    expectTrue(policy.allows(challenge(), configuredServerURLs: []))
    expectFalse(policy.allows(challenge("discovered.example"), configuredServerURLs: []))
    policy.endValidation(lease)
    expectFalse(policy.allows(challenge(), configuredServerURLs: []))
  }

  func testOverlappingValidationsDoNotRevokeEachOther() {
    let policy = ClientCertificateOriginPolicy()
    let first = policy.beginValidation(serverURL: server)
    let second = policy.beginValidation(serverURL: server)
    policy.endValidation(first)
    expectTrue(policy.allows(challenge(), configuredServerURLs: []))
    policy.endValidation(second)
    expectFalse(policy.allows(challenge(), configuredServerURLs: []))
  }

  func testRemovalOfConfiguredOriginTakesEffect() {
    let policy = ClientCertificateOriginPolicy()
    expectTrue(policy.allows(challenge(), configuredServerURLs: [server]))
    expectFalse(policy.allows(challenge(), configuredServerURLs: []))
  }

  func testStrictModeNeverUsesAnInstalledImport() {
    expectEqual(ClientCertificateMode.managedOnly.selection(managed: .available, importedAvailable: true), .managed)
    expectEqual(ClientCertificateMode.managedOnly.selection(managed: .missing, importedAvailable: true), .cancel)
    expectEqual(ClientCertificateMode.managedOnly.selection(managed: .failed, importedAvailable: true), .cancel)
  }

  func testAutomaticFallbackIsAnExplicitPolicy() {
    expectEqual(ClientCertificateMode.automatic.selection(managed: .available, importedAvailable: true), .managed)
    expectEqual(ClientCertificateMode.automatic.selection(managed: .missing, importedAvailable: true), .imported)
    expectEqual(ClientCertificateMode.automatic.selection(managed: .failed, importedAvailable: true), .imported)
    expectEqual(ClientCertificateMode.automatic.selection(managed: .missing, importedAvailable: false), .defaultHandling)
  }

  func testImportedModeIgnoresManagedIdentityAvailability() {
    expectEqual(ClientCertificateMode.importedOnly.selection(managed: .available, importedAvailable: true), .imported)
    expectEqual(ClientCertificateMode.importedOnly.selection(managed: .available, importedAvailable: false), .defaultHandling)
  }

  static let allTests = [
    ("testExactApprovedHTTPSOrigin", testExactApprovedHTTPSOrigin),
    ("testRejectsRedirectHostsAndPortChanges", testRejectsRedirectHostsAndPortChanges),
    ("testRejectsInsecureAndUnconfiguredOrigins", testRejectsInsecureAndUnconfiguredOrigins),
    ("testRejectsProxyChallenges", testRejectsProxyChallenges),
    ("testLocalAndExternalEndpointsAreExplicitApprovals", testLocalAndExternalEndpointsAreExplicitApprovals),
    ("testIPv6Origin", testIPv6Origin),
    ("testFirstLoginApprovalEndsWithValidation", testFirstLoginApprovalEndsWithValidation),
    ("testOverlappingValidationsDoNotRevokeEachOther", testOverlappingValidationsDoNotRevokeEachOther),
    ("testRemovalOfConfiguredOriginTakesEffect", testRemovalOfConfiguredOriginTakesEffect),
    ("testStrictModeNeverUsesAnInstalledImport", testStrictModeNeverUsesAnInstalledImport),
    ("testAutomaticFallbackIsAnExplicitPolicy", testAutomaticFallbackIsAnExplicitPolicy),
    ("testImportedModeIgnoresManagedIdentityAvailability", testImportedModeIgnoresManagedIdentityAvailability),
  ]
}

let suite = ClientCertificatePolicyTests()
for (name, test) in ClientCertificatePolicyTests.allTests {
  test(suite)()
  print("PASS: \(name)")
}
print("Passed \(ClientCertificatePolicyTests.allTests.count) client certificate policy tests")
