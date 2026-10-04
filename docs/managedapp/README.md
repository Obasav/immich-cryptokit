# Immich CryptoKit ManagedApp mTLS Deployment

This directory contains reference templates for provisioning the iOS Immich CryptoKit fork with a
ManagedApp-backed ACME client identity.

The Swift client currently requests this ManagedApp identity identifier:

```
immich.mtls.client-identity
```

The intended trust path is:

```
HSM-backed issuing CA
        |
        | ACME certificate issuance
        v
Apple Secure Enclave private key
        |
        | ManagedApp SecIdentity
        v
Immich URLSession
        |
        | TLS client authentication
        v
Traefik
```

## Files

- `app-managed.json.template`: Declarative Device Management AppManaged configuration.
- `acme-asset.json.template`: DDM ACME credential asset referenced by AppManaged.
- `acme-credential.json.template`: JSON returned from the ACME asset DataURL. This causes the
  device to generate a hardware-bound key and request a client certificate.
- `activation.json.template`: DDM activation that applies the AppManaged configuration.

## Identifier binding

The following value is an application-level identifier, not a certificate subject:

```
immich.mtls.client-identity
```

It MUST match the string used in
`mobile/ios/Runner/Core/URLSessionManager.swift`.

The AppManaged declaration maps that identifier to the ACME asset declaration:

```json
{
  "Identifier": "immich.mtls.client-identity",
  "AssetReference": "<ACME_ASSET_DECLARATION_UUID>"
}
```

The ManagedApp framework then exposes the resulting identity to Immich as a `SecIdentity`.

## Client certificate source

The iOS client certificate settings offer three modes:

| Mode | Behavior |
| --- | --- |
| Automatic (default) | Prefer the managed identity. If it is unavailable or lookup fails, allow the existing imported certificate as a fallback. Diagnostics retain the managed lookup outcome and the certificate source used. |
| Imported certificate only | Use the existing PKCS#12 import path without requesting a managed identity for TLS. |
| Require managed identity | Cancel client-certificate authentication if the managed identity cannot be obtained. Never read or use the locally imported identity as a fallback. |

Import and Remove affect only Immich's imported certificate. They do not alter MDM identities.
Mode changes apply to new TLS authentications; transfers on an already authenticated connection
may complete with the previous identity. The foreground session is recreated on a mode change.

"Require managed identity" selects the source of the identity, not its key provenance. ManagedApp
also supports managed PKCS#12 and SCEP identities. For hardware-only access, provision this ACME
asset with `HardwareBound` and `Attest` enabled, require validated attestation and CSR key matching
at the CA, and have Traefik require and verify certificates from that issuance policy. A server
that never requests a client certificate does not establish mTLS merely because this mode is set.

## Approved server origins

Both imported and managed identities are restricted to the explicitly configured HTTPS server
origins, including their ports. A pre-login server entered by the user is temporarily approved
only while server discovery and validation run. Overlapping validations have independent leases.
Redirect targets and discovery responses cannot add origins to the approved list. If discovery
returns an API on another origin, enter that API URL directly or configure it as an alternate
endpoint first. The origin and selection mode are checked again after asynchronous identity lookup.

## Device diagnostics

Expand Managed identity diagnostics in the iOS client certificate settings:

1. Check identity reports the configured identifiers, lookup outcome, certificate and private-key
   reference availability, and public-key type/size. A manually installed ACME profile does not
   substitute for an identity assigned to the app through `AppConfig.Identities`.
2. Test key additionally signs a fresh random message and verifies it against the certificate's
   public key. It uses the private-key reference without exporting it. A verified signature proves
   key usability, while hardware binding is established by CA-validated ACME attestation.
3. Test connection requests the configured server's `/api/server/ping` endpoint through a new
   session using the same configuration factory and TLS challenge handler as Immich. It reports
   the HTTP outcome and the identity source selected for that test. If no client-certificate
   challenge occurs, the result explicitly does not claim to prove mTLS.

Diagnostics never return certificate contents, certificate subjects, private-key material, full
key-attribute dictionaries, or signatures to Flutter, logs, or persistent storage.

For locked-screen uploads, consider setting the ACME asset's `Accessible` value to
`AfterFirstUnlock` and test foreground uploads, background transfers, and reboot/first-unlock
behavior on the actual device. The template retains Apple's default until that policy is chosen.

## Per-device ClientIdentifier

Do not deploy one shared `ClientIdentifier` to every device.

The ACME credential document should be generated per device/enrollment. The server serving
`ACME_CREDENTIAL_DATA_URL` should return a unique value for:

```json
"ClientIdentifier": "<UNIQUE_PER_DEVICE_CLIENT_IDENTIFIER>"
```

For a production deployment, the DataURL should normally use DDM's default MDM authentication so
the response can be bound to the requesting managed device.

## ACME credential choices

The template requests:

- P-384 EC key
- hardware-bound key generation
- device/key attestation
- digital-signature key usage
- TLS Web Client Authentication EKU: `1.3.6.1.5.5.7.3.2`

With `HardwareBound: true`, Apple generates the private key in the Secure Enclave and the key is
not exportable.

## Distribution model

The template uses Apple's enterprise `ManifestURL` form for `com.apple.configuration.app.managed`.
That is the appropriate DDM shape for a custom-signed Immich fork rather than an App Store binary.

The manifest referenced by `<IMMICH_ENTERPRISE_MANIFEST_URL>` must describe the signed IPA that the
device can install. Keep the `AppConfig.Identities` mapping unchanged across build updates.

## Fleet note

Fleet supports DDM assets and `com.apple.configuration.app.managed`, but its current documentation
states that an app referenced by `app.managed` must already be installed and managed through
Fleet's VPP functionality for the configuration to apply on-device.

That is a Fleet implementation constraint rather than an Apple ManagedApp constraint. Apple's
schema supports the enterprise `ManifestURL` form used by this template.

For this fork, do not assume that uploading these declarations to Fleet is sufficient until the
custom-app management path has been validated on a test device.

## Required deployment sequence

1. Serve a device-specific ACME credential document over HTTPS.
2. Make the ACME server capable of issuing the requested client certificate and validating the
   `device-attest-01` challenge if `Attest` remains enabled.
3. Publish the `com.apple.asset.credential.acme` asset.
4. Publish the `com.apple.configuration.app.managed` configuration pointing the Immich identity
   identifier at that asset.
5. Activate the AppManaged configuration.
6. Install/manage the signed Immich CryptoKit build.
7. Confirm ManagedApp exposes `immich.mtls.client-identity`.
8. Only then require the corresponding client CA on the Traefik test hostname.

Do not enable mandatory mTLS on the production Immich hostname until the managed identity has been
verified on a test device.
