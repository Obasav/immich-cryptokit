import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/platform/managed_client_identity.dart';
import 'package:immich_mobile/platform/network_api.g.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';

class SslClientCertSettings extends ConsumerStatefulWidget {
  const SslClientCertSettings({super.key});

  @override
  ConsumerState<SslClientCertSettings> createState() => _SslClientCertSettingsState();
}

class _SslClientCertSettingsState extends ConsumerState<SslClientCertSettings> {
  final _log = Logger("SslClientCertSettings");

  bool isCertExist = false;
  bool _busy = false;
  bool _modeReady = false;
  ClientCertificateMode _mode = ClientCertificateMode.automatic;
  Map<String, Object?>? _diagnostics;
  Map<String, Object?>? _connection;

  @override
  void initState() {
    super.initState();
    unawaited(_checkCertificate());
    if (Platform.isIOS) {
      unawaited(_loadMode());
    }
  }

  Future<void> _loadMode() async {
    try {
      final mode = await ManagedClientIdentityApi.getMode();
      if (mounted) {
        setState(() => _mode = mode);
      }
    } catch (_) {
      if (mounted) {
        showMessage(context.t.client_cert_diagnostic_error);
      }
    } finally {
      if (mounted) {
        setState(() => _modeReady = true);
      }
    }
  }

  Future<void> _checkCertificate() async {
    try {
      final exists = await networkApi.hasCertificate();
      if (mounted && exists != isCertExist) {
        setState(() => isCertExist = exists);
      }
    } catch (e) {
      _log.warning("Failed to check certificate existence", e);
    }
  }

  String _modeLabel(ClientCertificateMode mode) => switch (mode) {
    ClientCertificateMode.automatic => context.t.client_cert_mode_automatic,
    ClientCertificateMode.importedOnly => context.t.client_cert_mode_imported,
    ClientCertificateMode.managedOnly => context.t.client_cert_mode_managed,
  };

  String _statusLabel(Object? status) => switch (status) {
    'available' => context.t.client_cert_status_available,
    'not_provisioned' => context.t.client_cert_status_not_provisioned,
    'server_error' => context.t.client_cert_status_server_error,
    'system_error' => context.t.client_cert_status_system_error,
    'managed' => context.t.client_cert_mode_managed_identity,
    'imported' => context.t.client_cert_mode_imported,
    'none' => context.t.client_cert_status_none,
    'blocked' => context.t.client_cert_status_blocked,
    'verified' => context.t.client_cert_status_verified,
    'connected' => context.t.client_cert_status_connected,
    'not_requested' => context.t.client_cert_status_not_requested,
    'not_run' || null => context.t.client_cert_status_not_checked,
    _ => context.t.client_cert_diagnostic_error,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (Platform.isIOS)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t.client_cert_mode_title, style: context.textTheme.bodyLarge),
                DropdownButton<ClientCertificateMode>(
                  value: _mode,
                  isExpanded: true,
                  items: ClientCertificateMode.values
                      .map((mode) => DropdownMenuItem(value: mode, child: Text(_modeLabel(mode))))
                      .toList(),
                  onChanged: _busy || !_modeReady ? null : _changeMode,
                ),
                Text(
                  _mode == ClientCertificateMode.managedOnly
                      ? context.t.client_cert_mode_managed_help
                      : _mode == ClientCertificateMode.importedOnly
                      ? context.t.client_cert_mode_imported_help
                      : context.t.client_cert_mode_automatic_help,
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(context.t.client_cert_mode_connections_help, style: context.textTheme.bodySmall),
              ],
            ),
          ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          horizontalTitleGap: 20,
          isThreeLine: true,
          title: Text(
            context.t.client_cert_title,
            style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t.client_cert_subtitle,
                style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ElevatedButton(onPressed: _busy ? null : importCert, child: Text(context.t.client_cert_import)),
                  ElevatedButton(onPressed: !isCertExist || _busy ? null : removeCert, child: Text(context.t.remove)),
                ],
              ),
              if (Platform.isIOS) Text(context.t.client_cert_import_scope_help, style: context.textTheme.bodySmall),
            ],
          ),
        ),
        if (Platform.isIOS) _buildDiagnostics(),
      ],
    );
  }

  Widget _buildDiagnostics() {
    final report = _diagnostics;
    final identifiers = (report?['identifiers'] as List<Object?>? ?? []).whereType<String>().join(', ');
    final keyType = report?['keyType'];
    final keySize = report?['keySize'];
    return ExpansionTile(
      title: Text(context.t.client_cert_managed_diagnostics),
      subtitle: Text(_statusLabel(report?['identityStatus'])),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        Text(context.t.client_cert_diagnostic_help),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _checkManagedIdentity(),
              child: Text(context.t.client_cert_check_identity),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _checkManagedIdentity(testSigning: true),
              child: Text(context.t.client_cert_test_key),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _testConnection,
              child: Text(context.t.client_cert_test_connection),
            ),
          ],
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        if (report != null) ...[
          _diagnosticRow(context.t.client_cert_framework, report['frameworkAvailable'] == true),
          _diagnosticRow(context.t.client_cert_identifiers, identifiers.isEmpty ? '[]' : identifiers),
          _diagnosticRow(context.t.client_cert_target, report['targetIdentifier']),
          _diagnosticRow(context.t.client_cert_identity, _statusLabel(report['identityStatus'])),
          _diagnosticRow(context.t.client_cert_certificate_reference, report['certificateAvailable']),
          _diagnosticRow(context.t.client_cert_key_reference, report['privateKeyAvailable']),
          if (keyType != null) _diagnosticRow(context.t.client_cert_public_key, '$keyType / $keySize'),
          _diagnosticRow(context.t.client_cert_signature, _statusLabel(report['signatureStatus'])),
          _diagnosticRow(context.t.client_cert_last_tls_identity, _statusLabel(report['lastCredentialSource'])),
          _diagnosticRow(context.t.client_cert_last_tls_lookup, _statusLabel(report['lastManagedLookup'])),
        ],
        if (_connection case final connection?) ...[
          const Divider(),
          _diagnosticRow(context.t.client_cert_connection_result, _statusLabel(connection['connectionStatus'])),
          _diagnosticRow(context.t.client_cert_connection_identity, _statusLabel(connection['lastCredentialSource'])),
          if (connection['lastManagedLookup'] != null)
            _diagnosticRow(context.t.client_cert_last_tls_lookup, _statusLabel(connection['lastManagedLookup'])),
          if (connection['httpStatus'] != null)
            _diagnosticRow(context.t.client_cert_http_status, connection['httpStatus']),
          if (connection['errorCode'] != null)
            _diagnosticRow(context.t.client_cert_error_code, connection['errorCode']),
          if (connection['lastCredentialSource'] == 'not_requested') Text(context.t.client_cert_no_challenge_help),
        ],
      ],
    );
  }

  Widget _diagnosticRow(String label, Object? value) {
    final text = value is bool ? (value ? context.t.yes : context.t.no) : value?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Future<void> _changeMode(ClientCertificateMode? mode) async {
    if (mode == null || mode == _mode) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ManagedClientIdentityApi.setMode(mode);
      await ref.read(apiServiceProvider).updateHeaders();
      if (mounted) {
        setState(() {
          _mode = mode;
          _diagnostics = null;
          _connection = null;
        });
      }
    } catch (_) {
      if (mounted) {
        showMessage(context.t.client_cert_diagnostic_error);
        await _loadMode();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _checkManagedIdentity({bool testSigning = false}) async {
    setState(() => _busy = true);
    try {
      final report = await ManagedClientIdentityApi.diagnostics(testSigning: testSigning);
      if (mounted) {
        setState(() => _diagnostics = report);
      }
    } catch (_) {
      if (mounted) {
        showMessage(context.t.client_cert_diagnostic_error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _testConnection() async {
    final urls = ApiService.getServerUrls();
    if (urls.isEmpty) {
      showMessage(context.t.client_cert_configure_server);
      return;
    }
    final server = Uri.parse(urls.first);
    var path = server.path.replaceFirst(RegExp(r'/+$'), '');
    if (!path.endsWith('/api')) {
      path = '$path/api';
    }
    final pingUrl = server.replace(path: '$path/server/ping').toString();
    setState(() => _busy = true);
    try {
      final report = await ManagedClientIdentityApi.testConnection(pingUrl);
      if (mounted) {
        setState(() => _connection = report);
      }
    } catch (_) {
      if (mounted) {
        showMessage(context.t.client_cert_diagnostic_error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void showMessage(String message) {
    context.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(message, style: context.textTheme.bodyLarge?.copyWith(color: context.primaryColor)),
      ),
    );
  }

  Future<void> importCert() async {
    try {
      final styling = ClientCertPrompt(
        title: context.t.client_cert_password_title,
        message: context.t.client_cert_password_message,
        cancel: context.t.cancel,
        confirm: context.t.confirm,
      );
      await networkApi.selectCertificate(styling);
      if (!mounted) {
        return;
      }
      setState(() => isCertExist = true);
      showMessage(StaticTranslations.instance.client_cert_import_success_msg);
    } catch (e) {
      if (_isCancellation(e) || !mounted) {
        return;
      }
      _log.severe("Error importing client cert", e);
      showMessage(StaticTranslations.instance.client_cert_invalid_msg);
    }
  }

  Future<void> removeCert() async {
    try {
      await networkApi.removeCertificate();
      if (!mounted) {
        return;
      }
      setState(() => isCertExist = false);
      showMessage(StaticTranslations.instance.client_cert_remove_msg);
    } catch (e) {
      if (_isCancellation(e) || !mounted) {
        return;
      }
      _log.severe("Error removing client cert", e);
      showMessage(StaticTranslations.instance.client_cert_remove_msg);
    }
  }

  bool _isCancellation(Object e) => e is PlatformException && e.code.toLowerCase().contains("cancel");
}
