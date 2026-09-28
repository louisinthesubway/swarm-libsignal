# SWARM changes to libsignal

This repository is a fork of [signalapp/libsignal](https://github.com/signalapp/libsignal).

| | |
| --- | --- |
| Upstream base of `swarm-main` | **v0.101.2** = `eb7864c4d` (the version Signal-Desktop `abe80d3` pins) |
| Also pushed, for reference | branch `upstream-main` = `e8cc2dddd` (upstream main as cloned 2026-09-22, node version 0.103.1), tags `upstream-v0.101.2`, `upstream-e8cc2dd` |
| Node package | `@signalapp/libsignal-client` **0.101.2-swarm.3** (0.101.2-swarm.1 was the first release; 0.101.2-swarm.2 added the HTTP/2 chat connection; 0.101.2-swarm.3 pins Let's Encrypt's next-generation roots) |

Why v0.101.2 and not upstream main: Signal-Desktop pins `@signalapp/libsignal-client` at exactly
`0.101.2`, and upstream main has moved to 0.103.1. Building the SWARM environment on top of the
pinned version means the desktop's TypeScript keeps compiling; a later upstream bump is a separate
job (`git merge upstream-main` on top of these commits).

**Not changed:** nothing under `rust/protocol`, `rust/crypto`, `rust/zkgroup`, `rust/poksho`,
`rust/attest`, `rust/svrb`, `rust/keytrans` or any other cryptographic crate. The double ratchet,
PQXDH, SPQR, sealed sender and zkgroup code is byte-for-byte upstream v0.101.2. This fork only adds
**network environment constants** and the bindings needed to select them.

## Why

libsignal compiles its network environments into Rust. Before this change
`Net.Environment` offered only `Staging` and `Production`, both of which are Signal's own
deployments: Signal hostnames, Signal's root certificates, Signal's CDSI/SVR enclave identities and
Signal's censorship-circumvention reflectors. A rebranded client configured with a SWARM hostname
did not get a SWARM connection - the libsignal layer silently used Signal's production servers,
which their terms forbid and which would leak SWARM traffic to a third party.

## The diff, file by file

| File | Change |
| --- | --- |
| `rust/net/res/swarm/isrg-root-x1.cer`, `isrg-root-x2.cer` | The two public Let's Encrypt (ISRG) roots in every current OS trust store, DER. Provenance and fingerprints: `rust/net/res/swarm/README.md`. |
| `rust/net/res/swarm/isrg-root-ye.cer`, `isrg-root-yr.cer` | **new (0.101.2-swarm.3).** Let's Encrypt's next-generation roots ("ISRG Root YE", "ISRG Root YR"), DER, pinned ahead of OS trust-store adoption so the chat connection keeps validating if `chat.swarm.green`'s chain stops cross-signing through X1/X2. Fetched directly from <https://letsencrypt.org/certificates/> and fingerprint-verified independently, not copied from a changelog. Provenance and fingerprints: `rust/net/res/swarm/README.md`. |
| `rust/net/res/swarm/README.md` | What the roots are and how to add a private SWARM CA. |
| `rust/net/build.rs` | Generates `$OUT_DIR/swarm_root_ca_ders.rs`: the four roots above (`SWARM_BUILTIN_ROOT_DERS`) plus every certificate in the optional build-time PEM file named by `$SWARM_TLS_ROOT_CA_PEM` (default `rust/net/res/swarm/swarm-root-ca.pem`, git-ignored). Contains a 30-line base64/PEM reader so no build dependency was added. The protobuf part is untouched. |
| `rust/net/src/certs.rs` | Adds `SWARM_ROOT_CERTIFICATES` (the generated list) and `NO_ROOT_CERTIFICATES` (an empty trust store). Adds tests asserting the four ISRG fingerprints, that every pinned root's Organization is ISRG, that no Signal root is in the SWARM list, and that every DER parses. |
| `rust/net/src/env.rs` | Adds `SWARM` and `SWARM_STAGING` environments, `EnclaveServices`, the `Env::enclave_services` field, and tests. `SWARM` dials HTTP/2 since `0.101.2-swarm.2`. See below. |
| `rust/bridge/shared/types/src/net.rs` | `Environment::Swarm = 2`, `Environment::SwarmStaging = 3` and their mapping to the two new `Env`s. `set_censorship_circumvention_enabled` no longer panics when an environment has no reflector providers - it logs and does nothing. Tests for both. |
| `rust/bridge/shared/testing/src/net_env.rs` | Sets the new `enclave_services` field on the localhost test environment (the mock server does stand in for CDSI/SVR). |
| `node/ts/net.ts` | `Environment.Swarm = 2`, `Environment.SwarmStaging = 3`, documented. |
| `node/ts/test/NetTest.ts` | `new Net({ env: Environment.Swarm })` and `Environment.SwarmStaging` construct, and `setCensorshipCircumventionEnabled(true)` does not throw. |
| `node/package.json`, `node/package-lock.json` | Version `0.101.2-swarm.3`, repository points here, and a `"swarm"` block naming the upstream base and the chat host. |
| `.github/workflows/swarm-tests.yml` | **new.** `cargo test -p libsignal-net --lib`, `cargo test -p libsignal-bridge-types --lib`, `npm run tsc/lint/format -c`. |
| `.github/workflows/swarm-node-release.yml` | **new.** Prebuilds for win32-x64, linux-x64, darwin-arm64 (darwin-x64 optional) attached to a GitHub Release, then the npm tarball. |
| `.gitignore` | Ignores `rust/net/res/swarm/swarm-root-ca.pem`. |
| `docs/SWARM-CHANGES.md`, `docs/HOW-DESKTOP-USES-IT.md` | **new.** This file, and the consumption guide for the desktop app. |

Nothing else in the tree is modified. Upstream's own workflows are left exactly as they were (they
are not run here; they target `main` and upstream's self-hosted runner sizes).

## The SWARM environments

```
Environment::Swarm         Environment::SwarmStaging
chat.swarm.green           staging.chat.swarm.green
port 443, HTTP/2 (h2)      port 443, HTTP/1.1
TLS 1.3 minimum            TLS 1.2 minimum
x-signal-timestamp         no confirmation header
```

`Environment::Swarm` uses HTTP/2 since `0.101.2-swarm.2`, exactly like upstream's production chat
config: the chat websocket opens as an RFC 8441 extended CONNECT and gRPC rides the same HTTP/2
connection. libsignal 0.101.2 makes some calls **only** over that gRPC connection (username
reserve/confirm/delete, username links, device name, list/remove devices, registration lock,
discoverability, push token, backups) and panics with "requires an H2 connection" when there is
none; with HTTP/1.1 (`0.101.2-swarm.1`) a user could not set a username. There is no HTTP/1.1
fallback on this route. `Environment::SwarmStaging` stays on HTTP/1.1 until a staging deployment
exists on `staging.chat.swarm.green`.

Both share these properties:

- **TLS trust**: `SWARM_ROOT_CERTIFICATES` - the public Let's Encrypt roots (since `0.101.2-swarm.3`:
  both roots in every current OS trust store, ISRG Root X1/X2, **and** Let's Encrypt's
  next-generation roots ISRG Root YE/YR, pinned ahead of OS adoption - see
  `rust/net/res/swarm/README.md`), plus any private SWARM root compiled in. A normal certificate for
  the host works. Signal's roots are not trusted, so a SWARM build cannot complete a TLS handshake
  with Signal's servers even if pointed at one.
- **No DNS pinning**: no hardcoded fallback IP addresses (the resolver drops empty entries). Name
  resolution uses the system resolver first, with Cloudflare DNS-over-HTTPS as the fallback - that
  is upstream behaviour, and it is worth knowing that a failed system lookup means a query to
  `1.1.1.1`.
- **No domain fronting / no censorship circumvention**: `proxy: None` and an empty reflector list.
  Signal's reflectors (Fastly/Google fronts) are never used.
  `Net.setCensorshipCircumventionEnabled(true)` is a logged no-op.
- **No CDSI, no SVR2, no SVRB**: see the next section. The app must keep contact discovery and
  PIN/backup recovery switched off.
- **Key transparency is not configured**: the `KeyTransConfig` for SWARM is all zeroes, so no
  key-transparency proof can verify. Do not enable that feature against a SWARM server until SWARM
  deploys a KT log and real keys land here.

### How "absent" enclave services are modelled

Upstream's `Env` has non-optional `cdsi`, `svr2` and `svr_b` endpoints, because Signal always
deploys them; there is no upstream representation of "this environment has none". Making those
fields `Option` would have rippled through the CDSI/SVR bridge code for all four language bindings,
so instead:

1. `Env` gained one field, `enclave_services: EnclaveServices` (`Available` / `Absent`).
   `STAGING`, `PROD` and the localhost test env are `Available`; both SWARM envs are `Absent`.
2. The SWARM environments carry **placeholder** endpoints that cannot connect:
   hostname `service-not-deployed.swarm.invalid` (`.invalid` is reserved by RFC 2606 and can never
   resolve), no fallback IPs, no proxy, an empty trust store, and the non-attestable enclave id
   `swarm:no-enclave-services`.
3. `Env::static_fallback` skips those endpoints, so the placeholder hostname never reaches the DNS
   fallback map.

A CDSI lookup or SVR operation in a SWARM environment therefore fails while connecting, with a DNS
or TLS error, and can never reach anybody else's enclave. Clients should test
`enclave_services`/keep the features disabled rather than rely on the failure. Exposing
`enclave_services` through the Node bridge would need a new bridged function; it is not exposed yet
(see Open items).

### Hostname overrides at run time

There is no run-time hostname override in upstream libsignal, and none was added: `Env` stores
`&'static str` hostnames and `Net`'s constructor only takes an `Environment` number. The one
existing override is upstream's local test server:

```ts
new Net({
  localTestServer: true,
  userAgent,
  TESTING_localServer_chatPort: 8080,
  TESTING_localServer_cdsiPort: 0,
  TESTING_localServer_svr2Port: 0,
  TESTING_localServer_svrBPort: 0,
  TESTING_localServer_rootCertificateDer: der,  // self-signed root, at run time
});
```

That path uses hostname `localhost` and accepts a self-signed root certificate, which is what a
stack on a developer machine needs. For a hosted staging server, point DNS at it and use
`Environment.SwarmStaging`; changing the compiled-in hostname otherwise means a rebuild. If a
free-form host is ever needed in a shipped build, the smallest change is a node-only
`#[bridge_fn(jni = false, ffi = false)] ConnectionManager_newSwarm(userAgent, chatHost, chatPort,
rootCertificateDer, ...)` plus a new `NetConstructorOptions` variant - roughly 60 lines, and it
regenerates `node/ts/Native.ts`.

## Server-side requirements this implies

- `chat.swarm.green` must serve **TLS 1.3** with a certificate chaining to a trusted root (Let's
  Encrypt is the expected case), and must answer the websocket paths `/v1/websocket/` and
  `/v1/websocket/provisioning/`.
- It must send the `x-signal-timestamp` response header (a Signal-Server fork does; a reverse proxy
  must pass it through). Without it, libsignal treats responses as unconfirmed and reports
  `PossibleCaptiveNetwork`. `staging.chat.swarm.green` does not require the header.
- **HTTP/2 with ALPN `h2`** on `chat.swarm.green` (since `0.101.2-swarm.2`), advertising
  `SETTINGS_ENABLE_CONNECT_PROTOCOL` (RFC 8441) and answering the websocket paths as extended
  CONNECTs, and routing `Content-Type: application/grpc` requests to the chat server's gRPC
  services (Signal-Server's "omnibus" listener). The SWARM staging edge does this with Caddy
  (`GODEBUG=http2xconnect=1` plus a `protocol grpc` route): see `docs/STAGING.md` section 5b in
  `Swarm-Official/swarm-messenger-server`. A server that offers only HTTP/1.1 is unusable with
  `Environment::Swarm` from `0.101.2-swarm.2` on.
- `staging.chat.swarm.green` (`Environment::SwarmStaging`): HTTP/1.1.

## What is *not* in libsignal

CDN and SFU hostnames are **not** part of libsignal - it has no CDN or calling configuration at
all. `cdn.chat.swarm.green`, `reg.chat.swarm.green` and `sfu.chat.swarm.green` belong in
Signal-Desktop's own config (`config/*.json`: `serverUrl`, `cdn`, `cdnUrl*`, `sfuUrl`,
`updatesUrl`, ...) and in the server deployment. Setting `Environment.Swarm` changes the chat
connection only; the desktop's REST, attachment and calling endpoints must be pointed at SWARM
separately. See `docs/HOW-DESKTOP-USES-IT.md`.

## Open items

- `enclave_services` is not exposed to the app languages; the desktop must keep contact discovery
  and SVR off by its own configuration.
- Key transparency keys for SWARM are placeholders (all zeroes).
- Linux prebuilds are built on `ubuntu-latest` (glibc 2.39) rather than upstream's older Docker
  image, so a Linux build of the app may not run on much older distributions.
- darwin-x64 is built only when the release workflow is dispatched with `include_darwin_x64`.
- No `attestation`/provenance signing of the prebuilds (upstream uses `actions/attest`); the release
  publishes SHA-256 sums instead.
- Upstream bump to 0.103.x (or later) whenever Signal-Desktop is upgraded.
