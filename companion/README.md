# UAI Relay (Android companion)

A foreground service that holds the upstream provider connection so every
executor-visible call is a few milliseconds. Mobile executors cut long `request()`
calls off after a wall-clock limit that a reasoning turn easily exceeds; the
Project UAI client submits a job here, then polls a short loopback route until the
answer is ready. It is **not** the Cowork bridge: there is no web UI, no static
serving, no agent state, no commands. Just the relay contract in
[docs/MOBILE_COMPANION.md](../docs/MOBILE_COMPANION.md) Section 4.

## Requirements

- Android 8.0+ (`minSdk 26`). Sideload only; no Play dependency.
- A mobile executor that exposes `request` / `http_request` / `syn.request` /
  `http.request` / `fluxus.request`. Plain `HttpService` cannot reach loopback
  plain-HTTP or set the discovery header, so without an executor function nothing
  can connect.
- The client's `relay.mode` is `auto` by default: the script probes
  `127.0.0.1:8790`, pairs once for a stable token, and relays from then on.

## Build

JDK 17 and the Android SDK are required (Android Studio bundles both).

```powershell
# From companion/
./gradlew :app:assembleDebug          # APK at app/build/outputs/apk/debug/
./gradlew :app:testDebugUnitTest      # JVM contract tests, no device
```

`local.properties` must point at the SDK if `ANDROID_HOME` is unset:

```properties
sdk.dir=C\:\\Android\\Sdk
```

Install with `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

## Use

1. Start the app and tap **Start**. The notification appears and the relay listens
   on `127.0.0.1:8790` only.
2. In Roblox, run the Project UAI script. The Cowork panel's Relay card shows the
   companion once paired — no token copying.
3. Keep Roblox and the relay running. **Stop** in the app is authoritative: the
   watchdogs stay down until you start again.

## Survival notes

- The service uses `foregroundServiceType="specialUse"`; Android 15 caps `dataSync`
  services at six hours per day, which would end a long session.
- An exact-alarm watchdog and `BOOT_COMPLETED` resurrect the service unless the
  user pressed Stop. **Force stop** is unrecoverable without reopening the app.
- Grant the battery-optimisation exemption, and allow auto-start in vendor settings
  on Xiaomi/Samsung/Oppo/vivo. The Diagnostics screen logs every restart.

## Security

- Loopback binding only (`127.0.0.1`), never `allowLan`.
- 64-hex token, constant-time compare, generated once and stored in
  `EncryptedSharedPreferences`; `allowBackup=false`.
- `/api/pair` validates the Host and rejects browser Origins; the API never emits
  CORS headers and never serves files.
- Provider keys transit a job in memory only and are never logged or persisted.

## Verification

`app/src/test` runs on the JVM with a real CIO server and a `MockWebServer`
upstream: header filtering, URL safety, fingerprint idempotency, instance skew,
capacity 503, cancellation, tombstones and the pair/auth/hello contract. The
manifest and service behaviour need a device or emulator.

Before trusting the companion on a given executor, run the Phase 0 measurement in
`docs/MOBILE_COMPANION.md` Section 9.4: confirm loopback reachability and find the
exact wall. Executors that do not cut long calls do not need this app.
