import Foundation
import XCTest

final class ClientCertificatePolicyTests: XCTestCase {
  private let server = "https://immich.example/api"

  private func challenge(_ host: String = "immich.example", port: Int = 443, scheme: String = "https") -> URLProtectionSpace {
    URLProtectionSpace(host: host, port: port, protocol: scheme, realm: nil,
                       authenticationMethod: NSURLAuthenticationMethodClientCertificate)
  }

  func testExactApprovedHTTPSOrigin() {
    let policy = ClientCertificateOriginPolicy()
    XCTAssertTrue(policy.allows(challenge(), configuredServerURLs: [server]))
    XCTAssertTrue(policy.allows(challenge("IMMICH.EXAMPLE."), configuredServerURLs: [server]))
    XCTAssertTrue(policy.allows(challenge(scheme: "wss"), configuredServerURLs: [server]))
    XCTAssertTrue(policy.allows(challenge(port: 8443), configuredServerURLs: ["https://immich.example:8443"]))
  }

  func testRejectsRedirectHostsAndPortChanges() {
    let policy = ClientCertificateOriginPolicy()
    XCTAssertFalse(policy.allows(challenge("other.example"), configuredServerURLs: [server]))
    XCTAssertFalse(policy.allows(challenge("immich.example.attacker.test"), configuredServerURLs: [server]))
    XCTAssertFalse(policy.allows(challenge(port: 8443), configuredServerURLs: [server]))
  }

  func testRejectsInsecureAndUnconfiguredOrigins() {
    let policy = ClientCertificateOriginPolicy()
    XCTAssertFalse(policy.allows(challenge(scheme: "http"), configuredServerURLs: [server]))
    XCTAssertFalse(policy.allows(challenge(), configuredServerURLs: []))
    XCTAssertFalse(policy.allows(challenge(), configuredServerURLs: ["http://immich.example", "/api"]))
    XCTAssertFalse(policy.allows(challenge(port: 0), configuredServerURLs: [server]))
  }

  func testRejectsProxyChallenges() {
    let proxy = URLProtectionSpace(proxyHost: "immich.example", port: 443,
                                  type: NSURLProtectionSpaceHTTPSProxy, realm: nil,
                                  authenticationMethod: NSURLAuthenticationMethodClientCertificate)
    XCTAssertFalse(ClientCertificateOriginPolicy().allows(proxy, configuredServerURLs: [server]))
  }

  func testLocalAndExternalEndpointsAreExplicitApprovals() {
    let urls = [server, "https://immich.internal:8443"]
    let policy = ClientCertificateOriginPolicy()
    XCTAssertTrue(policy.allows(challenge(), configuredServerURLs: urls))
    XCTAssertTrue(policy.allows(challenge("immich.internal", port: 8443), configuredServerURLs: urls))
    XCTAssertFalse(policy.allows(challenge("immich.internal"), configuredServerURLs: urls))
  }

  func testIPv6Origin() {
    XCTAssertTrue(ClientCertificateOriginPolicy().allows(
      challenge("::1"), configuredServerURLs: ["https://[::1]:443/api"]
    ))
  }

  func testFirstLoginApprovalEndsWithValidation() {
    let policy = ClientCertificateOriginPolicy()
    XCTAssertFalse(policy.allows(challenge(), configuredServerURLs: []))
    let lease = policy.beginValidation(serverURL: server)
    XCTAssertTrue(policy.allows(challenge(), configuredServerURLs: []))
    XCTAssertFalse(policy.allows(challenge("discovered.example"), configuredServerURLs: []))
    policy.endValidation(lease)
    XCTAssertFalse(policy.allows(challenge(), configuredServerURLs: []))
  }

  func testOverlappingValidationsDoNotRevokeEachOther() {
    let policy = ClientCertificateOriginPolicy()
    let first = policy.beginValidation(serverURL: server)
    let second = policy.beginValidation(serverURL: server)
    policy.endValidation(first)
    XCTAssertTrue(policy.allows(challenge(), configuredServerURLs: []))
    policy.endValidation(second)
    XCTAssertFalse(policy.allows(challenge(), configuredServerURLs: []))
  }

  func testRemovalOfConfiguredOriginTakesEffect() {
    let policy = ClientCertificateOriginPolicy()
    XCTAssertTrue(policy.allows(challenge(), configuredServerURLs: [server]))
    XCTAssertFalse(policy.allows(challenge(), configuredServerURLs: []))
  }

  func testStrictModeNeverUsesAnInstalledImport() {
    XCTAssertEqual(ClientCertificateMode.managedOnly.selection(managed: .available, importedAvailable: true), .managed)
    XCTAssertEqual(ClientCertificateMode.managedOnly.selection(managed: .missing, importedAvailable: true), .cancel)
    XCTAssertEqual(ClientCertificateMode.managedOnly.selection(managed: .failed, importedAvailable: true), .cancel)
  }

  func testAutomaticFallbackIsAnExplicitPolicy() {
    XCTAssertEqual(ClientCertificateMode.automatic.selection(managed: .available, importedAvailable: true), .managed)
    XCTAssertEqual(ClientCertificateMode.automatic.selection(managed: .missing, importedAvailable: true), .imported)
    XCTAssertEqual(ClientCertificateMode.automatic.selection(managed: .failed, importedAvailable: true), .imported)
    XCTAssertEqual(ClientCertificateMode.automatic.selection(managed: .missing, importedAvailable: false), .defaultHandling)
  }

  func testImportedModeIgnoresManagedIdentityAvailability() {
    XCTAssertEqual(ClientCertificateMode.importedOnly.selection(managed: .available, importedAvailable: true), .imported)
    XCTAssertEqual(ClientCertificateMode.importedOnly.selection(managed: .available, importedAvailable: false), .defaultHandling)
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

XCTMain([testCase(ClientCertificatePolicyTests.allTests)])
