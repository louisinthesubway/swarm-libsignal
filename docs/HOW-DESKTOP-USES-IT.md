# How SWARM Messenger Desktop uses this library

For Opus M-A (desktop). This is the consumption guide for
`@signalapp/libsignal-client` **0.101.2-swarm.2** (HTTP/2 chat connection, so usernames work;
`0.101.2-swarm.1` was HTTP/1.1), built from
[Swarm-Official/swarm-libsignal](https://github.com/Swarm-Official/swarm-libsignal), branch
`swarm-main`.

What changed, in one line: `Net.Environment` now has **`Swarm` (2)** and **`SwarmStaging` (3)**
alongside Signal's `Staging` (0) and `Production` (1). `Environment.Swarm` connects to
`chat.swarm.green` over TLS 1.3, trusting the public Let's Encrypt roots, with no CDSI, no SVR, no
domain fronting and no key transparency. Details and the full diff:
[`SWARM-CHANGES.md`](SWARM-CHANGES.md). The protocol crates are byte-for-byte upstream v0.101.2, so
no cryptography changed and no API you already use was removed.

## 1. Get the package

The release is on a **private** repository, so anonymous `https://` download will not work; use the
GitHub CLI (already authenticated as `brs-holding`):

```bash
cd D:/swarm-messenger/Signal-Desktop
mkdir -p vendor
gh release download swarm-libsignal-0.101.2-swarm.2 \
  -R Swarm-Official/swarm-libsignal \
  --pattern 'signalapp-libsignal-client-*.tgz' \
  --dir vendor --clobber
gh release download swarm-libsignal-0.101.2-swarm.2 \
  -R Swarm-Official/swarm-libsignal \
  --pattern 'SHA256SUMS.txt' --dir vendor --clobber
sha256sum vendor/signalapp-libsignal-client-0.101.2-swarm.2.tgz
```

Expected hashes: see `SHA256SUMS.txt` in the release, and the table at the bottom of this file.

The tarball contains the prebuilt native library for **win32-x64**, **linux-x64** and
**darwin-arm64** under `prebuilds/<platform>-<arch>/@signalapp+libsignal-client.node`, which is
where `node-gyp-build` looks, so nothing has to be compiled on the developer's machine. darwin-x64
is only present when the release workflow was dispatched with `include_darwin_x64`.

## 2. Wire it into the pnpm workspace

Two options. **The first is recommended** because it needs no lockfile surgery and survives
`pnpm install` cleanly.

### (a) Replace the dependency (recommended)

In `Signal-Desktop/package.json`:

```diff
-    "@signalapp/libsignal-client": "0.101.2",
+    "@signalapp/libsignal-client": "file:./vendor/signalapp-libsignal-client-0.101.2-swarm.1.tgz",
```

then `pnpm install`. pnpm unpacks the tarball into the store; the import specifier
`@signalapp/libsignal-client` is unchanged, so not one import line in the app changes. Commit the
tarball only if the repository can carry ~40 MB - otherwise keep `vendor/` git-ignored and document
the `gh release download` step in the desktop README (a fresh clone runs it before `pnpm install`).

### (b) pnpm override (if the dependency string must stay `0.101.2`)

In `Signal-Desktop/package.json`:

```json
{
  "pnpm": {
    "overrides": {
      "@signalapp/libsignal-client": "file:./vendor/signalapp-libsignal-client-0.101.2-swarm.1.tgz"
    }
  }
}
```

An override also redirects any transitive dependency (for example `@signalapp/mock-server`), which
is what you want: only one copy of libsignal must be loaded. A URL override pointing at the GitHub
release asset is *not* usable while the repository is private - pnpm cannot authenticate - so keep
the `file:` form.

Verify after installing:

```bash
node -e "const p=require('@signalapp/libsignal-client/package.json'); console.log(p.version, p.swarm)"
# 0.101.2-swarm.1 { upstream: 'v0.101.2', chatHost: 'chat.swarm.green', ... }
node -e "const {Net}=require('@signalapp/libsignal-client'); console.log(Net.Environment.Swarm)"
# 2
```

The `swarm` block in `package.json` is a reliable marker that a SWARM build is installed; the
startup guard can assert it.

## 3. Use the new environment

In `ts/textsecure/preconnect.preload.ts`, `resolveLibsignalNet()` currently refuses
`unsupported-custom-host` (the M1 guard). With this package the SWARM case becomes a real branch.
Suggested shape, keeping the refusals for Signal hosts exactly as they are:

```ts
const swarmTarget = describeLibsignalNetTarget(url);
if (swarmTarget === 'signal-staging' || swarmTarget === 'signal-production') {
  throw new Error(/* unchanged */);
}
if (swarmTarget === 'swarm-production') {          // new: chat.swarm.green
  log.info('libsignal net environment resolved to SWARM');
  return new Net.Net({ env: Net.Environment.Swarm, userAgent });
}
if (swarmTarget === 'swarm-staging') {             // new: staging.chat.swarm.green
  log.info('libsignal net environment resolved to SWARM staging');
  return new Net.Net({ env: Net.Environment.SwarmStaging, userAgent });
}
if (swarmTarget === 'local-test-server' && certificateAuthority !== undefined) {
  /* unchanged localTestServer branch */
}
throw new Error(
  `SWARM Messenger cannot reach ${url}: libsignal only knows chat.swarm.green, ` +
    'staging.chat.swarm.green and a loopback test server.'
);
```

and in `ts/util/swarm/endpointGuard.std.ts`, extend `describeLibsignalNetTarget` so that hostname
`chat.swarm.green` returns `'swarm-production'` and `staging.chat.swarm.green` returns
`'swarm-staging'`. Everything else keeps returning `'unsupported-custom-host'`, so the
never-talk-to-Signal guarantee and the "no silent fallback" behaviour stay intact. The final
`Net.Environment.Production` fallback in the old code must not come back.

**The compiled-in hostnames are the only ones that work.** `serverUrl` in
`config/*.json` must be `https://chat.swarm.green` (or `https://staging.chat.swarm.green`) exactly;
libsignal takes the host from its own tables, not from the URL, and a mismatch would mean the
websocket goes to one host while the REST API goes to another.

## 4. What must stay switched off

| Feature | Why |
| --- | --- |
| Contact discovery (`CDSI`, `libsignalNet.cdsiLookup`) | SWARM deploys no CDSI enclave. The endpoint is a placeholder on an unresolvable `.invalid` host, so a lookup fails while connecting. |
| PIN / registration lock recovery (`svr2`) and backup keys (`svrB`) | same: no SVR2/SVRB deployment. |
| Key transparency | the SWARM key-transparency configuration is all zeroes; no proof can verify. |
| Censorship circumvention | there are no SWARM reflector proxies. `setCensorshipCircumventionEnabled(true)` is accepted and logged, then ignored - it will not crash, and it will not route through Signal's Fastly/Google fronts. |

Anything that calls those paths should be feature-flagged off in the desktop build rather than left
to fail at connect time.

## 5. What this package does *not* configure

libsignal has no CDN, registration or calling configuration at all. These stay in the desktop's own
`config/*.json` and are M-A's/M-B's to set:

```
serverUrl        https://chat.swarm.green
storageUrl       https://chat.swarm.green        (or its own host)
cdnUrl0/2/3      https://cdn.chat.swarm.green
sfuUrl           https://sfu.chat.swarm.green
updatesUrl, resourcesUrl, contentProxyUrl, challengeUrl ...
```

Only the chat websocket (and provisioning socket) comes from `Environment.Swarm`.

## 6. Server-side requirements

- TLS 1.3 on `chat.swarm.green` with a publicly trusted certificate (Let's Encrypt is the expected
  case; the two ISRG roots are compiled in). TLS 1.2 is accepted on
  `staging.chat.swarm.green` only.
- The response header `x-signal-timestamp` must reach the client on `chat.swarm.green`
  (Signal-Server sends it; a reverse proxy must not strip it). Without it libsignal reports
  `PossibleCaptiveNetwork`. Staging does not require it.
- `Environment.Swarm` (since `0.101.2-swarm.2`): HTTP/2 only (ALPN `h2`). The websocket paths
  `/v1/websocket/` and `/v1/websocket/provisioning/` are opened as RFC 8441 extended CONNECTs, so
  the server must advertise `SETTINGS_ENABLE_CONNECT_PROTOCOL`, and `Content-Type:
  application/grpc` requests on the same connection must reach the chat server's gRPC services
  (usernames, devices and backups exist only there). `Environment.SwarmStaging`: HTTP/1.1
  websocket upgrades on the same two paths.
- If the staging server uses a private CA, either use the loopback
  `localTestServer` path (root certificate passed at run time) or ask for a rebuild with
  `SWARM_TLS_ROOT_CA_PEM` - see [`SWARM-CHANGES.md`](SWARM-CHANGES.md).

## 7. Rebuilding or changing the library

```
Workflow "SWARM - node prebuilds and release" (workflow_dispatch)
  inputs: tag (default swarm-libsignal-0.101.2-swarm.2), include_darwin_x64
  jobs:   prepare -> build (linux-x64, win32-x64, darwin-arm64) -> package
```

Every output is attached to the release; the org's Actions artifact storage is exhausted, so the
workflow deliberately does not use `actions/upload-artifact`. Ask Opus M-D (or dispatch it
yourself) if a hostname, a root CA or the upstream base has to change. Do not patch the `.node`
binary or the tarball by hand.

## 8. Hashes

Release page:
<https://github.com/Swarm-Official/swarm-libsignal/releases/tag/swarm-libsignal-0.101.2-swarm.1>

These are the values in the release's `SHA256SUMS.txt`. Check the tarball against the first row
before you install it.

| File | SHA-256 |
| --- | --- |
| `signalapp-libsignal-client-0.101.2-swarm.1.tgz` | `34719bf6eaec78b50a0b70ed1d36465de2b1dbcf712d9288971571efffcebfe4` |
| `prebuilds/win32-x64/@signalapp+libsignal-client.node` | `f5f07db01c0867f67c00bd276ba7215e29ee0a6bfa57274a7b677ac1f94f2a6a` |
| `prebuilds/linux-x64/@signalapp+libsignal-client.node` | `541d839dc8ce43adab21460d0e9b54e84f45ae513967e69de09ea14ef0cd85ef` |
| `prebuilds/darwin-arm64/@signalapp+libsignal-client.node` | `c5657e5fd393e91a724dd5306d3d7fb561c11e5ca8eba779204e1a11c7201eb2` |

The three `.node` rows are also attached to the release on their own, as
`libsignal-client-<platform>-<arch>.node`, each with a `SHA256SUMS-<platform>-<arch>.txt` written by
the runner that built it. Those per-platform sums were computed on three different machines and they
agree with the table above, so the libraries inside the tarball are the ones the CI runners built -
nothing was rebuilt or repacked in between.

### Provenance, precisely

Worth knowing before you audit the tarball, because it is not a single-commit build:

- The three native libraries were built by run
  [36260619050](https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36260619050) from
  commit `f6843eab1` ("Match rustfmt on the SWARM additions").
- The JavaScript, the type declarations and `package.json` were packed from `2630f1683` ("Record the
  settled SWARM service hosts next to the chat host"), the current tip of `swarm-main`. That is why
  `SWARM_HOSTS` and the four-host `swarm` block are in the package.

One more drift, from after the pack: `node/package.json` has since been reformatted by Prettier, which
moves the `swarm` block below `devDependencies` and puts `environments` on three lines. The packed
copy has the old key order. Same keys, same values, so `require('@signalapp/libsignal-client/package.json').swarm`
reads identically and the checks in section 2 behave the same - but a byte diff against the tip will
show it.

The only Rust change between those two commits is `rust/net/src/env.rs`, +41 lines and zero
deletions: the `pub const` hostname strings and the tests that assert them. None of those constants
is referenced anywhere outside `env.rs`, and none is exported through the bridge, so none of them can
appear in a `.node` binary - the natives are behaviourally identical to the tip. The mismatch is
cosmetic, but it is real: for single-commit provenance, re-dispatch the release workflow at
`2630f1683`, and expect every hash in the table above to change.

The `package` job of that run failed, which is why the tarball was packed and hashed on the
maintainer's machine rather than by CI. It failed *before it started*, on GitHub billing ("recent
account payments have failed or your spending limit needs to be increased"), not on anything in this
repository: the three build jobs ahead of it all passed, and `SWARM - tests` is green on the tip
([36261683481](https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36261683481)). The
local pack did what that job would have done, and the per-platform sums above are the independent
check on it. Re-dispatching the workflow will keep failing at `package` until the org's Actions
billing is sorted out - that is an owner action, not a code fix.
