# v3.0.0 scripting and Code workspace audit

This records the source review of the scripting, filesystem, authoring and web
tool families, their runtime modules, all 21 `src/ui/code` modules, and five
application-shell/integration modules. The existing Code application remains
the presentation layer. No UI Library,
desktop, companion or bridge implementation was changed in this workstream.

Every module below was read, including retained implementations. “Retained”
means the existing mechanism was kept after review; it does not mean the file
received an artificial edit. Tool rows distinguish direct changes from shared
registry/result handling. The release-wide ledger records those shared changes
and other tool groups.

## Efficiency and correctness evidence

- Project outlines are keyed by exact source bytes, bounded to 128 entries and
  4 MiB of accounted source/outline storage, and copied on publication. Warm
  outlines avoid another lexer pass. Cancellation precedes reuse. Whitespace
  runs are consumed without allocating a token string per whitespace byte.
- Project syntax outcomes are keyed by exact path/source and compiler identity,
  bounded to 128 records and 2 MiB of source. Successful compiled closures are
  never retained. Saved bytes and dependency graphs are still checked. The
  focused fixture expects three cold compiles, zero additional warm compiles,
  and one additional compile after editing one module.
- Standalone syntax checks retain only successful exact-source checks, with
  16 records and 2 MiB of source. `check_luau` followed by `run_luau` skips the
  duplicate raw compile while compiling the managed execution wrapper fresh.
- `script_test` selects declared test modules and literal case-name filters.
  Each executed case receives fresh fixtures and a fresh module cache. Skipped
  cases are reported; zero matches cannot become a passing result. This avoids
  running unrelated test cases when focused verification is sufficient.
- `file_find` searches filename globs through bounded directory inventories and
  reads no file content. Results use canonical paths, sorted pagination and
  explicit incomplete coverage. Content search reports skipped binary/oversized
  files as incomplete coverage.
- Unique exact edits use their already-known byte offsets. Writes are read back
  so a host reporting success after writing partial bytes cannot produce a
  successful edit receipt. Project patch hashes are computed at staging, while
  full-byte guards remain authoritative at apply/restore.
- Code line reads locate the requested range without allocating all document
  lines. Equal-source diff calls return before line splitting. Source-document
  hash reuse checks the exact current source and uses weak document keys.
- Bytefall base64 encoding accumulates 1024-entry chunks instead of retaining
  one small output string for every input triple. Padding and cooperative
  cancellation are preserved.
- Web continuations read immutable text snapshots instead of issuing another
  HTTP request. Four snapshots and 4 MiB are retained for five minutes. The
  focused fake-HTTP fixture reconstructs UTF-8 pages with exactly one fetch.
- Native script discovery honors its advertised default 25/maximum 100 page
  sizes and adds name filtering. Template output sorts numeric player distance;
  template inputs reject unknown names and incorrect types. Skill discovery
  filters name, filename and description before paging.

These are bounded-work and invocation-counter claims, not native Roblox latency
measurements. Executor filesystem calls still return whole file/list values;
HTML extraction is best-effort text extraction, not browser rendering. Native
rendering and host input require a Roblox/executor check.

## Runtime module ledger

| Module | Reviewed mechanism and disposition |
| --- | --- |
| `runtime/bytefall` | Bytecode extraction, response validation, cancellation and base64 padding reviewed. Chunked encoding bounds the temporary string array. |
| `runtime/code_actions` | Saved source snapshots, revision guards, typed parameters and execution preparation reviewed; retained. Tool schemas now expose the supported input definition. |
| `runtime/code_diff` | Prefix/suffix reduction, bounded middle comparison and replacement fallback reviewed. Equal inputs now return before line allocation. |
| `runtime/code_files` | Canonical bindings, saved-base comparisons, conflicting disk changes, readback and document lifecycle reviewed; retained. |
| `runtime/code_lexer` | Lexical states, changed-line reuse, comment/string handling and token budgets reviewed; retained. Source-page reads no longer need its whole-source line splitter. |
| `runtime/code_limits` | Source/history/output limits and their shared callers reviewed; retained. Source-writing tool schemas now declare the 256000-byte limit. |
| `runtime/code_store` | Revision checks, proposals, histories, active/open documents, persistence and storage-failure reporting reviewed; retained. |
| `runtime/code_text` | UTF-8 boundaries, byte/column conversion and literal/pattern search reviewed. Added allocation-light line range location. |
| `runtime/decompile_result` | Native/service result classification, invalid output rejection and provenance reviewed; retained. |
| `runtime/fsx` | Scoped canonical paths, unsafe path rejection, executor listing variants, ambiguity and migration guards reviewed; retained. |
| `runtime/luacid` | Wrapper, embedded implementation, bytecode dispatch, protected service calls and output validation read; retained. Generated/embedded compiler source was not rewritten. |
| `runtime/project_patch` | Conversation ownership, expiration, exact-byte preconditions, verified partial writes and conditional restore reviewed. Precompute before/after hashes and cancel before staging reads. |
| `runtime/project_source` | Lexical outlines/imports, comments/strings, offsets and scanner bounds reviewed. Added bounded exact-source cache with deep-copy isolation and whole-whitespace-run consumption. |
| `runtime/script_project` | Manifest validation, saved-source loading, graph diagnostics, bundling and source-current checks reviewed. Added syntax-outcome reuse, compiler invalidation, cooperative analysis and explicit cancellation counters. |
| `runtime/script_sources` | Instance/document identities, provenance, immutable sources, extraction/decompilation cancellation and unload reviewed. Weak exact-source hash cache avoids repeated document hashing. |
| `runtime/workspace` | PlaceId-based selection, stable labels, saved mappings, legacy discovery bounds and ambiguous folder preservation reviewed; retained. |

## Tool module ledger

| Module | Reviewed mechanism and disposition |
| --- | --- |
| `tools/init` | Group loading, registry registration and native extension order reviewed; retained. |
| `tools/code_runner` | Approval-bound source snapshots, document/action revisions, task identity, stop/output ownership and disposal reviewed; retained. |
| `tools/coding` | Shared model access, revision-bound writes/runs, source identity, versions, proposals and action contracts reviewed. Added line-range reads, identity validation, source limits, action input schema and action pagination. |
| `tools/execution` | Managed wrapper compilation, deadlines, cancellation instrumentation, worker admission and returned values reviewed. Reuse successful raw-source syntax checks without retaining executable closures. |
| `tools/fs` | File list/read/edit/write/append/delete schemas, canonical routing, permission preparation and confirmations reviewed; retained. Uses improved shared workspace/result handling. |
| `tools/fs_bulk` | Bounded walk/search, repeated-file guards, snapshots and coordinated exact edits reviewed. Added filename-only discovery and explicit incomplete search coverage. |
| `tools/project` | Manifest map, staged patch lifecycle, saved-source analysis, testing, scaffolding and build preconditions reviewed. Pass cancellation to analysis, report compile reuse and expose focused test selection. |
| `tools/project_testing` | Fixture cloning, isolated module caches, assertion helpers, test discovery and bounded reports reviewed. Filter cases before execution and fail explicitly on no matches. |
| `tools/script` | Embedded guide routing, execution/check entry points and native extension handoff reviewed; retained. Uses updated embedded scripting guide and execution implementation. |
| `tools/script_native` | Instance/source identity, snapshot provenance and source pagination reviewed. Remove the hidden five-row cap and add script-name filtering. |
| `tools/skills` | Runtime skill store integration, reads, writes, installation, deletion and discovery bounds reviewed. Add filtered paginated inventory with totals. |
| `tools/source_documents` | Open/source/caller provenance, source-to-document reuse, request cancellation and focus ownership reviewed; retained. |
| `tools/templates` | Template expansion, dispatch identity, bounded parameters and operation deadlines reviewed. Sort player distances numerically, page detailed source, validate known typed parameters and forward timeouts. |
| `tools/web` | Search extraction, safe URL scheme selection, response bounds and cancellation reviewed. Add immutable paged text snapshots, broader HTML attribute parsing, structured results and script/style stripping. |
| `tools/workspace` | Exact edit matching, canonical preparation, full-byte conflict checks and file writes reviewed. Reconstruct unique matches by offsets and verify edited bytes after host writes. |

## Individual tool ledger

Every name in this workstream has an explicit disposition. Retained tool
contracts also receive shared recursive schema validation and bounded result
handling reviewed in the release-wide agent ledger; those changes do not imply
that every tool now caches or batches its domain operation.

| Tool | Disposition |
| --- | --- |
| `workspace_result_read` | Retained scoped detail reader; receives shared result-budget pagination improvements. |
| `code_tabs` | Retain lightweight document metadata pages without source retransmission. |
| `code_read` | Locate requested lines without a full split; reject conflicting source/version/proposal identities; reuse unchanged document hashes. |
| `code_write` | Retain conditional revision updates and checkpoints; declare the source byte limit in the schema. |
| `code_edit` | Retain inclusive line edits against an expected revision; declare the source byte limit. |
| `code_search` | Retain bounded literal-first search with offsets/revisions and explicit pattern opt-in. |
| `code_select` | Retain explicit user-workspace selection as a separate operation. |
| `code_run` | Retain approval-bound source revisions; shared execution avoids repeated raw syntax compilation when already checked. |
| `code_propose` | Retain non-mutating proposals tied to a base revision; declare source bounds. |
| `code_versions` | Retain source-free history/proposal metadata; larger receipts use retained detail. |
| `code_action_list` | Add offset/limit pages, default 12 and maximum 25 actions. |
| `code_action_save` | Expose supported typed input definitions and retain revision guards. |
| `code_action_read` | Declare definition/source sections explicitly; retain paged saved source. |
| `code_action_run` | Retain revision-bound snapshots and data-only typed input injection; shares syntax reuse. |
| `file_list` | Retain bounded canonical inventory without reading file bodies. |
| `file_read` | Retain resumable UTF-8 byte pages through the shared result budget helper. |
| `file_edit` | Avoid a redundant replacement scan for a unique literal match and verify host-written bytes. |
| `file_write` | Retain prepared target and guarded write behavior; shared schema/result validation applies. |
| `file_append` | Retain append semantics and scoped targets; shared schema/result validation applies. |
| `file_delete` | Retain prepared scoped identity and deletion result checks; no speculative deletion. |
| `file_find` | New bounded recursive filename glob inventory with canonical paths, pagination and zero content reads. |
| `file_search` | Preserve bounded literal content search; mark binary/large-file omissions incomplete. |
| `file_read_many` | Retain bounded snapshot reads and per-file outcomes to avoid repeated tool setup. |
| `file_edit_many` | Retain coordinated exact edits, prepared byte snapshots, conditional application and partial-result reporting. |
| `project_map` | Reuse exact-source outlines while re-reading saved bytes; return hashes/imports without full source. |
| `project_patch` | Compute staged hashes once; preserve conversation ownership, exact-source guards and reviewable proposals. |
| `project_patch_read` | Reuse staged hashes; equal-source diff avoids splitting; source and detail remain paged. |
| `project_patch_apply` | Reuse staged hashes for receipts while full-byte and unsaved-draft guards remain authoritative. |
| `project_patch_restore` | Reuse staged hashes and preserve conditional recovery with explicit partial outcomes. |
| `project_patch_discard` | Retain explicit release of bounded staged/recovery state without changing files. |
| `project_scaffold` | Retain a reviewable create-only multi-file starter proposal; shared staging improvements apply. |
| `script_analyze` | Reuse syntax outcomes and outlines, expose compiled/reused counts, and report cancellation/incomplete analysis. |
| `script_test` | Add declared-module and literal case filters; fresh executed-case state; no-match failure; reuse analysis. |
| `project_build` | Reuse project syntax checks, retain deterministic output and input overwrite guards, and reject cancelled analysis. |
| `scripting_docs` | Updated embedded guide routes narrow discovery, focused tests and reusable source/page references. |
| `run_luau` | Reuse a successful exact-source syntax check; always compile a fresh managed execution wrapper. |
| `check_luau` | Bounded successful-result reuse by exact source/compiler identity, exposing whether work was reused. |
| `script_list` | Honor default 25/maximum 100 results, add name filtering, preserve snapshot cursors and incomplete scan evidence. |
| `script_source` | Retain explicit immutable source identity/provenance and bounded byte pages. |
| `script_result_read` | Retained script-scoped detail reader receives shared result-budget pagination improvements. |
| `skills_list` | Filter name/file/description before paging; return page and match totals. |
| `skills_read` | Retain exact skill lookup and bounded source pages; benefits from runtime skill inventory reuse. |
| `skills_write` | Retain bounded local skill writes and runtime index invalidation. |
| `skills_install` | Retain explicit URL install and runtime skill validation/index invalidation. |
| `skills_delete` | Retain exact skill selection, deletion and index invalidation. |
| `template_list` | Page template details/source while preserving a compact discoverable inventory. |
| `template_run` | Validate known parameter names/types, sort nearest-player data numerically, and align nested execution deadlines. |
| `web_search` | Bound query/response work, support HTML attribute-order variations and return structured links/snippets. |
| `web_read` | Continue immutable UTF-8 text pages by `page_id` with no refetch; bound retention, response inspection and deadline. |

## Code presentation module ledger

Read-only review preserved the established application's design and its
separation from runtime state. This ledger covers presentation lifecycle,
allocation/virtualization, stale asynchronous results and interaction behavior;
it does not certify native Roblox rendering.

| Module | Reviewed mechanism and disposition |
| --- | --- |
| `ui/code/common` | Shared controls, virtual-list adapter, protected work callbacks, messages and menus; retained. |
| `ui/code/compare` | Paired source display, diff selection, responsive layout and owned teardown; retained. |
| `ui/code/diff_view` | Bounded comparison rows, reusable list rendering and selection behavior; retained. |
| `ui/code/editor` | Document subscription, guarded edits, selection restoration, debounced syntax and runner integration; retained. |
| `ui/code/explorer` | Query generations, tree/list pagination, selection identity, properties and pane teardown; retained. |
| `ui/code/files` | File binding, paged inventory, loaded-file filtering, open/create/delete dialogs and visibility lifecycle; retained. |
| `ui/code/forms` | Typed fields, reference selection, validation, submit ownership and cleanup; retained. |
| `ui/code/highlight` | Token-to-rich-text conversion, escaping and bounded highlighted source; retained. |
| `ui/code/history` | Version/proposal identity, source comparison, conditional restore and selected-document updates; retained. |
| `ui/code/large_source` | Viewport windows and source offset mapping limit work for large read-only source; retained. |
| `ui/code/library` | Document/action metadata, filtering, source-independent selection and list lifecycle; retained. |
| `ui/code/list` | Recycled visible rows, canvas bounds, keyboard/selection state and disposal; retained. |
| `ui/code/metrics` | Text/line dimensions and display scale calculations; retained. |
| `ui/code/output` | Bounded retained run output, selected run identity, row display and clear behavior; retained. |
| `ui/code/preview` | Immutable source preview, scrolling and resize ownership; retained. Full source metrics are recalculated on resize, a possible future optimization rather than a measured bottleneck. |
| `ui/code/remotes` | Capture/replay separation, generation-bound discovery/caller source work, bounded pages, debounced refresh, hidden-pane cancellation and teardown; retained. |
| `ui/code/splitter` | Input ownership, drag capture and explicit destroy; retained. Owners destroy splitters during their pane cleanup. |
| `ui/code/syntax` | Background syntax generation, lexical work bounds and stale-result rejection; retained. |
| `ui/code/tabs` | Stable IDs, active selection, overflow and control reuse; retained. |
| `ui/code/value_tree` | Bounded graph display, expanded paths, editable drafts and stable references; retained. |
| `ui/code/world_picker` | Bounded explorer search, query cancellation, stable selection and modal lifecycle; retained. |

| Application module | Reviewed mechanism and disposition |
| --- | --- |
| `ui/panels/code` | Lazy pane construction, document/source identity, keyboard scope, visibility propagation, generation-bound source refresh and pane/subscription cleanup; retained. |
| `ui/app` | Mounting, lazy panels, session attachment, bounded navigation/notifications, launcher drag ownership, view rebuilds and native visibility propagation; retained. Conversation search remains synchronous over retained session data and is a possible future optimization. |
| `ui/boot` | Minimal startup dependencies, real loaded/total progress, protected tween setup, success/failure retirement and fallback destruction; retained. |
| `ui/sidebar` | Signature-based history/navigation rebuild suppression, folder state, busy indicators, count-change-only agent debounce and subscription teardown; retained. |
| `ui/conversations` | Folder creation/rename/move flows, live conversation identity checks, error preservation, menu ownership and modal subscription teardown; retained. |

## Manual review and focused verification

Changed source, `docs/SCRIPT_DEVELOPMENT.md`, `docs/SCRIPT_PROJECTS.md`, release
metadata and focused test inputs were manually reviewed before the build gate.
The release tests use the existing offline workspace fixture, compiler/file-read
counters and fake HTTP responses. They make no live network calls and no native
speed claim.

The coordinator reviewed generated native/site outputs before focused execution.
All five assigned checks passed, with exit 0 and no remaining failures:

| Check | Final result | Elapsed host test time |
| --- | --- | --- |
| `test/release_scripting.lua` | 12 cases, 44 assertions | 1.163 seconds |
| `test/release_tools.lua` | 15 cases, 54 assertions | 1.787 seconds |
| `test/script_projects.lua` | 17 cases, 58 assertions | 3.898 seconds |
| `test/execution_tools.lua` | 238 checks | 7.436 seconds |
| `test/tool_workflows.lua` | 384 checks | 6.792 seconds |

These are 778 offline checks/assertions, not native performance measurements.
Logs are in `refer/release-3.0.0/`. The initial tool pass found that
`click_detector_fire` incorrectly required executor signal introspection before
native ProximityPrompt calls. Removed that requirement only from this tool;
`gui_click` retains its introspection requirement. The fix was manually reviewed,
rebuilt and inspected before the affected tool check passed. Its initial failed
log remains as `release_tools.initial.log`. The already-passing scripting test
was not repeated after this unrelated GUI change. The entire native suite was
not run. The coordinator owns final artifact identity and verification records.

Shared-helper cross-review additionally identified short line-read boundaries,
observed clamped property writes and retention-failure HTTP messaging. Those
findings were sent to the release coordinator before the build gate.
