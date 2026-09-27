# SWARM libsignal for the Android and iOS apps

For Opus M5-A (Android) and Opus M5-I (iOS). This is exactly what the two app forks consume: which
artifact, from where, with which checksum, and how to select the SWARM network in the app. What the
SWARM environment is and what changed in libsignal: [`SWARM-CHANGES.md`](SWARM-CHANGES.md).

| App fork | Upstream pin | SWARM build | Source |
| --- | --- | --- | --- |
| Signal-Android `v8.29.1` | `org.signal:libsignal-android` / `libsignal-client` **0.102.2** | **0.102.2-swarm.1** from the `maven` branch of this repository | branch `swarm-v0.102.2`, release/tag `swarm-libsignal-0.102.2-swarm.1` |
| Signal-iOS `8.30.0.1882` | `LibSignalClient` git tag **v0.102.3** | `LibSignalClient` **0.102.3-swarm.1**, prebuilt `libsignal_ffi.a` from the release | branch `swarm-v0.102.3`, release/tag `swarm-libsignal-0.102.3-swarm.1` |

Both builds are the upstream version the app already pins plus the SWARM network environment and
nothing else: no API was removed or changed, so the app's own code keeps compiling. The protocol and
cryptography crates are byte-for-byte upstream (each release's notes carry the
`git diff --stat upstream-vX..<commit>`).

## Android (Signal-Android v8.29.1)

### 1. Repository

In `settings.gradle.kts`, inside `dependencyResolutionManagement { repositories { ... } }`, add this
block (anywhere in the list; `exclusiveContent` makes it the only place Gradle looks for these two
modules):

```kotlin
exclusiveContent {
  forRepository {
    maven {
      name = "SwarmLibsignal"
      url = uri("https://raw.githubusercontent.com/Swarm-Official/swarm-libsignal/maven/")
    }
  }
  filter {
    includeModule("org.signal", "libsignal-android")
    includeModule("org.signal", "libsignal-client")
  }
}
```

This is a plain, public Maven repository (the orphan `maven` branch of this repository, served by
`raw.githubusercontent.com`): no credentials, no plugin. Because of `exclusiveContent`, Gradle never
asks Signal's artifact host (`SignalBuildArtifacts`, which matches `org\.signal.*`) for libsignal,
and a stray request for upstream `0.102.2` fails loudly instead of silently resolving Signal's
build. The other `org.signal` artifacts the app uses (for example `ringrtc-android` 2.72.0) still
resolve from wherever the app's other repositories point; that is outside this repository.

### 2. Version

In `gradle/libs.versions.toml`:

```toml
libsignal-client = "0.102.2-swarm.1"
```

(Both `libsignal-client` and `libsignal-android` use that version reference.)

### 3. Dependency verification

Signal-Android verifies dependencies (`gradle/verification-metadata.xml`). Replace the two
`0.102.2` components with these (values from `SHA256SUMS.txt` of the release):

```xml
<!-- SWARM_ANDROID_VERIFICATION_METADATA -->
```

### 4. What is inside

`libsignal-android` is upstream's AAR layout: `jni/<abi>/libsignal_jni.so` and
`libsignal_jni_testing.so` for arm64-v8a, armeabi-v7a, x86_64 and x86 (Signal-Android already
leaves the testing library out of release builds), plus the Java/Kotlin classes, and it
depends on `libsignal-client` of the same version. `libsignal-client` carries the desktop JNI
libraries for Linux x86_64, macOS (x86_64, aarch64) and Windows x86_64, which the app's JVM unit
tests load. One difference from upstream's packaging: the ELF libraries (Android and Linux) have
their DWARF debug sections removed (`llvm-strip --strip-debug`; code, exported JNI symbols and the
symbol table stay). With upstream's line tables the AAR is about 200 MB, over GitHub's 100 MB
limit for the `maven` branch, and an APK is unaffected because the Android Gradle plugin strips
native libraries when it packages the app. The unstripped libraries, exactly as built, are in
the release asset `libsignal-jni-unstripped-0.102.2-swarm.1.tar.gz` for symbolicating native
crashes.

### 5. Select the SWARM network

`app/build.gradle.kts` sets `LIBSIGNAL_NET_ENV` (line 299 for the production environment, line 501
for staging, at v8.29.1). Point it at SWARM:

```kotlin
buildConfigField("org.signal.libsignal.net.Network.Environment", "LIBSIGNAL_NET_ENV", "org.signal.libsignal.net.Network.Environment.SWARM")
```

`Network.Environment.SWARM` = `chat.swarm.green`; `Network.Environment.SWARM_STAGING` =
`staging.chat.swarm.green`.

## iOS (Signal-iOS 8.30.0.1882)

### 1. Podfile

Replace the two libsignal lines (lines 14-15 at 8.30.0.1882) with:

```ruby
ENV['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'] = '<!-- SWARM_IOS_CHECKSUM -->'
pod 'LibSignalClient', git: 'https://github.com/Swarm-Official/swarm-libsignal.git', tag: 'swarm-libsignal-0.102.3-swarm.1', testspecs: ["Tests"]
```

(`testspecs` is optional; Signal-iOS uses it.) Then `pod install`; `Podfile.lock` records
`LibSignalClient (0.102.3-swarm.1)`.

The podspec at that tag downloads
`https://github.com/Swarm-Official/swarm-libsignal/releases/download/swarm-libsignal-0.102.3-swarm.1/libsignal-client-ios-build-v0.102.3-swarm.1.tar.gz`
into `~/Library/Caches/org.signal.libsignal/` and refuses it unless its SHA-256 equals
`LIBSIGNAL_FFI_PREBUILD_CHECKSUM`. The archive holds `libsignal_ffi.a` for `aarch64-apple-ios`
(device), `aarch64-apple-ios-sim` and `x86_64-apple-ios` (simulators) in upstream's layout, so the
podspec's build settings are unchanged. As upstream, the device library leaves out the testing
entry points.

### 2. Select the SWARM network

Wherever the app creates its `Net`, pass `.swarm` (`chat.swarm.green`) or `.swarmStaging`
(`staging.chat.swarm.green`):

```swift
let net = Net(env: .swarm, userAgent: userAgent, buildVariant: .production)
```

## What the SWARM environment does and does not do (both apps)

- It changes the **libsignal chat connection only** (`chat.swarm.green`, TLS 1.3, publicly trusted
  certificates, HTTP/2 with the websocket as an RFC 8441 extended CONNECT and gRPC on the same
  connection, exactly as upstream dials its production chat host). Each app's REST, attachment
  (`cdn.chat.swarm.green`), registration (`reg.chat.swarm.green`) and calling
  (`sfu.chat.swarm.green`) endpoints live in the app's own configuration and must be pointed at
  SWARM there.
- SWARM deploys **no contact discovery (CDSI), no SVR2/SVRB and no key transparency**: those
  endpoints are placeholders that cannot connect (`service-not-deployed.swarm.invalid`, empty trust
  store), and the key transparency keys are zeroes. Keep contact discovery, PIN/backup recovery and
  key transparency switched off in the app.
- **No censorship circumvention**: SWARM runs no reflectors, so
  `setCensorshipCircumventionEnabled(true)` is a logged no-op.
- **The chat server must speak HTTP/2 and gRPC**: usernames, device management, registration
  lock, discoverability, push tokens and backups go only over gRPC on the chat connection, and
  libsignal panics ("requires an H2 connection") without it. `chat.swarm.green` must offer ALPN
  `h2`, RFC 8441 extended CONNECT for the websocket, and route `application/grpc` to the chat
  server (the SWARM edge does; see `SWARM-CHANGES.md`). `SWARM_STAGING` / `.swarmStaging` still
  dials HTTP/1.1.

## Verification

<!-- SWARM_VERIFICATION -->

## Making a new build

Bump the version (`java/build.gradle` on `swarm-v0.102.2`, `s.version` in `LibSignalClient.podspec`
on `swarm-v0.102.3`) to the next `-swarm.N`, push, and dispatch the release workflow on the branch
with the tag `swarm-libsignal-<version>`:

```bash
gh workflow run swarm-android-release.yml -R Swarm-Official/swarm-libsignal --ref swarm-v0.102.2 -f tag=swarm-libsignal-0.102.2-swarm.2
gh workflow run swarm-ios-release.yml -R Swarm-Official/swarm-libsignal --ref swarm-v0.102.3 -f tag=swarm-libsignal-0.102.3-swarm.2
```

The workflows refuse to overwrite an existing release, tag or Maven version. To follow a newer
upstream libsignal, cherry-pick the SWARM commits onto the new `upstream-vX` tag in a new
`swarm-vX` branch, as `SWARM-CHANGES.md` describes.
