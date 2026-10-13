# Project UAI 3.0.0 verification

Release date: October 13, 2026. This record covers the client efficiency and tool
reliability changes. Only necessary focused checks were run; the entire
native suite is excluded. Offline work counters establish avoided operations,
not quantitative native Roblox/executor performance benchmarks.

## Review and build gate

Status: completed for the offline scope. Changed inputs were manually reviewed
before building, generated outputs were inspected, and the focused checks below
passed. Native follow-up remains separate from this offline evidence.

1. Manually review changed source, documentation, examples, tests and build inputs.
2. Run `luajit tools/bundle.lua --native` after that review. Inspect generated
   source, embedded scripting reference, module ranges, version and manifest.
   Then run `node tools/build_site.js` and inspect the generated version metadata,
   tool catalog and documentation mirror.
3. Run the selected focused checks below only after output inspection. Use the
   official Luau compiler on changed client inputs and the native bundle where
   available, plus `luajit test/check.lua --native` and deterministic freshness.
4. For a failure, review its fix first, rebuild and inspect affected outputs,
   then rerun the affected check. Broaden testing only for an unresolved concern.

UI LIB, bridge, desktop and companion work are outside this release pass.
The native and site builders own their generated outputs; do not edit generated
bundles, manifests, embedded guide modules or website regions directly.

## Core focused checks

Each file is a focused synthetic contract suite. These commands do not invoke
the all-suite runner or native device interaction.

| Changed behavior | Command | Outcome |
| --- | --- | --- |
| Agent schema/result repair, streaming and accounting | `luajit test/release_agent.lua` | Pass: 12 cases, 51 assertions |
| Source reuse, filename discovery, focused project tests and web snapshots | `luajit test/release_scripting.lua` | Pass: 12 cases, 44 assertions |
| Debounce, UTF-8 processing, capture queue, skills and integration tools | `luajit test/release_runtime.lua` | Pass: 108 checks |
| HTTP continuations, observed writes, identities, GUI/Explorer pages and frame sampling | `luajit test/release_tools.lua` | Pass: 15 cases, 54 assertions |
| Held-input ownership, fallback and release behavior | `luajit test/release_input.lua` | Pass: 14 cases, 38 assertions |
| Confirmation, queued questions, icon extraction and animation lifetimes | `luajit test/release_ui.lua` | Pass: 22 checks |
| Provider test and model discovery cancellation | `luajit test/release_provider_ui.lua` | Pass: 4 cases, 12 assertions |
| Native module syntax/link/static rules | `luajit test/check.lua --native` | Pass: 202 files, 0 failures, 0 warnings |
| Official Luau syntax on changed client inputs and bundle | `refer/native-tools/luau/luau-compile.exe --null <selected files>` | Pass: 66 changed inputs; final GUI/bundle rechecked after the fix |
| Native artifact freshness | `luajit tools/bundle.lua --native --check` | Pass: final bundle, manifest and icons current |
| Published catalog/version/documentation freshness | `node tools/build_site.js --check` | Pass: 174 tools, 21 groups |
| Generated public website integrity | `python test/site_static.py` | Pass: 8,345 static checks |

## Existing regression coverage to select

The coordinator records which additional focused files are needed after review.
This is a coverage map, not an instruction to execute every row.

| Changed contract | Applicable existing focused coverage |
| --- | --- |
| Source/project analysis, patch guards and focused execution | `test/script_projects.lua`, `test/execution_tools.lua` |
| Filesystem traversal, literal edits, byte pages and scope checks | `test/tool_workflows.lua` |
| Source/history/actions and bytecode/decompiler behavior | `test/code_workspace.lua`, `test/decompilation.lua` |
| Tool scopes, structured receipts and cancellation | `test/agent_efficiency.lua`, `test/structured_results.lua`, `test/tool_cancellation.lua` |
| Provider stream/final result compatibility | `test/provider_compatibility.lua` |
| Capture identities, record lifetimes, typed edits and replay | `test/native_workspace.lua` |
| Gravity and IY source/command/plugin contracts | `test/gravity.lua`, `test/iy_control.lua` |
| Chat cursors and background job ownership | `test/chat_loops.lua`, `test/chat_bot.lua` |

Do not run `node tools/test_native.js --verify-only` or an unrestricted
`luajit test/run.lua --native` for this release. If an existing file needs a
scenario filter, record the exact selector with its outcome.

## Recorded artifact and outcomes

Original release build: **3.0.0-43f82d8ab5b100e0**, 206 bundled modules, **3,337,357 bytes**.
Bundle SHA-256:
`6b9bd51e7d63d4ec4ae8d7bc994daa54778ec31bcf771e180f46b61097bb6f36`.
The generated manifest uses its existing `uai-dual32-v1` source identity; the
SHA-256 above independently identifies the distributed bundle bytes.

Twenty selected Lua files passed **2,302 assertions/checks**, in addition to the
static/compiler/freshness checks. No full native suite was run. Selected existing
regressions, beyond the seven release-specific files above:

| Command | Result |
| --- | --- |
| `luajit test/script_projects.lua` | 17 cases, 58 assertions |
| `luajit test/execution_tools.lua` | 238 checks |
| `luajit test/tool_workflows.lua` | 384 checks |
| `luajit test/native_workspace.lua` | 13 cases, 76 assertions |
| `luajit test/gravity.lua` | 116 checks |
| `luajit test/iy_control.lua` | 176 checks |
| `luajit test/structured_results.lua` | 6 cases, 63 assertions |
| `luajit test/provider_compatibility.lua` | 40 cases, 637 assertions |
| `luajit test/agent_efficiency.lua` | 9 cases, 32 assertions |
| `luajit test/tool_cancellation.lua` | 4 cases, 19 assertions |
| `luajit test/tools_runtime_audit.lua` | 7 cases, 67 assertions |
| `luajit test/code_workspace.lua` | 14 cases, 79 assertions |
| `luajit test/scripting_docs.lua` | 28 checks |

These cover changed execution/patch/source contracts, tool receipts and scopes,
provider assembly, capture retention, integration tool behavior, and the generated
scripting guide. Passing files were not repeated without an affected change.
The two adjusted structured-input assertions in the monolithic `test/run.lua`
were manually reviewed; that whole file was deliberately not executed.

The first focused pass found a production capability bug: `click_detector_fire`
required executor hooks even for native ProximityPrompt interaction. Removing
that gate was manually reviewed, the client/site were rebuilt, and the generated
GUI tool/catalogue entry was inspected before its successful retest. The final
official compiler pass included the changed GUI module and rebuilt bundle.

Three first-run failures were fixture defects: unregistered conversation-search
sessions, a missing signal-method receiver, and a mock-click delay allowing a
provider response to finish before cancellation. Each fixture correction was
manually reviewed before its focused retest. Final failures: **zero**. Initial
failure logs and successful per-file logs remain locally under
`refer/release-3.0.0/` (ignored by Git).

Manual source review records:

- [Agent/provider/embedding](AUDIT_3.0.0_AGENT.md)
- [Runtime/integration/shared UI](AUDIT_3.0.0_RUNTIME.md)
- [Scripting/Code/application integration](AUDIT_3.0.0_SCRIPTING.md)
- [Core tools](AUDIT_3.0.0_TOOLS.md)

[Consolidated coverage](AUDIT_3.0.0.md): **198 of 206** source modules reviewed;
the eight named bridge/relay/library modules are excluded. All **174** exported
tool names are accounted for across the ledgers; `ui_library_docs` is protected
from direct change. Protected source/guide/bundle files remain unchanged.

## API key rotation follow-up

The original release used the same API key until a quota refusal. This fix
advances through ready keys on each new request, shares the cursor with request
snapshots, and retains the selected credential during proxy/transport retries.
Quota recovery selects the next key once. Independent editor drafts stay isolated.

Changed source, documentation and regression tests were manually reviewed before
verification; reviewed client inputs were rebuilt and the generated bundle and
manifest inspected before tests. Only the seven intended client module hashes
changed. The original twenty-file release pass above was not repeated.

Follow-up build: **3.0.0-dddf35b93158e58b**, 206 modules, **3,337,782 bytes**.
Bundle SHA-256:
`a845bdcbe1252c536d609a0d244f8527698c58c29bed3b62a90ab67e5ef52c66`.

| Command | Result |
| --- | --- |
| `luajit test/provider_key_rotation.lua` | 8 cases, 42 assertions, 0 failures |
| `luajit test/provider_key_snapshots.lua` | 6 cases, 19 assertions, 0 failures |
| `luajit test/provider_compatibility.lua` | 40 cases, 637 assertions, 0 failures |
| `luajit test/provider_proxy.lua` | 16 cases, 127 assertions, 0 failures |
| `luajit test/release_provider_ui.lua` | 4 cases, 12 assertions, 0 failures |
| `luajit test/chat_bot.lua` | 89 checks, 0 failed scenarios |
| Official Luau compiler: seven changed source files and `dist/uai.lua` | Pass |
| `luajit test/check.lua --native` | 202 files, 0 failures, 0 warnings |
| `luajit tools/bundle.lua --native --check` | Bundle, manifest and icons current |
| `node tools/build_site.js --check` | Current; no website changes needed |

The six selected Lua files passed **926 assertions/checks**. The added snapshot
cases cover shared discovery/cooldown state, cache hits, default Anthropic auth,
overlapping requests, independent editor drafts and discovery proxy recovery.

The adjusted quota-rotation expectation in `test/run.lua` was manually reviewed;
that monolithic file and the entire native suite were not run. Tests observe
synthetic outgoing credentials without real provider requests. Logs are under
`refer/key-rotation-3.0.0/` (ignored by Git).

## Native follow-up

Not run by the offline suites:

1. Reload an idle client and inspect 3.0.0 in About and What's New. Confirm saved
   conversations, settings, Code drafts and the release-note read marker persist.
2. In a small saved project, analyze unchanged source twice, edit one module,
   run one selected test case and inspect compiled/reused/skipped counts. Check
   an explicit no-match failure and that executed cases receive fresh fixtures.
3. Inspect a multi-page script, Explorer result and HTTP/web response. Follow
   returned cursors without gaps; expired references must require a fresh read.
4. Exercise held-input release, cancellation, camera/property readback and GUI
   ancestry in a controlled place. Mock outcomes do not prove engine delivery,
   server acceptance or native visibility.
5. Capture enough calls to evict older records, inspect a pinned call and stop
   capture. Confirm the retained count/gaps and actual native forwarding coverage.

Any native measurement must name the executor/device, fixture, provider/model
where relevant, workload and observed result. No native speedup figure is
claimed by this release verification record.
