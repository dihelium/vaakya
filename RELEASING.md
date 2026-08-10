# Releasing Vaakya Work Safe

The source-install path is authoritative until a personal Developer ID Application certificate and notarization profile are available.

## Source install

```bash
make test
make audit
make install
```

`make install` uses ad-hoc signing and installs only to the current user's `~/Applications` directory.

## Trusted downloadable release

A public binary requires an explicitly supplied Developer ID identity and Apple notarization:

```bash
VAAKYA_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VAAKYA_NOTARY_PROFILE="vaakya-notary" \
Scripts/release.sh 0.2.0
```

Never install a signing private key on an employer-owned Mac and never use an employer's certificate. The bundle script will not auto-discover any keychain identity.
