# v3.0.0 core tool audit

Manual review covers the following modules in full. The companion/bridge and
standalone UI library are outside the release scope. The `ui_library_docs` tool
definition and its embedded reference were preserved. Existing guarded runtime
implementations were kept when review found no justified domain change.

Shared validation, dispatch and result improvements apply across the registered
tool catalogue; a retained tool does not imply a new cache or faster native call.
Performance evidence is bounded work and synthetic invocation counts, not an
executor or Roblox latency benchmark.

| Module | Review and disposition |
| --- | --- |
| `tools/helpers` | Finite limits, byte-budgeted row pages, UTF-8 progress for short reads, optional child counting, observed property batches and owned bounded signal watches. |
| `tools/native_helpers` | Group-scoped immutable results, retention limits and expiry, result-budget text pages, bounded child projections, invalid path/offset rejection, HTTP reader and unload cleanup. |
| `tools/net` | Exact JSON selectors and false values, HTTP status failure, deadlines/cancellation, one write attempt, contiguous body pages with retained continuations. |
| `tools/players` | Exact username priority, ambiguous display names rejected, filtered pages, captured distances and observed teleport writes. |
| `tools/character` | Movement fields/ranges, dependent health write order, preflight and readback, elapsed-time walking with truthful timeout/respawn outcomes. |
| `tools/world` | Stable ray identity, capped spatial/fallback scans, cooperative distance capture, selected lighting reads, observed lighting/camera changes. |
| `tools/gui` | Child-only tree reads, bounded text traversal and effective ancestor visibility, bounded button calls, owned prompt/touch holds, failure cleanup and honest notification/clipboard results. |
| `tools/perf` | Owned cancellable sample, valid frame deltas, class pagination/completeness and conversation-scoped tool counts. |
| `tools/screen` | Viewport bounds, requested ray distance/water handling, stable hit identity, explicit no-hit outcome; obsolete screenshot helpers removed. |
| `tools/instance` | Budget-limited cooperative tree, resumable search, exact identities and paginated tags; unused eager source reader removed. |
| `tools/instance_bulk` | Lighter optional display-only values, unreadable-filter disclosure and duplicate-target projection reuse within a batch. |
| `tools/instance_native` | Exact prepared targets, guarded runtime mutation, selectable metadata, field deduplication and explicit source deferral. |
| `tools/explorer` | Useful page sizes, bounded multi-field pages, immutable cursor selectors, explicit schemas and field-page cleanup. Existing selection/export/Undo guards retained. |
| `tools/remotes` | Native adapter contracts reviewed; temporary remote/signal observation now shares owned listener cleanup and nil-position preservation. Native capture/replay reviewed in the runtime ledger. |
| `tools/scan` | Retained compatibility entry point to the shared cooperative instance scanner. |

## Tool dispositions

| Tool | Result of review |
| --- | --- |
| `http_get` | Fail HTTP errors; deadline/cancellation; contiguous retained response pages. |
| `http_request` | One attempt; accurate status and resumable large responses. |
| `json_api` | Exact key arrays, false-valued fields, missing-path failure and retained structured data. |
| `http_result_read` | New group-scoped reader; no second network request. |
| `players_list` | Filter/page results and capture each distance once before sorting. |
| `player_info` | Exact username priority and unambiguous display-name fallback. |
| `teleport_to_player` | Resolve unambiguous identity and report observed movement effects. |
| `character_state` | Include jump-height mode and hip height. |
| `character_set` | Validate ranges, apply maximum health before health and report partial/readback outcomes. |
| `character_walk` | Use elapsed time; report timeout, cancellation and respawn as failure. |
| `character_teleport` | Preflight and observe the resulting property write. |
| `raycast` | Include stable instance identity for follow-up operations. |
| `parts_near` | Bound engine results, cooperate during projection, page sorted captured distances and disclose incomplete scans. |
| `lighting_get` | Select fields, deduplicate reads and bound optional effect summaries. |
| `lighting_set` | Report readback rather than assume requested values persisted. |
| `camera_get` | Report exact camera identity and fail when no camera is available. |
| `camera_set` | Validate all supplied values before mutation and report observed partial effects. |
| `gui_tree` | Page direct interface children without allocating all descendants; disclose unreadable roots. |
| `gui_text` | Traverse cooperatively, include a selected text root, inspect ancestor visibility and expose continuation/coverage. |
| `gui_click` | Bound handler dispatch, check cancellation/rejections and disclose partial failure. |
| `click_detector_fire` | Own prompt/touch cleanup before begin dispatch, release after uncertainty/cancellation and preserve exact hold duration. |
| `highlight` | Validate color before allocation; destroy failed setup and register cleanup. |
| `notify` | Fail when a toast cannot be mounted. |
| `clipboard_set` | Treat explicit host rejection as failure; report bytes accurately. |
| `performance` | Ignore invalid frame deltas, report frame-time range and release the listener on every exit. |
| `class_counts` | Page classes and disclose incomplete counts. |
| `client_status` | Distinguish tools offered to this conversation from all registered/missing-capability tools. |
| `ray_target` | Validate usable viewport, bound ray range and return stable identity/no-hit data. |
| `instance_tree` | Stop formatting when the result budget fills, yield periodically and disclose omissions. |
| `instance_find` | Resume at traversal offsets; preserve scan-limit/cancellation evidence. |
| `instance_get` | Read selected fields; skip source bytes and optional metadata entirely. |
| `instance_query` | Optional lightweight values; mark unreadable filters incomplete. |
| `instance_get_many` | Reuse projections for repeated exact objects within one request; preserve per-path outcomes. |
| `instance_set` | Retain prepared exact identity and expected-value guards; improve typed-value schema guidance. |
| `instance_create` | Retain detached setup, validated properties and failure cleanup; correct sorted-property-order description. |
| `instance_clone` | Retain prepared exact source/parent and guarded hierarchy operation; shared schema/result improvements apply. |
| `instance_destroy` | Retain exact prepared identity and irreversible-action policy; shared validation applies. |
| `instance_parent` | Retain prepared source/destination and guarded detach/reparent; clearer identity schema. |
| `instance_attribute` | Retain read/typed write/remove and expected-value guards; clearer schema. |
| `instance_tagged` | Page tag/instance listings and fail unreadable enumeration. |
| `instance_result_read` | Shared UTF-8 pages use available result budget, with explicit invalid selectors and unload cleanup. |
| `explorer_state` | Retain source-free shared selection/capability receipt; shared receipt improvements apply. |
| `explorer_children` | Honor 1–100 requested children instead of a hidden five-item cap. |
| `explorer_search` | Honor requested page size, preserving bounded traversal/snapshot selectors. |
| `explorer_select` | Retain revision-guarded explicit selection; declare modes/revision range. |
| `explorer_properties` | Return multiple fitting field rows and preserve immutable snapshot cursors. |
| `instance_edit_many` | Describe ordered typed operations in the public schema; preserve runtime preflight/recovery. |
| `explorer_export` | Declare actual format/field/depth bounds; retain verified export behavior. |
| `code_open_source` | Retain exact immutable source opening and guarded modified documents; shared result handling applies. |
| `code_extract_source` | Retain exclusive source identity and explicit editable extraction; bound positive offsets. |
| `changes_list` | Retain bounded session history summaries and offsets; shared receipt handling applies. |
| `changes_read` | Retain bounded recorded-value pages and expiry semantics; shared detail reader improvements apply. |
| `changes_undo` | Retain full preflight and conditional recovery without overwriting conflicts. |
| `remotes_list` | Native listing now advertises useful page limits and snapshot continuation. |
| `remote_fire` | Retain prepared exact target and at-most-once typed dispatch; narrower transport construction reviewed in runtime audit. |
| `remote_invoke` | Retain outstanding native-call ownership and typed outcomes; shared transport/result changes apply. |
| `remote_watch` | Own/disconnect listeners, preserve nil argument positions and bound formatting. |
| `signal_watch` | Same temporary observer lifecycle for ordinary instance signals. |
| `remote_result_read` | Shared retained-detail improvements; originating group enforced. |

`ui_library_docs` is explicitly excluded from direct change. Scripting/Code/file/
web/skill tools are covered by [the scripting ledger](AUDIT_3.0.0_SCRIPTING.md).
Agent/input/metadata tools are covered by [the agent ledger](AUDIT_3.0.0_AGENT.md).
Gravity, IY, chat and remote capture/replay tools are covered by
[the runtime ledger](AUDIT_3.0.0_RUNTIME.md).

## Verification boundary

All root-owned source changes and `test/release_tools.lua` were manually read
before building. The release requires generated-output inspection before focused
verification. See [the test record](TESTING_3.0.0.md) for commands/results.
The full native behavioral suite is deliberately excluded by user instruction.
Mock observations do not certify Roblox rendering, live native input or server
acceptance of local mutations.
