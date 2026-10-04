import 'package:flutter/services.dart';

/// Compare origins without allowing paths, default-port spelling, or DNS case to alter trust.
bool clientCertificateOriginsMatch(String first, String second) {
  final left = Uri.tryParse(first);
  final right = Uri.tryParse(second);
  if (left == null || right == null || left.host.isEmpty || right.host.isEmpty) {
    return false;
  }
  if (!const {'http', 'https'}.contains(left.scheme) || left.scheme != right.scheme) {
    return false;
  }
  String host(Uri uri) => uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return host(left) == host(right) && left.port == right.port;
}

enum ClientCertificateMode {
  automatic('automatic'),
  importedOnly('imported_only'),
  managedOnly('managed_only');

  final String value;
  const ClientCertificateMode(this.value);

  static ClientCertificateMode parse(String? value) {
    return values.firstWhere((mode) => mode.value == value, orElse: () => automatic);
  }
}

/// iOS-only configuration; certificate and private-key objects stay in native code.
class ManagedClientIdentityApi {
  static const _channel = MethodChannel('immich/managed-client-identity');

  static Future<ClientCertificateMode> getMode() async {
    return ClientCertificateMode.parse(await _channel.invokeMethod<String>('getMode'));
  }

  static Future<void> setMode(ClientCertificateMode mode) {
    return _channel.invokeMethod<void>('setMode', {'mode': mode.value});
  }

  static Future<String?> beginServerValidation(String serverUrl) {
    return _channel.invokeMethod<String>('beginServerValidation', {'serverUrl': serverUrl});
  }

  static Future<void> endServerValidation(String identifier) {
    return _channel.invokeMethod<void>('endServerValidation', {'identifier': identifier});
  }

  static Future<Map<String, Object?>> diagnostics({bool testSigning = false}) async {
    return await _channel.invokeMapMethod<String, Object?>('diagnostics', {'testSigning': testSigning}) ?? {};
  }

  static Future<Map<String, Object?>> testConnection(String url) async {
    return await _channel.invokeMapMethod<String, Object?>('testConnection', {'url': url}) ?? {};
  }
}
