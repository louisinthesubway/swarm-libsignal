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
      <component group="org.signal" name="libsignal-android" version="0.102.2-swarm.1">
         <artifact name="libsignal-android-0.102.2-swarm.1.aar">
            <sha256 value="6edcc0cf10d5d9c56c539e62bd157fe988039a0388642f0519df2f96b7410ad7" origin="swarm-libsignal-0.102.2-swarm.1 SHA256SUMS.txt"/>
         </artifact>
         <artifact name="libsignal-android-0.102.2-swarm.1.module">
            <sha256 value="c8082e9da9a968d91ea8110c90f1fdf89cf33c4f177052737df98cb1c6efbf73" origin="swarm-libsignal-0.102.2-swarm.1 SHA256SUMS.txt"/>
         </artifact>
      </component>
      <component group="org.signal" name="libsignal-client" version="0.102.2-swarm.1">
         <artifact name="libsignal-client-0.102.2-swarm.1.jar">
            <sha256 value="1b029d0e4d9a8841d4e49ae9360711309d7a5635dfb92ebd43fe245adc22f1b2" origin="swarm-libsignal-0.102.2-swarm.1 SHA256SUMS.txt"/>
         </artifact>
         <artifact name="libsignal-client-0.102.2-swarm.1.module">
            <sha256 value="75a52c03887166349ae128fb59d42e4fadd9f8261f3361b526a01f8feef39546" origin="swarm-libsignal-0.102.2-swarm.1 SHA256SUMS.txt"/>
         </artifact>
      </component>
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
ENV['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'] = '9efbb25e146e950ca8be531f2c5c822b7ae6ca659f66d500f2304c1ad8727a46'
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

### Android: release `swarm-libsignal-0.102.2-swarm.1`

Built from `swarm-v0.102.2` at `90a3a9ff60ac6241ca2c2db4fec882e4ab6839ab` (upstream v0.102.2 plus the SWARM commits) by https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36353915436; the same run published the `maven` branch and ran the consumer check.

| File | SHA-256 |
| --- | --- |
| `libsignal-android-0.102.2-swarm.1.aar` | `6edcc0cf10d5d9c56c539e62bd157fe988039a0388642f0519df2f96b7410ad7` |
| `libsignal-client-0.102.2-swarm.1.jar` | `1b029d0e4d9a8841d4e49ae9360711309d7a5635dfb92ebd43fe245adc22f1b2` |
| `libsignal-jni-unstripped-0.102.2-swarm.1.tar.gz` | `5d934fa0f36f77406863190e737603cd6145243acae6390984e6c53dbffeea23` |
| `swarm-libsignal-maven-0.102.2-swarm.1.zip` | `c855c7bde340fac31dcf1fdbc065a17f2afb28fc12b0ed4519e2d73db8d58332` |
| `org/signal/libsignal-android/0.102.2-swarm.1/libsignal-android-0.102.2-swarm.1-dokka.jar` | `c6deada2fac53b8ea6523dbda77597b128006674616f140f04df23264c6d1aa3` |
| `org/signal/libsignal-android/0.102.2-swarm.1/libsignal-android-0.102.2-swarm.1-javadoc.jar` | `c6deada2fac53b8ea6523dbda77597b128006674616f140f04df23264c6d1aa3` |
| `org/signal/libsignal-android/0.102.2-swarm.1/libsignal-android-0.102.2-swarm.1.aar` | `6edcc0cf10d5d9c56c539e62bd157fe988039a0388642f0519df2f96b7410ad7` |
| `org/signal/libsignal-android/0.102.2-swarm.1/libsignal-android-0.102.2-swarm.1.module` | `c8082e9da9a968d91ea8110c90f1fdf89cf33c4f177052737df98cb1c6efbf73` |
| `org/signal/libsignal-android/0.102.2-swarm.1/libsignal-android-0.102.2-swarm.1.pom` | `920d095d1e64663c88ed88fd3fe1109c4f21fcdd89f0542913299cc454d481c9` |
| `org/signal/libsignal-client/0.102.2-swarm.1/libsignal-client-0.102.2-swarm.1-dokka.jar` | `15038377809a7e20f3ec9c748d89b5474058c4823bc95ef662a490ead27148ae` |
| `org/signal/libsignal-client/0.102.2-swarm.1/libsignal-client-0.102.2-swarm.1-javadoc.jar` | `1b08098cd7c32bb797a418991c5f6d6cc64211fea612c0c3372bd1a7cb0ee20b` |
| `org/signal/libsignal-client/0.102.2-swarm.1/libsignal-client-0.102.2-swarm.1-sources.jar` | `9511377400817b2607683c755424d010f8b934875a26f19f895cdf7817bbd9bc` |
| `org/signal/libsignal-client/0.102.2-swarm.1/libsignal-client-0.102.2-swarm.1.jar` | `1b029d0e4d9a8841d4e49ae9360711309d7a5635dfb92ebd43fe245adc22f1b2` |
| `org/signal/libsignal-client/0.102.2-swarm.1/libsignal-client-0.102.2-swarm.1.module` | `75a52c03887166349ae128fb59d42e4fadd9f8261f3361b526a01f8feef39546` |
| `org/signal/libsignal-client/0.102.2-swarm.1/libsignal-client-0.102.2-swarm.1.pom` | `130c7dd3345aabfd814ff8e6738d321b7618ec5749857e2f52e354d5ce2d0a4b` |

```bash
gh release download swarm-libsignal-0.102.2-swarm.1 -R Swarm-Official/swarm-libsignal --dir libsignal-0.102.2-swarm.1
cd libsignal-0.102.2-swarm.1 && sha256sum -c --ignore-missing SHA256SUMS.txt
```

### iOS: release `swarm-libsignal-0.102.3-swarm.1`

Built from `swarm-v0.102.3` at `d9aa96cb3d6cd64a7225bc3b534ef312904f4dbb` (upstream v0.102.3 plus the SWARM commits) by https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36351934896; the same run linted the pod and ran the consumer check.

| File | SHA-256 |
| --- | --- |
| `libsignal-client-ios-build-v0.102.3-swarm.1.tar.gz` | `9efbb25e146e950ca8be531f2c5c822b7ae6ca659f66d500f2304c1ad8727a46` |

### What was tested, and where

- SWARM - tests on `swarm-v0.102.2` at `90a3a9ff6`, the Android release commit: Rust (`cargo test -p libsignal-net`, `cargo test -p libsignal-bridge-types --lib`, `cargo fmt --check`), Java (JNI bindings checked by upstream's generator, the client test suite including the four SWARM tests, spotless), Swift (FFI header checked by upstream's generator, `swift test` including `SwarmNetTests`), swift-format and swiftlint with Xcode 26.3, Node: https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36353914765
- SWARM - tests on `swarm-v0.102.3` at `d9aa96cb3`, the iOS release commit: the same jobs: https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36351711122
- Android release run: the four Android ABIs and the Linux, macOS and Windows JNI libraries built on GitHub-hosted runners, each Android `libsignal_jni.so` contains `chat.swarm.green`; the Java client suite (484 tests, 0 failures) ran against the stripped Linux library that is in the JAR; consumer check: every Maven file served by `raw.githubusercontent.com` matches `SHA256SUMS.txt`, and a fresh Gradle 9.4.1 build resolved both artifacts from the `maven` branch and ran `new Network(Network.Environment.SWARM, ...)` from the published JAR: https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36353915436
- iOS release run: `libsignal_ffi.a` for device and both simulators built with Xcode 26.3, each contains `chat.swarm.green`; `pod lib lint` passed; consumer check: `pod install` from the tag, the podspec's script phase downloaded the archive from the release and checked it against the checksum, and Release builds for `iphonesimulator` and `iphoneos` succeeded: https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36351934896
- Not run: upstream's Android instrumented tests (they need an emulator or device). No app has
  connected to a SWARM server with these builds yet.
- On record, though unplanned: the first version of the Java and Swift SWARM tests sent a chat
  connection through a refusing local HTTP proxy, and libsignal's proxy-then-direct fallback took
  it straight to the real `chat.swarm.green`, which accepted an unauthenticated chat connection:
  over HTTP/1.1 from the Swift tests on Linux
  (https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36344961672,
  https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36344961250), and over HTTP/2
  from the Java tests on Linux and the Swift tests
  (https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36346259921,
  https://github.com/Swarm-Official/swarm-libsignal/actions/runs/36346259378). Those were branch
  builds, not the released artifacts, and the tests were replaced by the hermetic hostname tests
  above.

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
