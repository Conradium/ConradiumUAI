# Project UAI 3.1.0 verification

Release: October 14, 2026 — Bridge improvements.

## Scope and review order

This pass covers Cowork browser UI and every dialog, automatic runtime selection,
mobile polling and discovery, unlimited Cowork inference and OpenCode compatibility,
permanently enabled client animations, deadline help, automatic updates, the
single-executable Windows app with detected/on-demand Node.js, and release
artifacts. The entire native suite is excluded by request. UI LIB and the
embedding SDK keep their versions.

Review source, documentation, examples, tests and build inputs manually before
building. Inspect the generated bundle and manifest before focused verification.
Review every fix before rebuilding and retesting its affected behavior.

## Requirements and evidence

| Requirement | Focused evidence | Outcome |
| --- | --- | --- |
| Web on authenticated connection; Game on disconnect | Bridge lifecycle, desktop discovery and transport tests | Pass |
| No overall bridged request time limit or editable timeout | Virtual long-wait/poll-stall/Stop regressions, upstream fake-clock tests, configuration migration | Pass |
| Quiet mobile probes with bounded waits and stale-result protection | Mobile relay and bridge lifecycle regressions | Pass |
| Every dialog usable on desktop and short mobile screens | Browser workflow, revamp and UI audit suites, screenshots | Pending (needs Playwright Chromium run) |
| Smaller sidebar text in the Roblox mobile script | Dedicated native sidebar roles, font-scale/rotation/control checks | Pass |
| Complete bridge visual rework without UAI logo imagery | All workspace views and dialog screenshots; browser workflow regressions | Pending (needs Playwright Chromium run) |
| Client animations enabled across saved/imported configuration and platform changes | `test/bridge_release_ui.lua`, `test/config_transfer.lua`, `test/modal_motion.lua` | Pass |
| Four OpenCode commits preserved across Game and Web | Provider compatibility and relay/Responses regressions | Pass |
| Highlighted Discord tutorial link for deadline errors | Native and browser conditional error presentation | Pending (browser presentation needs Chromium run; native covered) |
| Automatic verified bridge release updates | Staging, integrity, idle activation, reconnect, rollback and launcher tests | Pass |
| One independent Windows executable with embedded files and separate Node.js setup | Embedded payload hashes, isolated EXE startup, runtime discovery and synthetic update tests | Pass |
| Automatic desktop executable updates on restart | Official asset selection, checksums, private cache, readiness and rollback | Pass |
| Bridge streaming, images, commands, cancellation and launcher behavior | Focused Node bridge suites | Pass |
| 3.1.0 metadata and generated artifacts | Native build, static check, official Luau compiler, bundle/site freshness | Pass |

## OpenCode review

The input baseline is commit `54c35afbeb65d2af5b1899573bdf105d4a551287`.
The review includes that connection-test/session-migration change,
`44098875f63d061e1e0d102547749b1b721b0d86` (cat-jam-free and tool ceiling),
`acd3f4be9d4127f2f747555131b5a4e292a7e790` (session generator and Responses),
and `38507805fc23932aa397b59e170223e96c6456ac` (protocol fallback).

Preserve session identity, selected credentials, protocol-specific streaming,
tool selection and direct/companion provider deadlines. Cowork waits without an
overall duration limit. Synthetic success does not establish
current upstream free-tier availability.

## Recorded results

Native inputs were manually reviewed, built and inspected before these focused
checks. Bridge updater inputs and tests were manually reviewed before the
synthetic release tests. Desktop verification and release packaging are complete;
browser Chromium suites remain the only pending pass.

The inspected native artifact is `3.1.0-62eae33abdeb7650`: 207 modules and
3,360,802 bytes. UI LIB remains 1.3.0 with current generated bundle, manifest and
embedded guide. The bridge release package is 19 files and 469,337 bytes
(`e9c73214…2320e1b8`). The desktop release is one 53,067,396-byte executable
(`c09b0866…883551e81d5b`) with 24 embedded bridge/client/license files and no
bundled Node.js.

| Command | Outcome |
| --- | --- |
| `luajit test/bridge_lifecycle.lua` | 54 checks passed, including a virtual 34.5-second poll stall and 320-second inference wait |
| `luajit test/desktop_bridge.lua` | 40 checks passed |
| `luajit test/mobile_relay.lua` | 28 checks passed |
| `luajit test/web_runtime.lua` | 22 checks passed |
| `luajit test/panel_layout_regressions.lua` | 63 checks passed |
| `luajit test/provider_compatibility.lua` | 54 cases, 871 assertions passed, including virtual 301-second Chat, Responses, Messages and protocol recovery |
| `luajit test/provider_transport.lua` | 21 cases, 554 assertions passed |
| `luajit test/bridge_release_ui.lua` | 45 checks passed |
| `luajit test/config_transfer.lua` | 103 checks passed |
| `luajit test/modal_motion.lua` | 31 checks passed |
| `luajit test/chat_regressions.lua` | 330 checks passed; folded traces retain plain text and format emphasis when expanded |
| `luajit test/bridge_install.lua` | 70 checks passed |
| `luajit test/mobile_ui.lua` | 192 checks passed |
| `luajit test/run.lua --native 'mascot stays animated'` | One selected scenario, 12 checks passed |
| `luajit test/check.lua --native` | 203 files, zero failures or warnings |
| Official `luau-compile --null` on changed client sources and bundle | Passed |
| `luajit tools/bundle.lua --native --check` | Passed |
| `node tools/build_site.js --check` | 3.1.0, 174 tools, 21 groups; root/docs match |
| `python test/site_static.py` | 8,345 checks passed |
| `luajit test/ui_library.lua` and `node tools/build_ui_lib.js --check` | 158 checks passed; generated UI LIB artifacts current |
| `node --test bridge/tests/updater.test.js` and the corrected inference-fixture rerun | 16 scenarios passed: official assets, integrity/path bounds, cache repair, idle gates, rollback, token retention, launcher cache and parent ownership |
| `node --test bridge/tests/runtime.test.js bridge/tests/security.test.js bridge/tests/desktop.test.js bridge/tests/launcher.test.js` | 25 cases passed |
| `node bridge/tests/run.js` (all non-browser Node suites) | 88 tests passed: desktop, launcher, opencode, picture-store, pictures, runtime, security, streaming, updater, vision |
| `powershell -ExecutionPolicy Bypass -File desktop/verify.ps1` | Self-test 28 checks, smoke-test 5 checks, native preview rendered; standalone EXE verified with no neighboring runtime or bridge folders |
| Desktop payload separator fix | `ZipFile.CreateFromDirectory` stored backslash entry names that never matched the forward-slash inventory; `build.ps1` now writes canonical forward-slash entries and `EmbeddedPayload` normalizes either spelling |

Only the selected mascot scenario was run from the main harness. Neither the
entire native suite nor the all-suite native runner was invoked.

## Verification limits

Chromium checks exercise a real browser with a local bridge and synthetic game
state. LuaJIT checks use the offline Roblox harness. These do not establish native
Roblox rendering, executor networking, touch/IME behavior, Safari/Firefox support
or live provider availability. A live executor check should connect, send, stop,
disconnect/reconnect and exercise the mobile keyboard with the updated bundle.
