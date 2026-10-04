import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/platform/managed_client_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('immich/managed-client-identity');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getMode') {
        return 'managed_only';
      }
      if (call.method == 'beginServerValidation') {
        return 'validation-lease';
      }
      if (call.method == 'diagnostics') {
        return {'identityStatus': 'not_provisioned', 'identifiers': <String>[]};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('discovery can preserve an approved origin despite path, case, and default-port changes', () {
    expect(clientCertificateOriginsMatch('https://IMMICH.example./', 'https://immich.example:443/api'), isTrue);
    expect(clientCertificateOriginsMatch('https://immich.example/subpath', 'https://immich.example/api'), isTrue);
  });

  test('discovery cannot approve another host, scheme, or port', () {
    for (final destination in [
      'https://other.example/api',
      'https://immich.example.attacker.test/api',
      'https://immich.example:8443/api',
      'http://immich.example/api',
      '/api',
    ]) {
      expect(clientCertificateOriginsMatch('https://immich.example', destination), isFalse);
    }
  });

  test('the strict selection reaches native code rather than changing only the settings UI', () async {
    await ManagedClientIdentityApi.setMode(ClientCertificateMode.managedOnly);
    expect(calls.single.method, 'setMode');
    expect(calls.single.arguments, {'mode': 'managed_only'});
    expect(await ManagedClientIdentityApi.getMode(), ClientCertificateMode.managedOnly);
  });

  test('temporary pre-login authorization has an explicit release', () async {
    final identifier = await ManagedClientIdentityApi.beginServerValidation('https://immich.example');
    await ManagedClientIdentityApi.endServerValidation(identifier!);
    expect(calls.map((call) => call.method), ['beginServerValidation', 'endServerValidation']);
    expect(calls.last.arguments, {'identifier': 'validation-lease'});
  });

  test('key testing is explicitly requested and not performed by an ordinary status check', () async {
    final report = await ManagedClientIdentityApi.diagnostics();
    expect(report['identityStatus'], 'not_provisioned');
    expect(calls.last.arguments, {'testSigning': false});
    await ManagedClientIdentityApi.diagnostics(testSigning: true);
    expect(calls.last.arguments, {'testSigning': true});
  });
}
