import Foundation

enum ClientCertificateMode: String, CaseIterable {
  case automatic
  case importedOnly = "imported_only"
  case managedOnly = "managed_only"

  func selection(managed: ManagedIdentityAvailability, importedAvailable: Bool) -> ClientCertificateSelection {
    switch self {
    case .managedOnly:
      return managed == .available ? .managed : .cancel
    case .importedOnly:
      return importedAvailable ? .imported : .defaultHandling
    case .automatic:
      if managed == .available { return .managed }
      return importedAvailable ? .imported : .defaultHandling
    }
  }
}

enum ManagedIdentityAvailability: Equatable {
  case available, missing, failed
}

enum ClientCertificateSelection: Equatable {
  case managed, imported, defaultHandling, cancel
}

struct ClientCertificateOrigin: Hashable {
  let host: String
  let port: Int

  init?(serverURL: String) {
    guard let url = URL(string: serverURL),
          url.scheme?.lowercased() == "https",
          let host = url.host else { return nil }
    self.init(host: host, port: url.port ?? 443)
  }

  init?(protectionSpace: URLProtectionSpace) {
    guard protectionSpace.proxyType == nil,
          let scheme = protectionSpace.protocol?.lowercased(),
          scheme == "https" || scheme == "wss" else { return nil }
    self.init(host: protectionSpace.host, port: protectionSpace.port)
  }

  private init?(host: String, port: Int) {
    var normalizedHost = host.lowercased()
    if normalizedHost.hasPrefix("["), normalizedHost.hasSuffix("]") {
      normalizedHost = String(normalizedHost.dropFirst().dropLast())
    }
    if normalizedHost.hasSuffix(".") { normalizedHost.removeLast() }
    guard !normalizedHost.isEmpty, (1...65535).contains(port) else { return nil }
    self.host = normalizedHost
    self.port = port
  }
}

/// Keeps explicitly selected pre-login servers eligible only while their validation runs.
/// A redirect or discovery response cannot add a new origin to this policy.
final class ClientCertificateOriginPolicy {
  private let lock = NSLock()
  private var validations: [String: ClientCertificateOrigin] = [:]

  func beginValidation(serverURL: String) -> String {
    let identifier = UUID().uuidString
    if let origin = ClientCertificateOrigin(serverURL: serverURL) {
      lock.withLock { validations[identifier] = origin }
    }
    return identifier
  }

  func endValidation(_ identifier: String) {
    _ = lock.withLock { validations.removeValue(forKey: identifier) }
  }

  func allows(_ protectionSpace: URLProtectionSpace, configuredServerURLs: [String]) -> Bool {
    guard let origin = ClientCertificateOrigin(protectionSpace: protectionSpace) else { return false }
    let configuredOrigins = Set(configuredServerURLs.compactMap(ClientCertificateOrigin.init(serverURL:)))
    if configuredOrigins.contains(origin) { return true }
    return lock.withLock { validations.values.contains(origin) }
  }
}
