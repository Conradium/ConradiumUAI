# UAI Bridge desktop launcher

A Windows 10/11 x64 app that starts Cowork, opens the browser and connects the
updated Roblox script automatically. The desktop project is separate from the
existing bridge and uses its server in `--desktop` mode on **127.0.0.1:28791**.
Manual terminal startup keeps port 8790 and its existing token workflow.

Extract `release/UAI-Bridge-1.0.0-win-x64.zip`, open **UAI Bridge.exe**, and click
**Start Cowork**. The package includes Node, .NET, browser assets and the matching
client in `client/uai.lua`. It needs neither an executor-workspace path nor an
installed runtime. Roblox and the UAI script must remain running.

The window reports bridge startup separately from Roblox connection. Closing a
running window hides it in the tray; **Exit** stops the owned bridge and exits.
Repeated launches restore the existing window. Occupied ports produce an error;
the app never chooses an undiscoverable random port or kills another application.

## Automatic connection

`bridge.autoDiscover` defaults to true. The client probes the dedicated port every
four seconds, with a two-second request deadline. An enabled manual bridge takes
priority. Turn off **Manual bridge enabled** in Cowork to use the desktop app.
Disable **Find desktop app automatically** to opt out. `bridge.stop()` suspends
discovery until `bridge.sync()` or a connection-setting change. Unloading releases
the discovery worker and ignores pending results.

Desktop credentials live only in memory and rotate at each app start. The app
and native executor discover through a desktop-only POST endpoint requiring the
exact loopback Host, a custom header and JSON. Browser Origin and Fetch Metadata
headers are rejected, with no CORS support. Native programs on this computer are
inside this trust boundary; this is not authentication against local malware.
All ordinary bridge routes still require the bearer token.

Discovery returns a fixed product marker, schema, port, instance and token. The
client validates these before attaching and uses one shared effective connection
for commands, web inference and pictures. Credentials never replace saved manual
settings. A changed connection terminates an outstanding relay request rather
than resending it to a new process.

## Build and verification

Install the .NET 10 SDK for Windows; Node is downloaded from nodejs.org at a pinned
version and checked against its pinned SHA-256. No NuGet library dependencies.
The launcher icon is generated from `bridge/web/favicon.ico` (a PNG asset) by
`desktop/make-icon.ps1` during the build, because the compiler only embeds
Win32-format `.ico` files. Manually audit all changed source, documentation and
tests first, then build:

```powershell
luajit tools/bundle.lua --native
powershell -ExecutionPolicy Bypass -File desktop/build.ps1
# Optional local SDK: -Dotnet C:/path/to/dotnet.exe
```

Inspect generated client and desktop outputs, then verify:

```powershell
node bridge/tests/run.js
luajit test/desktop_bridge.lua
luajit test/web_runtime.lua
luajit test/bridge_install.lua
luajit test/check.lua --native
luajit test/run.lua --native
luajit tools/bundle.lua --native --check
powershell -ExecutionPolicy Bypass -File desktop/verify.ps1
```

The desktop verification checks every packaged file hash and exercises the actual
bundled runtime: repeated startup, discovery, simulated game status, graceful stop
and restart with a new token. It also renders a native WinForms window preview in
`.build/verification/launcher.png`; inspect it. These checks do not claim a live
executor/Roblox connection. The source compiles with the official Luau compiler.

Build outputs, dependency caches and intermediate files are ignored by Git.
Publish the ZIP and adjacent SHA-256 file as release assets. This local build is
unsigned; signing and public release publication are separate distribution steps.
