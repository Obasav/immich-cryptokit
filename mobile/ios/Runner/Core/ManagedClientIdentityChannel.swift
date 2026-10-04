import Flutter
import Foundation
import ManagedApp
import Security

func managedIdentityErrorCode(_ error: Error) -> String {
  guard let error = error as? ManagedAppError else { return "lookup_error" }
  switch error {
  case .invalidIdentifier: return "not_provisioned"
  case .serverError: return "server_error"
  case .internalError: return "system_error"
  @unknown default: return "lookup_error"
  }
}

/// Apple-only settings and diagnostics. Identity and key objects never cross into Dart.
enum ManagedClientIdentityChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "immich/managed-client-identity", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "getMode":
        result(URLSessionManager.clientCertificateMode.rawValue)
      case "setMode":
        guard let value = arguments["mode"] as? String, let mode = ClientCertificateMode(rawValue: value) else {
          return result(FlutterError(code: "invalid_mode", message: "Unknown client certificate mode", details: nil))
        }
        URLSessionManager.shared.setClientCertificateMode(mode)
        result(nil)
      case "beginServerValidation":
        guard let url = arguments["serverUrl"] as? String else {
          return result(FlutterError(code: "invalid_url", message: "A server URL is required", details: nil))
        }
        result(URLSessionManager.clientCertificateOrigins.beginValidation(serverURL: url))
      case "endServerValidation":
        if let identifier = arguments["identifier"] as? String {
          URLSessionManager.clientCertificateOrigins.endValidation(identifier)
        }
        result(nil)
      case "diagnostics":
        let testSigning = arguments["testSigning"] as? Bool ?? false
        Task {
          let diagnostics = await identityDiagnostics(testSigning: testSigning)
          await MainActor.run { result(diagnostics) }
        }
      case "testConnection":
        guard let value = arguments["url"] as? String, let url = URL(string: value) else {
          return result(FlutterError(code: "invalid_url", message: "A valid server URL is required", details: nil))
        }
        Task {
          let report = await testConnection(url: url)
          await MainActor.run { result(report) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func testConnection(url: URL) async -> [String: Any] {
    guard let origin = ClientCertificateOrigin(serverURL: url.absoluteString),
          (UserDefaults.group.stringArray(forKey: SERVER_URLS_KEY) ?? [])
            .compactMap(ClientCertificateOrigin.init(serverURL:)).contains(origin) else {
      return ["connectionStatus": "unapproved_server", "lastCredentialSource": "not_requested"]
    }

    // A new session exercises the same factory and challenge handler without altering video playback.
    let delegate = URLSessionManagerDelegate(updateVideoProxy: false)
    let session = URLSessionManager.buildSession(delegate: delegate)
    defer { session.invalidateAndCancel() }
    var report: [String: Any] = [:]
    let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    do {
      let (_, response) = try await session.data(for: request)
      if let response = response as? HTTPURLResponse {
        report["httpStatus"] = response.statusCode
        let responseOrigin = response.url.flatMap { ClientCertificateOrigin(serverURL: $0.absoluteString) }
        report["connectionStatus"] = responseOrigin != origin ? "unexpected_server"
          : (200..<300).contains(response.statusCode) ? "connected" : "http_error"
      } else {
        report["connectionStatus"] = "connection_error"
      }
    } catch {
      report["connectionStatus"] = "connection_error"
      report["errorCode"] = (error as NSError).code
    }
    report["lastCredentialSource"] = "not_requested"
    for (key, value) in delegate.clientCertificateTLSStatus { report[key] = value }
    return report
  }

  private static func identityDiagnostics(testSigning: Bool) async -> [String: Any] {
    let provider = ManagedAppIdentitiesProvider()
    var report: [String: Any] = [
      "frameworkAvailable": true,
      "targetIdentifier": MANAGED_CLIENT_CERT_IDENTIFIER,
      "mode": URLSessionManager.clientCertificateMode.rawValue,
      "identifiers": [String](),
      "certificateAvailable": false,
      "privateKeyAvailable": false,
      "signatureStatus": "not_run",
    ]
    for await identifiers in await provider.identifiers {
      report["identifiers"] = identifiers
      break
    }

    do {
      let identity = try await provider.identity(withIdentifier: MANAGED_CLIENT_CERT_IDENTIFIER)
      report["identityStatus"] = "available"

      var certificate: SecCertificate?
      report["certificateAvailable"] = SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess
      var privateKey: SecKey?
      report["privateKeyAvailable"] = SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess

      if let certificate, let publicKey = SecCertificateCopyKey(certificate) {
        let attributes = SecKeyCopyAttributes(publicKey) as? [String: Any] ?? [:]
        let keyType = attributes[kSecAttrKeyType as String] as? String
        report["keyType"] = keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) ? "EC"
          : keyType == (kSecAttrKeyTypeRSA as String) ? "RSA" : "other"
        if let size = attributes[kSecAttrKeySizeInBits as String] as? NSNumber {
          report["keySize"] = size.intValue
        }
        if testSigning, let privateKey {
          report["signatureStatus"] = testPrivateKey(privateKey, certificatePublicKey: publicKey, keyType: keyType)
        } else if testSigning {
          report["signatureStatus"] = "key_unavailable"
        }
      } else if testSigning {
        report["signatureStatus"] = "certificate_unavailable"
      }
    } catch {
      report["identityStatus"] = managedIdentityErrorCode(error)
    }
    for (key, value) in URLSessionManager.shared.delegate.clientCertificateTLSStatus {
      report[key] = value
    }
    return report
  }

  private static func testPrivateKey(_ key: SecKey, certificatePublicKey: SecKey, keyType: String?) -> String {
    let algorithms: [SecKeyAlgorithm] = keyType == (kSecAttrKeyTypeECSECPrimeRandom as String)
      ? [.ecdsaSignatureMessageX962SHA384]
      : [.rsaSignatureMessagePSSSHA256, .rsaSignatureMessagePKCS1v15SHA256]
    guard let algorithm = algorithms.first(where: {
      SecKeyIsAlgorithmSupported(key, .sign, $0) && SecKeyIsAlgorithmSupported(certificatePublicKey, .verify, $0)
    }) else { return "unsupported_algorithm" }

    var nonce = [UInt8](repeating: 0, count: 32)
    let status = nonce.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else { return "random_error" }
    let message = Data(nonce) as CFData
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(key, algorithm, message, &error) else { return "signing_error" }
    return SecKeyVerifySignature(certificatePublicKey, algorithm, message, signature, &error)
      ? "verified" : "verification_error"
  }
}
