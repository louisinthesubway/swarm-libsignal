# SWARM changes to libsignal

This repository is a fork of [signalapp/libsignal](https://github.com/signalapp/libsignal). The
same SWARM change is carried on one branch per upstream version that a SWARM app pins:

| Branch | Upstream base | Built for | Package | Selects SWARM with |
| --- | --- | --- | --- | --- |
| `swarm-main` | **v0.101.2** = `eb7864c4d` (Signal-Desktop `abe80d3` pins it) | desktop | npm `@signalapp/libsignal-client` 0.101.2-swarm.1, release `swarm-libsignal-0.101.2-swarm.1` | `Net.Environment.Swarm` |
| `swarm-v0.102.2` | **v0.102.2** = `8fc2113bd` (Signal-Android v8.29.1 pins it) | Android | Maven `org.signal:libsignal-android` / `libsignal-client` 0.102.2-swarm.1, release `swarm-libsignal-0.102.2-swarm.1` | `Network.Environment.SWARM` |
| `swarm-v0.102.3` | **v0.102.3** = `91abf5000` (Signal-iOS 8.30.0.1882 pins it) | iOS | CocoaPod `LibSignalClient` 0.102.3-swarm.1, release `swarm-libsignal-0.102.3-swarm.1` | `Net.Environment.swarm` |

The upstream bases are also pushed as tags `upstream-v0.101.2`, `upstream-v0.102.2` and
`upstream-v0.102.3`. How the Android and iOS apps consume their builds:
[`SWARM-MOBILE.md`](SWARM-MOBILE.md). How the desktop consumes its build:
`docs/HOW-DESKTOP-USES-IT.md` on `swarm-main`.

**Not changed:** nothing under `rust/protocol`, `rust/crypto`, `rust/zkgroup`, `rust/zkcredential`,
`rust/poksho`, `rust/attest`, `rust/svrb`, `rust/keytrans`, `rust/core`, `rust/account-keys` or any
other cryptographic crate. The double ratchet, PQXDH, SPQR, sealed sender and zkgroup code on each
branch is byte-for-byte its upstream base; each release's notes carry the
`git diff --stat upstream-vX..<commit>` that proves it. This fork only adds **network environment
constants** and the bindings needed to select them.

## Why

libsignal compiles its network environments into Rust. Upstream, `Net.Environment` offers only
`Staging` and `Production`, both of which are Signal's own deployments: Signal hostnames, Signal's
root certificates, Signal's CDSI/SVR enclave identities and Signal's censorship-circumvention
reflectors. A rebranded client configured with a SWARM hostname does not get a SWARM connection -
the libsignal layer silently uses Signal's production servers, which their terms forbid and which
would leak SWARM traffic to a third party.

## The diff, file by file

### The SWARM environment (all three branches)

The six `swarm-main` commits (`495b37040` .. `adb95335b`), cherry-picked with `-x` onto the mobile
branches. `git range-diff` between the three series shows no difference except the package version
strings.

| File | Change |
| --- | --- |
| `rust/net/res/swarm/isrg-root-x1.cer`, `isrg-root-x2.cer` | **new.** The two public Let's Encrypt (ISRG) roots, DER. Provenance and fingerprints: `rust/net/res/swarm/README.md`. |
| `rust/net/res/swarm/README.md` | **new.** What the roots are and how to add a private SWARM CA. |
| `rust/net/build.rs` | Generates `$OUT_DIR/swarm_root_ca_ders.rs`: the two roots above plus every certificate in the optional build-time PEM file named by `$SWARM_TLS_ROOT_CA_PEM` (default `rust/net/res/swarm/swarm-root-ca.pem`, git-ignored). Contains a 30-line base64/PEM reader so no build dependency was added. The protobuf part is untouched. |
| `rust/net/src/certs.rs` | Adds `SWARM_ROOT_CERTIFICATES` (the generated list) and `NO_ROOT_CERTIFICATES` (an empty trust store). Adds tests asserting the ISRG fingerprints, that no Signal root is in the SWARM list, and that every DER parses. |
| `rust/net/src/env.rs` | Adds `SWARM` and `SWARM_STAGING` environments, `EnclaveServices`, the `Env::enclave_services` field, the settled SWARM host constants, and tests. See below. |
| `rust/bridge/shared/types/src/net.rs` | `Environment::Swarm = 2`, `Environment::SwarmStaging = 3` and their mapping to the two new `Env`s. `set_censorship_circumvention_enabled` no longer panics when an environment has no reflector providers - it logs and does nothing. Tests for both. |
| `rust/bridge/shared/testing/src/net_env.rs` | Sets the new `enclave_services` field on the localhost test environment (the mock server does stand in for CDSI/SVR). |
| `node/ts/net.ts`, `node/ts/test/NetTest.ts` | `Environment.Swarm = 2`, `Environment.SwarmStaging = 3`, `SWARM_HOSTS`, and their tests. |
| `node/package.json`, `node/package-lock.json` | Version `<upstream>-swarm.1`, repository points here, and a `"swarm"` block naming the upstream base and the hosts. The Node package is released from `swarm-main` only. |
| `.github/workflows/swarm-tests.yml` | **new.** The SWARM test workflow (see below for what it runs on the mobile branches). |
| `.gitignore` | Ignores `rust/net/res/swarm/swarm-root-ca.pem` and local release outputs. |
| `README.md`, `docs/` | The fork notice and these documents. |

Every bridge entry point that takes an environment (`ConnectionManager_new`, the key transparency
client and SVR-B) receives it as `AsType<Environment, u8>` and converts it with
`derive_more::TryFrom`, so the JNI, FFI and Node functions accept 2 and 3 as soon as the Rust enum
has them: no bridge function signature changed and no generated binding (`Native.kt`,
`signal_ffi.h`, `Native.ts`) had to be regenerated. The SWARM test workflow checks the JNI and FFI
bindings with upstream's own `--verify` generators.

### Added on the mobile branches

| File | Change |
| --- | --- |
| `java/client/src/main/java/org/signal/libsignal/net/Network.java` | `Network.Environment.SWARM(2)` and `SWARM_STAGING(3)`. |
| `java/client/src/test/java/org/signal/libsignal/net/NetworkTest.java` | The enum values match the Rust bridge; censorship circumvention is a no-op that configures no proxy; a chat connection attempt in each SWARM environment, sent through a refusing HTTP CONNECT proxy on 127.0.0.1, asks only for `chat.swarm.green:443` / `staging.chat.swarm.green:443` and never for a host containing `signal`. |
| `swift/Sources/LibSignalClient/Net.swift` | `Net.Environment.swarm = 2` and `.swarmStaging = 3`. |
| `swift/Tests/LibSignalClientTests/NetTests.swift` | The same three tests as the Java ones (`SwarmNetTests`). |
| `java/build.gradle`, `java/client/build.gradle`, `java/android/build.gradle` | (`swarm-v0.102.2`) version `0.102.2-swarm.1`; the POMs name this repository as the project URL and SCM, and say it is a SWARM build. |
| `LibSignalClient.podspec` | (`swarm-v0.102.3`) version `0.102.3-swarm.1`; homepage and source point here; the prebuilt `libsignal_ffi.a` archive is downloaded from this repository's release instead of Signal's artifact host. |
| `.github/workflows/swarm-android-release.yml` | (`swarm-v0.102.2`) **new.** Builds the AAR and JAR, tests them, publishes the release and the `maven` branch, and checks that a fresh Gradle build consumes them. |
| `.github/swarm/maven-repository.init.gradle` | (`swarm-v0.102.2`) **new.** Gives the Gradle build a file-system Maven repository to publish into; nothing is published to Signal's bucket. |
| `.github/workflows/swarm-ios-release.yml` | (`swarm-v0.102.3`) **new.** Builds the iOS archive (device and simulator), lints the pod, publishes the release, and checks that a fresh CocoaPods project consumes it. |
| `.github/workflows/swarm-node-release.yml` | **removed** on the mobile branches: the Node package is released from `swarm-main` only, and dispatching it from a mobile branch would have attached 0.102.x libraries to the 0.101.2 release. |

The Java and Swift tests live in files upstream already has, because the licence headers of new
files are enforced (spotless, swiftlint) and a new file would have to claim Signal's copyright.

## The SWARM environments

```
Environment::Swarm         Environment::SwarmStaging
chat.swarm.green           staging.chat.swarm.green
port 443, HTTP/1.1         port 443, HTTP/1.1
TLS 1.3 minimum            TLS 1.2 minimum
x-signal-timestamp         no confirmation header
```

Both share these properties:

- **TLS trust**: `SWARM_ROOT_CERTIFICATES` - the public Let's Encrypt roots, plus any private SWARM
  root compiled in. A normal certificate for the host works. Signal's roots are not trusted, so a
  SWARM build cannot complete a TLS handshake with Signal's servers even if pointed at one.
- **No DNS pinning**: no hardcoded fallback IP addresses (the resolver drops empty entries). Name
  resolution uses the system resolver first, with Cloudflare DNS-over-HTTPS as the fallback - that
  is upstream behaviour, and it is worth knowing that a failed system lookup means a query to
  `1.1.1.1`.
- **No domain fronting / no censorship circumvention**: `proxy: None` and an empty reflector list.
  Signal's reflectors (Fastly/Google fronts) are never used.
  `setCensorshipCircumventionEnabled(true)` is a logged no-op in every binding.
- **No CDSI, no SVR2, no SVRB**: see the next section. The app must keep contact discovery and
  PIN/backup recovery switched off.
- **Key transparency is not configured**: the `KeyTransConfig` for SWARM is all zeroes, so no
  key-transparency proof can verify. Do not enable that feature against a SWARM server until SWARM
  deploys a KT log and real keys land here.
- **Chat over WebSocket only**: the chat host is configured for HTTP/1.1, so the connection has no
  HTTP/2 channel. Typed APIs that have both a WebSocket and a gRPC implementation fall back to the
  WebSocket one (upstream's `grpc_service_to_use_instead` finds no HTTP/2 connection); APIs that
  exist only over gRPC cannot work against the SWARM chat host until it offers gRPC. This follows
  from the code; it has not been exercised against a live server.

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
or TLS error, and can never reach anybody else's enclave. Clients should keep the features disabled
rather than rely on the failure. `enclave_services` is not exposed through any bridge yet (see Open
items).

### Hostname overrides at run time

There is no run-time hostname override in upstream libsignal, and none was added: `Env` stores
`&'static str` hostnames and every binding's constructor only takes an `Environment` number. For a
hosted staging server, point DNS for `staging.chat.swarm.green` at it and select the staging
environment; a private CA can be compiled in with `SWARM_TLS_ROOT_CA_PEM` (see
`rust/net/res/swarm/README.md`). Upstream's local-test-server constructor (hostname `localhost`, a
port and a self-signed root at run time) exists in the Node binding only.

## Server-side requirements this implies

- `chat.swarm.green` must serve **TLS 1.3** with a certificate chaining to a trusted root (Let's
  Encrypt is the expected case), and must answer the websocket paths `/v1/websocket/` and
  `/v1/websocket/provisioning/`.
- It must send the `x-signal-timestamp` response header (a Signal-Server fork does; a reverse proxy
  must pass it through). Without it, libsignal treats responses as unconfirmed and reports
  `PossibleCaptiveNetwork`. `staging.chat.swarm.green` does not require the header.
- HTTP/1.1. gRPC over HTTP/2 (upstream's `grpc.chat.signal.org` path) is not configured for SWARM.

## What is *not* in libsignal

CDN, registration and SFU hostnames are **not** used by libsignal - it has no CDN or calling
configuration at all. `cdn.chat.swarm.green`, `reg.chat.swarm.green` and `sfu.chat.swarm.green` are
recorded as constants next to the chat host (Rust `SWARM_*_HOSTNAME`, Node `SWARM_HOSTS`) so every
app can check its own configuration against one list, but they belong in each app's own config and
in the server deployment. Selecting the SWARM environment changes the libsignal chat connection
only; each app's REST, attachment, registration and calling endpoints must be pointed at SWARM
separately.

## Open items

- `enclave_services` is not exposed to the app languages; the apps must keep contact discovery and
  SVR off by their own configuration.
- Key transparency keys for SWARM are placeholders (all zeroes).
- No provenance signing of the release artifacts (upstream signs its Maven artifacts with PGP and
  attests its npm builds); the releases publish SHA-256 sums instead.
- Android instrumented tests (upstream's `connectedAndroidTest` suite) are not run: they need an
  emulator or device.
- Upstream bumps: cherry-pick the SWARM commits onto the new upstream tag, as was done for the
  mobile branches, whenever an app moves to a newer libsignal.
