# Project UAI 2.8.0 verification

Release date: October 12, 2026. This checklist covers the changed execution,
agent, provider, runtime and interface behavior. Use focused checks only; the
full native suite is not part of this release pass. Offline fixtures cannot
establish native Roblox rendering, executor input delivery or live model quality.

## Review and build

Status: pending final source review, build and output inspection.

Manually review every changed source, guide, example, test and build input first.
Build `luajit tools/bundle.lua --native`, then `node tools/build_site.js`. Inspect
the generated bundle, source ranges, manifest and root/docs publishing changes
before running verification. Review each fix before rebuilding and rerunning
only the checks affected by it.

UI LIB source and guide are unchanged by the release version update. If either
changes during implementation, review those inputs first, run
`node tools/build_ui_lib.js`, inspect its outputs, then run
`luajit test/ui_library.lua` and `node tools/build_ui_lib.js --check`.

## Focused checks

Status: recorded below October 12, 2026; the UI regression row is still pending selection. Record the exact
selected commands and outcomes below after the final inputs have been reviewed.

| Changed behavior | Planned check |
| --- | --- |
| Execution failures, compiler/source validation, managed scheduling and templates | `luajit test/execution_tools.lua` |
| Real Luau syntax and a simple saved-path Part script | `lune run test/lune_runner.luau test/native_script_syntax.luau` |
| Project discovery failures and bounded test reporting | `luajit test/script_projects.lua` |
| Stale Code proposals, action inputs and run rejection | `luajit test/code_workspace.lua` |
| Prompt scope, read subagents, permissions and truncated arguments | `luajit test/agent_audit.lua` |
| Existing prompt/context contracts | `luajit test/prompt_context.lua` |
| OpenCode compatibility guidance, unknown tools and truncated-batch recovery | `luajit test/scripting_harness.lua` |
| Input outcomes, remote/numeric parsing, runtime probes and bounded scans | `luajit test/tools_runtime_audit.lua` |
| Supported Messages sampling | `luajit test/provider_sampling.lua` |
| HTTP diagnostic and error classification behavior | `luajit test/http_diagnostics.lua` |
| Changed interface behavior | Select the focused UI regression checks after the final UI review |
| Website catalog structure and examples | `python test/site_static.py` |

Run `luajit test/check.lua --native` for native static checks, and use the
official Luau compiler with `--null` on changed Lua inputs and the generated
bundle when available. Finish with `luajit tools/bundle.lua --native --check` and
`node tools/build_site.js --check`. Do not substitute the all-suite verification
runner for these focused checks.

## Recorded results

Verified October 12, 2026 against build `2.8.0-3fbaead153a192e3`
([`dist/uai.lua`](../dist/uai.lua), 3,244,341 bytes.
SHA-256: `99367d569d126de099fdf3b9d5e1a4bc7c992813ea983ef56f5e87de696216ed`).
Focused checks only; the full native suite was not run.

| Check | Outcome |
| --- | --- |
| `luajit test/execution_tools.lua` | 238 checks passed, 0 failed |
| `lune run test/lune_runner.luau test/native_script_syntax.luau` | 3 cases, 6 assertions, 0 failures |
| `luajit test/script_projects.lua` | 17 cases, 58 assertions, 0 failures |
| `luajit test/code_workspace.lua` | 14 cases, 79 assertions, 0 failures |
| `luajit test/agent_audit.lua` | 6 cases, 25 assertions, 0 failures |
| `luajit test/prompt_context.lua` | 5 cases, 120 assertions, 0 failures |
| `luajit test/scripting_harness.lua` | 4 cases, 15 assertions, 0 failures |
| `luajit test/tools_runtime_audit.lua` | 7 cases, 66 assertions, 0 failures |
| `luajit test/provider_sampling.lua` | 3 cases, 36 assertions, 0 failures |
| `luajit test/http_diagnostics.lua` | 2 cases, 7 assertions, 0 failures |
| `python test/site_static.py` | 8309 static checks passed |
| `luajit test/check.lua --native` | 201 parsed, 0 failures, 0 warnings |
| Official Luau compiler `--null` on 48 changed inputs + bundle | clean (84 KLOC) |
| `luajit tools/bundle.lua --native --check` | current |
| `node tools/build_site.js --check` | v2.8.0, 172 tools, synchronized |
| Changed interface behavior (UI regression set) | not run; selection requires the final UI review |

## Native follow-up scenarios

1. Reload the release while idle and confirm **2.8.0** in About and What's New.
   Check that revised notes show once and keep their read marker after reopening.
2. Create a small script by the current game path, compile it and run that same
   path. Exercise printing, multiple returns, a plain runtime error and a managed
   child error. Confirm the result identifies the failure and retains available
   output without claiming native work was rolled back.
3. Use an existing OpenCode configuration to verify its compatibility workaround
   still receives the extra tools introduction, declarations and required stream
   setting. Compare the same simple scripting request before and after the
   update on the same provider/model; record actual outcomes rather than assuming
   prompt changes prove model quality.
4. Dispatch a read subagent and verify it can inspect its allowed scope but cannot
   write memory, rename conversations or mutate game/files through mixed groups.
   `agent_status` must still report delegated work; `client_status` reports the
   runtime and provider diagnostics.
5. Exercise input and typed remote arguments only in an isolated fixture place.
   Check adapter failure reporting, literal `string:` values, vectors with decimal
   or exponent components, and incomplete scans. Confirm failure text does not
   claim delivery or absence that the host did not establish.

UI LIB 1.3.0, embedding SDK 1.0.0, Windows bridge 1.0.0 and Android companion
1.0.0 retain their independent versions.
