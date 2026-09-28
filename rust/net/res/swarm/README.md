# SWARM root certificates

These are the roots trusted when libsignal connects to a SWARM service
(`Environment::Swarm`, `Environment::SwarmStaging`). Signal's own roots
(`../signal.cer`, `../signal-ed25519.cer`) are deliberately **not** used by the SWARM
environments, so a SWARM build cannot validate a TLS connection to Signal's infrastructure.

| File               | Certificate    | SHA-256 of the DER                                                 |
| ------------------ | -------------- | ------------------------------------------------------------------ |
| `isrg-root-x1.cer` | ISRG Root X1   | `96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6` |
| `isrg-root-x2.cer` | ISRG Root X2   | `69729b8e15a86efc177a57afb7171dfc64add28c2fca8cf1507e34453ccb1470` |
| `isrg-root-ye.cer` | ISRG Root YE   | `e14ffcad5b0025731006caa43a121a22d8e9700f4fb9cf852f02a708aa5d5666` |
| `isrg-root-yr.cer` | ISRG Root YR   | `e57b7e6f150c419102e8d5c055729ff967b9d1a829bf00cec89ca604ebf4a86f` |

All four are public Let's Encrypt (Internet Security Research Group / ISRG) roots, in DER form, as
published at <https://letsencrypt.org/certificates/>. The four fingerprints above are asserted by a
unit test in `rust/net/src/certs.rs`, so the files cannot be silently swapped.

`isrg-root-x1.cer` and `isrg-root-x2.cer` are shipped in every current operating system trust
store. `isrg-root-ye.cer` and `isrg-root-yr.cer` ("ISRG Root YE" / "ISRG Root YR", ECDSA P-384 and
RSA 4096 respectively, both generated 2025-09-03) are Let's Encrypt's **next** root generation,
published on the same page but explicitly marked "Not Yet in Trust Stores" - they are pinned here
ahead of that adoption so that the SWARM chat connection keeps validating if
`chat.swarm.green`'s certificate chain ever stops cross-signing through X1/X2 and issues only
through the new generation. Because this list is additive (nothing is removed), a build with only
the old roots recognized by its OS still works exactly as before; this only adds a second path to
trust.

Because these roots are trusted, an ordinary publicly issued certificate for a `swarm.green`
host - for example one obtained from Let's Encrypt with certbot or Caddy - just works. There is no
certificate pinning to a private SWARM CA by default.

## Adding a private SWARM root CA

A self-hosted staging stack may prefer its own CA. Put the CA certificate in PEM form at

    rust/net/res/swarm/swarm-root-ca.pem     (git-ignored)

or point the environment variable `SWARM_TLS_ROOT_CA_PEM` at a PEM file when building:

    SWARM_TLS_ROOT_CA_PEM=/path/to/swarm-root-ca.pem npm run build   # in node/

`rust/net/build.rs` converts every `CERTIFICATE` block in that file to DER and appends it to the
list, so the private root is trusted **in addition to** the public roots. A build with no such file
trusts only the two public roots above.

The certificate is compiled in, so changing it means rebuilding the native library. For a server on
the developer's own machine, prefer libsignal's existing local-test-server path
(`new Net({ localTestServer: true, ... })`), which takes a port and a self-signed root certificate
at run time.
